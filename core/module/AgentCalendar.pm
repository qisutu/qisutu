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

package AgentCalendar;
use strict;
use warnings;
use utf8;
use JSON::PP qw(encode_json decode_json);
use Encode qw(encode);
use QisutuAppointment;

sub new { my ($Class,%P)=@_; return bless \%P,$Class; }
sub Run {
    my ($S,%P)=@_; my $R=$P{Request}||{}; my $U=$P{User}||{};
    my $A=QisutuAppointment->new(Config=>$S->{Config},DB=>$S->{DB});
    return $S->_JSON({success=>0,message=>'Zugriff verweigert.'},'403 Forbidden') if ($U->{account_type}||'') ne 'agent' || !$U->{user_account_id};
    my $Step=$R->{Step}||'';
    my %Read=map {$_=>1} qw(Bootstrap List Get Notifications Attachment Conflicts TicketInfo Fields);
    if ($Step && !$Read{$Step} && ($R->{__RequestMethod}||'') ne 'POST') { return $S->_JSON({success=>0,message=>'POST erforderlich.'},'405 Method Not Allowed'); }
    my $D={};
    if (defined $R->{Data}) {
        $D=eval { JSON::PP->new->decode($R->{Data}) };
        return $S->_JSON({success=>0,message=>'Ungültige Anfrage.'},'400 Bad Request') if ref($D) ne 'HASH';
    }
    if ($Step eq 'Attachment') {
        my $F=$A->Attachment($U,$R->{AttachmentID});
        return $S->_JSON({success=>0,message=>'Anhang nicht verfügbar.'},'404 Not Found') if !$F;
        my $Name=$F->{filename}; my $UTF=encode('UTF-8',$Name); $UTF=~s/([^A-Za-z0-9._-])/sprintf('%%%02X',ord($1))/ge;
        return {Response=>$S->{Output}->Response(ContentType=>'application/octet-stream',Headers=>['Cache-Control: no-store','X-Content-Type-Options: nosniff',"Content-Disposition: attachment; filename=\"attachment\"; filename*=UTF-8''$UTF"],Body=>$F->{content})};
    }
    my $Result;
    if ($Step eq 'Bootstrap') { $Result=$A->Bootstrap($U); }
    elsif ($Step eq 'List') { $Result=$A->List($U,{from=>$R->{From},to=>$R->{To},mine=>$R->{Mine},ticket_id=>$R->{TicketID}}); }
    elsif ($Step eq 'Get') { $Result=$A->EventGet($U,$R->{EventID},$R->{OccurrenceID}); }
    elsif ($Step eq 'Save') { $Result=$A->Save($U,$D,$R->{__Uploads}->{Attachments}||[]); }
    elsif ($Step eq 'Cancel') { $Result=$A->Cancel($U,$D); }
    elsif ($Step eq 'CalendarSave') { $Result=$A->CalendarSave($U,$D); }
    elsif ($Step eq 'Respond') { $Result=$A->Respond($U,$D->{id},$D->{response}); }
    elsif ($Step eq 'Notifications') { $Result=$A->Notifications($U); }
    elsif ($Step eq 'NotificationRead') { $Result=$A->NotificationRead($U,$D->{id},$D->{snooze}); }
    elsif ($Step eq 'Conflicts') { $Result=$A->Conflicts($U,$D); }
    elsif ($Step eq 'Fields') {
        if (!$A->_Permission->QueueAccessCheck(UserID=>$U->{user_account_id},QueueID=>$D->{queue_id}||0,Permission=>'ticket.create')) {
            return $S->_JSON({success=>0,message=>'Kein Zugriff auf diese Queue.'},'403 Forbidden');
        }
        require QisutuDynamicField;
        my $Fields=QisutuDynamicField->new(Config=>$S->{Config},DB=>$S->{DB},Output=>$S->{Output});
        $Result={html=>$Fields->FormHTML(QueueID=>$D->{queue_id},Request=>$D->{values}||{},Language=>$R->{Language}||'de',IDPrefix=>'qc-dynamic')};
    }
    elsif ($Step eq 'TicketInfo') {
        my $T=$A->_Ticket->TicketGet(User=>$U,TicketID=>$R->{TicketID});
        $Result=$T ? {id=>$T->{id},number=>$T->{ticket_number},title=>$T->{title},customer_id=>$T->{customer_id},customer_user_id=>$T->{customer_user_id},queue_id=>$T->{queue_id}} : undef;
    }
    elsif ($Step) { return $S->_JSON({success=>0,message=>'Unbekannte Aktion.'},'400 Bad Request'); }
    else {
        return {Template=>'AgentCalendar.tt',Data=>{PageTitle=>'Translate:AppointmentNavigation',ProgramTitle=>'Translate:AppointmentNavigation',PageCSS=>'qisutu-calendar.css?v=2026101701',CalendarCSRF=>$U->{csrf_token}||'',CalendarEventID=>QisutuAppointment::_ID($R->{EventID}),CalendarOccurrenceID=>QisutuAppointment::_ID($R->{OccurrenceID}),CalendarTicketID=>QisutuAppointment::_ID($R->{TicketID})}};
    }
    return $S->_JSON({success=>defined($Result)?1:0,data=>$Result,message=>defined($Result)?'':$A->Error||'Die Aktion konnte nicht ausgeführt werden.'});
}
sub _JSON {
    my ($S,$D,$Status)=@_;
    return {Response=>$S->{Output}->Response(Status=>$Status||'200 OK',ContentType=>'application/json; charset=UTF-8',Headers=>['Cache-Control: no-store'],Body=>encode_json($D))};
}
1;
