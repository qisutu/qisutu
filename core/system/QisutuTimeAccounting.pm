# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuTimeAccounting;

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);
use QisutuPermission;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        Permission => $Param{Permission},
        LastError => '',
        ActivityTypeListCache => {},
        DefaultBillableCache  => undef,
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub InputParse {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $Request = $Param{Request} || {};
    my $Prefix  = $Param{NamePrefix} || '';
    my $Hours   = defined $Request->{ $Prefix . 'TimeAccountingHours' } ? $Request->{ $Prefix . 'TimeAccountingHours' } : '';
    my $Minutes = defined $Request->{ $Prefix . 'TimeAccountingMinutes' } ? $Request->{ $Prefix . 'TimeAccountingMinutes' } : '';
    my $ActivityTypeID = $Request->{ $Prefix . 'TimeAccountingActivityTypeID' } || 0;

    for ($Hours, $Minutes) {
        $_ = '' if !defined $_;
        s{\A\s+|\s+\z}{}g;
    }

    $Hours   = 0 if $Hours eq '';
    $Minutes = 0 if $Minutes eq '';

    if ( $Hours !~ m{\A\d+\z} || $Minutes !~ m{\A\d+\z} || $Hours > 9999 || $Minutes > 59 ) {
        $Self->{LastError} = 'Translate:TimeAccountingInvalidDuration';
        return;
    }

    if ( $ActivityTypeID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Translate:TimeAccountingInvalidActivityType';
        return;
    }

    if ($ActivityTypeID) {
        my $Activity = $Self->ActivityTypeGet( ActivityTypeID => $ActivityTypeID );
        if ( !$Activity || !$Activity->{active} ) {
            $Self->{LastError} = 'Translate:TimeAccountingInvalidActivityType';
            return;
        }
    }

    return {
        DurationMinutes => ( $Hours * 60 ) + $Minutes,
        ActivityTypeID  => $ActivityTypeID || undef,
        Billable        => $Request->{ $Prefix . 'TimeAccountingBillable' } ? 1 : 0,
        Hours           => 0 + $Hours,
        Minutes         => 0 + $Minutes,
    };
}

sub EntryCreate {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $TicketID       = $Param{TicketID} || 0;
    my $AgentUserID    = $Param{AgentUserID} || 0;
    my $Duration       = $Param{DurationMinutes} || 0;
    my $ArticleID      = $Param{TicketArticleID} || undef;
    my $ActivityTypeID = $Param{ActivityTypeID} || undef;
    my $CreatedBy      = $Param{CreatedByUserID} || $AgentUserID;
    my $Description    = $Param{Description} || '';
    my $Source         = $Param{Source} || 'manual';
    my $WorkDate       = $Param{WorkDate} || strftime( '%Y-%m-%d', localtime );
    my $ExternalTransaction = $Param{TransactionActive} ? 1 : 0;

    return 1 if !$Duration;

    if (
        $TicketID !~ m{\A\d+\z} || !$TicketID
        || $AgentUserID !~ m{\A\d+\z} || !$AgentUserID
        || $CreatedBy !~ m{\A\d+\z} || !$CreatedBy
        || $Duration !~ m{\A\d+\z} || !$Duration
        || $WorkDate !~ m{\A\d{4}-\d{2}-\d{2}\z}
    ) {
        $Self->{LastError} = 'Translate:TimeAccountingCreateFailed';
        return;
    }

    if ($ActivityTypeID) {
        my $Activity = $Self->ActivityTypeGet( ActivityTypeID => $ActivityTypeID );
        if ( !$Activity || !$Activity->{active} ) {
            $Self->{LastError} = 'Translate:TimeAccountingInvalidActivityType';
            return;
        }
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, customer_id, customer_user_id FROM ticket WHERE id = ? LIMIT 1',
        $TicketID,
    );
    my $Agent = $Self->{DB}->SelectRow(
        'SELECT id FROM user_account WHERE id = ? AND account_type = ?'
            . ( $Param{AllowInactiveAgent} ? '' : ' AND is_active = 1' )
            . ' LIMIT 1',
        $AgentUserID, 'agent',
    );
    if ( !$Ticket || !$Agent ) {
        $Self->{LastError} = 'Translate:TimeAccountingCreateFailed';
        return;
    }

    if ( !$ExternalTransaction && !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = 'Translate:TimeAccountingCreateFailed';
        return;
    }

    my $OK = $Self->{DB}->Do(
        'INSERT INTO ticket_time_accounting (
            ticket_id, ticket_article_id, agent_user_id, activity_type_id,
            correction_of_time_accounting_id, work_date, duration_minutes,
            is_billable, source, description, queue_id_snapshot,
            customer_id_snapshot, customer_user_id_snapshot,
            created_by_user_id, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
        $TicketID,
        $ArticleID,
        $AgentUserID,
        $ActivityTypeID,
        $Param{CorrectionOfTimeAccountingID} || undef,
        $WorkDate,
        $Duration,
        $Param{Billable} ? 1 : 0,
        substr( $Source, 0, 50 ),
        $Description || undef,
        $Ticket->{queue_id},
        $Ticket->{customer_id},
        $Ticket->{customer_user_id},
        $CreatedBy,
    );

    if (!$OK) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TimeAccountingCreateFailed';
        $Self->{DB}->Rollback() if !$ExternalTransaction;
        return;
    }

    my $ID = $Self->{DB}->LastInsertID('ticket_time_accounting');
    if ( !$ID || ( !$ExternalTransaction && !$Self->{DB}->Commit() ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TimeAccountingCreateFailed';
        $Self->{DB}->Rollback() if !$ExternalTransaction;
        return;
    }

    return $ID;
}

sub EntryCorrect {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $ID       = $Param{TimeAccountingID} || 0;
    my $UserID   = $Param{UserID} || 0;
    my $Reason   = $Param{Reason} || '';
    my $Input    = $Param{Input} || {};
    my $ReplacementDescription = defined $Param{Description} ? $Param{Description} : undef;
    $Reason =~ s{\A\s+|\s+\z}{}g;
    $ReplacementDescription =~ s{\A\s+|\s+\z}{}g if defined $ReplacementDescription;

    if ( !$Self->CorrectionAllowed( UserID => $UserID ) ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionDenied';
        return;
    }
    if ( !$Reason ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionReasonRequired';
        return;
    }
    if ( !$Input->{DurationMinutes} ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionDurationRequired';
        return;
    }

    my $Original = $Self->{DB}->SelectRow(
        'SELECT ta.*
         FROM ticket_time_accounting ta
         LEFT JOIN ticket_time_accounting_cancellation tc ON tc.time_accounting_id = ta.id
         WHERE ta.id = ? AND tc.id IS NULL
         LIMIT 1',
        $ID,
    );
    if (!$Original) {
        $Self->{LastError} = 'Translate:TimeAccountingAlreadyCancelled';
        return;
    }

    my $Permission = $Self->{Permission} || QisutuPermission->new( Config => $Self->{Config}, DB => $Self->{DB} );
    if ( ( $Original->{agent_user_id} || 0 ) != $UserID && !$Permission->UserIsAdmin( UserID => $UserID ) ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionDenied';
        return;
    }

    if ( $Param{TicketID} && ( $Original->{ticket_id} || 0 ) != $Param{TicketID} ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionFailed';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = 'Translate:TimeAccountingCorrectionFailed';
        return;
    }

    my $ReplacementID = $Self->EntryCreate(
        TicketID                    => $Original->{ticket_id},
        TicketArticleID             => $Original->{ticket_article_id},
        AgentUserID                 => $Original->{agent_user_id},
        ActivityTypeID              => $Input->{ActivityTypeID},
        DurationMinutes             => $Input->{DurationMinutes},
        Billable                    => $Input->{Billable},
        Description                 => defined $ReplacementDescription ? $ReplacementDescription : $Original->{description},
        Source                      => 'correction',
        WorkDate                    => $Original->{work_date},
        CorrectionOfTimeAccountingID => $Original->{id},
        CreatedByUserID             => $UserID,
        TransactionActive           => 1,
        AllowInactiveAgent          => 1,
    );
    if (!$ReplacementID) {
        $Self->{DB}->Rollback();
        $Self->{LastError} ||= 'Translate:TimeAccountingCorrectionFailed';
        return;
    }

    my $OK = $Self->{DB}->Do(
        'INSERT INTO ticket_time_accounting_cancellation (
            time_accounting_id, replacement_time_accounting_id, reason,
            cancelled_by_user_id, cancelled_at
         ) VALUES (?, ?, ?, ?, NOW())',
        $Original->{id}, $ReplacementID, $Reason, $UserID,
    );
    if ( !$OK || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TimeAccountingCorrectionFailed';
        return;
    }

    return $ReplacementID;
}

sub CorrectionAllowed {
    my ( $Self, %Param ) = @_;
    my $Permission = $Self->{Permission} || QisutuPermission->new( Config => $Self->{Config}, DB => $Self->{DB} );
    return $Permission->UserPermissionCheck(
        UserID     => $Param{UserID},
        Permission => 'time_accounting.correct',
    ) ? 1 : 0;
}

sub TicketEntryList {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID} || 0;
    return [] if $TicketID !~ m{\A\d+\z} || !$TicketID;

    return $Self->{DB}->SelectAll(
        'SELECT ta.*, at.name AS activity_type_name,
                ua.login, ua.firstname, ua.lastname,
                tc.id AS cancellation_id, tc.reason AS cancellation_reason,
                tc.cancelled_at, tc.cancelled_by_user_id,
                tc.replacement_time_accounting_id,
                cua.login AS cancelled_by_login,
                cua.firstname AS cancelled_by_firstname,
                cua.lastname AS cancelled_by_lastname
         FROM ticket_time_accounting ta
         LEFT JOIN time_accounting_activity_type at ON at.id = ta.activity_type_id
         INNER JOIN user_account ua ON ua.id = ta.agent_user_id
         LEFT JOIN ticket_time_accounting_cancellation tc ON tc.time_accounting_id = ta.id
         LEFT JOIN user_account cua ON cua.id = tc.cancelled_by_user_id
         WHERE ta.ticket_id = ?
         ORDER BY ta.created_at ASC, ta.id ASC',
        $TicketID,
    ) || [];
}

sub ActivityTypeList {
    my ( $Self, %Param ) = @_;
    my $CacheKey = $Param{ActiveOnly} ? 'active' : 'all';
    return $Self->{ActivityTypeListCache}->{$CacheKey}
        if exists $Self->{ActivityTypeListCache}->{$CacheKey};
    my $Where = $Param{ActiveOnly} ? 'WHERE active = 1' : '';
    my $List = $Self->{DB}->SelectAll(
        'SELECT * FROM time_accounting_activity_type ' . $Where . ' ORDER BY sort_order ASC, name ASC, id ASC'
    ) || [];
    $Self->{ActivityTypeListCache}->{$CacheKey} = $List;
    return $List;
}

sub ActivityTypeGet {
    my ( $Self, %Param ) = @_;
    my $ID = $Param{ActivityTypeID} || 0;
    return if $ID !~ m{\A\d+\z} || !$ID;
    return $Self->{DB}->SelectRow(
        'SELECT * FROM time_accounting_activity_type WHERE id = ? LIMIT 1', $ID,
    );
}

sub ActivityTypeCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_ActivityTypeSave(%Param);
}

sub ActivityTypeUpdate {
    my ( $Self, %Param ) = @_;
    return $Self->_ActivityTypeSave(%Param, Update => 1);
}

sub _ActivityTypeSave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Name = $Param{Name} || '';
    my $ID = $Param{ActivityTypeID} || 0;
    $Name =~ s{\A\s+|\s+\z}{}g;
    if ( !$Name || length($Name) > 255 || ( $Param{Update} && ( $ID !~ m{\A\d+\z} || !$ID ) ) ) {
        $Self->{LastError} = 'Translate:AdminTimeAccountingActivityTypeInvalid';
        return;
    }
    if ( $Param{Update} && !$Self->ActivityTypeGet( ActivityTypeID => $ID ) ) {
        $Self->{LastError} = 'Translate:AdminTimeAccountingActivityTypeInvalid';
        return;
    }
    my $SortOrder = $Param{SortOrder} || 1000;
    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z} || !$SortOrder;
    my $UserID = $Param{ChangedByUserID} || 1;
    my $Active = $Param{Update} ? ( $Param{Active} || $Param{Default} ? 1 : 0 ) : 1;

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = 'Translate:AdminTimeAccountingActivityTypeSaveFailed';
        return;
    }
    if ( $Param{Default} ) {
        if ( !$Self->{DB}->Do('UPDATE time_accounting_activity_type SET is_default = 0, changed_by_user_id = ?, changed_at = NOW() WHERE is_default = 1', $UserID) ) {
            $Self->{DB}->Rollback();
            $Self->{LastError} = 'Translate:AdminTimeAccountingActivityTypeSaveFailed';
            return;
        }
    }

    my $OK;
    if ( $Param{Update} ) {
        $OK = $Self->{DB}->Do(
            'UPDATE time_accounting_activity_type SET name = ?, active = ?, is_default = ?, sort_order = ?, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $Name, $Active, $Param{Default} ? 1 : 0, $SortOrder, $UserID, $ID,
        );
    }
    else {
        $OK = $Self->{DB}->Do(
            'INSERT INTO time_accounting_activity_type (name, active, is_default, sort_order, created_by_user_id, changed_by_user_id, created_at, changed_at) VALUES (?, 1, ?, ?, ?, ?, NOW(), NOW())',
            $Name, $Param{Default} ? 1 : 0, $SortOrder, $UserID, $UserID,
        );
    }
    if ( !$OK || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTimeAccountingActivityTypeSaveFailed';
        return;
    }
    $Self->{ActivityTypeListCache} = {};
    return $Param{Update} ? $ID : $Self->{DB}->LastInsertID('time_accounting_activity_type');
}

sub FormHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $Request  = $Param{Request} || {};
    my $Prefix   = $Param{NamePrefix} || '';
    my $IDPrefix = $Param{IDPrefix} || 'qisutu-time-accounting';
    my $Hours    = $Request->{ $Prefix . 'TimeAccountingHours' } || '';
    my $Minutes  = $Request->{ $Prefix . 'TimeAccountingMinutes' } || '';
    my $Selected = $Request->{ $Prefix . 'TimeAccountingActivityTypeID' } || 0;
    my $HasRequest = scalar keys %{$Request} ? 1 : 0;
    my $HasSelected = exists $Request->{ $Prefix . 'TimeAccountingActivityTypeID' } ? 1 : 0;
    my $Billable = exists $Request->{ $Prefix . 'TimeAccountingBillable' }
        ? ( $Request->{ $Prefix . 'TimeAccountingBillable' } ? 1 : 0 )
        : ( $HasRequest ? 0 : $Self->_DefaultBillable() );

    my $HTML = '<fieldset class="qisutu-time-accounting-fields"><legend>' . $Self->_E( $Self->_T('TimeAccountingTitle', $Language) ) . '</legend>';
    $HTML .= '<div class="qisutu-time-accounting-grid">';
    $HTML .= '<div class="qisutu-form-field"><label for="' . $Self->_E($IDPrefix . '-hours') . '">' . $Self->_E( $Self->_T('TimeAccountingHours', $Language) ) . '</label>';
    $HTML .= '<input id="' . $Self->_E($IDPrefix . '-hours') . '" type="number" min="0" max="9999" name="' . $Self->_E($Prefix . 'TimeAccountingHours') . '" value="' . $Self->_E($Hours) . '"></div>';
    $HTML .= '<div class="qisutu-form-field"><label for="' . $Self->_E($IDPrefix . '-minutes') . '">' . $Self->_E( $Self->_T('TimeAccountingMinutes', $Language) ) . '</label>';
    $HTML .= '<input id="' . $Self->_E($IDPrefix . '-minutes') . '" type="number" min="0" max="59" name="' . $Self->_E($Prefix . 'TimeAccountingMinutes') . '" value="' . $Self->_E($Minutes) . '"></div>';
    $HTML .= '<div class="qisutu-form-field"><label for="' . $Self->_E($IDPrefix . '-activity') . '">' . $Self->_E( $Self->_T('TimeAccountingActivityType', $Language) ) . '</label>';
    $HTML .= '<select id="' . $Self->_E($IDPrefix . '-activity') . '" name="' . $Self->_E($Prefix . 'TimeAccountingActivityTypeID') . '"><option value="0"' . ( $HasSelected && !$Selected ? ' selected' : '' ) . '>' . $Self->_E( $Self->_T('TimeAccountingNoActivityType', $Language) ) . '</option>';
    for my $Activity ( @{ $Self->ActivityTypeList( ActiveOnly => 1 ) } ) {
        my $IsSelected = $HasSelected ? ( $Selected == $Activity->{id} ) : $Activity->{is_default};
        $HTML .= '<option value="' . $Self->_E($Activity->{id}) . '"' . ( $IsSelected ? ' selected' : '' ) . '>' . $Self->_E($Activity->{name}) . '</option>';
    }
    $HTML .= '</select></div>';
    $HTML .= '<label class="qisutu-form-checkbox qisutu-time-accounting-billable"><input type="checkbox" name="' . $Self->_E($Prefix . 'TimeAccountingBillable') . '" value="1"' . ( $Billable ? ' checked' : '' ) . '><span>' . $Self->_E( $Self->_T('TimeAccountingBillable', $Language) ) . '</span></label>';
    $HTML .= '</div><p class="qisutu-form-help">' . $Self->_E( $Self->_T('TimeAccountingOptionalHint', $Language) ) . '</p></fieldset>';
    return $HTML;
}

sub TicketSummaryHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $TicketID = $Param{TicketID} || 0;
    my $CanCorrect = !$Param{ReadOnly} && $Self->CorrectionAllowed( UserID => $Param{UserID} );
    my $Permission = $Self->{Permission} || QisutuPermission->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $IsAdmin = $Permission->UserIsAdmin( UserID => $Param{UserID} ) ? 1 : 0;
    my $Entries = $Self->TicketEntryList( TicketID => $TicketID );
    my ( $Total, $Billable ) = (0, 0);
    for my $Entry ( @{$Entries} ) {
        next if $Entry->{cancellation_id};
        $Total += $Entry->{duration_minutes} || 0;
        $Billable += $Entry->{duration_minutes} || 0 if $Entry->{is_billable};
    }

    my $HTML = '<section id="qisutu-ticket-time-accounting" class="qisutu-ticket-time-accounting"><div class="qisutu-ticket-time-accounting-summary">';
    $HTML .= '<div><span>' . $Self->_E( $Self->_T('TimeAccountingTotal', $Language) ) . '</span><strong>' . $Self->_E( $Self->_Duration($Total) ) . '</strong></div>';
    $HTML .= '<div><span>' . $Self->_E( $Self->_T('TimeAccountingBillableTotal', $Language) ) . '</span><strong>' . $Self->_E( $Self->_Duration($Billable) ) . '</strong></div>';
    $HTML .= '<div><span>' . $Self->_E( $Self->_T('TimeAccountingNonBillableTotal', $Language) ) . '</span><strong>' . $Self->_E( $Self->_Duration($Total - $Billable) ) . '</strong></div></div>';
    if ( !@{$Entries} ) {
        $HTML .= '<p class="qisutu-form-hint">' . $Self->_E( $Self->_T('TimeAccountingNoEntries', $Language) ) . '</p></section>';
        return $HTML;
    }
    $HTML .= '<div class="qisutu-time-accounting-entry-list">';
    for my $Entry ( @{$Entries} ) {
        my $Name = join ' ', grep {$_} ( $Entry->{firstname}, $Entry->{lastname} );
        $Name ||= $Entry->{login} || '-';
        my $CancelledClass = $Entry->{cancellation_id} ? ' qisutu-time-accounting-cancelled' : '';
        $HTML .= '<article class="qisutu-time-accounting-entry' . $CancelledClass . '">';
        $HTML .= '<div class="qisutu-time-accounting-entry-head"><strong>' . $Self->_E($Entry->{work_date}) . '</strong><span>' . $Self->_E( $Self->_Duration($Entry->{duration_minutes}) ) . '</span></div>';
        $HTML .= '<dl class="qisutu-time-accounting-entry-data">';
        $HTML .= '<div><dt>' . $Self->_E( $Self->_T('TimeAccountingAgent', $Language) ) . '</dt><dd>' . $Self->_E($Name) . '</dd></div>';
        $HTML .= '<div><dt>' . $Self->_E( $Self->_T('TimeAccountingActivityType', $Language) ) . '</dt><dd>' . $Self->_E($Entry->{activity_type_name} || '-') . '</dd></div>';
        $HTML .= '<div><dt>' . $Self->_E( $Self->_T('TimeAccountingDescription', $Language) ) . '</dt><dd>' . $Self->_E($Entry->{description} || '-') . '</dd></div>';
        $HTML .= '<div><dt>' . $Self->_E( $Self->_T('TimeAccountingBilling', $Language) ) . '</dt><dd>' . $Self->_E( $Self->_T($Entry->{is_billable} ? 'TimeAccountingBillableYes' : 'TimeAccountingBillableNo', $Language) ) . '</dd></div>';
        $HTML .= '</dl><div class="qisutu-time-accounting-entry-actions">';
        if ( $Entry->{cancellation_id} ) {
            $HTML .= '<strong>' . $Self->_E( $Self->_T('TimeAccountingCancelled', $Language) ) . '</strong><br><small>' . $Self->_E($Entry->{cancellation_reason}) . '</small>';
        }
        elsif ( $CanCorrect && ( $IsAdmin || ( $Entry->{agent_user_id} || 0 ) == ( $Param{UserID} || 0 ) ) ) {
            my $DialogID = 'qisutu-time-correction-dialog-' . $Entry->{id};
            my $DialogTitleID = $DialogID . '-title';
            my $CorrectLabel = $Self->_E( $Self->_T('TimeAccountingCorrect', $Language) );
            my $CancelLabel = $Self->_E( $Self->_T('AdminCancel', $Language) );

            $HTML .= '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-time-correction-open="' . $Self->_E($DialogID) . '" aria-haspopup="dialog">' . $CorrectLabel . '</button>';
            $HTML .= '<dialog id="' . $Self->_E($DialogID) . '" class="qisutu-time-accounting-dialog" aria-labelledby="' . $Self->_E($DialogTitleID) . '" data-qisutu-time-correction-dialog>';
            $HTML .= '<div class="qisutu-time-accounting-dialog-shell"><header class="qisutu-time-accounting-dialog-header"><h3 id="' . $Self->_E($DialogTitleID) . '">' . $CorrectLabel . '</h3>';
            $HTML .= '<button class="qisutu-time-accounting-dialog-close" type="button" aria-label="' . $CancelLabel . '" data-qisutu-time-correction-close>&times;</button></header>';
            $HTML .= '<form class="qisutu-time-accounting-correction" method="post" action="index.pl">';
            $HTML .= '<input type="hidden" name="Page" value="AgentTicketZoom"><input type="hidden" name="Step" value="TimeAccountingCorrect"><input type="hidden" name="TicketID" value="' . $Self->_E($TicketID) . '"><input type="hidden" name="TimeAccountingID" value="' . $Self->_E($Entry->{id}) . '">';
            $HTML .= '<div class="qisutu-form-field"><label>' . $Self->_E( $Self->_T('TimeAccountingCorrectionReason', $Language) ) . '</label><textarea name="TimeAccountingCorrectionReason" required></textarea></div>';
            $HTML .= '<div class="qisutu-form-field"><label>' . $Self->_E( $Self->_T('TimeAccountingDescription', $Language) ) . '</label><textarea name="ReplacementTimeAccountingDescription">' . $Self->_E($Entry->{description} || '') . '</textarea></div>';
            my $CorrectionRequest = {
                ReplacementTimeAccountingHours => int( ($Entry->{duration_minutes} || 0) / 60 ),
                ReplacementTimeAccountingMinutes => ($Entry->{duration_minutes} || 0) % 60,
                ReplacementTimeAccountingActivityTypeID => $Entry->{activity_type_id} || 0,
                ReplacementTimeAccountingBillable => $Entry->{is_billable} ? 1 : 0,
            };
            $HTML .= $Self->FormHTML( Language => $Language, Request => $CorrectionRequest, NamePrefix => 'Replacement', IDPrefix => 'qisutu-time-correction-' . $Entry->{id} );
            $HTML .= '<div class="qisutu-form-actions"><button class="qisutu-button qisutu-button-secondary" type="button" data-qisutu-time-correction-close>' . $CancelLabel . '</button>';
            $HTML .= '<button class="qisutu-button qisutu-button-primary" type="submit">' . $Self->_E( $Self->_T('TimeAccountingCreateCorrection', $Language) ) . '</button></div></form></div></dialog>';
        }
        $HTML .= '</div></article>';
    }
    $HTML .= '</div></section>';
    return $HTML;
}

sub _DefaultBillable {
    my ($Self) = @_;
    return $Self->{DefaultBillableCache} if defined $Self->{DefaultBillableCache};
    my $Setting = QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} );
    $Self->{DefaultBillableCache} = $Setting->Get( Key => 'time_accounting.default_billable' ) ? 1 : 0;
    return $Self->{DefaultBillableCache};
}

sub _Duration {
    my ( $Self, $Minutes ) = @_;
    $Minutes ||= 0;
    return int( $Minutes / 60 ) . ':' . sprintf( '%02d', $Minutes % 60 ) . ' h';
}

sub _T {
    my ( $Self, $Key, $Language ) = @_;
    return $Self->{Output} ? $Self->{Output}->Translate( Key => $Key, Language => $Language ) : $Key;
}

sub _E {
    my ( $Self, $Value ) = @_;
    return $Self->{Output} ? $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' ) : ( defined $Value ? $Value : '' );
}

1;
