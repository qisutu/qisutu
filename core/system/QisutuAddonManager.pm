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

package QisutuAddonManager;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use File::Copy qw(copy);
use File::Basename qw(dirname);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Uncompress::Unzip qw($UnzipError);
use JSON::PP;

use QisutuSecurity;
use QisutuAddonAPI;

my $MaximumPackageSize = 25 * 1024 * 1024;
my $MaximumFileSize    = 20 * 1024 * 1024;
my $MaximumTotalSize   = 60 * 1024 * 1024;
my $MaximumFileCount   = 1000;
my $AddonAPIVersion    = '1.0';
my %AddonCapability    = map { $_ => 1 } qw(
    settings.v1 programs.v1 authentication.v1 tasks.v1
    services.v1 events.v1 rest-routes.v1 ui-slots.v1
);

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        Security  => $Param{Security} || QisutuSecurity->new( Config => $Param{Config} || {} ),
        JSON      => JSON::PP->new->canonical(1)->utf8(1),
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub PackageList {
    my ($Self) = @_;
    return [] if !$Self->{DB};

    return $Self->{DB}->SelectAll(
        'SELECT id, package_identifier, name, vendor, version, description,
                installed_path, package_checksum_sha256, signature_status,
                active, status, last_error, installed_at, changed_at
         FROM addon_package
         ORDER BY name, package_identifier'
    ) || [];
}

sub PackageGet {
    my ( $Self, %Param ) = @_;
    my $Identifier = $Self->_IdentifierClean( $Param{Identifier} );
    return if !$Identifier || !$Self->{DB};

    return $Self->{DB}->SelectRow(
        'SELECT * FROM addon_package WHERE package_identifier = ? LIMIT 1',
        $Identifier,
    );
}

sub OperationList {
    my ( $Self, %Param ) = @_;
    my $Limit = $Param{Limit} || 30;
    $Limit = 30 if $Limit !~ m{\A\d+\z} || $Limit < 1;
    $Limit = 100 if $Limit > 100;
    return [] if !$Self->{DB};

    return $Self->{DB}->SelectAll(
        'SELECT id, package_identifier, operation_type, package_filename,
                package_checksum_sha256, status, requested_by_user_id,
                result_message, error_message, created_at, finished_at
         FROM addon_operation
         ORDER BY id DESC
         LIMIT ' . int($Limit)
    ) || [];
}

sub PackageInspect {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Content = defined $Param{Content} ? $Param{Content} : '';
    if ( !$Content || length($Content) > $MaximumPackageSize ) {
        $Self->{LastError} = 'Translate:AddonPackageSizeInvalid';
        return;
    }

    my $Files = $Self->_ArchiveRead( Content => $Content ) || return;
    $Files = $Self->_ArchiveNormalize( Files => $Files ) || return;
    my $ManifestContent = $Files->{'qisutu-module.json'};
    if ( !defined $ManifestContent ) {
        $Self->{LastError} = 'Translate:AddonPackageControlFilesMissing';
        return;
    }

    my $Manifest = eval { $Self->{JSON}->decode($ManifestContent) };
    if ( !$Manifest || ref $Manifest ne 'HASH' ) {
        $Self->{LastError} = 'Translate:AddonManifestInvalid';
        return;
    }

    return if !$Self->_ManifestValidate( Manifest => $Manifest, Files => $Files );

    return {
        Manifest       => $Manifest,
        Files          => $Files,
        PackageSHA256  => sha256_hex($Content),
        SignatureStatus => 'source-zip',
    };
}

sub OperationQueue {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    return if !$Self->{DB};

    my $Type   = lc( $Param{Type} || '' );
    my $UserID = $Param{UserID} || 1;
    return $Self->_Error('Translate:AddonOperationInvalid')
        if $Type !~ m{\A(?:install|update|uninstall)\z};

    my ( $Identifier, $Filename, $Content, $Checksum );
    if ( $Type eq 'install' || $Type eq 'update' ) {
        $Filename = $Param{Filename} || '';
        $Content  = defined $Param{Content} ? $Param{Content} : '';
        return $Self->_Error('Translate:AddonPackageExtensionInvalid') if $Filename !~ m{\.zip\z}i;
        my $Inspection = $Self->PackageInspect( Content => $Content ) || return;
        $Identifier = $Inspection->{Manifest}->{id};
        $Checksum   = $Inspection->{PackageSHA256};

        my $Existing = $Self->PackageGet( Identifier => $Identifier );
        if ( $Type eq 'install' && $Existing ) {
            return $Self->_Error('Translate:AddonPackageAlreadyInstalled');
        }
        if ( $Type eq 'update' && !$Existing ) {
            return $Self->_Error('Translate:AddonPackageNotInstalled');
        }
        if ( $Existing && !$Self->_VersionGreater( $Inspection->{Manifest}->{version}, $Existing->{version} ) ) {
            return $Self->_Error('Translate:AddonUpdateVersionInvalid');
        }
    }
    else {
        $Identifier = $Self->_IdentifierClean( $Param{Identifier} );
        return $Self->_Error('Translate:AddonPackageNotInstalled')
            if !$Identifier || !$Self->PackageGet( Identifier => $Identifier );
        $Filename = '';
        $Content  = undef;
        $Checksum = '';
    }

    my $Pending = $Self->{DB}->SelectRow(
        'SELECT id FROM addon_operation
         WHERE package_identifier = ? AND status IN ("pending", "processing") LIMIT 1',
        $Identifier,
    );
    return $Self->_Error('Translate:AddonOperationAlreadyPending') if $Pending;

    my $OK = $Self->{DB}->Do(
        'INSERT INTO addon_operation (
            package_identifier, operation_type, package_filename, package_data,
            package_checksum_sha256, status, requested_by_user_id
         ) VALUES (?, ?, ?, ?, ?, "pending", ?)',
        $Identifier, $Type, $Filename, $Content, $Checksum, $UserID,
    );
    return $Self->_Error( $Self->{DB}->Error() || 'Translate:AddonOperationQueueFailed' ) if !$OK;
    return 1;
}

sub OperationProcessNext {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    return if !$Self->{DB};
    my $Worker = $Param{Worker} || 'qisutu-daemon';

    $Self->{DB}->Do(
        'UPDATE addon_operation SET status = "pending", locked_by = NULL, locked_at = NULL,
             error_message = "Recovered after an interrupted daemon operation"
         WHERE status = "processing" AND locked_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE)'
    );

    my $Operation = $Self->{DB}->SelectRow(
        'SELECT * FROM addon_operation WHERE status = "pending" ORDER BY id LIMIT 1'
    );
    return 0 if !$Operation;

    my $Claimed = $Self->{DB}->Do(
        'UPDATE addon_operation SET status = "processing", locked_by = ?, locked_at = NOW()
         WHERE id = ? AND status = "pending"',
        $Worker, $Operation->{id},
    );
    return 0 if !$Claimed;

    my $Result;
    my $OK = eval {
        if ( $Operation->{operation_type} eq 'uninstall' ) {
            $Result = $Self->_PackageUninstall( Operation => $Operation );
        }
        else {
            $Result = $Self->_PackageInstallOrUpdate( Operation => $Operation );
        }
        die( $Self->{LastError} || 'add-on operation failed' ) if !$Result;
        1;
    };

    if ($OK) {
        $Self->{DB}->Do(
            'UPDATE addon_operation
             SET status = "completed", package_data = NULL, result_message = ?,
                 error_message = NULL, finished_at = NOW()
             WHERE id = ?',
            $Result->{Message} || 'completed', $Operation->{id},
        );
        return 1;
    }

    my $Error = $@ || $Self->{LastError} || 'add-on operation failed';
    $Error =~ s{\s+at\s+.*\z}{}s;
    $Error = substr( $Error, 0, 4000 );
    $Self->{DB}->Do(
        'UPDATE addon_operation
         SET status = "failed", package_data = NULL, error_message = ?, finished_at = NOW()
         WHERE id = ?',
        $Error, $Operation->{id},
    );
    $Self->{LastError} = $Error;
    return;
}

sub SettingsDefinition {
    my ( $Self, %Param ) = @_;
    my $Package = $Self->PackageGet( Identifier => $Param{Identifier} ) || return [];
    my $Manifest = eval { $Self->{JSON}->decode( $Package->{manifest_json} || '{}' ) } || {};
    return ref $Manifest->{settings} eq 'ARRAY' ? $Manifest->{settings} : [];
}

sub SettingsGet {
    my ( $Self, %Param ) = @_;
    my $Identifier = $Self->_IdentifierClean( $Param{Identifier} );
    return {} if !$Identifier || !$Self->{DB};

    my $Definition = $Self->SettingsDefinition( Identifier => $Identifier );
    my %Definition = map { ( $_->{key} || '' ) => $_ } grep { ref $_ eq 'HASH' } @{$Definition};
    my %Value = map {
        my $Key = $_->{key} || '';
        $Key => exists $_->{default} ? $_->{default} : ''
    } grep { ref $_ eq 'HASH' && $_->{key} } @{$Definition};

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT setting_key, setting_value, is_secret FROM addon_setting
         WHERE package_identifier = ?',
        $Identifier,
    ) || [];
    for my $Row ( @{$Rows} ) {
        next if !$Definition{ $Row->{setting_key} || '' };
        my $Stored = defined $Row->{setting_value} ? $Row->{setting_value} : '';
        if ( $Row->{is_secret} && $Stored ) {
            $Stored = $Self->{Security}->Decrypt( Value => $Stored );
            next if !defined $Stored;
        }
        $Value{ $Row->{setting_key} } = $Stored;
    }
    return \%Value;
}

sub SettingsSave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Identifier = $Self->_IdentifierClean( $Param{Identifier} );
    my $Input      = $Param{Values} || {};
    my $UserID     = $Param{UserID} || 1;
    return $Self->_Error('Translate:AddonPackageNotInstalled') if !$Identifier || !$Self->{DB};

    my $Definition = $Self->SettingsDefinition( Identifier => $Identifier );
    my $Old = $Self->SettingsGet( Identifier => $Identifier );
    for my $Item ( @{$Definition} ) {
        next if ref $Item ne 'HASH';
        my $Key  = $Item->{key} || '';
        my $Type = $Item->{type} || 'text';
        next if !$Key;
        my $Value = exists $Input->{$Key} ? $Input->{$Key} : '';
        $Value = '' if !defined $Value;
        $Value = $Value ? 1 : 0 if $Type eq 'boolean';
        if ( $Type eq 'secret' && $Value eq '' && exists $Old->{$Key} ) {
            $Value = $Old->{$Key};
        }
        return $Self->_Error('Translate:AddonSettingRequired') if $Item->{required} && $Value eq '';
        return $Self->_Error('Translate:AddonSettingInvalid')
            if $Type eq 'integer' && $Value !~ m{\A\d+\z};
        if ( $Type eq 'select' && ref $Item->{options} eq 'ARRAY' ) {
            my %Allowed = map { $_ => 1 } @{ $Item->{options} };
            return $Self->_Error('Translate:AddonSettingInvalid') if !$Allowed{$Value};
        }
        return $Self->_Error('Translate:AddonSettingInvalid') if length($Value) > 10000;

        my $IsSecret = $Type eq 'secret' ? 1 : 0;
        my $Stored = $IsSecret && $Value ne '' ? $Self->{Security}->Encrypt( Value => $Value ) : "$Value";
        return $Self->_Error( $Self->{Security}->Error() || 'Translate:AddonSettingEncryptFailed' )
            if !defined $Stored;
        $Self->{DB}->Do(
            'INSERT INTO addon_setting (
                package_identifier, setting_key, setting_value, is_secret, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value),
                is_secret = VALUES(is_secret), changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $Identifier, $Key, $Stored, $IsSecret, $UserID,
        ) || return $Self->_Error( $Self->{DB}->Error() || 'Translate:AddonSettingSaveFailed' );
    }
    return 1;
}

sub TaskRunDue {
    my ( $Self, %Param ) = @_;
    return 0 if !$Self->{DB};
    my $Worker = $Param{Worker} || 'qisutu-daemon';
    my $Task = $Self->{DB}->SelectRow(
        'SELECT t.* FROM addon_task t
         INNER JOIN addon_package p ON p.package_identifier = t.package_identifier
         WHERE t.active = 1 AND p.active = 1 AND p.status = "installed"
           AND t.next_run_at <= NOW()
           AND (t.locked_until IS NULL OR t.locked_until < NOW())
         ORDER BY t.next_run_at, t.id LIMIT 1'
    );
    return 0 if !$Task;
    my $Claimed = $Self->{DB}->Do(
        'UPDATE addon_task SET locked_by = ?, locked_until = DATE_ADD(NOW(), INTERVAL 30 MINUTE),
             last_started_at = NOW(), last_status = "running"
         WHERE id = ? AND (locked_until IS NULL OR locked_until < NOW())',
        $Worker, $Task->{id},
    );
    return 0 if !$Claimed;

    my $Class = $Task->{handler_class} || '';
    my ( $OK, $Message, $NextInterval );
    if ( $Class =~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z} && eval "require $Class; 1;" ) {
        my $API = QisutuAddonAPI->new(
            Config     => $Self->{Config},
            DB         => $Self->{DB},
            Identifier => $Task->{package_identifier},
        );
        my $Handler = eval { $Class->new( Config => $Self->{Config}, DB => $Self->{DB}, API => $API ) };
        my $Result = $Handler ? eval { $Handler->Run( Task => $Task, API => $API ) } : undef;
        if ( $Result && ref $Result eq 'HASH' && $Result->{Success} ) {
            $OK = 1;
            $Message = $Result->{Message} || 'completed';
            $NextInterval = $Result->{NextInterval};
        }
        else {
            $Message = $@ || ( $Handler && $Handler->can('Error') ? $Handler->Error() : '' ) || 'task failed';
        }
    }
    else {
        $Message = $@ || 'task handler could not be loaded';
    }
    $NextInterval = $Task->{interval_seconds}
        if !$NextInterval || $NextInterval !~ m{\A\d+\z} || $NextInterval < 60;
    $NextInterval = 604800 if $NextInterval > 604800;
    $Message = substr( $Message || '', 0, 4000 );
    $Self->{DB}->Do(
        'UPDATE addon_task SET locked_by = NULL, locked_until = NULL,
             last_finished_at = NOW(), last_status = ?, last_message = ?,
             next_run_at = DATE_ADD(NOW(), INTERVAL ? SECOND)
         WHERE id = ?',
        $OK ? 'success' : 'failed', $Message, $NextInterval, $Task->{id},
    );
    return $OK ? 1 : undef;
}

sub _ArchiveRead {
    my ( $Self, %Param ) = @_;
    my $Content = $Param{Content};
    return $Self->_Error('Translate:AddonPackageArchiveInvalid')
        if !defined $Content || substr( $Content, 0, 4 ) ne "PK\x03\x04";
    my $TailLength = length($Content) < 65557 ? length($Content) : 65557;
    my $TailStart  = length($Content) - $TailLength;
    my $EOCDInTail = rindex( substr( $Content, $TailStart ), "PK\x05\x06" );
    return $Self->_Error('Translate:AddonPackageArchiveInvalid') if $EOCDInTail < 0;
    my $EOCD = $TailStart + $EOCDInTail;
    return $Self->_Error('Translate:AddonPackageArchiveInvalid') if length($Content) < $EOCD + 22;
    my $CommentLength = unpack( 'v', substr( $Content, $EOCD + 20, 2 ) );
    return $Self->_Error('Translate:AddonPackageArchiveInvalid')
        if $EOCD + 22 + $CommentLength != length($Content);
    my $Unzip = IO::Uncompress::Unzip->new( \$Content );
    return $Self->_Error( 'Translate:AddonPackageArchiveInvalid' ) if !$Unzip;

    my %Files;
    my $Total = 0;
    my $Count = 0;
    STREAM:
    while (1) {
        my $Header = $Unzip->getHeaderInfo() || {};
        my $Name = $Header->{Name} || '';
        $Name =~ tr{\\}{/};
        if ( $Name =~ m{/$} ) {
            my $DirectoryName = $Name;
            $DirectoryName =~ s{/+\z}{};
            return $Self->_Error('Translate:AddonPackagePathInvalid')
                if !$Self->_ArchivePathValid($DirectoryName);
            1 while $Unzip->read( my $Discard, 65536 ) > 0;
        }
        else {
            return $Self->_Error('Translate:AddonPackagePathInvalid') if !$Self->_ArchivePathValid($Name);
            return $Self->_Error('Translate:AddonPackageDuplicateFile') if exists $Files{$Name};
            my $Data = '';
            while (1) {
                my $Read = $Unzip->read( my $Buffer, 65536 );
                return $Self->_Error('Translate:AddonPackageArchiveInvalid') if !defined $Read || $Read < 0;
                last if !$Read;
                $Data .= $Buffer;
                return $Self->_Error('Translate:AddonPackageFileTooLarge') if length($Data) > $MaximumFileSize;
            }
            $Total += length($Data);
            $Count++;
            return $Self->_Error('Translate:AddonPackageExpandedSizeInvalid') if $Total > $MaximumTotalSize;
            return $Self->_Error('Translate:AddonPackageFileCountInvalid') if $Count > $MaximumFileCount;
            $Files{$Name} = $Data;
        }
        last STREAM if !$Unzip->nextStream();
    }
    return \%Files;
}

sub _ArchiveNormalize {
    my ( $Self, %Param ) = @_;
    my $Files = $Param{Files} || {};
    return $Files if exists $Files->{'qisutu-module.json'};

    my @Manifest = grep { m{\A[A-Za-z0-9_.-]+/qisutu-module[.]json\z} } keys %{$Files};
    return $Self->_Error('Translate:AddonPackageControlFilesMissing') if @Manifest != 1;
    my ($Root) = $Manifest[0] =~ m{\A([^/]+)/};
    return $Self->_Error('Translate:AddonPackageRootInvalid') if !$Root;

    my %Normalized;
    for my $Name ( keys %{$Files} ) {
        return $Self->_Error('Translate:AddonPackageRootInvalid') if index( $Name, $Root . '/' ) != 0;
        my $Relative = substr( $Name, length($Root) + 1 );
        return $Self->_Error('Translate:AddonPackageRootInvalid')
            if !$Self->_ArchivePathValid($Relative) || exists $Normalized{$Relative};
        $Normalized{$Relative} = $Files->{$Name};
    }
    return \%Normalized;
}

sub _ArchivePathValid {
    my ( $Self, $Name ) = @_;
    return if !$Name || length($Name) > 500;
    return if $Name =~ m{\A/|\x00|[\r\n]|(?:\A|/)\.{1,2}(?:/|\z)|//};
    return if $Name !~ m{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\z};
    return 1;
}

sub _ManifestValidate {
    my ( $Self, %Param ) = @_;
    my $Manifest = $Param{Manifest};
    my $Files    = $Param{Files};
    return $Self->_Error('Translate:AddonManifestFormatInvalid')
        if !defined $Manifest->{manifest_version}
        || $Manifest->{manifest_version} !~ m{\A1\z};
    my $Identifier = $Self->_IdentifierClean( $Manifest->{id} );
    return $Self->_Error('Translate:AddonManifestIdentifierInvalid')
        if !$Identifier || $Identifier ne ( $Manifest->{id} || '' );
    return $Self->_Error('Translate:AddonManifestNameInvalid')
        if !( $Manifest->{name} || '' ) || length( $Manifest->{name} ) > 255;
    return $Self->_Error('Translate:AddonManifestVersionInvalid')
        if ( $Manifest->{version} || '' ) !~ m{\A\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?\z};
    my $Minimum = ref $Manifest->{qisutu} eq 'HASH' ? ( $Manifest->{qisutu}->{minimum} || '' ) : '';
    my $Maximum = ref $Manifest->{qisutu} eq 'HASH' ? ( $Manifest->{qisutu}->{maximum} || '' ) : '';
    my $Current = $Self->{Config}->{System}->{Version} || '0.0.0';
    return $Self->_Error('Translate:AddonQisutuVersionIncompatible')
        if $Minimum && $Self->_VersionCompare( $Current, $Minimum ) < 0;
    return $Self->_Error('Translate:AddonQisutuVersionIncompatible')
        if $Maximum && $Self->_VersionCompare( $Current, $Maximum ) > 0;

    if ( exists $Manifest->{addon_api} ) {
        return $Self->_Error('Translate:AddonManifestAPIInvalid')
            if ref $Manifest->{addon_api} ne 'HASH';
        my $APIMinimum = $Manifest->{addon_api}->{minimum} || '';
        my $APIMaximum = $Manifest->{addon_api}->{maximum} || '';
        return $Self->_Error('Translate:AddonManifestAPIInvalid')
            if ( $APIMinimum && $APIMinimum !~ m{\A\d+\.\d+\z} )
            || ( $APIMaximum && $APIMaximum !~ m{\A\d+\.\d+\z} )
            || ref( $Manifest->{addon_api}->{capabilities} || [] ) ne 'ARRAY';
        return $Self->_Error('Translate:AddonAPIIncompatible')
            if $APIMinimum && $Self->_VersionCompare( $AddonAPIVersion, $APIMinimum ) < 0;
        return $Self->_Error('Translate:AddonAPIIncompatible')
            if $APIMaximum && $Self->_VersionCompare( $AddonAPIVersion, $APIMaximum ) > 0;
        for my $Capability ( @{ $Manifest->{addon_api}->{capabilities} || [] } ) {
            return $Self->_Error('Translate:AddonCapabilityUnavailable')
                if !defined $Capability || !$AddonCapability{$Capability};
        }
    }

    for my $Setting ( @{ ref $Manifest->{settings} eq 'ARRAY' ? $Manifest->{settings} : [] } ) {
        return $Self->_Error('Translate:AddonManifestSettingInvalid') if ref $Setting ne 'HASH';
        return $Self->_Error('Translate:AddonManifestSettingInvalid')
            if ( $Setting->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z};
        return $Self->_Error('Translate:AddonManifestSettingInvalid')
            if ( $Setting->{type} || 'text' ) !~ m{\A(?:text|secret|boolean|integer|select)\z};
    }
    for my $Provider ( @{ ref $Manifest->{auth_providers} eq 'ARRAY' ? $Manifest->{auth_providers} : [] } ) {
        return $Self->_Error('Translate:AddonManifestProviderInvalid') if ref $Provider ne 'HASH';
        return $Self->_Error('Translate:AddonManifestProviderInvalid')
            if ( $Provider->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Provider->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || ( $Provider->{account_type} || '' ) !~ m{\A(?:agent|customer)\z};
    }
    for my $Task ( @{ ref $Manifest->{tasks} eq 'ARRAY' ? $Manifest->{tasks} : [] } ) {
        return $Self->_Error('Translate:AddonManifestTaskInvalid') if ref $Task ne 'HASH';
        return $Self->_Error('Translate:AddonManifestTaskInvalid')
            if ( $Task->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Task->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z};
    }
    my %ServiceKey;
    for my $Service ( @{ ref $Manifest->{services} eq 'ARRAY' ? $Manifest->{services} : [] } ) {
        return $Self->_Error('Translate:AddonManifestServiceInvalid') if ref $Service ne 'HASH';
        return $Self->_Error('Translate:AddonManifestServiceInvalid')
            if ( $Service->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Service->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || $ServiceKey{ $Service->{key} }++;
    }
    my %SubscriberKey;
    for my $Subscriber ( @{ ref $Manifest->{event_subscribers} eq 'ARRAY' ? $Manifest->{event_subscribers} : [] } ) {
        return $Self->_Error('Translate:AddonManifestEventInvalid') if ref $Subscriber ne 'HASH';
        return $Self->_Error('Translate:AddonManifestEventInvalid')
            if ( $Subscriber->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Subscriber->{event} || '' ) !~ m{\A[a-z][a-z0-9_-]*(?:(?:\.[a-z0-9_-]+)+(?:\.\*)?|\.\*)\z}
            || ( $Subscriber->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || ( $Subscriber->{method} || 'Handle' ) !~ m{\A[A-Za-z][A-Za-z0-9_]*\z}
            || ( $Subscriber->{mode} || 'async' ) !~ m{\A(?:async|sync)\z}
            || $SubscriberKey{ $Subscriber->{key} }++;
    }
    my %RouteKey;
    for my $Route ( @{ ref $Manifest->{rest_routes} eq 'ARRAY' ? $Manifest->{rest_routes} : [] } ) {
        return $Self->_Error('Translate:AddonManifestRESTInvalid') if ref $Route ne 'HASH';
        my $Path = $Route->{path} || '';
        return $Self->_Error('Translate:AddonManifestRESTInvalid')
            if ( $Route->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Route->{method} || '' ) !~ m{\A(?:GET|POST|PUT|PATCH|DELETE)\z}
            || $Path !~ m{\A/v1/addons/\Q$Identifier\E(?:/|\z)}
            || $Path !~ m{\A/v1/addons/[a-z0-9.-]+(?:/(?:[A-Za-z0-9._-]+|\{[a-z][a-z0-9_]*\}))*\z}
            || ( $Route->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || ( $Route->{handler_method} || 'Handle' ) !~ m{\A[A-Za-z][A-Za-z0-9_]*\z}
            || ref( $Route->{scopes} || [] ) ne 'ARRAY'
            || ref( $Route->{access_types} || [] ) ne 'ARRAY'
            || $RouteKey{ $Route->{key} }++;
        for my $Scope ( @{ $Route->{scopes} || [] } ) {
            return $Self->_Error('Translate:AddonManifestRESTInvalid')
                if !defined $Scope || $Scope !~ m{\A[a-z][a-z0-9_.-]{0,99}\z};
        }
        for my $Type ( @{ $Route->{access_types} || [] } ) {
            return $Self->_Error('Translate:AddonManifestRESTInvalid')
                if !defined $Type || $Type !~ m{\A(?:agent|customer)\z};
        }
    }
    my %SlotKey;
    for my $Slot ( @{ ref $Manifest->{ui_slots} eq 'ARRAY' ? $Manifest->{ui_slots} : [] } ) {
        return $Self->_Error('Translate:AddonManifestUISlotInvalid') if ref $Slot ne 'HASH';
        return $Self->_Error('Translate:AddonManifestUISlotInvalid')
            if ( $Slot->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z}
            || ( $Slot->{slot} || '' ) !~ m{\A(?:page|dashboard|ticket\.zoom|admin)\.(?:before|after)\z}
            || ( $Slot->{class} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || ( $Slot->{method} || 'Render' ) !~ m{\A[A-Za-z][A-Za-z0-9_]*\z}
            || ( defined $Slot->{order} && $Slot->{order} !~ m{\A\d{1,6}\z} )
            || ( $Slot->{program} && $Slot->{program} !~ m{\A[A-Za-z][A-Za-z0-9_:]*\z} )
            || ref( $Slot->{access_types} || [] ) ne 'ARRAY'
            || $SlotKey{ $Slot->{key} }++;
        for my $Type ( @{ $Slot->{access_types} || [] } ) {
            return $Self->_Error('Translate:AddonManifestUISlotInvalid')
                if !defined $Type || $Type !~ m{\A(?:agent|customer)\z};
        }
    }
    return $Self->_Error('Translate:AddonManifestFilesInvalid')
        if ref $Manifest->{files} ne 'ARRAY';
    my %Declared;
    for my $File ( @{ $Manifest->{files} } ) {
        return $Self->_Error('Translate:AddonManifestFilesInvalid') if ref $File ne 'HASH';
        my $Name = $File->{path} || '';
        my $Permission = defined $File->{permission} ? "$File->{permission}" : '';
        return $Self->_Error('Translate:AddonManifestFilesInvalid')
            if !$Self->_ArchivePathValid($Name)
            || $Name eq 'qisutu-module.json'
            || !$Self->_ModuleFileAllowed($Name)
            || $Permission !~ m{\A0?(?:644|755)\z}
            || ( $Permission =~ m{755\z} && $Name !~ m{\Abin/} )
            || $Declared{$Name}++
            || !exists $Files->{$Name};
        $File->{permission} = $Permission =~ m{755\z} ? '0755' : '0644';
        if ( $Name =~ m{\Alib/(.+)\.pm\z} ) {
            my $Package = $1;
            $Package =~ s{/}{::}g;
            return $Self->_Error('Translate:AddonPackageNamespaceInvalid')
                if $Package !~ m{\AQisutu::Addon::};
        }
    }
    for my $Name ( keys %{$Files} ) {
        next if $Name eq 'qisutu-module.json';
        return $Self->_Error('Translate:AddonPackageFileUndeclared') if !$Declared{$Name};
    }
    return 1;
}

sub _ModuleFileAllowed {
    my ( $Self, $Name ) = @_;
    return 1 if $Name =~ m{\A(?:README[.]md|LICENSE|COPYING|CHANGELOG[.]md)\z};
    return 1 if $Name =~ m{\A(?:lib|programs|templates|languages|static|migrations|bin|apache)/};
    return;
}

sub _PackageInstallOrUpdate {
    my ( $Self, %Param ) = @_;
    my $Operation = $Param{Operation};
    my $Content = $Operation->{package_data};
    return $Self->_Error('package data is missing') if !defined $Content;
    my $Inspection = $Self->PackageInspect( Content => $Content ) || return;
    return $Self->_Error('package checksum changed after upload')
        if ( $Operation->{package_checksum_sha256} || '' ) ne $Inspection->{PackageSHA256};
    my $Manifest   = $Inspection->{Manifest};
    my $Identifier = $Manifest->{id};
    return $Self->_Error('package identifier changed after upload')
        if ( $Operation->{package_identifier} || '' ) ne $Identifier;
    my $Existing = $Self->PackageGet( Identifier => $Identifier );
    my $OperationType = $Operation->{operation_type} || '';
    return $Self->_Error('add-on is already installed')
        if $OperationType eq 'install' && $Existing;
    return $Self->_Error('add-on is not installed')
        if $OperationType eq 'update' && !$Existing;
    return $Self->_Error('add-on update version is not newer than the installed version')
        if $OperationType eq 'update'
        && !$Self->_VersionGreater( $Manifest->{version}, $Existing->{version} );
    return $Self->_Error('invalid daemon-side add-on operation')
        if $OperationType !~ m{\A(?:install|update)\z};

    my $Root = $Self->_AddonRoot();
    make_path($Root, { mode => 0755 }) if !-d $Root;
    my $Target = File::Spec->catdir( $Root, split /\./, $Identifier );
    return $Self->_Error('unsafe add-on installation path') if index( $Target, $Root . '/' ) != 0;
    make_path( dirname($Target), { mode => 0755 } ) if !-d dirname($Target);
    my $Stage = tempdir( '.qisutu-addon-stage-XXXXXX', DIR => $Root, CLEANUP => 0 );
    my $Backup = $Target . '.previous-' . $Operation->{id};

    my $Written = eval {
        $Self->_FilesWrite(
            Root     => $Stage,
            Files    => $Inspection->{Files},
            Manifest => $Manifest,
        );
        1;
    };
    if (!$Written) {
        my $Error = $@ || $Self->{LastError} || 'package files could not be written';
        remove_tree($Stage) if -d $Stage;
        return $Self->_Error($Error);
    }

    if ( !$Self->_MigrationsApply( Manifest => $Manifest, Files => $Inspection->{Files} ) ) {
        remove_tree($Stage) if -d $Stage;
        return;
    }
    if ( -e $Backup ) {
        remove_tree($Backup);
    }
    if ( -d $Target && !rename $Target, $Backup ) {
        remove_tree($Stage);
        return $Self->_Error("installed add-on could not be backed up: $!");
    }
    if ( !rename $Stage, $Target ) {
        rename $Backup, $Target if -d $Backup;
        remove_tree($Stage) if -d $Stage;
        return $Self->_Error("add-on could not be activated on disk: $!");
    }

    my $StaticOK = eval {
        $Self->_StaticPublish( Identifier => $Identifier, Source => File::Spec->catdir( $Target, 'static' ) );
        1;
    };
    if (!$StaticOK) {
        my $Error = $@ || 'static add-on files could not be published';
        remove_tree($Target) if -d $Target;
        rename $Backup, $Target if -d $Backup;
        return $Self->_Error($Error);
    }

    my $ManifestJSON = $Self->{JSON}->encode($Manifest);
    my $OK = $Self->{DB}->Do(
        'INSERT INTO addon_package (
            package_identifier, name, vendor, version, description, installed_path,
            manifest_json, package_checksum_sha256, signature_status, active,
            status, last_error, installed_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, "installed", NULL, ?, ?)
         ON DUPLICATE KEY UPDATE name = VALUES(name), vendor = VALUES(vendor),
            version = VALUES(version), description = VALUES(description),
            installed_path = VALUES(installed_path), manifest_json = VALUES(manifest_json),
            package_checksum_sha256 = VALUES(package_checksum_sha256),
            signature_status = VALUES(signature_status), active = 1,
            status = "installed", last_error = NULL,
            changed_by_user_id = VALUES(changed_by_user_id), changed_at = CURRENT_TIMESTAMP',
        $Identifier, $Manifest->{name}, $Manifest->{vendor} || '', $Manifest->{version},
        $Manifest->{description} || '', $Target, $ManifestJSON, $Inspection->{PackageSHA256},
        $Inspection->{SignatureStatus}, $Operation->{requested_by_user_id} || 1,
        $Operation->{requested_by_user_id} || 1,
    );
    if (!$OK) {
        remove_tree($Target) if -d $Target;
        rename $Backup, $Target if -d $Backup;
        return $Self->_Error( $Self->{DB}->Error() || 'add-on registry update failed' );
    }
    $Self->_TasksRegister( Manifest => $Manifest );
    $Self->_AddonLifecycleEventEmit(
        Event => $Existing ? 'addon.updated' : 'addon.installed',
        Payload => {
            package_identifier => $Identifier,
            version => $Manifest->{version},
            previous_version => $Existing ? ( $Existing->{version} || '' ) : '',
        },
    );
    remove_tree($Backup) if -d $Backup;
    return { Message => ( $Existing ? 'updated' : 'installed' ) . ' ' . $Identifier . ' ' . $Manifest->{version} };
}

sub _PackageUninstall {
    my ( $Self, %Param ) = @_;
    my $Operation  = $Param{Operation};
    my $Identifier = $Self->_IdentifierClean( $Operation->{package_identifier} );
    my $Package    = $Self->PackageGet( Identifier => $Identifier )
        || return $Self->_Error('add-on is not installed');
    my $Root = $Self->_AddonRoot();
    my $Target = $Package->{installed_path} || '';
    return $Self->_Error('unsafe installed add-on path')
        if !$Target || index( $Target, $Root . '/' ) != 0 || $Target =~ m{(?:\A|/)\.\.(?:/|\z)};
    $Self->_AddonLifecycleEventEmit(
        Event => 'addon.uninstalling',
        Payload => { package_identifier => $Identifier, version => $Package->{version} || '' },
    );
    $Self->{DB}->Do(
        'UPDATE addon_package SET active = 0, status = "removing", changed_at = NOW()
         WHERE package_identifier = ?', $Identifier,
    ) || return $Self->_Error( $Self->{DB}->Error() || 'add-on could not be prepared for removal' );
    remove_tree($Target) if -d $Target;
    my $Static = File::Spec->catdir( $Self->_StaticAddonRoot(), split /\./, $Identifier );
    remove_tree($Static) if -d $Static && index( $Static, $Self->_StaticAddonRoot() . '/' ) == 0;
    $Self->{DB}->Do('DELETE FROM addon_event_queue WHERE package_identifier = ?', $Identifier);
    $Self->{DB}->Do('DELETE FROM addon_task WHERE package_identifier = ?', $Identifier);
    $Self->{DB}->Do('DELETE FROM addon_package WHERE package_identifier = ?', $Identifier)
        || return $Self->_Error( $Self->{DB}->Error() || 'add-on registry removal failed' );
    return { Message => 'uninstalled ' . $Identifier . '; settings and module data were retained' };
}

sub _FilesWrite {
    my ( $Self, %Param ) = @_;
    my $Root     = $Param{Root};
    my $Files    = $Param{Files};
    my $Manifest = $Param{Manifest} || {};
    my %Permission = map {
        ( $_->{path} || '' ) => ( ( $_->{permission} || '' ) eq '0755' ? 0755 : 0644 )
    } grep { ref $_ eq 'HASH' } @{ ref $Manifest->{files} eq 'ARRAY' ? $Manifest->{files} : [] };
    $Permission{'qisutu-module.json'} = 0644;
    for my $Name ( sort keys %{$Files} ) {
        my @Part = split /\//, $Name;
        my $FileName = pop @Part;
        my $Directory = @Part ? File::Spec->catdir( $Root, @Part ) : $Root;
        make_path( $Directory, { mode => 0755 } ) if !-d $Directory;
        my $Path = File::Spec->catfile( $Directory, $FileName );
        sysopen my $Handle, $Path, O_CREAT | O_EXCL | O_WRONLY, 0644
            or die "add-on file could not be created: $Name: $!";
        binmode $Handle;
        print {$Handle} $Files->{$Name} or die "add-on file could not be written: $Name: $!";
        close $Handle or die "add-on file could not be closed: $Name: $!";
        chmod( $Permission{$Name} || 0644, $Path )
            or die "add-on file permission could not be set: $Name: $!";
    }
    return 1;
}

sub _MigrationsApply {
    my ( $Self, %Param ) = @_;
    my $Manifest = $Param{Manifest};
    my $Files    = $Param{Files};
    for my $Migration ( @{ ref $Manifest->{migrations} eq 'ARRAY' ? $Manifest->{migrations} : [] } ) {
        return $Self->_Error('invalid add-on migration definition') if ref $Migration ne 'HASH';
        my $Key  = $Migration->{key} || '';
        my $File = $Migration->{file} || '';
        return $Self->_Error('invalid add-on migration path')
            if $Key !~ m{\A[a-zA-Z0-9_.-]{1,190}\z} || $File !~ m{\Amigrations/[A-Za-z0-9_.\/-]+\.sql\z}
            || !exists $Files->{$File};
        my $Checksum = sha256_hex( $Files->{$File} );
        my $Old = $Self->{DB}->SelectRow(
            'SELECT checksum_sha256 FROM addon_migration
             WHERE package_identifier = ? AND migration_key = ? LIMIT 1',
            $Manifest->{id}, $Key,
        );
        if ($Old) {
            return $Self->_Error('published add-on migration checksum changed')
                if ( $Old->{checksum_sha256} || '' ) ne $Checksum;
            next;
        }
        my $SQL = $Files->{$File};
        $SQL =~ s{\A\x{FEFF}}{};
        return $Self->_Error('empty add-on migration') if $SQL !~ m{\S};
        $Self->{DB}->Do($SQL) || return $Self->_Error( $Self->{DB}->Error() || 'add-on migration failed' );
        $Self->{DB}->Do(
            'INSERT INTO addon_migration (
                package_identifier, migration_key, package_version, checksum_sha256
             ) VALUES (?, ?, ?, ?)',
            $Manifest->{id}, $Key, $Manifest->{version}, $Checksum,
        ) || return $Self->_Error( $Self->{DB}->Error() || 'add-on migration log failed' );
    }
    return 1;
}

sub _TasksRegister {
    my ( $Self, %Param ) = @_;
    my $Manifest = $Param{Manifest};
    my %Current;
    for my $Task ( @{ ref $Manifest->{tasks} eq 'ARRAY' ? $Manifest->{tasks} : [] } ) {
        my $Key = $Task->{key};
        my $Interval = $Task->{interval_seconds} || 3600;
        $Interval = 60 if $Interval < 60;
        $Interval = 604800 if $Interval > 604800;
        $Current{$Key} = 1;
        $Self->{DB}->Do(
            'INSERT INTO addon_task (
                package_identifier, task_key, handler_class, interval_seconds, active, next_run_at
             ) VALUES (?, ?, ?, ?, 1, NOW())
             ON DUPLICATE KEY UPDATE handler_class = VALUES(handler_class),
                interval_seconds = VALUES(interval_seconds), active = 1,
                changed_at = CURRENT_TIMESTAMP',
            $Manifest->{id}, $Key, $Task->{class}, $Interval,
        );
    }
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT task_key FROM addon_task WHERE package_identifier = ?', $Manifest->{id}
    ) || [];
    for my $Row ( @{$Rows} ) {
        next if $Current{ $Row->{task_key} || '' };
        $Self->{DB}->Do(
            'UPDATE addon_task SET active = 0 WHERE package_identifier = ? AND task_key = ?',
            $Manifest->{id}, $Row->{task_key},
        );
    }
    return 1;
}

sub _StaticPublish {
    my ( $Self, %Param ) = @_;
    my $Identifier = $Param{Identifier};
    my $Source     = $Param{Source};
    my $Root = $Self->_StaticAddonRoot();
    make_path($Root, { mode => 0755 }) if !-d $Root;
    my $Target = File::Spec->catdir( $Root, split /\./, $Identifier );
    remove_tree($Target) if -d $Target;
    return 1 if !-d $Source;
    $Self->_DirectoryCopy( Source => $Source, Target => $Target );
    return 1;
}

sub _DirectoryCopy {
    my ( $Self, %Param ) = @_;
    my $Source = $Param{Source};
    my $Target = $Param{Target};
    make_path( $Target, { mode => 0755 } );
    opendir my $DH, $Source or die "directory could not be opened: $!";
    for my $Name ( grep { $_ ne '.' && $_ ne '..' } readdir $DH ) {
        my $From = File::Spec->catfile( $Source, $Name );
        my $To   = File::Spec->catfile( $Target, $Name );
        if ( -d $From ) {
            $Self->_DirectoryCopy( Source => $From, Target => $To );
        }
        elsif ( -f $From ) {
            copy( $From, $To ) or die "static add-on file could not be copied: $!";
            chmod 0644, $To;
        }
    }
    closedir $DH;
    return 1;
}

sub _AddonRoot {
    my ($Self) = @_;
    return $Self->{Config}->{Paths}->{Addons}
        || File::Spec->catdir( $Self->{Config}->{RootPath} || '/opt/qisutu', 'addons' );
}

sub _StaticAddonRoot {
    my ($Self) = @_;
    return File::Spec->catdir( $Self->{Config}->{Paths}->{Static} || '', 'addons' );
}

sub _IdentifierClean {
    my ( $Self, $Value ) = @_;
    $Value = lc( $Value || '' );
    return '' if $Value !~ m{\A[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+\z};
    return '' if length($Value) > 190;
    return $Value;
}

sub _VersionCompare {
    my ( $Self, $Left, $Right ) = @_;
    my ( $LeftCore, $LeftPre )   = split /-/, $Left || '0.0.0', 2;
    my ( $RightCore, $RightPre ) = split /-/, $Right || '0.0.0', 2;
    my @Left  = split /\./, $LeftCore;
    my @Right = split /\./, $RightCore;
    for my $Index ( 0 .. 2 ) {
        my $Compare = ( $Left[$Index] || 0 ) <=> ( $Right[$Index] || 0 );
        return $Compare if $Compare;
    }
    return 0 if !defined $LeftPre && !defined $RightPre;
    return 1 if !defined $LeftPre;
    return -1 if !defined $RightPre;
    my @LeftPre  = split /\./, $LeftPre;
    my @RightPre = split /\./, $RightPre;
    my $Count = @LeftPre > @RightPre ? scalar @LeftPre : scalar @RightPre;
    for my $Index ( 0 .. $Count - 1 ) {
        return -1 if !defined $LeftPre[$Index];
        return 1 if !defined $RightPre[$Index];
        my $Compare;
        if ( $LeftPre[$Index] =~ m{\A\d+\z} && $RightPre[$Index] =~ m{\A\d+\z} ) {
            $Compare = $LeftPre[$Index] <=> $RightPre[$Index];
        }
        elsif ( $LeftPre[$Index] =~ m{\A\d+\z} ) {
            $Compare = -1;
        }
        elsif ( $RightPre[$Index] =~ m{\A\d+\z} ) {
            $Compare = 1;
        }
        else {
            $Compare = $LeftPre[$Index] cmp $RightPre[$Index];
        }
        return $Compare if $Compare;
    }
    return 0;
}

sub _VersionGreater {
    my ( $Self, $Left, $Right ) = @_;
    return $Self->_VersionCompare( $Left, $Right ) > 0 ? 1 : 0;
}

sub _AddonLifecycleEventEmit {
    my ( $Self, %Param ) = @_;
    return 1 if !@{ ( $Self->{Config}->{AddonRuntime} || {} )->{EventSubscribers} || [] };
    eval {
        require QisutuAddonEvent;
        QisutuAddonEvent->new( Config => $Self->{Config}, DB => $Self->{DB} )->Emit(
            Event   => $Param{Event},
            Payload => ref $Param{Payload} eq 'HASH' ? $Param{Payload} : {},
            Source  => 'qisutu.core',
        );
    };
    return 1;
}

sub _Error {
    my ( $Self, $Message ) = @_;
    $Self->{LastError} = $Message || 'add-on error';
    return;
}

1;
