#!/usr/bin/env perl

# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

use strict;
use warnings;
use utf8;

use Cwd qw(abs_path);
use Encode qw(decode);
use FindBin;
use File::Spec;

my $QisutuHome=$ENV{QISUTU_HOME}||abs_path(File::Spec->catdir($FindBin::Bin,'..'));
$ENV{QISUTU_HOME}||=$QisutuHome;
unshift@INC,File::Spec->catdir($QisutuHome,'core','config'),File::Spec->catdir($QisutuHome,'core','system'),File::Spec->catdir($QisutuHome,'core','cpan-lib');

main();

sub main {
    require QisutuConfig;require QisutuDB;require QisutuCMDBImport;
    my($ProfileID,$File);while(@ARGV){my$Arg=shift@ARGV;if($Arg eq'--profile'){$ProfileID=shift@ARGV;}elsif($Arg eq'--file'){$File=shift@ARGV;}}
    if(!$ProfileID||$ProfileID!~m{\A\d+\z}||!$File||!-f$File){print STDERR "Usage: qisutu-cmdb-import.pl --profile ID --file /path/export.csv\n";exit 2;}
    my$Config=QisutuConfig::Load();my$DB=QisutuDB->new(Config=>$Config);if(!$DB->Connect()){print STDERR "Database connection failed: ".($DB->Error()||'')."\n";exit 1;}
    my$Import=QisutuCMDBImport->new(Config=>$Config,DB=>$DB);my$Profile=$Import->ProfileGet(ProfileID=>$ProfileID);if(!$Profile){print STDERR "Import profile not found.\n";$DB->Disconnect();exit 1;}
    open my$FH,'<:raw',$File or do{print STDERR "Cannot open $File: $!\n";$DB->Disconnect();exit 1;};local$/;my$Content=<$FH>;close$FH;$Content=eval{decode($Profile->{encoding_name}||'UTF-8',$Content,1)}||$Content;
    my$Result=$Import->Import(ProfileID=>$ProfileID,Content=>$Content,FileName=>$File,User=>{user_account_id=>1,account_type=>'system',login=>'qisutu-cron'});
    if(!$Result){print STDERR "CMDB import failed: ".($Import->Error()||'')."\n";$DB->Disconnect();exit 1;}
    print join(' ','CMDB import:','total='.$Result->{Total},'created='.$Result->{Created},'updated='.$Result->{Updated},'failed='.$Result->{Failed})."\n";$DB->Disconnect();exit($Result->{Failed}?3:0);
}
