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

package QisutuAddonUI;

use strict;
use warnings;
use utf8;

use QisutuAddonAPI;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config => $Param{Config} || {},
        DB     => $Param{DB},
        Output => $Param{Output},
    };
    bless $Self, $Class;
    return $Self;
}

sub Render {
    my ( $Self, %Param ) = @_;
    my $Slot = $Param{Slot} || '';
    return '' if $Slot !~ m{\A(?:page|dashboard|ticket\.zoom|admin)\.(?:before|after)\z};
    my $Program = $Param{Program} || {};
    my $ProgramName = $Program->{Name} || '';
    my $AccountType = ( $Param{User} || {} )->{account_type} || '';
    my @Definition = sort {
        ( $a->{order} || 1000 ) <=> ( $b->{order} || 1000 )
            || ( $a->{package_identifier} || '' ) cmp ( $b->{package_identifier} || '' )
    } grep {
        ref $_ eq 'HASH' && ( $_->{slot} || '' ) eq $Slot
    } @{ ( $Self->{Config}->{AddonRuntime} || {} )->{UISlots} || [] };

    my $HTML = '';
    for my $Definition (@Definition) {
        if ( $Definition->{program} && $Definition->{program} ne $ProgramName ) {
            next;
        }
        if ( ref $Definition->{access_types} eq 'ARRAY' && @{ $Definition->{access_types} } ) {
            my %Allowed = map { $_ => 1 } @{ $Definition->{access_types} };
            next if !$Allowed{$AccountType};
        }
        my $Class = $Definition->{class} || '';
        my $Method = $Definition->{method} || 'Render';
        next if $Class !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || $Method !~ m{\A[A-Za-z][A-Za-z0-9_]*\z}
            || !eval "require $Class; 1;";
        my $API = QisutuAddonAPI->new(
            Config     => $Self->{Config},
            DB         => $Self->{DB},
            Identifier => $Definition->{package_identifier},
        );
        my $Handler = eval {
            $Class->new(
                Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output},
                API => $API, Definition => $Definition,
            );
        };
        next if !$Handler || !$Handler->can($Method);
        my $Result = eval {
            $Handler->$Method(
                Slot    => $Slot,
                Program => $Program,
                User    => $Param{User} || {},
                Data    => $Param{Data} || {},
                API     => $API,
            );
        };
        next if !$Result || ref $Result ne 'HASH';
        my $Template = $Result->{Template} || '';
        next if $Template !~ m{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*[.]tt\z}
            || $Template =~ m{(?:\A|/)\.\.(?:/|\z)};
        my %Data = (
            %{ ref $Param{Data} eq 'HASH' ? $Param{Data} : {} },
            %{ ref $Result->{Data} eq 'HASH' ? $Result->{Data} : {} },
        );
        my $Part = $Self->{Output}->RenderSingle( Template => $Template, Data => \%Data );
        next if !defined $Part;
        $HTML .= $Part;
        last if length($HTML) > 1024 * 1024;
    }
    return substr( $HTML, 0, 1024 * 1024 );
}

1;
