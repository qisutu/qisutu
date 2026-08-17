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

package QisutuTicketSearch;

use strict;
use warnings;
use utf8;

use QisutuDynamicField;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Param{Permission},
        LastError  => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub WhereData {
    my ( $Self, %Param ) = @_;

    my $Search = ref $Param{Search} eq 'HASH' ? $Param{Search} : {};
    return { Where => [], Bind => [] } if !$Search->{Active};

    my @Where;
    my @Bind;

    if ( my $Text = $Self->_Trim( $Search->{Text} ) ) {
        my $FreeText = $Self->_FreeTextWhere(
            Text   => $Text,
            Mode   => $Search->{Mode} || 'all',
            Scopes => $Search->{Scopes} || {},
        );
        if ( $FreeText->{SQL} ) {
            push @Where, $FreeText->{SQL};
            push @Bind, @{ $FreeText->{Bind} || [] };
        }
    }

    if ( my $Number = $Self->_Trim( $Search->{TicketNumber} ) ) {
        push @Where, 't.ticket_number LIKE ? ESCAPE "\\\\"';
        push @Bind, '%' . $Self->_LikeEscape($Number) . '%';
    }

    if ( my $Title = $Self->_Trim( $Search->{Title} ) ) {
        push @Where, 't.title LIKE ? ESCAPE "\\\\"';
        push @Bind, '%' . $Self->_LikeEscape($Title) . '%';
    }

    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.queue_id',         Values => $Search->{QueueIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.state_id',         Values => $Search->{StateIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.priority_id',      Values => $Search->{PriorityIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.customer_id',      Values => $Search->{CustomerIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.customer_user_id', Values => $Search->{CustomerUserIDs} );
    $Self->_NullableIDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.owner_user_id',       Values => $Search->{OwnerIDs} );
    $Self->_NullableIDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.responsible_user_id', Values => $Search->{ResponsibleIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.service_id',       Values => $Search->{ServiceIDs} );
    $Self->_IDConditionAdd( Where => \@Where, Bind => \@Bind, Column => 't.sla_id',           Values => $Search->{SLAIDs} );

    for my $Range (
        [ CreatedFrom          => CreatedTo          => 't.created_at' ],
        [ ChangedFrom          => ChangedTo          => 't.changed_at' ],
        [ SolutionFrom         => SolutionTo         => 't.solution_at' ],
        [ PendingFrom          => PendingTo          => 't.pending_until' ],
        [ FirstResponseDueFrom => FirstResponseDueTo => 't.first_response_due_at' ],
        [ UpdateDueFrom        => UpdateDueTo        => 't.update_due_at' ],
        [ SolutionDueFrom      => SolutionDueTo      => 't.solution_due_at' ],
    ) {
        my ( $FromKey, $ToKey, $Column ) = @{$Range};
        my $From = $Self->_DateTimeClean( $Search->{$FromKey}, 0 );
        my $To   = $Self->_DateTimeClean( $Search->{$ToKey}, 1 );

        if ($From) {
            push @Where, $Column . ' >= ?';
            push @Bind, $From;
        }
        if ($To) {
            push @Where, $Column . ' <= ?';
            push @Bind, $To;
        }
    }

    my $Escalation = $Self->_EscalationWhere( Values => $Search->{Escalation} );
    if ( $Escalation->{SQL} ) {
        push @Where, $Escalation->{SQL};
        push @Bind, @{ $Escalation->{Bind} || [] };
    }

    for my $Dynamic ( @{ $Search->{Dynamic} || [] } ) {
        my $Condition = $Self->_DynamicWhere( Dynamic => $Dynamic );
        next if !$Condition->{SQL};
        push @Where, $Condition->{SQL};
        push @Bind, @{ $Condition->{Bind} || [] };
    }

    return {
        Where => \@Where,
        Bind  => \@Bind,
    };
}

sub Options {
    my ( $Self, %Param ) = @_;

    my $User     = $Param{User} || {};
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my @QueueIDs;

    if ( $Self->{Permission} ) {
        my $Allowed = $Self->{Permission}->QueueIDList(
            UserID     => $User->{user_account_id},
            Permission => 'ticket.view',
        );
        @QueueIDs = @{$Allowed || []};
    }

    my $QueueWhere = '';
    my @QueueBind;
    if ( $Self->{Permission} ) {
        return $Self->_EmptyOptions() if !@QueueIDs;
        my $Placeholder = join ', ', map {'?'} @QueueIDs;
        $QueueWhere = 'WHERE id IN (' . $Placeholder . ')';
        @QueueBind = @QueueIDs;
    }

    my $TicketQueueWhere = '';
    my @TicketQueueBind;
    if (@QueueIDs) {
        my $Placeholder = join ', ', map {'?'} @QueueIDs;
        $TicketQueueWhere = 'WHERE t.queue_id IN (' . $Placeholder . ')';
        @TicketQueueBind = @QueueIDs;
    }

    my $Queues = $Self->{DB}->SelectAll(
        'SELECT id, COALESCE(NULLIF(full_name, ""), name) AS label
         FROM ticket_queue
         ' . $QueueWhere . '
         ORDER BY sort_order ASC, label ASC, id ASC',
        @QueueBind,
    ) || [];

    my $States = $Self->{DB}->SelectAll(
        'SELECT id, name AS label, state_type
         FROM ticket_state
         WHERE active = 1
         ORDER BY sort_order ASC, name ASC, id ASC'
    ) || [];

    my $Priorities = $Self->{DB}->SelectAll(
        'SELECT id, name AS label
         FROM ticket_priority
         WHERE active = 1
         ORDER BY sort_order ASC, priority_value ASC, name ASC, id ASC'
    ) || [];

    my $Customers = $Self->{DB}->SelectAll(
        'SELECT DISTINCT c.id, CONCAT(c.name, " (", c.customer_number, ")") AS label
         FROM ticket t
         INNER JOIN customer c ON c.id = t.customer_id
         ' . $TicketQueueWhere . '
         ORDER BY c.name ASC, c.customer_number ASC, c.id ASC',
        @TicketQueueBind,
    ) || [];

    my $CustomerUsers = $Self->{DB}->SelectAll(
        'SELECT DISTINCT
            cu.id,
            CONCAT(
                COALESCE(NULLIF(TRIM(CONCAT(ua.firstname, " ", ua.lastname)), ""), ua.email),
                " — ", c.name,
                " <", ua.email, ">"
            ) AS label
         FROM ticket t
         INNER JOIN customer_user cu ON cu.id = t.customer_user_id
         INNER JOIN user_account ua ON ua.id = cu.user_account_id
         INNER JOIN customer c ON c.id = cu.customer_id
         ' . $TicketQueueWhere . '
         ORDER BY label ASC, cu.id ASC',
        @TicketQueueBind,
    ) || [];

    my $Agents = $Self->{DB}->SelectAll(
        'SELECT id,
            COALESCE(NULLIF(TRIM(CONCAT(firstname, " ", lastname)), ""), login, email) AS label
         FROM user_account
         WHERE account_type = ? AND is_active = 1
         ORDER BY label ASC, id ASC',
        'agent',
    ) || [];

    my $Services = $Self->{DB}->SelectAll(
        'SELECT id, full_name AS label
         FROM service
         WHERE active = 1
         ORDER BY sort_order ASC, full_name ASC, id ASC'
    ) || [];

    my $SLAs = $Self->{DB}->SelectAll(
        'SELECT sl.id, CONCAT(svc.full_name, " — ", sl.name) AS label
         FROM sla sl
         INNER JOIN service svc ON svc.id = sl.service_id
         WHERE sl.active = 1
         ORDER BY svc.full_name ASC, sl.sort_order ASC, sl.name ASC, sl.id ASC'
    ) || [];

    my $DynamicObject = QisutuDynamicField->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my $DynamicFields = $DynamicObject->FieldList(
        Language        => $Language,
        IncludeInactive => 0,
    ) || [];

    for my $Field ( @{$DynamicFields} ) {
        next if ( $Field->{field_type} || '' ) !~ m{\A(?:dropdown|multiselect)\z};
        $Field->{options} = $DynamicObject->OptionList(
            FieldID => $Field->{id},
            Language => $Language,
        ) || [];
    }

    if ( $DynamicObject->Error() ) {
        $Self->{LastError} = $DynamicObject->Error();
    }

    return {
        Queues         => $Queues,
        States         => $States,
        Priorities     => $Priorities,
        Customers      => $Customers,
        CustomerUsers  => $CustomerUsers,
        Owners         => $Agents,
        Responsibles   => $Agents,
        Services       => $Services,
        SLAs           => $SLAs,
        DynamicFields  => $DynamicFields,
    };
}

sub _EmptyOptions {
    return {
        Queues => [], States => [], Priorities => [], Customers => [], CustomerUsers => [],
        Owners => [], Responsibles => [], Services => [], SLAs => [], DynamicFields => [],
    };
}

sub _FreeTextWhere {
    my ( $Self, %Param ) = @_;

    my $Text   = $Self->_Trim( $Param{Text} );
    my $Mode   = $Param{Mode} || 'all';
    my $Scopes = ref $Param{Scopes} eq 'HASH' ? $Param{Scopes} : {};

    return { SQL => '', Bind => [] } if !$Text;

    my @Scope = grep { $Scopes->{$_} } qw(title article people attachment);
    @Scope = qw(title article people attachment) if !@Scope;

    my @Needle;
    if ( $Mode eq 'phrase' ) {
        @Needle = ($Text);
    }
    else {
        @Needle = grep { $_ ne '' } split /\s+/, $Text;
        @Needle = ($Text) if !@Needle;
    }

    my @TokenSQL;
    my @Bind;

    TOKEN:
    for my $Needle (@Needle) {
        $Needle = $Self->_Trim($Needle);
        next TOKEN if !$Needle;

        my @ScopeSQL;
        my @ScopeBind;
        my $Like = '%' . $Self->_LikeEscape($Needle) . '%';
        my $UseFullText = $Mode ne 'phrase' && $Self->_FullTextNeedleEligible($Needle);
        my $Boolean = $UseFullText ? $Self->_BooleanNeedle( Value => $Needle ) : '';

        if ( grep { $_ eq 'title' } @Scope ) {
            if ($UseFullText) {
                push @ScopeSQL,
                    '(MATCH(t.title) AGAINST (? IN BOOLEAN MODE)
                      OR t.ticket_number LIKE ? ESCAPE "\\\\")';
                push @ScopeBind, $Boolean, $Like;
            }
            else {
                push @ScopeSQL,
                    '(t.title LIKE ? ESCAPE "\\\\"
                      OR t.ticket_number LIKE ? ESCAPE "\\\\")';
                push @ScopeBind, $Like, $Like;
            }
        }

        if ( grep { $_ eq 'article' } @Scope ) {
            if ($UseFullText) {
                push @ScopeSQL,
                    'EXISTS (
                        SELECT 1
                        FROM ticket_article search_article
                        WHERE search_article.ticket_id = t.id
                          AND MATCH(search_article.subject, search_article.search_text)
                              AGAINST (? IN BOOLEAN MODE)
                    )';
                push @ScopeBind, $Boolean;
            }
            else {
                push @ScopeSQL,
                    'EXISTS (
                        SELECT 1
                        FROM ticket_article search_article
                        WHERE search_article.ticket_id = t.id
                          AND (
                            search_article.subject LIKE ? ESCAPE "\\\\"
                            OR search_article.search_text LIKE ? ESCAPE "\\\\"
                          )
                    )';
                push @ScopeBind, $Like, $Like;
            }
        }

        if ( grep { $_ eq 'people' } @Scope ) {
            push @ScopeSQL,
                '(
                    EXISTS (
                        SELECT 1 FROM customer search_customer
                        WHERE search_customer.id = t.customer_id
                          AND (search_customer.name LIKE ? ESCAPE "\\\\" OR search_customer.customer_number LIKE ? ESCAPE "\\\\")
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM customer_user search_customer_user
                        INNER JOIN user_account search_customer_account ON search_customer_account.id = search_customer_user.user_account_id
                        WHERE search_customer_user.id = t.customer_user_id
                          AND CONCAT_WS(" ", search_customer_account.firstname, search_customer_account.lastname, search_customer_account.email) LIKE ? ESCAPE "\\\\"
                    )
                    OR EXISTS (
                        SELECT 1 FROM user_account search_owner
                        WHERE search_owner.id = t.owner_user_id
                          AND CONCAT_WS(" ", search_owner.firstname, search_owner.lastname, search_owner.email, search_owner.login) LIKE ? ESCAPE "\\\\"
                    )
                    OR EXISTS (
                        SELECT 1 FROM user_account search_responsible
                        WHERE search_responsible.id = t.responsible_user_id
                          AND CONCAT_WS(" ", search_responsible.firstname, search_responsible.lastname, search_responsible.email, search_responsible.login) LIKE ? ESCAPE "\\\\"
                    )
                    OR EXISTS (
                        SELECT 1 FROM ticket_article search_address_article
                        WHERE search_address_article.ticket_id = t.id
                          AND CONCAT_WS(" ", search_address_article.from_name, search_address_article.from_email, search_address_article.to_name, search_address_article.to_email, search_address_article.cc) LIKE ? ESCAPE "\\\\"
                    )
                )';
            push @ScopeBind, ($Like) x 6;
        }

        if ( grep { $_ eq 'attachment' } @Scope ) {
            if ($UseFullText) {
                push @ScopeSQL,
                    'EXISTS (
                        SELECT 1
                        FROM ticket_article_attachment search_attachment
                        WHERE search_attachment.ticket_id = t.id
                          AND (
                            MATCH(search_attachment.filename) AGAINST (? IN BOOLEAN MODE)
                            OR search_attachment.content_type LIKE ? ESCAPE "\\\\"
                          )
                    )';
                push @ScopeBind, $Boolean, $Like;
            }
            else {
                push @ScopeSQL,
                    'EXISTS (
                        SELECT 1
                        FROM ticket_article_attachment search_attachment
                        WHERE search_attachment.ticket_id = t.id
                          AND (
                            search_attachment.filename LIKE ? ESCAPE "\\\\"
                            OR search_attachment.content_type LIKE ? ESCAPE "\\\\"
                          )
                    )';
                push @ScopeBind, $Like, $Like;
            }
        }

        next TOKEN if !@ScopeSQL;
        push @TokenSQL, '(' . join( ' OR ', map { '(' . $_ . ')' } @ScopeSQL ) . ')';
        push @Bind, @ScopeBind;
    }

    return { SQL => '', Bind => [] } if !@TokenSQL;

    my $Join = $Mode eq 'any' ? ' OR ' : ' AND ';
    return {
        SQL  => '(' . join( $Join, @TokenSQL ) . ')',
        Bind => \@Bind,
    };
}

sub _FullTextNeedleEligible {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{[^\p{L}\p{N}_]+}{ }g;
    my @Word = grep { length($_) >= 3 } split /\s+/, $Value;
    return @Word ? 1 : 0;
}

sub _BooleanNeedle {
    my ( $Self, %Param ) = @_;

    my $Value = $Param{Value} || '';
    $Value =~ s{[^\p{L}\p{N}_]+}{ }g;
    my @Word = grep { length($_) >= 3 } split /\s+/, $Value;
    return join ' ', map { '+' . $_ . '*' } @Word;
}

sub _IDConditionAdd {
    my ( $Self, %Param ) = @_;

    my $Values = $Self->_IDList( $Param{Values} );
    return if !@{$Values};

    push @{ $Param{Where} }, $Param{Column} . ' IN (' . join( ', ', map {'?'} @{$Values} ) . ')';
    push @{ $Param{Bind} }, @{$Values};
}

sub _NullableIDConditionAdd {
    my ( $Self, %Param ) = @_;

    my @Raw = @{ $Self->_ValueList( $Param{Values} ) };
    my $HasUnassigned = grep { defined $_ && $_ eq 'unassigned' } @Raw;
    my $Values = $Self->_IDList( \@Raw );
    return if !$HasUnassigned && !@{$Values};

    my @Condition;
    if (@{$Values}) {
        push @Condition, $Param{Column} . ' IN (' . join( ', ', map {'?'} @{$Values} ) . ')';
        push @{ $Param{Bind} }, @{$Values};
    }
    push @Condition, $Param{Column} . ' IS NULL' if $HasUnassigned;
    push @{ $Param{Where} }, '(' . join( ' OR ', @Condition ) . ')';
}

sub _EscalationWhere {
    my ( $Self, %Param ) = @_;

    my %Allowed = map { $_ => 1 } qw(normal warning escalated no_sla first_open update_open solution_open);
    my @Value = grep { $Allowed{$_} } @{ $Self->_ValueList( $Param{Values} ) };
    return { SQL => '', Bind => [] } if !@Value;

    my $CurrentBreach = '(
        (t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL AND t.first_response_due_at <= NOW())
        OR (t.update_due_at IS NOT NULL AND t.update_due_at <= NOW())
        OR (t.solution_due_at IS NOT NULL AND t.solution_at IS NULL AND t.solution_due_at <= NOW())
        OR t.sla_first_response_breached = 1
        OR t.sla_update_breached = 1
        OR t.sla_solution_breached = 1
    )';

    my @SQL;
    for my $Value (@Value) {
        if ( $Value eq 'normal' ) {
            push @SQL, '(COALESCE(t.escalation_state, "normal") = "normal" AND NOT ' . $CurrentBreach . ')';
        }
        elsif ( $Value eq 'warning' ) {
            push @SQL, '(t.escalation_state = "warning" AND NOT ' . $CurrentBreach . ')';
        }
        elsif ( $Value eq 'escalated' ) {
            push @SQL, $CurrentBreach;
        }
        elsif ( $Value eq 'no_sla' ) {
            push @SQL, 't.sla_id IS NULL';
        }
        elsif ( $Value eq 'first_open' ) {
            push @SQL, '(t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL)';
        }
        elsif ( $Value eq 'update_open' ) {
            push @SQL, 't.update_due_at IS NOT NULL';
        }
        elsif ( $Value eq 'solution_open' ) {
            push @SQL, '(t.solution_due_at IS NOT NULL AND t.solution_at IS NULL)';
        }
    }

    return {
        SQL  => '(' . join( ' OR ', map { '(' . $_ . ')' } @SQL ) . ')',
        Bind => [],
    };
}

sub _DynamicWhere {
    my ( $Self, %Param ) = @_;

    my $Dynamic = ref $Param{Dynamic} eq 'HASH' ? $Param{Dynamic} : {};
    my $FieldID = $Dynamic->{id} || 0;
    return { SQL => '', Bind => [] } if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Type     = $Dynamic->{type} || 'text';
    my $Operator = $Dynamic->{operator} || '';
    my $Value    = $Self->_Trim( $Dynamic->{value} );
    my $ValueTo  = $Self->_Trim( $Dynamic->{value_to} );
    my @Values   = grep { $_ ne '' } @{ $Self->_ValueList( $Dynamic->{values} ) };

    if ( $Operator eq 'empty' ) {
        return {
            SQL  => 'NOT EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND COALESCE(TRIM(search_dfv.value_text), "") <> "")',
            Bind => [$FieldID],
        };
    }
    if ( $Operator eq 'not_empty' ) {
        return {
            SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND COALESCE(TRIM(search_dfv.value_text), "") <> "")',
            Bind => [$FieldID],
        };
    }

    if ( $Type eq 'dropdown' ) {
        return { SQL => '', Bind => [] } if !@Values;
        return {
            SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND search_dfv.value_text IN (' . join( ', ', map {'?'} @Values ) . '))',
            Bind => [ $FieldID, @Values ],
        };
    }

    if ( $Type eq 'multiselect' ) {
        return { SQL => '', Bind => [] } if !@Values;
        my @Part;
        my @Bind = ($FieldID);
        for my $Selected (@Values) {
            push @Part, 'CONCAT("\\n", COALESCE(search_dfv.value_text, ""), "\\n") LIKE ? ESCAPE "\\\\"';
            push @Bind, '%\n' . $Self->_LikeEscape($Selected) . '\n%';
        }
        my $Join = $Operator eq 'all' ? ' AND ' : ' OR ';
        return {
            SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND (' . join( $Join, @Part ) . '))',
            Bind => \@Bind,
        };
    }

    if ( $Type eq 'number' ) {
        if ( $Operator eq 'between' && $Value ne '' && $ValueTo ne '' ) {
            $Value =~ tr/,/./;
            $ValueTo =~ tr/,/./;
            return { SQL => '', Bind => [] }
                if $Value !~ m{\A[-+]?(?:\d+(?:\.\d+)?|\.\d+)\z}
                || $ValueTo !~ m{\A[-+]?(?:\d+(?:\.\d+)?|\.\d+)\z};
            return {
                SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND CAST(REPLACE(search_dfv.value_text, ",", ".") AS DECIMAL(30,10)) BETWEEN ? AND ?)',
                Bind => [ $FieldID, $Value, $ValueTo ],
            };
        }
        return { SQL => '', Bind => [] } if $Value eq '';
        $Value =~ tr/,/./;
        return { SQL => '', Bind => [] }
            if $Value !~ m{\A[-+]?(?:\d+(?:\.\d+)?|\.\d+)\z};
        my $Comparison = $Operator eq 'from' ? '>=' : $Operator eq 'to' ? '<=' : '=';
        return {
            SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND CAST(REPLACE(search_dfv.value_text, ",", ".") AS DECIMAL(30,10)) ' . $Comparison . ' ?)',
            Bind => [ $FieldID, $Value ],
        };
    }

    if ( $Type eq 'date' ) {
        my $From = $Self->_DateTimeClean( $Value, 0 );
        my $To   = $Self->_DateTimeClean( $Operator eq 'between' ? $ValueTo : $Value, 1 );

        if ( $Operator eq 'between' && $From && $To ) {
            return {
                SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND search_dfv.value_text BETWEEN ? AND ?)',
                Bind => [ $FieldID, $From, $To ],
            };
        }
        if ( $Operator eq 'from' && $From ) {
            return {
                SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND search_dfv.value_text >= ?)',
                Bind => [ $FieldID, $From ],
            };
        }
        if ( $Operator eq 'to' && $To ) {
            return {
                SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND search_dfv.value_text <= ?)',
                Bind => [ $FieldID, $To ],
            };
        }
        return { SQL => '', Bind => [] };
    }

    return { SQL => '', Bind => [] } if $Value eq '';

    my $SQL;
    my $BindValue;
    if ( $Operator eq 'exact' ) {
        $SQL = 'search_dfv.value_text = ?';
        $BindValue = $Value;
    }
    elsif ( $Operator eq 'starts' ) {
        $SQL = 'search_dfv.value_text LIKE ? ESCAPE "\\\\"';
        $BindValue = $Self->_LikeEscape($Value) . '%';
    }
    else {
        $SQL = 'search_dfv.value_text LIKE ? ESCAPE "\\\\"';
        $BindValue = '%' . $Self->_LikeEscape($Value) . '%';
    }

    return {
        SQL  => 'EXISTS (SELECT 1 FROM ticket_dynamic_field_value search_dfv WHERE search_dfv.ticket_id = t.id AND search_dfv.field_id = ? AND ' . $SQL . ')',
        Bind => [ $FieldID, $BindValue ],
    };
}

sub _IDList {
    my ( $Self, $Value ) = @_;
    my %Seen;
    my @ID;
    for my $Item ( @{ $Self->_ValueList($Value) } ) {
        next if !defined $Item || $Item !~ m{\A\d+\z} || !$Item;
        next if $Seen{$Item}++;
        push @ID, 0 + $Item;
    }
    return \@ID;
}

sub _ValueList {
    my ( $Self, $Value ) = @_;
    return [] if !defined $Value;
    return [ @{$Value} ] if ref $Value eq 'ARRAY';
    return [$Value];
}

sub _DateTimeClean {
    my ( $Self, $Value, $EndOfDay ) = @_;

    $Value = $Self->_Trim($Value);
    return '' if !$Value;
    $Value =~ s{T}{ }g;

    if ( $Value =~ m{\A(\d{4})-(\d{2})-(\d{2})\z} ) {
        return '' if !$Self->_DatePartsValid( $1, $2, $3, 0, 0, 0 );
        return $1 . '-' . $2 . '-' . $3 . ( $EndOfDay ? ' 23:59:59' : ' 00:00:00' );
    }
    if ( $Value =~ m{\A(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?\z} ) {
        my $Second = defined $6 ? $6 : ( $EndOfDay ? 59 : 0 );
        return '' if !$Self->_DatePartsValid( $1, $2, $3, $4, $5, $Second );
        return sprintf '%04d-%02d-%02d %02d:%02d:%02d', $1, $2, $3, $4, $5, $Second;
    }

    return '';
}

sub _DatePartsValid {
    my ( $Self, $Year, $Month, $Day, $Hour, $Minute, $Second ) = @_;

    return 0 if $Year < 1000 || $Year > 9999;
    return 0 if $Month < 1 || $Month > 12;
    return 0 if $Hour < 0 || $Hour > 23;
    return 0 if $Minute < 0 || $Minute > 59;
    return 0 if $Second < 0 || $Second > 59;

    my @Days = ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );
    if ( ( $Year % 4 == 0 && $Year % 100 != 0 ) || $Year % 400 == 0 ) {
        $Days[1] = 29;
    }

    return 0 if $Day < 1 || $Day > $Days[ $Month - 1 ];
    return 1;
}

sub _LikeEscape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\\}{\\\\}g;
    $Value =~ s{%}{\\%}g;
    $Value =~ s{_}{\\_}g;
    return $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || ref $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
