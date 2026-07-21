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

use File::Find;
use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );

use QisutuOutput;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $OutputPath = File::Spec->catdir( $Root, 'core', 'output' );
my $Output = QisutuOutput->new( Config => {
    Paths => {
        Output   => $OutputPath,
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
    },
    Language => { Default => 'de' },
} );

my @Template;
find(
    sub {
        return if !-f $_ || $_ !~ m{[.]tt\z};
        push @Template, $File::Find::name;
    },
    $OutputPath,
);

ok( @Template > 50, 'the global template check covers the complete administration and portal UI' );

for my $File ( sort @Template ) {
    my $Content = _Read($File);
    my @Stack;
    my @Error;
    my %PopulatedData = ( Language => 'de' );

    while ( $Content =~ m{\[\%\s*(.*?)\s*\%\]}gs ) {
        my $Token = $1;
        $Token =~ s{\A\s+|\s+\z}{}g;
        next if $Token =~ m{\A\#};

        if ( $Token =~ m{\AIF\s+([A-Za-z0-9_]+)\z} ) {
            $PopulatedData{$1} = 1;
            push @Error, 'IF inside FOREACH is unsupported by QisutuOutput'
                if grep { $_->{Type} eq 'FOREACH' } @Stack;
            push @Stack, { Type => 'IF', Else => 0 };
            next;
        }
        if ( $Token =~ m{\AFOREACH\s+([A-Za-z0-9_]+)\s+IN\s+([A-Za-z0-9_]+)\z} ) {
            my ( $ItemName, $ListName ) = ( $1, $2 );
            $PopulatedData{$ListName} = [ {} ];
            push @Error, 'nested FOREACH is unsupported by QisutuOutput'
                if grep { $_->{Type} eq 'FOREACH' } @Stack;
            push @Stack, { Type => 'FOREACH', ItemName => $ItemName };
            next;
        }
        if ( $Token eq 'ELSE' ) {
            if ( !@Stack || $Stack[-1]->{Type} ne 'IF' || $Stack[-1]->{Else} ) {
                push @Error, 'ELSE without one matching IF';
            }
            else {
                $Stack[-1]->{Else} = 1;
            }
            next;
        }
        if ( $Token eq 'END' ) {
            if (@Stack) {
                pop @Stack;
            }
            else {
                push @Error, 'END without matching control block';
            }
            next;
        }
        next if $Token =~ m{\ATranslate[.][A-Za-z0-9_]+\z};
        if ( $Token =~ m{\ARAW[.]([A-Za-z0-9_]+)[.]([A-Za-z0-9_]+)\z} ) {
            push @Error, "item variable outside its FOREACH: $Token"
                if !grep { $_->{Type} eq 'FOREACH' && $_->{ItemName} eq $1 } @Stack;
            next;
        }
        next if $Token =~ m{\ARAW[.][A-Za-z0-9_]+\z};
        if ( $Token =~ m{\A([A-Za-z0-9_]+)[.]([A-Za-z0-9_]+)\z} ) {
            push @Error, "item variable outside its FOREACH: $Token"
                if !grep { $_->{Type} eq 'FOREACH' && $_->{ItemName} eq $1 } @Stack;
            next;
        }
        next if $Token =~ m{\A[A-Za-z0-9_]+\z};
        push @Error, "unsupported directive: $Token";
    }
    push @Error, 'unclosed control block' if @Stack;

    my $Relative = File::Spec->abs2rel( $File, $OutputPath );
    is_deeply( \@Error, [], "$Relative uses only template syntax supported by QisutuOutput" );

    my $Rendered = $Output->RenderSingle(
        Template => $Relative,
        Data     => { Language => 'de' },
    );
    ok( defined $Rendered, "$Relative renders without an engine error" );
    unlike( $Rendered || '', qr{\[\%}, "$Relative leaves no raw template directive in its default rendering" );

    my $PopulatedRendered = $Output->RenderSingle(
        Template => $Relative,
        Data     => \%PopulatedData,
    );
    ok( defined $PopulatedRendered, "$Relative renders with every section and list enabled" );
    unlike(
        $PopulatedRendered || '',
        qr{\[\%},
        "$Relative leaves no raw template directive when sections and lists contain data",
    );
}

my $Article = {
    id                      => 1,
    subject                 => 'Regressionstest',
    sender_name             => 'Testperson',
    sender_initials         => 'TP',
    sender_role_label       => 'Translate:TicketArticleRoleAgent',
    visibility_label        => 'Translate:TicketArticleVisibilityBoth',
    created_at_display      => '20.07.2026 12:00',
    crypto_encryption_label => 'Translate:MailCryptoEncrypted',
    crypto_encryption_class => 'is-success',
    crypto_signature_label  => 'Translate:MailCryptoSignedInvalid',
    crypto_signature_class  => 'is-error',
};

for my $Template ( qw(AgentTicketZoom.tt CustomerTicketZoom.tt) ) {
    my $Rendered = $Output->RenderSingle(
        Template => $Template,
        Data     => {
            Language       => 'de',
            TicketFound    => 1,
            TicketMerged   => 0,
            TicketID       => 1,
            ArticleCount   => 1,
            ArticleList    => [ { %{$Article} } ],
            TicketLinks    => [],
            FormAction     => 'index.pl',
        },
    );
    ok( defined $Rendered && length $Rendered, "$Template renders a non-empty article list" );
    unlike( $Rendered || '', qr{\[\%}, "$Template never exposes template source with a non-empty article list" );
    like(
        $Rendered || '',
        qr{qisutu-ticket-article-label is-success">[^<]+</span>},
        "$Template renders the encryption badge",
    );
    like(
        $Rendered || '',
        qr{qisutu-ticket-article-label is-error">[^<]+</span>},
        "$Template renders the signature badge",
    );
}

my $CMDBRendered = $Output->RenderSingle(
    Template => 'CMDBItems.tt',
    Data     => {
        Language     => 'de',
        ShowView     => 1,
        AdminMode    => 1,
        HasRelations => 1,
        Relations    => [ {
            relation_label      => 'gehört zu',
            related_display_html => '<a href="index.pl?Page=AdminCMDBItems;Action=View;CIID=2"><strong>CI-2</strong> Server</a>',
            note                => 'Test',
            remove_html         => '',
        } ],
    },
);
ok( defined $CMDBRendered && length $CMDBRendered, 'CMDB relation rendering succeeds with a non-empty list' );
unlike( $CMDBRendered || '', qr{\[\%}, 'CMDB relation rendering exposes no template source' );
like( $CMDBRendered || '', qr{CI-2}, 'CMDB relation rendering keeps the prepared relation link' );

done_testing();

sub _Read {
    my ($Path) = @_;
    open my $Handle, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}
