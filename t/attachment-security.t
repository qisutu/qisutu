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
use Test::More;
use lib "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output", "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config";

use QisutuOutput;
use TicketAttachmentDownload;

{
    package Local::AttachmentTicket;
    sub new { bless { Allowed => $_[1], SeenUser => undef }, $_[0] }
    sub ArticleAttachmentGet {
        my ( $Self, %Param ) = @_;
        $Self->{SeenUser} = $Param{User};
        return if !$Self->{Allowed};
        return {
            filename     => "Kundenübersicht 2026.xlsx",
            content_type => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            content      => "test-content",
        };
    }
    sub Error { return 'Attachment was not found.' }

    package Local::AttachmentDownload;
    our @ISA = ('TicketAttachmentDownload');
    sub _TicketObject { return $_[0]->{TestTicket} }
}

my $Output = QisutuOutput->new( Config => {} );
my $Ticket = Local::AttachmentTicket->new(1);
my $Download = Local::AttachmentDownload->new( Config => {}, DB => {}, Output => $Output );
$Download->{TestTicket} = $Ticket;

my $User = { user_account_id => 77, account_type => 'agent' };
my $Result = $Download->Run( Request => { AttachmentID => 9 }, User => $User );
like( $Result->{Response}, qr{^Status: 200 OK\r?$}m, 'authorized attachment request succeeds' );
is( $Ticket->{SeenUser}, $User, 'current user is passed to the ticket permission check' );
like( $Result->{Response}, qr{^Content-Disposition: attachment;}m, 'attachment is always downloaded rather than displayed inline' );
like( $Result->{Response}, qr{filename\*=UTF-8''Kunden%C3%BCbersicht%202026\.xlsx}, 'international original filename is preserved in the download header' );
like( $Result->{Response}, qr{^X-Content-Type-Options: nosniff\r?$}m, 'attachment response prevents MIME sniffing' );

my $DeniedTicket = Local::AttachmentTicket->new(0);
$Download->{TestTicket} = $DeniedTicket;
my $Denied = $Download->Run( Request => { AttachmentID => 9 }, User => $User );
like( $Denied->{Response}, qr{^Status: 404 Not Found\r?$}m, 'unauthorized and missing attachments are not disclosed' );
unlike( $Denied->{Response}, qr{test-content}, 'denied response contains no attachment data' );

done_testing();
