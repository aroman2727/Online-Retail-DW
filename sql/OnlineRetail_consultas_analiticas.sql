-- ============================================================
-- CONSULTAS ANALITICAS — Online Retail II Data Warehouse
-- Base de datos : OnlineRetail_DW
-- Motor: SQL Server
-- ============================================================
--
--  DESCRIPCION:
--  20 consultas organizadas en 5 grupos temáticos:
--    Grupo 1 — KPIs Globales           (consultas 01–04)
--    Grupo 2 — Analisis de Ventas      (consultas 05–08)
--    Grupo 3 — Clientes y Segmentacion (consultas 09–12)
--    Grupo 4 — Productos               (consultas 13–16)
--    Grupo 5 — Geografia y Tendencias  (consultas 17–20)
--
--  TÉCNICAS APLICADAS:
--    - Window Functions (RANK, ROW_NUMBER, LAG, SUM OVER)
--    - CTEs para calculos multi-paso
--    - Agregacion condicional (CASE WHEN dentro de SUM/AVG)
--    - Calculo de metricas de negocio (RFM, ticket promedio, YoY)
-- ============================================================

USE OnlineRetail_DW;
GO

-- ============================================================
-- GRUPO 1 — KPIs GLOBALES
-- ============================================================

-- ============================================================
-- CONSULTA 01
-- Pregunta  : ¿Cuál es el estado general del negocio?
-- Técnica   : Aggregation + CAST para porcentajes
-- Gráfico   : KPI Cards (portada del dashboard)
-- ============================================================

SELECT
	ROUND(SUM(CASE WHEN f.is_cancelled=0 THEN f.total_linea ELSE 0 END), 2)	AS ingreso_total,
	COUNT(DISTINCT CASE WHEN f.is_cancelled=0
		THEN f.invoice_number END)											AS total_pedidos,
	COUNT(DISTINCT CASE WHEN c.customer_id <> 'UNKNOWN'
		THEN c.cliente_id END)												AS clientes_activos,
	ROUND(SUM(CASE WHEN f.is_cancelled = 0 THEN f.total_linea ELSE 0 END)
		/ NULLIF(COUNT(DISTINCT CASE WHEN f.is_cancelled = 0
			THEN f.invoice_number END), 0)	,2)								AS ticket_promedio,
	COUNT(DISTINCT p.producto_id)											AS productos_distintos,
	COUNT(DISTINCT g.geografia_id)											AS paises_alcanzados,
	ROUND(100.0*SUM(CAST(f.is_cancelled AS INT)) / NULLIF(COUNT(*),0),2)	AS tasa_cancelacion_pct,
	COUNT(DISTINCT d.anio)													AS anios_en_dataset
FROM fact_ventas	f
JOIN dim_cliente	c ON f.cliente_id	= c.cliente_id
JOIN dim_producto	p ON f.producto_id	= p.producto_id
JOIN dim_geografia	g ON f.geografia_id	= g.geografia_id
JOIN dim_fecha		d ON f.fecha_id		= d.fecha_id;
GO

-- ============================================================
-- CONSULTA 02
-- Pregunta: ¿Como evolucionan los ingresos año a año?
-- Tecnica: CTE + LAG() para variacion YoY (Year over Year)
-- Grafico: Columnas agrupadas (Ingresos) + Linea (Crecimiento %)
-- ============================================================

WITH ingresos_por_anio AS(
	SELECT
		d.anio,
		ROUND(SUM(f.total_linea), 2)								AS ingresos_actual,
		COUNT(DISTINCT f.invoice_number)							AS pedidos_anio,
		COUNT(DISTINCT f.cliente_id)								AS cliente_anio,
		ROUND(LAG(SUM(f.total_linea)) OVER (ORDER BY d.anio), 2)	AS ingresos_anterior
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	WHERE f.is_cancelled = 0
	GROUP BY d.anio
)
SELECT
	anio,
	ingresos_actual		AS ingresos_anio,
	pedidos_anio,
	cliente_anio,
	ingresos_anterior			AS ingresos_anio_anterior,
	ROUND(ingresos_actual - ingresos_anterior,2)	AS  variacion_absoluta,
	ROUND( 100.0*(ingresos_actual - ingresos_anterior)
		/NULLIF(ingresos_anterior,0),2)			AS crecimiento_yoy_pct
FROM ingresos_por_anio
ORDER BY anio;
GO

-- ============================================================
-- CONSULTA 03
-- Pregunta	: ¿Cual es la tendencia mensual y acumulada de ingresos?
-- Tecnica	: CTE + SUM() OVER (ACUMULADO) + LAG() con offset por Particion
-- Grafico	: 1. lineas comparativas (Mes vs Año Ant)
--			  2. Area (Acumulado Anual)
-- ============================================================

WITH ingresos_base_mensual AS (
	SELECT 
		d.anio,
		d.mes,
		d.mes_nombre,
		ROUND(SUM(f.total_linea),2)			AS ingresos_mes,
		COUNT(DISTINCT f.invoice_number)	AS pedidos_mes
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	WHERE f.is_cancelled = 0
	GROUP BY d.anio, d.mes, d.mes_nombre
)
SELECT
	anio,
	mes,
	mes_nombre,
	ingresos_mes,
	pedidos_mes,
	-- Acumulado limpio por año (Running Total)
	ROUND(SUM(ingresos_mes) OVER (
		PARTITION BY anio
		ORDER BY mes
		ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2)	AS ingresos_acumulado_anio,
	ROUND(LAG(ingresos_mes,1) OVER (
		PARTITION BY mes ORDER BY anio), 2)						AS ingresos_mismo_mes_anio_ant
FROM ingresos_base_mensual
ORDER BY anio, mes;
GO

-- ============================================================
-- CONSULTA 04
-- Pregunta	: ¿Los fines de semana venden mas o menos?
-- Tecnica	: Agregacion condicional por dia de semana
-- Grafico	: Barras por dia de semana(Color distinto fin de semana)
-- ============================================================

SELECT
	d.dia_semana,
	d.nombre_dia,
	CASE 
		WHEN d.es_fin_semana = 1 THEN 'Fin de semana' 
		Else 'Dia laboral' END							AS tipo_dia,
	COUNT(DISTINCT f.invoice_number)					AS pedidos,
	ROUND(SUM(f.total_linea), 2)						AS ingreso_total,
	ROUND(SUM(f.total_linea)
		/NULLIF(COUNT(DISTINCT f.invoice_number),0),2)	AS ticket_promedio_real,
	SUM(f.cantidad)										AS unidades_fisicas_vendidas,
	COUNT(*)											AS lineas_vendidas
FROM fact_ventas f
JOIN dim_fecha d ON f.fecha_id = d.fecha_id
WHERE f.is_cancelled=0
GROUP BY d.dia_semana, d.nombre_dia, d.es_fin_semana
ORDER BY d.dia_semana;
GO

-- ============================================================
-- GRUPO 2 — ANALISIS DE VENTAS
-- ============================================================

-- ============================================================
-- CONSULTA 05
-- Pregunta	: ¿Cuales son los meses de mayor y menor venta?
-- Tecnica	: CTE + RANK() para clasificar meses por ingresos
-- Grafico	: Matriz Heatmap(meses en columnas, años en filas)
-- ============================================================

WITH ingresos_mensuales AS (
	SELECT
		d.anio,
		d.mes,
		d.mes_nombre,
		ROUND(SUM(f.total_linea), 2) AS ingresos_mes,
		COUNT(DISTINCT f.invoice_number) AS pedidos_mes
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	WHERE f.is_cancelled = 0
	GROUP BY d.anio, d.mes, d.mes_nombre
)
SELECT
	anio,
	mes,
	mes_nombre,
	ingresos_mes,
	pedidos_mes,
	RANK() OVER (
		PARTITION BY anio
		ORDER BY ingresos_mes DESC)			AS ranking_en_anio,
	RANK() OVER (
		ORDER BY ingresos_mes DESC)			AS ranking_global
FROM ingresos_mensuales
ORDER BY anio, mes;
GO

-- ============================================================
-- CONSULTA 06
-- Pregunta	: ¿Cual es el ticket promedio por trimestre?
-- Tecnica	: CTE para calcular ticket a nivel de factura,
--			  luego promedio y extremos por trimestre
-- Grafico	: Barras (Ingresos) y Línea (Ticket Promedio)
-- ============================================================

WITH ticket_por_factura AS (
	SELECT
		f.invoice_number,
		d.anio,
		d.trimestre,
		SUM(f.total_linea) AS total_factura
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	WHERE f.is_cancelled = 0
	GROUP BY f.invoice_number, d.anio, d.trimestre
)
SELECT
	anio,
	trimestre,
	-- Creamos una etiqueta limpia para Power BI
	CONCAT(anio, '-Q', trimestre)			AS periodo_completo,
	COUNT(invoice_number)					AS total_pedidos,
	ROUND(SUM(total_factura), 2)			AS ingresos_trimestre,
	ROUND(AVG(total_factura), 2)			AS ticket_promedio,
	ROUND(MAX(total_factura), 2)			AS ticket_maximo,
	ROUND(MIN(total_factura), 2)			As ticket_minimo
FROM ticket_por_factura
GROUP BY anio, trimestre
ORDER BY anio, trimestre
GO

-- ============================================================
-- CONSULTA 07
-- Pregunta: ¿Que proporcion de los ingresos totales representan
--			las cancelaciones vs las ventas reales?
-- Tecnica: CTE + Agregacion condicional con ABS() y Ratios
-- Grafico: Columnas apiladas al 100%(Ventas vs Cancelaciones)
-- ============================================================
WITH base_cancelaciones AS (
	SELECT
		d.anio,
		-- Dinero de ventas normales
		ROUND(SUM(CASE WHEN f.is_cancelled = 0
					THEN f.total_linea ELSE 0 END), 2)		AS ingresos_ventas,
		-- Volumen de dinero devuelto (En positivo gracias a ABS)
		ROUND(ABS(SUM(CASE WHEN f.is_cancelled = 1
					THEN f.total_linea ELSE 0 END)), 2)		AS impacto_cancelaciones,
		-- Conteo de facturas
		COUNT(DISTINCT CASE WHEN f.is_cancelled = 0
				THEN f.invoice_number END)					AS pedidos_normales,
		COUNT(DISTINCT CASE WHEN f.is_cancelled = 1
				THEN f.invoice_number END)					AS pedidos_cancelados,
		COUNT(DISTINCT f.invoice_number)					AS total_pedidos
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	GROUP BY d.anio
)
SELECT
	anio,
	ingresos_ventas,
	impacto_cancelaciones,
	pedidos_normales,
	pedidos_cancelados,
	-- Metrica Operativa: Proporcion de clientes que devuelven
	ROUND(
		100.0 * pedidos_cancelados/NULLIF(total_pedidos,0), 2)	AS tasa_cancelacion_pedidos_pct,
	-- Metrica financiera: Proporcion de dinero perdido (La respuesta a la pregunta)
	ROUND(
		100.0 * impacto_cancelaciones
		/ NULLIF(ingresos_ventas + impacto_cancelaciones, 0), 2)	AS impacto_economico_pct
FROM base_cancelaciones
ORDER BY anio;
GO

-- ============================================================
-- CONSULTA 08
-- Pregunta	:¿A que hora del dia se generan mas ventas y pedidos?
-- Tecnica	: CTE + Porcentaje dinamico con OVER() (Modelo optimizado sin JOIN)
-- Grafico	: Grafico de lineas (Curva horaria) o Matriz Heatmap
-- ============================================================

WITH base_horas AS (
	SELECT
		f.hora_venta						AS hora_dia,
		COUNT(DISTINCT f.invoice_number)	AS pedidos_hora,
		ROUND(SUM(f.total_linea), 2)		AS ingresos_hora
	FROM fact_ventas f
	WHERE f.is_cancelled = 0
	GROUP BY f.hora_venta
)
SELECT
	hora_dia,
	pedidos_hora												AS pedidos,
	ingresos_hora												AS ingresos,
	ROUND(ingresos_hora/NULLIF(pedidos_hora, 0), 2)				AS ticket_promedio_real,
	ROUND( 100.0 * pedidos_hora/SUM(pedidos_hora) OVER(), 2)	AS pct_pedidos
FROM base_horas
ORDER BY hora_dia;
GO

-- ============================================================
-- GRUPO 3 - CLIENTES Y SEGMENTACION
-- ============================================================

-- ============================================================
-- CONSULTA 09
-- Pregunta	: ¿Cuanto aporta cada segmento de cliente al negocio?
-- Tecnica	: CTE + Porcentaje del total dinamico con OVER()
-- Grafico	: Treemap (% de ingresos) + Barras (Ingreso Total vs Por cliente)
-- ============================================================

WITH base_segmento AS (
	SELECT
		c.segmento,
		COUNT(DISTINCT c.cliente_id)		AS total_clientes,
		COUNT(DISTINCT f.invoice_number)	AS total_pedidos,
		ROUND(SUM(f.total_linea), 2)		AS ingresos_totales
	FROM fact_ventas f
	JOIN dim_cliente c ON f.cliente_id = c.cliente_id
	WHERE f.is_cancelled = 0
	GROUP BY c.segmento
)
SELECT
	segmento,
	total_clientes,
	total_pedidos,
	ingresos_totales,
	-- Metrica 1: Eficiencia de compra (Ticket Promedio Real)
	ROUND(ingresos_totales/NULLIF(total_pedidos, 0), 2)		AS ticket_promedio_real,
	-- Metrica 2: Valor del cliente en el segmento
	ROUND(ingresos_totales/NULLIF(total_clientes, 0), 2)	AS ingreso_por_cliente,
	-- Metrica 3: Peso del segmento sobre la empresa global
	ROUND(100.0 * ingresos_totales/SUM(ingresos_totales) OVER(), 2)	AS pct_ingresos_global
FROM base_segmento
ORDER BY ingresos_totales DESC;
GO

-- ============================================================
-- CONSULTA 10
-- Pregunta	: ¿Quienes son los top 10 clientes por ingresos?
-- Tecnica : CTE + ROW_NUMBER() para ranking estricto sin empates
-- Grafico	: Barras horizontales (Top 10)
-- ============================================================

WITH base_clientes AS(
	SELECT
		c.customer_id,
		c.segmento,
		c.country							AS pais,
		ROUND(SUM(f.total_linea), 2)		AS ingresos_totales,
		COUNT(DISTINCT f.invoice_number)	AS total_pedidos
	FROM fact_ventas f
	JOIN dim_cliente c ON f.cliente_id = c.cliente_id
	WHERE f.is_cancelled = 0
		-- Filtramos eventos genericos para no ensuciar el Top 10
		AND c.customer_id <> 'UNKNOWN'
	GROUP BY c.customer_id, c.segmento, c.country
)
SELECT TOP 10
	ROW_NUMBER() OVER (ORDER BY ingresos_totales DESC)	AS ranking,
	customer_id,
	segmento,
	pais,
	ingresos_totales,
	total_pedidos,
	-- El verdadero ticket promedio por factura para este cliente
	ROUND(ingresos_totales/NULLIF(total_pedidos, 0), 2)	AS ticket_promedio_real
FROM base_clientes
ORDER BY ingresos_totales DESC;
GO

-- ============================================================
-- CONSULTA 11
-- Pregunta	: ¿Como es la curva de adquisicion de nuevos clientes por mes?
-- Tecnica	: CTE + Windows Function (Acumulado) + Limpieza de joins
-- Grafico	: Barras (Nuevos) + Linea (Acumulado)
-- ============================================================

WITH primera_compra AS (
	SELECT
		f.cliente_id,
		MIN(d.fecha_completa) AS fecha_primera_compra
	FROM fact_ventas f
	JOIN dim_fecha d ON f.fecha_id = d.fecha_id
	WHERE f.is_cancelled = 0
	GROUP BY f.cliente_id
),
calendario_adquisicion AS(
	SELECT
		-- Normalizamos la fecha al inicio de cada mes
		FORMAT(fecha_primera_compra, 'yyyy-MM') AS periodo_mes,
		COUNT(cliente_id)						AS clientes_nuevos
		FROM primera_compra
		GROUP BY FORMAT(fecha_primera_compra, 'yyyy-MM')
)
SELECT
	periodo_mes,
	clientes_nuevos,
	--Acumulado usando la funcion de ventana
	SUM(clientes_nuevos) OVER (ORDER BY periodo_mes) AS clientes_acumulados
FROM calendario_adquisicion
ORDER BY periodo_mes;
GO

-- ============================================================
-- CONSULTA 12
-- Pregunta	: ¿Que porcentaje de clientes son recurrentes y como varia por segmento?
-- Tecnica	: CTE + Agregacion condicional por segmento
-- Grafica	: KPI cart (Total) + Barras apiladas (Por segmento)
-- ============================================================

WITH pedidos_por_cliente AS (
	SELECT
		c.customer_id,
		c.segmento,
		COUNT(DISTINCT f.invoice_number)	AS num_pedidos,
		ROUND(SUM(f.total_linea), 2)		AS ingresos_cliente
	FROM fact_ventas f
	JOIN dim_cliente c ON f.cliente_id = c.cliente_id
	WHERE f.is_cancelled = 0
		AND c.customer_id <> 'UNKNOWN'
	GROUP BY c.customer_id, c.segmento
)
SELECT
	segmento,
	COUNT(*)											AS total_clientes,
	SUM(CASE WHEN num_pedidos = 1 THEN 1 ELSE 0 END)	AS clientes_unicos,
	SUM(CASE WHEN num_pedidos > 1 THEN 1 ELSE 0 END)	AS clientes_recurrentes,
	-- % de recurrencia por segmento
	ROUND(100.0 * SUM(CASE WHEN num_pedidos > 1 THEN 1 ELSE 0 END)
		/NULLIF(COUNT(*), 0), 2)						AS pct_recurrentes,
	ROUND(AVG(CAST(num_pedidos AS FLOAT)), 2)			AS pedidos_promedio,
	ROUND(AVG(ingresos_cliente), 2)						AS ingresos_promedio_cliente
FROM pedidos_por_cliente
GROUP BY segmento
ORDER BY pct_recurrentes DESC;
GO

-- ============================================================
-- GRUPO 4 - PRODUCTOS
-- ============================================================

-- ============================================================
-- CONSULTA 13
-- Pregunta	: ¿Cuales son los 10 productos estrella por ingresos?
-- Tecnica	: CTE + RANK() doble para analisis comparativo
-- Grafico	: Barras horizontales (Top 10 Ingresos)
-- ============================================================

WITH metricas_producto AS (
	SELECT
		p.stock_code,
		p.descripcion,
		p.precio_referencia,
		SUM(f.cantidad)						AS unidades_vendidas,
		ROUND(SUM(f.total_linea), 2)		AS ingresos_totales,
		COUNT(DISTINCT f.invoice_number)	AS pedidos_con_producto,
		COUNT(DISTINCT f.cliente_id)		AS clientes_distintos
	FROM fact_ventas f
	JOIN dim_producto p ON f.producto_id = p.producto_id
	WHERE f.is_cancelled = 0
	GROUP BY p.stock_code, p.descripcion, p.precio_referencia
)
SELECT TOP 10
	RANK() OVER (ORDER BY ingresos_totales DESC)	AS ranking_ingresos,
	RANK() OVER (ORDER BY unidades_vendidas DESC)	AS ranking_unidades,
	descripcion,
	precio_referencia,
	unidades_vendidas,
	ingresos_totales,
	-- que% de los ingresos totales de la empresa aporrta este producto?
	ROUND(100.0*ingresos_totales
		/NULLIF(SUM(ingresos_totales) OVER (), 0), 2)	AS pct_ingresos_global
FROM metricas_producto
ORDER BY ingresos_totales DESC;
GO

-- ============================================================
-- CONSULTA 14
-- Pregunta	: ¿Cuales son los productos con mayor tasa de devolucion?
-- Tecnica	: Analisis de tasa de error vs volumen de ventas
-- Grafico	: Barras horizontales (Productos problematicos)
-- ============================================================

SELECT TOP 15
	p.stock_code,
	p.descripcion,
	SUM(CASE WHEN f.is_cancelled = 0 THEN f.cantidad ELSE 0 END)		AS unidades_vendidas,
	ABS(SUM(CASE WHEN f.is_cancelled = 1 THEN f.cantidad ELSE 0 END))	AS unidades_devueltas,
	-- Tasa de devolucion (Unidades devueltas/unidades vendidas)
	ROUND(100.0*ABS(SUM(CASE WHEN f.is_cancelled = 1 THEN f.cantidad ELSE 0 END))
		/NULLIF(SUM(CASE WHEN f.is_cancelled = 0 THEN f.cantidad ELSE 0 END), 0), 2)	AS tasa_devolucion_pct
FROM fact_ventas f
JOIN dim_producto p ON f.producto_id = p.producto_id
GROUP BY p.stock_code, p.descripcion
-- Filtramos para asegurar que solo analizamos productos con movimiento y al menos una devolucion
HAVING SUM(CASE WHEN f.is_cancelled = 1 THEN 1 ELSE 0 END) >0
	AND SUM(CASE WHEN f.is_cancelled = 0 THEN f.cantidad ELSE 0 END)>10
ORDER BY tasa_devolucion_pct DESC;
GO

-- ============================================================
-- CONSULTA 15
-- Pregunta	:¿Que productos generan el 80% de los ingresos? (Analisis Pareto)
-- Tecnica	: CTE + Window Function (Acumulado) + Etiquetado condicional
-- Grafico	: Pareto Chart (Barras Ingresos + Linea Acumulada)
-- ============================================================

WITH ingresos_producto AS (
	SELECT
		p.stock_code,
		p.descripcion,
		ROUND(SUM(f.total_linea), 2) AS ingresos
	FROM fact_ventas f
	JOIN dim_producto p ON f.producto_id = p.producto_id
	WHERE f.is_cancelled = 0
	GROUP BY p.stock_code, p.descripcion
),
pareto_calc AS (
	SELECT
		stock_code,
		descripcion,
		ingresos,
		-- % acumulado de ingresos
		ROUND( 100.0*SUM(ingresos) OVER (ORDER BY ingresos DESC)
		/NULLIF(SUM(ingresos) OVER (), 0), 2) AS pct_acumulado,
		ROW_NUMBER() OVER (ORDER BY ingresos DESC) AS ranking
	FROM ingresos_producto
)
SELECT
	ranking,
	stock_code,
	descripcion,
	ingresos,
	pct_acumulado,
	CASE WHEN pct_acumulado <= 80 THEN 'A - Top 80% Ingresos'
		ELSE 'B - Cola (20% restante)'
	END AS categoria_pareto
FROM pareto_calc
ORDER BY ranking;
GO

-- ============================================================
-- CONSULTA 16
-- Pregunta	: ¿Como se desvia el precio real de venta frente al de referencia?
-- Tecnica	: Analisis de varianza de precios con filtros estadisticos
-- Grafico	: Scatter Plot (Precio Ref vs Precio Real)
-- ============================================================

WITH analisis_precios AS (
	SELECT
		p.stock_code,
		p.descripcion,
		p.precio_referencia,
		AVG(f.precio_unitario)			AS precio_promedio_real,
		SUM(f.cantidad)					AS unidades_vendidas,
		SUM(f.total_linea)				AS ingresos_totales,
		COUNT(*)						AS transacciones
	FROM fact_ventas f
	JOIN dim_producto p ON f.producto_id = p.producto_id
	WHERE f.is_cancelled = 0
		AND p.precio_referencia > 0
	GROUP BY p.stock_code, p.descripcion, p.precio_referencia
	having count(*) >= 10
)
SELECT TOP 20
	stock_code,
	descripcion,
	precio_referencia,
	ROUND(precio_promedio_real, 2)							AS precio_promedio_real,
	ROUND(precio_promedio_real - precio_referencia, 2)		AS diferencia_precio,
	ROUND(100.0*(precio_promedio_real - precio_referencia)
	/NULLIF(precio_referencia, 0), 2)						AS variacion_pct,
	-- Clasificador rapido para el dashboard
	CASE 
		WHEN precio_promedio_real < precio_referencia THEN 'Descuento'
		WHEN precio_promedio_real > precio_referencia THEN 'Sobreprecio'
		ELSE 'Exacto'
	END AS estado_precio
FROM analisis_precios
ORDER BY ABS(precio_promedio_real - precio_referencia) DESC;
GO

-- ============================================================
-- GRUPO 5 - GEOGRAFIA Y TENDENCIAS
-- ============================================================-- 

-- ============================================================-- 
-- CONSULTA 17
-- Pregunta	: ¿Como contribuye cada pais a los ingresos globales y regionales?
-- Tecnica	: Windows Functions con Partition BY (Analisis Jerarquico)
-- Grafico	: Mapa interactivo + Barras drill-down (Region -> Pais)
-- ============================================================-- 

SELECT
	g.region,
	g.country,
	COUNT(DISTINCT f.invoice_number)				AS pedidos,
	COUNT(DISTINCT f.cliente_id)					AS clientes,
	ROUND(SUM(f.total_linea), 2)					AS ingresos_totales,
	-- Ticket promedio real por factura
	ROUND(SUM(f.total_linea)/NULLIF(COUNT(DISTINCT f.invoice_number), 0), 2)		AS ticket_promedio_real,
	-- % de ingfresos sobre el total global
	ROUND(100.0*SUM(f.total_linea)
	/NULLIF(SUM(SUM(f.total_linea)) OVER (), 0), 2)		AS pct_ingresos_global,
	-- % de ingresos dentro de la region (Uso de Partition by)
	ROUND(100.0*SUM(f.total_linea)
	/NULLIF(SUM(SUM(f.total_linea)) OVER (PARTITION BY g.region),0), 2)			AS pct_ingresos_region
FROM fact_ventas f
JOIN dim_geografia g ON f.geografia_id = g.geografia_id
WHERE f.is_cancelled = 0
GROUP BY g.region, g.country
ORDER BY region ASC, ingresos_totales DESC;
GO

-- ============================================================
-- CONSULTA 18
-- Pregunta  : ¿Cuales son los 3 productos estrella por cada pais?
-- Tecnica   : Window Function (ROW_NUMBER) con particionamiento geografico
-- Grafico   : Matriz (Pais vs Top 3 Productos)
-- ============================================================

WITH ranking_pais_producto AS (
    SELECT
        g.country                               AS pais,
        p.descripcion,
        ROUND(SUM(f.total_linea), 2)            AS ingresos,
        SUM(f.cantidad)                         AS unidades,
        -- Ranking reiniciable por país
        ROW_NUMBER() OVER (
            PARTITION BY g.country
            ORDER BY SUM(f.total_linea) DESC
        )                                       AS ranking
    FROM fact_ventas f
    JOIN dim_geografia g ON f.geografia_id = g.geografia_id
    JOIN dim_producto  p ON f.producto_id  = p.producto_id
    WHERE f.is_cancelled = 0
    GROUP BY g.country, p.descripcion
)
SELECT
    pais,
    ranking,
    descripcion,
    ingresos,
    unidades
FROM ranking_pais_producto
WHERE ranking <= 3
ORDER BY pais ASC, ranking ASC;
GO

-- ============================================================
-- CONSULTA 19
-- Pregunta  : ¿Cual es el crecimiento YoY (Año contra Año) por region?
-- Tecnica   : CTE + LAG() con PARTITION BY (Analisis de tendencia)
-- Grafico   : Grafico de lineas multiples (Evolucion de ingresos)
-- ============================================================

WITH ingresos_region_anio AS (
    SELECT
        g.region,
        d.anio,
        ROUND(SUM(f.total_linea), 2) AS ingresos_anio
    FROM fact_ventas f
    JOIN dim_geografia g ON f.geografia_id = g.geografia_id
    JOIN dim_fecha d     ON f.fecha_id     = d.fecha_id
    WHERE f.is_cancelled = 0
    GROUP BY g.region, d.anio
),
comparativa_yoy AS (
    SELECT
        region,
        anio,
        ingresos_anio,
        -- Extraemos el dato del año anterior usando LAG
        LAG(ingresos_anio) OVER (PARTITION BY region ORDER BY anio) AS ingresos_anio_ant
    FROM ingresos_region_anio
)
SELECT
    region,
    anio,
    ingresos_anio,
    ingresos_anio_ant,
    -- Crecimiento YoY (Year-over-Year)
    ROUND(
        100.0 * (ingresos_anio - ingresos_anio_ant) 
        / NULLIF(ingresos_anio_ant, 0)
    , 2) AS crecimiento_yoy_pct
FROM comparativa_yoy
ORDER BY region, anio;
GO

-- ============================================================
-- CONSULTA 20
-- Pregunta  : ¿Cuál es el análisis RFM (Recency, Frequency, Monetary) de clientes?
-- Técnica   : CTE multi-paso + NTILE para segmentación en quintiles
-- Gráfico   : Treemap de Segmentos o Bubble Chart (R vs F, tamaño M)
-- ============================================================

WITH fecha_max AS (
    SELECT MAX(fecha_completa) AS fecha_ref
    FROM dim_fecha
),
rfm_base AS (
    SELECT
        c.customer_id,
        c.segmento,
        -- R: días desde la última compra
        DATEDIFF(DAY, MAX(d.fecha_completa), (SELECT fecha_ref FROM fecha_max)) AS recency_dias,
        -- F: número de facturas distintas
        COUNT(DISTINCT f.invoice_number)                                          AS frequency,
        -- M: ingresos totales
        ROUND(SUM(f.total_linea), 2)                                              AS monetary
    FROM fact_ventas f
    JOIN dim_cliente c ON f.cliente_id = c.cliente_id
    JOIN dim_fecha   d ON f.fecha_id   = d.fecha_id
    WHERE f.is_cancelled = 0
      AND c.customer_id <> 'UNKNOWN'
    GROUP BY c.customer_id, c.segmento
),
rfm_scores AS (
    SELECT
        customer_id,
        segmento,
        recency_dias,
        frequency,
        monetary,
        -- NTILE(5) asigna 1 al peor y 5 al mejor
        NTILE(5) OVER (ORDER BY recency_dias DESC)  AS r_score, 
        NTILE(5) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    segmento,
    recency_dias,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    
    -- El estándar de la industria es concatenar, no sumar
    CONCAT(r_score, f_score, m_score) AS rfm_codigo,
    
    -- Clasificación basada en el cruce de R y F (ignorando M para el segmento principal)
    CASE
        WHEN r_score IN (4, 5) AND f_score IN (4, 5) THEN 'Champions'
        WHEN r_score IN (3, 4, 5) AND f_score IN (3, 4) THEN 'Loyal Customers'
        WHEN r_score IN (4, 5) AND f_score IN (1, 2) THEN 'Promising / Recent'
        WHEN r_score IN (2, 3) AND f_score IN (1, 2) THEN 'Needs Attention'
        WHEN r_score IN (1, 2) AND f_score IN (3, 4, 5) THEN 'At Risk / Cant Lose Them'
        WHEN r_score = 1 AND f_score IN (1, 2) THEN 'Lost'
        ELSE 'Regulars'
    END AS rfm_segment
FROM rfm_scores
ORDER BY rfm_codigo DESC;
GO