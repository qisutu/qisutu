# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminCommunicationLog;

use strict;
use warnings;
use utf8;

use QisutuCommunicationLog;

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
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuCommunicationLog->new( Config => $Self->{Config}, DB => $Self->{DB} );

    my %Filter = (
        Period    => $Self->_Allowed( $Request->{Period}, [qw(1h 24h 7d 30d custom)], '24h' ),
        DateFrom  => $Self->_Date( $Request->{DateFrom} ),
        DateTo    => $Self->_Date( $Request->{DateTo} ),
        Protocol  => $Self->_Allowed( $Request->{Protocol}, [qw(imap smtp oauth2)], '' ),
        Direction => $Self->_Allowed( $Request->{Direction}, [qw(incoming outgoing system)], '' ),
        Status    => $Self->_Allowed( $Request->{Status}, [qw(running success warning error cancelled)], '' ),
        Account   => $Self->_Account( $Request->{Account} ),
        Search    => substr( $Self->_Trim( $Request->{Search} ), 0, 190 ),
        ListPage  => $Self->_PositiveInteger( $Request->{ListPage}, 1 ),
    );

    my @DataError;
    my $Statistics = $Object->Statistics(%Filter);
    push @DataError, $Object->Error() if $Object->Error();
    my $PerPage    = 25;
    my $TotalCount = $Statistics->{total_count} || 0;
    my $TotalPages = $TotalCount ? int( ( $TotalCount + $PerPage - 1 ) / $PerPage ) : 1;
    $Filter{ListPage} = $TotalPages if $Filter{ListPage} > $TotalPages;
    my $Logs = $Object->List(
        %Filter,
        Limit  => $PerPage,
        Offset => ( $Filter{ListPage} - 1 ) * $PerPage,
    );
    push @DataError, $Object->Error() if $Object->Error();
    my $Accounts = $Object->AccountList();
    push @DataError, $Object->Error() if $Object->Error();
    my $Detail = $Request->{LogID} ? $Object->Get( CommunicationID => $Request->{LogID} ) : undef;
    push @DataError, $Object->Error() if $Request->{LogID} && $Object->Error();
    my $FilterURL  = $Self->_FilterURL(%Filter);

    for my $Log ( @{$Logs} ) {
        $Self->_LogPrepare( Log => $Log, Language => $Language, FilterURL => $FilterURL );
    }
    if ($Detail) {
        $Self->_LogPrepare( Log => $Detail, Language => $Language, FilterURL => $FilterURL );
        for my $Step ( @{ $Detail->{Steps} || [] } ) {
            $Step->{step_number} = ++$Detail->{_step_counter};
            $Step->{level_display} = $Self->_T( 'CommunicationLogLevel' . ucfirst( $Step->{level} || 'info' ), $Language );
            $Step->{stage_display} = $Self->_StageDisplay( $Step->{stage}, $Language );
            $Step->{level_class}   = 'is-' . ( $Step->{level} || 'info' );
            $Step->{message_display} = $Self->_MessageDisplay( $Step->{message}, $Language );
            $Step->{source_display} = uc( $Step->{source_protocol} || $Detail->{protocol} || '' )
                . ' · ' . $Self->_OperationDisplay( $Step->{source_operation} || $Detail->{operation}, $Language );
            $Step->{is_child_class} = ( $Step->{source_log_id} || 0 ) != ( $Detail->{id} || 0 ) ? 'is-child-operation' : '';
            $Step->{technical_details_html} = '';
            if ( defined $Step->{technical_details} && $Step->{technical_details} ne '' ) {
                $Step->{technical_details_html} = '<details><summary>'
                    . $Self->_E( $Self->_T( 'CommunicationLogTechnicalDetails', $Language ) )
                    . '</summary><pre>' . $Self->_E( $Step->{technical_details} ) . '</pre></details>';
            }
        }
    }

    my $AccountOptions = '<option value="">' . $Self->_E( $Self->_T( 'CommunicationLogAllAccounts', $Language ) ) . '</option>';
    for my $Account ( @{$Accounts} ) {
        my $Value = ( $Account->{account_type} || '' ) . ':' . ( $Account->{account_id} || 0 );
        my $Selected = $Value eq $Filter{Account} ? ' selected' : '';
        my $Label = ( $Account->{account_display} || $Value ) . ' (' . uc( $Account->{account_type} || '' ) . ')';
        $AccountOptions .= '<option value="' . $Self->_E($Value) . '"' . $Selected . '>' . $Self->_E($Label) . '</option>';
    }

    my %ErrorSeen;
    my $Error = join '; ', grep { defined $_ && $_ ne '' && !$ErrorSeen{$_}++ } @DataError;
    my $DetailTicketHTML = '-';
    if ( $Detail && $Detail->{ticket_url} ) {
        $DetailTicketHTML = '<a href="' . $Self->_E( $Detail->{ticket_url} ) . '">'
            . $Self->_E( $Detail->{ticket_number} || '#' . ( $Detail->{ticket_id} || 0 ) ) . '</a>';
    }
    my $HasDetailSteps = $Detail && @{ $Detail->{Steps} || [] } ? 1 : 0;
    my $HasMessageMetadata = $Detail && ( grep {
        defined $_ && $_ ne ''
    } @{$Detail}{qw(sender_email recipient_email subject message_id ticket_id article_id)} ) ? 1 : 0;
    my $HasProcessingData = $Detail && ( grep {
        $_
    } @{$Detail}{qw(messages_found messages_processed messages_created messages_updated messages_ignored messages_failed messages_sent bytes_transferred)} ) ? 1 : 0;
    return {
        Template => 'AdminCommunicationLog.tt',
        Data     => {
            PageTitle          => 'Translate:CommunicationLogTitle',
            ProgramTitle       => 'Translate:CommunicationLogTitle',
            ProgramDescription => 'Translate:CommunicationLogDescription',
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            Logs               => $Logs,
            HasLogs            => @{$Logs} ? 1 : 0,
            LogCount           => scalar @{$Logs},
            Detail             => $Detail || {},
            HasDetail          => $Detail ? 1 : 0,
            DetailCloseURL     => $FilterURL,
            DetailProtocolDisplay => $Detail ? $Detail->{protocol_display} : '',
            DetailOperationDisplay => $Detail ? $Detail->{operation_display} : '',
            DetailDirectionDisplay => $Detail ? $Detail->{direction_display} : '',
            DetailStartedAt       => $Detail ? ( $Detail->{started_at} || '' ) : '',
            DetailFinishedAt      => $Detail ? ( $Detail->{finished_at} || '-' ) : '',
            DetailStatusClass     => $Detail ? ( $Detail->{status_class} || '' ) : '',
            DetailStatusDisplay   => $Detail ? ( $Detail->{status_display} || '' ) : '',
            DetailDurationDisplay => $Detail ? ( $Detail->{duration_display} || '' ) : '',
            DetailAccountDisplay  => $Detail ? ( $Detail->{account_display} || '-' ) : '',
            DetailServerDisplay   => $Detail ? ( $Detail->{server_display} || '-' ) : '',
            DetailTraceID         => $Detail ? ( $Detail->{trace_id} || '-' ) : '',
            DetailSecurity        => $Detail ? ( $Detail->{connection_security} || '-' ) : '',
            DetailSender          => $Detail ? ( $Detail->{sender_email} || '-' ) : '',
            DetailRecipient       => $Detail ? ( $Detail->{recipient_email} || '-' ) : '',
            DetailSubject         => $Detail ? ( $Detail->{subject} || '-' ) : '',
            DetailMessageID       => $Detail ? ( $Detail->{message_id} || '-' ) : '',
            DetailTicketHTML      => $DetailTicketHTML,
            DetailArticle        => $Detail && $Detail->{article_id} ? '#' . $Detail->{article_id} : '-',
            DetailResult          => $Detail ? ( $Detail->{result_display} || '-' ) : '',
            DetailSteps           => $Detail ? ( $Detail->{Steps} || [] ) : [],
            DetailStepCount       => $Detail ? scalar( @{ $Detail->{Steps} || [] } ) : 0,
            HasDetailSteps        => $HasDetailSteps,
            HasMessageMetadata    => $HasMessageMetadata,
            HasProcessingData     => $HasProcessingData,
            DetailMessagesFound   => $Detail ? ( $Detail->{messages_found} || 0 ) : 0,
            DetailMessagesProcessed => $Detail ? ( $Detail->{messages_processed} || 0 ) : 0,
            DetailMessagesCreated => $Detail ? ( $Detail->{messages_created} || 0 ) : 0,
            DetailMessagesUpdated => $Detail ? ( $Detail->{messages_updated} || 0 ) : 0,
            DetailMessagesIgnored => $Detail ? ( $Detail->{messages_ignored} || 0 ) : 0,
            DetailMessagesFailed  => $Detail ? ( $Detail->{messages_failed} || 0 ) : 0,
            DetailMessagesSent    => $Detail ? ( $Detail->{messages_sent} || 0 ) : 0,
            DetailBytesTransferred => $Detail ? ( $Detail->{bytes_transferred} || 0 ) : 0,
            AccountOptionsHTML => $AccountOptions,
            PaginationHTML    => $Self->_PaginationHTML(
                Filter      => \%Filter,
                CurrentPage => $Filter{ListPage},
                TotalPages  => $TotalPages,
                TotalCount  => $TotalCount,
                Language    => $Language,
            ),
            FilterSearch       => $Filter{Search},
            FilterDateFrom     => $Filter{DateFrom},
            FilterDateTo       => $Filter{DateTo},
            Period1hSelected   => $Filter{Period} eq '1h' ? 'selected' : '',
            Period24hSelected  => $Filter{Period} eq '24h' ? 'selected' : '',
            Period7dSelected   => $Filter{Period} eq '7d' ? 'selected' : '',
            Period30dSelected  => $Filter{Period} eq '30d' ? 'selected' : '',
            PeriodCustomSelected => $Filter{Period} eq 'custom' ? 'selected' : '',
            ProtocolAllSelected => !$Filter{Protocol} ? 'selected' : '',
            ProtocolIMAPSelected => $Filter{Protocol} eq 'imap' ? 'selected' : '',
            ProtocolSMTPSelected => $Filter{Protocol} eq 'smtp' ? 'selected' : '',
            ProtocolOAuth2Selected => $Filter{Protocol} eq 'oauth2' ? 'selected' : '',
            DirectionAllSelected => !$Filter{Direction} ? 'selected' : '',
            DirectionIncomingSelected => $Filter{Direction} eq 'incoming' ? 'selected' : '',
            DirectionOutgoingSelected => $Filter{Direction} eq 'outgoing' ? 'selected' : '',
            DirectionSystemSelected => $Filter{Direction} eq 'system' ? 'selected' : '',
            StatusAllSelected => !$Filter{Status} ? 'selected' : '',
            StatusRunningSelected => $Filter{Status} eq 'running' ? 'selected' : '',
            StatusSuccessSelected => $Filter{Status} eq 'success' ? 'selected' : '',
            StatusWarningSelected => $Filter{Status} eq 'warning' ? 'selected' : '',
            StatusErrorSelected => $Filter{Status} eq 'error' ? 'selected' : '',
            TotalCount     => $TotalCount,
            SuccessCount   => $Statistics->{success_count} || 0,
            WarningCount   => $Statistics->{warning_count} || 0,
            ErrorCount     => $Statistics->{error_count} || 0,
            RunningCount   => $Statistics->{running_count} || 0,
            ReceivedCount  => $Statistics->{received_count} || 0,
            SentCount      => $Statistics->{sent_count} || 0,
            AverageDuration => $Self->_Duration( $Statistics->{average_duration_ms} || 0, $Language ),
        },
    };
}

sub _LogPrepare {
    my ( $Self, %Param ) = @_;
    my $Log      = $Param{Log} || {};
    my $Language = $Param{Language};
    $Log->{protocol_display}  = uc( $Log->{protocol} || '' );
    $Log->{direction_display} = $Self->_T( 'CommunicationLogDirection' . ucfirst( $Log->{direction} || 'system' ), $Language );
    $Log->{status_display}    = $Self->_T( 'CommunicationLogStatus' . ucfirst( $Log->{status} || 'running' ), $Language );
    $Log->{operation_display} = $Self->_OperationDisplay( $Log->{operation}, $Language );
    $Log->{status_class}      = 'is-' . ( $Log->{status} || 'running' );
    $Log->{duration_display}  = $Self->_Duration( $Log->{display_duration_ms} || $Log->{duration_ms} || 0, $Language );
    $Log->{account_display}   = $Log->{account_name} || $Log->{account_email} || uc( $Log->{account_type} || '' ) . ' #' . ( $Log->{account_id} || 0 );
    $Log->{server_display}    = $Log->{server_host} || '-';
    $Log->{server_display}   .= ':' . $Log->{server_port} if $Log->{server_port};
    $Log->{detail_url}        = ( $Param{FilterURL} || 'index.pl?Page=AdminCommunicationLog' )
        . ';LogID=' . int( $Log->{id} || 0 );
    $Log->{ticket_url}        = $Log->{ticket_id} ? 'index.pl?Page=AgentTicketZoom;TicketID=' . int( $Log->{ticket_id} ) : '';
    $Log->{result_display}    = $Log->{error_message} || $Log->{result_summary} || '-';
    my %StatusSymbol = ( success => '✓', warning => '!', error => '×', running => '↔', cancelled => '–' );
    my %DirectionSymbol = ( incoming => '←', outgoing => '→', system => '↔' );
    $Log->{status_symbol}     = $StatusSymbol{ $Log->{status} || '' } || '•';
    $Log->{direction_symbol}  = $DirectionSymbol{ $Log->{direction} || '' } || '↔';
    $Log->{finished_display}  = $Log->{finished_at} || '-';
    $Log->{row_title}         = $Self->_T( 'CommunicationLogOpenDetailsHint', $Language );
    return;
}

sub _MessageDisplay {
    my ( $Self, $Value, $Language ) = @_;
    return '-' if !defined $Value || $Value eq '';
    return $Self->_T( substr( $Value, 10 ), $Language ) if $Value =~ m{\ATranslate:};
    return $Value;
}

sub _OperationDisplay {
    my ( $Self, $Value, $Language ) = @_;
    my %Key = (
        test => 'CommunicationLogOperationTest', fetch => 'CommunicationLogOperationFetch',
        delete => 'CommunicationLogOperationDelete', send => 'CommunicationLogOperationSend',
        notification => 'CommunicationLogOperationNotification', automation => 'CommunicationLogOperationAutomation',
        customer_registration => 'CommunicationLogOperationCustomerRegistration',
        password_reset => 'CommunicationLogOperationPasswordReset', password_changed => 'CommunicationLogOperationPasswordChanged',
        token_refresh => 'CommunicationLogOperationTokenRefresh', token_authorization => 'CommunicationLogOperationTokenAuthorization',
        authorization_callback => 'CommunicationLogOperationAuthorizationCallback',
    );
    return $Self->_T( $Key{$Value || ''}, $Language ) if $Key{$Value || ''};
    return $Value || '-';
}

sub _StageDisplay {
    my ( $Self, $Value, $Language ) = @_;
    my %Key = map { $_ => 'CommunicationLogStage' . join( '', map { ucfirst($_) } split /_/, $_ ) } qw(
        start connect greeting tls oauth2 authentication select search folder_list fetch_message parse_message
        process_message postmaster_filter ignored ticket delete expunge envelope transfer request response token
        authorization configuration logout result processing ticket_recognition filter_check filter_action
        dynamic_field attachment notification source_cleanup message_build
    );
    return $Self->_T( $Key{$Value || ''}, $Language ) if $Key{$Value || ''};
    return $Value || '-';
}

sub _Duration {
    my ( $Self, $Milliseconds, $Language ) = @_;
    $Milliseconds = 0 if !$Milliseconds || $Milliseconds !~ m{\A\d+\z};
    return $Milliseconds . ' ms' if $Milliseconds < 1000;
    return sprintf( '%.2f s', $Milliseconds / 1000 ) if $Milliseconds < 60000;
    return sprintf( '%.2f min', $Milliseconds / 60000 );
}

sub _FilterURL {
    my ( $Self, %Filter ) = @_;
    my $URL = 'index.pl?Page=AdminCommunicationLog';
    for my $Key ( qw(Period DateFrom DateTo Protocol Direction Status Account Search ListPage) ) {
        next if !defined $Filter{$Key} || $Filter{$Key} eq '';
        next if $Key eq 'ListPage' && $Filter{$Key} == 1;
        $URL .= ';' . $Key . '=' . $Self->_URLEncode( $Filter{$Key} );
    }
    return $URL;
}

sub _PaginationHTML {
    my ( $Self, %Param ) = @_;

    my $Filter      = $Param{Filter} || {};
    my $CurrentPage = $Param{CurrentPage} || 1;
    my $TotalPages  = $Param{TotalPages} || 1;
    return '' if $TotalPages <= 1;

    my $Language = $Param{Language};
    my $HTML = '<nav class="qisutu-communication-pagination" aria-label="'
        . $Self->_E( $Self->_T( 'CommunicationLogPagination', $Language ) ) . '">';
    if ( $CurrentPage > 1 ) {
        my %Previous = ( %{$Filter}, ListPage => $CurrentPage - 1 );
        $HTML .= '<a href="' . $Self->_E( $Self->_FilterURL(%Previous) ) . '" aria-label="'
            . $Self->_E( $Self->_T( 'CommunicationLogPreviousPage', $Language ) ) . '">‹</a>';
    }

    my $From = $CurrentPage - 2;
    my $To   = $CurrentPage + 2;
    $From = 1 if $From < 1;
    $To = $TotalPages if $To > $TotalPages;
    for my $Page ( $From .. $To ) {
        if ( $Page == $CurrentPage ) {
            $HTML .= '<strong aria-current="page">' . $Page . '</strong>';
        }
        else {
            my %PageFilter = ( %{$Filter}, ListPage => $Page );
            $HTML .= '<a href="' . $Self->_E( $Self->_FilterURL(%PageFilter) ) . '">' . $Page . '</a>';
        }
    }
    if ( $CurrentPage < $TotalPages ) {
        my %Next = ( %{$Filter}, ListPage => $CurrentPage + 1 );
        $HTML .= '<a href="' . $Self->_E( $Self->_FilterURL(%Next) ) . '" aria-label="'
            . $Self->_E( $Self->_T( 'CommunicationLogNextPage', $Language ) ) . '">›</a>';
    }
    $HTML .= '<span>' . $Self->_E( $Self->_T( 'CommunicationLogPage', $Language ) ) . ' '
        . $CurrentPage . ' / ' . $TotalPages . '</span></nav>';
    return $HTML;
}

sub _Allowed {
    my ( $Self, $Value, $Allowed, $Default ) = @_;
    $Value = lc( $Self->_Trim($Value) );
    my %Allowed = map { $_ => 1 } @{$Allowed || []};
    return $Allowed{$Value} ? $Value : $Default;
}

sub _Account {
    my ( $Self, $Value ) = @_;
    $Value = lc( $Self->_Trim($Value) );
    return $Value =~ m{\A(?:imap|smtp):\d+\z} ? $Value : '';
}

sub _Date {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_Trim($Value);
    return $Value =~ m{\A\d{4}-\d{2}-\d{2}\z} ? $Value : '';
}

sub _PositiveInteger {
    my ( $Self, $Value, $Default ) = @_;
    return $Default if !defined $Value || ref $Value || $Value !~ m{\A\d+\z} || $Value < 1;
    return $Value > 100000 ? 100000 : 0 + $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;
    utf8::encode($Value) if utf8::is_utf8($Value);
    $Value =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord($1)}eg;
    return $Value;
}

sub _T {
    my ( $Self, $Key, $Language ) = @_;
    return $Key if !$Key || !$Self->{Output};
    my $Text = $Self->{Output}->Translate( Key => $Key, Language => $Language );
    return defined $Text && $Text ne '' ? $Text : $Key;
}

sub _E {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

1;
