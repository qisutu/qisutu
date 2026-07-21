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

package QisutuCMDB;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json decode_json);

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

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub PermissionLevel {
    my ( $Self, %Param ) = @_;
    my $User = $Param{User} || {};
    return { View => 0, Create => 0, Change => 0, Import => 0, Admin => 0 }
        if ( $User->{account_type} || '' ) ne 'agent' || !( $User->{user_account_id} || 0 );

    my $Admin = $Self->{DB}->SelectRow(
        'SELECT 1 AS allowed
         FROM user_group_member ugm
         INNER JOIN user_group_permission ugp ON ugp.user_group_id = ugm.user_group_id
         INNER JOIN user_group ug ON ug.id = ugm.user_group_id
         WHERE ugm.user_account_id = ? AND ugm.active = 1 AND ug.active = 1
           AND ugp.permission_key = ? AND ugp.active = 1 LIMIT 1',
        $User->{user_account_id}, 'admin.view',
    ) ? 1 : 0;

    return {
        View   => 1,
        Create => $Admin ? 1 : 0,
        Change => 1,
        Import => $Admin ? 1 : 0,
        Admin  => $Admin,
    };
}

sub StatusSetActive {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{StatusID} );
    return if !$ID;
    my $Result = $Self->{DB}->Do(
        'UPDATE cmdb_status SET active=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',
        $Param{Active} ? 1 : 0, $Self->_ID( $Param{ChangedByUserID} ) || 1, $ID,
    );
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBStatusSaveFailed' if !$Result;
    return $Result ? 1 : undef;
}

sub TypeList {
    my ( $Self, %Param ) = @_;
    my $Where = $Param{IncludeInactive} ? '' : 'WHERE t.active = 1';
    return $Self->{DB}->SelectAll(
        'SELECT t.*,
            (SELECT COUNT(*) FROM cmdb_ci c WHERE c.type_id = t.id) AS ci_count,
            (SELECT COUNT(*) FROM cmdb_ci_field f WHERE f.type_id = t.id AND f.active = 1) AS field_count
         FROM cmdb_ci_type t ' . $Where . '
         ORDER BY t.sort_order ASC, t.name ASC, t.id ASC'
    ) || [];
}

sub TypeGet {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{TypeID} );
    return if !$ID;
    return $Self->{DB}->SelectRow('SELECT * FROM cmdb_ci_type WHERE id = ? LIMIT 1', $ID);
}

sub TypeSave {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{TypeID} );
    my $Name = $Self->_Trim( $Param{Name} );
    my $Key = $Self->_TechnicalKey( $Param{TypeKey} || $Name );
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    if ( !$Name || !$Key ) {
        $Self->{LastError} = 'Translate:CMDBTypeNameRequired';
        return;
    }
    my $Icon = $Self->_Trim( $Param{Icon} );
    $Icon = substr( $Icon || 'CI', 0, 20 );
    my $Sort = $Self->_UInt( $Param{SortOrder}, 1000 );
    my $Result;
    if ($ID) {
        $Result = $Self->{DB}->Do(
            'UPDATE cmdb_ci_type SET name = ?, description = ?, icon = ?, active = ?, sort_order = ?, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
            $Name, $Self->_Trim( $Param{Description} ), $Icon, $Param{Active} ? 1 : 0, $Sort, $UserID, $ID,
        );
    }
    else {
        $Result = $Self->{DB}->Do(
            'INSERT INTO cmdb_ci_type (type_key,name,description,icon,active,sort_order,created_by_user_id,changed_by_user_id,created_at,changed_at)
             VALUES (?,?,?,?,?,?,?,?,NOW(),NOW())',
            $Key, $Name, $Self->_Trim( $Param{Description} ), $Icon, $Param{Active} ? 1 : 0, $Sort, $UserID, $UserID,
        );
        $ID = $Self->{DB}->LastInsertID('cmdb_ci_type') if $Result;
    }
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBTypeSaveFailed';
        return;
    }
    return $ID;
}

sub FieldGroupList {
    my ( $Self, %Param ) = @_;
    my $TypeID = $Self->_ID( $Param{TypeID} );
    return [] if !$TypeID;
    my $Where = $Param{IncludeInactive} ? '' : 'AND g.active = 1';
    return $Self->{DB}->SelectAll(
        'SELECT g.*,(SELECT COUNT(*) FROM cmdb_ci_field f WHERE f.group_id=g.id) AS field_count
         FROM cmdb_ci_field_group g WHERE g.type_id=? ' . $Where . '
         ORDER BY g.sort_order,g.label,g.id', $TypeID,
    ) || [];
}

sub FieldGroupGet {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{GroupID} );
    return if !$ID;
    return $Self->{DB}->SelectRow('SELECT * FROM cmdb_ci_field_group WHERE id=? LIMIT 1', $ID);
}

sub FieldGroupSave {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{GroupID} );
    my $TypeID = $Self->_ID( $Param{TypeID} );
    my $Key = $Self->_TechnicalKey( $Param{GroupKey} || $Param{Label} );
    my $Label = $Self->_Trim( $Param{Label} );
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    if ( !$TypeID || !$Key || !$Label ) {
        $Self->{LastError} = 'Translate:CMDBFieldGroupRequired';
        return;
    }
    my $Result;
    if ($ID) {
        $Result = $Self->{DB}->Do(
            'UPDATE cmdb_ci_field_group SET label=?,description=?,active=?,sort_order=?,changed_by_user_id=?,changed_at=NOW() WHERE id=? AND type_id=?',
            $Label,$Self->_Trim($Param{Description}),$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$ID,$TypeID,
        );
    }
    else {
        $Result = $Self->{DB}->Do(
            'INSERT INTO cmdb_ci_field_group (type_id,group_key,label,description,active,sort_order,created_by_user_id,changed_by_user_id,created_at,changed_at)
             VALUES (?,?,?,?,?,?,?,?,NOW(),NOW())',
            $TypeID,$Key,$Label,$Self->_Trim($Param{Description}),$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$UserID,
        );
        $ID = $Self->{DB}->LastInsertID('cmdb_ci_field_group') if $Result;
    }
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldGroupSaveFailed';
        return;
    }
    return $ID;
}

sub StatusList {
    my ( $Self, %Param ) = @_;
    my @Where;
    my @Bind;
    push @Where, 's.active=1' if !$Param{IncludeInactive};
    if ( my $TypeID = $Self->_ID( $Param{TypeID} ) ) {
        push @Where, 'EXISTS (SELECT 1 FROM cmdb_ci_type_status ts WHERE ts.status_id=s.id AND ts.type_id=?)';
        push @Bind, $TypeID;
    }
    my $Where = @Where ? 'WHERE ' . join(' AND ',@Where) : '';
    return $Self->{DB}->SelectAll(
        'SELECT s.*,(SELECT COUNT(*) FROM cmdb_ci ci WHERE ci.status=s.status_key) AS ci_count
         FROM cmdb_status s ' . $Where . ' ORDER BY s.sort_order,s.label,s.id', @Bind,
    ) || [];
}

sub StatusGet {
    my ( $Self, %Param ) = @_;
    if ( my $ID = $Self->_ID( $Param{StatusID} ) ) {
        return $Self->{DB}->SelectRow('SELECT * FROM cmdb_status WHERE id=? LIMIT 1',$ID);
    }
    my $Key = $Self->_TechnicalKey( $Param{StatusKey} );
    return if !$Key;
    return $Self->{DB}->SelectRow('SELECT * FROM cmdb_status WHERE status_key=? LIMIT 1',$Key);
}

sub StatusSave {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{StatusID} );
    my $Key = $Self->_TechnicalKey( $Param{StatusKey} || $Param{Label} );
    my $Label = $Self->_Trim( $Param{Label} );
    my %Class = map { $_ => 1 } qw(active inactive retired);
    my $Class = $Class{$Param{StatusClass}||''} ? $Param{StatusClass} : 'active';
    my $Color = $Self->_Trim( $Param{Color} );
    $Color = '#4b6478' if $Color !~ m{\A#[0-9a-fA-F]{6}\z};
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    if (!$Key || !$Label) { $Self->{LastError}='Translate:CMDBStatusRequired'; return; }
    my $Result;
    if ($ID) {
        $Result=$Self->{DB}->Do('UPDATE cmdb_status SET label=?,status_class=?,color=?,active=?,sort_order=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',
            $Label,$Class,$Color,$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$ID);
    }
    else {
        $Result=$Self->{DB}->Do('INSERT INTO cmdb_status (status_key,label,status_class,color,active,sort_order,created_by_user_id,changed_by_user_id,created_at,changed_at) VALUES (?,?,?,?,?,?,?,?,NOW(),NOW())',
            $Key,$Label,$Class,$Color,$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$UserID);
        $ID=$Self->{DB}->LastInsertID('cmdb_status') if $Result;
    }
    if(!$Result){$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBStatusSaveFailed';return;}
    return $ID;
}

sub TypeStatusSave {
    my ( $Self, %Param ) = @_;
    my $TypeID=$Self->_ID($Param{TypeID});return if !$TypeID;
    my @StatusIDs=ref$Param{StatusIDs} eq 'ARRAY'?@{$Param{StatusIDs}}:defined$Param{StatusIDs}?($Param{StatusIDs}):();
    my %Selected=map{$Self->_ID($_)=>1}grep{$Self->_ID($_)}@StatusIDs;
    my $DefaultID=$Self->_ID($Param{DefaultStatusID});
    my $Used=$Self->{DB}->SelectAll('SELECT DISTINCT s.id FROM cmdb_ci ci INNER JOIN cmdb_status s ON s.status_key=ci.status WHERE ci.type_id=? AND ci.status<>""',$TypeID)||[];
    for my$Row(@{$Used}){if(!$Selected{$Row->{id}}){$Self->{LastError}='Translate:CMDBStatusInUse';return;}}
    $DefaultID=0 if$DefaultID&&!$Selected{$DefaultID};
    $Self->{DB}->BeginWork()||do{$Self->{LastError}=$Self->{DB}->Error();return;};
    if(!$Self->{DB}->Do('DELETE FROM cmdb_ci_type_status WHERE type_id=?',$TypeID)){$Self->_RollbackError('Translate:CMDBStatusSaveFailed');return;}
    my $Sort=0;
    for my $StatusID(sort{$a<=>$b}keys%Selected){$Sort+=100;if(!$Self->{DB}->Do('INSERT INTO cmdb_ci_type_status (type_id,status_id,is_default,sort_order) VALUES (?,?,?,?)',$TypeID,$StatusID,$StatusID==$DefaultID?1:0,$Sort)){$Self->_RollbackError('Translate:CMDBStatusSaveFailed');return;}}
    if(!$Self->{DB}->Commit()){$Self->_RollbackError('Translate:CMDBStatusSaveFailed');return;}
    return 1;
}

sub TypeSetActive {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{TypeID} );
    return if !$ID;
    my $Result = $Self->{DB}->Do(
        'UPDATE cmdb_ci_type SET active = ?, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $Param{Active} ? 1 : 0, $Self->_ID( $Param{ChangedByUserID} ) || 1, $ID,
    );
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBTypeSaveFailed' if !$Result;
    return $Result ? 1 : undef;
}

sub FieldList {
    my ( $Self, %Param ) = @_;
    my $TypeID = $Self->_ID( $Param{TypeID} );
    return [] if !$TypeID;
    my $Active = $Param{IncludeInactive} ? '' : 'AND f.active = 1';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT f.*,g.label AS group_label,g.group_key,g.sort_order AS group_sort_order
         FROM cmdb_ci_field f LEFT JOIN cmdb_ci_field_group g ON g.id=f.group_id
         WHERE f.type_id = ? ' . $Active . '
         ORDER BY COALESCE(g.sort_order,0),COALESCE(g.label,""),f.sort_order,f.label,f.id', $TypeID,
    ) || [];
    for my $Field ( @{$Rows} ) {
        $Field->{options} = $Self->FieldOptionList( FieldID => $Field->{id}, IncludeInactive => $Param{IncludeInactive} );
    }
    return $Rows;
}

sub FieldGet {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{FieldID} );
    return if !$ID;
    my $Field = $Self->{DB}->SelectRow('SELECT * FROM cmdb_ci_field WHERE id = ? LIMIT 1', $ID);
    $Field->{options} = $Self->FieldOptionList( FieldID => $ID, IncludeInactive => 1 ) if $Field;
    return $Field;
}

sub FieldOptionList {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{FieldID} );
    return [] if !$ID;
    my $Where = $Param{IncludeInactive} ? '' : 'AND active = 1';
    return $Self->{DB}->SelectAll(
        'SELECT * FROM cmdb_ci_field_option WHERE field_id = ? ' . $Where . ' ORDER BY sort_order ASC, id ASC', $ID,
    ) || [];
}

sub FieldSave {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{FieldID} );
    my $TypeID = $Self->_ID( $Param{TypeID} );
    my $Key = lc $Self->_Trim( $Param{FieldKey} );
    $Key =~ s{[^a-z0-9_]+}{_}g;
    $Key =~ s{\A_+|_+\z}{}g;
    my $Label = $Self->_Trim( $Param{Label} );
    my $GroupID = $Self->_ID( $Param{GroupID} );
    if ($GroupID) {
        my $Group=$Self->FieldGroupGet(GroupID=>$GroupID);
        $GroupID=0 if !$Group || ($Group->{type_id}||0)!=$TypeID;
    }
    my %Allowed = map { $_ => 1 } qw(text textarea integer decimal date datetime boolean dropdown multiselect email url ip);
    my $FieldType = $Allowed{ $Param{FieldType} || '' } ? $Param{FieldType} : 'text';
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    if ( !$TypeID || !$Key || !$Label ) {
        $Self->{LastError} = 'Translate:CMDBFieldRequired';
        return;
    }
    my $Options = ref $Param{Options} eq 'ARRAY' ? $Param{Options} : [];
    if ( $FieldType =~ m{\A(?:dropdown|multiselect)\z} && !@{$Options} ) {
        $Self->{LastError} = 'Translate:CMDBFieldOptionsRequired';
        return;
    }
    $Self->{DB}->BeginWork() || do { $Self->{LastError} = $Self->{DB}->Error(); return; };
    my $Result;
    if ($ID) {
        $Result = $Self->{DB}->Do(
            'UPDATE cmdb_ci_field SET group_id=?,label=?,field_type=?,is_required=?,is_searchable=?,is_unique=?,customer_visible=?,default_value=?,active=?,sort_order=?,changed_by_user_id=?,changed_at=NOW()
             WHERE id=? AND type_id=?',
            $GroupID||undef,$Label,$FieldType,$Param{IsRequired}?1:0,$Param{IsSearchable}?1:0,$Param{IsUnique}?1:0,$Param{CustomerVisible}?1:0,
            $Param{DefaultValue},$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$ID,$TypeID,
        );
    }
    else {
        $Result = $Self->{DB}->Do(
            'INSERT INTO cmdb_ci_field (type_id,group_id,field_key,label,field_type,is_required,is_searchable,is_unique,customer_visible,default_value,active,sort_order,created_by_user_id,changed_by_user_id,created_at,changed_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,NOW(),NOW())',
            $TypeID,$GroupID||undef,$Key,$Label,$FieldType,$Param{IsRequired}?1:0,$Param{IsSearchable}?1:0,$Param{IsUnique}?1:0,$Param{CustomerVisible}?1:0,
            $Param{DefaultValue},$Param{Active}?1:0,$Self->_UInt($Param{SortOrder},1000),$UserID,$UserID,
        );
        $ID = $Self->{DB}->LastInsertID('cmdb_ci_field') if $Result;
    }
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }
    if ( !$Self->{DB}->Do('DELETE FROM cmdb_ci_field_option WHERE field_id = ?', $ID) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }
    my $Position = 0;
    for my $Option ( @{$Options} ) {
        next if ref $Option ne 'HASH';
        my $OptionKey = $Self->_Trim( $Option->{Key} );
        my $OptionLabel = $Self->_Trim( $Option->{Label} );
        next if !$OptionKey || !$OptionLabel;
        $Position += 100;
        if ( !$Self->{DB}->Do(
            'INSERT INTO cmdb_ci_field_option (field_id,option_key,option_label,active,sort_order) VALUES (?,?,?,?,?)',
            $ID, $OptionKey, $OptionLabel, 1, $Position,
        ) ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }
    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }
    return $ID;
}

sub FieldSetActive {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{FieldID} );
    return if !$ID;
    my $Result = $Self->{DB}->Do(
        'UPDATE cmdb_ci_field SET active=?, changed_by_user_id=?, changed_at=NOW() WHERE id=?',
        $Param{Active} ? 1 : 0, $Self->_ID( $Param{ChangedByUserID} ) || 1, $ID,
    );
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBFieldSaveFailed' if !$Result;
    return $Result ? 1 : undef;
}

sub RelationTypeList {
    my ( $Self, %Param ) = @_;
    my $Where = $Param{IncludeInactive} ? '' : 'WHERE active = 1';
    return $Self->{DB}->SelectAll(
        'SELECT * FROM cmdb_relation_type ' . $Where . ' ORDER BY sort_order ASC, name ASC, id ASC'
    ) || [];
}

sub RelationTypeSave {
    my ( $Self, %Param ) = @_;
    my $Name = lc $Self->_Trim( $Param{Name} );
    $Name =~ s{[^a-z0-9_]+}{_}g;
    $Name =~ s{\A_+|_+\z}{}g;
    my $Forward = $Self->_Trim( $Param{ForwardLabel} );
    my $Reverse = $Self->_Trim( $Param{ReverseLabel} );
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    if ( !$Name || !$Forward || !$Reverse ) {
        $Self->{LastError} = 'Translate:CMDBRelationTypeRequired';
        return;
    }
    my $Result = $Self->{DB}->Do(
        'INSERT INTO cmdb_relation_type (name,forward_label,reverse_label,active,sort_order,created_by_user_id,changed_by_user_id,created_at,changed_at)
         VALUES (?,?,?,?,?,?,?,NOW(),NOW())
         ON DUPLICATE KEY UPDATE forward_label=VALUES(forward_label),reverse_label=VALUES(reverse_label),active=VALUES(active),sort_order=VALUES(sort_order),changed_by_user_id=VALUES(changed_by_user_id),changed_at=NOW()',
        $Name, $Forward, $Reverse, $Param{Active} ? 1 : 0, $Self->_UInt( $Param{SortOrder}, 1000 ), $UserID, $UserID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CMDBRelationTypeSaveFailed';
        return;
    }
    return 1;
}

sub RelationTypeSetActive {
    my ( $Self, %Param ) = @_;
    my $ID=$Self->_ID($Param{RelationTypeID});return if!$ID;
    my $Result=$Self->{DB}->Do('UPDATE cmdb_relation_type SET active=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',$Param{Active}?1:0,$Self->_ID($Param{ChangedByUserID})||1,$ID);
    $Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBRelationTypeSaveFailed'if!$Result;return$Result?1:undef;
}

sub CIList {
    my ( $Self, %Param ) = @_;
    my @Where;
    my @Bind;
    if ( !$Param{IncludeInactive} ) { push @Where, 'ci.active = 1'; }
    if ( my $TypeID = $Self->_ID( $Param{TypeID} ) ) { push @Where, 'ci.type_id = ?'; push @Bind, $TypeID; }
    if ( my $CustomerID = $Self->_ID( $Param{CustomerID} ) ) { push @Where, 'ci.customer_id = ?'; push @Bind, $CustomerID; }
    if ( defined $Param{Status} && $Param{Status} ne '' ) { push @Where, 'ci.status = ?'; push @Bind, $Param{Status}; }
    my $Search = $Self->_Trim( $Param{Search} );
    if ($Search) {
        my $Like = '%' . $Search . '%';
        push @Where, '(ci.ci_number LIKE ? OR ci.name LIKE ? OR EXISTS (SELECT 1 FROM cmdb_ci_value cv INNER JOIN cmdb_ci_field cf ON cf.id=cv.field_id WHERE cv.ci_id=ci.id AND cf.active=1 AND cf.is_searchable=1 AND cv.value_text LIKE ?))';
        push @Bind, ($Like) x 3;
    }
    if ( my $CustomerUserID = $Self->_ID( $Param{CustomerUserID} ) ) {
        my $CU = $Self->{DB}->SelectRow('SELECT customer_id FROM customer_user WHERE id=? AND active=1 LIMIT 1', $CustomerUserID) || {};
        push @Where, 'ci.customer_id = ? AND (ci.customer_user_id IS NULL OR ci.customer_user_id = ?)';
        push @Bind, $CU->{customer_id} || 0, $CustomerUserID;
    }
    my $Limit = $Self->_UInt( $Param{Limit}, 50 );
    $Limit = 200 if $Limit > 200;
    my $Offset = $Self->_UInt( $Param{Offset}, 0 );
    my $WhereSQL = @Where ? 'WHERE ' . join( ' AND ', @Where ) : '';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT ci.*,ct.name AS type_name,ct.type_key,ct.icon AS type_icon,s.label AS status_label,s.status_class,s.color AS status_color,c.name AS customer_name,
            COALESCE(NULLIF(TRIM(CONCAT(ua.firstname," ",ua.lastname)),""),ua.login,ua.email) AS customer_user_name,
            (SELECT COUNT(*) FROM ticket_cmdb_ci tc WHERE tc.ci_id=ci.id) AS ticket_count
         FROM cmdb_ci ci
         INNER JOIN cmdb_ci_type ct ON ct.id=ci.type_id
         LEFT JOIN cmdb_status s ON s.status_key=ci.status
         LEFT JOIN customer c ON c.id=ci.customer_id
         LEFT JOIN customer_user cu ON cu.id=ci.customer_user_id
         LEFT JOIN user_account ua ON ua.id=cu.user_account_id
         ' . $WhereSQL . '
         ORDER BY ci.active DESC, ci.name ASC, ci.ci_number ASC
         LIMIT ' . int($Limit) . ' OFFSET ' . int($Offset), @Bind,
    ) || [];
    my $Count = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS count FROM cmdb_ci ci ' . $WhereSQL, @Bind,
    ) || {};
    return { Items => $Rows, Count => 0 + ( $Count->{count} || 0 ) };
}

sub CIGet {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{CIID} );
    return if !$ID;
    my $CI = $Self->{DB}->SelectRow(
        'SELECT ci.*,ct.name AS type_name,ct.type_key,ct.icon AS type_icon,s.label AS status_label,s.status_class,s.color AS status_color,c.name AS customer_name,
            COALESCE(NULLIF(TRIM(CONCAT(ua.firstname," ",ua.lastname)),""),ua.login,ua.email) AS customer_user_name
         FROM cmdb_ci ci INNER JOIN cmdb_ci_type ct ON ct.id=ci.type_id
         LEFT JOIN cmdb_status s ON s.status_key=ci.status
         LEFT JOIN customer c ON c.id=ci.customer_id
         LEFT JOIN customer_user cu ON cu.id=ci.customer_user_id
         LEFT JOIN user_account ua ON ua.id=cu.user_account_id
         WHERE ci.id=? LIMIT 1', $ID,
    );
    return if !$CI;
    my $Values = $Self->{DB}->SelectAll('SELECT field_id,value_text FROM cmdb_ci_value WHERE ci_id=?', $ID) || [];
    $CI->{values} = { map { $_->{field_id} => $_->{value_text} } @{$Values} };
    return $CI;
}

sub CISave {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $User = $Param{User} || {};
    my $UserID = $Self->_ID( $User->{user_account_id} ) || 1;
    my $ID = $Self->_ID( $Param{CIID} || $Request->{CIID} );
    my $Old = $ID ? $Self->CIGet( CIID => $ID ) : undef;
    if ( $ID && !$Old ) { $Self->{LastError}='Translate:CMDBNotFound'; return; }
    my $TypeID = $Old ? $Old->{type_id} : $Self->_ID( $Request->{TypeID} );
    my $Type = $Self->TypeGet( TypeID => $TypeID );
    my $Name = $Self->_Trim( $Request->{Name} );
    if ( !$Type || !$Name ) { $Self->{LastError}='Translate:CMDBRequiredFields'; return; }
    my $Status = $Self->_TechnicalKey( $Request->{Status} );
    if (!$Status && !$Old) {
        my $Default=$Self->{DB}->SelectRow('SELECT s.status_key FROM cmdb_ci_type_status ts INNER JOIN cmdb_status s ON s.id=ts.status_id WHERE ts.type_id=? AND ts.is_default=1 AND s.active=1 LIMIT 1',$TypeID)||{};
        $Status=$Default->{status_key}||'';
    }
    if ($Status) {
        my $StatusRow=$Self->StatusGet(StatusKey=>$Status);
        my $Allowed=$StatusRow?$Self->{DB}->SelectRow('SELECT 1 AS allowed FROM cmdb_ci_type_status WHERE type_id=? AND status_id=? LIMIT 1',$TypeID,$StatusRow->{id}):undef;
        if(!$StatusRow||!$Allowed){$Self->{LastError}='Translate:CMDBStatusInvalid';return;}
    }
    my $CustomerID = $Self->_ID( $Request->{CustomerID} );
    my $CustomerUserID = $Self->_ID( $Request->{CustomerUserID} );
    if ($CustomerUserID) {
        my $CU = $Self->{DB}->SelectRow('SELECT customer_id FROM customer_user WHERE id=? AND active=1 LIMIT 1', $CustomerUserID);
        if ( !$CU || !$CustomerID || ( $CU->{customer_id} || 0 ) != $CustomerID ) {
            $Self->{LastError}='Translate:CMDBCustomerUserInvalid'; return;
        }
    }
    my $Fields = $Self->FieldList( TypeID => $TypeID );
    my %Value;
    for my $Field ( @{$Fields} ) {
        my $Key = 'CMDBField_' . $Field->{id};
        my $Raw = $Request->{$Key};
        my $Value = '';
        if ( ref $Raw eq 'ARRAY' ) {
            my %Seen;
            $Value = join "\n", grep { $_ ne '' && !$Seen{$_}++ } map { $Self->_Trim($_) } @{$Raw};
        }
        else { $Value = $Self->_Trim( defined $Raw ? $Raw : ( $Field->{default_value} || '' ) ); }
        if ( $Field->{is_required} && $Value eq '' ) {
            $Self->{LastError} = 'Translate:CMDBRequiredField'; return;
        }
        if ( !$Self->_FieldValueValid( Field => $Field, Value => $Value ) ) {
            $Self->{LastError} = 'Translate:CMDBInvalidField'; return;
        }
        if ($Field->{is_unique} && $Value ne '') {
            my $Duplicate=$Self->{DB}->SelectRow('SELECT cv.ci_id FROM cmdb_ci_value cv WHERE cv.field_id=? AND cv.value_text=? AND cv.ci_id<>? LIMIT 1',$Field->{id},$Value,$ID||0);
            if($Duplicate){$Self->{LastError}='Translate:CMDBUniqueFieldDuplicate';return;}
        }
        $Value{ $Field->{id} } = $Value;
    }

    my $Active=exists$Request->{Active}?($Request->{Active}?1:0):($Old?($Old->{active}?1:0):1);
    my $CustomerVisible=exists$Request->{CustomerVisible}?($Request->{CustomerVisible}?1:0):($Old?($Old->{customer_visible}?1:0):0);
    my $ExternalID=exists$Request->{ExternalID}?$Self->_Trim($Request->{ExternalID}):($Old?($Old->{external_id}||''):'');
    my $Source=$Param{Source}||($Old?($Old->{source}||'manual'):'manual');

    $Self->{DB}->BeginWork() || do { $Self->{LastError}=$Self->{DB}->Error(); return; };
    if (!$ID) {
        my $Counter = $Self->{DB}->SelectRow('SELECT next_value FROM cmdb_counter WHERE counter_key=? FOR UPDATE','ci_number') || {};
        my $Number = $Counter->{next_value} || 1;
        if ( !$Self->{DB}->Do('UPDATE cmdb_counter SET next_value=? WHERE counter_key=?',$Number+1,'ci_number') ) { $Self->_RollbackError(); return; }
        my $CINumber = sprintf 'CI-%06d', $Number;
        if ( !$Self->{DB}->Do(
            'INSERT INTO cmdb_ci (ci_number,type_id,name,status,customer_id,customer_user_id,customer_visible,source,external_id,active,created_by_user_id,changed_by_user_id,created_at,changed_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NOW(),NOW())',
            $CINumber,$TypeID,$Name,$Status,$CustomerID||undef,$CustomerUserID||undef,$CustomerVisible,$Source,$ExternalID,$Active,$UserID,$UserID,
        ) ) { $Self->_RollbackError(); return; }
        $ID = $Self->{DB}->LastInsertID('cmdb_ci');
        if (!$ID) { $Self->_RollbackError('Translate:CMDBSaveFailed'); return; }
        $Self->_HistoryAdd(CIID=>$ID,EventType=>'created',NewValue=>$Name,Details=>$CINumber,User=>$User,Source=>$Param{Source}||'application');
    }
    else {
        if ( !$Self->{DB}->Do(
            'UPDATE cmdb_ci SET name=?,status=?,customer_id=?,customer_user_id=?,customer_visible=?,source=?,external_id=?,active=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',
            $Name,$Status,$CustomerID||undef,$CustomerUserID||undef,$CustomerVisible,$Source,$ExternalID,$Active,$UserID,$ID,
        ) ) { $Self->_RollbackError(); return; }
        my @Fixed = (
            [name=>'CMDBName',$Old->{name},$Name], [status=>'CMDBStatus',$Old->{status},$Status],
            [customer_id=>'TicketCustomer',$Old->{customer_id},$CustomerID], [customer_user_id=>'TicketCustomerUser',$Old->{customer_user_id},$CustomerUserID],
            [customer_visible=>'CMDBCustomerVisible',$Old->{customer_visible},$CustomerVisible], [active=>'AdminActive',$Old->{active},$Active],
        );
        for my $Change (@Fixed) {
            next if ( defined $Change->[2] ? $Change->[2] : '' ) eq ( defined $Change->[3] ? $Change->[3] : '' );
            $Self->_HistoryAdd(CIID=>$ID,EventType=>'changed',FieldKey=>$Change->[0],FieldLabel=>$Change->[1],OldValue=>$Change->[2],NewValue=>$Change->[3],User=>$User,Source=>$Param{Source}||'application');
        }
    }
    my $OldValues = $Old ? ( $Old->{values} || {} ) : {};
    for my $Field ( @{$Fields} ) {
        my $NewValue = $Value{ $Field->{id} };
        my $OldValue = defined $OldValues->{ $Field->{id} } ? $OldValues->{ $Field->{id} } : '';
        if ( $NewValue eq '' ) {
            if ( !$Self->{DB}->Do('DELETE FROM cmdb_ci_value WHERE ci_id=? AND field_id=?',$ID,$Field->{id}) ) { $Self->_RollbackError(); return; }
        }
        else {
            if ( !$Self->{DB}->Do(
                'INSERT INTO cmdb_ci_value (ci_id,field_id,value_text,created_by_user_id,changed_by_user_id,created_at,changed_at)
                 VALUES (?,?,?,?,?,NOW(),NOW()) ON DUPLICATE KEY UPDATE value_text=VALUES(value_text),changed_by_user_id=VALUES(changed_by_user_id),changed_at=NOW()',
                $ID,$Field->{id},$NewValue,$UserID,$UserID,
            ) ) { $Self->_RollbackError(); return; }
        }
        if ( $OldValue ne $NewValue ) {
            $Self->_HistoryAdd(CIID=>$ID,EventType=>'field_changed',FieldKey=>$Field->{field_key},FieldLabel=>$Field->{label},OldValue=>$OldValue,NewValue=>$NewValue,User=>$User,Source=>$Param{Source}||'application');
        }
    }
    if ( $Self->Error() || !$Self->{DB}->Commit() ) { $Self->_RollbackError(); return; }
    return $ID;
}

sub CISetActive {
    my ( $Self, %Param ) = @_;
    my $CI = $Self->CIGet( CIID => $Param{CIID} );
    return if !$CI;
    my $Active = $Param{Active} ? 1 : 0;
    return 1 if ( $CI->{active} || 0 ) == $Active;
    my $User = $Param{User} || {};
    $Self->{DB}->BeginWork() || do { $Self->{LastError}=$Self->{DB}->Error(); return; };
    if ( !$Self->{DB}->Do('UPDATE cmdb_ci SET active=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',
        $Active,$Self->_ID($User->{user_account_id})||1,$CI->{id}) ) {
        $Self->_RollbackError('Translate:CMDBSaveFailed'); return;
    }
    $Self->_HistoryAdd(CIID=>$CI->{id},EventType=>$Active?'activated':'archived',OldValue=>$CI->{active},NewValue=>$Active,User=>$User,Source=>'application');
    if ($Self->Error() || !$Self->{DB}->Commit()) {$Self->_RollbackError();return;}
    return 1;
}

sub TicketCIList {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Self->_ID( $Param{TicketID} );
    return [] if !$TicketID;
    return $Self->{DB}->SelectAll(
        'SELECT ci.id,ci.ci_number,ci.name,ci.status,ci.active,ct.name AS type_name,s.label AS status_label,s.status_class,tc.created_at
         FROM ticket_cmdb_ci tc INNER JOIN cmdb_ci ci ON ci.id=tc.ci_id INNER JOIN cmdb_ci_type ct ON ct.id=ci.type_id
         LEFT JOIN cmdb_status s ON s.status_key=ci.status
         WHERE tc.ticket_id=? ORDER BY ci.name ASC,ci.ci_number ASC', $TicketID,
    ) || [];
}

sub TicketLinkAdd {
    my ( $Self, %Param ) = @_;
    my $TicketID=$Self->_ID($Param{TicketID}); my $CIID=$Self->_ID($Param{CIID}); my $User=$Param{User}||{};
    return if !$TicketID || !$CIID;
    my $CI=$Self->CIGet(CIID=>$CIID); return if !$CI || !$CI->{active};
    if ( $Param{CustomerContext} ) {
        return if !$Self->CustomerCIAccessCheck(CIID=>$CIID,User=>$User);
    }
    my $Existing=$Self->{DB}->SelectRow('SELECT id FROM ticket_cmdb_ci WHERE ticket_id=? AND ci_id=? LIMIT 1',$TicketID,$CIID);
    return 1 if $Existing;
    $Self->{DB}->BeginWork() || do {$Self->{LastError}=$Self->{DB}->Error();return;};
    if (!$Self->{DB}->Do('INSERT INTO ticket_cmdb_ci (ticket_id,ci_id,created_by_user_id,created_at) VALUES (?,?,?,NOW())',$TicketID,$CIID,$Self->_ID($User->{user_account_id})||1)) {$Self->_RollbackError();return;}
    $Self->_HistoryAdd(CIID=>$CIID,EventType=>'ticket_linked',NewValue=>$TicketID,Details=>$CI->{ci_number},RelatedTicketID=>$TicketID,User=>$User,Source=>$Param{CustomerContext}?'customer_portal':'application');
    $Self->_TicketHistoryAdd(TicketID=>$TicketID,CI=>$CI,EventType=>'cmdb_ci_linked',User=>$User,Source=>$Param{CustomerContext}?'customer_portal':'application');
    if ($Self->Error() || !$Self->{DB}->Commit()) {$Self->_RollbackError();return;}
    return 1;
}

sub TicketLinkRemove {
    my ( $Self, %Param ) = @_;
    my $TicketID=$Self->_ID($Param{TicketID}); my $CIID=$Self->_ID($Param{CIID}); my $User=$Param{User}||{};
    my $CI=$Self->CIGet(CIID=>$CIID); return if !$TicketID || !$CI;
    $Self->{DB}->BeginWork() || do {$Self->{LastError}=$Self->{DB}->Error();return;};
    my $Result=$Self->{DB}->Do('DELETE FROM ticket_cmdb_ci WHERE ticket_id=? AND ci_id=?',$TicketID,$CIID);
    if (!$Result) {$Self->_RollbackError();return;}
    $Self->_HistoryAdd(CIID=>$CIID,EventType=>'ticket_unlinked',OldValue=>$TicketID,RelatedTicketID=>$TicketID,User=>$User,Source=>'application');
    $Self->_TicketHistoryAdd(TicketID=>$TicketID,CI=>$CI,EventType=>'cmdb_ci_unlinked',User=>$User,Source=>'application');
    if ($Self->Error() || !$Self->{DB}->Commit()) {$Self->_RollbackError();return;}
    return 1;
}

sub RelationList {
    my ( $Self, %Param ) = @_;
    my $CIID=$Self->_ID($Param{CIID}); return [] if !$CIID;
    return $Self->{DB}->SelectAll(
        'SELECT r.id,r.source_ci_id,r.target_ci_id,r.relation_type_id,r.note,r.active,
            CASE WHEN r.source_ci_id=? THEN target.id ELSE source.id END AS related_ci_id,
            CASE WHEN r.source_ci_id=? THEN target.ci_number ELSE source.ci_number END AS related_ci_number,
            CASE WHEN r.source_ci_id=? THEN target.name ELSE source.name END AS related_ci_name,
            CASE WHEN r.source_ci_id=? THEN rt.forward_label ELSE rt.reverse_label END AS relation_label
         FROM cmdb_ci_relation r INNER JOIN cmdb_relation_type rt ON rt.id=r.relation_type_id
         INNER JOIN cmdb_ci source ON source.id=r.source_ci_id INNER JOIN cmdb_ci target ON target.id=r.target_ci_id
         WHERE r.active=1 AND (r.source_ci_id=? OR r.target_ci_id=?) ORDER BY relation_label,related_ci_name',
        $CIID,$CIID,$CIID,$CIID,$CIID,$CIID,
    ) || [];
}

sub RelationAdd {
    my ( $Self, %Param ) = @_;
    my $SourceID=$Self->_ID($Param{SourceCIID}); my $TargetID=$Self->_ID($Param{TargetCIID}); my $TypeID=$Self->_ID($Param{RelationTypeID}); my $User=$Param{User}||{};
    if (!$SourceID||!$TargetID||$SourceID==$TargetID||!$TypeID) {$Self->{LastError}='Translate:CMDBRelationInvalid';return;}
    my $Source=$Self->CIGet(CIID=>$SourceID); my $Target=$Self->CIGet(CIID=>$TargetID); return if !$Source || !$Target;
    $Self->{DB}->BeginWork() || do {$Self->{LastError}=$Self->{DB}->Error();return;};
    my $Result=$Self->{DB}->Do(
        'INSERT INTO cmdb_ci_relation (source_ci_id,target_ci_id,relation_type_id,note,active,created_by_user_id,changed_by_user_id,created_at,changed_at)
         VALUES (?,?,?,?,1,?,?,NOW(),NOW()) ON DUPLICATE KEY UPDATE active=1,note=VALUES(note),changed_by_user_id=VALUES(changed_by_user_id),changed_at=NOW()',
        $SourceID,$TargetID,$TypeID,$Self->_Trim($Param{Note}),$Self->_ID($User->{user_account_id})||1,$Self->_ID($User->{user_account_id})||1,
    );
    if (!$Result) {$Self->_RollbackError('Translate:CMDBRelationSaveFailed');return;}
    $Self->_HistoryAdd(CIID=>$SourceID,EventType=>'relation_added',NewValue=>$Target->{ci_number}.' '.$Target->{name},RelatedCIID=>$TargetID,User=>$User,Source=>'application');
    $Self->_HistoryAdd(CIID=>$TargetID,EventType=>'relation_added',NewValue=>$Source->{ci_number}.' '.$Source->{name},RelatedCIID=>$SourceID,User=>$User,Source=>'application');
    if ($Self->Error() || !$Self->{DB}->Commit()) {$Self->_RollbackError();return;}
    return 1;
}

sub RelationRemove {
    my ( $Self, %Param ) = @_;
    my $ID=$Self->_ID($Param{RelationID}); my $CIID=$Self->_ID($Param{CIID}); my $User=$Param{User}||{};
    my $Row=$Self->{DB}->SelectRow('SELECT * FROM cmdb_ci_relation WHERE id=? AND (source_ci_id=? OR target_ci_id=?) LIMIT 1',$ID,$CIID,$CIID);
    return if !$Row;
    my $RelatedID=$Row->{source_ci_id}==$CIID?$Row->{target_ci_id}:$Row->{source_ci_id}; my $Related=$Self->CIGet(CIID=>$RelatedID)||{};
    my $Current=$Self->CIGet(CIID=>$CIID)||{};
    $Self->{DB}->BeginWork() || do {$Self->{LastError}=$Self->{DB}->Error();return;};
    if (!$Self->{DB}->Do('UPDATE cmdb_ci_relation SET active=0,changed_by_user_id=?,changed_at=NOW() WHERE id=?',$Self->_ID($User->{user_account_id})||1,$ID)) {$Self->_RollbackError('Translate:CMDBRelationSaveFailed');return;}
    $Self->_HistoryAdd(CIID=>$CIID,EventType=>'relation_removed',OldValue=>($Related->{ci_number}||'').' '.($Related->{name}||''),RelatedCIID=>$RelatedID,User=>$User,Source=>'application');
    $Self->_HistoryAdd(CIID=>$RelatedID,EventType=>'relation_removed',OldValue=>($Current->{ci_number}||'').' '.($Current->{name}||''),RelatedCIID=>$CIID,User=>$User,Source=>'application');
    if ($Self->Error() || !$Self->{DB}->Commit()) {$Self->_RollbackError();return;}
    return 1;
}

sub CustomerCIAccessCheck {
    my ( $Self, %Param ) = @_;
    my $CIID=$Self->_ID($Param{CIID}); my $User=$Param{User}||{};
    return if !$CIID || !( $User->{customer_id} || 0 ) || !( $User->{customer_user_id} || 0 );
    my $Row=$Self->{DB}->SelectRow(
        'SELECT 1 AS allowed FROM cmdb_ci WHERE id=? AND active=1 AND customer_visible=1 AND customer_id=? AND (customer_user_id IS NULL OR customer_user_id=?) LIMIT 1',
        $CIID,$User->{customer_id},$User->{customer_user_id},
    );
    return $Row ? 1 : undef;
}

sub CustomerCIList {
    my ( $Self, %Param ) = @_;
    my $User=$Param{User}||{}; return [] if !( $User->{customer_id}||0 ) || !( $User->{customer_user_id}||0 );
    return $Self->{DB}->SelectAll(
        'SELECT ci.id,ci.ci_number,ci.name,ct.name AS type_name
         FROM cmdb_ci ci INNER JOIN cmdb_ci_type ct ON ct.id=ci.type_id
         WHERE ci.active=1 AND ci.customer_visible=1 AND ci.customer_id=? AND (ci.customer_user_id IS NULL OR ci.customer_user_id=?)
         ORDER BY ci.name ASC,ci.ci_number ASC LIMIT 500', $User->{customer_id},$User->{customer_user_id},
    ) || [];
}

sub SearchItems {
    my ( $Self, %Param ) = @_;
    my $Result=$Self->CIList(Search=>$Param{Query},TypeID=>$Param{TypeID},CustomerID=>$Param{CustomerID},CustomerUserID=>$Param{CustomerUserID},Limit=>$Param{Limit}||30);
    return [ map {{
        id=>0+($_->{id}||0), label=>($_->{ci_number}||'').' · '.($_->{name}||''),
        meta=>join(' · ',grep {$_} ($_->{type_name},$_->{status_label},$_->{customer_name})),
        description=>join(' · ',grep {$_} ($_->{type_name},$_->{status_label},$_->{customer_name})),
        ci_number=>$_->{ci_number}||'', name=>$_->{name}||'', type_name=>$_->{type_name}||''
    }} @{ $Result->{Items}||[] } ];
}

sub CustomerSearchItems {
    my ( $Self, %Param ) = @_;
    my $Q=$Self->_Trim($Param{Query}); return [] if length($Q)<1; my $Like='%'.$Q.'%';
    return $Self->{DB}->SelectAll(
        'SELECT id,customer_number,name FROM customer WHERE active=1 AND (name LIKE ? OR customer_number LIKE ?) ORDER BY name,id LIMIT 40',$Like,$Like,
    ) || [];
}

sub CustomerUserItems {
    my ( $Self, %Param ) = @_;
    my $CID=$Self->_ID($Param{CustomerID}); return [] if !$CID;
    return $Self->{DB}->SelectAll(
        'SELECT cu.id,COALESCE(NULLIF(TRIM(CONCAT(ua.firstname," ",ua.lastname)),""),ua.login,ua.email) AS name,ua.email
         FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id
         WHERE cu.customer_id=? AND cu.active=1 AND ua.is_active=1 ORDER BY name,cu.id LIMIT 500',$CID,
    ) || [];
}

sub TicketSummaryHTML {
    my ( $Self, %Param ) = @_;
    my $Items=$Self->TicketCIList(TicketID=>$Param{TicketID}); my $CanChange=$Param{CanChange}?1:0; my $TicketID=$Self->_ID($Param{TicketID}); my $Language=$Param{Language}||'en';
    my $HTML='';
    for my $CI (@{$Items}) {
        $HTML.='<article class="qisutu-cmdb-ticket-ci"><a href="index.pl?Page=CMDBItems&amp;Action=View&amp;CIID='.int($CI->{id}).'&amp;TicketID='.$TicketID.'"><strong>'.$Self->_E($CI->{ci_number}).'</strong><span>'.$Self->_E($CI->{name}).'</span></a>';
        $HTML.='<small>'.$Self->_E(join(' · ',grep{$_}($CI->{type_name},$CI->{status_label}))).'</small>';
        if($CanChange){$HTML.='<form method="post" action="index.pl"><input type="hidden" name="Page" value="AgentTicketZoom"><input type="hidden" name="Step" value="CMDBUnlink"><input type="hidden" name="TicketID" value="'.$TicketID.'"><input type="hidden" name="CIID" value="'.int($CI->{id}).'"><button class="qisutu-button-link qisutu-button-danger-text" type="submit">'.$Self->_E($Self->_T('CMDBUnlink',$Language)).'</button></form>';}
        $HTML.='</article>';
    }
    if(!@{$Items}){$HTML='<p class="qisutu-form-hint">'.$Self->_E($Self->_T('CMDBTicketNone',$Language)).'</p>';}
    if($CanChange){$HTML.='<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-cmdb-ticket-open>'.$Self->_E($Self->_T('CMDBLink',$Language)).'</button>';}
    return $HTML;
}

sub CustomerTicketSelectionHTML {
    my ( $Self, %Param ) = @_;
    my $Items=$Self->CustomerCIList(User=>$Param{User}); return '' if !@{$Items};
    my $Selected=$Self->_ID($Param{Selected}); my $Language=$Param{Language}||'en';
    my $HTML='<div class="qisutu-form-field"><label for="qisutu-customer-cmdb-ci">'.$Self->_E($Self->_T('CMDBAffectedCI',$Language)).'</label><select id="qisutu-customer-cmdb-ci" name="CMDBCIID"><option value="">'.$Self->_E($Self->_T('CMDBNoSelection',$Language)).'</option>';
    for my $CI(@{$Items}){$HTML.='<option value="'.int($CI->{id}).'"'.($Selected==$CI->{id}?' selected':'').'>'.$Self->_E(($CI->{ci_number}||'').' · '.($CI->{name}||'').' · '.($CI->{type_name}||'')).'</option>';}
    $HTML.='</select><span class="qisutu-form-hint">'.$Self->_E($Self->_T('CMDBAffectedCIHelp',$Language)).'</span></div>';
    return $HTML;
}

sub CustomerTicketSummaryHTML {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Self->_ID( $Param{TicketID} );
    my $User = $Param{User} || {};
    return '' if !$TicketID;
    my $HTML = '';
    for my $Item ( @{ $Self->TicketCIList( TicketID => $TicketID ) } ) {
        next if !$Self->CustomerCIAccessCheck( CIID => $Item->{id}, User => $User );
        my $CI = $Self->CIGet( CIID => $Item->{id} ) || next;
        $HTML .= '<article class="qisutu-cmdb-ticket-ci"><strong>' . $Self->_E( $CI->{ci_number} ) . '</strong>'
            . '<span>' . $Self->_E( $CI->{name} ) . '</span><small>' . $Self->_E( $CI->{type_name} ) . '</small>';
        my $Details = $Self->CIDisplayHTML( CI => $CI, CustomerContext => 1, Language => $Param{Language} );
        $HTML .= '<dl class="qisutu-ticket-info-list">' . $Details . '</dl>' if $Details;
        $HTML .= '</article>';
    }
    return $HTML;
}

sub CIFieldsFormHTML {
    my ( $Self, %Param ) = @_;
    my $Fields=$Self->FieldList(TypeID=>$Param{TypeID}); my $CI=$Param{CI}||{}; my $Values=$CI->{values}||{}; my $Language=$Param{Language}||'en'; my $ReadOnly=$Param{ReadOnly}?1:0; my $HTML='';
    my $LastGroup='__start__';
    for my $F(@{$Fields}){my $ID=int($F->{id});my $Name='CMDBField_'.$ID;my $Value=defined $Values->{$ID}?$Values->{$ID}:($F->{default_value}||'');my $Req=$F->{is_required}?' required':'';my $Disabled=$ReadOnly?' disabled':'';
        my $Group=$F->{group_label}||'';if($Group ne $LastGroup){$HTML.='<div class="qisutu-cmdb-field-group-heading">'.$Self->_E($Group).'</div>' if $Group;$LastGroup=$Group;}
        $HTML.='<div class="qisutu-form-field"><label for="qisutu-cmdb-field-'.$ID.'">'.$Self->_E($F->{label}).($F->{is_required}?' *':'').'</label>';
        if($F->{field_type} eq 'textarea'){$HTML.='<textarea id="qisutu-cmdb-field-'.$ID.'" name="'.$Name.'" rows="4"'.$Req.$Disabled.'>'.$Self->_E($Value).'</textarea>';}
        elsif($F->{field_type}=~m{\A(?:dropdown|multiselect)\z}){my %Sel=map{$_=>1}split/\r?\n/,$Value;$HTML.='<select id="qisutu-cmdb-field-'.$ID.'" name="'.$Name.'"'.($F->{field_type} eq 'multiselect'?' multiple size="5"':'').$Req.$Disabled.'>';if($F->{field_type} eq 'dropdown'){$HTML.='<option value=""></option>';}for my $O(@{$F->{options}||[]}){$HTML.='<option value="'.$Self->_E($O->{option_key}).'"'.($Sel{$O->{option_key}}?' selected':'').'>'.$Self->_E($O->{option_label}).'</option>';}$HTML.='</select>';}
        elsif($F->{field_type} eq 'boolean'){$HTML.='<select id="qisutu-cmdb-field-'.$ID.'" name="'.$Name.'"'.$Req.$Disabled.'><option value=""></option><option value="1"'.($Value eq '1'?' selected':'').'>'.$Self->_E($Self->_T('AdminActiveYes',$Language)).'</option><option value="0"'.($Value eq '0'?' selected':'').'>'.$Self->_E($Self->_T('AdminActiveNo',$Language)).'</option></select>';}
        else{my %Input=(integer=>'number',decimal=>'number',date=>'date',datetime=>'datetime-local',email=>'email',url=>'url');my $T=$Input{$F->{field_type}}||'text';$HTML.='<input id="qisutu-cmdb-field-'.$ID.'" type="'.$T.'" name="'.$Name.'" value="'.$Self->_E($Value).'"'.($F->{field_type} eq 'decimal'?' step="any"':'').($F->{field_type} eq 'ip'?' inputmode="decimal"':'').$Req.$Disabled.'>';}
        if($F->{customer_visible}){$HTML.='<span class="qisutu-form-hint">'.$Self->_E($Self->_T('CMDBFieldCustomerVisible',$Language)).'</span>';}$HTML.='</div>';
    }
    return $HTML;
}

sub CIDisplayHTML {
    my ( $Self, %Param ) = @_;
    my $CI=$Param{CI}||{};my $Customer=$Param{CustomerContext}?1:0;my $Fields=$Self->FieldList(TypeID=>$CI->{type_id});my $Values=$CI->{values}||{};my $HTML='';
    for my $F(@{$Fields}){next if $Customer&&!$F->{customer_visible};my $V=$Values->{$F->{id}};next if !defined $V||$V eq '';$HTML.='<div class="qisutu-ticket-info-row"><dt>'.$Self->_E($F->{label}).'</dt><dd>'.$Self->_E($Self->_FieldDisplayValue(Field=>$F,Value=>$V)).'</dd></div>';}
    return $HTML;
}

sub HistoryList {
    my ( $Self, %Param ) = @_;
    my $CIID=$Self->_ID($Param{CIID}); return [] if !$CIID;
    return $Self->{DB}->SelectAll('SELECT * FROM cmdb_ci_history WHERE ci_id=? ORDER BY created_at DESC,id DESC LIMIT 300',$CIID)||[];
}

sub ExportRows {
    my ( $Self, %Param ) = @_;
    my $Types=$Self->TypeList(IncludeInactive=>1);my @Rows;
    for my $Type(@{$Types}){my $List=$Self->CIList(TypeID=>$Type->{id},IncludeInactive=>1,Limit=>200);my $Offset=0;while(1){$List=$Self->CIList(TypeID=>$Type->{id},IncludeInactive=>1,Limit=>200,Offset=>$Offset);last if !@{$List->{Items}};for my $Row(@{$List->{Items}}){my $CI=$Self->CIGet(CIID=>$Row->{id});push @Rows,$CI;} $Offset+=200;last if $Offset>=($List->{Count}||0);}}
    return \@Rows;
}

sub CSVParse {
    my ( $Self, %Param ) = @_;
    my $Text=$Param{Content};$Text='' if !defined $Text;$Text=~s{\A\x{FEFF}}{};my @Rows;my @Row;my $Field='';my $Quoted=0;my @Char=split//,$Text;
    for(my $i=0;$i<@Char;$i++){my $C=$Char[$i];if($Quoted){if($C eq '"'){if(($Char[$i+1]||'') eq '"'){$Field.='"';$i++;}else{$Quoted=0;}}else{$Field.=$C;}next;}if($C eq '"'&&$Field eq ''){$Quoted=1;next;}if($C eq ';'){push @Row,$Field;$Field='';next;}if($C eq "\n"){push @Row,$Field;$Field='';push @Rows,[@Row] if grep{defined$_&&$_ ne ''}@Row;@Row=();next;}next if $C eq "\r";$Field.=$C;}
    push @Row,$Field if $Field ne ''||@Row;push @Rows,[@Row] if @Row&&grep{defined$_&&$_ ne ''}@Row;return \@Rows;
}

sub CSVImport {
    my ( $Self, %Param ) = @_;
    my $Rows=$Self->CSVParse(Content=>$Param{Content});my $User=$Param{User}||{};if(@{$Rows}<2){$Self->{LastError}='Translate:CMDBImportEmpty';return;}
    my @Header=map{my $H=lc $Self->_Trim($_);$H=~s{[^a-z0-9_]+}{_}g;$H}@{$Rows->[0]};my %Index;for my $I(0..$#Header){$Index{$Header[$I]}=$I;}
    if(!exists$Index{name}||(!exists$Index{type}&&!exists$Index{type_key})){$Self->{LastError}='Translate:CMDBImportHeader';return;}
    my($Created,$Updated,$Failed)=(0,0,0);my @Error;
    ROW:for my $R(@{$Rows}[1..$#{$Rows}]){last if $Created+$Updated+$Failed>=2000;my $TypeName=exists$Index{type_key}?$Self->_Trim($R->[$Index{type_key}]):$Self->_Trim($R->[$Index{type}]);my($Type)=grep{lc($_->{type_key}||'') eq lc$TypeName||lc($_->{name}||'') eq lc$TypeName}@{$Self->TypeList(IncludeInactive=>1)};if(!$Type){$Failed++;push@Error,"Type: $TypeName";next ROW;}
        my $Existing;if(exists$Index{ci_number}&&$R->[$Index{ci_number}]){$Existing=$Self->{DB}->SelectRow('SELECT id FROM cmdb_ci WHERE ci_number=? LIMIT 1',$Self->_Trim($R->[$Index{ci_number}]));}elsif(exists$Index{source}&&exists$Index{external_id}&&$R->[$Index{source}]&&$R->[$Index{external_id}]){$Existing=$Self->{DB}->SelectRow('SELECT id FROM cmdb_ci WHERE source=? AND external_id=? LIMIT 1',$Self->_Trim($R->[$Index{source}]),$Self->_Trim($R->[$Index{external_id}]));}
        my $Old=$Existing?$Self->CIGet(CIID=>$Existing->{id}):undef;my %Req=(TypeID=>$Type->{id},Name=>$R->[$Index{name}],Status=>exists$Index{status}?$R->[$Index{status}]:($Old?$Old->{status}:''),CustomerID=>$Old?($Old->{customer_id}||0):0,CustomerUserID=>$Old?($Old->{customer_user_id}||0):0,Active=>exists$Index{active}?($R->[$Index{active}]!~m{\A(?:0|no|nein|false)\z}i):($Old?$Old->{active}:1),CustomerVisible=>exists$Index{customer_visible}?($R->[$Index{customer_visible}]=~m{\A(?:1|yes|ja|true)\z}i):($Old?$Old->{customer_visible}:0),ExternalID=>exists$Index{external_id}?$R->[$Index{external_id}]:($Old?$Old->{external_id}:'') );
        if(exists$Index{customer_number}&&$R->[$Index{customer_number}]){my $C=$Self->{DB}->SelectRow('SELECT id FROM customer WHERE customer_number=? LIMIT 1',$Self->_Trim($R->[$Index{customer_number}]));$Req{CustomerID}=$C->{id} if$C;}
        for my $F(@{$Self->FieldList(TypeID=>$Type->{id})}){my $K='field_'.($Type->{type_key}||$Type->{id}).'__'.$F->{field_key};my$Fallback='field_'.$F->{field_key};$Req{'CMDBField_'.$F->{id}}=exists$Index{$K}?$R->[$Index{$K}]:exists$Index{$Fallback}?$R->[$Index{$Fallback}]:($Old?($Old->{values}{$F->{id}}||''):'');}
        my$Source=exists$Index{source}?$Self->_Trim($R->[$Index{source}]):($Old?$Old->{source}:'csv_import');my $ID=$Self->CISave(CIID=>$Existing?$Existing->{id}:0,Request=>\%Req,User=>$User,Source=>$Source);if($ID){$Existing?$Updated++:$Created++;}else{$Failed++;push@Error,($Req{Name}||'-').': '.($Self->Error()||'error');$Self->{LastError}='';}
    }
    return {Created=>$Created,Updated=>$Updated,Failed=>$Failed,Errors=>\@Error};
}

sub _HistoryAdd {
    my ( $Self, %Param ) = @_;
    my $CIID=$Self->_ID($Param{CIID});return if !$CIID;my $User=$Param{User}||{};my $ActorID=$Self->_ID($User->{user_account_id});my $Actor=$Self->_ActorName($User);
    my $Result=$Self->{DB}->Do(
        'INSERT INTO cmdb_ci_history (ci_id,event_type,field_key,field_label,old_value,new_value,details,related_ticket_id,related_ci_id,actor_user_id,actor_name,source,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NOW())',$CIID,$Param{EventType}||'changed',$Param{FieldKey}||'',$Param{FieldLabel}||'',$Param{OldValue},$Param{NewValue},$Param{Details},$Param{RelatedTicketID},$Param{RelatedCIID},$ActorID||undef,$Actor,$Param{Source}||'application');
    if(!$Result){$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBHistorySaveFailed';return;}return 1;
}

sub _TicketHistoryAdd {
    my ( $Self, %Param ) = @_;
    my $CI=$Param{CI}||{};my $User=$Param{User}||{};my $ActorID=$Self->_ID($User->{user_account_id});my $Actor=$Self->_ActorName($User);
    my $Result=$Self->{DB}->Do(
        'INSERT INTO ticket_history (ticket_id,event_type,event_category,new_value,new_display,object_type,object_id,actor_user_id,actor_type,actor_name,source,details_text,created_at)
         VALUES (?,?,?, ?,?,?,?,?,?,?,?,?,NOW())',$Param{TicketID},$Param{EventType},'system',$CI->{id},($CI->{ci_number}||'').' · '.($CI->{name}||''),'cmdb_ci',$CI->{id},$ActorID||undef,$User->{account_type}||'agent',$Actor,$Param{Source}||'application',($CI->{type_name}||''));
    if(!$Result){$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBHistorySaveFailed';return;}return 1;
}

sub _FieldValueValid {
    my ( $Self, %Param ) = @_;my $F=$Param{Field}||{};my $V=defined$Param{Value}?$Param{Value}:'';return 1 if $V eq '';
    return $V=~m{\A-?\d+\z}?1:0 if $F->{field_type} eq 'integer';return $V=~m{\A-?(?:\d+(?:[.,]\d+)?|[.,]\d+)\z}?1:0 if $F->{field_type} eq 'decimal';return $V=~m{\A\d{4}-\d{2}-\d{2}\z}?1:0 if $F->{field_type} eq 'date';return $V=~m{\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?\z}?1:0 if $F->{field_type} eq 'datetime';return $V=~m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z}?1:0 if $F->{field_type} eq 'email';return $V=~m{\Ahttps?://}i?1:0 if $F->{field_type} eq 'url';return $V=~m{\A(?:\d{1,3}(?:\.\d{1,3}){3}|[0-9a-fA-F:]+)\z}?1:0 if $F->{field_type} eq 'ip';
    if($F->{field_type}=~m{\A(?:dropdown|multiselect)\z}){my%Allowed=map{$_->{option_key}=>1}@{$F->{options}||[]};for my $X(split/\r?\n/,$V){return 0 if !$Allowed{$X};}return 1;}return 1;
}

sub _FieldDisplayValue {
    my ( $Self, %Param ) = @_;my $F=$Param{Field}||{};my $V=$Param{Value}||'';if($F->{field_type}=~m{\A(?:dropdown|multiselect)\z}){my%L=map{$_->{option_key}=>$_->{option_label}}@{$F->{options}||[]};return join(', ',map{$L{$_}||$_}split/\r?\n/,$V);}return $V;
}

sub _ActorName { my($Self,$U)=@_;$U||={};my$N=join' ',grep{$_}($U->{firstname},$U->{lastname});return$N||$U->{login}||$U->{email}||'System'; }
sub _RollbackError { my($Self,$Fallback)=@_;$Self->{LastError}||=$Self->{DB}->Error()||$Fallback||'Translate:CMDBSaveFailed';$Self->{DB}->Rollback();return; }
sub _ID { my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int($V):0; }
sub _UInt { my($Self,$V,$D)=@_;return defined$V&&$V=~m{\A\d+\z}?int($V):($D||0); }
sub _TechnicalKey { my($Self,$V)=@_;$V=lc$Self->_Trim($V);$V=~tr{äöüß}{aous};$V=~s{[^a-z0-9_]+}{_}g;$V=~s{\A_+|_+\z}{}g;return substr($V,0,100); }
sub _Trim { my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V; }
sub _E { my($Self,$V)=@_;$V=''if!defined$V;return $Self->{Output}?$Self->{Output}->HTMLEscape($V):do{$V=~s{&}{&amp;}g;$V=~s{<}{&lt;}g;$V=~s{>}{&gt;}g;$V=~s{"}{&quot;}g;$V}; }
sub _T { my($Self,$K,$L)=@_;return$Self->{Output}?$Self->{Output}->Translate(Key=>$K,Language=>$L||'en'):$K; }

1;
