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

package QisutuPasswordReset;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use File::Spec;
use QisutuMail;
use QisutuOutput;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub RequestCreate {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || '';
    my $UserInput   = $Self->_Trim( $Param{UserInput} || '' );
    my $IPAddress   = $Self->_IPAddressClean( $Param{IPAddress} || '' );
    my $UserAgent   = $Self->_UserAgentClean( $Param{UserAgent} || '' );

    if ( $AccountType ne 'agent' && $AccountType ne 'customer' ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordForgotAccountTypeRequired',
        );
    }

    if ( !$UserInput ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordForgotUserRequired',
        );
    }

    if ( length $UserInput > 255 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordForgotUserRequired',
        );
    }

    $Self->_ExpiredDataCleanup();

    my $User = $Self->_UserFind(
        AccountType => $AccountType,
        UserInput   => $UserInput,
    );

    # The public result deliberately does not disclose whether an account exists.
    return $Self->_Result( Success => 1 ) if !$User;

    if (
        $Self->_RateLimitReached(
            UserAccountID => $User->{id},
            IPAddress     => $IPAddress,
        )
        )
    {
        return $Self->_Result( Success => 1 );
    }

    my $BaseURL = $Self->_BaseURL();
    if ( !$BaseURL ) {
        $Self->_Log('Password reset e-mail was not sent because the public Qisutu base URL is not configured.');
        return $Self->_Result( Success => 1 );
    }

    my $SMTPAccount = $Self->_ActiveSMTPAccount();
    my $SystemEmail = $Self->_ActiveSystemEmail();

    if ( !$SMTPAccount || !$SystemEmail ) {
        $Self->_Log('Password reset e-mail was not sent because an active SMTP transport or system e-mail address is missing.');
        return $Self->_Result( Success => 1 );
    }

    my $Token     = $Self->_TokenCreate();
    my $TokenHash = sha256_hex($Token);
    my $Lifetime  = 60;

    $Self->{DB}->Do(
        'UPDATE password_reset_token
         SET invalidated_at = NOW()
         WHERE user_account_id = ?
           AND used_at IS NULL
           AND invalidated_at IS NULL',
        $User->{id},
    );

    my $Created = $Self->{DB}->Do(
        'INSERT INTO password_reset_token (
            user_account_id,
            token_hash,
            requested_ip,
            user_agent,
            created_at,
            expires_at
         ) VALUES (
            ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? MINUTE)
         )',
        $User->{id},
        $TokenHash,
        $IPAddress || undef,
        $UserAgent || undef,
        $Lifetime,
    );

    if ( !$Created ) {
        $Self->_Log( 'Password reset token could not be stored: ' . ( $Self->{DB}->Error() || 'unknown database error' ) );
        return $Self->_Result( Success => 1 );
    }

    my $TokenID = $Self->{DB}->LastInsertID('password_reset_token') || 0;
    my $Language = $Self->_UserLanguage( UserAccountID => $User->{id} );
    my $ResetURL = $BaseURL . '/index.pl?Step=PasswordReset&Token=' . $Token
        . '&Language=' . $Language;
    my $Mail      = $Self->_ResetMailBuild(
        User      => $User,
        Language  => $Language,
        ResetURL  => $ResetURL,
        Lifetime  => $Lifetime,
    );

    if ( !$Mail ) {
        if ($TokenID) {
            $Self->{DB}->Do(
                'UPDATE password_reset_token
                 SET invalidated_at = NOW()
                 WHERE id = ?',
                $TokenID,
            );
        }

        return $Self->_Result( Success => 1 );
    }

    my $SendResult = QisutuMail->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->SMTPSend(
        Account      => $SMTPAccount,
        Operation    => 'password_reset',
        FromName     => $SystemEmail->{name} || $Self->_SystemName(),
        FromEmail    => $SystemEmail->{email},
        EnvelopeFrom => $SMTPAccount->{smtp_username} || $SystemEmail->{email},
        ToName       => $Self->_UserDisplayName($User),
        ToEmail      => $User->{email},
        Subject      => $Mail->{Subject},
        Body         => $Mail->{HTML},
        PlainBody    => $Mail->{Text},
        InlineImages => $Self->_MailInlineImages(),
    );

    if ( !$SendResult || !$SendResult->{Success} ) {
        if ($TokenID) {
            $Self->{DB}->Do(
                'UPDATE password_reset_token
                 SET invalidated_at = NOW()
                 WHERE id = ?',
                $TokenID,
            );
        }

        $Self->_Log(
            'Password reset e-mail could not be sent: '
                . ( $SendResult && $SendResult->{Message} ? $SendResult->{Message} : 'unknown SMTP error' )
        );

        return $Self->_Result( Success => 1 );
    }

    if ($TokenID) {
        $Self->{DB}->Do(
            'UPDATE password_reset_token
             SET mail_sent_at = NOW()
             WHERE id = ?',
            $TokenID,
        );
    }

    return $Self->_Result( Success => 1 );
}

sub TokenGet {
    my ( $Self, %Param ) = @_;

    my $Token = $Self->_TokenClean( $Param{Token} || '' );
    return if !$Token;

    my $TokenHash = sha256_hex($Token);

    return $Self->{DB}->SelectRow(
        'SELECT
            prt.id AS token_id,
            prt.user_account_id,
            prt.created_at,
            prt.expires_at,
            ua.login,
            ua.account_type,
            ua.email,
            ua.firstname,
            ua.lastname
         FROM password_reset_token prt
         INNER JOIN user_account ua
            ON ua.id = prt.user_account_id
         WHERE prt.token_hash = ?
           AND prt.used_at IS NULL
           AND prt.invalidated_at IS NULL
           AND prt.expires_at > NOW()
           AND ua.is_active = 1
           AND ua.is_system_user = 0
           AND ua.account_type IN ("agent", "customer")
         LIMIT 1',
        $TokenHash,
    );
}

sub PasswordSet {
    my ( $Self, %Param ) = @_;

    my $Token          = $Self->_TokenClean( $Param{Token} || '' );
    my $NewPassword    = defined $Param{NewPassword} ? $Param{NewPassword} : '';
    my $RepeatPassword = defined $Param{RepeatPassword} ? $Param{RepeatPassword} : '';

    if ( !$Token ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetInvalid',
        );
    }

    if ( !$NewPassword || !$RepeatPassword ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetAllFieldsRequired',
        );
    }

    if ( length $NewPassword < 8 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetTooShort',
        );
    }

    if ( length $NewPassword > 4096 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetTooLong',
        );
    }

    if ( $NewPassword ne $RepeatPassword ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetRepeatMismatch',
        );
    }

    my $TokenHash   = sha256_hex($Token);
    my $PasswordHash = $Self->_PasswordHash( Password => $NewPassword );

    if ( !$PasswordHash ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetCouldNotBeSaved',
        );
    }

    my $User;
    my $TransactionStarted = 0;
    my $TransactionOK      = eval {
        $Self->{DB}->BeginWork() || die "Database transaction could not be started\n";
        $TransactionStarted = 1;

        $User = $Self->{DB}->SelectRow(
            'SELECT
                prt.id AS token_id,
                prt.user_account_id,
                ua.login,
                ua.account_type,
                ua.email,
                ua.firstname,
                ua.lastname
             FROM password_reset_token prt
             INNER JOIN user_account ua
                ON ua.id = prt.user_account_id
             WHERE prt.token_hash = ?
               AND prt.used_at IS NULL
               AND prt.invalidated_at IS NULL
               AND prt.expires_at > NOW()
               AND ua.is_active = 1
               AND ua.is_system_user = 0
               AND ua.account_type IN ("agent", "customer")
               AND ua.authentication_type = "local"
             LIMIT 1
             FOR UPDATE',
            $TokenHash,
        );

        die "Password reset token is invalid or expired\n" if !$User;

        $Self->{DB}->Do(
            'UPDATE user_account
             SET password_hash = ?,
                 failed_login_count = 0,
                 locked_until = NULL,
                 password_changed_at = NOW(),
                 updated_at = NOW()
             WHERE id = ?',
            $PasswordHash,
            $User->{user_account_id},
        ) || die "Password could not be stored\n";

        $Self->{DB}->Do(
            'UPDATE user_session
             SET is_active = 0
             WHERE user_account_id = ?
               AND is_active = 1',
            $User->{user_account_id},
        ) || die "User sessions could not be invalidated\n";

        $Self->{DB}->Do(
            'UPDATE password_reset_token
             SET used_at = NOW()
             WHERE id = ?',
            $User->{token_id},
        ) || die "Password reset token could not be marked as used\n";

        $Self->{DB}->Do(
            'UPDATE password_reset_token
             SET invalidated_at = NOW()
             WHERE user_account_id = ?
               AND id <> ?
               AND used_at IS NULL
               AND invalidated_at IS NULL',
            $User->{user_account_id},
            $User->{token_id},
        ) || die "Other password reset tokens could not be invalidated\n";

        $Self->{DB}->Commit() || die "Database transaction could not be committed\n";
        $TransactionStarted = 0;

        1;
    };

    if ( !$TransactionOK ) {
        my $Error = $@ || $Self->{DB}->Error() || 'unknown password reset error';
        $Self->{DB}->Rollback() if $TransactionStarted;

        if ( $Error =~ m{invalid or expired}i ) {
            return $Self->_Result(
                Success => 0,
                Error   => 'Translate:PasswordResetInvalid',
            );
        }

        $Self->_Log( 'Password could not be reset: ' . $Error );

        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:PasswordResetCouldNotBeSaved',
        );
    }

    $Self->_PasswordChangedMailSend( User => $User );

    return $Self->_Result(
        Success => 1,
        UserID  => $User->{user_account_id},
    );
}

sub _UserFind {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || '';
    my $UserInput   = $Param{UserInput}   || '';

    my $User = $Self->{DB}->SelectRow(
        'SELECT id, login, account_type, email, firstname, lastname
         FROM user_account
         WHERE login = ?
           AND account_type = ?
           AND authentication_type = "local"
           AND is_active = 1
           AND is_system_user = 0
           AND email <> ""
         LIMIT 1',
        $UserInput,
        $AccountType,
    );

    return $User if $User;

    return $Self->{DB}->SelectRow(
        'SELECT id, login, account_type, email, firstname, lastname
         FROM user_account
         WHERE LOWER(email) = LOWER(?)
           AND account_type = ?
           AND authentication_type = "local"
           AND is_active = 1
           AND is_system_user = 0
           AND email <> ""
         LIMIT 1',
        $UserInput,
        $AccountType,
    );
}

sub _RateLimitReached {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $IPAddress     = $Param{IPAddress} || '';

    my $UserCount = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS request_count
         FROM password_reset_token
         WHERE user_account_id = ?
           AND created_at >= DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
        $UserAccountID,
    );

    return 1 if $UserCount && ( $UserCount->{request_count} || 0 ) >= 3;

    if ($IPAddress) {
        my $IPCount = $Self->{DB}->SelectRow(
            'SELECT COUNT(*) AS request_count
             FROM password_reset_token
             WHERE requested_ip = ?
               AND created_at >= DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
            $IPAddress,
        );

        return 1 if $IPCount && ( $IPCount->{request_count} || 0 ) >= 3;
    }

    return 0;
}

sub _ExpiredDataCleanup {
    my ($Self) = @_;

    $Self->{DB}->Do(
        'DELETE FROM password_reset_token
         WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)'
    );

    return 1;
}

sub _PasswordChangedMailSend {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};
    return if !$User->{email};

    my $SMTPAccount = $Self->_ActiveSMTPAccount();
    my $SystemEmail = $Self->_ActiveSystemEmail();

    if ( !$SMTPAccount || !$SystemEmail ) {
        $Self->_Log('Password change confirmation e-mail was not sent because an active SMTP transport or system e-mail address is missing.');
        return;
    }

    my $Language = $Self->_UserLanguage( UserAccountID => $User->{user_account_id} );
    my $Mail = $Self->_ChangedMailBuild(
        User     => $User,
        Language => $Language,
    );

    return if !$Mail;

    my $SendResult = QisutuMail->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->SMTPSend(
        Account      => $SMTPAccount,
        Operation    => 'password_changed',
        FromName     => $SystemEmail->{name} || $Self->_SystemName(),
        FromEmail    => $SystemEmail->{email},
        EnvelopeFrom => $SMTPAccount->{smtp_username} || $SystemEmail->{email},
        ToName       => $Self->_UserDisplayName($User),
        ToEmail      => $User->{email},
        Subject      => $Mail->{Subject},
        Body         => $Mail->{HTML},
        PlainBody    => $Mail->{Text},
        InlineImages => $Self->_MailInlineImages(),
    );

    if ( !$SendResult || !$SendResult->{Success} ) {
        $Self->_Log(
            'Password change confirmation e-mail could not be sent: '
                . ( $SendResult && $SendResult->{Message} ? $SendResult->{Message} : 'unknown SMTP error' )
        );
    }

    return 1;
}

sub _ResetMailBuild {
    my ( $Self, %Param ) = @_;

    my $Language = $Self->_LanguageClean( $Param{Language} || '' );
    my $Text     = $Self->_MailText($Language);
    my $User     = $Param{User} || {};
    my $ResetURL = $Param{ResetURL} || '';
    my $Lifetime = $Param{Lifetime} || 60;
    my $Name     = $Self->_UserDisplayName($User);

    my $Greeting = $Text->{Greeting};
    $Greeting =~ s{\{name\}}{$Name}g;

    my $Validity = $Text->{Validity};
    $Validity =~ s{\{minutes\}}{$Lifetime}g;

    my $HTML = $Self->_MailTemplateRender(
        Template => 'PasswordResetEmail.tt',
        Data     => {
            Language     => $Language,
            SystemName   => $Self->_SystemName(),
            Greeting     => $Greeting,
            RequestIntro => $Text->{RequestIntro},
            ResetURL     => $ResetURL,
            ButtonLabel  => $Text->{Button},
            Validity     => $Validity,
            IgnoreText   => $Text->{Ignore},
            LinkHint     => $Text->{LinkHint},
        },
    );

    return if !defined $HTML;

    my $Plain = join "\n\n",
        $Greeting,
        $Text->{RequestIntro},
        $Text->{Button} . ': ' . $ResetURL,
        $Validity,
        $Text->{Ignore};

    return {
        Subject => $Text->{ResetSubject},
        HTML    => $HTML,
        Text    => $Plain,
    };
}

sub _ChangedMailBuild {
    my ( $Self, %Param ) = @_;

    my $Language = $Self->_LanguageClean( $Param{Language} || '' );
    my $Text     = $Self->_MailText($Language);
    my $User     = $Param{User} || {};
    my $Name     = $Self->_UserDisplayName($User);

    my $Greeting = $Text->{Greeting};
    $Greeting =~ s{
        \{name\}
    }{$Name}gx;

    my $HTML = $Self->_MailTemplateRender(
        Template => 'PasswordChangedEmail.tt',
        Data     => {
            Language       => $Language,
            SystemName     => $Self->_SystemName(),
            Greeting       => $Greeting,
            ChangedIntro   => $Text->{ChangedIntro},
            ChangedWarning => $Text->{ChangedWarning},
        },
    );

    return if !defined $HTML;

    my $Plain = join "\n\n",
        $Greeting,
        $Text->{ChangedIntro},
        $Text->{ChangedWarning};

    return {
        Subject => $Text->{ChangedSubject},
        HTML    => $HTML,
        Text    => $Plain,
    };
}

sub _MailTemplateRender {
    my ( $Self, %Param ) = @_;

    my $OutputConfig = { %{ $Self->{Config} || {} } };
    $OutputConfig->{Paths} = { %{ $Self->{Config}->{Paths} || {} } };

    if ( !$OutputConfig->{Paths}->{Output} && $Self->{Config}->{RootPath} ) {
        $OutputConfig->{Paths}->{Output} = $Self->{Config}->{RootPath} . '/core/output';
    }

    my $Output = QisutuOutput->new(
        Config => $OutputConfig,
    );

    my $HTML = $Output->RenderSingle(
        Template => $Param{Template} || '',
        Data     => $Param{Data} || {},
    );

    if ( !defined $HTML ) {
        $Self->_Log( 'Password e-mail template could not be rendered: ' . ( $Output->Error() || 'unknown template error' ) );
        return;
    }

    return $HTML;
}

sub _MailHTMLBuild {
    my ( $Self, %Param ) = @_;

    my $BodyHTML  = $Param{BodyHTML} || '';
    my $SystemName = $Self->_SystemName();

    return '<!doctype html><html><head><meta charset="utf-8"></head>'
        . '<body style="margin:0;padding:0;background:#f4f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2933;">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;margin:0;padding:0;background:#f4f7f9;border-collapse:collapse;">'
        . '<tr><td align="center" style="padding:0 12px 24px 12px;">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;max-width:760px;background:#ffffff;border:1px solid #d8e0e7;border-radius:8px;border-collapse:separate;overflow:hidden;">'
        . '<tr><td style="background:#015068;padding:12px 18px;">'
        . '<table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse;"><tr>'
        . '<td style="width:34px;padding:0 10px 0 0;vertical-align:middle;">'
        . '<img src="cid:qisutu-logo" alt="Qisutu" style="height:28px;max-height:28px;width:auto;display:block;border:0;outline:none;text-decoration:none;">'
        . '</td>'
        . '<td style="vertical-align:middle;color:#ffffff;font-size:20px;font-weight:bold;line-height:28px;">'
        . $Self->_Escape($SystemName)
        . '</td></tr></table>'
        . '</td></tr>'
        . '<tr><td style="padding:24px 28px;font-size:15px;line-height:1.55;">'
        . $BodyHTML
        . '</td></tr></table></td></tr></table></body></html>';
}

sub _MailInlineImages {
    my ($Self) = @_;

    my $LogoPath = $Self->_LogoFilePath();
    return [] if !$LogoPath;

    return [
        {
            ContentID => 'qisutu-logo',
            Path      => $LogoPath,
            Filename  => 'logo.png',
            MimeType  => 'image/png',
        },
    ];
}

sub _LogoFilePath {
    my ($Self) = @_;

    my @Paths;

    if ( $Self->{Config}->{Paths}->{Static} ) {
        push @Paths, $Self->{Config}->{Paths}->{Static} . '/img/logo.png';
    }

    if ( $Self->{Config}->{RootPath} ) {
        push @Paths, $Self->{Config}->{RootPath} . '/var/static/img/logo.png';
    }

    my %Seen;
    for my $Path (@Paths) {
        next if !$Path || $Seen{$Path}++;
        return $Path if -f $Path && -r $Path;
    }

    return '';
}

sub _BaseURL {
    my ($Self) = @_;

    my $BaseURL = QisutuSystemSetting->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->BaseURL() || '';

    $BaseURL =~ s{\A\s+|\s+\z}{}g;
    $BaseURL =~ s{/+\z}{};

    return '' if $BaseURL =~ m{[?#]};
    return '' if $BaseURL !~ m{\Ahttps?://[^\s/]+(?:/[^\s]*)?\z}i;
    return $BaseURL;
}

sub _ActiveSMTPAccount {
    my ($Self) = @_;

    return $Self->{DB}->SelectRow(
        'SELECT *
         FROM smtp_account
         WHERE active = 1
         ORDER BY sort_order ASC, id ASC
         LIMIT 1'
    );
}

sub _ActiveSystemEmail {
    my ($Self) = @_;

    return $Self->{DB}->SelectRow(
        'SELECT id, name, email
         FROM system_email
         WHERE active = 1
           AND email <> ""
         ORDER BY sort_order ASC, id ASC
         LIMIT 1'
    );
}

sub _UserLanguage {
    my ( $Self, %Param ) = @_;

    my $Language = '';
    my $Row = $Self->{DB}->SelectRow(
        'SELECT preference_value
         FROM user_preference
         WHERE user_account_id = ?
           AND preference_key = "language"
         LIMIT 1',
        $Param{UserAccountID} || 0,
    );

    if ($Row) {
        $Language = $Row->{preference_value} || '';
    }

    if (!$Language) {
        $Language = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        )->Get(
            Key     => 'system.default_language',
            Default => $Self->{Config}->{Language}->{Default} || 'en',
        ) || '';
    }

    return $Self->_LanguageClean($Language);
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    my $LanguagePath = $Self->{Config}->{Paths}->{Language} || '';
    if ( !$LanguagePath && $Self->{Config}->{RootPath} ) {
        $LanguagePath = File::Spec->catdir( $Self->{Config}->{RootPath}, 'core', 'language' );
    }

    for my $Candidate (
        $Language,
        $Self->{Config}->{Language}->{Default} || '',
        'en',
    ) {
        $Candidate = $Self->_LanguageCanonical($Candidate);
        next if !$Candidate;

        my $File = File::Spec->catfile( $LanguagePath, "$Candidate.pm" );
        return $Candidate if $LanguagePath && -f $File && !-l $File;
    }

    return 'en';
}

sub _LanguageCanonical {
    my ( $Self, $Language ) = @_;

    return '' if !defined $Language || ref $Language;
    $Language =~ s{\A\s+|\s+\z}{}g;
    $Language =~ tr{_}{-};
    return '' if $Language !~ m{\A[A-Za-z]{2,3}(?:-[A-Za-z]{2})?\z};

    if ( $Language =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
        return lc($1) . '-' . uc($2);
    }

    return lc $Language;
}

sub _MailText {
    my ( $Self, $Language ) = @_;

    my $OutputConfig = { %{ $Self->{Config} || {} } };
    $OutputConfig->{Paths} = { %{ $Self->{Config}->{Paths} || {} } };
    if ( !$OutputConfig->{Paths}->{Language} && $Self->{Config}->{RootPath} ) {
        $OutputConfig->{Paths}->{Language}
            = File::Spec->catdir( $Self->{Config}->{RootPath}, 'core', 'language' );
    }

    my $Output = QisutuOutput->new( Config => $OutputConfig );
    my %Key = (
        ResetSubject   => 'PasswordResetEmailSubject',
        ChangedSubject => 'PasswordChangedEmailSubject',
        Greeting       => 'PasswordEmailGreeting',
        RequestIntro   => 'PasswordResetEmailIntro',
        Button         => 'PasswordResetEmailButton',
        Validity       => 'PasswordResetEmailValidity',
        Ignore         => 'PasswordResetEmailIgnore',
        LinkHint       => 'PasswordResetEmailLinkHint',
        ChangedIntro   => 'PasswordChangedEmailIntro',
        ChangedWarning => 'PasswordChangedEmailWarning',
    );

    my %Text;
    for my $Field ( keys %Key ) {
        $Text{$Field} = $Output->Translate(
            Key      => $Key{$Field},
            Language => $Language,
        );
    }

    return \%Text;
}

sub _UserDisplayName {
    my ( $Self, $User ) = @_;

    my $Name = join ' ', grep { defined $_ && $_ ne '' } ( $User->{firstname}, $User->{lastname} );
    $Name = $User->{login} || $User->{email} || 'Qisutu user' if !$Name;
    $Name =~ s{\r|\n}{ }g;
    $Name =~ s{\s+}{ }g;
    $Name = $Self->_Trim($Name);

    return $Name;
}

sub _SystemName {
    my ($Self) = @_;

    return $Self->{Config}->{System}->{Name} || 'Qisutu';
}

sub _PasswordHash {
    my ( $Self, %Param ) = @_;

    my $Password = defined $Param{Password} ? $Param{Password} : '';
    return '' if !$Password;

    my @Chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '.', '/' );
    my $Random = $Self->_RandomBytes(16);
    my $Salt = '';

    for my $Index ( 0 .. 15 ) {
        my $Value = ord( substr( $Random, $Index, 1 ) || chr( int rand 256 ) );
        $Salt .= $Chars[ $Value % scalar @Chars ];
    }

    return crypt( $Password, '$6$' . $Salt . '$' );
}

sub _TokenCreate {
    my ($Self) = @_;

    return unpack 'H*', $Self->_RandomBytes(32);
}

sub _RandomBytes {
    my ( $Self, $Length ) = @_;

    $Length ||= 32;
    my $Random = '';

    if ( open my $RandomHandle, '<', '/dev/urandom' ) {
        binmode $RandomHandle;
        read $RandomHandle, $Random, $Length;
        close $RandomHandle;
    }

    while ( length $Random < $Length ) {
        $Random .= pack 'H*', sha256_hex( time() . $$ . rand() . {} . length($Random) );
    }

    return substr( $Random, 0, $Length );
}

sub _TokenClean {
    my ( $Self, $Token ) = @_;

    $Token = lc( $Token || '' );
    return '' if $Token !~ m{\A[0-9a-f]{64}\z};

    return $Token;
}

sub _IPAddressClean {
    my ( $Self, $IPAddress ) = @_;

    $IPAddress = $Self->_Trim($IPAddress);
    $IPAddress = substr( $IPAddress, 0, 45 ) if length $IPAddress > 45;
    $IPAddress =~ s{[^0-9A-Fa-f:.]}{}g;

    return $IPAddress;
}

sub _UserAgentClean {
    my ( $Self, $UserAgent ) = @_;

    $UserAgent =~ s{\r|\n}{}g;
    return substr( $UserAgent, 0, 255 );
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;

    return $Value;
}

sub _Result {
    my ( $Self, %Param ) = @_;

    return {
        Success => $Param{Success} ? 1 : 0,
        Error   => $Param{Error} || '',
        UserID  => $Param{UserID} || 0,
    };
}

sub _Log {
    my ( $Self, $Message ) = @_;

    $Message = '' if !defined $Message;
    $Message =~ s{\r|\n}{ }g;
    print STDERR '[QisutuPasswordReset] ' . $Message . "\n";

    return 1;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
