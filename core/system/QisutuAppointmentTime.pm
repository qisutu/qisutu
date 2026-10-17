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

package QisutuAppointmentTime;
use strict;
use warnings;
use utf8;
use POSIX qw(strftime tzset);
use Time::Local qw(timegm timelocal);

sub ZoneValid {
    my ($Zone) = @_;
    return $Zone && $Zone =~ m{\A[A-Za-z_+-]+(?:/[A-Za-z0-9_+-]+)*\z}
        && -f "/usr/share/zoneinfo/$Zone" ? 1 : 0;
}
sub UTC { return strftime('%Y-%m-%d %H:%M:%S', gmtime($_[0])); }
sub Epoch {
    my ($Value) = @_;
    return if !$Value || $Value !~ /\A(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d)(?::(\d\d))?\z/;
    my ($Y,$M,$D,$H,$N,$S) = ($1,$2,$3,$4,$5,$6||0);
    return if $Y < 1970 || $Y > 2099;
    my $E = eval { timegm($S,$N,$H,$D,$M-1,$Y) };
    return if !defined $E || UTC($E) ne sprintf('%04d-%02d-%02d %02d:%02d:%02d',$Y,$M,$D,$H,$N,$S);
    return $E;
}
sub LocalEpoch {
    my ($Value,$Zone) = @_;
    return if !ZoneValid($Zone) || !defined Epoch($Value);
    $Value =~ tr/T/ /;
    $Value .= ':00' if length($Value)==16;
    my ($Y,$M,$D,$H,$N,$S) = $Value =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
    my $E;
    { local $ENV{TZ}=$Zone; tzset(); $E=eval { timelocal($S,$N,$H,$D,$M-1,$Y) };
      $E=undef if defined($E) && strftime('%Y-%m-%d %H:%M:%S',localtime($E)) ne $Value; }
    tzset();
    return $E;
}
sub Local {
    my ($Epoch,$Zone) = @_;
    return if !ZoneValid($Zone);
    my $Value;
    { local $ENV{TZ}=$Zone; tzset(); $Value=strftime('%Y-%m-%d %H:%M:%S',localtime($Epoch)); }
    tzset(); return $Value;
}
sub Occurrences {
    my ($Data,$Through) = @_;
    my $Start = Epoch($Data->{start_local});
    my $End = Epoch($Data->{end_local});
    die "Start und Ende sind ungültig.\n" if !defined($Start) || !defined($End) || $End <= $Start;
    die "Die Zeitzone ist ungültig.\n" if !ZoneValid($Data->{timezone});
    die "Diese Uhrzeit existiert wegen der Zeitumstellung nicht.\n"
        if !defined LocalEpoch($Data->{start_local},$Data->{timezone}) || !defined LocalEpoch($Data->{end_local},$Data->{timezone});
    my $R = $Data->{repeat} || {};
    my $Freq = $R->{frequency} || 'none';
    die "Ungültige Wiederholung.\n" if $Freq !~ /\A(?:none|daily|weekly|monthly|yearly)\z/;
    my $Interval = $R->{interval} || 1;
    die "Ungültiges Wiederholungsintervall.\n" if $Interval !~ /^\d+$/ || $Interval>365;
    my $Count = $R->{count} || 0;
    die "Ungültige Anzahl.\n" if $Count !~ /^\d+$/ || $Count>10000;
    my $Until = $R->{until} ? Epoch($R->{until}.' 23:59:59') : undef;
    die "Ungültiges Serienende.\n" if $R->{until} && (!defined($Until) || $Until<$Start);
    my @S = gmtime($Start);
    my $StartDay = $Start - $S[2]*3600-$S[1]*60-$S[0];
    my $ThroughEpoch = Epoch($Through.' 23:59:59');
    die "Ungültiger Zeitraum.\n" if !defined($ThroughEpoch);
    my %Days = map { $_ => 1 } @{ $R->{weekdays} || [] };
    %Days = (($S[6] || 7) => 1) if !keys %Days;
    die "Ungültiger Wochentag.\n" if grep { !/^[1-7]$/ } keys %Days;
    my $Nth = $R->{monthly_mode} || 'date';
    die "Ungültige Monatsregel.\n" if $Nth !~ /\A(?:date|weekday|last)\z/;
    my @Result; my $Sequence=0;
    for (my $Day=$StartDay; $Day<=$ThroughEpoch; $Day+=86400) {
        last if defined($Until) && $Day>$Until;
        my @D=gmtime($Day); my $Delta=int(($Day-$StartDay)/86400);
        my $Week=int(($Delta+(($S[6]||7)-1))/7);
        my $Month=($D[5]-$S[5])*12+$D[4]-$S[4];
        my $Match=$Delta==0;
        if ($Freq eq 'daily') { $Match=$Delta%$Interval==0; }
        elsif ($Freq eq 'weekly') { $Match=$Week%$Interval==0 && $Days{$D[6]||7}; }
        elsif ($Freq eq 'monthly') {
            my @Next=gmtime($Day+7*86400);
            $Match=$Month%$Interval==0 && ($Nth eq 'date' ? $D[3]==$S[3] :
                $D[6]==$S[6] && ($Nth eq 'last' ? $Next[4]!=$D[4] : int(($D[3]-1)/7)==int(($S[3]-1)/7)));
        }
        elsif ($Freq eq 'yearly') { $Match=($D[5]-$S[5])%$Interval==0 && $D[4]==$S[4] && $D[3]==$S[3]; }
        next if !$Match;
        my $LocalStart=UTC($Day+($Start-$StartDay));
        my $LocalEnd=UTC($Day+($End-$StartDay));
        my $A=LocalEpoch($LocalStart,$Data->{timezone}); my $B=LocalEpoch($LocalEnd,$Data->{timezone});
        # A non-existing DST wall time is omitted, never silently shifted.
        next if !defined($A) || !defined($B) || $B<=$A;
        push @Result,{ sequence_no=>$Sequence++,start_utc=>UTC($A),end_utc=>UTC($B),start_local=>$LocalStart,end_local=>$LocalEnd };
        last if $Freq eq 'none' || ($Count && $Sequence >= $Count);
        die "Die Serie ist zu umfangreich.\n" if $Sequence>47500;
    }
    return \@Result;
}
1;
