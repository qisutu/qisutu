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

Qisutu to nowy system obsługi zgłoszeń open source oparty na Perl/CGI, MariaDB
lub MySQL, Template Toolkit oraz interfejsie przeglądarkowym.

Strona projektu: https://qisutu.de

## Status wydania

Qisutu jest samodzielnie instalowanym systemem z portalami agentów i klientów,
obsługą poczty, logowaniem katalogowym, automatyzacją, bazą wiedzy, CMDB,
raportami i REST API. Qisutu 1.0.3 jest stabilnym wydaniem do pracy produkcyjnej
i nie znajduje się już w fazie rozwoju. Interfejsy oraz struktury bazy są nadal
rozwijane w ramach regularnego utrzymania; zmiany dostarcza zintegrowany
aktualizator i stale utrzymywane migracje danych.

## Języki

Qisutu 1.0.3 zawiera jedenaście pełnych języków interfejsu: niemiecki (`de`),
angielski (`en`), francuski (`fr`), włoski (`it`), portugalski brazylijski
(`pt-BR`), portugalski europejski (`pt-PT`), hiszpański (`es`), niderlandzki
(`nl`), polski (`pl`), czeski (`cs`) i turecki (`tr`).

## Instalacja

Jako root w `/opt` wykonaj:

    wget https://ftp.qisutu.de/qisutu-1.0.3.tar.gz
    tar xzf qisutu-1.0.3.tar.gz
    mv qisutu-1.0.3 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

Na początku `install.sh` pyta o jeden z jedenastu języków. Wybór jest zapisywany
w konfiguracji instancji, instalator WWW otwiera się w tym języku i ustawia go
jako domyślny. Nazwa katalogu bezpośrednio określa wartości techniczne:
`/opt/qisutu` tworzy instancję `qisutu` bez dodatkowego prefiksu `qisutu-`.

Następnie otwórz wyświetlony adres, na przykład:

    http://SERVER/qisutu/install.pl

Przejdź sześć kroków instalatora. `install.sh` wykrywa system, instaluje pakiety
i moduły Perl oraz konfiguruje dla każdej instancji osobną integrację Apache,
usługi systemd, ścieżkę WWW i bazę. Produkcja i test mogą działać równolegle.

Instalator tworzy bazę, użytkownika, strukturę z `install/sql/schema.sql`, dane z
`install/sql/insert.sql` i pierwszego administratora. Losowe hasło bazy zapisuje
bezpośrednio w `core/config/QisutuConfig.pm`. Szczegóły i przykład dwóch instancji
znajdują się w `INSTALL.md`.

## Aktualizacja

Jako root w `/opt` wykonaj:

    wget https://ftp.qisutu.de/qisutu-1.0.3.tar.gz
    tar xzf qisutu-1.0.3.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.3

    cd /opt/qisutu-1.0.3
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.3
    rm qisutu-1.0.3.tar.gz

Aktualizator rozpoznaje instancję przez `var/install/instance.conf`, zatrzymuje
tylko jej daemon i blokuje tylko jej pobieranie poczty. Kopiuje pliki zarządzane
bez nadpisywania konfiguracji instancji, Apache i systemd. Opcjonalnie tworzy
zrzut bazy. Tabele i trwałe migracje są sprawdzane i uzupełniane. Zobacz
`INSTALL.md`.

## Struktura katalogów

- `bin/` – wejścia CGI, procesy w tle i programy wiersza poleceń
- `core/` – konfiguracja, moduły, szablony, języki i klasy systemowe
- `install/sql/schema.sql` – kompletna struktura tabel
- `install/sql/insert.sql` – dane początkowe nowej instalacji
- `scriptfiles/` – szablony Apache i systemd
- `var/static/` – zasoby frontendowe i komponenty zewnętrzne

## Moduły dodatkowe

Od wersji 0.0.78 Qisutu ma menedżer zwykłych ZIP-ów z czytelnym plikiem
`qisutu-module.json`. Administratorzy instalują, aktualizują i usuwają moduły w
panelu, a daemon wykonuje operacje na plikach niezależnie od procesu WWW. Moduł
może dostarczać własne odnośniki i ekrany oraz szyfrować sekrety.

Rdzeń Qisutu udostępnia też wewnętrzne API 1.0: usługi wielokrotnego użytku,
trwale dostarczane zdarzenia rdzenia, izolowane trasy REST z własnymi prawami i
kontrolowane punkty UI. Starsze moduły zachowują zgodność. Moduł może deklarować
wersję API i funkcje; w razie potrzeby Qisutu żąda zwykłej aktualizacji rdzenia,
bez wariantów dla klientów. Moduły są niezależnymi projektami z pełnym kodem.
Instalacja i bezpieczeństwo: `MODULES.md`.

## Ewidencja czasu

Agenci mogą rejestrować godziny i minuty przy zgłoszeniach, artykułach i
zmianach. Każdy wpis rozróżnia czas rozliczalny i nierozliczalny oraz może mieć
typ aktywności. Możliwe są wpisy ręczne. Dane są audytowalne: uprawniona korekta
anuluje oryginał z obowiązkowym powodem i tworzy powiązany zamiennik. Początkowo
korygować może tylko grupa admin. Ekrany i artykuły klientów nie zawierają czasu.

## Pobieranie poczty i OAuth2

Administracja grupuje konta przychodzące w `Pobieranie poczty` i oferuje:

- standardowy IMAP z użytkownikiem i hasłem
- Microsoft 365 z OAuth2/XOAUTH2
- Google Workspace lub Gmail z OAuth2/XOAUTH2

Microsoft i Google przekierowują do dostawcy po zapisie. Qisutu sprawdza powrót
OAuth2 jednorazową wartością stanu, zapisuje tokeny i testuje IMAP. Konto jest
aktywowane dopiero po teście; wygasłe tokeny odnawiają się automatycznie. Daemon
instancji pobiera pocztę co pięć minut bez dodatkowego crona dla
`qisutu-mail-fetch.pl`.

Nieaktywne konto jest testowane przed aktywacją i może być usunięte dopiero po
dezaktywacji. Dane i tokeny znikają, logi Postmaster pozostają. `Ustawienia SMTP`
oferują standard SMTP, Microsoft 365 i Google. Microsoft i Google używają
`AUTH XOAUTH2` z zakresami `https://outlook.office.com/SMTP.Send` i
`https://mail.google.com/`. Tokeny są szyfrowane i odnawiane; aktywacja wymaga
autoryzacji oraz rzeczywistego testu SMTP.

W `Administracja > Ustawienia systemowe` należy ustawić dostępny z zewnątrz URL
HTTPS. Pokazany URI trzeba dokładnie zarejestrować u dostawcy. Zobacz `INSTALL.md`.

## Dziennik komunikacji

Dziennik zapisuje operacje IMAP, SMTP i OAuth2 z czasem, wynikiem, migawką konta
i krokami. Dostępne są wskaźniki i filtry. Przechowywane są tylko metadane —
nadawca, odbiorca, temat, Message-ID i ewentualne zgłoszenie — bez treści i
załączników. Hasła, sekrety i tokeny są wcześniej usuwane. Domyślna retencja to
90 dni; 0 wyłącza czyszczenie.

## Automatyczne odpowiedzi klientom

Oddzielne szablony HTML obsługują zgłoszenie klienta, odpowiedź klienta,
odpowiedź na zamknięte zgłoszenie i e-mail odrzucony filtrem Postmaster. Każdy
ma temat, tekst CKEditor, aktywację i znaczniki. Początkowo są wyłączone. Odpowiedź
odrzucająca wymaga akcji `Odrzuć e-mail i uruchom automatyczną odpowiedź`;
ignorowanie nie odpowiada. Działania agentów nie wysyłają dodatkowej wiadomości.

## LDAP i Active Directory

Konfigurowane są dwa osobne profile: agentów oraz kontaktów i firm klientów.
Każdy ma własne połączenie, wyszukiwanie, mapowanie, testy i aktywację. Qisutu
automatycznie wybiera profil portalu.

Login, imię, nazwisko i e-mail są obowiązkowe. Profil agentów może importować
dodatkowe pola i przypisywać grupę domyślną. Profil klientów wymaga też unikalnego
numeru klienta Qisutu i nazwy firmy. Pola obowiązkowe wymagają mapowania i wartości.

Agenci są dopasowywani po kanonicznym loginie. Firma klienta jest znajdowana lub
tworzona po numerze, a kontakt przypisywany dokładnie do niej. Użyty e-mail
powoduje błąd, nigdy automatyczne scalanie. Dozwolone są tylko LDAPS i StartTLS;
weryfikacja certyfikatu jest aktywna, a hasło wyszukiwania szyfrowane. Zmiana
wyłącza profil do czasu testów. Gdy katalog nie znajdzie użytkownika, istniejące
konto lokalne może się zalogować; gdy znajdzie, decyduje hasło katalogowe.

## Formularze klientów i WWW

Administratorzy tworzą formularze portalu i publiczne formularze WWW ze stałą
kolejką, tekstami wielojęzycznymi i własnymi polami. Formularz może być dla
wszystkich lub wybranych klientów. Bez formularza indywidualnego pozostaje
standardowe tworzenie zgłoszenia.

Formularze publiczne otrzymują link i iframe. Chronią je Content Security Policy,
honeypot, kontrola czasu i limity. Imię i e-mail są obowiązkowe; aktywne konto nie
powstaje. Wszystkie wartości są niezmienną migawką obok pól dynamicznych. Agenci
widzą `Informacje formularza`, klienci `Dane formularza`. Późniejsze zmiany nie
modyfikują istniejących wysłań.

## CMDB

CMDB nie narzuca typów CI. Administratorzy definiują typy, grupy pól, wymagania,
wybory, unikalność, stany i relacje oraz zarządzają inwentarzem, przypisaniami,
archiwizacją i importem. Agenci nie zmieniają danych głównych; wyszukują i łączą
CI ze zgłoszeniem i otwierają je tylko do odczytu. Scalanie przenosi wszystkie
powiązania.

Każda zmiana trafia do niezmiennej historii. Profile CSV mapują kolumny, wartości
i reguły na pola Qisutu; zewnętrzne ID zapewnia dopasowanie według źródła. Profil
można uruchomić ręcznie lub przez cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Portal pokazuje tylko aktywne CI i pola jawnie udostępnione zalogowanemu klientowi.

## Import CSV danych głównych

Osobne importy dotyczą klientów, kontaktów i agentów. Aktywne pola dynamiczne są
dodawane jako `dynamic.<nazwapola>`; aktualny szablon należy pobrać z systemu
docelowego. Każdy plik jest sprawdzany w całości. Podgląd dzieli wiersze na nowe,
zmienione, niezmienione i błędne; jeden błąd blokuje całość. Po potwierdzeniu
wszystko jest zapisywane w jednej transakcji. Numer klienta lub login jest kluczem.
Brakujące rekordy nie są usuwane ani wyłączane.

Hasła, grupy i prawa nie należą do CSV. Prawa istniejących agentów nie zmieniają
się, a nowi nie dostają praw. Po imporcie można zaprosić nowe aktywne kontakty i
agentów do ustawienia pierwszego hasła.

## Baza wiedzy i FAQ

Wszyscy agenci mogą tworzyć wielojęzyczne kategorie i FAQ. Artykuł ma unikalny
numer, język i widoczność `Tylko agenci` albo `Agenci i klienci`. Prawa grup,
kolejki, udostępnienia klientom i dodatkowy status publikacji nie należą do tej
logiki. Każdy zapis tworzy niezmienną rewizję.

Artykuły `Agenci i klienci` są w portalu. Obok CKEditor agenci mogą wyszukiwać i
wstawiać rozwiązanie, tytuł z rozwiązaniem lub link. W e-mailach i notatkach dla
klienta blokowane są tylko artykuły `Tylko agenci`. Użycie rewizji jest zapisywane.

## Motywy agentów

Agenci wybierają motyw w `Ustawieniach osobistych`; jest zwykłą preferencją.
Motyw `Boże Narodzenie` dodaje dyskretne statyczne dekoracje tylko do stron
agentów. Inne motywy używają `core/config/themes`, CSS w
`var/static/css/themes` i ewentualnych obrazów w `var/static/img/themes`.
Centralny rejestr waliduje je przed załadowaniem.

## Bezpieczeństwo

Zmiany WWW używają tokenów CSRF związanych z sesją; REST API oddzielnych Bearer
tokenów. Nagłówki zapobiegają MIME sniffing i niechcianemu osadzaniu. Ciasteczka
są `HttpOnly`, `SameSite=Lax` i przy HTTPS `Secure`.

Hasła IMAP/SMTP, sekrety i tokeny OAuth oraz sekrety 2FA są szyfrowane kluczem
`var/secure/security.key`, który musi być w chronionej kopii. Agenci i kontakty
mogą włączyć TOTP lokalnym kodem QR i otrzymują kody odzyskiwania. Administratorzy
mogą osobno wymuszać 2FA i resetować utraconą konfigurację.

## Konfiguracja bazy danych

Połączenie jest w `core/config/QisutuConfig.pm`. Instalator zapisuje host, port,
bazę, użytkownika i losowe hasło. Restrykcyjne prawa chronią plik.

## Licencja

Qisutu jest objęty GNU Affero General Public License w wersji 3 lub późniejszej
(`AGPL-3.0-or-later`). Pełne warunki są w `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Oprogramowanie zewnętrzne

Pliki zewnętrzne zachowują oryginalne informacje. Podsumowanie znajduje się w
`THIRD_PARTY_NOTICES.md`.
