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

package CMDBItems;

use strict;
use warnings;
use utf8;

use Encode qw(decode encode);
use JSON::PP qw(encode_json);
use QisutuCMDB;
use QisutuService;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self={Config=>$Param{Config},DB=>$Param{DB},Output=>$Param{Output},Program=>$Param{Program}};
    bless$Self,$Class;return$Self;
}

sub Run {
    my($Self,%Param)=@_;my$R=$Param{Request}||{};my$User=$Param{User}||{};my$Language=$R->{Language}||'en';
    my$Object=QisutuCMDB->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output});my$Permission=$Object->PermissionLevel(User=>$User);
    my$ProgramPage=$Self->{Program}->{Name}||'CMDBItems';
    if(!$Permission->{View}){return{Template=>'CMDBItems.tt',Data=>{PageTitle=>'Translate:CMDBItemsTitle',ProgramTitle=>'Translate:CMDBItemsTitle',ProgramDescription=>'Translate:CMDBDescription',AccessDenied=>1,ShowList=>0,ErrorMessage=>'Translate:CMDBAccessDenied',ErrorClass=>''}};}

    my$Step=$R->{Step}||'';my$Action=$R->{Action}||'List';my$CIID=$Self->_ID($R->{CIID});my$ContextTicketID=$Self->_ID($R->{TicketID});
    my$TicketContextMode=$ProgramPage eq'CMDBItems'&&$ContextTicketID?1:0;my$AdminMode=$TicketContextMode?0:1;
    if($TicketContextMode){
        $Permission={View=>1,Create=>0,Change=>0,Import=>0,Admin=>0};
        my$Linked=$CIID&&$ContextTicketID?$Self->{DB}->SelectRow('SELECT 1 AS linked FROM ticket_cmdb_ci WHERE ticket_id=? AND ci_id=? LIMIT 1',$ContextTicketID,$CIID):undef;
        my$Ticket=$Linked?QisutuTicket->new(Config=>$Self->{Config},DB=>$Self->{DB},Output=>$Self->{Output})->TicketGet(TicketID=>$ContextTicketID,User=>$User,Language=>$Language):undef;
        if($Step ne''||$Action ne'View'||!$CIID||!$Ticket){return{Template=>'CMDBItems.tt',Data=>{PageTitle=>'Translate:CMDBItemsTitle',ProgramTitle=>'Translate:CMDBItemsTitle',ProgramDescription=>'Translate:CMDBDescription',AccessDenied=>1,ShowList=>0,ErrorMessage=>'Translate:CMDBAccessDenied',ErrorClass=>'',ProgramPage=>$ProgramPage}};}
    }
    if($Step eq 'Search'){
        return$Self->_JSON({success=>1,items=>$Object->SearchItems(Query=>$R->{Query},TypeID=>$R->{TypeID},CustomerID=>$R->{CustomerID},CustomerUserID=>$R->{CustomerUserID},Limit=>30)});
    }
    if($Step eq 'CustomerSearch'){
        my$Rows=$Object->CustomerSearchItems(Query=>$R->{Query});return$Self->_JSON({success=>1,items=>[map{{id=>0+($_->{id}||0),label=>($_->{name}||''),meta=>($_->{customer_number}||'')}}@{$Rows}]});
    }
    if($Step eq 'CustomerUsers'){
        my$Rows=$Object->CustomerUserItems(CustomerID=>$R->{CustomerID});return$Self->_JSON({success=>1,items=>[map{{id=>0+($_->{id}||0),label=>($_->{name}||''),meta=>($_->{email}||'')}}@{$Rows}]});
    }
    if(($R->{Action}||'') eq 'ExportCSV'){
        return{Response=>$Self->_CSVResponse(Object=>$Object,Language=>$Language)} if$Permission->{Import};
        $Object->{LastError}='Translate:CMDBAccessDenied';
    }
    if($Step eq 'CISave'){
        if(($CIID&&$Permission->{Change})||(!$CIID&&$Permission->{Create})){
            my$Saved=$Object->CISave(CIID=>$CIID,Request=>$R,User=>$User);
            return{Redirect=>'index.pl?Page='.$ProgramPage.';Action=View;CIID='.$Saved.';Status=ci_saved'}if$Saved;
            $Action=$CIID?'Edit':'Create';
        }else{$Object->{LastError}='Translate:CMDBAccessDenied';$Action=$CIID?'View':'List';}
    }
    elsif($Step eq 'CIToggle'){
        if($Permission->{Change}&&$Object->CISetActive(CIID=>$CIID,Active=>$R->{Active},User=>$User)){return{Redirect=>'index.pl?Page='.$ProgramPage.';Action=View;CIID='.$CIID.';Status=ci_toggled'};}
        $Object->{LastError}||='Translate:CMDBAccessDenied';$Action='View';
    }
    elsif($Step eq 'RelationAdd'){
        if($Permission->{Change}){my$TargetID=$Self->_ID($R->{TargetCIID});if(!$TargetID&&$R->{TargetCINumber}){my$Target=$Self->{DB}->SelectRow('SELECT id FROM cmdb_ci WHERE ci_number=? LIMIT 1',$Self->_Trim($R->{TargetCINumber}));$TargetID=$Target->{id}if$Target;}$Object->RelationAdd(SourceCIID=>$CIID,TargetCIID=>$TargetID,RelationTypeID=>$R->{RelationTypeID},Note=>$R->{RelationNote},User=>$User);return{Redirect=>'index.pl?Page='.$ProgramPage.';Action=View;CIID='.$CIID.';Status=relation_saved'}if!$Object->Error();}
        else{$Object->{LastError}='Translate:CMDBAccessDenied';}$Action='View';
    }
    elsif($Step eq 'RelationRemove'){
        if($Permission->{Change}&&$Object->RelationRemove(RelationID=>$R->{RelationID},CIID=>$CIID,User=>$User)){return{Redirect=>'index.pl?Page='.$ProgramPage.';Action=View;CIID='.$CIID.';Status=relation_removed'};}
        $Object->{LastError}||='Translate:CMDBAccessDenied';$Action='View';
    }
    elsif($Step eq 'CSVImport'){
        if($Permission->{Import}){my$Upload=$Self->_Upload($R);if($Upload&&($Upload->{ContentSize}||0)<=5*1024*1024){my$Content=$Upload->{Content};$Content=eval{decode('UTF-8',$Content,1)}||$Content;my$Result=$Object->CSVImport(Content=>$Content,User=>$User);if($Result){return{Redirect=>'index.pl?Page='.$ProgramPage.';Action=Import;Status=imported;Created='.$Result->{Created}.';Updated='.$Result->{Updated}.';Failed='.$Result->{Failed}};}}else{$Object->{LastError}='Translate:CMDBImportFileInvalid';}}
        else{$Object->{LastError}='Translate:CMDBAccessDenied';}$Action='Import';
    }

    my$CI=$CIID?$Object->CIGet(CIID=>$CIID):undef;if(($Action eq'View'||$Action eq'Edit')&&!$CI){$Action='List';$Object->{LastError}||='Translate:CMDBNotFound';}
    $Action='View'if$Action eq'Edit'&&!$Permission->{Change};$Action='List'if$Action eq'Create'&&!$Permission->{Create};$Action='List'if$Action eq'Import'&&!$Permission->{Import};
    my$TypeID=$CI?$CI->{type_id}:$Self->_ID($R->{TypeID});my$Type=$TypeID?$Object->TypeGet(TypeID=>$TypeID):undef;
    my$Types=$Object->TypeList();my$List=$Object->CIList(Search=>$R->{Search},TypeID=>$R->{FilterTypeID},Status=>$R->{FilterStatus},IncludeInactive=>$R->{IncludeInactive},Limit=>100);
    for my$Item(@{$List->{Items}}){$Item->{status_label}=$Item->{status_label}||$Item->{status}||'-';$Item->{active_label}=$Self->_T($Item->{active}?'AdminActiveYes':'AdminActiveNo',$Language);$Item->{customer_display}=$Item->{customer_name}||'-';}
    my$FieldsHTML=$Type?$Object->CIFieldsFormHTML(TypeID=>$TypeID,CI=>$CI||{},Language=>$Language,ReadOnly=>$Action eq'View'?1:0):'';
    my$Relations=$CI?$Object->RelationList(CIID=>$CIID):[];my$Tickets=$CI&&$AdminMode?$Self->_TicketRows($CIID):[];my$History=$CI&&$AdminMode?$Object->HistoryList(CIID=>$CIID):[];
    my$Services=$CI&&$AdminMode?QisutuService->new(Config=>$Self->{Config},DB=>$Self->{DB})->CIServiceList(CIID=>$CIID):[];
    for my$Relation(@{$Relations}){
        my$RelatedDisplay='<strong>'.$Self->_E($Relation->{related_ci_number}||'').'</strong> '.$Self->_E($Relation->{related_ci_name}||'');
        $Relation->{related_display_html}=$AdminMode
            ? '<a href="index.pl?Page='.$Self->_E($ProgramPage).';Action=View;CIID='.int($Relation->{related_ci_id}||0).'">'.$RelatedDisplay.'</a>'
            : $RelatedDisplay;
        $Relation->{remove_html}='';
        if($Permission->{Change}){$Relation->{remove_html}='<form method="post" action="index.pl"><input type="hidden" name="Page" value="'.$Self->_E($ProgramPage).'"><input type="hidden" name="Step" value="RelationRemove"><input type="hidden" name="CIID" value="'.int($CIID).'"><input type="hidden" name="RelationID" value="'.int($Relation->{id}||0).'"><button class="qisutu-button-link qisutu-button-danger-text" type="submit">'.$Self->_E($Self->_T('AdminRemove',$Language)).'</button></form>';}
    }
    for my$H(@{$History}){$H->{event_label}=$Self->_T('CMDBHistory_'.$H->{event_type},$Language);$H->{actor_display}=$H->{actor_name}||$Self->_T('TicketHistorySystem',$Language);$H->{change_display}=$Self->_HistoryChange($H);$H->{ticket_url}=$H->{related_ticket_id}?'index.pl?Page=AgentTicketZoom;TicketID='.$H->{related_ticket_id}:'';$H->{ticket_link_html}=$H->{ticket_url}?'<a href="'.$Self->_E($H->{ticket_url}).'">'.$Self->_E($Self->_T('CMDBOpenTicket',$Language)).'</a>':'';}
    for my$Service(@{$Services}){
        my$Name=$Self->_E($Service->{full_name}||'');
        $Service->{display_html}=$Permission->{Admin}
            ?'<a class="qisutu-table-link" href="index.pl?Page=AdminServices;Action=Edit;ServiceID='.int($Service->{id}||0).'">'.$Name.'</a>'
            :'<strong>'.$Name.'</strong>';
        $Service->{active_label}=$Self->_T($Service->{active}?'AdminActiveYes':'AdminActiveNo',$Language);
    }
    my$Notice=$Self->_Notice($R,$Language);
    my$CustomerUsers=$CI&&$CI->{customer_id}?$Object->CustomerUserItems(CustomerID=>$CI->{customer_id}):[];

    return{Template=>'CMDBItems.tt',Data=>{
        PageTitle=>'Translate:CMDBItemsTitle',ProgramTitle=>'Translate:CMDBItemsTitle',ProgramDescription=>'Translate:CMDBDescription',FormAction=>'index.pl',ProgramPage=>$ProgramPage,AdminMode=>$AdminMode,ContextTicketID=>$ContextTicketID,AccessDenied=>0,
        ShowList=>$Action eq'List'?1:0,ShowListCanImport=>$Action eq'List'&&$Permission->{Import}?1:0,ShowListCanCreate=>$Action eq'List'&&$Permission->{Create}?1:0,ShowCreate=>$Action eq'Create'?1:0,ShowView=>$Action eq'View'?1:0,ShowEdit=>$Action eq'Edit'?1:0,ShowImport=>$Action eq'Import'?1:0,ShowBack=>$Action ne'List'?1:0,ShowTypeSelection=>$Action eq'Create'&&!$Type?1:0,ShowForm=>(($Action eq'Create'&&$Type)||$Action eq'Edit')?1:0,
        CanCreate=>$Permission->{Create},CanChange=>$Permission->{Change},CanImport=>$Permission->{Import},Types=>$Types,Items=>$List->{Items},ItemCount=>$List->{Count},
        TypeOptionsHTML=>$Self->_TypeOptions($Types,$TypeID,$Language),FilterTypeOptionsHTML=>$Self->_TypeOptions($Types,$R->{FilterTypeID},$Language,1),StatusOptionsHTML=>$Self->_StatusOptions($Object,$CI?$CI->{status}:($R->{Status}||''),$Language,0,$TypeID),FilterStatusOptionsHTML=>$Self->_StatusOptions($Object,$R->{FilterStatus},$Language,1,0),
        Search=>$R->{Search}||'',IncludeInactiveChecked=>$R->{IncludeInactive}?'checked':'',SelectedTypeID=>$TypeID,HasSelectedType=>$Type?1:0,
        CIID=>$CIID,CINumber=>$CI?$CI->{ci_number}:'',CIName=>$CI?$CI->{name}:($R->{Name}||''),CIStatus=>$CI?$CI->{status}:($R->{Status}||''),CIStatusDisplay=>$CI?($CI->{status_label}||$CI->{status}||'-'):'-',CITypeName=>$CI?$CI->{type_name}:($Type?$Type->{name}:''),CITypeIcon=>$CI?$CI->{type_icon}:($Type?$Type->{icon}:'CI'),CIExternalID=>$CI?$CI->{external_id}:($R->{ExternalID}||''),CISource=>$CI?$CI->{source}:($R->{Source}||'manual'),CIActiveChecked=>!$CI||$CI->{active}?'checked':'',CICustomerVisibleChecked=>$CI&&$CI->{customer_visible}?'checked':'',
        CustomerID=>$CI?$CI->{customer_id}:($R->{CustomerID}||''),CustomerName=>$CI?$CI->{customer_name}:($R->{CustomerName}||''),CustomerUserOptionsHTML=>$Self->_CustomerUserOptions($CustomerUsers,$CI?$CI->{customer_user_id}:$R->{CustomerUserID},$Language),CIFieldsHTML=>$FieldsHTML,CIDisplayHTML=>$CI?$Object->CIDisplayHTML(CI=>$CI,Language=>$Language):'',
        Relations=>$Relations,RelationTypes=>$Object->RelationTypeList(),RelationTypeOptionsHTML=>$Self->_RelationTypeOptions($Object->RelationTypeList()),Tickets=>$Tickets,History=>$History,Services=>$Services,HasRelations=>@{$Relations}?1:0,HasTickets=>@{$Tickets}?1:0,HasHistory=>@{$History}?1:0,HasServices=>@{$Services}?1:0,
        TicketCount=>scalar@{$Tickets},RelationCount=>scalar@{$Relations},HistoryCount=>scalar@{$History},ServiceCount=>scalar@{$Services},ErrorMessage=>$Object->Error(),ErrorClass=>$Object->Error()?'':'qisutu-hidden',NoticeMessage=>$Notice,NoticeClass=>$Notice?'qisutu-form-success':'qisutu-hidden',
        ImportCreated=>$R->{Created}||0,ImportUpdated=>$R->{Updated}||0,ImportFailed=>$R->{Failed}||0,
    }};
}

sub _CSVResponse{my($Self,%P)=@_;my$O=$P{Object};my$Rows=$O->ExportRows();my$Types=$O->TypeList(IncludeInactive=>1);my@Fields;for my$T(@{$Types}){for my$F(@{$O->FieldList(TypeID=>$T->{id},IncludeInactive=>1)}){push@Fields,{%{$F},export_key=>'field_'.($T->{type_key}||$T->{id}).'__'.$F->{field_key}};}}
    my@Header=qw(ci_number type_key type name status customer_number customer_user_email customer_visible source external_id active);push@Header,map{$_->{export_key}}@Fields;my@Line=(join';',map{$Self->_CSVField($_)}@Header);
    for my$CI(@{$Rows}){my$Customer=$CI->{customer_id}?$Self->{DB}->SelectRow('SELECT customer_number FROM customer WHERE id=?',$CI->{customer_id}):{};my$CU=$CI->{customer_user_id}?$Self->{DB}->SelectRow('SELECT ua.email FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id WHERE cu.id=?',$CI->{customer_user_id}):{};my@V=($CI->{ci_number},$CI->{type_key},$CI->{type_name},$CI->{name},$CI->{status},$Customer->{customer_number},$CU->{email},$CI->{customer_visible},$CI->{source},$CI->{external_id},$CI->{active});for my$F(@Fields){push@V,$F->{type_id}==$CI->{type_id}?($CI->{values}{$F->{id}}||''):'';}push@Line,join';',map{$Self->_CSVField($_)}@V;}
    my$Body="\x{FEFF}".join("\r\n",@Line)."\r\n";return$Self->{Output}->Response(ContentType=>'text/csv; charset=UTF-8',Headers=>['Content-Disposition: attachment; filename="qisutu-cmdb.csv"','Cache-Control: no-store'],Body=>$Body);
}
sub _CSVField{my($Self,$V)=@_;$V=''if!defined$V;$V=~s{"}{""}g;return'"'.$V.'"';}
sub _Upload{my($Self,$R)=@_;my$U=$R->{__Uploads}||{};my$L=$U->{CMDBCSV};return ref$L eq'ARRAY'?$L->[0]:undef;}
sub _TicketRows{my($Self,$CIID)=@_;return$Self->{DB}->SelectAll('SELECT t.id,t.ticket_number,t.title,s.name AS state_name,tc.created_at FROM ticket_cmdb_ci tc INNER JOIN ticket t ON t.id=tc.ticket_id INNER JOIN ticket_state s ON s.id=t.state_id WHERE tc.ci_id=? ORDER BY tc.created_at DESC,tc.id DESC LIMIT 200',$CIID)||[];}
sub _TypeOptions{my($Self,$Rows,$Sel,$L,$Empty)=@_;my$H=$Empty?'<option value="">'.$Self->_E($Self->_T('CMDBAllTypes',$L)).'</option>':'';for my$R(@{$Rows||[]}){$H.='<option value="'.int($R->{id}).'"'.(($Sel||0)==$R->{id}?' selected':'').'>'.$Self->_E($R->{name}).'</option>';}return$H;}
sub _StatusOptions{my($Self,$Object,$Sel,$L,$Empty,$TypeID)=@_;my$Rows=$Object->StatusList($TypeID?(TypeID=>$TypeID):());my$H=$Empty?'<option value="">'.$Self->_E($Self->_T('CMDBAllStatuses',$L)).'</option>':'<option value=""></option>';for my$S(@{$Rows}){$H.='<option value="'.$Self->_E($S->{status_key}).'"'.(($Sel||'')eq($S->{status_key}||'')?' selected':'').'>'.$Self->_E($S->{label}).'</option>';}return$H;}
sub _RelationTypeOptions{my($Self,$R)=@_;my$H='';for my$X(@{$R||[]}){$H.='<option value="'.int($X->{id}).'">'.$Self->_E($X->{forward_label}).'</option>';}return$H;}
sub _CustomerUserOptions{my($Self,$R,$Sel,$L)=@_;my$H='<option value="">'.$Self->_E($Self->_T('CMDBCustomerAllUsers',$L)).'</option>';for my$X(@{$R||[]}){$H.='<option value="'.int($X->{id}).'"'.(($Sel||0)==$X->{id}?' selected':'').'>'.$Self->_E(($X->{name}||'').' · '.($X->{email}||'')).'</option>';}return$H;}
sub _HistoryChange{my($Self,$H)=@_;my$O=defined$H->{old_value}?$H->{old_value}:'';my$N=defined$H->{new_value}?$H->{new_value}:'';return''if$O eq''&&$N eq'';return($O||'–').' → '.($N||'–');}
sub _Notice{my($Self,$R,$L)=@_;return$Self->_T('CMDBSaved',$L)if($R->{Status}||'')eq'ci_saved';return$Self->_T('CMDBStatusChanged',$L)if($R->{Status}||'')eq'ci_toggled';return$Self->_T('CMDBRelationSaved',$L)if($R->{Status}||'')=~m{\Arelation_};return$Self->_T('CMDBImportResult',$L).' '.($R->{Created}||0).'/'.($R->{Updated}||0).'/'.($R->{Failed}||0)if($R->{Status}||'')eq'imported';return'';}
sub _JSON{my($Self,$D)=@_;return{Response=>$Self->{Output}->Response(ContentType=>'application/json; charset=UTF-8',Headers=>['Cache-Control: no-store'],Body=>encode_json($D||{}))};}
sub _ID{my($Self,$V)=@_;return defined$V&&$V=~m{\A\d+\z}&&$V>0?int$V:0;}
sub _Trim{my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V;}
sub _E{my($Self,$V)=@_;$V=''if!defined$V;return$Self->{Output}->HTMLEscape($V);}
sub _T{my($Self,$K,$L)=@_;return$Self->{Output}->Translate(Key=>$K,Language=>$L||'en');}
1;
