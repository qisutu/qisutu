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

package QisutuDynamicField;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub FieldList {
    my ( $Self, %Param ) = @_;

    my $Language        = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;
    my $QueueID         = $Param{QueueID} || 0;
    my $QueueJoin       = '';
    my $Where           = 'WHERE 1 = 1';

    if ( !$IncludeInactive ) {
        $Where .= ' AND f.active = 1';
    }

    if ($QueueID) {
        return [] if $QueueID !~ m{\A\d+\z};
        $QueueJoin = 'INNER JOIN ticket_dynamic_field_queue fq
            ON fq.field_id = f.id
           AND fq.queue_id = ?';
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.id,
            f.name,
            COALESCE(current_translation.label, f.label, f.name) AS label,
            f.field_type,
            f.is_required,
            f.show_empty_value,
            f.default_value,
            f.active,
            f.sort_order
         FROM ticket_dynamic_field f
         ' . $QueueJoin . '
         LEFT JOIN ticket_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
           AND current_translation.language = ?
         ' . $Where . '
         ORDER BY f.sort_order ASC, label ASC, f.id ASC',
        $QueueID ? ( $QueueID, $Language ) : ($Language),
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic fields could not be loaded';
        return [];
    }

    return $Rows;
}

sub FieldGet {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Field = $Self->{DB}->SelectRow(
        'SELECT id, name, label, field_type, is_required, show_empty_value, default_value, active, sort_order
         FROM ticket_dynamic_field
         WHERE id = ?
         LIMIT 1',
        $FieldID,
    );

    if ( !$Field ) {
        $Self->{LastError} = 'Dynamic field was not found';
        return;
    }

    return $Field;
}

sub FieldCreate {
    my ( $Self, %Param ) = @_;

    my $Name         = $Self->_Trim( $Param{Name} );
    my $FieldType    = $Self->_FieldTypeClean( $Param{FieldType} );
    my $Required     = $Param{IsRequired} ? 1 : 0;
    my $SortOrder    = $Param{SortOrder} || 1000;
    my $Selection    = $Self->_SelectionConfigurationClean(
        FieldType      => $FieldType,
        Options        => $Param{Options},
        ShowEmptyValue => $Param{ShowEmptyValue},
        DefaultValues  => $Param{DefaultValues},
    );
    return if !$Selection;
    my $UserID       = $Param{ChangedByUserID} || 1;
    my $Labels       = $Param{LabelByLanguage} || {};
    my $OptionTranslations = ref $Param{OptionTranslations} eq 'HASH'
        ? $Param{OptionTranslations}
        : {};
    my $DefaultLabel = $Self->_FirstTranslationLabel( Labels => $Labels );

    if ( !$Name || !$DefaultLabel ) {
        $Self->{LastError} = 'Translate:AdminDynamicFieldNameAndLabelRequired';
        return;
    }

    if ( $Name !~ m{\A[A-Za-z][A-Za-z0-9_]*\z} ) {
        $Self->{LastError} = 'Translate:AdminDynamicFieldDatabaseNameInvalid';
        return;
    }

    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field transaction could not be started';
        return;
    };

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_dynamic_field (
            name, label, field_type, is_required, show_empty_value, default_value, active, sort_order,
            created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
        $Name,
        $DefaultLabel,
        $FieldType,
        $Required,
        $Selection->{ShowEmptyValue},
        $Selection->{DefaultValue},
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $FieldID = $Self->{DB}->LastInsertID('ticket_dynamic_field');
    if ( !$FieldID || !$Self->TranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{DB}->Rollback();
        return;
    }

    if ( $Selection->{IsSelection} && !$Self->OptionSave(
        FieldID         => $FieldID,
        Options         => $Selection->{Options},
        OptionTranslations => $OptionTranslations,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return $FieldID;
}

sub FieldUpdate {
    my ( $Self, %Param ) = @_;

    my $FieldID      = $Param{FieldID} || 0;
    my $FieldType    = $Self->_FieldTypeClean( $Param{FieldType} );
    my $Required     = $Param{IsRequired} ? 1 : 0;
    my $Active       = $Param{Active} ? 1 : 0;
    my $SortOrder    = $Param{SortOrder} || 1000;
    my $Selection    = $Self->_SelectionConfigurationClean(
        FieldType      => $FieldType,
        Options        => $Param{Options},
        ShowEmptyValue => $Param{ShowEmptyValue},
        DefaultValues  => $Param{DefaultValues},
    );
    return if !$Selection;
    my $UserID       = $Param{ChangedByUserID} || 1;
    my $Labels       = $Param{LabelByLanguage} || {};
    my $OptionTranslations = ref $Param{OptionTranslations} eq 'HASH'
        ? $Param{OptionTranslations}
        : {};
    my $ExistingField = $FieldID =~ m{\A\d+\z} && $FieldID
        ? $Self->FieldGet( FieldID => $FieldID )
        : undef;
    my $DefaultLabel = $Self->_FirstTranslationLabel(
        Labels        => $Labels,
        ExistingLabel => $ExistingField ? $ExistingField->{label} : '',
    );

    if ( $FieldID !~ m{\A\d+\z} || !$FieldID || !$ExistingField || !$DefaultLabel ) {
        $Self->{LastError} = 'Translate:AdminDynamicFieldNameAndLabelRequired';
        return;
    }

    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field transaction could not be started';
        return;
    };

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_dynamic_field
         SET label = ?,
             field_type = ?,
             is_required = ?,
             show_empty_value = ?,
             default_value = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE id = ?',
        $DefaultLabel,
        $FieldType,
        $Required,
        $Selection->{ShowEmptyValue},
        $Selection->{DefaultValue},
        $Active,
        $SortOrder,
        $UserID,
        $FieldID,
    );

    if ( !$Result || !$Self->TranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Translate:AdminDynamicFieldUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    if ( $Selection->{IsSelection} && !$Self->OptionSave(
        FieldID         => $FieldID,
        Options         => $Selection->{Options},
        OptionTranslations => $OptionTranslations,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return 1;
}

sub FieldDelete {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Result = $Self->{DB}->Do(
        'DELETE FROM ticket_dynamic_field WHERE id = ?',
        $FieldID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldDeleteFailed';
        return;
    }

    return 1;
}

sub TranslationList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return {} if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT language, label
         FROM ticket_dynamic_field_translation
         WHERE field_id = ?',
        $FieldID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field translations could not be loaded';
        return {};
    }

    my %Translation = map {
        ( $_->{language} || '' ) => ( defined $_->{label} ? $_->{label} : '' )
    } @{$Rows};

    return \%Translation;
}

sub TranslationSave {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $Labels  = $Param{LabelByLanguage} || {};
    my $UserID  = $Param{ChangedByUserID} || 1;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my @Language = sort keys %{$Labels};
    if ( !@Language ) {
        $Self->{LastError} = 'Translate:AdminDynamicFieldTranslationRequired';
        return;
    }

    my $DeleteResult = $Self->{DB}->Do(
        'DELETE FROM ticket_dynamic_field_translation WHERE field_id = ?',
        $FieldID,
    );

    if ( !$DeleteResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field translations could not be deleted';
        return;
    }

    for my $Language (@Language) {
        my $Label = $Self->_Trim( $Labels->{$Language} );

        if ( !$Label || $Language !~ m{\A[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})?\z} ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldTranslationRequired';
            return;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_translation (
                field_id, language, label, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?)',
            $FieldID,
            $Language,
            $Label,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field translation could not be saved';
            return;
        }
    }

    return 1;
}

sub OptionList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return [] if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Language = $Param{Language}
        ? $Self->_LanguageClean( $Param{Language} )
        : '';
    my ( $SQL, @Bind );

    if ($Language) {
        $SQL = 'SELECT
                    field_option.id,
                    field_option.field_id,
                    field_option.option_key,
                    COALESCE(current_translation.option_value, field_option.option_value) AS option_value,
                    field_option.option_value AS base_option_value,
                    field_option.sort_order
                FROM ticket_dynamic_field_option field_option
                LEFT JOIN ticket_dynamic_field_option_translation current_translation
                   ON current_translation.option_id = field_option.id
                  AND current_translation.language = ?
                WHERE field_option.field_id = ?
                ORDER BY field_option.sort_order ASC, field_option.id ASC';
        @Bind = ( $Language, $FieldID );
    }
    else {
        $SQL = 'SELECT id, field_id, option_key, option_value, option_value AS base_option_value, sort_order
                FROM ticket_dynamic_field_option
                WHERE field_id = ?
                ORDER BY sort_order ASC, id ASC';
        @Bind = ($FieldID);
    }

    my $Rows = $Self->{DB}->SelectAll(
        $SQL,
        @Bind,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field options could not be loaded';
        return [];
    }

    return $Rows;
}

sub OptionTranslationList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return {} if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT translation.language, field_option.option_key, translation.option_value
         FROM ticket_dynamic_field_option_translation translation
         INNER JOIN ticket_dynamic_field_option field_option
            ON field_option.id = translation.option_id
         WHERE field_option.field_id = ?
         ORDER BY translation.language ASC, field_option.sort_order ASC, field_option.id ASC',
        $FieldID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field option translations could not be loaded';
        return {};
    }

    my %Translation;
    for my $Row ( @{$Rows} ) {
        my $Language = $Row->{language} || '';
        my $OptionKey = $Row->{option_key} || '';
        next if !$Language || !$OptionKey;
        $Translation{$Language}->{$OptionKey} = defined $Row->{option_value}
            ? $Row->{option_value}
            : '';
    }

    return \%Translation;
}

sub OptionSave {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $Options = ref $Param{Options} eq 'ARRAY' ? $Param{Options} : [];
    my $Translations = ref $Param{OptionTranslations} eq 'HASH'
        ? $Param{OptionTranslations}
        : {};
    my $UserID  = $Param{ChangedByUserID} || 1;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $DeleteResult = $Self->{DB}->Do(
        'DELETE FROM ticket_dynamic_field_option WHERE field_id = ?',
        $FieldID,
    );

    if ( !$DeleteResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldOptionSaveFailed';
        return;
    }

    my %OptionIDByKey;
    for my $Option ( @{$Options} ) {
        next if ref $Option ne 'HASH';

        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_option (
                field_id, option_key, option_value, sort_order,
                created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?, ?)',
            $FieldID,
            $Option->{option_key},
            $Option->{option_value},
            $Option->{sort_order},
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldOptionSaveFailed';
            return;
        }

        my $OptionID = $Self->{DB}->LastInsertID('ticket_dynamic_field_option');
        if ( !$OptionID ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldOptionSaveFailed';
            return;
        }
        $OptionIDByKey{ $Option->{option_key} } = $OptionID;
    }

    for my $Language ( sort keys %{$Translations} ) {
        my $CleanLanguage = $Self->_LanguageClean($Language);
        my $LanguageValues = $Translations->{$Language};

        if ( $CleanLanguage ne $Language || ref $LanguageValues ne 'HASH' ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldOptionTranslationInvalid';
            return;
        }

        for my $OptionKey ( sort keys %{$LanguageValues} ) {
            my $OptionValue = $Self->_Trim( $LanguageValues->{$OptionKey} );
            next if $OptionValue eq '';

            if ( !$OptionIDByKey{$OptionKey} || length($OptionValue) > 255 || $OptionValue =~ m{[\r\n]} ) {
                $Self->{LastError} = 'Translate:AdminDynamicFieldOptionTranslationInvalid';
                return;
            }

            my $Result = $Self->{DB}->Do(
                'INSERT INTO ticket_dynamic_field_option_translation (
                    option_id, language, option_value, created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, ?, ?, ?)',
                $OptionIDByKey{$OptionKey},
                $CleanLanguage,
                $OptionValue,
                $UserID,
                $UserID,
            );

            if ( !$Result ) {
                $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldOptionSaveFailed';
                return;
            }
        }
    }

    return 1;
}

sub QueueList {
    my ( $Self, %Param ) = @_;

    my $IncludeInactive = exists $Param{IncludeInactive} ? ( $Param{IncludeInactive} ? 1 : 0 ) : 1;
    my $Where = $IncludeInactive ? '' : 'WHERE active = 1';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name, active, sort_order
         FROM ticket_queue
         ' . $Where . '
         ORDER BY sort_order ASC, full_name ASC, name ASC, id ASC'
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queues could not be loaded';
        return [];
    }

    return $Rows;
}

sub FieldQueueIDList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return [] if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT queue_id
         FROM ticket_dynamic_field_queue
         WHERE field_id = ?
         ORDER BY queue_id ASC',
        $FieldID,
    ) || [];

    return [ map { 0 + ( $_->{queue_id} || 0 ) } @{$Rows} ];
}

sub QueueFieldIDList {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    return [] if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT field_id
         FROM ticket_dynamic_field_queue
         WHERE queue_id = ?
         ORDER BY field_id ASC',
        $QueueID,
    ) || [];

    return [ map { 0 + ( $_->{field_id} || 0 ) } @{$Rows} ];
}

sub FieldQueueSave {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $QueueIDs = ref $Param{QueueIDs} eq 'ARRAY' ? $Param{QueueIDs} : [];
    my $UserID   = $Param{ChangedByUserID} || 1;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    return $Self->_AssignmentSave(
        DeleteSQL => 'DELETE FROM ticket_dynamic_field_queue WHERE field_id = ?',
        DeleteID  => $FieldID,
        Rows      => [ map { [ $FieldID, $_ ] } grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{$QueueIDs} ],
        UserID    => $UserID,
    );
}

sub QueueFieldSave {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    my $FieldIDs = ref $Param{FieldIDs} eq 'ARRAY' ? $Param{FieldIDs} : [];
    my $UserID   = $Param{ChangedByUserID} || 1;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    return $Self->_AssignmentSave(
        DeleteSQL => 'DELETE FROM ticket_dynamic_field_queue WHERE queue_id = ?',
        DeleteID  => $QueueID,
        Rows      => [ map { [ $_, $QueueID ] } grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{$FieldIDs} ],
        UserID    => $UserID,
    );
}

sub TicketValueList {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    return {} if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT field_id, value_text
         FROM ticket_dynamic_field_value
         WHERE ticket_id = ?',
        $TicketID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field values could not be loaded';
        return {};
    }

    my %Value = map {
        ( $_->{field_id} || 0 ) => ( defined $_->{value_text} ? $_->{value_text} : '' )
    } @{$Rows};

    return \%Value;
}

sub TicketValueValidate {
    my ( $Self, %Param ) = @_;

    my $QueueID  = $Param{QueueID} || 0;
    my $Request  = $Param{Request} || {};
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    my $Fields = $Self->FieldList(
        QueueID  => $QueueID,
        Language => $Language,
    );
    return if $Self->Error();

    for my $Field ( @{$Fields} ) {
        my $Key  = 'TicketDynamicField_' . ( $Field->{id} || 0 );
        my $Type = $Field->{field_type} || 'text';

        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my $Values = $Self->_ValueList( $Request->{$Key} );
            my $Options = $Self->OptionList( FieldID => $Field->{id} );
            return if $Self->Error();

            my %Allowed = map { ( $_->{option_key} || '' ) => 1 } @{$Options};

            if ( $Type eq 'dropdown' && @{$Values} > 1 ) {
                $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
                return;
            }

            if ( ( $Field->{is_required} || !$Field->{show_empty_value} ) && !@{$Values} ) {
                $Self->{LastError} = 'Translate:TicketDynamicFieldRequired';
                return;
            }

            for my $Value ( @{$Values} ) {
                if ( !$Allowed{$Value} ) {
                    $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
                    return;
                }
            }

            next;
        }

        my $Value = $Self->_Trim( $Request->{$Key} );

        if ( $Type eq 'checkbox' ) {
            if ( $Value ne '' && $Value ne '1' ) {
                $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
                return;
            }
            if ( $Field->{is_required} && $Value ne '1' ) {
                $Self->{LastError} = 'Translate:TicketDynamicFieldRequired';
                return;
            }
            next;
        }

        if ( $Field->{is_required} && $Value eq '' ) {
            $Self->{LastError} = 'Translate:TicketDynamicFieldRequired';
            return;
        }

        next if $Value eq '';

        if ( $Type eq 'email' && $Value !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} ) {
            $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
            return;
        }
        if ( $Type eq 'number' && $Value !~ m{\A[-+]?(?:\d+(?:[\.,]\d+)?|[\.,]\d+)\z} ) {
            $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
            return;
        }
        if ( $Type eq 'date' && !$Self->_DateTimeValueValid($Value) ) {
            $Self->{LastError} = 'Translate:TicketDynamicFieldInvalid';
            return;
        }
    }

    return 1;
}

sub TicketValueSave {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $QueueID  = $Param{QueueID} || 0;
    my $Request  = $Param{Request} || {};
    my $UserID   = $Param{ChangedByUserID} || 1;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    return if $TicketID !~ m{\A\d+\z} || !$TicketID;
    return if !$Self->TicketValueValidate(
        QueueID  => $QueueID,
        Request  => $Request,
        Language => $Language,
    );

    my $Fields = $Self->FieldList(
        QueueID  => $QueueID,
        Language => $Language,
    );
    return if $Self->Error();

    for my $Field ( @{$Fields} ) {
        my $FieldID = $Field->{id} || 0;
        my $Key = 'TicketDynamicField_' . $FieldID;
        my $PresentKey = 'TicketDynamicFieldPresent_' . $FieldID;
        next if !exists $Request->{$Key} && !$Request->{$PresentKey};

        my $Type = $Field->{field_type} || 'text';
        my $Value = $Type eq 'dropdown' || $Type eq 'multiselect'
            ? join( "\n", @{ $Self->_ValueList( $Request->{$Key} ) } )
            : $Type eq 'checkbox'
                ? ( $Self->_Trim( $Request->{$Key} ) eq '1' ? '1' : '0' )
                : $Self->_Trim( $Request->{$Key} );

        if ( $Type eq 'date' && $Value ne '' ) {
            $Value = $Self->_DateTimeInputValue($Value);
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_value (
                ticket_id, field_id, value_text, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                value_text = VALUES(value_text),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $TicketID,
            $FieldID,
            $Value,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketDynamicFieldSaveFailed';
            return;
        }
    }

    return 1;
}

sub FormHTML {
    my ( $Self, %Param ) = @_;

    my $QueueID   = $Param{QueueID} || 0;
    my $TicketID  = $Param{TicketID} || 0;
    my $Request   = $Param{Request} || {};
    my $Language  = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $FormClass = $Param{FormClass} || '';
    my $IDPrefix  = $Param{IDPrefix} || 'qisutu-ticket-dynamic-field';
    $IDPrefix =~ s{[^A-Za-z0-9_-]}{-}g;

    return '' if !$QueueID;

    my $Fields = $Self->FieldList(
        QueueID  => $QueueID,
        Language => $Language,
    );
    return '' if !@{$Fields};

    my $Values = $TicketID ? $Self->TicketValueList( TicketID => $TicketID ) : {};
    my $Title = $Self->_Translate(
        Key      => 'TicketDynamicFields',
        Language => $Language,
        Fallback => $Language eq 'de' ? 'Dynamische Felder' : 'Dynamic fields',
    );
    my $MultiSelectHint = $Self->_Translate(
        Key      => 'TicketDynamicFieldMultiSelectHint',
        Language => $Language,
        Fallback => $Language eq 'de'
            ? 'Mehrere Werte mit Strg bzw. Cmd auswählen.'
            : 'Select multiple values with Ctrl or Cmd.',
    );
    my $EmptyLabel = $Self->_Translate(
        Key      => 'TicketDynamicFieldEmptyValue',
        Language => $Language,
        Fallback => '-',
    );

    my $HTML = '<section class="qisutu-ticket-dynamic-fields ' . $Self->_Escape($FormClass) . '" data-qisutu-ticket-dynamic-fields>'
        . '<h4>' . $Self->_Escape($Title) . '</h4>'
        . '<div class="qisutu-ticket-dynamic-fields-grid">';

    for my $Field ( @{$Fields} ) {
        my $FieldID = $Field->{id} || 0;
        my $Key     = 'TicketDynamicField_' . $FieldID;
        my $Type    = $Field->{field_type} || 'text';
        my $HasRequestValue = exists $Request->{$Key};
        my $HasTicketValue  = exists $Values->{$FieldID};
        my $RawValue = $HasRequestValue
            ? $Request->{$Key}
            : ( $HasTicketValue ? $Values->{$FieldID} : '' );

        my $Required = ( $Field->{is_required} || ( ( $Type eq 'dropdown' || $Type eq 'multiselect' ) && !$Field->{show_empty_value} ) )
            ? ' required'
            : '';
        my $RequiredMarker = $Field->{is_required} ? ' *' : '';
        my $InputType = $Type eq 'email' ? 'email'
            : $Type eq 'phone' ? 'tel'
            : $Type eq 'date' ? 'datetime-local'
            : $Type eq 'number' ? 'number'
            : 'text';
        my $WideClass = $Type eq 'textarea' || $Type eq 'multiselect'
            ? ' qisutu-ticket-dynamic-field-wide'
            : '';
        my $InputID = $IDPrefix . '-' . $FieldID;

        $HTML .= '<div class="qisutu-form-field' . $WideClass . '">';
        if ( $Type ne 'checkbox' ) {
            $HTML .= '<label for="' . $Self->_Escape($InputID) . '">'
                . $Self->_Escape( $Field->{label} || $Field->{name} || '' )
                . $RequiredMarker
                . '</label>';
        }

        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my $SelectedValues = $Self->_ValueList($RawValue);

            if ( !$HasRequestValue && !$HasTicketValue && !@{$SelectedValues} && !$Field->{show_empty_value} ) {
                $SelectedValues = $Self->_ValueList( $Field->{default_value} );
            }

            my %Selected = map { $_ => 1 } @{$SelectedValues};
            my $Options = $Self->OptionList( FieldID => $FieldID, Language => $Language );
            return '' if $Self->Error();

            my $Multiple = $Type eq 'multiselect' ? ' multiple' : '';
            my $OptionCount = scalar @{$Options};
            $OptionCount++ if $Field->{show_empty_value};
            $OptionCount = 2 if $OptionCount < 2;
            $OptionCount = 6 if $OptionCount > 6;
            my $Size = $Type eq 'multiselect' ? ' size="' . $OptionCount . '"' : '';
            my $DataAttribute = $Type eq 'multiselect' ? ' data-qisutu-dynamic-multiselect' : '';

            $HTML .= '<input type="hidden" name="TicketDynamicFieldPresent_' . $FieldID . '" value="1">';
            $HTML .= '<select id="' . $Self->_Escape($InputID) . '" name="' . $Key . '"'
                . $Multiple . $Size . $DataAttribute . $Required . '>';

            if ( $Field->{show_empty_value} ) {
                my $EmptySelected = !@{$SelectedValues} ? ' selected' : '';
                $HTML .= '<option value=""' . $EmptySelected . '>' . $Self->_Escape($EmptyLabel) . '</option>';
            }

            for my $Option ( @{$Options} ) {
                my $OptionKey = defined $Option->{option_key} ? $Option->{option_key} : '';
                my $OptionSelected = $Selected{$OptionKey} ? ' selected' : '';
                $HTML .= '<option value="' . $Self->_Escape($OptionKey) . '"' . $OptionSelected . '>'
                    . $Self->_Escape( $Option->{option_value} || $OptionKey )
                    . '</option>';
            }

            $HTML .= '</select>';
            if ( $Type eq 'multiselect' ) {
                $HTML .= '<span class="qisutu-form-hint">' . $Self->_Escape($MultiSelectHint) . '</span>';
            }
        }
        elsif ( $Type eq 'checkbox' ) {
            my $Checked = defined $RawValue && $RawValue eq '1' ? ' checked' : '';
            $HTML .= '<input type="hidden" name="TicketDynamicFieldPresent_' . $FieldID . '" value="1">'
                . '<label class="qisutu-form-checkbox" for="' . $Self->_Escape($InputID) . '">'
                . '<input id="' . $Self->_Escape($InputID) . '" type="checkbox" name="' . $Key . '" value="1"'
                . $Checked . $Required . '>'
                . '<span>' . $Self->_Escape( $Field->{label} || $Field->{name} || '' ) . $RequiredMarker . '</span>'
                . '</label>';
        }
        elsif ( $Type eq 'textarea' ) {
            my $Value = defined $RawValue && ref $RawValue ne 'ARRAY' ? $RawValue : '';
            $HTML .= '<textarea id="' . $Self->_Escape($InputID) . '" name="' . $Key . '" rows="4"' . $Required . '>'
                . $Self->_Escape($Value) . '</textarea>';
        }
        else {
            my $Value = defined $RawValue && ref $RawValue ne 'ARRAY' ? $RawValue : '';
            if ( $Type eq 'date' && $Value ne '' ) {
                $Value = $Self->_DateTimeInputValue($Value);
            }
            my $Step = $Type eq 'number' ? ' step="any"'
                : $Type eq 'date' ? ' step="60"'
                : '';
            my $LanguageAttribute = $Type eq 'date'
                ? ' lang="' . $Self->_Escape( $Self->_LanguageClean($Language) ) . '"'
                : '';
            $HTML .= '<input id="' . $Self->_Escape($InputID) . '" type="' . $InputType . '" name="' . $Key . '" value="'
                . $Self->_Escape($Value) . '"' . $Step . $LanguageAttribute . $Required . '>';
        }

        $HTML .= '</div>';
    }

    $HTML .= '</div></section>';

    return $HTML;
}

sub DisplayHTML {
    my ( $Self, %Param ) = @_;

    my $QueueID  = $Param{QueueID} || 0;
    my $TicketID = $Param{TicketID} || 0;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    return '' if !$QueueID || !$TicketID;

    my $Fields = $Self->FieldList(
        QueueID  => $QueueID,
        Language => $Language,
    );
    my $Values = $Self->TicketValueList( TicketID => $TicketID );
    my $HTML = '';

    for my $Field ( @{$Fields} ) {
        my $FieldID = $Field->{id} || 0;
        my $Type = $Field->{field_type} || 'text';
        my $RawValue = exists $Values->{$FieldID} && defined $Values->{$FieldID}
            ? $Values->{$FieldID}
            : '';
        my $ValueHTML = '-';

        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my $SelectedValues = $Self->_ValueList($RawValue);
            if ( @{$SelectedValues} ) {
                my $Options = $Self->OptionList( FieldID => $FieldID, Language => $Language );
                my %Label = map {
                    ( $_->{option_key} || '' ) => ( $_->{option_value} || $_->{option_key} || '' )
                } @{$Options};
                my @Display = map {
                    $Self->_Escape( exists $Label{$_} ? $Label{$_} : $_ )
                } @{$SelectedValues};
                $ValueHTML = join( '<br>', @Display );
            }
        }
        elsif ( $Type eq 'checkbox' ) {
            $ValueHTML = $Self->_Escape(
                $Self->_Translate(
                    Key      => $RawValue eq '1' ? 'AdminActiveYes' : 'AdminActiveNo',
                    Language => $Language,
                    Fallback => $RawValue eq '1' ? 'Yes' : 'No',
                )
            );
        }
        elsif ( $Type eq 'date' && $RawValue ne '' ) {
            $ValueHTML = $Self->_Escape(
                $Self->_DateTimeDisplay(
                    Value    => $RawValue,
                    Language => $Language,
                )
            );
        }
        elsif ( $RawValue ne '' ) {
            $ValueHTML = $Self->_Escape($RawValue);
        }

        $HTML .= '<div class="qisutu-ticket-info-row">'
            . '<dt>' . $Self->_Escape( $Field->{label} || $Field->{name} || '' ) . '</dt>'
            . '<dd>' . $ValueHTML . '</dd>'
            . '</div>';
    }

    return $HTML;
}

sub _AssignmentSave {
    my ( $Self, %Param ) = @_;

    my $Rows   = $Param{Rows} || [];
    my $UserID = $Param{UserID} || 1;

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Assignment transaction could not be started';
        return;
    };

    my $DeleteResult = $Self->{DB}->Do( $Param{DeleteSQL}, $Param{DeleteID} );
    if ( !$DeleteResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldAssignmentSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my %Seen;
    for my $Row ( @{$Rows} ) {
        next if ref $Row ne 'ARRAY' || @{$Row} < 2;
        my ( $FieldID, $QueueID ) = @{$Row};
        next if $Seen{ $FieldID . ':' . $QueueID }++;

        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_queue (
                field_id, queue_id, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?)',
            $FieldID,
            $QueueID,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldAssignmentSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminDynamicFieldAssignmentSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return 1;
}

sub _SelectionConfigurationClean {
    my ( $Self, %Param ) = @_;

    my $FieldType = $Self->_FieldTypeClean( $Param{FieldType} );
    my $IsSelection = $FieldType eq 'dropdown' || $FieldType eq 'multiselect' ? 1 : 0;

    return {
        IsSelection   => 0,
        Options       => [],
        ShowEmptyValue => 1,
        DefaultValue  => '',
    } if !$IsSelection;

    my $RawOptions = ref $Param{Options} eq 'ARRAY' ? $Param{Options} : [];
    my @Options;
    my %Seen;

    for my $RawOption ( @{$RawOptions} ) {
        next if ref $RawOption ne 'HASH';

        my $OptionKey   = $Self->_Trim( $RawOption->{option_key} );
        my $OptionValue = $Self->_Trim( $RawOption->{option_value} );
        my $SortOrder   = $RawOption->{sort_order};

        next if $OptionKey eq '' && $OptionValue eq '';

        if ( !$OptionKey || !$OptionValue || length($OptionKey) > 255 || length($OptionValue) > 255 || $OptionKey =~ m{[\r\n]} ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldOptionInvalid';
            return;
        }

        if ( $Seen{$OptionKey}++ ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldOptionDuplicate';
            return;
        }

        $SortOrder = 1000 if !defined $SortOrder || $SortOrder !~ m{\A\d+\z};

        push @Options, {
            option_key   => $OptionKey,
            option_value => $OptionValue,
            sort_order   => $SortOrder,
        };
    }

    if ( !@Options ) {
        $Self->{LastError} = 'Translate:AdminDynamicFieldOptionRequired';
        return;
    }

    @Options = sort {
        ( $a->{sort_order} || 0 ) <=> ( $b->{sort_order} || 0 )
            || $a->{option_value} cmp $b->{option_value}
            || $a->{option_key} cmp $b->{option_key}
    } @Options;

    my $ShowEmptyValue = $Param{ShowEmptyValue} ? 1 : 0;
    my $DefaultValues  = $Self->_ValueList( $Param{DefaultValues} );
    my %Allowed = map { $_->{option_key} => 1 } @Options;

    if ($ShowEmptyValue) {
        $DefaultValues = [];
    }
    else {
        if ( !@{$DefaultValues} ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldDefaultRequired';
            return;
        }
        if ( $FieldType eq 'dropdown' && @{$DefaultValues} > 1 ) {
            $Self->{LastError} = 'Translate:AdminDynamicFieldDefaultInvalid';
            return;
        }
        for my $DefaultValue ( @{$DefaultValues} ) {
            if ( !$Allowed{$DefaultValue} ) {
                $Self->{LastError} = 'Translate:AdminDynamicFieldDefaultInvalid';
                return;
            }
        }
    }

    return {
        IsSelection    => 1,
        Options        => \@Options,
        ShowEmptyValue => $ShowEmptyValue,
        DefaultValue   => join( "\n", @{$DefaultValues} ),
    };
}

sub _DateTimeInputValue {
    my ( $Self, $Value ) = @_;

    my $Parts = $Self->_DateTimeParts($Value);
    return '' if !$Parts;

    my $Date = sprintf( '%04d-%02d-%02d', $Parts->{Year}, $Parts->{Month}, $Parts->{Day} );
    return $Date . sprintf( 'T%02d:%02d', $Parts->{Hour}, $Parts->{Minute} );
}

sub _DateTimeDisplay {
    my ( $Self, %Param ) = @_;

    my $Value    = $Param{Value};
    my $Language = $Self->_LanguageClean( $Param{Language} || 'en' );
    my $Parts    = $Self->_DateTimeParts($Value);

    return defined $Value ? $Value : '' if !$Parts;

    my $Date = $Language eq 'de'
        ? sprintf( '%02d.%02d.%04d', $Parts->{Day}, $Parts->{Month}, $Parts->{Year} )
        : sprintf( '%04d-%02d-%02d', $Parts->{Year}, $Parts->{Month}, $Parts->{Day} );

    if ( $Parts->{HasTime} ) {
        $Date .= sprintf( ' %02d:%02d', $Parts->{Hour}, $Parts->{Minute} );
    }

    return $Date;
}

sub _DateTimeValueValid {
    my ( $Self, $Value ) = @_;
    return $Self->_DateTimeParts($Value) ? 1 : 0;
}

sub _DateTimeParts {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);
    return if $Value eq '';

    return if $Value !~ m{
        \A
        (\d{4})-(\d{2})-(\d{2})
        (?:[T\x20](\d{2}):(\d{2})(?::(\d{2}))?)?
        \z
    }x;

    my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );
    my $HasTime = defined $Hour ? 1 : 0;

    return if $Month < 1 || $Month > 12;

    my @DaysInMonth = ( 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );
    if ( $Year % 400 == 0 || ( $Year % 4 == 0 && $Year % 100 != 0 ) ) {
        $DaysInMonth[2] = 29;
    }

    return if $Day < 1 || $Day > $DaysInMonth[$Month];

    if ($HasTime) {
        return if $Hour > 23 || $Minute > 59;
        return if defined $Second && $Second > 59;
    }

    return {
        Year     => 0 + $Year,
        Month    => 0 + $Month,
        Day      => 0 + $Day,
        HasTime  => $HasTime,
        Hour     => $HasTime ? 0 + $Hour : 0,
        Minute   => $HasTime ? 0 + $Minute : 0,
        Second   => defined $Second ? 0 + $Second : 0,
    };
}

sub _ValueList {
    my ( $Self, $RawValue ) = @_;

    my @Raw = ref $RawValue eq 'ARRAY'
        ? @{$RawValue}
        : split( /\r?\n/, defined $RawValue ? $RawValue : '' );
    my @Value;
    my %Seen;

    for my $Item (@Raw) {
        my $Value = $Self->_Trim($Item);
        next if $Value eq '' || $Seen{$Value}++;
        push @Value, $Value;
    }

    return \@Value;
}

sub _FirstTranslationLabel {
    my ( $Self, %Param ) = @_;

    my $Labels = $Param{Labels} || {};
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $ExistingLabel = $Self->_Trim( $Param{ExistingLabel} );

    return $Self->_Trim( $Labels->{$DefaultLanguage} ) if $Self->_Trim( $Labels->{$DefaultLanguage} );
    return $ExistingLabel if $ExistingLabel;

    for my $Language ( sort keys %{$Labels} ) {
        my $Label = $Self->_Trim( $Labels->{$Language} );
        return $Label if $Label;
    }

    return '';
}

sub _FieldTypeClean {
    my ( $Self, $FieldType ) = @_;

    $FieldType = $Self->_Trim($FieldType) || 'text';
    return $FieldType if $FieldType =~ m{\A(?:text|textarea|email|phone|date|number|dropdown|multiselect|checkbox)\z};
    return 'text';
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    $Language ||= 'en';
    $Language =~ s{[^A-Za-z0-9_-]}{}g;
    return $Language || 'en';
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    my $Key      = $Param{Key} || '';
    my $Language = $Param{Language} || 'en';
    my $Fallback = defined $Param{Fallback} ? $Param{Fallback} : $Key;

    return $Fallback if !$Self->{Output} || !$Key;

    my $Text = $Self->{Output}->Translate(
        Key      => $Key,
        Language => $Language,
    );

    return $Text && $Text ne $Key ? $Text : $Fallback;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
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

1;
