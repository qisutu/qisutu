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

package QisutuAppointment;
use strict;
use warnings;
use utf8;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Encode qw(encode);
use QisutuAppointmentTime;
use QisutuPermission;
use QisutuTicket;
use QisutuSecurity;

sub new { my ($Class,%P)=@_; return bless { %P, LastError=>'' },$Class; }
sub Error { return $_[0]->{LastError} || ''; }
sub _Fail { $_[0]->{LastError}=$_[1]; return; }
sub _JSON { return JSON::PP->new->canonical->encode($_[0]); }
sub _Data { my $D=eval { JSON::PP->new->decode($_[0]||'{}') }; return ref($D) eq 'HASH' ? $D : {}; }
sub _ID { return defined($_[0]) && $_[0] =~ /\A[1-9]\d{0,17}\z/ ? 0+$_[0] : 0; }
sub _Now { return QisutuAppointmentTime::UTC(time); }
sub _UserID { return ($_[0]->{account_type}||'') eq 'agent' ? _ID($_[0]->{user_account_id}) : 0; }
sub _Permission { return QisutuPermission->new(Config=>$_[0]->{Config},DB=>$_[0]->{DB}); }
sub _Ticket { return QisutuTicket->new(Config=>$_[0]->{Config},DB=>$_[0]->{DB},Permission=>$_[0]->_Permission); }
sub _Do { my ($S,@A)=@_; my $R=$S->{DB}->Do(@A); die($S->{DB}->Error()||'Datenbankfehler') if !$R; return $R; }
sub _Locked {
    my ($S,$Code)=@_; $S->{LastError}='';
    my $Lock=$S->{DB}->SelectRow('SELECT GET_LOCK(?, 10) AS acquired','qisutu-appointments');
    return $S->_Fail('Der Kalender wird gerade aktualisiert. Bitte erneut versuchen.') if !$Lock || !$Lock->{acquired};
    my $R=eval { $Code->() }; my $Error=$@;
    $S->{DB}->SelectRow('SELECT RELEASE_LOCK(?) AS released','qisutu-appointments');
    if ($Error) { $Error =~ s/ at [^\n]+ line \d+\.?\s*\z//; return $S->_Fail($Error); }
    return $R;
}
sub _Transaction {
    my ($S,$Code)=@_;
    die 'Transaktion konnte nicht gestartet werden.' if !$S->{DB}->BeginWork;
    my $R=eval { $Code->() }; my $Error=$@;
    if ($Error || !$R) { $S->{DB}->Rollback; die($Error||$S->Error||'Speichern fehlgeschlagen.'); }
    if (!$S->{DB}->Commit) { $S->{DB}->Rollback; die 'Speichern fehlgeschlagen.'; }
    return $R;
}
sub CalendarList {
    my ($S,$U)=@_; my $UID=_UserID($U); return [] if !$UID;
    my $Admin=$S->_Permission->UserIsAdmin(UserID=>$UID);
    my $Rows=$S->{DB}->SelectAll('SELECT * FROM appointment_calendar WHERE active=1 ORDER BY name,id') || [];
    my $Shares=$S->{DB}->SelectAll('SELECT s.* FROM appointment_share s WHERE (s.subject_type="user" AND s.subject_id=?) OR
        (s.subject_type="group" AND s.subject_id IN (SELECT m.user_group_id FROM user_group_member m INNER JOIN user_group g ON g.id=m.user_group_id AND g.active=1 WHERE m.user_account_id=? AND m.active=1))',$UID,$UID)||[];
    my %Role; for my $R (@$Shares) { $Role{$R->{calendar_id}}=$R->{role} if $R->{role}>($Role{$R->{calendar_id}}||0); }
    my @Out;
    for my $C (@$Rows) {
        $C->{role}=($C->{owner_user_id}==$UID || $Admin) ? 4 : ($Role{$C->{id}}||0);
        next if !$C->{role};
        $C->{shares}=$S->{DB}->SelectAll('SELECT subject_type,subject_id,role FROM appointment_share WHERE calendar_id=?',$C->{id})||[] if $C->{role}==4;
        push @Out,$C;
    }
    return \@Out;
}
sub Role {
    my ($S,$U,$CID)=@_; return 0 if !_ID($CID);
    my ($C)=grep { $_->{id}==$CID } @{$S->CalendarList($U)}; return $C ? $C->{role} : 0;
}
sub CalendarSave {
    my ($S,$U,$D)=@_; my $UID=_UserID($U); return $S->_Fail('Zugriff verweigert.') if !$UID;
    return $S->_Locked(sub { $S->_Transaction(sub {
        my $ID=_ID($D->{id});
        if ($ID) {
            die 'Zugriff verweigert.' if $S->Role($U,$ID)<4;
            my $C=$S->{DB}->SelectRow('SELECT * FROM appointment_calendar WHERE id=?',$ID);
            die 'Der Kalender wurde zwischenzeitlich geändert. Bitte neu laden.' if ($D->{version}||0)!=$C->{version};
        }
        my $Name=$D->{name}||''; $Name =~ s/^\s+|\s+$//g;
        die 'Bitte einen Kalendernamen angeben.' if !$Name || length($Name)>160;
        die 'Ungültige Farbe.' if ($D->{color}||'') !~ /^#[a-fA-F0-9]{6}$/;
        die 'Ungültiger Kalendertyp.' if ($D->{kind}||'') !~ /\A(?:personal|team|company)\z/;
        if ($ID) { $S->_Do('UPDATE appointment_calendar SET name=?,color=?,kind=?,version=version+1 WHERE id=?',$Name,$D->{color},$D->{kind},$ID); }
        else { $S->_Do('INSERT INTO appointment_calendar (name,color,kind,owner_user_id) VALUES (?,?,?,?)',$Name,$D->{color},$D->{kind},$UID); $ID=$S->{DB}->LastInsertID('appointment_calendar'); }
        $S->_Do('DELETE FROM appointment_share WHERE calendar_id=?',$ID);
        die 'Zu viele Freigaben.' if ref($D->{shares}) ne 'ARRAY' || @{$D->{shares}}>500;
        for my $Share (@{$D->{shares}}) {
            my $Type=$Share->{subject_type}||''; my $SID=_ID($Share->{subject_id}); my $Role=$Share->{role}||0;
            die 'Ungültige Freigabe.' if !$SID || $Type !~ /\A(?:user|group)\z/ || $Role !~ /\A[1-4]\z/;
            my $SQL=$Type eq 'user' ? 'SELECT id FROM user_account WHERE id=? AND account_type="agent" AND is_active=1 AND is_system_user=0' : 'SELECT id FROM user_group WHERE id=? AND active=1';
            die 'Die Freigabe ist nicht mehr verfügbar.' if !$S->{DB}->SelectRow($SQL,$SID);
            $S->_Do('INSERT INTO appointment_share (calendar_id,subject_type,subject_id,role) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE role=VALUES(role)',$ID,$Type,$SID,$Role);
        }
        return {id=>$ID};
    }) });
}
sub Bootstrap {
    my ($S,$U)=@_; return if !_UserID($U);
    my $DB=$S->{DB};
    return {
        user_id=>_UserID($U), calendars=>$S->CalendarList($U),
        agents=>$DB->SelectAll('SELECT id,CONCAT(firstname," ",lastname) AS name,email FROM user_account WHERE account_type="agent" AND is_active=1 AND is_system_user=0 ORDER BY firstname,lastname')||[],
        groups=>$DB->SelectAll('SELECT id,name FROM user_group WHERE active=1 ORDER BY name')||[],
        queues=>$S->_Queues($U),
        priorities=>$DB->SelectAll('SELECT id,name FROM ticket_priority WHERE active=1 ORDER BY sort_order,id')||[],
        customers=>$DB->SelectAll('SELECT id,name FROM customer WHERE active=1 ORDER BY name')||[],
        contacts=>$DB->SelectAll('SELECT cu.id,cu.customer_id,CONCAT(ua.firstname," ",ua.lastname," (",ua.email,")") AS name FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id AND ua.is_active=1 INNER JOIN customer c ON c.id=cu.customer_id AND c.active=1 WHERE cu.active=1 ORDER BY ua.firstname,ua.lastname')||[],
        timezone=>'Europe/Berlin', now=>_Now(),
    };
}
sub _Queues {
    my ($S,$U)=@_; my $IDs=$S->_Permission->QueueIDList(UserID=>_UserID($U),Permission=>'ticket.create');
    return [] if !$IDs || !@$IDs;
    return $S->{DB}->SelectAll('SELECT id,full_name AS name FROM ticket_queue WHERE active=1 AND id IN ('.join(',',map {'?'} @$IDs).') ORDER BY full_name',@$IDs)||[];
}
sub _RawEvent {
    my ($S,$ID)=@_; return if !_ID($ID);
    return $S->{DB}->SelectRow('SELECT e.*,c.active AS calendar_active FROM appointment_event e INNER JOIN appointment_calendar c ON c.id=e.calendar_id WHERE e.id=?',$ID);
}
sub _Visible {
    my ($S,$U,$E,$D)=@_; my $UID=_UserID($U); return 0 if !$UID || !$E->{calendar_active};
    return 1 if $UID==$E->{owner_user_id};
    my $Invited=$S->{DB}->SelectRow('SELECT id FROM appointment_invitee WHERE event_id=? AND user_id=?',$E->{id},$UID);
    return 1 if $Invited;
    return !$D->{private} && $S->Role($U,$E->{calendar_id})>=2 ? 1 : 0;
}
sub _Editable {
    my ($S,$U,$E,$D)=@_; my $Role=$S->Role($U,$E->{calendar_id});
    return $Role>=3 && $S->_Visible($U,$E,$D) ? 1 : 0;
}
sub EventGet {
    my ($S,$U,$ID,$OID)=@_; my $E=$S->_RawEvent($ID); return $S->_Fail('Termin nicht verfügbar.') if !$E;
    my $D=_Data($E->{data_json});
    return $S->_Fail('Zugriff verweigert.') if !$S->_Visible($U,$E,$D);
    my $Occurrence;
    if (_ID($OID)) {
        $Occurrence=$S->{DB}->SelectRow('SELECT * FROM appointment_occurrence WHERE id=? AND event_id=?',$OID,$ID);
        return $S->_Fail('Termin nicht verfügbar.') if !$Occurrence;
        $D=_Data($Occurrence->{data_json}) if $Occurrence->{data_json};
        my $Base=_Data($E->{data_json});
        for my $K (qw(private participants send_invites repeat)) { $D->{$K}=$Base->{$K}; }
        $D->{start_local}=QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($Occurrence->{start_utc}),$D->{timezone});
        $D->{end_local}=QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($Occurrence->{end_utc}),$D->{timezone});
        $D->{ticket_error}=$Occurrence->{ticket_error} if $S->_Editable($U,$E,$D);
    }
    my $Result={%$D,id=>0+$E->{id},calendar_id=>0+$E->{calendar_id},version=>0+$E->{version},owner_user_id=>0+$E->{owner_user_id},editable=>$S->_Editable($U,$E,$D),active=>0+$E->{active},
        occurrence_id=>$Occurrence ? 0+$Occurrence->{id} : 0,
        cancelled=>$Occurrence ? 0+$Occurrence->{cancelled} : 0,
        invitees=>$S->{DB}->SelectAll('SELECT id,user_id,email,name,response FROM appointment_invitee WHERE event_id=? ORDER BY name,email',$ID)||[],
        attachments=>$S->{DB}->SelectAll('SELECT id,filename,content_size FROM appointment_attachment WHERE event_id=? ORDER BY id',$ID)||[],
    };
    $Result->{delivery_errors}=$S->_Editable($U,$E,$D) ? ($S->{DB}->SelectAll('SELECT recipient_email,last_error FROM appointment_delivery WHERE event_id=? AND status="pending" AND last_error IS NOT NULL ORDER BY id DESC LIMIT 10',$ID)||[]) : [];
    my @Tickets=grep {$_} ($D->{ticket_id},$Occurrence ? $Occurrence->{ticket_id} : 0);
    $Result->{tickets}=[];
    for my $TID (@Tickets) { my $T=$S->_Ticket->TicketGet(User=>$U,TicketID=>$TID); push @{$Result->{tickets}},{id=>$T->{id},number=>$T->{ticket_number},title=>$T->{title}} if $T; }
    return $Result;
}
sub _Validate {
    my ($S,$U,$D,$Old)=@_;
    die 'Ungültige Termindaten.' if ref($D) ne 'HASH';
    my %Clean;
    for my $Key (qw(title description location meeting_url type start_local end_local timezone recipient_email ticket_title ticket_body)) {
        $Clean{$Key}=defined($D->{$Key}) && !ref($D->{$Key}) ? "$D->{$Key}" : '';
        die 'Der Text ist zu lang.' if length($Clean{$Key})>($Key =~ /^(description|ticket_body)$/ ? 100000 : 1000);
    }
    $Clean{title}=~s/^\s+|\s+$//g;
    die 'Bitte einen Titel angeben.' if !$Clean{title} || length($Clean{title})>500;
    die 'Ungültiger Besprechungslink.' if $Clean{meeting_url} && $Clean{meeting_url} !~ m{\Ahttps?://[^\s<>"']+\z}i;
    die 'Ungültige Terminart.' if $Clean{type} !~ /\A(?:meeting|callback|visit|maintenance|absence|holiday|other)\z/;
    for my $Key (qw(all_day private auto_ticket send_invites reminder_email reminder_app)) { $Clean{$Key}=$D->{$Key} ? 1 : 0; }
    for my $Key (qw(customer_id customer_user_id ticket_id queue_id priority_id ticket_owner_id)) { $Clean{$Key}=_ID($D->{$Key}); }
    my $CID=$Clean{customer_id}; my $CUID=$Clean{customer_user_id};
    if ($CID) { die 'Kunde nicht verfügbar.' if !$S->{DB}->SelectRow('SELECT id FROM customer WHERE id=? AND active=1',$CID); }
    if ($CUID) {
        my $C=$S->{DB}->SelectRow('SELECT customer_id FROM customer_user WHERE id=? AND active=1',$CUID);
        die 'Ansprechpartner nicht verfügbar.' if !$C || ($CID && $CID!=$C->{customer_id}); $Clean{customer_id}=$C->{customer_id};
    }
    if (exists $D->{ticket_number}) {
        my $Number=$D->{ticket_number}||''; $Number =~ s/^\s+|\s+$//g;
        if ($Number) {
            die 'Ungültige Ticketnummer.' if ref($D->{ticket_number}) || length($Number)>100;
            my $T=$S->_Ticket->TicketGet(User=>$U,TicketNumber=>$Number);
            die 'Ticket nicht gefunden oder kein Zugriff.' if !$T;
            $Clean{ticket_id}=$T->{id};
        } else { $Clean{ticket_id}=0; }
    }
    if ($Clean{ticket_id}) { die 'Kein Zugriff auf das Ticket.' if !$S->_Ticket->TicketGet(User=>$U,TicketID=>$Clean{ticket_id}); }
    $Clean{ticket_lead}=defined $D->{ticket_lead} ? $D->{ticket_lead} : 0;
    die 'Ungültiger Vorlauf.' if ref($Clean{ticket_lead}) || $Clean{ticket_lead} !~ /^\d+$/ || $Clean{ticket_lead}>525600;
    $Clean{ticket_dynamic_fields}={};
    if (ref($D->{ticket_dynamic_fields}) eq 'HASH') {
        for my $Key (keys %{$D->{ticket_dynamic_fields}}) {
            next if $Key !~ /\ATicketDynamicField_\d+\z/;
            my $Value=$D->{ticket_dynamic_fields}->{$Key};
            die 'Ungültiges dynamisches Feld.' if ref($Value) && (ref($Value) ne 'ARRAY' || grep {ref($_)} @$Value);
            $Clean{ticket_dynamic_fields}->{$Key}=$Value;
        }
    }
    if ($Clean{auto_ticket}) {
        die 'Bitte eine berechtigte Queue für die Ticketerstellung auswählen.' if !$Clean{queue_id} || !$S->_Permission->QueueAccessCheck(UserID=>_UserID($U),QueueID=>$Clean{queue_id},Permission=>'ticket.create');
        die 'Bitte eine Priorität auswählen.' if !$S->{DB}->SelectRow('SELECT id FROM ticket_priority WHERE id=? AND active=1',$Clean{priority_id});
        if ($Clean{ticket_owner_id}) {
            die 'Besitzer nicht verfügbar.' if !$S->{DB}->SelectRow('SELECT id FROM user_account WHERE id=? AND account_type="agent" AND is_active=1 AND is_system_user=0',$Clean{ticket_owner_id});
            die 'Der Besitzer hat keinen Zugriff auf die Queue.' if !$S->_Permission->QueueAccessCheck(UserID=>$Clean{ticket_owner_id},QueueID=>$Clean{queue_id},Permission=>'ticket.view');
        }
        if ($Clean{recipient_email}) { die 'Ungültige E-Mail-Adresse.' if !_Email($Clean{recipient_email}); }
        require QisutuDynamicField;
        my $Fields=QisutuDynamicField->new(Config=>$S->{Config},DB=>$S->{DB});
        die 'Bitte die Pflichtfelder der ausgewählten Queue ausfüllen.' if !$Fields->TicketValueValidate(QueueID=>$Clean{queue_id},Request=>$Clean{ticket_dynamic_fields});

    }
    $Clean{repeat}=ref($D->{repeat}) eq 'HASH' ? $D->{repeat} : {frequency=>'none'};
    die 'Ungültige Wochentage.' if exists($Clean{repeat}->{weekdays}) && ref($Clean{repeat}->{weekdays}) ne 'ARRAY';
    $Clean{participants}=ref($D->{participants}) eq 'ARRAY' ? $D->{participants} : [];
    die 'Zu viele Teilnehmer.' if @{$Clean{participants}}>100;
    my @Participants; my %Seen;
    for my $P (@{$Clean{participants}}) {
        die 'Ungültiger Teilnehmer.' if ref($P) ne 'HASH';
        my $ID=_ID($P->{user_id}); my $Email=lc($P->{email}||''); my $Name=$P->{name}||$Email;
        if ($ID) {
            my $A=$S->{DB}->SelectRow('SELECT email,CONCAT(firstname," ",lastname) AS name FROM user_account WHERE id=? AND account_type="agent" AND is_active=1 AND is_system_user=0',$ID);
            die 'Teilnehmer nicht verfügbar.' if !$A;
            ($Email,$Name)=(lc($A->{email}||''),$A->{name});
        }
        die 'Ungültige Teilnehmeradresse.' if !_Email($Email) || ref($Name) || length($Name)>200;
        push @Participants,{user_id=>$ID,email=>$Email,name=>$Name} if !$Seen{$Email}++;
    }
    $Clean{participants}=\@Participants;
    $Clean{reminders}=ref($D->{reminders}) eq 'ARRAY' ? $D->{reminders} : [];
    die 'Höchstens fünf Erinnerungen sind möglich.' if @{$Clean{reminders}}>5;
    my %Rem; for (@{$Clean{reminders}}) { die 'Ungültige Erinnerung.' if ref($_) || !/^\d+$/ || $_>525600; $Rem{0+$_}=1; }
    $Clean{reminders}=[sort {$b<=>$a} keys %Rem];
    my $Start=QisutuAppointmentTime::LocalEpoch($Clean{start_local},$Clean{timezone});
    my $End=QisutuAppointmentTime::LocalEpoch($Clean{end_local},$Clean{timezone});
    die 'Bitte gültige Anfangs- und Endzeiten angeben (Zeitumstellung beachten).' if !defined($Start) || !defined($End) || $End<=$Start;
    die 'Ein Termin darf höchstens 366 Tage dauern.' if $End-$Start>366*86400;
    if ($Clean{all_day}) { die 'Ganztägige Termine beginnen um 00:00 und enden um 00:00 am Folgetag.' if $Clean{start_local}!~/[ T]00:00(?::00)?$/ || $Clean{end_local}!~/[ T]00:00(?::00)?$/; }
    my $Through=substr(QisutuAppointmentTime::UTC(($Start>time?$Start:time)+400*86400),0,10);
    QisutuAppointmentTime::Occurrences(\%Clean,$Through);
    $Clean{ticket_author_id}=$Clean{auto_ticket} ? _UserID($U) : 0;
    return \%Clean;
}
sub _Email { return defined($_[0]) && !ref($_[0]) && length($_[0])<=254 && $_[0] =~ /\A[A-Z0-9.!#\$%&'*+\/=?^_`{|}~-]+\@[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?\.[A-Z]{2,}\z/i; }
sub Save {
    my ($S,$U,$Input,$Uploads)=@_; return $S->_Fail('Zugriff verweigert.') if !_UserID($U);
    return $S->_Locked(sub { $S->_Transaction(sub {
        my $ID=_ID($Input->{id}); my $E=$ID ? $S->_RawEvent($ID) : undef;
        my $CID=_ID($Input->{calendar_id});
        die 'Keine Schreibberechtigung für diesen Kalender.' if $S->Role($U,$CID)<3;
        if ($ID) {
            die 'Termin nicht verfügbar.' if !$E || !$E->{active};
            die 'Zugriff verweigert.' if !$S->_Editable($U,$E,_Data($E->{data_json}));
            die 'Der Termin wurde zwischenzeitlich geändert. Bitte neu laden.' if ($Input->{version}||0)!=$E->{version};
        }
        my $D=$S->_Validate($U,$Input,$E);
        my $OID=_ID($Input->{occurrence_id}); my $Single=$ID && $OID && ($Input->{scope}||'') eq 'one';
        my $Occurrence;
        if ($Single) {
            $Occurrence=$S->{DB}->SelectRow('SELECT * FROM appointment_occurrence WHERE id=? AND event_id=?',$OID,$ID);
            die 'Termin nicht verfügbar.' if !$Occurrence || $Occurrence->{cancelled};
            die 'Ein Einzeltermin kann nicht in einen anderen Kalender verschoben werden.' if $CID!=$E->{calendar_id};
            # Attendance, visibility and attachments belong to the entire series.
            my $Base=_Data($E->{data_json});
            for my $K (qw(participants send_invites private repeat)) { $D->{$K}=$Base->{$K}; }
            my $Start=QisutuAppointmentTime::LocalEpoch($D->{start_local},$D->{timezone});
            my $End=QisutuAppointmentTime::LocalEpoch($D->{end_local},$D->{timezone});
            $S->_Do('UPDATE appointment_occurrence SET start_utc=?,end_utc=?,data_json=?,is_exception=1,ticket_due_at=?,ticket_error=NULL,ticket_retry_at=NULL WHERE id=?',QisutuAppointmentTime::UTC($Start),QisutuAppointmentTime::UTC($End),_JSON($D),$D->{auto_ticket}?QisutuAppointmentTime::UTC($Start-$D->{ticket_lead}*60):undef,$OID);
            $S->_Do('UPDATE appointment_event SET version=version+1,changed_at=? WHERE id=?',_Now(),$ID);
            $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE occurrence_id=? AND kind="reminder" AND status="pending"',$OID);
        }
        elsif ($ID) {
            $S->_Do('UPDATE appointment_event SET calendar_id=?,data_json=?,version=version+1,changed_at=? WHERE id=?',$CID,_JSON($D),_Now(),$ID);
            $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE event_id=? AND status="pending"',$ID);
            $S->_Expand($ID,undef,1);
        }
        else {
            $S->_Do('INSERT INTO appointment_event (calendar_id,owner_user_id,data_json,created_at,changed_at) VALUES (?,?,?,?,?)',$CID,_UserID($U),_JSON($D),_Now(),_Now());
            $ID=$S->{DB}->LastInsertID('appointment_event'); $S->_Expand($ID,undef,0);
        }
        $S->_AttachmentsSave($ID,$Uploads||[],$Input->{remove_attachments}||[]);
        $S->_InviteesSave($ID,$D,$Single ? 'update' : $E ? 'update' : 'invite',$OID);
        $S->_Reminders($ID);
        return {id=>$ID,occurrence_id=>$OID};
    }) });
}
sub _Expand {
    my ($S,$ID,$Through,$Replace)=@_; my $E=$S->_RawEvent($ID); return if !$E || !$E->{active};
    my $D=_Data($E->{data_json});
    my $Start=QisutuAppointmentTime::LocalEpoch($D->{start_local},$D->{timezone});
    $Through ||= substr(QisutuAppointmentTime::UTC(($Start>time?$Start:time)+400*86400),0,10);
    return if !$Replace && ($E->{generated_until}||'') ge $Through;
    my $List=QisutuAppointmentTime::Occurrences($D,$Through);
    # Keep occurrence identities and generated tickets across changes to a series.
    my %Present;
    for my $O (@$List) {
        $Present{$O->{sequence_no}}=1;
        my $Due=$D->{auto_ticket} && $O->{start_utc} ge $E->{created_at} ? QisutuAppointmentTime::UTC(QisutuAppointmentTime::Epoch($O->{start_utc})-$D->{ticket_lead}*60) : undef;
        $S->_Do('INSERT INTO appointment_occurrence (event_id,sequence_no,start_utc,end_utc,ticket_due_at) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE
            start_utc=IF(is_exception=0,VALUES(start_utc),start_utc),end_utc=IF(is_exception=0,VALUES(end_utc),end_utc),
            ticket_due_at=IF(is_exception=0,VALUES(ticket_due_at),ticket_due_at),cancelled=IF(is_exception=0,0,cancelled)',$ID,$O->{sequence_no},$O->{start_utc},$O->{end_utc},$Due);
    }
    if ($Replace) {
        my $Rows=$S->{DB}->SelectAll('SELECT id,sequence_no FROM appointment_occurrence WHERE event_id=? AND is_exception=0',$ID)||[];
        for my $O (@$Rows) { $S->_Do('UPDATE appointment_occurrence SET cancelled=1,ticket_due_at=NULL WHERE id=?',$O->{id}) if !$Present{$O->{sequence_no}}; }
    }
    $S->_Do('UPDATE appointment_event SET generated_until=? WHERE id=?',$Through,$ID);
    return 1;
}
sub Cancel {
    my ($S,$U,$Input)=@_;
    return $S->_Locked(sub { $S->_Transaction(sub {
        my $E=$S->_RawEvent(_ID($Input->{id})); die 'Termin nicht verfügbar.' if !$E;
        my $D=_Data($E->{data_json}); die 'Zugriff verweigert.' if !$S->_Editable($U,$E,$D);
        die 'Der Termin wurde zwischenzeitlich geändert.' if ($Input->{version}||0)!=$E->{version};
        my $Single=($Input->{scope}||'') eq 'one' && _ID($Input->{occurrence_id});
        if ($Single) {
            my $O=$S->{DB}->SelectRow('SELECT * FROM appointment_occurrence WHERE id=? AND event_id=?',$Single,$E->{id}); die 'Termin nicht verfügbar.' if !$O;
            $D->{start_local}=QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{start_utc}),$D->{timezone});
            $S->_Do('UPDATE appointment_occurrence SET cancelled=1,is_exception=1,ticket_due_at=NULL WHERE id=?',$Single);
            $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE occurrence_id=? AND status="pending"',$Single);
        } else {
            $S->_Do('UPDATE appointment_event SET active=0 WHERE id=?',$E->{id});
            $S->_Do('UPDATE appointment_occurrence SET cancelled=1,ticket_due_at=NULL WHERE event_id=?',$E->{id});
            $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE event_id=? AND status="pending"',$E->{id});
        }
        $S->_Do('UPDATE appointment_event SET version=version+1,changed_at=? WHERE id=?',_Now(),$E->{id});
        $S->_InviteesSave($E->{id},$D,'cancel',$Single||0);
        return {id=>$E->{id}};
    }) });
}
sub List {
    my ($S,$U,$P)=@_; my $UID=_UserID($U); return [] if !$UID;
    return $S->_Fail('Kein Zugriff auf das Ticket.') if $P->{ticket_id} && !$S->_Ticket->TicketGet(User=>$U,TicketID=>$P->{ticket_id});
    my $From=QisutuAppointmentTime::Epoch(($P->{from}||'').' 00:00:00');
    my $To=QisutuAppointmentTime::Epoch(($P->{to}||'').' 23:59:59');
    return $S->_Fail('Der Zeitraum ist ungültig oder länger als ein Jahr.') if !defined($From)||!defined($To)||$To<$From||$To-$From>367*86400;
    my %Calendar=map {$_->{id}=>$_} @{$S->CalendarList($U)};
    my $Needs=$S->{DB}->SelectAll('SELECT e.id,e.calendar_id FROM appointment_event e WHERE e.active=1 AND (e.generated_until IS NULL OR e.generated_until<?)', $P->{to})||[];
    if (@$Needs) {
        my $Expanded=$S->_Locked(sub {
            for my $N (@$Needs) {
                next if !$Calendar{$N->{calendar_id}} && !$S->{DB}->SelectRow('SELECT id FROM appointment_invitee WHERE event_id=? AND user_id=?',$N->{id},$UID);
                $S->_Expand($N->{id},$P->{to},0);
            }
            return 1;
        });
        return if !$Expanded;
    }

    my $Rows=$S->{DB}->SelectAll('SELECT o.*,e.calendar_id,e.owner_user_id,e.data_json AS master_json,e.version,e.active,c.color,c.name AS calendar_name,c.active AS calendar_active
        FROM appointment_occurrence o INNER JOIN appointment_event e ON e.id=o.event_id INNER JOIN appointment_calendar c ON c.id=e.calendar_id
        WHERE e.active=1 AND c.active=1 AND o.cancelled=0 AND (?=1 OR (o.start_utc<=? AND o.end_utc>=?)) ORDER BY o.start_utc,o.id',$P->{ticket_id}?1:0,QisutuAppointmentTime::UTC($To+86400),QisutuAppointmentTime::UTC($From-86400))||[];
    my @Out;
    my $Invites=$S->{DB}->SelectAll('SELECT event_id,response FROM appointment_invitee WHERE user_id=?',$UID)||[]; my %Invited=map {$_->{event_id}=>$_->{response}} @$Invites;
    for my $O (@$Rows) {
        next if !$Calendar{$O->{calendar_id}} && !exists($Invited{$O->{event_id}});
        my $D=_Data($O->{data_json}||$O->{master_json});
        my $Master=_Data($O->{master_json});
        $D->{private}=$Master->{private};
        my $E={%$O,id=>$O->{event_id}};
        my $Details=$O->{owner_user_id}==$UID || exists($Invited{$O->{event_id}}) || (!$D->{private} && ($Calendar{$O->{calendar_id}}->{role}||0)>=2);
        my $Mine=$O->{owner_user_id}==$UID || (exists($Invited{$O->{event_id}}) && $Invited{$O->{event_id}} ne 'declined');
        next if $P->{mine} && !$Mine;
        if ($P->{ticket_id}) {
            next if !$Details || ($D->{ticket_id}||0)!=$P->{ticket_id} && ($O->{ticket_id}||0)!=$P->{ticket_id};
        }
        my $TID=$Details?($O->{ticket_id}||$D->{ticket_id}||0):0;
        my $T=$TID ? $S->_Ticket->TicketGet(User=>$U,TicketID=>$TID) : undef;
        push @Out,{
            id=>0+$O->{event_id},occurrence_id=>0+$O->{id},calendar_id=>0+$O->{calendar_id},version=>0+$O->{version},
            title=>$Details?$D->{title}:'Belegt', description=>$Details?$D->{description}:'',start=>$O->{start_utc}.'Z',end=>$O->{end_utc}.'Z',
            start_local=>QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{start_utc}),$D->{timezone}),
            end_local=>QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{end_utc}),$D->{timezone}),
            timezone=>$D->{timezone},all_day=>$D->{all_day}?1:0,color=>$O->{color},calendar_name=>$O->{calendar_name},
            readable=>$Details?1:0,editable=>$Details && ($Calendar{$O->{calendar_id}}->{role}||0)>=3?1:0,
            type=>$Details?$D->{type}:'busy',private=>$D->{private}?1:0,mine=>$Mine?1:0,
            customer_id=>$Details?$D->{customer_id}:0,queue_id=>$Details?$D->{queue_id}:0,
            participant_ids=>$Details?[$O->{owner_user_id},map {$_->{user_id}||0} @{$D->{participants}||[]}]:[],
            ticket_id=>$T?$T->{id}:0,ticket_number=>$T?$T->{ticket_number}:'',
            auto_ticket=>$Details&&$D->{auto_ticket}?1:0,has_error=>$Details&&$O->{ticket_error}?1:0,
            recurrence=>$Details?($D->{repeat}->{frequency}||'none'):'none',
        };
    }
    return \@Out;
}
sub Conflicts {
    my ($S,$U,$D)=@_; my $Start=QisutuAppointmentTime::LocalEpoch($D->{start_local},$D->{timezone}); my $End=QisutuAppointmentTime::LocalEpoch($D->{end_local},$D->{timezone});
    return [] if !defined($Start)||!defined($End);
    my %IDs=map { _ID($_->{user_id})=>1 } @{ref($D->{participants}) eq 'ARRAY'?$D->{participants}:[]}; $IDs{_UserID($U)}=1; delete $IDs{0};
    my $Rows=$S->{DB}->SelectAll('SELECT o.event_id,e.owner_user_id FROM appointment_occurrence o INNER JOIN appointment_event e ON e.id=o.event_id INNER JOIN appointment_calendar c ON c.id=e.calendar_id WHERE e.active=1 AND c.active=1 AND o.cancelled=0 AND o.start_utc<? AND o.end_utc>? AND e.id<>?',QisutuAppointmentTime::UTC($End),QisutuAppointmentTime::UTC($Start),_ID($D->{id}))||[];
    my %Busy;
    for my $O (@$Rows) {
        $Busy{$O->{owner_user_id}}=1 if $IDs{$O->{owner_user_id}};
        my $Guests=$S->{DB}->SelectAll('SELECT user_id FROM appointment_invitee WHERE event_id=? AND response<>"declined"',$O->{event_id})||[];
        for (@$Guests) { $Busy{$_->{user_id}}=1 if $_->{user_id} && $IDs{$_->{user_id}}; }
    }
    return [sort {$a<=>$b} keys %Busy];
}
sub _AttachmentsSave {
    my ($S,$ID,$Uploads,$Remove)=@_;
    die 'Ungültige Anhänge.' if ref($Remove) ne 'ARRAY' || ref($Uploads) ne 'ARRAY';
    for my $A (@$Remove) { $S->_Do('DELETE FROM appointment_attachment WHERE id=? AND event_id=?',_ID($A),$ID); }
    my $Size=$S->{DB}->SelectRow('SELECT COUNT(*) AS n,COALESCE(SUM(content_size),0) AS bytes FROM appointment_attachment WHERE event_id=?',$ID)||{};
    die 'Höchstens 20 Anhänge pro Termin.' if ($Size->{n}||0)+@$Uploads>20;
    for my $A (@$Uploads) {
        my $Name=$A->{Filename}||'Anhang'; $Name=~s{.*[\\/]}{}; $Name=~s/[\x00-\x1f\x7f]//g;
        my $Bytes=length($A->{Content}||''); $Size->{bytes}+=$Bytes;
        die 'Anhänge dürfen zusammen höchstens 25 MB groß sein.' if $Size->{bytes}>25*1024*1024;
        $S->_Do('INSERT INTO appointment_attachment (event_id,filename,content_type,content_size,content) VALUES (?,?,?,?,?)',$ID,substr($Name,0,255),'application/octet-stream',$Bytes,$A->{Content}||'');
    }
}
sub Attachment {
    my ($S,$U,$ID)=@_; my $A=$S->{DB}->SelectRow('SELECT * FROM appointment_attachment WHERE id=?',_ID($ID)); return if !$A;
    return if !$S->EventGet($U,$A->{event_id}); return $A;
}
sub _Enqueue {
    my ($S,%P)=@_; my $Key=sha256_hex(encode('UTF-8',$P{key}));
    $S->_Do('INSERT INTO appointment_delivery (event_id,occurrence_id,recipient_user_id,recipient_email,delivery_key,kind,channel,due_at,payload_json) VALUES (?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
        due_at=IF(status="cancelled",VALUES(due_at),due_at),payload_json=IF(status="cancelled",VALUES(payload_json),payload_json),status=IF(status="cancelled","pending",status)',
        $P{event_id},$P{occurrence_id}||0,$P{user_id}||undef,$P{email}||'',$Key,$P{kind},$P{channel},$P{due_at}||_Now(),_JSON($P{payload}||{}));
}
sub _InviteesSave {
    my ($S,$ID,$D,$Kind,$OID)=@_;
    my $E=$S->_RawEvent($ID); my $Old=$S->{DB}->SelectAll('SELECT * FROM appointment_invitee WHERE event_id=?',$ID)||[];
    my %Wanted=map {lc($_->{email})=>1} @{$D->{participants}||[]};
    for my $P (@$Old) {
        next if $Wanted{$P->{email}};
        if ($P->{token_hash}) {
            $S->_Enqueue(event_id=>$ID,kind=>'cancel',channel=>'email',email=>$P->{email},key=>"remove:$ID:$E->{version}:$P->{email}",payload=>{%$D,notice=>'Teilnahme aufgehoben'});
        }
        $S->_Do('DELETE FROM appointment_invitee WHERE id=?',$P->{id});
        $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE event_id=? AND recipient_email=? AND status="pending" AND kind<>"cancel"',$ID,$P->{email});
    }
    for my $P (@{$D->{participants}||[]}) {
        my $Existing=$S->{DB}->SelectRow('SELECT * FROM appointment_invitee WHERE event_id=? AND email=?',$ID,$P->{email});
        my $Token;
        if ($D->{send_invites} && !$P->{user_id} && $Kind ne 'cancel') {
            my $Bytes=QisutuSecurity->new(Config=>$S->{Config})->_RandomBytes(32); die 'Einladungslink konnte nicht erstellt werden.' if !$Bytes;
            $Token=unpack('H*',$Bytes);
        }
        $S->_Do('INSERT INTO appointment_invitee (event_id,user_id,email,name,response,token_hash) VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id),name=VALUES(name),response=VALUES(response),token_hash=COALESCE(VALUES(token_hash),token_hash)',
            $ID,$P->{user_id}||undef,$P->{email},$P->{name},$Existing ? $Existing->{response} : 'pending',$Token?sha256_hex($Token):undef);
        next if !$D->{send_invites};
        my %Payload=(%$D,revision=>$E->{version},notice=>$Kind eq 'cancel'?'Termin abgesagt':$Kind eq 'update'?'Termin geändert':'Einladung',reply_token=>$Token||'',series=>($D->{repeat}->{frequency}||'none') ne 'none'?1:0);
        $Payload{notice}.=' (einzelner Termin)' if $OID;
        my $Key="invitation:$ID:$E->{version}:$OID:$Kind:$P->{email}";
        $S->_Enqueue(event_id=>$ID,occurrence_id=>$OID,user_id=>$P->{user_id},email=>$P->{email},kind=>$Kind,channel=>'email',key=>$Key.':email',payload=>\%Payload);
        if ($P->{user_id}) { $S->_Enqueue(event_id=>$ID,occurrence_id=>$OID,user_id=>$P->{user_id},email=>$P->{email},kind=>$Kind,channel=>'app',key=>$Key.':app',payload=>\%Payload); }
    }
}
sub _Reminders {
    my ($S,$ID)=@_; my $E=$S->_RawEvent($ID); return if !$E || !$E->{active} || !$E->{calendar_active};
    my $Owner=$S->{DB}->SelectRow('SELECT id,email FROM user_account WHERE id=? AND is_active=1',$E->{owner_user_id});
    my $Invitees=$S->{DB}->SelectAll('SELECT user_id AS id,email FROM appointment_invitee WHERE event_id=? AND user_id IS NOT NULL AND response<>"declined"',$ID)||[];
    my %Recipients=map {$_->{id}=>$_} (@$Invitees,$Owner?($Owner):());
    my $Rows=$S->{DB}->SelectAll('SELECT * FROM appointment_occurrence WHERE event_id=? AND cancelled=0 AND end_utc>=?',$ID,_Now())||[];
    for my $O (@$Rows) {
        my $D=_Data($O->{data_json}||$E->{data_json});
        for my $Offset (@{$D->{reminders}||[]}) {
            my $Due=QisutuAppointmentTime::Epoch($O->{start_utc})-$Offset*60;
            next if $O->{start_utc} lt $E->{created_at};
            my $Created=QisutuAppointmentTime::Epoch($E->{created_at});
            $Due=$Created if $Due<$Created;
            next if $Due>time+7*86400;
            for my $P (values %Recipients) {
                for my $Channel (qw(app email)) {
                    next if !$D->{'reminder_'.$Channel};
                    my $Key=join(':','reminder',$O->{id},$O->{start_utc},$Offset,$P->{id},$Channel);
                    $S->_Enqueue(event_id=>$ID,occurrence_id=>$O->{id},user_id=>$P->{id},email=>$P->{email},kind=>'reminder',channel=>$Channel,key=>$Key,due_at=>QisutuAppointmentTime::UTC($Due),payload=>{%$D,start_local=>QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{start_utc}),$D->{timezone}),end_local=>QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{end_utc}),$D->{timezone}),notice=>'Terminerinnerung'});
                }
            }
        }
    }
}
sub Respond {
    my ($S,$U,$ID,$Response)=@_;
    return $S->_Fail('Ungültige Antwort.') if ($Response||'') !~ /\A(?:accepted|declined|tentative)\z/;
    return $S->_Locked(sub {
        my $E=$S->_RawEvent(_ID($ID)); die 'Termin nicht verfügbar.' if !$E || !$E->{active};
        my $I=$S->{DB}->SelectRow('SELECT id FROM appointment_invitee WHERE event_id=? AND user_id=?',_ID($ID),_UserID($U)); die 'Keine Einladung vorhanden.' if !$I;
        $S->_Do('UPDATE appointment_invitee SET response=? WHERE id=?',$Response,$I->{id});
        if ($Response eq 'declined') { $S->_Do('UPDATE appointment_delivery SET status="cancelled" WHERE event_id=? AND recipient_user_id=? AND kind="reminder" AND status="pending"',$ID,_UserID($U)); }
        else { $S->_Reminders($ID); }
        return {success=>1};
    });
}
sub PublicReply {
    my ($S,$Token,$Response)=@_; return if !$Token || $Token!~/\A[a-f0-9]{64}\z/;
    my $I=$S->{DB}->SelectRow('SELECT * FROM appointment_invitee WHERE token_hash=? AND user_id IS NULL',sha256_hex($Token)); return if !$I;
    my $E=$S->_RawEvent($I->{event_id}); return if !$E || !$E->{active} || !$E->{calendar_active};
    my $D=_Data($E->{data_json});
    my $Last=$S->{DB}->SelectRow('SELECT MAX(end_utc) AS last_end FROM appointment_occurrence WHERE event_id=? AND cancelled=0',$E->{id});
    return if !$Last || !$Last->{last_end} || $Last->{last_end} lt _Now();
    if (defined $Response) {
        return if $Response!~/\A(?:accepted|declined|tentative)\z/;
        return $S->_Locked(sub { $S->_Do('UPDATE appointment_invitee SET response=? WHERE id=? AND token_hash=?',$Response,$I->{id},sha256_hex($Token)); return {title=>$D->{title},saved=>1}; });
    }
    return {title=>$D->{title},start_local=>$D->{start_local},timezone=>$D->{timezone},response=>$I->{response},series=>($D->{repeat}->{frequency}||'none') ne 'none'?1:0};
}
sub Notifications {
    my ($S,$U)=@_; my $UID=_UserID($U); return [] if !$UID;
    my $Rows=$S->{DB}->SelectAll('SELECT * FROM appointment_delivery WHERE recipient_user_id=? AND channel="app" AND status="pending" AND due_at<=? AND read_at IS NULL ORDER BY due_at DESC LIMIT 50',$UID,_Now())||[];
    my @Out;
    for my $R (@$Rows) {
        my $E=$S->_RawEvent($R->{event_id}); next if !$E || !$S->_Visible($U,$E,_Data($E->{data_json}));
        my $D=_Data($R->{payload_json});
        push @Out,{id=>$R->{id},event_id=>$R->{event_id},occurrence_id=>$R->{occurrence_id},kind=>$R->{kind},title=>$D->{title},notice=>$D->{notice},start_local=>$D->{start_local},timezone=>$D->{timezone}};
    }
    return \@Out;
}
sub NotificationRead {
    my ($S,$U,$ID,$Snooze)=@_; my $UID=_UserID($U); return if !$UID;
    if ($Snooze) { return $S->{DB}->Do('UPDATE appointment_delivery SET due_at=? WHERE id=? AND recipient_user_id=? AND channel="app"',QisutuAppointmentTime::UTC(time+600),_ID($ID),$UID); }
    return $S->{DB}->Do('UPDATE appointment_delivery SET read_at=? WHERE id=? AND recipient_user_id=? AND channel="app"',_Now(),_ID($ID),$UID);
}
sub ProcessDue {
    my ($S,%P)=@_;
    my $Processed=$S->_Locked(sub {
        my $Through=substr(QisutuAppointmentTime::UTC(time+400*86400),0,10);
        my $Events=$S->{DB}->SelectAll('SELECT e.id FROM appointment_event e INNER JOIN appointment_calendar c ON c.id=e.calendar_id WHERE e.active=1 AND c.active=1')||[];
        for my $E (@$Events) { $S->_Expand($E->{id},$Through,0); $S->_Reminders($E->{id}); }
        my $Due=$S->{DB}->SelectAll('SELECT o.*,e.data_json AS master_json,e.owner_user_id,e.calendar_id,e.created_at FROM appointment_occurrence o INNER JOIN appointment_event e ON e.id=o.event_id INNER JOIN appointment_calendar c ON c.id=e.calendar_id WHERE e.active=1 AND c.active=1 AND o.cancelled=0 AND o.ticket_id IS NULL AND o.ticket_due_at<=? AND (o.ticket_retry_at IS NULL OR o.ticket_retry_at<=?) ORDER BY o.ticket_due_at,o.id LIMIT 50',_Now(),_Now())||[];
        my $Processed=0; my @Errors;
        for my $O (@$Due) {
            my $D=_Data($O->{data_json}||$O->{master_json}); next if !$D->{auto_ticket};
            my $Result=eval {
                my $UID=$D->{ticket_author_id}||$O->{owner_user_id};
                my $U=$S->{DB}->SelectRow('SELECT *,id AS user_account_id FROM user_account WHERE id=? AND is_active=1 AND is_system_user=0 AND account_type="agent"',$UID);
                die 'Der für die Ticketerstellung verantwortliche Agent ist nicht mehr aktiv.' if !$U;
                die 'Keine Schreibberechtigung für den Kalender.' if $S->Role($U,$O->{calendar_id})<3;
                die 'Keine Berechtigung zur Ticketerstellung in der Queue.' if !$S->_Permission->QueueAccessCheck(UserID=>$UID,QueueID=>$D->{queue_id},Permission=>'ticket.create');
                die 'Der vorgesehene Ticketbesitzer hat keinen Zugriff auf die Queue.' if $D->{ticket_owner_id} && !$S->_Permission->QueueAccessCheck(UserID=>$D->{ticket_owner_id},QueueID=>$D->{queue_id},Permission=>'ticket.view');
                my $State=$S->{DB}->SelectRow('SELECT id FROM ticket_state WHERE active=1 AND state_type="open" ORDER BY sort_order,id LIMIT 1'); die 'Kein Status vom Typ offen vorhanden.' if !$State;
                my $Body=$D->{ticket_body}||$D->{description}||$D->{title};
                $Body.="\n\nKalendertermin: ".QisutuAppointmentTime::Local(QisutuAppointmentTime::Epoch($O->{start_utc}),$D->{timezone}).' ('.$D->{timezone}.')';
                my $T=$S->_Ticket;
                my $ID=$T->TicketCreateFromAgent(User=>$U,QueueID=>$D->{queue_id},StateID=>$State->{id},PriorityID=>$D->{priority_id},OwnerUserID=>$D->{ticket_owner_id}||$UID,
                    CustomerUserID=>$D->{customer_user_id}||0,CustomerID=>$D->{customer_id}||0,RecipientEmail=>$D->{recipient_email}||'',Title=>$D->{ticket_title}||$D->{title},Body=>$Body,ContentType=>'text/plain',SendEmail=>0,InternalOnly=>1,DynamicFieldRequest=>$D->{ticket_dynamic_fields}||{},AppointmentOccurrenceID=>$O->{id});
                die($T->Error||'Ticket konnte nicht erstellt werden.') if !$ID;
                $Processed++; 1;
            };
            if (!$Result) { my $Error=$@||'Ticket konnte nicht erstellt werden.'; push @Errors, 'Termin '.$O->{id}.': '.$Error; $S->_Do('UPDATE appointment_occurrence SET ticket_error=?,ticket_retry_at=? WHERE id=?',substr($Error,0,2000),QisutuAppointmentTime::UTC(time+300),$O->{id}); }
        }
        $S->{LastError}=join('; ',@Errors) if @Errors;
        return $Processed;
    });
    return if !defined $Processed;
    my @Errors=$S->Error ? ($S->Error) : ();
    # Claim under the advisory lock, then release it before contacting SMTP.
    # A slow mail server must not block interactive calendar changes.
    for (1..50) {
        my $R=$S->_Locked(sub {
            $S->_Do('UPDATE appointment_delivery SET status="pending" WHERE channel="email" AND status="sending" AND due_at<=?',_Now());
            my $Next=$S->{DB}->SelectRow('SELECT * FROM appointment_delivery WHERE channel="email" AND status="pending" AND due_at<=? ORDER BY due_at,id LIMIT 1',_Now());
            return {done=>1} if !$Next;
            $S->_Do('UPDATE appointment_delivery SET status="sending",attempts=attempts+1,due_at=? WHERE id=?',QisutuAppointmentTime::UTC(time+900),$Next->{id});
            return $Next;
        });
        if (!$R) { push @Errors,$S->Error; last; }
        last if $R->{done};
        my $OK=eval { $S->_SendDelivery($R) }; my $Error=$@;
        if ($OK) { $S->{DB}->Do('UPDATE appointment_delivery SET status="sent",last_error=NULL WHERE id=?',$R->{id}); }
        else {
            push @Errors, 'Kalender-E-Mail '.$R->{id}.': '.($Error||'Versand fehlgeschlagen');
            $S->{DB}->Do('UPDATE appointment_delivery SET status="pending",last_error=?,due_at=? WHERE id=?',substr($Error||'E-Mail konnte nicht gesendet werden.',0,2000),QisutuAppointmentTime::UTC(time+900),$R->{id});
        }
        $Processed++;
    }
    $S->{LastError}=join('; ',@Errors);
    return $Processed;
}
sub _SendDelivery {
    my ($S,$R)=@_; require QisutuMail; require QisutuSystemSetting;
    my $Current=$S->_RawEvent($R->{event_id});
    my $Payload=_Data($R->{payload_json});
    if ($R->{kind} ne 'cancel') {
        return 1 if !$Current || !$Current->{active} || !$Current->{calendar_active};
        return 1 if $Payload->{revision} && $Payload->{revision}!=$Current->{version};
        if ($R->{occurrence_id}) {
            my $Occurrence=$S->{DB}->SelectRow('SELECT cancelled FROM appointment_occurrence WHERE id=?',$R->{occurrence_id});
            return 1 if !$Occurrence || $Occurrence->{cancelled};
        }
    }
    if ($R->{kind} eq 'reminder') {
        my $E=$S->_RawEvent($R->{event_id});
        my $U=$S->{DB}->SelectRow('SELECT *,id AS user_account_id FROM user_account WHERE id=? AND is_active=1',$R->{recipient_user_id}||0);
        if (!$E || !$E->{active} || !$U || !$S->_Visible($U,$E,_Data($E->{data_json}))) { return 1; }
    }
    my $SMTP=$S->{DB}->SelectRow('SELECT * FROM smtp_account WHERE active=1 ORDER BY sort_order,id LIMIT 1');
    my $Sender=$S->{DB}->SelectRow('SELECT name,email FROM system_email WHERE active=1 ORDER BY sort_order,id LIMIT 1');
    die 'Kein aktives SMTP-Konto oder keine Systemadresse konfiguriert.' if !$SMTP || !$Sender || !$Sender->{email};
    my $D=_Data($R->{payload_json}); my $Plain=($D->{notice}||'Kalendertermin').": ".($D->{title}||'')."\n\n";
    $Plain.=($D->{start_local}||'').' – '.($D->{end_local}||'').' ('.($D->{timezone}||'').")\n";
    $Plain.="Ort: $D->{location}\n" if $D->{location};
    $Plain.="$D->{meeting_url}\n" if $D->{meeting_url};
    $Plain.="\n".($D->{description}||'')."\n";
    $Plain.="\nDieser Termin ist Teil einer Serie. Die Teilnahmeantwort gilt für die Serie.\n" if $D->{series};
    my $Base=QisutuSystemSetting->new(Config=>$S->{Config},DB=>$S->{DB})->BaseURL(); $Base=~s{/+$}{};
    if ($D->{reply_token}) {
        die 'Die System-Basis-URL fehlt für externe Einladungen.' if !$Base || $Base!~m{\Ahttps?://};
        $Plain.="\nTeilnahme bestätigen oder absagen:\n$Base/index.pl?Page=CalendarReply&Token=$D->{reply_token}\n";
    } elsif ($R->{recipient_user_id} && $Base) { $Plain.="\n$Base/index.pl?Page=AgentCalendar&EventID=$R->{event_id}\n"; }
    my $HTML=$Plain; $HTML=~s/&/&amp;/g; $HTML=~s/</&lt;/g; $HTML=~s/>/&gt;/g; $HTML=~s/\n/<br>/g;
    my $Sent=QisutuMail->new(Config=>$S->{Config},DB=>$S->{DB})->SMTPSend(Account=>$SMTP,Operation=>'calendar',FromName=>$Sender->{name}||'Qisutu',FromEmail=>$Sender->{email},ToEmail=>$R->{recipient_email},Subject=>($D->{notice}||'Kalendertermin').': '.($D->{title}||''),PlainBody=>$Plain,Body=>'<p>'.$HTML.'</p>');
    die($Sent->{Message}||'E-Mail konnte nicht gesendet werden.') if !$Sent || !$Sent->{Success};
    return 1;
}
1;
