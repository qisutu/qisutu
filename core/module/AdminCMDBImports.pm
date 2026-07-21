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

package AdminCMDBImports;

use strict;
use warnings;
use utf8;

use Encode qw(decode);
use QisutuCMDB;
use QisutuCMDBImport;

sub new {my($Class,%Param)=@_;my$Self={Config=>$Param{Config},DB=>$Param{DB},Output=>$Param{Output},Program=>$Param{Program}};bless$Self,$Class;return$Self;}

sub Run {
    my($Self,%Param)=@_;my$R=$Param{Request}||{};my$User=$Param{User}||{};my$Language=$R->{Language}||'en';
    my$CMDB=QisutuCMDB->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output});my$Import=QisutuCMDBImport->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output});
    if(!$CMDB->PermissionLevel(User=>$User)->{Admin}){return{Template=>'AdminCMDBImports.tt',Data=>{PageTitle=>'Translate:AdminCMDBImportsTitle',ProgramTitle=>'Translate:AdminCMDBImportsTitle',ProgramDescription=>'Translate:AdminCMDBImportsDescription',AccessDenied=>1,ShowList=>0,ErrorMessage=>'Translate:CMDBAccessDenied',ErrorClass=>''}};}
    my$Action=$R->{Action}||'List';my$Step=$R->{Step}||'';my$ProfileID=$Self->_ID($R->{ProfileID});
    if($Step eq'ProfileSave'){$ProfileID=$Import->ProfileSave(ProfileID=>$ProfileID,Name=>$R->{Name},SourceKey=>$R->{SourceKey},Delimiter=>$R->{Delimiter},Encoding=>$R->{Encoding},TypeMode=>$R->{TypeMode},FixedTypeID=>$R->{FixedTypeID},TypeColumn=>$R->{TypeColumn},ExternalIDColumn=>$R->{ExternalIDColumn},MaxRows=>$R->{MaxRows},Active=>$R->{Active},ChangedByUserID=>$User->{user_account_id})||0;return{Redirect=>'index.pl?Page=AdminCMDBImports;Action=Edit;ProfileID='.$ProfileID.';Status=profile_saved'}if$ProfileID&&!$Import->Error();$Action=$ProfileID?'Edit':'Create';}
    elsif($Step eq'MappingSave'){if($Import->MappingSave(ProfileID=>$ProfileID,SourceColumn=>$R->{SourceColumn},TargetKind=>$R->{TargetKind},TargetKey=>$R->{TargetKey},UpdatePolicy=>$R->{UpdatePolicy},IsRequired=>$R->{IsRequired},DefaultValue=>$R->{DefaultValue},SortOrder=>$R->{SortOrder},ValueMapText=>$R->{ValueMapText})){return{Redirect=>'index.pl?Page=AdminCMDBImports;Action=Edit;ProfileID='.$ProfileID.';Status=mapping_saved'};}$Action='Edit';}
    elsif($Step eq'MappingDelete'){if($Import->MappingDelete(ProfileID=>$ProfileID,MappingID=>$R->{MappingID})){return{Redirect=>'index.pl?Page=AdminCMDBImports;Action=Edit;ProfileID='.$ProfileID.';Status=mapping_deleted'};}$Action='Edit';}
    elsif($Step eq'ImportRun'){my$Upload=$Self->_Upload($R);if($Upload&&($Upload->{ContentSize}||0)<=25*1024*1024){my$Profile=$Import->ProfileGet(ProfileID=>$ProfileID)||{};my$Content=$Upload->{Content};my$Encoding=$Profile->{encoding_name}||'UTF-8';$Content=eval{decode($Encoding,$Content,1)}||$Content;my$Result=$Import->Import(ProfileID=>$ProfileID,Content=>$Content,FileName=>$Upload->{Filename},User=>$User);if($Result){return{Redirect=>'index.pl?Page=AdminCMDBImports;Action=Edit;ProfileID='.$ProfileID.';Status=imported;Created='.$Result->{Created}.';Updated='.$Result->{Updated}.';Failed='.$Result->{Failed}};}}else{$Import->{LastError}='Translate:CMDBImportFileInvalid';}$Action='Edit';}
    my$Profile=$ProfileID?$Import->ProfileGet(ProfileID=>$ProfileID):undef;if($Action eq'Edit'&&!$Profile){$Action='List';}
    my$Values=$Profile||{};my$Profiles=$Import->ProfileList(IncludeInactive=>1);for my$P(@{$Profiles}){$P->{active_label}=$Self->_T($P->{active}?'AdminActiveYes':'AdminActiveNo',$Language);$P->{type_mode_label}=$P->{type_mode}eq'fixed'?($P->{fixed_type_name}||'-'):($P->{type_column}||'-');}
    my$Mappings=$Profile?$Import->MappingList(ProfileID=>$ProfileID):[];for my$M(@{$Mappings}){$M->{value_map_text}=join', ',map{($_->{source_value}||'').' → '.($_->{target_value}||'')}@{$M->{value_maps}||[]};}
    my$Runs=$Profile?$Import->RunList(ProfileID=>$ProfileID):[];my$Types=$CMDB->TypeList(IncludeInactive=>1);my$Notice=$Self->_Notice($R,$Language);
    return{Template=>'AdminCMDBImports.tt',Data=>{PageTitle=>'Translate:AdminCMDBImportsTitle',ProgramTitle=>'Translate:AdminCMDBImportsTitle',ProgramDescription=>'Translate:AdminCMDBImportsDescription',FormAction=>'index.pl',AccessDenied=>0,ShowList=>$Action eq'List'?1:0,ShowForm=>$Action eq'Create'||$Action eq'Edit'?1:0,ShowEdit=>$Action eq'Edit'?1:0,Profiles=>$Profiles,ProfileCount=>scalar@{$Profiles},ProfileID=>$ProfileID,Name=>$Values->{name}||'',SourceKey=>$Values->{source_key}||'',DelimiterOptionsHTML=>$Self->_DelimiterOptions($Values->{delimiter_char}||';'),EncodingOptionsHTML=>$Self->_EncodingOptions($Values->{encoding_name}||'UTF-8'),TypeModeOptionsHTML=>$Self->_TypeModeOptions($Values->{type_mode}||'fixed',$Language),TypeOptionsHTML=>$Self->_TypeOptions($Types,$Values->{fixed_type_id},$Language),TypeColumn=>$Values->{type_column}||'',ExternalIDColumn=>$Values->{external_id_column}||'',MaxRows=>$Values->{max_rows}||100000,ActiveChecked=>!$Profile||$Values->{active}?'checked':'',Mappings=>$Mappings,HasMappings=>@{$Mappings}?1:0,TargetKindOptionsHTML=>$Self->_TargetKindOptions($Language),UpdatePolicyOptionsHTML=>$Self->_UpdatePolicyOptions($Language),Runs=>$Runs,HasRuns=>@{$Runs}?1:0,ErrorMessage=>$Import->Error(),ErrorClass=>$Import->Error()?'':'qisutu-hidden',NoticeMessage=>$Notice,NoticeClass=>$Notice?'qisutu-form-success':'qisutu-hidden'}};
}

sub _DelimiterOptions{my($Self,$S)=@_;my@O=([';','semicolon'],[',','comma'],["\t",'tab']);return join'',map{'<option value="'.$_->[1].'"'.($S eq$_->[0]?' selected':'').'>'.($_->[1]eq'semicolon'?';':$_->[1]eq'comma'?',':'Tab').'</option>'}@O;}
sub _EncodingOptions{my($Self,$S)=@_;return join'',map{'<option value="'.$_.'"'.(uc$S eq$_?' selected':'').'>'.$_.'</option>'}qw(UTF-8 ISO-8859-1 WINDOWS-1252);}
sub _TypeModeOptions{my($Self,$S,$L)=@_;return'<option value="fixed"'.($S eq'fixed'?' selected':'').'>'.$Self->_E($Self->_T('CMDBImportFixedType',$L)).'</option><option value="column"'.($S eq'column'?' selected':'').'>'.$Self->_E($Self->_T('CMDBImportTypeFromColumn',$L)).'</option>';}
sub _TypeOptions{my($Self,$Rows,$S,$L)=@_;my$H='<option value="">'.$Self->_E($Self->_T('CMDBNoSelection',$L)).'</option>';for my$T(@{$Rows||[]}){$H.='<option value="'.int($T->{id}).'"'.(($S||0)==$T->{id}?' selected':'').'>'.$Self->_E($T->{name}).'</option>';}return$H;}
sub _TargetKindOptions{my($Self,$L)=@_;my@K=qw(name status customer_number customer_user_email customer_visible active field);return join'',map{'<option value="'.$_.'">'.$Self->_E($Self->_T('CMDBImportTarget_'.$_,$L)).'</option>'}@K;}
sub _UpdatePolicyOptions{my($Self,$L)=@_;my@K=qw(always if_empty create_only);return join'',map{'<option value="'.$_.'">'.$Self->_E($Self->_T('CMDBImportPolicy_'.$_,$L)).'</option>'}@K;}
sub _Notice{my($Self,$R,$L)=@_;my$S=$R->{Status}||'';return$Self->_T('CMDBImportProfileSaved',$L)if$S eq'profile_saved';return$Self->_T('CMDBImportMappingSaved',$L)if$S=~m{\Amapping_};return$Self->_T('CMDBImportResult',$L).' '.($R->{Created}||0).'/'.($R->{Updated}||0).'/'.($R->{Failed}||0)if$S eq'imported';return'';}
sub _Upload{my($Self,$R)=@_;my$U=$R->{__Uploads}||{};my$L=$U->{CMDBCSV};return ref$L eq'ARRAY'?$L->[0]:undef;}
sub _ID{my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int$V:0;}
sub _E{my($Self,$V)=@_;$V=''if!defined$V;return$Self->{Output}->HTMLEscape($V);}
sub _T{my($Self,$K,$L)=@_;return$Self->{Output}->Translate(Key=>$K,Language=>$L||'en');}
1;
