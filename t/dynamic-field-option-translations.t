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

use AdminDynamicFields;
use QisutuDynamicField;

{
    package Local::DynamicFieldDB;

    sub new {
        my ( $Class, %Param ) = @_;
        return bless {
            DoCalls    => [],
            SelectCalls => [],
            SelectRows => $Param{SelectRows} || [],
            LastID     => 0,
        }, $Class;
    }

    sub Do {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{DoCalls} }, \@Param;
        return 1;
    }

    sub SelectAll {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{SelectCalls} }, \@Param;
        return $Self->{SelectRows};
    }

    sub LastInsertID {
        my ($Self) = @_;
        return ++$Self->{LastID};
    }

    sub Error {
        return '';
    }
}

{
    package Local::AdminDynamicFieldDB;

    sub new {
        return bless {}, shift;
    }

    sub SelectRow {
        return {
            id               => 3,
            name             => 'Form1_84ff394a0c72',
            label            => 'Anlass',
            field_type       => 'multiselect',
            is_required      => 0,
            show_empty_value => 1,
            default_value    => '',
            active           => 1,
            sort_order       => 40,
        };
    }

    sub SelectAll {
        my ( $Self, $SQL ) = @_;

        return [ {
            id               => 3,
            name             => 'Form1_84ff394a0c72',
            label            => 'Anlass',
            field_type       => 'multiselect',
            is_required      => 0,
            show_empty_value => 1,
            default_value    => '',
            active           => 1,
            sort_order       => 40,
        } ] if $SQL =~ m{FROM ticket_dynamic_field f};

        return [] if $SQL =~ m{FROM ticket_queue};
        return [ { language => 'en', label => 'Occasion' } ]
            if $SQL =~ m{FROM ticket_dynamic_field_translation};
        return [ {
            id                => 11,
            field_id          => 3,
            option_key        => 'new-installation',
            option_value      => 'Qisutu neu einführen',
            base_option_value => 'Qisutu neu einführen',
            sort_order        => 100,
        } ] if $SQL =~ m{SELECT id, field_id, option_key, option_value};
        return [
            {
                language     => 'en',
                option_key   => 'new-installation',
                option_value => 'Introduce Qisutu',
            },
            {
                language     => 'fr',
                option_key   => 'new-installation',
                option_value => 'Introduire Qisutu',
            },
        ] if $SQL =~ m{FROM ticket_dynamic_field_option_translation translation};

        return [];
    }

    sub Error {
        return '';
    }
}

my $Admin = AdminDynamicFields->new(
    Config => {
        Language => { Default => 'de' },
        Paths    => { Language => '' },
    },
);
my $LabelObject = QisutuDynamicField->new(
    Config => { Language => { Default => 'de' } },
);

my $Parsed = $Admin->_OptionTranslationsFromRequest(
    Request => {
        TranslationRowCount => 2,
        TranslationLanguage_1 => 'de',
        TranslationLanguage_2 => 'en',
        OptionRowCount => 2,
        OptionKey_1 => 'new-installation',
        OptionKey_2 => 'managed-hosting',
        OptionTranslation_1_1 => 'Qisutu neu einführen',
        OptionTranslation_1_2 => 'Managed Hosting',
        OptionTranslation_2_1 => 'Introduce Qisutu',
        OptionTranslation_2_2 => 'Managed hosting',
    },
);

is_deeply(
    $Parsed,
    {
        de => {
            'new-installation' => 'Qisutu neu einführen',
            'managed-hosting'  => 'Managed Hosting',
        },
        en => {
            'new-installation' => 'Introduce Qisutu',
            'managed-hosting'  => 'Managed hosting',
        },
    },
    'the administration request keeps every option translation grouped by language and stable option key',
);

is(
    $LabelObject->_FirstTranslationLabel(
        Labels        => { en => 'Occasion' },
        ExistingLabel => 'Anlass',
    ),
    'Anlass',
    'saving a foreign-language translation does not overwrite the existing base label',
);

is(
    $LabelObject->_FirstTranslationLabel(
        Labels        => { de => 'Gelegenheit', en => 'Occasion' },
        ExistingLabel => 'Anlass',
    ),
    'Gelegenheit',
    'an explicitly submitted base-language label remains editable',
);

my $Rows = $Admin->_TranslationRows(
    Value => { en => 'Occasion' },
    Options => [
        { option_key => 'new-installation', option_value => 'Qisutu neu einführen' },
        { option_key => 'managed-hosting', option_value => 'Managed Hosting' },
    ],
    OptionTranslations => {
        en => {
            'new-installation' => 'Introduce Qisutu',
            'managed-hosting'  => 'Managed hosting',
        },
    },
    Language => 'de',
);

like( $Rows->{HTML}, qr{name="OptionTranslation_1_1" value="Introduce Qisutu"}, 'the first translated option is rendered for editing' );
like( $Rows->{HTML}, qr{name="OptionTranslation_1_2" value="Managed hosting"}, 'the second translated option is rendered for editing' );

my $AllLanguageRows = $Admin->_TranslationRows(
    Value => {
        de => 'Anlass',
        en => 'Occasion',
    },
    Options => [
        { option_key => 'new-installation', option_value => 'Qisutu neu einführen' },
    ],
    OptionTranslations => {
        en => { 'new-installation' => 'Introduce Qisutu' },
        fr => { 'new-installation' => 'Introduire Qisutu' },
    },
    Language => 'de',
);

is( $AllLanguageRows->{Count}, 3, 'all field and option translation languages remain visible for editing' );
like( $AllLanguageRows->{HTML}, qr{<option value="de" selected>de</option>}, 'the German base-language row remains visible' );
like( $AllLanguageRows->{HTML}, qr{<option value="en" selected>en</option>}, 'the English translation row remains visible' );
like( $AllLanguageRows->{HTML}, qr{<option value="fr" selected>fr</option>}, 'an option-only French translation row remains visible' );

my $SaveDB = Local::DynamicFieldDB->new();
my $Dynamic = QisutuDynamicField->new(
    Config => { Language => { Default => 'de' } },
    DB     => $SaveDB,
);

ok(
    $Dynamic->OptionSave(
        FieldID => 3,
        Options => [
            { option_key => 'new-installation', option_value => 'Qisutu neu einführen', sort_order => 100 },
            { option_key => 'managed-hosting', option_value => 'Managed Hosting', sort_order => 200 },
        ],
        OptionTranslations => {
            en => {
                'new-installation' => 'Introduce Qisutu',
                'managed-hosting'  => 'Managed hosting',
            },
        },
        ChangedByUserID => 7,
    ),
    'possible values and their translations are saved together',
);

my @TranslationInsert = grep {
    $_->[0] =~ m{INSERT INTO ticket_dynamic_field_option_translation}
} @{ $SaveDB->{DoCalls} };
is( scalar @TranslationInsert, 2, 'one database translation row is written for each translated option value' );
is_deeply(
    [ @{$TranslationInsert[0]}[ 1 .. 5 ] ],
    [ 2, 'en', 'Managed hosting', 7, 7 ],
    'the translated text is attached to the newly stored technical option',
);

my $ListDB = Local::DynamicFieldDB->new(
    SelectRows => [ {
        id                => 1,
        field_id          => 3,
        option_key        => 'new-installation',
        option_value      => 'Introduce Qisutu',
        base_option_value => 'Qisutu neu einführen',
        sort_order        => 100,
    } ],
);
my $ListObject = QisutuDynamicField->new(
    Config => { Language => { Default => 'de' } },
    DB     => $ListDB,
);
my $Options = $ListObject->OptionList( FieldID => 3, Language => 'en' );

is( $Options->[0]->{option_value}, 'Introduce Qisutu', 'the language-specific display value is returned to ticket forms' );
like( $ListDB->{SelectCalls}->[0]->[0], qr{ticket_dynamic_field_option_translation}, 'the option lookup includes the translation table' );
unlike( $ListDB->{SelectCalls}->[0]->[0], qr{default_translation}, 'missing option translations fall back directly to the original display value' );
is_deeply(
    [ @{ $ListDB->{SelectCalls}->[0] }[ 1 .. 2 ] ],
    [ 'en', 3 ],
    'the requested language and field are bound in the correct order',
);

my $FieldListDB = Local::DynamicFieldDB->new(
    SelectRows => [ {
        id         => 3,
        name       => 'Form1_84ff394a0c72',
        label      => 'Anlass',
        field_type => 'multiselect',
        active     => 1,
        sort_order => 40,
    } ],
);
my $FieldListObject = QisutuDynamicField->new(
    Config => { Language => { Default => 'en' } },
    DB     => $FieldListDB,
);
$FieldListObject->FieldList( Language => 'de', IncludeInactive => 1 );
like( $FieldListDB->{SelectCalls}->[0]->[0], qr{current_translation\.label, f\.label}, 'the overview uses the requested translation before the original label' );
unlike( $FieldListDB->{SelectCalls}->[0]->[0], qr{default_translation}, 'the German overview cannot fall back to an English translation' );
is_deeply(
    [ @{ $FieldListDB->{SelectCalls}->[0] }[ 1 .. 1 ] ],
    ['de'],
    'only the current interface language is bound for the overview',
);

my $EditAdmin = AdminDynamicFields->new(
    Config => {
        Language => { Default => 'de' },
        Paths    => { Language => '' },
    },
    DB => Local::AdminDynamicFieldDB->new(),
);
my $EditResult = $EditAdmin->Run(
    Request => {
        Action   => 'FieldEdit',
        FieldID  => 3,
        Language => 'de',
    },
    User => { user_account_id => 7 },
);
my $EditHTML = $EditResult->{Data}->{EditTranslationRowsHTML} || '';
like( $EditHTML, qr{<option value="de" selected>de</option>}, 'the original German label is restored as an editable language row' );
like( $EditHTML, qr{name="TranslationLabel_1" value="Anlass"}, 'the original German label remains editable after adding translations' );
like( $EditHTML, qr{<option value="en" selected>en</option>}, 'the existing English language remains editable' );
like( $EditHTML, qr{<option value="fr" selected>fr</option>}, 'the existing French option translation remains editable' );
like( $EditHTML, qr{value="Introduce Qisutu"}, 'the English option translation remains populated' );
like( $EditHTML, qr{value="Introduire Qisutu"}, 'the French option translation remains populated' );

my $SchemaPath = File::Spec->catfile( $FindBin::Bin, '..', 'install', 'sql', 'schema.sql' );
open my $SchemaFH, '<:encoding(UTF-8)', $SchemaPath or die "Cannot read $SchemaPath: $!";
local $/;
my $Schema = <$SchemaFH>;
close $SchemaFH;

like( $Schema, qr{CREATE TABLE `ticket_dynamic_field_option_translation`}, 'fresh and updated installations contain the option translation table' );
like( $Schema, qr{REFERENCES `ticket_dynamic_field_option` \(`id`\) ON DELETE CASCADE}, 'option translations are removed together with their option' );

done_testing();
