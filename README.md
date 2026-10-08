# GnvRuteHelper

Web app para comerciales de preventa: ordena las visitas del día andando por calles reales, desde donde estás, y comparte entre compañeros lo que ya se ha visitado y las notas de cada cliente.

Nace de un problema real: el software de pedidos da la lista de clientes del día **sin ordenar**, y quien cubre una ruta que no conoce pierde tiempo o se deja clientes cercanos.

## Qué hace

**App del comercial** (`index.html`, pensada para móvil y tablet)
- Entrada con ruta + buzón, como en el software de pedidos de la empresa.
- Elección del día de visita: carga solo los clientes de ese día.
- Orden de visita calculado por tiempo **andando por calle** (vecino más cercano + mejora 2-opt), desde la ubicación GPS o desde el cliente que elijas.
- Botón *Ir* que abre Google Maps, *Hecho*, *Para luego* y *Deshacer*.
- Notas compartidas por cliente y pines corregibles en el mapa.
- Funciona con poca cobertura: los cambios se guardan en cola y se envían al volver la señal.
- Instalable (PWA) con icono propio, a pantalla completa y ahorrando datos móviles.

**Oficina** (`oficina.html`)
- Crear rutas y gestionar buzones.
- Cargar el Excel/CSV de clientes de cada ruta, con ubicación automática de direcciones.

## Tecnología
- HTML, CSS y JavaScript sin frameworks.
- [Supabase](https://supabase.com) (PostgreSQL) como base de datos, con las tablas cerradas y acceso solo mediante funciones que validan la sesión.
- [Leaflet](https://leafletjs.com) + mapas de [OpenStreetMap](https://www.openstreetmap.org).
- Direcciones con Nominatim y tiempos andando con OSRM (servicios de OpenStreetMap / FOSSGIS).
- Alojado en GitHub Pages.

## Estado
Prototipo en pruebas con datos de ejemplo (bares del centro de Barakaldo). Sin datos reales de clientes.

---
Proyecto personal de aprendizaje de desarrollo web.
