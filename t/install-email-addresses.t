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

my $InstallerPath = "$FindBin::Bin/../bin/cgi-bin/install.pl";
open my $InstallerFH, '<:encoding(UTF-8)', $InstallerPath
    or die "Cannot open $InstallerPath: $!";
my $Installer = do { local $/; <$InstallerFH> };
close $InstallerFH;

like(
    $Installer,
    qr{UPDATE user_account SET email = \?, updated_at = NOW\(\) WHERE id = 1},
    'the e-mail address from installation step 4 is stored on the administrator account',
);

unlike(
    $Installer,
    qr{_Field\( 'Absenderadresse', 'SMTPEmail', \$Request->\{SMTPEmail\} \|\| \$State->\{admin_email\}},
    'the SMTP sender field in step 5 is not prefilled with the administrator e-mail address',
);

like(
    $Installer,
    qr{my \$SystemEmail = \$IMAPEnabled \? \$IMAP->\{email\} : \$SMTP->\{email\};},
    'the incoming mailbox address from step 5 becomes the system e-mail when IMAP is configured',
);

my $PasswordResetPath = "$FindBin::Bin/../core/system/QisutuPasswordReset.pm";
open my $PasswordResetFH, '<:encoding(UTF-8)', $PasswordResetPath
    or die "Cannot open $PasswordResetPath: $!";
my $PasswordReset = do { local $/; <$PasswordResetFH> };
close $PasswordResetFH;

like(
    $PasswordReset,
    qr{ToEmail\s*=>\s*\$User->\{email\}},
    'password-reset messages are sent to the administrator e-mail stored on the user account',
);

like(
    $PasswordReset,
    qr{FromEmail\s*=>\s*\$SystemEmail->\{email\}},
    'password-reset messages use the configured system e-mail as their sender',
);

done_testing();
