# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuCMDBImport;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use QisutuCMDB;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config=>$Param{Config},DB=>$Param{DB},Output=>$Param{Output},LastError=>'' };
    bless $Self,$Class;
    return $Self;
}

sub Error { return $_[0]->{LastError} || ''; }

sub ProfileList {
    my ( $Self, %Param ) = @_;
    my $Where=$Param{IncludeInactive}?'':'WHERE p.active=1';
    return $Self->{DB}->SelectAll(
        'SELECT p.*,t.name AS fixed_type_name,
            (SELECT COUNT(*) FROM cmdb_import_mapping m WHERE m.profile_id=p.id) AS mapping_count,
            (SELECT MAX(r.started_at) FROM cmdb_import_run r WHERE r.profile_id=p.id) AS last_run_at
         FROM cmdb_import_profile p LEFT JOIN cmdb_ci_type t ON t.id=p.fixed_type_id '.$Where.' ORDER BY p.name,p.id'
    )||[];
}

sub ProfileGet {
    my($Self,%Param)=@_;my$ID=$Self->_ID($Param{ProfileID});return if!$ID;
    return$Self->{DB}->SelectRow('SELECT * FROM cmdb_import_profile WHERE id=? LIMIT 1',$ID);
}

sub ProfileSave {
    my($Self,%Param)=@_;my$ID=$Self->_ID($Param{ProfileID});my$Name=$Self->_Trim($Param{Name});my$Source=$Self->_Key($Param{SourceKey});
    my$Mode=($Param{TypeMode}||'')eq'column'?'column':'fixed';my$Fixed=$Self->_ID($Param{FixedTypeID});my$TypeColumn=$Self->_Trim($Param{TypeColumn});my$External=$Self->_Trim($Param{ExternalIDColumn});
    my$Delimiter=$Param{Delimiter};$Delimiter=','if defined$Delimiter&&$Delimiter eq'comma';$Delimiter="\t"if defined$Delimiter&&$Delimiter eq'tab';$Delimiter=';'if!defined$Delimiter||$Delimiter eq'semicolon'||length($Delimiter)!=1;
    my$Encoding=uc($Self->_Trim($Param{Encoding}));$Encoding='UTF-8'if$Encoding!~m{\A(?:UTF-8|ISO-8859-1|WINDOWS-1252)\z};
    if(!$Name||!$Source||!$External||($Mode eq'fixed'&&!$Fixed)||($Mode eq'column'&&!$TypeColumn)){$Self->{LastError}='Translate:CMDBImportProfileRequired';return;}
    my$UserID=$Self->_ID($Param{ChangedByUserID})||1;my$Max=$Self->_UInt($Param{MaxRows},100000);$Max=1000000if$Max>1000000;
    my$Result;
    if($ID){$Result=$Self->{DB}->Do('UPDATE cmdb_import_profile SET name=?,source_key=?,delimiter_char=?,encoding_name=?,type_mode=?,fixed_type_id=?,type_column=?,external_id_column=?,max_rows=?,active=?,changed_by_user_id=?,changed_at=NOW() WHERE id=?',
        $Name,$Source,$Delimiter,$Encoding,$Mode,$Fixed||undef,$TypeColumn,$External,$Max,$Param{Active}?1:0,$UserID,$ID);}
    else{$Result=$Self->{DB}->Do('INSERT INTO cmdb_import_profile (name,source_key,delimiter_char,encoding_name,type_mode,fixed_type_id,type_column,external_id_column,max_rows,active,created_by_user_id,changed_by_user_id,created_at,changed_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NOW(),NOW())',
        $Name,$Source,$Delimiter,$Encoding,$Mode,$Fixed||undef,$TypeColumn,$External,$Max,$Param{Active}?1:0,$UserID,$UserID);$ID=$Self->{DB}->LastInsertID('cmdb_import_profile')if$Result;}
    if(!$Result){$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBImportProfileSaveFailed';return;}return$ID;
}

sub MappingList {
    my($Self,%Param)=@_;my$ID=$Self->_ID($Param{ProfileID});return[]if!$ID;
    my$Rows=$Self->{DB}->SelectAll('SELECT * FROM cmdb_import_mapping WHERE profile_id=? ORDER BY sort_order,id',$ID)||[];
    for my$M(@{$Rows}){$M->{value_maps}=$Self->{DB}->SelectAll('SELECT * FROM cmdb_import_value_map WHERE mapping_id=? ORDER BY source_value',$M->{id})||[];}
    return$Rows;
}

sub MappingSave {
    my($Self,%Param)=@_;my$ProfileID=$Self->_ID($Param{ProfileID});my$Source=$Self->_Trim($Param{SourceColumn});my$Kind=$Param{TargetKind}||'';my%Kind=map{$_=>1}qw(name status customer_number customer_user_email customer_visible active field);
    my$Target=$Kind eq'field'?$Self->_Key($Param{TargetKey}):'';my$Policy=$Param{UpdatePolicy}||'always';$Policy='always'if$Policy!~m{\A(?:always|if_empty|create_only)\z};
    if(!$ProfileID||!$Source||!$Kind{$Kind}||($Kind eq'field'&&!$Target)){$Self->{LastError}='Translate:CMDBImportMappingRequired';return;}
    $Self->{DB}->BeginWork()||do{$Self->{LastError}=$Self->{DB}->Error();return;};
    my$Result=$Self->{DB}->Do('INSERT INTO cmdb_import_mapping (profile_id,source_column,target_kind,target_key,update_policy,is_required,default_value,sort_order,created_at,changed_at) VALUES (?,?,?,?,?,?,?,?,NOW(),NOW())',
        $ProfileID,$Source,$Kind,$Target,$Policy,$Param{IsRequired}?1:0,$Param{DefaultValue},$Self->_UInt($Param{SortOrder},1000));
    if(!$Result){$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBImportMappingSaveFailed';$Self->{DB}->Rollback();return;}
    my$ID=$Self->{DB}->LastInsertID('cmdb_import_mapping');
    for my$Line(split/\r?\n/,$Param{ValueMapText}||''){my($From,$To)=split/\|/,$Line,2;$From=$Self->_Trim($From);$To=$Self->_Trim(defined$To?$To:'');next if$From eq'';if(!$Self->{DB}->Do('INSERT INTO cmdb_import_value_map (mapping_id,source_value,target_value) VALUES (?,?,?)',$ID,$From,$To)){$Self->{LastError}=$Self->{DB}->Error();$Self->{DB}->Rollback();return;}}
    if(!$Self->{DB}->Commit()){$Self->{LastError}=$Self->{DB}->Error();$Self->{DB}->Rollback();return;}return$ID;
}

sub MappingDelete {
    my($Self,%Param)=@_;my$ID=$Self->_ID($Param{MappingID});my$ProfileID=$Self->_ID($Param{ProfileID});return if!$ID||!$ProfileID;
    my$Result=$Self->{DB}->Do('DELETE FROM cmdb_import_mapping WHERE id=? AND profile_id=?',$ID,$ProfileID);$Self->{LastError}=$Self->{DB}->Error()||'Translate:CMDBImportMappingSaveFailed'if!$Result;return$Result?1:undef;
}

sub RunList {
    my($Self,%Param)=@_;my$ID=$Self->_ID($Param{ProfileID});return[]if!$ID;
    return$Self->{DB}->SelectAll('SELECT * FROM cmdb_import_run WHERE profile_id=? ORDER BY started_at DESC,id DESC LIMIT 30',$ID)||[];
}

sub Import {
    my($Self,%Param)=@_;my$Profile=$Self->ProfileGet(ProfileID=>$Param{ProfileID});if(!$Profile||!$Profile->{active}){$Self->{LastError}='Translate:CMDBImportProfileNotFound';return;}
    my$Content=defined$Param{Content}?$Param{Content}:'';my$User=$Param{User}||{};my$FileName=$Self->_Trim($Param{FileName})||'cmdb.csv';
    my$RunOK=$Self->{DB}->Do('INSERT INTO cmdb_import_run (profile_id,file_name,file_sha256,run_mode,status,created_by_user_id,started_at) VALUES (?,?,?,"import","running",?,NOW())',$Profile->{id},$FileName,sha256_hex($Content),$Self->_ID($User->{user_account_id})||undef);
    if(!$RunOK){$Self->{LastError}=$Self->{DB}->Error();return;}my$RunID=$Self->{DB}->LastInsertID('cmdb_import_run');
    my$Rows=$Self->_CSVParse(Content=>$Content,Delimiter=>$Profile->{delimiter_char});my@Errors;my($Created,$Updated,$Unchanged,$Failed)=(0,0,0,0);
    if(@{$Rows}<2){push@Errors,'Empty CSV';$Failed=1;return$Self->_FinishRun($RunID,0,$Created,$Updated,$Unchanged,$Failed,\@Errors);}
    my@Header=map{$Self->_ColumnKey($_)}@{$Rows->[0]};my%Index;for my$I(0..$#Header){$Index{$Header[$I]}=$I if $Header[$I] ne '';}
    my$ExternalKey=$Self->_ColumnKey($Profile->{external_id_column});my$TypeKey=$Self->_ColumnKey($Profile->{type_column});
    if(!exists$Index{$ExternalKey}||($Profile->{type_mode}eq'column'&&!exists$Index{$TypeKey})){push@Errors,'Required profile column missing';$Failed=@{$Rows}-1;return$Self->_FinishRun($RunID,@{$Rows}-1,$Created,$Updated,$Unchanged,$Failed,\@Errors);}
    my$Mappings=$Self->MappingList(ProfileID=>$Profile->{id});my$CMDB=QisutuCMDB->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output});my$Max=$Profile->{max_rows}||100000;my$Total=0;
    ROW:for my$Row(@{$Rows}[1..$#{$Rows}]){last if$Total>=$Max;$Total++;my$ExternalID=$Self->_Trim($Row->[$Index{$ExternalKey}]);if(!$ExternalID){$Failed++;push@Errors,"Row ".($Total+1).": external ID missing";next;}
        my$Type;if($Profile->{type_mode}eq'fixed'){$Type=$CMDB->TypeGet(TypeID=>$Profile->{fixed_type_id});}else{my$Value=$Self->_Trim($Row->[$Index{$TypeKey}]);($Type)=grep{lc($_->{type_key}||'')eq lc($Value)||lc($_->{name}||'')eq lc($Value)}@{$CMDB->TypeList(IncludeInactive=>1)};}
        if(!$Type){$Failed++;push@Errors,"Row ".($Total+1).": CI type not found";next;}
        my$OldRow=$Self->{DB}->SelectRow('SELECT id FROM cmdb_ci WHERE source=? AND external_id=? LIMIT 1',$Profile->{source_key},$ExternalID);my$Old=$OldRow?$CMDB->CIGet(CIID=>$OldRow->{id}):undef;
        my%Req=(TypeID=>$Type->{id},Name=>$Old?($Old->{name}||''):'',Status=>$Old?($Old->{status}||''):'',CustomerID=>$Old?($Old->{customer_id}||0):0,CustomerUserID=>$Old?($Old->{customer_user_id}||0):0,CustomerVisible=>$Old?($Old->{customer_visible}?1:0):0,Active=>$Old?($Old->{active}?1:0):1,ExternalID=>$ExternalID);
        my%Fields=map{$_->{field_key}=>$_}@{$CMDB->FieldList(TypeID=>$Type->{id})};for my$F(values%Fields){$Req{'CMDBField_'.$F->{id}}=$Old?($Old->{values}{$F->{id}}||''):($F->{default_value}||'');}
        my$Skip=0;
        for my$Map(@{$Mappings}){my$Column=$Self->_ColumnKey($Map->{source_column});my$Value=exists$Index{$Column}?$Self->_Trim($Row->[$Index{$Column}]):'';$Value=$Map->{default_value}if$Value eq''&&defined$Map->{default_value};my%VM=map{$_->{source_value}=>$_->{target_value}}@{$Map->{value_maps}||[]};$Value=$VM{$Value}if exists$VM{$Value};
            if($Map->{is_required}&&$Value eq''){$Failed++;push@Errors,"Row ".($Total+1).": $Map->{source_column} is required";$Skip=1;last;}next if$Map->{update_policy}eq'create_only'&&$Old;
            my($Target,$Current);if($Map->{target_kind}eq'field'){my$F=$Fields{$Map->{target_key}};next if!$F;$Target='CMDBField_'.$F->{id};$Current=$Req{$Target};}elsif($Map->{target_kind}eq'customer_number'){my$C=$Value ne''?$Self->{DB}->SelectRow('SELECT id FROM customer WHERE customer_number=? LIMIT 1',$Value):undef;$Target='CustomerID';$Value=$C?$C->{id}:0;$Current=$Req{$Target};}elsif($Map->{target_kind}eq'customer_user_email'){my$CU=$Value ne''?$Self->{DB}->SelectRow('SELECT cu.id,cu.customer_id FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id WHERE ua.email=? LIMIT 1',$Value):undef;$Target='CustomerUserID';$Value=$CU?$CU->{id}:0;$Req{CustomerID}=$CU->{customer_id}if$CU;$Current=$Req{$Target};}else{$Target={name=>'Name',status=>'Status',customer_visible=>'CustomerVisible',active=>'Active'}->{$Map->{target_kind}};$Value=$Self->_Bool($Value)if$Map->{target_kind}=~m{\A(?:active|customer_visible)\z};$Current=$Req{$Target};}
            next if!$Target;next if$Map->{update_policy}eq'if_empty'&&defined$Current&&$Current ne'';$Req{$Target}=$Value;
        }
        next ROW if$Skip;
        my$ID=$CMDB->CISave(CIID=>$Old?($Old->{id}):0,Request=>\%Req,User=>$User,Source=>$Profile->{source_key});if($ID){$Old?$Updated++:$Created++;}else{$Failed++;push@Errors,"Row ".($Total+1).": ".($CMDB->Error()||'save failed');$CMDB->{LastError}='';}
    }
    return$Self->_FinishRun($RunID,$Total,$Created,$Updated,$Unchanged,$Failed,\@Errors);
}

sub _FinishRun {my($Self,$RunID,$Total,$Created,$Updated,$Unchanged,$Failed,$Errors)=@_;my$Status=$Failed?'completed_with_errors':'completed';my$Text=join"\n",@{$Errors||[]};$Text=substr($Text,0,65000);$Self->{DB}->Do('UPDATE cmdb_import_run SET status=?,total_count=?,created_count=?,updated_count=?,unchanged_count=?,failed_count=?,error_text=?,finished_at=NOW() WHERE id=?',$Status,$Total,$Created,$Updated,$Unchanged,$Failed,$Text,$RunID);return{RunID=>$RunID,Total=>$Total,Created=>$Created,Updated=>$Updated,Unchanged=>$Unchanged,Failed=>$Failed,Errors=>$Errors};}
sub _CSVParse {my($Self,%Param)=@_;my$Text=$Param{Content};my$D=$Param{Delimiter}||';';$Text=~s{\A\x{FEFF}}{};my(@Rows,@Row);my$Field='';my$Quoted=0;my@C=split//,$Text;for(my$i=0;$i<@C;$i++){my$c=$C[$i];if($Quoted){if($c eq'"'){if(($C[$i+1]||'')eq'"'){$Field.='"';$i++;}else{$Quoted=0;}}else{$Field.=$c;}next;}if($c eq'"'&&$Field eq''){$Quoted=1;next;}if($c eq$D){push@Row,$Field;$Field='';next;}if($c eq"\n"){push@Row,$Field;$Field='';push@Rows,[@Row]if grep{defined$_&&$_ ne''}@Row;@Row=();next;}next if$c eq"\r";$Field.=$c;}push@Row,$Field if$Field ne''||@Row;push@Rows,[@Row]if@Row&&grep{defined$_&&$_ ne''}@Row;return\@Rows;}
sub _Bool {my($Self,$V)=@_;return defined$V&&$V=~m{\A(?:1|yes|ja|true|on|active)\z}i?1:0;}
sub _ColumnKey {my($Self,$V)=@_;$V=lc$Self->_Trim($V);$V=~s{\s+}{_}g;return$V;}
sub _Key {my($Self,$V)=@_;$V=lc$Self->_Trim($V);$V=~tr{äöüß}{aous};$V=~s{[^a-z0-9_]+}{_}g;$V=~s{\A_+|_+\z}{}g;return substr($V,0,100);}
sub _ID {my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int$V:0;}
sub _UInt {my($Self,$V,$D)=@_;return defined$V&&$V=~m{\A\d+\z}?int$V:($D||0);}
sub _Trim {my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V;}

1;
