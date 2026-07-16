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

use Getopt::Long qw(GetOptions);
my $SchemaFile = q{};
my $StatusFile = q{};
my $ParseOnly  = 0;

GetOptions(
    'schema=s'      => \$SchemaFile,
    'status-file=s' => \$StatusFile,
    'parse-only'    => \$ParseOnly,
) or die "Ungültige Parameter für QisutuSchemaSync.pl.\n";

if ( !$SchemaFile ) {
    die "Der Parameter --schema fehlt.\n";
}
if ( !-r $SchemaFile ) {
    die "Die Qisutu-Schemadatei kann nicht gelesen werden: $SchemaFile\n";
}
my $ExpectedTables = _SchemaParse( File => $SchemaFile );

if ($ParseOnly) {
    my $TableCount      = scalar keys %{$ExpectedTables};
    my $ColumnCount     = 0;
    my $IndexCount      = 0;
    my $ForeignKeyCount = 0;

    for my $TableName ( sort keys %{$ExpectedTables} ) {
        my $Table = $ExpectedTables->{$TableName};
        $ColumnCount     += scalar @{ $Table->{Columns} };
        $IndexCount      += scalar @{ $Table->{Indexes} };
        $ForeignKeyCount += scalar @{ $Table->{ForeignKeys} };
    }

    print "Schema erfolgreich gelesen: $TableCount Tabellen, $ColumnCount Spalten, $IndexCount Indizes, $ForeignKeyCount Fremdschlüssel.\n";
    exit 0;
}

require DBI;
require QisutuConfig;

my $Config = QisutuConfig::Load();
my $DB     = $Config->{Database} || {};

my $DatabaseName = $DB->{Name} || q{};
my $DatabaseUser = $DB->{User} || q{};

if ( $DatabaseName !~ m{\A[A-Za-z][A-Za-z0-9_]{0,63}\z} ) {
    die "Der Datenbankname aus QisutuConfig.pm ist ungültig.\n";
}
if ( !$DatabaseUser ) {
    die "Der Datenbankbenutzer fehlt in QisutuConfig.pm.\n";
}

my $DSN = sprintf(
    'DBI:mysql:database=%s;host=%s;port=%d',
    $DatabaseName,
    $DB->{Host} || 'localhost',
    0 + ( $DB->{Port} || 3306 ),
);

my $DBH = DBI->connect(
    $DSN,
    $DatabaseUser,
    defined $DB->{Password} ? $DB->{Password} : q{},
    {
        RaiseError           => 1,
        PrintError           => 0,
        AutoCommit           => 1,
        mysql_enable_utf8mb4 => 1,
    },
);

if ( !$DBH ) {
    die "Die Verbindung zur Qisutu-Datenbank konnte nicht hergestellt werden.\n";
}

my $Changed      = 0;
my $WarningCount = 0;
my %ExistingTable;

my $TableRows = $DBH->selectall_arrayref(
    q{
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = ?
          AND TABLE_TYPE = 'BASE TABLE'
    },
    { Slice => {} },
    $DatabaseName,
);

for my $Row ( @{$TableRows} ) {
    $ExistingTable{ $Row->{TABLE_NAME} } = 1;
}

print "Vergleiche die bestehende Datenbank mit install/sql/schema.sql.\n";

# Zuerst werden fehlende Tabellen ohne Fremdschlüssel angelegt. Dadurch ist
# die Reihenfolge der CREATE-TABLE-Blöcke in schema.sql für Fremdschlüssel
# unerheblich. Die Fremdschlüssel werden in einem getrennten Durchlauf ergänzt.
for my $TableName ( sort keys %{$ExpectedTables} ) {
    next if $ExistingTable{$TableName};

    my $Table = $ExpectedTables->{$TableName};
    print "  Tabelle anlegen: $TableName\n";
    $DBH->do( $Table->{CreateWithoutForeignKeys} );
    $ExistingTable{$TableName} = 1;
    $Changed = 1;
}

# Bestehende Tabellen werden nur um fehlende, eindeutig sichere Strukturelemente
# ergänzt. Vorhandene oder zusätzliche Strukturen werden niemals gelöscht.
for my $TableName ( sort keys %{$ExpectedTables} ) {
    my $Expected = $ExpectedTables->{$TableName};
    my $LiveCreate = _ShowCreateTable(
        DBH       => $DBH,
        TableName => $TableName,
    );
    my $Live = _CreateStatementParse(
        SQL          => $LiveCreate,
        ExpectedName => $TableName,
    );

    my %LiveColumn = map { $_->{Name} => $_ } @{ $Live->{Columns} };
    my $PreviousColumn = q{};

    for my $ExpectedColumn ( @{ $Expected->{Columns} } ) {
        my $ColumnName = $ExpectedColumn->{Name};

        if ( !$LiveColumn{$ColumnName} ) {
            _MissingColumnSafetyCheck(
                DBH        => $DBH,
                TableName  => $TableName,
                Definition => $ExpectedColumn->{Definition},
            );

            my $Position = $PreviousColumn
                ? ' AFTER ' . _QuoteIdentifier($PreviousColumn)
                : ' FIRST';

            print "  Spalte ergänzen: $TableName.$ColumnName\n";
            $DBH->do(
                'ALTER TABLE ' . _QuoteIdentifier($TableName)
                    . ' ADD COLUMN ' . $ExpectedColumn->{Definition}
                    . $Position
            );
            $Changed = 1;

            $LiveCreate = _ShowCreateTable(
                DBH       => $DBH,
                TableName => $TableName,
            );
            $Live = _CreateStatementParse(
                SQL          => $LiveCreate,
                ExpectedName => $TableName,
            );
                    %LiveColumn = map { $_->{Name} => $_ } @{ $Live->{Columns} };
        }
        elsif (
            _DefinitionNormalize( $ExpectedColumn->{Definition} ) ne
            _DefinitionNormalize( $LiveColumn{$ColumnName}->{Definition} )
        ) {
            _Warning(
                Message => "Spaltendefinition weicht ab und wurde nicht automatisch geändert: $TableName.$ColumnName",
                Counter => \$WarningCount,
            );
        }

        $PreviousColumn = $ColumnName;
    }

    $LiveCreate = _ShowCreateTable(
        DBH       => $DBH,
        TableName => $TableName,
    );
    $Live = _CreateStatementParse(
        SQL          => $LiveCreate,
        ExpectedName => $TableName,
    );

    my %LiveIndexByName = map {
        ( defined $_->{Name} ? $_->{Name} : '__PRIMARY__' ) => $_
    } @{ $Live->{Indexes} };
    my %LiveIndexBySignature = map {
        $_->{Signature} => 1
    } @{ $Live->{Indexes} };

    for my $ExpectedIndex ( @{ $Expected->{Indexes} } ) {
        next if $LiveIndexBySignature{ $ExpectedIndex->{Signature} };

        my $IndexName = defined $ExpectedIndex->{Name}
            ? $ExpectedIndex->{Name}
            : '__PRIMARY__';

        if ( $LiveIndexByName{$IndexName} ) {
            _Warning(
                Message => "Index $IndexName auf Tabelle $TableName ist vorhanden, besitzt aber eine andere Definition und wurde nicht automatisch geändert.",
                Counter => \$WarningCount,
            );
            next;
        }

        print "  Index ergänzen: $TableName.$IndexName\n";
        $DBH->do(
            'ALTER TABLE ' . _QuoteIdentifier($TableName)
                . ' ADD ' . $ExpectedIndex->{Definition}
        );
        $Changed = 1;
        $LiveIndexByName{$IndexName} = $ExpectedIndex;
        $LiveIndexBySignature{ $ExpectedIndex->{Signature} } = 1;
    }

    if (
        _TableOptionsNormalize( $Expected->{TableOptions} ) ne
        _TableOptionsNormalize( $Live->{TableOptions} )
    ) {
        _Warning(
            Message => "Tabellenoptionen weichen ab und wurden nicht automatisch geändert: $TableName",
            Counter => \$WarningCount,
        );
    }
}

# Fremdschlüssel werden zuletzt ergänzt, nachdem alle Tabellen, Spalten und
# benötigten Indizes vorhanden sind.
for my $TableName ( sort keys %{$ExpectedTables} ) {
    my $Expected = $ExpectedTables->{$TableName};

    my $LiveCreate = _ShowCreateTable(
        DBH       => $DBH,
        TableName => $TableName,
    );
    my $Live = _CreateStatementParse(
        SQL          => $LiveCreate,
        ExpectedName => $TableName,
    );

    my %LiveForeignByName = map {
        ( $_->{Name} || q{} ) => $_
    } @{ $Live->{ForeignKeys} };
    my %LiveForeignBySignature = map {
        $_->{Signature} => 1
    } @{ $Live->{ForeignKeys} };

    for my $ExpectedForeign ( @{ $Expected->{ForeignKeys} } ) {
        next if $LiveForeignBySignature{ $ExpectedForeign->{Signature} };

        my $ForeignName = $ExpectedForeign->{Name} || q{};
        if ( $ForeignName && $LiveForeignByName{$ForeignName} ) {
            _Warning(
                Message => "Fremdschlüssel $ForeignName auf Tabelle $TableName ist vorhanden, besitzt aber eine andere Definition und wurde nicht automatisch geändert.",
                Counter => \$WarningCount,
            );
            next;
        }

        print "  Fremdschlüssel ergänzen: $TableName.$ForeignName\n";
        $DBH->do(
            'ALTER TABLE ' . _QuoteIdentifier($TableName)
                . ' ADD ' . $ExpectedForeign->{Definition}
        );
        $Changed = 1;
        $LiveForeignBySignature{ $ExpectedForeign->{Signature} } = 1;
        $LiveForeignByName{$ForeignName} = $ExpectedForeign if $ForeignName;
    }
}

$DBH->disconnect();

if ($StatusFile) {
    open my $StatusFH, '>', $StatusFile
        or die "Die Statusdatei kann nicht geschrieben werden: $StatusFile: $!\n";
    print {$StatusFH} "changed=$Changed\n";
    print {$StatusFH} "warnings=$WarningCount\n";
    close $StatusFH
        or die "Die Statusdatei kann nicht geschlossen werden: $StatusFile: $!\n";
}

if ($Changed) {
    print "Der Datenbankabgleich wurde erfolgreich durchgeführt.\n";
}
else {
    print "Die Datenbank entspricht bereits der aktuellen Qisutu-Sollstruktur.\n";
}

if ($WarningCount) {
    print "Hinweis: $WarningCount bestehende Abweichung(en) wurden aus Sicherheitsgründen nicht automatisch verändert.\n";
}

exit 0;

sub _SchemaParse {
    my (%Param) = @_;

    open my $SchemaFH, '<', $Param{File}
        or die "Die Schemadatei kann nicht geöffnet werden: $Param{File}: $!\n";
    local $/;
    my $SQL = <$SchemaFH>;
    close $SchemaFH
        or die "Die Schemadatei kann nicht geschlossen werden: $Param{File}: $!\n";

    my %Table;

    while (
        $SQL =~ m{
            (^CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+`[^`]+`\s*\(.*?^\)\s*[^;]*;)
        }gmsix
    ) {
        my $CreateSQL = $1;
        my $Parsed = _CreateStatementParse( SQL => $CreateSQL );
        my $Name = $Parsed->{Name};

        if ( $Table{$Name} ) {
            die "Die Tabelle $Name ist in schema.sql mehrfach definiert.\n";
        }

        my @CreateItems = (
            ( map { $_->{Definition} } @{ $Parsed->{Columns} } ),
            ( map { $_->{Definition} } @{ $Parsed->{Indexes} } ),
            ( map { $_->{Definition} } @{ $Parsed->{OtherItems} } ),
        );

        if ( !@CreateItems ) {
            die "Die Tabelle $Name enthält keine auswertbare Definition.\n";
        }

        $Parsed->{CreateWithoutForeignKeys} =
              'CREATE TABLE ' . _QuoteIdentifier($Name) . " (\n  "
            . join( ",\n  ", @CreateItems )
            . "\n) " . $Parsed->{TableOptions} . ';';

        $Table{$Name} = $Parsed;
    }

    if ( !%Table ) {
        die "In der Schemadatei wurden keine CREATE-TABLE-Anweisungen gefunden.\n";
    }

    return \%Table;
}

sub _CreateStatementParse {
    my (%Param) = @_;

    my $SQL = $Param{SQL};
    $SQL =~ s/\A\s+//;
    $SQL =~ s/\s+\z//;
    $SQL =~ s/;\s*\z//;

    if (
        $SQL !~ m{
            \ACREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+`([^`]+)`\s*\((.*)\)\s*(.*?)\z
        }six
    ) {
        die "Eine CREATE-TABLE-Anweisung aus schema.sql konnte nicht ausgewertet werden.\n";
    }

    my $Name         = $1;
    my $Body         = $2;
    my $TableOptions = $3;

    if ( $Param{ExpectedName} && $Name ne $Param{ExpectedName} ) {
        die "SHOW CREATE TABLE lieferte unerwartet die Tabelle $Name statt $Param{ExpectedName}.\n";
    }

    my @Columns;
    my @Indexes;
    my @ForeignKeys;
    my @OtherItems;

    for my $Definition ( _DefinitionListSplit($Body) ) {
        $Definition =~ s/\A\s+//;
        $Definition =~ s/\s+\z//;
        next if $Definition eq q{};

        if ( $Definition =~ m{\A`([^`]+)`\s+}s ) {
            push @Columns, {
                Name       => $1,
                Definition => $Definition,
            };
            next;
        }

        if ( $Definition =~ m{\APRIMARY\s+KEY\b}i ) {
            push @Indexes, {
                Name       => undef,
                Definition => $Definition,
                Signature  => _IndexSignature($Definition),
            };
            next;
        }

        if ( $Definition =~ m{\A(?:UNIQUE\s+|FULLTEXT\s+|SPATIAL\s+)?KEY\s+`([^`]+)`}i ) {
            push @Indexes, {
                Name       => $1,
                Definition => $Definition,
                Signature  => _IndexSignature($Definition),
            };
            next;
        }

        if ( $Definition =~ m{\A(?:CONSTRAINT\s+`([^`]+)`\s+)?FOREIGN\s+KEY\b}i ) {
            push @ForeignKeys, {
                Name       => defined $1 ? $1 : q{},
                Definition => $Definition,
                Signature  => _ForeignKeySignature($Definition),
            };
            next;
        }

        push @OtherItems, {
            Definition => $Definition,
        };
    }

    return {
        Name        => $Name,
        Columns     => \@Columns,
        Indexes     => \@Indexes,
        ForeignKeys => \@ForeignKeys,
        OtherItems  => \@OtherItems,
        TableOptions => $TableOptions,
    };
}

sub _DefinitionListSplit {
    my ($Body) = @_;

    my @Part;
    my $Current = q{};
    my $Depth = 0;
    my $Quote = q{};
    my $Escaped = 0;
    my @Character = split //, $Body;

    for my $Character (@Character) {
        if ($Quote) {
            $Current .= $Character;

            if ($Escaped) {
                $Escaped = 0;
                next;
            }
            if ( $Character eq '\\' && $Quote ne '`' ) {
                $Escaped = 1;
                next;
            }
            if ( $Character eq $Quote ) {
                $Quote = q{};
            }
            next;
        }

        if ( $Character eq "'" || $Character eq '"' || $Character eq '`' ) {
            $Quote = $Character;
            $Current .= $Character;
            next;
        }
        if ( $Character eq q{(} ) {
            $Depth++;
            $Current .= $Character;
            next;
        }
        if ( $Character eq q{)} ) {
            $Depth--;
            if ( $Depth < 0 ) {
                die "Ungültige Klammerung in einer CREATE-TABLE-Anweisung.\n";
            }
            $Current .= $Character;
            next;
        }
        if ( $Character eq q{,} && $Depth == 0 ) {
            push @Part, $Current;
            $Current = q{};
            next;
        }

        $Current .= $Character;
    }

    if ($Quote) {
        die "Nicht abgeschlossene Zeichenkette in einer CREATE-TABLE-Anweisung.\n";
    }
    if ( $Depth != 0 ) {
        die "Ungültige Klammerung in einer CREATE-TABLE-Anweisung.\n";
    }

    push @Part, $Current if $Current =~ m{\S};
    return @Part;
}

sub _ShowCreateTable {
    my (%Param) = @_;

    my $Statement = $Param{DBH}->prepare(
        'SHOW CREATE TABLE ' . _QuoteIdentifier( $Param{TableName} )
    );
    $Statement->execute();
    my $Row = $Statement->fetchrow_arrayref();
    $Statement->finish();

    if ( !$Row || !defined $Row->[1] ) {
        die "Die Definition der Tabelle $Param{TableName} konnte nicht gelesen werden.\n";
    }

    return $Row->[1];
}

sub _MissingColumnSafetyCheck {
    my (%Param) = @_;

    my $Definition = $Param{Definition};
    return if $Definition !~ m{\bNOT\s+NULL\b}i;
    return if $Definition =~ m{\bDEFAULT\b}i;
    return if $Definition =~ m{\bAUTO_INCREMENT\b}i;

    my ($HasRows) = $Param{DBH}->selectrow_array(
        'SELECT EXISTS(SELECT 1 FROM ' . _QuoteIdentifier( $Param{TableName} ) . ' LIMIT 1)'
    );

    if ($HasRows) {
        die "Die fehlende Pflichtspalte aus schema.sql kann nicht sicher zu einer bereits gefüllten Tabelle hinzugefügt werden: $Param{TableName}. Eine ausdrückliche Datenmigration ist erforderlich.\n";
    }
}

sub _IndexSignature {
    my ($Definition) = @_;

    my $Normalized = _DefinitionNormalize($Definition);
    $Normalized =~ s/\A(unique|fulltext|spatial)\s+key\s+`[^`]+`\s*/$1 key /i;
    $Normalized =~ s/\Akey\s+`[^`]+`\s*/key /i;
    return $Normalized;
}

sub _ForeignKeySignature {
    my ($Definition) = @_;

    my $Normalized = _DefinitionNormalize($Definition);
    $Normalized =~ s/\Aconstraint\s+`[^`]+`\s+//i;
    return $Normalized;
}

sub _DefinitionNormalize {
    my ($Definition) = @_;

    my $Normalized = lc $Definition;
    $Normalized =~ s/\s+/ /g;
    $Normalized =~ s/\s*\(\s*/(/g;
    $Normalized =~ s/\s*\)\s*/)/g;
    $Normalized =~ s/\s*,\s*/,/g;
    $Normalized =~ s/\A\s+//;
    $Normalized =~ s/\s+\z//;
    return $Normalized;
}

sub _TableOptionsNormalize {
    my ($Options) = @_;

    my $Normalized = lc( $Options || q{} );
    $Normalized =~ s/\bauto_increment\s*=\s*\d+\b//g;
    $Normalized =~ s/\s+/ /g;
    $Normalized =~ s/\A\s+//;
    $Normalized =~ s/\s+\z//;
    return $Normalized;
}

sub _QuoteIdentifier {
    my ($Identifier) = @_;

    if ( !defined $Identifier || $Identifier !~ m{\A[A-Za-z0-9_]+\z} ) {
        die "Ungültiger SQL-Bezeichner.\n";
    }
    return '`' . $Identifier . '`';
}

sub _Warning {
    my (%Param) = @_;

    ${ $Param{Counter} }++;
    print "  WARNUNG: $Param{Message}\n";
    return;
}
