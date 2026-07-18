# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminCSVImports;

use strict;
use warnings;
use utf8;

use Encode qw(decode FB_CROAK);
use QisutuMasterDataImport;

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
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Type     = $Self->_Type( $Request->{ImportType} );
    my $Action   = $Request->{Action} || '';
    my $Step     = $Request->{Step} || '';
    my $RunID    = $Self->_ID( $Request->{RunID} );
    my $UserID   = $Self->_ID( $User->{user_account_id} );
    my $Object   = QisutuMasterDataImport->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );
    my $Error = '';

    if ( $Action eq 'Template' ) {
        my $Body = $Object->TemplateCSV( Type => $Type, Language => $Language );
        return { Response => $Self->_CSVResponse( Body => $Body, Filename => $Self->_TemplateFilename($Type) ) } if defined $Body;
        $Error = $Object->Error() || 'Translate:MasterDataImportTemplateFailed';
    }
    elsif ( $Action eq 'ErrorCSV' && $RunID ) {
        my $Run = $Object->RunGet( RunID => $RunID );
        if ($Run) {
            my $Items = $Object->RunItemList( RunID => $RunID, OnlyErrors => 1, Limit => 50000 );
            return { Response => $Self->_ErrorCSVResponse( Items => $Items, RunID => $RunID, Language => $Language ) };
        }
        $Error = 'Translate:MasterDataImportRunInvalid';
    }
    elsif ( $Step eq 'Preview' ) {
        my $Upload = $Self->_Upload($Request);
        if ( !$Upload ) {
            $Error = 'Translate:MasterDataImportFileInvalid';
        }
        else {
            my $Raw  = defined $Upload->{Content} ? $Upload->{Content} : '';
            my $Size = $Upload->{ContentSize} || length($Raw);
            if ( !$Size || $Size > 10 * 1024 * 1024 ) {
                $Error = $Size ? 'Translate:MasterDataImportFileTooLarge' : 'Translate:MasterDataImportFileInvalid';
            }
            else {
                my $Content = eval { decode( 'UTF-8', $Raw, FB_CROAK ) };
                if ($@) {
                    $Error = 'Translate:MasterDataImportUTF8Required';
                }
                else {
                    my $Run = $Object->PreviewCreate(
                        Type     => $Type,
                        Content  => $Content,
                        FileName => $Upload->{Filename} || 'import.csv',
                        UserID   => $UserID,
                        Language => $Language,
                    );
                    return { Redirect => 'index.pl?Page=AdminCSVImports;ImportType=' . $Type . ';RunID=' . $Run->{id} . ';Notice=preview' } if $Run;
                    $Error = $Object->Error() || 'Translate:MasterDataImportPreviewFailed';
                }
            }
        }
    }
    elsif ( $Step eq 'Import' && $RunID ) {
        my $Run = $Object->ImportRun(
            RunID           => $RunID,
            UserID          => $UserID,
            Language        => $Language,
            SendInvitations => $Request->{SendInvitations},
        );
        return { Redirect => 'index.pl?Page=AdminCSVImports;ImportType=' . $Type . ';RunID=' . $RunID . ';Notice=imported' } if $Run;
        $Error = $Object->Error() || 'Translate:MasterDataImportTransactionFailed';
    }
    elsif ( $Step eq 'Cancel' && $RunID ) {
        if ( $Object->RunCancel( RunID => $RunID, UserID => $UserID ) ) {
            return { Redirect => 'index.pl?Page=AdminCSVImports;ImportType=' . $Type . ';RunID=' . $RunID . ';Notice=cancelled' };
        }
        $Error = 'Translate:MasterDataImportRunInvalid';
    }

    my $Definition = $Object->Definition( Type => $Type, Language => $Language );
    if ( !$Definition ) {
        $Error ||= $Object->Error() || 'Translate:MasterDataImportDataLoadFailed';
        $Definition = { Fields => [], Header => [] };
    }
    for my $Field ( @{$Definition->{Fields} || []} ) {
        my $Description = $Self->_T( $Field->{DescriptionKey}, $Language );
        $Description .= ': ' . $Field->{Label} if $Field->{Dynamic} && $Field->{Label};
        $Field->{description} = $Description;
        $Field->{required_label} = $Self->_T( $Field->{Required} ? 'MasterDataImportYes' : 'MasterDataImportNo', $Language );
        $Field->{example_display} = $Field->{Example} || '-';
    }

    my $Run = $RunID ? $Object->RunGet( RunID => $RunID ) : undef;
    my $Items = $Run ? $Object->RunItemList( RunID => $RunID, Limit => 500 ) : [];
    $Self->_RunsPrepare( Rows => $Items, Language => $Language, ItemMode => 1 );
    my $Runs = $Object->RunList( Limit => 50 );
    $Self->_RunsPrepare( Rows => $Runs, Language => $Language );
    $Self->_RunPrepare( Run => $Run, Language => $Language ) if $Run;

    my $Notice = '';
    $Notice = 'Translate:MasterDataImportPreviewReady' if ( $Request->{Notice} || '' ) eq 'preview';
    $Notice = 'Translate:MasterDataImportCompleted' if ( $Request->{Notice} || '' ) eq 'imported';
    $Notice = 'Translate:MasterDataImportCancelled' if ( $Request->{Notice} || '' ) eq 'cancelled';

    my @Tabs;
    for my $TabType (qw(customer customer_user agent)) {
        push @Tabs, {
            type       => $TabType,
            label      => $Self->_T( $Self->_TypeLabelKey($TabType), $Language ),
            url        => 'index.pl?Page=AdminCSVImports;ImportType=' . $TabType,
            active_class => $TabType eq $Type ? 'qisutu-master-import-tab-active' : '',
        };
    }

    return {
        Template => 'AdminCSVImports.tt',
        Data => {
            PageTitle          => 'Translate:AdminCSVImportsTitle',
            ProgramTitle       => 'Translate:AdminCSVImportsTitle',
            ProgramDescription => 'Translate:AdminCSVImportsDescription',
            FormAction         => 'index.pl',
            ImportType         => $Type,
            ImportTypeLabel    => $Self->_T( $Self->_TypeLabelKey($Type), $Language ),
            Tabs               => \@Tabs,
            DefinitionFields   => $Definition->{Fields},
            HeaderLine         => join( ';', @{$Definition->{Header} || []} ),
            TemplateURL        => 'index.pl?Page=AdminCSVImports;Action=Template;ImportType=' . $Type,
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            NoticeMessage      => $Notice,
            NoticeClass        => $Notice ? 'qisutu-form-success' : 'qisutu-hidden',
            CurrentRun         => $Run,
            HasCurrentRun      => $Run ? 1 : 0,
            CurrentRunID       => $Run ? $Run->{id} : '',
            CurrentRunFileName => $Run ? $Run->{file_name} : '',
            CurrentRunCreatedAt => $Run ? $Run->{created_at} : '',
            CurrentRunCreatedBy => $Run ? $Run->{created_by_name} : '',
            CurrentRunStatusClass => $Run ? $Run->{status_class} : '',
            CurrentRunStatusLabel => $Run ? $Run->{status_label} : '',
            CurrentRunTotalCount => $Run ? 0 + ( $Run->{total_count} || 0 ) : 0,
            CurrentRunCreatedCount => $Run ? 0 + ( $Run->{created_count} || 0 ) : 0,
            CurrentRunUpdatedCount => $Run ? 0 + ( $Run->{updated_count} || 0 ) : 0,
            CurrentRunUnchangedCount => $Run ? 0 + ( $Run->{unchanged_count} || 0 ) : 0,
            CurrentRunErrorCount => $Run ? 0 + ( $Run->{error_count} || 0 ) : 0,
            CurrentRunErrorSummary => $Run ? $Run->{error_summary_display} : '',
            HasCurrentErrorSummary => $Run && $Run->{error_summary_display} ? 1 : 0,
            CurrentItems       => $Items,
            HasCurrentItems    => @{$Items} ? 1 : 0,
            CurrentItemsLimited => $Run && ( $Run->{total_count} || 0 ) > 500 ? 1 : 0,
            CanImportCurrent   => $Run && ( $Run->{status} || '' ) eq 'pending' && ( $Run->{created_by_user_id} || 0 ) == $UserID ? 1 : 0,
            ShowInvitationOption => $Type ne 'customer' ? 1 : 0,
            HasCurrentErrors   => $Run && ( $Run->{error_count} || 0 ) > 0 ? 1 : 0,
            ErrorCSVURL        => $Run ? 'index.pl?Page=AdminCSVImports;Action=ErrorCSV;RunID=' . $Run->{id} . ';ImportType=' . $Type : '',
            RunList            => $Runs,
            HasRuns            => @{$Runs} ? 1 : 0,
        },
    };
}

sub _RunsPrepare {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    for my $Row ( @{$Param{Rows} || []} ) {
        if ( $Param{ItemMode} ) {
            $Row->{action_label} = $Self->_T( 'MasterDataImportAction_' . ( $Row->{action} || 'error' ), $Language );
            $Row->{action_class} = 'qisutu-master-import-action-' . ( $Row->{action} || 'error' );
            $Row->{message_display} = $Row->{message} || '-';
        }
        else {
            $Self->_RunPrepare( Run => $Row, Language => $Language );
            $Row->{type_label} = $Self->_T( $Self->_TypeLabelKey( $Row->{import_type} ), $Language );
            $Row->{url} = 'index.pl?Page=AdminCSVImports;ImportType=' . ( $Row->{import_type} || 'customer' ) . ';RunID=' . ( $Row->{id} || 0 );
        }
    }
    return;
}

sub _RunPrepare {
    my ( $Self, %Param ) = @_;
    my $Run = $Param{Run} || return;
    my $Language = $Param{Language} || 'en';
    $Run->{status_label} = $Self->_T( 'MasterDataImportStatus_' . ( $Run->{status} || 'invalid' ), $Language );
    $Run->{status_class} = 'qisutu-master-import-status-' . ( $Run->{status} || 'invalid' );
    $Run->{error_summary_display} = $Run->{error_summary} || '';
    return;
}

sub _CSVResponse {
    my ( $Self, %Param ) = @_;
    return $Self->{Output}->Response(
        Body        => defined $Param{Body} ? $Param{Body} : '',
        ContentType => 'text/csv; charset=UTF-8',
        Headers     => [
            'Content-Disposition: attachment; filename="' . ( $Param{Filename} || 'qisutu-import.csv' ) . '"',
            'Cache-Control: no-store',
        ],
    );
}

sub _ErrorCSVResponse {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my @Lines = ( join ';', map { $Self->_CSVField($_) } (
        $Self->_T( 'MasterDataImportRow', $Language ),
        $Self->_T( 'MasterDataImportRecordKey', $Language ),
        $Self->_T( 'MasterDataImportMessage', $Language ),
    ) );
    for my $Item ( @{$Param{Items} || []} ) {
        push @Lines, join ';', map { $Self->_CSVField($_) } (
            $Item->{row_number}, $Item->{record_key}, $Item->{message},
        );
    }
    return $Self->_CSVResponse(
        Body     => chr(0xFEFF) . join( "\r\n", @Lines ) . "\r\n",
        Filename => 'qisutu-import-errors-' . ( $Param{RunID} || 0 ) . '.csv',
    );
}

sub _CSVField {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value = "'" . $Value if $Value =~ m{\A[\t\r ]*[=+\-\@]};
    $Value =~ s{"}{""}g;
    return '"' . $Value . '"';
}

sub _Upload {
    my ( $Self, $Request ) = @_;
    my $Uploads = $Request->{__Uploads} || {};
    my $List = $Uploads->{MasterDataCSV};
    return ref $List eq 'ARRAY' ? $List->[0] : undef;
}

sub _TemplateFilename {
    my ( $Self, $Type ) = @_;
    return 'qisutu-kunden.csv' if $Type eq 'customer';
    return 'qisutu-ansprechpartner.csv' if $Type eq 'customer_user';
    return 'qisutu-agenten.csv';
}

sub _TypeLabelKey {
    my ( $Self, $Type ) = @_;
    return 'MasterDataImportCustomers' if ( $Type || '' ) eq 'customer';
    return 'MasterDataImportCustomerUsers' if ( $Type || '' ) eq 'customer_user';
    return 'MasterDataImportAgents';
}

sub _Type {
    my ( $Self, $Type ) = @_;
    return $Type if ( $Type || '' ) =~ m{\A(?:customer|customer_user|agent)\z};
    return 'customer';
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return defined $Value && $Value =~ m{\A\d+\z} && $Value > 0 ? int($Value) : 0;
}

sub _T {
    my ( $Self, $Key, $Language ) = @_;
    return $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' );
}

1;
