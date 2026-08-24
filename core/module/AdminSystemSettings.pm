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

package AdminSystemSettings;

use strict;
use warnings;
use utf8;

use File::Path qw(make_path);
use File::Spec;

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

    my $Request    = $Param{Request} || {};
    my $User       = $Param{User} || {};
    my $Language   = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Action     = $Request->{Action} || 'List';
    my $SettingKey = $Request->{SettingKey} || '';
    my $Error      = '';
    my $Success    = '';
    my $ShowDatabasePassword = ( ( $Request->{Step} || '' ) eq 'DatabasePasswordShow' ) ? 1 : 0;

    my $SettingObject = $Self->_SettingObject();

    if ( !$SettingObject ) {
        $Error  = 'System settings module could not be loaded';
        $Action = 'List';
    }
    elsif ( ( $Request->{Step} || '' ) eq 'SystemSettingUpdate' ) {
        my $Setting = $Self->_SettingGet(
            SettingObject => $SettingObject,
            SettingKey    => $SettingKey,
        );

        if ( !$Setting ) {
            $Error  = 'System setting was not found';
            $Action = 'List';
        }
        else {
            my $Value;

            if ( ( $Setting->{type} || '' ) eq 'image' ) {
                my ( $ImageValue, $ImageError ) = $Self->_ImageUploadSave(
                    Request => $Request,
                );

                if ($ImageError) {
                    $Error  = $ImageError;
                    $Action = 'Edit';
                }
                elsif ($ImageValue) {
                    $Value = $ImageValue;
                }
                else {
                    $Error  = 'Bitte wählen Sie eine PNG-, JPEG- oder GIF-Datei aus.';
                    $Action = 'Edit';
                }
            }
            elsif ( ( $Setting->{type} || '' ) eq 'boolean' ) {
                $Value = exists $Request->{SettingValue} && $Request->{SettingValue} ? 1 : 0;
            }
            else {
                $Value = exists $Request->{SettingValue} ? $Request->{SettingValue} : '';
            }

            if ( !$Error &&
                $SettingObject->Set(
                    Key             => $SettingKey,
                    Value           => $Value,
                    ChangedByUserID => $User->{user_account_id},
                )
                )
            {
                return {
                    Redirect => 'index.pl?Page=AdminSystemSettings;Action=Edit;SettingKey=' . $Self->_URLEncode($SettingKey) . ';Saved=1',
                };
            }

            $Error  = $SettingObject->Error() || 'System setting could not be saved' if !$Error;
            $Action = 'Edit';
        }
    }

    if ( $Request->{Saved} ) {
        $Success = 'Translate:AdminSystemSettingsSaved';
    }

    my $SettingList = $SettingObject ? $SettingObject->SettingList() : [];
    my $CurrentSetting;

    if ( $SettingObject && $Action eq 'Edit' ) {
        $CurrentSetting = $Self->_SettingGet(
            SettingObject => $SettingObject,
            SettingKey    => $SettingKey,
        );

        if ( !$CurrentSetting ) {
            $Error ||= 'System setting was not found';
            $Action = 'List';
        }
    }

    my $SettingListHTML = $Self->_SettingListHTML(
        SettingList => $SettingList,
        Language    => $Language,
    );

    my $CurrentName        = '';
    my $CurrentDescription = '';
    my $CurrentKey         = '';
    my $CurrentValue       = '';
    my $CurrentInputHTML   = '';
    my $CurrentType        = '';

    if ($CurrentSetting) {
        $CurrentName = $Self->_ValueTranslate(
            Value    => $CurrentSetting->{name} || $CurrentSetting->{key},
            Language => $Language,
        );
        $CurrentDescription = $Self->_ValueTranslate(
            Value    => $CurrentSetting->{description} || '',
            Language => $Language,
        );
        $CurrentKey       = $CurrentSetting->{key} || '';
        $CurrentValue     = defined $CurrentSetting->{value} ? $CurrentSetting->{value} : '';
        $CurrentType      = $CurrentSetting->{type} || 'text';
        $CurrentInputHTML = $Self->_InputHTML(
            Setting  => $CurrentSetting,
            Language => $Language,
        );
    }

    return {
        Template => 'AdminSystemSettings.tt',
        Data     => {
            PageTitle          => 'Translate:AdminSystemSettingsTitle',
            ProgramTitle       => 'Translate:AdminSystemSettingsTitle',
            ProgramDescription => 'Translate:AdminSystemSettingsDescription',
            SettingCount       => scalar @{$SettingList},
            SettingListHTML    => $SettingListHTML,
            CurrentName        => $CurrentName,
            CurrentDescription => $CurrentDescription,
            CurrentKey         => $CurrentKey,
            CurrentValue       => $CurrentValue,
            CurrentType        => $CurrentType,
            CurrentInputHTML   => $CurrentInputHTML,
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            SuccessMessage     => $Success,
            SuccessClass       => $Success ? '' : 'qisutu-hidden',
            DatabaseHost       => $Self->{Config}->{Database}->{Host} || '',
            DatabasePort       => $Self->{Config}->{Database}->{Port} || '',
            DatabaseName       => $Self->{Config}->{Database}->{Name} || '',
            DatabaseUser       => $Self->{Config}->{Database}->{User} || '',
            DatabasePassword   => $ShowDatabasePassword
                ? ( $Self->{Config}->{Database}->{Password} || '' )
                : '••••••••••••••••',
            ShowDatabasePassword => $ShowDatabasePassword,
            FormAction         => 'index.pl',
        },
    };
}

sub _SettingObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuSystemSetting;
        1;
    };

    return if !$Loaded;

    return QisutuSystemSetting->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _SettingGet {
    my ( $Self, %Param ) = @_;

    my $SettingObject = $Param{SettingObject};
    my $SettingKey    = $Param{SettingKey} || '';

    return if !$SettingObject || !$SettingKey;

    for my $Setting ( @{ $SettingObject->SettingList() } ) {
        next if ( $Setting->{key} || '' ) ne $SettingKey;
        return $Setting;
    }

    return;
}

sub _SettingListHTML {
    my ( $Self, %Param ) = @_;

    my $SettingList = $Param{SettingList} || [];
    my $Language    = $Param{Language} || 'en';
    my $HTML        = '';
    my $LastGroup   = '';

    for my $Setting ( @{$SettingList} ) {
        my $Group = $Self->_ValueTranslate(
            Value    => $Setting->{group} || $Setting->{module} || 'System',
            Language => $Language,
        );

        if ( $Group ne $LastGroup ) {
            $HTML .= '<tr class="qisutu-system-settings-group"><th colspan="4">'
                . $Self->_Escape($Group)
                . '</th></tr>';
            $LastGroup = $Group;
        }

        my $Name = $Self->_ValueTranslate(
            Value    => $Setting->{name} || $Setting->{key},
            Language => $Language,
        );
        my $Description = $Self->_ValueTranslate(
            Value    => $Setting->{description} || '',
            Language => $Language,
        );
        my $Value        = $Self->_DisplayValue( Setting => $Setting, Language => $Language, Field => 'value' );
        my $EditURL      = 'index.pl?Page=AdminSystemSettings;Action=Edit;SettingKey=' . $Self->_URLEncode( $Setting->{key} || '' );

        $HTML .= '<tr>';
        $HTML .= '<td class="qisutu-system-settings-name">';
        $HTML .= '<a class="qisutu-table-link" href="' . $Self->_Escape($EditURL) . '">' . $Self->_Escape($Name) . '</a>';
        if ($Description) {
            $HTML .= '<span>' . $Self->_Escape($Description) . '</span>';
        }
        $HTML .= '</td>';
        $HTML .= '<td><code class="qisutu-system-settings-key">' . $Self->_Escape( $Setting->{key} ) . '</code></td>';
        $HTML .= '<td class="qisutu-system-settings-value">' . $Self->_Escape($Value) . '</td>';
        $HTML .= '<td><a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="' . $Self->_Escape($EditURL) . '">'
            . $Self->_Escape( $Self->_Translate( Key => 'AdminEdit', Language => $Language ) || 'Edit' )
            . '</a></td>';
        $HTML .= '</tr>';
    }

    if ( !$HTML ) {
        $HTML = '<tr><td colspan="4">' . $Self->_Escape( $Self->_Translate( Key => 'AdminNoEntries', Language => $Language ) || 'No entries' ) . '</td></tr>';
    }

    return $HTML;
}

sub _InputHTML {
    my ( $Self, %Param ) = @_;

    my $Setting  = $Param{Setting} || {};
    my $Language = $Param{Language} || 'en';
    my $Value    = defined $Setting->{value} ? $Setting->{value} : '';
    my $Type     = $Setting->{type} || 'text';

    if ( $Type eq 'select' ) {
        my $HTML = '<select name="SettingValue">';

        for my $Option ( @{ $Setting->{possible_values} || [] } ) {
            my $OptionValue = defined $Option->{value} ? $Option->{value} : '';
            my $OptionLabel = $Self->_ValueTranslate(
                Value    => defined $Option->{label} ? $Option->{label} : $OptionValue,
                Language => $Language,
            );
            my $Selected = $OptionValue eq $Value ? ' selected' : '';

            $HTML .= '<option value="' . $Self->_Escape($OptionValue) . '"' . $Selected . '>'
                . $Self->_Escape($OptionLabel)
                . '</option>';
        }

        $HTML .= '</select>';
        return $HTML;
    }

    if ( $Type eq 'textarea' ) {
        return '<textarea name="SettingValue" rows="6">' . $Self->_Escape($Value) . '</textarea>';
    }

    if ( $Type eq 'boolean' ) {
        my $Checked = $Value ? ' checked' : '';
        return '<label class="qisutu-form-checkbox"><input type="checkbox" name="SettingValue" value="1"'
            . $Checked
            . '> <span>'
            . $Self->_Escape( $Self->_Translate( Key => 'AdminActiveYes', Language => $Language ) || 'Yes' )
            . '</span></label>';
    }

    if ( $Type eq 'image' ) {
        my $Current = $Value
            ? '<p><strong>Aktuelles eigenes Logo:</strong> ' . $Self->_Escape($Value) . '</p>'
            : '<p>Aktuell wird das mitgelieferte kleine Qisutu-Logo verwendet.</p>';

        return $Current
            . '<input type="file" name="SettingImage" accept="image/png,image/jpeg,image/gif" required>'
            . '<p class="qisutu-form-hint">Das Logo wird in E-Mails auf 28 × 28 Pixel begrenzt.</p>';
    }

    my $InputType = $Type eq 'integer' ? 'number' : 'text';
    my $Attributes = '';

    if ( $Type eq 'integer' ) {
        $Attributes .= ' step="1"';
        $Attributes .= ' min="' . $Self->_Escape( $Setting->{minimum} ) . '"'
            if defined $Setting->{minimum} && $Setting->{minimum} ne '';
        $Attributes .= ' max="' . $Self->_Escape( $Setting->{maximum} ) . '"'
            if defined $Setting->{maximum} && $Setting->{maximum} ne '';
    }

    my $Input = '<input type="' . $InputType . '" name="SettingValue" value="' . $Self->_Escape($Value) . '"' . $Attributes . '>';

    if ( $Setting->{unit} ) {
        return '<div class="qisutu-system-setting-value-with-unit">'
            . $Input
            . '<span>' . $Self->_Escape( $Setting->{unit} ) . '</span>'
            . '</div>';
    }

    return $Input;
}

sub _DisplayValue {
    my ( $Self, %Param ) = @_;

    my $Setting  = $Param{Setting} || {};
    my $Language = $Param{Language} || 'en';
    my $Field    = $Param{Field} || 'value';
    my $Value    = defined $Setting->{$Field} ? $Setting->{$Field} : '';

    if ( $Value eq '' ) {
        return '-';
    }

    if ( ( $Setting->{type} || '' ) eq 'select' ) {
        for my $Option ( @{ $Setting->{possible_values} || [] } ) {
            next if ( defined $Option->{value} ? $Option->{value} : '' ) ne $Value;
            return $Self->_ValueTranslate(
                Value    => defined $Option->{label} ? $Option->{label} : $Value,
                Language => $Language,
            );
        }
    }

    if ( ( $Setting->{type} || '' ) eq 'boolean' ) {
        return $Value
            ? ( $Self->_Translate( Key => 'AdminActiveYes', Language => $Language ) || 'Yes' )
            : ( $Self->_Translate( Key => 'AdminActiveNo',  Language => $Language ) || 'No' );
    }

    if ( $Setting->{unit} ) {
        return $Value . ' ' . $Setting->{unit};
    }

    return $Value;
}

sub _ValueTranslate {
    my ( $Self, %Param ) = @_;

    my $Value    = $Param{Value};
    my $Language = $Param{Language} || 'en';

    $Value = '' if !defined $Value;

    if ( $Value =~ m{\ATranslate:([A-Za-z0-9_]+)\z} ) {
        return $Self->_Translate(
            Key      => $1,
            Language => $Language,
        );
    }

    return $Value;
}

sub _ImageUploadSave {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $Uploads = $Request->{__Uploads} || {};
    my $List    = $Uploads->{SettingImage};
    my $Upload  = ref $List eq 'ARRAY' ? $List->[0] : undef;

    return ( '', '' ) if !$Upload;

    my $Content = defined $Upload->{Content} ? $Upload->{Content} : '';
    return ( '', 'Die ausgewählte Logodatei ist leer.' ) if $Content eq '';
    return ( '', 'Die Logodatei darf höchstens 2 MB groß sein.' ) if length($Content) > 2 * 1024 * 1024;

    my ( $Extension, $MimeType );
    if ( substr( $Content, 0, 8 ) eq "\x89PNG\r\n\x1a\n" ) {
        ( $Extension, $MimeType ) = ( 'png', 'image/png' );
    }
    elsif ( substr( $Content, 0, 3 ) eq "\xff\xd8\xff" ) {
        ( $Extension, $MimeType ) = ( 'jpg', 'image/jpeg' );
    }
    elsif ( substr( $Content, 0, 6 ) eq 'GIF87a' || substr( $Content, 0, 6 ) eq 'GIF89a' ) {
        ( $Extension, $MimeType ) = ( 'gif', 'image/gif' );
    }
    else {
        return ( '', 'Die Datei ist kein gültiges PNG-, JPEG- oder GIF-Bild.' );
    }

    my $RootPath = $Self->{Config}->{RootPath} || '';
    return ( '', 'Das Qisutu-Verzeichnis konnte nicht ermittelt werden.' ) if !$RootPath;

    my $Directory = File::Spec->catdir( $RootPath, 'var', 'data' );
    if ( !-d $Directory && !eval { make_path($Directory); 1 } ) {
        return ( '', 'Das Verzeichnis für das E-Mail-Logo konnte nicht angelegt werden.' );
    }

    my $Filename = 'email-logo-custom.' . $Extension;
    my $Path     = File::Spec->catfile( $Directory, $Filename );

    my $FileHandle;
    if ( !open $FileHandle, '>:raw', $Path ) {
        return ( '', 'Das E-Mail-Logo konnte nicht gespeichert werden.' );
    }
    print {$FileHandle} $Content;
    if ( !close $FileHandle ) {
        return ( '', 'Das E-Mail-Logo konnte nicht vollständig gespeichert werden.' );
    }

    chmod 0644, $Path;

    for my $OldExtension (qw(png jpg gif)) {
        next if $OldExtension eq $Extension;
        my $OldPath = File::Spec->catfile( $Directory, 'email-logo-custom.' . $OldExtension );
        unlink $OldPath if -f $OldPath;
    }

    return ( $Filename . '|' . $MimeType, '' );
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->Translate(%Param);
    }

    return $Param{Key} || '';
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf('%%%02X', ord($1))}eg;

    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

1;
