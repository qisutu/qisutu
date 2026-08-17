#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use AgentTicketCreate;

{
    package Local::AgentTicketCreateResponseTemplateObject;

    sub TemplateListForQueueAllLanguages {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{ListCalls} }, \%Param;
        return [
            {
                id   => 7,
                language => 'de',
                name => 'Standardantwort',
                selection_label => 'DE – Standardantwort',
            },
            {
                id   => 7,
                language => 'en',
                name => 'Standard reply',
                selection_label => 'EN – Standard reply',
            },
        ];
    }

    sub LanguageClean {
        my ( $Self, $Language ) = @_;
        return $Language || 'de';
    }

    sub TemplateForQueueGet {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{GetCalls} }, \%Param;
        return if ( $Param{TemplateID} || 0 ) != 7 || ( $Param{QueueID} || 0 ) != 3;

        return {
            id      => 7,
            content => $Param{Language} eq 'en' ? '<p>Hello</p>' : '<p>Hallo</p>',
            attachments => [
                {
                    id           => 11,
                    filename     => 'information.pdf',
                    content_type => 'application/pdf',
                    content_size => 2048,
                    size_display => '2 KB',
                },
            ],
        };
    }

    sub Error {
        return '';
    }
}

{
    package Local::AgentTicketCreateWithResponseTemplates;

    our @ISA = ('AgentTicketCreate');

    sub _QueueCreateAccessCheck {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{AccessCalls} }, \%Param;
        return $Self->{AllowAccess} ? 1 : 0;
    }

    sub _ResponseTemplateObject {
        my ($Self) = @_;
        return $Self->{ResponseTemplateObject};
    }

    sub _QueueTemplateHTML {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{BodyCalls} }, \%Param;
        return '<div data-language="' . ( $Param{Language} || '' ) . '" class="qisutu-response-template-slot"><p><br></p></div>';
    }
}

my $TemplateObject = bless {
    ListCalls => [],
    GetCalls  => [],
}, 'Local::AgentTicketCreateResponseTemplateObject';

my $Module = Local::AgentTicketCreateWithResponseTemplates->new(
    Config => { Language => { Default => 'de' } },
);
$Module->{AllowAccess} = 1;
$Module->{ResponseTemplateObject} = $TemplateObject;

my $QueueData = $Module->_QueueTemplateData(
    QueueID  => 3,
    User     => { user_account_id => 9 },
    Language => 'en',
);

ok( $QueueData->{success}, 'the queue template request succeeds for an accessible queue' );
is( scalar @{ $QueueData->{response_templates} || [] }, 2, 'queue changes return every available response-template language' );
is( $QueueData->{response_templates}->[1]->{selection_label}, 'EN – Standard reply', 'the English template version is selectable in a German agent session' );
is( $TemplateObject->{ListCalls}->[0]->{QueueID}, 3, 'only response templates assigned to the selected queue are loaded' );

my $TemplateData = $Module->_ResponseTemplateData(
    QueueID           => 3,
    ResponseTemplateID => 7,
    ResponseTemplateLanguage => 'en',
    User              => { user_account_id => 9 },
    Language          => 'en',
);

ok( $TemplateData->{success}, 'an assigned response template can be loaded while creating a ticket' );
is( $TemplateData->{content}, '<p>Hello</p>', 'the localized template content is returned' );
is( $TemplateData->{language}, 'en', 'the explicitly selected response language is retained' );
like( $TemplateData->{body_template}, qr{qisutu-response-template-slot}, 'the selected language also rebuilds the salutation and signature template' );
like( $TemplateData->{body_template}, qr{data-language="en"}, 'salutation and signature use the selected English response language' );
is( $TemplateData->{attachments}->[0]->{id}, 11, 'template attachments are returned for the creation form' );
is( $TemplateData->{attachments}->[0]->{size_display}, '2 KB', 'the attachment display size is returned' );

$Module->{AllowAccess} = 0;
my $Denied = $Module->_ResponseTemplateData(
    QueueID           => 3,
    ResponseTemplateID => 7,
    User              => { user_account_id => 9 },
    Language          => 'de',
);
ok( !$Denied->{success}, 'response templates cannot be loaded without ticket-create permission for the queue' );
is_deeply( $Denied->{attachments}, [], 'an unauthorized response-template request exposes no attachments' );

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $ModuleSource = _Read( File::Spec->catfile( $Root, 'core', 'module', 'AgentTicketCreate.pm' ) );
my $TemplateSource = _Read( File::Spec->catfile( $Root, 'core', 'output', 'AgentTicketCreate.tt' ) );
my $JavaScript = _Read( File::Spec->catfile( $Root, 'var', 'static', 'js', 'qisutu-agent-ticket-create.js' ) );

like( $ModuleSource, qr{Step\s+eq\s+'ResponseTemplateGet'}, 'ticket creation provides the response-template JSON endpoint' );
like( $ModuleSource, qr{AttachmentsForArticle\s*[(]}, 'selected template attachments are added when the ticket is submitted' );
like( $TemplateSource, qr{name="ResponseTemplateID"}, 'the ticket-create form contains a response-template selector' );
like( $TemplateSource, qr{name="ResponseTemplateLanguage"}, 'the selected response language is submitted independently of the agent language' );
like( $TemplateSource, qr{data-response-template-language}, 'every selectable template option carries its own language' );
like( $TemplateSource, qr{data-qisutu-create-response-template-attachment-wrap}, 'the ticket-create form displays selected template attachments' );
like( $JavaScript, qr{responseTemplateSlotSet}, 'the response-template text is inserted into the editor slot' );
like( $JavaScript, qr{response_templates}, 'the available response templates are refreshed after a queue change' );
like( $JavaScript, qr{ResponseTemplateLanguage}, 'ticket creation loads the explicitly selected template language' );
like( $JavaScript, qr{ResponseTemplateAttachmentSelection}, 'removed template attachments remain excluded on submit' );

done_testing();

sub _Read {
    my ($File) = @_;

    open my $Handle, '<:encoding(UTF-8)', $File or die "Could not read $File: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;

    return $Content;
}
