# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminTicketForms;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json);
use QisutuTicketForm;

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
    my $Action   = $Request->{Action} || 'List';
    my $Step     = $Request->{Step} || '';
    my $FormID   = $Self->_ID( $Request->{FormID} );
    my $FieldID  = $Self->_ID( $Request->{FieldID} );
    my $RequestedFormType = ( $Request->{FormType} || '' ) eq 'public' ? 'public' : 'customer';
    my $Object   = QisutuTicketForm->new(
        Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output},
    );
    my $Status = $Request->{Status} || '';

    if ( $Step eq 'CustomerSearch' ) {
        return $Self->_CustomerSearchResponse(
            Query  => $Request->{Query},
            Offset => $Request->{Offset},
        );
    }

    if ( $Step eq 'FormCreate' ) {
        $FormID = $Object->FormCreate(
            %{ $Self->_FormParameters( Request => $Request ) },
            ChangedByUserID => $User->{user_account_id},
        ) || 0;
        return { Redirect => 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . $FormID . ';Status=created' }
            if $FormID && !$Object->Error();
        $Action = 'Create';
    }
    elsif ( $Step eq 'FormUpdate' ) {
        my $Success = $Object->FormUpdate(
            FormID => $FormID,
            %{ $Self->_FormParameters( Request => $Request ) },
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . $FormID . ';Status=updated' }
            if $Success && !$Object->Error();
        $Action = 'Edit';
    }
    elsif ( $Step eq 'FormActivate' || $Step eq 'FormDeactivate' ) {
        my $Success = $Object->FormSetActive(
            FormID         => $FormID,
            Active         => $Step eq 'FormActivate' ? 1 : 0,
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketForms;Status=' . ( $Step eq 'FormActivate' ? 'activated' : 'deactivated' ) }
            if $Success && !$Object->Error();
        $Action = 'List';
    }
    elsif ( $Step eq 'FormDelete' ) {
        my $Success = $Object->FormDelete(
            FormID         => $FormID,
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketForms;Status=deleted' }
            if $Success && !$Object->Error();
        $Action = 'List';
    }
    elsif ( $Step eq 'FieldCreate' ) {
        $FieldID = $Object->FieldCreate(
            FormID => $FormID,
            %{ $Self->_FieldParameters( Request => $Request ) },
            ChangedByUserID => $User->{user_account_id},
        ) || 0;
        return { Redirect => 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . $FormID . ';Status=field_created' }
            if $FieldID && !$Object->Error();
        $Action = 'Edit';
    }
    elsif ( $Step eq 'FieldUpdate' ) {
        my $Success = $Object->FieldUpdate(
            FieldID => $FieldID,
            %{ $Self->_FieldParameters( Request => $Request ) },
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . $FormID . ';Status=field_updated' }
            if $Success && !$Object->Error();
        $Action = 'FieldEdit';
    }
    elsif ( $Step eq 'FieldDeactivate' ) {
        my $Success = $Object->FieldDeactivate(
            FieldID         => $FieldID,
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . $FormID . ';Status=field_deactivated' }
            if $Success && !$Object->Error();
        $Action = 'Edit';
    }

    my $FormList = $Object->FormList( Language => $Language, IncludeInactive => 1 );
    for my $Form ( @{$FormList} ) {
        $Form->{type_display} = ( $Form->{form_type} || '' ) eq 'public'
            ? $Self->_T( 'AdminTicketFormTypePublic', $Language )
            : $Self->_T( 'AdminTicketFormTypeCustomer', $Language );
        $Form->{active_display} = $Self->_T( $Form->{active} ? 'AdminActiveYes' : 'AdminActiveNo', $Language );
        $Form->{queue_display}  = $Form->{queue_full_name} || $Form->{queue_name} || '-';
        $Form->{edit_url}       = 'index.pl?Page=AdminTicketForms;Action=Edit;FormID=' . ( $Form->{id} || 0 );
        $Form->{toggle_step}    = $Form->{active} ? 'FormDeactivate' : 'FormActivate';
        $Form->{toggle_label}   = $Self->_T( $Form->{active} ? 'AdminDeactivate' : 'AdminActivate', $Language );
        $Form->{toggle_class}   = $Form->{active} ? 'qisutu-button-danger' : 'qisutu-button-success';
        $Form->{delete_class}   = !$Form->{active} && !$Form->{submission_count} ? '' : 'qisutu-hidden';
    }

    my $Form;
    if ( $Action eq 'Edit' || $Action eq 'FieldEdit' ) {
        $Form = $Object->FormGet( FormID => $FormID, Language => $Language );
        if ( !$Form ) {
            $Action = 'List';
            $Object->{LastError} ||= 'Translate:AdminTicketFormNotFound';
        }
    }

    my $FormSubmitted = $Step eq 'FormCreate' || $Step eq 'FormUpdate' ? 1 : 0;
    my $FormValues = $FormSubmitted
        ? $Self->_FormValuesFromRequest($Request)
        : ( $Form || { form_type => $RequestedFormType } );
    my $EditorFormType = ( $FormValues->{form_type} || '' ) eq 'public' ? 'public' : 'customer';
    my $FormTranslations = $FormSubmitted
        ? $Self->_FormTranslationsFromRequest($Request)
        : ( $Form ? $Object->FormTranslationList( FormID => $Form->{id} ) : $Self->_DefaultFormTranslations($Language) );
    my $SelectedCustomerIDs = $FormSubmitted
        ? $Self->_CustomerIDsFromRequest($Request)
        : ( $Form ? $Object->FormCustomerIDList( FormID => $Form->{id} ) : [] );
    my %SelectedCustomer = map { $_ => 1 } @{$SelectedCustomerIDs};

    my $Queues = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name, active FROM ticket_queue ORDER BY sort_order ASC, full_name ASC, name ASC, id ASC'
    ) || [];
    my $SelectedCustomers = $EditorFormType eq 'customer'
        ? $Self->_CustomerRowsByID( CustomerIDs => $SelectedCustomerIDs )
        : [];

    my $FieldList = $Form ? $Object->FieldList( FormID => $Form->{id}, Language => $Language, IncludeInactive => 1 ) : [];
    my $Field;
    if ( $Action eq 'FieldEdit' ) {
        $Field = $Object->FieldGet( FieldID => $FieldID );
        if ( !$Field || ( $Field->{form_id} || 0 ) != ( $Form->{id} || 0 ) ) {
            $Action = 'Edit';
            $Field = undef;
        }
    }
    my $FieldSubmitted = $Step eq 'FieldCreate' || $Step eq 'FieldUpdate' ? 1 : 0;
    my $FieldValues = $FieldSubmitted ? $Self->_FieldValuesFromRequest($Request) : ( $Field || {} );
    my $FieldTranslations = $FieldSubmitted
        ? $Self->_FieldTranslationsFromRequest($Request)
        : ( $Field ? $Object->FieldTranslationList( FieldID => $Field->{id} ) : $Self->_DefaultFieldTranslations($Language) );
    my $OptionsText = $FieldSubmitted
        ? ( $Request->{OptionsText} || '' )
        : $Self->_OptionsText( Field => $Field );

    my $Error = $Object->Error();
    my $Notice = $Self->_StatusNotice( Status => $Status, Language => $Language );
    my $PublicURL = $Form ? $Self->_PublicURL( Slug => $Form->{slug} ) : '';
    my $EmbedCode = $PublicURL
        ? '<iframe src="' . $PublicURL . '" title="' . ( $Form->{title} || $Form->{internal_name} )
            . '" width="100%" height="720" loading="lazy"></iframe>'
        : '';

    return {
        Template => 'AdminTicketForms.tt',
        Data     => {
            PageTitle          => 'Translate:AdminTicketFormsTitle',
            ProgramTitle       => 'Translate:AdminTicketFormsTitle',
            ProgramDescription => 'Translate:AdminTicketFormsDescription',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' || $Action eq 'FieldEdit' ? 1 : 0,
            ShowFieldEdit      => $Action eq 'FieldEdit' ? 1 : 0,
            ShowFieldCreate    => $Action eq 'Edit' ? 1 : 0,
            FormList           => $FormList,
            FormCount          => scalar @{$FormList},
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            NoticeMessage      => $Notice,
            NoticeClass        => $Notice ? 'qisutu-form-success' : 'qisutu-hidden',
            FormID             => $Form ? $Form->{id} : '',
            SettingsStep       => $Form ? 'FormUpdate' : 'FormCreate',
            FormInternalName   => $FormValues->{internal_name} || '',
            FormSlug           => $FormValues->{slug} || '',
            FormType            => $EditorFormType,
            FormEditorTitle     => $Self->_T(
                $Action eq 'Create'
                    ? ( $EditorFormType eq 'public' ? 'AdminTicketFormCreatePublic' : 'AdminTicketFormCreateCustomer' )
                    : ( $EditorFormType eq 'public' ? 'AdminTicketFormEditPublic' : 'AdminTicketFormEditCustomer' ),
                $Language,
            ),
            QueueOptionsHTML   => $Self->_QueueOptions( Queues => $Queues, Selected => $FormValues->{queue_id} ),
            FormSortOrder      => defined $FormValues->{sort_order} ? $FormValues->{sort_order} : 1000,
            FormActiveChecked  => !exists $FormValues->{active} || $FormValues->{active} ? 'checked' : '',
            FormAllCustomersChecked => !exists $FormValues->{all_customers} || $FormValues->{all_customers} ? 'checked' : '',
            FormRequireConsentChecked => $FormValues->{require_consent} ? 'checked' : '',
            FormAllowedOrigins => defined $FormValues->{allowed_origins} ? $FormValues->{allowed_origins} : '*',
            FormRateLimitHour   => defined $FormValues->{rate_limit_hour} ? $FormValues->{rate_limit_hour} : 20,
            FormRateLimitDay    => defined $FormValues->{rate_limit_day} ? $FormValues->{rate_limit_day} : 240,
            FormRateLimitTotalDay => defined $FormValues->{rate_limit_total_day} ? $FormValues->{rate_limit_total_day} : 5000,
            FormTranslationsHTML => $Self->_FormTranslationsHTML(
                Translations => $FormTranslations,
                Language     => $Language,
                FormType     => $EditorFormType,
            ),
            CustomerAssignmentsHTML => $Self->_CustomerAssignmentsHTML(
                Customers => $SelectedCustomers,
                Selected  => \%SelectedCustomer,
                Language  => $Language,
            ),
            SelectedCustomerCount => scalar @{$SelectedCustomerIDs},
            CustomerSearchURL     => 'index.pl?Page=AdminTicketForms&Step=CustomerSearch',
            FormFieldsHTML      => $Self->_FormFieldsAdminHTML( Fields => $FieldList, Form => $Form, Language => $Language ),
            PublicURL           => $PublicURL,
            EmbedCode           => $EmbedCode,
            IsPublicForm        => $EditorFormType eq 'public' ? 1 : 0,
            IsCustomerForm      => $EditorFormType eq 'customer' ? 1 : 0,
            FieldID             => $Field ? $Field->{id} : '',
            FieldStep           => $Field ? 'FieldUpdate' : 'FieldCreate',
            FieldKey            => $FieldValues->{field_key} || '',
            FieldKeyReadonly    => $Field ? 'readonly' : '',
            FieldTypeOptionsHTML => $Self->_FieldTypeOptions( Selected => $FieldValues->{field_type} || 'text', Core => $Field && !$Field->{dynamic_field_id}, Language => $Language ),
            FieldRequiredChecked => $FieldValues->{is_required} ? 'checked' : '',
            FieldActiveChecked  => !exists $FieldValues->{active} || $FieldValues->{active} ? 'checked' : '',
            FieldDefaultValue   => $FieldValues->{default_value} || '',
            FieldSortOrder      => defined $FieldValues->{sort_order} ? $FieldValues->{sort_order} : 1000,
            FieldTranslationsHTML => $Self->_FieldTranslationsHTML( Translations => $FieldTranslations, Language => $Language ),
            FieldOptionsText    => $OptionsText,
            FieldOptionsClass   => ( $FieldValues->{field_type} || 'text' ) =~ m{\A(?:dropdown|multiselect)\z} ? '' : 'qisutu-hidden',
            FieldIsCore         => $Field && !$Field->{dynamic_field_id} ? 1 : 0,
        },
    };
}

sub _FormParameters {
    my ( $Self, %Param ) = @_;
    my $R = $Param{Request} || {};
    my $FormType = ( $R->{FormType} || '' ) eq 'public' ? 'public' : 'customer';
    my $Slug = $R->{Slug};

    if ( $FormType eq 'customer' && !$Self->_Trim($Slug) ) {
        my $Base = lc $Self->_Trim( $R->{InternalName} );
        $Base =~ s{[^a-z0-9]+}{-}g;
        $Base =~ s{\A-+|-+\z}{}g;
        $Base ||= 'customer-form';
        $Base = substr( $Base, 0, 60 );
        $Slug = $Base . '-' . time . '-' . int( 100000 + rand 900000 );
    }

    return {
        InternalName   => $R->{InternalName}, FormType => $FormType, Slug => $Slug,
        QueueID        => $R->{QueueID},
        AllCustomers   => $FormType eq 'customer' && $R->{AllCustomers} ? 1 : 0,
        RequireConsent => $FormType eq 'public' && $R->{RequireConsent} ? 1 : 0,
        AllowedOrigins => $FormType eq 'public' ? $R->{AllowedOrigins} : '*',
        RateLimitHour  => $FormType eq 'public' ? $R->{RateLimitHour} : 20,
        RateLimitDay   => $FormType eq 'public' ? $R->{RateLimitDay} : 240,
        RateLimitTotalDay => $FormType eq 'public' ? $R->{RateLimitTotalDay} : 5000,
        Active         => $R->{Active}, SortOrder => $R->{SortOrder},
        Translations   => $Self->_FormTranslationsFromRequest($R),
        CustomerIDs    => $FormType eq 'customer' ? $Self->_CustomerIDsFromRequest($R) : [],
    };
}

sub _FieldParameters {
    my ( $Self, %Param ) = @_;
    my $R = $Param{Request} || {};
    return {
        FieldKey     => $R->{FieldKey}, FieldType => $R->{FieldType}, IsRequired => $R->{IsRequired},
        Active       => $R->{Active}, DefaultValue => $R->{DefaultValue}, SortOrder => $R->{SortOrder},
        Options      => $Self->_OptionsFromText( $R->{OptionsText} ),
        Translations => $Self->_FieldTranslationsFromRequest($R),
    };
}

sub _FormTranslationsFromRequest {
    my ( $Self, $R ) = @_;
    my %Value;
    for my $Language (qw(de en fr it)) {
        $Value{$Language} = {
            title => $R->{ 'FormTitle_' . $Language }, description => $R->{ 'FormDescription_' . $Language },
            submit_label => $R->{ 'FormSubmitLabel_' . $Language }, confirmation_text => $R->{ 'FormConfirmation_' . $Language },
            consent_text => $R->{ 'FormConsentText_' . $Language },
        };
    }
    return \%Value;
}

sub _FieldTranslationsFromRequest {
    my ( $Self, $R ) = @_;
    my %Value;
    for my $Language (qw(de en fr it)) {
        $Value{$Language} = {
            label => $R->{ 'FieldLabel_' . $Language }, help_text => $R->{ 'FieldHelp_' . $Language },
            placeholder => $R->{ 'FieldPlaceholder_' . $Language },
        };
    }
    return \%Value;
}

sub _CustomerIDsFromRequest {
    my ( $Self, $R ) = @_;

    my @CustomerIDs;
    for my $Key ( keys %{$R} ) {
        next if $Key !~ m{\ACustomer_(\d+)\z};
        next if !$R->{$Key};
        push @CustomerIDs, 0 + $1;
    }

    return \@CustomerIDs;
}

sub _CustomerRowsByID {
    my ( $Self, %Param ) = @_;

    my %Seen;
    my @CustomerIDs = grep {
        defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 && !$Seen{$_}++
    } @{ $Param{CustomerIDs} || [] };
    return [] if !@CustomerIDs;

    my @Rows;
    while (@CustomerIDs) {
        my @Chunk = splice @CustomerIDs, 0, 500;
        my $Placeholder = join ', ', map {'?'} @Chunk;
        my $ChunkRows = $Self->{DB}->SelectAll(
            'SELECT id, customer_number, name, active
             FROM customer
             WHERE id IN (' . $Placeholder . ')',
            @Chunk,
        ) || [];
        push @Rows, @{$ChunkRows};
    }

    @Rows = sort {
        lc( $a->{name} || '' ) cmp lc( $b->{name} || '' )
            || ( $a->{id} || 0 ) <=> ( $b->{id} || 0 )
    } @Rows;

    return \@Rows;
}

sub _CustomerSearchResponse {
    my ( $Self, %Param ) = @_;

    my $Query = ref $Param{Query} ? '' : $Self->_Trim( $Param{Query} );
    $Query = substr( $Query, 0, 100 );
    my $Offset = $Param{Offset};
    $Offset = 0 if !defined $Offset || $Offset !~ m{\A\d+\z};
    $Offset = 1000000 if $Offset > 1000000;
    my $Limit = 100;
    my @Bind;
    my $Where = 'WHERE active = 1';

    if ($Query) {
        my $Like = '%' . $Query . '%';
        $Where .= ' AND (name LIKE ? OR customer_number LIKE ?)';
        push @Bind, $Like, $Like;
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, customer_number, name
         FROM customer
         ' . $Where . '
         ORDER BY name ASC, id ASC
         LIMIT ' . ( $Limit + 1 ) . ' OFFSET ' . int($Offset),
        @Bind,
    ) || [];

    my $HasMore = @{$Rows} > $Limit ? 1 : 0;
    splice @{$Rows}, $Limit if $HasMore;
    my @Items = map {
        {
            id              => 0 + ( $_->{id} || 0 ),
            name            => $_->{name} || '',
            customer_number => $_->{customer_number} || '',
        }
    } @{$Rows};

    return {
        Response => $Self->{Output}->Response(
            ContentType => 'application/json; charset=UTF-8',
            Body        => encode_json({
                items    => \@Items,
                has_more => $HasMore ? JSON::PP::true : JSON::PP::false,
                offset   => int($Offset),
                limit    => $Limit,
            }),
        ),
    };
}

sub _FormValuesFromRequest {
    my ( $Self, $R ) = @_;
    return {
        internal_name => $R->{InternalName}, slug => $R->{Slug}, form_type => $R->{FormType}, queue_id => $R->{QueueID},
        all_customers => $R->{AllCustomers} ? 1 : 0, require_consent => $R->{RequireConsent} ? 1 : 0,
        allowed_origins => $R->{AllowedOrigins}, rate_limit_hour => $R->{RateLimitHour}, rate_limit_day => $R->{RateLimitDay},
        rate_limit_total_day => $R->{RateLimitTotalDay}, active => $R->{Active} ? 1 : 0, sort_order => $R->{SortOrder},
    };
}

sub _FieldValuesFromRequest {
    my ( $Self, $R ) = @_;
    return {
        field_key => $R->{FieldKey}, field_type => $R->{FieldType}, is_required => $R->{IsRequired} ? 1 : 0,
        active => $R->{Active} ? 1 : 0, default_value => $R->{DefaultValue}, sort_order => $R->{SortOrder},
    };
}

sub _DefaultFormTranslations {
    my ( $Self, $Language ) = @_;
    my %Value;
    for my $Code (qw(de en fr it)) {
        $Value{$Code} = { title => '', description => '', submit_label => $Self->_T( 'TicketFormSubmit', $Code ),
            confirmation_text => $Self->_T( 'TicketFormConfirmationDefault', $Code ), consent_text => '' };
    }
    return \%Value;
}

sub _DefaultFieldTranslations {
    my ( $Self, $Language ) = @_;
    return { map { $_ => { label => '', help_text => '', placeholder => '' } } qw(de en fr it) };
}

sub _FormTranslationsHTML {
    my ( $Self, %Param ) = @_;
    my $Value = $Param{Translations} || {};
    my $HTML = '';
    for my $Code (qw(de en fr it)) {
        my $Row = $Value->{$Code} || {};
        $HTML .= '<details class="qisutu-ticket-form-language"' . ( $Code eq ( $Self->{Config}->{Language}->{Default} || 'de' ) ? ' open' : '' ) . '>'
            . '<summary>' . uc($Code) . '</summary><div class="qisutu-ticket-form-language-grid">'
            . $Self->_Input( Label => $Self->_T('AdminTicketFormPublicTitle', $Param{Language}), Name => 'FormTitle_' . $Code, Value => $Row->{title}, Required => $Code eq ( $Self->{Config}->{Language}->{Default} || 'de' ) )
            . $Self->_Textarea( Label => $Self->_T('AdminDescription', $Param{Language}), Name => 'FormDescription_' . $Code, Value => $Row->{description}, Rows => 3 )
            . $Self->_Input( Label => $Self->_T('AdminTicketFormSubmitLabel', $Param{Language}), Name => 'FormSubmitLabel_' . $Code, Value => $Row->{submit_label} );
        if ( ( $Param{FormType} || '' ) eq 'public' ) {
            $HTML .= $Self->_Textarea( Label => $Self->_T('AdminTicketFormConfirmation', $Param{Language}), Name => 'FormConfirmation_' . $Code, Value => $Row->{confirmation_text}, Rows => 3 )
                . $Self->_Textarea( Label => $Self->_T('AdminTicketFormConsentText', $Param{Language}), Name => 'FormConsentText_' . $Code, Value => $Row->{consent_text}, Rows => 3 );
        }
        $HTML .= '</div></details>';
    }
    return $HTML;
}

sub _FieldTranslationsHTML {
    my ( $Self, %Param ) = @_;
    my $Value = $Param{Translations} || {};
    my $HTML = '';
    for my $Code (qw(de en fr it)) {
        my $Row = $Value->{$Code} || {};
        $HTML .= '<details class="qisutu-ticket-form-language"' . ( $Code eq ( $Self->{Config}->{Language}->{Default} || 'de' ) ? ' open' : '' ) . '>'
            . '<summary>' . uc($Code) . '</summary><div class="qisutu-ticket-form-language-grid">'
            . $Self->_Input( Label => $Self->_T('AdminTicketFormFieldLabel', $Param{Language}), Name => 'FieldLabel_' . $Code, Value => $Row->{label}, Required => $Code eq ( $Self->{Config}->{Language}->{Default} || 'de' ) )
            . $Self->_Input( Label => $Self->_T('AdminTicketFormFieldPlaceholder', $Param{Language}), Name => 'FieldPlaceholder_' . $Code, Value => $Row->{placeholder} )
            . $Self->_Textarea( Label => $Self->_T('AdminTicketFormFieldHelp', $Param{Language}), Name => 'FieldHelp_' . $Code, Value => $Row->{help_text}, Rows => 2 )
            . '</div></details>';
    }
    return $HTML;
}

sub _FormFieldsAdminHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Field ( @{ $Param{Fields} || [] } ) {
        my $Core = $Field->{dynamic_field_id} ? '' : ' <span class="qisutu-badge">' . $Self->_E( $Self->_T('AdminTicketFormCoreField', $Param{Language}) ) . '</span>';
        my $Inactive = $Field->{active} ? '' : ' <span class="qisutu-badge">' . $Self->_E( $Self->_T('AdminInactive', $Param{Language}) ) . '</span>';
        $HTML .= '<article class="qisutu-ticket-form-field-card"><div><strong>' . $Self->_E( $Field->{label} || $Field->{field_key} ) . '</strong>'
            . $Core . $Inactive . '<span>' . $Self->_E( $Field->{field_type} ) . ' · '
            . $Self->_E( $Field->{is_required} ? $Self->_T('AdminRequired', $Param{Language}) : $Self->_T('AdminOptional', $Param{Language}) )
            . ' · ' . $Self->_E( $Self->_T('AdminSortOrder', $Param{Language}) ) . ': ' . $Self->_E( $Field->{sort_order} ) . '</span></div>'
            . '<div class="qisutu-ticket-form-field-actions"><a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="index.pl?Page=AdminTicketForms;Action=FieldEdit;FormID=' . int($Param{Form}->{id}) . ';FieldID=' . int($Field->{id}) . '">' . $Self->_E( $Self->_T('AdminEdit', $Param{Language}) ) . '</a>';
        if ( $Field->{active} ) {
            $HTML .= '<form method="post" action="index.pl"><input type="hidden" name="Page" value="AdminTicketForms"><input type="hidden" name="Step" value="FieldDeactivate"><input type="hidden" name="FormID" value="' . int($Param{Form}->{id}) . '"><input type="hidden" name="FieldID" value="' . int($Field->{id}) . '"><button class="qisutu-button qisutu-button-danger qisutu-button-small" type="submit">' . $Self->_E( $Self->_T('AdminRemove', $Param{Language}) ) . '</button></form>';
        }
        $HTML .= '</div></article>';
    }
    return $HTML || '<div class="qisutu-empty"><p>' . $Self->_E( $Self->_T('AdminTicketFormNoFields', $Param{Language}) ) . '</p></div>';
}

sub _CustomerAssignmentsHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Customer ( @{ $Param{Customers} || [] } ) {
        my $ID = $Customer->{id} || 0;
        next if !$Param{Selected}->{$ID};
        my $Label = ( $Customer->{name} || '' ) . ' (' . ( $Customer->{customer_number} || '' ) . ')';
        $HTML .= '<input type="hidden" name="Customer_' . int($ID) . '" value="1" data-qisutu-customer-selected'
            . ' data-customer-id="' . int($ID) . '" data-customer-label="' . $Self->_E($Label) . '">';
    }
    return $HTML;
}

sub _QueueOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '<option value="">-</option>';
    for my $Queue ( @{ $Param{Queues} || [] } ) {
        my $ID = $Queue->{id} || 0;
        $HTML .= '<option value="' . int($ID) . '"' . ( $ID == ( $Param{Selected} || 0 ) ? ' selected' : '' ) . '>'
            . $Self->_E( $Queue->{full_name} || $Queue->{name} || '' ) . '</option>';
    }
    return $HTML;
}

sub _FieldTypeOptions {
    my ( $Self, %Param ) = @_;
    my @Type = $Param{Core} ? ( $Param{Selected} ) : qw(text textarea email phone date number dropdown multiselect checkbox);
    return join '', map { '<option value="' . $_ . '"' . ( $_ eq $Param{Selected} ? ' selected' : '' ) . '>' . $Self->_E($_) . '</option>' } @Type;
}

sub _OptionsFromText {
    my ( $Self, $Text ) = @_;
    my @Options;
    my $Sort = 0;
    for my $Line ( split /\r?\n/, ( defined $Text ? $Text : '' ) ) {
        next if $Line !~ /\S/;
        my ( $Key, $Value ) = split /\|/, $Line, 2;
        $Key   = $Self->_Trim($Key);
        $Value = $Self->_Trim( defined $Value ? $Value : $Key );
        next if !$Key || !$Value;
        $Sort += 100;
        push @Options, { option_key => $Key, option_value => $Value, sort_order => $Sort };
    }
    return \@Options;
}

sub _OptionsText {
    my ( $Self, %Param ) = @_;
    my $Field = $Param{Field} || {};
    return '' if !$Field->{dynamic_field_id};
    my $Rows = $Self->{DB}->SelectAll('SELECT option_key, option_value FROM ticket_dynamic_field_option WHERE field_id = ? ORDER BY sort_order ASC, id ASC', $Field->{dynamic_field_id}) || [];
    return join "\n", map { ( $_->{option_key} || '' ) . '|' . ( $_->{option_value} || '' ) } @{$Rows};
}

sub _PublicURL {
    my ( $Self, %Param ) = @_;
    my $Base = $Self->{Config}->{System}->{BaseURL} || '';
    $Base =~ s{/index\.pl\z}{};
    $Base =~ s{/\z}{};
    return ( $Base ? $Base . '/' : '' ) . 'form.pl?Form=' . ( $Param{Slug} || '' );
}

sub _StatusNotice {
    my ( $Self, %Param ) = @_;
    my %Key = (
        created => 'AdminTicketFormCreated', updated => 'AdminTicketFormUpdated', activated => 'AdminTicketFormActivated',
        deactivated => 'AdminTicketFormDeactivated', deleted => 'AdminTicketFormDeleted', field_created => 'AdminTicketFormFieldCreated',
        field_updated => 'AdminTicketFormFieldUpdated', field_deactivated => 'AdminTicketFormFieldDeactivated',
    );
    return $Key{ $Param{Status} || '' } ? $Self->_T( $Key{ $Param{Status} }, $Param{Language} ) : '';
}

sub _Input {
    my ( $Self, %Param ) = @_;
    return '<div class="qisutu-form-field"><label>' . $Self->_E( $Param{Label} ) . '</label><input type="text" name="'
        . $Self->_E( $Param{Name} ) . '" value="' . $Self->_E( $Param{Value} ) . '"' . ( $Param{Required} ? ' required' : '' ) . '></div>';
}

sub _Textarea {
    my ( $Self, %Param ) = @_;
    return '<div class="qisutu-form-field qisutu-ticket-form-field-wide"><label>' . $Self->_E( $Param{Label} ) . '</label><textarea name="'
        . $Self->_E( $Param{Name} ) . '" rows="' . int( $Param{Rows} || 3 ) . '">' . $Self->_E( $Param{Value} ) . '</textarea></div>';
}

sub _ID { my ( $Self, $Value ) = @_; return defined $Value && $Value =~ m{\A\d+\z} ? int($Value) : 0; }
sub _Trim { my ( $Self, $Value ) = @_; $Value = '' if !defined $Value || ref $Value; $Value =~ s{\A\s+|\s+\z}{}g; return $Value; }
sub _E { my ( $Self, $Value ) = @_; return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' ); }
sub _T { my ( $Self, $Key, $Language ) = @_; return $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' ); }

1;
