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

package QisutuTicketForm;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);

use QisutuChecklist;
use QisutuDynamicField;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        Output    => $Param{Output},
        Permission => $Param{Permission},
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub FormList {
    my ( $Self, %Param ) = @_;

    my $Language        = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;
    my $Where            = $IncludeInactive ? '' : 'WHERE f.active = 1';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.*,
            q.name AS queue_name,
            q.full_name AS queue_full_name,
            COALESCE(current_translation.title, default_translation.title, f.internal_name) AS title,
            COALESCE(current_translation.description, default_translation.description, "") AS description,
            COALESCE(current_translation.submit_label, default_translation.submit_label, "Submit") AS submit_label,
            COALESCE(current_translation.confirmation_text, default_translation.confirmation_text, "") AS confirmation_text,
            COALESCE(current_translation.consent_text, default_translation.consent_text, "") AS consent_text,
            (SELECT COUNT(*) FROM ticket_form_field ff WHERE ff.form_id = f.id AND ff.active = 1) AS field_count,
            (SELECT COUNT(*) FROM ticket_form_submission fs WHERE fs.form_id = f.id) AS submission_count
         FROM ticket_form f
         INNER JOIN ticket_queue q ON q.id = f.queue_id
         LEFT JOIN ticket_form_translation current_translation
            ON current_translation.form_id = f.id
           AND current_translation.language = ?
         LEFT JOIN ticket_form_translation default_translation
            ON default_translation.form_id = f.id
           AND default_translation.language = ?
         ' . $Where . '
         ORDER BY f.sort_order ASC, f.internal_name ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket forms could not be loaded';
        return [];
    }

    return $Rows;
}

sub FormListForCustomer {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Param{CustomerID} || 0;
    return [] if $CustomerID !~ m{\A\d+\z} || !$CustomerID;

    my $Rows = $Self->FormList(
        Language => $Param{Language},
    );
    return [] if $Self->Error();

    my $Assigned = $Self->{DB}->SelectAll(
        'SELECT form_id
         FROM ticket_form_customer
         WHERE customer_id = ?',
        $CustomerID,
    ) || [];
    my %Assigned = map { ( $_->{form_id} || 0 ) => 1 } @{$Assigned};

    return [ grep {
        ( $_->{form_type} || '' ) eq 'customer'
            && ( $_->{all_customers} || $Assigned{ $_->{id} || 0 } )
    } @{$Rows} ];
}

sub FormGet {
    my ( $Self, %Param ) = @_;

    my $FormID   = $Param{FormID} || 0;
    my $Slug     = $Self->_Trim( $Param{Slug} );
    my $Language = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my ( $Where, @Bind );

    if ( $FormID =~ m{\A\d+\z} && $FormID ) {
        $Where = 'f.id = ?';
        push @Bind, $FormID;
    }
    elsif ( $Slug =~ m{\A[a-z0-9][a-z0-9-]{0,99}\z} ) {
        $Where = 'f.slug = ?';
        push @Bind, $Slug;
    }
    else {
        return;
    }

    my $Form = $Self->{DB}->SelectRow(
        'SELECT
            f.*,
            q.name AS queue_name,
            q.full_name AS queue_full_name,
            COALESCE(current_translation.title, default_translation.title, f.internal_name) AS title,
            COALESCE(current_translation.description, default_translation.description, "") AS description,
            COALESCE(current_translation.submit_label, default_translation.submit_label, "Submit") AS submit_label,
            COALESCE(current_translation.confirmation_text, default_translation.confirmation_text, "") AS confirmation_text,
            COALESCE(current_translation.consent_text, default_translation.consent_text, "") AS consent_text,
            (SELECT COUNT(*) FROM ticket_form_submission fs WHERE fs.form_id = f.id) AS submission_count
         FROM ticket_form f
         INNER JOIN ticket_queue q ON q.id = f.queue_id
         LEFT JOIN ticket_form_translation current_translation
            ON current_translation.form_id = f.id
           AND current_translation.language = ?
         LEFT JOIN ticket_form_translation default_translation
            ON default_translation.form_id = f.id
           AND default_translation.language = ?
         WHERE ' . $Where . '
         LIMIT 1',
        $Language,
        $DefaultLanguage,
        @Bind,
    );

    return $Form;
}

sub FormTranslationList {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    return {} if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT language, title, description, submit_label, confirmation_text, consent_text
         FROM ticket_form_translation
         WHERE form_id = ?
         ORDER BY language ASC',
        $FormID,
    ) || [];

    return { map { ( $_->{language} || '' ) => $_ } @{$Rows} };
}

sub FormCustomerIDList {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    return [] if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT customer_id
         FROM ticket_form_customer
         WHERE form_id = ?
         ORDER BY customer_id ASC',
        $FormID,
    ) || [];

    return [ map { 0 + ( $_->{customer_id} || 0 ) } @{$Rows} ];
}

sub FormCreate {
    my ( $Self, %Param ) = @_;

    my $Data = $Self->_FormDataValidate(%Param);
    return if !$Data;

    my $UserID = $Param{ChangedByUserID} || 1;
    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form transaction could not be started';
        return;
    };

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_form (
            internal_name, form_type, slug, queue_id, all_customers, require_consent,
            allowed_origins, rate_limit_hour, rate_limit_day, rate_limit_total_day,
            active, sort_order, form_version, created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
        @{$Data}{qw(
            InternalName FormType Slug QueueID AllCustomers RequireConsent
            AllowedOrigins RateLimitHour RateLimitDay RateLimitTotalDay Active SortOrder
        )},
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $FormID = $Self->{DB}->LastInsertID('ticket_form');
    if ( !$FormID
        || !$Self->_FormTranslationReplace( FormID => $FormID, Translations => $Data->{Translations}, UserID => $UserID )
        || !$Self->_FormCustomerReplace( FormID => $FormID, CustomerIDs => $Data->{CustomerIDs}, UserID => $UserID )
        || !$Self->_CoreFieldsEnsure( FormID => $FormID, FormType => $Data->{FormType}, UserID => $UserID )
    ) {
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return $FormID;
}

sub FormUpdate {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    return if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Current = $Self->FormGet( FormID => $FormID );
    if ( !$Current ) {
        $Self->{LastError} = 'Translate:AdminTicketFormNotFound';
        return;
    }

    my $Data = $Self->_FormDataValidate(%Param);
    return if !$Data;

    # The two form types have intentionally different administration masks and
    # required data. Changing an existing form to the other type would leave
    # incompatible fields and assignments behind, so its type is immutable.
    $Data->{FormType} = $Current->{form_type};
    if ( $Data->{FormType} eq 'public' ) {
        $Data->{AllCustomers} = 0;
        $Data->{CustomerIDs}  = [];
    }
    else {
        $Data->{RequireConsent}    = 0;
        $Data->{AllowedOrigins}    = '*';
        $Data->{RateLimitHour}     = 20;
        $Data->{RateLimitDay}      = 240;
        $Data->{RateLimitTotalDay} = 5000;
    }

    my $UserID = $Param{ChangedByUserID} || 1;
    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form transaction could not be started';
        return;
    };

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_form
         SET internal_name = ?, form_type = ?, slug = ?, queue_id = ?, all_customers = ?,
             require_consent = ?, allowed_origins = ?, rate_limit_hour = ?, rate_limit_day = ?,
             rate_limit_total_day = ?, active = ?, sort_order = ?,
             form_version = form_version + 1, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        @{$Data}{qw(
            InternalName FormType Slug QueueID AllCustomers RequireConsent
            AllowedOrigins RateLimitHour RateLimitDay RateLimitTotalDay Active SortOrder
        )},
        $UserID,
        $FormID,
    );

    if ( !$Result
        || !$Self->_FormTranslationReplace( FormID => $FormID, Translations => $Data->{Translations}, UserID => $UserID )
        || !$Self->_FormCustomerReplace( FormID => $FormID, CustomerIDs => $Data->{CustomerIDs}, UserID => $UserID )
        || !$Self->_CoreFieldsEnsure( FormID => $FormID, FormType => $Data->{FormType}, UserID => $UserID )
    ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Translate:AdminTicketFormUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return 1;
}

sub FormSetActive {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    return if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_form
         SET active = ?, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Param{Active} ? 1 : 0,
        $Param{ChangedByUserID} || 1,
        $FormID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormUpdateFailed';
        return;
    }
    return 1;
}

sub FormDelete {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    return if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Form = $Self->FormGet( FormID => $FormID );
    if ( !$Form ) {
        $Self->{LastError} = 'Translate:AdminTicketFormNotFound';
        return;
    }
    if ( $Form->{active} ) {
        $Self->{LastError} = 'Translate:AdminTicketFormDeleteInactiveRequired';
        return;
    }
    if ( $Form->{submission_count} ) {
        $Self->{LastError} = 'Translate:AdminTicketFormDeleteHasSubmissions';
        return;
    }

    my $DynamicFields = $Self->{DB}->SelectAll(
        'SELECT dynamic_field_id FROM ticket_form_field WHERE form_id = ? AND dynamic_field_id IS NOT NULL',
        $FormID,
    );
    if ( !$DynamicFields ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormDeleteFailed';
        return;
    }
    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormDeleteFailed';
        return;
    }
    for my $DynamicField ( @{$DynamicFields} ) {
        my $Disabled = $Self->{DB}->Do(
            'UPDATE ticket_dynamic_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $Param{ChangedByUserID} || 1,
            $DynamicField->{dynamic_field_id},
        );
        if ( !$Disabled ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormDeleteFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }
    my $Result = $Self->{DB}->Do('DELETE FROM ticket_form WHERE id = ?', $FormID);
    if ( !$Result || !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormDeleteFailed';
        $Self->{DB}->Rollback();
        return;
    }
    return 1;
}

sub FieldList {
    my ( $Self, %Param ) = @_;

    my $FormID          = $Param{FormID} || 0;
    my $Language        = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;
    return [] if $FormID !~ m{\A\d+\z} || !$FormID;

    my $Where = $IncludeInactive ? '' : 'AND ff.active = 1';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ff.*,
            COALESCE(current_translation.label, default_translation.label, ff.field_key) AS label,
            COALESCE(current_translation.help_text, default_translation.help_text, "") AS help_text,
            COALESCE(current_translation.placeholder, default_translation.placeholder, "") AS placeholder
         FROM ticket_form_field ff
         LEFT JOIN ticket_form_field_translation current_translation
            ON current_translation.form_field_id = ff.id
           AND current_translation.language = ?
         LEFT JOIN ticket_form_field_translation default_translation
            ON default_translation.form_field_id = ff.id
           AND default_translation.language = ?
         WHERE ff.form_id = ?
         ' . $Where . '
         ORDER BY ff.sort_order ASC, ff.id ASC',
        $Language,
        $DefaultLanguage,
        $FormID,
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form fields could not be loaded';
        return [];
    }
    return $Rows;
}

sub FieldGet {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    return $Self->{DB}->SelectRow(
        'SELECT * FROM ticket_form_field WHERE id = ? LIMIT 1',
        $FieldID,
    );
}

sub FieldTranslationList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    return {} if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT language, label, help_text, placeholder
         FROM ticket_form_field_translation
         WHERE form_field_id = ?
         ORDER BY language ASC',
        $FieldID,
    ) || [];
    return { map { ( $_->{language} || '' ) => $_ } @{$Rows} };
}

sub FieldCreate {
    my ( $Self, %Param ) = @_;

    my $FormID = $Param{FormID} || 0;
    my $Form = $Self->FormGet( FormID => $FormID );
    if ( !$Form ) {
        $Self->{LastError} = 'Translate:AdminTicketFormNotFound';
        return;
    }

    my $Data = $Self->_FieldDataValidate(%Param);
    return if !$Data;

    my $UserID = $Param{ChangedByUserID} || 1;
    my $Suffix = substr sha256_hex( join ':', $FormID, $Data->{FieldKey}, time, rand() ), 0, 12;
    my $DynamicName = 'Form' . $FormID . '_' . $Suffix;
    my %LabelByLanguage = map {
        $_ => $Data->{Translations}->{$_}->{label}
    } grep {
        $Data->{Translations}->{$_}->{label}
    } keys %{ $Data->{Translations} };

    my $Dynamic = QisutuDynamicField->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );
    my $DynamicFieldID = $Dynamic->FieldCreate(
        Name            => $DynamicName,
        LabelByLanguage => \%LabelByLanguage,
        FieldType       => $Data->{FieldType},
        IsRequired      => 0,
        SortOrder       => $Data->{SortOrder},
        Options         => $Data->{Options},
        ShowEmptyValue  => 1,
        DefaultValues   => [],
        ChangedByUserID => $UserID,
    );
    if ( !$DynamicFieldID ) {
        $Self->{LastError} = $Dynamic->Error() || 'Translate:AdminTicketFormFieldCreateFailed';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_form_field (
            form_id, field_key, field_type, dynamic_field_id, is_required, default_value,
            active, sort_order, created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
        $FormID,
        $Data->{FieldKey},
        $Data->{FieldType},
        $DynamicFieldID,
        $Data->{IsRequired},
        $Data->{DefaultValue},
        $Data->{SortOrder},
        $UserID,
        $UserID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormFieldCreateFailed';
        $Self->{DB}->Do(
            'UPDATE ticket_dynamic_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $UserID, $DynamicFieldID,
        );
        return;
    }

    my $FieldID = $Self->{DB}->LastInsertID('ticket_form_field');
    if ( !$Self->_FieldTranslationReplace(
        FieldID     => $FieldID,
        Translations => $Data->{Translations},
        UserID      => $UserID,
    ) ) {
        $Self->{DB}->Do(
            'UPDATE ticket_form_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $UserID, $FieldID,
        );
        $Self->{DB}->Do(
            'UPDATE ticket_dynamic_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $UserID, $DynamicFieldID,
        );
        return;
    }

    $Self->_FormVersionIncrement( FormID => $FormID, UserID => $UserID );
    return $FieldID;
}

sub FieldUpdate {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $Field = $Self->FieldGet( FieldID => $FieldID );
    if ( !$Field ) {
        $Self->{LastError} = 'Translate:AdminTicketFormFieldNotFound';
        return;
    }
    my $Form = $Self->FormGet( FormID => $Field->{form_id} );
    return if !$Form;

    my $Data = $Self->_FieldDataValidate( %Param, ExistingField => $Field );
    return if !$Data;

    my $IsProtectedPublicIdentity = ( $Form->{form_type} || '' ) eq 'public'
        && ( ( $Field->{field_key} || '' ) eq 'name' || ( $Field->{field_key} || '' ) eq 'email' );
    $Data->{IsRequired} = 1 if $IsProtectedPublicIdentity;
    $Data->{Active}     = 1 if $IsProtectedPublicIdentity;
    my $UserID = $Param{ChangedByUserID} || 1;

    if ( $Field->{dynamic_field_id} ) {
        my %LabelByLanguage = map {
            $_ => $Data->{Translations}->{$_}->{label}
        } grep {
            $Data->{Translations}->{$_}->{label}
        } keys %{ $Data->{Translations} };
        my $Dynamic = QisutuDynamicField->new(
            Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output},
        );
        if ( !$Dynamic->FieldUpdate(
            FieldID         => $Field->{dynamic_field_id},
            LabelByLanguage => \%LabelByLanguage,
            FieldType       => $Data->{FieldType},
            IsRequired      => 0,
            Active          => $Data->{Active},
            SortOrder       => $Data->{SortOrder},
            Options         => $Data->{Options},
            ShowEmptyValue  => 1,
            DefaultValues   => [],
            ChangedByUserID => $UserID,
        ) ) {
            $Self->{LastError} = $Dynamic->Error() || 'Translate:AdminTicketFormFieldUpdateFailed';
            return;
        }
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_form_field
         SET field_type = ?, is_required = ?, default_value = ?, active = ?, sort_order = ?,
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Data->{FieldType},
        $Data->{IsRequired},
        $Data->{DefaultValue},
        $Data->{Active},
        $Data->{SortOrder},
        $UserID,
        $FieldID,
    );
    if ( !$Result || !$Self->_FieldTranslationReplace(
        FieldID      => $FieldID,
        Translations => $Data->{Translations},
        UserID       => $UserID,
    ) ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Translate:AdminTicketFormFieldUpdateFailed';
        return;
    }

    $Self->_FormVersionIncrement( FormID => $Field->{form_id}, UserID => $UserID );
    return 1;
}

sub FieldDeactivate {
    my ( $Self, %Param ) = @_;

    my $Field = $Self->FieldGet( FieldID => $Param{FieldID} );
    return if !$Field;
    my $Form = $Self->FormGet( FormID => $Field->{form_id} );
    return if !$Form;
    if ( ( $Form->{form_type} || '' ) eq 'public'
        && ( ( $Field->{field_key} || '' ) eq 'name' || ( $Field->{field_key} || '' ) eq 'email' )
    ) {
        $Self->{LastError} = 'Translate:AdminTicketFormIdentityFieldRequired';
        return;
    }

    my $UserID = $Param{ChangedByUserID} || 1;
    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_form_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $UserID, $Field->{id},
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketFormFieldUpdateFailed';
        return;
    }
    if ( $Field->{dynamic_field_id} ) {
        $Self->{DB}->Do(
            'UPDATE ticket_dynamic_field SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $UserID, $Field->{dynamic_field_id},
        );
    }
    $Self->_FormVersionIncrement( FormID => $Field->{form_id}, UserID => $UserID );
    return 1;
}

sub FieldsHTML {
    my ( $Self, %Param ) = @_;

    my $Form     = $Param{Form} || {};
    my $Request  = $Param{Request} || {};
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Fields   = $Self->FieldList( FormID => $Form->{id}, Language => $Language );
    return '' if $Self->Error();

    my $HTML = '<div class="qisutu-ticket-form-fields">';
    for my $Field ( @{$Fields} ) {
        next if ( $Form->{form_type} || '' ) eq 'customer'
            && ( ( $Field->{field_key} || '' ) eq 'name' || ( $Field->{field_key} || '' ) eq 'email' );

        my $Name = 'FormField_' . ( $Field->{id} || 0 );
        my $ID   = 'qisutu-ticket-form-field-' . ( $Field->{id} || 0 );
        my $Type = $Field->{field_type} || 'text';
        my $Raw  = exists $Request->{$Name} ? $Request->{$Name} : ( $Field->{default_value} || '' );
        my $Required = $Field->{is_required} ? ' required' : '';
        my $Marker   = $Field->{is_required} ? ' *' : '';
        my $Wide     = $Type eq 'textarea' || $Type eq 'body' || $Type eq 'multiselect' ? ' qisutu-ticket-form-field-wide' : '';
        my $Placeholder = $Field->{placeholder} ? ' placeholder="' . $Self->_Escape( $Field->{placeholder} ) . '"' : '';

        $HTML .= '<div class="qisutu-form-field' . $Wide . '">';
        if ( $Type ne 'checkbox' ) {
            $HTML .= '<label for="' . $ID . '">' . $Self->_Escape( $Field->{label} ) . $Marker . '</label>';
        }

        if ( $Type eq 'textarea' || $Type eq 'body' ) {
            $HTML .= '<textarea id="' . $ID . '" name="' . $Name . '" rows="'
                . ( $Type eq 'body' ? '8' : '4' ) . '"' . $Placeholder . $Required . '>'
                . $Self->_Escape( ref $Raw ? '' : $Raw ) . '</textarea>';
        }
        elsif ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my @Selected = ref $Raw eq 'ARRAY' ? @{$Raw} : grep { $_ ne '' } split /\r?\n/, ( defined $Raw ? $Raw : '' );
            my %Selected = map { $_ => 1 } @Selected;
            my $Options = $Self->_FieldOptionList($Field);
            my $Multiple = $Type eq 'multiselect' ? ' multiple size="5"' : '';
            $HTML .= '<select id="' . $ID . '" name="' . $Name . '"' . $Multiple . $Required . '>';
            if ( $Type eq 'dropdown' ) {
                $HTML .= '<option value="">-</option>';
            }
            for my $Option ( @{$Options} ) {
                my $Key = $Option->{option_key} || '';
                $HTML .= '<option value="' . $Self->_Escape($Key) . '"'
                    . ( $Selected{$Key} ? ' selected' : '' ) . '>'
                    . $Self->_Escape( $Option->{option_value} || $Key ) . '</option>';
            }
            $HTML .= '</select>';
        }
        elsif ( $Type eq 'checkbox' ) {
            my $Checked = defined $Raw && !ref $Raw && $Raw eq '1' ? ' checked' : '';
            $HTML .= '<label class="qisutu-form-checkbox" for="' . $ID . '">'
                . '<input id="' . $ID . '" type="checkbox" name="' . $Name . '" value="1"'
                . $Checked . $Required . '><span>' . $Self->_Escape( $Field->{label} ) . $Marker . '</span></label>';
        }
        else {
            my $InputType = $Type eq 'email' ? 'email'
                : $Type eq 'phone' ? 'tel'
                : $Type eq 'number' ? 'number'
                : $Type eq 'date' ? 'datetime-local'
                : 'text';
            my $MaxLength = $Type eq 'title' ? ' maxlength="500"'
                : $Type eq 'name' || $Type eq 'email' ? ' maxlength="255"'
                : ' maxlength="2000"';
            $HTML .= '<input id="' . $ID . '" type="' . $InputType . '" name="' . $Name . '" value="'
                . $Self->_Escape( ref $Raw ? '' : $Raw ) . '"' . $Placeholder . $MaxLength
                . ( $Type eq 'number' ? ' step="any"' : '' ) . $Required . '>';
        }

        if ( $Field->{help_text} ) {
            $HTML .= '<span class="qisutu-form-hint">' . $Self->_Escape( $Field->{help_text} ) . '</span>';
        }
        $HTML .= '</div>';
    }

    if ( $Form->{require_consent} ) {
        $HTML .= '<div class="qisutu-form-field qisutu-ticket-form-field-wide">'
            . '<label class="qisutu-form-checkbox"><input type="checkbox" name="FormConsent" value="1" required'
            . ( $Request->{FormConsent} ? ' checked' : '' ) . '><span>'
            . $Self->_Escape( $Form->{consent_text} || $Self->_T( 'TicketFormConsentFallback', $Language, 'I agree.' ) )
            . ' *</span></label></div>';
    }

    $HTML .= '</div>';
    return $HTML;
}

sub SubmissionCreate {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $Context  = $Param{Context} || '';
    my $User     = $Param{User} || {};
    my $Request  = $Param{Request} || {};
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Form = $Self->FormGet( FormID => $Param{FormID}, Language => $Language );
    if ( !$Form || !$Form->{active} ) {
        $Self->{LastError} = 'Translate:TicketFormUnavailable';
        return;
    }

    if ( $Context eq 'customer' && ( $Form->{form_type} || '' ) ne 'customer' ) {
        $Self->{LastError} = 'Translate:TicketFormUnavailable';
        return;
    }
    if ( $Context eq 'public' && ( $Form->{form_type} || '' ) ne 'public' ) {
        $Self->{LastError} = 'Translate:TicketFormUnavailable';
        return;
    }

    my $TicketObject = QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $Self->{Permission},
    );
    my ( $CustomerID, $CustomerUserID, $CreatedByUserID, $SubmitterName, $SubmitterEmail );

    if ( $Context eq 'customer' ) {
        $CustomerID      = $User->{customer_id} || 0;
        $CustomerUserID  = $User->{customer_user_id} || 0;
        $CreatedByUserID = $User->{user_account_id} || 0;
        if ( !$CustomerID || !$CustomerUserID || !$CreatedByUserID ) {
            $Self->{LastError} = 'Translate:TicketFormUnavailable';
            return;
        }
        my $AllowedForms = $Self->FormListForCustomer( CustomerID => $CustomerID, Language => $Language );
        my %Allowed = map { ( $_->{id} || 0 ) => 1 } @{$AllowedForms};
        if ( !$Allowed{ $Form->{id} } ) {
            $Self->{LastError} = 'Translate:TicketFormUnavailable';
            return;
        }
        $SubmitterName = join ' ', grep {$_} ( $User->{firstname}, $User->{lastname} );
        $SubmitterName ||= $User->{login} || '';
        $SubmitterEmail = $User->{email} || '';
    }
    elsif ( $Context eq 'public' ) {
        if ( defined $Request->{Website} && $Self->_Trim( $Request->{Website} ) ne '' ) {
            return { SpamIgnored => 1, ConfirmationText => $Form->{confirmation_text} || '' };
        }
        my $StartedAt = $Request->{FormStartedAt} || 0;
        if ( $StartedAt =~ m{\A\d+\z} && time - $StartedAt < 2 ) {
            $Self->{LastError} = 'Translate:PublicTicketFormTooFast';
            return;
        }
        my $Rate = $Self->_RateLimitCheck(
            Form      => $Form,
            IPAddress => $Param{IPAddress},
        );
        return if !$Rate;
    }
    else {
        $Self->{LastError} = 'Translate:TicketFormUnavailable';
        return;
    }

    my $Validated = $Self->_SubmissionValidate(
        Form     => $Form,
        Request  => $Request,
        Language => $Language,
        Context  => $Context,
    );
    return if !$Validated;

    $SubmitterName  = $Validated->{Core}->{name}  if $Context eq 'public';
    $SubmitterEmail = $Validated->{Core}->{email} if $Context eq 'public';

    my $Title = $Validated->{Core}->{title} || $Form->{title} || $Form->{internal_name};
    my $Body  = $Validated->{Core}->{body} || $Self->_SubmissionBodyFallback(
        Form   => $Form,
        Values => $Validated->{Values},
    );
    $Title = substr $Title, 0, 500 if length $Title > 500;

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT id FROM ticket_queue WHERE id = ? AND active = 1 LIMIT 1',
        $Form->{queue_id},
    );
    if ( !$Queue ) {
        $Self->{LastError} = 'Translate:TicketFormQueueUnavailable';
        return;
    }

    my $StateID = $TicketObject->_DefaultStateID();
    my $PriorityID = $TicketObject->_DefaultPriorityID();
    my $TicketNumber = $TicketObject->_TicketNumberCreate();
    if ( !$StateID || !$PriorityID || !$TicketNumber ) {
        $Self->{LastError} = $TicketObject->Error() || 'Translate:TicketCreateFailed';
        return;
    }

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        return;
    };

    if ( $Context eq 'public' ) {
        my $Contact = $Self->_PublicContactResolve(
            Name  => $SubmitterName,
            Email => $SubmitterEmail,
        );
        if ( !$Contact ) {
            $Self->{DB}->Rollback();
            return;
        }
        $CustomerID      = $Contact->{customer_id};
        $CustomerUserID  = $Contact->{customer_user_id};
        $CreatedByUserID = $Contact->{user_account_id};
    }

    my $TicketResult = $Self->{DB}->Do(
        'INSERT INTO ticket (
            ticket_number, title, queue_id, state_id, priority_id,
            customer_id, customer_user_id, owner_user_id, responsible_user_id,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, NOW(), NOW())',
        $TicketNumber,
        $Title,
        $Form->{queue_id},
        $StateID,
        $PriorityID,
        $CustomerID,
        $CustomerUserID,
        $CreatedByUserID,
        $CreatedByUserID,
    );
    if ( !$TicketResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $TicketID = $Self->{DB}->LastInsertID('ticket');
    my $Checklist = QisutuChecklist->new( Config => $Self->{Config}, DB => $Self->{DB} );
    if ( !$TicketID || !$Checklist->TicketAutoCreate( TicketID => $TicketID, ChangedByUserID => $CreatedByUserID ) ) {
        $Self->{LastError} = $Checklist->Error() || 'Translate:TicketCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my ( $ToName, $ToEmail ) = $TicketObject->_QueueAddress( QueueID => $Form->{queue_id} );
    my $ArticleID = $TicketObject->ArticleCreate(
        TicketID        => $TicketID,
        User            => $User,
        Subject         => $Title,
        Body            => $Body,
        Channel         => 'web',
        SenderType      => 'customer',
        FromName        => $SubmitterName,
        FromEmail       => $SubmitterEmail,
        ToName          => $ToName,
        ToEmail         => $ToEmail,
        ContentType     => 'text/plain',
        Visibility      => 'both',
        SkipTicketAccessCheck => 1,
        SkipNotification      => 1,
        CreatedByUserID => $CreatedByUserID,
        ChangedByUserID => $CreatedByUserID,
    );
    if ( !$ArticleID ) {
        $Self->{LastError} = $TicketObject->Error() || 'Translate:TicketCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    for my $Value ( @{ $Validated->{Values} } ) {
        next if !$Value->{dynamic_field_id};
        my $Saved = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_value (
                ticket_id, field_id, value_text, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE value_text = VALUES(value_text),
                changed_by_user_id = VALUES(changed_by_user_id), changed_at = NOW()',
            $TicketID,
            $Value->{dynamic_field_id},
            $Value->{raw_value},
            $CreatedByUserID,
            $CreatedByUserID,
        );
        if ( !$Saved ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketDynamicFieldSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    my $IPHash = $Context eq 'public' ? $Self->_IPAddressHash( $Param{IPAddress} ) : undef;
    my $SubmissionResult = $Self->{DB}->Do(
        'INSERT INTO ticket_form_submission (
            ticket_id, form_id, form_name_snapshot, form_title_snapshot, form_version,
            source, submitter_name, submitter_email, remote_ip_hash, user_agent, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
        $TicketID,
        $Form->{id},
        $Form->{internal_name},
        $Form->{title},
        $Form->{form_version} || 1,
        $Context eq 'public' ? 'webform' : 'customer_portal',
        $SubmitterName,
        $SubmitterEmail,
        $IPHash,
        substr( $Param{UserAgent} || '', 0, 255 ),
    );
    if ( !$SubmissionResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketFormSubmissionSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $SubmissionID = $Self->{DB}->LastInsertID('ticket_form_submission');
    for my $Value ( @{ $Validated->{Values} } ) {
        my $Saved = $Self->{DB}->Do(
            'INSERT INTO ticket_form_submission_value (
                submission_id, form_field_id, dynamic_field_id, field_key, label_snapshot,
                field_type_snapshot, value_text, display_value_text, sort_order, created_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
            $SubmissionID,
            $Value->{form_field_id},
            $Value->{dynamic_field_id},
            $Value->{field_key},
            $Value->{label},
            $Value->{field_type},
            $Value->{raw_value},
            $Value->{display_value},
            $Value->{sort_order},
        );
        if ( !$Saved ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketFormSubmissionSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    $TicketObject->_AgentNotificationSend(
        NotificationType => 'ticket_new_in_my_queues',
        TicketID         => $TicketID,
        ChangedByUserID  => $CreatedByUserID,
    );

    $TicketObject->_CustomerAutoResponseSend(
        ResponseType   => 'customer_ticket_created',
        TicketID       => $TicketID,
        ArticleID      => $ArticleID,
        RecipientName  => $SubmitterName,
        RecipientEmail => $SubmitterEmail,
    );

    return {
        TicketID         => $TicketID,
        TicketNumber     => $TicketNumber,
        ConfirmationText => $Form->{confirmation_text} || '',
    };
}

sub SubmissionDisplayHTML {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    return '' if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Submission = $Self->{DB}->SelectRow(
        'SELECT id, form_name_snapshot, form_title_snapshot, form_version, source,
                submitter_name, submitter_email, created_at
         FROM ticket_form_submission
         WHERE ticket_id = ?
         LIMIT 1',
        $TicketID,
    );
    return '' if !$Submission;

    my $Values = $Self->{DB}->SelectAll(
        'SELECT label_snapshot, display_value_text, field_type_snapshot
         FROM ticket_form_submission_value
         WHERE submission_id = ?
         ORDER BY sort_order ASC, id ASC',
        $Submission->{id},
    ) || [];

    my $Language = $Param{Language} || 'en';
    my $SourceLabel = ( $Submission->{source} || '' ) eq 'webform'
        ? $Self->_T( 'TicketFormSourceWeb', $Language, 'Web form' )
        : $Self->_T( 'TicketFormSourceCustomer', $Language, 'Customer portal' );
    my $HTML = $Self->_InfoRow(
        Label => $Self->_T( 'TicketFormName', $Language, 'Form' ),
        Value => $Submission->{form_title_snapshot} || $Submission->{form_name_snapshot},
    );
    $HTML .= $Self->_InfoRow(
        Label => $Self->_T( 'TicketFormSource', $Language, 'Source' ),
        Value => $SourceLabel,
    );
    $HTML .= $Self->_InfoRow(
        Label => $Self->_T( 'TicketFormSubmittedAt', $Language, 'Submitted at' ),
        Value => $Submission->{created_at} || '-',
    );

    for my $Value ( @{$Values} ) {
        my $Display = defined $Value->{display_value_text} && $Value->{display_value_text} ne ''
            ? $Value->{display_value_text}
            : '-';
        $HTML .= $Self->_InfoRow(
            Label => $Value->{label_snapshot} || '-',
            Value => $Display,
        );
    }

    return $HTML;
}

sub PublicFrameAncestors {
    my ( $Self, %Param ) = @_;

    my $Raw = $Param{AllowedOrigins} || '';
    my @Origin;
    for my $Line ( split /[\r\n,]+/, $Raw ) {
        $Line = $Self->_Trim($Line);
        next if !$Line;
        return '*' if $Line eq '*';
        next if $Line !~ m{\Ahttps?://[A-Za-z0-9.-]+(?::\d+)?\z};
        push @Origin, $Line;
    }
    return @Origin ? join( ' ', @Origin ) : "'self'";
}

sub _SubmissionValidate {
    my ( $Self, %Param ) = @_;

    my $Form     = $Param{Form} || {};
    my $Request  = $Param{Request} || {};
    my $Language = $Param{Language} || 'en';
    my $Context  = $Param{Context} || '';
    my $Fields   = $Self->FieldList( FormID => $Form->{id}, Language => $Language );
    return if $Self->Error();

    if ( $Form->{require_consent} && ( $Request->{FormConsent} || '' ) ne '1' ) {
        $Self->{LastError} = 'Translate:TicketFormConsentRequired';
        return;
    }

    my %Core;
    my @Values;
    for my $Field ( @{$Fields} ) {
        next if $Context eq 'customer'
            && ( ( $Field->{field_key} || '' ) eq 'name' || ( $Field->{field_key} || '' ) eq 'email' );

        my $Key  = 'FormField_' . ( $Field->{id} || 0 );
        my $Type = $Field->{field_type} || 'text';
        my ( $RawValue, $DisplayValue );

        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my @Raw = ref $Request->{$Key} eq 'ARRAY'
                ? @{ $Request->{$Key} }
                : split /\r?\n/, ( defined $Request->{$Key} ? $Request->{$Key} : '' );
            my @Selected;
            my %Seen;
            for my $Item (@Raw) {
                $Item = $Self->_Trim($Item);
                next if !$Item || $Seen{$Item}++;
                push @Selected, $Item;
            }
            if ( $Type eq 'dropdown' && @Selected > 1 ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormFieldInvalid', Field => $Field, Language => $Language );
                return;
            }
            my $Options = $Self->_FieldOptionList($Field);
            my %Label = map { ( $_->{option_key} || '' ) => ( $_->{option_value} || $_->{option_key} || '' ) } @{$Options};
            for my $Selected (@Selected) {
                if ( !exists $Label{$Selected} ) {
                    $Self->_SubmissionFieldError( Key => 'TicketFormFieldInvalid', Field => $Field, Language => $Language );
                    return;
                }
            }
            if ( $Field->{is_required} && !@Selected ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormRequiredFields', Field => $Field, Language => $Language );
                return;
            }
            $RawValue = join "\n", @Selected;
            $DisplayValue = join "\n", map { $Label{$_} } @Selected;
        }
        elsif ( $Type eq 'checkbox' ) {
            $RawValue = ( $Request->{$Key} || '' ) eq '1' ? '1' : '0';
            if ( $Field->{is_required} && $RawValue ne '1' ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormRequiredFields', Field => $Field, Language => $Language );
                return;
            }
            $DisplayValue = $Self->_T(
                $RawValue eq '1' ? 'AdminActiveYes' : 'AdminActiveNo',
                $Language,
                $RawValue eq '1' ? 'Yes' : 'No',
            );
        }
        else {
            $RawValue = $Self->_Trim( $Request->{$Key} );
            my $Required = $Field->{is_required} ? 1 : 0;
            $Required = 1 if $Context eq 'public'
                && ( ( $Field->{field_key} || '' ) eq 'name' || ( $Field->{field_key} || '' ) eq 'email' );
            if ( $Required && $RawValue eq '' ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormRequiredFields', Field => $Field, Language => $Language );
                return;
            }
            my $MaxLength = $Type eq 'body' || $Type eq 'textarea' ? 50000
                : $Type eq 'title' ? 500
                : $Type eq 'name' || $Type eq 'email' ? 255
                : 2000;
            if ( length $RawValue > $MaxLength ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormFieldTooLong', Field => $Field, Language => $Language );
                return;
            }
            if ( $Type eq 'email' && $RawValue ne '' && $RawValue !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} ) {
                $Self->{LastError} = 'Translate:TicketFormEmailInvalid';
                return;
            }
            if ( $Type eq 'number' && $RawValue ne '' && $RawValue !~ m{\A[-+]?(?:\d+(?:[\.,]\d+)?|[\.,]\d+)\z} ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormFieldInvalid', Field => $Field, Language => $Language );
                return;
            }
            if ( $Type eq 'date' && $RawValue ne '' && $RawValue !~ m{\A\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2})?\z} ) {
                $Self->_SubmissionFieldError( Key => 'TicketFormFieldInvalid', Field => $Field, Language => $Language );
                return;
            }
            $DisplayValue = $RawValue;
        }

        $Core{ $Field->{field_key} } = $RawValue
            if ( $Field->{field_key} || '' ) =~ m{\A(?:title|body|name|email)\z};
        push @Values, {
            form_field_id   => $Field->{id},
            dynamic_field_id => $Field->{dynamic_field_id},
            field_key       => $Field->{field_key},
            label           => $Field->{label},
            field_type      => $Field->{field_type},
            raw_value       => $RawValue,
            display_value   => $DisplayValue,
            sort_order      => $Field->{sort_order},
        };
    }

    if ( $Context eq 'public' && ( !$Core{name} || !$Core{email} ) ) {
        $Self->{LastError} = 'Translate:TicketFormRequiredFields';
        return;
    }
    return { Core => \%Core, Values => \@Values };
}

sub _RateLimitCheck {
    my ( $Self, %Param ) = @_;

    my $Form = $Param{Form} || {};
    my $IPHash = $Self->_IPAddressHash( $Param{IPAddress} );
    return 1 if !$IPHash;

    my @Check = (
        [ $Form->{rate_limit_hour} || 20,
          'SELECT COUNT(*) AS count_value FROM ticket_form_submission WHERE form_id = ? AND remote_ip_hash = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)',
          $Form->{id}, $IPHash ],
        [ $Form->{rate_limit_day} || 240,
          'SELECT COUNT(*) AS count_value FROM ticket_form_submission WHERE form_id = ? AND remote_ip_hash = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)',
          $Form->{id}, $IPHash ],
        [ $Form->{rate_limit_total_day} || 5000,
          'SELECT COUNT(*) AS count_value FROM ticket_form_submission WHERE source = "webform" AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)' ],
    );

    for my $Check (@Check) {
        my ( $Limit, $SQL, @Bind ) = @{$Check};
        next if !$Limit;
        my $Row = $Self->{DB}->SelectRow( $SQL, @Bind );
        if ( !$Row ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PublicTicketFormRateLimited';
            return;
        }
        if ( ( $Row->{count_value} || 0 ) >= $Limit ) {
            $Self->{LastError} = 'Translate:PublicTicketFormRateLimited';
            return;
        }
    }
    return 1;
}

sub _PublicContactResolve {
    my ( $Self, %Param ) = @_;

    my $Email = lc $Self->_Trim( $Param{Email} );
    my $Name  = $Self->_Trim( $Param{Name} );
    my $Existing = $Self->{DB}->SelectRow(
        'SELECT ua.id AS user_account_id, cu.id AS customer_user_id, cu.customer_id
         FROM user_account ua
         INNER JOIN customer_user cu ON cu.user_account_id = ua.id
         INNER JOIN customer c ON c.id = cu.customer_id
         WHERE LOWER(ua.email) = ? AND ua.account_type = "customer"
           AND ua.is_active = 0 AND c.customer_number = "QISUTU-WEBFORM"
         ORDER BY cu.active DESC, cu.id ASC
         LIMIT 1',
        $Email,
    );
    return $Existing if $Existing;

    my $Customer = $Self->{DB}->SelectRow(
        'SELECT id FROM customer WHERE customer_number = ? LIMIT 1',
        'QISUTU-WEBFORM',
    );
    if ( !$Customer ) {
        my $Created = $Self->{DB}->Do(
            'INSERT INTO customer (
                customer_number, name, active, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, 1, 1, 1)',
            'QISUTU-WEBFORM',
            'Web form contacts',
        );
        if ( !$Created ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
            return;
        }
        $Customer = { id => $Self->{DB}->LastInsertID('customer') };
    }

    # Never attach an unauthenticated public submission to an existing portal
    # identity. Otherwise knowing an e-mail address could expose that new
    # ticket in the real customer's portal. In the rare e-mail collision case
    # the submission remains assigned to the web-form customer without a
    # customer user; its validated input snapshot and article keep the address.
    my $ExistingAccount = $Self->{DB}->SelectRow(
        'SELECT id AS user_account_id
         FROM user_account
         WHERE LOWER(email) = ? AND account_type = "customer"
         LIMIT 1',
        $Email,
    );
    if ($ExistingAccount) {
        return {
            customer_id      => $Customer->{id},
            customer_user_id => undef,
            user_account_id  => 1,
        };
    }

    my ( $Firstname, $Lastname ) = split /\s+/, $Name, 2;
    $Firstname ||= $Name || 'Web';
    $Lastname  ||= 'Form';
    my $PasswordHash = 'QISUTU_WEBFORM_CONTACT_' . sha256_hex( join ':', $Email, time, rand() );
    my $Created = $Self->{DB}->Do(
        'INSERT INTO user_account (
            login, account_type, email, password_hash, firstname, lastname,
            is_active, is_system_user, password_changed_at
         ) VALUES (?, "customer", ?, ?, ?, ?, 0, 0, NULL)',
        $Email,
        $Email,
        $PasswordHash,
        $Firstname,
        $Lastname,
    );
    if ( !$Created ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        return;
    }
    my $UserAccountID = $Self->{DB}->LastInsertID('user_account');
    $Created = $Self->{DB}->Do(
        'INSERT INTO customer_user (
            customer_id, user_account_id, active, created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, 1, 1, 1)',
        $Customer->{id},
        $UserAccountID,
    );
    if ( !$Created ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        return;
    }
    return {
        customer_id      => $Customer->{id},
        customer_user_id => $Self->{DB}->LastInsertID('customer_user'),
        user_account_id  => $UserAccountID,
    };
}

sub _FormDataValidate {
    my ( $Self, %Param ) = @_;

    my $InternalName = $Self->_Trim( $Param{InternalName} );
    my $FormType     = $Self->_Trim( $Param{FormType} );
    my $Slug         = lc $Self->_Trim( $Param{Slug} );
    my $QueueID      = $Param{QueueID} || 0;
    my $SortOrder    = $Param{SortOrder} || 1000;
    my $Translations = ref $Param{Translations} eq 'HASH' ? $Param{Translations} : {};
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );

    $Slug =~ s{[^a-z0-9-]+}{-}g;
    $Slug =~ s{\A-+|-+\z}{}g;
    if ( !$InternalName || $FormType !~ m{\A(?:customer|public)\z}
        || !$Slug || length($Slug) > 100 || $QueueID !~ m{\A\d+\z} || !$QueueID
    ) {
        $Self->{LastError} = 'Translate:AdminTicketFormRequired';
        return;
    }
    my $Queue = $Self->{DB}->SelectRow('SELECT id FROM ticket_queue WHERE id = ? LIMIT 1', $QueueID);
    if ( !$Queue ) {
        $Self->{LastError} = 'Translate:TicketFormQueueUnavailable';
        return;
    }
    my $Default = $Translations->{$DefaultLanguage} || {};
    if ( !$Self->_Trim( $Default->{title} ) ) {
        $Self->{LastError} = 'Translate:AdminTicketFormDefaultTranslationRequired';
        return;
    }

    my %CleanTranslations;
    for my $Language ( keys %{$Translations} ) {
        my $Code = $Self->_LanguageClean($Language);
        my $Row  = $Translations->{$Language} || {};
        my $Title = $Self->_Trim( $Row->{title} );
        next if !$Title;
        $CleanTranslations{$Code} = {
            title             => substr( $Title, 0, 255 ),
            description       => substr( $Self->_Trim( $Row->{description} ), 0, 10000 ),
            submit_label      => substr( $Self->_Trim( $Row->{submit_label} ) || $Self->_T( 'TicketFormSubmit', $Code, 'Submit' ), 0, 100 ),
            confirmation_text => substr( $Self->_Trim( $Row->{confirmation_text} ) || $Self->_T( 'TicketFormConfirmationDefault', $Code, 'Thank you. Your request was submitted.' ), 0, 10000 ),
            consent_text      => substr( $Self->_Trim( $Row->{consent_text} ), 0, 10000 ),
        };
    }

    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};
    my $AllowedOrigins = $Self->_AllowedOriginsClean( $Param{AllowedOrigins} );
    return {
        InternalName     => substr( $InternalName, 0, 190 ),
        FormType         => $FormType,
        Slug             => $Slug,
        QueueID          => 0 + $QueueID,
        AllCustomers     => $Param{AllCustomers} ? 1 : 0,
        RequireConsent   => $Param{RequireConsent} ? 1 : 0,
        AllowedOrigins   => $AllowedOrigins,
        RateLimitHour    => $Self->_PositiveLimit( $Param{RateLimitHour}, 20, 10000 ),
        RateLimitDay     => $Self->_PositiveLimit( $Param{RateLimitDay}, 240, 100000 ),
        RateLimitTotalDay => $Self->_PositiveLimit( $Param{RateLimitTotalDay}, 5000, 1000000 ),
        Active           => $Param{Active} ? 1 : 0,
        SortOrder        => 0 + $SortOrder,
        Translations     => \%CleanTranslations,
        CustomerIDs      => ref $Param{CustomerIDs} eq 'ARRAY' ? $Param{CustomerIDs} : [],
    };
}

sub _FieldDataValidate {
    my ( $Self, %Param ) = @_;

    my $Existing = $Param{ExistingField} || {};
    my $FieldType = $Self->_Trim( $Param{FieldType} ) || ( $Existing->{field_type} || 'text' );
    my $FieldKey  = $Existing->{field_key} || lc $Self->_Trim( $Param{FieldKey} );
    my $Translations = ref $Param{Translations} eq 'HASH' ? $Param{Translations} : {};
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );

    if ( $FieldType !~ m{\A(?:text|textarea|email|phone|date|number|dropdown|multiselect|checkbox|title|body|name)\z} ) {
        $Self->{LastError} = 'Translate:AdminTicketFormFieldTypeInvalid';
        return;
    }
    $FieldKey =~ s{[^a-z0-9_]+}{_}g;
    $FieldKey =~ s{\A_+|_+\z}{}g;
    $FieldKey = 'field_' . substr( sha256_hex( join ':', time, rand() ), 0, 10 ) if !$FieldKey;

    my $Default = $Translations->{$DefaultLanguage} || {};
    if ( !$Self->_Trim( $Default->{label} ) ) {
        $Self->{LastError} = 'Translate:AdminTicketFormFieldLabelRequired';
        return;
    }
    my %Clean;
    for my $Language ( keys %{$Translations} ) {
        my $Code = $Self->_LanguageClean($Language);
        my $Row  = $Translations->{$Language} || {};
        my $Label = $Self->_Trim( $Row->{label} );
        next if !$Label;
        $Clean{$Code} = {
            label       => substr( $Label, 0, 255 ),
            help_text   => substr( $Self->_Trim( $Row->{help_text} ), 0, 10000 ),
            placeholder => substr( $Self->_Trim( $Row->{placeholder} ), 0, 255 ),
        };
    }
    my $SortOrder = $Param{SortOrder} || 1000;
    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};
    return {
        FieldKey      => substr( $FieldKey, 0, 100 ),
        FieldType     => $FieldType,
        IsRequired    => $Param{IsRequired} ? 1 : 0,
        DefaultValue  => substr( $Self->_Trim( $Param{DefaultValue} ), 0, 50000 ),
        Active        => exists $Param{Active} ? ( $Param{Active} ? 1 : 0 ) : 1,
        SortOrder     => 0 + $SortOrder,
        Options       => ref $Param{Options} eq 'ARRAY' ? $Param{Options} : [],
        Translations  => \%Clean,
    };
}

sub _FormTranslationReplace {
    my ( $Self, %Param ) = @_;
    my $Deleted = $Self->{DB}->Do('DELETE FROM ticket_form_translation WHERE form_id = ?', $Param{FormID});
    return if !$Deleted;
    for my $Language ( sort keys %{ $Param{Translations} || {} } ) {
        my $Row = $Param{Translations}->{$Language};
        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_form_translation (
                form_id, language, title, description, submit_label, confirmation_text, consent_text,
                created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            $Param{FormID}, $Language, @{$Row}{qw(title description submit_label confirmation_text consent_text)},
            $Param{UserID}, $Param{UserID},
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form translations could not be saved';
            return;
        }
    }
    return 1;
}

sub _FieldTranslationReplace {
    my ( $Self, %Param ) = @_;
    my $Deleted = $Self->{DB}->Do('DELETE FROM ticket_form_field_translation WHERE form_field_id = ?', $Param{FieldID});
    return if !$Deleted;
    for my $Language ( sort keys %{ $Param{Translations} || {} } ) {
        my $Row = $Param{Translations}->{$Language};
        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_form_field_translation (
                form_field_id, language, label, help_text, placeholder,
                created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?, ?, ?)',
            $Param{FieldID}, $Language, @{$Row}{qw(label help_text placeholder)},
            $Param{UserID}, $Param{UserID},
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form field translations could not be saved';
            return;
        }
    }
    return 1;
}

sub _FormCustomerReplace {
    my ( $Self, %Param ) = @_;
    my $Deleted = $Self->{DB}->Do('DELETE FROM ticket_form_customer WHERE form_id = ?', $Param{FormID});
    return if !$Deleted;
    my %Seen;
    for my $CustomerID ( @{ $Param{CustomerIDs} || [] } ) {
        next if !defined $CustomerID || $CustomerID !~ m{\A\d+\z} || !$CustomerID || $Seen{$CustomerID}++;
        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_form_customer (form_id, customer_id, created_by_user_id) VALUES (?, ?, ?)',
            $Param{FormID}, $CustomerID, $Param{UserID},
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Ticket form customer assignments could not be saved';
            return;
        }
    }
    return 1;
}

sub _CoreFieldsEnsure {
    my ( $Self, %Param ) = @_;

    my @Core = (
        [ title => 'title', 1, 100, 'TicketArticleSubject', 'Subject' ],
        [ body  => 'body',  1, 200, 'TicketArticleBody', 'Message' ],
    );
    if ( ( $Param{FormType} || '' ) eq 'public' ) {
        unshift @Core,
            [ name  => 'name',  1, 10, 'PublicTicketFormName', 'Name' ],
            [ email => 'email', 1, 20, 'PublicTicketFormEmail', 'Email' ];
    }

    for my $Core (@Core) {
        my ( $Key, $Type, $Required, $Sort, $TranslationKey, $Fallback ) = @{$Core};
        my $Existing = $Self->{DB}->SelectRow(
            'SELECT id FROM ticket_form_field WHERE form_id = ? AND field_key = ? LIMIT 1',
            $Param{FormID}, $Key,
        );
        if ($Existing) {
            # Name and e-mail are mandatory security/identity fields for public forms.
            # Subject and message stay configurable after their initial creation.
            if ( ( $Param{FormType} || '' ) eq 'public' && ( $Key eq 'name' || $Key eq 'email' ) ) {
                my $Result = $Self->{DB}->Do(
                    'UPDATE ticket_form_field SET field_type = ?, is_required = 1, active = 1,
                        changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
                    $Type, $Param{UserID}, $Existing->{id},
                );
                return if !$Result;
            }
            next;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_form_field (
                form_id, field_key, field_type, dynamic_field_id, is_required, default_value,
                active, sort_order, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, NULL, ?, "", 1, ?, ?, ?)',
            $Param{FormID}, $Key, $Type, $Required, $Sort, $Param{UserID}, $Param{UserID},
        );
        return if !$Result;
        my $FieldID = $Self->{DB}->LastInsertID('ticket_form_field');
        for my $Language ( @{ $Self->_LanguageList() } ) {
            my $Label = $Self->_T( $TranslationKey, $Language, $Fallback );
            $Result = $Self->{DB}->Do(
                'INSERT INTO ticket_form_field_translation (
                    form_field_id, language, label, help_text, placeholder,
                    created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, ?, "", "", ?, ?)',
                $FieldID, $Language, $Label, $Param{UserID}, $Param{UserID},
            );
            return if !$Result;
        }
    }
    return 1;
}

sub _FieldOptionList {
    my ( $Self, $Field ) = @_;
    return [] if !$Field->{dynamic_field_id};
    my $Dynamic = QisutuDynamicField->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    return $Dynamic->OptionList( FieldID => $Field->{dynamic_field_id} ) || [];
}

sub _FormVersionIncrement {
    my ( $Self, %Param ) = @_;
    return $Self->{DB}->Do(
        'UPDATE ticket_form SET form_version = form_version + 1, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $Param{UserID} || 1, $Param{FormID},
    );
}

sub _SubmissionBodyFallback {
    my ( $Self, %Param ) = @_;
    my @Line;
    for my $Value ( @{ $Param{Values} || [] } ) {
        next if ( $Value->{field_key} || '' ) =~ m{\A(?:title|body)\z};
        next if !defined $Value->{display_value} || $Value->{display_value} eq '';
        my $Display = $Value->{display_value};
        $Display =~ s{\r?\n}{, }g;
        push @Line, ( $Value->{label} || $Value->{field_key} ) . ': ' . $Display;
    }
    return join( "\n", @Line ) || ( $Param{Form}->{description} || $Param{Form}->{title} || 'Form submission' );
}

sub _InfoRow {
    my ( $Self, %Param ) = @_;
    my $Value = defined $Param{Value} ? $Param{Value} : '-';
    $Value =~ s{\r?\n}{<br>}g;
    return '<div class="qisutu-ticket-info-row"><dt>' . $Self->_Escape( $Param{Label} || '' )
        . '</dt><dd>' . join( '<br>', map { $Self->_Escape($_) } split /<br>/, $Value, -1 ) . '</dd></div>';
}

sub _SubmissionFieldError {
    my ( $Self, %Param ) = @_;
    my $Field = $Param{Field} || {};
    my $Text = $Self->_T( $Param{Key}, $Param{Language}, 'Invalid form value: {field}' );
    my $Label = $Field->{label} || $Field->{field_key} || '-';
    $Text =~ s{\{field\}}{$Label}g;
    $Self->{LastError} = $Text;
    return;
}

sub _AllowedOriginsClean {
    my ( $Self, $Raw ) = @_;
    my @Origin;
    for my $Line ( split /[\r\n,]+/, ( defined $Raw ? $Raw : '' ) ) {
        $Line = $Self->_Trim($Line);
        next if !$Line;
        if ( $Line eq '*' ) {
            return '*';
        }
        next if $Line !~ m{\Ahttps?://[A-Za-z0-9.-]+(?::\d+)?\z};
        push @Origin, $Line;
    }
    return join "\n", @Origin;
}

sub _IPAddressHash {
    my ( $Self, $IPAddress ) = @_;
    $IPAddress = $Self->_Trim($IPAddress);
    return '' if !$IPAddress || $IPAddress !~ m{\A[0-9A-Fa-f:.]{3,45}\z};
    my $Salt = ( $Self->{Config}->{System}->{InstanceID} || 'qisutu' ) . ':'
        . ( $Self->{Config}->{Database}->{Password} || 'ticket-form' );
    return sha256_hex( $Salt . ':' . $IPAddress );
}

sub _PositiveLimit {
    my ( $Self, $Value, $Default, $Maximum ) = @_;
    return $Default if !defined $Value || $Value !~ m{\A\d+\z};
    $Value = 0 + $Value;
    return $Maximum if $Value > $Maximum;
    return $Value;
}

sub _T {
    my ( $Self, $Key, $Language, $Fallback ) = @_;
    return $Fallback if !$Self->{Output};
    my $Text = $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' );
    return $Text && $Text ne $Key ? $Text : $Fallback;
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;
    $Language ||= 'en';
    $Language =~ s{[^A-Za-z0-9_-]}{}g;
    $Language =~ tr{_}{-};

    if ( $Language =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
        $Language = lc($1) . '-' . uc($2);
    }
    else {
        $Language = lc $Language;
    }

    return $Language || 'en';
}

sub _LanguageList {
    my ($Self) = @_;

    my $Default = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $Path    = $Self->{Config}->{Paths}->{Language} || '';
    my %Language = ( $Default => 1 );

    if ( $Path && opendir my $DirectoryHandle, $Path ) {
        while ( my $Entry = readdir $DirectoryHandle ) {
            next if $Entry !~ m{\A([A-Za-z0-9_-]+)[.]pm\z};
            my $Code = $Self->_LanguageClean($1);
            $Language{$Code} = 1 if $Code;
        }
        closedir $DirectoryHandle;
    }

    return [
        $Default,
        sort grep { $_ ne $Default } keys %Language,
    ];
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

1;
