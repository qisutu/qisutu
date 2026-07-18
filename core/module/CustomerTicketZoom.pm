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

package CustomerTicketZoom;

use strict;
use warnings;
use utf8;
use Time::Local qw(timelocal);
use QisutuCMDB;

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
    my $TicketID = $Request->{TicketID} || 0;
    my $Ticket;
    my $Articles = [];
    my $ArticleCreateError = '';
    my $TicketObject = $Self->_TicketObject();
    my $TicketFormObject = $Self->_TicketFormObject();
    my $CMDBObject = QisutuCMDB->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );

    if ( $TicketObject && ( $Request->{Step} || '' ) eq 'CustomerArticleCreate' ) {
        my $Body    = $Request->{Body} || '';
        my $Subject = $Request->{Subject} || '';

        my $TicketForSubmit = $TicketObject->TicketGet(
            TicketID  => $TicketID,
            User      => $User,
            Language  => $Language,
        );

        if ( !$TicketForSubmit ) {
            $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
        }

        if ( !$ArticleCreateError && !$Self->_BodyHasVisibleContent( Body => $Body ) ) {
            $ArticleCreateError = 'Translate:TicketArticleBodyRequired';
        }

        if ( !$ArticleCreateError ) {
            $Subject ||= $Self->_DefaultReplySubject(
                TicketObject => $TicketObject,
                TicketID     => $TicketID,
                User         => $User,
                Language     => $Language,
            );
        }

        my ( $ToName, $ToEmail ) = $Self->_QueueAddress( TicketID => $TicketID );
        my $FromName = $Self->_UserName( User => $User );
        my $FromEmail = $User->{email} || '';

        if ( !$ArticleCreateError ) {
            $Self->{DB}->BeginWork() || do {
                $ArticleCreateError = 'Translate:TicketArticleCreateFailed';
            };
        }

        if ( !$ArticleCreateError ) {
            my $ArticleID = $TicketObject->ArticleCreate(
                TicketID        => $TicketID,
                User            => $User,
                Subject         => $Subject,
                Body            => $Body,
                Channel         => 'web',
                SenderType      => 'customer',
                FromName        => $FromName,
                FromEmail       => $FromEmail,
                ToName          => $ToName,
                ToEmail         => $ToEmail,
                ContentType     => 'text/html',
                Visibility      => 'both',
                Language        => $Language,
                CreatedByUserID => $User->{user_account_id},
                ChangedByUserID => $User->{user_account_id},
            );

            if ( !$ArticleID ) {
                $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
                $Self->{DB}->Rollback();
            }
        }

        if ( !$ArticleCreateError ) {
            if ( $Self->{DB}->Commit() ) {
                return {
                    Redirect => 'index.pl?Page=CustomerTicketZoom&TicketID=' . $TicketID,
                };
            }

            $ArticleCreateError = 'Translate:TicketArticleCreateFailed';
            $Self->{DB}->Rollback();
        }
    }

    if ($TicketObject) {
        $Ticket = $TicketObject->TicketGet(
            TicketID  => $TicketID,
            User      => $User,
            Language  => $Language,
        );
    }

    if ( !$Ticket ) {
        return {
            Template => 'CustomerTicketZoom.tt',
            Data     => {
                PageTitle          => 'Translate:TicketZoomTitle',
                ProgramTitle       => 'Translate:TicketZoomTitle',
                ProgramDescription => 'Translate:TicketZoomDescription',
                TicketFound        => 0,
                TicketListURL      => 'index.pl?Page=CustomerTicketList',
            },
        };
    }

    $Articles = $TicketObject->ArticleList(
        TicketID => $Ticket->{id},
        User     => $User,
        Language => $Language,
    );

    my $ArticleIndex = 0;
    my $ArticleCount = scalar @{$Articles};

    for my $Article ( @{$Articles} ) {
        $ArticleIndex++;

        $Article->{created_at_display} = $Self->_DateTimeFormat(
            DateTime => $Article->{created_at},
            Language => $Language,
        );

        $Article->{article_open_class} = $ArticleIndex == $ArticleCount
            ? 'qisutu-ticket-article-open'
            : '';
    }

    my $ArticleEmptyClass = $ArticleCount ? 'qisutu-hidden' : '';
    my $ArticleCreateErrorClass = $ArticleCreateError ? '' : 'qisutu-hidden';
    my $ArticleReplyFormClass = $ArticleCreateError ? '' : 'qisutu-hidden';
    my $TicketFormInformationHTML = $TicketFormObject ? $TicketFormObject->SubmissionDisplayHTML(
        TicketID => $Ticket->{id},
        Language => $Language,
    ) : '';
    my $TicketCMDBHTML = $CMDBObject->CustomerTicketSummaryHTML(
        TicketID => $Ticket->{id},
        User     => $User,
        Language => $Language,
    );

    return {
        Template => 'CustomerTicketZoom.tt',
        Data     => {
            PageTitle          => $Ticket->{ticket_number} . ' - ' . $Ticket->{title},
            ProgramTitle       => $Ticket->{ticket_number},
            ProgramDescription => $Ticket->{title},
            TicketFound        => 1,
            TicketListURL      => 'index.pl?Page=CustomerTicketList',

            TicketID            => $Ticket->{id},
            TicketNumber        => $Ticket->{ticket_number},
            TicketTitle         => $Ticket->{title},
            TicketQueue         => $Ticket->{queue_full_name} || $Ticket->{queue_name},
            TicketState         => $Ticket->{state_name_display},
            TicketPriority      => $Ticket->{priority_name_display} || $Ticket->{priority_name},
            TicketAge           => $Self->_AgeFormat(
                DateTime => $Ticket->{created_at},
                Language => $Language,
            ),
            TicketCustomer      => $Ticket->{customer_name} || '-',
            TicketCustomerUser  => $Ticket->{customer_user_name} || '-',
            TicketCustomerEmail => $Ticket->{customer_user_email} || '-',
            TicketCreatedAt     => $Self->_DateTimeFormat(
                DateTime => $Ticket->{created_at},
                Language => $Language,
            ),
            TicketChangedAt     => $Self->_DateTimeFormat(
                DateTime => $Ticket->{changed_at},
                Language => $Language,
            ),
            TicketFormInformationHTML => $TicketFormInformationHTML,
            HasTicketFormInformation  => $TicketFormInformationHTML ? 1 : 0,
            TicketCMDBHTML            => $TicketCMDBHTML,
            HasTicketCMDB             => $TicketCMDBHTML ? 1 : 0,

            ArticleList              => $Articles,
            ArticleCount             => $ArticleCount,
            ArticleEmptyClass        => $ArticleEmptyClass,
            ArticleFormAction        => 'index.pl',
            ArticleCreateError       => $ArticleCreateError,
            ArticleCreateErrorClass  => $ArticleCreateErrorClass,
            ArticleReplyFormClass    => $ArticleReplyFormClass,
            DefaultArticleMode       => 'customer_reply',
            ReplyFormDefaultTitle    => 'Translate:TicketReplyCustomer',
            ReplySubmitDefaultLabel  => 'Translate:TicketArticleSubmit',
        },
    };
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        require QisutuTicket;
        1;
    };

    if ( !$Loaded ) {
        return;
    }

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );
}

sub _TicketFormObject {
    my ($Self) = @_;

    return if !$Self->{DB};
    my $Loaded = eval {
        require QisutuTicketForm;
        1;
    };
    return if !$Loaded;

    return QisutuTicketForm->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );
}

sub _UserName {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $Firstname = $User->{firstname} || '';
    my $Lastname  = $User->{lastname}  || '';
    my $Login     = $User->{login}     || '';
    my $Name      = join ' ', grep {$_} ( $Firstname, $Lastname );

    if ( !$Name ) {
        $Name = $Login;
    }

    return $Name;
}

sub _QueueAddress {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;

    return ( '', '' ) if !$Self->{DB} || !$TicketID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            se.name,
            se.email
         FROM ticket t
         INNER JOIN ticket_queue q
            ON q.id = t.queue_id
         LEFT JOIN system_email se
            ON se.id = q.system_email_id
           AND se.active = 1
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    return ( '', '' ) if !$Row;

    return (
        $Row->{name}  || '',
        $Row->{email} || '',
    );
}

sub _DefaultReplySubject {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Param{TicketObject};
    my $TicketID     = $Param{TicketID} || 0;
    my $User         = $Param{User} || {};
    my $Language     = $Param{Language} || 'en';

    my $Ticket = $TicketObject
        ? $TicketObject->TicketGet( TicketID => $TicketID, User => $User )
        : undef;

    my $TicketNumber = $Ticket ? ( $Ticket->{ticket_number} || $TicketID ) : $TicketID;

    return $Language eq 'de'
        ? 'Antwort zu ' . $TicketNumber
        : 'Reply to ' . $TicketNumber;
}

sub _BodyHasVisibleContent {
    my ( $Self, %Param ) = @_;

    my $Body = $Param{Body} || '';

    $Body =~ s{<style\b[^>]*>.*?</style>}{}gis;
    $Body =~ s{<script\b[^>]*>.*?</script>}{}gis;
    $Body =~ s{<[^>]+>}{}g;
    $Body =~ s{&nbsp;}{ }gi;
    $Body =~ s{&#160;}{ }g;
    $Body =~ s{\s+}{ }g;
    $Body =~ s{\A\s+}{};
    $Body =~ s{\s+\z}{};

    return $Body ? 1 : 0;
}

sub _DateTimeFormat {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    return '' if !$DateTime;

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );

        if ( $Language eq 'de' ) {
            return "$Day.$Month.$Year $Hour:$Minute:$Second";
        }

        return "$Year-$Month-$Day $Hour:$Minute:$Second";
    }

    return $DateTime;
}

sub _AgeFormat {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    return '-' if !$DateTime;

    if ( $DateTime !~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        return '-';
    }

    my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );
    my $CreatedEpoch;

    eval {
        $CreatedEpoch = timelocal( $Second, $Minute, $Hour, $Day, $Month - 1, $Year - 1900 );
        1;
    } || return '-';

    my $AgeSeconds = time() - $CreatedEpoch;

    if ( $AgeSeconds < 0 ) {
        $AgeSeconds = 0;
    }

    my $Minutes = int( $AgeSeconds / 60 );
    my $Hours   = int( $Minutes / 60 );
    my $Days    = int( $Hours / 24 );

    if ( $Language eq 'de' ) {
        return $Days . ( $Days == 1 ? ' Tag' : ' Tage' ) if $Days;
        return $Hours . ( $Hours == 1 ? ' Stunde' : ' Stunden' ) if $Hours;
        return $Minutes . ( $Minutes == 1 ? ' Minute' : ' Minuten' );
    }

    return $Days . ( $Days == 1 ? ' day' : ' days' ) if $Days;
    return $Hours . ( $Hours == 1 ? ' hour' : ' hours' ) if $Hours;
    return $Minutes . ( $Minutes == 1 ? ' minute' : ' minutes' );
}

1;
