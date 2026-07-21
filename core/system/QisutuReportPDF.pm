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

package QisutuReportPDF;

use strict;
use warnings;
use utf8;

use Encode qw(encode FB_DEFAULT);

sub new { my($Class,%Param)=@_;return bless{LastError=>'',%Param},$Class; }
sub Error { return $_[0]->{LastError}||''; }

sub Create {
    my($Self,%Param)=@_;$Self->{LastError}='';my$Result=$Param{Result}||{};
    my@Pages;
    push@Pages,$Self->_OverviewPage(%Param);
    my$Details=$Result->{details}||{};my$Rows=$Details->{rows}||[];my$Columns=$Details->{columns}||[];
    my$MaxRows=@{$Rows}>200?200:scalar@{$Rows};my$Offset=0;
    while($Offset<$MaxRows){my$End=$Offset+27;$End=$MaxRows if$End>$MaxRows;push@Pages,$Self->_DetailPage(%Param,Rows=>[ @{$Rows}[$Offset..$End-1] ],Columns=>$Columns,PageOffset=>$Offset);$Offset=$End;}
    return$Self->_PDFBuild(Pages=>\@Pages,Title=>$Param{Title}||'Qisutu Report');
}

sub _OverviewPage {
    my($Self,%Param)=@_;my$Result=$Param{Result}||{};my$C='';
    $C.=$Self->_Rect(0,0,842,595,0.965,0.975,0.982);
    $C.=$Self->_Rect(0,548,842,47,0.015,0.35,0.45);
    $C.=$Self->_Text(28,568,19,$Param{Title}||'Qisutu Report',1,1,1,1);
    $C.=$Self->_Text(28,552,8,$Param{GeneratedLabel}||'',0,0.86,0.95,0.97);
    my$Y=526;
    if($Param{Description}){$C.=$Self->_Text(28,$Y,9,$Self->_Truncate($Param{Description},135),0,0.15,0.19,0.24);$Y-=16;}
    if($Param{FilterLabel}){$C.=$Self->_Text(28,$Y,8,$Self->_Truncate($Param{FilterLabel},150),0,0.35,0.42,0.49);$Y-=18;}
    my$Metrics=$Result->{metrics}||[];my$Summary=$Result->{summary}||[];my$BoxCount=@{$Metrics}||1;my$BoxWidth=(786-(($BoxCount-1)*10))/$BoxCount;my$X=28;
    for my$Index(0..$#{$Metrics}){$C.=$Self->_Rect($X,$Y-48,$BoxWidth,48,1,1,1);$C.=$Self->_StrokeRect($X,$Y-48,$BoxWidth,48,0.82,0.87,0.91);$C.=$Self->_Text($X+10,$Y-18,8,$Self->_Truncate($Metrics->[$Index]->{label}||'',35),0,0.35,0.42,0.49);$C.=$Self->_Text($X+10,$Y-38,14,$Self->_FormatValue($Summary->[$Index],$Metrics->[$Index]->{format}),1,0.04,0.18,0.24);$X+=$BoxWidth+10;}
    $Y-=70;
    my$ChartType=$Result->{configuration}->{chart_type}||'bar';
    if($ChartType!~m{\A(?:table|kpi)\z}&&@{$Result->{rows}||[]}){$C.=$Self->_Chart(X=>28,Y=>$Y-235,W=>500,H=>225,Result=>$Result,Type=>$ChartType);}
    else{$C.=$Self->_Text(28,$Y-22,11,$Param{ResultLabel}||'Results',1,0.04,0.18,0.24);}
    my$TableX=$ChartType!~m{\A(?:table|kpi)\z}?548:28;my$TableW=$ChartType!~m{\A(?:table|kpi)\z}?266:786;my$TableY=$Y-10;
    $C.=$Self->_AggregateTable(X=>$TableX,Y=>$TableY,W=>$TableW,H=>225,Result=>$Result);
    $C.=$Self->_Text(28,18,7,'Qisutu · '.$Self->_Truncate($Param{FooterLabel}||'',120),0,0.45,0.50,0.55);
    return$C;
}

sub _DetailPage {
    my($Self,%Param)=@_;my$C='';$C.=$Self->_Rect(0,0,842,595,1,1,1);$C.=$Self->_Rect(0,554,842,41,0.015,0.35,0.45);
    $C.=$Self->_Text(24,571,14,$Self->_Truncate($Param{Title}||'Qisutu Report',90),1,1,1,1);
    $C.=$Self->_Text(24,558,8,($Param{DetailLabel}||'Details').' · '.(($Param{PageOffset}||0)+1).'–'.(($Param{PageOffset}||0)+@{$Param{Rows}||[]}),0,0.86,0.95,0.97);
    my@Columns=@{$Param{Columns}||[]};@Columns=@Columns[0..7]if@Columns>8;my$Count=@Columns||1;my$W=794/$Count;my$Y=530;
    for my$I(0..$#Columns){$C.=$Self->_Rect(24+$I*$W,$Y-18,$W,18,0.91,0.94,0.96);$C.=$Self->_Text(28+$I*$W,$Y-12,7,$Self->_Truncate($Columns[$I]->{label}||'',18),1,0.15,0.20,0.25);}
    $Y-=18;my$RowIndex=0;
    for my$Row(@{$Param{Rows}||[]}){my$BG=$RowIndex%2?0.97:1;$C.=$Self->_Rect(24,$Y-17,794,17,$BG,$BG,$BG);for my$I(0..$#Columns){my$Value=$Row->[$I];$C.=$Self->_Text(28+$I*$W,$Y-11,6.5,$Self->_Truncate(defined$Value?$Value:'',22),0,0.12,0.16,0.20);}$Y-=17;$RowIndex++;}
    $C.=$Self->_Text(24,18,7,'Qisutu · '.($Param{GeneratedLabel}||''),0,0.45,0.50,0.55);return$C;
}

sub _Chart {
    my($Self,%Param)=@_;my$R=$Param{Result};my$Rows=$R->{rows}||[];my$Metrics=$R->{metrics}||[];my$Type=$Param{Type};my$C='';
    $C.=$Self->_Rect($Param{X},$Param{Y},$Param{W},$Param{H},1,1,1);$C.=$Self->_StrokeRect($Param{X},$Param{Y},$Param{W},$Param{H},0.84,0.88,0.91);
    my@Colors=([0.02,0.46,0.62],[0.95,0.35,0.20],[0.32,0.70,0.42]);my$PlotX=$Param{X}+42;my$PlotY=$Param{Y}+35;my$PlotW=$Param{W}-60;my$PlotH=$Param{H}-65;
    if($Type eq'doughnut'){
        my@Values=map{0+($_->{values}->[0]||0)}@{$Rows};my$Total=0;$Total+=$_ for@Values;return$C if!$Total;my$CX=$Param{X}+$Param{W}*0.38;my$CY=$Param{Y}+$Param{H}*0.52;my$Radius=70;my$Start=-1.570796;
        for my$I(0..$#Values){next if!$Values[$I];my$End=$Start+6.283185*$Values[$I]/$Total;my$Color=$Colors[$I%@Colors];$C.=$Self->_Sector($CX,$CY,$Radius,$Start,$End,@{$Color});$Start=$End;}
        $C.=$Self->_Circle($CX,$CY,35,1,1,1);my$LY=$Param{Y}+$Param{H}-35;for my$I(0..$#{$Rows}){last if$I>8;my$Color=$Colors[$I%@Colors];$C.=$Self->_Rect($Param{X}+$Param{W}*0.64,$LY-5,8,8,@{$Color});$C.=$Self->_Text($Param{X}+$Param{W}*0.64+13,$LY,7,$Self->_Truncate($Rows->[$I]->{label},25).' '.$Self->_FormatValue($Values[$I],$Metrics->[0]->{format}),0,0.2,0.25,0.3);$LY-=16;}return$C;
    }
    my$Max=0;for my$Row(@{$Rows}){my$V=$Type eq'stacked_bar'?0:undef;for my$I(0..$#{$Metrics}){my$N=0+($Row->{values}->[$I]||0);$V=$Type eq'stacked_bar'?$V+$N:(!defined$V||$N>$V?$N:$V);}$Max=$V if defined$V&&$V>$Max;}$Max=1 if!$Max;
    for my$I(0..4){my$Y=$PlotY+$PlotH*$I/4;$C.=$Self->_Line($PlotX,$Y,$PlotX+$PlotW,$Y,0.88,0.90,0.92,0.5);$C.=$Self->_Text($Param{X}+4,$Y-2,6,sprintf('%.0f',$Max*$I/4),0,0.4,0.45,0.5);}
    my$Count=@{$Rows}||1;my$Step=$PlotW/$Count;
    if($Type=~m{\A(?:line|area)\z}){for my$M(0..$#{$Metrics}){my$Color=$Colors[$M%@Colors];my@Points;for my$I(0..$#{$Rows}){push@Points,[$PlotX+$Step*($I+0.5),$PlotY+$PlotH*(0+($Rows->[$I]->{values}->[$M]||0))/$Max];}$C.=$Self->_Polyline(\@Points,@{$Color},1.7);for my$P(@Points){$C.=$Self->_Circle($P->[0],$P->[1],2.4,@{$Color});}}}
    else{my$BarW=$Step*0.72;for my$I(0..$#{$Rows}){my$X=$PlotX+$Step*$I+$Step*0.14;my$Base=$PlotY;for my$M(0..$#{$Metrics}){my$V=0+($Rows->[$I]->{values}->[$M]||0);my$H=$PlotH*$V/$Max;my$W=$Type eq'stacked_bar'?$BarW:$BarW/@{$Metrics};my$BX=$Type eq'stacked_bar'?$X:$X+$M*$W;my$Color=$Colors[$M%@Colors];$C.=$Self->_Rect($BX,$Base,$W-1,$H,@{$Color});$Base+=$H if$Type eq'stacked_bar';}}}
    for my$I(0..$#{$Rows}){next if$I%int(($Count+7)/8);$C.=$Self->_Text($PlotX+$Step*$I,$Param{Y}+12,6,$Self->_Truncate($Rows->[$I]->{label},10),0,0.35,0.4,0.45);}
    my$LegendX=$Param{X}+12;for my$I(0..$#{$Metrics}){my$Color=$Colors[$I%@Colors];$C.=$Self->_Rect($LegendX,$Param{Y}+$Param{H}-17,7,7,@{$Color});$C.=$Self->_Text($LegendX+11,$Param{Y}+$Param{H}-13,7,$Self->_Truncate($Metrics->[$I]->{label},28),0,0.2,0.25,0.3);$LegendX+=150;}return$C;
}

sub _AggregateTable {
    my($Self,%Param)=@_;my$R=$Param{Result};my$Rows=$R->{rows}||[];my$Metrics=$R->{metrics}||[];my$C='';$C.=$Self->_Rect($Param{X},$Param{Y}-$Param{H},$Param{W},$Param{H},1,1,1);$C.=$Self->_StrokeRect($Param{X},$Param{Y}-$Param{H},$Param{W},$Param{H},0.84,0.88,0.91);my$MetricCount=@{$Metrics}||1;my$LabelW=$Param{W}*0.48;my$MetricW=($Param{W}-$LabelW)/$MetricCount;
    $C.=$Self->_Rect($Param{X},$Param{Y}-20,$Param{W},20,0.91,0.94,0.96);$C.=$Self->_Text($Param{X}+7,$Param{Y}-13,7,$R->{group}->{label}||'',1,0.14,0.2,0.25);for my$I(0..$#{$Metrics}){$C.=$Self->_Text($Param{X}+$LabelW+$I*$MetricW+4,$Param{Y}-13,6.5,$Self->_Truncate($Metrics->[$I]->{label},16),1,0.14,0.2,0.25);}
    my$Y=$Param{Y}-20;for my$I(0..$#{$Rows}){last if$I>10;$Y-=17;my$BG=$I%2?0.97:1;$C.=$Self->_Rect($Param{X},$Y,$Param{W},17,$BG,$BG,$BG);$C.=$Self->_Text($Param{X}+7,$Y+5,6.5,$Self->_Truncate($Rows->[$I]->{label},28),0,0.15,0.2,0.25);for my$M(0..$#{$Metrics}){$C.=$Self->_Text($Param{X}+$LabelW+$M*$MetricW+4,$Y+5,6.5,$Self->_FormatValue($Rows->[$I]->{values}->[$M],$Metrics->[$M]->{format}),0,0.15,0.2,0.25);}}
    return$C;
}

sub _PDFBuild {
    my($Self,%Param)=@_;my@PageContent=@{$Param{Pages}||[]};my@Objects;push@Objects,'<< /Type /Catalog /Pages 2 0 R >>';my@Kids;for my$I(0..$#PageContent){push@Kids,(5+$I*2).' 0 R';}push@Objects,'<< /Type /Pages /Kids ['.join(' ',@Kids).'] /Count '.scalar(@Kids).' >>';push@Objects,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';push@Objects,'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';for my$I(0..$#PageContent){my$PageID=5+$I*2;my$StreamID=$PageID+1;my$Stream=$PageContent[$I];push@Objects,'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents '.$StreamID.' 0 R >>';push@Objects,'<< /Length '.length($Stream).' >>' . "\nstream\n".$Stream."\nendstream";}
    my$PDF="%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";my@Offsets=(0);for my$I(0..$#Objects){push@Offsets,length($PDF);$PDF.=($I+1)." 0 obj\n".$Objects[$I]."\nendobj\n";}my$XRef=length($PDF);$PDF.='xref'."\n0 ".(scalar(@Objects)+1)."\n0000000000 65535 f \n";for my$I(1..$#Offsets){$PDF.=sprintf("%010d 00000 n \n",$Offsets[$I]);}$PDF.='trailer'."\n<< /Size ".(scalar(@Objects)+1).' /Root 1 0 R >>'."\nstartxref\n$XRef\n%%EOF\n";return$PDF;
}

sub _Text { my($Self,$X,$Y,$Size,$Text,$Bold,$R,$G,$B)=@_;$R//=0;$G//=0;$B//=0;return sprintf('%.3f %.3f %.3f rg BT /F%s %.2f Tf %.2f %.2f Td (%s) Tj ET'."\n",$R,$G,$B,$Bold?2:1,$Size,$X,$Y,$Self->_PDFText($Text)); }
sub _Rect { my($Self,$X,$Y,$W,$H,$R,$G,$B)=@_;return sprintf('%.3f %.3f %.3f rg %.2f %.2f %.2f %.2f re f'."\n",$R,$G,$B,$X,$Y,$W,$H); }
sub _StrokeRect { my($Self,$X,$Y,$W,$H,$R,$G,$B)=@_;return sprintf('%.3f %.3f %.3f RG %.2f %.2f %.2f %.2f re S'."\n",$R,$G,$B,$X,$Y,$W,$H); }
sub _Line { my($Self,$X1,$Y1,$X2,$Y2,$R,$G,$B,$Width)=@_;return sprintf('%.3f %.3f %.3f RG %.2f w %.2f %.2f m %.2f %.2f l S'."\n",$R,$G,$B,$Width||1,$X1,$Y1,$X2,$Y2); }
sub _Polyline { my($Self,$P,$R,$G,$B,$W)=@_;return''if!@{$P};my$C=sprintf('%.3f %.3f %.3f RG %.2f w %.2f %.2f m ',$R,$G,$B,$W||1,$P->[0]->[0],$P->[0]->[1]);for my$I(1..$#{$P}){$C.=sprintf('%.2f %.2f l ',$P->[$I]->[0],$P->[$I]->[1]);}return$C."S\n"; }
sub _Circle { my($Self,$X,$Y,$R,$CR,$CG,$CB)=@_;my$K=0.55228475*$R;return sprintf('%.3f %.3f %.3f rg %.2f %.2f m %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c %.2f %.2f %.2f %.2f %.2f %.2f c f'."\n",$CR,$CG,$CB,$X+$R,$Y,$X+$R,$Y+$K,$X+$K,$Y+$R,$X,$Y+$R,$X-$K,$Y+$R,$X-$R,$Y+$K,$X-$R,$Y,$X-$R,$Y-$K,$X-$K,$Y-$R,$X,$Y-$R,$X+$K,$Y-$R,$X+$R,$Y-$K,$X+$R,$Y); }
sub _Sector { my($Self,$X,$Y,$R,$Start,$End,$CR,$CG,$CB)=@_;my$Steps=int(($End-$Start)*18);$Steps=2 if$Steps<2;my$C=sprintf('%.3f %.3f %.3f rg %.2f %.2f m ',$CR,$CG,$CB,$X,$Y);for my$I(0..$Steps){my$A=$Start+($End-$Start)*$I/$Steps;$C.=sprintf('%.2f %.2f l ',$X+$R*cos($A),$Y+$R*sin($A));}return$C."h f\n"; }
sub _PDFText { my($Self,$V)=@_;$V=''if!defined$V;$V="$V";$V=encode('cp1252',$V,FB_DEFAULT)if utf8::is_utf8($V);$V=~s{\\}{\\\\}g;$V=~s{\(}{\\(}g;$V=~s{\)}{\\)}g;$V=~s{\r|\n}{ }g;return$V; }
sub _Truncate { my($Self,$V,$N)=@_;$V=''if!defined$V;$V=~s{\s+}{ }g;return length($V)>$N?substr($V,0,$N-1).'…':$V; }
sub _FormatValue { my($Self,$V,$Format)=@_;$V=0 if!defined$V;return sprintf('%.2f %%',$V)if($Format||'')eq'percent';if(($Format||'')eq'minutes'){my$M=int($V+0.5);return int($M/60).' h '.sprintf('%02d',$M%60).' min';}return $V==int($V)?int($V):sprintf('%.2f',$V); }

1;
