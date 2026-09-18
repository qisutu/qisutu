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

package QisutuAddonEvent;

use strict;
use warnings;
use utf8;

use JSON::PP;

use QisutuAddonAPI;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        JSON      => JSON::PP->new->canonical(1)->utf8(1),
        LastError => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub Emit {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Event = lc( $Param{Event} || '' );
    my $Source = lc( $Param{Source} || 'qisutu.core' );
    my $Payload = ref $Param{Payload} eq 'HASH' ? $Param{Payload} : {};
    return $Self->_Error('invalid add-on event name')
        if $Event !~ m{\A[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)+\z} || length($Event) > 190;
    return $Self->_Error('invalid add-on event source')
        if $Source !~ m{\A[a-z][a-z0-9_-]*(?:\.[a-z0-9_-]+)+\z} || length($Source) > 190;

    my $PayloadJSON = eval { $Self->{JSON}->encode($Payload) };
    return $Self->_Error('add-on event payload is not JSON compatible') if !defined $PayloadJSON;
    return $Self->_Error('add-on event payload is too large') if length($PayloadJSON) > 1024 * 1024;

    my $Subscribers = ( $Self->{Config}->{AddonRuntime} || {} )->{EventSubscribers} || [];
    for my $Subscriber ( @{$Subscribers} ) {
        next if ref $Subscriber ne 'HASH';
        next if !$Self->_EventMatches( Pattern => $Subscriber->{event}, Event => $Event );
        if ( ( $Subscriber->{mode} || 'async' ) eq 'sync' ) {
            $Self->_Run(
                Subscriber => $Subscriber,
                Event      => $Event,
                Source     => $Source,
                Payload    => $Payload,
            );
            next;
        }
        return $Self->_Error('add-on event database is unavailable') if !$Self->{DB};
        my $OK = $Self->{DB}->Do(
            'INSERT INTO addon_event_queue (
                package_identifier, event_name, event_source, handler_class,
                handler_method, payload_json, status, available_at
             ) VALUES (?, ?, ?, ?, ?, ?, "pending", NOW())',
            $Subscriber->{package_identifier}, $Event, $Source,
            $Subscriber->{class}, $Subscriber->{method} || 'Handle', $PayloadJSON,
        );
        return $Self->_Error( $Self->{DB}->Error() || 'add-on event could not be queued' ) if !$OK;
    }
    return 1;
}

sub ProcessNext {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    return 0 if !$Self->{DB};
    my $Worker = $Param{Worker} || 'qisutu-daemon';

    $Self->{DB}->Do(
        'UPDATE addon_event_queue
         SET status = "pending", locked_by = NULL, locked_at = NULL,
             available_at = NOW(), last_error = "Recovered after interrupted event processing"
         WHERE status = "processing" AND locked_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE)'
    );
    my $Row = $Self->{DB}->SelectRow(
        'SELECT e.* FROM addon_event_queue e
         INNER JOIN addon_package p ON p.package_identifier = e.package_identifier
         WHERE e.status = "pending" AND e.available_at <= NOW()
           AND p.active = 1 AND p.status = "installed"
         ORDER BY e.id LIMIT 1'
    );
    return 0 if !$Row;
    my $Claimed = $Self->{DB}->Do(
        'UPDATE addon_event_queue
         SET status = "processing", locked_by = ?, locked_at = NOW(), attempts = attempts + 1
         WHERE id = ? AND status = "pending"',
        $Worker, $Row->{id},
    );
    return 0 if !$Claimed;
    $Row->{attempts} = 1 + ( $Row->{attempts} || 0 );

    my $Payload = eval { $Self->{JSON}->decode( $Row->{payload_json} || '{}' ) };
    my ( $Success, $Result, $Error );
    if ( ref $Payload eq 'HASH' ) {
        $Result = $Self->_Run(
            Subscriber => {
                package_identifier => $Row->{package_identifier},
                class              => $Row->{handler_class},
                method             => $Row->{handler_method},
            },
            Event   => $Row->{event_name},
            Source  => $Row->{event_source},
            Payload => $Payload,
        );
        $Success = $Result ? 1 : 0;
        $Error = $Self->{LastError} if !$Success;
    }
    else {
        $Error = 'stored add-on event payload is invalid';
    }

    if ($Success) {
        my $ResultJSON = eval { $Self->{JSON}->encode( ref $Result eq 'HASH' ? $Result : { success => 1 } ) } || '{}';
        $Self->{DB}->Do(
            'UPDATE addon_event_queue
             SET status = "completed", result_json = ?, last_error = NULL,
                 locked_by = NULL, locked_at = NULL, finished_at = NOW()
             WHERE id = ?',
            $ResultJSON, $Row->{id},
        );
        return 1;
    }

    $Error = substr( $Error || 'add-on event handler failed', 0, 4000 );
    if ( $Row->{attempts} < 3 ) {
        my $Delay = $Row->{attempts} * 60;
        $Self->{DB}->Do(
            'UPDATE addon_event_queue
             SET status = "pending", last_error = ?, locked_by = NULL, locked_at = NULL,
                 available_at = DATE_ADD(NOW(), INTERVAL ? SECOND)
             WHERE id = ?',
            $Error, $Delay, $Row->{id},
        );
    }
    else {
        $Self->{DB}->Do(
            'UPDATE addon_event_queue
             SET status = "failed", last_error = ?, locked_by = NULL, locked_at = NULL,
                 finished_at = NOW()
             WHERE id = ?',
            $Error, $Row->{id},
        );
    }
    $Self->{LastError} = $Error;
    return;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub Cleanup {
    my ($Self) = @_;
    return 0 if !$Self->{DB};
    $Self->{DB}->Do(
        'DELETE FROM addon_event_queue
         WHERE (status = "completed" AND finished_at < DATE_SUB(NOW(), INTERVAL 30 DAY))
            OR (status = "failed" AND finished_at < DATE_SUB(NOW(), INTERVAL 180 DAY))'
    );
    return 1;
}

sub _Run {
    my ( $Self, %Param ) = @_;
    my $Subscriber = $Param{Subscriber} || {};
    my $Class = $Subscriber->{class} || '';
    my $Method = $Subscriber->{method} || 'Handle';
    return $Self->_Error('invalid add-on event handler')
        if $Class !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
        || $Method !~ m{\A[A-Za-z][A-Za-z0-9_]*\z};
    if ( !eval "require $Class; 1;" ) {
        return $Self->_Error( $@ || 'add-on event handler could not be loaded' );
    }
    my $API = QisutuAddonAPI->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Identifier => $Subscriber->{package_identifier},
    );
    my $Handler = eval {
        $Class->new(
            Config => $Self->{Config}, DB => $Self->{DB}, API => $API,
            Definition => $Subscriber,
        );
    };
    return $Self->_Error( $@ || 'add-on event handler could not be created' ) if !$Handler;
    return $Self->_Error('add-on event handler method is missing') if !$Handler->can($Method);
    my $Result = eval {
        $Handler->$Method(
            Event   => $Param{Event},
            Source  => $Param{Source},
            Payload => $Param{Payload},
            API     => $API,
        );
    };
    return $Self->_Error( $@ || 'add-on event handler returned no success result' ) if !$Result;
    return $Result;
}

sub _EventMatches {
    my ( $Self, %Param ) = @_;
    my $Pattern = lc( $Param{Pattern} || '' );
    my $Event   = lc( $Param{Event} || '' );
    return 1 if $Pattern eq $Event;
    if ( $Pattern =~ m{\A(.+)[.]\*\z} ) {
        return index( $Event, $1 . '.' ) == 0 ? 1 : 0;
    }
    return;
}

sub _Error {
    my ( $Self, $Message ) = @_;
    $Self->{LastError} = $Message || 'add-on event error';
    return;
}

1;
