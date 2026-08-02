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

Qisutu est un nouveau système de gestion de tickets open source basé sur
Perl/CGI, MariaDB ou MySQL, Template Toolkit et une interface utilisateur dans
le navigateur.

Site du projet : https://qisutu.de

## État de la version

Qisutu est un système de tickets open source installable de façon autonome,
avec portail agents et clients, traitement des e-mails, authentification par
annuaire, automatisation, base de connaissances, CMDB, rapports et API REST.
Qisutu 1.0.1 est une version stable autorisée pour la production. Le projet
n’est donc plus en phase de développement. Les interfaces et structures de
base de données continuent d’évoluer dans le cadre de la maintenance normale ;
les modifications nécessaires sont fournies par la mise à jour intégrée et les
migrations de données maintenues durablement.

## Langues

Qisutu 1.0.1 contient onze langues d’interface complètes : allemand (`de`),
anglais (`en`), français (`fr`), italien (`it`), portugais brésilien (`pt-BR`),
portugais européen (`pt-PT`), espagnol (`es`), néerlandais (`nl`), polonais
(`pl`), tchèque (`cs`) et turc (`tr`).

## Installation

Exécutez les commandes suivantes en tant que root dans `/opt` :

    wget https://ftp.qisutu.de/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz
    mv qisutu-1.0.1 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

Dès le démarrage, `install.sh` demande l’une des onze langues d’interface. Le
choix est enregistré dans la configuration de l’instance, l’installateur web
s’ouvre dans cette langue et celle-ci devient la langue par défaut de Qisutu.

Le nom du répertoire détermine directement les valeurs techniques de
l’instance. `/opt/qisutu` crée l’instance `qisutu` sans préfixe `qisutu-`
supplémentaire. Ouvrez ensuite l’adresse affichée, par exemple :

    http://SERVER/qisutu/install.pl

Suivez les six étapes de l’installateur web. `install.sh` détecte le système,
installe les paquets et modules Perl requis et configure, pour chaque instance,
une intégration Apache, des services systemd, un chemin web et une base de
données distincts. Production et test peuvent fonctionner en parallèle.

L’installateur crée la base, son utilisateur, la structure de
`install/sql/schema.sql`, les données de `install/sql/insert.sql` et le premier
administrateur. Le mot de passe aléatoire de la base est écrit directement dans
`core/config/QisutuConfig.pm`. Un exemple complet avec deux instances figure
dans `INSTALL.md`.

## Mise à jour

Exécutez les commandes suivantes en tant que root dans `/opt` :

    wget https://ftp.qisutu.de/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.1

    cd /opt/qisutu-1.0.1
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.1
    rm qisutu-1.0.1.tar.gz

La mise à jour identifie l’instance par `var/install/instance.conf`, arrête
uniquement son daemon et verrouille sa relève d’e-mails. Elle copie les fichiers
gérés sans écraser les fichiers d’instance ni les configurations Apache et
systemd. Sur demande, elle sauvegarde la base. La structure des tables et toutes
les migrations permanentes sont vérifiées et complétées. Détails : `INSTALL.md`.

## Structure des répertoires

- `bin/` – points d’entrée CGI, processus d’arrière-plan et programmes en ligne de commande
- `core/` – configuration, modules, modèles, langues et classes système
- `install/sql/schema.sql` – structure complète des tables
- `install/sql/insert.sql` – données initiales d’une nouvelle installation
- `scriptfiles/` – modèles Apache et systemd
- `var/static/` – ressources frontales et composants tiers intégrés

## Modules complémentaires

Depuis la version 0.0.78, Qisutu possède un gestionnaire de modules pour des ZIP
ordinaires contenant un fichier lisible `qisutu-module.json`. Les modules sont
installés, mis à jour et désinstallés dans l’administration ; le daemon effectue
les opérations sur les fichiers séparément du processus web. Chaque module peut
fournir ses liens et écrans, et stocker les secrets chiffrés.

Qisutu 1.0.1 fournit aussi l’API interne versionnée 1.0 : services réutilisables,
événements du noyau distribués durablement par le daemon, routes REST isolées
avec autorisations propres et points d’insertion contrôlés. Les anciens modules
restent compatibles. Un module peut déclarer l’API et les capacités requises ;
Qisutu demande si nécessaire une mise à jour normale du noyau, sans variante
client. Les modules sont des projets indépendants publiés avec leur code source
complet. Installation et sécurité sont décrites dans `MODULES.md`.

## Saisie du temps

Les agents peuvent saisir du temps en heures et minutes lors de la création
d’un ticket, d’un article ou d’une modification. Chaque écriture distingue le
temps facturable du temps non facturable et peut recevoir un type d’activité.
Des écritures manuelles sont possibles. Elles sont infalsifiables : une
correction autorisée annule l’original avec motif obligatoire et crée un
remplacement lié. Seul le groupe admin reçoit initialement ce droit. Les écrans
et articles clients ne contiennent aucune saisie du temps.

## Relève des e-mails et OAuth2

L’administration regroupe les comptes entrants sous `Relève des e-mails` et
propose :

- IMAP standard avec nom d’utilisateur et mot de passe
- Microsoft 365 avec OAuth2/XOAUTH2
- Google Workspace ou Gmail avec OAuth2/XOAUTH2

Microsoft et Google redirigent vers le fournisseur après l’enregistrement.
Qisutu vérifie le retour OAuth2 avec une valeur d’état unique, stocke les jetons
et teste IMAP. Le compte n’est activé qu’après réussite ; les jetons expirés
sont renouvelés automatiquement. Le daemon de l’instance relève les boîtes
toutes les cinq minutes, sans cron supplémentaire pour
`qisutu-mail-fetch.pl`.

Un compte inactif est testé avant réactivation et ne peut être supprimé qu’après
désactivation. Ses identifiants et jetons disparaissent, mais les journaux
Postmaster restent conservés. `Paramètres SMTP` propose SMTP standard,
Microsoft 365 et Google Workspace/Gmail. Microsoft et Google utilisent
`AUTH XOAUTH2`, avec les scopes `https://outlook.office.com/SMTP.Send` et
`https://mail.google.com/`. Les jetons sont chiffrés et renouvelés ; activation
uniquement après autorisation et test SMTP réels. Reconnexion et déconnexion
OAuth sont disponibles.

Une URL de base HTTPS accessible de l’extérieur doit être définie sous
`Administration > Paramètres système`. L’URI affichée doit être enregistrée
exactement chez le fournisseur OAuth2. Voir `INSTALL.md`.

## Journal des communications

Le journal consigne relèves IMAP, envois SMTP et opérations OAuth2 avec heure,
durée, résultat, instantané du compte et étapes. Il offre des indicateurs et des
filtres. Seules les métadonnées techniques (expéditeur, destinataire, objet,
Message-ID et ticket éventuel) sont conservées ; corps et pièces jointes ne
sont pas dupliqués. Mots de passe, secrets et jetons sont retirés avant
enregistrement. La conservation vaut 90 jours par défaut ; 0 désactive le
nettoyage.

## Réponses automatiques aux clients

Des modèles HTML séparés existent pour un ticket créé par le client, une
réponse client, une réponse sur ticket fermé et un e-mail rejeté par un filtre.
Chaque modèle a son objet, son texte CKEditor, son activation et ses variables.
Ils sont d’abord désactivés. Une réponse de rejet exige l’action
`Rejeter l’e-mail et déclencher une réponse automatique` ; ignorer un e-mail ne
répond pas. Les tickets et réponses d’agents ne déclenchent pas d’e-mail client
supplémentaire.

## LDAP et Active Directory

Deux profils séparés sont configurés : agents d’un côté, contacts et entreprises
clientes de l’autre. Chacun possède connexion, recherche, mapping, tests et
activation propres. Qisutu choisit automatiquement le profil du portail.

Identifiant, prénom, nom et e-mail sont obligatoires. Le profil agents peut
importer des champs supplémentaires et affecter un groupe par défaut. Le profil
clients exige aussi le numéro client Qisutu unique et le nom de l’entreprise.
Les champs Qisutu obligatoires exigent un mapping et une valeur.

Qisutu rapproche les agents par identifiant canonique. Pour les clients,
l’entreprise est trouvée ou créée par numéro, puis le contact est affecté
exactement à cette entreprise. Une adresse e-mail déjà utilisée provoque une
erreur, jamais une fusion. Seuls LDAPS et StartTLS sont admis ; la vérification
des certificats est active et le mot de passe de recherche est chiffré. Une
modification désactive le profil jusqu’à réussite des tests. Si l’annuaire ne
trouve personne, un compte local existant peut encore se connecter ; si une
entrée existe, son mot de passe est déterminant.

## Formulaires clients et formulaires web

Les administrateurs créent des formulaires de portail et des formulaires web
publics avec file cible fixe, textes multilingues et champs propres. Un
formulaire client peut être ouvert à tous ou à certains clients. Sans formulaire
individuel, la création standard reste disponible.

Les formulaires publics reçoivent lien direct et iframe. Content Security
Policy, honeypot, contrôle du temps et limites configurables les protègent. Nom
et e-mail sont obligatoires ; aucun compte actif n’est créé. Toutes les valeurs
sont conservées comme instantané immuable en plus des champs dynamiques. Les
agents le voient sous `Informations du formulaire`, les clients sous
`Vos données de formulaire`. Une modification ultérieure ne change pas les
soumissions existantes.

## CMDB

La CMDB n’impose aucun type de CI. Les administrateurs définissent types,
groupes de champs, champs obligatoires, listes, unicité, états et relations. Ils
gèrent aussi inventaire, affectations, archivage et imports. Les agents ne
modifient pas les données de référence ; ils recherchent et lient des CI dans le
ticket et les ouvrent en lecture seule. Une fusion transfère tous les liens.

Chaque modification alimente un historique immuable. Des profils CSV associent
colonnes, valeurs et règles aux champs Qisutu ; une ID externe assure le
rapprochement par source. Un profil peut être exécuté manuellement ou par cron :

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Le portail affiche uniquement les CI actifs et champs explicitement autorisés
pour le client ou contact connecté.

## Imports CSV des données de référence

Des imports séparés existent pour clients, contacts et agents. Les champs
dynamiques actifs sont ajoutés au modèle comme `dynamic.<nomduchamp>` ; il faut
donc télécharger le modèle depuis la cible. Chaque fichier est entièrement
vérifié avant import. L’aperçu distingue nouvelles, modifiées, inchangées et
erronées ; une erreur bloque tout. Après confirmation, toutes les lignes sont
écrites dans une transaction. Numéro client ou identifiant est la clé unique.
Les absents du CSV ne sont ni supprimés ni désactivés.

Mots de passe, groupes et autorisations ne font pas partie du CSV. Les droits
existants restent inchangés et les nouveaux agents n’en reçoivent aucun. Après
réussite, des invitations peuvent être envoyées aux nouveaux contacts et agents
actifs pour définir leur premier mot de passe.

## Base de connaissances et FAQ

Tous les agents créent des catégories multilingues et des FAQ. Un article a un
numéro unique, une langue et une visibilité : `Agents uniquement` ou
`Agents et clients`. Droits de groupe, files, autorisations client et état de
publication supplémentaire sont exclus. Chaque enregistrement crée une révision
immuable.

Les articles `Agents et clients` apparaissent dans le portail. Près de CKEditor,
les agents peuvent rechercher et insérer solution, titre avec solution ou lien
du portail. Pour e-mails et notes visibles, seuls les articles
`Agents uniquement` sont bloqués. L’utilisation d’une révision est journalisée.

## Thèmes des agents

Les agents choisissent leur thème sous `Paramètres personnels`; il est stocké
comme préférence normale. Le thème `Noël` ajoute des décorations statiques
discrètes aux pages agents, sans toucher à l’administration ni au portail.
D’autres thèmes se composent d’une configuration sous `core/config/themes`,
d’une feuille sous `var/static/css/themes` et éventuellement d’images sous
`var/static/img/themes`. Le registre central valide les éléments avant chargement.

## Fonctions de sécurité

Les modifications web utilisent des jetons CSRF liés à la session ; l’API REST
emploie des Bearer tokens distincts. Des en-têtes empêchent MIME sniffing et
intégration indésirable. Les cookies sont `HttpOnly`, `SameSite=Lax` et `Secure`
en HTTPS.

Mots de passe IMAP/SMTP, secrets et jetons OAuth et secrets 2FA sont chiffrés
avec la clé d’installation `var/secure/security.key`, à inclure dans toute
sauvegarde protégée. Agents et contacts peuvent activer TOTP par QR code et
reçoivent des codes de récupération. Le QR est généré localement. Les
administrateurs peuvent imposer la 2FA séparément et réinitialiser une
configuration perdue.

## Configuration de la base de données

La connexion figure dans `core/config/QisutuConfig.pm`. L’installateur y inscrit
hôte, port, base, utilisateur et mot de passe aléatoire. Des droits restrictifs
protègent le fichier.

## Licence

Qisutu est distribué sous GNU Affero General Public License version 3 ou toute
version ultérieure (`AGPL-3.0-or-later`). Les conditions complètes figurent dans
`LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Logiciels tiers

Les fichiers tiers conservent leurs mentions d’origine. Un récapitulatif figure
dans `THIRD_PARTY_NOTICES.md`.
