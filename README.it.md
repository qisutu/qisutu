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

Qisutu è un nuovo sistema di ticket open source basato su Perl/CGI, MariaDB o
MySQL, Template Toolkit e un’interfaccia utente nel browser.

Sito del progetto: https://qisutu.de

## Stato della versione

Qisutu è un sistema open source installabile autonomamente con portale agenti e
clienti, elaborazione e-mail, autenticazione tramite directory, automazione,
knowledge base, CMDB, report e API REST. Qisutu 1.0.3 è una versione stabile
approvata per l’uso in produzione e non si trova più in fase di sviluppo.
Interfacce e strutture del database continuano a evolvere con la manutenzione
ordinaria; le modifiche necessarie vengono distribuite tramite l’aggiornamento
integrato e migrazioni dei dati mantenute nel tempo.

## Lingue

Qisutu 1.0.3 include undici lingue complete dell’interfaccia: tedesco (`de`),
inglese (`en`), francese (`fr`), italiano (`it`), portoghese brasiliano
(`pt-BR`), portoghese europeo (`pt-PT`), spagnolo (`es`), olandese (`nl`),
polacco (`pl`), ceco (`cs`) e turco (`tr`).

## Installazione

Eseguire come root in `/opt`:

    wget https://ftp.qisutu.de/qisutu-1.0.3.tar.gz
    tar xzf qisutu-1.0.3.tar.gz
    mv qisutu-1.0.3 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

All’avvio, `install.sh` richiede una delle undici lingue. La scelta viene
salvata nella configurazione dell’istanza, il programma di installazione web si
apre in quella lingua e la adotta come lingua predefinita di Qisutu.

Il nome della directory determina direttamente i valori tecnici dell’istanza:
`/opt/qisutu` crea l’istanza `qisutu` senza aggiungere un prefisso `qisutu-`.
Aprire quindi l’indirizzo mostrato dallo script, ad esempio:

    http://SERVER/qisutu/install.pl

Seguire i sei passaggi del programma di installazione web. `install.sh` rileva
il sistema operativo, installa pacchetti e moduli Perl e configura per ogni
istanza un’integrazione Apache, servizi systemd, percorso web e database
separati. Produzione e test possono così funzionare sullo stesso server.

Il programma di installazione crea database, utente, struttura da
`install/sql/schema.sql`, dati iniziali da `install/sql/insert.sql` e primo
amministratore. La password casuale del database viene scritta direttamente in
`core/config/QisutuConfig.pm`. Istruzioni dettagliate e un esempio con due
istanze sono disponibili in `INSTALL.md`.

## Aggiornamento

Eseguire come root in `/opt`:

    wget https://ftp.qisutu.de/qisutu-1.0.3.tar.gz
    tar xzf qisutu-1.0.3.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.3

    cd /opt/qisutu-1.0.3
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.3
    rm qisutu-1.0.3.tar.gz

L’aggiornamento identifica l’istanza tramite `var/install/instance.conf`, arresta
solo il relativo daemon e blocca solo il recupero e-mail. Copia i file gestiti
senza sovrascrivere file dell’istanza o configurazioni Apache e systemd. Su
richiesta crea anche un dump del database. Struttura delle tabelle e migrazioni
permanenti vengono controllate e integrate. Dettagli in `INSTALL.md`.

## Struttura delle directory

- `bin/` – punti di ingresso CGI, processi in background e programmi da riga di comando
- `core/` – configurazione, moduli, template, lingue e classi di sistema
- `install/sql/schema.sql` – struttura completa delle tabelle
- `install/sql/insert.sql` – dati iniziali per una nuova installazione
- `scriptfiles/` – modelli Apache e systemd
- `var/static/` – risorse frontend e componenti di terze parti

## Moduli aggiuntivi

Dalla versione 0.0.78 Qisutu include un gestore di moduli per normali file ZIP
con un `qisutu-module.json` leggibile. Gli amministratori installano, aggiornano
e disinstallano i moduli nell’area amministrativa; il daemon esegue le operazioni
sui file separatamente dal processo web. Ogni modulo può fornire link e schermate
proprie e salvare segreti cifrati.

Il core di Qisutu fornisce anche l’API interna versionata 1.0: servizi riutilizzabili,
eventi del core consegnati in modo persistente dal daemon, route REST isolate
con permessi propri e punti di inserimento UI controllati. I moduli precedenti
restano compatibili. Un modulo può dichiarare versione API e funzionalità
richieste; se necessario Qisutu richiede un normale aggiornamento del core,
senza varianti specifiche per cliente. I moduli sono progetti indipendenti con
codice sorgente completo. Installazione e sicurezza: `MODULES.md`.

## Contabilizzazione del tempo

Gli agenti possono registrare ore e minuti durante la creazione di ticket,
articoli e modifiche. Ogni registrazione distingue tempo fatturabile e non
fatturabile e può usare un tipo di attività amministrato. Sono possibili anche
registrazioni manuali. I dati sono a prova di revisione: una correzione
autorizzata annulla l’originale con motivazione obbligatoria e crea una voce
sostitutiva collegata. Inizialmente solo il gruppo admin può correggere. Le
schermate e gli articoli dei clienti non contengono dati temporali.

## Recupero e-mail e OAuth2

L’amministrazione riunisce gli account in entrata sotto `Recupero e-mail` e
offre:

- IMAP standard con nome utente e password
- Microsoft 365 con OAuth2/XOAUTH2
- Google Workspace o Gmail con OAuth2/XOAUTH2

Dopo il salvataggio Microsoft e Google reindirizzano al provider. Qisutu verifica
il ritorno OAuth2 con un valore di stato monouso, salva i token e testa IMAP.
L’account viene attivato solo dopo il test; i token scaduti si rinnovano
automaticamente. Il daemon dell’istanza recupera la posta ogni cinque minuti,
senza cron aggiuntivo per `qisutu-mail-fetch.pl`.

Un account inattivo viene testato prima della riattivazione e può essere
eliminato solo dopo la disattivazione. Credenziali e token vengono rimossi, ma i
log Postmaster restano. `Impostazioni SMTP` offre SMTP standard, Microsoft 365 e
Google Workspace/Gmail. Microsoft e Google usano `AUTH XOAUTH2` con gli scope
`https://outlook.office.com/SMTP.Send` e `https://mail.google.com/`. I token sono
cifrati e rinnovati; l’attivazione avviene solo dopo autorizzazione e test SMTP
reale. Sono disponibili riconnessione e disconnessione OAuth.

In `Amministrazione > Impostazioni di sistema` deve essere configurato un URL
base HTTPS raggiungibile dall’esterno. L’URI di reindirizzamento mostrato deve
essere registrato esattamente presso il provider. Vedere `INSTALL.md`.

## Registro delle comunicazioni

Il registro salva recuperi IMAP, invii SMTP e operazioni OAuth2 con ora, durata,
risultato, istantanea dell’account e passaggi. Offre indicatori e filtri. Vengono
conservati solo metadati tecnici — mittente, destinatario, oggetto, Message-ID ed
eventuale ticket — senza duplicare corpo o allegati. Password, segreti e token
vengono rimossi prima del salvataggio. La conservazione predefinita è 90 giorni;
0 disattiva la pulizia automatica.

## Risposte automatiche ai clienti

Sono disponibili modelli HTML separati per ticket creato dal cliente, risposta
del cliente, risposta a ticket chiuso ed e-mail rifiutata da un filtro
Postmaster. Ogni modello ha oggetto, testo CKEditor, attivazione e segnaposto.
Inizialmente sono disattivati. La risposta di rifiuto richiede l’azione
`Rifiuta e-mail e attiva risposta automatica`; ignorare un’e-mail non invia
risposte. Ticket e risposte degli agenti non generano ulteriori e-mail al cliente.

## LDAP e Active Directory

Si configurano due profili completamente separati: uno per gli agenti e uno per
contatti e aziende clienti. Ognuno dispone di connessione, ricerca, mapping,
test e attivazione propri. Qisutu sceglie automaticamente il profilo del portale.

Login, nome, cognome ed e-mail sono obbligatori. Il profilo agenti può importare
campi aggiuntivi e assegnare un gruppo predefinito. Il profilo clienti richiede
anche numero cliente Qisutu univoco e nome azienda. I campi obbligatori in
Qisutu richiedono mapping e valore.

Gli agenti vengono confrontati tramite login canonico. Per i clienti, l’azienda
viene trovata o creata per numero e il contatto viene assegnato esattamente a
essa. Un’e-mail già usata causa un errore, mai una fusione automatica. Sono
consentiti solo LDAPS e StartTLS; la verifica certificati è attiva e la password
di ricerca è cifrata. Una modifica disattiva il profilo fino al superamento dei
test. Se la directory non trova l’utente, un account locale esistente può ancora
accedere; se trova una voce, vale la sua password.

## Moduli cliente e moduli web

Gli amministratori creano moduli per il portale clienti e moduli web pubblici
con coda di destinazione fissa, testi multilingue e campi propri. Un modulo
cliente può essere disponibile a tutti o a clienti selezionati. Senza modulo
individuale resta disponibile la creazione standard.

I moduli pubblici ricevono link diretto e codice iframe. Content Security
Policy, honeypot, controllo temporale e limiti configurabili li proteggono. Nome
ed e-mail sono obbligatori; non viene creato un account attivo. Tutti i valori
sono conservati come istantanea immutabile oltre ai campi dinamici. Gli agenti
la vedono in `Informazioni del modulo`, i clienti in `Dati del modulo`. Modifiche
successive non alterano gli invii esistenti.

## CMDB

La CMDB non impone tipi di CI. Gli amministratori definiscono tipi, gruppi di
campi, obbligatorietà, selezioni, unicità, stati e relazioni. Gestiscono anche
inventario, assegnazioni, archiviazione e import. Gli agenti non modificano i
dati principali: cercano e collegano CI nel ticket e li aprono in sola lettura.
La fusione trasferisce tutti i collegamenti.

Ogni modifica entra in una cronologia immutabile. Profili CSV associano colonne,
valori e regole ai campi Qisutu; un ID esterno garantisce il confronto per fonte.
Un profilo può essere eseguito manualmente o via cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Il portale mostra solo CI attivi e campi esplicitamente autorizzati per il
cliente o contatto connesso.

## Import CSV dei dati principali

Sono disponibili import separati per clienti, contatti e agenti. I campi
dinamici attivi vengono aggiunti al modello come `dynamic.<nomecampo>`; il
modello attuale va scaricato dall’installazione di destinazione. Ogni file viene
verificato interamente. L’anteprima distingue righe nuove, modificate, invariate
ed errate; un errore blocca tutto. Dopo la conferma tutte le righe vengono
scritte in una transazione. Numero cliente o login è la chiave univoca. I record
assenti non vengono eliminati né disattivati.

Password, gruppi e permessi non fanno parte del CSV. I diritti esistenti restano
invariati e i nuovi agenti non ricevono diritti. Dopo l’import si possono
invitare nuovi contatti e agenti attivi a impostare la prima password.

## Knowledge base e FAQ

Tutti gli agenti possono creare categorie multilingue e FAQ. Un articolo ha
numero univoco, lingua e visibilità `Solo agenti` oppure `Agenti e clienti`.
Permessi di gruppo, code, autorizzazioni cliente e ulteriore stato di
pubblicazione sono esclusi. Ogni salvataggio crea una revisione immutabile.

Gli articoli `Agenti e clienti` appaiono nel portale. Accanto a CKEditor gli
agenti possono cercare e inserire soluzione, titolo con soluzione o link al
portale. Per e-mail e note visibili vengono bloccati solo gli articoli
`Solo agenti`. L’uso di una revisione viene registrato.

## Temi degli agenti

Gli agenti scelgono il tema in `Impostazioni personali`; viene salvato come
normale preferenza. Il tema `Natale` aggiunge decorazioni statiche discrete alle
pagine agenti senza modificare amministrazione o portale. Altri temi usano una
configurazione in `core/config/themes`, un foglio in `var/static/css/themes` ed
eventuali immagini in `var/static/img/themes`. Il registro centrale verifica
tutto prima del caricamento.

## Funzioni di sicurezza

Le modifiche web usano token CSRF legati alla sessione; l’API REST usa Bearer
token separati. Header centrali impediscono MIME sniffing e incorporamento
indesiderato. I cookie sono `HttpOnly`, `SameSite=Lax` e `Secure` con HTTPS.

Password IMAP/SMTP, segreti e token OAuth e segreti 2FA sono cifrati con la
chiave `var/secure/security.key`, che deve essere inclusa in un backup protetto.
Agenti e contatti possono attivare TOTP tramite QR e ricevono codici di recupero.
Il QR è generato localmente. Gli amministratori possono imporre 2FA separatamente
e reimpostare una configurazione persa.

## Configurazione del database

La connessione si trova in `core/config/QisutuConfig.pm`. Il programma di
installazione inserisce host, porta, database, utente e password casuale. Il file
è protetto da permessi restrittivi.

## Licenza

Qisutu è distribuito secondo GNU Affero General Public License versione 3 o
successiva (`AGPL-3.0-or-later`). Il testo completo si trova in `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software di terze parti

I file di terze parti mantengono gli avvisi originali. Il riepilogo si trova in
`THIRD_PARTY_NOTICES.md`.
