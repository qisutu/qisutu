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

use Test::More;
use MIME::Base64 qw(decode_base64);
use FindBin;
use lib "$FindBin::Bin/../core/system";
use lib "$FindBin::Bin/../core/config";
use lib "$FindBin::Bin/../core/output";

use QisutuMail;
use QisutuOAuth2;
use QisutuOutput;

{
    package Local::SMTPDB;
    sub new { bless {}, shift }
    sub SelectRow {
        my ( $Self, $SQL ) = @_;
        return {
            id                         => 41,
            name                       => 'Microsoft SMTP',
            smtp_host                  => 'smtp.office365.com',
            smtp_username              => 'support@example.test',
            smtp_auth_type             => 'oauth2',
            oauth_provider             => 'microsoft',
            oauth_access_token         => 'access-token-value',
            oauth_refresh_token        => 'refresh-token-value',
            oauth_token_expires_epoch  => time() + 3600,
        } if $SQL =~ /FROM\s+smtp_account/i;
        return;
    }
    sub Error { return '' }
}

{
    package Local::SMTP;
    sub new { bless { command => [] }, shift }
    sub command {
        my ( $Self, @Command ) = @_;
        $Self->{command} = \@Command;
        return $Self;
    }
    sub response { return 2 }
    sub message { return '' }
}

my $OAuth = QisutuOAuth2->new();
my $Microsoft = $OAuth->ProviderDefinition(
    Provider    => 'microsoft',
    AccountType => 'smtp',
    Account     => { oauth_tenant_id => 'common' },
);
is( $Microsoft->{SMTPHost}, 'smtp.office365.com', 'Microsoft SMTP host is fixed' );
is( $Microsoft->{SMTPPort}, 587, 'Microsoft SMTP port is fixed' );
like( $Microsoft->{Scope}, qr{SMTP\.Send}, 'Microsoft SMTP OAuth scope requests SMTP.Send' );
unlike( $Microsoft->{Scope}, qr{IMAP\.AccessAsUser}, 'Microsoft SMTP OAuth scope is not the IMAP scope' );

my $Google = $OAuth->ProviderDefinition( Provider => 'google', AccountType => 'smtp' );
is( $Google->{SMTPHost}, 'smtp.gmail.com', 'Google SMTP host is fixed' );
is( $Google->{Scope}, 'https://mail.google.com/', 'Google mail OAuth scope supports SMTP XOAUTH2' );

my $SMTP = Local::SMTP->new();
my $Mail = QisutuMail->new( Config => {}, DB => Local::SMTPDB->new() );
my ( $OK, $Message ) = $Mail->_SMTPAuthenticate(
    SMTP => $SMTP,
    Account => {
        id             => 41,
        smtp_host      => 'smtp.office365.com',
        smtp_username  => 'support@example.test',
        smtp_auth_type => 'oauth2',
    },
);
ok( $OK, 'SMTP OAuth authentication succeeds with a valid stored access token' );
is( $Message, '', 'successful SMTP OAuth authentication has no error message' );
is( $SMTP->{command}->[0], 'AUTH', 'SMTP AUTH command is used' );
is( $SMTP->{command}->[1], 'XOAUTH2', 'SMTP AUTH uses XOAUTH2' );
my $Payload = decode_base64( $SMTP->{command}->[2] || '' );
like( $Payload, qr{\Auser=support\@example\.test\x01auth=Bearer access-token-value\x01\x01\z}, 'XOAUTH2 SASL payload contains mailbox and bearer token' );

my $Source = do {
    open my $FH, '<', "$FindBin::Bin/../core/system/QisutuMail.pm" or die $!;
    local $/;
    <$FH>;
};
unlike( $Source, qr{AdminOAuth2FlowMissing}, 'SMTP OAuth is no longer blocked as an unfinished flow' );

my $Migration = do {
    open my $FH, '<', "$FindBin::Bin/../install/update/database/0.0.22/001-enable-smtp-oauth2.sql" or die $!;
    local $/;
    <$FH>;
};
like( $Migration, qr{information_schema[.]COLUMNS}i, 'SMTP OAuth migration checks whether account_type already exists' );
like( $Migration, qr{information_schema[.]TABLE_CONSTRAINTS}i, 'SMTP OAuth migration conditionally removes the old IMAP foreign key' );
like( $Migration, qr{GROUP_CONCAT[(]COLUMN_NAME}, 'SMTP OAuth migration repairs the account index only when needed' );

my $TemplateSource = do {
    open my $FH, '<', "$FindBin::Bin/../core/output/AdminSMTPAccount.tt" or die $!;
    local $/;
    <$FH>;
};
unlike( $TemplateSource, qr{IF\s+IsMicrosoft\s*[|][|]\s*IsGoogle}, 'SMTP template uses no unsupported boolean expression' );
like( $TemplateSource, qr{IF\s+IsOAuth}, 'SMTP template uses the controller-provided OAuth flag' );

my $Output = QisutuOutput->new( Config => {
    Paths    => { Output => "$FindBin::Bin/../core/output", Language => "$FindBin::Bin/../core/language" },
    Language => { Default => 'de' },
} );

sub RenderSMTPForm {
    my (%Data) = @_;
    return $Output->RenderSingle(
        Template => 'AdminSMTPAccount.tt',
        Data     => {
            Language => 'de', ShowList => 0, ShowForm => 1, AccountList => [],
            FormAction => 'index.pl', CurrentPage => 'AdminSMTPStandard',
            FormStep => 'SMTPAccountCreate', FormTitle => 'SMTP-Konto anlegen',
            SubmitLabel => 'Translate:AdminCreate', AccountKind => 'standard',
            AccountSMTPPort => 587, AccountSortOrder => 1000,
            SMTPSecurityOptionsHTML => '<option value="smtp_starttls">SMTP STARTTLS (587)</option>',
            %Data,
        },
    );
}

my $StandardCreate = RenderSMTPForm( IsStandard => 1, IsOAuth => 0, ShowEdit => 0 );
unlike( $StandardCreate || '', qr{\[\%}, 'standard SMTP create form leaves no template directives behind' );
like( $StandardCreate || '', qr{id="qisutu-smtp-password"}, 'standard SMTP create form contains the password field' );
unlike( $StandardCreate || '', qr{id="qisutu-oauth-client-id"}, 'standard SMTP create form contains no OAuth client field' );
unlike( $StandardCreate || '', qr{SMTPAccountTest}, 'standard SMTP create form contains no edit-only connection actions' );

my $MicrosoftCreate = RenderSMTPForm(
    IsStandard => 0, IsMicrosoft => 1, IsGoogle => 0, IsOAuth => 1, ShowEdit => 0,
    CurrentPage => 'AdminSMTPMicrosoft365', AccountKind => 'microsoft',
);
unlike( $MicrosoftCreate || '', qr{\[\%}, 'Microsoft SMTP create form leaves no template directives behind' );
like( $MicrosoftCreate || '', qr{id="qisutu-oauth-tenant"}, 'Microsoft SMTP create form contains the tenant field' );
like( $MicrosoftCreate || '', qr{id="qisutu-oauth-client-id"}, 'Microsoft SMTP create form contains the OAuth client field' );
unlike( $MicrosoftCreate || '', qr{id="qisutu-smtp-password"}, 'Microsoft SMTP create form contains no password field' );
unlike( $MicrosoftCreate || '', qr{SMTPAccountTest}, 'Microsoft SMTP create form contains no edit-only connection actions' );

my $GoogleCreate = RenderSMTPForm(
    IsStandard => 0, IsMicrosoft => 0, IsGoogle => 1, IsOAuth => 1, ShowEdit => 0,
    CurrentPage => 'AdminSMTPGoogleMail', AccountKind => 'google',
);
unlike( $GoogleCreate || '', qr{\[\%}, 'Google SMTP create form leaves no template directives behind' );
like( $GoogleCreate || '', qr{id="qisutu-oauth-client-id"}, 'Google SMTP create form contains the OAuth client field' );
unlike( $GoogleCreate || '', qr{id="qisutu-oauth-tenant"}, 'Google SMTP create form contains no Microsoft tenant field' );
unlike( $GoogleCreate || '', qr{SMTPAccountTest}, 'Google SMTP create form contains no edit-only connection actions' );

my $StandardEdit = RenderSMTPForm( IsStandard => 1, IsOAuth => 0, ShowEdit => 1, FormStep => 'SMTPAccountUpdate' );
like( $StandardEdit || '', qr{SMTPAccountTest}, 'standard SMTP edit form contains the connection test' );
unlike( $StandardEdit || '', qr{SMTPOAuthReconnect|SMTPOAuthDisconnect}, 'standard SMTP edit form contains no OAuth actions' );

for my $Provider (qw(Microsoft Google)) {
    my $Edit = RenderSMTPForm(
        IsStandard => 0, IsMicrosoft => $Provider eq 'Microsoft' ? 1 : 0,
        IsGoogle => $Provider eq 'Google' ? 1 : 0, IsOAuth => 1, ShowEdit => 1,
        CurrentPage => $Provider eq 'Microsoft' ? 'AdminSMTPMicrosoft365' : 'AdminSMTPGoogleMail',
        AccountKind => lc($Provider), FormStep => 'SMTPAccountUpdate', AccountID => 41,
    );
    unlike( $Edit || '', qr{\[\%}, "$Provider SMTP edit form leaves no template directives behind" );
    like( $Edit || '', qr{SMTPAccountTest}, "$Provider SMTP edit form contains the connection test" );
    like( $Edit || '', qr{SMTPOAuthReconnect}, "$Provider SMTP edit form contains reconnect" );
    like( $Edit || '', qr{SMTPOAuthDisconnect}, "$Provider SMTP edit form contains disconnect" );
}

done_testing();
