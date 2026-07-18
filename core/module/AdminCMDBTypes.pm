# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminCMDBTypes;

use strict;
use warnings;
use utf8;

use QisutuCMDB;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config=>$Param{Config}, DB=>$Param{DB}, Output=>$Param{Output}, Program=>$Param{Program} };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $R=$Param{Request}||{}; my $User=$Param{User}||{}; my $Language=$R->{Language}||'en';
    my $Object=QisutuCMDB->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output});
    if (!$Object->PermissionLevel(User=>$User)->{Admin}) {
        return {Template=>'AdminCMDBTypes.tt',Data=>{PageTitle=>'Translate:AdminCMDBTypesTitle',ProgramTitle=>'Translate:AdminCMDBTypesTitle',ProgramDescription=>'Translate:AdminCMDBTypesDescription',ShowList=>0,ErrorMessage=>'Translate:CMDBAccessDenied',ErrorClass=>'',NoticeClass=>'qisutu-hidden'}};
    }
    my $Action=$R->{Action}||'List'; my $Step=$R->{Step}||''; my $TypeID=$Self->_ID($R->{TypeID}); my $FieldID=$Self->_ID($R->{FieldID});

    if($Step eq 'TypeSave'){
        $TypeID=$Object->TypeSave(TypeID=>$TypeID,TypeKey=>$R->{TypeKey},Name=>$R->{Name},Description=>$R->{Description},Icon=>$R->{Icon},Active=>$R->{Active},SortOrder=>$R->{SortOrder},ChangedByUserID=>$User->{user_account_id})||0;
        return {Redirect=>'index.pl?Page=AdminCMDBTypes;Action=Edit;TypeID='.$TypeID.';Status=type_saved'} if $TypeID&&!$Object->Error();
        $Action=$TypeID?'Edit':'Create';
    }
    elsif($Step eq 'TypeToggle'){
        if($Object->TypeSetActive(TypeID=>$TypeID,Active=>$R->{Active},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Status=type_toggled'};}
        $Action='List';
    }
    elsif($Step eq 'FieldSave'){
        $FieldID=$Object->FieldSave(FieldID=>$FieldID,TypeID=>$TypeID,GroupID=>$R->{GroupID},FieldKey=>$R->{FieldKey},Label=>$R->{Label},FieldType=>$R->{FieldType},IsRequired=>$R->{IsRequired},IsSearchable=>$R->{IsSearchable},IsUnique=>$R->{IsUnique},CustomerVisible=>$R->{CustomerVisible},DefaultValue=>$R->{DefaultValue},Active=>$R->{Active},SortOrder=>$R->{SortOrder},Options=>$Self->_Options($R->{OptionsText}),ChangedByUserID=>$User->{user_account_id})||0;
        return {Redirect=>'index.pl?Page=AdminCMDBTypes;Action=Edit;TypeID='.$TypeID.';Status=field_saved'} if $FieldID&&!$Object->Error();
        $Action=$R->{FieldID}?'FieldEdit':'Edit';
    }
    elsif($Step eq 'FieldToggle'){
        if($Object->FieldSetActive(FieldID=>$FieldID,Active=>$R->{Active},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Action=Edit;TypeID='.$TypeID.';Status=field_toggled'};}
        $Action='Edit';
    }
    elsif($Step eq 'RelationTypeSave'){
        if($Object->RelationTypeSave(Name=>$R->{RelationName},ForwardLabel=>$R->{ForwardLabel},ReverseLabel=>$R->{ReverseLabel},Active=>$R->{RelationActive},SortOrder=>$R->{RelationSortOrder},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Status=relation_saved'};}
        $Action='List';
    }
    elsif($Step eq 'RelationTypeToggle'){
        if($Object->RelationTypeSetActive(RelationTypeID=>$R->{RelationTypeID},Active=>$R->{Active},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Status=relation_saved'};}
        $Action='List';
    }
    elsif($Step eq 'StatusSave'){
        if($Object->StatusSave(StatusKey=>$R->{StatusKey},Label=>$R->{StatusLabel},StatusClass=>$R->{StatusClass},Color=>$R->{StatusColor},Active=>$R->{StatusActive},SortOrder=>$R->{StatusSortOrder},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Status=status_saved'};}
        $Action='List';
    }
    elsif($Step eq 'StatusToggle'){
        if($Object->StatusSetActive(StatusID=>$R->{StatusID},Active=>$R->{Active},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Status=status_saved'};}
        $Action='List';
    }
    elsif($Step eq 'FieldGroupSave'){
        if($Object->FieldGroupSave(TypeID=>$TypeID,GroupKey=>$R->{GroupKey},Label=>$R->{GroupLabel},Description=>$R->{GroupDescription},Active=>$R->{GroupActive},SortOrder=>$R->{GroupSortOrder},ChangedByUserID=>$User->{user_account_id})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Action=Edit;TypeID='.$TypeID.';Status=group_saved'};}
        $Action='Edit';
    }
    elsif($Step eq 'TypeStatusSave'){
        my @StatusIDs=ref$R->{StatusIDs} eq'ARRAY'?@{$R->{StatusIDs}}:defined$R->{StatusIDs}?($R->{StatusIDs}):();
        if($Object->TypeStatusSave(TypeID=>$TypeID,StatusIDs=>\@StatusIDs,DefaultStatusID=>$R->{DefaultStatusID})){return {Redirect=>'index.pl?Page=AdminCMDBTypes;Action=Edit;TypeID='.$TypeID.';Status=type_status_saved'};}
        $Action='Edit';
    }

    my $Type=$TypeID?$Object->TypeGet(TypeID=>$TypeID):undef;
    if(($Action eq 'Edit'||$Action eq 'FieldEdit')&&!$Type){$Action='List';}
    my $Field=$FieldID?$Object->FieldGet(FieldID=>$FieldID):undef;
    if($Action eq 'FieldEdit'&&(!$Field||($Field->{type_id}||0)!=$TypeID)){$Action='Edit';$Field=undef;}
    my $FieldValues=($Step eq 'FieldSave'&&$Object->Error())?{group_id=>$R->{GroupID},field_key=>$R->{FieldKey},label=>$R->{Label},field_type=>$R->{FieldType},is_required=>$R->{IsRequired}?1:0,is_searchable=>$R->{IsSearchable}?1:0,is_unique=>$R->{IsUnique}?1:0,customer_visible=>$R->{CustomerVisible}?1:0,default_value=>$R->{DefaultValue},active=>$R->{Active}?1:0,sort_order=>$R->{SortOrder}}:($Field||{});
    my $TypeValues=($Step eq 'TypeSave'&&$Object->Error())?{type_key=>$R->{TypeKey},name=>$R->{Name},description=>$R->{Description},icon=>$R->{Icon},active=>$R->{Active}?1:0,sort_order=>$R->{SortOrder}}:($Type||{});
    my $Types=$Object->TypeList(IncludeInactive=>1); for my $T(@{$Types}){$T->{active_label}=$Self->_T($T->{active}?'AdminActiveYes':'AdminActiveNo',$Language);$T->{toggle_label}=$Self->_T($T->{active}?'AdminDeactivate':'AdminActivate',$Language);$T->{toggle_value}=$T->{active}?0:1;}
    my $Fields=$Type?$Object->FieldList(TypeID=>$TypeID,IncludeInactive=>1):[];for my $F(@{$Fields}){$F->{active_label}=$Self->_T($F->{active}?'AdminActiveYes':'AdminActiveNo',$Language);$F->{required_label}=$Self->_T($F->{is_required}?'AdminActiveYes':'AdminActiveNo',$Language);$F->{customer_label}=$Self->_T($F->{customer_visible}?'AdminActiveYes':'AdminActiveNo',$Language);$F->{searchable_label}=$Self->_T($F->{is_searchable}?'AdminActiveYes':'AdminActiveNo',$Language);$F->{unique_label}=$Self->_T($F->{is_unique}?'AdminActiveYes':'AdminActiveNo',$Language);$F->{toggle_label}=$Self->_T($F->{active}?'AdminDeactivate':'AdminActivate',$Language);$F->{toggle_value}=$F->{active}?0:1;}
    my $OptionsText=$Step eq 'FieldSave'&&$Object->Error()?($R->{OptionsText}||''):$Self->_OptionsText($Field);
    my $RelationTypes=$Object->RelationTypeList(IncludeInactive=>1);
    for my $RelationType (@{$RelationTypes}) {
        $RelationType->{active_label}=$Self->_T($RelationType->{active}?'AdminActiveYes':'AdminActiveNo',$Language);
        $RelationType->{toggle_label}=$Self->_T($RelationType->{active}?'AdminDeactivate':'AdminActivate',$Language);
        $RelationType->{toggle_value}=$RelationType->{active}?0:1;
    }
    my $Statuses=$Object->StatusList(IncludeInactive=>1);for my$S(@{$Statuses}){$S->{active_label}=$Self->_T($S->{active}?'AdminActiveYes':'AdminActiveNo',$Language);$S->{toggle_label}=$Self->_T($S->{active}?'AdminDeactivate':'AdminActivate',$Language);$S->{toggle_value}=$S->{active}?0:1;}
    my $Groups=$Type?$Object->FieldGroupList(TypeID=>$TypeID,IncludeInactive=>1):[];
    my %TypeStatus;my$DefaultStatusID=0;if($Type){for my$S(@{$Self->{DB}->SelectAll('SELECT status_id,is_default FROM cmdb_ci_type_status WHERE type_id=?',$TypeID)||[]}){$TypeStatus{$S->{status_id}}=1;$DefaultStatusID=$S->{status_id}if$S->{is_default};}}
    for my$S(@{$Statuses}){$S->{type_checked}=$TypeStatus{$S->{id}}?'checked':'';}
    my $Notice=$Self->_Notice($R->{Status},$Language);

    return {Template=>'AdminCMDBTypes.tt',Data=>{
        PageTitle=>'Translate:AdminCMDBTypesTitle',ProgramTitle=>'Translate:AdminCMDBTypesTitle',ProgramDescription=>'Translate:AdminCMDBTypesDescription',
        FormAction=>'index.pl',ShowList=>$Action eq 'List'?1:0,ShowCreate=>$Action eq 'Create'?1:0,ShowEdit=>($Action eq 'Edit'||$Action eq 'FieldEdit')?1:0,ShowTypeForm=>($Action eq 'Create'||$Action eq 'Edit'||$Action eq 'FieldEdit')?1:0,ShowFieldEdit=>$Action eq 'FieldEdit'?1:0,
        Types=>$Types,TypeCount=>scalar@{$Types},TypeID=>$TypeID,TypeKey=>$TypeValues->{type_key}||'',TypeKeyReadonly=>$Type?'readonly':'',TypeName=>$TypeValues->{name}||'',TypeDescription=>$TypeValues->{description}||'',TypeIcon=>$TypeValues->{icon}||'CI',TypeSortOrder=>defined$TypeValues->{sort_order}?$TypeValues->{sort_order}:1000,TypeActiveChecked=>!exists$TypeValues->{active}||$TypeValues->{active}?'checked':'',
        Fields=>$Fields,HasFields=>@{$Fields}?1:0,FieldID=>$FieldID,FieldStep=>'FieldSave',FieldKey=>$FieldValues->{field_key}||'',FieldKeyReadonly=>$Field?'readonly':'',FieldGroupOptionsHTML=>$Self->_GroupOptions($Groups,$FieldValues->{group_id},$Language),FieldLabel=>$FieldValues->{label}||'',FieldTypeOptionsHTML=>$Self->_FieldTypeOptions($FieldValues->{field_type}||'text',$Language),FieldRequiredChecked=>$FieldValues->{is_required}?'checked':'',FieldSearchableChecked=>!exists$FieldValues->{is_searchable}||$FieldValues->{is_searchable}?'checked':'',FieldUniqueChecked=>$FieldValues->{is_unique}?'checked':'',FieldCustomerVisibleChecked=>$FieldValues->{customer_visible}?'checked':'',FieldDefaultValue=>$FieldValues->{default_value}||'',FieldActiveChecked=>!exists$FieldValues->{active}||$FieldValues->{active}?'checked':'',FieldSortOrder=>defined$FieldValues->{sort_order}?$FieldValues->{sort_order}:1000,FieldOptionsText=>$OptionsText,FieldOptionsClass=>($FieldValues->{field_type}||'')=~m{\A(?:dropdown|multiselect)\z}?'':'qisutu-hidden',
        Groups=>$Groups,HasGroups=>@{$Groups}?1:0,Statuses=>$Statuses,HasStatuses=>@{$Statuses}?1:0,DefaultStatusOptionsHTML=>$Self->_StatusOptions($Statuses,$DefaultStatusID,$Language),RelationTypes=>$RelationTypes,ErrorMessage=>$Object->Error(),ErrorClass=>$Object->Error()?'':'qisutu-hidden',NoticeMessage=>$Notice,NoticeClass=>$Notice?'qisutu-form-success':'qisutu-hidden',
    }};
}

sub _FieldTypeOptions {my($Self,$Selected,$L)=@_;my@Type=qw(text textarea integer decimal date datetime boolean dropdown multiselect email url ip);my$H='';for my$T(@Type){$H.='<option value="'.$Self->_E($T).'"'.($T eq$Selected?' selected':'').'>'.$Self->_E($Self->_T('CMDBFieldType_'.$T,$L)).'</option>';}return$H;}
sub _GroupOptions {my($Self,$Rows,$Selected,$L)=@_;my$H='<option value="">'.$Self->_E($Self->_T('CMDBNoFieldGroup',$L)).'</option>';for my$G(@{$Rows||[]}){$H.='<option value="'.int($G->{id}).'"'.(($Selected||0)==$G->{id}?' selected':'').'>'.$Self->_E($G->{label}).'</option>';}return$H;}
sub _StatusOptions {my($Self,$Rows,$Selected,$L)=@_;my$H='<option value="">'.$Self->_E($Self->_T('CMDBNoDefaultStatus',$L)).'</option>';for my$S(@{$Rows||[]}){$H.='<option value="'.int($S->{id}).'"'.(($Selected||0)==$S->{id}?' selected':'').'>'.$Self->_E($S->{label}).'</option>';}return$H;}
sub _Options {my($Self,$Text)=@_;my@O;my%Seen;for my$Line(split/\r?\n/,$Text||''){my($K,$L)=split/\|/,$Line,2;$K=$Self->_Trim($K);$L=$Self->_Trim(defined$L?$L:$K);next if!$K||!$L||$Seen{$K}++;push@O,{Key=>$K,Label=>$L};}return\@O;}
sub _OptionsText {my($Self,$F)=@_;return''if!$F;return join"\n",map{($_->{option_key}||'').'|'.($_->{option_label}||'')}@{$F->{options}||[]};}
sub _Notice {my($Self,$S,$L)=@_;my%K=(type_saved=>'CMDBTypeSaved',type_toggled=>'CMDBTypeSaved',field_saved=>'CMDBFieldSaved',field_toggled=>'CMDBFieldSaved',relation_saved=>'CMDBRelationTypeSaved',status_saved=>'CMDBStatusSaved',group_saved=>'CMDBFieldGroupSaved',type_status_saved=>'CMDBTypeStatusSaved');return$K{$S||''}?$Self->_T($K{$S},$L):'';}
sub _ID {my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int$V:0;}
sub _Trim {my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V;}
sub _E {my($Self,$V)=@_;$V=''if!defined$V;return$Self->{Output}->HTMLEscape($V);}
sub _T {my($Self,$K,$L)=@_;return$Self->{Output}->Translate(Key=>$K,Language=>$L||'en');}

1;
