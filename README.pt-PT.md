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

Qisutu é um novo sistema de tickets open source baseado em Perl/CGI, MariaDB ou
MySQL, Template Toolkit e uma interface de utilizador no navegador.

Site do projeto: https://qisutu.de

## Estado da versão

Qisutu é um sistema open source instalável de forma autónoma, com portais de
agentes e clientes, processamento de e-mail, autenticação por diretório,
automatização, base de conhecimento, CMDB, relatórios e API REST. Qisutu 2.0.1
é uma versão estável aprovada para produção e já não se encontra em fase de
desenvolvimento. Interfaces e estruturas da base de dados continuam a evoluir
na manutenção regular; as alterações necessárias são fornecidas pelo
atualizador integrado e por migrações de dados mantidas permanentemente.

## Idiomas

Qisutu 2.0.1 inclui onze idiomas completos: alemão (`de`), inglês (`en`),
francês (`fr`), italiano (`it`), português brasileiro (`pt-BR`), português
europeu (`pt-PT`), espanhol (`es`), neerlandês (`nl`), polaco (`pl`), checo
(`cs`) e turco (`tr`).

## Instalação

Execute como root em `/opt`:

    wget https://ftp.qisutu.de/qisutu-2.0.1.tar.gz
    tar xzf qisutu-2.0.1.tar.gz
    mv qisutu-2.0.1 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

No início, `install.sh` solicita um dos onze idiomas. A escolha é guardada na
configuração da instância, o instalador web abre nesse idioma e adota-o como
idioma predefinido. O nome do diretório determina diretamente os valores
técnicos: `/opt/qisutu` cria a instância `qisutu`, sem prefixo `qisutu-` extra.

Abra o endereço apresentado pelo script, por exemplo:

    http://SERVER/qisutu/install.pl

Siga os seis passos do instalador web. `install.sh` deteta o sistema, instala
pacotes e módulos Perl e configura, para cada instância, integração Apache,
serviços systemd, caminho web e base de dados separados. Produção e teste podem
funcionar no mesmo servidor.

O instalador cria a base de dados, o utilizador, a estrutura de
`install/sql/schema.sql`, os dados de `install/sql/insert.sql` e o primeiro
administrador. A palavra-passe aleatória da base é escrita diretamente em
`core/config/QisutuConfig.pm`. As instruções detalhadas e um exemplo com duas
instâncias encontram-se em `INSTALL.md`.

## Atualização

Execute como root em `/opt`:

    wget https://ftp.qisutu.de/qisutu-2.0.1.tar.gz
    tar xzf qisutu-2.0.1.tar.gz

    chown qisutu:www-data -R /opt/qisutu-2.0.1

    cd /opt/qisutu-2.0.1
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-2.0.1
    rm qisutu-2.0.1.tar.gz

O atualizador identifica a instância através de `var/install/instance.conf`,
para apenas o respetivo daemon e bloqueia só a recolha de e-mail correspondente.
Copia os ficheiros geridos sem substituir ficheiros da instância nem as
configurações Apache e systemd. Opcionalmente cria um dump. A estrutura das
tabelas e as migrações permanentes são verificadas e completadas. Consulte
`INSTALL.md`.

## Estrutura de diretórios

- `bin/` – entradas CGI, processos em segundo plano e programas de linha de comandos
- `core/` – configuração, módulos, modelos, idiomas e classes do sistema
- `install/sql/schema.sql` – estrutura completa das tabelas
- `install/sql/insert.sql` – dados iniciais de uma nova instalação
- `scriptfiles/` – modelos Apache e systemd
- `var/static/` – recursos de frontend e componentes de terceiros

## Módulos adicionais

Desde a versão 0.0.78, Qisutu possui um gestor para ZIPs normais com um
`qisutu-module.json` legível. Os administradores instalam, atualizam e removem
módulos na administração; o daemon executa as operações sobre ficheiros
separadamente do processo web. Cada módulo pode fornecer ligações e ecrãs
próprios e guardar segredos cifrados.

O núcleo do Qisutu também fornece a API interna versionada 1.0: serviços reutilizáveis,
eventos persistentes do núcleo entregues pelo daemon, rotas REST isoladas com
permissões próprias e pontos controlados na interface. Os módulos anteriores
continuam compatíveis. Um módulo pode declarar a versão e as capacidades
necessárias; se for preciso, Qisutu solicita uma atualização normal do núcleo,
sem variantes por cliente. Os módulos são projetos independentes com código
fonte completo. Instalação e segurança: `MODULES.md`.

## Registo de tempo

Os agentes podem registar horas e minutos na criação de tickets, artigos e
alterações. Cada registo distingue tempo faturável e não faturável e pode usar
um tipo de atividade. Também são possíveis registos manuais. Os dados são
auditáveis: uma correção autorizada cancela o original com motivo obrigatório e
cria um substituto associado. Inicialmente, só o grupo admin pode corrigir. Os
ecrãs e artigos dos clientes não contêm registos de tempo.

## Recolha de e-mail e OAuth2

A administração reúne as contas de entrada em `Recolha de e-mail` e oferece:

- IMAP normal com utilizador e palavra-passe
- Microsoft 365 com OAuth2/XOAUTH2
- Google Workspace ou Gmail com OAuth2/XOAUTH2

Microsoft e Google redirecionam para o fornecedor depois de guardar. Qisutu
valida o retorno OAuth2 com um valor de estado de utilização única, guarda os
tokens e testa IMAP. A conta só é ativada após o teste; tokens expirados são
renovados automaticamente. Nas definições do sistema, o intervalo de recolha
pode ser configurado para 1, 2, 5, 10, 15 ou 30 minutos e é aplicado sem
reiniciar, sem cron adicional para `qisutu-mail-fetch.pl`.

Uma conta inativa é testada antes da reativação e só pode ser eliminada depois
de ser desativada. Credenciais e tokens são removidos, mas os registos Postmaster
permanecem. `Definições SMTP` oferece SMTP normal, Microsoft 365 e Google
Workspace/Gmail. Microsoft e Google usam `AUTH XOAUTH2` com os âmbitos
`https://outlook.office.com/SMTP.Send` e `https://mail.google.com/`. Os tokens
são cifrados e renovados; a ativação exige autorização e teste SMTP real.

É necessário configurar um URL base HTTPS acessível externamente em
`Administração > Definições do sistema`. O URI apresentado deve ser registado
exatamente no fornecedor OAuth2. Consulte `INSTALL.md`.

## Registo de comunicações

O registo guarda recolhas IMAP, envios SMTP e operações OAuth2 com hora, duração,
resultado, instantâneo da conta e passos. Existem indicadores e filtros. Apenas
metadados técnicos — remetente, destinatário, assunto, Message-ID e possível
ticket — são guardados; corpo e anexos não são duplicados. Palavras-passe,
segredos e tokens são removidos antes do registo. A retenção predefinida é 90
dias; 0 desativa a limpeza automática.

## Respostas automáticas aos clientes

Existem modelos HTML separados para ticket criado pelo cliente, resposta do
cliente, resposta num ticket fechado e e-mail rejeitado por um filtro
Postmaster. Cada modelo tem assunto, texto CKEditor, ativação e marcadores.
Inicialmente ficam desativados. A resposta de rejeição exige a ação
`Rejeitar e-mail e acionar resposta automática`; ignorar um e-mail não responde.
Tickets e respostas de agentes não geram outro e-mail ao cliente.

## LDAP e Active Directory

São configurados dois perfis totalmente separados: um para agentes e outro para
contactos e empresas clientes. Cada um tem ligação, pesquisa, mapeamento, testes
e ativação próprios. Qisutu escolhe automaticamente o perfil do portal.

Login, nome, apelido e e-mail são obrigatórios. O perfil de agentes pode importar
campos adicionais e atribuir um grupo predefinido. O perfil de clientes também
exige o número de cliente Qisutu único e o nome da empresa. Campos obrigatórios
no Qisutu exigem mapeamento e valor.

Os agentes são conciliados pelo login canónico. Para clientes, a empresa é
encontrada ou criada pelo número e o contacto é associado exatamente a ela. Um
e-mail já utilizado causa erro, nunca uma fusão automática. Apenas LDAPS e
StartTLS são permitidos; a validação do certificado está ativa e a palavra-passe
de pesquisa é cifrada. Uma alteração desativa o perfil até os testes passarem.
Se o diretório não encontrar o utilizador, uma conta local existente ainda pode
entrar; se encontrar, a palavra-passe do diretório é decisiva.

## Formulários de clientes e formulários web

Os administradores criam formulários do portal e formulários web públicos com
fila de destino fixa, textos multilingues e campos próprios. Um formulário pode
ser disponibilizado a todos ou a clientes selecionados. Sem formulário
individual, a criação normal continua disponível.

Os formulários públicos recebem uma ligação direta e código iframe. Content
Security Policy, honeypot, verificação temporal e limites configuráveis
protegem-nos. Nome e e-mail são obrigatórios; não é criada uma conta ativa.
Todos os valores são guardados como instantâneo imutável, além dos campos
dinâmicos. Os agentes veem `Informações do formulário` e os clientes
`Os seus dados do formulário`. Alterações posteriores não modificam submissões
existentes.

## CMDB

A CMDB não impõe tipos de CI. Os administradores definem tipos, grupos de
campos, obrigatoriedade, seleções, unicidade, estados e relações. Também gerem
inventário, associações, arquivo e importações. Os agentes não alteram dados
principais; pesquisam e associam CIs no ticket e abrem-nos só para leitura. Uma
fusão transfere todas as associações.

Cada mudança entra num histórico imutável. Perfis CSV associam colunas, valores
e regras aos campos Qisutu; um ID externo garante a conciliação por origem. Um
perfil pode ser executado manualmente ou por cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

O portal mostra apenas CIs ativos e campos explicitamente autorizados para o
cliente ou contacto autenticado.

## Importações CSV de dados principais

Existem importações separadas para clientes, contactos e agentes. Os campos
dinâmicos ativos são adicionados ao modelo como `dynamic.<nomedocampo>`; o
modelo atual deve ser descarregado da instalação de destino. Cada ficheiro é
verificado integralmente. A pré-visualização separa linhas novas, alteradas,
inalteradas e erradas; um erro bloqueia tudo. Depois da confirmação, todas as
linhas são escritas numa transação. Número de cliente ou login é a chave única.
Registos ausentes não são eliminados nem desativados.

Palavras-passe, grupos e permissões não fazem parte do CSV. Os direitos
existentes não mudam e novos agentes não recebem direitos. Depois da importação,
novos contactos e agentes ativos podem receber convite para definir a primeira
palavra-passe.

## Base de conhecimento e FAQ

Todos os agentes podem criar categorias multilingues e artigos FAQ. Um artigo
tem número único, idioma e visibilidade `Apenas agentes` ou `Agentes e clientes`.
Direitos de grupo, filas, disponibilizações por cliente e um estado adicional de
publicação não fazem parte da lógica. Cada gravação cria uma revisão imutável.

Artigos `Agentes e clientes` aparecem no portal. Junto do CKEditor, os agentes
podem pesquisar e inserir solução, título com solução ou ligação do portal. Para
e-mails e notas visíveis ao cliente, apenas artigos `Apenas agentes` são
bloqueados. A utilização da revisão fica registada.

## Temas dos agentes

Os agentes escolhem o tema em `Definições pessoais`; é guardado como preferência
normal. O tema `Natal` acrescenta decoração estática discreta às páginas dos
agentes sem alterar administração ou portal. Outros temas usam configuração em
`core/config/themes`, CSS em `var/static/css/themes` e, se necessário, imagens
em `var/static/img/themes`. O registo central valida tudo antes de carregar.

## Funções de segurança

As alterações web usam tokens CSRF ligados à sessão; a API REST usa Bearer
tokens separados. Cabeçalhos centrais impedem MIME sniffing e incorporação
indesejada. Os cookies são `HttpOnly`, `SameSite=Lax` e `Secure` em HTTPS.

Palavras-passe IMAP/SMTP, segredos e tokens OAuth e segredos 2FA são cifrados com
a chave `var/secure/security.key`, que deve fazer parte de uma cópia de segurança
protegida. Agentes e contactos podem ativar TOTP por QR e recebem códigos de
recuperação. O QR é gerado localmente. Os administradores podem impor 2FA
separadamente e redefinir uma configuração perdida.

## Configuração da base de dados

A ligação está em `core/config/QisutuConfig.pm`. O instalador grava host, porta,
base de dados, utilizador e palavra-passe aleatória. Permissões restritivas
protegem o ficheiro.

## Licença

Qisutu é licenciado sob a GNU Affero General Public License versão 3 ou posterior
(`AGPL-3.0-or-later`). Os termos completos estão em `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software de terceiros

Os ficheiros de terceiros mantêm os avisos originais. O resumo encontra-se em
`THIRD_PARTY_NOTICES.md`.
