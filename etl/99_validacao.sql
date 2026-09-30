-- =====================================================================
-- VALIDAÇÃO DO ETL - testes de integridade origem x DW
-- (um ETL sem testes é fé, não engenharia)
-- =====================================================================
SET search_path TO dw, public;

\echo '--- T1) Contagens: origem x DW (devem ser iguais) ---'
SELECT 'fato_vendas MERCEARIA'   AS item,
       (SELECT count(*) FROM itens_vendas)  AS na_origem,
       (SELECT count(*) FROM dw.fato_vendas WHERE origem='MERCEARIA') AS no_dw
UNION ALL SELECT 'fato_vendas NORTHWIND', (SELECT count(*) FROM order_details),
       (SELECT count(*) FROM dw.fato_vendas WHERE origem='NORTHWIND')
UNION ALL SELECT 'fato_compras', (SELECT count(*) FROM itens_compras),
       (SELECT count(*) FROM dw.fato_compras)
UNION ALL SELECT 'fato_entregas', (SELECT count(*) FROM orders),
       (SELECT count(*) FROM dw.fato_entregas)
UNION ALL SELECT 'dim_produto MERCEARIA', (SELECT count(*) FROM produtos),
       (SELECT count(*) FROM dw.dim_produto WHERE origem='MERCEARIA')
UNION ALL SELECT 'dim_produto NORTHWIND', (SELECT count(*) FROM products),
       (SELECT count(*) FROM dw.dim_produto WHERE origem='NORTHWIND')
UNION ALL SELECT 'dim_cliente MERCEARIA', (SELECT count(*) FROM pessoas WHERE tipo_pessoa IN (1,2)),
       (SELECT count(*) FROM dw.dim_cliente WHERE origem='MERCEARIA')
UNION ALL SELECT 'dim_cliente NORTHWIND', (SELECT count(*) FROM customers),
       (SELECT count(*) FROM dw.dim_cliente WHERE origem='NORTHWIND')
UNION ALL SELECT 'dim_fornecedor MERCEARIA', (SELECT count(*) FROM pessoas WHERE tipo_pessoa=3),
       (SELECT count(*) FROM dw.dim_fornecedor WHERE origem='MERCEARIA')
UNION ALL SELECT 'dim_fornecedor NORTHWIND', (SELECT count(*) FROM suppliers),
       (SELECT count(*) FROM dw.dim_fornecedor WHERE origem='NORTHWIND')
UNION ALL SELECT 'dim_vendedor', (SELECT count(*) FROM employees),
       (SELECT count(*) FROM dw.dim_vendedor)
UNION ALL SELECT 'dim_transportadora', (SELECT count(*) FROM shippers),
       (SELECT count(*) FROM dw.dim_transportadora)
UNION ALL SELECT 'dim_localidade BR (bairros Mercearia)', (SELECT count(*) FROM bairros),
       (SELECT count(*) FROM dw.dim_localidade WHERE id_bairro IS NOT NULL)
ORDER BY 1;

\echo '--- T2) Identidade das medidas e nulos indevidos (tudo deve ser 0) ---'
SELECT count(*)                                                          AS linhas,
       count(*) FILTER (WHERE vlr_bruto <> round(quantidade * vlr_unitario, 2)) AS erro_bruto,
       count(*) FILTER (WHERE vlr_liquido <> vlr_bruto - vlr_desconto)          AS erro_liquido,
       count(*) FILTER (WHERE vlr_liquido < 0 OR vlr_bruto < 0)                 AS valor_negativo,
       count(*) FILTER (WHERE sk_localidade IS NULL AND origem='MERCEARIA')     AS merce_sem_local,
       count(*) FILTER (WHERE sk_localidade IS NULL AND origem='NORTHWIND')     AS nw_sem_local,
       count(*) FILTER (WHERE sk_tempo_fatura IS NULL AND origem='NORTHWIND')   AS nw_sem_expedicao
FROM dw.fato_vendas;

\echo '--- T3) Câmbio aplicado e totais em BRL por origem ---'
SELECT origem, moeda_origem, count(*) AS linhas,
       count(*) FILTER (WHERE taxa_cambio IS NULL) AS sem_taxa,
       round(min(taxa_cambio), 4) AS taxa_min,
       round(max(taxa_cambio), 4) AS taxa_max,
       round(sum(vlr_liquido), 2) AS total_liquido_brl
FROM dw.fato_vendas
GROUP BY 1, 2
ORDER BY 1;

\echo '--- T4) Registros órfãos (as FKs já impedem; teste de regressão) ---'
SELECT 'fato_vendas -> dim_cliente'      AS fk, count(*) AS orfaos
  FROM dw.fato_vendas f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_cliente d WHERE d.sk_cliente = f.sk_cliente)
UNION ALL SELECT 'fato_vendas -> dim_produto', count(*)
  FROM dw.fato_vendas f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_produto d WHERE d.sk_produto = f.sk_produto)
UNION ALL SELECT 'fato_vendas -> dim_tempo', count(*)
  FROM dw.fato_vendas f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_tempo d WHERE d.sk_tempo = f.sk_tempo_venda)
UNION ALL SELECT 'fato_compras -> dim_fornecedor', count(*)
  FROM dw.fato_compras f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_fornecedor d WHERE d.sk_fornecedor = f.sk_fornecedor)
UNION ALL SELECT 'fato_entregas -> dim_transportadora', count(*)
  FROM dw.fato_entregas f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_transportadora d WHERE d.sk_transportadora = f.sk_transportadora)
ORDER BY 1;

\echo '--- T5) SCD2: exatamente UMA versão vigente por chave natural ---'
SELECT origem, count(*) AS chaves, count(*) FILTER (WHERE qtd_atual = 1) AS ok_uma_vigente
FROM (
    SELECT origem,
           COALESCE(id_produto::text, product_id::text) AS chave,
           count(*) FILTER (WHERE flag_atual)           AS qtd_atual
    FROM dw.dim_produto
    GROUP BY 1, 2
) t
GROUP BY 1
ORDER BY 1;

\echo '--- T6) Integração dos dados externos na dimensão ---'
SELECT count(*) AS cidades_br_na_dim,
       count(*) FILTER (WHERE codigo_ibge IS NOT NULL) AS com_codigo_ibge,
       count(*) FILTER (WHERE populacao  IS NOT NULL)  AS com_populacao
FROM dw.dim_localidade WHERE pais = 'Brasil';
