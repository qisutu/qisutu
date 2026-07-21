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

package QisutuMasterDataImport;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use Encode qw(encode);

use QisutuAdmin;
use QisutuPasswordReset;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub ImportTypes {
    return [qw(customer customer_user agent)];
}

sub Definition {
    my ( $Self, %Param ) = @_;

    my $Type     = $Self->_TypeClean( $Param{Type} );
    my $Language = $Self->_LanguageClean( $Param{Language} || 'en' );
    return if !$Type;

    my %Core = (
        customer => [
            { Column => 'customer_number', Required => 1, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldCustomerNumber', Example => 'K-1000' },
            { Column => 'name',            Required => 1, MaxLength => 255, DescriptionKey => 'MasterDataImportFieldCustomerName',   Example => 'Beispiel GmbH' },
            { Column => 'active',          Required => 1, FieldType => 'boolean', DescriptionKey => 'MasterDataImportFieldActive', Example => '1' },
        ],
        customer_user => [
            { Column => 'customer_number', Required => 1, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldCustomerReference', Example => 'K-1000' },
            { Column => 'login',           Required => 1, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldLogin',              Example => 'max.mustermann' },
            { Column => 'email',           Required => 1, MaxLength => 255, FieldType => 'email', DescriptionKey => 'MasterDataImportFieldEmail', Example => 'max@example.org' },
            { Column => 'firstname',       Required => 0, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldFirstname', Example => 'Max' },
            { Column => 'lastname',        Required => 0, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldLastname',  Example => 'Mustermann' },
            { Column => 'active',          Required => 1, FieldType => 'boolean', DescriptionKey => 'MasterDataImportFieldActive', Example => '1' },
        ],
        agent => [
            { Column => 'login',     Required => 1, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldLogin',     Example => 'agent01' },
            { Column => 'email',     Required => 1, MaxLength => 255, FieldType => 'email', DescriptionKey => 'MasterDataImportFieldEmail', Example => 'agent01@example.org' },
            { Column => 'firstname', Required => 0, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldFirstname', Example => 'Erika' },
            { Column => 'lastname',  Required => 0, MaxLength => 100, DescriptionKey => 'MasterDataImportFieldLastname',  Example => 'Musterfrau' },
            { Column => 'active',    Required => 1, FieldType => 'boolean', DescriptionKey => 'MasterDataImportFieldActive', Example => '1' },
        ],
    );

    my @Fields = map { +{%{$_}} } @{$Core{$Type}};
    my $ObjectType = $Self->_ObjectType($Type);
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );

    my $Dynamic = $Self->{DB}->SelectAll(
        'SELECT
            f.id,
            f.name,
            COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label,
            f.field_type,
            f.is_required,
            f.sort_order
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
            AND current_translation.language = ?
         LEFT JOIN user_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id
            AND default_translation.language = ?
         WHERE f.object_type = ?
           AND f.active = 1
         ORDER BY f.sort_order ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
        $ObjectType,
    );
    if ( !defined $Dynamic ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:MasterDataImportDataLoadFailed';
        return;
    }

    for my $Field ( @{$Dynamic} ) {
        push @Fields, {
            Column       => 'dynamic.' . ( $Field->{name} || '' ),
            Required     => $Field->{is_required} ? 1 : 0,
            FieldType    => $Field->{field_type} || 'text',
            Dynamic      => 1,
            DynamicID    => $Field->{id},
            DynamicName  => $Field->{name} || '',
            Label        => $Field->{label} || $Field->{name} || '',
            DescriptionKey => 'MasterDataImportFieldDynamic',
            Example      => '',
        };
    }

    return {
        Type       => $Type,
        ObjectType => $ObjectType,
        Fields     => \@Fields,
        Header     => [ map { $_->{Column} } @Fields ],
    };
}

sub TemplateCSV {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->Definition(%Param) || return;
    my $Line = join ';', map { $Self->_CSVField($_) } @{$Definition->{Header}};
    return chr(0xFEFF) . $Line . "\r\n";
}

sub PreviewCreate {
    my ( $Self, %Param ) = @_;

    my $Type     = $Self->_TypeClean( $Param{Type} );
    my $Content  = defined $Param{Content} ? $Param{Content} : '';
    my $FileName = $Self->_FileNameClean( $Param{FileName} || 'import.csv' );
    my $UserID   = $Self->_ID( $Param{UserID} );
    my $Language = $Self->_LanguageClean( $Param{Language} || 'en' );

    if ( !$Type || !$UserID || !length $Content ) {
        $Self->{LastError} = 'Translate:MasterDataImportFileInvalid';
        return;
    }

    if ( length( encode( 'UTF-8', $Content ) ) > 10 * 1024 * 1024 ) {
        $Self->{LastError} = 'Translate:MasterDataImportFileTooLarge';
        return;
    }

    $Self->_ExpiredCleanup();

    my $Analysis = $Self->_Analyze(
        Type     => $Type,
        Content  => $Content,
        Language => $Language,
    );
    return if !$Analysis;

    my $Status = $Analysis->{ErrorCount} ? 'invalid' : 'pending';
    my $StoredContent = $Status eq 'pending' ? $Content : undef;
    my $FileSHA = sha256_hex( encode( 'UTF-8', $Content ) );
    my $AnalysisSHA = $Self->_AnalysisSHA($Analysis);

    my $Created = $Self->{DB}->Do(
        'INSERT INTO master_data_import_run (
            import_type, file_name, file_sha256, analysis_sha256, status, staged_content,
            total_count, created_count, updated_count, unchanged_count, error_count,
            created_by_user_id, created_at, expires_at
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL 24 HOUR)
         )',
        $Type,
        $FileName,
        $FileSHA,
        $AnalysisSHA,
        $Status,
        $StoredContent,
        $Analysis->{TotalCount},
        $Analysis->{CreateCount},
        $Analysis->{UpdateCount},
        $Analysis->{UnchangedCount},
        $Analysis->{ErrorCount},
        $UserID,
    );

    if ( !$Created ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:MasterDataImportPreviewFailed';
        return;
    }

    my $RunID = $Self->{DB}->LastInsertID('master_data_import_run') || 0;
    if ( !$RunID || !$Self->_ItemsStore( RunID => $RunID, Items => $Analysis->{Items} ) ) {
        $Self->{DB}->Do( 'DELETE FROM master_data_import_run WHERE id = ?', $RunID ) if $RunID;
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Translate:MasterDataImportPreviewFailed';
        return;
    }

    return $Self->RunGet( RunID => $RunID );
}

sub ImportRun {
    my ( $Self, %Param ) = @_;

    my $RunID           = $Self->_ID( $Param{RunID} );
    my $UserID          = $Self->_ID( $Param{UserID} );
    my $Language        = $Self->_LanguageClean( $Param{Language} || 'en' );
    my $SendInvitations = $Param{SendInvitations} ? 1 : 0;

    if ( !$RunID || !$UserID ) {
        $Self->{LastError} = 'Translate:MasterDataImportRunInvalid';
        return;
    }

    my $Run = $Self->{DB}->SelectRow(
        'SELECT *
         FROM master_data_import_run
         WHERE id = ?
           AND created_by_user_id = ?
           AND status = "pending"
           AND staged_content IS NOT NULL
           AND expires_at > NOW()
         LIMIT 1',
        $RunID,
        $UserID,
    );

    if ( !$Run ) {
        $Self->{LastError} = 'Translate:MasterDataImportRunExpired';
        return;
    }

    my $TransactionStarted = 0;
    my $AnalysisChanged = 0;
    my @Invitation;
    my $Analysis;
    my $Success = eval {
        $Self->{DB}->BeginWork() || die "Database transaction could not be started\n";
        $TransactionStarted = 1;

        $Run = $Self->{DB}->SelectRow(
            'SELECT *
             FROM master_data_import_run
             WHERE id = ?
               AND created_by_user_id = ?
               AND status = "pending"
               AND staged_content IS NOT NULL
               AND expires_at > NOW()
             LIMIT 1
             FOR UPDATE',
            $RunID,
            $UserID,
        );
        die "Import run is no longer available\n" if !$Run;

        my $CurrentSHA = sha256_hex( encode( 'UTF-8', $Run->{staged_content} || '' ) );
        die "Staged CSV checksum differs\n" if $CurrentSHA ne ( $Run->{file_sha256} || '' );

        $Analysis = $Self->_Analyze(
            Type     => $Run->{import_type},
            Content  => $Run->{staged_content},
            Language => $Language,
        );
        die "CSV validation could not be repeated\n" if !$Analysis;
        if ( $Analysis->{ErrorCount} || $Self->_AnalysisSHA($Analysis) ne ( $Run->{analysis_sha256} || '' ) ) {
            $AnalysisChanged = 1;
            die "CSV validation changed\n";
        }

        my $Admin = QisutuAdmin->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );

        for my $Item ( @{$Analysis->{Items}} ) {
            next if ( $Item->{Action} || '' ) eq 'unchanged';
            next if ( $Item->{Action} || '' ) eq 'error';

            my $Result = $Self->_ApplyItem(
                Type     => $Run->{import_type},
                Item     => $Item,
                Admin    => $Admin,
                UserID   => $UserID,
            );
            die( ( $Self->{LastError} || $Admin->Error() || $Self->{DB}->Error() || 'Import row failed' ) . "\n" ) if !$Result;

            if (
                $SendInvitations
                && ( $Item->{Action} || '' ) eq 'create'
                && ( $Item->{Data}->{active} || '' ) eq '1'
                && $Run->{import_type} ne 'customer'
                )
            {
                push @Invitation, {
                    AccountType => $Run->{import_type} eq 'agent' ? 'agent' : 'customer',
                    Login       => $Item->{Data}->{login},
                };
            }
        }

        $Self->{DB}->Do(
            'UPDATE master_data_import_run
             SET status = "imported",
                 staged_content = NULL,
                 total_count = ?,
                 created_count = ?,
                 updated_count = ?,
                 unchanged_count = ?,
                 error_count = 0,
                 error_summary = NULL,
                 imported_at = NOW()
             WHERE id = ?',
            $Analysis->{TotalCount},
            $Analysis->{CreateCount},
            $Analysis->{UpdateCount},
            $Analysis->{UnchangedCount},
            $RunID,
        ) || die "Import run could not be completed\n";

        $Self->{DB}->Commit() || die "Database transaction could not be committed\n";
        $TransactionStarted = 0;
        1;
    };

    if ( !$Success ) {
        my $Error = $@ || $Self->{DB}->Error() || 'unknown import error';
        $Self->{DB}->Rollback() if $TransactionStarted;

        if ( $Analysis && $AnalysisChanged ) {
            $Self->_RunAnalysisReplace(
                RunID    => $RunID,
                Analysis => $Analysis,
                Status   => 'invalid',
            );
            $Self->{LastError} = 'Translate:MasterDataImportChangedAfterPreview';
        }
        else {
            $Error =~ s{\s+\z}{};
            $Self->{DB}->Do(
                'UPDATE master_data_import_run
                 SET error_summary = ?
                 WHERE id = ?',
                substr( $Error, 0, 4000 ),
                $RunID,
            );
            $Self->{LastError} = 'Translate:MasterDataImportTransactionFailed';
        }
        return;
    }

    my $InvitationCount = 0;
    if (@Invitation) {
        my $PasswordReset = QisutuPasswordReset->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
        for my $Entry (@Invitation) {
            my $Result = $PasswordReset->RequestCreate(
                AccountType => $Entry->{AccountType},
                UserInput   => $Entry->{Login},
            );
            $InvitationCount++ if $Result && $Result->{Success};
        }
    }

    $Self->{DB}->Do(
        'UPDATE master_data_import_run
         SET invitation_count = ?
         WHERE id = ?',
        $InvitationCount,
        $RunID,
    );

    return $Self->RunGet( RunID => $RunID );
}

sub RunCancel {
    my ( $Self, %Param ) = @_;

    my $RunID  = $Self->_ID( $Param{RunID} );
    my $UserID = $Self->_ID( $Param{UserID} );
    return if !$RunID || !$UserID;

    my $Result = $Self->{DB}->Do(
        'UPDATE master_data_import_run
         SET status = "cancelled",
             staged_content = NULL
         WHERE id = ?
           AND created_by_user_id = ?
           AND status = "pending"',
        $RunID,
        $UserID,
    );

    return $Result ? 1 : undef;
}

sub RunGet {
    my ( $Self, %Param ) = @_;
    my $RunID = $Self->_ID( $Param{RunID} );
    return if !$RunID;
    $Self->_ExpiredCleanup();

    return $Self->{DB}->SelectRow(
        'SELECT
            r.id, r.import_type, r.file_name, r.file_sha256, r.status,
            r.total_count, r.created_count, r.updated_count,
            r.unchanged_count, r.error_count, r.invitation_count,
            r.error_summary, r.created_by_user_id, r.created_at,
            r.expires_at, r.imported_at,
            COALESCE(NULLIF(TRIM(CONCAT(ua.firstname, " ", ua.lastname)), ""), ua.login, ua.email) AS created_by_name
         FROM master_data_import_run r
         INNER JOIN user_account ua ON ua.id = r.created_by_user_id
         WHERE r.id = ?
         LIMIT 1',
        $RunID,
    );
}

sub RunList {
    my ( $Self, %Param ) = @_;
    $Self->_ExpiredCleanup();
    my $Limit = $Param{Limit} || 50;
    $Limit = 50 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 200;

    return $Self->{DB}->SelectAll(
        'SELECT
            r.id, r.import_type, r.file_name, r.status,
            r.total_count, r.created_count, r.updated_count,
            r.unchanged_count, r.error_count, r.invitation_count,
            r.created_at, r.expires_at, r.imported_at,
            COALESCE(NULLIF(TRIM(CONCAT(ua.firstname, " ", ua.lastname)), ""), ua.login, ua.email) AS created_by_name
         FROM master_data_import_run r
         INNER JOIN user_account ua ON ua.id = r.created_by_user_id
         ORDER BY r.created_at DESC, r.id DESC
         LIMIT ' . int($Limit)
    ) || [];
}

sub RunItemList {
    my ( $Self, %Param ) = @_;
    my $RunID = $Self->_ID( $Param{RunID} );
    my $OnlyErrors = $Param{OnlyErrors} ? 1 : 0;
    my $Limit = $Param{Limit} || 500;
    $Limit = 500 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 50000;
    return [] if !$RunID;

    my $Where = $OnlyErrors ? 'AND action = "error"' : '';
    return $Self->{DB}->SelectAll(
        'SELECT id, run_id, row_number, record_key, action, message, created_at
         FROM master_data_import_item
         WHERE run_id = ? ' . $Where . '
         ORDER BY row_number ASC, id ASC
         LIMIT ' . int($Limit),
        $RunID,
    ) || [];
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError};
}

sub _Analyze {
    my ( $Self, %Param ) = @_;

    my $Type       = $Self->_TypeClean( $Param{Type} );
    my $Content    = defined $Param{Content} ? $Param{Content} : '';
    my $Language   = $Self->_LanguageClean( $Param{Language} || 'en' );
    my $Definition = $Self->Definition( Type => $Type, Language => $Language ) || return;
    my $Parsed     = $Self->_CSVParse( Content => $Content );

    my @Items;
    if ( !$Parsed || $Parsed->{Error} ) {
        push @Items, {
            RowNumber => 1,
            RecordKey => '',
            Action    => 'error',
            Message   => $Self->_Message( 'MasterDataImportCSVInvalid', $Language ),
        };
        return $Self->_AnalysisResult( Items => \@Items );
    }

    my $Rows = $Parsed->{Rows} || [];
    if ( !@{$Rows} ) {
        push @Items, {
            RowNumber => 1,
            RecordKey => '',
            Action    => 'error',
            Message   => $Self->_Message( 'MasterDataImportCSVEmpty', $Language ),
        };
        return $Self->_AnalysisResult( Items => \@Items );
    }

    my @ActualHeader = @{$Rows->[0] || []};
    $ActualHeader[0] =~ s{\A\x{FEFF}}{} if @ActualHeader;
    my @ExpectedHeader = @{$Definition->{Header}};

    if (
        @ActualHeader != @ExpectedHeader
        || join( "\x1E", @ActualHeader ) ne join( "\x1E", @ExpectedHeader )
        )
    {
        push @Items, {
            RowNumber => 1,
            RecordKey => '',
            Action    => 'error',
            Message   => $Self->_Message(
                'MasterDataImportHeaderMismatch',
                $Language,
                Expected => join( ';', @ExpectedHeader ),
            ),
        };
        return $Self->_AnalysisResult( Items => \@Items );
    }

    my @DataRows = @{$Rows}[ 1 .. $#{$Rows} ];
    if ( !@DataRows ) {
        push @Items, {
            RowNumber => 2,
            RecordKey => '',
            Action    => 'error',
            Message   => $Self->_Message( 'MasterDataImportNoDataRows', $Language ),
        };
        return $Self->_AnalysisResult( Items => \@Items );
    }
    if ( @DataRows > 50000 ) {
        push @Items, {
            RowNumber => 2,
            RecordKey => '',
            Action    => 'error',
            Message   => $Self->_Message( 'MasterDataImportTooManyRows', $Language ),
        };
        return $Self->_AnalysisResult( Items => \@Items );
    }

    my $State = $Self->_StateLoad( Type => $Type, Definition => $Definition );
    return if !$State;
    my %SeenKey;
    my %SeenEmail;

    ROW:
    for my $Index ( 0 .. $#DataRows ) {
        my $RowNumber = $Index + 2;
        my $Values = $DataRows[$Index] || [];
        my %Data;
        my @Error;

        if ( @{$Values} != @ExpectedHeader ) {
            push @Items, {
                RowNumber => $RowNumber,
                RecordKey => '',
                Action    => 'error',
                Message   => $Self->_Message( 'MasterDataImportColumnCount', $Language ),
            };
            next ROW;
        }

        for my $ColumnIndex ( 0 .. $#ExpectedHeader ) {
            $Data{$ExpectedHeader[$ColumnIndex]} = $Self->_Trim( $Values->[$ColumnIndex] );
        }

        my $KeyColumn = $Type eq 'customer' ? 'customer_number' : 'login';
        my $RecordKey = $Data{$KeyColumn} || '';
        my $NormalizedKey = lc $RecordKey;

        if ($NormalizedKey) {
            if ( $SeenKey{$NormalizedKey}++ ) {
                push @Error, $Self->_Message( 'MasterDataImportDuplicateKey', $Language, Value => $RecordKey );
            }
        }

        if ( $Type ne 'customer' && $Data{email} ) {
            my $NormalizedEmail = lc $Data{email};
            if ( $SeenEmail{$NormalizedEmail}++ ) {
                push @Error, $Self->_Message( 'MasterDataImportDuplicateEmail', $Language, Value => $Data{email} );
            }
        }

        for my $Field ( @{$Definition->{Fields}} ) {
            my $Value = $Data{$Field->{Column}};
            if ( $Field->{Required} && ( !defined $Value || $Value eq '' ) ) {
                push @Error, $Self->_Message( 'MasterDataImportRequiredField', $Language, Field => $Field->{Column} );
                next;
            }
            if ( $Field->{MaxLength} && length($Value) > $Field->{MaxLength} ) {
                push @Error, $Self->_Message( 'MasterDataImportFieldTooLong', $Language, Field => $Field->{Column}, Max => $Field->{MaxLength} );
            }
            if ( ( $Field->{FieldType} || '' ) eq 'boolean' && $Value !~ m{\A[01]\z} ) {
                push @Error, $Self->_Message( 'MasterDataImportBooleanInvalid', $Language, Field => $Field->{Column} );
            }
            if ( ( $Field->{FieldType} || '' ) eq 'email' && $Value ne '' && $Value !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} ) {
                push @Error, $Self->_Message( 'MasterDataImportEmailInvalid', $Language, Field => $Field->{Column} );
            }
            if ( ( $Field->{FieldType} || '' ) eq 'number' && $Value ne '' && $Value !~ m{\A-?(?:\d+|\d*[.]\d+)\z} ) {
                push @Error, $Self->_Message( 'MasterDataImportNumberInvalid', $Language, Field => $Field->{Column} );
            }
            if ( ( $Field->{FieldType} || '' ) eq 'date' && $Value ne '' && $Value !~ m{\A\d{4}-\d{2}-\d{2}\z} ) {
                push @Error, $Self->_Message( 'MasterDataImportDateInvalid', $Language, Field => $Field->{Column} );
            }
        }

        my $Existing = $State->{ByKey}->{$NormalizedKey};

        if ( $Type eq 'customer_user' ) {
            my $Customer = $State->{CustomerByNumber}->{ lc( $Data{customer_number} || '' ) };
            if ( !$Customer ) {
                push @Error, $Self->_Message( 'MasterDataImportCustomerUnknown', $Language, Value => $Data{customer_number} );
            }
            elsif ( !$Customer->{active} ) {
                push @Error, $Self->_Message( 'MasterDataImportCustomerInactive', $Language, Value => $Data{customer_number} );
            }
            $Data{_customer_id} = $Customer->{id} if $Customer;
        }

        if ( $Type ne 'customer' && $Data{email} ) {
            my $EmailOwner = $State->{ByEmail}->{ lc $Data{email} };
            if ( $EmailOwner && ( !$Existing || $EmailOwner->{id} != $Existing->{id} ) ) {
                push @Error, $Self->_Message( 'MasterDataImportEmailUsed', $Language, Value => $Data{email} );
            }
        }

        if ( $Type eq 'agent' && $Existing && $Existing->{is_system_user} ) {
            push @Error, $Self->_Message( 'MasterDataImportSystemAgentProtected', $Language );
        }
        if ( $Type eq 'agent' && $Existing && $Existing->{protected_admin} && $Data{active} eq '0' ) {
            push @Error, $Self->_Message( 'MasterDataImportAdminDeactivationProtected', $Language );
        }

        if (@Error) {
            push @Items, {
                RowNumber => $RowNumber,
                RecordKey => $RecordKey,
                Action    => 'error',
                Message   => join( ' ', @Error ),
                Data      => \%Data,
            };
            next ROW;
        }

        my $Action = !$Existing ? 'create' : $Self->_RowChanged(
            Type       => $Type,
            Data       => \%Data,
            Existing   => $Existing,
            Definition => $Definition,
            State      => $State,
        ) ? 'update' : 'unchanged';

        push @Items, {
            RowNumber => $RowNumber,
            RecordKey => $RecordKey,
            Action    => $Action,
            Message   => '',
            Data      => \%Data,
            Existing  => $Existing,
            Definition => $Definition,
        };
    }

    return $Self->_AnalysisResult( Items => \@Items );
}

sub _AnalysisResult {
    my ( $Self, %Param ) = @_;
    my $Items = $Param{Items} || [];
    my %Count = ( create => 0, update => 0, unchanged => 0, error => 0 );
    for my $Item ( @{$Items} ) {
        my $Action = $Item->{Action} || '';
        $Count{$Action}++ if exists $Count{$Action};
    }

    return {
        Items          => $Items,
        TotalCount     => scalar @{$Items},
        CreateCount    => $Count{create},
        UpdateCount    => $Count{update},
        UnchangedCount => $Count{unchanged},
        ErrorCount     => $Count{error},
    };
}

sub _AnalysisSHA {
    my ( $Self, $Analysis ) = @_;
    my @Part;
    for my $Item ( @{$Analysis->{Items} || []} ) {
        my $Existing = ref $Item->{Existing} eq 'HASH' ? $Item->{Existing} : {};
        my $Data = ref $Item->{Data} eq 'HASH' ? $Item->{Data} : {};
        push @Part, join "\x1F",
            $Item->{RowNumber} || 0,
            $Item->{RecordKey} || '',
            $Item->{Action} || '',
            $Item->{Message} || '',
            $Existing->{id} || 0,
            $Existing->{customer_user_id} || 0,
            $Data->{_customer_id} || 0;
    }
    return sha256_hex( encode( 'UTF-8', join( "\x1E", @Part ) ) );
}

sub _StateLoad {
    my ( $Self, %Param ) = @_;
    my $Type       = $Param{Type};
    my $Definition = $Param{Definition};
    my %ByKey;
    my %ByEmail;
    my %CustomerByNumber;

    if ( $Type eq 'customer' ) {
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT id, customer_number, name, active
             FROM customer'
        );
        return $Self->_DataLoadFailed() if !defined $Rows;
        for my $Row (@{$Rows}) {
            $ByKey{ lc( $Row->{customer_number} || '' ) } = $Row;
        }
    }
    elsif ( $Type eq 'customer_user' ) {
        my $Customers = $Self->{DB}->SelectAll(
            'SELECT id, customer_number, name, active FROM customer'
        );
        return $Self->_DataLoadFailed() if !defined $Customers;
        for my $Customer (@{$Customers}) {
            $CustomerByNumber{ lc( $Customer->{customer_number} || '' ) } = $Customer;
        }

        my $Rows = $Self->{DB}->SelectAll(
            'SELECT
                ua.id, ua.login, ua.email, ua.firstname, ua.lastname,
                ua.is_active, ua.is_system_user,
                cu.id AS customer_user_id, cu.customer_id, cu.active AS customer_user_active
             FROM user_account ua
             LEFT JOIN customer_user cu ON cu.user_account_id = ua.id
             WHERE ua.account_type = "customer"'
        );
        return $Self->_DataLoadFailed() if !defined $Rows;
        for my $Row (@{$Rows}) {
            $ByKey{ lc( $Row->{login} || '' ) } = $Row;
            $ByEmail{ lc( $Row->{email} || '' ) } = $Row if $Row->{email};
        }
    }
    else {
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT
                ua.id, ua.login, ua.email, ua.firstname, ua.lastname,
                ua.is_active, ua.is_system_user,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM user_group_member ugm
                    INNER JOIN user_group ug ON ug.id = ugm.user_group_id
                    WHERE ugm.user_account_id = ua.id
                      AND ugm.active = 1
                      AND ug.active = 1
                      AND ug.name = "admin"
                      AND (
                        ugm.permission_read = 1
                        OR ugm.permission_create = 1
                        OR ugm.permission_change = 1
                        OR ugm.permission_overview = 1
                        OR ugm.permission_full = 1
                      )
                ) THEN 1 ELSE 0 END AS protected_admin
             FROM user_account ua
             WHERE ua.account_type = "agent"'
        );
        return $Self->_DataLoadFailed() if !defined $Rows;
        for my $Row (@{$Rows}) {
            $ByKey{ lc( $Row->{login} || '' ) } = $Row;
            $ByEmail{ lc( $Row->{email} || '' ) } = $Row if $Row->{email};
        }
    }

    my %Dynamic;
    my $ObjectType = $Definition->{ObjectType};
    my $Values = $Self->{DB}->SelectAll(
        'SELECT object_id, field_id, value_text
         FROM user_dynamic_field_value
         WHERE object_type = ?',
        $ObjectType,
    );
    return $Self->_DataLoadFailed() if !defined $Values;
    for my $Value (@{$Values}) {
        $Dynamic{ $Value->{object_id} }->{ $Value->{field_id} } = defined $Value->{value_text} ? $Value->{value_text} : '';
    }

    return {
        ByKey            => \%ByKey,
        ByEmail          => \%ByEmail,
        CustomerByNumber => \%CustomerByNumber,
        Dynamic          => \%Dynamic,
    };
}

sub _DataLoadFailed {
    my ($Self) = @_;
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:MasterDataImportDataLoadFailed';
    return;
}

sub _RowChanged {
    my ( $Self, %Param ) = @_;
    my $Type       = $Param{Type};
    my $Data       = $Param{Data};
    my $Existing   = $Param{Existing};
    my $Definition = $Param{Definition};
    my $State      = $Param{State};

    if ( $Type eq 'customer' ) {
        return 1 if ( $Existing->{name} || '' ) ne ( $Data->{name} || '' );
        return 1 if 0 + ( $Existing->{active} || 0 ) != 0 + ( $Data->{active} || 0 );
    }
    elsif ( $Type eq 'customer_user' ) {
        return 1 if 0 + ( $Existing->{customer_id} || 0 ) != 0 + ( $Data->{_customer_id} || 0 );
        return 1 if ( $Existing->{email} || '' ) ne ( $Data->{email} || '' );
        return 1 if ( $Existing->{firstname} || '' ) ne ( $Data->{firstname} || '' );
        return 1 if ( $Existing->{lastname} || '' ) ne ( $Data->{lastname} || '' );
        return 1 if 0 + ( $Existing->{is_active} || 0 ) != 0 + ( $Data->{active} || 0 );
        return 1 if 0 + ( $Existing->{customer_user_active} || 0 ) != 0 + ( $Data->{active} || 0 );
    }
    else {
        return 1 if ( $Existing->{email} || '' ) ne ( $Data->{email} || '' );
        return 1 if ( $Existing->{firstname} || '' ) ne ( $Data->{firstname} || '' );
        return 1 if ( $Existing->{lastname} || '' ) ne ( $Data->{lastname} || '' );
        return 1 if 0 + ( $Existing->{is_active} || 0 ) != 0 + ( $Data->{active} || 0 );
    }

    my $ObjectID = $Type eq 'customer_user' ? ( $Existing->{customer_user_id} || 0 ) : ( $Existing->{id} || 0 );
    for my $Field ( grep { $_->{Dynamic} } @{$Definition->{Fields}} ) {
        my $Current = $State->{Dynamic}->{$ObjectID}->{ $Field->{DynamicID} };
        $Current = '' if !defined $Current;
        return 1 if $Current ne ( $Data->{ $Field->{Column} } || '' );
    }

    return 0;
}

sub _ApplyItem {
    my ( $Self, %Param ) = @_;
    my $Type   = $Param{Type};
    my $Item   = $Param{Item};
    my $Admin  = $Param{Admin};
    my $UserID = $Param{UserID};
    my $Data   = $Item->{Data} || {};
    my $Action = $Item->{Action} || '';
    my $Request = $Self->_DynamicRequest( Item => $Item );

    $Admin->{LastError} = '';
    $Self->{LastError} = '';

    if ( $Type eq 'customer' ) {
        if ( $Action eq 'create' ) {
            $Admin->CustomerCreate(
                CustomerNumber  => $Data->{customer_number},
                Name            => $Data->{name},
                Request         => $Request,
                ChangedByUserID => $UserID,
            ) || return;
            my $Customer = $Self->{DB}->SelectRow(
                'SELECT id FROM customer WHERE customer_number = ? LIMIT 1',
                $Data->{customer_number},
            ) || return;
            if ( $Data->{active} eq '0' ) {
                $Self->{DB}->Do(
                    'UPDATE customer SET active = 0, changed_by_user_id = ? WHERE id = ?',
                    $UserID,
                    $Customer->{id},
                ) || return;
            }
            return 1;
        }

        return $Admin->CustomerUpdate(
            CustomerID      => $Item->{Existing}->{id},
            CustomerNumber  => $Data->{customer_number},
            Name            => $Data->{name},
            Active          => $Data->{active} eq '1' ? 1 : 0,
            Request         => $Request,
            ChangedByUserID => $UserID,
        );
    }

    if ( $Type eq 'customer_user' ) {
        if ( $Action eq 'create' ) {
            $Admin->CustomerUserCreate(
                CustomerID      => $Data->{_customer_id},
                Login           => $Data->{login},
                Email           => $Data->{email},
                Password        => $Self->_RandomPassword(),
                Firstname       => $Data->{firstname},
                Lastname        => $Data->{lastname},
                Request         => $Request,
                ChangedByUserID => $UserID,
            ) || return;
            if ( $Data->{active} eq '0' ) {
                my $Created = $Self->{DB}->SelectRow(
                    'SELECT cu.id, cu.user_account_id
                     FROM customer_user cu
                     INNER JOIN user_account ua ON ua.id = cu.user_account_id
                     WHERE ua.account_type = "customer" AND ua.login = ?
                     LIMIT 1',
                    $Data->{login},
                ) || return;
                $Self->{DB}->Do( 'UPDATE user_account SET is_active = 0 WHERE id = ?', $Created->{user_account_id} ) || return;
                $Self->{DB}->Do( 'UPDATE customer_user SET active = 0, changed_by_user_id = ? WHERE id = ?', $UserID, $Created->{id} ) || return;
            }
            return 1;
        }

        return $Admin->CustomerUserUpdate(
            CustomerUserID  => $Item->{Existing}->{customer_user_id},
            CustomerID      => $Data->{_customer_id},
            Login           => $Data->{login},
            Email           => $Data->{email},
            Password        => '',
            Firstname       => $Data->{firstname},
            Lastname        => $Data->{lastname},
            Active          => $Data->{active} eq '1' ? 1 : 0,
            Request         => $Request,
            ChangedByUserID => $UserID,
        );
    }

    if ( $Action eq 'create' ) {
        $Admin->AgentCreate(
            Login           => $Data->{login},
            Email           => $Data->{email},
            Password        => $Self->_RandomPassword(),
            Firstname       => $Data->{firstname},
            Lastname        => $Data->{lastname},
            Request         => $Request,
            ChangedByUserID => $UserID,
        ) || return;
        return if $Admin->Error();
        if ( $Data->{active} eq '0' ) {
            $Self->{DB}->Do(
                'UPDATE user_account
                 SET is_active = 0
                 WHERE account_type = "agent" AND login = ?',
                $Data->{login},
            ) || return;
        }
        return 1;
    }

    my $Updated = $Admin->AgentUpdate(
        UserAccountID   => $Item->{Existing}->{id},
        Login           => $Data->{login},
        Email           => $Data->{email},
        Password        => '',
        Firstname       => $Data->{firstname},
        Lastname        => $Data->{lastname},
        IsActive        => $Data->{active} eq '1' ? 1 : 0,
        Request         => $Request,
        ChangedByUserID => $UserID,
    );
    return if !$Updated || $Admin->Error();
    return 1;
}

sub _DynamicRequest {
    my ( $Self, %Param ) = @_;
    my $Item = $Param{Item} || {};
    my $Data = $Item->{Data} || {};
    my $Definition = $Item->{Definition} || {};
    my %Request;
    for my $Field ( grep { $_->{Dynamic} } @{$Definition->{Fields} || []} ) {
        $Request{ 'DynamicField_' . $Field->{DynamicID} } = $Data->{ $Field->{Column} } || '';
    }
    return \%Request;
}

sub _RunAnalysisReplace {
    my ( $Self, %Param ) = @_;
    my $RunID    = $Param{RunID};
    my $Analysis = $Param{Analysis};
    my $Status   = $Param{Status} || 'invalid';

    $Self->{DB}->Do( 'DELETE FROM master_data_import_item WHERE run_id = ?', $RunID );
    $Self->_ItemsStore( RunID => $RunID, Items => $Analysis->{Items} );
    $Self->{DB}->Do(
        'UPDATE master_data_import_run
         SET status = ?, staged_content = NULL, analysis_sha256 = ?,
             total_count = ?, created_count = ?, updated_count = ?,
             unchanged_count = ?, error_count = ?
         WHERE id = ?',
        $Status,
        $Self->_AnalysisSHA($Analysis),
        $Analysis->{TotalCount},
        $Analysis->{CreateCount},
        $Analysis->{UpdateCount},
        $Analysis->{UnchangedCount},
        $Analysis->{ErrorCount},
        $RunID,
    );
    return 1;
}

sub _ItemsStore {
    my ( $Self, %Param ) = @_;
    my $RunID = $Param{RunID};
    for my $Item ( @{$Param{Items} || []} ) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO master_data_import_item (
                run_id, row_number, record_key, action, message, created_at
             ) VALUES (?, ?, ?, ?, ?, NOW())',
            $RunID,
            $Item->{RowNumber} || 0,
            substr( $Item->{RecordKey} || '', 0, 255 ),
            $Item->{Action} || 'error',
            $Item->{Message} || '',
        );
        return if !$Result;
    }
    return 1;
}

sub _CSVParse {
    my ( $Self, %Param ) = @_;
    my $Text = defined $Param{Content} ? $Param{Content} : '';
    my @Rows;
    my @Row;
    my $Field = '';
    my $Quoted = 0;
    my @Chars = split //, $Text;

    for ( my $Index = 0; $Index < @Chars; $Index++ ) {
        my $Char = $Chars[$Index];
        if ($Quoted) {
            if ( $Char eq '"' ) {
                if ( ( $Chars[ $Index + 1 ] || '' ) eq '"' ) {
                    $Field .= '"';
                    $Index++;
                }
                else {
                    $Quoted = 0;
                }
            }
            else {
                $Field .= $Char;
            }
            next;
        }

        if ( $Char eq '"' && $Field eq '' ) {
            $Quoted = 1;
            next;
        }
        if ( $Char eq ';' ) {
            push @Row, $Field;
            $Field = '';
            next;
        }
        if ( $Char eq "\n" ) {
            push @Row, $Field;
            $Field = '';
            push @Rows, [@Row] if grep { defined $_ && $_ ne '' } @Row;
            @Row = ();
            next;
        }
        next if $Char eq "\r";
        $Field .= $Char;
    }

    return { Error => 'quote' } if $Quoted;
    push @Row, $Field if $Field ne '' || @Row;
    push @Rows, [@Row] if @Row && grep { defined $_ && $_ ne '' } @Row;
    return { Rows => \@Rows };
}

sub _ExpiredCleanup {
    my ($Self) = @_;
    $Self->{DB}->Do(
        'UPDATE master_data_import_run
         SET status = "expired",
             staged_content = NULL
         WHERE status = "pending" AND expires_at < NOW()'
    );
    return 1;
}

sub _RandomPassword {
    my ($Self) = @_;
    my $Bytes = '';
    if ( open my $Handle, '<', '/dev/urandom' ) {
        binmode $Handle;
        read $Handle, $Bytes, 48;
        close $Handle;
    }
    $Bytes .= time() . $$ . rand() . {} while length($Bytes) < 48;
    return sha256_hex($Bytes) . sha256_hex( reverse $Bytes );
}

sub _Message {
    my ( $Self, $Key, $Language, %Value ) = @_;
    my $Text = $Self->{Output}
        ? $Self->{Output}->Translate( Key => $Key, Language => $Language )
        : $Key;
    for my $Name ( keys %Value ) {
        my $Replacement = defined $Value{$Name} ? $Value{$Name} : '';
        $Text =~ s{\{\Q$Name\E\}}{$Replacement}g;
    }
    return $Text;
}

sub _CSVField {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{"}{""}g;
    return '"' . $Value . '"';
}

sub _ObjectType {
    my ( $Self, $Type ) = @_;
    return 'customer'      if $Type eq 'customer';
    return 'customer_user' if $Type eq 'customer_user';
    return 'agent';
}

sub _TypeClean {
    my ( $Self, $Type ) = @_;
    $Type ||= '';
    return $Type if $Type =~ m{\A(?:customer|customer_user|agent)\z};
    return '';
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;
    $Language ||= 'en';
    $Language =~ s{[^A-Za-z0-9_-]}{}g;
    return $Language || 'en';
}

sub _FileNameClean {
    my ( $Self, $FileName ) = @_;
    $FileName ||= 'import.csv';
    $FileName =~ s{\\}{/}g;
    $FileName =~ s{\A.*/}{}g;
    $FileName =~ s{[\r\n\x00"]}{}g;
    $FileName = substr( $FileName, 0, 255 );
    return $FileName || 'import.csv';
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return defined $Value && $Value =~ m{\A\d+\z} && $Value > 0 ? int($Value) : 0;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};
    return $Value;
}

1;
