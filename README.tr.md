<!--
Qisutu - Open Source Ticket System
Copyright (C) 2026 Franziska Steps
Qisutu - Kim-KI, https://qisutu.de

This file is part of Qisutu.

Qisutu is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Qisutu is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Qisutu. If not, see <https://www.gnu.org/licenses/>.

SPDX-FileCopyrightText: 2026 Franziska Steps
SPDX-License-Identifier: AGPL-3.0-or-later
-->

[Deutsch](README.md) | [English](README.en.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português (Brasil)](README.pt-BR.md) | [Português (Portugal)](README.pt-PT.md) | [Español](README.es.md) | [Nederlands](README.nl.md) | [Polski](README.pl.md) | [Čeština](README.cs.md) | [Türkçe](README.tr.md)

# Qisutu

Qisutu; Perl/CGI, MariaDB veya MySQL, Template Toolkit ve tarayıcı tabanlı bir
kullanıcı arayüzü üzerine kurulu yeni bir açık kaynak talep sistemidir.

Proje sitesi: https://qisutu.de

## Sürüm durumu

Qisutu; ajan ve müşteri portalları, e-posta işleme, dizin girişi, otomasyon,
bilgi bankası, CMDB, raporlar ve REST API içeren bağımsız bir sistemdir. Qisutu
1.0.1 üretim için onaylanmış kararlı sürümdür ve geliştirme aşamasında değildir.
Arayüzler ve veritabanı yapıları düzenli bakımda gelişmeye devam eder; gerekli
değişiklikler entegre güncelleyici ve kalıcı veri geçişleriyle sağlanır.

## Diller

Qisutu 1.0.1 on bir tam arayüz dili içerir: Almanca (`de`), İngilizce (`en`),
Fransızca (`fr`), İtalyanca (`it`), Brezilya Portekizcesi (`pt-BR`), Avrupa
Portekizcesi (`pt-PT`), İspanyolca (`es`), Felemenkçe (`nl`), Lehçe (`pl`),
Çekçe (`cs`) ve Türkçe (`tr`).

## Kurulum

`/opt` altında root olarak çalıştırın:

    wget https://ftp.qisutu.de/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz
    mv qisutu-1.0.1 qisutu
    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu
    chown qisutu:www-data -R qisutu
    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

`install.sh` önce on bir dilden birini sorar. Seçim örnek yapılandırmasına
kaydedilir, web yükleyici o dilde açılır ve varsayılan olarak kullanır. Dizin adı
teknik değerleri doğrudan belirler: `/opt/qisutu`, ek `qisutu-` öneki olmadan
`qisutu` örneğini oluşturur. Ardından örneğin şu adresi açın:

    http://SERVER/qisutu/install.pl

Altı adımı tamamlayın. Betik sistemi algılar, paketleri ve Perl modüllerini kurar
ve her örnek için ayrı Apache, systemd hizmetleri, web yolu ve veritabanı
ayarlar. Yükleyici `install/sql/schema.sql` yapısını,
`install/sql/insert.sql` verilerini ve ilk yöneticiyi oluşturur; rastgele
veritabanı parolasını `core/config/QisutuConfig.pm` içine yazar. Ayrıntılar
`INSTALL.md` dosyasındadır.

## Güncelleme

`/opt` altında root olarak çalıştırın:

    wget https://ftp.qisutu.de/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz
    chown qisutu:www-data -R /opt/qisutu-1.0.1
    cd /opt/qisutu-1.0.1
    chmod +x update.sh
    ./update.sh
    cd /opt
    rm -R qisutu-1.0.1
    rm qisutu-1.0.1.tar.gz

Güncelleyici örneği `var/install/instance.conf` ile tanır, yalnızca onun daemon
ve posta alımını durdurur, örnek/Apache/systemd yapılandırmasını ezmez. İstenirse
dump alır; tabloları ve kalıcı geçişleri denetler. Bkz. `INSTALL.md`.

## Dizin yapısı

- `bin/` – CGI girişleri, arka plan işlemleri ve komut satırı programları
- `core/` – yapılandırma, modüller, şablonlar, diller ve sistem sınıfları
- `install/sql/schema.sql` ve `install/sql/insert.sql` – yapı ve başlangıç verileri
- `scriptfiles/` – Apache ve systemd şablonları
- `var/static/` – frontend ve üçüncü taraf dosyaları

## Ek modüller

0.0.78’den beri Qisutu, okunabilir `qisutu-module.json` içeren normal ZIP
modüllerini yönetir. Dosya işlemlerini webden ayrı daemon yürütür; modüller kendi
ekranlarını ve şifreli sırlarını sunabilir. API 1.0; yeniden kullanılabilir
hizmetler, kalıcı çekirdek olayları, izole REST yolları ve kontrollü UI noktaları
sağlar. Eski modüller uyumludur; gereken çekirdek sürümü müşteriye özel varyant
olmadan normal güncellemeyle sağlanır. Bkz. `MODULES.md`.

## Zaman kaydı

Ajanlar saat ve dakika kaydeder, faturalandırılabilir zamanı ve etkinlik türünü
belirtir. Kayıtlar denetlenebilirdir: yetkili düzeltme, zorunlu gerekçeyle aslı
iptal eder ve bağlı bir yenisini oluşturur. Başta yalnızca admin düzeltebilir.
Müşteri ekranlarında zaman kaydı yoktur.

## E-posta ve OAuth2

`E-posta alımı`; standart IMAP, Microsoft 365 OAuth2/XOAUTH2 ve Google
Workspace/Gmail OAuth2/XOAUTH2 sunar. OAuth2 dönüşü tek kullanımlık durumla
doğrulanır, tokenlar şifrelenip yenilenir ve hesap gerçek testten sonra açılır.
Örnek daemonu postayı beş dakikada bir, `qisutu-mail-fetch.pl` için ek cron
olmadan alır. Etkin olmayan hesap yeniden açılmadan test edilir ve ancak
kapatıldıktan sonra silinir; günlükler korunur.

SMTP aynı türleri, `AUTH XOAUTH2` ve `https://outlook.office.com/SMTP.Send` ile
`https://mail.google.com/` kapsamlarını destekler. Dışarıdan erişilen HTTPS temel
URL ve tam yönlendirme URI’si sistem ayarlarında tanımlanır.

## İletişim günlüğü

IMAP, SMTP ve OAuth2 işlemleri zaman, sonuç ve adımlarla kaydedilir. Yalnızca
teknik meta veriler tutulur; gövde ve ekler kopyalanmaz, parola ve tokenlar
çıkarılır. Varsayılan saklama 90 gündür; 0 temizlemeyi kapatır.

## Otomatik müşteri yanıtları

Yeni müşteri talebi, müşteri yanıtı, kapalı talebe yanıt ve filtreyle reddedilen
e-posta için ayrı HTML şablonları vardır. Başta kapalıdır. Red yanıtı açıkça
tetiklenmelidir; ajan işlemleri ek müşteri e-postası göndermez.

## LDAP ve Active Directory

Ajanlar ile müşteri bağlantıları için iki ayrı profil vardır. Her birinin kendi
bağlantısı, araması, eşlemesi ve testi bulunur. Giriş, ad, soyad ve e-posta
zorunludur; müşteri ayrıca benzersiz numara ve şirket adı ister. Hesaplar kanonik
girişle eşleştirilir; e-posta çakışması birleşme değil hata üretir. Yalnızca
sertifika doğrulamalı LDAPS ve StartTLS kullanılır. Değişiklik, testler geçene
kadar profili kapatır; dizinde bulunmayan mevcut yerel hesap yine giriş yapabilir.

## Müşteri ve web formları

Formlarda sabit hedef kuyruk, çok dilli metinler ve özel alanlar bulunur. Tüm ya
da seçili müşterilere açılabilir; form yoksa standart oluşturma kalır. Herkese
açık formlar bağlantı ve iframe alır; CSP, honeypot, zaman kontrolü ve limitlerle
korunur, etkin hesap oluşturmaz. Değerler değişmez gönderim anlık görüntüsü
olarak saklanır ve sonraki değişiklikler eski gönderimleri etkilemez.

## CMDB

Yöneticiler CI türlerini, alanları, durumları ve ilişkileri tanımlar; envanter,
atama ve içe aktarmayı yönetir. Ajanlar CI’ları yalnızca arar, bağlar ve okur;
birleştirme tüm bağları taşır. Geçmiş değişmezdir ve CSV profilleri dış kimlikle
kaynak eşleştirir:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Portal yalnızca açıkça izin verilen etkin CI ve alanları gösterir.

## Ana veri CSV içe aktarma

Müşteri, bağlantı ve ajan için ayrı içe aktarmalar vardır. Dinamik alanlar
`dynamic.<alanadı>` olarak eklenir. Dosyanın tamamı önce doğrulanır; tek hata
işlemi engeller, onaydan sonra her şey tek işlemde yazılır. Eksik kayıtlar
silinmez. CSV parola, grup ve yetki içermez; yeni hesaplara davet gönderilebilir.

## Bilgi bankası ve SSS

SSS makalesinin benzersiz numarası, dili ve `Yalnızca ajanlar` veya
`Ajanlar ve müşteriler` görünürlüğü vardır. Her kayıt değişmez revizyon oluşturur.
Müşteriye açık makaleler portalda görünür ve ajanlar CKEditor yanında çözüm ya da
bağlantı ekleyebilir. Dahili makaleler müşteri içeriklerinde engellenir; revizyon
kullanımı kaydedilir.

## Ajan temaları

Tema normal kişisel tercihtir. `Noel` teması yalnızca ajan sayfalarını süsler.
Diğer temalar `core/config/themes`, `var/static/css/themes` ve gerekirse
`var/static/img/themes` kullanır; merkezi kayıt yüklemeden önce doğrular.

## Güvenlik

Web değişikliklerini oturuma bağlı CSRF, REST API’yi ayrı Bearer tokenlar korur.
Çerezler `HttpOnly`, `SameSite=Lax` ve HTTPS’de `Secure` olur. IMAP/SMTP
parolaları, OAuth tokenları ve 2FA sırları `var/secure/security.key` ile
şifrelenir; anahtar korumalı yedekte bulunmalıdır. Ajanlar ve bağlantılar yerel
QR ile TOTP açıp kurtarma kodu alabilir; yöneticiler 2FA’yı zorlayıp sıfırlayabilir.

## Veritabanı yapılandırması

Bağlantı `core/config/QisutuConfig.pm` içindedir. Yükleyici sunucu, port,
veritabanı, kullanıcı ve rastgele parolayı yazar; kısıtlı izinler dosyayı korur.

## Lisans

Qisutu, GNU Affero General Public License sürüm 3 veya sonrası ile lisanslıdır
(`AGPL-3.0-or-later`). Tam şartlar `LICENSE` içindedir.

Copyright (C) 2026 Franziska Steps.

## Üçüncü taraf yazılım

Üçüncü taraf dosyaları özgün bildirimlerini korur; özet
`THIRD_PARTY_NOTICES.md` içindedir.
