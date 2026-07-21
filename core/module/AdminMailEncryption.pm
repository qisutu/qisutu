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

package AdminMailEncryption;

use strict;
use warnings;
use utf8;

use QisutuMailCrypto;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config => $Param{Config},
        DB     => $Param{DB},
        Output => $Param{Output},
    };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $User = $Param{User} || {};
    my $UserID = $User->{user_account_id} || 1;
    my $Object = QisutuMailCrypto->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step = $Self->_Scalar( $Request->{Step} );
    my ( $Error, $Notice ) = ( '', '' );

    if ( !$Object->OpenSSLAvailable() ) {
        $Error = 'Translate:AdminMailEncryptionOpenSSLMissing';
    }
    elsif ( $Step eq 'PolicySave' ) {
        my $Saved = $Object->PolicySave(
            SystemEmailID   => $Self->_Scalar( $Request->{SystemEmailID} ),
            SignOutgoing    => $Request->{SignOutgoing} ? 1 : 0,
            EncryptOutgoing => $Self->_Scalar( $Request->{EncryptOutgoing} ),
            DecryptIncoming => $Request->{DecryptIncoming} ? 1 : 0,
            VerifyIncoming  => $Request->{VerifyIncoming} ? 1 : 0,
            Active          => $Request->{Active} ? 1 : 0,
            ChangedByUserID => $UserID,
        );
        $Saved ? ( $Notice = 'Translate:AdminMailEncryptionPolicySaved' ) : ( $Error = $Object->Error() );
    }
    elsif ( $Step eq 'IdentityImport' ) {
        my $PKCS12 = $Self->_Upload( Request => $Request, Name => 'IdentityPKCS12' );
        my $Certificate = $Self->_Upload( Request => $Request, Name => 'IdentityCertificate' );
        my $PrivateKey = $Self->_Upload( Request => $Request, Name => 'IdentityPrivateKey' );
        if ( !$Self->_UploadsWithinLimit( grep {$_} $PKCS12, $Certificate, $PrivateKey ) ) {
            $Error = 'Translate:AdminMailEncryptionFileTooLarge';
        }
        else {
            my %Import = (
                SystemEmailID   => $Self->_Scalar( $Request->{SystemEmailID} ),
                DisplayName     => $Self->_Scalar( $Request->{DisplayName} ),
                Passphrase      => $Self->_Scalar( $Request->{Passphrase} ),
                ChangedByUserID => $UserID,
            );
            my $KeyID = $PKCS12
                ? $Object->IdentityImportPKCS12( %Import, Content => $PKCS12->{Content} || '' )
                : $Object->IdentityImportPEM(
                    %Import,
                    Certificate => $Certificate ? ( $Certificate->{Content} || '' ) : '',
                    PrivateKey  => $PrivateKey ? ( $PrivateKey->{Content} || '' ) : '',
                );
            $KeyID ? ( $Notice = 'Translate:AdminMailEncryptionIdentityImported' ) : ( $Error = $Object->Error() );
        }
    }
    elsif ( $Step eq 'RecipientImport' ) {
        my $Certificate = $Self->_Upload( Request => $Request, Name => 'RecipientCertificate' );
        if ( !$Certificate || !$Self->_UploadsWithinLimit($Certificate) ) {
            $Error = $Certificate
                ? 'Translate:AdminMailEncryptionFileTooLarge'
                : 'Translate:AdminMailEncryptionCertificateRequired';
        }
        else {
            my $KeyID = $Object->RecipientImport(
                Email           => $Self->_Scalar( $Request->{Email} ),
                DisplayName     => $Self->_Scalar( $Request->{DisplayName} ),
                Certificate     => $Certificate->{Content} || '',
                ChangedByUserID => $UserID,
            );
            $KeyID ? ( $Notice = 'Translate:AdminMailEncryptionRecipientImported' ) : ( $Error = $Object->Error() );
        }
    }
    elsif ( $Step eq 'KeyActivate' || $Step eq 'KeyDeactivate' ) {
        my $Saved = $Object->KeyActiveSet(
            KeyID           => $Self->_Scalar( $Request->{KeyID} ),
            Active          => $Step eq 'KeyActivate' ? 1 : 0,
            ChangedByUserID => $UserID,
        );
        $Saved ? ( $Notice = 'Translate:AdminMailEncryptionKeyUpdated' ) : ( $Error = $Object->Error() );
    }
    elsif ( $Step eq 'KeyDelete' ) {
        my $Deleted = $Object->KeyDelete( KeyID => $Self->_Scalar( $Request->{KeyID} ) );
        $Deleted ? ( $Notice = 'Translate:AdminMailEncryptionKeyDeleted' ) : ( $Error = $Object->Error() );
    }

    my $SystemEmails = $Object->SystemEmailList();
    my $Keys = $Object->KeyList();
    my $Policies = $Object->PolicyList();

    for my $Key ( @{$Keys} ) {
        $Key->{role_label} = $Key->{key_role} eq 'identity'
            ? 'Translate:AdminMailEncryptionIdentity'
            : 'Translate:AdminMailEncryptionRecipient';
        $Key->{status_label} = $Key->{active}
            ? 'Translate:AdminActive'
            : 'Translate:AdminInactive';
        $Key->{status_class} = $Key->{active} ? 'qisutu-status-badge-active' : '';
        $Key->{toggle_step} = $Key->{active} ? 'KeyDeactivate' : 'KeyActivate';
        $Key->{toggle_label} = $Key->{active}
            ? 'Translate:AdminDeactivate'
            : 'Translate:AdminActivate';
    }

    for my $Policy ( @{$Policies} ) {
        $Policy->{sign_checked} = $Policy->{sign_outgoing} ? 'checked' : '';
        $Policy->{decrypt_checked} = $Policy->{decrypt_incoming} ? 'checked' : '';
        $Policy->{verify_checked} = $Policy->{verify_incoming} ? 'checked' : '';
        $Policy->{active_checked} = $Policy->{active} ? 'checked' : '';
        $Policy->{encrypt_disabled_selected} = $Policy->{encrypt_outgoing} eq 'disabled' ? 'selected' : '';
        $Policy->{encrypt_available_selected} = $Policy->{encrypt_outgoing} eq 'available' ? 'selected' : '';
        $Policy->{encrypt_required_selected} = $Policy->{encrypt_outgoing} eq 'required' ? 'selected' : '';
    }

    return {
        Template => 'AdminMailEncryption.tt',
        Data     => {
            PageTitle          => 'Translate:AdminMailEncryptionTitle',
            ProgramTitle       => 'Translate:AdminMailEncryptionTitle',
            ProgramDescription => 'Translate:AdminMailEncryptionDescription',
            FormAction         => 'index.pl',
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? 'qisutu-form-error' : 'qisutu-hidden',
            NoticeMessage      => $Notice,
            NoticeClass        => $Notice ? 'qisutu-form-success' : 'qisutu-hidden',
            SystemEmailOptionsHTML => $Self->_SystemEmailOptions($SystemEmails),
            Keys               => $Keys,
            HasKeys            => @{$Keys} ? 1 : 0,
            Policies           => $Policies,
            HasPolicies        => @{$Policies} ? 1 : 0,
        },
    };
}

sub _Upload {
    my ( $Self, %Param ) = @_;
    my $Uploads = $Param{Request}->{__Uploads} || {};
    my $List = $Uploads->{ $Param{Name} };
    return ref $List eq 'ARRAY' ? $List->[0] : undef;
}

sub _UploadsWithinLimit {
    my ( $Self, @Uploads ) = @_;
    for my $Upload (@Uploads) {
        my $Size = $Upload->{ContentSize} || length( $Upload->{Content} || '' );
        return if $Size > 5 * 1024 * 1024;
    }
    return 1;
}

sub _SystemEmailOptions {
    my ( $Self, $Rows ) = @_;
    my $HTML = '<option value="">--</option>';
    for my $Row ( @{$Rows || []} ) {
        $HTML .= '<option value="' . ( $Row->{id} || 0 ) . '">'
            . $Self->_Escape( ( $Row->{name} || '' ) . ' <' . ( $Row->{email} || '' ) . '>' )
            . '</option>';
    }
    return $HTML;
}

sub _Scalar {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value;
    return ref $Value eq 'ARRAY' ? ( $Value->[0] || '' ) : $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

1;
