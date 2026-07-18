# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

package CustomerKnowledgeBase;

use strict;
use warnings;
use utf8;

use QisutuKnowledgeBase;

sub new { my ( $Class, %Param ) = @_; return bless { %Param }, $Class; }

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuKnowledgeBase->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $CustomerID = $Object->CustomerIDFromUser( UserID => $User->{user_account_id} );
    my $Action   = $Request->{Action} || 'List';

    if ( $Action eq 'View' ) {
        my $Article = $Object->CustomerArticleGet(
            ArticleID  => $Request->{ArticleID},
            CustomerID => $CustomerID,
            Language   => $Language,
        );
        return {
            Template => 'CustomerKnowledgeBase.tt',
            Data => {
                PageTitle          => $Article ? $Article->{title} : 'Translate:KnowledgeArticleNotFound',
                ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
                ProgramDescription => 'Translate:KnowledgeBaseCustomerDescription',
                ShowArticle        => $Article ? 1 : 0,
                ArticleFound       => $Article ? 1 : 0,
                ArticleNumber      => $Article ? $Article->{article_number} : '',
                ArticleTitle       => $Article ? $Article->{title} : '',
                ArticleSummary     => $Article ? $Article->{summary} : '',
                ArticleCategory    => $Article ? $Article->{category_name} : '',
                ArticleContent     => $Article ? $Article->{content} : '',
            },
        };
    }

    my $Articles = $Object->CustomerArticleList(
        CustomerID => $CustomerID,
        Language   => $Language,
        CategoryID => $Request->{CategoryID},
        Query      => $Request->{Query},
    );
    my $Categories = $Object->CustomerCategoryList(
        CustomerID => $CustomerID,
        Language   => $Language,
    );
    for my $Article ( @{$Articles} ) {
        $Article->{url} = 'index.pl?Page=CustomerKnowledgeBase;Action=View;ArticleID=' . ( $Article->{id} || 0 );
    }
    return {
        Template => 'CustomerKnowledgeBase.tt',
        Data => {
            PageTitle          => 'Translate:KnowledgeBaseNavigation',
            ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
            ProgramDescription => 'Translate:KnowledgeBaseCustomerDescription',
            ShowList           => 1,
            Articles           => $Articles,
            ArticleCount       => scalar @{$Articles},
            HasArticles        => @{$Articles} ? 1 : 0,
            Categories         => $Categories,
            Query              => $Request->{Query} || '',
            CategoryOptionsHTML => $Self->_CategoryOptions( Categories => $Categories, Selected => $Request->{CategoryID}, Language => $Language ),
        },
    };
}

sub _CategoryOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '<option value="">' . $Self->_E( $Self->_T( 'KnowledgeAllCategories', $Param{Language} ) ) . '</option>';
    for my $Category ( @{ $Param{Categories} || [] } ) {
        my $Selected = ( $Category->{id} || 0 ) == ( $Param{Selected} || 0 ) ? ' selected' : '';
        $HTML .= '<option value="' . int( $Category->{id} || 0 ) . '"' . $Selected . '>' . $Self->_E( $Category->{display_name} || $Category->{name} ) . '</option>';
    }
    return $HTML;
}
sub _T { my ( $Self, $Key, $Language ) = @_; return $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' ); }
sub _E { my ( $Self, $Value ) = @_; return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' ); }
1;
