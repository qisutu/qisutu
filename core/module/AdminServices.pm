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

package AdminServices;

use strict;
use warnings;
use utf8;

use QisutuService;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $User    = $Param{User} || {};
    my $ServiceObject = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step = $Request->{Step} || '';

    if ( $Step eq 'ServiceCreate' ) {
        my $ID = $ServiceObject->ServiceCreate(
            Name            => $Request->{Name},
            ParentServiceID => $Request->{ParentServiceID},
            Description     => $Request->{Description},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminServices' } if $ID && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'ServiceUpdate' ) {
        my $OK = $ServiceObject->ServiceUpdate(
            ServiceID       => $Request->{ServiceID},
            Name            => $Request->{Name},
            ParentServiceID => $Request->{ParentServiceID},
            Description     => $Request->{Description},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminServices;Action=Edit;ServiceID=' . ( $Request->{ServiceID} || 0 ) } if $OK && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'ServiceDeactivate' ) {
        my $OK = $ServiceObject->ServiceDeactivate(
            ServiceID       => $Request->{ServiceID},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminServices' } if $OK && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'ServiceCILink' ) {
        my $ServiceID = $Request->{ServiceID};
        my $CIID      = $Request->{CMDBCIID};

        if ( !$CIID && $Request->{CMDBCINumber} ) {
            my $CI = $Self->{DB}->SelectRow(
                'SELECT id FROM cmdb_ci WHERE ci_number = ? LIMIT 1',
                $Request->{CMDBCINumber},
            );
            $CIID = $CI->{id} if $CI;
        }

        my $OK = $ServiceObject->ServiceCILinkAdd(
            ServiceID       => $ServiceID,
            CIID            => $CIID,
            ChangedByUserID => $User->{user_account_id},
            User            => $User,
        );
        return {
            Redirect => 'index.pl?Page=AdminServices;Action=Edit;ServiceID=' . ( $ServiceID || 0 ) . ';Status=ci_linked'
        } if $OK && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'ServiceCIUnlink' ) {
        my $ServiceID = $Request->{ServiceID};
        my $OK = $ServiceObject->ServiceCILinkRemove(
            ServiceID       => $ServiceID,
            CIID            => $Request->{CMDBCIID},
            ChangedByUserID => $User->{user_account_id},
            User            => $User,
        );
        return {
            Redirect => 'index.pl?Page=AdminServices;Action=Edit;ServiceID=' . ( $ServiceID || 0 ) . ';Status=ci_unlinked'
        } if $OK && !$ServiceObject->Error();
    }

    my $Action = $Request->{Action} || 'List';
    my $ServiceList = $ServiceObject->ServiceList();
    my $Service;

    if ( $Action eq 'Edit' ) {
        $Service = $ServiceObject->ServiceGet( ServiceID => $Request->{ServiceID} );
        $Action = 'List' if !$Service;
    }

    my $ServiceCIs = $Service
        ? $ServiceObject->ServiceCIList( ServiceID => $Service->{id} )
        : [];

    for my $CI ( @{$ServiceCIs} ) {
        $CI->{active_label} = $CI->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
    }

    for my $Row ( @{$ServiceList} ) {
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
    }

    my $Error = $ServiceObject->Error() || '';
    my %NoticeKey = (
        ci_linked   => 'Translate:AdminServiceCILinked',
        ci_unlinked => 'Translate:AdminServiceCIUnlinked',
    );
    my $Notice = $NoticeKey{ $Request->{Status} || '' } || '';

    return {
        Template => 'AdminServices.tt',
        Data     => {
            PageTitle          => 'Translate:AdminServicesTitle',
            ProgramTitle       => 'Translate:AdminServicesTitle',
            ProgramDescription => 'Translate:AdminServicesDescription',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowBackToList     => $Action eq 'List' ? 0 : 1,
            ServiceList        => $ServiceList,
            ServiceCount       => scalar @{$ServiceList},
            ServiceCIs         => $ServiceCIs,
            ServiceCICount     => scalar @{$ServiceCIs},
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            NoticeMessage      => $Notice,
            NoticeClass        => $Notice ? '' : 'qisutu-hidden',
            ServiceID          => $Service ? $Service->{id} : '',
            ServiceName        => $Service ? $Service->{name} : '',
            ServiceFullName    => $Service ? $Service->{full_name} : '',
            ServiceDescription => $Service ? ( $Service->{description} || '' ) : '',
            ServiceSortOrder   => $Service ? $Service->{sort_order} : 1000,
            ServiceActiveChecked => $Service && $Service->{active} ? 'checked' : '',
            CreateParentOptionsHTML => $Self->_Options(
                List => $ServiceList, LabelKey => 'full_name', SelectedID => '',
            ),
            EditParentOptionsHTML => $Self->_Options(
                List => $ServiceList, LabelKey => 'full_name', SelectedID => $Service ? $Service->{parent_id} : '', SkipID => $Service ? $Service->{id} : '',
            ),
        },
    };
}

sub _Options {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        next if $Param{SkipID} && ( $Row->{id} || 0 ) == $Param{SkipID};
        my $Selected = defined $Param{SelectedID} && $Param{SelectedID} ne '' && ( $Row->{id} || 0 ) == $Param{SelectedID} ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape( $Row->{id} || '' ) . '"' . $Selected . '>'
            . $Self->{Output}->HTMLEscape( $Row->{ $Param{LabelKey} } || '' ) . '</option>';
    }
    return $HTML;
}

1;
