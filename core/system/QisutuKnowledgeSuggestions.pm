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

package QisutuKnowledgeSuggestions;

use strict;
use warnings;
use utf8;
use QisutuHTML;
use QisutuSystemSetting;

# These words add noise to a problem description. Product names, error codes,
# identifiers and words such as "nicht"/"not" deliberately remain searchable.
my %Stopword = map { $_ => 1 } qw(
    ich mich mir mein meine meinen meinem wir uns unser unsere sie ihnen ihr ihre
    du dich dir dein deine der die das den dem des ein eine einer einen einem eines
    und oder aber als auch an am auf aus bei bis durch für im in mit nach ohne um
    vom von vor zu zum zur ist sind war waren bin bist sein kann können konnte
    bitte habe haben hat hallo problem probleme hilfe
    i me my mine we us our you your yours he him his she her they them their
    a an the and or but as at by for from in into of on to with is are was were
    be been being can could would should have has had please hello problem problems help
    je me moi mon ma mes nous notre nos vous votre vos il elle ils elles leur leurs
    le la les un une des du de et ou au aux dans en avec par pour sur est sont
    suis être peux peut pouvez bonjour merci problème problèmes aide
    io mi mio mia noi nostro nostra voi vostro vostra lui lei loro il lo gli la le
    un uno una di da del della dei delle e o per con su al alla è sono posso può
    por yo me mi mis nosotros nuestro nuestra vosotros usted ustedes el la los las
    una unas unos y o de del en con para que es son puedo puede hola gracias
    eu meu minha meus minhas nós nosso nossa você vocês ele ela eles elas um uma
    os as dos das do da em com pelo pela ao aos é são posso pode obrigado olá
    ik mij mijn wij ons onze jij jou jouw u uw hij hem zijn zij haar hun het een
    de en of van voor met op aan bij uit is ben kan kunnen graag hallo hulp
    ja mnie mój moja my nas nasz nasze ty ci twój twoja on ona oni one oraz i lub
    w z na do od dla jest są mogę może proszę pomoc
    já mě můj moje my nás náš naše ty tě tvůj tvoje on ona oni nebo a v ve na do
    od pro se je jsou mohu může prosím pomoc
    ben beni benim biz bizim siz sizin o onlar ve veya bir bu şu için ile dan den
    da de mı mi mu mü olan olabilir merhaba lütfen
);

sub new {
    my ( $Class, %Param ) = @_;
    return bless { Config => $Param{Config} || {}, DB => $Param{DB} }, $Class;
}

sub Articles {
    my ( $Self, %Param ) = @_;

    my $Prepared = $Self->Prepare(%Param);
    my $Language = $Self->_Language( $Param{Language} );
    my $Limit = $Param{Limit};
    my $Maximum = $Param{Browse} ? 250 : 10;
    my $Default = $Param{Browse} ? 250 : 3;
    $Limit = $Default if !defined $Limit || ref $Limit || $Limit !~ m{\A\d{1,3}\z} || $Limit < 1 || $Limit > $Maximum;

    my @Token = @{ $Prepared->{tokens} };
    return [] if !@Token;

    # The WHERE clause matches individual words. An entire sentence does not
    # have to occur verbatim in the article. Coverage and precise phrase hits
    # improve relevance, while title/keywords outweigh body-only matches.
    my @Column = qw(a.title a.keywords a.summary a.search_text a.article_number);
    my @Weight = ( 15, 10, 6, 2, 12 );
    my @PhraseWeight = ( 80, 50, 30, 10, 60 );
    my ( @Score, @ScoreBind, @Match, @MatchBind );

    for my $Text ( @{ $Prepared->{phrases} } ) {
        my $Phrase = '%' . $Self->_LikeEscape( lc $Text ) . '%';
        for my $Index ( 0 .. $#Column ) {
            push @Score, 'CASE WHEN LOWER(COALESCE(' . $Column[$Index] . ", '')) LIKE ? ESCAPE '!' THEN " . $PhraseWeight[$Index] . ' ELSE 0 END';
            push @ScoreBind, $Phrase;
        }
    }

    for my $Token (@Token) {
        my $Like = '%' . $Self->_LikeEscape($Token) . '%';
        my @Coverage;
        for my $Index ( 0 .. $#Column ) {
            my $Condition = 'LOWER(COALESCE(' . $Column[$Index] . ", '')) LIKE ? ESCAPE '!'";
            push @Score, 'CASE WHEN ' . $Condition . ' THEN ' . $Weight[$Index] . ' ELSE 0 END';
            push @ScoreBind, $Like;
            push @Coverage, $Condition;
            push @Match, $Condition;
            push @MatchBind, $Like;
        }
        push @Score, 'CASE WHEN (' . join( ' OR ', @Coverage ) . ') THEN 25 ELSE 0 END';
        push @ScoreBind, ($Like) x scalar(@Column);
    }

    my $SQL = 'SELECT a.id, a.title, a.summary,
            COALESCE(NULLIF(ct.name, \'\'), c.internal_name) AS category_name,
            (' . join( ' + ', @Score ) . ') AS suggestion_score
        FROM knowledge_article a
        INNER JOIN knowledge_category c ON c.id = a.category_id
        LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
        WHERE a.visibility = \'customer\' AND a.status = \'published\'
            AND c.active = 1 AND a.language = ?
            AND (' . join( ' OR ', @Match ) . ')
        ORDER BY suggestion_score DESC, a.changed_at DESC, a.id DESC
        LIMIT ' . int($Limit);

    # The core DB wrapper does not assign bind types. Use only the validated
    # bounded integer for LIMIT so DBD::mysql cannot quote it as a string.
    my $Rows = $Self->{DB}->SelectAll( $SQL, @ScoreBind, $Language, @MatchBind );
    die "Knowledge search unavailable\n" if !defined $Rows || ref $Rows ne 'ARRAY';

    return $Self->_Results($Rows);
}

sub Browse {
    my ( $Self, %Param ) = @_;
    my $Query = $Self->_Query( defined $Param{Query} ? $Param{Query} : '' );
    my $Language = $Self->_Language( $Param{Language} );
    return $Self->Articles( Query => $Query, Language => $Language, Limit => 250, Browse => 1 )
        if length($Query);

    # The chooser remains useful before a customer has entered any ticket text.
    # Apply exactly the same publication, audience, category and language guards.
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT a.id, a.title, a.summary,
            COALESCE(NULLIF(ct.name, \'\'), c.internal_name) AS category_name
         FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id
         LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
         WHERE a.visibility = \'customer\' AND a.status = \'published\'
            AND c.active = 1 AND a.language = ?
         ORDER BY LOWER(a.title), a.id
         LIMIT 250',
        $Language,
    );
    die "Knowledge browse unavailable\n" if !defined $Rows || ref $Rows ne 'ARRAY';
    return $Self->_Results($Rows);
}

sub _Results {
    my ( $Self, $Rows ) = @_;

    # Return only public display fields, never search text or internal metadata.
    my @Result;
    for my $Row ( @{$Rows} ) {
        next if ref $Row ne 'HASH' || !defined $Row->{id} || ref $Row->{id}
            || $Row->{id} !~ m{\A\d{1,18}\z} || $Row->{id} < 1;
        push @Result, {
            id            => 0 + $Row->{id},
            title         => $Row->{title} || '',
            summary       => $Row->{summary} || '',
            category_name => $Row->{category_name} || '',
        };
    }
    return \@Result;
}

sub Tokens {
    my ( $Self, $Query, $Limit ) = @_;
    $Query = $Self->_Text( $Query, 50000 );
    $Limit = 8 if !defined $Limit || ref $Limit || $Limit !~ m{\A\d{1,2}\z} || $Limit < 1 || $Limit > 24;
    $Query = lc $Query;
    my %Seen;
    my @Token;
    while ( $Query =~ m{([\p{L}\p{N}][\p{L}\p{N}_%\\-]*)}g ) {
        my $Token = $1;
        next if length($Token) < 2 || length($Token) > 128 || $Stopword{$Token} || $Seen{$Token}++;
        push @Token, $Token;
        last if @Token == $Limit;
    }
    return \@Token;
}

sub _Query {
    my ( $Self, $Query ) = @_;
    return $Self->_Text( $Query, 500 );
}

sub Prepare {
    my ( $Self, %Param ) = @_;
    # Separate budgets ensure a long subject never uses up all description
    # terms. SQL is bounded, while either field can independently find articles.
    my $Separate = exists $Param{Subject} || exists $Param{Description};
    my $Subject = $Separate
        ? $Self->_Text( defined $Param{Subject} ? $Param{Subject} : '', 500 )
        : $Self->_Query( defined $Param{Query} ? $Param{Query} : '' );
    my $Description = $Self->_Text( defined $Param{Description} ? $Param{Description} : '', 50000 );
    $Description = $Self->_Text( QisutuHTML->PlainTextSearch($Description), 50000 );
    my @SubjectToken = @{ $Self->Tokens( $Subject, $Separate ? 12 : 8 ) };
    my @DescriptionToken = @{ $Self->Tokens( $Description, 12 ) };
    my ( %Seen, @Token, %PhraseSeen, @Phrase );
    for my $Token ( @SubjectToken, @DescriptionToken ) {
        push @Token, $Token if !$Seen{$Token}++;
    }
    for my $Text ( $Subject, substr( $Description, 0, 500 ) ) {
        next if !length($Text) || $PhraseSeen{ lc $Text }++;
        push @Phrase, $Text;
    }
    return {
        tokens => \@Token,
        phrases => \@Phrase,
        length => length($Subject) + length($Description),
    };
}

sub _Language {
    my ( $Self, $Language ) = @_;
    die "Invalid search language\n" if !defined $Language || ref $Language
        || $Language !~ m{\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z} || length($Language) > 20;
    return $Language;
}

sub _Text {
    my ( $Self, $Query, $Maximum ) = @_;
    die "Invalid search query\n" if !defined $Query || ref $Query || length($Query) > $Maximum;
    $Query =~ s{[\x00-\x1f\x7f]}{ }g;
    $Query =~ s{\s+}{ }g;
    $Query =~ s{\A\s+|\s+\z}{}g;
    return $Query;
}

sub _LikeEscape {
    my ( $Self, $Value ) = @_;
    # Explicit ! keeps a backslash literal under both MySQL SQL modes.
    $Value =~ s{([!%_\\])}{!$1}g;
    return $Value;
}

sub SettingsGet {
    my ($Self) = @_;
    my $Store = QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my %Settings;
    for my $Pair ( [ enabled => 1 ], [ max_results => 3 ], [ minimum_length => 3 ] ) {
        $Settings{ $Pair->[0] } = $Store->Get(
            Key => 'knowledge.suggestions.' . $Pair->[0], Default => $Pair->[1],
        );
    }
    return \%Settings;
}

sub SettingsSave {
    my ( $Self, %Param ) = @_;
    my $Values = $Param{Values} || {};
    return if !defined $Values->{enabled} || ref $Values->{enabled} || $Values->{enabled} !~ m{\A[01]\z}
        || !defined $Values->{max_results} || ref $Values->{max_results} || $Values->{max_results} !~ m{\A(?:[1-9]|10)\z}
        || !defined $Values->{minimum_length} || ref $Values->{minimum_length} || $Values->{minimum_length} !~ m{\A(?:[2-9]|10)\z};
    my $Store = QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} );
    for my $Key (qw(enabled max_results minimum_length)) {
        $Store->Set(
            Key => 'knowledge.suggestions.' . $Key,
            Value => $Values->{$Key}, ChangedByUserID => $Param{UserID},
        ) || return;
    }
    return 1;
}

sub FormData {
    my ( $Self, %Param ) = @_;
    my $User = $Param{User} || {};
    my $Data = $Param{Data} || {};
    return {} if ( $User->{account_type} || '' ) ne 'customer'
        || !defined $User->{user_account_id} || ref $User->{user_account_id}
        || $User->{user_account_id} !~ m{\A[1-9][0-9]*\z};

    my $Settings = $Self->SettingsGet();
    return {} if !$Settings->{enabled};

    my $FieldName = '';
    my $BodyFieldName = '';
    if ( $Data->{ShowLegacyForm} && $Data->{HasQueueOptions} ) {
        $FieldName = 'Title';
        $BodyFieldName = 'Body';
    }
    elsif ( $Data->{ShowConfiguredForm} ) {
        my $FormID = $Data->{FormID};
        return {} if !defined $FormID || ref $FormID || $FormID !~ m{\A[1-9][0-9]*\z};
        my $Fields = $Self->{DB}->SelectAll(
            'SELECT id, field_key FROM ticket_form_field
             WHERE form_id = ? AND active = 1
               AND ((field_key = "title" AND field_type IN ("title", "text"))
                 OR (field_key = "body" AND field_type IN ("body", "textarea", "text")))
             ORDER BY sort_order, id',
            $FormID,
        );
        return {} if ref $Fields ne 'ARRAY';
        for my $Field ( @{$Fields} ) {
            next if ref $Field ne 'HASH' || !defined $Field->{id} || ref $Field->{id}
                || $Field->{id} !~ m{\A[1-9][0-9]*\z};
            my $Key = $Field->{field_key} || '';
            $FieldName = 'FormField_' . $Field->{id} if $Key eq 'title' && !$FieldName;
            $BodyFieldName = 'FormField_' . $Field->{id} if $Key eq 'body' && !$BodyFieldName;
        }
    }
    return {} if !$FieldName && !$BodyFieldName;

    my $Minimum = $Settings->{minimum_length};
    $Minimum = 3 if !defined $Minimum || ref $Minimum || $Minimum !~ m{\A(?:[2-9]|10)\z};
    return {
            ShowKnowledgeSuggestions => 1,
            KnowledgeFieldName => $FieldName,
            KnowledgeBodyFieldName => $BodyFieldName,
            KnowledgeLanguage => $Data->{Language} || $Self->{Config}->{Language}->{Default} || 'en',
            KnowledgeEndpoint => 'index.pl?Page=CustomerKnowledgeSuggestions',
            KnowledgeMinimumLength => $Minimum,
            KnowledgeDebounce => 350,
    };
}

1;
