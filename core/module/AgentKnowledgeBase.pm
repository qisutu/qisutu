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

package AgentKnowledgeBase;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json);
use QisutuKnowledgeBase;

sub new { my ( $Class, %Param ) = @_; return bless { %Param }, $Class; }

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuKnowledgeBase->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $Step     = $Request->{Step} || '';
    my $Action   = $Request->{Action} || 'List';
    my $Error    = '';
    my $AttachmentMaxSizeMB    = $Self->_AttachmentMaxSizeMB();
    my $AttachmentMaxSizeBytes = $AttachmentMaxSizeMB * 1024 * 1024;

    if ( $Step eq 'SearchJSON' ) {
        return $Self->_JSON({
            success => 1,
            items   => $Object->AgentInsertSearch(
                Query        => $Request->{Query},
                Language     => $Language,
                CustomerSafe => $Request->{CustomerSafe},
            ),
        });
    }
    if ( $Step eq 'ArticleGetJSON' ) {
        my $Article = $Object->AgentInsertArticleGet(
            ArticleID    => $Request->{ArticleID},
            CustomerSafe => $Request->{CustomerSafe},
        );
        return $Self->_JSON({ success => $Article ? 1 : 0, article => $Article || {} });
    }
    if ( $Step eq 'UsageRecord' ) {
        my $Success = $Object->UsageRecord(
            ArticleID  => $Request->{ArticleID},
            TicketID   => $Request->{TicketID},
            UserID     => $User->{user_account_id},
            Context    => $Request->{Context},
            InsertMode => $Request->{InsertMode},
        );
        return $Self->_JSON({ success => $Success ? 1 : 0 });
    }

    if ( $Step eq 'CategorySave' ) {
        my %Translations;
        for my $Code ( @{ $Self->_LanguageList() } ) {
            $Translations{$Code} = {
                name        => $Self->_Scalar( $Request->{ 'TranslationName_' . $Code } ),
                description => $Self->_Scalar( $Request->{ 'TranslationDescription_' . $Code } ),
            };
        }
        my $ID = $Object->CategorySave(
            CategoryID      => $Request->{CategoryID},
            ParentID        => $Request->{ParentID},
            InternalName    => $Request->{InternalName},
            SortOrder       => $Request->{SortOrder},
            Active          => $Request->{Active},
            Translations    => \%Translations,
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AgentKnowledgeBase;Action=CategoryEdit;CategoryID=' . $ID } if $ID;
        $Error = $Object->Error() || 'Translate:KnowledgeCategorySaveFailed';
        $Action = $Request->{CategoryID} ? 'CategoryEdit' : 'CategoryCreate';
    }
    elsif ( $Step eq 'CategoryToggle' ) {
        if ( $Object->CategoryToggle(
            CategoryID      => $Request->{CategoryID},
            Active          => $Request->{Active},
            ChangedByUserID => $User->{user_account_id},
        ) ) {
            return { Redirect => 'index.pl?Page=AgentKnowledgeBase;Action=Categories' };
        }
        $Error = $Object->Error() || 'Translate:KnowledgeCategorySaveFailed';
        $Action = 'Categories';
    }
    elsif ( $Step eq 'ArticleSave' ) {
        my $UploadResult = $Self->_UploadedAttachments(
            Request      => $Request,
            MaxSizeBytes => $AttachmentMaxSizeBytes,
        );

        if ( @{ $UploadResult->{Oversized} || [] } ) {
            $Error = $Self->_AttachmentTooLargeMessage(
                Attachment => $UploadResult->{Oversized}->[0],
                MaxSizeMB  => $AttachmentMaxSizeMB,
                Language   => $Language,
            );
        }
        else {
            my $ID = $Object->ArticleSave(
                ArticleID          => $Request->{ArticleID},
                CategoryID         => $Request->{CategoryID},
                Language           => $Request->{ArticleLanguage},
                Title              => $Request->{Title},
                Summary            => $Request->{Summary},
                Keywords           => $Request->{Keywords},
                Content            => $Request->{Content},
                Visibility         => $Request->{Visibility},
                Attachments        => $UploadResult->{Attachments},
                RemoveAttachmentIDs => $Request->{RemoveKnowledgeAttachmentID},
                ChangedByUserID    => $User->{user_account_id},
            );
            return { Redirect => 'index.pl?Page=AgentKnowledgeBase;Action=View;ArticleID=' . $ID } if $ID;
            $Error = $Object->Error() || 'Translate:KnowledgeArticleSaveFailed';
        }
        $Action = $Request->{ArticleID} ? 'Edit' : 'Create';
    }

    if ( $Action eq 'Categories' ) {
        my $Categories = $Object->CategoryList( Language => $Language, IncludeInactive => 1 );
        for my $Category ( @{$Categories} ) {
            $Category->{active_label} = $Category->{active} ? 'Translate:CommonYes' : 'Translate:CommonNo';
            $Category->{toggle_active} = $Category->{active} ? 0 : 1;
            $Category->{toggle_label} = $Category->{active} ? 'Translate:AdminDeactivate' : 'Translate:AdminActivate';
        }
        return {
            Template => 'AgentKnowledgeBase.tt',
            Data => {
                PageTitle          => 'Translate:KnowledgeCategories',
                ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
                ProgramDescription => 'Translate:KnowledgeBaseDescription',
                ShowCategories     => 1,
                Categories         => $Categories,
                CategoryCount      => scalar @{$Categories},
                ErrorMessage       => $Error,
                ErrorClass         => $Error ? '' : 'qisutu-hidden',
            },
        };
    }

    if ( $Action eq 'CategoryCreate' || $Action eq 'CategoryEdit' ) {
        my $AllCategories = $Object->CategoryList( Language => $Language, IncludeInactive => 1 );
        my $Category = $Action eq 'CategoryEdit' ? $Object->CategoryGet( CategoryID => $Request->{CategoryID} ) : {};
        if ( $Action eq 'CategoryEdit' && !$Category ) {
            $Error ||= 'Translate:KnowledgeCategoryNotFound';
            $Action = 'Categories';
        }
        else {
            my %Translation = map { ( $_->{language} || '' ) => $_ } @{ $Category->{translations} || [] };
            my @TranslationRows;
            for my $Code ( @{ $Self->_LanguageList() } ) {
                push @TranslationRows, {
                    code        => $Code,
                    name        => $Error ? $Self->_Scalar( $Request->{ 'TranslationName_' . $Code } ) : ( $Translation{$Code}->{name} || '' ),
                    description => $Error ? $Self->_Scalar( $Request->{ 'TranslationDescription_' . $Code } ) : ( $Translation{$Code}->{description} || '' ),
                    open        => $Code eq lc($Language) ? 'open' : '',
                };
            }
            return {
                Template => 'AgentKnowledgeBase.tt',
                Data => {
                    PageTitle          => $Action eq 'CategoryEdit' ? 'Translate:KnowledgeCategoryEdit' : 'Translate:KnowledgeCategoryCreate',
                    ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
                    ProgramDescription => 'Translate:KnowledgeBaseDescription',
                    ShowCategoryForm   => 1,
                    IsEdit             => $Action eq 'CategoryEdit' ? 1 : 0,
                    CategoryID         => $Category->{id} || $Request->{CategoryID} || '',
                    InternalName       => $Error ? ( $Request->{InternalName} || '' ) : ( $Category->{internal_name} || '' ),
                    SortOrder          => $Error ? ( $Request->{SortOrder} || 1000 ) : ( $Category->{sort_order} || 1000 ),
                    ActiveChecked      => $Error ? ( $Request->{Active} ? 'checked' : '' ) : ( !$Category->{id} || $Category->{active} ? 'checked' : '' ),
                    ParentOptionsHTML  => $Self->_ParentCategoryOptions(
                        Categories => $AllCategories,
                        Selected   => $Error ? $Request->{ParentID} : $Category->{parent_id},
                        Exclude    => $Category->{id} || 0,
                        Language   => $Language,
                    ),
                    TranslationRows => \@TranslationRows,
                    ErrorMessage    => $Error,
                    ErrorClass      => $Error ? '' : 'qisutu-hidden',
                },
            };
        }
    }

    my $Categories = $Object->CategoryList( Language => $Language );

    if ( $Action eq 'View' ) {
        my $Article = $Object->ArticleGet( ArticleID => $Request->{ArticleID} );
        if (!$Article) {
            $Action = 'List';
            $Error ||= 'Translate:KnowledgeArticleNotFound';
        }
        else {
            return {
                Template => 'AgentKnowledgeBase.tt',
                Data => {
                    PageTitle          => $Article->{title},
                    ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
                    ProgramDescription => 'Translate:KnowledgeBaseDescription',
                    ShowArticle        => 1,
                    ArticleID          => $Article->{id},
                    ArticleNumber      => $Article->{article_number},
                    ArticleTitle       => $Article->{title},
                    ArticleSummary     => $Article->{summary},
                    ArticleContent     => $Article->{content},
                    ArticleCategory    => $Article->{category_name},
                    ArticleLanguage    => uc( $Article->{language} || '' ),
                    ArticleVisibility  => 'Translate:KnowledgeVisibility_' . ( $Article->{visibility} || 'internal' ),
                    ArticleRevision    => $Article->{revision_number},
                    ArticleAttachments => $Article->{attachments} || [],
                    HasArticleAttachments => $Article->{has_attachments} ? 1 : 0,
                    Revisions          => $Self->_RevisionRows( $Article->{revisions} || [] ),
                },
            };
        }
    }

    if ( $Action eq 'Create' || $Action eq 'Edit' ) {
        my $Article = $Action eq 'Edit' ? $Object->ArticleGet( ArticleID => $Request->{ArticleID} ) : {};
        if ( $Action eq 'Edit' && !$Article ) {
            $Action = 'List';
            $Error ||= 'Translate:KnowledgeArticleNotFound';
        }
        else {
            my $Visibility = $Error ? ( $Request->{Visibility} || 'internal' ) : ( $Article->{visibility} || 'internal' );
            return {
                Template => 'AgentKnowledgeBase.tt',
                Data => {
                    PageTitle            => $Action eq 'Edit' ? 'Translate:KnowledgeArticleEdit' : 'Translate:KnowledgeArticleCreate',
                    ProgramTitle         => 'Translate:KnowledgeBaseNavigation',
                    ProgramDescription   => 'Translate:KnowledgeBaseDescription',
                    ShowForm             => 1,
                    IsEdit               => $Action eq 'Edit' ? 1 : 0,
                    ArticleID            => $Article->{id} || $Request->{ArticleID} || '',
                    Title                => $Error ? ( $Request->{Title} || '' ) : ( $Article->{title} || '' ),
                    Summary              => $Error ? ( $Request->{Summary} || '' ) : ( $Article->{summary} || '' ),
                    Keywords             => $Error ? ( $Request->{Keywords} || '' ) : ( $Article->{keywords} || '' ),
                    Content              => $Error ? ( $Request->{Content} || '' ) : ( $Article->{content} || '' ),
                    CategoryOptionsHTML  => $Self->_CategoryOptions( Categories => $Categories, Selected => $Error ? $Request->{CategoryID} : $Article->{category_id}, Language => $Language ),
                    LanguageOptionsHTML  => $Self->_LanguageOptions( Selected => $Error ? $Request->{ArticleLanguage} : $Article->{language}, Language => $Language ),
                    VisibilityOptionsHTML => $Self->_Options( [ [internal => 'KnowledgeVisibility_internal'], [customer => 'KnowledgeVisibility_customer'] ], $Visibility, $Language ),
                    ArticleAttachments  => $Article->{attachments} || [],
                    HasArticleAttachments => $Article->{has_attachments} ? 1 : 0,
                    AttachmentMaxSizeMB => $AttachmentMaxSizeMB,
                    AttachmentMaxSizeBytes => $AttachmentMaxSizeBytes,
                    ErrorMessage         => $Error,
                    ErrorClass           => $Error ? '' : 'qisutu-hidden',
                },
            };
        }
    }

    my $Articles = $Object->ArticleList(
        Query      => $Request->{Query},
        CategoryID => $Request->{CategoryID},
        Language   => $Request->{ArticleLanguage},
        Limit      => 250,
    );
    for my $Article ( @{$Articles} ) {
        $Article->{url} = 'index.pl?Page=AgentKnowledgeBase;Action=View;ArticleID=' . ( $Article->{id} || 0 );
        $Article->{visibility_label} = 'Translate:KnowledgeVisibility_' . ( $Article->{visibility} || 'internal' );
    }
    return {
        Template => 'AgentKnowledgeBase.tt',
        Data => {
            PageTitle          => 'Translate:KnowledgeBaseNavigation',
            ProgramTitle       => 'Translate:KnowledgeBaseNavigation',
            ProgramDescription => 'Translate:KnowledgeBaseDescription',
            ShowList           => 1,
            Articles           => $Articles,
            ArticleCount       => scalar @{$Articles},
            HasArticles        => @{$Articles} ? 1 : 0,
            Query              => $Request->{Query} || '',
            CategoryOptionsHTML => $Self->_CategoryOptions( Categories => $Categories, Selected => $Request->{CategoryID}, IncludeAll => 1, Language => $Language ),
            FilterLanguageOptionsHTML => $Self->_LanguageOptions( Selected => $Request->{ArticleLanguage}, IncludeAll => 1, Language => $Language ),
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
        },
    };
}

sub _JSON {
    my ( $Self, $Data ) = @_;
    return { Response => $Self->{Output}->Response(
        ContentType => 'application/json; charset=UTF-8', Headers => [ 'Cache-Control: no-store' ], Body => encode_json( $Data || {} ),
    ) };
}

sub _UploadedAttachments {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $MaxSizeBytes = $Param{MaxSizeBytes} || 0;
    my $Uploads      = $Request->{__Uploads} || {};
    my $RawList      = [];

    if ( ref $Uploads->{KnowledgeAttachment} eq 'ARRAY' ) {
        $RawList = $Uploads->{KnowledgeAttachment};
    }
    elsif ( ref $Uploads->{'KnowledgeAttachment[]'} eq 'ARRAY' ) {
        $RawList = $Uploads->{'KnowledgeAttachment[]'};
    }

    my @Attachments;
    my @Oversized;
    for my $Upload ( @{$RawList} ) {
        next if ref $Upload ne 'HASH';

        my $Filename = $Upload->{Filename} || '';
        $Filename =~ s{\\}{/}g;
        $Filename =~ s{\A.*/}{}g;
        $Filename =~ s{[\r\n\x00]}{}g;
        $Filename =~ s{\A\s+|\s+\z}{}g;
        next if !$Filename;

        my $Content = $Upload->{Content};
        next if !defined $Content;
        my $Size = $Upload->{ContentSize};
        $Size = length($Content) if !defined $Size || $Size !~ m{\A\d+\z};

        my $Attachment = {
            Filename           => $Filename,
            ContentType        => $Upload->{ContentType} || 'application/octet-stream',
            Content            => $Content,
            ContentSize        => $Size,
            ContentDisposition => 'attachment',
        };

        if ( $MaxSizeBytes && $Size > $MaxSizeBytes ) {
            push @Oversized, $Attachment;
        }
        else {
            push @Attachments, $Attachment;
        }
    }

    return { Attachments => \@Attachments, Oversized => \@Oversized };
}

sub _AttachmentMaxSizeMB {
    my ($Self) = @_;

    my $Value = 25;
    my $Loaded = eval { require QisutuSystemSetting; 1; };
    if ( $Loaded && $Self->{DB} ) {
        $Value = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        )->AttachmentMaxSizeMB();
    }
    return $Value;
}

sub _AttachmentTooLargeMessage {
    my ( $Self, %Param ) = @_;

    my $Message = $Self->_T( 'KnowledgeAttachmentTooLarge', $Param{Language} );
    my $Filename = $Param{Attachment}->{Filename} || 'attachment';
    my $Maximum  = ( $Param{MaxSizeMB} || 25 ) . ' MB';
    $Message =~ s{\{\{Filename\}\}}{$Filename}g;
    $Message =~ s{\{\{MaxSize\}\}}{$Maximum}g;
    return $Message;
}

sub _CategoryOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = $Param{IncludeAll} ? '<option value="">' . $Self->_E( $Self->_T( 'KnowledgeAllCategories', $Param{Language} ) ) . '</option>' : '<option value="">' . $Self->_E( $Self->_T( 'KnowledgeSelectCategory', $Param{Language} ) ) . '</option>';
    for my $Category ( @{ $Param{Categories} || [] } ) {
        my $Selected = ( $Category->{id} || 0 ) == ( $Param{Selected} || 0 ) ? ' selected' : '';
        $HTML .= '<option value="' . int( $Category->{id} || 0 ) . '"' . $Selected . '>' . $Self->_E( $Category->{display_name} || $Category->{name} ) . '</option>';
    }
    return $HTML;
}

sub _ParentCategoryOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '<option value="0">' . $Self->_E( $Self->_T( 'KnowledgeCategoryNoParent', $Param{Language} ) ) . '</option>';
    for my $Category ( @{ $Param{Categories} || [] } ) {
        next if ( $Category->{id} || 0 ) == ( $Param{Exclude} || 0 );
        my $Selected = ( $Category->{id} || 0 ) == ( $Param{Selected} || 0 ) ? ' selected' : '';
        $HTML .= '<option value="' . int( $Category->{id} || 0 ) . '"' . $Selected . '>' . $Self->_E( $Category->{display_name} || $Category->{name} ) . '</option>';
    }
    return $HTML;
}

sub _LanguageOptions {
    my ( $Self, %Param ) = @_;
    my @Codes = @{ $Self->_LanguageList() };
    my $HTML = $Param{IncludeAll} ? '<option value="">' . $Self->_E( $Self->_T( 'KnowledgeAllLanguages', $Param{Language} ) ) . '</option>' : '';
    my $SelectedValue = $Param{Selected} || ( $Param{IncludeAll} ? '' : $Param{Language} || 'en' );
    for my $Code (@Codes) {
        my $Selected = $Code eq $SelectedValue ? ' selected' : '';
        $HTML .= '<option value="' . $Code . '"' . $Selected . '>' . uc($Code) . '</option>';
    }
    return $HTML;
}

sub _LanguageList {
    my ($Self) = @_;
    my $Path = $Self->{Config}->{Paths}->{Language};
    my @Code;
    if ( $Path && opendir my $DH, $Path ) {
        @Code = sort map {
            my ($Code) = m{\A([A-Za-z0-9_-]+)\.pm\z};
            $Code =~ tr{_}{-};
            if ( $Code =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
                $Code = lc($1) . '-' . uc($2);
            }
            else {
                $Code = lc $Code;
            }
            $Code;
        } grep { m{\A[A-Za-z0-9_-]+\.pm\z} } readdir $DH;
        closedir $DH;
    }
    return \@Code if @Code;
    return [ $Self->{Config}->{Language}->{Default} || 'en' ];
}

sub _Options {
    my ( $Self, $Options, $Selected, $Language ) = @_;
    my $HTML = '';
    for my $Option ( @{$Options || []} ) {
        my ( $Value, $Key ) = @{$Option};
        my $Attribute = $Value eq ( $Selected || '' ) ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_E($Value) . '"' . $Attribute . '>' . $Self->_E( $Self->_T( $Key, $Language ) ) . '</option>';
    }
    return $HTML;
}

sub _RevisionRows {
    my ( $Self, $Rows ) = @_;
    for my $Row ( @{$Rows || []} ) {
        $Row->{visibility_label} = 'Translate:KnowledgeVisibility_' . ( $Row->{visibility} || 'internal' );
        $Row->{actor} = $Row->{changed_by_name} || $Row->{changed_by_login} || '-';
    }
    return $Rows || [];
}

sub _Scalar { my ( $Self, $Value ) = @_; return ref $Value eq 'ARRAY' ? ( $Value->[-1] || '' ) : ( $Value || '' ); }
sub _T { my ( $Self, $Key, $Language ) = @_; return $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' ); }
sub _E { my ( $Self, $Value ) = @_; return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' ); }

1;
