# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# Qisutu is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Qisutu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use Encode qw(encode);
use Test::More;
use lib qw(core/system core/output core/module);
use QisutuMasterDataImport;

{
    package Local::TransactionOutput;
    sub new { bless {}, shift }
    sub Translate { return $_[2] }
}

{
    package Local::TransactionDB;
    sub new {
        my ( $Class, %Param ) = @_;
        return bless {
            AgentRows => $Param{AgentRows} || [],
            Run       => $Param{Run},
            Commit    => 0,
            Rollback  => 0,
        }, $Class;
    }
    sub SelectAll {
        my ( $Self, $SQL ) = @_;
        return [] if $SQL =~ /FROM user_dynamic_field f/;
        return $Self->{AgentRows} if $SQL =~ /WHERE ua\.account_type = "agent"/;
        return [] if $SQL =~ /FROM user_dynamic_field_value/;
        return [] if $SQL =~ /FROM master_data_import_item/;
        die "Unexpected SelectAll: $SQL";
    }
    sub SelectRow {
        my ( $Self, $SQL ) = @_;
        return { %{$Self->{Run}}, created_by_name => 'Administrator' } if $SQL =~ /FROM master_data_import_run/;
        die "Unexpected SelectRow: $SQL";
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /SET status = "imported"/ ) {
            $Self->{Run}->{status} = 'imported';
            $Self->{Run}->{staged_content} = undef;
        }
        elsif ( $SQL =~ /SET status = \?, staged_content = NULL, analysis_sha256/ ) {
            $Self->{Run}->{status} = $Bind[0];
            $Self->{Run}->{analysis_sha256} = $Bind[1];
        }
        elsif ( $SQL =~ /SET status = "expired"/ ) {
            # The test run is not expired.
        }
        return 1 if $SQL =~ /master_data_import_(?:run|item)/;
        die "Unexpected Do: $SQL";
    }
    sub BeginWork { $_[0]->{Begin}++; return 1 }
    sub Commit { $_[0]->{Commit}++; return 1 }
    sub Rollback { $_[0]->{Rollback}++; return 1 }
    sub Error { return '' }
}

{
    package Local::ImportAdmin;
    our @Create;
    sub new { bless { LastError => '' }, shift }
    sub AgentCreate {
        my ( $Self, %Param ) = @_;
        push @Create, { %Param };
        return 1;
    }
    sub Error { return $_[0]->{LastError} || '' }
}

sub BuildObject {
    my ($DB) = @_;
    return QisutuMasterDataImport->new(
        Config => { Language => { Default => 'de' } },
        DB     => $DB,
        Output => Local::TransactionOutput->new(),
    );
}

my $Content = "login;email;firstname;lastname;active\r\nagent01;agent01\@example.org;Erika;Musterfrau;1\r\n";
my $DB = Local::TransactionDB->new();
my $Object = BuildObject($DB);
my $Analysis = $Object->_Analyze( Type => 'agent', Content => $Content, Language => 'de' );
$DB->{Run} = {
    id => 1, import_type => 'agent', file_name => 'agenten.csv',
    file_sha256 => sha256_hex( encode( 'UTF-8', $Content ) ),
    analysis_sha256 => $Object->_AnalysisSHA($Analysis),
    status => 'pending', staged_content => $Content,
    total_count => 1, created_count => 1, updated_count => 0,
    unchanged_count => 0, error_count => 0, invitation_count => 0,
    created_by_user_id => 5, created_at => '2026-07-18 12:00:00',
    expires_at => '2099-01-01 00:00:00',
};

{
    no warnings 'redefine';
    local *QisutuAdmin::new = sub { return Local::ImportAdmin->new() };
    @Local::ImportAdmin::Create = ();
    my $Run = $Object->ImportRun( RunID => 1, UserID => 5, Language => 'de' );
    ok( $Run, 'validated import is executed' );
    is( $DB->{Commit}, 1, 'the entire import is committed once' );
    is( $DB->{Rollback}, 0, 'successful import is not rolled back' );
    is( scalar @Local::ImportAdmin::Create, 1, 'one agent is created' );
    my $Parameters = $Local::ImportAdmin::Create[0];
    ok( !grep( { /(?:Group|Permission)/i } keys %{$Parameters} ), 'agent creation receives no group or permission parameter' );
}

my $DriftDB = Local::TransactionDB->new();
my $DriftObject = BuildObject($DriftDB);
my $PreviewAnalysis = $DriftObject->_Analyze( Type => 'agent', Content => $Content, Language => 'de' );
$DriftDB->{Run} = {
    %{$DB->{Run}}, id => 2, status => 'pending', staged_content => $Content,
    analysis_sha256 => $DriftObject->_AnalysisSHA($PreviewAnalysis),
};
$DriftDB->{AgentRows} = [{
    id => 99, login => 'agent01', email => 'agent01@example.org', firstname => 'Erika',
    lastname => 'Musterfrau', is_active => 1, is_system_user => 0, protected_admin => 0,
}];

{
    no warnings 'redefine';
    local *QisutuAdmin::new = sub { return Local::ImportAdmin->new() };
    @Local::ImportAdmin::Create = ();
    my $Run = $DriftObject->ImportRun( RunID => 2, UserID => 5, Language => 'de' );
    ok( !$Run, 'changed master data invalidates the old preview' );
    is( $DriftObject->Error(), 'Translate:MasterDataImportChangedAfterPreview', 'preview drift has a clear error' );
    is( $DriftDB->{Rollback}, 1, 'preview drift rolls the transaction back' );
    is( $DriftDB->{Run}->{status}, 'invalid', 'drifted preview is marked invalid' );
    is( scalar @Local::ImportAdmin::Create, 0, 'no record is written after preview drift' );
}

done_testing();
