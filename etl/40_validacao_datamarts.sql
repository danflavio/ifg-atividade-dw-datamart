-- =====================================================================
-- VALIDAÇÃO DOS DATAMARTS (Fase 4)
-- =====================================================================
SET search_path TO dm_vendas, dm_suprimentos, dm_logistica, dw, public;

\echo '--- D1) Fatos: DW x DataMart (devem ser iguais) ---'
SELECT 'dm_vendas.fato_vendas'          AS objeto,
       (SELECT count(*) FROM dw.fato_vendas)          AS no_dw,
       (SELECT count(*) FROM dm_vendas.fato_vendas)   AS no_dm
UNION ALL SELECT 'dm_suprimentos.fato_compras',
       (SELECT count(*) FROM dw.fato_compras), (SELECT count(*) FROM dm_suprimentos.fato_compras)
UNION ALL SELECT 'dm_logistica.fato_entregas',
       (SELECT count(*) FROM dw.fato_entregas), (SELECT count(*) FROM dm_logistica.fato_entregas)
ORDER BY 1;

\echo '--- D2) Orfaos nos DataMarts (0 esperado) ---'
SELECT 'dm_vendas -> produto'             AS fk, count(*) AS orfaos
  FROM dm_vendas.fato_vendas f
 WHERE NOT EXISTS (SELECT 1 FROM dm_vendas.dim_produto d WHERE d.sk_produto = f.sk_produto)
UNION ALL SELECT 'dm_vendas -> tempo', count(*)
  FROM dm_vendas.fato_vendas f
 WHERE NOT EXISTS (SELECT 1 FROM dm_vendas.dim_tempo d WHERE d.sk_tempo = f.sk_tempo_venda)
UNION ALL SELECT 'dm_suprimentos -> fornecedor', count(*)
  FROM dm_suprimentos.fato_compras f
 WHERE NOT EXISTS (SELECT 1 FROM dm_suprimentos.dim_fornecedor d WHERE d.sk_fornecedor = f.sk_fornecedor)
UNION ALL SELECT 'dm_logistica -> transportadora', count(*)
  FROM dm_logistica.fato_entregas f
 WHERE NOT EXISTS (SELECT 1 FROM dm_logistica.dim_transportadora d WHERE d.sk_transportadora = f.sk_transportadora)
ORDER BY 1;

\echo '--- D3) CONFORMIDADE entre DataMarts: mesmo membro = mesmos atributos (0 divergencias) ---'
SELECT 'produto (vendas x suprimentos)' AS dimensao, count(*) AS divergencias
  FROM dm_vendas.dim_produto a
  JOIN dm_suprimentos.dim_produto b USING (sk_produto)
 WHERE a.nome_produto IS DISTINCT FROM b.nome_produto
    OR a.preco_venda  IS DISTINCT FROM b.preco_venda
    OR a.versao       IS DISTINCT FROM b.versao
    OR a.flag_atual   IS DISTINCT FROM b.flag_atual
UNION ALL SELECT 'localidade (vendas x logistica)', count(*)
  FROM dm_vendas.dim_localidade a
  JOIN dm_logistica.dim_localidade b USING (sk_localidade)
 WHERE a.nm_cidade   IS DISTINCT FROM b.nm_cidade
    OR a.codigo_ibge IS DISTINCT FROM b.codigo_ibge
    OR a.populacao   IS DISTINCT FROM b.populacao
UNION ALL SELECT 'cliente (vendas x logistica) nas colunas comuns', count(*)
  FROM dm_vendas.dim_cliente a
  JOIN dm_logistica.dim_cliente b USING (sk_cliente)
 WHERE a.nome IS DISTINCT FROM b.nome OR a.pais IS DISTINCT FROM b.pais
UNION ALL SELECT 'tempo (vendas x logistica)', count(*)
  FROM dm_vendas.dim_tempo a
  JOIN dm_logistica.dim_tempo b USING (sk_tempo)
 WHERE a.data IS DISTINCT FROM b.data OR a.eh_feriado IS DISTINCT FROM b.eh_feriado
ORDER BY 1;

\echo '--- D4) RECORTE: membros carregados que nao sao usados (0 esperado) ---'
SELECT 'dm_vendas.dim_produto' AS dimensao, count(*) AS nao_usados
  FROM dm_vendas.dim_produto d
 WHERE NOT EXISTS (SELECT 1 FROM dm_vendas.fato_vendas f WHERE f.sk_produto = d.sk_produto)
UNION ALL SELECT 'dm_vendas.dim_vendedor', count(*)
  FROM dm_vendas.dim_vendedor d
 WHERE NOT EXISTS (SELECT 1 FROM dm_vendas.fato_vendas f WHERE f.sk_vendedor = d.sk_vendedor)
UNION ALL SELECT 'dm_suprimentos.dim_fornecedor', count(*)
  FROM dm_suprimentos.dim_fornecedor d
 WHERE NOT EXISTS (SELECT 1 FROM dm_suprimentos.fato_compras f WHERE f.sk_fornecedor = d.sk_fornecedor)
UNION ALL SELECT 'dm_logistica.dim_transportadora', count(*)
  FROM dm_logistica.dim_transportadora d
 WHERE NOT EXISTS (SELECT 1 FROM dm_logistica.fato_entregas f WHERE f.sk_transportadora = d.sk_transportadora)
ORDER BY 1;

\echo '--- D5) LGPD: dm_logistica.dim_cliente deve estar MINIMIZADA (0 esperado) ---'
SELECT count(*) AS colunas_sensiveis_presentes
  FROM information_schema.columns
 WHERE table_schema = 'dm_logistica'
   AND table_name   = 'dim_cliente'
   AND column_name IN ('cpf_cnpj_masked', 'faixa_renda', 'data_nascimento');

\echo '--- D6) SCD2 preservado no DataMart (informativo: 0 antes do teste, 3 depois) ---'
SELECT count(*)                              AS membros_produto,
       count(*) FILTER (WHERE NOT flag_atual) AS versoes_historicas
  FROM dm_vendas.dim_produto;

\echo '--- D7) Amostra de analise sobre o DataMart de Vendas ---'
SELECT p.nome_produto, p.categoria,
       sum(f.quantidade)            AS unidades,
       round(sum(f.vlr_liquido), 2) AS faturamento_brl
  FROM dm_vendas.fato_vendas f
  JOIN dm_vendas.dim_produto p USING (sk_produto)
 GROUP BY 1, 2
 ORDER BY 3 DESC
 LIMIT 5;
