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

    if ( $Admin && $Step eq 'IMAPAccountCreate' ) {
        $Admin->PostmasterIMAPAccountCreate( %{$Request}, ChangedByUserID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts' } if !$Admin->Error();
        $Action = 'Create';
    }
    elsif ( $Admin && $Step eq 'IMAPAccountUpdate' ) {
        $Admin->PostmasterIMAPAccountUpdate( %{$Request}, ChangedByUserID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts;Action=Edit;AccountID=' . ( $Request->{AccountID} || 0 ) } if !$Admin->Error();
        $Action = 'Edit';
    }
    elsif ( $Admin && $Step eq 'IMAPAccountDeactivate' ) {
        $Admin->PostmasterIMAPAccountDeactivate(
            AccountID       => $Request->{AccountID},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminPostmasterIMAPAccounts' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'IMAPAccountTest' ) {
        my $Result = $Admin->PostmasterIMAPAccountTest(
            AccountID       => $Request->{AccountID},
            ChangedByUserID => $User->{user_account_id},
        );

        $Action      = 'Edit';
        $TestMessage = $Result ? $Result->{Message} : $Admin->Error();
        $TestClass   = $Result && $Result->{Success} ? 'qisutu-form-success' : '';
    }

    my $AccountList = $Admin ? $Admin->PostmasterIMAPAccountList() : [];
    my $QueueList   = $Admin ? $Admin->QueueList() : [];
    my $Account;

    if ( $Admin && $Action eq 'Edit' ) {
        $Account = $Admin->PostmasterIMAPAccountGet( AccountID => $Request->{AccountID} );
        $Action = 'List' if !$Account;
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';

    return {
        Template => 'AdminPostmasterIMAPAccounts.tt',
        Data     => {
            PageTitle          => 'Translate:AdminPostmasterIMAPAccountsTitle',
            ProgramTitle       => 'Translate:AdminPostmasterIMAPAccountsTitle',
            ProgramDescription => 'Translate:AdminPostmasterIMAPAccountsDescription',
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
            AccountEmail       => $Account ? $Account->{email} : '',
            AccountQueueID     => $Account ? $Account->{queue_id} : '',
            AccountIMAPHost    => $Account ? $Account->{imap_host} : '',
            AccountIMAPPort    => $Account ? $Account->{imap_port} : 143,
            AccountIMAPUsername => $Account ? $Account->{imap_username} : '',
            AccountOAuthProvider => $Account ? $Account->{oauth_provider} : '',
            AccountOAuthClientID => $Account ? $Account->{oauth_client_id} : '',
            AccountOAuthTenantID => $Account ? $Account->{oauth_tenant_id} : '',
            AccountOAuthScope => $Account ? $Account->{oauth_scope} : '',
            AccountSortOrder   => $Account ? $Account->{sort_order} : 1000,
            AccountActiveChecked => !$Account || $Account->{active} ? 'checked' : '',
            CreateIMAPSecurityOptionsHTML => $Self->_SecurityOptionsHTML(
                Type     => 'imap',
                Selected => 'imap_starttls',
            ),
            EditIMAPSecurityOptionsHTML => $Self->_SecurityOptionsHTML(
                Type     => 'imap',
                Selected => $Account ? $Account->{imap_security} : 'imap_starttls',
            ),
            CreateIMAPAuthOptionsHTML => $Self->_AuthOptionsHTML(
                Selected => 'password',
            ),
            EditIMAPAuthOptionsHTML => $Self->_AuthOptionsHTML(
                Selected => $Account ? $Account->{imap_auth_type} : 'password',
            ),
            CreateQueueOptionsHTML => $Self->_QueueOptionsHTML(
                QueueList  => $QueueList,
                SelectedID => '',
            ),
            EditQueueOptionsHTML => $Self->_QueueOptionsHTML(
                QueueList  => $QueueList,
                SelectedID => $Account ? $Account->{queue_id} : '',
            ),
        },
    };
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
