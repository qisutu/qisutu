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

package AdminDynamicFields;

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

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Step     = $Request->{Step} || '';
    my $Action   = $Request->{Action} || 'List';
    my $DynamicField = $Self->_DynamicFieldObject();

    if ( $DynamicField && $Step eq 'DynamicFieldCreate' ) {
        my $FieldID = $DynamicField->FieldCreate(
            Name            => $Request->{Name},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest( Request => $Request ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            SortOrder       => $Request->{SortOrder},
            Options         => $Self->_OptionsFromRequest( Request => $Request ),
            ShowEmptyValue  => $Request->{ShowEmptyValue},
            DefaultValues   => $Self->_RequestValueList( $Request->{DefaultOption} ),
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminDynamicFields;Action=FieldEdit;FieldID=' . $FieldID }
            if $FieldID && !$DynamicField->Error();

        $Action = 'FieldCreate';
    }
    elsif ( $DynamicField && $Step eq 'DynamicFieldUpdate' ) {
        my $Success = $DynamicField->FieldUpdate(
            FieldID         => $Request->{FieldID},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest( Request => $Request ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            Options         => $Self->_OptionsFromRequest( Request => $Request ),
            ShowEmptyValue  => $Request->{ShowEmptyValue},
            DefaultValues   => $Self->_RequestValueList( $Request->{DefaultOption} ),
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminDynamicFields;Action=FieldEdit;FieldID=' . ( $Request->{FieldID} || 0 ) }
            if $Success && !$DynamicField->Error();

        $Action = 'FieldEdit';
    }
    elsif ( $DynamicField && $Step eq 'DynamicFieldDelete' ) {
        my $Success = $DynamicField->FieldDelete(
            FieldID         => $Request->{FieldID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminDynamicFields' }
            if $Success && !$DynamicField->Error();

        $Action = 'FieldEdit';
    }
    elsif ( $DynamicField && $Step eq 'DynamicFieldQueueSave' ) {
        my $QueueList = $DynamicField->QueueList( IncludeInactive => 1 );
        my @QueueIDs = map { $_->{id} }
            grep { $Request->{ 'Queue_' . ( $_->{id} || 0 ) } } @{$QueueList};

        my $Success = $DynamicField->FieldQueueSave(
            FieldID         => $Request->{FieldID},
            QueueIDs        => \@QueueIDs,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminDynamicFields;Action=FieldQueue;FieldID=' . ( $Request->{FieldID} || 0 ) }
            if $Success && !$DynamicField->Error();

        $Action = 'FieldQueue';
    }
    elsif ( $DynamicField && $Step eq 'DynamicQueueFieldSave' ) {
        my $FieldList = $DynamicField->FieldList(
            Language        => $Language,
            IncludeInactive => 1,
        );
        my @FieldIDs = map { $_->{id} }
            grep { $Request->{ 'Field_' . ( $_->{id} || 0 ) } } @{$FieldList};

        my $Success = $DynamicField->QueueFieldSave(
            QueueID         => $Request->{QueueID},
            FieldIDs        => \@FieldIDs,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminDynamicFields;Action=QueueField;QueueID=' . ( $Request->{QueueID} || 0 ) }
            if $Success && !$DynamicField->Error();

        $Action = 'QueueField';
    }

    my $FieldList = $DynamicField ? $DynamicField->FieldList(
        Language        => $Language,
        IncludeInactive => 1,
    ) : [];
    my $QueueList = $DynamicField ? $DynamicField->QueueList( IncludeInactive => 1 ) : [];

    for my $ListField ( @{$FieldList} ) {
        $ListField->{required_display} = $Self->_Text(
            $ListField->{is_required} ? 'AdminActiveYes' : 'AdminActiveNo',
            $ListField->{is_required} ? 'Yes' : 'No',
            $Language,
        );
        $ListField->{active_display} = $Self->_Text(
            $ListField->{active} ? 'AdminActiveYes' : 'AdminActiveNo',
            $ListField->{active} ? 'Yes' : 'No',
            $Language,
        );
    }

    for my $ListQueue ( @{$QueueList} ) {
        $ListQueue->{display_name} = $ListQueue->{full_name} || $ListQueue->{name} || '';
        $ListQueue->{inactive_display} = $ListQueue->{active}
            ? ''
            : $Self->_Text( 'AdminInactive', 'Inactive', $Language );
    }

    my $Field;
    my $FieldTranslation = {};
    my $FieldOptions     = [];

    if ( $DynamicField && ( $Action eq 'FieldEdit' || $Action eq 'FieldQueue' ) ) {
        $Field = $DynamicField->FieldGet( FieldID => $Request->{FieldID} );
        if ( !$Field ) {
            $Action = 'List';
        }
        elsif ( $Action eq 'FieldEdit' ) {
            $FieldTranslation = $DynamicField->TranslationList( FieldID => $Field->{id} );
            $FieldOptions     = $DynamicField->OptionList( FieldID => $Field->{id} );
        }
    }

    my $SelectedQueue;
    if ( $Action eq 'QueueField' ) {
        for my $Queue ( @{$QueueList} ) {
            if ( ( $Queue->{id} || 0 ) == ( $Request->{QueueID} || 0 ) ) {
                $SelectedQueue = $Queue;
                last;
            }
        }
        $Action = 'List' if !$SelectedQueue;
    }

    my $CreateSubmitted = $Step eq 'DynamicFieldCreate' && $Action eq 'FieldCreate' ? 1 : 0;
    my $EditSubmitted   = $Step eq 'DynamicFieldUpdate' && $Action eq 'FieldEdit' ? 1 : 0;

    my $CreateTranslationRows = $Self->_TranslationRows(
        Value    => $CreateSubmitted ? $Self->_LabelByLanguageFromRequest( Request => $Request ) : {},
        MinRows  => 1,
        Language => $Language,
    );
    my $EditTranslationRows = $Self->_TranslationRows(
        Value    => $EditSubmitted ? $Self->_LabelByLanguageFromRequest( Request => $Request ) : $FieldTranslation,
        MinRows  => 1,
        Language => $Language,
    );

    my $CreateFieldType = $Request->{FieldType} || 'text';
    my $EditFieldType   = $EditSubmitted
        ? ( $Request->{FieldType} || 'text' )
        : ( $Field ? ( $Field->{field_type} || 'text' ) : 'text' );
    my $CreateOptions = $CreateSubmitted ? $Self->_OptionsFromRequest( Request => $Request ) : [];
    my $EditOptions   = $EditSubmitted ? $Self->_OptionsFromRequest( Request => $Request ) : $FieldOptions;
    my $CreateDefaults = $CreateSubmitted ? $Self->_RequestValueList( $Request->{DefaultOption} ) : [];
    my $EditDefaults   = $EditSubmitted
        ? $Self->_RequestValueList( $Request->{DefaultOption} )
        : $Self->_RequestValueList( $Field ? $Field->{default_value} : '' );
    my $CreateOptionRows = $Self->_OptionRows(
        Options       => $CreateOptions,
        DefaultValues => $CreateDefaults,
        FieldType     => $CreateFieldType,
        MinRows       => 1,
        Language      => $Language,
    );
    my $EditOptionRows = $Self->_OptionRows(
        Options       => $EditOptions,
        DefaultValues => $EditDefaults,
        FieldType     => $EditFieldType,
        MinRows       => 1,
        Language      => $Language,
    );

    my $FieldQueueOptionsHTML = '';
    if ( $DynamicField && $Action eq 'FieldQueue' && $Field ) {
        my %Assigned = map { $_ => 1 } @{ $DynamicField->FieldQueueIDList( FieldID => $Field->{id} ) };
        $FieldQueueOptionsHTML = $Self->_QueueCheckboxesHTML(
            QueueList => $QueueList,
            Assigned  => \%Assigned,
        );
    }

    my $QueueFieldOptionsHTML = '';
    if ( $DynamicField && $Action eq 'QueueField' && $SelectedQueue ) {
        my %Assigned = map { $_ => 1 } @{ $DynamicField->QueueFieldIDList( QueueID => $SelectedQueue->{id} ) };
        $QueueFieldOptionsHTML = $Self->_FieldCheckboxesHTML(
            FieldList => $FieldList,
            Assigned  => \%Assigned,
        );
    }

    my $ErrorMessage = $DynamicField ? $DynamicField->Error() : 'Translate:AdminDynamicFieldLoadFailed';

    return {
        Template => 'AdminDynamicFields.tt',
        Data     => {
            PageTitle          => 'Translate:AdminDynamicFieldsTitle',
            ProgramTitle       => 'Translate:AdminDynamicFieldsTitle',
            ProgramDescription => 'Translate:AdminDynamicFieldsDescription',
            FormAction         => 'index.pl',
            FieldList          => $FieldList,
            QueueList          => $QueueList,
            FieldCount         => scalar @{$FieldList},
            QueueCount         => scalar @{$QueueList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowFieldCreate    => $Action eq 'FieldCreate' ? 1 : 0,
            ShowFieldEdit      => $Action eq 'FieldEdit' ? 1 : 0,
            ShowFieldQueue     => $Action eq 'FieldQueue' ? 1 : 0,
            ShowQueueField     => $Action eq 'QueueField' ? 1 : 0,
            FieldID            => $Field ? $Field->{id} : ( $Request->{FieldID} || '' ),
            FieldName          => $Field ? $Field->{name} : ( $Request->{Name} || '' ),
            FieldSortOrder     => $EditSubmitted ? ( $Request->{SortOrder} || 1000 ) : ( $Field ? $Field->{sort_order} : ( $Request->{SortOrder} || 1000 ) ),
            FieldRequiredChecked => $EditSubmitted ? ( $Request->{IsRequired} ? 'checked' : '' ) : ( $Field ? ( $Field->{is_required} ? 'checked' : '' ) : ( $Request->{IsRequired} ? 'checked' : '' ) ),
            FieldActiveChecked   => $EditSubmitted ? ( $Request->{Active} ? 'checked' : '' ) : ( $Field ? ( $Field->{active} ? 'checked' : '' ) : 'checked' ),
            FieldCreateTypeOptionsHTML => $Self->_FieldTypeOptions( Selected => $CreateFieldType ),
            FieldEditTypeOptionsHTML   => $Self->_FieldTypeOptions( Selected => $EditFieldType ),
            CreateShowEmptyChecked     => ( !$CreateSubmitted || $Request->{ShowEmptyValue} ) ? 'checked' : '',
            EditShowEmptyChecked       => $EditSubmitted
                ? ( $Request->{ShowEmptyValue} ? 'checked' : '' )
                : ( $Field && $Field->{show_empty_value} ? 'checked' : '' ),
            CreateOptionRowsHTML       => $CreateOptionRows->{HTML},
            CreateOptionRowCount       => $CreateOptionRows->{Count},
            EditOptionRowsHTML         => $EditOptionRows->{HTML},
            EditOptionRowCount         => $EditOptionRows->{Count},
            CreateTranslationRowsHTML  => $CreateTranslationRows->{HTML},
            CreateTranslationRowCount  => $CreateTranslationRows->{Count},
            EditTranslationRowsHTML    => $EditTranslationRows->{HTML},
            EditTranslationRowCount    => $EditTranslationRows->{Count},
            TranslationLanguageOptionsHTML => $Self->_TranslationLanguageOptions( Selected => '' ),
            FieldQueueOptionsHTML      => $FieldQueueOptionsHTML,
            QueueFieldOptionsHTML      => $QueueFieldOptionsHTML,
            AssignmentFieldLabel       => $Field ? ( $Field->{label} || $Field->{name} || '' ) : '',
            AssignmentQueueID          => $SelectedQueue ? $SelectedQueue->{id} : '',
            AssignmentQueueLabel       => $SelectedQueue ? ( $SelectedQueue->{full_name} || $SelectedQueue->{name} || '' ) : '',
        },
    };
}

sub _QueueCheckboxesHTML {
    my ( $Self, %Param ) = @_;

    my $QueueList = $Param{QueueList} || [];
    my $Assigned  = $Param{Assigned} || {};
    my $HTML = '';

    for my $Queue ( @{$QueueList} ) {
        my $QueueID = $Queue->{id} || 0;
        my $Checked = $Assigned->{$QueueID} ? ' checked' : '';
        my $Inactive = $Queue->{active} ? '' : ' (' . $Self->_Text( 'AdminInactive', 'Inactive' ) . ')';
        my $Label = ( $Queue->{full_name} || $Queue->{name} || '' ) . $Inactive;
        $HTML .= '<label class="qisutu-assignment-checkbox">'
            . '<input type="checkbox" name="Queue_' . $QueueID . '" value="1"' . $Checked . '>'
            . '<span>' . $Self->_Escape($Label) . '</span>'
            . '</label>';
    }

    return $HTML || '<p class="qisutu-form-hint">' . $Self->_Escape( $Self->_Text( 'AdminNoEntries', 'No entries.' ) ) . '</p>';
}

sub _FieldCheckboxesHTML {
    my ( $Self, %Param ) = @_;

    my $FieldList = $Param{FieldList} || [];
    my $Assigned  = $Param{Assigned} || {};
    my $HTML = '';

    for my $Field ( @{$FieldList} ) {
        my $FieldID = $Field->{id} || 0;
        my $Checked = $Assigned->{$FieldID} ? ' checked' : '';
        my $Inactive = $Field->{active} ? '' : ' (' . $Self->_Text( 'AdminInactive', 'Inactive' ) . ')';
        my $Label = ( $Field->{label} || $Field->{name} || '' ) . $Inactive;
        $HTML .= '<label class="qisutu-assignment-checkbox">'
            . '<input type="checkbox" name="Field_' . $FieldID . '" value="1"' . $Checked . '>'
            . '<span>' . $Self->_Escape($Label) . '</span>'
            . '</label>';
    }

    return $HTML || '<p class="qisutu-form-hint">' . $Self->_Escape( $Self->_Text( 'AdminNoEntries', 'No entries.' ) ) . '</p>';
}

sub _FieldTypeOptions {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || 'text';
    my @Types = qw(text textarea email phone date number dropdown multiselect checkbox);
    my $HTML = '';

    for my $Type (@Types) {
        my $SelectedAttribute = $Type eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape($Type) . '"' . $SelectedAttribute . '>'
            . $Self->_Escape($Type) . '</option>';
    }

    return $HTML;
}

sub _OptionsFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request  = $Param{Request} || {};
    my $RowCount = $Request->{OptionRowCount} || 0;
    my @Options;

    $RowCount = 0 if $RowCount !~ m{\A\d+\z};
    if ( !$RowCount ) {
        for my $Key ( keys %{$Request} ) {
            if ( $Key =~ m{\AOptionKey_(\d+)\z} && $1 > $RowCount ) {
                $RowCount = $1;
            }
        }
    }

    for my $Index ( 1 .. $RowCount ) {
        my $OptionKey   = defined $Request->{ 'OptionKey_' . $Index } ? $Request->{ 'OptionKey_' . $Index } : '';
        my $OptionValue = defined $Request->{ 'OptionValue_' . $Index } ? $Request->{ 'OptionValue_' . $Index } : '';
        my $SortOrder   = $Request->{ 'OptionSortOrder_' . $Index } || 1000;

        next if $OptionKey eq '' && $OptionValue eq '';

        push @Options, {
            option_key   => $OptionKey,
            option_value => $OptionValue,
            sort_order   => $SortOrder,
        };
    }

    return \@Options;
}

sub _RequestValueList {
    my ( $Self, $Value ) = @_;

    my @Raw = ref $Value eq 'ARRAY'
        ? @{$Value}
        : split( /\r?\n/, defined $Value ? $Value : '' );
    my @Value;
    my %Seen;

    for my $Item (@Raw) {
        $Item = '' if !defined $Item;
        $Item =~ s{\A\s+|\s+\z}{}g;
        next if $Item eq '' || $Seen{$Item}++;
        push @Value, $Item;
    }

    return \@Value;
}

sub _OptionRows {
    my ( $Self, %Param ) = @_;

    my $Options       = ref $Param{Options} eq 'ARRAY' ? $Param{Options} : [];
    my $DefaultValues = ref $Param{DefaultValues} eq 'ARRAY' ? $Param{DefaultValues} : [];
    my $FieldType     = $Param{FieldType} || 'dropdown';
    my $MinRows       = $Param{MinRows} || 1;
    my $Language      = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my %Default       = map { $_ => 1 } @{$DefaultValues};
    my $HTML          = '';
    my $Index         = 0;

    for my $Option ( @{$Options} ) {
        next if ref $Option ne 'HASH';
        $Index++;
        $HTML .= $Self->_OptionRowHTML(
            Index       => $Index,
            OptionKey   => $Option->{option_key},
            OptionValue => $Option->{option_value},
            SortOrder   => $Option->{sort_order},
            IsDefault   => $Default{ $Option->{option_key} || '' } ? 1 : 0,
            FieldType   => $FieldType,
            Language    => $Language,
        );
    }

    while ( $Index < $MinRows ) {
        $Index++;
        $HTML .= $Self->_OptionRowHTML(
            Index       => $Index,
            OptionKey   => '',
            OptionValue => '',
            SortOrder   => $Index * 100,
            IsDefault   => 0,
            FieldType   => $FieldType,
            Language    => $Language,
        );
    }

    return { HTML => $HTML, Count => $Index };
}

sub _OptionRowHTML {
    my ( $Self, %Param ) = @_;

    my $Index       = $Param{Index} || 1;
    my $OptionKey   = defined $Param{OptionKey} ? $Param{OptionKey} : '';
    my $OptionValue = defined $Param{OptionValue} ? $Param{OptionValue} : '';
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $IsDefault   = $Param{IsDefault} ? 1 : 0;
    my $FieldType   = $Param{FieldType} || 'dropdown';
    my $Language    = $Param{Language} || 'en';
    my $InputType   = $FieldType eq 'dropdown' ? 'radio' : 'checkbox';
    my $Checked     = $IsDefault ? ' checked' : '';

    return '<div class="qisutu-dynamic-option-row" data-qisutu-option-row>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape( $Self->_Text( 'AdminDynamicFieldOptionKey', 'Key', $Language ) ) . '</label>'
        . '<input type="text" name="OptionKey_' . $Index . '" value="' . $Self->_Escape($OptionKey) . '" data-qisutu-option-key>'
        . '</div>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape( $Self->_Text( 'AdminDynamicFieldOptionValue', 'Value', $Language ) ) . '</label>'
        . '<input type="text" name="OptionValue_' . $Index . '" value="' . $Self->_Escape($OptionValue) . '">'
        . '</div>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape( $Self->_Text( 'AdminSortOrder', 'Sort order', $Language ) ) . '</label>'
        . '<input type="number" name="OptionSortOrder_' . $Index . '" value="' . $Self->_Escape($SortOrder) . '" min="1">'
        . '</div>'
        . '<label class="qisutu-form-checkbox qisutu-dynamic-option-default">'
        . '<input type="' . $InputType . '" name="DefaultOption" value="' . $Self->_Escape($OptionKey) . '" data-qisutu-option-default' . $Checked . '>'
        . '<span>' . $Self->_Escape( $Self->_Text( 'AdminDynamicFieldOptionDefault', 'Default', $Language ) ) . '</span>'
        . '</label>'
        . '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-option-remove>'
        . $Self->_Escape( $Self->_Text( 'AdminRemove', 'Remove', $Language ) )
        . '</button>'
        . '</div>';
}

sub _TranslationRows {
    my ( $Self, %Param ) = @_;

    my $Value    = $Param{Value} || {};
    my $MinRows  = $Param{MinRows} || 1;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my @Codes    = sort keys %{$Value};
    my $HTML     = '';
    my $Index    = 0;

    if ( !@Codes ) {
        @Codes = ( $Self->{Config}->{Language}->{Default} || 'en' );
    }

    for my $Code (@Codes) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index      => $Index,
            Language   => $Code,
            Label      => $Value->{$Code} || '',
            UILanguage => $Language,
        );
    }

    while ( $Index < $MinRows ) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index      => $Index,
            Language   => '',
            Label      => '',
            UILanguage => $Language,
        );
    }

    return { HTML => $HTML, Count => $Index };
}

sub _TranslationRowHTML {
    my ( $Self, %Param ) = @_;

    my $Index      = $Param{Index} || 1;
    my $Language   = $Param{Language} || '';
    my $Label      = $Param{Label} || '';
    my $UILanguage = $Param{UILanguage} || 'en';

    return '<div class="qisutu-translation-row" data-qisutu-translation-row>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape( $Self->_Text( 'AdminTranslationLanguage', 'Language', $UILanguage ) ) . '</label>'
        . '<select name="TranslationLanguage_' . $Index . '">'
        . $Self->_TranslationLanguageOptions( Selected => $Language )
        . '</select></div>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape( $Self->_Text( 'AdminDisplayName', 'Display name', $UILanguage ) ) . '</label>'
        . '<input type="text" name="TranslationLabel_' . $Index . '" value="' . $Self->_Escape($Label) . '">'
        . '</div>'
        . '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-translation-remove>'
        . $Self->_Escape( $Self->_Text( 'AdminRemove', 'Remove', $UILanguage ) )
        . '</button></div>';
}

sub _LabelByLanguageFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $RowCount = $Request->{TranslationRowCount} || 0;
    my %Label;

    $RowCount = 0 if $RowCount !~ m{\A\d+\z};
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
    my @Languages = ( [ '' => '-' ] );
    my $Path = $Self->{Config}->{Paths}->{Language} || '';

    if ( $Path && -d $Path ) {
        if ( opendir my $DH, $Path ) {
            for my $File ( sort grep { m{\A[A-Za-z0-9_-]+\.pm\z} } readdir $DH ) {
                ( my $Code = $File ) =~ s{\.pm\z}{};
                push @Languages, [ $Code => $Code ];
            }
            closedir $DH;
        }
    }

    if ( @Languages == 1 ) {
        push @Languages, map { [ $_ => $_ ] }
            qw(de en fr it pt-BR pt-PT es nl pl cs tr);
    }

    my $HTML = '';
    for my $Language (@Languages) {
        my ( $Code, $Label ) = @{$Language};
        my $SelectedAttribute = $Code eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape($Code) . '"' . $SelectedAttribute . '>'
            . $Self->_Escape($Label) . '</option>';
    }

    return $HTML;
}

sub _Text {
    my ( $Self, $Key, $Fallback, $Language ) = @_;

    $Language ||= $Self->{Config}->{Language}->{Default} || 'en';
    return $Fallback if !$Self->{Output};

    my $Text = $Self->{Output}->Translate( Key => $Key, Language => $Language );
    return $Text && $Text ne $Key ? $Text : $Fallback;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;
    return $Value;
}

sub _DynamicFieldObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuDynamicField;
        1;
    };
    return if !$Loaded;

    return QisutuDynamicField->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );
}

1;
