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
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output";
use QisutuHTML;
use QisutuKnowledgeBase;
use QisutuOutput;

my @Malicious = (
    '<img src=x onerror=alert(1)>',
    '<<x>img src=x onerror=alert(1)>',
    '<<<x>x>img src=x onerror=alert(1)>',
    '<<x>script>alert(1)<</x>/script>',
    '<svg><style><img src=x onerror=alert(1)></style></svg>',
    '<math><mtext><table><mglyph><style><!--</style><img src=x onerror=alert(1)>',
    '<noscript><p title="</noscript><img src=x onerror=alert(1)>">',
    '<img src=x onerror=alert(1)//>',
    '<p title="<img src=x onerror=alert(1)>">safe</p>',
    '<script>alert(1)</script><p>safe</p>',
    '<p bad=<img src=x onerror=alert(1)>>safe',
    '<!--><img src=x onerror=alert(1)>',
    '<a href="javascript:alert(1)">test</a>',
    "<a href=\"java\tscript:alert(1)\">test</a>",
    "<a href=\"java\nscript:alert(1)\">test</a>",
    '<a href="java&#9;script:alert(1)">test</a>',
    '<a href="java&#x0a;script:alert(1)">test</a>',
    '<a href="&#106;avascript&colon;alert(1)">test</a>',
    '<a href="javascript&colon;alert(1)">test</a>',
    '<a href="java&Tab;script:alert(1)">test</a>',
    '<a href="data:text/html,test">test</a>',
    '<a href="vbscript:msgbox(1)">test</a>',
    '<img src="data:image/svg+xml;base64,PHN2Zz4=">',
    '<img src="x" style="background-image:url(javascript:alert(1))">',
);
for my $Input (@Malicious) {
    my $Clean = QisutuHTML->Sanitize($Input);
    unlike($Clean, qr{<[^>]*\son[a-z]+\s*=}i, 'no event-handler attribute remains');
    unlike($Clean, qr{<(?:script|svg|math|iframe|object|embed|style|template)\b}i, 'no active/foreign content tag remains');
    unlike($Clean, qr{(?:href|src)="(?:javascript|vbscript|data:(?!image/(?:png|jpeg|gif)))}i, 'unsafe URL schemes are removed');
    is(QisutuHTML->Sanitize($Clean), $Clean, 'sanitizing twice is stable');
}
for my $Depth (1 .. 12) {
    my $Input = '<p>Printer broken</p><' . ('<x>' x $Depth) . 'img src=x onerror=alert(1)>';
    for (1 .. 6) { $Input = QisutuHTML->Sanitize($Input); }
    unlike($Input, qr{<img\b[^>]*\bonerror}i, 'repeated cleanup never activates nested markup');
}
my @Safe = (
    '<p>Grüße „Kunde“</p><p>&nbsp;</p><p>A<br><br>B</p>',
    '<blockquote class="qisutu-mail-quote"><p>Text</p></blockquote>',
    '<a href="https://example.invalid/?a=1&amp;b=2">Link</a>',
    '<a href="mailto:test@example.invalid">Mail</a>',
    '<a href="tel:+33123456789">Telefon</a>',
    '<a href="../index.pl?Page=Dashboard">Intern</a>',
    '<img src="cid:example" alt="Grüße &amp; mehr" width="50">',
    '<img src="data:image/png;base64,iVBORw0KGgo=">',
    '<table><tbody><tr><td colspan="2">Text</td></tr></tbody></table>',
    '<p style="color: #aabbcc; font-weight: bold">Text</p>',
);
is(QisutuHTML->Sanitize('<script>var text="<script>";</script><p>safe</p>'),'<p>safe</p>','script-like strings do not remove the following content');
is(QisutuHTML->Sanitize('<script><!-- old wrapper </script><p>safe</p>'),'<p>safe</p>','legacy script comment does not consume the rest of the message');
for my $HTML (@Safe) {
    is(QisutuHTML->Sanitize($HTML),$HTML,'safe rich text retains formatting, links and images');
    is(QisutuHTML->Sanitize(QisutuHTML->Sanitize($HTML)),$HTML,'safe markup remains stable across storage and display');
}
my $Knowledge=QisutuKnowledgeBase->new(Config=>{});
unlike($Knowledge->ContentHTML('<<x>img src=x onerror=alert(1)>'),qr{<img\b[^>]*onerror},'legacy stored FAQ content is sanitized on display');

my $Directory=tempdir(CLEANUP=>1);
open my $Template,'>:encoding(UTF-8)',"$Directory/Test.tt" or die $!;
print {$Template} '<script>window.trusted = 1;</script><div>[% RAW.Body %]</div>';
close $Template;
my $Config={Paths=>{Output=>$Directory,Language=>$Directory}};
my $Output=QisutuOutput->new(Config=>$Config);
my $HTML=$Output->RenderSingle(Template=>'Test.tt',Data=>{Body=>'<script>window.untrusted = 1;</script><img src=x onerror=alert(1)>'});
like($HTML,qr{<script nonce="[A-Za-z0-9+/]{32}">window.trusted},'trusted template script receives random nonce');
like($HTML,qr{<script>window.untrusted},'dynamic script never acquires a nonce');
my ($Nonce)=$HTML=~/nonce="([^"]+)"/;
my $Response=$Output->Response(Body=>$HTML);
like($Response,qr{Content-Security-Policy:.*'nonce-\Q$Nonce\E'},'response policy matches trusted script nonce');
like($Response,qr{script-src-attr 'none'},'browser policy denies inline event handlers');
unlike($Response,qr{'unsafe-inline'},'browser policy does not permit arbitrary inline scripts');
my $Other=QisutuOutput->new(Config=>$Config)->Response(Body=>'test');
unlike($Other,qr{nonce-\Q$Nonce\E},'independent output objects use independent nonces');
my $Explicit=$Output->Response(Body=>'test',Headers=>["Content-Security-Policy: default-src 'none'"]);
is(scalar(()=$Explicit=~/^Content-Security-Policy:/mg),1,'explicit restrictive policy is preserved without duplicate headers');
done_testing();
