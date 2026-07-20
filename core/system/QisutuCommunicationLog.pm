# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuCommunicationLog;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Database = $Param{DB};
    my $FallbackDatabase = $Database;
    my $OwnDatabase = 0;
    if ( $Param{Independent} && $Database && ref($Database) eq 'QisutuDB' ) {
        require QisutuDB;
        my $Separate = QisutuDB->new( Config => $Param{Config} );
        if ( $Separate->Connect() ) {
            $Database = $Separate;
            $OwnDatabase = 1;
        }
    }

    my $Self = {
        Config    => $Param{Config},
        DB        => $Database,
        FallbackDB => $FallbackDatabase,
        OwnDB     => $OwnDatabase,
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Start {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    return if !$Self->{DB};

    my $Protocol  = lc( $Self->_Trim( $Param{Protocol} ) );
    my $Direction = lc( $Self->_Trim( $Param{Direction} ) );
    my $Operation = lc( $Self->_Trim( $Param{Operation} ) );

    $Protocol  = 'imap'     if $Protocol !~ m{\A(?:imap|smtp|oauth2)\z};
    $Direction = 'incoming' if $Direction !~ m{\A(?:incoming|outgoing|system)\z};
    $Operation = 'connection' if $Operation !~ m{\A[a-z0-9_-]{1,50}\z};

    my $TraceID = $Self->_TraceID();
    my @Bind = (
        $TraceID,
        $Self->_OptionalID( $Param{ParentID} ),
        $Protocol,
        $Direction,
        $Operation,
        substr( lc( $Self->_Trim( $Param{AccountType} ) ), 0, 20 ) || undef,
        $Self->_OptionalID( $Param{AccountID} ),
        substr( $Self->_Trim( $Param{AccountName} ), 0, 190 ) || undef,
        substr( $Self->_Trim( $Param{AccountEmail} ), 0, 255 ) || undef,
        substr( $Self->_Trim( $Param{ServerHost} ), 0, 255 ) || undef,
        $Self->_Unsigned( $Param{ServerPort} ) || undef,
        substr( lc( $Self->_Trim( $Param{ConnectionSecurity} ) ), 0, 50 ) || undef,
        $Self->_OptionalID( $Param{TicketID} ),
        $Self->_OptionalID( $Param{ArticleID} ),
        substr( $Self->_CleanText( $Param{MessageID} ), 0, 500 ) || undef,
        substr( $Self->_CleanText( $Param{SenderEmail} ), 0, 500 ) || undef,
        substr( $Self->_CleanText( $Param{RecipientEmail} ), 0, 1000 ) || undef,
        substr( $Self->_CleanText( $Param{Subject} ), 0, 500 ) || undef,
    );
    my $SQL = q{INSERT INTO communication_log (
            trace_id, parent_id, protocol, direction, operation, status,
            account_type, account_id, account_name, account_email,
            server_host, server_port, connection_security,
            ticket_id, article_id, message_id, sender_email, recipient_email, subject,
            started_at, created_at
         ) VALUES (?, ?, ?, ?, ?, 'running', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(6), NOW(6))};

    my $OK = $Self->{DB}->Do( $SQL, @Bind );

    if ( !$OK ) {
        my $PrimaryError = $Self->{DB}->Error() || 'Communication log could not be started';
        my $Fallback = $Self->{FallbackDB};

        # A separate logging connection is preferred, but communication must
        # not disappear merely because that connection cannot write. Retry on
        # the already established application connection and keep using it for
        # all subsequent steps of this entry.
        if ( $Fallback && $Fallback != $Self->{DB} ) {
            my $FallbackOK = $Fallback->Do( $SQL, @Bind );
            if ($FallbackOK) {
                $Self->{DB}    = $Fallback;
                $Self->{OwnDB} = 0;
                $OK = 1;
            }
            else {
                my $FallbackError = $Fallback->Error() || 'fallback write failed';
                $Self->{LastError} = $PrimaryError . '; fallback: ' . $FallbackError;
                return;
            }
        }
        else {
            $Self->{LastError} = $PrimaryError;
            return;
        }
    }

    # Do not trust a driver-specific last_insert_id implementation here.  A
    # communication operation is considered recorded only after the exact
    # trace ID can be read back on the same connection.
    my $Row = $Self->{DB}->SelectRow(
        'SELECT id FROM communication_log WHERE trace_id = ? LIMIT 1',
        $TraceID,
    );
    my $ID = $Row && $Row->{id} ? $Row->{id} : 0;
    if ( !$ID ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Communication log ID could not be loaded';
    }
    return if !$ID;

    return {
        ID      => 0 + $ID,
        TraceID => $TraceID,
    };
}

sub StepAdd {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $CommunicationID = $Self->_OptionalID( $Param{CommunicationID} );
    return if !$Self->{DB} || !$CommunicationID;

    my $Level = lc( $Self->_Trim( $Param{Level} ) );
    $Level = 'info' if $Level !~ m{\A(?:info|success|warning|error)\z};

    my $Stage = lc( $Self->_Trim( $Param{Stage} ) );
    $Stage = 'processing' if $Stage !~ m{\A[a-z0-9_-]{1,50}\z};

    my $Message = substr( $Self->_SensitiveDataRemove( $Param{Message} ), 0, 2000 );
    my $Details = substr( $Self->_SensitiveDataRemove( $Param{Details} ), 0, 16000 );

    my $OK = $Self->{DB}->Do(
        'INSERT INTO communication_log_step (
            communication_log_id, level, stage, message, technical_details, created_at
         ) VALUES (?, ?, ?, ?, ?, NOW(6))',
        $CommunicationID,
        $Level,
        $Stage,
        $Message || 'Communication step',
        $Details || undef,
    );

    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Communication log step could not be saved';
        return;
    }

    return $Self->{DB}->LastInsertID('communication_log_step') || 1;
}

sub Finish {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $CommunicationID = $Self->_OptionalID( $Param{CommunicationID} );
    return if !$Self->{DB} || !$CommunicationID;

    my $Status = lc( $Self->_Trim( $Param{Status} ) );
    $Status = 'success' if $Status !~ m{\A(?:success|warning|error|cancelled)\z};

    my $OK = $Self->{DB}->Do(
        'UPDATE communication_log
         SET status = ?,
             result_summary = ?,
             error_message = ?,
             messages_found = ?,
             messages_processed = ?,
             messages_created = ?,
             messages_updated = ?,
             messages_ignored = ?,
             messages_failed = ?,
             messages_sent = ?,
             bytes_transferred = ?,
             ticket_id = COALESCE(?, ticket_id),
             article_id = COALESCE(?, article_id),
             message_id = COALESCE(?, message_id),
             sender_email = COALESCE(?, sender_email),
             recipient_email = COALESCE(?, recipient_email),
             subject = COALESCE(?, subject),
             finished_at = NOW(6),
             duration_ms = GREATEST(0, ROUND(TIMESTAMPDIFF(MICROSECOND, started_at, NOW(6)) / 1000))
         WHERE id = ?',
        $Status,
        substr( $Self->_SensitiveDataRemove( $Param{Summary} ), 0, 2000 ) || undef,
        substr( $Self->_SensitiveDataRemove( $Param{ErrorMessage} ), 0, 4000 ) || undef,
        $Self->_Unsigned( $Param{MessagesFound} ),
        $Self->_Unsigned( $Param{MessagesProcessed} ),
        $Self->_Unsigned( $Param{MessagesCreated} ),
        $Self->_Unsigned( $Param{MessagesUpdated} ),
        $Self->_Unsigned( $Param{MessagesIgnored} ),
        $Self->_Unsigned( $Param{MessagesFailed} ),
        $Self->_Unsigned( $Param{MessagesSent} ),
        $Self->_Unsigned( $Param{BytesTransferred} ),
        $Self->_OptionalID( $Param{TicketID} ),
        $Self->_OptionalID( $Param{ArticleID} ),
        substr( $Self->_CleanText( $Param{MessageID} ), 0, 500 ) || undef,
        substr( $Self->_CleanText( $Param{SenderEmail} ), 0, 500 ) || undef,
        substr( $Self->_CleanText( $Param{RecipientEmail} ), 0, 1000 ) || undef,
        substr( $Self->_CleanText( $Param{Subject} ), 0, 500 ) || undef,
        $CommunicationID,
    );

    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Communication log could not be completed';
        return;
    }

    return 1;
}

sub Statistics {
    my ( $Self, %Param ) = @_;

    my ( $Where, $Bind ) = $Self->_FilterSQL(%Param);
    my $Row = $Self->{DB}->SelectRow(
        q{SELECT COUNT(*) AS total_count,
                SUM(status = 'success') AS success_count,
                SUM(status = 'warning') AS warning_count,
                SUM(status = 'error') AS error_count,
                SUM(status = 'running') AS running_count,
                COALESCE(SUM(messages_processed), 0) AS received_count,
                COALESCE(SUM(messages_sent), 0) AS sent_count,
                COALESCE(ROUND(AVG(CASE WHEN duration_ms IS NOT NULL THEN duration_ms END)), 0) AS average_duration_ms
         FROM communication_log l } . $Where,
        @{$Bind},
    );

    if ( !$Row ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Communication statistics could not be loaded';
    }

    return $Row || {
        total_count => 0, success_count => 0, warning_count => 0, error_count => 0,
        running_count => 0, received_count => 0, sent_count => 0, average_duration_ms => 0,
    };
}

sub List {
    my ( $Self, %Param ) = @_;

    my $Limit = $Self->_Unsigned( $Param{Limit} ) || 100;
    $Limit = 500 if $Limit > 500;
    my $Offset = $Self->_Unsigned( $Param{Offset} );
    $Offset = 1000000 if $Offset > 1000000;
    my ( $Where, $Bind ) = $Self->_FilterSQL(%Param);

    my $Rows = $Self->{DB}->SelectAll(
        q{SELECT l.*, t.ticket_number,
                CASE WHEN l.status = 'running'
                     THEN GREATEST(0, ROUND(TIMESTAMPDIFF(MICROSECOND, l.started_at, NOW(6)) / 1000))
                     ELSE l.duration_ms END AS display_duration_ms
         FROM communication_log l
         LEFT JOIN ticket t ON t.id = l.ticket_id } . $Where . q{
         ORDER BY l.started_at DESC, l.id DESC
         LIMIT } . int($Limit) . ' OFFSET ' . int($Offset),
        @{$Bind},
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Communication logs could not be loaded';
        return [];
    }

    return $Rows;
}

sub Get {
    my ( $Self, %Param ) = @_;

    my $ID = $Self->_OptionalID( $Param{CommunicationID} );
    return if !$ID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT l.*, t.ticket_number, t.title AS ticket_title
         FROM communication_log l
         LEFT JOIN ticket t ON t.id = l.ticket_id
         WHERE l.id = ? LIMIT 1',
        $ID,
    );
    if ( !$Row ) {
        $Self->{LastError} = 'Communication log was not found';
        return;
    }

    $Row->{Steps} = $Self->{DB}->SelectAll(
        'SELECT s.id, s.level, s.stage, s.message, s.technical_details, s.created_at,
                l.id AS source_log_id, l.protocol AS source_protocol,
                l.operation AS source_operation, l.parent_id AS source_parent_id
         FROM communication_log_step s
         INNER JOIN communication_log l ON l.id = s.communication_log_id
         WHERE l.id = ? OR l.parent_id = ?
         ORDER BY s.created_at ASC, s.id ASC',
        $ID,
        $ID,
    ) || [];

    return $Row;
}

sub AccountList {
    my ($Self) = @_;

    return [] if !$Self->{DB};

    # The filter must already contain configured accounts before their first
    # communication attempt. Historical snapshots are added afterwards so
    # that deleted accounts remain usable for older log entries.
    my @Configured;
    my @Error;
    my $IMAP = $Self->{DB}->SelectAll(
        q{SELECT 'imap' AS account_type, id AS account_id,
                COALESCE(NULLIF(name, ''), NULLIF(email, ''), CONCAT('IMAP #', id)) AS account_display
         FROM postmaster_imap_account}
    );
    if ( defined $IMAP ) {
        push @Configured, @{$IMAP};
    }
    else {
        push @Error, 'IMAP accounts: ' . ( $Self->{DB}->Error() || 'could not be loaded' );
    }

    my $SMTP = $Self->{DB}->SelectAll(
        q{SELECT 'smtp' AS account_type, id AS account_id,
                COALESCE(NULLIF(name, ''), NULLIF(smtp_username, ''), CONCAT('SMTP #', id)) AS account_display
         FROM smtp_account}
    );
    if ( defined $SMTP ) {
        push @Configured, @{$SMTP};
    }
    else {
        push @Error, 'SMTP accounts: ' . ( $Self->{DB}->Error() || 'could not be loaded' );
    }

    my $Historical = $Self->{DB}->SelectAll(
        q{SELECT account_type, account_id,
                MAX(COALESCE(NULLIF(account_name, ''), NULLIF(account_email, ''), CONCAT(UPPER(account_type), ' #', account_id))) AS account_display
         FROM communication_log
         WHERE account_id IS NOT NULL AND account_type IN ('imap', 'smtp')
         GROUP BY account_type, account_id
        }
    );
    if ( !defined $Historical ) {
        push @Error, 'communication history: ' . ( $Self->{DB}->Error() || 'could not be loaded' );
        $Historical = [];
    }

    my %Seen;
    my @Rows;
    for my $Row ( @Configured, @{$Historical} ) {
        next if ref($Row) ne 'HASH';
        my $Type = lc( $Self->_Trim( $Row->{account_type} ) );
        my $ID   = $Self->_OptionalID( $Row->{account_id} );
        next if $Type !~ m{\A(?:imap|smtp)\z} || !$ID;

        my $Key = "$Type:$ID";
        next if $Seen{$Key}++;

        push @Rows, {
            account_type    => $Type,
            account_id      => $ID,
            account_display => $Self->_Trim( $Row->{account_display} ) || uc($Type) . " #$ID",
        };
    }

    @Rows = sort {
        lc( $a->{account_display} ) cmp lc( $b->{account_display} )
            || $a->{account_type} cmp $b->{account_type}
            || $a->{account_id} <=> $b->{account_id}
    } @Rows;

    $Self->{LastError} = join '; ', @Error if @Error;
    return \@Rows;
}

sub Cleanup {
    my ($Self) = @_;

    return 1 if !$Self->{DB};
    my $StaleOK = $Self->{DB}->Do(
        q{UPDATE communication_log
         SET status = 'error',
             result_summary = COALESCE(result_summary, 'Communication process ended without a final status'),
             error_message = COALESCE(error_message, 'Communication process ended without a final status'),
             finished_at = NOW(6),
             duration_ms = GREATEST(0, ROUND(TIMESTAMPDIFF(MICROSECOND, started_at, NOW(6)) / 1000))
         WHERE status = 'running' AND started_at < DATE_SUB(NOW(), INTERVAL 2 HOUR)}
    );
    if ( !$StaleOK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Stale communication logs could not be completed';
        return;
    }

    my $Days = QisutuSystemSetting->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->Get(
        Key     => 'mail.communication_log_retention_days',
        Default => 90,
    );
    $Days = 90 if !defined $Days || $Days !~ m{\A\d+\z};
    return 1 if !$Days;
    $Days = 3650 if $Days > 3650;

    my $OK = $Self->{DB}->Do(
        'DELETE FROM communication_log WHERE started_at < DATE_SUB(NOW(), INTERVAL ' . int($Days) . ' DAY)'
    );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Old communication logs could not be removed';
        return;
    }
    return 1;
}

sub _FilterSQL {
    my ( $Self, %Param ) = @_;

    my @Where;
    my @Bind;
    my $Alias = 'l';
    my $Period = lc( $Self->_Trim( $Param{Period} ) );
    $Period = '24h' if $Period !~ m{\A(?:1h|24h|7d|30d|custom)\z};

    if ( $Period eq '1h' ) {
        push @Where, "$Alias.started_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)";
    }
    elsif ( $Period eq '24h' ) {
        push @Where, "$Alias.started_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)";
    }
    elsif ( $Period eq '7d' ) {
        push @Where, "$Alias.started_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)";
    }
    elsif ( $Period eq '30d' ) {
        push @Where, "$Alias.started_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)";
    }
    else {
        my $From = $Self->_Date( $Param{DateFrom} );
        my $To   = $Self->_Date( $Param{DateTo} );
        if ($From) {
            push @Where, "$Alias.started_at >= ?";
            push @Bind, $From . ' 00:00:00';
        }
        if ($To) {
            push @Where, "$Alias.started_at < DATE_ADD(?, INTERVAL 1 DAY)";
            push @Bind, $To . ' 00:00:00';
        }
    }

    my $Protocol = lc( $Self->_Trim( $Param{Protocol} ) );
    if ( $Protocol =~ m{\A(?:imap|smtp|oauth2)\z} ) {
        push @Where, "$Alias.protocol = ?";
        push @Bind, $Protocol;
    }
    my $Direction = lc( $Self->_Trim( $Param{Direction} ) );
    if ( $Direction =~ m{\A(?:incoming|outgoing|system)\z} ) {
        push @Where, "$Alias.direction = ?";
        push @Bind, $Direction;
    }
    my $Status = lc( $Self->_Trim( $Param{Status} ) );
    if ( $Status =~ m{\A(?:running|success|warning|error|cancelled)\z} ) {
        push @Where, "$Alias.status = ?";
        push @Bind, $Status;
    }
    my $Account = lc( $Self->_Trim( $Param{Account} ) );
    if ( $Account =~ m{\A(imap|smtp):(\d+)\z} && $2 ) {
        push @Where, "$Alias.account_type = ? AND $Alias.account_id = ?";
        push @Bind, $1, 0 + $2;
    }
    else {
        my $AccountID = $Self->_OptionalID( $Param{AccountID} );
        if ($AccountID) {
            push @Where, "$Alias.account_id = ?";
            push @Bind, $AccountID;
        }
    }
    my $Search = $Self->_Trim( $Param{Search} );
    if ($Search) {
        $Search = substr( $Search, 0, 190 );
        push @Where, '(l.trace_id LIKE ? OR l.account_name LIKE ? OR l.account_email LIKE ? OR l.sender_email LIKE ? OR l.recipient_email LIKE ? OR l.subject LIKE ? OR l.message_id LIKE ? OR l.result_summary LIKE ? OR l.error_message LIKE ? OR EXISTS (SELECT 1 FROM ticket tx WHERE tx.id = l.ticket_id AND tx.ticket_number LIKE ?))';
        push @Bind, ( '%' . $Search . '%' ) x 10;
    }

    return ( @Where ? 'WHERE ' . join( ' AND ', @Where ) : '', \@Bind );
}

sub _TraceID {
    my ($Self) = @_;
    my $Random = '';
    if ( open my $FH, '<', '/dev/urandom' ) {
        binmode $FH;
        read $FH, $Random, 32;
        close $FH;
    }
    return sha256_hex( join "\0", $Random, time(), $$, rand(), {} );
}

sub _SensitiveDataRemove {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_CleanText($Value);
    $Value =~ s{(Bearer\s+)[A-Za-z0-9._~+/=-]+}{${1}[REDACTED]}ig;
    $Value =~ s!(["']?(?:password|passwort|client_secret|access_token|refresh_token)["']?\s*[=:]\s*["']?)[^"',&\s}\]]+!${1}[REDACTED]!ig;
    $Value =~ s{(Authorization\s*:\s*(?:Basic|Bearer)\s+)\S+}{${1}[REDACTED]}ig;
    $Value =~ s{(AUTH\s+(?:PLAIN|LOGIN)\s+)\S+}{${1}[REDACTED]}ig;
    $Value =~ s{(AUTHENTICATE\s+XOAUTH2\s+)\S+}{${1}[REDACTED]}ig;
    $Value =~ s{(LOGIN\s+"[^"]*"\s+)"[^"]*"}{${1}"[REDACTED]"}ig;
    return $Value;
}

sub _CleanText {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\r\n?}{\n}g;
    return $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _Unsigned {
    my ( $Self, $Value ) = @_;
    return 0 if !defined $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub _OptionalID {
    my ( $Self, $Value ) = @_;
    # This helper is also used while building DBI bind lists.  A bare
    # C<return> produces an empty list in list context and silently removes a
    # bind value.  Missing optional IDs must therefore be represented by one
    # explicit SQL NULL value.
    return undef if !defined $Value || $Value !~ m{\A\d+\z} || !$Value;
    return 0 + $Value;
}

sub _Date {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_Trim($Value);
    return '' if $Value !~ m{\A\d{4}-\d{2}-\d{2}\z};
    return $Value;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError};
}

sub DESTROY {
    my ($Self) = @_;
    $Self->{DB}->Disconnect() if $Self->{OwnDB} && $Self->{DB};
    return;
}

1;
