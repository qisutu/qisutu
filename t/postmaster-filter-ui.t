use strict;
use warnings;
use utf8;

use Test::More;
use JSON::PP qw(decode_json);
use FindBin;
use File::Spec;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module";

use QisutuPostmasterFilter;
use AdminPostmasterFilters;

my $Object = QisutuPostmasterFilter->new(
    Config => { Language => { Default => 'de' } },
);

my %Condition = map { ( $_->{key} || '' ) => $_ } @{ $Object->ConditionDefinitions() };
ok( $Condition{from_email} && !$Condition{from_email}->{advanced}, 'sender address is a basic email condition' );
ok( $Condition{custom_header}->{advanced} && $Condition{custom_header}->{argument}, 'custom header is an advanced condition with a header name' );
ok( $Condition{existing_ticket}->{legacy}, 'existing-ticket condition is retained only for legacy compatibility' );

my %Action = map { ( $_->{key} || '' ) => $_ } @{ $Object->ActionDefinitions() };
is( $Action{state}->{target}, 'state', 'state action uses a state selector' );
is( $Action{state}->{target_label}, 'Translate:PostmasterActionFieldState', 'state selector has a specific label' );
ok( !$Action{state}->{value_label}, 'state action has no redundant free value' );
is( $Action{dynamic_field}->{target}, 'dynamic_field_value', 'dynamic-field action requires target and value' );
is( $Action{pending_minutes}->{value_label}, 'Translate:PostmasterActionFieldMinutes', 'pending time is labelled as minutes' );

my $Module = AdminPostmasterFilters->new(
    Config => { Language => { Default => 'de' } },
);
my $NewConfig = decode_json( $Module->_ClientConfig(
    Object   => $Object,
    Options  => {},
    Form     => { conditions => [], actions => [] },
    Language => 'de',
) );
my %NewField = map { ( $_->{key} || '' ) => 1 } @{ $NewConfig->{conditionDefinitions} || [] };
ok( !$NewField{existing_ticket}, 'existing-ticket context is not selectable in new filters' );
ok( !$NewField{customer_name} && !$NewField{customer_company}, 'derived customer context is not presented as an email field' );

my $LegacyConfig = decode_json( $Module->_ClientConfig(
    Object   => $Object,
    Options  => {},
    Form     => { conditions => [ { field_name => 'existing_ticket', operator => 'equals', match_value => 'yes' } ], actions => [] },
    Language => 'de',
) );
my %LegacyField = map { ( $_->{key} || '' ) => $_ } @{ $LegacyConfig->{conditionDefinitions} || [] };
ok( $LegacyField{existing_ticket}->{legacy}, 'a previously stored legacy condition remains editable without data loss' );

my $JavaScriptFile = File::Spec->catfile( $FindBin::Bin, '..', 'var', 'static', 'js', 'qisutu-postmaster-filter.js' );
open my $JavaScriptHandle, '<:encoding(UTF-8)', $JavaScriptFile or die "Could not read $JavaScriptFile: $!";
local $/;
my $JavaScript = <$JavaScriptHandle>;
close $JavaScriptHandle;
like( $JavaScript, qr{argumentWrap\.style\.display\s*=\s*hasArgument}, 'email-header input is hidden directly when it is not applicable' );
like( $JavaScript, qr{valueWrap\.style\.display\s*=\s*needsValue}, 'redundant action-value input is hidden directly when it is not applicable' );

done_testing();
