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

use Cwd qw(abs_path);
use FindBin;
use File::Spec;

my $QisutuHome = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..' ) );

$ENV{QISUTU_HOME} ||= $QisutuHome;

unshift @INC,
    File::Spec->catdir( $QisutuHome, 'core', 'config' ),
    File::Spec->catdir( $QisutuHome, 'core', 'system' );

main();

sub main {
    require QisutuConfig;
    require QisutuDB;
    require QisutuAdmin;
    require QisutuMail;
    require QisutuCommunicationLog;
    require QisutuRuntimeLock;
    require QisutuTicket;
    require QisutuPostmasterFilter;

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        _Log('Qisutu update is active. Mail fetch skipped.');
        return;
    }

    my $RuntimeLock = QisutuRuntimeLock::SharedAcquire(
        RootPath    => $QisutuHome,
        NonBlocking => 1,
    );
    if ( !$RuntimeLock->{Success} ) {
        if ( $RuntimeLock->{Busy} ) {
            _Log('Qisutu runtime is exclusively locked. Mail fetch skipped.');
            return;
        }
        _Log( $RuntimeLock->{Error} || 'Runtime lock could not be acquired.' );
        return;
    }

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        _Log('Qisutu update became active. Mail fetch skipped.');
        return;
    }

    my $MailFetchLock = QisutuRuntimeLock::ProcessAcquire(
        RootPath    => $QisutuHome,
        Name        => 'mail-fetch',
        NonBlocking => 1,
    );
    if ( !$MailFetchLock->{Success} ) {
        if ( $MailFetchLock->{Busy} ) {
            _Log('Another mail fetch is already running. Mail fetch skipped.');
            return;
        }
        _Log( $MailFetchLock->{Error} || 'Mail-fetch process lock could not be acquired.' );
        return;
    }

    my $Config = QisutuConfig::Load();

    my $DB = QisutuDB->new(
        Config => $Config,
    );

    if ( !$DB->Connect() ) {
        _Log( 'Database connection failed: ' . ( $DB->Error() || '' ) );
        return;
    }

    my $Admin = QisutuAdmin->new(
        Config => $Config,
        DB     => $DB,
    );

    my $Mail = QisutuMail->new(
        Config => $Config,
        DB     => $DB,
    );

    my $CommunicationLog = QisutuCommunicationLog->new(
        Config => $Config,
        DB     => $DB,
    );
    if ( !$CommunicationLog->Cleanup() ) {
        _Log( 'communication-log-error ' . ( $CommunicationLog->Error() || 'cleanup failed' ) );
    }

    my $TicketObject = QisutuTicket->new(
        Config => $Config,
        DB     => $DB,
    );

    my $PostmasterFilter = QisutuPostmasterFilter->new(
        Config => $Config,
        DB     => $DB,
    );
    my $PostmasterTraceLookup = _PostmasterTraceLookup(
        Options => $PostmasterFilter->Options(
            Language => $Config->{Language}->{Default} || 'en',
        ),
    );

    my $MailboxList = $Admin->PostmasterIMAPAccountInboundList();

    for my $Mailbox ( @{$MailboxList} ) {
        my $Result = $Mail->IMAPFetchNewMessages(
            Account => $Mailbox,
            Limit   => 50,
            KeepLogOpen => 1,
        );

        my $CommunicationID = $Result->{CommunicationLogID} || 0;
        if ( $Result->{CommunicationLogError} ) {
            _Log(
                ( $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id} )
                    . ' communication-log-error '
                    . $Result->{CommunicationLogError}
            );
        }

        if ( !$Result->{Success} ) {
            _CheckStatusUpdate(
                DB        => $DB,
                AccountID => $Mailbox->{id},
                Status    => 'error',
                Message   => $Result->{Message} || 'IMAP fetch failed.',
            );

            _Log( join(
                ' ',
                $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id},
                'error',
                $Result->{Message} || 'IMAP fetch failed.',
            ) );

            next;
        }

        my $Created = 0;
        my $Updated = 0;
        my $Ignored = 0;
        my $Filtered = 0;
        my $LastTicketID  = 0;
        my $LastArticleID = 0;
        my $Failed  = $Result->{FetchFailures} || 0;
        my @ErrorMessages = $Failed
            ? ( $Failed . ' IMAP message(s) could not be fetched or parsed' )
            : ();
        my @NotificationMessages;
        my @AttachmentLimitMessages;

        for my $Message ( @{ $Result->{Messages} || [] } ) {
            $CommunicationLog->StepAdd(
                CommunicationID => $CommunicationID,
                Stage   => 'process_message',
                Message => 'Processing IMAP message UID ' . ( $Message->{uid} || '' ),
                Details => 'From: ' . ( $Message->{from_email} || '' )
                    . "\nTo: " . ( $Message->{to_email} || $Mailbox->{email} || '' )
                    . "\nSubject: " . ( $Message->{subject} || '' )
                    . "\nMessage-ID: " . ( $Message->{message_id} || '' )
                    . "\nContent-Type: " . ( $Message->{content_type} || '' )
                    . "\nAccepted attachments: " . scalar( @{ $Message->{attachments} || [] } )
                    . "\nRejected attachments: " . scalar( @{ $Message->{rejected_attachments} || [] } ),
            ) if $CommunicationID;

            my $ExistingTicketID = $TicketObject->TicketIDFromSubject(
                Subject => $Message->{subject},
            );
            my $MessageScope = $ExistingTicketID ? 'follow_up' : 'new';

            if ($CommunicationID) {
                my $Reference = $ExistingTicketID
                    ? _TicketReference( DB => $DB, TicketID => $ExistingTicketID )
                    : '';
                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => $ExistingTicketID ? 'success' : 'info',
                    Stage   => 'ticket_recognition',
                    Message => $ExistingTicketID
                        ? 'Existing ticket recognized: ' . ( $Reference || '#' . $ExistingTicketID )
                        : 'No existing ticket recognized; a new ticket will be created',
                    Details => 'IMAP UID: ' . ( $Message->{uid} || '' )
                        . "\nMessage scope: " . $MessageScope,
                );
            }

            my $FilterResult = $PostmasterFilter->Evaluate(
                Message => $Message,
                Context => {
                    IMAPAccount     => $Mailbox,
                    MessageUID      => $Message->{uid},
                    ExistingTicketID => $ExistingTicketID,
                    MessageScope    => $MessageScope,
                },
            );

            if ( !$FilterResult ) {
                my $Error = $PostmasterFilter->Error() || 'Postmaster filters could not be evaluated';
                $Failed++;
                push @ErrorMessages, $Error;
                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => 'error',
                    Stage   => 'postmaster_filter',
                    Message => 'Postmaster filters failed for UID ' . ( $Message->{uid} || '' ),
                    Details => $Error,
                ) if $CommunicationID;
                $PostmasterFilter->RunLogSave(
                    IMAPAccountID => $Mailbox->{id},
                    MessageUID    => $Message->{uid},
                    MessageScope  => $MessageScope,
                    MessageSubject => $Message->{subject},
                    FromEmail     => $Message->{from_email},
                    TicketID      => $ExistingTicketID,
                    Result        => 'error',
                    ErrorMessage  => $Error,
                );
                next;
            }

            $Filtered++ if $FilterResult->{MatchedCount};
            _PostmasterTraceWrite(
                CommunicationLog => $CommunicationLog,
                CommunicationID  => $CommunicationID,
                FilterResult     => $FilterResult,
                Lookup           => $PostmasterTraceLookup,
                MessageUID       => $Message->{uid},
            ) if $CommunicationID;

            if ( $FilterResult->{Ignore} ) {
                my $DeleteResult = $Mail->IMAPDeleteMessage(
                    Account => $Mailbox,
                    UID     => $Message->{uid},
                    ParentCommunicationLogID => $CommunicationID,
                );
                if ( !$DeleteResult->{Success} ) {
                    $Failed++;
                    my $Error = $DeleteResult->{Message} || 'Ignored IMAP message could not be deleted';
                    push @ErrorMessages, $Error;
                    $PostmasterFilter->RunLogSave(
                        IMAPAccountID => $Mailbox->{id},
                        MessageUID    => $Message->{uid},
                        MessageScope  => $MessageScope,
                        MessageSubject => $Message->{subject},
                        FromEmail     => $Message->{from_email},
                        TicketID      => $ExistingTicketID,
                        Result        => 'error',
                        FilterCount   => $FilterResult->{FilterCount},
                        MatchedCount  => $FilterResult->{MatchedCount},
                        Details       => $FilterResult,
                        ErrorMessage  => $Error,
                    );
                    next;
                }

                $Ignored++;
                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => 'warning',
                    Stage   => 'ignored',
                    Message => 'IMAP message UID ' . ( $Message->{uid} || '' ) . ' ignored by postmaster filter',
                ) if $CommunicationID;
                $PostmasterFilter->RunLogSave(
                    IMAPAccountID => $Mailbox->{id},
                    MessageUID    => $Message->{uid},
                    MessageScope  => $MessageScope,
                    MessageSubject => $Message->{subject},
                    FromEmail     => $Message->{from_email},
                    TicketID      => $ExistingTicketID,
                    Result        => 'ignored',
                    FilterCount   => $FilterResult->{FilterCount},
                    MatchedCount  => $FilterResult->{MatchedCount},
                    Details       => $FilterResult,
                );
                next;
            }

            if ($CommunicationID) {
                my @Accepted = map {
                    ( $_->{Filename} || 'attachment' ) . ' ('
                        . ( $_->{ContentType} || 'application/octet-stream' ) . ', '
                        . ( $_->{ContentSize} || length( $_->{Content} || '' ) ) . ' bytes)'
                } @{ $Message->{attachments} || [] };
                my @Rejected = map {
                    ( $_->{Filename} || 'attachment' ) . ' ('
                        . ( $_->{ContentType} || 'application/octet-stream' ) . ', '
                        . ( $_->{ContentSize} || length( $_->{Content} || '' ) ) . ' bytes)'
                } @{ $Message->{rejected_attachments} || [] };

                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => @Rejected ? 'warning' : 'success',
                    Stage   => 'attachment',
                    Message => scalar(@Accepted) . ' attachment(s) accepted, '
                        . scalar(@Rejected) . ' attachment(s) rejected',
                    Details => join( "\n", map { 'Accepted: ' . $_ } @Accepted,
                        map { 'Rejected: ' . $_ } @Rejected ),
                ) if @Accepted || @Rejected;
            }

            my $TicketID = $TicketObject->TicketCreateFromEmail(
                QueueID         => $Mailbox->{queue_id},
                ExistingTicketID => $ExistingTicketID,
                PostmasterResult => $FilterResult,
                Subject         => $Message->{subject},
                Body            => $Message->{body},
                ContentType     => $Message->{content_type},
                FromName        => $Message->{from_name},
                FromEmail       => $Message->{from_email},
                ToName          => $Message->{to_name},
                ToEmail         => $Message->{to_email} || $Mailbox->{email},
                Cc              => $Message->{cc},
                Attachments     => $Message->{attachments} || [],
                CreatedByUserID => 1,
                ChangedByUserID => 1,
            );

            if ($TicketID) {
                for my $RejectedAttachment ( @{ $Message->{rejected_attachments} || [] } ) {
                    my $Filename = $RejectedAttachment->{Filename} || 'attachment';
                    my $Size     = $RejectedAttachment->{ContentSize} || length( $RejectedAttachment->{Content} || '' );
                    push @AttachmentLimitMessages, $Filename . ' (' . $Size . ' bytes)';
                }

                my $ImportAction = $TicketObject->LastEmailImportAction();
                my $ArticleID    = $TicketObject->LastEmailImportArticleID();
                my $TicketReference = _TicketReference( DB => $DB, TicketID => $TicketID );
                if ( $ImportAction && $ImportAction eq 'updated' ) {
                    $Updated++;
                }
                else {
                    $Created++;
                }
                $LastTicketID  = $TicketID;
                $LastArticleID = $ArticleID || 0;

                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => 'success',
                    Stage   => 'ticket',
                    Message => ( $ImportAction && $ImportAction eq 'updated' ? 'Ticket updated: ' : 'Ticket created: ' )
                        . ( $TicketReference || '#' . $TicketID ),
                    Details => 'IMAP UID: ' . ( $Message->{uid} || '' )
                        . "\nTicket ID: " . $TicketID
                        . "\nArticle ID: " . ( $ArticleID || 0 )
                        . "\nArticle visibility: " . ( $FilterResult->{ArticleVisibility} || 'both' )
                        . "\nSender type: " . ( $FilterResult->{SenderType} || 'customer' ),
                ) if $CommunicationID;

                my $NotificationSummary = $TicketObject->LastAgentNotificationSummary();
                push @NotificationMessages, 'Ticket ' . $TicketID . ': ' . $NotificationSummary if $NotificationSummary;
                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => $TicketObject->LastAgentNotificationError() ? 'warning' : 'success',
                    Stage   => 'notification',
                    Message => $NotificationSummary || 'No agent notification was required',
                    Details => 'Ticket ID: ' . $TicketID,
                ) if $CommunicationID;

                my $DeleteResult = $Mail->IMAPDeleteMessage(
                    Account => $Mailbox,
                    UID     => $Message->{uid},
                    ParentCommunicationLogID => $CommunicationID,
                );

                if ( !$DeleteResult->{Success} ) {
                    $Failed++;
                    my $Error = $DeleteResult->{Message} || 'IMAP message could not be deleted';
                    push @ErrorMessages, $Error;
                    $PostmasterFilter->RunLogSave(
                        IMAPAccountID => $Mailbox->{id},
                        MessageUID    => $Message->{uid},
                        MessageScope  => $MessageScope,
                        MessageSubject => $Message->{subject},
                        FromEmail     => $Message->{from_email},
                        TicketID      => $TicketID,
                        Result        => 'error',
                        FilterCount   => $FilterResult->{FilterCount},
                        MatchedCount  => $FilterResult->{MatchedCount},
                        Details       => $FilterResult,
                        ErrorMessage  => $Error,
                    );
                    next;
                }

                $CommunicationLog->StepAdd(
                    CommunicationID => $CommunicationID,
                    Level   => 'success',
                    Stage   => 'source_cleanup',
                    Message => 'Source message UID ' . ( $Message->{uid} || '' ) . ' deleted from the IMAP mailbox',
                    Details => 'The child connection contains the IMAP STORE and EXPUNGE protocol steps.',
                ) if $CommunicationID;

                $PostmasterFilter->RunLogSave(
                    IMAPAccountID => $Mailbox->{id},
                    MessageUID    => $Message->{uid},
                    MessageScope  => $MessageScope,
                    MessageSubject => $Message->{subject},
                    FromEmail     => $Message->{from_email},
                    TicketID      => $TicketID,
                    Result        => $ImportAction && $ImportAction eq 'updated' ? 'updated' : 'created',
                    FilterCount   => $FilterResult->{FilterCount},
                    MatchedCount  => $FilterResult->{MatchedCount},
                    Details       => $FilterResult,
                );
                next;
            }

            $Failed++;
            my $Error = $TicketObject->Error() || 'Ticket and article could not be created';
            push @ErrorMessages, $Error;
            $CommunicationLog->StepAdd(
                CommunicationID => $CommunicationID,
                Level   => 'error',
                Stage   => 'ticket',
                Message => 'Ticket processing failed for IMAP UID ' . ( $Message->{uid} || '' ),
                Details => $Error,
            ) if $CommunicationID;
            $PostmasterFilter->RunLogSave(
                IMAPAccountID => $Mailbox->{id},
                MessageUID    => $Message->{uid},
                MessageScope  => $MessageScope,
                MessageSubject => $Message->{subject},
                FromEmail     => $Message->{from_email},
                TicketID      => $ExistingTicketID,
                Result        => 'error',
                FilterCount   => $FilterResult->{FilterCount},
                MatchedCount  => $FilterResult->{MatchedCount},
                Details       => $FilterResult,
                ErrorMessage  => $Error,
            );
        }

        my $Status = $Failed ? 'error' : 'ok';
        my $Message = $Created || $Updated || $Ignored || $Filtered || $Failed
            ? $Created . ' ticket(s) created, ' . $Updated . ' ticket(s) updated, ' . $Ignored . ' message(s) ignored, ' . $Filtered . ' message(s) matched filters, ' . $Failed . ' failed'
            : 'No new messages';

        if (@ErrorMessages) {
            $Message .= ': ' . join '; ', @ErrorMessages;
        }

        if (@NotificationMessages) {
            $Message .= '; notifications: ' . join '; ', @NotificationMessages;
        }

        if (@AttachmentLimitMessages) {
            $Message .= '; oversized attachments omitted: ' . join '; ', @AttachmentLimitMessages;
        }

        _CheckStatusUpdate(
            DB        => $DB,
            AccountID => $Mailbox->{id},
            Status    => $Status,
            Message   => $Message,
        );

        if ($CommunicationID) {
            my $LogStatus = $Failed
                ? ( ( $Created || $Updated || $Ignored ) ? 'warning' : 'error' )
                : 'success';
            my $LogFinished = $CommunicationLog->Finish(
                CommunicationID   => $CommunicationID,
                Status            => $LogStatus,
                Summary           => $Message,
                ErrorMessage      => @ErrorMessages ? join( '; ', @ErrorMessages ) : '',
                MessagesFound     => $Result->{MessagesFound} || scalar( @{ $Result->{Messages} || [] } ),
                MessagesProcessed => scalar( @{ $Result->{Messages} || [] } ),
                MessagesCreated   => $Created,
                MessagesUpdated   => $Updated,
                MessagesIgnored   => $Ignored,
                MessagesFailed    => $Failed,
                TicketID          => $LastTicketID,
                ArticleID         => $LastArticleID,
            );
            if ( !$LogFinished ) {
                _Log(
                    ( $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id} )
                        . ' communication-log-error '
                        . ( $CommunicationLog->Error() || 'completion failed' )
                );
            }
        }

        _Log( join(
            ' ',
            $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id},
            $Status,
            $Message,
        ) );
    }

    $DB->Disconnect();

    return;
}

sub _PostmasterTraceLookup {
    my (%Param) = @_;

    my $Options = ref $Param{Options} eq 'HASH' ? $Param{Options} : {};
    my %Source = (
        queue         => $Options->{Queues},
        state         => $Options->{States},
        priority      => $Options->{Priorities},
        owner         => $Options->{Agents},
        responsible   => $Options->{Agents},
        service       => $Options->{Services},
        sla           => $Options->{SLAs},
        customer      => $Options->{Customers},
        customer_user => $Options->{CustomerUsers},
        dynamic_field => $Options->{DynamicFields},
    );
    my %Lookup;
    for my $Type ( keys %Source ) {
        for my $Item ( @{ $Source{$Type} || [] } ) {
            next if ref $Item ne 'HASH' || !$Item->{id};
            $Lookup{$Type}->{ $Item->{id} } = $Item->{label} || $Item->{name} || '#' . $Item->{id};
        }
    }
    return \%Lookup;
}

sub _PostmasterTraceWrite {
    my (%Param) = @_;

    my $Log    = $Param{CommunicationLog};
    my $ID     = $Param{CommunicationID} || 0;
    my $Result = ref $Param{FilterResult} eq 'HASH' ? $Param{FilterResult} : {};
    my $Lookup = ref $Param{Lookup} eq 'HASH' ? $Param{Lookup} : {};
    my $UID    = $Param{MessageUID} || '';
    return if !$Log || !$ID;

    my @Matched = grep { defined $_ && $_ ne '' } @{ $Result->{MatchedFilters} || [] };
    $Log->StepAdd(
        CommunicationID => $ID,
        Level   => @Matched ? 'success' : 'info',
        Stage   => 'postmaster_filter',
        Message => @Matched
            ? scalar(@Matched) . ' postmaster filter(s) matched: ' . join( ', ', @Matched )
            : 'No postmaster filter matched',
        Details => 'IMAP UID: ' . $UID . "\nFilters evaluated: " . ( $Result->{FilterCount} || 0 ),
    );

    for my $Filter ( @{ $Result->{Details} || [] } ) {
        next if ref $Filter ne 'HASH';
        my $Name = $Filter->{filter_name} || '#' . ( $Filter->{filter_id} || 0 );
        my @Condition;
        for my $Condition ( @{ $Filter->{conditions} || [] } ) {
            next if ref $Condition ne 'HASH';
            my $Field = $Condition->{field_name} || '-';
            $Field .= ' (' . $Condition->{field_argument} . ')' if $Condition->{field_argument};
            my $Actual = join( ' | ', map { _TraceValue($_) } @{ $Condition->{values} || [] } );
            push @Condition,
                ( $Condition->{matched} ? '[matched] ' : '[not matched] ' )
                . $Field . ' ' . ( $Condition->{operator} || '' )
                . ' "' . _TraceValue( $Condition->{match_value} ) . '"'
                . ( $Actual ne '' ? '; actual: "' . $Actual . '"' : '' );
        }
        my $ScopeMatch = exists $Filter->{scope_match} ? $Filter->{scope_match} : 1;
        my $Matched    = $Filter->{matched} ? 1 : 0;
        $Log->StepAdd(
            CommunicationID => $ID,
            Level   => $Matched ? 'success' : 'info',
            Stage   => 'filter_check',
            Message => !$ScopeMatch
                ? 'Postmaster filter skipped because its message scope does not apply: ' . $Name
                : $Matched
                    ? 'Postmaster filter matched: ' . $Name
                    : 'Postmaster filter did not match: ' . $Name,
            Details => join( "\n", @Condition )
                . ( $Filter->{stopped} ? "\nFurther filter processing stopped after this match." : '' ),
        );

        my $ActionDetails = $Filter->{action_details} || [];
        if ( !@{$ActionDetails} && @{ $Filter->{actions} || [] } ) {
            $ActionDetails = [ map { { result => $_ } } @{ $Filter->{actions} } ];
        }
        for my $Action ( @{$ActionDetails} ) {
            next if ref $Action ne 'HASH';
            my ( $Text, $Details ) = _PostmasterActionText( Action => $Action, Lookup => $Lookup );
            $Log->StepAdd(
                CommunicationID => $ID,
                Level   => 'success',
                Stage   => ( ( $Action->{action_type} || '' ) =~ m{\Adynamic_field} ? 'dynamic_field' : 'filter_action' ),
                Message => 'Filter "' . $Name . '": ' . $Text,
                Details => $Details,
            );
        }
    }
    return 1;
}

sub _PostmasterActionText {
    my (%Param) = @_;

    my $Action = $Param{Action} || {};
    my $Lookup = $Param{Lookup} || {};
    my $Type   = $Action->{action_type} || '';
    my $ID     = $Action->{target_id} || 0;
    my $Value  = defined $Action->{action_value} ? $Action->{action_value} : '';
    my %Name = (
        queue=>'Queue', state=>'Status', priority=>'Priority', owner=>'Owner', responsible=>'Responsible',
        service=>'Service', sla=>'SLA', customer=>'Customer', customer_user=>'Customer user',
        dynamic_field=>'Dynamic field', dynamic_field_clear=>'Dynamic field', pending_minutes=>'Pending time',
        article_visibility=>'Article visibility', sender_type=>'Sender type', ignore=>'Ignore message',
        title_set=>'Set title', title_prepend=>'Prepend title', title_append=>'Append title',
        owner_clear=>'Clear owner', responsible_clear=>'Clear responsible', service_clear=>'Clear service/SLA',
        customer_clear=>'Clear customer',
    );
    my $LookupType = $Type eq 'dynamic_field_clear' ? 'dynamic_field' : $Type;
    my $Target = $ID && $Lookup->{$LookupType} ? $Lookup->{$LookupType}->{$ID} : '';
    $Target ||= $ID ? '#' . $ID : '';

    my $Text = $Name{$Type} || $Type || ( $Action->{result} || 'Action applied' );
    if ( $Type =~ m{\A(?:queue|state|priority|owner|responsible|service|sla|customer|customer_user)\z} ) {
        $Text .= ' = ' . $Target;
    }
    elsif ( $Type eq 'dynamic_field' ) {
        $Text .= ' "' . $Target . '" = "' . _TraceValue($Value) . '"';
    }
    elsif ( $Type eq 'dynamic_field_clear' ) {
        $Text .= ' "' . $Target . '" cleared';
    }
    elsif ( $Value ne '' ) {
        $Text .= ' = "' . _TraceValue($Value) . '"';
    }

    my $Details = 'Action type: ' . ( $Type || '-' );
    $Details .= "\nTarget ID: " . $ID if $ID;
    $Details .= "\nResolved target: " . $Target if $Target;
    $Details .= "\nResult: " . ( $Action->{result} || '' ) if $Action->{result};
    return ( $Text, $Details );
}

sub _TicketReference {
    my (%Param) = @_;
    return '' if !$Param{DB} || !$Param{TicketID};
    my $Ticket = $Param{DB}->SelectRow(
        'SELECT ticket_number FROM ticket WHERE id = ? LIMIT 1',
        $Param{TicketID},
    );
    return $Ticket && $Ticket->{ticket_number} ? $Ticket->{ticket_number} : '';
}

sub _TraceValue {
    my ($Value) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{[\r\n\t]+}{ }g;
    $Value =~ s{\s+}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return length($Value) > 300 ? substr( $Value, 0, 297 ) . '...' : $Value;
}

sub _Log {
    my ($Message) = @_;
    my @Now = localtime();
    my $Stamp = sprintf '%04d-%02d-%02d %02d:%02d:%02d',
        $Now[5] + 1900, $Now[4] + 1, $Now[3], $Now[2], $Now[1], $Now[0];
    print $Stamp . ' ' . ( $Message || '' ) . "\n";
    return 1;
}

sub _CheckStatusUpdate {
    my (%Param) = @_;

    my $DB        = $Param{DB};
    my $AccountID = $Param{AccountID} || 0;
    my $Status    = $Param{Status} || '';
    my $Message   = $Param{Message} || '';

    return if !$DB || !$AccountID;

    $DB->Do(
        'UPDATE postmaster_imap_account
         SET last_check_at = NOW(),
             last_check_status = ?,
             last_check_message = ?,
             changed_by_user_id = 1
         WHERE id = ?',
        $Status,
        $Message,
        $AccountID,
    );

    return 1;
}
