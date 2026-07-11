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
    my $Admin       = $Self->_AdminObject();
    my $Step        = $Request->{Step} || '';
    my $Action      = $Request->{Action} || 'List';
    my $TestMessage = '';
    my $TestClass   = 'qisutu-hidden';

    if ( $Admin && $Step eq 'SMTPAccountCreate' ) {
        $Admin->SMTPAccountCreate( %{$Request}, ChangedByUserID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=AdminSMTPAccount' } if !$Admin->Error();
        $Action = 'Create';
    }
    elsif ( $Admin && $Step eq 'SMTPAccountUpdate' ) {
        $Admin->SMTPAccountUpdate( %{$Request}, ChangedByUserID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=AdminSMTPAccount;Action=Edit;AccountID=' . ( $Request->{AccountID} || 0 ) } if !$Admin->Error();
        $Action = 'Edit';
    }
    elsif ( $Admin && $Step eq 'SMTPAccountDeactivate' ) {
        $Admin->SMTPAccountDeactivate(
            AccountID       => $Request->{AccountID},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminSMTPAccount' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'SMTPAccountTest' ) {
        my $Result = $Admin->SMTPAccountTest(
            AccountID       => $Request->{AccountID},
            ChangedByUserID => $User->{user_account_id},
        );

        $Action      = 'Edit';
        $TestMessage = $Result ? $Result->{Message} : $Admin->Error();
        $TestClass   = $Result && $Result->{Success} ? 'qisutu-form-success' : '';
    }

    my $AccountList = $Admin ? $Admin->SMTPAccountList() : [];
    my $Account;

    if ( $Admin && $Action eq 'Edit' ) {
        $Account = $Admin->SMTPAccountGet( AccountID => $Request->{AccountID} );
        $Action = 'List' if !$Account;
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';

    return {
        Template => 'AdminSMTPAccount.tt',
        Data     => {
            PageTitle          => 'Translate:AdminSMTPAccountTitle',
            ProgramTitle       => 'Translate:AdminSMTPAccountTitle',
            ProgramDescription => 'Translate:AdminSMTPAccountDescription',
            AccountList        => $AccountList,
            AccountCount       => scalar @{$AccountList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            TestMessage        => $TestMessage,
            TestClass          => $TestMessage ? $TestClass : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            AccountID          => $Account ? $Account->{id} : '',
            AccountName        => $Account ? $Account->{name} : '',
            AccountSMTPHost    => $Account ? $Account->{smtp_host} : '',
            AccountSMTPPort    => $Account ? $Account->{smtp_port} : 587,
            AccountSMTPUsername => $Account ? $Account->{smtp_username} : '',
            AccountOAuthProvider => $Account ? $Account->{oauth_provider} : '',
            AccountOAuthClientID => $Account ? $Account->{oauth_client_id} : '',
            AccountOAuthTenantID => $Account ? $Account->{oauth_tenant_id} : '',
            AccountOAuthScope => $Account ? $Account->{oauth_scope} : '',
            AccountSortOrder   => $Account ? $Account->{sort_order} : 1000,
            AccountActiveChecked => !$Account || $Account->{active} ? 'checked' : '',
            CreateSMTPSecurityOptionsHTML => $Self->_SecurityOptionsHTML(
                Selected => 'smtp_starttls',
            ),
            EditSMTPSecurityOptionsHTML => $Self->_SecurityOptionsHTML(
                Selected => $Account ? $Account->{smtp_security} : 'smtp_starttls',
            ),
            CreateSMTPAuthOptionsHTML => $Self->_AuthOptionsHTML(
                Selected => 'password',
            ),
            EditSMTPAuthOptionsHTML => $Self->_AuthOptionsHTML(
                Selected => $Account ? $Account->{smtp_auth_type} : 'password',
            ),
        },
    };
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
