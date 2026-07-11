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

package AdminAgents;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $User    = $Param{User}    || {};
    my $Admin   = $Self->_AdminObject();
    my $Step    = $Request->{Step} || '';

    if ( $Admin && $Step eq 'AgentCreate' ) {
        $Admin->AgentCreate(
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentUpdate' ) {
        $Admin->AgentUpdate(
            UserAccountID   => $Request->{UserAccountID},
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            IsActive        => $Request->{IsActive},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDeactivate' ) {
        $Admin->AgentDeactivate(
            UserAccountID   => $Request->{UserAccountID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentGroupPermissionUpdate' ) {
        $Admin->UserGroupPermissionUpdate(
            UserAccountID   => $Request->{UserAccountID},
            GroupID         => $Request->{GroupID},
            PermissionRead  => $Request->{PermissionRead},
            PermissionCreate => $Request->{PermissionCreate},
            PermissionChange => $Request->{PermissionChange},
            PermissionOverview => $Request->{PermissionOverview},
            PermissionFull  => $Request->{PermissionFull},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentGroupRemove' ) {
        $Admin->UserGroupRemove(
            UserAccountID   => $Request->{UserAccountID},
            GroupID         => $Request->{GroupID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldCreate' ) {
        $Admin->AgentDynamicFieldCreate(
            Name            => $Request->{Name},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Admin   => $Admin,
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldUpdate' ) {
        $Admin->AgentDynamicFieldUpdate(
            FieldID         => $Request->{FieldID},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Admin   => $Admin,
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=FieldEdit;FieldID=' . ( $Request->{FieldID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldDelete' ) {
        $Admin->AgentDynamicFieldDelete(
            FieldID         => $Request->{FieldID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }

    my $Action     = $Request->{Action} || 'List';
    my $Language   = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $AgentList  = $Admin ? $Admin->AgentList() : [];
    my $GroupList  = $Admin ? $Admin->GroupList() : [];
    my $LanguageList = $Admin ? $Admin->LanguageList() : [];
    my $FieldList  = $Admin ? $Admin->AgentDynamicFieldList( Language => $Language, IncludeInactive => 1 ) : [];
    my $ActiveFieldList = $Admin ? $Admin->AgentDynamicFieldList( Language => $Language ) : [];
    my $Agent;
    my $Field;
    my $AgentGroupList = [];
    my $FieldTranslation = {};
    my $FieldValue = {};

    if ( $Admin && $Action eq 'Edit' ) {
        $Agent = $Admin->AgentGet( UserAccountID => $Request->{UserAccountID} );
        if ($Agent) {
            $FieldValue = $Admin->AgentDynamicFieldValueList(
                UserAccountID => $Agent->{id},
            );
            $AgentGroupList = $Admin->UserGroupList(
                UserAccountID => $Agent->{id},
            );

            for my $Group ( @{$AgentGroupList} ) {
                $Group->{permission_read_checked}     = $Group->{permission_read} ? 'checked' : '';
                $Group->{permission_create_checked}   = $Group->{permission_create} ? 'checked' : '';
                $Group->{permission_change_checked}   = $Group->{permission_change} ? 'checked' : '';
                $Group->{permission_overview_checked} = $Group->{permission_overview} ? 'checked' : '';
                $Group->{permission_full_checked}     = $Group->{permission_full} ? 'checked' : '';
            }
        }
        else {
            $Action = 'List';
        }
    }

    if ( $Admin && $Action eq 'FieldEdit' ) {
        $Field = $Admin->AgentDynamicFieldGet( FieldID => $Request->{FieldID} );
        if ($Field) {
            $FieldTranslation = $Admin->AgentDynamicFieldTranslationList(
                FieldID => $Field->{id},
            );
        }
        else {
            $Action = 'List';
        }
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';
    my $CreateFields = $Self->_DynamicFieldFormFields(
        FieldList  => $ActiveFieldList,
        FieldValue => {},
    );
    my $EditFields = $Self->_DynamicFieldFormFields(
        FieldList  => $ActiveFieldList,
        FieldValue => $FieldValue,
    );
    my $TranslationLanguageOptions = $Self->_TranslationLanguageOptions(
        Selected => '',
    );
    my $CreateTranslationRows = $Self->_TranslationRows(
        Value     => {},
        MinRows   => 1,
        Language  => $Language,
    );
    my $EditTranslationRows = $Self->_TranslationRows(
        Value     => $FieldTranslation,
        MinRows   => 1,
        Language  => $Language,
    );

    return {
        Template => 'AdminAgents.tt',
        Data     => {
            PageTitle          => 'Translate:AdminAgentsTitle',
            ProgramTitle       => 'Translate:AdminAgentsTitle',
            ProgramDescription => 'Translate:AdminAgentsDescription',
            AgentList          => $AgentList,
            GroupList          => $GroupList,
            AgentGroupList     => $AgentGroupList,
            FieldList          => $FieldList,
            LanguageList       => $LanguageList,
            AgentCount         => scalar @{$AgentList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowFieldCreate    => $Action eq 'FieldCreate' ? 1 : 0,
            ShowFieldEdit      => $Action eq 'FieldEdit' ? 1 : 0,
            AgentID            => $Agent ? $Agent->{id} : '',
            AgentLogin         => $Agent ? $Agent->{login} : '',
            AgentEmail         => $Agent ? $Agent->{email} : '',
            AgentFirstname     => $Agent ? $Agent->{firstname} : '',
            AgentLastname      => $Agent ? $Agent->{lastname} : '',
            AgentGroups        => $Agent ? $Agent->{group_names} : '',
            AgentActiveChecked => $Agent && $Agent->{is_active} ? 'checked' : '',
            FieldID            => $Field ? $Field->{id} : '',
            FieldName          => $Field ? $Field->{name} : '',
            FieldType          => $Field ? $Field->{field_type} : '',
            FieldSortOrder     => $Field ? $Field->{sort_order} : '',
            FieldRequiredChecked => $Field && $Field->{is_required} ? 'checked' : '',
            FieldActiveChecked   => $Field && $Field->{active} ? 'checked' : '',
            CreateDynamicFieldsHTML => $CreateFields,
            EditDynamicFieldsHTML   => $EditFields,
            TranslationLanguageOptionsHTML => $TranslationLanguageOptions,
            CreateTranslationRowsHTML      => $CreateTranslationRows->{HTML},
            CreateTranslationRowCount      => $CreateTranslationRows->{Count},
            EditTranslationRowsHTML        => $EditTranslationRows->{HTML},
            EditTranslationRowCount        => $EditTranslationRows->{Count},
            FieldCreateTypeOptionsHTML => $Self->_FieldTypeOptions(),
            FieldEditTypeOptionsHTML   => $Self->_FieldTypeOptions(
                Selected => $Field ? $Field->{field_type} : '',
            ),
        },
    };
}

sub _DynamicFieldFormFields {
    my ( $Self, %Param ) = @_;

    my $FieldList  = $Param{FieldList} || [];
    my $FieldValue = $Param{FieldValue} || {};
    my $HTML       = '';

    for my $Field ( @{$FieldList} ) {
        my $FieldID  = $Field->{id};
        my $Name     = 'DynamicField_' . $FieldID;
        my $Label    = $Self->_Escape( $Field->{label} || $Field->{name} || '' );
        my $Value    = $Self->_Escape( $FieldValue->{$FieldID} || '' );
        my $Required = $Field->{is_required} ? ' required' : '';
        my $Type     = $Field->{field_type} || 'text';

        if ( $Type eq 'textarea' ) {
            $HTML .= '<div class="qisutu-form-field"><label>' . $Label . '</label><textarea name="' . $Name . '"' . $Required . '>' . $Value . '</textarea></div>';
        }
        else {
            if ( $Type eq 'phone' ) {
                $Type = 'text';
            }

            $HTML .= '<div class="qisutu-form-field"><label>' . $Label . '</label><input type="' . $Type . '" name="' . $Name . '" value="' . $Value . '"' . $Required . '></div>';
        }
    }

    return $HTML;
}

sub _FieldTypeOptions {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || 'text';
    my @Types    = qw(text textarea email phone date number);
    my $HTML     = '';

    for my $Type (@Types) {
        my $SelectedAttribute = $Type eq $Selected ? ' selected' : '';
        my $EscapedType       = $Self->_Escape($Type);

        $HTML .= '<option value="' . $EscapedType . '"' . $SelectedAttribute . '>' . $EscapedType . '</option>';
    }

    return $HTML;
}

sub _TranslationRows {
    my ( $Self, %Param ) = @_;

    my $Value   = $Param{Value} || {};
    my $MinRows = $Param{MinRows} || 1;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my @Codes   = sort keys %{$Value};
    my $HTML    = '';
    my $Index   = 0;

    if ( !@Codes ) {
        @Codes = ( $Self->{Config}->{Language}->{Default} || 'en' );
    }

    for my $Code (@Codes) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index    => $Index,
            Language => $Code,
            Label    => $Value->{$Code} || '',
            UILanguage => $Language,
        );
    }

    while ( $Index < $MinRows ) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index    => $Index,
            Language => '',
            Label    => '',
            UILanguage => $Language,
        );
    }

    return {
        HTML  => $HTML,
        Count => $Index,
    };
}

sub _TranslationRowHTML {
    my ( $Self, %Param ) = @_;

    my $Index    = $Param{Index} || 1;
    my $Language = $Param{Language} || '';
    my $Label    = $Param{Label} || '';
    my $UILanguage = $Param{UILanguage} || $Self->{Config}->{Language}->{Default} || 'en';
    my $LanguageLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminTranslationLanguage', Language => $UILanguage )
        : 'Language';
    my $DisplayNameLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminDisplayName', Language => $UILanguage )
        : 'Display name';
    my $RemoveLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminRemove', Language => $UILanguage )
        : 'Remove';

    return '<div class="qisutu-translation-row" data-qisutu-translation-row>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape($LanguageLabel) . '</label>'
        . '<select name="TranslationLanguage_' . $Index . '">'
        . $Self->_TranslationLanguageOptions( Selected => $Language )
        . '</select>'
        . '</div>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape($DisplayNameLabel) . '</label>'
        . '<input type="text" name="TranslationLabel_' . $Index . '" value="' . $Self->_Escape($Label) . '">'
        . '</div>'
        . '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-translation-remove>' . $Self->_Escape($RemoveLabel) . '</button>'
        . '</div>';
}

sub _LabelByLanguageFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my %Label;
    my $RowCount = $Request->{TranslationRowCount} || 0;

    if ( $RowCount !~ m{\A\d+\z} ) {
        $RowCount = 0;
    }

    if ( !$RowCount ) {
        for my $Key ( keys %{$Request} ) {
            if ( $Key =~ m{\ATranslationLanguage_(\d+)\z} && $1 > $RowCount ) {
                $RowCount = $1;
            }
        }
    }

    for my $Index ( 1 .. $RowCount ) {
        my $Code  = $Request->{ 'TranslationLanguage_' . $Index } || '';
        my $Value = $Request->{ 'TranslationLabel_' . $Index } || '';

        $Code =~ s{[^A-Za-z0-9_-]}{}g;
        next if !$Code || !$Value;

        $Label{$Code} = $Value;
    }

    return \%Label;
}

sub _TranslationLanguageOptions {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || '';
    my @Language = (
        [ '' => '-' ],
        [ aa => 'aa - Afar' ], [ ab => 'ab - Abkhazian' ], [ af => 'af - Afrikaans' ],
        [ ak => 'ak - Akan' ], [ am => 'am - Amharic' ], [ ar => 'ar - Arabic' ],
        [ as => 'as - Assamese' ], [ ay => 'ay - Aymara' ], [ az => 'az - Azerbaijani' ],
        [ ba => 'ba - Bashkir' ], [ be => 'be - Belarusian' ], [ bg => 'bg - Bulgarian' ],
        [ bh => 'bh - Bihari' ], [ bi => 'bi - Bislama' ], [ bn => 'bn - Bengali' ],
        [ bo => 'bo - Tibetan' ], [ br => 'br - Breton' ], [ bs => 'bs - Bosnian' ],
        [ ca => 'ca - Catalan' ], [ co => 'co - Corsican' ], [ cs => 'cs - Czech' ],
        [ cy => 'cy - Welsh' ], [ da => 'da - Danish' ], [ de => 'de - German' ],
        [ dz => 'dz - Dzongkha' ], [ el => 'el - Greek' ], [ en => 'en - English' ],
        [ eo => 'eo - Esperanto' ], [ es => 'es - Spanish' ], [ et => 'et - Estonian' ],
        [ eu => 'eu - Basque' ], [ fa => 'fa - Persian' ], [ fi => 'fi - Finnish' ],
        [ fj => 'fj - Fijian' ], [ fo => 'fo - Faroese' ], [ fr => 'fr - French' ],
        [ fy => 'fy - Frisian' ], [ ga => 'ga - Irish' ], [ gd => 'gd - Scottish Gaelic' ],
        [ gl => 'gl - Galician' ], [ gn => 'gn - Guarani' ], [ gu => 'gu - Gujarati' ],
        [ ha => 'ha - Hausa' ], [ haw => 'haw - Hawaiian' ], [ he => 'he - Hebrew' ],
        [ hi => 'hi - Hindi' ], [ hr => 'hr - Croatian' ], [ ht => 'ht - Haitian Creole' ],
        [ hu => 'hu - Hungarian' ], [ hy => 'hy - Armenian' ], [ id => 'id - Indonesian' ],
        [ ig => 'ig - Igbo' ], [ is => 'is - Icelandic' ], [ it => 'it - Italian' ],
        [ ja => 'ja - Japanese' ], [ jv => 'jv - Javanese' ], [ ka => 'ka - Georgian' ],
        [ kk => 'kk - Kazakh' ], [ km => 'km - Khmer' ], [ kn => 'kn - Kannada' ],
        [ ko => 'ko - Korean' ], [ ku => 'ku - Kurdish' ], [ ky => 'ky - Kyrgyz' ],
        [ la => 'la - Latin' ], [ lb => 'lb - Luxembourgish' ], [ lo => 'lo - Lao' ],
        [ lt => 'lt - Lithuanian' ], [ lv => 'lv - Latvian' ], [ mg => 'mg - Malagasy' ],
        [ mi => 'mi - Maori' ], [ mk => 'mk - Macedonian' ], [ ml => 'ml - Malayalam' ],
        [ mn => 'mn - Mongolian' ], [ mr => 'mr - Marathi' ], [ ms => 'ms - Malay' ],
        [ mt => 'mt - Maltese' ], [ my => 'my - Burmese' ], [ nb => 'nb - Norwegian Bokmal' ],
        [ ne => 'ne - Nepali' ], [ nl => 'nl - Dutch' ], [ nn => 'nn - Norwegian Nynorsk' ],
        [ no => 'no - Norwegian' ], [ oc => 'oc - Occitan' ], [ or => 'or - Odia' ],
        [ pa => 'pa - Punjabi' ], [ pl => 'pl - Polish' ], [ ps => 'ps - Pashto' ],
        [ pt => 'pt - Portuguese' ], [ qu => 'qu - Quechua' ], [ rm => 'rm - Romansh' ],
        [ ro => 'ro - Romanian' ], [ ru => 'ru - Russian' ], [ rw => 'rw - Kinyarwanda' ],
        [ sa => 'sa - Sanskrit' ], [ sd => 'sd - Sindhi' ], [ si => 'si - Sinhala' ],
        [ sk => 'sk - Slovak' ], [ sl => 'sl - Slovenian' ], [ sm => 'sm - Samoan' ],
        [ sn => 'sn - Shona' ], [ so => 'so - Somali' ], [ sq => 'sq - Albanian' ],
        [ sr => 'sr - Serbian' ], [ st => 'st - Southern Sotho' ], [ su => 'su - Sundanese' ],
        [ sv => 'sv - Swedish' ], [ sw => 'sw - Swahili' ], [ ta => 'ta - Tamil' ],
        [ te => 'te - Telugu' ], [ tg => 'tg - Tajik' ], [ th => 'th - Thai' ],
        [ tk => 'tk - Turkmen' ], [ tl => 'tl - Tagalog' ], [ tn => 'tn - Tswana' ],
        [ to => 'to - Tongan' ], [ tr => 'tr - Turkish' ], [ tt => 'tt - Tatar' ],
        [ ty => 'ty - Tahitian' ], [ ug => 'ug - Uyghur' ], [ uk => 'uk - Ukrainian' ],
        [ ur => 'ur - Urdu' ], [ uz => 'uz - Uzbek' ], [ vi => 'vi - Vietnamese' ],
        [ wo => 'wo - Wolof' ], [ xh => 'xh - Xhosa' ], [ yi => 'yi - Yiddish' ],
        [ yo => 'yo - Yoruba' ], [ zh => 'zh - Chinese' ], [ zu => 'zu - Zulu' ],
    );
    my $HTML = '';

    for my $Language (@Language) {
        my ( $Code, $Label ) = @{$Language};
        my $SelectedAttribute = $Code eq $Selected ? ' selected' : '';

        $HTML .= '<option value="' . $Self->_Escape($Code) . '"' . $SelectedAttribute . '>' . $Self->_Escape($Label) . '</option>';
    }

    return $HTML;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub _AdminObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuAdmin;
        1;
    };

    return if !$Loaded;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

1;
