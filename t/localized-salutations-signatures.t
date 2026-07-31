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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use AdminSalutations;
use AdminSignatures;
use QisutuLocalizedContent;

my @ExpectedLanguages = qw(de en fr it es pt-BR pt-PT nl pl cs tr);
is_deeply(
    [ map { $_->{code} } @{ QisutuLocalizedContent->LanguageList() } ],
    \@ExpectedLanguages,
    'salutations and signatures use all eleven Qisutu languages',
);

{
    package Local::LocalizedContentDB;

    sub new {
        return bless {
            Do         => [],
            SelectAll  => [],
            SelectRow  => [],
            Begun      => 0,
            Committed  => 0,
            RolledBack => 0,
        }, shift;
    }
    sub Do {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Do} }, \@Param;
        return 1;
    }
    sub SelectAll {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{SelectAll} }, \@Param;
        return [
            {
                id                 => 7,
                name               => 'Standard',
                content            => '<p>Bonjour</p>',
                translation_exists => 1,
                active             => 1,
                sort_order         => 100,
            },
        ];
    }
    sub SelectRow {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{SelectRow} }, \@Param;
        return {
            id                 => 7,
            name               => 'Standard',
            content            => '<p>Bonjour</p>',
            translation_exists => 1,
            active             => 1,
            sort_order         => 100,
        };
    }
    sub LastInsertID { return 7 }
    sub BeginWork {
        my ($Self) = @_;
        $Self->{Begun}++;
        return 1;
    }
    sub Commit {
        my ($Self) = @_;
        $Self->{Committed}++;
        return 1;
    }
    sub Rollback {
        my ($Self) = @_;
        $Self->{RolledBack}++;
        return 1;
    }
    sub Error { return '' }
}

my $DB = Local::LocalizedContentDB->new();
my $Localized = QisutuLocalizedContent->new(
    Config => { Language => { Default => 'en' } },
    DB     => $DB,
);

ok( $Localized->SchemaEnsure(), 'localized-content schema preparation succeeds' );
is( scalar @{ $DB->{Do} }, 4, 'schema preparation creates both tables and imports both legacy contents' );
like( $DB->{Do}->[2]->[0], qr{INSERT IGNORE INTO salutation_translation}, 'existing salutations are imported as German' );
like( $DB->{Do}->[3]->[0], qr{INSERT IGNORE INTO signature_translation}, 'existing signatures are imported as German' );

my $List = $Localized->ItemList(
    Type            => 'salutation',
    Language        => 'pt-PT',
    IncludeInactive => 1,
);
is( $List->[0]->{content}, '<p>Bonjour</p>', 'the selected salutation content is returned' );
is_deeply(
    [ @{ $DB->{SelectAll}->[-1] }[ 1, 2 ] ],
    [ 'pt-PT', 'en' ],
    'salutation lists bind the selected and configured fallback languages',
);

my $Signature = $Localized->ItemGet(
    Type     => 'signature',
    ID       => 7,
    Language => 'fr',
);
is( $Signature->{name}, 'Standard', 'the selected signature translation is returned' );
is_deeply(
    [ @{ $DB->{SelectRow}->[-1] }[ 1, 2, 3 ] ],
    [ 'fr', 'en', 7 ],
    'signature lookup is restricted to the selected logical entry and language',
);

ok(
    $Localized->ItemUpdate(
        Type            => 'salutation',
        ID              => 7,
        Language        => 'fr',
        Name            => 'Formule standard',
        Content         => '<p>Bonjour {{CustomerUser.Firstname}}</p><script>bad()</script>',
        Active          => 1,
        SortOrder       => 100,
        ChangedByUserID => 1,
    ),
    'a French salutation can be saved',
);
like( $DB->{Do}->[-1]->[0], qr{ON DUPLICATE KEY UPDATE}, 'saving creates or updates exactly one language row' );
unlike( join( ' ', @{ $DB->{Do}->[-1] } ), qr{script}, 'localized rich text is sanitized before storage' );

ok(
    $Localized->ItemCreate(
        Type            => 'signature',
        Language        => 'pt-BR',
        Name            => 'Assinatura padrão',
        Content         => '<p>Atenciosamente</p>',
        SortOrder       => 200,
        ChangedByUserID => 1,
    ),
    'a signature can be created directly in Brazilian Portuguese',
);
like(
    $DB->{Do}->[-1]->[0],
    qr{INSERT IGNORE INTO signature_translation},
    'a non-German creation receives an empty German marker so migration cannot mislabel its content',
);
is( $DB->{Committed}, 2, 'localized creates and updates are committed transactionally' );
is( $DB->{RolledBack}, 0, 'successful localized writes require no rollback' );

{
    package Local::LocalizedAdminOutput;

    sub new { return bless {}, shift }
    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        $Value = '' if !defined $Value;
        $Value =~ s/&/&amp;/g;
        $Value =~ s/</&lt;/g;
        $Value =~ s/>/&gt;/g;
        $Value =~ s/"/&quot;/g;
        return $Value;
    }
    sub Translate {
        my ( $Self, %Param ) = @_;
        return $Param{Key};
    }
}

{
    package Local::LocalizedAdminObject;

    sub new { return bless { Calls => [] }, shift }
    sub SalutationList {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Calls} }, [ SalutationList => $Param{Language} ];
        return [];
    }
    sub Error { return '' }
}

{
    package Local::SalutationAdminModule;

    our @ISA = ('AdminSalutations');

    sub _AdminObject {
        my ($Self) = @_;
        return $Self->{TestAdminObject};
    }
}

my $AdminObject = Local::LocalizedAdminObject->new();
my $AdminModule = Local::SalutationAdminModule->new(
    Config => { Language => { Default => 'de' } },
    DB     => bless( {}, 'Local::UnusedLocalizedAdminDB' ),
    Output => Local::LocalizedAdminOutput->new(),
);
$AdminModule->{TestAdminObject} = $AdminObject;

my $DefaultView = $AdminModule->Run(
    Request => { Language => 'it' },
    User    => { user_account_id => 1 },
);
is( $DefaultView->{Data}->{CurrentContentLanguage}, 'it', 'salutations default to the current agent language' );
like(
    $DefaultView->{Data}->{ContentLanguageOptionsHTML},
    qr{<option value="it" selected>Italiano</option>},
    'the current agent language is selected for salutations',
);

my $PortugueseView = $AdminModule->Run(
    Request => {
        Language        => 'it',
        ContentLanguage => 'pt-PT',
    },
    User => { user_account_id => 1 },
);
is( $PortugueseView->{Data}->{CurrentContentLanguage}, 'pt-PT', 'the explicit salutation language is retained' );
is_deeply(
    $AdminObject->{Calls},
    [
        [ SalutationList => 'it' ],
        [ SalutationList => 'pt-PT' ],
    ],
    'the salutation list is loaded in the selected language',
);

sub content {
    my (@Parts) = @_;
    my $Path = File::Spec->catfile( $FindBin::Bin, '..', @Parts );
    open my $FH, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;
    return $Content;
}

my $SalutationDefinition = content( 'core', 'module', 'AdminSalutations.pm' );
my $SignatureDefinition  = content( 'core', 'module', 'AdminSignatures.pm' );
like( $SalutationDefinition, qr{LocalizedContent\s*=>\s*1}, 'salutations enable localized administration' );
like( $SignatureDefinition, qr{LocalizedContent\s*=>\s*1}, 'signatures enable localized administration' );

for my $TemplateName (qw(AdminSalutations.tt AdminSignatures.tt)) {
    my $Template = content( 'core', 'output', $TemplateName );
    like(
        $Template,
        qr{name="ContentLanguage"[^>]*data-localized-content-language},
        "$TemplateName contains the eleven-language dropdown",
    );
    like(
        $Template,
        qr{name="ContentLanguage" value="\[% CurrentContentLanguage %\]"},
        "$TemplateName preserves the selected language when saving",
    );
}

my $Schema = content( 'install', 'sql', 'schema.sql' );
like( $Schema, qr{CREATE TABLE `salutation_translation`}, 'fresh installations create salutation translations' );
like( $Schema, qr{PRIMARY KEY \(`salutation_id`,`language`\)}, 'each salutation has at most one version per language' );
like( $Schema, qr{CREATE TABLE `signature_translation`}, 'fresh installations create signature translations' );
like( $Schema, qr{PRIMARY KEY \(`signature_id`,`language`\)}, 'each signature has at most one version per language' );

my $TicketCreate = content( 'core', 'module', 'AgentTicketCreate.pm' );
my $TicketZoom   = content( 'core', 'module', 'AgentTicketZoom.pm' );
like( $TicketCreate, qr{LEFT JOIN salutation_translation sal_current}, 'ticket creation selects the localized salutation' );
like( $TicketCreate, qr{LEFT JOIN signature_translation sig_current}, 'ticket creation selects the localized signature' );
like( $TicketZoom, qr{LEFT JOIN salutation_translation sal_current}, 'ticket replies select the localized salutation' );
like( $TicketZoom, qr{LEFT JOIN signature_translation sig_current}, 'ticket replies select the localized signature' );

done_testing();
