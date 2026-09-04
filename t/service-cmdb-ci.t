#!/usr/bin/env perl

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

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuService;

{
    package Local::ServiceCIDB;

    sub new {
        return bless {
            Link    => {},
            History => [],
            Commits => 0,
        }, shift;
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{FROM service WHERE id} ) {
            return $Bind[0] == 7 ? { id => 7, full_name => 'Portal' } : undef;
        }
        if ( $SQL =~ m{FROM cmdb_ci WHERE id = .*active = 1} ) {
            return $Bind[0] == 11 ? { id => 11, ci_number => 'CI00011', name => 'Webserver 01' } : undef;
        }
        if ( $SQL =~ m{SELECT service_id FROM service_cmdb_ci} ) {
            return $Self->{Link}->{ $Bind[0] . ':' . $Bind[1] }
                ? { service_id => $Bind[0] }
                : undef;
        }
        if ( $SQL =~ m{FROM service_cmdb_ci sci} && $SQL =~ m{INNER JOIN service s} ) {
            return if !$Self->{Link}->{ $Bind[0] . ':' . $Bind[1] };
            return {
                service_id => 7,
                full_name  => 'Portal',
                ci_id      => 11,
                ci_number  => 'CI00011',
                name       => 'Webserver 01',
            };
        }
        if ( $SQL =~ m{FROM user_account} ) {
            return { login => 'admin', firstname => 'Franziska', lastname => 'Steps' };
        }

        die "Unexpected SelectRow SQL: $SQL";
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{WHERE sci[.]service_id =} ) {
            return [] if !$Self->{Link}->{ '7:11' };
            return [ {
                id => 11, ci_number => 'CI00011', name => 'Webserver 01',
                status => 'active', active => 1, type_name => 'Server',
            } ];
        }
        if ( $SQL =~ m{WHERE sci[.]ci_id =} ) {
            return [] if !$Self->{Link}->{ '7:11' };
            return [ { id => 7, full_name => 'Portal', active => 1, sort_order => 100 } ];
        }

        die "Unexpected SelectAll SQL: $SQL";
    }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{INSERT INTO service_cmdb_ci} ) {
            $Self->{Link}->{ $Bind[0] . ':' . $Bind[1] } = 1;
            return 1;
        }
        if ( $SQL =~ m{DELETE FROM service_cmdb_ci} ) {
            delete $Self->{Link}->{ $Bind[0] . ':' . $Bind[1] };
            return 1;
        }
        if ( $SQL =~ m{INSERT INTO cmdb_ci_history} ) {
            push @{ $Self->{History} }, {
                ci_id      => $Bind[0],
                event_type => $Bind[1],
                old_value  => $Bind[4],
                new_value  => $Bind[5],
                actor_name => $Bind[8],
            };
            return 1;
        }

        die "Unexpected Do SQL: $SQL";
    }

    sub BeginWork { return 1 }
    sub Rollback  { return 1 }
    sub Commit    { $_[0]->{Commits}++; return 1 }
    sub Error     { return '' }
}

my $DB = Local::ServiceCIDB->new();
my $ServiceObject = QisutuService->new( DB => $DB, Config => {} );
my $User = {
    user_account_id => 3,
    firstname       => 'Franziska',
    lastname        => 'Steps',
};

ok(
    $ServiceObject->ServiceCILinkAdd(
        ServiceID => 7,
        CIID      => 11,
        User      => $User,
    ),
    'a configuration item can be assigned to a service',
);
ok( $DB->{Link}->{'7:11'}, 'the service-CI relation is stored' );
is( $DB->{History}->[-1]->{event_type}, 'service_linked', 'the assignment is audited' );
is( $DB->{History}->[-1]->{new_value}, 'Portal', 'the service name is retained in the audit entry' );
is( $DB->{History}->[-1]->{actor_name}, 'Franziska Steps', 'the acting agent is retained in the audit entry' );

is( scalar @{ $ServiceObject->ServiceCIList( ServiceID => 7 ) }, 1, 'assigned CIs are listed for a service' );
is( scalar @{ $ServiceObject->CIServiceList( CIID => 11 ) }, 1, 'assigned services are listed for a CI' );

ok(
    $ServiceObject->ServiceCILinkRemove(
        ServiceID => 7,
        CIID      => 11,
        User      => $User,
    ),
    'a configuration item can be removed from a service',
);
ok( !$DB->{Link}->{'7:11'}, 'the service-CI relation is removed' );
is( $DB->{History}->[-1]->{event_type}, 'service_unlinked', 'the removal is audited' );
is( $DB->{History}->[-1]->{old_value}, 'Portal', 'the removed service name remains in the audit entry' );
is( $DB->{Commits}, 2, 'assignment and removal are committed transactionally' );

my $SchemaPath = File::Spec->catfile( $FindBin::Bin, '..', 'install', 'sql', 'schema.sql' );
open my $SchemaFH, '<:encoding(UTF-8)', $SchemaPath or die "Cannot read $SchemaPath: $!";
local $/;
my $Schema = <$SchemaFH>;
close $SchemaFH;

like( $Schema, qr{CREATE TABLE IF NOT EXISTS `service_cmdb_ci`}, 'the installation and update schema contains the service-CI table' );
like( $Schema, qr{PRIMARY KEY \(`service_id`,`ci_id`\)}, 'duplicate service-CI assignments are prevented' );
like( $Schema, qr{service_cmdb_ci_service_fk.*REFERENCES `service`}s, 'service deletion cleans up assignments' );
like( $Schema, qr{service_cmdb_ci_ci_fk.*REFERENCES `cmdb_ci`}s, 'CI deletion cleans up assignments' );

my %SourceFile = (
    'core/module/AdminServices.pm' => [
        qr{Step eq 'ServiceCILink'},
        qr{ServiceCILinkAdd},
        qr{ServiceCILinkRemove},
    ],
    'core/output/AdminServices.tt' => [
        qr{Translate[.]AdminServiceCIs},
        qr{data-qisutu-cmdb-autocomplete},
        qr{Step" value="ServiceCIUnlink},
    ],
    'core/module/CMDBItems.pm' => [
        qr{CIServiceList},
        qr{HasServices},
    ],
    'core/output/CMDBItems.tt' => [
        qr{Translate[.]CMDBServices},
        qr{FOREACH Service IN Services},
    ],
);

for my $Relative ( sort keys %SourceFile ) {
    my $Path = File::Spec->catfile( $FindBin::Bin, '..', split m{/}, $Relative );
    open my $FH, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    my $Content = do { local $/; <$FH> };
    close $FH;
    for my $Pattern ( @{ $SourceFile{$Relative} } ) {
        like( $Content, $Pattern, "$Relative contains the service-CI user interface integration" );
    }
}

done_testing();
