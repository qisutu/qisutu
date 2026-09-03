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

Qisutu é um novo sistema de chamados open source baseado em Perl/CGI, MariaDB
ou MySQL, Template Toolkit e uma interface de usuário no navegador.

Site do projeto: https://qisutu.de

## Status da versão

Qisutu é um sistema open source instalável de forma independente, com portais
de agentes e clientes, processamento de e-mail, login por diretório,
automação, base de conhecimento, CMDB, relatórios e API REST. Qisutu 2.0.1 é uma
versão estável liberada para produção e não está mais em fase de desenvolvimento.
Interfaces e estruturas de banco de dados continuam evoluindo na manutenção
regular; alterações necessárias são entregues pelo atualizador integrado e por
migrações de dados mantidas permanentemente.

## Idiomas

Qisutu 2.0.1 inclui onze idiomas completos: alemão (`de`), inglês (`en`),
francês (`fr`), italiano (`it`), português brasileiro (`pt-BR`), português
europeu (`pt-PT`), espanhol (`es`), neerlandês (`nl`), polonês (`pl`), tcheco
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

No início, `install.sh` solicita um dos onze idiomas. A escolha é salva na
configuração da instância, o instalador web abre nesse idioma e o adota como
padrão do Qisutu. O nome do diretório determina diretamente os valores técnicos:
`/opt/qisutu` cria a instância `qisutu`, sem prefixo `qisutu-` adicional.

Abra o endereço exibido pelo script, por exemplo:

    http://SERVER/qisutu/install.pl

Siga as seis etapas do instalador web. `install.sh` detecta o sistema, instala
pacotes e módulos Perl e configura, para cada instância, integração Apache,
serviços systemd, caminho web e banco de dados separados. Produção e teste podem
rodar no mesmo servidor.

O instalador cria banco, usuário, estrutura de `install/sql/schema.sql`, dados
de `install/sql/insert.sql` e o primeiro administrador. A senha aleatória do
banco é gravada diretamente em `core/config/QisutuConfig.pm`. Instruções
detalhadas e um exemplo com duas instâncias estão em `INSTALL.md`.

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

O atualizador identifica a instância por `var/install/instance.conf`, para
somente o daemon dela e bloqueia apenas a coleta de e-mail correspondente. Ele
copia os arquivos gerenciados sem sobrescrever arquivos da instância nem as
configurações Apache e systemd. Opcionalmente cria um dump. Estrutura de tabelas
e migrações permanentes são verificadas e complementadas. Veja `INSTALL.md`.

## Estrutura de diretórios

- `bin/` – entradas CGI, processos em segundo plano e programas de linha de comando
- `core/` – configuração, módulos, templates, idiomas e classes do sistema
- `install/sql/schema.sql` – estrutura completa das tabelas
- `install/sql/insert.sql` – dados iniciais de uma nova instalação
- `scriptfiles/` – modelos Apache e systemd
- `var/static/` – recursos de frontend e componentes de terceiros

## Módulos adicionais

Desde a versão 0.0.78, Qisutu possui um gerenciador para ZIPs comuns com um
`qisutu-module.json` legível. Administradores instalam, atualizam e desinstalam
módulos na administração; o daemon executa as operações de arquivos separado do
processo web. Cada módulo pode fornecer links e telas próprias e armazenar
segredos criptografados.

O núcleo do Qisutu também fornece a API interna versionada 1.0: serviços reutilizáveis,
eventos persistentes do núcleo entregues pelo daemon, rotas REST isoladas com
permissões próprias e pontos controlados na interface. Módulos anteriores
continuam compatíveis. Um módulo pode declarar versão e capacidades necessárias;
se preciso, Qisutu solicita uma atualização normal do núcleo, sem variantes por
cliente. Os módulos são projetos independentes com código-fonte completo.
Instalação e segurança: `MODULES.md`.

## Contabilização de tempo

Agentes podem registrar horas e minutos na criação de chamados, artigos e
alterações. Cada lançamento distingue tempo faturável e não faturável e pode
usar um tipo de atividade. Lançamentos manuais também são possíveis. Os dados
são auditáveis: uma correção autorizada cancela o original com motivo obrigatório
e cria um substituto vinculado. Inicialmente só o grupo admin pode corrigir. As
telas e os artigos de clientes não contêm contabilização de tempo.

## Coleta de e-mail e OAuth2

A administração reúne contas de entrada em `Coleta de e-mail` e oferece:

- IMAP padrão com usuário e senha
- Microsoft 365 com OAuth2/XOAUTH2
- Google Workspace ou Gmail com OAuth2/XOAUTH2

Microsoft e Google redirecionam ao provedor após salvar. Qisutu verifica o
retorno OAuth2 com um valor de estado de uso único, armazena tokens e testa IMAP.
A conta só é ativada após o teste; tokens expirados são renovados
automaticamente. Nas configurações do sistema, o intervalo de coleta pode ser
definido como 1, 2, 5, 10, 15 ou 30 minutos e é aplicado sem reinicialização,
sem cron adicional para `qisutu-mail-fetch.pl`.

Uma conta inativa é testada antes da reativação e só pode ser excluída após ser
desativada. Credenciais e tokens são removidos, mas os logs Postmaster permanecem.
`Configurações SMTP` oferece SMTP padrão, Microsoft 365 e Google Workspace/Gmail.
Microsoft e Google usam `AUTH XOAUTH2` com os escopos
`https://outlook.office.com/SMTP.Send` e `https://mail.google.com/`. Tokens são
criptografados e renovados; a ativação exige autorização e teste SMTP real.

Uma URL base HTTPS acessível externamente deve ser configurada em
`Administração > Configurações do sistema`. A URI exibida deve ser registrada
exatamente no provedor OAuth2. Veja `INSTALL.md`.

## Registro de comunicação

O registro guarda coletas IMAP, envios SMTP e operações OAuth2 com horário,
duração, resultado, instantâneo da conta e etapas. Há indicadores e filtros.
Somente metadados técnicos — remetente, destinatário, assunto, Message-ID e
possível chamado — são armazenados; corpo e anexos não são duplicados. Senhas,
segredos e tokens são removidos antes do registro. A retenção padrão é 90 dias;
0 desativa a limpeza automática.

## Respostas automáticas aos clientes

Há modelos HTML separados para chamado criado pelo cliente, resposta do cliente,
resposta em chamado fechado e e-mail rejeitado por filtro Postmaster. Cada modelo
tem assunto, texto CKEditor, ativação e marcadores. Inicialmente ficam
desativados. A resposta de rejeição exige a ação `Rejeitar e-mail e acionar
resposta automática`; ignorar um e-mail não responde. Chamados e respostas de
agentes não geram outro e-mail ao cliente.

## LDAP e Active Directory

São configurados dois perfis completamente separados: um para agentes e outro
para contatos e empresas clientes. Cada perfil possui conexão, pesquisa,
mapeamento, testes e ativação próprios. Qisutu escolhe automaticamente o perfil
do portal.

Login, nome, sobrenome e e-mail são obrigatórios. O perfil de agentes pode
importar campos adicionais e atribuir um grupo padrão. O perfil de clientes
também exige número de cliente Qisutu exclusivo e nome da empresa. Campos
obrigatórios no Qisutu exigem mapeamento e valor.

Agentes são conciliados pelo login canônico. Para clientes, a empresa é
localizada ou criada pelo número e o contato é atribuído exatamente a ela. Um
e-mail já utilizado causa erro, nunca fusão automática. Apenas LDAPS e StartTLS
são permitidos; a validação de certificado é ativa e a senha de pesquisa é
criptografada. Uma alteração desativa o perfil até os testes passarem. Se o
diretório não encontrar o usuário, uma conta local existente ainda pode entrar;
se encontrar, a senha do diretório é decisiva.

## Formulários de clientes e formulários web

Administradores criam formulários do portal e formulários web públicos com fila
de destino fixa, textos multilíngues e campos próprios. Um formulário pode ser
liberado para todos ou clientes selecionados. Sem formulário individual, a
criação padrão continua disponível.

Formulários públicos recebem link direto e código iframe. Content Security
Policy, honeypot, verificação de tempo e limites configuráveis os protegem. Nome
e e-mail são obrigatórios; nenhuma conta ativa é criada. Todos os valores são
armazenados como instantâneo imutável, além dos campos dinâmicos. Agentes veem
`Informações do formulário` e clientes veem `Seus dados do formulário`.
Alterações posteriores não modificam envios existentes.

## CMDB

A CMDB não impõe tipos de CI. Administradores definem tipos, grupos de campos,
obrigatoriedade, seleções, unicidade, estados e relações. Também gerenciam
inventário, atribuições, arquivamento e importações. Agentes não alteram dados
mestres; pesquisam e vinculam CIs no chamado e os abrem somente para leitura.
Uma mesclagem transfere todos os vínculos.

Cada mudança entra em um histórico imutável. Perfis CSV associam colunas,
valores e regras aos campos Qisutu; um ID externo garante a conciliação por
fonte. Um perfil pode ser executado manualmente ou por cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

O portal mostra apenas CIs ativos e campos explicitamente liberados para o
cliente ou contato conectado.

## Importações CSV de dados mestres

Há importações separadas para clientes, contatos e agentes. Campos dinâmicos
ativos são adicionados ao modelo como `dynamic.<nomedocampo>`; o modelo atual
deve ser baixado da instalação de destino. Cada arquivo é verificado por inteiro.
A prévia separa linhas novas, alteradas, inalteradas e erradas; um erro bloqueia
tudo. Após a confirmação, todas as linhas são gravadas em uma transação. Número
do cliente ou login é a chave exclusiva. Registros ausentes não são excluídos
nem desativados.

Senhas, grupos e permissões não fazem parte do CSV. Direitos existentes não
mudam e novos agentes não recebem direitos. Após a importação, novos contatos e
agentes ativos podem receber convite para definir a primeira senha.

## Base de conhecimento e FAQ

Todos os agentes podem criar categorias multilíngues e artigos FAQ. Um artigo
tem número exclusivo, idioma e visibilidade `Somente agentes` ou
`Agentes e clientes`. Direitos de grupo, filas, liberações por cliente e estado
extra de publicação não fazem parte da lógica. Cada salvamento cria uma revisão
imutável.

Artigos `Agentes e clientes` aparecem no portal. Ao lado do CKEditor, agentes
podem pesquisar e inserir solução, título com solução ou link do portal. Para
e-mails e notas visíveis ao cliente, apenas artigos `Somente agentes` são
bloqueados. O uso da revisão é registrado.

## Temas dos agentes

Agentes escolhem o tema em `Configurações pessoais`; ele é salvo como preferência
normal. O tema `Natal` adiciona decoração estática discreta às páginas dos
agentes, sem alterar administração ou portal. Outros temas usam configuração em
`core/config/themes`, CSS em `var/static/css/themes` e, se necessário, imagens
em `var/static/img/themes`. O registro central valida tudo antes de carregar.

## Recursos de segurança

Alterações web usam tokens CSRF vinculados à sessão; a API REST usa Bearer
tokens separados. Cabeçalhos centrais impedem MIME sniffing e incorporação
indesejada. Cookies são `HttpOnly`, `SameSite=Lax` e `Secure` em HTTPS.

Senhas IMAP/SMTP, segredos e tokens OAuth e segredos 2FA são criptografados com
a chave `var/secure/security.key`, que deve fazer parte de um backup protegido.
Agentes e contatos podem ativar TOTP por QR e recebem códigos de recuperação. O
QR é gerado localmente. Administradores podem exigir 2FA separadamente e
redefinir uma configuração perdida.

## Configuração do banco de dados

A conexão está em `core/config/QisutuConfig.pm`. O instalador grava host, porta,
banco, usuário e senha aleatória. Permissões restritivas protegem o arquivo.

## Licença

Qisutu é licenciado sob a GNU Affero General Public License versão 3 ou posterior
(`AGPL-3.0-or-later`). Os termos completos estão em `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software de terceiros

Arquivos de terceiros mantêm seus avisos originais. O resumo está em
`THIRD_PARTY_NOTICES.md`.
