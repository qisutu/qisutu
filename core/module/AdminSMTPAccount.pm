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

package AdminSMTPAccount;

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
    my $User        = $Param{User} || {};
    my $Program     = $Param{Program} || {};
    my $ProgramName = $Program->{Name} || 'AdminSMTPAccount';
    my $Admin       = $Self->_AdminObject();
    my $OAuth       = QisutuOAuth2->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step        = $Self->_Scalar( $Request->{Step} );
    my $Action      = $Self->_Scalar( $Request->{Action} ) || ( $ProgramName eq 'AdminSMTPAccount' ? 'List' : 'Create' );
    my $AccountKind = $Self->_KindFromPage($ProgramName);
    my $AccountID   = $Self->_Scalar( $Request->{AccountID} ) || 0;
    my $UserID      = $User->{user_account_id} || 0;
    my $ErrorMessage = '';
    my $NoticeMessage = '';
    my $NoticeClass = 'qisutu-hidden';

    if ( $ProgramName eq 'AdminSMTPAccount' && $Action eq 'OAuthCallback' ) {
        return $Self->_OAuthCallback( Request => $Request, UserID => $UserID, Admin => $Admin, OAuth => $OAuth );
    }
    if ( $ProgramName eq 'AdminSMTPAccount' && $Action eq 'Create' ) {
        return { Redirect => 'index.pl?Page=AdminSMTPStandard' };
    }
    if ( $ProgramName eq 'AdminSMTPAccount' && $Action eq 'Edit' && $AccountID ) {
        my $Existing = $Admin->SMTPAccountGet( AccountID => $AccountID );
        return { Redirect => $Self->_EditURL($Existing) } if $Existing;
    }

    if ( $Step eq 'SMTPAccountCreate' || $Step eq 'SMTPAccountUpdate' ) {
        my $SubmittedKind = $Self->_Scalar( $Request->{AccountKind} );
        if ( !$AccountKind || $SubmittedKind ne $AccountKind ) {
            $ErrorMessage = 'Translate:AdminOAuthProviderInvalid';
        }
        else {
            my %Save = (
                %{$Request},
                $Self->_KindParameters($AccountKind),
                SMTPVerifyCertificate => $Request->{SMTPVerifyCertificate} ? 1 : 0,
                ChangedByUserID => $UserID,
            );
            my $SavedID = $Step eq 'SMTPAccountCreate'
                ? $Admin->SMTPAccountCreate(%Save)
                : $Admin->SMTPAccountUpdate(%Save);
            if ($SavedID) {
                $AccountID = $Step eq 'SMTPAccountCreate' ? $SavedID : $AccountID;
                return { Redirect => 'index.pl?Page=AdminSMTPAccount' } if $AccountKind eq 'standard';

                my $Account = $Admin->SMTPAccountGet( AccountID => $AccountID );
                my $URL = $OAuth->AuthorizationBegin(
                    AccountType     => 'smtp',
                    Account         => $Account,
                    UserID          => $UserID,
                    RequestedActive => $Request->{Active} ? 1 : 0,
                    ReturnPage      => $ProgramName,
                );
                return { Redirect => $URL } if $URL;
                $ErrorMessage = $OAuth->Error() || 'Translate:AdminOAuthAuthorizationStartFailed';
                $Action = 'Edit';
            }
            else {
                $ErrorMessage = $Admin->Error() || 'Translate:AdminMailAccountSaveFailed';
            }
        }
    }
    elsif ( $Step eq 'SMTPAccountDeactivate' || $Step eq 'SMTPAccountActivate' ) {
        my $Active = $Step eq 'SMTPAccountActivate' ? 1 : 0;
        if ($Active) {
            my $Test = $Admin->SMTPAccountTest( AccountID => $AccountID, ChangedByUserID => $UserID );
            $ErrorMessage = $Test ? $Test->{Message} : $Admin->Error() if !$Test || !$Test->{Success};
        }
        $Admin->SMTPAccountActiveSet( AccountID => $AccountID, Active => $Active, ChangedByUserID => $UserID ) if !$ErrorMessage;
        return { Redirect => 'index.pl?Page=AdminSMTPAccount;Status=' . ( $Active ? 'activated' : 'deactivated' ) }
            if !$ErrorMessage && !$Admin->Error();
        $ErrorMessage ||= $Admin->Error();
    }
    elsif ( $Step eq 'SMTPAccountTest' ) {
        my $Result = $Admin->SMTPAccountTest( AccountID => $AccountID, ChangedByUserID => $UserID );
        $Action = 'Edit';
        $NoticeMessage = $Result ? $Result->{Message} : $Admin->Error();
        $NoticeClass = $Result && $Result->{Success} ? 'qisutu-form-success' : 'qisutu-form-error';
    }
    elsif ( $Step eq 'SMTPOAuthDisconnect' ) {
        if ( $OAuth->AuthorizationDisconnect( AccountType => 'smtp', AccountID => $AccountID, UserID => $UserID ) ) {
            return { Redirect => 'index.pl?Page=' . $ProgramName . ';Action=Edit;AccountID=' . $AccountID . ';OAuthStatus=disconnected' };
        }
        $ErrorMessage = $OAuth->Error();
        $Action = 'Edit';
    }
    elsif ( $Step eq 'SMTPOAuthReconnect' ) {
        my $Existing = $Admin->SMTPAccountGet( AccountID => $AccountID );
        $Admin->SMTPAccountActiveSet( AccountID => $AccountID, Active => 0, ChangedByUserID => $UserID ) if $Existing;
        my $URL = $Existing && !$Admin->Error() ? $OAuth->AuthorizationBegin(
            AccountType     => 'smtp',
            Account         => $Existing,
            UserID          => $UserID,
            RequestedActive => 1,
            ReturnPage      => $ProgramName,
        ) : '';
        return { Redirect => $URL } if $URL;
        $ErrorMessage = $OAuth->Error() || $Admin->Error() || 'Translate:AdminOAuthAuthorizationStartFailed';
        $Action = 'Edit';
    }

    my $Account;
    if ( $Action eq 'Edit' && $AccountID ) {
        $Account = $Admin->SMTPAccountGet( AccountID => $AccountID );
        if ($Account) {
            my $ActualKind = $Self->_KindFromAccount($Account);
            my $ActualPage = $Self->_PageFromKind($ActualKind);
            return { Redirect => $Self->_EditURL($Account) } if $ProgramName ne $ActualPage;
            $AccountKind = $ActualKind;
        }
    }

    my $OAuthStatus = $Self->_Scalar( $Request->{OAuthStatus} );
    if ( $OAuthStatus eq 'success' ) {
        $NoticeMessage = 'Translate:AdminOAuthConnectedAndTested';
        $NoticeClass = 'qisutu-form-success';
    }
    elsif ( $OAuthStatus eq 'disconnected' ) {
        $NoticeMessage = 'Translate:AdminOAuthDisconnected';
        $NoticeClass = 'qisutu-form-success';
    }
    elsif ($OAuthStatus) {
        $NoticeMessage = $Account ? ( $Account->{last_check_message} || 'Translate:AdminOAuthAuthorizationFailed' ) : 'Translate:AdminOAuthStateInvalid';
        $NoticeClass = 'qisutu-form-error';
    }

    my $Status = $Self->_Scalar( $Request->{Status} );
    if ( $Status eq 'activated' || $Status eq 'deactivated' ) {
        $NoticeMessage = $Status eq 'activated' ? 'Translate:AdminMailAccountActivated' : 'Translate:AdminMailAccountDeactivated';
        $NoticeClass = 'qisutu-form-success';
    }

    my $AccountList = $Admin->SMTPAccountList() || [];
    for my $Item ( @{$AccountList} ) {
        my $Kind = $Self->_KindFromAccount($Item);
        $Item->{edit_url} = $Self->_EditURL($Item);
        $Item->{type_label} = $Kind eq 'microsoft' ? 'Translate:AdminSMTPTypeMicrosoft365'
            : $Kind eq 'google' ? 'Translate:AdminSMTPTypeGoogle' : 'Translate:AdminSMTPTypeStandard';
        $Item->{connection_label} = $Self->_ConnectionLabel($Item);
        $Item->{toggle_step} = $Item->{active} ? 'SMTPAccountDeactivate' : 'SMTPAccountActivate';
        $Item->{toggle_label} = $Item->{active} ? 'Translate:AdminDeactivate' : 'Translate:AdminActivate';
        $Item->{toggle_button_class} = $Item->{active} ? 'qisutu-button-danger' : 'qisutu-button-success';
    }

    my $Submitted = $Step eq 'SMTPAccountCreate' || $Step eq 'SMTPAccountUpdate';
    my $Source = $Submitted ? $Request : ( $Account || {} );
    my $Info = $Self->_PageInfo($AccountKind);
    my $Security = $Self->_SourceValue( $Source, 'SMTPSecurity', 'smtp_security', 'smtp_starttls' );
    my $Active = $Submitted ? ( $Request->{Active} ? 1 : 0 ) : ( !$Account || $Account->{active} ? 1 : 0 );
    my $VerifyCertificate = $Submitted
        ? ( $Request->{SMTPVerifyCertificate} ? 1 : 0 )
        : ( !$Account || !exists $Account->{smtp_verify_certificate} || $Account->{smtp_verify_certificate} ? 1 : 0 );
    $ErrorMessage ||= $Admin->Error() || '';

    return {
        Template => 'AdminSMTPAccount.tt',
        Data     => {
            PageTitle          => $Info->{Title},
            ProgramTitle       => $Info->{Title},
            ProgramDescription => $Info->{Description},
            AccountList        => $AccountList,
            AccountCount       => scalar @{$AccountList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? 'qisutu-form-error' : 'qisutu-hidden',
            NoticeMessage      => $NoticeMessage,
            NoticeClass        => $NoticeMessage ? $NoticeClass : 'qisutu-hidden',
            FormAction         => 'index.pl',
            CurrentPage        => $ProgramName,
            AccountKind        => $AccountKind,
            ShowList           => $ProgramName eq 'AdminSMTPAccount' && $Action eq 'List' ? 1 : 0,
            ShowForm           => $ProgramName ne 'AdminSMTPAccount' && ( $Action eq 'Create' || $Action eq 'Edit' ) ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' && $Account ? 1 : 0,
            IsStandard         => $AccountKind eq 'standard' ? 1 : 0,
            IsMicrosoft        => $AccountKind eq 'microsoft' ? 1 : 0,
            IsGoogle           => $AccountKind eq 'google' ? 1 : 0,
            IsOAuth            => $AccountKind eq 'microsoft' || $AccountKind eq 'google' ? 1 : 0,
            FormTitle          => $Action eq 'Edit' ? $Info->{EditTitle} : $Info->{CreateTitle},
            FormStep           => $Action eq 'Edit' ? 'SMTPAccountUpdate' : 'SMTPAccountCreate',
            SubmitLabel        => $AccountKind eq 'standard'
                ? ( $Action eq 'Edit' ? 'Translate:AdminSave' : 'Translate:AdminCreate' )
                : 'Translate:AdminOAuthSaveAndConnect',
            AccountID          => $Account ? $Account->{id} : '',
            AccountName        => $Self->_SourceValue( $Source, 'Name', 'name', '' ),
            AccountSMTPHost    => $Self->_SourceValue( $Source, 'SMTPHost', 'smtp_host', '' ),
            AccountSMTPPort    => $Self->_SourceValue( $Source, 'SMTPPort', 'smtp_port', 587 ),
            AccountSMTPVerifyCertificateChecked => $VerifyCertificate ? 'checked' : '',
            AccountSMTPCAFile  => $Self->_SourceValue( $Source, 'SMTPCAFile', 'smtp_ca_file', '' ),
            AccountSMTPUsername => $Self->_SourceValue( $Source, 'SMTPUsername', 'smtp_username', '' ),
            AccountOAuthClientID => $Self->_SourceValue( $Source, 'OAuthClientID', 'oauth_client_id', '' ),
            AccountOAuthTenantID => $Self->_SourceValue( $Source, 'OAuthTenantID', 'oauth_tenant_id', 'common' ),
            AccountOAuthScope  => $Account ? $Account->{oauth_scope} || '' : '',
            AccountSortOrder   => $Self->_SourceValue( $Source, 'SortOrder', 'sort_order', 1000 ),
            AccountActiveChecked => $Active ? 'checked' : '',
            AccountTokenExpires => $Account ? $Account->{oauth_token_expires_at} || '' : '',
            AccountLastCheckAt => $Account ? $Account->{last_check_at} || '' : '',
            AccountLastCheckMessage => $Account ? $Account->{last_check_message} || '' : '',
            AccountConnectionLabel => $Account ? $Self->_ConnectionLabel($Account) : 'Translate:AdminOAuthNotConnected',
            SMTPSecurityOptionsHTML => $Self->_SecurityOptionsHTML( Selected => $Security ),
            OAuthRedirectURI => $AccountKind eq 'standard' ? '' : ( $OAuth->RedirectURI( AccountType => 'smtp' ) || '' ),
            MicrosoftSMTPHost => 'smtp.office365.com',
            GoogleSMTPHost    => 'smtp.gmail.com',
        },
    };
}

sub _OAuthCallback {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{OAuth}->AuthorizationComplete( Request => $Param{Request}, UserID => $Param{UserID} );
    return { Redirect => 'index.pl?Page=AdminSMTPAccount;OAuthStatus=invalid' } if !$Result || $Result->{AccountType} ne 'smtp';

    my $Status = 'error';
    if ( $Result->{Success} ) {
        my $Test = $Param{Admin}->SMTPAccountTest( AccountID => $Result->{AccountID}, ChangedByUserID => $Param{UserID} );
        if ( $Test && $Test->{Success} ) {
            $Param{Admin}->SMTPAccountActiveSet(
                AccountID => $Result->{AccountID}, Active => $Result->{RequestedActive}, ChangedByUserID => $Param{UserID}
            );
            $Status = 'success';
        }
        else {
            $Param{Admin}->SMTPAccountActiveSet( AccountID => $Result->{AccountID}, Active => 0, ChangedByUserID => $Param{UserID} );
            $Status = 'test_failed';
        }
    }
    my $Page = $Result->{ReturnPage} || $Self->_PageFromKind( $Self->_KindFromProvider( $Result->{Provider} ) );
    return { Redirect => 'index.pl?Page=' . $Page . ';Action=Edit;AccountID=' . ( $Result->{AccountID} || 0 ) . ';OAuthStatus=' . $Status };
}

sub _KindParameters {
    my ( $Self, $Kind ) = @_;
    return ( SMTPAuthType => 'oauth2', OAuthProvider => 'microsoft', SMTPHost => 'smtp.office365.com', SMTPSecurity => 'smtp_starttls', SMTPPort => 587 ) if $Kind eq 'microsoft';
    return ( SMTPAuthType => 'oauth2', OAuthProvider => 'google', OAuthTenantID => '', SMTPHost => 'smtp.gmail.com', SMTPSecurity => 'smtp_starttls', SMTPPort => 587 ) if $Kind eq 'google';
    return ( SMTPAuthType => 'password', OAuthProvider => '', OAuthClientID => '', OAuthClientSecret => '', OAuthTenantID => '', OAuthScope => '' );
}

sub _KindFromPage {
    my ( $Self, $Page ) = @_;
    return 'standard' if ( $Page || '' ) eq 'AdminSMTPStandard';
    return 'microsoft' if ( $Page || '' ) eq 'AdminSMTPMicrosoft365';
    return 'google' if ( $Page || '' ) eq 'AdminSMTPGoogleMail';
    return '';
}

sub _KindFromProvider {
    my ( $Self, $Provider ) = @_;
    my $Key = QisutuOAuth2->new()->ProviderNormalize($Provider);
    return $Key eq 'microsoft' ? 'microsoft' : $Key eq 'google' ? 'google' : 'standard';
}

sub _KindFromAccount {
    my ( $Self, $Account ) = @_;
    return 'standard' if !$Account || ( $Account->{smtp_auth_type} || 'password' ) ne 'oauth2';
    return $Self->_KindFromProvider( $Account->{oauth_provider} );
}

sub _PageFromKind {
    my ( $Self, $Kind ) = @_;
    return 'AdminSMTPMicrosoft365' if ( $Kind || '' ) eq 'microsoft';
    return 'AdminSMTPGoogleMail' if ( $Kind || '' ) eq 'google';
    return 'AdminSMTPStandard';
}

sub _EditURL {
    my ( $Self, $Account ) = @_;
    return 'index.pl?Page=AdminSMTPAccount' if !$Account;
    return 'index.pl?Page=' . $Self->_PageFromKind( $Self->_KindFromAccount($Account) ) . ';Action=Edit;AccountID=' . ( $Account->{id} || 0 );
}

sub _PageInfo {
    my ( $Self, $Kind ) = @_;
    return { Title=>'Translate:AdminSMTPMicrosoft365Title', Description=>'Translate:AdminSMTPMicrosoft365Description', CreateTitle=>'Translate:AdminSMTPMicrosoft365Create', EditTitle=>'Translate:AdminSMTPMicrosoft365Edit' } if ( $Kind || '' ) eq 'microsoft';
    return { Title=>'Translate:AdminSMTPGoogleTitle', Description=>'Translate:AdminSMTPGoogleDescription', CreateTitle=>'Translate:AdminSMTPGoogleCreate', EditTitle=>'Translate:AdminSMTPGoogleEdit' } if ( $Kind || '' ) eq 'google';
    return { Title=>'Translate:AdminSMTPStandardTitle', Description=>'Translate:AdminSMTPStandardDescription', CreateTitle=>'Translate:AdminSMTPStandardCreate', EditTitle=>'Translate:AdminSMTPStandardEdit' } if ( $Kind || '' ) eq 'standard';
    return { Title=>'Translate:AdminSMTPAccountTitle', Description=>'Translate:AdminSMTPAccountDescription', CreateTitle=>'Translate:AdminSMTPAccountCreate', EditTitle=>'Translate:AdminSMTPAccountEdit' };
}

sub _ConnectionLabel {
    my ( $Self, $Account ) = @_;
    return 'Translate:AdminOAuthNotConnected' if !$Account;
    my $Status = $Account->{last_check_status} || '';
    return 'Translate:AdminConnectionSuccessful' if $Status eq 'ok' || $Status eq 'success';
    return 'Translate:AdminOAuthAuthorizationPending' if $Status eq 'pending';
    return 'Translate:AdminOAuthDisconnected' if $Status eq 'disconnected';
    return 'Translate:AdminConnectionFailed' if $Status eq 'error';
    return 'Translate:AdminConnectionSuccessful' if ( $Account->{smtp_auth_type} || '' ) eq 'oauth2' && $Account->{oauth_refresh_token};
    return $Account->{smtp_auth_type} eq 'oauth2' ? 'Translate:AdminOAuthNotConnected' : 'Translate:AdminPasswordAuthentication';
}

sub _SourceValue {
    my ( $Self, $Source, $RequestKey, $DBKey, $Default ) = @_;
    return $Source->{$RequestKey} if exists $Source->{$RequestKey};
    return $Source->{$DBKey} if exists $Source->{$DBKey};
    return $Default;
}

sub _Scalar {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value;
    return defined $Value->[0] ? $Value->[0] : '' if ref $Value eq 'ARRAY';
    return '' if ref $Value;
    return $Value;
}

sub _SecurityOptionsHTML {
    my ( $Self, %Param ) = @_;

    return $Self->_OptionsHTML(
        Options => [
            [ smtp          => 'SMTP (25)' ],
            [ smtp_starttls => 'SMTP STARTTLS (587)' ],
            [ smtps         => 'SMTPS (465)' ],
        ],
        Selected => $Param{Selected} || 'smtp_starttls',
    );
}

sub _AuthOptionsHTML {
    my ( $Self, %Param ) = @_;

    return $Self->_OptionsHTML(
        Options => [
            [ password => 'Password' ],
            [ oauth2   => 'OAuth2' ],
        ],
        Selected => $Param{Selected} || 'password',
    );
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
        DB     => $Self->{DB},
        Config => $Self->{Config},
    );
}

1;
