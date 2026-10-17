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

package CalendarReply;
use strict;
use warnings;
use utf8;
use QisutuAppointment;
sub new { my ($Class,%P)=@_; return bless \%P,$Class; }
sub _HTML { my $V=defined($_[0])?$_[0]:''; $V=~s/&/&amp;/g; $V=~s/</&lt;/g; $V=~s/>/&gt;/g; $V=~s/"/&quot;/g; $V=~s/'/&#39;/g; return $V; }
sub Run {
    my ($S,%P)=@_; my $R=$P{Request}||{}; my $Post=($R->{__RequestMethod}||'') eq 'POST';
    my $A=QisutuAppointment->new(Config=>$S->{Config},DB=>$S->{DB});
    my $D=$A->PublicReply($R->{Token},$Post?$R->{Response}:undef);
    my $Body='<h1>Kalendereinladung</h1>';
    if (!$D) { $Body.='<p>Diese Einladung ist ungültig, abgelaufen oder wurde aufgehoben.</p>'; }
    elsif ($D->{saved}) { $Body.='<h2>'._HTML($D->{title}).'</h2><p>Vielen Dank. Deine Teilnahmeantwort wurde gespeichert.</p>'; }
    else {
        $Body.='<h2>'._HTML($D->{title}).'</h2><p>'._HTML($D->{start_local}).' ('._HTML($D->{timezone}).')</p>';
        $Body.='<p>Die Antwort gilt für die gesamte Terminserie.</p>' if $D->{series};
        $Body.='<form method="post" action="index.pl"><input type="hidden" name="Page" value="CalendarReply"><input type="hidden" name="Token" value="'._HTML($R->{Token}).'"><input type="hidden" name="CSRFToken" value="'._HTML($P{CSRFToken}).'">';
        $Body.='<button name="Response" value="accepted">Zusagen</button> <button name="Response" value="tentative">Vorläufig</button> <button name="Response" value="declined">Absagen</button></form>';
    }
    return $S->{Output}->Response(Status=>$D?'200 OK':'404 Not Found',ContentType=>'text/html; charset=UTF-8',Headers=>['Cache-Control: no-store','Referrer-Policy: no-referrer','X-Robots-Tag: noindex, nofollow'],Body=>'<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Qisutu Kalendereinladung</title><style>body{font:16px system-ui;background:#edf3f7;color:#23394b;padding:30px}main{max-width:640px;background:white;padding:30px;border-radius:12px;margin:5vh auto;box-shadow:0 5px 25px #2342}button{padding:12px 20px;background:#005b70;color:white;border:0;border-radius:6px;cursor:pointer;margin:5px}</style></head><body><main>'.$Body.'</main></body></html>');
}
1;
