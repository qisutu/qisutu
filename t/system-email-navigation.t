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

use File::Spec;
use FindBin;
use Test::More;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Program = do File::Spec->catfile( $Root, 'core', 'config', 'programs', 'AdminSystemEmails.pm' );
my $German  = do File::Spec->catfile( $Root, 'core', 'language', 'de.pm' );

is( $Program->{Title}, 'AdminSystemEmailsTitle', 'the navigation uses the translatable title key' );
is( $German->{AdminSystemEmailsTitle}, 'System-E-Mails', 'the German navigation title uses the requested name' );
is( $German->{AdminSystemEmailsList}, 'System-E-Mails', 'the administration list uses the same name' );
is( $German->{AdminSystemEmail}, 'System-E-Mail', 'singular field labels use the shortened name' );

done_testing();
