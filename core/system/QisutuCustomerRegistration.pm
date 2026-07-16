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

package QisutuCustomerRegistration;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
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

    my $Firstname = $Self->_Trim( $Param{Firstname} || '' );
    my $Lastname  = $Self->_Trim( $Param{Lastname}  || '' );
    my $Email     = $Self->_EmailClean( $Param{Email} || '' );
    my $Company   = $Self->_Trim( $Param{Company} || '' );
    my $Language  = $Self->_LanguageClean( $Param{Language} || '' );
    my $IPAddress = $Self->_IPAddressClean( $Param{IPAddress} || '' );
    my $UserAgent = $Self->_UserAgentClean( $Param{UserAgent} || '' );

    if ( !$Firstname || !$Lastname || !$Email || !$Company ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationAllFieldsRequired',
        );
    }

    if ( length $Firstname > 100 || length $Lastname > 100 || length $Company > 255 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationFieldTooLong',
        );
    }

    if ( !$Self->_EmailValid($Email) ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationEmailInvalid',
        );
    }

    $Self->_ExpiredDataCleanup();

    # Do not disclose whether the e-mail address already belongs to a customer user.
    return $Self->_Result( Success => 1 ) if $Self->_CustomerUserExists( Email => $Email );

    if (
        $Self->_RateLimitReached(
            Email     => $Email,
            IPAddress => $IPAddress,
        )
        )
    {
        return $Self->_Result( Success => 1 );
    }

    my $BaseURL = $Self->_BaseURL();
    if ( !$BaseURL ) {
        $Self->_Log('Customer registration e-mail was not sent because the public Qisutu base URL is not configured.');
        return $Self->_Result( Success => 1 );
    }

    my $SMTPAccount = $Self->_ActiveSMTPAccount();
    my $SystemEmail = $Self->_ActiveSystemEmail();

    if ( !$SMTPAccount || !$SystemEmail ) {
        $Self->_Log('Customer registration e-mail was not sent because an active SMTP transport or system e-mail address is missing.');
        return $Self->_Result( Success => 1 );
    }

    my $Token     = $Self->_TokenCreate();
    my $TokenHash = sha256_hex($Token);
    my $Lifetime  = 60;

    $Self->{DB}->Do(
        'UPDATE customer_registration_request
         SET invalidated_at = NOW()
         WHERE LOWER(email) = LOWER(?)
           AND used_at IS NULL
           AND invalidated_at IS NULL',
        $Email,
    );

    my $Created = $Self->{DB}->Do(
        'INSERT INTO customer_registration_request (
            firstname,
            lastname,
            email,
            company,
            language,
            token_hash,
            requested_ip,
            user_agent,
            created_at,
            expires_at
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? MINUTE)
         )',
        $Firstname,
        $Lastname,
        $Email,
        $Company,
        $Language,
        $TokenHash,
        $IPAddress || undef,
        $UserAgent || undef,
        $Lifetime,
    );

    if ( !$Created ) {
        $Self->_Log( 'Customer registration request could not be stored: ' . ( $Self->{DB}->Error() || 'unknown database error' ) );
        return $Self->_Result( Success => 1 );
    }

    my $RequestID = $Self->{DB}->LastInsertID('customer_registration_request') || 0;
    my $RegistrationURL = $BaseURL . '/index.pl?Step=CustomerRegistrationPassword&Token=' . $Token;
    my $Mail = $Self->_RegistrationMailBuild(
        Firstname       => $Firstname,
        Lastname        => $Lastname,
        Email           => $Email,
        Company         => $Company,
        Language        => $Language,
        RegistrationURL => $RegistrationURL,
        Lifetime        => $Lifetime,
    );

    if ( !$Mail ) {
        $Self->_RequestInvalidate( RequestID => $RequestID );
        return $Self->_Result( Success => 1 );
    }

    my $SendResult = QisutuMail->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->SMTPSend(
        Account      => $SMTPAccount,
        FromName     => $SystemEmail->{name} || $Self->_SystemName(),
        FromEmail    => $SystemEmail->{email},
        EnvelopeFrom => $SMTPAccount->{smtp_username} || $SystemEmail->{email},
        ToName       => join( ' ', $Firstname, $Lastname ),
        ToEmail      => $Email,
        Subject      => $Mail->{Subject},
        Body         => $Mail->{HTML},
        PlainBody    => $Mail->{Text},
        InlineImages => $Self->_MailInlineImages(),
    );

    if ( !$SendResult || !$SendResult->{Success} ) {
        $Self->_RequestInvalidate( RequestID => $RequestID );
        $Self->_Log(
            'Customer registration e-mail could not be sent: '
                . ( $SendResult && $SendResult->{Message} ? $SendResult->{Message} : 'unknown SMTP error' )
        );
        return $Self->_Result( Success => 1 );
    }

    if ($RequestID) {
        $Self->{DB}->Do(
            'UPDATE customer_registration_request
             SET mail_sent_at = NOW()
             WHERE id = ?',
            $RequestID,
        );
    }

    return $Self->_Result( Success => 1 );
}

sub TokenGet {
    my ( $Self, %Param ) = @_;

    my $Token = $Self->_TokenClean( $Param{Token} || '' );
    return if !$Token;

    return $Self->{DB}->SelectRow(
        'SELECT id, firstname, lastname, email, company, language, created_at, expires_at
         FROM customer_registration_request
         WHERE token_hash = ?
           AND used_at IS NULL
           AND invalidated_at IS NULL
           AND expires_at > NOW()
         LIMIT 1',
        sha256_hex($Token),
    );
}

sub RegistrationComplete {
    my ( $Self, %Param ) = @_;

    my $Token          = $Self->_TokenClean( $Param{Token} || '' );
    my $NewPassword    = defined $Param{NewPassword} ? $Param{NewPassword} : '';
    my $RepeatPassword = defined $Param{RepeatPassword} ? $Param{RepeatPassword} : '';

    if ( !$Token ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationInvalid',
        );
    }

    if ( !$NewPassword || !$RepeatPassword ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationPasswordAllFieldsRequired',
        );
    }

    if ( length $NewPassword < 8 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationPasswordTooShort',
        );
    }

    if ( length $NewPassword > 4096 ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationPasswordTooLong',
        );
    }

    if ( $NewPassword ne $RepeatPassword ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationPasswordMismatch',
        );
    }

    my $PasswordHash = $Self->_PasswordHash( Password => $NewPassword );
    if ( !$PasswordHash ) {
        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationCouldNotBeCompleted',
        );
    }

    my $TokenHash = sha256_hex($Token);
    my $Request;
    my $NewUserID = 0;
    my $TransactionStarted = 0;

    my $TransactionOK = eval {
        $Self->{DB}->BeginWork() || die "Database transaction could not be started\n";
        $TransactionStarted = 1;

        $Request = $Self->{DB}->SelectRow(
            'SELECT id, firstname, lastname, email, company, language, token_hash
             FROM customer_registration_request
             WHERE token_hash = ?
               AND used_at IS NULL
               AND invalidated_at IS NULL
               AND expires_at > NOW()
             LIMIT 1
             FOR UPDATE',
            $TokenHash,
        );

        die "REGISTRATION_INVALID\n" if !$Request;

        my $ExistingUser = $Self->{DB}->SelectRow(
            'SELECT id
             FROM user_account
             WHERE account_type = "customer"
               AND (LOWER(email) = LOWER(?) OR LOWER(login) = LOWER(?))
             LIMIT 1',
            $Request->{email},
            $Request->{email},
        );

        die "REGISTRATION_ACCOUNT_EXISTS\n" if $ExistingUser;

        my $CustomerNumber = $Self->_CustomerNumberCreate($Request);

        $Self->{DB}->Do(
            'INSERT INTO customer (
                customer_number,
                name,
                active,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, 1, 1, 1
             )',
            $CustomerNumber,
            $Request->{company},
        ) || die "Customer could not be created\n";

        my $CustomerID = $Self->{DB}->LastInsertID('customer') || 0;
        die "Customer ID could not be determined\n" if !$CustomerID;

        $Self->{DB}->Do(
            'INSERT INTO user_account (
                login,
                account_type,
                email,
                password_hash,
                firstname,
                lastname,
                is_active,
                is_system_user,
                failed_login_count,
                locked_until,
                password_changed_at
             ) VALUES (
                ?, "customer", ?, ?, ?, ?, 1, 0, 0, NULL, NOW()
             )',
            $Request->{email},
            $Request->{email},
            $PasswordHash,
            $Request->{firstname},
            $Request->{lastname},
        ) || die "Customer user account could not be created\n";

        $NewUserID = $Self->{DB}->LastInsertID('user_account') || 0;
        die "Customer user account ID could not be determined\n" if !$NewUserID;

        $Self->{DB}->Do(
            'INSERT INTO customer_user (
                customer_id,
                user_account_id,
                active,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, 1, 1, 1
             )',
            $CustomerID,
            $NewUserID,
        ) || die "Customer user could not be created\n";

        my $CustomerUserID = $Self->{DB}->LastInsertID('customer_user') || 0;
        die "Customer user ID could not be determined\n" if !$CustomerUserID;

        $Self->{DB}->Do(
            'UPDATE ticket t
             SET t.customer_id = ?,
                 t.customer_user_id = ?,
                 t.changed_by_user_id = 1,
                 t.changed_at = t.changed_at
             WHERE t.customer_user_id IS NULL
               AND (t.customer_id IS NULL OR t.customer_id = ?)
               AND EXISTS (
                    SELECT 1
                    FROM ticket_article ta
                    WHERE ta.ticket_id = t.id
                      AND ta.sender_type = "customer"
                      AND LOWER(TRIM(ta.from_email)) = LOWER(TRIM(?))
                    LIMIT 1
               )',
            $CustomerID,
            $CustomerUserID,
            $CustomerID,
            $Request->{email},
        ) || die "Existing tickets could not be assigned to the customer user\n";

        $Self->{DB}->Do(
            'INSERT INTO user_preference (
                user_account_id,
                preference_key,
                preference_value
             ) VALUES (
                ?, "language", ?
             )',
            $NewUserID,
            $Self->_LanguageClean( $Request->{language} || '' ),
        ) || die "Customer user language could not be stored\n";

        $Self->{DB}->Do(
            'UPDATE customer_registration_request
             SET used_at = NOW()
             WHERE id = ?',
            $Request->{id},
        ) || die "Customer registration request could not be marked as used\n";

        $Self->{DB}->Commit() || die "Database transaction could not be committed\n";
        $TransactionStarted = 0;

        1;
    };

    if ( !$TransactionOK ) {
        my $Error = $@ || $Self->{DB}->Error() || 'unknown customer registration error';
        $Self->{DB}->Rollback() if $TransactionStarted;

        if ( $Error =~ m{REGISTRATION_INVALID} ) {
            return $Self->_Result(
                Success => 0,
                Error   => 'Translate:CustomerRegistrationInvalid',
            );
        }

        if ( $Error =~ m{REGISTRATION_ACCOUNT_EXISTS} ) {
            return $Self->_Result(
                Success => 0,
                Error   => 'Translate:CustomerRegistrationAccountExists',
            );
        }

        $Self->_Log( 'Customer registration could not be completed: ' . $Error );

        return $Self->_Result(
            Success => 0,
            Error   => 'Translate:CustomerRegistrationCouldNotBeCompleted',
        );
    }

    return $Self->_Result(
        Success => 1,
        UserID  => $NewUserID,
        Login   => $Request->{email},
    );
}

sub _CustomerUserExists {
    my ( $Self, %Param ) = @_;

    my $Email = $Param{Email} || '';
    return if !$Email;

    return $Self->{DB}->SelectRow(
        'SELECT id
         FROM user_account
         WHERE account_type = "customer"
           AND (LOWER(email) = LOWER(?) OR LOWER(login) = LOWER(?))
         LIMIT 1',
        $Email,
        $Email,
    );
}

sub _RateLimitReached {
    my ( $Self, %Param ) = @_;

    my $Email     = $Param{Email} || '';
    my $IPAddress = $Param{IPAddress} || '';

    my $EmailCount = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS request_count
         FROM customer_registration_request
         WHERE LOWER(email) = LOWER(?)
           AND created_at >= DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
        $Email,
    );

    return 1 if $EmailCount && ( $EmailCount->{request_count} || 0 ) >= 3;

    if ($IPAddress) {
        my $IPCount = $Self->{DB}->SelectRow(
            'SELECT COUNT(*) AS request_count
             FROM customer_registration_request
             WHERE requested_ip = ?
               AND created_at >= DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
            $IPAddress,
        );

        return 1 if $IPCount && ( $IPCount->{request_count} || 0 ) >= 5;
    }

    return 0;
}

sub _ExpiredDataCleanup {
    my ($Self) = @_;

    $Self->{DB}->Do(
        'DELETE FROM customer_registration_request
         WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)'
    );

    return 1;
}

sub _RequestInvalidate {
    my ( $Self, %Param ) = @_;

    my $RequestID = $Param{RequestID} || 0;
    return if !$RequestID;

    $Self->{DB}->Do(
        'UPDATE customer_registration_request
         SET invalidated_at = NOW()
         WHERE id = ?',
        $RequestID,
    );

    return 1;
}

sub _RegistrationMailBuild {
    my ( $Self, %Param ) = @_;

    my $Language = $Self->_LanguageClean( $Param{Language} || '' );
    my $Output   = $Self->_OutputObject();
    return if !$Output;

    my $Name = join ' ', grep { $_ ne '' } ( $Param{Firstname} || '', $Param{Lastname} || '' );
    my $Greeting = $Self->_Translate(
        Output   => $Output,
        Key      => 'CustomerRegistrationEmailGreeting',
        Language => $Language,
    );
    $Greeting =~ s{\{name\}}{$Name}g;

    my $Validity = $Self->_Translate(
        Output   => $Output,
        Key      => 'CustomerRegistrationEmailValidity',
        Language => $Language,
    );
    my $Lifetime = $Param{Lifetime} || 60;
    $Validity =~ s{\{minutes\}}{$Lifetime}g;

    my %Text;
    for my $Key (qw(
        CustomerRegistrationEmailSubject
        CustomerRegistrationEmailIntro
        CustomerRegistrationEmailCompany
        CustomerRegistrationEmailUsername
        CustomerRegistrationEmailButton
        CustomerRegistrationEmailIgnore
        CustomerRegistrationEmailLinkHint
    )) {
        $Text{$Key} = $Self->_Translate(
            Output   => $Output,
            Key      => $Key,
            Language => $Language,
        );
    }

    my $HTML = $Output->RenderSingle(
        Template => 'CustomerRegistrationEmail.tt',
        Data     => {
            Language        => $Language,
            SystemName      => $Self->_SystemName(),
            Greeting        => $Greeting,
            IntroText       => $Text{CustomerRegistrationEmailIntro},
            CompanyLabel    => $Text{CustomerRegistrationEmailCompany},
            Company         => $Param{Company} || '',
            UsernameLabel   => $Text{CustomerRegistrationEmailUsername},
            Email           => $Param{Email} || '',
            RegistrationURL => $Param{RegistrationURL} || '',
            ButtonLabel     => $Text{CustomerRegistrationEmailButton},
            Validity        => $Validity,
            IgnoreText      => $Text{CustomerRegistrationEmailIgnore},
            LinkHint        => $Text{CustomerRegistrationEmailLinkHint},
        },
    );

    if ( !defined $HTML ) {
        $Self->_Log( 'Customer registration e-mail template could not be rendered: ' . ( $Output->Error() || 'unknown template error' ) );
        return;
    }

    my $Plain = join "\n\n",
        $Greeting,
        $Text{CustomerRegistrationEmailIntro},
        $Text{CustomerRegistrationEmailCompany} . ': ' . ( $Param{Company} || '' ),
        $Text{CustomerRegistrationEmailUsername} . ': ' . ( $Param{Email} || '' ),
        $Text{CustomerRegistrationEmailButton} . ': ' . ( $Param{RegistrationURL} || '' ),
        $Validity,
        $Text{CustomerRegistrationEmailIgnore};

    return {
        Subject => $Text{CustomerRegistrationEmailSubject},
        HTML    => $HTML,
        Text    => $Plain,
    };
}

sub _OutputObject {
    my ($Self) = @_;

    my $OutputConfig = { %{ $Self->{Config} || {} } };
    $OutputConfig->{Paths} = { %{ $Self->{Config}->{Paths} || {} } };

    if ( !$OutputConfig->{Paths}->{Output} && $Self->{Config}->{RootPath} ) {
        $OutputConfig->{Paths}->{Output} = $Self->{Config}->{RootPath} . '/core/output';
    }

    if ( !$OutputConfig->{Paths}->{Language} && $Self->{Config}->{RootPath} ) {
        $OutputConfig->{Paths}->{Language} = $Self->{Config}->{RootPath} . '/core/language';
    }

    return QisutuOutput->new( Config => $OutputConfig );
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    return $Param{Output}->Translate(
        Key      => $Param{Key} || '',
        Language => $Param{Language} || 'en',
    );
}

sub _CustomerNumberCreate {
    my ( $Self, $Request ) = @_;

    my $ID   = 0 + ( $Request->{id} || 0 );
    my $Hash = uc substr( $Request->{token_hash} || sha256_hex( time() . rand() ), 0, 12 );

    return sprintf( 'REG-%010d-%s', $ID, $Hash );
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

sub _EmailClean {
    my ( $Self, $Email ) = @_;

    $Email = $Self->_Trim($Email);
    $Email =~ s{\r|\n}{}g;

    return $Email;
}

sub _EmailValid {
    my ( $Self, $Email ) = @_;

    return if !$Email || length $Email > 255;
    return if $Email =~ m{\s};
    return if $Email !~ m{\A[^\@]+\@[^\@]+\.[^\@]+\z};

    return 1;
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

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    $Language = lc( $Language || '' );
    return $Language if $Language =~ m{\A(?:de|en|fr|it)\z};

    my $Default = lc( $Self->{Config}->{Language}->{Default} || 'en' );
    return $Default if $Default =~ m{\A(?:de|en|fr|it)\z};

    return 'en';
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

sub _SystemName {
    my ($Self) = @_;

    return $Self->{Config}->{System}->{Name} || 'Qisutu';
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub _Result {
    my ( $Self, %Param ) = @_;

    return {
        Success => $Param{Success} ? 1 : 0,
        Error   => $Param{Error} || '',
        UserID  => $Param{UserID} || 0,
        Login   => $Param{Login} || '',
    };
}

sub _Log {
    my ( $Self, $Message ) = @_;

    $Message = '' if !defined $Message;
    $Message =~ s{\r|\n}{ }g;
    print STDERR '[QisutuCustomerRegistration] ' . $Message . "\n";

    return 1;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
