# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminKnowledgeBase;

use strict;
use warnings;
use utf8;

use QisutuKnowledgeBase;

sub new {
    my ( $Class, %Param ) = @_;
    return bless { %Param }, $Class;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Action   = $Request->{Action} || 'List';
    my $Step     = $Request->{Step} || '';
    my $Object   = QisutuKnowledgeBase->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $Error    = '';

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
        return { Redirect => 'index.pl?Page=AdminKnowledgeBase;Action=Edit;CategoryID=' . $ID } if $ID;
        $Error = $Object->Error() || 'Translate:KnowledgeCategorySaveFailed';
        $Action = $Request->{CategoryID} ? 'Edit' : 'Create';
    }
    elsif ( $Step eq 'CategoryToggle' ) {
        if ( $Object->CategoryToggle(
            CategoryID      => $Request->{CategoryID},
            Active          => $Request->{Active},
            ChangedByUserID => $User->{user_account_id},
        ) ) {
            return { Redirect => 'index.pl?Page=AdminKnowledgeBase' };
        }
        $Error = $Object->Error() || 'Translate:KnowledgeCategorySaveFailed';
    }
    elsif ( $Step eq 'PermissionsSave' ) {
        my %Assignments;
        for my $Group ( @{ $Object->GroupPermissionList() } ) {
            my $ID = $Group->{id} || 0;
            $Assignments{$ID} = {
                view    => $Request->{ 'PermissionView_' . $ID } ? 1 : 0,
                edit    => $Request->{ 'PermissionEdit_' . $ID } ? 1 : 0,
                publish => $Request->{ 'PermissionPublish_' . $ID } ? 1 : 0,
            };
        }
        if ( $Object->GroupPermissionSet( Assignments => \%Assignments, ChangedByUserID => $User->{user_account_id} ) ) {
            return { Redirect => 'index.pl?Page=AdminKnowledgeBase;Saved=Permissions' };
        }
        $Error = $Object->Error() || 'Translate:KnowledgePermissionsSaveFailed';
    }

    my $Categories = $Object->CategoryList( Language => $Language, IncludeInactive => 1 );
    for my $Category ( @{$Categories} ) {
        $Category->{active_label} = $Category->{active} ? 'Translate:CommonYes' : 'Translate:CommonNo';
        $Category->{toggle_active} = $Category->{active} ? 0 : 1;
        $Category->{toggle_label} = $Category->{active} ? 'Translate:AdminDeactivate' : 'Translate:AdminActivate';
    }
    my $Category = ( $Action eq 'Edit' ) ? $Object->CategoryGet( CategoryID => $Request->{CategoryID} ) : undef;
    if ( $Action eq 'Edit' && !$Category ) {
        $Action = 'List';
        $Error ||= 'Translate:KnowledgeCategoryNotFound';
    }
    my %Translation = map { ( $_->{language} || '' ) => $_ } @{ $Category->{translations} || [] };
    my @TranslationRows;
    for my $Code ( @{ $Self->_LanguageList() } ) {
        push @TranslationRows, {
            code        => $Code,
            name        => $Translation{$Code}->{name} || '',
            description => $Translation{$Code}->{description} || '',
            open        => $Code eq $Language ? 'open' : '',
        };
    }

    return {
        Template => 'AdminKnowledgeBase.tt',
        Data => {
            PageTitle          => 'Translate:AdminKnowledgeBaseTitle',
            ProgramTitle       => 'Translate:AdminKnowledgeBaseTitle',
            ProgramDescription => 'Translate:AdminKnowledgeBaseDescription',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowForm           => $Action eq 'Create' || $Action eq 'Edit' ? 1 : 0,
            IsEdit             => $Action eq 'Edit' ? 1 : 0,
            Categories         => $Categories,
            CategoryCount      => scalar @{$Categories},
            CategoryID         => $Category ? $Category->{id} : '',
            InternalName       => $Category ? $Category->{internal_name} : '',
            SortOrder          => $Category ? $Category->{sort_order} : 1000,
            ActiveChecked      => !$Category || $Category->{active} ? 'checked' : '',
            ParentOptionsHTML  => $Self->_CategoryOptions( Categories => $Categories, Selected => $Category ? $Category->{parent_id} : 0, Exclude => $Category ? $Category->{id} : 0, Language => $Language ),
            TranslationRows    => \@TranslationRows,
            PermissionGroups   => $Self->_PermissionRows( $Object->GroupPermissionList() ),
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            SavedMessage       => $Request->{Saved} ? 'Translate:KnowledgePermissionsSaved' : '',
            SavedClass         => $Request->{Saved} ? '' : 'qisutu-hidden',
        },
    };
}

sub _PermissionRows {
    my ( $Self, $Groups ) = @_;
    for my $Group ( @{$Groups || []} ) {
        $Group->{view_checked}    = $Group->{can_view} ? 'checked' : '';
        $Group->{edit_checked}    = $Group->{can_edit} ? 'checked' : '';
        $Group->{publish_checked} = $Group->{can_publish} ? 'checked' : '';
    }
    return $Groups || [];
}

sub _CategoryOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '<option value="0">' . $Self->_E( $Self->_T( 'KnowledgeCategoryNoParent', $Param{Language} ) ) . '</option>';
    for my $Category ( @{ $Param{Categories} || [] } ) {
        next if ( $Category->{id} || 0 ) == ( $Param{Exclude} || 0 );
        my $Selected = ( $Category->{id} || 0 ) == ( $Param{Selected} || 0 ) ? ' selected' : '';
        $HTML .= '<option value="' . int( $Category->{id} || 0 ) . '"' . $Selected . '>' . $Self->_E( $Category->{display_name} || $Category->{name} ) . '</option>';
    }
    return $HTML;
}

sub _LanguageList {
    my ($Self) = @_;
    my $Path = $Self->{Config}->{Paths}->{Language};
    my @Code;
    if ( $Path && opendir my $DH, $Path ) {
        @Code = sort map { /^([A-Za-z0-9_-]+)\.pm$/ ? lc($1) : () } readdir $DH;
        closedir $DH;
    }
    return \@Code if @Code;
    return [ $Self->{Config}->{Language}->{Default} || 'en' ];
}

sub _Scalar { my ( $Self, $Value ) = @_; return ref $Value eq 'ARRAY' ? ( $Value->[-1] || '' ) : ( $Value || '' ); }
sub _T { my ( $Self, $Key, $Language ) = @_; return $Self->{Output}->Translate( Key => $Key, Language => $Language || 'en' ); }
sub _E { my ( $Self, $Value ) = @_; return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' ); }

1;
