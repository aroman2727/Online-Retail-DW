# Online Retail II — ETL + Data Warehouse + Power BI

![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![SQL Server](https://img.shields.io/badge/SQL_Server-CC2927?style=for-the-badge&logo=microsoft-sql-server&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-F2C811?style=for-the-badge&logo=power-bi&logoColor=black)

Proyecto de Data Engineering y Analytics end-to-end sobre un dataset real de e-commerce con más de 1 millón de transacciones. Va desde la limpieza del CSV original hasta un Data Warehouse en SQL Server y un dashboard de 4 páginas en Power BI.

---

## Fuente de datos

| Campo | Detalle |
| :--- | :--- |
| **Dataset** | Online Retail II UCI |
| **Plataforma** | Kaggle ([Enlace al dataset](https://www.kaggle.com/datasets/mashlyn/online-retail-ii-uci)) |
| **Volumen original** | 1,067,371 filas · 8 columnas |
| **Volumen limpio** | 1,021,332 filas (46,039 eliminados en limpieza) |
| **Período** | Diciembre 2009 — Diciembre 2011 |
| **Origen** | Tienda de regalos online con sede en UK |

---

## Estructura del proyecto

```
Online-Retail-DW/
│
├── data/
│   └── online_retail_II.csv         # CSV original de Kaggle
│
├── notebooks/
│   └── 02_etl_online_retail.ipynb   # ETL completo: Extract, Transform, Load
│
├── sql/
│   └── 03_consultas_analiticas.sql  # 20 consultas analíticas (en proceso)
│
├── assets/                           # Capturas del dashboard (en proceso)
│   ├── page1_resumen.png
│   ├── page2_ventas.png
│   ├── page3_clientes.png
│   └── page4_productos.png
│
├── powerbi/
│   └── dashboard.pbix    (en proceso)
│
└── README.md
```

---

## Arquitectura — Esquema Estrella

El ETL transforma un único CSV plano en 5 tablas relacionadas en SQL Server:

| Tabla | Filas | Descripción |
| :--- | :--- | :--- |
| `fact_ventas` | 1,021,539 | Tabla central con métricas de venta |
| `dim_fecha` | 604 | Atributos temporales: año, mes, trimestre, día de semana |
| `dim_cliente` | 5,895 | Clientes con segmentación por frecuencia de compra |
| `dim_producto` | 4,924 | Productos con descripción y precio de referencia |
| `dim_geografia` | 43 | Países con región geográfica asignada |

---

## ETL — Problemas resueltos

El dataset original tiene varios problemas de calidad que el ETL resuelve antes de cargar al Data Warehouse:

| Problema | Cantidad | Solución aplicada |
| :--- | :--- | :--- |
| `Customer ID` nulos | 243,007 (22.77%) | Asignados como cliente `UNKNOWN` |
| Duplicados exactos | 34,335 | Eliminados con `drop_duplicates()` |
| Cantidades negativas | 22,950 | Excluidas — corresponden a devoluciones |
| Precios en cero | 6,202 | Excluidos de ventas normales |
| Códigos especiales (`POST`, `DOT`, `M`) | 5,985 | Excluidos — no son productos reales |
| Cancelaciones (`Invoice` empieza con `C`) | 19,494 | Conservadas con flag `is_cancelled = 1` |

La segmentación de clientes se construyó a partir de la frecuencia de compra histórica:

| Segmento | Criterio |
| :--- | :--- |
| UNKNOWN | Sin Customer ID en el dataset |
| NUEVO | 1 pedido |
| REGULAR | 2 a 5 pedidos |
| FRECUENTE | 6 a 15 pedidos |
| VIP | Más de 15 pedidos |

---

## Consultas analíticas — 20 queries

### Grupo 1 — KPIs Globales (01–04)

| # | Pregunta | Técnica SQL |
| :--- | :--- | :--- |
| 01 | ¿Cuál es el estado general del negocio? | Aggregation + NULLIF |
| 02 | ¿Cómo evolucionó el revenue año a año? | `LAG()` — crecimiento YoY |
| 03 | ¿Cuál es la tendencia mensual acumulada? | `SUM() OVER` — running total |
| 04 | ¿Los fines de semana venden más? | `DATEPART` + `CASE WHEN` |

### Grupo 2 — Análisis de Ventas (05–08)

| # | Pregunta | Técnica SQL |
| :--- | :--- | :--- |
| 05 | ¿Cuáles son los meses de mayor venta? | `RANK()` |
| 06 | ¿Cuál es el ticket promedio por trimestre? | CTE + `AVG` por factura |
| 07 | ¿Cuánto impactan económicamente las cancelaciones? | Agregación condicional |
| 08 | ¿A qué hora del día se generan más pedidos? | `DATEPART(HOUR)` + `% OVER` |

### Grupo 3 — Clientes y Segmentación (09–12)

| # | Pregunta | Técnica SQL |
| :--- | :--- | :--- |
| 09 | ¿Cuánto aporta cada segmento al revenue total? | `% OVER` particionado |
| 10 | ¿Quiénes son los top 10 clientes? | `ROW_NUMBER()` |
| 11 | ¿Cuántos clientes nuevos se captan cada mes? | `MIN(fecha)` + acumulado |
| 12 | ¿Qué porcentaje de clientes son recurrentes? | CTE + conteo condicional |

### Grupo 4 — Productos (13–16)

| # | Pregunta | Técnica SQL |
| :--- | :--- | :--- |
| 13 | ¿Cuáles son los top 10 productos por revenue? | `RANK()` doble |
| 14 | ¿Qué productos tienen mayor tasa de devolución? | Ratio cancelaciones / ventas |
| 15 | ¿Qué productos concentran el 80% del revenue? | Análisis de Pareto — acumulado |
| 16 | ¿El precio de venta real coincide con el de referencia? | JOIN `dim_producto` |

### Grupo 5 — Geografía y Tendencias (17–20)

| # | Pregunta | Técnica SQL |
| :--- | :--- | :--- |
| 17 | ¿Cuánto vende cada país y región? | `% OVER` global y por región |
| 18 | ¿Cuál es el top 3 de productos por país? | `ROW_NUMBER PARTITION BY` |
| 19 | ¿Cómo creció cada región año a año? | `LAG PARTITION BY` región |
| 20 | ¿Cuál es el perfil RFM de los clientes? | `NTILE(5)` + clasificación |

---

## Dashboard Power BI — 4 páginas

### 1 — Resumen Ejecutivo

![Resumen Ejecutivo](assets/page1_resumen.png)

Revenue total de £19.7M en 2 años, con 39,569 pedidos y un ticket promedio de £497. El crecimiento entre 2010 y 2011 fue casi plano, lo que sugiere un negocio con base de clientes estable más que en expansión activa.

---

### 2 — Ventas y Estacionalidad

![Ventas](assets/page2_ventas.png)

Noviembre y octubre concentran los picos de venta, claramente impulsados por la temporada navideña. Los fines de semana tienen actividad casi nula, lo que confirma que los compradores son principalmente empresas (B2B) y no consumidores individuales.

---

### 3 — Clientes y Análisis RFM

![Clientes](assets/page3_clientes.png)

Los clientes VIP representan menos del 8% de la base pero concentran aproximadamente el 65% del revenue. El análisis RFM identifica a los Champions y señala los clientes At Risk que vale la pena recuperar con acciones comerciales.

---

### 4 — Productos y Geografía

![Productos](assets/page4_productos.png)

UK concentra el 85.5% del revenue global. El análisis de Pareto confirma la regla 80/20 en los productos. Se identifican también los artículos con mayor tasa de devolución como señal de posibles problemas de calidad o expectativas del cliente.

---

## Cómo reproducir el proyecto

1. Clona el repositorio: `git clone https://github.com/aroman2727/Online-Retail-DW`
2. Descarga el CSV desde [Kaggle](https://www.kaggle.com/datasets/mashlyn/online-retail-ii-uci) y colócalo en la carpeta `data/`
3. Crea la base de datos en SSMS: `CREATE DATABASE OnlineRetail_DW`
4. Abre `02_etl_online_retail.ipynb` en Jupyter o VS Code, ajusta la ruta del CSV y ejecuta celda por celda
5. Abre `03_consultas_analiticas.sql` en SSMS para explorar los análisis
6. Conecta Power BI: Obtener datos → SQL Server → `OnlineRetail_DW` → pega cada consulta como fuente independiente

---

## Autor

**Aaron Alejandro Kiwaki Alvarez**
Ingeniero Mecatrónico con 5 años en telecomunicaciones, en transición hacia roles de Data Analytics y Business Intelligence.

- LinkedIn: [aaron-kiwaki](https://www.linkedin.com/in/aaron-kiwaki/)
- GitHub: [aroman2727](https://github.com/aroman2727)
- Email: alejandro.kiwaki@gmail.com

---

*Dataset utilizado bajo los términos de uso de Kaggle.*
