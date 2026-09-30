-- =====================================================================
-- TESTE DE HISTORICIDADE (SCD TIPO 2) - dw.dim_produto e dw.dim_cliente
-- ---------------------------------------------------------------------
-- Declarar "SCD Tipo 2" na DDL não prova nada. Este script DEMONSTRA:
--
--   1. simula uma mudança na fonte (preço de 3 produtos / renda de 2 clientes);
--   2. roda a atualização incremental das dimensões;
--   3. verifica que a versão antiga foi FECHADA (data_fim + flag_atual=FALSE);
--   4. verifica que uma NOVA versão foi aberta;
--   5. verifica que as VENDAS ANTIGAS continuam apontando para a versão
--      antiga  <- este é o ponto central da historicidade: o passado não
--      é reescrito quando o cadastro muda.
--
-- Observação: como este script altera a FONTE, ele é um teste destrutivo.
-- Para voltar ao estado limpo, rode novamente:
--   docker compose exec -T db sh /etl/00_carga_inicial.sh
-- =====================================================================
SET search_path TO dw, public;

\echo '=== PASSO 1) Simulando mudanca na fonte ==='
UPDATE Produtos SET VALOR_VENDA = round((VALOR_VENDA * 1.10)::numeric, 2)
 WHERE ID_PRODUTO IN (1, 2, 3);
UPDATE Pessoas  SET RENDA = RENDA * 1.5
 WHERE ID_PESSOA IN (1, 2);

SELECT 'produtos alterados' AS o_que, count(*) AS quantidade
  FROM Produtos WHERE ID_PRODUTO IN (1,2,3)
UNION ALL
SELECT 'clientes alterados', count(*) FROM Pessoas WHERE ID_PESSOA IN (1,2);

-- =====================================================================
-- PASSO 2) Atualização incremental da dim_produto (SCD Tipo 2)
-- =====================================================================
BEGIN;

-- estado atual da origem, no mesmo "formato" da dimensão
CREATE TEMP TABLE origem_produto ON COMMIT DROP AS
SELECT 'MERCEARIA'::varchar(10) AS origem,
       p.ID_PRODUTO             AS id_produto,
       NULL::smallint           AS product_id,
       p.PRODUTO                AS nome_produto,
       cat.NOME_CATEGORIA       AS categoria,
       round(p.VALOR_VENDA::numeric, 2) AS preco_venda,
       FALSE                    AS descontinuado
FROM Produtos p
JOIN Categorias cat ON cat.ID_CATEGORIA = p.ID_CATEGORIA
UNION ALL
SELECT 'NORTHWIND', NULL, p.product_id, p.product_name, c.category_name,
       round(p.unit_price::numeric, 2), COALESCE(p.discontinued, 0) <> 0
FROM products p
LEFT JOIN categories c ON c.category_id = p.category_id;

-- membros cujos atributos versionados MUDARAM
CREATE TEMP TABLE mudou ON COMMIT DROP AS
SELECT o.*, d.sk_produto AS sk_antigo, d.versao AS versao_antiga
FROM origem_produto o
JOIN dw.dim_produto d
  ON d.flag_atual
 AND d.origem = o.origem
 AND COALESCE(d.id_produto::text, d.product_id::text)
   = COALESCE(o.id_produto::text, o.product_id::text)
WHERE d.nome_produto IS DISTINCT FROM o.nome_produto
   OR d.categoria    IS DISTINCT FROM o.categoria
   OR d.preco_venda  IS DISTINCT FROM o.preco_venda
   OR d.descontinuado IS DISTINCT FROM o.descontinuado;

-- fecha as versões antigas
UPDATE dw.dim_produto d
   SET flag_atual = FALSE,
       data_fim   = CURRENT_DATE - 1
 WHERE d.sk_produto IN (SELECT sk_antigo FROM mudou);

-- abre as novas versões
INSERT INTO dw.dim_produto (id_produto, product_id, origem, nome_produto,
                            categoria, preco_venda, descontinuado, versao,
                            data_inicio, data_fim, flag_atual)
SELECT id_produto, product_id, origem, nome_produto, categoria, preco_venda,
       descontinuado, versao_antiga + 1, CURRENT_DATE, NULL, TRUE
FROM mudou;

COMMIT;

\echo '=== PASSO 3) dim_produto: versoes criadas ==='
SELECT sk_produto, id_produto, nome_produto, preco_venda, versao,
       data_inicio, data_fim, flag_atual
FROM dw.dim_produto
WHERE id_produto IN (1, 2, 3)
ORDER BY id_produto, versao;

-- =====================================================================
-- PASSO 4) Atualização incremental da dim_cliente (SCD Tipo 2)
-- =====================================================================
BEGIN;

CREATE TEMP TABLE origem_cliente ON COMMIT DROP AS
SELECT 'MERCEARIA'::varchar(10) AS origem,
       p.ID_PESSOA              AS id_pessoa,
       NULL::varchar(5)         AS customer_id,
       p.NOME                   AS nome,
       CASE
           WHEN p.TIPO_PESSOA = 2                THEN NULL
           WHEN p.RENDA IS NULL OR p.RENDA <= 0  THEN 'Não informado'
           WHEN p.RENDA <= 3000                  THEN 'Até R$ 3 mil'
           WHEN p.RENDA <= 7500                  THEN 'R$ 3 a 7,5 mil'
           WHEN p.RENDA <= 15000                 THEN 'R$ 7,5 a 15 mil'
           ELSE 'Acima de R$ 15 mil'
       END                      AS faixa_renda
FROM Pessoas p
WHERE p.TIPO_PESSOA IN (1, 2)
UNION ALL
SELECT 'NORTHWIND', NULL, c.customer_id, c.company_name, NULL
FROM customers c;

CREATE TEMP TABLE mudou_cli ON COMMIT DROP AS
SELECT o.*, d.sk_cliente AS sk_antigo, d.versao AS versao_antiga
FROM origem_cliente o
JOIN dw.dim_cliente d
  ON d.flag_atual
 AND d.origem = o.origem
 AND COALESCE(d.id_pessoa::text, d.customer_id)
   = COALESCE(o.id_pessoa::text, o.customer_id)
WHERE d.nome        IS DISTINCT FROM o.nome
   OR d.faixa_renda IS DISTINCT FROM o.faixa_renda;

UPDATE dw.dim_cliente d
   SET flag_atual = FALSE,
       data_fim   = CURRENT_DATE - 1
 WHERE d.sk_cliente IN (SELECT sk_antigo FROM mudou_cli);

INSERT INTO dw.dim_cliente (id_pessoa, customer_id, origem, nome,
                            faixa_renda, versao, data_inicio, data_fim, flag_atual)
SELECT id_pessoa, customer_id, origem, nome, faixa_renda,
       versao_antiga + 1, CURRENT_DATE, NULL, TRUE
FROM mudou_cli;

COMMIT;

\echo '=== PASSO 4) dim_cliente: versoes criadas ==='
SELECT sk_cliente, id_pessoa, nome, faixa_renda, versao,
       data_inicio, data_fim, flag_atual
FROM dw.dim_cliente
WHERE id_pessoa IN (1, 2)
ORDER BY id_pessoa, versao;

-- =====================================================================
-- PASSO 5) A PROVA: as vendas antigas continuam na versão ANTIGA
--   Se o passado tivesse sido reescrito, tudo apareceria na versão 2.
-- =====================================================================
\echo '=== PASSO 5) Vendas por versao do produto (produtos 1,2,3) ==='
SELECT p.id_produto,
       p.versao,
       p.preco_venda,
       count(*)                    AS linhas_de_venda,
       round(sum(f.vlr_liquido),2) AS total_vendido
FROM dw.fato_vendas f
JOIN dw.dim_produto p ON p.sk_produto = f.sk_produto
WHERE p.id_produto IN (1, 2, 3)
GROUP BY 1, 2, 3
ORDER BY 1, 2;

\echo '=== PASSO 5) Vendas por versao do cliente (clientes 1 e 2) ==='
SELECT c.id_pessoa, c.versao, c.faixa_renda,
       count(*) AS linhas_de_venda
FROM dw.fato_vendas f
JOIN dw.dim_cliente c ON c.sk_cliente = f.sk_cliente
WHERE c.id_pessoa IN (1, 2)
GROUP BY 1, 2, 3
ORDER BY 1, 2;

\echo '=== PASSO 6) Consistencia final da dimensao (deve ser tudo 0) ==='
SELECT (SELECT count(*) FROM (
            SELECT origem, COALESCE(id_produto::text, product_id::text) k
            FROM dw.dim_produto GROUP BY 1,2 HAVING count(*) FILTER (WHERE flag_atual) <> 1
        ) x) AS produtos_sem_uma_vigente,
       (SELECT count(*) FROM (
            SELECT origem, COALESCE(id_pessoa::text, customer_id) k
            FROM dw.dim_cliente GROUP BY 1,2 HAVING count(*) FILTER (WHERE flag_atual) <> 1
        ) x) AS clientes_sem_uma_vigente,
       (SELECT count(*) FROM dw.dim_produto WHERE flag_atual AND data_fim IS NOT NULL) AS vigente_com_data_fim,
       (SELECT count(*) FROM dw.dim_produto WHERE NOT flag_atual AND data_fim IS NULL) AS fechado_sem_data_fim;
