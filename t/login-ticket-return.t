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

use Digest::SHA qw(sha256_hex);
use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );

use Login;
use QisutuOutput;
use QisutuAuthProvider;

{
    package Local::TicketReturnSecurity;
    sub new { return bless {}, shift }
    sub PublicCSRFTokenCreate { return 'public-csrf-token' }
    sub Encrypt { my ( $Self, %Param ) = @_; return 'encrypted:' . $Param{Value} }
    sub Decrypt { my ( $Self, %Param ) = @_; my $Value = $Param{Value}; $Value =~ s{\Aencrypted:}{}; return $Value }
}

{
    package Local::TicketReturnAuth;
    sub new { return bless {}, shift }
    sub LoginCheck {
        my ( $Self, %Param ) = @_;
        return if ( $Param{Password} || '' ) ne 'correct';
        return { id => 17, login => 'test', account_type => $Param{AccountType} };
    }
}

{
    package Local::TicketReturnSession;
    sub new { return bless { Count => 0 }, shift }
    sub Create { my ($Self) = @_; $Self->{Count}++; return { Token => 'new-session' } }
}

{
    package Local::TicketReturnTwoFactor;
    sub new { return bless { Required => 0, RecoveryCodes => [] }, shift }
    sub Required { return shift->{Required} }
    sub ChallengeCreate { return { Token => 'challenge-token', Mode => 'login' } }
    sub ChallengeVerify {
        my ( $Self, %Param ) = @_;
        return if ( $Param{Code} || '' ) ne '123456';
        return {
            User => { user_account_id => 17, login => 'test', account_type => 'agent' },
            RecoveryCodes => $Self->{RecoveryCodes},
        };
    }
    sub Error { return 'Translate:TwoFactorCodeInvalid' }
}

{
    package Local::TicketReturnDB;
    sub new { return bless { Rows => {}, NextID => 0 }, shift }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ m{INSERT INTO addon_auth_state} ) {
            $Self->{Rows}->{ $Bind[0] } = {
                id => ++$Self->{NextID}, state_hash => $Bind[0], provider_key => $Bind[1],
                nonce_encrypted => $Bind[2], verifier_encrypted => $Bind[3], return_location => $Bind[4],
            };
        }
        elsif ( $SQL =~ m{DELETE FROM addon_auth_state WHERE id =} ) {
            for my $State ( keys %{ $Self->{Rows} } ) {
                delete $Self->{Rows}->{$State} if $Self->{Rows}->{$State}->{id} == $Bind[0];
            }
        }
        return 1;
    }
    sub SelectRow { my ( $Self, $SQL, $State ) = @_; return $Self->{Rows}->{$State} }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
}

{
    package Local::TicketReturnProvider;
    sub new { return bless {}, shift }
    sub AuthorizationURL {
        my ( $Self, %Param ) = @_;
        $Self->{LastState} = $Param{State};
        return 'https://login.example.test/authorize?state=' . $Param{State};
    }
    sub Authenticate {
        my ($Self) = @_;
        return if $Self->{Fail};
        return { id => 17, login => 'test', account_type => 'agent' };
    }
    sub Error { return 'Translate:ExternalAuthLoginFailed' }
}

{
    package Local::TicketReturnExternalAuth;
    our @ISA = ('QisutuAuthProvider');
    sub ProviderList {
        my ($Self) = @_;
        return [{
            key => 'entra-agent', begin_url => 'index.pl?Step=ExternalAuthBegin;Provider=entra-agent',
            label => 'Microsoft Entra ID', allow_local_login => 1,
            auto_redirect => $Self->{AutoRedirect} || 0,
        }];
    }
    sub _ProviderObject { return shift->{Provider} }
    sub _RedirectURI { return 'https://tickets.example.test/index.pl?Step=ExternalAuthCallback' }
}

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my $Config = {
    RootPath => $Root,
    Paths => {
        Output => File::Spec->catdir( $Root, 'core', 'output' ),
        Language => File::Spec->catdir( $Root, 'core', 'language' ), StaticURL => '/static',
    },
    Language => { Default => 'de' }, System => { Name => 'Qisutu' },
    Session => { CookieName => 'QisutuSession', LifetimeSeconds => 3600 },
};
my $Security = Local::TicketReturnSecurity->new();
my $DB = Local::TicketReturnDB->new();
my $Provider = Local::TicketReturnProvider->new();
my $ExternalAuth = Local::TicketReturnExternalAuth->new( Config => $Config, DB => $DB, Security => $Security );
$ExternalAuth->{Provider} = $Provider;
my $Session = Local::TicketReturnSession->new();
my $TwoFactor = Local::TicketReturnTwoFactor->new();
my $Login = Login->new(
    Config => $Config, Output => QisutuOutput->new( Config => $Config ), Security => $Security,
    Auth => Local::TicketReturnAuth->new(), Session => $Session, TwoFactor => $TwoFactor,
    ExternalAuth => $ExternalAuth, PasswordReset => bless({}, 'Local::Unused'),
    CustomerRegistration => bless({}, 'Local::Unused'),
);
my $Target = 'index.pl?Page=AgentTicketZoom&TicketID=90';
my $EscapedTarget = 'index.pl?Page=AgentTicketZoom&amp;TicketID=90';
my $EncodedTarget = 'index.pl%3FPage%3DAgentTicketZoom%26TicketID%3D90';

my $Initial = $Login->Run( Page => 'AgentTicketZoom', TicketID => 90, Language => 'de', __RequestMethod => 'GET' );
is( scalar( () = $Initial =~ m{name="ReturnLocation" value="\Q$EscapedTarget\E"}g ), 2,
    'the ticket link survives in both the language form and the password form' );
like( $Initial, qr{Provider=entra-agent;Language=de;ReturnLocation=\Q$EncodedTarget\E},
    'the external sign-in link carries one URL-encoded destination' );

my %Password = ( Step => 'Login', Login => 'test', AccountType => 'agent', __RequestMethod => 'POST', ReturnLocation => $Target );
my $Failed = $Login->Run( %Password, Password => 'wrong' );
like( $Failed, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'failed password authentication preserves the ticket' );
is( $Session->{Count}, 0, 'failed password authentication creates no session' );
my $Success = $Login->Run( %Password, Password => 'correct', SuccessLocation => 'index.pl' );
like( $Success, qr{\r\nLocation: \Q$Target\E\r\n}, 'password authentication returns to the original ticket' );

my $Language = $Login->Run( Step => 'LocalLogin', Language => 'fr', ReturnLocation => $Target );
like( $Language, qr{<html lang="fr">}, 'the language can change before signing in' );
like( $Language, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'changing language preserves the ticket' );
my $Plain = $Login->Run( Step => 'Login', Password => 'correct', SuccessLocation => 'index.pl' );
like( $Plain, qr{\r\nLocation: index[.]pl\r\n}, 'a normal login still uses the configured start page without a stale ticket' );
my $Post = $Login->Run( Page => 'AgentTicketZoom', TicketID => 90, __RequestMethod => 'POST' );
unlike( $Post, qr{name="ReturnLocation" value="index[.]pl[?]}, 'an expired POST does not replay a submitted ticket action' );

my $Customer = $Login->Run( Page => 'CustomerTicketZoom', TicketID => 42 );
like( $Customer, qr{name="AccountType" value="customer" checked}, 'a customer ticket link selects customer login' );
my $CustomerTarget = 'index.pl?Page=CustomerTicketZoom&TicketID=42';
my $CustomerLogin = $Login->Run( %Password, AccountType => 'customer', ReturnLocation => $CustomerTarget, Password => 'correct' );
like( $CustomerLogin, qr{\r\nLocation: \Q$CustomerTarget\E\r\n}, 'customer authentication keeps the customer ticket route' );

for my $Invalid (
    'https://evil.example/', '//evil.example/', 'javascript:alert(1)',
    "index.pl?Page=AgentTicketZoom&TicketID=90\r\nInjected: header",
    'index.pl?Page=AgentTicketZoom&TicketID=90&Action=Delete',
    'index.pl?Page=AgentTicketZoom&TicketID=90%26Action%3DDelete',
    'index.pl?Page=Logout&TicketID=90', 'index.pl?Page=AgentTicketZoom&TicketID=-1',
    'index.pl?Page=AgentTicketZoom&TicketID=0', 'index.pl?Page=AgentTicketZoom&TicketID=' . ('9' x 2000),
    [ $Target ], { Location => $Target },
) {
    is( QisutuAuthProvider->ReturnLocationClean($Invalid), '', 'invalid, external or action-bearing destinations are rejected' );
}
my $InvalidLogin = $Login->Run( %Password, Password => 'correct', ReturnLocation => '//evil.example/' );
like( $InvalidLogin, qr{\r\nLocation: index[.]pl\r\n}, 'untrusted return URLs cannot turn sign-in into an open redirect' );
is( QisutuAuthProvider->ReturnLocationClean('index.pl?Page=AgentTicketZoom;TicketID=90'), $Target,
    'the alternate query separator is normalized' );

$TwoFactor->{Required} = 1;
my $BeforeChallenge = $Session->{Count};
my $Challenge = $Login->Run( %Password, Password => 'correct' );
like( $Challenge, qr{name="Step" value="TwoFactorVerify"}, 'two-factor authentication is still required' );
like( $Challenge, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'the second-factor form preserves the ticket' );
is( $Session->{Count}, $BeforeChallenge, 'a ticket destination does not bypass two-factor authentication' );
my %TwoFactorRequest = ( Step => 'TwoFactorVerify', ChallengeToken => 'challenge-token', ReturnLocation => $Target );
my $WrongCode = $Login->Run( %TwoFactorRequest, TwoFactorCode => '000000' );
like( $WrongCode, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'an invalid second factor retains the destination for retry' );
is( $Session->{Count}, $BeforeChallenge, 'an invalid second factor does not create a session' );
my $CorrectCode = $Login->Run( %TwoFactorRequest, TwoFactorCode => '123456' );
like( $CorrectCode, qr{\r\nLocation: \Q$Target\E\r\n}, 'a valid second factor returns to the ticket' );
$TwoFactor->{RecoveryCodes} = [ 'example-recovery-code' ];
my $Recovery = $Login->Run( %TwoFactorRequest, TwoFactorCode => '123456' );
like( $Recovery, qr{href="\Q$EscapedTarget\E"}, 'after initial setup the recovery-code continue link returns to the ticket' );
$TwoFactor->{RecoveryCodes} = [];
$TwoFactor->{Required} = 0;

$ExternalAuth->{AutoRedirect} = 1;
my $Automatic = $Login->Run( Page => 'AgentTicketZoom', TicketID => 90 );
like( $Automatic, qr{Location: index[.]pl[?]Step=ExternalAuthBegin;Provider=entra-agent;Language=en;ReturnLocation=\Q$EncodedTarget\E},
    'automatic Entra sign-in preserves the notification destination' );
my $AutomaticCustomer = $Login->Run( Page => 'CustomerTicketZoom', TicketID => 42 );
unlike( $AutomaticCustomer, qr{Location:}, 'an agent-only automatic provider does not intercept a customer ticket link' );
$ExternalAuth->{AutoRedirect} = 0;

sub StartExternal {
    $Login->Run( Step => 'ExternalAuthBegin', Provider => 'entra-agent', ReturnLocation => $Target );
    return $Provider->{LastState};
}
my $State = StartExternal();
is( $DB->{Rows}->{ sha256_hex($State) }->{return_location}, $Target,
    'the destination is stored in the existing server-side OAuth state' );
my $External = $Login->Run( Step => 'ExternalAuthCallback', state => $State, code => 'valid-code', ReturnLocation => $CustomerTarget );
like( $External, qr{\r\nLocation: \Q$Target\E\r\n}, 'the callback uses the saved destination, ignoring a supplied callback destination' );
ok( !exists $DB->{Rows}->{ sha256_hex($State) }, 'the OAuth state remains single-use' );

my $BeforeReplay = $Session->{Count};
my $Replay = $Login->Run( Step => 'ExternalAuthCallback', state => $State, code => 'valid-code', ReturnLocation => $Target );
unlike( $Replay, qr{Location:}, 'a consumed state cannot complete another sign-in' );
unlike( $Replay, qr{name="ReturnLocation" value="index[.]pl[?]}, 'an invalid callback cannot inject a return destination' );
is( $Session->{Count}, $BeforeReplay, 'a replayed state does not create another session' );

$State = StartExternal();
my $Cancelled = $Login->Run( Step => 'ExternalAuthCallback', state => $State, error => 'access_denied' );
like( $Cancelled, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'cancelling external authentication retains the ticket for another login attempt' );
is( $Session->{Count}, $BeforeReplay, 'a cancelled external authentication does not create a session' );

$State = StartExternal();
$Provider->{Fail} = 1;
my $ProviderFailure = $Login->Run( Step => 'ExternalAuthCallback', state => $State, code => 'invalid-code' );
like( $ProviderFailure, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'a provider authentication failure retains the ticket for retry' );
is( $Session->{Count}, $BeforeReplay, 'provider authentication failure does not create a session' );
$Provider->{Fail} = 0;

$State = StartExternal();
$TwoFactor->{Required} = 1;
my $ExternalChallenge = $Login->Run( Step => 'ExternalAuthCallback', state => $State, code => 'valid-code' );
like( $ExternalChallenge, qr{name="ReturnLocation" value="\Q$EscapedTarget\E"}, 'SSO hands its stored destination to the second-factor form' );
is( $Session->{Count}, $BeforeReplay, 'SSO still waits for the second factor before creating a session' );

done_testing();
