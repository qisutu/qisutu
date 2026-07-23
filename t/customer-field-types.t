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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );

use AdminCustomers;
use AdminCustomerUsers;
use QisutuOutput;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Config = {
    Paths => {
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
    },
    Language => { Default => 'de' },
};
my $Output = QisutuOutput->new( Config => $Config );
my $Customers = AdminCustomers->new( Config => $Config, Output => $Output );
my $CustomerUsers = AdminCustomerUsers->new( Config => $Config, Output => $Output );

my $GermanOptions = $Customers->_FieldTypeOptions(
    Selected => 'date',
    Language => 'de',
);

like( $GermanOptions, qr{<option value="text">Text</option>}, 'customer text field type is translated into German' );
like( $GermanOptions, qr{<option value="textarea">Mehrzeiliger Text</option>}, 'customer textarea field type is translated into German' );
like( $GermanOptions, qr{<option value="email">E-Mail-Adresse</option>}, 'customer email field type is translated into German' );
like( $GermanOptions, qr{<option value="phone">Telefon</option>}, 'customer phone field type is translated into German' );
like( $GermanOptions, qr{<option value="date" selected>Datum</option>}, 'customer date field type is translated and remains selected' );
like( $GermanOptions, qr{<option value="number">Zahl</option>}, 'customer number field type is translated into German' );
unlike( $GermanOptions, qr{>textarea<|>email<|>phone<|>date<|>number<}, 'customer field types no longer expose technical values as labels' );

my $FrenchOptions = $Customers->_FieldTypeOptions( Language => 'fr' );
like( $FrenchOptions, qr{<option value="textarea">Texte multiligne</option>}, 'customer field type uses the selected interface language' );

my $CustomerUserOptions = $CustomerUsers->_FieldTypeOptions( Language => 'de' );
like( $CustomerUserOptions, qr{<option value="date">Datum</option>}, 'customer users retain the same translated field type options' );

done_testing();
