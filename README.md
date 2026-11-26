# Metodix

Plataforma de metodología para clubes de fútbol formativo: banco de tareas con diagramas, borradores de sesión por mesociclo, plantillas, asistencia, evaluación y valoración.

- **Web:** https://metodix-app.github.io/

## Cómo está hecha

| Pieza | Dónde | Qué hace |
| --- | --- | --- |
| `index.html` | este repositorio | Toda la aplicación (diseño y lógica) en un solo archivo |
| `img/` | este repositorio | Diagramas de las tareas |
| Supabase | supabase.com (proyecto Metodix) | Usuarios, clubes, banco de ejercicios, configuración y datos guardados |
| `supabase/esquema.sql` | este repositorio | Tablas básicas y reglas de permisos |
| `supabase/multiclub.sql` | este repositorio | Administradores, banco de ejercicios, configuración general y alta de clubes |
| `supabase/datos/` | este repositorio | Configuración general y programación del Cimadevilla (copia de referencia) |

## Roles

- **Administración de Metodix:** ve todos los clubes, da de alta clubes nuevos y recibe las propuestas de ejercicios de todos los entrenadores. Decide si cada ejercicio va al banco común o solo al club que lo propuso.
- **Coordinación de club:** gestiona su club, da de alta a sus entrenadores y asigna equipos.
- **Entrenadores:** trabajan solo con su equipo y pueden proponer ejercicios.

Los permisos los aplica la base de datos (Row Level Security), no la web. Los códigos de alta de cada club no están en este repositorio.

## Programación de cada club

Cada club guarda sus equipos y mesociclos en la base de datos (`config/club`). Si un club no tiene mesociclos propios, usa la configuración general.

## Banco de ejercicios

Está en la tabla `ejercicios` de Supabase: los que no tienen club son el banco común; los que tienen club solo los ve ese club. Las propuestas aprobadas las prepara Claude (formato del banco y diagrama) y quedan «preparadas para publicar» en el panel de administración hasta que se publican.
