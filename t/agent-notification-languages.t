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

use AdminAgentNotifications;
use QisutuAgentNotificationTemplates;
use QisutuNotification;

my @ExpectedLanguages = qw(de en fr it es pt-BR pt-PT nl pl cs tr);
my $Languages = QisutuAgentNotificationTemplates->Languages();

is_deeply(
    [ map { $_->{code} } @{$Languages} ],
    \@ExpectedLanguages,
    'agent notification templates provide all eleven Qisutu languages',
);

for my $Language (@ExpectedLanguages) {
    my $Templates = QisutuAgentNotificationTemplates->Templates( Language => $Language );
    is( scalar @{$Templates}, 6, "$Language provides all six agent notification types" );
    is_deeply(
        [ map { $_->{sort_order} } @{$Templates} ],
        [ 100, 200, 300, 400, 500, 600 ],
        "$Language keeps the stable notification order",
    );
    is(
        scalar( grep { !$_->{name} || !$_->{subject} || !$_->{body_html} } @{$Templates} ),
        0,
        "$Language contains complete names, subjects, and HTML bodies",
    );
}

is(
    QisutuAgentNotificationTemplates->LanguageClean( 'pt_pt' ),
    'pt-PT',
    'language codes are normalized canonically',
);
is(
    QisutuAgentNotificationTemplates->LanguageClean( 'unknown', 'fr' ),
    'fr',
    'an invalid language falls back to the configured language',
);

my $Brazil = QisutuAgentNotificationTemplates->Templates( Language => 'pt-BR' )->[1]->{body_html};
my $Portugal = QisutuAgentNotificationTemplates->Templates( Language => 'pt-PT' )->[1]->{body_html};
like( $Brazil, qr{Contato:}, 'Brazilian Portuguese uses the Brazilian contact term' );
like( $Portugal, qr{Contacto:}, 'European Portuguese uses the European contact term' );

my %AgentPlaceholder = map {
    ( $_->{placeholder} || '' ) => 1
} @{ QisutuNotification->PlaceholderList() };
ok(
    $AgentPlaceholder{'{{Ticket.ArticleBody[15]}}'},
    'agent notification settings offer the configurable article-line placeholder',
);

{
    package Local::AgentNotificationOutput;

    sub new { return bless {}, shift }
    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        $Value = '' if !defined $Value;
        $Value =~ s/&/&amp;/g;
        $Value =~ s/</&lt;/g;
        $Value =~ s/>/&gt;/g;
        $Value =~ s/"/&quot;/g;
        return $Value;
    }
}

{
    package Local::AgentNotificationObject;

    sub new { return bless { Calls => [] }, shift }
    sub LanguageClean {
        my ( $Self, $Language ) = @_;
        return QisutuAgentNotificationTemplates->LanguageClean( $Language, 'en' );
    }
    sub LanguageList { return QisutuAgentNotificationTemplates->Languages() }
    sub TemplateList {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Calls} }, [ TemplateList => $Param{Language} ];
        return [];
    }
    sub PlaceholderList { return [] }
    sub Error { return '' }
}

{
    package Local::AdminAgentNotificationModule;

    our @ISA = ('AdminAgentNotifications');

    sub _NotificationObject {
        my ($Self) = @_;
        return $Self->{NotificationObject};
    }
}

my $NotificationObject = Local::AgentNotificationObject->new();
my $AdminModule = Local::AdminAgentNotificationModule->new(
    Config  => { Language => { Default => 'de' } },
    DB      => bless( {}, 'Local::UnusedAgentNotificationDB' ),
    Output  => Local::AgentNotificationOutput->new(),
    Program => {},
);
$AdminModule->{NotificationObject} = $NotificationObject;

my $DefaultView = $AdminModule->Run(
    Request => { Language => 'it' },
    User    => { user_account_id => 1 },
);
is(
    $DefaultView->{Data}->{CurrentLanguage},
    'it',
    'the notification language defaults to the current agent interface language',
);
like(
    $DefaultView->{Data}->{LanguageOptionsHTML},
    qr{<option value="it" selected>Italiano</option>},
    'the current agent language is selected in the dropdown',
);

my $PortugueseView = $AdminModule->Run(
    Request => {
        Language             => 'it',
        NotificationLanguage => 'pt-PT',
    },
    User => { user_account_id => 1 },
);
is(
    $PortugueseView->{Data}->{CurrentLanguage},
    'pt-PT',
    'an explicitly selected notification language overrides the default',
);
is_deeply(
    $NotificationObject->{Calls},
    [
        [ TemplateList => 'it' ],
        [ TemplateList => 'pt-PT' ],
    ],
    'the list is loaded only for the selected language',
);

{
    package Local::AgentNotificationDB;

    sub new { return bless { Calls => [] }, shift }
    sub SelectAll {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Calls} }, [ SelectAll => @Param ];
        return [
            {
                notification_type => 'ticket_new_in_my_queues',
                language          => $Param[-1],
                name              => 'Test',
                subject           => 'Test',
                body_html         => '<p>Test</p>',
                active            => 1,
            },
        ];
    }
    sub SelectRow {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Calls} }, [ SelectRow => @Param ];
        return {
            notification_type => $Param[-2],
            language          => $Param[-1],
            name              => 'Test',
            subject           => 'Test',
            body_html         => '<p>Test</p>',
            active            => 1,
        };
    }
    sub Do {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Calls} }, [ Do => @Param ];
        return 1;
    }
    sub Error { return '' }
}

my $DB = Local::AgentNotificationDB->new();
my $Runtime = QisutuNotification->new(
    Config => {
        Language => { Default => 'en' },
        System   => { BaseURL => 'https://support.example.test/qisutu' },
        Paths    => { SettingConfig => '/nonexistent/qisutu-test-settings' },
    },
    DB => $DB,
);
$Runtime->{SchemaChecked}   = 1;
$Runtime->{DefaultsEnsured} = 1;

$Runtime->TemplateGet(
    NotificationType => 'ticket_new_in_my_queues',
    Language         => 'fr',
);
is(
    $DB->{Calls}->[-1]->[-1],
    'fr',
    'template lookup binds the selected language',
);

$Runtime->TemplateUpdate(
    NotificationType => 'ticket_new_in_my_queues',
    Language         => 'nl',
    Subject          => 'Nieuw',
    BodyHTML         => '<p>Nieuw</p>',
    Active           => 1,
    ChangedByUserID  => 1,
);
is(
    $DB->{Calls}->[-1]->[-1],
    'nl',
    'template updates are restricted to the selected language',
);

my $EnglishPlaceholder = $Runtime->_PlaceholderBuild(
    Language => 'en',
    Ticket   => { id => 42, ticket_number => '2026000042' },
    Agent    => {},
    SystemPlaceholder => {},
);
my $GermanPlaceholder = $Runtime->_PlaceholderBuild(
    Language => 'de',
    Ticket   => { id => 42, ticket_number => '2026000042' },
    Agent    => {},
    SystemPlaceholder => {},
);
like( $EnglishPlaceholder->{'Ticket.LinkHTML'}, qr{Open ticket 2026000042}, 'the ticket link follows the recipient language' );
like( $GermanPlaceholder->{'Ticket.LinkHTML'}, qr{Ticket 2026000042 öffnen}, 'the German ticket link remains German' );

my $ArticleText = $Runtime->_ArticleBodyPlainText(
    Article => {
        content_type => 'text/html',
        body => '<p>Line 1 &amp; safe</p><p>Line 2</p><p>&lt;Line 3&gt;</p>',
    },
);
is(
    $ArticleText,
    "Line 1 & safe\nLine 2\n<Line 3>",
    'HTML ticket articles are converted to safe text while preserving their lines',
);
my $ArticlePlaceholder = { 'Ticket.ArticleBody' => $ArticleText };
my $ArticleHTML = $Runtime->_PlaceholderReplaceHTML(
    HTML        => '<p>Before</p>{{Ticket.ArticleBody[2]}}<p>After</p>',
    Placeholder => $ArticlePlaceholder,
);
like( $ArticleHTML, qr{Line 1 &amp; safe<br>Line 2}, 'the requested first two article lines are inserted into an HTML notification' );
unlike( $ArticleHTML, qr{Line 3}, 'an HTML agent notification excludes article lines after the configured limit' );
like( $ArticleHTML, qr{background: #f5f5f5}, 'the article excerpt is displayed as a separate readable block' );
like(
    $Runtime->_PlaceholderReplaceHTML(
        HTML        => '{{Ticket.ArticleBody}}',
        Placeholder => $ArticlePlaceholder,
    ),
    qr{&lt;Line 3&gt;},
    'the article placeholder without a number includes the complete article text',
);
is(
    $Runtime->_PlaceholderReplacePlain(
        Text        => 'Excerpt: {{Ticket.ArticleBody[2]}}',
        Placeholder => $ArticlePlaceholder,
    ),
    'Excerpt: Line 1 & safe Line 2',
    'the configurable article-line placeholder is also safe in notification subjects',
);

{
    package Local::MultilingualSendNotification;

    our @ISA = ('QisutuNotification');

    sub SchemaEnsure { return 1 }
    sub _DefaultTemplatesEnsure { return 1 }
    sub TemplateGet {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{LoadedLanguages} }, $Param{Language};
        my ($Template) = grep {
            $_->{type} eq $Param{NotificationType}
        } @{ QisutuAgentNotificationTemplates->Templates( Language => $Param{Language} ) };
        return {
            %{$Template},
            body_html => ( $Template->{body_html} || '' ) . '<p>{{Ticket.ArticleBody[2]}}</p>',
            active    => 1,
        };
    }
    sub _TicketDataGet {
        return {
            id             => 42,
            ticket_number  => '2026000042',
            title          => 'Printer',
            queue_id       => 1,
            queue_name     => 'Support',
            queue_full_name => 'Support',
            system_email_name => 'Qisutu Support',
            system_email   => 'support@example.test',
        };
    }
    sub _RecipientList {
        return [
            {
                id => 10, login => 'english', email => 'english@example.test',
                firstname => 'Eve', lastname => 'English', full_name => 'Eve English',
                language => 'en',
            },
            {
                id => 11, login => 'francais', email => 'francais@example.test',
                firstname => 'François', lastname => 'Français', full_name => 'François Français',
                language => 'fr',
            },
        ];
    }
    sub _RecipientPreferenceFilter {
        my ( $Self, %Param ) = @_;
        return $Param{RecipientList};
    }
    sub _TicketArticleDataGet {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{LoadedArticles} }, { %Param };
        return {
            id           => $Param{ArticleID},
            ticket_id    => $Param{TicketID},
            sender_type  => 'customer',
            content_type => 'text/plain',
            body         => "Agent line 1\nAgent line 2\nAgent line 3",
        };
    }
    sub _ActiveSMTPAccount {
        return {
            id            => 1,
            smtp_username => 'mailer@example.test',
        };
    }
    sub _SystemPlaceholderHash {
        return {
            'System.Name'            => 'Qisutu',
            'System.DefaultLanguage' => 'en',
        };
    }
    sub _SystemBaseURL {
        return 'https://support.example.test/qisutu';
    }
    sub _MailInlineImages { return [] }
}

my @Sent;
{
    no warnings 'redefine';
    local *QisutuMail::SMTPSend = sub {
        my ( $Self, %Param ) = @_;
        push @Sent, \%Param;
        return { Success => 1, Message => 'sent' };
    };

    my $Sender = Local::MultilingualSendNotification->new(
        Config => {
            Language => { Default => 'de' },
            System   => { Name => 'Qisutu' },
            Paths    => {},
        },
        DB => bless( {}, 'Local::UnusedMultilingualSendDB' ),
    );

    is(
        $Sender->Send(
            NotificationType => 'ticket_new_in_my_queues',
            TicketID         => 42,
            ArticleID        => 77,
        ),
        2,
        'one notification is sent to each recipient',
    );
    is_deeply(
        $Sender->{LoadedLanguages},
        [ 'en', 'fr' ],
        'the send path loads the template in each recipient agent language',
    );
    is_deeply(
        $Sender->{LoadedArticles},
        [ { TicketID => 42, ArticleID => 77 } ],
        'the triggering ticket article is loaded only once for all agent recipients',
    );
}
like( $Sent[0]->{Subject}, qr{\ANew ticket 2026000042}, 'the English agent receives the English subject' );
like( $Sent[1]->{Subject}, qr{\ANouveau ticket 2026000042}, 'the French agent receives the French subject' );
like( $Sent[0]->{Body}, qr{Hello Eve English}, 'the English agent receives the English body' );
like( $Sent[1]->{Body}, qr{Bonjour François Français}, 'the French agent receives the French body' );
like( $Sent[0]->{Body}, qr{Agent line 1<br>Agent line 2}, 'the agent notification contains the requested article excerpt' );
unlike( $Sent[0]->{Body}, qr{Agent line 3}, 'the agent notification respects the configured article line limit' );

sub content {
    my (@Parts) = @_;
    my $Path = File::Spec->catfile( $FindBin::Bin, '..', @Parts );
    open my $FH, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;
    return $Content;
}

my $Schema = content( 'install', 'sql', 'schema.sql' );
like( $Schema, qr{`language`\s+varchar\(10\)\s+NOT NULL DEFAULT 'de'}, 'fresh installations create the notification language column' );
like(
    $Schema,
    qr{agent_notification_template_type_language_unique`\s+\(`notification_type`,`language`\)},
    'fresh installations enforce one template per type and language',
);

my $NotificationSource = content( 'core', 'system', 'QisutuNotification.pm' );
like(
    $NotificationSource,
    qr{language_preference[.]preference_value AS language},
    'notification recipients load their saved agent language',
);
like(
    $NotificationSource,
    qr{ADD COLUMN language VARCHAR\(10\) NOT NULL DEFAULT "de"},
    'existing installations receive the language column automatically',
);

my $TemplateSource = content( 'core', 'output', 'AdminAgentNotifications.tt' );
like(
    $TemplateSource,
    qr{name="NotificationLanguage"[^>]*data-agent-notification-language},
    'the administration view contains the language dropdown',
);
like(
    $TemplateSource,
    qr{name="NotificationLanguage" value="\[% CurrentLanguage %\]"},
    'saving an edit preserves the selected language',
);

done_testing();
