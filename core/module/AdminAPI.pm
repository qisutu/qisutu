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

package AdminAPI;

use strict;
use warnings;
use utf8;

use JSON::PP ();
use QisutuAPIAuth;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config=>$Param{Config}, DB=>$Param{DB}, Output=>$Param{Output}, Program=>$Param{Program} };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuAPIAuth->new( Config=>$Self->{Config}, DB=>$Self->{DB} );
    my $Step     = $Request->{Step} || '';
    my $Error    = '';
    my $Created;

    if ( $Step eq 'APIUserSearch' ) {
        my $Rows = $Object->UserSearch( Search => $Request->{Search} || '' );
        my @Items = map { +{
            id=>0+$_->{user_account_id}, name=>$_->{user_name}, login=>$_->{login}, email=>$_->{email},
            account_type=>$_->{account_type}, customer_name=>$_->{customer_name} || '',
        } } @{$Rows || []};
        return { Response => $Self->{Output}->Response(
            ContentType=>'application/json; charset=UTF-8',
            Headers=>['Cache-Control: no-store'],
            Body=>JSON::PP->new->canonical(1)->encode({success=>JSON::PP::true,items=>\@Items}),
        ) };
    }
    if ( $Step =~ m{\AAPIToken(?:Create|Update|Activate|Deactivate)\z}
        && ( $Request->{__RequestMethod} || '' ) ne 'POST' ) {
        return { Response => $Self->{Output}->Response(
            Status => '405 Method Not Allowed', Headers => ['Allow: POST'], Body => 'POST required.',
        ) };
    }

    my $Editing = $Step eq 'APITokenEdit' || $Step eq 'APITokenUpdate';
    my $EditToken = $Editing ? $Object->TokenGet( TokenID => $Request->{TokenID} ) : undef;
    if ( $Editing && !$EditToken ) {
        $Error = $Object->Error();
        $Editing = 0;
    }
    if ( $Step eq 'APITokenCreate' || ( $Step eq 'APITokenUpdate' && $EditToken ) ) {
        my @Scopes = ref $Request->{Scope} eq 'ARRAY' ? @{$Request->{Scope}} : defined $Request->{Scope} ? ($Request->{Scope}) : ();
        my %Settings = (
            UserAccountID=>$Request->{UserAccountID}, Label=>$Request->{Label}, Scopes=>\@Scopes,
            Lifetime=>$Request->{Lifetime}, AllowedIPs=>$Request->{AllowedIPs},
            RateLimitPerMinute=>$Request->{RateLimitPerMinute}, ChangedByUserID=>$User->{user_account_id},
        );
        if ( $Editing ) {
            return { Redirect => 'index.pl?Page=AdminAPI;Notice=updated' }
                if $Object->TokenUpdate( %Settings, TokenID => $EditToken->{id} );
            $Error = $Object->Error();
        }
        else {
            $Created = $Object->TokenCreate(%Settings);
            $Error = $Object->Error() if !$Created;
        }
    }
    elsif ( $Step eq 'APITokenDeactivate' || $Step eq 'APITokenActivate' ) {
        my $Method = $Step eq 'APITokenActivate' ? 'TokenActivate' : 'TokenDeactivate';
        my $OK = $Object->$Method( TokenID=>$Request->{TokenID}, ChangedByUserID=>$User->{user_account_id} );
        return { Redirect=>'index.pl?Page=AdminAPI;Notice=' . ( $Step eq 'APITokenActivate' ? 'activated' : 'deactivated' ) } if $OK;
        $Error = $Object->Error();
    }

    my $Form = {};
    if ( $Editing && $Step eq 'APITokenEdit' ) {
        $Form = {
            Label => $EditToken->{label}, UserAccountID => $EditToken->{user_account_id},
            Scope => $EditToken->{scopes}, Lifetime => 'keep', AllowedIPs => $EditToken->{allowed_ips},
            RateLimitPerMinute => $EditToken->{rate_limit_per_minute},
        };
    }
    elsif ( $Error && ( $Step eq 'APITokenCreate' || ( $Editing && $Step eq 'APITokenUpdate' ) ) ) {
        $Form = $Request;
    }
    my $HasFormValues = $Editing || $Step eq 'APITokenCreate' && $Error;
    my $Definitions = $Object->ScopeDefinitions();
    if ( $EditToken ) {
        my %Known = map { $_->{Key} => 1 } @{$Definitions};
        for my $Scope ( @{$EditToken->{scopes}} ) {
            push @{$Definitions}, { Key => $Scope, Label => $Scope, Group => 'addons' } if !$Known{$Scope}++;
        }
    }
    my %Group;
    for my $Def (@{$Definitions}) {
        my %Copy=%{$Def};
        $Copy{LabelText}=$Self->_T($Def->{Label},$Language);
        $Copy{InputID}='api-scope-'.$Def->{Key};$Copy{InputID}=~s{[^A-Za-z0-9_-]}{-}g;
        push @{$Group{$Def->{Group}}},\%Copy;
    }
    my @ScopeGroups;
    for my $GroupKey (qw(tickets communication data customers addons)) {
        push @ScopeGroups,{Key=>$GroupKey,Label=>$Self->_T('APIScopeGroup'.ucfirst($GroupKey),$Language),Items=>$Group{$GroupKey}||[]};
    }

    my $Tokens=$Object->TokenList();
    my %ScopeLabel=map{$_->{Key}=>$Self->_T($_->{Label},$Language)}@{$Definitions};
    for my $Token(@{$Tokens}) {
        $Token->{scope_html} = join '', map {
            '<span class="qisutu-api-scope-tag">' . $Self->_E( $ScopeLabel{$_} || $_ ) . '</span>'
        } @{$Token->{scopes} || []};
        $Token->{status_key}=!$Token->{active}?'APITokenStatusInactive':$Token->{expired}?'APITokenStatusExpired':!$Token->{is_active}?'APITokenStatusUserInactive':'APITokenStatusActive';
        $Token->{status_display}=$Self->_T($Token->{status_key},$Language);
        $Token->{status_class}=$Token->{status_key} eq 'APITokenStatusActive' ? 'is-active' : $Token->{status_key} eq 'APITokenStatusInactive' ? 'is-inactive' : 'is-warning';
        $Token->{account_type_display}=$Self->_T(($Token->{account_type}||'')eq'customer'?'APIAccountCustomer':'APIAccountAgent',$Language);
        $Token->{expires_display}=$Token->{expires_at}||$Self->_T('APILifetimeNever',$Language);
        $Token->{last_used_display}=$Token->{last_used_at} || '-';
        my $TokenID = int($Token->{id} || 0);
        my $ActionStep = $Token->{active} ? 'APITokenDeactivate' : 'APITokenActivate';
        my $ActionLabel = $Token->{active} ? 'APIDeactivateToken' : 'APIActivateToken';
        my $ActionClass = $Token->{active} ? 'qisutu-button-danger' : 'qisutu-button-secondary';
        $Token->{action_html} = '<div class="qisutu-api-token-actions">'
            . '<a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="index.pl?Page=AdminAPI&amp;Step=APITokenEdit&amp;TokenID=' . $TokenID . '">'
            . $Self->_E($Self->_T('AdminEdit',$Language)) . '</a>'
            . '<form method="post" action="index.pl" class="qisutu-inline-form"' . ($Token->{active} ? ' data-api-deactivate' : '') . '>'
            . '<input type="hidden" name="Page" value="AdminAPI"><input type="hidden" name="Step" value="' . $ActionStep . '">'
            . '<input type="hidden" name="TokenID" value="' . $TokenID . '">'
            . '<button class="qisutu-button ' . $ActionClass . ' qisutu-button-small" type="submit">' . $Self->_E($Self->_T($ActionLabel,$Language)) . '</button></form></div>';
    }
    my $Logs=$Object->RequestLogList(Limit=>100);
    for my $Log(@{$Logs}){$Log->{success_class}=($Log->{status_code}||500)<400?'is-success':'is-error';}

    my $WebPath=$Self->{Config}->{System}->{WebPath}||'/qisutu';
    my $BaseURL=QisutuSystemSetting->new(Config=>$Self->{Config},DB=>$Self->{DB})->BaseURL()||'';
    $BaseURL=~s{/+\z}{};
    my $APIURL=$BaseURL;
    $APIURL.=$WebPath if!$APIURL||$APIURL!~m{\Q$WebPath\E\z};
    $APIURL.='/api.pl/v1';
    my $SelectedUser='';
    if ($Form->{UserAccountID}) {
        my $Row=$Object->UserGet(UserAccountID=>$Form->{UserAccountID});
        $Row = $EditToken if !$Row && $EditToken && $Form->{UserAccountID} eq $EditToken->{user_account_id};
        $SelectedUser=$Row->{user_name}.' — '.$Row->{login} if $Row;
    }
    my %NoticeKeys = ( deactivated => 'APITokenDeactivated', activated => 'APITokenActivated', updated => 'APITokenUpdated' );
    my $NoticeKey = $NoticeKeys{$Request->{Notice} || ''} || '';
    my $Lifetime = $Form->{Lifetime} || ( $Editing ? 'keep' : '90d' );
    return {
        Template=>'AdminAPI.tt',
        Data=>{
            PageTitle=>'Translate:AdminAPITitle',ProgramTitle=>'Translate:AdminAPITitle',ProgramDescription=>'Translate:AdminAPIDescription',
            ErrorMessage=>$Self->_ErrorTranslate($Error,$Language),ErrorClass=>$Error?'':'qisutu-hidden',
            TokenCreated=>$Created?1:0,PlainToken=>$Created?$Created->{PlainToken}:'',CreatedPrefix=>$Created?$Created->{Prefix}:'',
            TokenList=>$Tokens,TokenCount=>scalar@{$Tokens},HasTokens=>@{$Tokens}?1:0,
            ScopeGroupsHTML=>$Self->_ScopeGroupsHTML(Groups=>\@ScopeGroups,Request=>$Form,HasError=>$HasFormValues?1:0),RequestLogs=>$Logs,HasRequestLogs=>@{$Logs}?1:0,
            APIBaseURL=>$APIURL,OpenAPIURL=>$APIURL.'/openapi.json',
            EditingToken => $Editing ? 1 : 0,
            FormTitle => $Self->_T($Editing ? 'APITokenEditTitle' : 'APITokenCreateTitle', $Language),
            FormDescription => $Self->_T($Editing ? 'APITokenEditDescription' : 'APITokenCreateDescription', $Language),
            FormStep => $Editing ? 'APITokenUpdate' : 'APITokenCreate',
            FormSubmitLabel => $Self->_T($Editing ? 'APISaveToken' : 'APICreateToken', $Language),
            FormTokenID => $Editing ? $EditToken->{id} : '',
            FormCurrentExpiry => $Editing ? ($EditToken->{expires_at} || $Self->_T('APILifetimeNever', $Language)) : '',
            FormLabel=>$Form->{Label}||'', FormUserAccountID=>$Form->{UserAccountID}||'', FormSelectedUser=>$SelectedUser,
            FormLifetimeKeepSelected=>$Lifetime eq 'keep'?'selected':'',
            FormLifetime30Selected=>$Lifetime eq '30d'?'selected':'',
            FormLifetime90Selected=>$Lifetime eq '90d'?'selected':'',
            FormLifetime365Selected=>$Lifetime eq '365d'?'selected':'',
            FormLifetimeNeverSelected=>$Lifetime eq 'never'?'selected':'',
            FormAllowedIPs=>$Form->{AllowedIPs}||'', FormRateLimit=>$Form->{RateLimitPerMinute}||120,
            NoticeMessage=>$NoticeKey?$Self->_T($NoticeKey,$Language):'',
            NoticeClass=>$NoticeKey?'':'qisutu-hidden',
        },
    };
}

sub _T {
    my($Self,$Key,$Language)=@_;return$Key if!$Self->{Output};my$Text=$Self->{Output}->Translate(Key=>$Key,Language=>$Language);return defined$Text&&$Text ne''?$Text:$Key;
}
sub _ErrorTranslate {
    my($Self,$Error,$Language)=@_;return''if!$Error;my%Map=(
        'API token was not found'=>'APITokenNotFound', 'API token lifetime is invalid'=>'APITokenLifetimeInvalid',
        'API token has expired; update its validity first'=>'APITokenActivateExpired',
        'API token could not be updated'=>'APITokenUpdateFailed', 'API token could not be activated'=>'APITokenActivateFailed',
        'API token user and label are required'=>'APITokenUserLabelRequired','API token label is too long'=>'APITokenLabelTooLong',
        'At least one API permission is required'=>'APITokenScopeRequired','API user was not found or is inactive'=>'APITokenUserInvalid',
        'API allowed IP address list is invalid'=>'APITokenAllowedIPInvalid','Secure API token generation failed'=>'APITokenGenerationFailed',
    );return$Self->_T($Map{$Error},$Language)if$Map{$Error};return$Error;
}

sub _ScopeGroupsHTML {
    my($Self,%Param)=@_;my$Request=$Param{Request}||{};my@Selected=ref$Request->{Scope}eq'ARRAY'?@{$Request->{Scope}}:defined$Request->{Scope}?($Request->{Scope}):();
    my%Selected=map{$_=>1}@Selected;$Selected{'tickets.read'}=1 if!$Param{HasError};my$HTML='';
    for my$Group(@{$Param{Groups}||[]}){$HTML.='<section><h3>'.$Self->_E($Group->{Label}).'</h3>';for my$Scope(@{$Group->{Items}||[]}){$HTML.='<label class="qisutu-form-checkbox"><input id="'.$Self->_E($Scope->{InputID}).'" type="checkbox" name="Scope" value="'.$Self->_E($Scope->{Key}).'"'.($Selected{$Scope->{Key}}?' checked':'').'><span>'.$Self->_E($Scope->{LabelText}).'</span></label>';}$HTML.='</section>';}
    return$HTML;
}
sub _E { my($Self,$V)=@_;$V=''if!defined$V;$V=~s{&}{&amp;}g;$V=~s{<}{&lt;}g;$V=~s{>}{&gt;}g;$V=~s{"}{&quot;}g;$V=~s{'}{&#39;}g;return$V; }

1;
