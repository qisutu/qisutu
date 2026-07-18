# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
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
    if ( $Step eq 'APITokenCreate' ) {
        my @Scopes = ref $Request->{Scope} eq 'ARRAY' ? @{$Request->{Scope}} : defined $Request->{Scope} ? ($Request->{Scope}) : ();
        $Created = $Object->TokenCreate(
            UserAccountID=>$Request->{UserAccountID}, Label=>$Request->{Label}, Scopes=>\@Scopes,
            Lifetime=>$Request->{Lifetime}, AllowedIPs=>$Request->{AllowedIPs},
            RateLimitPerMinute=>$Request->{RateLimitPerMinute}, ChangedByUserID=>$User->{user_account_id},
        );
        $Error = $Object->Error() if !$Created;
    }
    elsif ( $Step eq 'APITokenDeactivate' ) {
        my $OK = $Object->TokenDeactivate( TokenID=>$Request->{TokenID}, ChangedByUserID=>$User->{user_account_id} );
        return { Redirect=>'index.pl?Page=AdminAPI;Notice=deactivated' } if $OK;
        $Error = $Object->Error();
    }

    my $Definitions = $Object->ScopeDefinitions();
    my %Group;
    for my $Def (@{$Definitions}) {
        my %Copy=%{$Def};
        $Copy{LabelText}=$Self->_T($Def->{Label},$Language);
        $Copy{InputID}='api-scope-'.$Def->{Key};$Copy{InputID}=~s{[^A-Za-z0-9_-]}{-}g;
        push @{$Group{$Def->{Group}}},\%Copy;
    }
    my @ScopeGroups;
    for my $GroupKey (qw(tickets communication data customers)) {
        push @ScopeGroups,{Key=>$GroupKey,Label=>$Self->_T('APIScopeGroup'.ucfirst($GroupKey),$Language),Items=>$Group{$GroupKey}||[]};
    }

    my $Tokens=$Object->TokenList();
    my %ScopeLabel=map{$_->{Key}=>$Self->_T($_->{Label},$Language)}@{$Definitions};
    for my $Token(@{$Tokens}) {
        $Token->{scope_display}=join(', ',map{$ScopeLabel{$_}||$_}@{$Token->{scopes}||[]});
        $Token->{status_key}=!$Token->{active}?'APITokenStatusInactive':$Token->{expired}?'APITokenStatusExpired':!$Token->{is_active}?'APITokenStatusUserInactive':'APITokenStatusActive';
        $Token->{status_display}=$Self->_T($Token->{status_key},$Language);
        $Token->{account_type_display}=$Self->_T(($Token->{account_type}||'')eq'customer'?'APIAccountCustomer':'APIAccountAgent',$Language);
        $Token->{expires_display}=$Token->{expires_at}||$Self->_T('APILifetimeNever',$Language);
        $Token->{last_used_display}=$Token->{last_used_at}?$Token->{last_used_at}.($Token->{last_used_ip}?' / '.$Token->{last_used_ip}:''):'-';
        $Token->{action_html}='';
        if($Token->{active}) {
            $Token->{action_html}='<form method="post" action="index.pl" class="qisutu-inline-form" data-api-deactivate>'
                .'<input type="hidden" name="Page" value="AdminAPI"><input type="hidden" name="Step" value="APITokenDeactivate">'
                .'<input type="hidden" name="TokenID" value="'.int($Token->{id}||0).'">'
                .'<button class="qisutu-button qisutu-button-danger qisutu-button-small" type="submit">'.$Self->_E($Self->_T('APIDeactivateToken',$Language)).'</button></form>';
        }
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
    if ($Request->{UserAccountID}) {
        my $Row=$Object->UserGet(UserAccountID=>$Request->{UserAccountID});
        $SelectedUser=$Row->{user_name}.' — '.$Row->{login} if$Row;
    }
    return {
        Template=>'AdminAPI.tt',
        Data=>{
            PageTitle=>'Translate:AdminAPITitle',ProgramTitle=>'Translate:AdminAPITitle',ProgramDescription=>'Translate:AdminAPIDescription',
            ErrorMessage=>$Self->_ErrorTranslate($Error,$Language),ErrorClass=>$Error?'':'qisutu-hidden',
            TokenCreated=>$Created?1:0,PlainToken=>$Created?$Created->{PlainToken}:'',CreatedPrefix=>$Created?$Created->{Prefix}:'',
            TokenList=>$Tokens,TokenCount=>scalar@{$Tokens},HasTokens=>@{$Tokens}?1:0,
            ScopeGroupsHTML=>$Self->_ScopeGroupsHTML(Groups=>\@ScopeGroups,Request=>$Request,HasError=>$Error?1:0),RequestLogs=>$Logs,HasRequestLogs=>@{$Logs}?1:0,
            APIBaseURL=>$APIURL,OpenAPIURL=>$APIURL.'/openapi.json',
            FormLabel=>$Error?($Request->{Label}||''):'',FormUserAccountID=>$Error?($Request->{UserAccountID}||''):'',FormSelectedUser=>$SelectedUser,
            FormLifetime30Selected=>$Error&&($Request->{Lifetime}||'')eq'30d'?'selected':'',
            FormLifetime90Selected=>!$Error||($Request->{Lifetime}||'')eq'90d'?'selected':'',
            FormLifetime365Selected=>$Error&&($Request->{Lifetime}||'')eq'365d'?'selected':'',
            FormLifetimeNeverSelected=>$Error&&($Request->{Lifetime}||'')eq'never'?'selected':'',
            FormAllowedIPs=>$Error?($Request->{AllowedIPs}||''):'',FormRateLimit=>$Error?($Request->{RateLimitPerMinute}||120):120,
            FormRateLimit60Selected=>($Error?($Request->{RateLimitPerMinute}||120):120)==60?'selected':'',
            FormRateLimit120Selected=>($Error?($Request->{RateLimitPerMinute}||120):120)==120?'selected':'',
            FormRateLimit300Selected=>($Error?($Request->{RateLimitPerMinute}||120):120)==300?'selected':'',
            FormRateLimit1000Selected=>($Error?($Request->{RateLimitPerMinute}||120):120)==1000?'selected':'',
            NoticeMessage=>($Request->{Notice}||'')eq'deactivated'?$Self->_T('APITokenDeactivated',$Language):'',
            NoticeClass=>($Request->{Notice}||'')eq'deactivated'?'':'qisutu-hidden',
        },
    };
}

sub _T {
    my($Self,$Key,$Language)=@_;return$Key if!$Self->{Output};my$Text=$Self->{Output}->Translate(Key=>$Key,Language=>$Language);return defined$Text&&$Text ne''?$Text:$Key;
}
sub _ErrorTranslate {
    my($Self,$Error,$Language)=@_;return''if!$Error;my%Map=(
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
