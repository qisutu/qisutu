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

package AdminPostmasterIMAPAccounts;

use strict;
use warnings;
use utf8;

use QisutuAdmin;
use QisutuOAuth2;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config => $Param{Config},
        DB     => $Param{DB},
        Output => $Param{Output},
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request     = $Param{Request} || {};
    my $User        = $Param{User}    || {};
    my $Program     = $Param{Program} || {};
    my $ProgramName = $Program->{Name} || 'AdminPostmasterIMAPAccounts';
    my $Admin       = $Self->_AdminObject();
    my $OAuthObject = QisutuOAuth2->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step        = $Self->_Scalar( $Request->{Step} );
    my $Action      = $Self->_Scalar( $Request->{Action} ) || ( $ProgramName eq 'AdminPostmasterIMAPAccounts' ? 'List' : 'Create' );
    my $UserID      = $User->{user_account_id} || 0;
    my $AccountKind = $Self->_KindFromPage($ProgramName);
    my $AccountID   = $Self->_Scalar( $Request->{AccountID} ) || 0;
    my $ErrorMessage = '';
    my $NoticeMessage = '';
    my $NoticeClass   = 'qisutu-hidden';

    if ( $ProgramName eq 'AdminPostmasterIMAPAccounts' && $Action eq 'OAuthCallback' ) {
        return $Self->_OAuthCallback(
            Request     => $Request,
            UserID      => $UserID,
            Admin       => $Admin,
            OAuthObject => $OAuthObject,
        );
    }

    if ( $ProgramName eq 'AdminPostmasterIMAPAccounts' && $Action eq 'Create' ) {
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccount' };
    }

    if ( $ProgramName eq 'AdminPostmasterIMAPAccounts' && $Action eq 'Edit' && $AccountID ) {
        my $LegacyAccount = $Admin->PostmasterIMAPAccountGet( AccountID => $AccountID );
        return { Redirect => $Self->_EditURL($LegacyAccount) } if $LegacyAccount;
    }

    if ( $Step eq 'IMAPAccountCreate' || $Step eq 'IMAPAccountUpdate' ) {
        my $SubmittedKind = $Self->_Scalar( $Request->{AccountKind} );
        if ( !$AccountKind || $SubmittedKind ne $AccountKind ) {
            $ErrorMessage = 'Translate:AdminOAuthProviderInvalid';
        }
        else {
            my %SaveParam = (
                %{$Request},
                $Self->_KindParameters($AccountKind),
                IMAPVerifyCertificate => $Request->{IMAPVerifyCertificate} ? 1 : 0,
                ChangedByUserID => $UserID,
            );

            my $SavedID;
            if ( $Step eq 'IMAPAccountCreate' ) {
                $SavedID = $Admin->PostmasterIMAPAccountCreate(%SaveParam);
                $Action = 'Create';
            }
            else {
                $SavedID = $Admin->PostmasterIMAPAccountUpdate(%SaveParam);
                $Action = 'Edit';
            }

            if ($SavedID) {
                $AccountID = $Step eq 'IMAPAccountCreate' ? $SavedID : $AccountID;

                if ( $AccountKind eq 'standard' ) {
                    return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts' };
                }

                my $Account = $Admin->PostmasterIMAPAccountGet( AccountID => $AccountID );
                my $AuthURL = $OAuthObject->AuthorizationBegin(
                    Account         => $Account,
                    UserID          => $UserID,
                    RequestedActive => $Request->{Active} ? 1 : 0,
                    ReturnPage      => $ProgramName,
                );

                if ($AuthURL) {
                    return { Redirect => $AuthURL };
                }

                $ErrorMessage = $OAuthObject->Error() || 'Translate:AdminOAuthAuthorizationStartFailed';
                $Action = 'Edit';
            }
            else {
                $ErrorMessage = $Admin->Error() || 'Translate:AdminMailAccountSaveFailed';
            }
        }
    }
    elsif ( $Step eq 'IMAPAccountDeactivate' ) {
        $Admin->PostmasterIMAPAccountDeactivate(
            AccountID       => $AccountID,
            ChangedByUserID => $UserID,
        );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts;Status=deactivated' } if !$Admin->Error();
        $ErrorMessage = $Admin->Error();
    }
    elsif ( $Step eq 'IMAPAccountActivate' ) {
        $Admin->PostmasterIMAPAccountActivate(
            AccountID       => $AccountID,
            ChangedByUserID => $UserID,
        );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts;Status=activated' } if !$Admin->Error();
        $ErrorMessage = $Admin->Error();
    }
    elsif ( $Step eq 'IMAPAccountDelete' ) {
        $Admin->PostmasterIMAPAccountDelete(
            AccountID       => $AccountID,
            ChangedByUserID => $UserID,
        );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts;Status=deleted' } if !$Admin->Error();
        $ErrorMessage = $Admin->Error();
    }
    elsif ( $Step eq 'IMAPAccountTest' ) {
        my $Result = $Admin->PostmasterIMAPAccountTest(
            AccountID       => $AccountID,
            ChangedByUserID => $UserID,
        );
        $Action = 'Edit';
        $NoticeMessage = $Result ? $Result->{Message} : $Admin->Error();
        $NoticeClass = $Result && $Result->{Success} ? 'qisutu-form-success' : 'qisutu-form-error';
    }

    my $Account;
    if ( $Action eq 'Edit' && $AccountID ) {
        $Account = $Admin->PostmasterIMAPAccountGet( AccountID => $AccountID );
        if ($Account) {
            my $ActualKind = $Self->_KindFromAccount($Account);
            my $ActualPage = $Self->_PageFromKind($ActualKind);
            if ( $ProgramName ne $ActualPage ) {
                return { Redirect => $Self->_EditURL($Account) };
            }
            $AccountKind = $ActualKind;
        }
        else {
            $Action = $ProgramName eq 'AdminPostmasterIMAPAccounts' ? 'List' : 'Create';
        }
    }

    my $OAuthStatus = $Self->_Scalar( $Request->{OAuthStatus} );
    if ($OAuthStatus) {
        if ( $OAuthStatus eq 'success' ) {
            $NoticeMessage = 'Translate:AdminOAuthConnectedAndTested';
            $NoticeClass   = 'qisutu-form-success';
        }
        elsif ($Account) {
            $NoticeMessage = $Account->{last_check_message} || 'Translate:AdminOAuthAuthorizationFailed';
            $NoticeClass   = 'qisutu-form-error';
        }
        else {
            $NoticeMessage = 'Translate:AdminOAuthStateInvalid';
            $NoticeClass   = 'qisutu-form-error';
        }
    }

    my $Status = $Self->_Scalar( $Request->{Status} );
    if ( $ProgramName eq 'AdminPostmasterIMAPAccounts' && $Status ) {
        my %StatusMessage = (
            activated   => 'Translate:AdminMailAccountActivated',
            deactivated => 'Translate:AdminMailAccountDeactivated',
            deleted     => 'Translate:AdminMailAccountDeleted',
        );
        if ( $StatusMessage{$Status} ) {
            $NoticeMessage = $StatusMessage{$Status};
            $NoticeClass   = 'qisutu-form-success';
        }
    }

    $ErrorMessage ||= $Admin->Error() || '';

    my $AccountList = $Admin->PostmasterIMAPAccountList() || [];
    for my $Item ( @{$AccountList} ) {
        my $Kind = $Self->_KindFromAccount($Item);
        $Item->{edit_url} = $Self->_EditURL($Item);
        $Item->{type_label} = $Kind eq 'microsoft'
            ? 'Translate:AdminMailTypeMicrosoft365'
            : $Kind eq 'google'
                ? 'Translate:AdminMailTypeGoogle'
                : 'Translate:AdminMailTypeStandardIMAP';
        $Item->{connection_label} = $Self->_ConnectionLabel($Item);
        if ( $Item->{active} ) {
            $Item->{toggle_step}         = 'IMAPAccountDeactivate';
            $Item->{toggle_label}        = 'Translate:AdminDeactivate';
            $Item->{toggle_button_class} = 'qisutu-button-danger';
            $Item->{delete_class}        = 'qisutu-hidden';
        }
        else {
            $Item->{toggle_step}         = 'IMAPAccountActivate';
            $Item->{toggle_label}        = 'Translate:AdminActivate';
            $Item->{toggle_button_class} = 'qisutu-button-success';
            $Item->{delete_class}        = '';
        }
    }

    my $QueueList = $Admin->QueueList() || [];
    my $Submitted = $Step eq 'IMAPAccountCreate' || $Step eq 'IMAPAccountUpdate' ? 1 : 0;
    my $Source    = $Submitted ? $Request : ( $Account || {} );
    my $PageInfo  = $Self->_PageInfo($AccountKind);
    my $QueueID   = $Self->_SourceValue( $Source, 'QueueID', 'queue_id', '' );
    my $Security  = $Self->_SourceValue( $Source, 'IMAPSecurity', 'imap_security', 'imap_starttls' );
    my $Active    = $Submitted ? ( $Request->{Active} ? 1 : 0 ) : ( !$Account || $Account->{active} ? 1 : 0 );
    my $VerifyCertificate = $Submitted
        ? ( $Request->{IMAPVerifyCertificate} ? 1 : 0 )
        : ( !$Account || !exists $Account->{imap_verify_certificate} || $Account->{imap_verify_certificate} ? 1 : 0 );

    return {
        Template => 'AdminPostmasterIMAPAccounts.tt',
        Data     => {
            PageTitle          => $PageInfo->{Title},
            ProgramTitle       => $PageInfo->{Title},
            ProgramDescription => $PageInfo->{Description},
            AccountList        => $AccountList,
            AccountCount       => scalar @{$AccountList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? 'qisutu-form-error' : 'qisutu-hidden',
            NoticeMessage      => $NoticeMessage,
            NoticeClass        => $NoticeMessage ? $NoticeClass : 'qisutu-hidden',
            FormAction         => 'index.pl',
            CurrentPage        => $ProgramName,
            AccountKind        => $AccountKind,
            ShowList           => $ProgramName eq 'AdminPostmasterIMAPAccounts' && $Action eq 'List' ? 1 : 0,
            ShowForm           => $ProgramName ne 'AdminPostmasterIMAPAccounts' && ( $Action eq 'Create' || $Action eq 'Edit' ) ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' && $Account ? 1 : 0,
            IsStandard         => $AccountKind eq 'standard' ? 1 : 0,
            IsMicrosoft        => $AccountKind eq 'microsoft' ? 1 : 0,
            IsGoogle           => $AccountKind eq 'google' ? 1 : 0,
            FormTitle          => $Action eq 'Edit' ? $PageInfo->{EditTitle} : $PageInfo->{CreateTitle},
            FormStep           => $Action eq 'Edit' ? 'IMAPAccountUpdate' : 'IMAPAccountCreate',
            SubmitLabel        => $AccountKind eq 'standard'
                ? ( $Action eq 'Edit' ? 'Translate:AdminSave' : 'Translate:AdminCreate' )
                : 'Translate:AdminOAuthSaveAndConnect',
            AccountID          => $Account ? $Account->{id} : '',
            AccountName        => $Self->_SourceValue( $Source, 'Name', 'name', '' ),
            AccountEmail       => $Self->_SourceValue( $Source, 'Email', 'email', '' ),
            AccountQueueID     => $QueueID,
            AccountIMAPHost    => $Self->_SourceValue( $Source, 'IMAPHost', 'imap_host', '' ),
            AccountIMAPPort    => $Self->_SourceValue( $Source, 'IMAPPort', 'imap_port', 143 ),
            AccountIMAPVerifyCertificateChecked => $VerifyCertificate ? 'checked' : '',
            AccountIMAPCAFile  => $Self->_SourceValue( $Source, 'IMAPCAFile', 'imap_ca_file', '' ),
            AccountIMAPUsername => $Self->_SourceValue( $Source, 'IMAPUsername', 'imap_username', '' ),
            AccountOAuthClientID => $Self->_SourceValue( $Source, 'OAuthClientID', 'oauth_client_id', '' ),
            AccountOAuthTenantID => $Self->_SourceValue( $Source, 'OAuthTenantID', 'oauth_tenant_id', 'common' ),
            AccountOAuthScope  => $Account ? $Account->{oauth_scope} || '' : '',
            AccountTokenExpires => $Account ? $Account->{oauth_token_expires_at} || '' : '',
            AccountLastCheckAt => $Account ? $Account->{last_check_at} || '' : '',
            AccountLastCheckMessage => $Account ? $Account->{last_check_message} || '' : '',
            AccountConnectionLabel => $Account ? $Self->_ConnectionLabel($Account) : 'Translate:AdminOAuthNotConnected',
            AccountClientSecretPresent => $Account && $Account->{oauth_client_secret} ? 1 : 0,
            AccountSortOrder   => $Self->_SourceValue( $Source, 'SortOrder', 'sort_order', 1000 ),
            AccountActiveChecked => $Active ? 'checked' : '',
            IMAPSecurityOptionsHTML => $Self->_SecurityOptionsHTML( Selected => $Security ),
            QueueOptionsHTML => $Self->_QueueOptionsHTML(
                QueueList  => $QueueList,
                SelectedID => $QueueID,
            ),
            OAuthRedirectURI => $AccountKind eq 'standard' ? '' : ( $OAuthObject->RedirectURI() || '' ),
            MicrosoftIMAPHost => 'outlook.office365.com',
            GoogleIMAPHost    => 'imap.gmail.com',
        },
    };
}

sub _OAuthCallback {
    my ( $Self, %Param ) = @_;

    my $Result = $Param{OAuthObject}->AuthorizationComplete(
        Request => $Param{Request},
        UserID  => $Param{UserID},
    );

    if ( !$Result ) {
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts;OAuthStatus=invalid' };
    }

    my $Status = 'error';
    if ( $Result->{Success} ) {
        my $Test = $Param{Admin}->PostmasterIMAPAccountTest(
            AccountID       => $Result->{AccountID},
            ChangedByUserID => $Param{UserID},
        );

        if ( $Test && $Test->{Success} ) {
            $Param{Admin}->PostmasterIMAPAccountActiveSet(
                AccountID       => $Result->{AccountID},
                Active          => $Result->{RequestedActive},
                ChangedByUserID => $Param{UserID},
            );
            $Status = 'success';
        }
        else {
            $Param{Admin}->PostmasterIMAPAccountActiveSet(
                AccountID       => $Result->{AccountID},
                Active          => 0,
                ChangedByUserID => $Param{UserID},
            );
            $Status = 'test_failed';
        }
    }

    my $Page = $Result->{ReturnPage} || $Self->_PageFromKind( $Self->_KindFromProvider( $Result->{Provider} ) );
    my $URL = 'index.pl?Page=' . $Page
        . ';Action=Edit;AccountID=' . ( $Result->{AccountID} || 0 )
        . ';OAuthStatus=' . $Status;

    return { Redirect => $URL };
}

sub _KindParameters {
    my ( $Self, $Kind ) = @_;

    return (
        IMAPAuthType => 'oauth2',
        OAuthProvider => 'microsoft',
        IMAPHost => 'outlook.office365.com',
        IMAPSecurity => 'imaps',
        IMAPPort => 993,
    ) if $Kind eq 'microsoft';

    return (
        IMAPAuthType => 'oauth2',
        OAuthProvider => 'google',
        OAuthTenantID => '',
        IMAPHost => 'imap.gmail.com',
        IMAPSecurity => 'imaps',
        IMAPPort => 993,
    ) if $Kind eq 'google';

    return (
        IMAPAuthType => 'password',
        OAuthProvider => '',
        OAuthClientID => '',
        OAuthClientSecret => '',
        OAuthTenantID => '',
        OAuthScope => '',
    );
}

sub _KindFromPage {
    my ( $Self, $Page ) = @_;

    return 'standard'  if ( $Page || '' ) eq 'AdminPostmasterIMAPAccount';
    return 'microsoft' if ( $Page || '' ) eq 'AdminPostmasterMicrosoft365';
    return 'google'    if ( $Page || '' ) eq 'AdminPostmasterGoogleMail';
    return '';
}

sub _KindFromProvider {
    my ( $Self, $Provider ) = @_;

    my $Key = QisutuOAuth2->new()->ProviderNormalize($Provider);
    return $Key eq 'microsoft' ? 'microsoft' : $Key eq 'google' ? 'google' : 'standard';
}

sub _KindFromAccount {
    my ( $Self, $Account ) = @_;

    return 'standard' if !$Account || ( $Account->{imap_auth_type} || 'password' ) ne 'oauth2';
    return $Self->_KindFromProvider( $Account->{oauth_provider} );
}

sub _PageFromKind {
    my ( $Self, $Kind ) = @_;

    return 'AdminPostmasterMicrosoft365' if ( $Kind || '' ) eq 'microsoft';
    return 'AdminPostmasterGoogleMail' if ( $Kind || '' ) eq 'google';
    return 'AdminPostmasterIMAPAccount';
}

sub _EditURL {
    my ( $Self, $Account ) = @_;

    return 'index.pl?Page=AdminPostmasterIMAPAccounts' if !$Account;
    return 'index.pl?Page=' . $Self->_PageFromKind( $Self->_KindFromAccount($Account) )
        . ';Action=Edit;AccountID=' . ( $Account->{id} || 0 );
}

sub _PageInfo {
    my ( $Self, $Kind ) = @_;

    if ( ( $Kind || '' ) eq 'microsoft' ) {
        return {
            Title       => 'Translate:AdminMicrosoft365Title',
            Description => 'Translate:AdminMicrosoft365Description',
            CreateTitle => 'Translate:AdminMicrosoft365Create',
            EditTitle   => 'Translate:AdminMicrosoft365Edit',
        };
    }
    if ( ( $Kind || '' ) eq 'google' ) {
        return {
            Title       => 'Translate:AdminGoogleMailTitle',
            Description => 'Translate:AdminGoogleMailDescription',
            CreateTitle => 'Translate:AdminGoogleMailCreate',
            EditTitle   => 'Translate:AdminGoogleMailEdit',
        };
    }
    if ( ( $Kind || '' ) eq 'standard' ) {
        return {
            Title       => 'Translate:AdminStandardIMAPTitle',
            Description => 'Translate:AdminStandardIMAPDescription',
            CreateTitle => 'Translate:AdminStandardIMAPCreate',
            EditTitle   => 'Translate:AdminStandardIMAPEdit',
        };
    }

    return {
        Title       => 'Translate:AdminPostmasterIMAPAccountsTitle',
        Description => 'Translate:AdminPostmasterIMAPAccountsDescription',
        CreateTitle => 'Translate:AdminPostmasterIMAPAccountCreate',
        EditTitle   => 'Translate:AdminPostmasterIMAPAccountEdit',
    };
}

sub _ConnectionLabel {
    my ( $Self, $Account ) = @_;

    return 'Translate:AdminPasswordAuthentication'
        if ( $Account->{imap_auth_type} || 'password' ) ne 'oauth2';
    return 'Translate:AdminOAuthConnectionError'
        if ( $Account->{last_check_status} || '' ) eq 'error';
    return 'Translate:AdminOAuthConnected'
        if $Account->{oauth_refresh_token};
    return 'Translate:AdminOAuthAuthorizationPending';
}

sub _SourceValue {
    my ( $Self, $Source, $RequestKey, $DBKey, $Default ) = @_;

    return $Source->{$RequestKey} if exists $Source->{$RequestKey} && !ref $Source->{$RequestKey};
    return $Source->{$DBKey} if exists $Source->{$DBKey} && !ref $Source->{$DBKey};
    return $Default;
}

sub _SecurityOptionsHTML {
    my ( $Self, %Param ) = @_;

    return $Self->_OptionsHTML(
        Options => [
            [ imap          => 'IMAP (143)' ],
            [ imap_starttls => 'IMAP STARTTLS (143)' ],
            [ imaps         => 'IMAPS (993)' ],
        ],
        Selected => $Param{Selected} || 'imap_starttls',
    );
}

sub _QueueOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $QueueList  = $Param{QueueList} || [];
    my $SelectedID = $Param{SelectedID} || '';
    my $HTML       = '';

    for my $Queue ( @{$QueueList} ) {
        next if ref $Queue ne 'HASH';

        my $Value    = $Queue->{id} || '';
        my $Label    = $Queue->{full_name} || $Queue->{name} || '';
        my $Selected = $Value && $Value eq $SelectedID ? ' selected' : '';

        $HTML .= '<option value="' . $Self->_Escape($Value) . '"' . $Selected . '>' . $Self->_Escape($Label) . '</option>';
    }

    return $HTML;
}

sub _OptionsHTML {
    my ( $Self, %Param ) = @_;

    my $HTML = '';

    for my $Option ( @{ $Param{Options} || [] } ) {
        my $Selected = $Option->[0] eq ( $Param{Selected} || '' ) ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape( $Option->[0] ) . '"' . $Selected . '>' . $Self->_Escape( $Option->[1] ) . '</option>';
    }

    return $HTML;
}

sub _Scalar {
    my ( $Self, $Value ) = @_;

    return '' if !defined $Value;
    return defined $Value->[0] ? $Value->[0] : '' if ref $Value eq 'ARRAY';
    return '' if ref $Value;
    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub _AdminObject {
    my ($Self) = @_;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

1;
