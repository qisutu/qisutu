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
    require QisutuRuntimeLock;
    require QisutuTicket;
    require QisutuPostmasterFilter;

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        print "Qisutu update is active. Mail fetch skipped.\n";
        return;
    }

    my $RuntimeLock = QisutuRuntimeLock::SharedAcquire(
        RootPath    => $QisutuHome,
        NonBlocking => 1,
    );
    if ( !$RuntimeLock->{Success} ) {
        if ( $RuntimeLock->{Busy} ) {
            print "Qisutu runtime is exclusively locked. Mail fetch skipped.\n";
            return;
        }
        print( ( $RuntimeLock->{Error} || 'Runtime lock could not be acquired.' ) . "\n" );
        return;
    }

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        print "Qisutu update became active. Mail fetch skipped.\n";
        return;
    }

    my $Config = QisutuConfig::Load();

    my $DB = QisutuDB->new(
        Config => $Config,
    );

    if ( !$DB->Connect() ) {
        print "Database connection failed: " . ( $DB->Error() || '' ) . "\n";
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

    my $TicketObject = QisutuTicket->new(
        Config => $Config,
        DB     => $DB,
    );

    my $PostmasterFilter = QisutuPostmasterFilter->new(
        Config => $Config,
        DB     => $DB,
    );

    my $MailboxList = $Admin->PostmasterIMAPAccountInboundList();

    for my $Mailbox ( @{$MailboxList} ) {
        my $Result = $Mail->IMAPFetchNewMessages(
            Account => $Mailbox,
            Limit   => 50,
        );

        if ( !$Result->{Success} ) {
            _CheckStatusUpdate(
                DB        => $DB,
                AccountID => $Mailbox->{id},
                Status    => 'error',
                Message   => $Result->{Message} || 'IMAP fetch failed.',
            );

            print join(
                ' ',
                $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id},
                'error',
                $Result->{Message} || 'IMAP fetch failed.',
            ) . "\n";

            next;
        }

        my $Created = 0;
        my $Updated = 0;
        my $Ignored = 0;
        my $Filtered = 0;
        my $Failed  = 0;
        my @ErrorMessages;
        my @NotificationMessages;
        my @AttachmentLimitMessages;

        for my $Message ( @{ $Result->{Messages} || [] } ) {
            my $ExistingTicketID = $TicketObject->TicketIDFromSubject(
                Subject => $Message->{subject},
            );
            my $MessageScope = $ExistingTicketID ? 'follow_up' : 'new';

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

            if ( $FilterResult->{Ignore} ) {
                my $DeleteResult = $Mail->IMAPDeleteMessage(
                    Account => $Mailbox,
                    UID     => $Message->{uid},
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

                my $NotificationSummary = $TicketObject->LastAgentNotificationSummary();
                push @NotificationMessages, 'Ticket ' . $TicketID . ': ' . $NotificationSummary if $NotificationSummary;

                my $DeleteResult = $Mail->IMAPDeleteMessage(
                    Account => $Mailbox,
                    UID     => $Message->{uid},
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

                my $ImportAction = $TicketObject->LastEmailImportAction();
                if ( $ImportAction && $ImportAction eq 'updated' ) {
                    $Updated++;
                }
                else {
                    $Created++;
                }

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

        print join(
            ' ',
            $Mailbox->{name} || $Mailbox->{email} || $Mailbox->{id},
            $Status,
            $Message,
        ) . "\n";
    }

    $DB->Disconnect();

    return;
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
