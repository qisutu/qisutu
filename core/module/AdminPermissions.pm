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

package AdminPermissions;

use strict;
use warnings;
use utf8;

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

    my $Request      = $Param{Request} || {};
    my $Step         = $Request->{Step} || '';
    my $Action       = $Request->{Action} || 'List';
    my $Language     = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $ErrorMessage = '';

    if ( $Step eq 'ProgramConfigUpdate' ) {
        if (
            $Self->_ProgramConfigUpdate(
                OldName     => $Request->{OldName},
                Name        => $Request->{Name},
                Module      => $Request->{Module},
                Title       => $Request->{Title},
                Description => $Request->{Description},
                Icon        => $Request->{Icon},
                URL         => $Request->{URL},
                Type        => $Request->{Type},
                Parent      => $Request->{Parent},
                Order       => $Request->{Order},
                VisibleFor  => $Self->_VisibleForListFromRequest( Request => $Request ),
                Active      => $Request->{Active},
            )
            )
        {
            return { Redirect => 'index.pl?Page=AdminPermissions;Action=Edit;ProgramName=' . $Self->_URLEscape( $Request->{Name} || $Request->{OldName} || '' ) };
        }

        $ErrorMessage = $Self->{LastError} || 'Program config could not be saved';
        $Action = 'Edit';
        $Request->{ProgramName} = $Request->{OldName} || $Request->{Name};
    }

    my $ProgramList = $Self->_ProgramList();
    my $Program;

    if ( $Action eq 'Edit' ) {
        $Program = $Self->_ProgramGet(
            ProgramList => $ProgramList,
            Name        => $Request->{ProgramName},
        );

        if ( !$Program ) {
            $Action = 'List';
            $ErrorMessage ||= 'Program config was not found';
        }
    }

    return {
        Template => 'AdminPermissions.tt',
        Data     => {
            PageTitle          => 'Translate:AdminPermissionsTitle',
            ProgramTitle       => 'Translate:AdminPermissionsTitle',
            ProgramDescription => 'Translate:AdminPermissionsDescription',
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ProgramRowsHTML    => $Self->_ProgramRowsHTML( ProgramList => $ProgramList, Language => $Language ),
            ProgramOldName     => $Program ? $Program->{Name} : '',
            ProgramName        => $Program ? $Program->{Name} : '',
            ProgramModule      => $Program ? $Program->{Module} : '',
            ProgramTitleField  => $Program ? $Program->{Title} : '',
            ProgramDescriptionField => $Program ? $Program->{Description} : '',
            ProgramIcon        => $Program ? $Program->{Icon} : '',
            ProgramURL         => $Program ? $Program->{URL} : '',
            ProgramParent      => $Program ? $Program->{Parent} : '',
            ProgramOrder       => $Program ? $Program->{Order} : '',
            ProgramActiveChecked   => $Program && $Program->{Active} ? 'checked' : '',
            TypeOptionsHTML        => $Self->_TypeOptionsHTML( Selected => $Program ? $Program->{Type} : '' ),
            VisibleForOptionsHTML  => $Self->_VisibleForOptionsHTML( Selected => $Program ? $Program->{VisibleFor} : '', Language => $Language ),
        },
    };
}

sub _ProgramList {
    my ($Self) = @_;

    my $Loaded = eval {
        require QisutuProgramRegistry;
        1;
    };

    return [] if !$Loaded;

    my $Registry = QisutuProgramRegistry->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );

    my $Programs = $Registry->Programs();

    my @VisiblePrograms;

    for my $Program ( @{$Programs} ) {
        next if $Program->{Hidden};

        $Program->{VisibleFor} = join ',', @{ $Self->_VisibleFor( Program => $Program ) };
        push @VisiblePrograms, $Program;
    }

    return \@VisiblePrograms;
}

sub _ProgramGet {
    my ( $Self, %Param ) = @_;

    my $ProgramList = $Param{ProgramList} || [];
    my $Name        = $Param{Name} || '';

    return if !$Name;

    for my $Program ( @{$ProgramList} ) {
        return $Program if ( $Program->{Name} || '' ) eq $Name;
    }

    return;
}

sub _ProgramConfigUpdate {
    my ( $Self, %Param ) = @_;

    my $OldName = $Self->_CleanIdentifier( $Param{OldName} );
    my $Name    = $Self->_CleanIdentifier( $Param{Name} );
    my $Module  = $Self->_CleanModule( $Param{Module} );
    my $Order   = $Param{Order} || 0;
    my $Active  = $Param{Active} ? 1 : 0;

    if ( !$OldName || !$Name || !$Module ) {
        $Self->{LastError} = 'Program name and module are required';
        return;
    }

    if ( $Order !~ m{\A\d+\z} ) {
        $Order = 0;
    }

    my $Path = $Self->_ProgramConfigPath();
    return if !$Path;

    my $OldFile = File::Spec->catfile( $Path, $OldName . '.pm' );
    my $NewFile = File::Spec->catfile( $Path, $Name . '.pm' );

    if ( !-f $OldFile ) {
        $Self->{LastError} = 'Program config file was not found';
        return;
    }

    my $VisibleFor;
    if ( $Self->_InternalPublicProgram( Name => $OldName ) || $Self->_InternalPublicProgram( Name => $Name ) ) {
        $VisibleFor = 'anonymous';
    }
    else {
        $VisibleFor = $Self->_CleanVisibleForList( $Param{VisibleFor} );
    }

    my ( $AccessType, $Permission ) = $Self->_RuntimeAccessFromVisibleFor( VisibleFor => $VisibleFor );
    my $PermissionGroup = $Self->_PermissionGroupFromKey($Permission);
    my $PermissionMode  = $Self->_PermissionModeFromKey($Permission);

    my $Content = $Self->_ProgramConfigBuild(
        Name            => $Name,
        Module          => $Module,
        Title           => $Self->_Trim( $Param{Title} ),
        Description     => $Self->_Trim( $Param{Description} ),
        Icon            => $Self->_Trim( $Param{Icon} ),
        URL             => $Self->_Trim( $Param{URL} ),
        Type            => $Self->_CleanChoice( Value => $Param{Type}, Allowed => { map { $_ => 1 } qw(MainNavigation SubNavigation ProgramOnly) }, Default => 'ProgramOnly' ),
        Parent          => $Self->_CleanIdentifierOptional( $Param{Parent} ),
        Order           => $Order,
        VisibleFor      => $VisibleFor,
        AccessType      => $AccessType,
        PermissionGroup => $PermissionGroup,
        PermissionMode  => $PermissionMode,
        Permission      => $Permission,
        Active          => $Active,
    );

    my $FileHandle;
    if ( !open $FileHandle, '>:encoding(UTF-8)', $NewFile ) {
        $Self->{LastError} = 'Program config file could not be written';
        return;
    }

    print {$FileHandle} $Content;
    close $FileHandle;

    if ( $OldFile ne $NewFile && -f $OldFile ) {
        unlink $OldFile;
    }

    return 1;
}

sub _ProgramConfigBuild {
    my ( $Self, %Param ) = @_;

    my @Lines = (
        '{',
        '    Name            => ' . $Self->_PerlQuote( $Param{Name} ) . ',',
        '    Module          => ' . $Self->_PerlQuote( $Param{Module} ) . ',',
        '    Title           => ' . $Self->_PerlQuote( $Param{Title} ) . ',',
        '    Description     => ' . $Self->_PerlQuote( $Param{Description} ) . ',',
        '    Icon            => ' . $Self->_PerlQuote( $Param{Icon} ) . ',',
        '    URL             => ' . $Self->_PerlQuote( $Param{URL} ) . ',',
        '    Type            => ' . $Self->_PerlQuote( $Param{Type} ) . ',',
        '    Parent          => ' . $Self->_PerlQuote( $Param{Parent} ) . ',',
        '    Order           => ' . ( $Param{Order} || 0 ) . ',',
        '    VisibleFor      => ' . $Self->_PerlArray( [ split m{,}, ( $Param{VisibleFor} || '' ) ] ) . ',',
        '    AccessType      => ' . $Self->_PerlQuote( $Param{AccessType} ) . ',',
        '    AccessTypes     => ' . $Self->_PerlArray( [ split m{,}, ( $Param{AccessType} || '' ) ] ) . ',',
        '    PermissionGroup => ' . $Self->_PerlQuote( $Param{PermissionGroup} ) . ',',
        '    PermissionMode  => ' . $Self->_PerlQuote( $Param{PermissionMode} ) . ',',
        '    Permission      => ' . $Self->_PerlQuote( $Param{Permission} ) . ',',
        '    Active          => ' . ( $Param{Active} ? 1 : 0 ) . ',',
        '}',
    );

    return join( "\n", @Lines ) . "\n";
}

sub _ProgramRowsHTML {
    my ( $Self, %Param ) = @_;

    my $ProgramList = $Param{ProgramList} || [];
    my $Language    = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $HTML = '';

    for my $Program ( @{$ProgramList} ) {
        $HTML .= '<tr>';
        $HTML .= '<td><a class="qisutu-table-link" href="index.pl?Page=AdminPermissions;Action=Edit;ProgramName=' . $Self->_URLEscape( $Program->{Name} || '' ) . '">' . $Self->_Escape( $Program->{Name} || '' ) . '</a></td>';
        $HTML .= '<td>' . $Self->_Escape( $Program->{Title} || '' ) . '</td>';
        $HTML .= '<td>' . $Self->_Escape( $Program->{Type} || '' ) . '</td>';
        $HTML .= '<td>' . $Self->_Escape( $Self->_VisibleForLabelList( VisibleFor => $Program->{VisibleFor} || '', Language => $Language ) ) . '</td>';
        $HTML .= '<td>' . $Self->_Escape( $Program->{Active} ? '1' : '0' ) . '</td>';
        $HTML .= '</tr>';
    }

    return $HTML;
}

sub _TypeOptionsHTML {
    my ( $Self, %Param ) = @_;

    return $Self->_OptionsHTML(
        Selected => $Param{Selected},
        Values   => [qw(MainNavigation SubNavigation ProgramOnly)],
    );
}

sub _VisibleForOptionsHTML {
    my ( $Self, %Param ) = @_;

    my %Selected = map { $_ => 1 } split m{\s*,\s*|\s+}, ( $Param{Selected} || '' );
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $HTML = '';

    if ( $Selected{anonymous} ) {
        $HTML .= '<span class="qisutu-admin-static-value">' . $Self->_Escape( $Self->_VisibleForLabel( VisibleFor => 'anonymous', Language => $Language ) ) . '</span>';
        return $HTML;
    }

    for my $Value (qw(customer agent admin)) {
        my $Checked = $Selected{$Value} ? ' checked' : '';
        $HTML .= '<label class="qisutu-form-checkbox">';
        $HTML .= '<input type="checkbox" name="VisibleFor' . ucfirst($Value) . '" value="1"' . $Checked . '>';
        $HTML .= '<span>' . $Self->_Escape( $Self->_VisibleForLabel( VisibleFor => $Value, Language => $Language ) ) . '</span>';
        $HTML .= '</label>';
    }

    return $HTML;
}

sub _VisibleForLabelList {
    my ( $Self, %Param ) = @_;

    my @VisibleFor = split m{\s*,\s*|\s+}, ( $Param{VisibleFor} || '' );
    my @Labels     = map { $Self->_VisibleForLabel( VisibleFor => $_, Language => $Param{Language} ) } grep {$_} @VisibleFor;

    return join ', ', @Labels;
}

sub _VisibleForLabel {
    my ( $Self, %Param ) = @_;

    my $VisibleFor = $Param{VisibleFor} || '';
    my $Language   = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my %Label = $Language eq 'de' ? (
        anonymous => 'Interne Login-Seite',
        customer  => 'Kunden',
        agent     => 'Agenten',
        admin     => 'Administratoren',
    ) : (
        anonymous => 'Internal login page',
        customer  => 'Customers',
        agent     => 'Agents',
        admin     => 'Administrators',
    );

    return $Label{$VisibleFor} || $VisibleFor;
}

sub _OptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || '';
    my $Values   = $Param{Values} || [];
    my $HTML     = '';

    for my $Value ( @{$Values} ) {
        my $SelectedAttribute = $Value eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape($Value) . '"' . $SelectedAttribute . '>' . $Self->_Escape($Value) . '</option>';
    }

    return $HTML;
}

sub _VisibleForListFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my @VisibleFor;

    push @VisibleFor, 'customer'  if $Request->{VisibleForCustomer};
    push @VisibleFor, 'agent'     if $Request->{VisibleForAgent};
    push @VisibleFor, 'admin'     if $Request->{VisibleForAdmin};

    return join ',', @VisibleFor;
}

sub _CleanVisibleForList {
    my ( $Self, $Value ) = @_;

    my %Allowed = map { $_ => 1 } qw(anonymous customer agent admin);
    my %Seen;
    my @VisibleFor = grep { $Allowed{$_} && !$Seen{$_}++ } split m{\s*,\s*|\s+}, ( $Value || '' );

    @VisibleFor = ('anonymous') if grep { $_ eq 'anonymous' } @VisibleFor;
    @VisibleFor = ('agent') if !@VisibleFor;

    return join ',', @VisibleFor;
}

sub _VisibleFor {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};
    my @VisibleFor;

    if ( ref $Program->{VisibleFor} eq 'ARRAY' ) {
        @VisibleFor = @{ $Program->{VisibleFor} };
    }
    elsif ( defined $Program->{VisibleFor} ) {
        @VisibleFor = split m{\s*,\s*|\s+}, $Program->{VisibleFor};
    }

    my %Allowed = map { $_ => 1 } qw(anonymous customer agent admin);
    my %Seen;
    @VisibleFor = grep { $Allowed{$_} && !$Seen{$_}++ } @VisibleFor;

    if ( !@VisibleFor ) {
        my @AccessTypes;
        if ( ref $Program->{AccessTypes} eq 'ARRAY' ) {
            @AccessTypes = @{ $Program->{AccessTypes} };
        }
        elsif ( defined $Program->{AccessType} ) {
            @AccessTypes = split m{\s*,\s*|\s+}, $Program->{AccessType};
        }
        @VisibleFor = map { $_ eq 'agent' && ( $Program->{Permission} || '' ) eq 'admin.view' ? 'admin' : $_ } @AccessTypes;
    }

    @VisibleFor = ('anonymous') if grep { $_ eq 'anonymous' } @VisibleFor;
    @VisibleFor = ('agent') if !@VisibleFor;

    return \@VisibleFor;
}

sub _RuntimeAccessFromVisibleFor {
    my ( $Self, %Param ) = @_;

    my %VisibleFor = map { $_ => 1 } split m{\s*,\s*|\s+}, ( $Param{VisibleFor} || '' );

    return ( 'anonymous', '' ) if $VisibleFor{anonymous};

    my @AccessType;
    push @AccessType, 'agent' if $VisibleFor{agent} || $VisibleFor{admin};
    push @AccessType, 'customer' if $VisibleFor{customer};

    my $Permission = '';
    $Permission = 'admin.view' if $VisibleFor{admin} && !$VisibleFor{agent} && !$VisibleFor{customer};

    return ( join( ',', @AccessType ), $Permission );
}

sub _InternalPublicProgram {
    my ( $Self, %Param ) = @_;

    my $Name = $Param{Name} || '';

    return 1 if $Name eq 'Login';

    return;
}

sub _ProgramConfigPath {
    my ($Self) = @_;

    my $Path = $Self->{Config}->{Paths}->{ProgramConfig};

    if ( !$Path ) {
        $Path = File::Spec->catdir( $Self->{Config}->{Paths}->{Config}, 'programs' );
    }

    if ( !$Path || !-d $Path ) {
        $Self->{LastError} = 'Program config path was not found';
        return;
    }

    return $Path;
}

sub _PermissionGroupFromKey {
    my ( $Self, $Permission ) = @_;

    return '' if !$Permission;
    return $1 if $Permission =~ m{\A([A-Za-z0-9_]+)\.};

    return '';
}

sub _PermissionModeFromKey {
    my ( $Self, $Permission ) = @_;

    return '' if !$Permission;
    return 'ro' if $Permission =~ m{\.view\z};
    return 'rw' if $Permission =~ m{\.(?:edit|update|change|manage)\z};
    return $1 if $Permission =~ m{\.([A-Za-z0-9_]+)\z};

    return '';
}

sub _CleanIdentifier {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);
    $Value =~ s{[^A-Za-z0-9_]}{}g;

    return $Value;
}

sub _CleanIdentifierOptional {
    my ( $Self, $Value ) = @_;

    return '' if !defined $Value || $Value eq '';

    return $Self->_CleanIdentifier($Value);
}

sub _CleanModule {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);
    $Value =~ s{[^A-Za-z0-9_:]}{}g;

    return $Value;
}

sub _CleanChoice {
    my ( $Self, %Param ) = @_;

    my $Value   = $Self->_Trim( $Param{Value} );
    my $Allowed = $Param{Allowed} || {};

    return $Value if $Allowed->{$Value};

    return $Param{Default};
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub _PerlQuote {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\\}{\\\\}g;
    $Value =~ s{'}{\\'}g;

    return "'" . $Value . "'";
}

sub _PerlArray {
    my ( $Self, $Values ) = @_;

    $Values ||= [];

    return '[ ' . join( ', ', map { $Self->_PerlQuote($_) } grep { defined $_ && $_ ne '' } @{$Values} ) . ' ]';
}

sub _URLEscape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf("%%%02X", ord($1))}eg;

    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;

    return $Value;
}

1;
