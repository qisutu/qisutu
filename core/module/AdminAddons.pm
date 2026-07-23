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

package AdminAddons;

use strict;
use warnings;
use utf8;

use QisutuAddonManager;

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
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Step     = $Request->{Step} || '';
    my $Identifier = $Request->{Identifier} || '';
    my $Error = '';
    my $Notice = '';
    my $Manager = QisutuAddonManager->new( Config => $Self->{Config}, DB => $Self->{DB} );

    if ( $Step eq 'PackageUpload' ) {
        my $Upload = $Self->_UploadGet( Request => $Request );
        if ( !$Upload || ( $Upload->{ContentSize} || 0 ) > 25 * 1024 * 1024 ) {
            $Error = 'Translate:AddonPackageSizeInvalid';
        }
        else {
            my $Inspection = $Manager->PackageInspect( Content => $Upload->{Content} );
            if ($Inspection) {
                my $Existing = $Manager->PackageGet( Identifier => $Inspection->{Manifest}->{id} );
                my $Type = $Existing ? 'update' : 'install';
                if ( $Manager->OperationQueue(
                    Type     => $Type,
                    Filename => $Upload->{Filename},
                    Content  => $Upload->{Content},
                    UserID   => $User->{user_account_id},
                ) ) {
                    return { Redirect => 'index.pl?Page=AdminAddons;Status=queued' };
                }
            }
            $Error = $Manager->Error() || 'Translate:AddonOperationQueueFailed';
        }
    }
    elsif ( $Step eq 'PackageUninstall' ) {
        if ( $Manager->OperationQueue(
            Type       => 'uninstall',
            Identifier => $Identifier,
            UserID     => $User->{user_account_id},
        ) ) {
            return { Redirect => 'index.pl?Page=AdminAddons;Status=queued' };
        }
        $Error = $Manager->Error();
    }

    $Notice = 'Translate:AddonOperationQueued' if ( $Request->{Status} || '' ) eq 'queued';

    my $Packages = $Manager->PackageList();
    for my $Package ( @{$Packages} ) {
        $Package->{status_label} = 'Translate:AddonStatus_' . ucfirst( $Package->{status} || 'unknown' );
    }
    my $Operations = $Manager->OperationList();
    for my $Operation ( @{$Operations} ) {
        $Operation->{operation_label} = 'Translate:AddonOperation_' . ucfirst( $Operation->{operation_type} || 'unknown' );
        $Operation->{status_label} = 'Translate:AddonOperationStatus_' . ucfirst( $Operation->{status} || 'unknown' );
        $Operation->{message} = $Operation->{error_message} || $Operation->{result_message} || '';
    }

    return {
        Template => 'AdminAddons.tt',
        Data => {
            PageTitle          => 'Translate:AdminAddonsTitle',
            ProgramTitle       => 'Translate:AdminAddonsTitle',
            ProgramDescription => 'Translate:AdminAddonsDescription',
            PackageList        => $Packages,
            PackageCount       => scalar @{$Packages},
            OperationList      => $Operations,
            OperationCount     => scalar @{$Operations},
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            NoticeMessage      => $Notice,
            NoticeClass        => $Notice ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
        },
    };
}

sub _UploadGet {
    my ( $Self, %Param ) = @_;
    my $Uploads = ( $Param{Request} || {} )->{__Uploads} || {};
    my $List = $Uploads->{AddonPackage};
    return ref $List eq 'ARRAY' ? $List->[0] : undef;
}

1;
