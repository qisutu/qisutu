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

use QisutuResponseTemplate;

{
    package Local::ResponseTemplateLanguageDB;

    sub new {
        return bless {
            Do        => [],
            SelectRow => [],
        }, shift;
    }

    sub Error {
        return '';
    }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Do} }, {
            SQL  => $SQL,
            Bind => \@Bind,
        };
        return 1;
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{SelectRow} }, {
            SQL  => $SQL,
            Bind => \@Bind,
        };

        if ( $SQL =~ m{FROM\s+response_template\s+rt}si ) {
            my $Language = $Bind[0] || 'de';
            return {
                id          => 7,
                name        => $Language eq 'fr' ? 'Réponse standard' : 'Standardantwort',
                description => $Language eq 'fr' ? 'Description française' : 'Deutsche Beschreibung',
                content     => $Language eq 'fr' ? '<p>Bonjour</p>' : '<p>Hallo</p>',
                active      => 1,
                sort_order  => 100,
            };
        }

        return;
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;

        return [] if $SQL =~ m{FROM\s+response_template_attachment}si;
        return [];
    }
}

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $DB = Local::ResponseTemplateLanguageDB->new();
my $Object = QisutuResponseTemplate->new(
    Config => {
        Language => { Default => 'de' },
    },
    DB => $DB,
);

is( scalar @{ $Object->LanguageList() }, 11, 'response templates support all eleven Qisutu languages' );
is( $Object->LanguageClean('pt_BR'), 'pt-BR', 'Portuguese locale spelling is normalized' );

ok( $Object->SchemaEnsure(), 'translation schema is prepared' );
ok(
    ( scalar grep { $_->{SQL} =~ m{CREATE TABLE IF NOT EXISTS response_template_translation}si } @{ $DB->{Do} } ),
    'the response-template translation table is created for existing installations',
);
ok(
    ( scalar grep { $_->{SQL} =~ m{INSERT IGNORE INTO response_template_translation}si && $_->{SQL} =~ m{"de"} } @{ $DB->{Do} } ),
    'legacy response-template content is migrated as German',
);

ok(
    $Object->TemplateUpdate(
        TemplateID      => 7,
        Language        => 'pt-BR',
        Name            => 'Resposta padrão',
        Description     => 'Descrição',
        Content         => '<p>Olá</p><script>bad()</script>',
        Active          => 1,
        SortOrder       => 200,
        ChangedByUserID => 9,
    ),
    'a Brazilian Portuguese response-template translation can be saved',
);

my ($BaseUpdate) = grep {
    $_->{SQL} =~ m{UPDATE\s+response_template}si
        && $_->{SQL} !~ m{response_template_translation}si
} @{ $DB->{Do} };
unlike(
    $BaseUpdate->{SQL},
    qr{SET\s+name\s*=}si,
    'saving a non-German translation does not overwrite the legacy German text',
);

my ($TranslationUpdate) = grep {
    $_->{SQL} =~ m{INSERT\s+INTO\s+response_template_translation}si
        && $_->{SQL} =~ m{ON DUPLICATE KEY UPDATE}si
} @{ $DB->{Do} };
is( $TranslationUpdate->{Bind}->[1], 'pt-BR', 'the selected translation language is stored' );
unlike( $TranslationUpdate->{Bind}->[4], qr{script}, 'translated CKEditor content is sanitized' );

my $French = $Object->TemplateForQueueGet(
    TemplateID => 7,
    QueueID    => 3,
    Language   => 'fr',
);
is( $French->{name}, 'Réponse standard', 'runtime loading selects the agent language' );
is( $French->{content}, '<p>Bonjour</p>', 'runtime loading returns the localized template body' );

my ($RuntimeSelect) = grep {
    $_->{SQL} =~ m{INNER JOIN\s+response_template_queue}si
} @{ $DB->{SelectRow} };
is_deeply(
    [ @{ $RuntimeSelect->{Bind} }[ 0, 1 ] ],
    [ 'fr', 'de' ],
    'runtime loading passes the requested and configured fallback languages',
);

my $Schema = _Read( File::Spec->catfile( $Root, 'install', 'sql', 'schema.sql' ) );
like(
    $Schema,
    qr{CREATE TABLE `response_template_translation`},
    'fresh installations include the response-template translation table',
);

my $AdminTemplate = _Read( File::Spec->catfile( $Root, 'core', 'output', 'AdminResponseTemplates.tt' ) );
like( $AdminTemplate, qr{name="TemplateLanguage"}, 'response-template administration offers a language selector' );
like( $AdminTemplate, qr{qisutu-localized-content[.]js}, 'language changes are applied immediately' );

my $AgentZoom = _Read( File::Spec->catfile( $Root, 'core', 'module', 'AgentTicketZoom.pm' ) );
like(
    $AgentZoom,
    qr{TemplateListForQueue\s*[(].*?Language\s*=>\s*\$Language}ms,
    'the response-template list uses the active agent language',
);
like(
    $AgentZoom,
    qr{TemplateForQueueGet\s*[(].*?Language\s*=>\s*\$Language}ms,
    'inserting a response template uses the active agent language',
);

done_testing();

sub _Read {
    my ($File) = @_;

    open my $Handle, '<:encoding(UTF-8)', $File or die "Could not read $File: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;

    return $Content;
}
