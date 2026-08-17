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

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
use lib "$FindBin::Bin/../core/config";
use lib "$FindBin::Bin/../core/system";
use lib "$FindBin::Bin/../core/module";
use lib "$FindBin::Bin/../core/output";

use AdminTicketForms;
use QisutuDynamicField;
use QisutuTicketForm;

{
    package Local::Output;

    sub new { return bless {}, shift }

    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        $Value = '' if !defined $Value;
        $Value =~ s{&}{&amp;}g;
        $Value =~ s{<}{&lt;}g;
        $Value =~ s{>}{&gt;}g;
        $Value =~ s{"}{&quot;}g;
        $Value =~ s{'}{&#39;}g;
        return $Value;
    }

    sub Translate {
        my ( $Self, %Param ) = @_;
        return $Param{Key} || '';
    }
}

{
    package Local::DB;

    sub new { return bless { Do => [] }, shift }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub Error { return '' }
    sub LastInsertID { return 9 }
    sub Do {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Do} }, \@Param;
        return 1;
    }
}

{
    package Local::LabelDB;

    sub new { return bless { FieldListSQL => '', FieldListBind => [] }, shift }
    sub Error { return '' }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return {
            id               => 9,
            form_id          => 4,
            dynamic_field_id => 17,
            field_key        => 'occasion',
            field_type       => 'text',
        } if $SQL =~ m{FROM ticket_form_field WHERE id};
        return {
            id         => 17,
            name       => 'Form4_occasion',
            label      => 'Anlass',
            field_type => 'text',
        } if $SQL =~ m{FROM ticket_dynamic_field};
        return;
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ m{FROM ticket_form_field_translation} ) {
            return [
                { language => 'de', label => 'Anlass',   help_text => 'Deutsche Hilfe', placeholder => 'Deutsch' },
                { language => 'en', label => 'Occasion', help_text => 'English help',   placeholder => 'English' },
            ];
        }
        if ( $SQL =~ m{FROM ticket_dynamic_field_translation} ) {
            return [
                { language => 'de', label => 'Anlass' },
                { language => 'en', label => 'Occasion22' },
            ];
        }
        if ( $SQL =~ m{FROM ticket_form_field ff} ) {
            $Self->{FieldListSQL}  = $SQL;
            $Self->{FieldListBind} = \@Bind;
            return [ {
                id               => 9,
                form_id          => 4,
                dynamic_field_id => 17,
                field_key        => 'occasion',
                field_type       => 'text',
                label            => $Bind[0] eq 'en' ? 'Occasion22' : 'Anlass',
                help_text        => $Bind[0] eq 'en' ? 'English help' : 'Deutsche Hilfe',
                placeholder      => $Bind[0] eq 'en' ? 'English' : 'Deutsch',
                is_required      => 0,
                default_value    => '',
                active           => 1,
                sort_order       => 100,
            } ];
        }
        return [];
    }
}

{
    package Local::TicketFormUpdate;
    our @ISA = ('QisutuTicketForm');

    sub FieldGet {
        return {
            id               => 9,
            form_id          => 4,
            dynamic_field_id => 17,
            field_key        => 'occasion',
            field_type       => 'multiselect',
        };
    }

    sub FormGet { return { id => 4, form_type => 'public' } }
    sub _FieldDataValidate { return $_[0]->{TestData} }
    sub _FieldTranslationReplace { return 1 }
    sub _FormVersionIncrement { return 1 }
}

my $Config = {
    Language => { Default => 'de' },
    Paths    => { Language => File::Spec->catdir( $Root, 'core', 'language' ) },
    System   => { BaseURL => 'https://portal.qisutu.de/qisutu/index.pl' },
};
my $Output = Local::Output->new();
my $Admin = AdminTicketForms->new(
    Config => $Config,
    DB     => Local::DB->new(),
    Output => $Output,
);

my $Options = $Admin->_OptionsFromRequest(
    Request => {
        OptionRowCount => 2,
        OptionKey_1    => 'introduce-qisutu',
        OptionValue_1  => 'Qisutu neu einführen',
        OptionKey_2    => '',
        OptionValue_2  => 'Managed Hosting',
    },
);
is_deeply(
    $Options,
    [
        { option_key => 'introduce-qisutu', option_value => 'Qisutu neu einführen', sort_order => 100 },
        { option_key => 'Managed Hosting', option_value => 'Managed Hosting', sort_order => 200 },
    ],
    'the form editor keeps existing technical keys and creates a key for a new option',
);

my $Translations = $Admin->_OptionTranslationsFromRequest(
    Request => {
        OptionRowCount        => 2,
        OptionKey_1           => 'introduce-qisutu',
        OptionValue_1         => 'Qisutu neu einführen',
        OptionKey_2           => 'managed-hosting',
        OptionValue_2         => 'Managed Hosting',
        OptionTranslation_en_1 => 'Introduce Qisutu',
        OptionTranslation_en_2 => 'Managed Hosting',
        OptionTranslation_fr_1 => 'Introduire Qisutu',
    },
);
is_deeply(
    $Translations,
    {
        en => {
            'introduce-qisutu' => 'Introduce Qisutu',
            'managed-hosting'  => 'Managed Hosting',
        },
        fr => {
            'introduce-qisutu' => 'Introduire Qisutu',
        },
    },
    'the form editor maps every translated display value to its stable dynamic-field option key',
);

my $OptionRows = $Admin->_FieldOptionRows(
    Options  => $Options,
    MinRows => 1,
    Language => 'de',
);
is( $OptionRows->{Count}, 2, 'the existing form options retain their row count' );
like( $OptionRows->{HTML}, qr{name="OptionKey_1" value="introduce-qisutu"}, 'the technical option key is preserved in the form editor' );
like( $OptionRows->{HTML}, qr{name="OptionValue_1" value="Qisutu neu einführen"}, 'the base display value remains editable' );

my $TranslationHTML = $Admin->_FieldTranslationsHTML(
    Translations => {
        de => { label => 'Anlass', help_text => '', placeholder => '' },
        en => { label => 'Occasion', help_text => '', placeholder => '' },
    },
    Options => $Options,
    OptionTranslations => $Translations,
    Language => 'de',
);
like( $TranslationHTML, qr{name="OptionTranslation_en_1" value="Introduce Qisutu"}, 'the English option translation is visible in the form editor' );
like( $TranslationHTML, qr{name="OptionTranslation_fr_1" value="Introduire Qisutu"}, 'the French option translation is visible in the form editor' );
like( $TranslationHTML, qr{AdminDynamicFieldOptionTranslations}, 'the form editor labels the option translation area' );

my $LabelDB = Local::LabelDB->new();
my $LabelObject = QisutuTicketForm->new(
    Config => $Config,
    DB     => $LabelDB,
    Output => $Output,
);
my $CurrentFieldTranslations = $LabelObject->FieldTranslationList( FieldID => 9 );
is(
    $CurrentFieldTranslations->{en}->{label},
    'Occasion22',
    'the form editor reads a changed field label from the linked dynamic field',
);
is(
    $CurrentFieldTranslations->{en}->{help_text},
    'English help',
    'the form-specific help text remains unchanged when the dynamic label changes',
);
is(
    $CurrentFieldTranslations->{en}->{placeholder},
    'English',
    'the form-specific placeholder remains unchanged when the dynamic label changes',
);
my $CurrentFieldTranslationHTML = $Admin->_FieldTranslationsHTML(
    Translations => $CurrentFieldTranslations,
    Language     => 'de',
);
like(
    $CurrentFieldTranslationHTML,
    qr{name="FieldLabel_en" value="Occasion22"},
    'the changed dynamic-field label is visible in the form administration mask',
);

my $CurrentFields = $LabelObject->FieldList(
    FormID         => 4,
    Language       => 'en',
    IncludeInactive => 1,
);
is( $CurrentFields->[0]->{label}, 'Occasion22', 'the English form runtime receives the changed dynamic-field label' );
like(
    $LabelDB->{FieldListSQL},
    qr{ticket_dynamic_field_translation dynamic_current_translation},
    'the form runtime joins the current dynamic-field translation',
);
is_deeply(
    $LabelDB->{FieldListBind},
    [ 'en', 'de', 'en', 'de', 4 ],
    'the form runtime selects current and default dynamic-field translations for the requested form',
);
my $CurrentFieldsHTML = $LabelObject->FieldsHTML(
    Form     => { id => 4, form_type => 'public' },
    Request  => {},
    Language => 'en',
);
like( $CurrentFieldsHTML, qr{>Occasion22</label>}, 'the public form renders the changed dynamic-field label' );

my $Links = $Admin->_PublicLanguageLinks(
    Slug => 'https-qisutu-de-anfragen-html',
    Translations => {
        de => { title => 'Angebot anfordern' },
        en => { title => 'Request a quote' },
        fr => { title => '' },
    },
);
is( scalar @{$Links}, 2, 'one public link is generated for every configured form language' );
is( $Links->[0]->{language_code}, 'de', 'the configured default language is listed first' );
like( $Links->[0]->{url}, qr{[&]Language=de\z}, 'the German direct link contains its explicit language' );
like( $Links->[1]->{url}, qr{[&]Language=en\z}, 'the English direct link contains its explicit language' );
like( $Links->[1]->{iframe_code}, qr{[&]amp;Language=en}, 'the iframe code contains an HTML-safe language parameter' );

my %CapturedUpdate;
my $Updater = Local::TicketFormUpdate->new(
    Config => $Config,
    DB     => Local::DB->new(),
    Output => $Output,
);
$Updater->{TestData} = {
    FieldKey        => 'occasion',
    FieldType       => 'multiselect',
    IsRequired      => 0,
    Active          => 1,
    DefaultValue    => '',
    SortOrder       => 100,
    Options         => [ { option_key => 'kept', option_value => 'Behalten', sort_order => 100 } ],
    OptionTranslations => { en => { kept => 'Keep' } },
    OptionTranslationsProvided => 1,
    Translations    => { de => { label => 'Anlass' }, en => { label => 'Occasion' } },
};
my %CapturedCreate;
{
    no warnings 'redefine';
    local *QisutuDynamicField::FieldCreate = sub {
        my ( $Self, %Param ) = @_;
        %CapturedCreate = %Param;
        return 17;
    };
    is( $Updater->FieldCreate( FormID => 4 ), 9, 'a translated selection field can be created from the form editor' );
}
is_deeply(
    $CapturedCreate{OptionTranslations},
    { en => { kept => 'Keep' } },
    'form-field creation forwards translated option values to the shared dynamic field',
);

$Updater->{TestData} = {
    FieldType       => 'multiselect',
    IsRequired      => 0,
    Active          => 1,
    DefaultValue    => '',
    SortOrder       => 100,
    Options         => [ { option_key => 'kept', option_value => 'Behalten', sort_order => 100 } ],
    OptionTranslations => {},
    OptionTranslationsProvided => 0,
    Translations    => { de => { label => 'Anlass' } },
};
{
    no warnings 'redefine';
    local *QisutuDynamicField::OptionTranslationList = sub {
        return {
            en => { kept => 'Keep', removed => 'Remove' },
            fr => { kept => 'Conserver' },
        };
    };
    local *QisutuDynamicField::FieldUpdate = sub {
        my ( $Self, %Param ) = @_;
        %CapturedUpdate = %Param;
        return 1;
    };
    ok( $Updater->FieldUpdate( FieldID => 9 ), 'a legacy form-editor request can update the field safely' );
}
is_deeply(
    $CapturedUpdate{OptionTranslations},
    {
        en => { kept => 'Keep' },
        fr => { kept => 'Conserver' },
    },
    'an update request without translation controls preserves translations for the remaining options',
);

$Updater->{TestData}->{OptionTranslationsProvided} = 1;
$Updater->{TestData}->{OptionTranslations} = { en => { kept => 'Provided value' } };
{
    no warnings 'redefine';
    local *QisutuDynamicField::OptionTranslationList = sub { die 'existing translations must not replace submitted values' };
    local *QisutuDynamicField::FieldUpdate = sub {
        my ( $Self, %Param ) = @_;
        %CapturedUpdate = %Param;
        return 1;
    };
    ok( $Updater->FieldUpdate( FieldID => 9 ), 'the current form editor submits its translated option values' );
}
is_deeply(
    $CapturedUpdate{OptionTranslations},
    { en => { kept => 'Provided value' } },
    'submitted form-option translations are forwarded to the shared dynamic field',
);

{
    package Local::TicketFormRender;
    our @ISA = ('QisutuTicketForm');
    our $LanguageSeen = '';

    sub FieldList {
        return [ {
            id               => 5,
            field_key        => 'occasion',
            field_type       => 'dropdown',
            dynamic_field_id => 17,
            label            => 'Occasion',
            is_required      => 0,
            default_value    => '',
            sort_order       => 100,
        } ];
    }

    sub _FieldOptionList {
        my ( $Self, $Field, %Param ) = @_;
        $LanguageSeen = $Param{Language} || '';
        return [ { option_key => 'consulting', option_value => 'Consulting' } ];
    }
}

my $Renderer = Local::TicketFormRender->new(
    Config => $Config,
    DB     => Local::DB->new(),
    Output => $Output,
);
my $FieldsHTML = $Renderer->FieldsHTML(
    Form     => { id => 4, form_type => 'public' },
    Request  => {},
    Language => 'en',
);
is( $Local::TicketFormRender::LanguageSeen, 'en', 'the public form requests option labels in the selected URL language' );
like( $FieldsHTML, qr{<option value="consulting">Consulting</option>}, 'the public form renders the translated option label' );

my $AdminTemplate = _ReadRaw( File::Spec->catfile( $Root, 'core', 'output', 'AdminTicketForms.tt' ) );
like( $AdminTemplate, qr{FOREACH PublicLanguageLink IN PublicLanguageLinks}, 'the administration mask renders all configured language links' );
like( $AdminTemplate, qr{name="OptionTranslationsProvided" value="1"}, 'the current editor marks its complete translation payload' );
unlike( $AdminTemplate, qr{name="OptionsText"}, 'the obsolete untranslated option textarea is gone' );

my $PublicTemplate = _ReadRaw( File::Spec->catfile( $Root, 'core', 'output', 'PublicTicketForm.tt' ) );
like( $PublicTemplate, qr{FOREACH LanguageLink IN LanguageLinks}, 'the public form offers its configured languages' );
my $PublicProgram = _ReadRaw( File::Spec->catfile( $Root, 'bin', 'cgi-bin', 'form.pl' ) );
like( $PublicProgram, qr{url\s+=>\s+'form[.]pl[?]Form='.*?[&]Language=}s, 'public language links carry an explicit language parameter' );

ok( -x File::Spec->catfile( $Root, 'update.sh' ), 'update.sh is executable in the release tree' );
ok( -x File::Spec->catfile( $Root, 'install.sh' ), 'install.sh is executable in the release tree' );

done_testing();

sub _ReadRaw {
    my ($Path) = @_;
    open my $FH, '<:raw', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;
    return $Content;
}
