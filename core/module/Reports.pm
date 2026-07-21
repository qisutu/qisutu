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

package Reports;

use strict;
use warnings;
use utf8;

use JSON::PP ();
use POSIX qw(strftime);
use QisutuReportBuilder;
use QisutuReportPDF;

sub new {
    my ( $Class, %Param ) = @_;
    return bless { Config=>$Param{Config},DB=>$Param{DB},Output=>$Param{Output},Program=>$Param{Program} },$Class;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request=$Param{Request}||{};my$User=$Param{User}||{};my$Language=$Request->{Language}||$Self->{Config}->{Language}->{Default}||'en';
    my $Object=QisutuReportBuilder->new(Config=>$Self->{Config},DB=>$Self->{DB});my$Step=$Request->{Step}||'';my$Action=$Request->{Action}||'';my$UserID=$User->{user_account_id}||0;

    if($Step eq'OptionSearch'){
        my$Rows=$Object->OptionSearch(User=>$User,Source=>$Request->{Source},Field=>$Request->{Field},Search=>$Request->{Search});
        return$Self->_JSONResponse({success=>JSON::PP::true,items=>$Rows});
    }

    my$ReportID=$Request->{ReportID}||0;my$Report=$ReportID?$Object->ReportGet(ReportID=>$ReportID,UserID=>$UserID):undef;
    if($ReportID&&!$Report&&$Step!~m{\A(?:Save|Preview|ExportCSVDetail|ExportCSVAnalysis|ExportPDF)\z}){$Action='List';}
    my$Configuration=$Self->_Configuration(Request=>$Request,Report=>$Report,Object=>$Object);

    if($Step eq'Preview'){
        my$Result=$Object->Execute(Configuration=>$Configuration,User=>$User,ReportID=>$ReportID,ExecutionType=>'preview',DetailLimit=>200);
        return$Self->_JSONError($Object->Error(),$Language)if!$Result;
        $Self->_ResultTranslate(Result=>$Result,Language=>$Language);
        return$Self->_JSONResponse({success=>JSON::PP::true,result=>$Result});
    }
    if($Step eq'Save'){
        my@Groups=ref$Request->{GroupID}eq'ARRAY'?@{$Request->{GroupID}}:defined$Request->{GroupID}?($Request->{GroupID}):();
        my$ID=$Object->ReportSave(ReportID=>$ReportID,UserID=>$UserID,Name=>$Request->{Name},Description=>$Request->{Description},Visibility=>$Request->{Visibility},GroupIDs=>\@Groups,Configuration=>$Configuration);
        return{Redirect=>'index.pl?Page=Reports;Action=Edit;ReportID='.$ID.';Notice=saved'}if$ID;
        $Report||={id=>$ReportID,name=>$Request->{Name},description=>$Request->{Description},visibility=>$Request->{Visibility},configuration=>$Configuration,is_editable=>1,group_ids=>\@Groups};$Action='Edit';
    }
    elsif($Step eq'Copy'){
        my$ID=$Object->ReportCopy(ReportID=>$ReportID,UserID=>$UserID);return{Redirect=>'index.pl?Page=Reports;Action=Edit;ReportID='.$ID.';Notice=copied'}if$ID;$Action='List';
    }
    elsif($Step eq'Deactivate'){
        return{Redirect=>'index.pl?Page=Reports;Notice=deleted'}if$Object->ReportDeactivate(ReportID=>$ReportID,UserID=>$UserID);$Action='List';
    }
    elsif($Step=~m{\A(?:ExportCSVDetail|ExportCSVAnalysis|ExportPDF)\z}){
        my$Limit=$Step eq'ExportCSVDetail'?50000:200;
        my$Result=$Object->Execute(Configuration=>$Configuration,User=>$User,ReportID=>$ReportID,ExecutionType=>lc($Step),DetailLimit=>$Limit);
        if($Result){$Self->_ResultTranslate(Result=>$Result,Language=>$Language);my$Name=$Self->_Trim($Request->{Name})||($Report?$Report->{name}:'Qisutu Report');return{Response=>$Step eq'ExportPDF'?$Self->_PDFResponse(Name=>$Name,Description=>$Request->{Description}||($Report?$Report->{description}:''),Result=>$Result,Language=>$Language):$Self->_CSVResponse(Name=>$Name,Result=>$Result,Language=>$Language,Analysis=>$Step eq'ExportCSVAnalysis'?1:0)};}
        $Action=$ReportID?'Edit':'Create';
    }

    if(!$Action||$Action eq'List'){
        my$Reports=$Object->ReportList(UserID=>$UserID);my%SourceLabel=map{$_->{key}=>$Self->_T($_->{label_key},$Language)}@{$Object->Catalog()->{sources}};
        for my$Row(@{$Reports}){$Row->{source_label}=$SourceLabel{$Row->{data_source}}||$Row->{data_source};$Row->{visibility_label}=$Self->_T($Row->{visibility}eq'shared'?'ReportVisibilityShared':'ReportVisibilityPrivate',$Language);$Row->{open_url}='index.pl?Page=Reports;Action=Edit;ReportID='.$Row->{id};$Row->{action_html}='<a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="'.$Row->{open_url}.'">'.$Self->_E($Self->_T('ReportOpen',$Language)).'</a> <form method="post" action="index.pl" class="qisutu-inline-form"><input type="hidden" name="Page" value="Reports"><input type="hidden" name="Step" value="Copy"><input type="hidden" name="ReportID" value="'.int($Row->{id}).'"><button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="submit">'.$Self->_E($Self->_T('ReportCopy',$Language)).'</button></form>';if($Row->{is_editable}){$Row->{action_html}.=' <form method="post" action="index.pl" class="qisutu-inline-form" data-report-delete><input type="hidden" name="Page" value="Reports"><input type="hidden" name="Step" value="Deactivate"><input type="hidden" name="ReportID" value="'.int($Row->{id}).'"><button class="qisutu-button qisutu-button-danger qisutu-button-small" type="submit">'.$Self->_E($Self->_T('ReportDelete',$Language)).'</button></form>';}}
        return{Template=>'Reports.tt',Data=>{PageTitle=>'Translate:NavigationReports',ProgramTitle=>'Translate:NavigationReports',ProgramDescription=>'Translate:ProgramReportsDescription',IsReportList=>1,IsReportDesigner=>0,ReportList=>$Reports,HasReports=>@{$Reports}?1:0,ReportCount=>scalar@{$Reports},CreateURL=>'index.pl?Page=Reports;Action=Create',NoticeMessage=>$Self->_Notice($Request->{Notice},$Language),NoticeClass=>$Request->{Notice}?'':'qisutu-hidden',DeleteConfirm=>$Self->_T('ReportDeleteConfirm',$Language)}};
    }

    $Report||={id=>0,name=>'',description=>'',visibility=>'private',configuration=>$Configuration,is_editable=>1,group_ids=>[]};
    my$Catalog=$Self->_CatalogTranslate(Catalog=>$Object->Catalog(),Language=>$Language);my$Groups=$Object->GroupList(UserID=>$UserID);my%Selected=map{$_=>1}@{$Report->{group_ids}||[]};for my$Group(@{$Groups}){$Group->{selected}=$Selected{$Group->{id}}?'selected':'';}
    my$CanEdit=$Report->{is_editable}?1:0;my$ConfigJSON=$Self->_JSONForHTML($Configuration);my$CatalogJSON=$Self->_JSONForHTML($Catalog);
    return{Template=>'Reports.tt',Data=>{
        PageTitle=>'Translate:NavigationReports',ProgramTitle=>$Report->{name}||'Translate:ReportCreateTitle',ProgramDescription=>'Translate:ReportDesignerDescription',
        IsReportList=>0,IsReportDesigner=>1,ReportID=>$Report->{id}||0,ReportName=>$Report->{name}||'',ReportDescription=>$Report->{description}||'',
        VisibilityPrivateSelected=>($Report->{visibility}||'private')eq'private'?'selected':'',VisibilitySharedSelected=>($Report->{visibility}||'')eq'shared'?'selected':'',
        GroupOptions=>$Groups,CanEdit=>$CanEdit,ReadOnlyClass=>$CanEdit?'':'is-readonly',ReadOnlyAlertClass=>$CanEdit?'qisutu-hidden':'',SaveButtonClass=>$CanEdit?'':'qisutu-hidden',CopyButtonClass=>$Report->{id}&&!$CanEdit?'':'qisutu-hidden',
        CatalogJSON=>$CatalogJSON,ConfigurationJSON=>$ConfigJSON,OptionSearchURL=>'index.pl?Page=Reports;Step=OptionSearch',ListURL=>'index.pl?Page=Reports',
        ErrorMessage=>$Self->_ErrorText($Object->Error(),$Language),ErrorClass=>$Object->Error()?'':'qisutu-hidden',NoticeMessage=>$Self->_Notice($Request->{Notice},$Language),NoticeClass=>$Request->{Notice}?'':'qisutu-hidden',
        ReportIDField=>$Report->{id}||0,ReportOwnerLabel=>$Report->{owner_name}||'',ReportReadOnlyHint=>$CanEdit?'':$Self->_T('ReportReadOnlyHint',$Language),
        JSPreviewError=>$Self->_T('ReportPreviewError',$Language),JSNoValues=>$Self->_T('ReportNoValues',$Language),JSFilterValue=>$Self->_T('ReportFilterValue',$Language),
        JSFilterValues=>$Self->_T('ReportFilterValues',$Language),JSSelectValues=>$Self->_T('ReportSelectValues',$Language),JSSearch=>$Self->_T('Search',$Language),
        JSApply=>$Self->_T('ReportApplySelection',$Language),JSCancel=>$Self->_T('Cancel',$Language),JSNoMatches=>$Self->_T('ReportNoMatches',$Language),
        JSDeleteConfirm=>$Self->_T('ReportDeleteConfirm',$Language),JSMetricValue=>$Self->_T('ReportMetricValue',$Language),JSDetailLimited=>$Self->_T('ReportDetailLimited',$Language),
        JSMetricLimit=>$Self->_T('ReportMetricLimit',$Language),JSColumnLimit=>$Self->_T('ReportColumnLimit',$Language),JSRemove=>$Self->_T('Remove',$Language),
        DeleteConfirm=>$Self->_T('ReportDeleteConfirm',$Language),
    }};
}

sub _Configuration { my($Self,%Param)=@_;my$JSON=$Param{Request}->{ConfigurationJSON}||'';if($JSON){my$C=eval{JSON::PP->new->decode($JSON)};return$C if ref$C eq'HASH';}return$Param{Report}->{configuration}if$Param{Report}&&ref$Param{Report}->{configuration}eq'HASH';return$Param{Object}->DefaultConfiguration(); }

sub _CatalogTranslate {
    my($Self,%Param)=@_;my$Catalog=$Param{Catalog};my$Language=$Param{Language};for my$Source(@{$Catalog->{sources}}){$Source->{label}=$Self->_T($Source->{label_key},$Language);$Source->{description}=$Self->_T($Source->{description_key},$Language);for my$Kind(qw(fields groups metrics)){for my$Item(@{$Source->{$Kind}}){$Item->{label}||=$Self->_T($Item->{label_key},$Language);for my$Option(@{$Item->{options}||[]}){$Option->{label}||=$Self->_T($Option->{label_key},$Language);}}}}for my$Kind(qw(operators chart_types sorts)){for my$Item(@{$Catalog->{$Kind}}){$Item->{label}=$Self->_T($Item->{label_key},$Language);}}return$Catalog;
}

sub _ResultTranslate {
    my($Self,%Param)=@_;my$R=$Param{Result};my$L=$Param{Language};for my$M(@{$R->{metrics}||[]}){$M->{label}=$Self->_T($M->{label_key},$L);}my$G=$R->{group}||{};$G->{label}||=$Self->_T($G->{label_key},$L);
    if(($R->{configuration}->{group_by}||'')eq'billable'){for my$Row(@{$R->{rows}||[]}){$Row->{label}=$Self->_T($Row->{key}?'Yes':'No',$L);}}
    if(($R->{configuration}->{group_by}||'')eq'escalation'){for my$Row(@{$R->{rows}||[]}){my$Key='ReportEscalation'.ucfirst($Row->{key}||'normal');$Row->{label}=$Self->_T($Key,$L);}}
    my$Columns=$R->{details}->{columns}||[];for my$Index(0..$#{$Columns}){my$C=$Columns->[$Index];$C->{label}||=$Self->_T($C->{label_key},$L);if(($C->{type}||'')eq'boolean'){for my$Row(@{$R->{details}->{rows}||[]}){$Row->[$Index]=$Self->_T($Row->[$Index]?'Yes':'No',$L);}}}return$R;
}

sub _CSVResponse {
    my($Self,%Param)=@_;my$R=$Param{Result};my@Lines;if($Param{Analysis}){my@Header=($R->{group}->{label},map{$_->{label}}@{$R->{metrics}});push@Lines,join(';',map{$Self->_CSVField($_)}@Header);for my$Row(@{$R->{rows}}){push@Lines,join(';',map{$Self->_CSVField($_)}($Row->{label},@{$Row->{values}}));}}
    else{push@Lines,join(';',map{$Self->_CSVField($_->{label})}@{$R->{details}->{columns}});for my$Row(@{$R->{details}->{rows}}){push@Lines,join(';',map{$Self->_CSVField($_)}@{$Row});}}
    my$Filename=$Self->_Filename($Param{Name}).($Param{Analysis}?'-analysis':'-details').'.csv';my$Body=chr(0xFEFF).join("\r\n",@Lines)."\r\n";return$Self->{Output}->Response(Body=>$Body,ContentType=>'text/csv; charset=UTF-8',Headers=>['Content-Disposition: attachment; filename="'.$Filename.'"','Cache-Control: no-store']);
}

sub _PDFResponse {
    my($Self,%Param)=@_;my$Generated=strftime('%Y-%m-%d %H:%M:%S',localtime);my$PDF=QisutuReportPDF->new()->Create(Title=>$Param{Name},Description=>$Param{Description},GeneratedLabel=>$Self->_T('ReportGeneratedAt',$Param{Language}).' '.$Generated,FilterLabel=>$Self->_FilterSummary($Param{Result}->{configuration},$Param{Language}),ResultLabel=>$Self->_T('ReportResults',$Param{Language}),DetailLabel=>$Self->_T('ReportDetails',$Param{Language}),FooterLabel=>$Self->_T('ReportPDFConfidential',$Param{Language}),Result=>$Param{Result});return$Self->{Output}->Response(Body=>$PDF,ContentType=>'application/pdf',Headers=>['Content-Disposition: attachment; filename="'.$Self->_Filename($Param{Name}).'.pdf"','Cache-Control: no-store']);
}

sub _FilterSummary { my($Self,$C,$L)=@_;my@Parts;for my$F(@{$C->{filters}||[]}){my@V=@{$F->{value_labels}||[]};@V=@{$F->{values}||[]}if!@V;push@Parts,$F->{field}.' '.$F->{operator}.' '.join(', ',@V);}return@Parts?join(' · ',@Parts):$Self->_T('ReportNoFilters',$L); }
sub _JSONResponse { my($Self,$Data)=@_;return{Response=>$Self->{Output}->Response(ContentType=>'application/json; charset=UTF-8',Headers=>['Cache-Control: no-store'],Body=>JSON::PP->new->canonical(1)->encode($Data))}; }
sub _JSONError { my($Self,$Error,$L)=@_;$Error||='Translate:ReportErrorExecution';$Error=$Self->_T($1,$L)if$Error=~m{\ATranslate:(.+)\z};return$Self->_JSONResponse({success=>JSON::PP::false,error=>$Error}); }
sub _ErrorText { my($Self,$Error,$L)=@_;return''if!$Error;$Error=$Self->_T($1,$L)if$Error=~m{\ATranslate:(.+)\z};return$Error; }
sub _JSONForHTML { my($Self,$V)=@_;my$JSON=JSON::PP->new->canonical(1)->encode($V);$JSON=~s{<}{\\u003c}g;$JSON=~s{>}{\\u003e}g;$JSON=~s{&}{\\u0026}g;return$JSON; }
sub _CSVField { my($Self,$V)=@_;$V=''if!defined$V;$V="'$V"if$V=~m{\A[\t\r ]*[=+\-\@]};$V=~s{"}{""}g;return'"'.$V.'"'; }
sub _Filename { my($Self,$V)=@_;$V=lc($V||'qisutu-report');$V=~s{[^a-z0-9_-]+}{-}g;$V=~s{\A-+|-+\z}{}g;return substr($V||'qisutu-report',0,80); }
sub _Notice { my($Self,$N,$L)=@_;my%K=(saved=>'ReportSaved',copied=>'ReportCopied',deleted=>'ReportDeleted');return$K{$N}?$Self->_T($K{$N},$L):''; }
sub _T { my($Self,$K,$L)=@_;return''if!$K;return$Self->{Output}->Translate(Key=>$K,Language=>$L)||$K; }
sub _E { my($Self,$V)=@_;return$Self->{Output}->HTMLEscape(defined$V?$V:''); }
sub _Trim { my($Self,$V)=@_;$V=''if!defined$V;$V=~s{\A\s+|\s+\z}{}g;return$V; }

1;
