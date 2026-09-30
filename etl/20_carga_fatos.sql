-- =====================================================================
-- ETL - CARGA DOS FATOS (schema dw)
-- ---------------------------------------------------------------------
-- fato_vendas  : grão = ITEM de venda/pedido  (Mercearia + Northwind)
-- fato_compras : grão = ITEM de compra        (Mercearia)
-- fato_entregas: grão = PEDIDO/ENTREGA        (Northwind)
--
-- MOEDA: todas as medidas ficam em BRL.
--   * Mercearia já é BRL  -> taxa_cambio = NULL
--   * Northwind é USD     -> converte pela PTAX de COMPRA do dia
--     (ext.cotacao_dolar_dia, com carry forward) e grava a taxa usada.
--   Regra de arredondamento (garante a identidade da linha):
--     vlr_unitario = round(unit_price_usd * taxa, 2)
--     vlr_bruto    = round(quantidade * vlr_unitario, 2)
--     vlr_desconto = round(vlr_bruto * pct_desconto, 2)
--     vlr_liquido  = vlr_bruto - vlr_desconto
-- =====================================================================
SET search_path TO dw, public;

BEGIN;

-- ---------------------------------------------------------------------
-- 1) FATO_VENDAS - Mercearia (BRL, sem desconto na origem)
--    Localidade = endereço PREFERENCIAL do cliente (bairro)
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_vendas (num_pedido, origem, moeda_origem, taxa_cambio,
                            sk_tempo_venda, sk_tempo_fatura, sk_cliente,
                            sk_produto, sk_localidade, sk_vendedor,
                            quantidade, vlr_unitario, pct_desconto,
                            vlr_bruto, vlr_desconto, vlr_liquido)
SELECT v.ID_VENDA::text,
       'MERCEARIA',
       'BRL',
       NULL,
       to_char(v.DATA_VENDA, 'YYYYMMDD')::int,
       CASE WHEN v.DATA_FATURAMENTO IS NULL THEN NULL
            ELSE to_char(v.DATA_FATURAMENTO, 'YYYYMMDD')::int END,
       dc.sk_cliente,
       dp.sk_produto,
       dl.sk_localidade,
       NULL,                                    -- Mercearia não tem vendedor
       i.QUANTIDADE,
       round(i.VLR_UNITARIO::numeric, 2),
       0,                                       -- sem desconto na origem
       round(i.QUANTIDADE * i.VLR_UNITARIO::numeric, 2),
       0,
       round(i.QUANTIDADE * i.VLR_UNITARIO::numeric, 2)
FROM Itens_Vendas i
JOIN Vendas v      ON v.ID_VENDA = i.ID_VENDA
JOIN dw.dim_cliente dc
     ON dc.origem = 'MERCEARIA' AND dc.id_pessoa = v.ID_PESSOA AND dc.flag_atual
JOIN dw.dim_produto dp
     ON dp.origem = 'MERCEARIA' AND dp.id_produto = i.ID_PRODUTO AND dp.flag_atual
LEFT JOIN LATERAL (
    SELECT l.ID_BAIRRO
    FROM Enderecos e
    JOIN Logradouros l ON l.ID_LOGRADOURO = e.ID_LOGRADOURO
    WHERE e.ID_PESSOA = v.ID_PESSOA AND e.PREFERENCIAL = B'1'
    LIMIT 1
) end_cli ON TRUE
LEFT JOIN dw.dim_localidade dl ON dl.id_bairro = end_cli.ID_BAIRRO;

-- ---------------------------------------------------------------------
-- 2) FATO_VENDAS - Northwind (USD -> BRL pela PTAX do dia)
-- ---------------------------------------------------------------------
WITH base AS (
    SELECT o.order_id,
           o.order_date,
           o.shipped_date,
           o.customer_id,
           o.employee_id,
           o.ship_city,
           o.ship_region,
           COALESCE(pn.nome_padronizado, o.ship_country) AS pais_destino,
           od.product_id,
           od.quantity,
           od.discount::numeric                AS pct_desconto,
           round(od.unit_price::numeric * c.cotacao_compra, 2) AS vlr_unitario,
           c.cotacao_compra                    AS taxa_cambio
    FROM order_details od
    JOIN orders o                 ON o.order_id = od.order_id
    JOIN ext.cotacao_dolar_dia c  ON c.data = o.order_date
    LEFT JOIN ext.pais_nome pn    ON pn.nome_origem = o.ship_country
)
INSERT INTO dw.fato_vendas (num_pedido, origem, moeda_origem, taxa_cambio,
                            sk_tempo_venda, sk_tempo_fatura, sk_cliente,
                            sk_produto, sk_localidade, sk_vendedor,
                            quantidade, vlr_unitario, pct_desconto,
                            vlr_bruto, vlr_desconto, vlr_liquido)
SELECT b.order_id::text,
       'NORTHWIND',
       'USD',
       b.taxa_cambio,
       to_char(b.order_date, 'YYYYMMDD')::int,
       CASE WHEN b.shipped_date IS NULL THEN NULL
            ELSE to_char(b.shipped_date, 'YYYYMMDD')::int END,
       dc.sk_cliente,
       dp.sk_produto,
       dl.sk_localidade,
       dv.sk_vendedor,
       b.quantity,
       b.vlr_unitario,
       b.pct_desconto,
       round(b.quantity * b.vlr_unitario, 2),
       round(round(b.quantity * b.vlr_unitario, 2) * b.pct_desconto, 2),
       round(b.quantity * b.vlr_unitario, 2)
         - round(round(b.quantity * b.vlr_unitario, 2) * b.pct_desconto, 2)
FROM base b
JOIN dw.dim_cliente dc
     ON dc.origem = 'NORTHWIND' AND dc.customer_id = b.customer_id AND dc.flag_atual
JOIN dw.dim_produto dp
     ON dp.origem = 'NORTHWIND' AND dp.product_id = b.product_id AND dp.flag_atual
LEFT JOIN dw.dim_vendedor dv ON dv.employee_id = b.employee_id
LEFT JOIN dw.dim_localidade dl
     ON unaccent(lower(dl.nm_cidade)) = unaccent(lower(b.ship_city))
    AND COALESCE(dl.sigla_uf, '') = COALESCE(b.ship_region, '')
    AND dl.pais = b.pais_destino
    AND dl.nm_bairro IS NULL;      -- membro no nível de CIDADE (sem bairro)

-- ---------------------------------------------------------------------
-- 3) FATO_COMPRAS - Mercearia (só ela tem compras)
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_compras (num_compra, sk_tempo_pedido, sk_tempo_entrada,
                             sk_produto, sk_fornecedor, quantidade,
                             vlr_unitario, vlr_bruto)
SELECT c.ID_COMPRA::text,
       to_char(c.DATA_PEDIDO, 'YYYYMMDD')::int,
       CASE WHEN c.DATA_ENTRADA IS NULL THEN NULL
            ELSE to_char(c.DATA_ENTRADA, 'YYYYMMDD')::int END,
       dp.sk_produto,
       df.sk_fornecedor,
       i.QUANTIDADE,
       round(i.VLR_UNITARIO::numeric, 2),
       round(i.QUANTIDADE * i.VLR_UNITARIO::numeric, 2)
FROM Itens_compras i
JOIN Compras c ON c.ID_COMPRA = i.ID_COMPRA
JOIN dw.dim_produto dp
     ON dp.origem = 'MERCEARIA' AND dp.id_produto = i.ID_PRODUTO AND dp.flag_atual
JOIN dw.dim_fornecedor df
     ON df.origem = 'MERCEARIA' AND df.id_pessoa = c.ID_PESSOA;

-- ---------------------------------------------------------------------
-- 4) FATO_ENTREGAS - Northwind, grão de PEDIDO (frete não é aditivo
--    no grão de item; por isso um fato separado no grão correto)
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_entregas (num_pedido, sk_tempo_pedido, sk_tempo_expedicao,
                              sk_cliente, sk_localidade, sk_transportadora,
                              vlr_frete, qtd_itens, prazo_dias)
SELECT o.order_id::text,
       to_char(o.order_date, 'YYYYMMDD')::int,
       CASE WHEN o.shipped_date IS NULL THEN NULL
            ELSE to_char(o.shipped_date, 'YYYYMMDD')::int END,
       dc.sk_cliente,
       dl.sk_localidade,
       dt.sk_transportadora,
       round(o.freight::numeric * c.cotacao_compra, 2),
       it.qtd_itens,
       CASE WHEN o.shipped_date IS NULL THEN NULL
            ELSE (o.shipped_date - o.order_date) END
FROM orders o
JOIN ext.cotacao_dolar_dia c ON c.data = o.order_date
LEFT JOIN dw.dim_cliente dc
     ON dc.origem = 'NORTHWIND' AND dc.customer_id = o.customer_id AND dc.flag_atual
LEFT JOIN ext.pais_nome pne ON pne.nome_origem = o.ship_country
LEFT JOIN dw.dim_localidade dl
     ON unaccent(lower(dl.nm_cidade)) = unaccent(lower(o.ship_city))
    AND COALESCE(dl.sigla_uf, '') = COALESCE(o.ship_region, '')
    AND dl.pais = COALESCE(pne.nome_padronizado, o.ship_country)
    AND dl.nm_bairro IS NULL      -- membro no nível de CIDADE (sem bairro)
LEFT JOIN dw.dim_transportadora dt ON dt.shipper_id = o.ship_via
LEFT JOIN (
    SELECT order_id, count(*) AS qtd_itens
    FROM order_details
    GROUP BY order_id
) it ON it.order_id = o.order_id;

COMMIT;

ANALYZE dw.fato_vendas, dw.fato_compras, dw.fato_entregas;

-- ---------------------------------------------------------------------
-- Conferência
-- ---------------------------------------------------------------------
SELECT 'fato_vendas'  AS fato, origem AS origem_ou_grupo, count(*) AS linhas,
       sum(vlr_liquido) AS total_liquido_brl
FROM dw.fato_vendas GROUP BY origem
UNION ALL
SELECT 'fato_compras', 'MERCEARIA', count(*), sum(vlr_bruto)
FROM dw.fato_compras
UNION ALL
SELECT 'fato_entregas', 'NORTHWIND', count(*), sum(vlr_frete)
FROM dw.fato_entregas
ORDER BY 1, 2;
