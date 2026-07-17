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
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminPostmasterFilters;

use strict;
use warnings;
use utf8;

use JSON::PP ();
use QisutuMail;
use QisutuPostmasterFilter;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config => $Param{Config},
        DB     => $Param{DB},
        Output => $Param{Output},
    };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $User->{language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuPostmasterFilter->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $Mail     = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Ticket   = QisutuTicket->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Options  = $Object->Options( Language => $Language ) || {};
    my $Step     = $Request->{Step} || '';
    my $Action   = $Request->{Action} || 'List';
    my $Error    = '';
    my $TestResult;
    my $Form = {};

    if ( $Step eq 'PostmasterFilterCreate' || $Step eq 'PostmasterFilterUpdate' || $Step eq 'PostmasterFilterTest' ) {
        my $Conditions = $Object->ConditionsFromRequest( Request => $Request );
        my $Actions    = $Object->ActionsFromRequest( Request => $Request );
        $Form = {
            id               => $Request->{FilterID} || '',
            name             => $Request->{Name} || '',
            description      => $Request->{Description} || '',
            match_mode       => $Request->{MatchMode} || 'all',
            message_scope    => $Request->{MessageScope} || 'both',
            stop_after_match => $Request->{StopAfterMatch} ? 1 : 0,
            active           => $Request->{Active} ? 1 : 0,
            sort_order       => $Request->{SortOrder} || 1000,
            conditions       => $Conditions,
            actions          => $Actions,
            test_raw_email   => $Request->{TestRawEmail} || '',
            test_mailbox_id  => $Request->{TestIMAPAccountID} || '',
        };
        $Action = $Request->{FilterID} ? 'Edit' : 'Create';

        if ( $Step eq 'PostmasterFilterTest' ) {
            my $Raw = $Self->_TestEmailContent( Request => $Request );
            if (!$Raw) {
                $Error = 'Translate:PostmasterFilterTestEmailRequired';
            }
            else {
                my $Message = $Mail->MessageParse( RawMessage => $Raw );
                if (!$Message) {
                    $Error = $Mail->Error() || 'Translate:PostmasterFilterTestParseFailed';
                }
                else {
                    my $Mailbox = $Self->_MailboxByID( Mailboxes => $Options->{Mailboxes}, ID => $Request->{TestIMAPAccountID} );
                    my $ExistingTicketID = $Ticket->TicketIDFromSubject( Subject => $Message->{subject} );
                    my $Scope = $ExistingTicketID ? 'follow_up' : 'new';
                    $TestResult = $Object->EvaluateDraft(
                        Filter => $Form,
                        Message => $Message,
                        Context => {
                            IMAPAccount      => $Mailbox,
                            ExistingTicketID => $ExistingTicketID,
                            MessageScope     => $Scope,
                        },
                    );
                    $Error = $Object->Error() if !$TestResult;
                }
            }
        }
        elsif ( $Step eq 'PostmasterFilterCreate' ) {
            my $ID = $Object->FilterCreate(
                Name             => $Form->{name},
                Description      => $Form->{description},
                MatchMode        => $Form->{match_mode},
                MessageScope     => $Form->{message_scope},
                StopAfterMatch   => $Form->{stop_after_match},
                Active           => $Form->{active},
                SortOrder        => $Form->{sort_order},
                Conditions       => $Conditions,
                Actions          => $Actions,
                ChangedByUserID  => $User->{user_account_id},
            );
            return { Redirect => 'index.pl?Page=AdminPostmasterFilters' } if $ID;
            $Error = $Object->Error();
        }
        else {
            my $ID = $Object->FilterUpdate(
                FilterID         => $Form->{id},
                Name             => $Form->{name},
                Description      => $Form->{description},
                MatchMode        => $Form->{match_mode},
                MessageScope     => $Form->{message_scope},
                StopAfterMatch   => $Form->{stop_after_match},
                Active           => $Form->{active},
                SortOrder        => $Form->{sort_order},
                Conditions       => $Conditions,
                Actions          => $Actions,
                ChangedByUserID  => $User->{user_account_id},
            );
            return { Redirect => 'index.pl?Page=AdminPostmasterFilters;Action=Edit;FilterID=' . int( $Form->{id} || 0 ) } if $ID;
            $Error = $Object->Error();
        }
    }
    elsif ( $Step eq 'PostmasterFilterDeactivate' ) {
        my $OK = $Object->FilterDeactivate(
            FilterID         => $Request->{FilterID},
            ChangedByUserID  => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminPostmasterFilters' } if $OK;
        $Error = $Object->Error();
    }

    if ( $Action eq 'Edit' && !%{$Form} ) {
        $Form = $Object->FilterGet( FilterID => $Request->{FilterID} ) || {};
        if (!%{$Form}) {
            $Error ||= $Object->Error();
            $Action = 'List';
        }
    }
    elsif ( $Action eq 'Create' && !%{$Form} ) {
        $Form = {
            match_mode       => 'all',
            message_scope    => 'both',
            active           => 1,
            stop_after_match => 0,
            sort_order       => 1000,
            conditions       => [ { field_name => 'subject', operator => 'contains', match_value => '', case_sensitive => 0 } ],
            actions          => [ { action_type => 'queue', target_id => '', action_value => '' } ],
        };
    }

    my $LogEntry;
    if ( $Action eq 'Log' ) {
        $LogEntry = $Object->RunLogGet( RunID => $Request->{RunID} );
        if (!$LogEntry) {
            $Error ||= $Object->Error();
            $Action = 'List';
        }
    }

    my $Filters = $Object->FilterList( IncludeInactive => 1 );
    $Error ||= $Object->Error();
    my $Logs = $Object->RunLogList( Limit => 50 );
    $Error ||= $Object->Error();

    my $ClientConfig = $Self->_ClientConfig(
        Object     => $Object,
        Options    => $Options,
        Form       => $Form,
        Language   => $Language,
    );

    return {
        Template => 'AdminPostmasterFilters.tt',
        Data => {
            PageTitle          => 'Translate:AdminPostmasterFiltersTitle',
            ProgramTitle       => 'Translate:AdminPostmasterFiltersTitle',
            ProgramDescription => 'Translate:AdminPostmasterFiltersDescription',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowForm           => $Action eq 'Create' || $Action eq 'Edit' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowLog            => $Action eq 'Log' ? 1 : 0,
            FormTitle          => $Action eq 'Edit' ? 'Translate:PostmasterFilterEdit' : 'Translate:PostmasterFilterCreate',
            FormStep           => $Action eq 'Edit' ? 'PostmasterFilterUpdate' : 'PostmasterFilterCreate',
            FormFilterID       => $Form->{id} || '',
            FormName           => $Form->{name} || '',
            FormDescription    => $Form->{description} || '',
            FormSortOrder      => defined $Form->{sort_order} ? $Form->{sort_order} : 1000,
            FormActiveChecked  => $Form->{active} ? 'checked' : '',
            FormStopChecked    => $Form->{stop_after_match} ? 'checked' : '',
            MatchAllSelected   => ( $Form->{match_mode} || 'all' ) eq 'all' ? 'selected' : '',
            MatchAnySelected   => ( $Form->{match_mode} || '' ) eq 'any' ? 'selected' : '',
            ScopeBothSelected  => ( $Form->{message_scope} || 'both' ) eq 'both' ? 'selected' : '',
            ScopeNewSelected   => ( $Form->{message_scope} || '' ) eq 'new' ? 'selected' : '',
            ScopeFollowSelected => ( $Form->{message_scope} || '' ) eq 'follow_up' ? 'selected' : '',
            TestRawEmail       => $Form->{test_raw_email} || '',
            MailboxOptionsHTML => $Self->_OptionsHTML( List => $Options->{Mailboxes}, Selected => $Form->{test_mailbox_id}, EmptyLabel => $Self->_T('PostmasterFilterAnyMailbox', $Language) ),
            FiltersRowsHTML    => $Self->_FiltersRowsHTML( Filters => $Filters, Language => $Language ),
            LogsRowsHTML       => $Self->_LogsRowsHTML( Logs => $Logs, Language => $Language ),
            HasFilters         => @{$Filters} ? 1 : 0,
            HasLogs            => @{$Logs} ? 1 : 0,
            ClientConfigJSON   => $ClientConfig,
            TestResultHTML     => $Self->_TestResultHTML( Result => $TestResult, Language => $Language ),
            TestResultVisible  => $TestResult ? 1 : 0,
            LogDetailHTML      => $Self->_LogDetailHTML( Log => $LogEntry, Language => $Language ),
            ErrorMessage       => $Self->_TranslateError( $Error, $Language ),
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
        },
    };
}

sub _ClientConfig {
    my ( $Self, %Param ) = @_;
    my $Object   = $Param{Object};
    my $Options  = $Param{Options} || {};
    my $Form     = $Param{Form} || {};
    my $Language = $Param{Language} || 'en';

    my @Conditions = map {
        +{
            key      => $_->{key},
            label    => $Self->_DefinitionLabel( $_->{label}, $Language ),
            type     => $_->{type} || 'text',
            argument => $_->{argument} ? JSON::PP::true : JSON::PP::false,
        }
    } @{ $Object->ConditionDefinitions() };
    my @Operators = map {
        +{
            key      => $_->{key},
            label    => $Self->_DefinitionLabel( $_->{label}, $Language ),
            type     => $_->{type} || 'text',
            advanced => $_->{advanced} ? JSON::PP::true : JSON::PP::false,
        }
    } @{ $Object->OperatorDefinitions() };
    my @Actions = map {
        +{
            key    => $_->{key},
            label  => $Self->_DefinitionLabel( $_->{label}, $Language ),
            target => $_->{target} || 'none',
        }
    } @{ $Object->ActionDefinitions() };

    my %OptionMap = (
        queue         => $Self->_PlainOptions( $Options->{Queues} ),
        state         => $Self->_PlainOptions( $Options->{States} ),
        priority      => $Self->_PlainOptions( $Options->{Priorities} ),
        agent         => $Self->_PlainOptions( $Options->{Agents} ),
        service       => $Self->_PlainOptions( $Options->{Services} ),
        sla           => $Self->_PlainOptions( $Options->{SLAs} ),
        customer      => $Self->_PlainOptions( $Options->{Customers} ),
        customer_user => $Self->_PlainOptions( $Options->{CustomerUsers} ),
        dynamic_field => $Self->_PlainOptions( $Options->{DynamicFields} ),
    );

    my $Data = {
        conditionDefinitions => \@Conditions,
        operatorDefinitions  => \@Operators,
        actionDefinitions    => \@Actions,
        options              => \%OptionMap,
        conditions           => $Form->{conditions} || [],
        actions              => $Form->{actions} || [],
        labels => {
            field          => $Self->_T('PostmasterFilterField', $Language),
            header         => $Self->_T('PostmasterFilterHeaderName', $Language),
            operator       => $Self->_T('PostmasterFilterOperator', $Language),
            value          => $Self->_T('PostmasterFilterValue', $Language),
            caseSensitive  => $Self->_T('PostmasterFilterCaseSensitive', $Language),
            remove         => $Self->_T('AdminRemove', $Language),
            action         => $Self->_T('PostmasterFilterAction', $Language),
            target         => $Self->_T('PostmasterFilterTarget', $Language),
            select         => $Self->_T('PostmasterFilterSelect', $Language),
            yes            => $Self->_T('CommonYes', $Language),
            no             => $Self->_T('CommonNo', $Language),
            visibleBoth    => $Self->_T('PostmasterFilterVisibleBoth', $Language),
            visibleAgent   => $Self->_T('PostmasterFilterVisibleAgent', $Language),
            senderCustomer => $Self->_T('PostmasterFilterSenderCustomer', $Language),
            senderAgent    => $Self->_T('PostmasterFilterSenderAgent', $Language),
            senderSystem   => $Self->_T('PostmasterFilterSenderSystem', $Language),
            regexAdvanced  => $Self->_T('PostmasterFilterRegexAdvanced', $Language),
        },
    };

    my $JSON = JSON::PP->new->canonical(1)->encode($Data);
    $JSON =~ s{<}{\\u003c}g;
    $JSON =~ s{>}{\\u003e}g;
    $JSON =~ s{&}{\\u0026}g;
    return $JSON;
}

sub _FiltersRowsHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $Edit = $Self->_T('AdminEdit', $Language);
    my $Deactivate = $Self->_T('AdminDeactivate', $Language);
    my $Yes = $Self->_T('CommonYes', $Language);
    my $No  = $Self->_T('CommonNo', $Language);
    my $HTML = '';
    for my $Filter ( @{ $Param{Filters} || [] } ) {
        my $ID = int( $Filter->{id} || 0 );
        $HTML .= '<tr><td>' . $Self->_E( $Filter->{sort_order} || 0 ) . '</td>';
        $HTML .= '<td><strong>' . $Self->_E( $Filter->{name} || '' ) . '</strong>';
        $HTML .= '<br><small>' . $Self->_E( $Filter->{description} ) . '</small>' if $Filter->{description};
        $HTML .= '</td><td>' . $Self->_E( $Self->_T('PostmasterFilterScope' . _Camel( $Filter->{message_scope} || 'both' ), $Language) ) . '</td>';
        $HTML .= '<td>' . int( $Filter->{condition_count} || 0 ) . '</td><td>' . int( $Filter->{action_count} || 0 ) . '</td>';
        $HTML .= '<td>' . ( $Filter->{active} ? $Yes : $No ) . '</td><td class="qisutu-table-actions">';
        $HTML .= '<a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="index.pl?Page=AdminPostmasterFilters;Action=Edit;FilterID=' . $ID . '">' . $Self->_E($Edit) . '</a>';
        if ( $Filter->{active} ) {
            $HTML .= ' <form method="post" action="index.pl" class="qisutu-inline-form"><input type="hidden" name="Page" value="AdminPostmasterFilters"><input type="hidden" name="Step" value="PostmasterFilterDeactivate"><input type="hidden" name="FilterID" value="' . $ID . '"><button class="qisutu-button qisutu-button-danger qisutu-button-small" type="submit">' . $Self->_E($Deactivate) . '</button></form>';
        }
        $HTML .= '</td></tr>';
    }
    return $HTML;
}

sub _LogsRowsHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Log ( @{ $Param{Logs} || [] } ) {
        my $Ticket = $Log->{ticket_id} ? '<a href="index.pl?Page=AgentTicketZoom;TicketID=' . int($Log->{ticket_id}) . '">#' . int($Log->{ticket_id}) . '</a>' : '-';
        $HTML .= '<tr><td>' . $Self->_E( $Log->{created_at} || '' ) . '</td>';
        $HTML .= '<td>' . $Self->_E( $Log->{mailbox_name} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->_E( $Log->{from_email} || '-' ) . '<br><small>' . $Self->_E( $Log->{message_subject} || '' ) . '</small></td>';
        $HTML .= '<td>' . $Self->_E( $Log->{message_scope} || '' ) . '</td><td>' . $Self->_E( $Log->{result} || '' ) . '</td>';
        $HTML .= '<td>' . int( $Log->{matched_count} || 0 ) . '/' . int( $Log->{filter_count} || 0 ) . '</td><td>' . $Ticket . '</td>';
        $HTML .= '<td>' . $Self->_E( $Log->{error_message} || '' ) . '</td>';
        $HTML .= '<td><a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="index.pl?Page=AdminPostmasterFilters;Action=Log;RunID=' . int( $Log->{id} || 0 ) . '">' . $Self->_E( $Self->_T('PostmasterFilterLogDetails', $Param{Language} || 'en') ) . '</a></td></tr>';
    }
    return $HTML;
}

sub _TestResultHTML {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{Result};
    return '' if !$Result;
    my $Language = $Param{Language} || 'en';
    my $HTML = '<div class="qisutu-postmaster-test-summary"><strong>' . $Self->_E( $Result->{MatchedCount} ? $Self->_T('PostmasterFilterTestMatched', $Language) : $Self->_T('PostmasterFilterTestNotMatched', $Language) ) . '</strong></div>';
    for my $Detail ( @{ $Result->{Details} || [] } ) {
        $HTML .= '<section class="qisutu-postmaster-test-filter"><h4>' . $Self->_E( $Detail->{filter_name} || '' ) . ': ' . $Self->_E( $Detail->{matched} ? $Self->_T('CommonYes', $Language) : $Self->_T('CommonNo', $Language) ) . '</h4><ul>';
        for my $Condition ( @{ $Detail->{conditions} || [] } ) {
            my $Values = join( ' | ', @{ $Condition->{values} || [] } );
            $HTML .= '<li class="' . ( $Condition->{matched} ? 'is-match' : 'is-no-match' ) . '">' . $Self->_E( $Condition->{field_name} . ' / ' . $Condition->{operator} . ' / ' . $Condition->{match_value} . ' → ' . $Values ) . '</li>';
        }
        $HTML .= '</ul>';
        if ( @{ $Detail->{actions} || [] } ) {
            $HTML .= '<p><strong>' . $Self->_E( $Self->_T('PostmasterFilterActionsWouldRun', $Language) ) . '</strong> ' . $Self->_E( join(', ', @{ $Detail->{actions} }) ) . '</p>';
        }
        $HTML .= '</section>';
    }
    return $HTML;
}

sub _LogDetailHTML {
    my ( $Self, %Param ) = @_;
    my $Log = $Param{Log};
    return '' if !$Log;
    my $Language = $Param{Language} || 'en';
    my $Details = ref $Log->{details} eq 'HASH' ? $Log->{details} : {};
    my $HTML = '<dl class="qisutu-postmaster-log-meta">';
    for my $Item (
        [ 'CommonDate', $Log->{created_at} ],
        [ 'PostmasterFilterMailbox', $Log->{mailbox_name} || $Log->{mailbox_email} ],
        [ 'PostmasterFilterEmail', ( $Log->{from_email} || '' ) . ' — ' . ( $Log->{message_subject} || '' ) ],
        [ 'PostmasterFilterScope', $Log->{message_scope} ],
        [ 'PostmasterFilterResult', $Log->{result} ],
        [ 'PostmasterFilterMatches', ( $Log->{matched_count} || 0 ) . '/' . ( $Log->{filter_count} || 0 ) ],
        [ 'Ticket', $Log->{ticket_number} || $Log->{ticket_id} || '-' ],
        [ 'CommonError', $Log->{error_message} || '-' ],
    ) {
        $HTML .= '<dt>' . $Self->_E( $Self->_T( $Item->[0], $Language ) ) . '</dt><dd>' . $Self->_E( $Item->[1] || '-' ) . '</dd>';
    }
    $HTML .= '</dl>';

    for my $Detail ( @{ $Details->{Details} || [] } ) {
        $HTML .= '<section class="qisutu-postmaster-test-filter"><h3>' . $Self->_E( $Detail->{filter_name} || '' ) . '</h3>';
        if ( !$Detail->{scope_match} ) {
            $HTML .= '<p>' . $Self->_E( $Self->_T('PostmasterFilterLogScopeSkipped', $Language) ) . '</p></section>';
            next;
        }
        $HTML .= '<p><strong>' . $Self->_E( $Self->_T('PostmasterFilterTestMatched', $Language) ) . '</strong> ' . $Self->_E( $Detail->{matched} ? $Self->_T('CommonYes', $Language) : $Self->_T('CommonNo', $Language) ) . '</p>';
        if ( @{ $Detail->{conditions} || [] } ) {
            $HTML .= '<div class="qisutu-table-wrap"><table class="qisutu-table"><thead><tr><th>' . $Self->_E($Self->_T('PostmasterFilterField',$Language)) . '</th><th>' . $Self->_E($Self->_T('PostmasterFilterOperator',$Language)) . '</th><th>' . $Self->_E($Self->_T('PostmasterFilterValue',$Language)) . '</th><th>' . $Self->_E($Self->_T('PostmasterFilterActualValues',$Language)) . '</th><th>' . $Self->_E($Self->_T('PostmasterFilterTestMatched',$Language)) . '</th></tr></thead><tbody>';
            for my $Condition ( @{ $Detail->{conditions} || [] } ) {
                $HTML .= '<tr><td>' . $Self->_E( $Condition->{field_name} || '' ) . '</td><td>' . $Self->_E( $Condition->{operator} || '' ) . '</td><td>' . $Self->_E( $Condition->{match_value} || '' ) . '</td><td>' . $Self->_E( join(' | ', @{ $Condition->{values} || [] }) ) . '</td><td>' . $Self->_E( $Condition->{matched} ? $Self->_T('CommonYes',$Language) : $Self->_T('CommonNo',$Language) ) . '</td></tr>';
            }
            $HTML .= '</tbody></table></div>';
        }
        if ( @{ $Detail->{actions} || [] } ) {
            $HTML .= '<p><strong>' . $Self->_E( $Self->_T('PostmasterFilterActionsWouldRun', $Language) ) . '</strong> ' . $Self->_E( join(', ', @{ $Detail->{actions} }) ) . '</p>';
        }
        $HTML .= '</section>';
    }
    return $HTML;
}

sub _TestEmailContent {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $Uploads = $Request->{__Uploads} || {};
    my $List = ref $Uploads->{TestEmailFile} eq 'ARRAY' ? $Uploads->{TestEmailFile} : [];
    if ( @{$List} && ref $List->[0] eq 'HASH' && defined $List->[0]->{Content} ) {
        return $List->[0]->{Content};
    }
    return $Request->{TestRawEmail} || '';
}

sub _MailboxByID {
    my ( $Self, %Param ) = @_;
    my $ID = $Param{ID} || 0;
    for my $Mailbox ( @{ $Param{Mailboxes} || [] } ) {
        return $Mailbox if $ID && ( $Mailbox->{id} || 0 ) == $ID;
    }
    return {};
}

sub _PlainOptions {
    my ( $Self, $List ) = @_;
    return [ map { +{ id => 0 + ( $_->{id} || 0 ), label => $_->{label} || $_->{name} || $_->{id} || '' } } @{ $List || [] } ];
}

sub _OptionsHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '<option value="">' . $Self->_E( $Param{EmptyLabel} || '' ) . '</option>';
    for my $Item ( @{ $Param{List} || [] } ) {
        my $Selected = ( $Item->{id} || '' ) eq ( $Param{Selected} || '' ) ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_E( $Item->{id} || '' ) . '"' . $Selected . '>' . $Self->_E( $Item->{label} || $Item->{name} || '' ) . '</option>';
    }
    return $HTML;
}

sub _DefinitionLabel {
    my ( $Self, $Label, $Language ) = @_;
    $Label ||= '';
    $Label =~ s{\ATranslate:}{};
    return $Self->_T( $Label, $Language );
}

sub _TranslateError {
    my ( $Self, $Error, $Language ) = @_;
    return '' if !$Error;
    if ( $Error =~ m{\ATranslate:([^:]+)(?::\s*(.*))?\z}s ) {
        my $Text = $Self->_T( $1, $Language );
        $Text .= ': ' . $2 if defined $2 && $2 ne '';
        return $Text;
    }
    return $Error;
}

sub _T {
    my ( $Self, $Key, $Language ) = @_;
    return $Self->{Output}->Translate( Key => $Key, Language => $Language ) if $Self->{Output};
    return $Key;
}

sub _E {
    my ( $Self, $Value ) = @_;
    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};
    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g; $Value =~ s/</&lt;/g; $Value =~ s/>/&gt;/g; $Value =~ s/"/&quot;/g; $Value =~ s/'/&#39;/g;
    return $Value;
}

sub _Camel {
    my ($Value) = @_;
    $Value ||= '';
    return join '', map { ucfirst lc $_ } split /_+/, $Value;
}

1;
