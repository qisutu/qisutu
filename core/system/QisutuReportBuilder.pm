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

package QisutuReportBuilder;

use strict;
use warnings;
use utf8;

use JSON::PP ();
use Time::HiRes qw(time);
use QisutuPermission;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Param{Permission} || QisutuPermission->new( Config => $Param{Config}, DB => $Param{DB} ),
        LastError  => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub Error { return $_[0]->{LastError} || ''; }

sub DefaultConfiguration {
    return {
        source       => 'tickets',
        filter_logic => 'all',
        filters      => [],
        group_by     => 'created_month',
        metrics      => ['ticket_count'],
        chart_type   => 'bar',
        sort         => 'label_asc',
        limit        => 24,
        columns      => [qw(ticket_number title queue_id state_id priority_id customer_id created_at)],
    };
}

sub Catalog {
    my ( $Self, %Param ) = @_;
    my $Definitions = $Self->_Definitions();
    my @Sources;
    for my $SourceKey (qw(tickets articles time)) {
        my $Source = $Definitions->{$SourceKey};
        push @Sources, {
            key             => $SourceKey,
            label_key       => $Source->{label_key},
            description_key => $Source->{description_key},
            fields          => [ map { $Self->_PublicDefinition($_) } @{ $Source->{field_order} } ],
            groups          => [ map { $Self->_PublicDefinition($_) } @{ $Source->{group_order} } ],
            metrics         => [ map { $Self->_PublicDefinition($_) } @{ $Source->{metric_order} } ],
            default_columns => $Source->{default_columns},
            default_group   => $Source->{default_group},
            default_metric  => $Source->{default_metric},
        };
    }
    return {
        sources => \@Sources,
        operators => [
            { key=>'eq',label_key=>'ReportOperatorEquals' }, { key=>'neq',label_key=>'ReportOperatorNotEquals' },
            { key=>'contains',label_key=>'ReportOperatorContains' }, { key=>'not_contains',label_key=>'ReportOperatorNotContains' },
            { key=>'in',label_key=>'ReportOperatorOneOf' }, { key=>'not_in',label_key=>'ReportOperatorNoneOf' },
            { key=>'between',label_key=>'ReportOperatorBetween' }, { key=>'gte',label_key=>'ReportOperatorAtLeast' },
            { key=>'lte',label_key=>'ReportOperatorAtMost' }, { key=>'empty',label_key=>'ReportOperatorEmpty' },
            { key=>'not_empty',label_key=>'ReportOperatorNotEmpty' },
        ],
        chart_types => [
            {key=>'bar',label_key=>'ReportChartBar'}, {key=>'stacked_bar',label_key=>'ReportChartStackedBar'},
            {key=>'line',label_key=>'ReportChartLine'}, {key=>'area',label_key=>'ReportChartArea'},
            {key=>'doughnut',label_key=>'ReportChartDoughnut'}, {key=>'table',label_key=>'ReportChartTable'},
            {key=>'kpi',label_key=>'ReportChartKPI'},
        ],
        sorts => [
            {key=>'label_asc',label_key=>'ReportSortLabelAsc'}, {key=>'label_desc',label_key=>'ReportSortLabelDesc'},
            {key=>'value_desc',label_key=>'ReportSortValueDesc'}, {key=>'value_asc',label_key=>'ReportSortValueAsc'},
        ],
    };
}

sub ConfigurationValidate {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Input = $Param{Configuration};
    if ( ref $Input ne 'HASH' ) {
        $Self->{LastError} = 'Translate:ReportErrorInvalidConfiguration';
        return;
    }
    my $Definitions = $Self->_Definitions();
    my $SourceKey = $Input->{source} || '';
    my $Source = $Definitions->{$SourceKey};
    if (!$Source) {
        $Self->{LastError} = 'Translate:ReportErrorInvalidSource';
        return;
    }

    my $GroupKey = $Input->{group_by} || $Source->{default_group};
    my $Group = $Source->{groups}->{$GroupKey};
    if (!$Group) {
        $Self->{LastError} = 'Translate:ReportErrorInvalidGroup';
        return;
    }
    my @MetricKeys = ref $Input->{metrics} eq 'ARRAY' ? @{ $Input->{metrics} } : ( $Input->{metrics} || '' );
    my %SeenMetric;
    @MetricKeys = grep { $_ && !$SeenMetric{$_}++ } @MetricKeys;
    @MetricKeys = ( $Source->{default_metric} ) if !@MetricKeys;
    if ( @MetricKeys > 3 || grep { !$Source->{metrics}->{$_} } @MetricKeys ) {
        $Self->{LastError} = 'Translate:ReportErrorInvalidMetric';
        return;
    }

    my %Chart = map { $_=>1 } qw(bar stacked_bar line area doughnut table kpi);
    my $ChartType = $Input->{chart_type} || 'bar';
    if ( !$Chart{$ChartType} ) {
        $Self->{LastError} = 'Translate:ReportErrorInvalidChart';
        return;
    }
    $ChartType = 'kpi' if $GroupKey eq 'none' && $ChartType eq 'doughnut';
    $ChartType = 'bar' if $ChartType eq 'doughnut' && @MetricKeys > 1;

    my %Sort = map { $_=>1 } qw(label_asc label_desc value_desc value_asc);
    my $Sort = $Input->{sort} || 'label_asc';
    $Sort = 'label_asc' if !$Sort{$Sort};
    my $Limit = $Input->{limit};
    $Limit = 25 if !defined $Limit || $Limit !~ m{\A\d+\z};
    $Limit = 5 if $Limit < 5;
    $Limit = 100 if $Limit > 100;

    my @Filters = ref $Input->{filters} eq 'ARRAY' ? @{ $Input->{filters} } : ();
    if (@Filters > 20) {
        $Self->{LastError} = 'Translate:ReportErrorTooManyFilters';
        return;
    }
    my @CleanFilters;
    FILTER:
    for my $Filter (@Filters) {
        next FILTER if ref $Filter ne 'HASH';
        my $FieldKey = $Filter->{field} || '';
        my $Field = $Source->{fields}->{$FieldKey};
        if (!$Field) {
            $Self->{LastError} = 'Translate:ReportErrorInvalidField';
            return;
        }
        my $Operator = $Filter->{operator} || 'eq';
        my %AllowedOperator = map { $_=>1 } @{ $Field->{operators} || [] };
        if (!$AllowedOperator{$Operator}) {
            $Self->{LastError} = 'Translate:ReportErrorInvalidOperator';
            return;
        }
        my @Values = ref $Filter->{values} eq 'ARRAY' ? @{ $Filter->{values} } : defined $Filter->{value} ? ( $Filter->{value} ) : ();
        @Values = map { $Self->_Trim($_) } @Values;
        @Values = grep { defined $_ && $_ ne '' } @Values;
        if ( $Operator !~ m{\A(?:empty|not_empty)\z} && !@Values ) {
            $Self->{LastError} = 'Translate:ReportErrorFilterValueMissing';
            return;
        }
        if ( $Operator eq 'between' && @Values != 2 ) {
            $Self->{LastError} = 'Translate:ReportErrorFilterValueMissing';
            return;
        }
        if ( $Field->{type} =~ m{\A(?:number|reference|boolean)\z} && grep { $_ !~ m{\A-?\d+(?:\.\d+)?\z} } @Values ) {
            $Self->{LastError} = 'Translate:ReportErrorInvalidFilterValue';
            return;
        }
        if ( $Field->{type} eq 'date' && grep { !$Self->_DateValid($_) } @Values ) {
            $Self->{LastError} = 'Translate:ReportErrorInvalidFilterValue';
            return;
        }
        my @Labels = ref $Filter->{value_labels} eq 'ARRAY' ? @{ $Filter->{value_labels} } : ();
        push @CleanFilters, { field=>$FieldKey,operator=>$Operator,values=>\@Values,value_labels=>\@Labels };
    }

    my @Columns = ref $Input->{columns} eq 'ARRAY' ? @{ $Input->{columns} } : @{ $Source->{default_columns} };
    my %SeenColumn;
    @Columns = grep { $Source->{fields}->{$_} && !$SeenColumn{$_}++ } @Columns;
    @Columns = @{ $Source->{default_columns} } if !@Columns;
    @Columns = @Columns[0..11] if @Columns > 12;

    return {
        source       => $SourceKey,
        filter_logic => ( $Input->{filter_logic} || '' ) eq 'any' ? 'any' : 'all',
        filters      => \@CleanFilters,
        group_by     => $GroupKey,
        metrics      => \@MetricKeys,
        chart_type   => $ChartType,
        sort         => $Sort,
        limit        => $Limit,
        columns      => \@Columns,
    };
}

sub Execute {
    my ( $Self, %Param ) = @_;
    my $Started = time();
    my $Config = $Self->ConfigurationValidate( Configuration=>$Param{Configuration} ) || return;
    my $User = $Param{User} || {};
    my $UserID = $Self->_ID( $User->{user_account_id} );
    if (!$UserID) { $Self->{LastError}='Translate:ReportErrorPermission'; return; }
    my $Source = $Self->_Definitions()->{ $Config->{source} };
    my $Where = $Self->_WhereBuild( Source=>$Source, Configuration=>$Config, User=>$User ) || return;
    my $Group = $Source->{groups}->{ $Config->{group_by} };
    my @Metrics = map { $Source->{metrics}->{$_} } @{ $Config->{metrics} };

    my @Select;
    my @GroupBy;
    if ( $Config->{group_by} eq 'none' ) {
        push @Select, '"total" AS group_key', '"" AS group_label';
    }
    else {
        push @Select, $Group->{key_sql} . ' AS group_key', $Group->{label_sql} . ' AS group_label';
        push @GroupBy, $Group->{key_sql};
        push @GroupBy, $Group->{label_sql} if $Group->{label_sql} ne $Group->{key_sql};
    }
    for my $Index ( 0 .. $#Metrics ) { push @Select, $Metrics[$Index]->{sql} . ' AS metric_' . ( $Index + 1 ); }
    my $SQL = 'SELECT ' . join(', ',@Select) . ' ' . $Source->{from_sql} . ' WHERE ' . $Where->{sql};
    $SQL .= ' GROUP BY ' . join(', ',@GroupBy) if @GroupBy;
    my %Order = (
        label_asc=>'group_label ASC',label_desc=>'group_label DESC',
        value_desc=>'metric_1 DESC, group_label ASC',value_asc=>'metric_1 ASC, group_label ASC',
    );
    $SQL .= ' ORDER BY ' . $Order{ $Config->{sort} } if @GroupBy;
    $SQL .= ' LIMIT ' . int( $Config->{limit} ) if @GroupBy;
    my $Rows = $Self->{DB}->SelectAll( $SQL, @{ $Where->{bind} } );
    if (!defined $Rows) { $Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorExecution'; return; }

    my @ResultRows;
    for my $Row (@{$Rows}) {
        my @Values;
        for my $Index ( 0 .. $#Metrics ) { push @Values, 0 + ( $Row->{'metric_'.($Index+1)} || 0 ); }
        push @ResultRows, { key=>defined$Row->{group_key}?"$Row->{group_key}":'',label=>defined$Row->{group_label}&&$Row->{group_label}ne''?$Row->{group_label}:'-',values=>\@Values };
    }

    my @SummarySelect;
    for my $Index ( 0 .. $#Metrics ) { push @SummarySelect, $Metrics[$Index]->{sql} . ' AS metric_' . ( $Index + 1 ); }
    my $SummaryRow = $Self->{DB}->SelectRow( 'SELECT '.join(', ',@SummarySelect).' '.$Source->{from_sql}.' WHERE '.$Where->{sql}, @{ $Where->{bind} } ) || {};
    my @SummaryValues = map { 0 + ( $SummaryRow->{'metric_'.($_+1)} || 0 ) } 0..$#Metrics;

    my $DetailLimit = defined $Param{DetailLimit} ? $Param{DetailLimit} : 200;
    $DetailLimit = 200 if $DetailLimit !~ m{\A\d+\z};
    $DetailLimit = 50000 if $DetailLimit > 50000;
    my $Details = $Self->_Details( Source=>$Source,Configuration=>$Config,Where=>$Where,Limit=>$DetailLimit );
    return if !defined $Details;
    my $Duration = int( (time()-$Started)*1000 );
    my $Limited = $DetailLimit && @{ $Details->{rows} } >= $DetailLimit ? 1 : 0;

    my $Result = {
        configuration=>$Config,rows=>\@ResultRows,summary=>\@SummaryValues,
        metrics=>[ map { {key=>$_->{key},label_key=>$_->{label_key},format=>$_->{format}||'number'} } @Metrics ],
        group=>{key=>$Group->{key},label_key=>$Group->{label_key},label=>$Group->{label}},
        details=>$Details,duration_ms=>$Duration,was_limited=>$Limited,
    };
    $Self->ExecutionLogCreate(
        ReportID=>$Param{ReportID},UserID=>$UserID,ExecutionType=>$Param{ExecutionType}||'preview',
        DataSource=>$Config->{source},ResultRows=>scalar(@{$Details->{rows}}),DurationMS=>$Duration,WasLimited=>$Limited,
    );
    return $Result;
}

sub ReportList {
    my ( $Self, %Param ) = @_;
    my $UserID=$Self->_ID($Param{UserID});return[]if!$UserID;
    my $IsAdmin=$Self->{Permission}->UserIsAdmin(UserID=>$UserID)?1:0;
    my $Rows=$Self->{DB}->SelectAll(
        'SELECT rd.*, COALESCE(NULLIF(TRIM(CONCAT(COALESCE(ua.firstname,"")," ",COALESCE(ua.lastname,""))),""),ua.login,"-") AS owner_name,
            CASE WHEN rd.owner_user_id=? THEN 1 ELSE 0 END AS is_owner
         FROM report_definition rd INNER JOIN user_account ua ON ua.id=rd.owner_user_id
         WHERE rd.active=1 AND (?=1 OR rd.owner_user_id=? OR (rd.visibility="shared" AND EXISTS(
            SELECT 1 FROM report_definition_group rdg INNER JOIN user_group_member ugm ON ugm.user_group_id=rdg.user_group_id
            INNER JOIN user_group ug ON ug.id=ugm.user_group_id
            WHERE rdg.report_definition_id=rd.id AND ugm.user_account_id=? AND ugm.active=1 AND ug.active=1)))
         ORDER BY is_owner DESC,rd.changed_at DESC,rd.name ASC,rd.id DESC',
        $UserID,$IsAdmin,$UserID,$UserID,
    )||[];
    for my$Row(@{$Rows}){$Row->{configuration}=$Self->_JSONDecode($Row->{configuration_json})||{};$Row->{is_editable}=($Row->{is_owner}||$IsAdmin)?1:0;}
    return$Rows;
}

sub ReportGet {
    my ( $Self, %Param ) = @_;
    my$ID=$Self->_ID($Param{ReportID});my$UserID=$Self->_ID($Param{UserID});return if!$ID||!$UserID;
    my$IsAdmin=$Self->{Permission}->UserIsAdmin(UserID=>$UserID)?1:0;
    my$Row=$Self->{DB}->SelectRow(
        'SELECT rd.*,COALESCE(NULLIF(TRIM(CONCAT(COALESCE(ua.firstname,"")," ",COALESCE(ua.lastname,""))),""),ua.login,"-") AS owner_name,
            CASE WHEN rd.owner_user_id=? THEN 1 ELSE 0 END AS is_owner
         FROM report_definition rd INNER JOIN user_account ua ON ua.id=rd.owner_user_id
         WHERE rd.id=? AND rd.active=1 AND (?=1 OR rd.owner_user_id=? OR (rd.visibility="shared" AND EXISTS(
            SELECT 1 FROM report_definition_group rdg INNER JOIN user_group_member ugm ON ugm.user_group_id=rdg.user_group_id
            INNER JOIN user_group ug ON ug.id=ugm.user_group_id
            WHERE rdg.report_definition_id=rd.id AND ugm.user_account_id=? AND ugm.active=1 AND ug.active=1))) LIMIT 1',
        $UserID,$ID,$IsAdmin,$UserID,$UserID,
    );
    if(!$Row){$Self->{LastError}='Translate:ReportErrorNotFound';return;}
    $Row->{configuration}=$Self->_JSONDecode($Row->{configuration_json})||{};
    $Row->{is_editable}=($Row->{is_owner}||$IsAdmin)?1:0;
    my$Groups=$Self->{DB}->SelectAll('SELECT user_group_id FROM report_definition_group WHERE report_definition_id=? ORDER BY user_group_id',$ID)||[];
    $Row->{group_ids}=[map{0+$_->{user_group_id}}@{$Groups}];
    return$Row;
}

sub ReportSave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError}='';my$UserID=$Self->_ID($Param{UserID});my$ReportID=$Self->_ID($Param{ReportID});
    my$Name=$Self->_Trim($Param{Name});my$Description=$Self->_Trim($Param{Description});
    if(!$UserID||!$Name||length($Name)>190){$Self->{LastError}='Translate:ReportErrorName';return;}
    my$Config=$Self->ConfigurationValidate(Configuration=>$Param{Configuration})||return;
    my$Visibility=($Param{Visibility}||'')eq'shared'?'shared':'private';
    my$Editable;
    if($ReportID){$Editable=$Self->ReportGet(ReportID=>$ReportID,UserID=>$UserID);if(!$Editable||!$Editable->{is_editable}){$Self->{LastError}='Translate:ReportErrorPermission';return;}}
    my$AllowedGroups=$Self->GroupList(UserID=>$UserID);my%Allowed=map{$_->{id}=>1}@{$AllowedGroups};
    my@GroupIDs=ref$Param{GroupIDs}eq'ARRAY'?@{$Param{GroupIDs}}:defined$Param{GroupIDs}?($Param{GroupIDs}):();
    my%Seen;@GroupIDs=grep{my$ID=$Self->_ID($_);$ID&&$Allowed{$ID}&&!$Seen{$ID}++}@GroupIDs;
    $Visibility='private' if!@GroupIDs;
    my$JSON=JSON::PP->new->canonical(1)->encode($Config);
    $Self->{DB}->BeginWork()||do{$Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorSave';return;};
    my$OK;
    if($ReportID){$OK=$Self->{DB}->Do('UPDATE report_definition SET name=?,description=?,data_source=?,configuration_json=?,visibility=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?', $Name,$Description,$Config->{source},$JSON,$Visibility,$UserID,$ReportID);}
    else{$OK=$Self->{DB}->Do('INSERT INTO report_definition (owner_user_id,name,description,data_source,configuration_json,visibility,active,created_by_user_id,changed_by_user_id) VALUES (?,?,?,?,?,?,1,?,?)',$UserID,$Name,$Description,$Config->{source},$JSON,$Visibility,$UserID,$UserID);$ReportID=$Self->{DB}->LastInsertID('report_definition') if$OK;}
    $OK=$Self->{DB}->Do('DELETE FROM report_definition_group WHERE report_definition_id=?',$ReportID) if$OK;
    if($OK&&$Visibility eq'shared'){for my$GroupID(@GroupIDs){$OK=$Self->{DB}->Do('INSERT INTO report_definition_group (report_definition_id,user_group_id,created_by_user_id) VALUES (?,?,?)',$ReportID,$GroupID,$UserID);last if!$OK;}}
    if(!$OK){$Self->{DB}->Rollback();$Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorSave';return;}
    $Self->{DB}->Commit()||do{$Self->{DB}->Rollback();$Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorSave';return;};
    return$ReportID;
}

sub ReportCopy {
    my($Self,%Param)=@_;my$Source=$Self->ReportGet(ReportID=>$Param{ReportID},UserID=>$Param{UserID})||return;
    return$Self->ReportSave(UserID=>$Param{UserID},Name=>($Source->{name}||'Report').' (Copy)',Description=>$Source->{description},Configuration=>$Source->{configuration},Visibility=>'private',GroupIDs=>[]);
}

sub ReportDeactivate {
    my($Self,%Param)=@_;my$Report=$Self->ReportGet(ReportID=>$Param{ReportID},UserID=>$Param{UserID})||return;
    if(!$Report->{is_editable}){$Self->{LastError}='Translate:ReportErrorPermission';return;}
    my$OK=$Self->{DB}->Do('UPDATE report_definition SET active=0,changed_by_user_id=?,changed_at=NOW() WHERE id=?',$Param{UserID},$Report->{id});
    if(!$OK){$Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorDelete';return;}return 1;
}

sub GroupList {
    my($Self,%Param)=@_;my$UserID=$Self->_ID($Param{UserID});return[]if!$UserID;
    return$Self->{DB}->SelectAll('SELECT ug.id,ug.name,ug.title AS description FROM user_group ug WHERE ug.active=1 AND ug.group_type=? ORDER BY ug.sort_order,ug.name,ug.id','agent')||[];
}

sub OptionSearch {
    my($Self,%Param)=@_;my$User=$Param{User}||{};my$UserID=$Self->_ID($User->{user_account_id});return[]if!$UserID;
    my$SourceKey=$Param{Source}||'';my$FieldKey=$Param{Field}||'';my$Search=$Self->_Trim($Param{Search});
    my$Source=$Self->_Definitions()->{$SourceKey};return[]if!$Source||!$Source->{fields}->{$FieldKey};
    my$Like='%'.$Self->_LikeEscape($Search).'%';my($SQL,@Bind);
    if($FieldKey=~m{\Adynamic:(\d+)\z}){my$Language=$Param{Language}||$Self->{Config}->{Language}->{Default}||'en';$SQL='SELECT field_option.option_key AS id,COALESCE(current_translation.option_value,field_option.option_value) AS label FROM ticket_dynamic_field_option field_option LEFT JOIN ticket_dynamic_field_option_translation current_translation ON current_translation.option_id=field_option.id AND current_translation.language=? WHERE field_option.field_id=? AND (?="" OR COALESCE(current_translation.option_value,field_option.option_value) LIKE ? ESCAPE "\\\\") ORDER BY field_option.sort_order,label,field_option.id LIMIT 50';@Bind=($Language,$1,$Search,$Like);}
    elsif($FieldKey eq'queue_id'){$SQL='SELECT id,full_name AS label FROM ticket_queue WHERE active=1 AND (?="" OR full_name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,full_name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'state_id'){$SQL='SELECT id,name AS label FROM ticket_state WHERE active=1 AND (?="" OR name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'priority_id'){$SQL='SELECT id,name AS label FROM ticket_priority WHERE active=1 AND (?="" OR name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,priority_value,name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'service_id'){$SQL='SELECT id,full_name AS label FROM service WHERE active=1 AND (?="" OR full_name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,full_name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'sla_id'){$SQL='SELECT id,name AS label FROM sla WHERE active=1 AND (?="" OR name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'activity_type_id'){$SQL='SELECT id,name AS label FROM time_accounting_activity_type WHERE active=1 AND (?="" OR name LIKE ? ESCAPE "\\\\") ORDER BY sort_order,name,id LIMIT 50';@Bind=($Search,$Like);}
    elsif($FieldKey eq'customer_id'){$SQL='SELECT c.id,c.name AS label FROM customer c WHERE c.active=1 AND (?="" OR c.name LIKE ? ESCAPE "\\\\" OR c.customer_number LIKE ? ESCAPE "\\\\") ORDER BY c.name,c.id LIMIT 50';@Bind=($Search,$Like,$Like);}
    elsif($FieldKey eq'customer_user_id'){$SQL='SELECT cu.id,COALESCE(NULLIF(TRIM(CONCAT(ua.firstname," ",ua.lastname)),""),ua.login) AS label FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id WHERE cu.active=1 AND ua.is_active=1 AND (?="" OR ua.login LIKE ? ESCAPE "\\\\" OR ua.email LIKE ? ESCAPE "\\\\" OR ua.firstname LIKE ? ESCAPE "\\\\" OR ua.lastname LIKE ? ESCAPE "\\\\") ORDER BY label,cu.id LIMIT 50';@Bind=($Search,$Like,$Like,$Like,$Like);}
    elsif($FieldKey eq'agent_user_id'||$FieldKey=~m{\A(?:owner_user_id|responsible_user_id|created_by_user_id)\z}){$SQL='SELECT ua.id,COALESCE(NULLIF(TRIM(CONCAT(ua.firstname," ",ua.lastname)),""),ua.login) AS label FROM user_account ua WHERE ua.account_type="agent" AND ua.is_active=1 AND (?="" OR ua.login LIKE ? ESCAPE "\\\\" OR ua.email LIKE ? ESCAPE "\\\\" OR ua.firstname LIKE ? ESCAPE "\\\\" OR ua.lastname LIKE ? ESCAPE "\\\\") ORDER BY label,ua.id LIMIT 50';@Bind=($Search,$Like,$Like,$Like,$Like);}
    else{return[];}
    my$Rows=$Self->{DB}->SelectAll($SQL,@Bind)||[];return[map{{id=>"$_->{id}",label=>defined$_->{label}?$_->{label}:"$_->{id}"}}@{$Rows}];
}

sub ExecutionLogCreate {
    my($Self,%Param)=@_;return if!$Self->{DB};$Self->{DB}->Do('INSERT INTO report_execution_log (report_definition_id,user_account_id,execution_type,data_source,result_rows,duration_ms,was_limited) VALUES (NULLIF(?,0),?,?,?,?,?,?)',$Param{ReportID}||0,$Param{UserID}||0,$Param{ExecutionType}||'preview',$Param{DataSource}||'',int($Param{ResultRows}||0),int($Param{DurationMS}||0),$Param{WasLimited}?1:0);return 1;
}

sub _WhereBuild {
    my($Self,%Param)=@_;my$Source=$Param{Source};my$Config=$Param{Configuration};my$User=$Param{User};
    my@Bind;my@FilterSQL;
    for my$Filter(@{$Config->{filters}}){my$Field=$Source->{fields}->{$Filter->{field}};my$SQL=$Field->{filter_sql}||$Field->{sql};my$Op=$Filter->{operator};my@Values=@{$Filter->{values}};
        if($Op eq'empty'){push@FilterSQL,'('.$SQL.' IS NULL OR '.$SQL.' = "")';}
        elsif($Op eq'not_empty'){push@FilterSQL,'('.$SQL.' IS NOT NULL AND '.$SQL.' <> "")';}
        elsif($Op eq'eq'){push@FilterSQL,$SQL.' = ?';push@Bind,$Values[0];}
        elsif($Op eq'neq'){push@FilterSQL,'('.$SQL.' IS NULL OR '.$SQL.' <> ?)';push@Bind,$Values[0];}
        elsif($Op eq'contains'){push@FilterSQL,$SQL.' LIKE ? ESCAPE "\\\\"';push@Bind,'%'.$Self->_LikeEscape($Values[0]).'%';}
        elsif($Op eq'not_contains'){push@FilterSQL,'('.$SQL.' IS NULL OR '.$SQL.' NOT LIKE ? ESCAPE "\\\\")';push@Bind,'%'.$Self->_LikeEscape($Values[0]).'%';}
        elsif($Op eq'in'||$Op eq'not_in'){my$P=join(',',map{'?'}@Values);push@FilterSQL,$SQL.($Op eq'in'?' IN (':' NOT IN (').$P.')';push@Bind,@Values;}
        elsif($Op eq'between'){push@FilterSQL,$Field->{type}eq'date'?$SQL.' >= ? AND '.$SQL.' < DATE_ADD(?, INTERVAL 1 DAY)':$SQL.' BETWEEN ? AND ?';push@Bind,@Values;}
        elsif($Op eq'gte'){push@FilterSQL,$SQL.' >= ?';push@Bind,$Values[0];}
        elsif($Op eq'lte'){push@FilterSQL,$SQL.($Field->{type}eq'date'?' < DATE_ADD(?, INTERVAL 1 DAY)':' <= ?');push@Bind,$Values[0];}
    }
    my$SQL='1=1';if(@FilterSQL){$SQL.=' AND ('.join($Config->{filter_logic}eq'any'?' OR ':' AND ',map{'('.$_.')'}@FilterSQL).')';}
    $SQL.=' AND tc.id IS NULL' if$Source->{key}eq'time';return{sql=>$SQL,bind=>\@Bind};
}

sub _Details {
    my($Self,%Param)=@_;my$Source=$Param{Source};my$Config=$Param{Configuration};my$Where=$Param{Where};my$Limit=$Param{Limit};my@Fields=map{$Source->{fields}->{$_}}@{$Config->{columns}};my@Select;
    for my$Index(0..$#Fields){push@Select,$Fields[$Index]->{sql}.' AS field_'.($Index+1);}
    my$SQL='SELECT '.join(', ',@Select).' '.$Source->{from_sql}.' WHERE '.$Where->{sql}.' ORDER BY '.$Source->{detail_order};$SQL.=' LIMIT '.int($Limit) if$Limit;
    my$Rows=$Self->{DB}->SelectAll($SQL,@{$Where->{bind}});if(!defined$Rows){$Self->{LastError}=$Self->{DB}->Error()||'Translate:ReportErrorExecution';return;}
    my@Out;for my$Row(@{$Rows}){push@Out,[map{defined$Row->{'field_'.($_+1)}?$Row->{'field_'.($_+1)}:''}0..$#Fields];}
    return{columns=>[map{{key=>$_->{key},label_key=>$_->{label_key},label=>$_->{label},type=>$_->{type}}}@Fields],rows=>\@Out};
}

sub _Definitions {
    my($Self)=@_;return$Self->{Definitions}if$Self->{Definitions};
    my@TextOps=qw(eq neq contains not_contains empty not_empty);my@OptionOps=qw(eq neq in not_in empty not_empty);my@DateOps=qw(between gte lte empty not_empty);my@NumberOps=qw(eq neq gte lte empty not_empty);
    my%TicketFields=(
        ticket_number=>{key=>'ticket_number',label_key=>'ReportFieldTicketNumber',type=>'text',sql=>'t.ticket_number',operators=>\@TextOps},title=>{key=>'title',label_key=>'ReportFieldTitle',type=>'text',sql=>'t.title',operators=>\@TextOps},
        created_at=>{key=>'created_at',label_key=>'ReportFieldCreatedAt',type=>'date',sql=>'t.created_at',operators=>\@DateOps},changed_at=>{key=>'changed_at',label_key=>'ReportFieldChangedAt',type=>'date',sql=>'t.changed_at',operators=>\@DateOps},solution_at=>{key=>'solution_at',label_key=>'ReportFieldClosedAt',type=>'date',sql=>'t.solution_at',operators=>\@DateOps},
        queue_id=>{key=>'queue_id',label_key=>'ReportFieldQueue',type=>'reference',sql=>'t.queue_id',detail_sql=>'q.full_name',operators=>\@OptionOps,option_mode=>'search'},state_id=>{key=>'state_id',label_key=>'ReportFieldStatus',type=>'reference',sql=>'t.state_id',detail_sql=>'st.name',operators=>\@OptionOps,option_mode=>'search'},state_type=>{key=>'state_type',label_key=>'ReportFieldStateType',type=>'option',sql=>'st.state_type',operators=>\@OptionOps,option_mode=>'local',options=>[map{{value=>$_,label_key=>'ReportStateType'.ucfirst($_)}}qw(new open pending closed)]},
        priority_id=>{key=>'priority_id',label_key=>'ReportFieldPriority',type=>'reference',sql=>'t.priority_id',detail_sql=>'p.name',operators=>\@OptionOps,option_mode=>'search'},customer_id=>{key=>'customer_id',label_key=>'ReportFieldCustomer',type=>'reference',sql=>'t.customer_id',detail_sql=>'c.name',operators=>\@OptionOps,option_mode=>'search'},customer_user_id=>{key=>'customer_user_id',label_key=>'ReportFieldContact',type=>'reference',sql=>'t.customer_user_id',detail_sql=>'COALESCE(NULLIF(TRIM(CONCAT(cua.firstname," ",cua.lastname)),""),cua.login)',operators=>\@OptionOps,option_mode=>'search'},
        owner_user_id=>{key=>'owner_user_id',label_key=>'ReportFieldOwner',type=>'reference',sql=>'t.owner_user_id',detail_sql=>'COALESCE(NULLIF(TRIM(CONCAT(ou.firstname," ",ou.lastname)),""),ou.login)',operators=>\@OptionOps,option_mode=>'search'},responsible_user_id=>{key=>'responsible_user_id',label_key=>'ReportFieldResponsible',type=>'reference',sql=>'t.responsible_user_id',detail_sql=>'COALESCE(NULLIF(TRIM(CONCAT(ru.firstname," ",ru.lastname)),""),ru.login)',operators=>\@OptionOps,option_mode=>'search'},
        service_id=>{key=>'service_id',label_key=>'ReportFieldService',type=>'reference',sql=>'t.service_id',detail_sql=>'srv.full_name',operators=>\@OptionOps,option_mode=>'search'},sla_id=>{key=>'sla_id',label_key=>'ReportFieldSLA',type=>'reference',sql=>'t.sla_id',detail_sql=>'COALESCE(t.sla_name_snapshot,sl.name)',operators=>\@OptionOps,option_mode=>'search'},
        escalation_state=>{key=>'escalation_state',label_key=>'ReportFieldEscalation',type=>'option',sql=>'t.escalation_state',operators=>\@OptionOps,option_mode=>'local',options=>[map{{value=>$_,label_key=>'ReportEscalation'.ucfirst($_)}}qw(normal warning escalated)]},
        sla_breached=>{key=>'sla_breached',label_key=>'ReportFieldSLABreached',type=>'boolean',sql=>'(t.sla_first_response_breached=1 OR t.sla_update_breached=1 OR t.sla_solution_breached=1)',operators=>\@OptionOps,option_mode=>'local',options=>[{value=>1,label_key=>'Yes'},{value=>0,label_key=>'No'}]},
        first_response_minutes=>{key=>'first_response_minutes',label_key=>'ReportFieldFirstResponseMinutes',type=>'number',sql=>'TIMESTAMPDIFF(MINUTE,t.created_at,t.first_response_at)',operators=>\@NumberOps},solution_minutes=>{key=>'solution_minutes',label_key=>'ReportFieldSolutionMinutes',type=>'number',sql=>'TIMESTAMPDIFF(MINUTE,t.created_at,t.solution_at)',operators=>\@NumberOps},
    );
    my$Dynamic=$Self->{DB}->SelectAll('SELECT f.id,f.name,COALESCE(tr.label,f.label,f.name) AS label,f.field_type FROM ticket_dynamic_field f LEFT JOIN ticket_dynamic_field_translation tr ON tr.field_id=f.id AND tr.language=? WHERE f.active=1 ORDER BY f.sort_order,f.id',$Self->{Config}->{Language}->{Default}||'de')||[];
    for my$Field(@{$Dynamic}){my$Key='dynamic:'.$Field->{id};my$SQL='(SELECT dfv.value_text FROM ticket_dynamic_field_value dfv WHERE dfv.ticket_id=t.id AND dfv.field_id='.int($Field->{id}).' LIMIT 1)';my$Mode=($Field->{field_type}||'')=~m{\A(?:dropdown|multiselect)\z}?'search':($Field->{field_type}||'')=~m{date}?'date':'text';my$Type=$Mode eq'date'?'date':$Mode eq'search'?'option':'text';$TicketFields{$Key}={key=>$Key,label=>$Field->{label},type=>$Type,sql=>$SQL,operators=>$Type eq'date'?\@DateOps:$Type eq'option'?\@OptionOps:\@TextOps,option_mode=>$Mode,dynamic=>1};}
    for my$F(values%TicketFields){if($F->{detail_sql}){$F->{filter_sql}=$F->{sql};$F->{sql}=$F->{detail_sql};}}
    my@TicketFieldOrder=map{$TicketFields{$_}}grep{$TicketFields{$_}}(qw(ticket_number title created_at changed_at solution_at queue_id state_id state_type priority_id customer_id customer_user_id owner_user_id responsible_user_id service_id sla_id escalation_state sla_breached first_response_minutes solution_minutes),sort grep{/^dynamic:/}keys%TicketFields);
    my%TicketGroups=(none=>{key=>'none',label_key=>'ReportGroupNone',key_sql=>'"total"',label_sql=>'""'},created_day=>{key=>'created_day',label_key=>'ReportGroupCreatedDay',key_sql=>'DATE(t.created_at)',label_sql=>'DATE_FORMAT(t.created_at,"%Y-%m-%d")'},created_week=>{key=>'created_week',label_key=>'ReportGroupCreatedWeek',key_sql=>'YEARWEEK(t.created_at,3)',label_sql=>'CONCAT(DATE_FORMAT(DATE_SUB(DATE(t.created_at),INTERVAL WEEKDAY(t.created_at) DAY),"%Y-%m-%d")," – ",DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(t.created_at),INTERVAL WEEKDAY(t.created_at) DAY),INTERVAL 6 DAY),"%Y-%m-%d"))'},created_month=>{key=>'created_month',label_key=>'ReportGroupCreatedMonth',key_sql=>'DATE_FORMAT(t.created_at,"%Y-%m")',label_sql=>'DATE_FORMAT(t.created_at,"%Y-%m")'},created_quarter=>{key=>'created_quarter',label_key=>'ReportGroupCreatedQuarter',key_sql=>'CONCAT(YEAR(t.created_at),"-Q",QUARTER(t.created_at))',label_sql=>'CONCAT(YEAR(t.created_at)," Q",QUARTER(t.created_at))'},created_year=>{key=>'created_year',label_key=>'ReportGroupCreatedYear',key_sql=>'YEAR(t.created_at)',label_sql=>'YEAR(t.created_at)'},queue=>{key=>'queue',label_key=>'ReportFieldQueue',key_sql=>'t.queue_id',label_sql=>'q.full_name'},status=>{key=>'status',label_key=>'ReportFieldStatus',key_sql=>'t.state_id',label_sql=>'st.name'},priority=>{key=>'priority',label_key=>'ReportFieldPriority',key_sql=>'t.priority_id',label_sql=>'p.name'},customer=>{key=>'customer',label_key=>'ReportFieldCustomer',key_sql=>'COALESCE(t.customer_id,0)',label_sql=>'COALESCE(c.name,"-")'},owner=>{key=>'owner',label_key=>'ReportFieldOwner',key_sql=>'COALESCE(t.owner_user_id,0)',label_sql=>'COALESCE(NULLIF(TRIM(CONCAT(ou.firstname," ",ou.lastname)),""),ou.login,"-")'},service=>{key=>'service',label_key=>'ReportFieldService',key_sql=>'COALESCE(t.service_id,0)',label_sql=>'COALESCE(srv.full_name,"-")'},sla=>{key=>'sla',label_key=>'ReportFieldSLA',key_sql=>'COALESCE(t.sla_id,0)',label_sql=>'COALESCE(t.sla_name_snapshot,sl.name,"-")'},escalation=>{key=>'escalation',label_key=>'ReportFieldEscalation',key_sql=>'t.escalation_state',label_sql=>'t.escalation_state'});
    for my$Key(grep{/^dynamic:/}keys%TicketFields){my$F=$TicketFields{$Key};$TicketGroups{$Key}={key=>$Key,label=>$F->{label},key_sql=>$F->{sql},label_sql=>'COALESCE('.$F->{sql}.',"-")'};}
    my%TicketMetrics=(ticket_count=>{key=>'ticket_count',label_key=>'ReportMetricTicketCount',sql=>'COUNT(DISTINCT t.id)',format=>'number'},open_count=>{key=>'open_count',label_key=>'ReportMetricOpenCount',sql=>'COUNT(DISTINCT CASE WHEN st.state_type<>"closed" THEN t.id END)',format=>'number'},closed_count=>{key=>'closed_count',label_key=>'ReportMetricClosedCount',sql=>'COUNT(DISTINCT CASE WHEN st.state_type="closed" THEN t.id END)',format=>'number'},new_count=>{key=>'new_count',label_key=>'ReportMetricNewCount',sql=>'COUNT(DISTINCT CASE WHEN st.state_type="new" THEN t.id END)',format=>'number'},escalated_count=>{key=>'escalated_count',label_key=>'ReportMetricEscalatedCount',sql=>'COUNT(DISTINCT CASE WHEN t.escalation_state="escalated" THEN t.id END)',format=>'number'},breached_count=>{key=>'breached_count',label_key=>'ReportMetricBreachedCount',sql=>'COUNT(DISTINCT CASE WHEN t.sla_first_response_breached=1 OR t.sla_update_breached=1 OR t.sla_solution_breached=1 THEN t.id END)',format=>'number'},sla_compliance=>{key=>'sla_compliance',label_key=>'ReportMetricSLACompliance',sql=>'COALESCE(ROUND(100*COUNT(DISTINCT CASE WHEN t.sla_id IS NOT NULL AND t.sla_first_response_breached=0 AND t.sla_update_breached=0 AND t.sla_solution_breached=0 THEN t.id END)/NULLIF(COUNT(DISTINCT CASE WHEN t.sla_id IS NOT NULL THEN t.id END),0),2),0)',format=>'percent'},avg_first_response=>{key=>'avg_first_response',label_key=>'ReportMetricAvgFirstResponse',sql=>'COALESCE(ROUND(AVG(TIMESTAMPDIFF(MINUTE,t.created_at,t.first_response_at)),2),0)',format=>'minutes'},avg_solution=>{key=>'avg_solution',label_key=>'ReportMetricAvgSolution',sql=>'COALESCE(ROUND(AVG(TIMESTAMPDIFF(MINUTE,t.created_at,t.solution_at)),2),0)',format=>'minutes'});
    my$TicketFrom='FROM ticket t INNER JOIN ticket_queue q ON q.id=t.queue_id INNER JOIN ticket_state st ON st.id=t.state_id INNER JOIN ticket_priority p ON p.id=t.priority_id LEFT JOIN customer c ON c.id=t.customer_id LEFT JOIN customer_user cu ON cu.id=t.customer_user_id LEFT JOIN user_account cua ON cua.id=cu.user_account_id LEFT JOIN user_account ou ON ou.id=t.owner_user_id LEFT JOIN user_account ru ON ru.id=t.responsible_user_id LEFT JOIN service srv ON srv.id=t.service_id LEFT JOIN sla sl ON sl.id=t.sla_id';
    my%Sources;
    $Sources{tickets}={key=>'tickets',label_key=>'ReportSourceTickets',description_key=>'ReportSourceTicketsDescription',from_sql=>$TicketFrom,fields=>\%TicketFields,field_order=>\@TicketFieldOrder,groups=>\%TicketGroups,group_order=>[map{$TicketGroups{$_}}qw(none created_day created_week created_month created_quarter created_year queue status priority customer owner service sla escalation),map{$TicketGroups{$_}}sort grep{/^dynamic:/}keys%TicketGroups],metrics=>\%TicketMetrics,metric_order=>[map{$TicketMetrics{$_}}qw(ticket_count open_count closed_count new_count escalated_count breached_count sla_compliance avg_first_response avg_solution)],default_columns=>[qw(ticket_number title queue_id state_id priority_id customer_id created_at)],default_group=>'created_month',default_metric=>'ticket_count',detail_order=>'t.created_at DESC,t.id DESC'};

    my%ArticleFields=(ticket_number=>$TicketFields{ticket_number},title=>$TicketFields{title},created_at=>{key=>'created_at',label_key=>'ReportFieldArticleCreatedAt',type=>'date',sql=>'a.created_at',operators=>\@DateOps},article_number=>{key=>'article_number',label_key=>'ReportFieldArticleNumber',type=>'number',sql=>'a.article_number',operators=>\@NumberOps},subject=>{key=>'subject',label_key=>'ReportFieldSubject',type=>'text',sql=>'a.subject',operators=>\@TextOps},channel=>{key=>'channel',label_key=>'ReportFieldChannel',type=>'option',sql=>'a.channel',operators=>\@OptionOps,option_mode=>'local',options=>[map{{value=>$_,label=>$_}}qw(email note web phone)]},sender_type=>{key=>'sender_type',label_key=>'ReportFieldSenderType',type=>'option',sql=>'a.sender_type',operators=>\@OptionOps,option_mode=>'local',options=>[map{{value=>$_,label=>$_}}qw(agent customer system)]},visibility=>{key=>'visibility',label_key=>'ReportFieldVisibility',type=>'option',sql=>'a.visibility',operators=>\@OptionOps,option_mode=>'local',options=>[map{{value=>$_,label=>$_}}qw(agent customer both)]},internal=>{key=>'internal',label_key=>'ReportFieldInternal',type=>'boolean',sql=>'a.internal',operators=>\@OptionOps,option_mode=>'local',options=>[{value=>1,label_key=>'Yes'},{value=>0,label_key=>'No'}]},queue_id=>$TicketFields{queue_id},customer_id=>$TicketFields{customer_id},created_by_user_id=>{key=>'created_by_user_id',label_key=>'ReportFieldCreatedBy',type=>'reference',sql=>'a.created_by_user_id',detail_sql=>'COALESCE(NULLIF(TRIM(CONCAT(au.firstname," ",au.lastname)),""),au.login)',operators=>\@OptionOps,option_mode=>'search'});for my$F(values%ArticleFields){$F={%{$F}};if($F->{detail_sql}){$F->{filter_sql}=$F->{sql};$F->{sql}=$F->{detail_sql};}$ArticleFields{$F->{key}}=$F;}
    for my$Key(grep{/^dynamic:/}keys%TicketFields){$ArticleFields{$Key}={%{$TicketFields{$Key}}};}
    my%ArticleGroups=(none=>$TicketGroups{none},created_day=>{key=>'created_day',label_key=>'ReportGroupArticleDay',key_sql=>'DATE(a.created_at)',label_sql=>'DATE_FORMAT(a.created_at,"%Y-%m-%d")'},created_month=>{key=>'created_month',label_key=>'ReportGroupArticleMonth',key_sql=>'DATE_FORMAT(a.created_at,"%Y-%m")',label_sql=>'DATE_FORMAT(a.created_at,"%Y-%m")'},queue=>$TicketGroups{queue},channel=>{key=>'channel',label_key=>'ReportFieldChannel',key_sql=>'a.channel',label_sql=>'a.channel'},sender_type=>{key=>'sender_type',label_key=>'ReportFieldSenderType',key_sql=>'a.sender_type',label_sql=>'a.sender_type'},customer=>$TicketGroups{customer},created_by=>{key=>'created_by',label_key=>'ReportFieldCreatedBy',key_sql=>'a.created_by_user_id',label_sql=>'COALESCE(NULLIF(TRIM(CONCAT(au.firstname," ",au.lastname)),""),au.login,"-")'});
    for my$Key(grep{/^dynamic:/}keys%TicketGroups){$ArticleGroups{$Key}={%{$TicketGroups{$Key}}};}
    my%ArticleMetrics=(article_count=>{key=>'article_count',label_key=>'ReportMetricArticleCount',sql=>'COUNT(DISTINCT a.id)',format=>'number'},distinct_tickets=>{key=>'distinct_tickets',label_key=>'ReportMetricDistinctTickets',sql=>'COUNT(DISTINCT t.id)',format=>'number'},internal_count=>{key=>'internal_count',label_key=>'ReportMetricInternalCount',sql=>'COUNT(DISTINCT CASE WHEN a.internal=1 THEN a.id END)',format=>'number'},customer_article_count=>{key=>'customer_article_count',label_key=>'ReportMetricCustomerArticleCount',sql=>'COUNT(DISTINCT CASE WHEN a.sender_type="customer" THEN a.id END)',format=>'number'});
    $Sources{articles}={key=>'articles',label_key=>'ReportSourceArticles',description_key=>'ReportSourceArticlesDescription',from_sql=>'FROM ticket_article a INNER JOIN ticket t ON t.id=a.ticket_id INNER JOIN ticket_queue q ON q.id=t.queue_id LEFT JOIN customer c ON c.id=t.customer_id LEFT JOIN user_account au ON au.id=a.created_by_user_id',fields=>\%ArticleFields,field_order=>[map{$ArticleFields{$_}}qw(ticket_number title article_number subject created_at channel sender_type visibility internal queue_id customer_id created_by_user_id),map{$ArticleFields{$_}}sort grep{/^dynamic:/}keys%ArticleFields],groups=>\%ArticleGroups,group_order=>[map{$ArticleGroups{$_}}qw(none created_day created_month queue channel sender_type customer created_by),map{$ArticleGroups{$_}}sort grep{/^dynamic:/}keys%ArticleGroups],metrics=>\%ArticleMetrics,metric_order=>[map{$ArticleMetrics{$_}}qw(article_count distinct_tickets internal_count customer_article_count)],default_columns=>[qw(ticket_number title article_number subject channel sender_type visibility created_at)],default_group=>'created_month',default_metric=>'article_count',detail_order=>'a.created_at DESC,a.id DESC'};

    my%TimeFields=(ticket_number=>$TicketFields{ticket_number},title=>$TicketFields{title},work_date=>{key=>'work_date',label_key=>'ReportFieldWorkDate',type=>'date',sql=>'ta.work_date',operators=>\@DateOps},duration_minutes=>{key=>'duration_minutes',label_key=>'ReportFieldDurationMinutes',type=>'number',sql=>'ta.duration_minutes',operators=>\@NumberOps},is_billable=>{key=>'is_billable',label_key=>'ReportFieldBillable',type=>'boolean',sql=>'ta.is_billable',operators=>\@OptionOps,option_mode=>'local',options=>[{value=>1,label_key=>'Yes'},{value=>0,label_key=>'No'}]},description=>{key=>'description',label_key=>'ReportFieldDescription',type=>'text',sql=>'ta.description',operators=>\@TextOps},source=>{key=>'source',label_key=>'ReportFieldSource',type=>'text',sql=>'ta.source',operators=>\@TextOps},agent_user_id=>{key=>'agent_user_id',label_key=>'ReportFieldAgent',type=>'reference',sql=>'ta.agent_user_id',detail_sql=>'COALESCE(NULLIF(TRIM(CONCAT(ag.firstname," ",ag.lastname)),""),ag.login)',operators=>\@OptionOps,option_mode=>'search'},activity_type_id=>{key=>'activity_type_id',label_key=>'ReportFieldActivity',type=>'reference',sql=>'ta.activity_type_id',detail_sql=>'act.name',operators=>\@OptionOps,option_mode=>'search'},queue_id=>{key=>'queue_id',label_key=>'ReportFieldQueue',type=>'reference',sql=>'COALESCE(ta.queue_id_snapshot,t.queue_id)',detail_sql=>'q.full_name',operators=>\@OptionOps,option_mode=>'search'},customer_id=>{key=>'customer_id',label_key=>'ReportFieldCustomer',type=>'reference',sql=>'COALESCE(ta.customer_id_snapshot,t.customer_id)',detail_sql=>'c.name',operators=>\@OptionOps,option_mode=>'search'});for my$F(values%TimeFields){$F={%{$F}};if($F->{detail_sql}){$F->{filter_sql}=$F->{sql};$F->{sql}=$F->{detail_sql};}$TimeFields{$F->{key}}=$F;}
    for my$Key(grep{/^dynamic:/}keys%TicketFields){$TimeFields{$Key}={%{$TicketFields{$Key}}};}
    my%TimeGroups=(none=>$TicketGroups{none},work_day=>{key=>'work_day',label_key=>'ReportGroupWorkDay',key_sql=>'ta.work_date',label_sql=>'DATE_FORMAT(ta.work_date,"%Y-%m-%d")'},work_month=>{key=>'work_month',label_key=>'ReportGroupWorkMonth',key_sql=>'DATE_FORMAT(ta.work_date,"%Y-%m")',label_sql=>'DATE_FORMAT(ta.work_date,"%Y-%m")'},agent=>{key=>'agent',label_key=>'ReportFieldAgent',key_sql=>'ta.agent_user_id',label_sql=>'COALESCE(NULLIF(TRIM(CONCAT(ag.firstname," ",ag.lastname)),""),ag.login,"-")'},queue=>{key=>'queue',label_key=>'ReportFieldQueue',key_sql=>'COALESCE(ta.queue_id_snapshot,t.queue_id)',label_sql=>'q.full_name'},customer=>{key=>'customer',label_key=>'ReportFieldCustomer',key_sql=>'COALESCE(ta.customer_id_snapshot,t.customer_id,0)',label_sql=>'COALESCE(c.name,"-")'},activity=>{key=>'activity',label_key=>'ReportFieldActivity',key_sql=>'COALESCE(ta.activity_type_id,0)',label_sql=>'COALESCE(act.name,"-")'},billable=>{key=>'billable',label_key=>'ReportFieldBillable',key_sql=>'ta.is_billable',label_sql=>'CASE WHEN ta.is_billable=1 THEN "Yes" ELSE "No" END'});
    for my$Key(grep{/^dynamic:/}keys%TicketGroups){$TimeGroups{$Key}={%{$TicketGroups{$Key}}};}
    my%TimeMetrics=(entry_count=>{key=>'entry_count',label_key=>'ReportMetricTimeEntries',sql=>'COUNT(DISTINCT ta.id)',format=>'number'},distinct_tickets=>{key=>'distinct_tickets',label_key=>'ReportMetricDistinctTickets',sql=>'COUNT(DISTINCT t.id)',format=>'number'},total_minutes=>{key=>'total_minutes',label_key=>'ReportMetricTotalMinutes',sql=>'COALESCE(SUM(ta.duration_minutes),0)',format=>'minutes'},billable_minutes=>{key=>'billable_minutes',label_key=>'ReportMetricBillableMinutes',sql=>'COALESCE(SUM(CASE WHEN ta.is_billable=1 THEN ta.duration_minutes ELSE 0 END),0)',format=>'minutes'},non_billable_minutes=>{key=>'non_billable_minutes',label_key=>'ReportMetricNonBillableMinutes',sql=>'COALESCE(SUM(CASE WHEN ta.is_billable=0 THEN ta.duration_minutes ELSE 0 END),0)',format=>'minutes'},avg_minutes=>{key=>'avg_minutes',label_key=>'ReportMetricAverageMinutes',sql=>'COALESCE(ROUND(AVG(ta.duration_minutes),2),0)',format=>'minutes'});
    $Sources{time}={key=>'time',label_key=>'ReportSourceTime',description_key=>'ReportSourceTimeDescription',from_sql=>'FROM ticket_time_accounting ta INNER JOIN ticket t ON t.id=ta.ticket_id INNER JOIN ticket_queue q ON q.id=COALESCE(ta.queue_id_snapshot,t.queue_id) LEFT JOIN customer c ON c.id=COALESCE(ta.customer_id_snapshot,t.customer_id) INNER JOIN user_account ag ON ag.id=ta.agent_user_id LEFT JOIN time_accounting_activity_type act ON act.id=ta.activity_type_id LEFT JOIN ticket_time_accounting_cancellation tc ON tc.time_accounting_id=ta.id',fields=>\%TimeFields,field_order=>[map{$TimeFields{$_}}qw(ticket_number title work_date duration_minutes is_billable agent_user_id customer_id queue_id activity_type_id source description),map{$TimeFields{$_}}sort grep{/^dynamic:/}keys%TimeFields],groups=>\%TimeGroups,group_order=>[map{$TimeGroups{$_}}qw(none work_day work_month agent queue customer activity billable),map{$TimeGroups{$_}}sort grep{/^dynamic:/}keys%TimeGroups],metrics=>\%TimeMetrics,metric_order=>[map{$TimeMetrics{$_}}qw(entry_count distinct_tickets total_minutes billable_minutes non_billable_minutes avg_minutes)],default_columns=>[qw(work_date ticket_number title agent_user_id customer_id queue_id activity_type_id duration_minutes is_billable description)],default_group=>'work_month',default_metric=>'total_minutes',detail_order=>'ta.work_date DESC,ta.created_at DESC,ta.id DESC'};
    $Self->{Definitions}=\%Sources;return\%Sources;
}

sub _PublicDefinition { my($Self,$D)=@_;return{map{$_=>$D->{$_}}grep{exists$D->{$_}}qw(key label label_key type operators option_mode options format dynamic)}; }
sub _JSONDecode { my($Self,$V)=@_;return if!defined$V||$V eq'';return eval{JSON::PP->new->decode($V)}; }
sub _ID { my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int$V:0; }
sub _Trim { my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V; }
sub _LikeEscape { my($Self,$V)=@_;$V=''if!defined$V;$V=~s{([\\%_])}{\\$1}g;return$V; }
sub _DateValid { my($Self,$V)=@_;return defined$V&&$V=~m{\A\d{4}-\d{2}-\d{2}\z}?1:0; }

1;
