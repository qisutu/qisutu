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

Qisutu es un nuevo sistema de solicitudes open source basado en Perl/CGI,
MariaDB o MySQL, Template Toolkit y una interfaz de usuario en el navegador.

Sitio del proyecto: https://qisutu.de

## Estado de la versión

Qisutu es un sistema open source instalable de forma independiente, con portales
de agentes y clientes, procesamiento de correo, autenticación por directorio,
automatización, base de conocimientos, CMDB, informes y API REST. Qisutu 2.0.1
es una versión estable aprobada para producción y ya no está en fase de
desarrollo. Las interfaces y estructuras de base de datos siguen evolucionando
con el mantenimiento regular; los cambios necesarios se distribuyen mediante
el actualizador integrado y migraciones de datos mantenidas permanentemente.

## Idiomas

Qisutu 2.0.1 incluye once idiomas completos: alemán (`de`), inglés (`en`),
francés (`fr`), italiano (`it`), portugués brasileño (`pt-BR`), portugués
europeo (`pt-PT`), español (`es`), neerlandés (`nl`), polaco (`pl`), checo
(`cs`) y turco (`tr`).

## Instalación

Ejecute como root en `/opt`:

    wget https://ftp.qisutu.de/qisutu-2.0.1.tar.gz
    tar xzf qisutu-2.0.1.tar.gz
    mv qisutu-2.0.1 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

Al principio, `install.sh` solicita uno de los once idiomas. La selección se
guarda en la configuración de la instancia, el instalador web se abre en ese
idioma y lo adopta como idioma predeterminado. El nombre del directorio
determina directamente los valores técnicos: `/opt/qisutu` crea la instancia
`qisutu`, sin añadir otro prefijo `qisutu-`.

Abra la dirección mostrada por el script, por ejemplo:

    http://SERVER/qisutu/install.pl

Siga los seis pasos del instalador web. `install.sh` detecta el sistema, instala
paquetes y módulos Perl y configura para cada instancia una integración Apache,
servicios systemd, ruta web y base de datos separados. Producción y pruebas
pueden funcionar en el mismo servidor.

El instalador crea la base, su usuario, la estructura de
`install/sql/schema.sql`, los datos de `install/sql/insert.sql` y el primer
administrador. La contraseña aleatoria de la base se escribe directamente en
`core/config/QisutuConfig.pm`. Las instrucciones detalladas y un ejemplo con dos
instancias están en `INSTALL.md`.

## Actualización

Ejecute como root en `/opt`:

    wget https://ftp.qisutu.de/qisutu-2.0.1.tar.gz
    tar xzf qisutu-2.0.1.tar.gz

    chown qisutu:www-data -R /opt/qisutu-2.0.1

    cd /opt/qisutu-2.0.1
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-2.0.1
    rm qisutu-2.0.1.tar.gz

El actualizador identifica la instancia mediante `var/install/instance.conf`,
detiene solo su daemon y bloquea únicamente su recogida de correo. Copia los
archivos gestionados sin sobrescribir archivos de instancia ni configuraciones
Apache y systemd. Opcionalmente crea un dump. La estructura de tablas y las
migraciones permanentes se comprueban y completan. Consulte `INSTALL.md`.

## Estructura de directorios

- `bin/` – entradas CGI, procesos en segundo plano y programas de línea de comandos
- `core/` – configuración, módulos, plantillas, idiomas y clases del sistema
- `install/sql/schema.sql` – estructura completa de tablas
- `install/sql/insert.sql` – datos iniciales para una nueva instalación
- `scriptfiles/` – plantillas Apache y systemd
- `var/static/` – recursos frontend y componentes de terceros

## Módulos adicionales

Desde la versión 0.0.78, Qisutu incluye un gestor para ZIP normales con un
`qisutu-module.json` legible. Los administradores instalan, actualizan y
desinstalan módulos en la administración; el daemon ejecuta las operaciones de
archivos por separado del proceso web. Cada módulo puede proporcionar enlaces y
pantallas propias y guardar secretos cifrados.

El núcleo de Qisutu también proporciona la API interna versionada 1.0: servicios
reutilizables, eventos persistentes del núcleo entregados por el daemon, rutas
REST aisladas con permisos propios y puntos de inserción controlados. Los
módulos anteriores siguen siendo compatibles. Un módulo puede declarar versión
y capacidades necesarias; si hace falta, Qisutu solicita una actualización
normal del núcleo, sin variantes por cliente. Los módulos son proyectos
independientes con código fuente completo. Instalación y seguridad: `MODULES.md`.

## Contabilización del tiempo

Los agentes pueden registrar horas y minutos al crear solicitudes, artículos y
cambios. Cada asiento distingue tiempo facturable y no facturable y puede usar
un tipo de actividad. También se permiten asientos manuales. Los datos son
auditables: una corrección autorizada anula el original con motivo obligatorio y
crea un sustituto vinculado. Inicialmente solo el grupo admin puede corregir. Las
pantallas y los artículos de clientes no contienen datos de tiempo.

## Recogida de correo y OAuth2

La administración reúne las cuentas entrantes en `Recogida de correo` y ofrece:

- IMAP estándar con usuario y contraseña
- Microsoft 365 con OAuth2/XOAUTH2
- Google Workspace o Gmail con OAuth2/XOAUTH2

Microsoft y Google redirigen al proveedor después de guardar. Qisutu valida el
retorno OAuth2 con un valor de estado de un solo uso, guarda los tokens y prueba
IMAP. La cuenta solo se activa tras la prueba; los tokens caducados se renuevan
automáticamente. En la configuración del sistema, el intervalo de recogida se
puede establecer en 1, 2, 5, 10, 15 o 30 minutos y se aplica sin reiniciar, sin
cron adicional para `qisutu-mail-fetch.pl`.

Una cuenta inactiva se prueba antes de reactivarla y solo puede eliminarse tras
desactivarla. Se borran credenciales y tokens, pero se conservan los registros
Postmaster. `Configuración SMTP` ofrece SMTP estándar, Microsoft 365 y Google
Workspace/Gmail. Microsoft y Google usan `AUTH XOAUTH2` con los ámbitos
`https://outlook.office.com/SMTP.Send` y `https://mail.google.com/`. Los tokens
se cifran y renuevan; la activación exige autorización y una prueba SMTP real.

Debe configurarse una URL base HTTPS accesible desde el exterior en
`Administración > Configuración del sistema`. La URI mostrada debe registrarse
exactamente en el proveedor OAuth2. Consulte `INSTALL.md`.

## Registro de comunicaciones

El registro guarda recogidas IMAP, envíos SMTP y operaciones OAuth2 con hora,
duración, resultado, instantánea de la cuenta y pasos. Hay indicadores y filtros.
Solo se almacenan metadatos técnicos — remitente, destinatario, asunto,
Message-ID y posible solicitud —; cuerpo y adjuntos no se duplican. Contraseñas,
secretos y tokens se eliminan antes de guardar. La retención predeterminada es
de 90 días; 0 desactiva la limpieza automática.

## Respuestas automáticas a clientes

Hay plantillas HTML separadas para solicitud creada por el cliente, respuesta
del cliente, respuesta a una solicitud cerrada y correo rechazado por un filtro
Postmaster. Cada plantilla tiene asunto, texto CKEditor, activación y marcadores.
Inicialmente están desactivadas. La respuesta de rechazo exige la acción
`Rechazar correo y activar respuesta automática`; ignorar un correo no responde.
Las solicitudes y respuestas de agentes no generan otro correo al cliente.

## LDAP y Active Directory

Se configuran dos perfiles completamente separados: uno para agentes y otro
para contactos y empresas clientes. Cada uno tiene conexión, búsqueda, mapeo,
pruebas y activación propios. Qisutu elige automáticamente el perfil del portal.

Login, nombre, apellidos y correo son obligatorios. El perfil de agentes puede
importar campos adicionales y asignar un grupo predeterminado. El perfil de
clientes también exige número de cliente Qisutu único y nombre de empresa. Los
campos obligatorios en Qisutu requieren mapeo y valor.

Los agentes se concilian por login canónico. Para los clientes, la empresa se
busca o crea por número y el contacto se asigna exactamente a ella. Un correo ya
utilizado provoca un error, nunca una fusión automática. Solo se permiten LDAPS
y StartTLS; la validación de certificados está activa y la contraseña de
búsqueda se cifra. Un cambio desactiva el perfil hasta superar las pruebas. Si
el directorio no encuentra al usuario, una cuenta local existente aún puede
acceder; si lo encuentra, su contraseña es decisiva.

## Formularios de clientes y formularios web

Los administradores crean formularios del portal y formularios web públicos con
cola de destino fija, textos multilingües y campos propios. Un formulario puede
habilitarse para todos o para clientes seleccionados. Sin formulario individual,
la creación estándar sigue disponible.

Los formularios públicos reciben enlace directo y código iframe. Content
Security Policy, honeypot, comprobación temporal y límites configurables los
protegen. Nombre y correo son obligatorios; no se crea una cuenta activa. Todos
los valores se guardan como instantánea inmutable además de los campos dinámicos.
Los agentes ven `Información del formulario` y los clientes `Sus datos del
formulario`. Los cambios posteriores no alteran envíos existentes.

## CMDB

La CMDB no impone tipos de CI. Los administradores definen tipos, grupos de
campos, obligatoriedad, selecciones, unicidad, estados y relaciones. También
gestionan inventario, asignaciones, archivado e importaciones. Los agentes no
modifican datos maestros; buscan y vinculan CIs en la solicitud y los abren en
solo lectura. Una fusión transfiere todos los vínculos.

Cada cambio entra en un historial inmutable. Los perfiles CSV asignan columnas,
valores y reglas a campos Qisutu; un ID externo garantiza la conciliación por
origen. Un perfil puede ejecutarse manualmente o por cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

El portal muestra solo CIs activos y campos expresamente habilitados para el
cliente o contacto conectado.

## Importaciones CSV de datos maestros

Hay importaciones separadas para clientes, contactos y agentes. Los campos
dinámicos activos se añaden a la plantilla como `dynamic.<nombrecampo>`; la
plantilla actual debe descargarse de la instalación de destino. Cada archivo se
comprueba por completo. La vista previa separa filas nuevas, cambiadas,
sin cambios y erróneas; un error bloquea todo. Tras confirmar, todas las filas
se escriben en una transacción. Número de cliente o login es la clave única. Los
registros ausentes no se eliminan ni desactivan.

Contraseñas, grupos y permisos no forman parte del CSV. Los derechos existentes
no cambian y los nuevos agentes no reciben derechos. Tras la importación, los
nuevos contactos y agentes activos pueden recibir una invitación para definir
su primera contraseña.

## Base de conocimientos y FAQ

Todos los agentes pueden crear categorías multilingües y artículos FAQ. Un
artículo tiene número único, idioma y visibilidad `Solo agentes` o
`Agentes y clientes`. Derechos de grupo, colas, habilitaciones por cliente y un
estado extra de publicación no forman parte de la lógica. Cada guardado crea una
revisión inmutable.

Los artículos `Agentes y clientes` aparecen en el portal. Junto a CKEditor, los
agentes pueden buscar e insertar solución, título con solución o enlace del
portal. Para correos y notas visibles al cliente, solo se bloquean artículos
`Solo agentes`. El uso de la revisión se registra.

## Temas de agentes

Los agentes eligen el tema en `Configuración personal`; se guarda como una
preferencia normal. El tema `Navidad` añade decoración estática discreta a las
páginas de agentes sin cambiar administración ni portal. Otros temas usan
configuración en `core/config/themes`, CSS en `var/static/css/themes` y, si es
necesario, imágenes en `var/static/img/themes`. El registro central valida todo.

## Funciones de seguridad

Los cambios web usan tokens CSRF vinculados a la sesión; la API REST usa Bearer
tokens separados. Las cabeceras centrales impiden MIME sniffing e incrustación
no deseada. Las cookies son `HttpOnly`, `SameSite=Lax` y `Secure` con HTTPS.

Contraseñas IMAP/SMTP, secretos y tokens OAuth y secretos 2FA se cifran con la
clave `var/secure/security.key`, que debe incluirse en una copia protegida.
Agentes y contactos pueden activar TOTP mediante QR y reciben códigos de
recuperación. El QR se genera localmente. Los administradores pueden exigir 2FA
por separado y restablecer una configuración perdida.

## Configuración de la base de datos

La conexión está en `core/config/QisutuConfig.pm`. El instalador escribe host,
puerto, base, usuario y contraseña aleatoria. Los permisos restrictivos protegen
el archivo.

## Licencia

Qisutu se distribuye bajo la GNU Affero General Public License versión 3 o
posterior (`AGPL-3.0-or-later`). Los términos completos están en `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software de terceros

Los archivos de terceros conservan sus avisos originales. El resumen está en
`THIRD_PARTY_NOTICES.md`.
