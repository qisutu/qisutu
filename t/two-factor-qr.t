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

use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output";

use QisutuOutput;
use QisutuTwoFactor;

my $Root = "$FindBin::Bin/..";
my $Config = {
    Paths => {
        Language => "$Root/core/language",
        Output   => "$Root/core/output",
    },
    Language => { Default => 'de' },
    System   => {
        Name       => 'Qisutu Service',
        InstanceID => 'qisututest',
    },
};

my $TwoFactor = QisutuTwoFactor->new( Config => $Config, DB => undef );
my $URI = $TwoFactor->ProvisioningURI(
    Secret      => 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq',
    AccountName => 'ud+test@einräumwerk.de',
);

is(
    $URI,
    'otpauth://totp/Qisutu%20Service%20%28qisututest%29:ud%2Btest%40einr%C3%A4umwerk.de'
        . '?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
        . '&issuer=Qisutu%20Service%20%28qisututest%29&algorithm=SHA1&digits=6&period=30',
    'provisioning URI contains the encoded issuer, account and standard TOTP parameters',
);
is(
    $TwoFactor->ProvisioningURI( Secret => 'not-a-base32-secret', AccountName => 'agent' ),
    '',
    'invalid Base32 secrets are not exposed through a provisioning URI',
);

my $Output = QisutuOutput->new( Config => $Config );

sub FileRead {
    my ($File) = @_;
    open my $FH, '<:encoding(UTF-8)', $File or die "Could not read $File: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;
    return $Content;
}

sub TemplateRead {
    my ($Name) = @_;
    return FileRead("$Root/core/output/$Name");
}

my %SetupData = (
    Language                    => 'de',
    StaticBase                  => '/qisututest/static',
    TwoFactorSetup              => 1,
    TwoFactorEnabled            => 0,
    TwoFactorSecret             => 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    TwoFactorProvisioningURI    => $URI,
    TwoFactorAccountName        => 'ud+test@einräumwerk.de',
    ShowRecoveryCodes           => 0,
    TicketListLimit20Selected   => 'selected',
);

for my $TemplateName ( 'AgentPreferences.tt', 'CustomerPreferences.tt', 'TwoFactorChallenge.tt' ) {
    my $Rendered = $Output->_TemplateReplace(
        Content => TemplateRead($TemplateName),
        Data    => \%SetupData,
    );

    unlike( $Rendered, qr{\[\%\s*(?:IF|ELSE|ELSIF|END)\b}, "$TemplateName contains no unresolved conditional" );
    like( $Rendered, qr{data-qisutu-two-factor-uri="otpauth://totp/}, "$TemplateName renders the local QR target" );
    like( $Rendered, qr{/js/qrcode-generator/qrcode[.]js[?]v=2[.]0[.]4}, "$TemplateName loads the bundled QR generator" );
    like( $Rendered, qr{Google Authenticator}, "$TemplateName explains QR setup for Google Authenticator" );
}

my $LoginChallenge = $Output->_TemplateReplace(
    Content => TemplateRead('TwoFactorChallenge.tt'),
    Data    => {
        Language       => 'de',
        StaticBase     => '/qisututest/static',
        SystemName     => 'Qisutu',
        TwoFactorSetup => 0,
    },
);
like( $LoginChallenge, qr{class="qisutu-login"}, 'two-factor login uses the compact public login layout' );
like( $LoginChallenge, qr{class="qisutu-login-panel "}, 'two-factor login uses the width-limited login panel' );
like( $LoginChallenge, qr{<h1>Qisutu</h1>}, 'two-factor login displays the same Qisutu brand heading as the login page' );
like( $LoginChallenge, qr{<h2 id="qisutu-two-factor-login-title">Zwei-Faktor-Anmeldung</h2>}, 'two-factor title is displayed below the Qisutu brand heading' );
like( $LoginChallenge, qr{class="qisutu-login-field"}, 'two-factor code uses the regular login input styling' );
like( $LoginChallenge, qr{class="qisutu-login-button"}, 'two-factor verification uses the regular login button styling' );
unlike( $LoginChallenge, qr{qisutu-login-(?:main|card|error)}, 'two-factor login no longer relies on undefined layout classes' );

my $RecoveryView = $Output->_TemplateReplace(
    Content => TemplateRead('TwoFactorRecoveryCodes.tt'),
    Data    => {
        Language          => 'de',
        StaticBase        => '/qisututest/static',
        SystemName        => 'Qisutu',
        RecoveryCodesHTML => '<li><code>ABCD-EFGH</code></li>',
    },
);
like( $RecoveryView, qr{class="qisutu-login-panel"}, 'recovery codes use the compact public login panel' );
like( $RecoveryView, qr{<h1>Qisutu</h1>}, 'recovery codes retain the standard Qisutu login heading' );
unlike( $RecoveryView, qr{qisutu-login-(?:main|card)}, 'recovery codes no longer rely on undefined layout classes' );

my $EnabledAgent = $Output->_TemplateReplace(
    Content => TemplateRead('AgentPreferences.tt'),
    Data    => {
        Language         => 'de',
        TwoFactorSetup   => 0,
        TwoFactorEnabled => 1,
        ShowRecoveryCodes => 0,
    },
);
unlike( $EnabledAgent, qr{data-qisutu-two-factor-uri}, 'enabled view does not expose the setup QR code or secret' );
like( $EnabledAgent, qr{Zwei-Faktor-Authentifizierung ist aktiv}, 'enabled view renders only the active state' );

my $QRSource = FileRead("$Root/var/static/js/qrcode-generator/qrcode.js");
like( $QRSource, qr{var qrcode = function}, 'bundled QR generator is present' );

my $QisutuQRSource = FileRead("$Root/var/static/js/qisutu-two-factor.js");
like( $QisutuQRSource, qr{data-qisutu-two-factor-uri}, 'Qisutu QR renderer reads the local provisioning URI' );
unlike( $QisutuQRSource, qr{\b(?:fetch|XMLHttpRequest)\b}, 'Qisutu QR renderer performs no network request' );

done_testing();
