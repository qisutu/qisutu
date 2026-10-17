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

package QisutuAppointmentTestDB;
use strict;
use warnings;
use utf8;
use DBI;
use File::Temp;
use POSIX qw(strftime);
use parent 'QisutuDB';

# Test-only SQLite adapter. The current installation schema supplies every
# table; MariaDB-specific syntax is normalized here, never in production.
sub new {
    my ($Class,%P)=@_;
    my $File=File::Temp->new(SUFFIX=>'.sqlite',UNLINK=>1);
    my $H=DBI->connect('dbi:SQLite:dbname='.$File,'','',{RaiseError=>0,PrintError=>0,AutoCommit=>1,sqlite_unicode=>1});
    die 'SQLite test database unavailable' if !$H;
    $H->sqlite_create_function('NOW',0,sub {strftime('%Y-%m-%d %H:%M:%S',gmtime)});
    $H->sqlite_create_function('CONCAT',-1,sub {join('',map {defined $_?$_:''} @_)});
    $H->sqlite_create_function('IF',3,sub {$_[0]?$_[1]:$_[2]});
    $H->sqlite_create_function('GREATEST',-1,sub{(sort {$b<=>$a} @_)[0]});
    $H->sqlite_create_function('DATE_FORMAT',2,sub {return substr($_[0]||'',0,10)});
    $H->sqlite_create_function('GET_LOCK',2,sub{1});
    $H->sqlite_create_function('RELEASE_LOCK',1,sub{1});
    my $S=bless {DBH=>$H,LastError=>'',File=>$File},$Class;
    open my $FH,'<:encoding(UTF-8)',$P{Schema} or die $!;
    my $SQL=do {local $/;<$FH>};close $FH;
    while ($SQL =~ /^CREATE TABLE(?: IF NOT EXISTS)? `([^`]+)` \((.*?)^\) ENGINE=.*?;/msg) {
        my ($Table,$Body)=($1,$2);my @Defs;
        for my $Line (_Definitions($Body)) {
            next if $Line =~ /\A(?:KEY|FULLTEXT|CONSTRAINT)/;
            my $Prefix='';$Prefix=$1 if $Line =~ s/\A(`[^`]+`\s+)//;
            $Line =~ s/UNIQUE KEY `[^`]+`/UNIQUE/g;
            $Line =~ s/\b(?:tinyint|smallint|mediumint|bigint|int)\b(?:\(\d+\))?(?: unsigned)?/INTEGER/ig;
            $Line =~ s/\b(?:mediumtext|longtext|datetime|date|time)\b/TEXT/ig;
            $Line =~ s/\benum\([^)]*\)/TEXT/ig;
            $Line =~ s/\b(?:longblob|mediumblob)\b/BLOB/ig;
            $Line =~ s/\b(?:unsigned|AUTO_INCREMENT)\b//ig;
            $Line =~ s/ON UPDATE current_timestamp\(\d*\)//ig;
            $Line =~ s/current_timestamp\(\d*\)/CURRENT_TIMESTAMP/ig;
            $Line =~ s/COLLATE \w+|CHARACTER SET \w+//ig;
            $Line =~ s/(`[^`]+`)\(\d+\)/$1/g;
            push @Defs,$Prefix.$Line;
        }
        $H->do('CREATE TABLE `'.$Table.'` ('.join(',',@Defs).')') or die $H->errstr;
    }
    for my $Seed (
        q{INSERT INTO user_account (id,login,email,password_hash,firstname,lastname) VALUES (1,'admin','admin@example.invalid','INVALID','Test','Administrator')},
        q{INSERT INTO user_group (id,name,title,group_type,active,created_by_user_id,changed_by_user_id) VALUES (1,'admin','Administrators','agent',1,1,1),(2,'agent','Agents','agent',1,1,1)},
        q{INSERT INTO user_group_member (user_group_id,user_account_id,role_name,active,permission_read,permission_create,permission_change,permission_overview,permission_full,created_by_user_id,changed_by_user_id) VALUES (1,1,'admin',1,1,1,1,1,1,1,1),(2,1,'admin',1,1,1,1,1,1,1,1)},
        q{INSERT INTO user_group_permission (user_group_id,permission_key,active,created_by_user_id,changed_by_user_id) VALUES (1,'admin.view',1,1,1)},
        q{INSERT INTO ticket_queue (id,name,full_name,active,created_by_user_id,changed_by_user_id) VALUES (1,'Support','Support',1,1,1)},
        q{INSERT INTO ticket_queue_group (queue_id,user_group_id,permission_key,active,created_by_user_id,changed_by_user_id) VALUES (1,2,'ticket.full',1,1,1)},
        q{INSERT INTO ticket_state (id,name,state_type,active,created_by_user_id,changed_by_user_id) VALUES (2,'open','open',1,1,1)},
        q{INSERT INTO ticket_priority (id,name,active,created_by_user_id,changed_by_user_id) VALUES (3,'3 normal',1,1,1)},
    ) {$H->do($Seed) or die $H->errstr;}
    return $S;
}
sub _Definitions {
    my ($Text)=@_;my @Out;my $Part='';my $Depth=0;my $Quote='';my $Previous='';
    for my $C(split //,$Text) {
        if ($Quote) {$Quote='' if $C eq $Quote && $Previous ne '\\';}
        elsif ($C =~ /["'`]/) {$Quote=$C;}
        elsif ($C eq '(') {$Depth++;}
        elsif ($C eq ')') {$Depth--;}
        elsif ($C eq ',' && !$Depth) {$Part =~ s/^\s+|\s+$//g;push @Out,$Part;$Part='';$Previous=$C;next;}
        $Part.=$C;$Previous=$C;
    }
    $Part =~ s/^\s+|\s+$//g;push @Out,$Part if length $Part;return @Out;
}
sub _SQL {
    my ($SQL)=@_;
    $SQL =~ s/ON DUPLICATE KEY UPDATE/ON CONFLICT DO UPDATE SET/ig;
    $SQL =~ s/VALUES\((\w+)\)/excluded.$1/ig;
    $SQL =~ s/FOR UPDATE\s*$//i;
    return $SQL;
}
sub Do {my ($S,$SQL,@B)=@_;return 1 if $SQL=~/^SET /;return $S->SUPER::Do(_SQL($SQL),@B);}
sub SelectRow {
    my ($S,$SQL,@B)=@_;
    if($SQL=~/INFORMATION_SCHEMA\.COLUMNS/i){
        return if $B[0]!~/\A[a-z_]+\z/;
        my $Rows=$S->{DBH}->selectall_arrayref('PRAGMA table_info('.$B[0].')',{Slice=>{}});
        return scalar(grep {$_->{name} eq $B[1]} @$Rows)?{column_exists=>1}:undef;
    }
    return $S->SUPER::SelectRow(_SQL($SQL),@B);
}
sub SelectAll {my ($S,$SQL,@B)=@_;return $S->SUPER::SelectAll(_SQL($SQL),@B);}
sub LastInsertID {return $_[0]->{DBH}->sqlite_last_insert_rowid;}
1;
