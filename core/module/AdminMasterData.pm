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

package AdminMasterData;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition();
    my $Request    = $Param{Request} || {};
    my $User       = $Param{User}    || {};
    my $Admin      = $Self->_AdminObject();
    my $Step       = $Request->{Step} || '';
    my $Language   = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    if ( $Admin && $Step eq $Definition->{CreateStep} ) {
        my $CreateMethod = $Definition->{CreateMethod};

        $Admin->$CreateMethod(
            Name            => $Request->{Name},
            $Definition->{ValueParam} => $Request->{Value},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=' . $Definition->{Page} } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq $Definition->{UpdateStep} ) {
        my $UpdateMethod = $Definition->{UpdateMethod};

        $Admin->$UpdateMethod(
            $Definition->{IDParam} => $Request->{ItemID},
            Name            => $Request->{Name},
            $Definition->{ValueParam} => $Request->{Value},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=' . $Definition->{Page} . ';Action=Edit;ItemID=' . ( $Request->{ItemID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq $Definition->{DeactivateStep} ) {
        my $DeactivateMethod = $Definition->{DeactivateMethod};

        $Admin->$DeactivateMethod(
            $Definition->{IDParam} => $Request->{ItemID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=' . $Definition->{Page} } if !$Admin->Error();
    }

    my $Action     = $Request->{Action} || 'List';
    my $ListMethod = $Definition->{ListMethod};
    my $ItemList   = $Admin ? $Admin->$ListMethod( IncludeInactive => 1 ) : [];
    my $Item;

    for my $ListItem ( @{$ItemList} ) {
        next if ref $ListItem ne 'HASH';

        $ListItem->{value} = $ListItem->{ $Definition->{ValueColumn} } || '';
        $ListItem->{value_preview} = $Self->_ValuePreview(
            Value    => $ListItem->{value},
            RichText => $Definition->{RichText},
        );
    }

    if ( $Admin && $Action eq 'Edit' ) {
        my $GetMethod = $Definition->{GetMethod};

        $Item = $Admin->$GetMethod(
            $Definition->{IDParam} => $Request->{ItemID},
        );

        if ( !$Item ) {
            $Action = 'List';
        }
        else {
            $Item->{value} = $Item->{ $Definition->{ValueColumn} } || '';
        }
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';

    return {
        Template => $Definition->{Template},
        Data     => {
            PageTitle          => 'Translate:' . $Definition->{Title},
            ProgramTitle       => 'Translate:' . $Definition->{Title},
            ProgramDescription => 'Translate:' . $Definition->{Description},
            ListTitle          => 'Translate:' . $Definition->{ListTitle},
            CreateTitle        => 'Translate:' . $Definition->{CreateTitle},
            EditTitle          => 'Translate:' . $Definition->{EditTitle},
            ValueLabel         => 'Translate:' . $Definition->{ValueLabel},
            PageName           => $Definition->{Page},
            CreateStep         => $Definition->{CreateStep},
            UpdateStep         => $Definition->{UpdateStep},
            DeactivateStep     => $Definition->{DeactivateStep},
            ValueIsTextarea    => $Definition->{ValueIsTextarea} ? 1 : 0,
            ItemList           => $ItemList,
            ItemCount          => scalar @{$ItemList},
            ItemID             => $Item ? $Item->{id} : '',
            ItemName           => $Item ? $Item->{name} : '',
            ItemValue          => $Item ? $Item->{value} : '',
            ItemSortOrder      => $Item ? $Item->{sort_order} : 1000,
            ItemActiveChecked  => $Item && $Item->{active} ? 'checked' : '',
            CreateValueFieldHTML => $Self->_ValueFieldHTML(
                LabelKey => $Definition->{ValueLabel},
                Textarea => $Definition->{ValueIsTextarea},
                RichText => $Definition->{RichText},
                Value    => '',
                Language => $Language,
            ),
            EditValueFieldHTML => $Self->_ValueFieldHTML(
                LabelKey => $Definition->{ValueLabel},
                Textarea => $Definition->{ValueIsTextarea},
                RichText => $Definition->{RichText},
                Value    => $Item ? $Item->{value} : '',
                Language => $Language,
            ),
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
        },
    };
}

sub _ValueFieldHTML {
    my ( $Self, %Param ) = @_;

    my $LabelKey = $Param{LabelKey} || '';
    my $Value    = $Self->_Escape( $Param{Value} );
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Label    = $LabelKey;

    if ( $Self->{Output} && $LabelKey ) {
        $Label = $Self->{Output}->Translate(
            Key      => $LabelKey,
            Language => $Language,
        );
    }

    $Label = $Self->_Escape($Label);

    if ( $Param{Textarea} ) {
        my $FieldClass = $Param{RichText} ? ' qisutu-form-field-richtext' : '';
        my $Class      = $Param{RichText} ? ' class="qisutu-richtext"' : '';
        my $Required   = $Param{RichText} ? '' : ' required';
        return '<div class="qisutu-form-field' . $FieldClass . '"><label>' . $Label . '</label><textarea name="Value"' . $Class . $Required . '>' . $Value . '</textarea></div>';
    }

    return '<div class="qisutu-form-field"><label>' . $Label . '</label><input type="text" name="Value" value="' . $Value . '" required></div>';
}

sub _ValuePreview {
    my ( $Self, %Param ) = @_;

    my $Value = $Param{Value} || '';

    if ( $Param{RichText} ) {
        my $Loaded = eval {
            require QisutuHTML;
            1;
        };

        return QisutuHTML->PlainTextPreview( $Value, 120 ) if $Loaded;
    }

    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub _AdminObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuAdmin;
        1;
    };

    return if !$Loaded;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

1;
