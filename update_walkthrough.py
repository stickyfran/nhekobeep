import re

with open("/home/kes/.gemini/antigravity/brain/a1e66c54-449c-424e-8104-0dc976c1e7d2/walkthrough.md", "r") as f:
    c = f.read()

c += """
### Optimización de Rendimiento y UX

- **Indicador Temporal Flotante (Sticky Header):** Al scrollear rápidamente, el chat muestra ahora la fecha central de los mensajes visibles, lo que ayuda a orientarse en historiales de años.
- **Scrollbar con Tooltip:** Añadí un tooltip estilizado al arrastrar la barra de desplazamiento, que te indica instantáneamente la fecha sin necesidad de leer todo el texto, mejorando enormemente la navegación en historiales extensos.
- **Filtro de Chats Fantasma (Ghost Chats):** Los chats vacíos creados por Beeper (que solo tienen eventos de estado y ningún mensaje real) ya no aparecerán saturando tu bandeja de entrada o sección de "All Rooms". Se evaluará si tienen al menos un mensaje real.
- **Limpieza de Eventos de Estado:** Se añadieron filtros en QML para ocultar los constantes avisos de "cambio de avatar" o "unión al grupo" que saturaban visualmente e interrumpían la cronología en Matrix.
- **Mejora del Scrolling (ListView):** Aumenté considerablemente el `cacheBuffer` y `displayMargin` en la vista de lista, además de forzar `reuseItems: true`, lo cual previene que Nheko se congele al deslizar rápido hacia arriba.
- **Descarga Absoluta:** Recordatorio: Ya dispones del botón **"Fetch full history"** en el menú de ajustes de cada sala (ícono de información superior derecha) para forzar la descarga de todo el historial.
"""

with open("/home/kes/.gemini/antigravity/brain/a1e66c54-449c-424e-8104-0dc976c1e7d2/walkthrough.md", "w") as f:
    f.write(c)
