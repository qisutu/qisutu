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

package QisutuSystemSetting;

use strict;
use warnings;
use utf8;

use File::Spec;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config        => $Param{Config},
        DB            => $Param{DB},
        LastError     => '',
        SchemaChecked => 0,
        DefinitionCache => undef,
        ValueCache      => undef,
    };

    bless $Self, $Class;

    return $Self;
}

sub SchemaEnsure {
    my ($Self) = @_;

    return 1 if $Self->{SchemaChecked};
    return if !$Self->{DB};

    my $OK = $Self->{DB}->Do(
        'CREATE TABLE IF NOT EXISTS system_setting (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            setting_key VARCHAR(190) NOT NULL,
            setting_value LONGTEXT NULL,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY system_setting_key_unique (setting_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'System setting schema could not be prepared';
        return;
    }

    $Self->{SchemaChecked} = 1;

    return 1;
}

sub DefinitionList {
    my ($Self) = @_;

    if ( $Self->{DefinitionCache} ) {
        return $Self->{DefinitionCache};
    }

    my @Definition;

    my $Path = $Self->{Config}->{Paths}->{SettingConfig}
        || File::Spec->catdir( $Self->{Config}->{Paths}->{Config}, 'settings' );

    if ( -d $Path ) {
        my $DirectoryHandle;

        if ( opendir $DirectoryHandle, $Path ) {
            my @Files = sort grep { $_ =~ m{\.pm\z} } readdir $DirectoryHandle;
            closedir $DirectoryHandle;

            for my $File (@Files) {
                my $FullPath = File::Spec->catfile( $Path, $File );
                my $Data     = do $FullPath;

                if ( !$Data ) {
                    next;
                }

                if ( ref $Data eq 'ARRAY' ) {
                    push @Definition, @{$Data};
                }
                elsif ( ref $Data eq 'HASH' && ref $Data->{Settings} eq 'ARRAY' ) {
                    push @Definition, @{ $Data->{Settings} };
                }
            }
        }
    }

    if ( ref $Self->{Config}->{SystemSettings} eq 'ARRAY' ) {
        push @Definition, @{ $Self->{Config}->{SystemSettings} };
    }

    my %Seen;
    my @CleanDefinition;

    for my $Definition (@Definition) {
        next if ref $Definition ne 'HASH';

        my $Key = $Self->_KeyClean( $Definition->{Key} || $Definition->{key} || '' );
        next if !$Key;
        next if $Seen{$Key}++;
        next if exists $Definition->{Active} && !$Definition->{Active};

        my $Type = lc( $Definition->{Type} || $Definition->{type} || 'text' );
        $Type = 'text' if $Type !~ m{\A(?:text|textarea|select|boolean|integer)\z};

        my $Default = exists $Definition->{Default} ? $Definition->{Default} : $Definition->{default};
        $Default = '' if !defined $Default;

        if ( $Key eq 'system.default_language' && !$Default ) {
            $Default = $Self->{Config}->{Language}->{Default} || 'en';
        }

        my $Module = $Definition->{Module} || $Definition->{module} || 'System';
        my $Group  = $Definition->{Group}  || $Definition->{group}  || $Module;

        my $Clean = {
            key             => $Key,
            module          => $Module,
            group           => $Group,
            name            => $Definition->{Name} || $Definition->{name} || $Key,
            description     => $Definition->{Description} || $Definition->{description} || '',
            type            => $Type,
            default_value   => $Default,
            possible_values => $Self->_PossibleValuesClean( $Definition->{PossibleValues} || $Definition->{possible_values} || [] ),
            minimum         => defined $Definition->{Minimum} ? $Definition->{Minimum} : $Definition->{minimum},
            maximum         => defined $Definition->{Maximum} ? $Definition->{Maximum} : $Definition->{maximum},
            unit            => defined $Definition->{Unit} ? $Definition->{Unit} : ( defined $Definition->{unit} ? $Definition->{unit} : '' ),
            sort_order      => $Definition->{SortOrder} || $Definition->{sort_order} || 1000,
            module_sort_order => $Definition->{ModuleSortOrder} || $Definition->{module_sort_order} || 1000,
            group_sort_order  => $Definition->{GroupSortOrder}  || $Definition->{group_sort_order}  || 1000,
        };

        if ( $Clean->{type} eq 'select' && !@{ $Clean->{possible_values} } ) {
            $Clean->{type} = 'text';
        }

        push @CleanDefinition, $Clean;
    }

    @CleanDefinition = sort {
        ( $a->{module_sort_order} || 0 ) <=> ( $b->{module_sort_order} || 0 )
            || ( $a->{module} || '' ) cmp ( $b->{module} || '' )
            || ( $a->{group_sort_order} || 0 ) <=> ( $b->{group_sort_order} || 0 )
            || ( $a->{group} || '' ) cmp ( $b->{group} || '' )
            || ( $a->{sort_order} || 0 ) <=> ( $b->{sort_order} || 0 )
            || ( $a->{key} || '' ) cmp ( $b->{key} || '' )
    } @CleanDefinition;

    $Self->{DefinitionCache} = \@CleanDefinition;

    return $Self->{DefinitionCache};
}

sub SettingList {
    my ($Self) = @_;

    my $Definitions = $Self->DefinitionList();
    my $Values      = $Self->_ValueHashGet();
    my @List;

    for my $Definition ( @{$Definitions} ) {
        my %Item = %{$Definition};
        my $Value = exists $Values->{ $Definition->{key} }
            ? $Values->{ $Definition->{key} }
            : $Definition->{default_value};

        $Item{value}          = defined $Value ? $Value : '';
        $Item{default_value}  = defined $Item{default_value} ? $Item{default_value} : '';
        $Item{is_overwritten} = exists $Values->{ $Definition->{key} } ? 1 : 0;

        push @List, \%Item;
    }

    return \@List;
}

sub Get {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->_KeyClean( $Param{Key} || $Param{Name} || '' );
    return $Param{Default} if !$Key;

    my $Values = $Self->_ValueHashGet();

    if ( exists $Values->{$Key} ) {
        return $Values->{$Key};
    }

    my $Definition = $Self->_DefinitionGet( Key => $Key );

    if ($Definition) {
        return $Definition->{default_value};
    }

    return $Param{Default};
}

sub Set {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->_KeyClean( $Param{Key} || $Param{Name} || '' );
    if ( !$Key ) {
        $Self->{LastError} = 'Invalid system setting key';
        return;
    }

    my $Definition = $Self->_DefinitionGet( Key => $Key );
    if ( !$Definition ) {
        $Self->{LastError} = 'Unknown system setting key: ' . $Key;
        return;
    }

    my ( $Value, $OK ) = $Self->_ValueValidate(
        Definition => $Definition,
        Value      => $Param{Value},
        Exists     => exists $Param{Value} ? 1 : 0,
    );

    if ( !$OK ) {
        return;
    }

    my $UserID = $Param{ChangedByUserID} || 1;

    $Self->SchemaEnsure() || return;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO system_setting (
            setting_key,
            setting_value,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?
         )
         ON DUPLICATE KEY UPDATE
            setting_value = VALUES(setting_value),
            changed_by_user_id = VALUES(changed_by_user_id)',
        $Key,
        $Value,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'System setting could not be saved';
        return;
    }

    delete $Self->{ValueCache};

    return 1;
}

sub UpdateList {
    my ( $Self, %Param ) = @_;

    my $Values = $Param{Values} || {};
    my $UserID = $Param{ChangedByUserID} || 1;

    for my $Definition ( @{ $Self->DefinitionList() } ) {
        my $Key = $Definition->{key};
        my $Exists = exists $Values->{$Key} ? 1 : 0;
        my $Value  = $Exists ? $Values->{$Key} : undef;

        if ( $Definition->{type} eq 'boolean' ) {
            $Value  = $Exists && $Value ? 1 : 0;
            $Exists = 1;
        }

        if (
            !$Self->Set(
                Key             => $Key,
                Value           => $Value,
                ChangedByUserID => $UserID,
            )
            )
        {
            return;
        }
    }

    return 1;
}

sub BaseURL {
    my ($Self) = @_;

    my $FQDN = $Self->Get( Key => 'system.fqdn', Default => '' ) || '';
    $FQDN =~ s{\A\s+|\s+\z}{}g;

    if ($FQDN) {
        my $HTTPType = lc( $Self->Get( Key => 'system.http_type', Default => 'https' ) || 'https' );
        $HTTPType = 'https' if $HTTPType !~ m{\A(?:http|https)\z};

        my $WebPath = $Self->_WebPathNormalize( $Self->Get( Key => 'system.web_path', Default => '' ) || '' );

        return $HTTPType . '://' . $FQDN . $WebPath;
    }

    my $BaseURL = $Self->{Config}->{System}->{BaseURL} || $ENV{QISUTU_BASE_URL} || '';
    $BaseURL =~ s{/+\z}{};

    return $BaseURL;
}

sub AttachmentMaxSizeMB {
    my ($Self) = @_;

    my $Value = $Self->Get(
        Key     => 'system.attachment_max_size_mb',
        Default => 25,
    );

    $Value = 25 if !defined $Value || $Value !~ m{\A\d+\z} || $Value < 1;
    $Value = 10240 if $Value > 10240;

    return 0 + $Value;
}

sub AttachmentMaxSizeBytes {
    my ($Self) = @_;

    return $Self->AttachmentMaxSizeMB() * 1024 * 1024;
}

sub PlaceholderHash {
    my ($Self) = @_;

    return {
        'System.Name'            => $Self->{Config}->{System}->{Name} || 'Qisutu',
        'System.HTTPType'        => $Self->Get( Key => 'system.http_type', Default => 'https' ) || 'https',
        'System.FQDN'            => $Self->Get( Key => 'system.fqdn', Default => '' ) || '',
        'System.WebPath'         => $Self->Get( Key => 'system.web_path', Default => '' ) || '',
        'System.BaseURL'         => $Self->BaseURL() || '',
        'System.DefaultLanguage' => $Self->Get( Key => 'system.default_language', Default => $Self->{Config}->{Language}->{Default} || 'en' ) || 'en',
        'System.TicketHook'      => $Self->Get( Key => 'system.ticket_hook', Default => 'Qisutu' ) || 'Qisutu',
    };
}

sub _DefinitionGet {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->_KeyClean( $Param{Key} || '' );
    return if !$Key;

    for my $Definition ( @{ $Self->DefinitionList() } ) {
        next if $Definition->{key} ne $Key;
        return $Definition;
    }

    return;
}

sub _ValueHashGet {
    my ($Self) = @_;

    if ( $Self->{ValueCache} ) {
        return $Self->{ValueCache};
    }

    my %Value;

    if ( $Self->{DB} && $Self->SchemaEnsure() ) {
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT setting_key, setting_value
             FROM system_setting'
        ) || [];

        for my $Row ( @{$Rows} ) {
            my $Key = $Self->_KeyClean( $Row->{setting_key} || '' );
            next if !$Key;

            $Value{$Key} = defined $Row->{setting_value} ? $Row->{setting_value} : '';
        }
    }

    $Self->{ValueCache} = \%Value;

    return $Self->{ValueCache};
}

sub _ValueValidate {
    my ( $Self, %Param ) = @_;

    my $Definition = $Param{Definition} || {};
    my $Type       = $Definition->{type} || 'text';
    my $Value      = defined $Param{Value} ? $Param{Value} : '';

    $Value = $Self->_Trim($Value);

    if ( $Type eq 'boolean' ) {
        return ( $Value ? 1 : 0, 1 );
    }

    if ( $Type eq 'integer' ) {
        if ( $Value ne '' && $Value !~ m{\A-?\d+\z} ) {
            $Self->{LastError} = 'Invalid integer value for system setting: ' . ( $Definition->{key} || '' );
            return ( '', 0 );
        }

        if ( $Value ne '' && defined $Definition->{minimum} && $Definition->{minimum} ne '' && $Value < $Definition->{minimum} ) {
            $Self->{LastError} = 'System setting value is below the allowed minimum: ' . ( $Definition->{key} || '' );
            return ( '', 0 );
        }

        if ( $Value ne '' && defined $Definition->{maximum} && $Definition->{maximum} ne '' && $Value > $Definition->{maximum} ) {
            $Self->{LastError} = 'System setting value exceeds the allowed maximum: ' . ( $Definition->{key} || '' );
            return ( '', 0 );
        }

        return ( $Value, 1 );
    }

    if ( $Type eq 'select' ) {
        my %Allowed = map { $_->{value} => 1 } @{ $Definition->{possible_values} || [] };

        if ( !$Allowed{$Value} ) {
            $Self->{LastError} = 'Invalid selection for system setting: ' . ( $Definition->{key} || '' );
            return ( '', 0 );
        }

        return ( $Value, 1 );
    }

    if ( ( $Definition->{key} || '' ) eq 'system.http_type' ) {
        $Value = lc $Value;
        if ( $Value !~ m{\A(?:http|https)\z} ) {
            $Self->{LastError} = 'HTTP type must be http or https';
            return ( '', 0 );
        }
    }
    elsif ( ( $Definition->{key} || '' ) eq 'system.fqdn' ) {
        $Value =~ s{\Ahttps?://}{}i;
        $Value =~ s{/.*\z}{};
        $Value =~ s{\s+}{}g;

        if ( $Value && $Value !~ m{\A[A-Za-z0-9][A-Za-z0-9\.\-]*(?::\d+)?\z} ) {
            $Self->{LastError} = 'FQDN is invalid';
            return ( '', 0 );
        }
    }
    elsif ( ( $Definition->{key} || '' ) eq 'system.web_path' ) {
        $Value = $Self->_WebPathNormalize($Value);
    }
    elsif ( ( $Definition->{key} || '' ) eq 'system.default_language' ) {
        my $LanguagePath = $Self->{Config}->{Paths}->{Language} || '';
        my $LanguageFile = $LanguagePath && $Value =~ m{\A[A-Za-z0-9_-]+\z}
            ? File::Spec->catfile( $LanguagePath, "$Value.pm" )
            : '';

        if ( !$LanguageFile || !-f $LanguageFile || -l $LanguageFile ) {
            $Self->{LastError} = 'Default system language is invalid';
            return ( '', 0 );
        }
    }

    return ( $Value, 1 );
}

sub _PossibleValuesClean {
    my ( $Self, $PossibleValues ) = @_;

    my @Value;

    if ( ref $PossibleValues eq 'ARRAY' ) {
        for my $Item ( @{$PossibleValues} ) {
            if ( ref $Item eq 'HASH' ) {
                my $Value = defined $Item->{Value} ? $Item->{Value} : $Item->{value};
                next if !defined $Value;
                push @Value, {
                    value => $Value,
                    label => defined $Item->{Label} ? $Item->{Label} : ( defined $Item->{label} ? $Item->{label} : $Value ),
                };
            }
            elsif ( defined $Item ) {
                push @Value, {
                    value => $Item,
                    label => $Item,
                };
            }
        }
    }

    return \@Value;
}

sub _WebPathNormalize {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);
    return '' if !$Value || $Value eq '/';

    $Value =~ s{\s+}{}g;
    $Value =~ s{\Ahttps?://[^/]+}{}i;
    $Value =~ s{\?.*\z}{};
    $Value =~ s{/+\z}{};
    $Value =~ s{\A([^/])}{/$1};

    return $Value;
}

sub _KeyClean {
    my ( $Self, $Key ) = @_;

    $Key = '' if !defined $Key;
    $Key =~ s{\A\s+|\s+\z}{}g;
    return '' if $Key !~ m{\A[a-z0-9][a-z0-9_.\-]*\z};

    return $Key;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
