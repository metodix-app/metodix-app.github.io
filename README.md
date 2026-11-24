# Metodix

Plataforma de metodología para clubes de fútbol formativo: banco de tareas con diagramas, borradores de sesión por mesociclo, plantillas, asistencia, valoración de sesiones y evaluación individual de jugadores (0 a 10).

- **Web:** https://metodix-app.github.io/
- **Primer club:** Cimadevilla CF (Gijón)

## Cómo está hecha

| Pieza | Dónde | Qué hace |
| --- | --- | --- |
| `index.html` | este repositorio | Toda la aplicación (diseño, datos de tareas y lógica) en un solo archivo |
| `img/` | este repositorio | Diagramas de las tareas |
| Supabase | supabase.com (proyecto Metodix) | Usuarios, clubes y datos guardados (sesiones, plantillas, asistencia) |
| `supabase/esquema.sql` | este repositorio | Tablas y reglas de permisos de la base de datos |
| `supabase/conexion.js` | este repositorio | Copia de referencia del bloque que conecta la web con Supabase (el que se usa está dentro de `index.html`) |

## Permisos

- **Coordinación** (entra con el código de coordinación): ve y edita todo lo del club.
- **Entrenadores** (entran con el código de entrenador): ven la configuración común y solo sus propias sesiones y plantillas.
- Los permisos los aplica la base de datos (Row Level Security), no la web.

Los códigos de alta de cada club **no** están en este repositorio: se guardan en la tabla `clubs` de Supabase.

## Cómo hacer cambios

1. Abre el repositorio y pulsa la tecla `.` para editar en el navegador (github.dev).
2. Cambia `index.html` y guarda con un *commit*.
3. En uno o dos minutos la web se actualiza sola.
