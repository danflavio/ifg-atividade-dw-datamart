-- =====================================================================
-- ETL - CARGA DAS DIMENSÕES (schema dw)
-- ---------------------------------------------------------------------
-- Ordem: localidade -> produto -> cliente -> vendedor -> fornecedor
--        -> transportadora   (dimensões antes dos fatos: as FKs exigem)
--
-- Historicidade (SCD Tipo 2): a PRIMEIRA carga cria a versão 1 de cada
-- membro, com data_inicio = 1900-01-01 (sentinela) e flag_atual = TRUE.
-- O teste de mudança de preço/renda está em etl/90_teste_scd2.sql.
-- =====================================================================
SET search_path TO dw, public;

BEGIN;

-- ---------------------------------------------------------------------
-- 1) DIM_LOCALIDADE - Brasil (Mercearia), enriquecida pelo IBGE
--    Granularidade brasileira: bairro | cep = representativo do bairro
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_localidade (id_uf, id_cidade, id_bairro, nm_estado,
                               sigla_uf, nm_cidade, regiao_cidade, nm_bairro,
                               cep, pais, codigo_ibge, populacao, populacao_ano)
SELECT u.ID_UF,
       c.ID_CIDADE,
       b.ID_BAIRRO,
       u.NOME_ESTADO,
       u.SIGLA,
       c.NOME_CIDADE,
       b.REGIAOCIDADE,
       b.NOME_BAIRRO,
       (SELECT min(l.CEP) FROM Logradouros l WHERE l.ID_BAIRRO = b.ID_BAIRRO),
       'Brasil',
       m.codigo_ibge,
       m.populacao,
       m.ano_ref
FROM Bairros b
JOIN Cidades c ON c.ID_CIDADE = b.ID_CIDADE
JOIN Uf u      ON u.ID_UF     = c.ID_UF
LEFT JOIN ext.municipio_ibge m
       ON m.nome = c.NOME_CIDADE
      AND m.uf_sigla = u.SIGLA;

-- ---------------------------------------------------------------------
-- 2) DIM_LOCALIDADE - exterior (pedidos do Northwind)
--    O Northwind envia para 21 países: aqui a granularidade garantida é
--    país + cidade (e região, quando existir). NÃO há bairro nem IBGE.
--    Um único membro por combinação país/cidade/região (DISTINCT).
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_localidade (nm_estado, sigla_uf, nm_cidade, pais,
                               codigo_ibge, populacao, populacao_ano)
SELECT DISTINCT
       -- Nome do estado: usa a tabela Uf quando o destino e brasileiro
       -- (senao o MESMO estado apareceria com rotulo vazio e nomeado)
       COALESCE(ubr.NOME_ESTADO, s.state_name),
       o.ship_region,
       -- Rótulo canônico: se o destino é uma cidade brasileira conhecida,
       -- usa o nome da Mercearia (com acento); senão, mantém o do Northwind.
       COALESCE(cid.NOME_CIDADE, o.ship_city),
       COALESCE(pn.nome_padronizado, o.ship_country),
       m.codigo_ibge,
       m.populacao,
       m.ano_ref
FROM orders o
LEFT JOIN us_states   s    ON s.state_abbr   = o.ship_region
LEFT JOIN ext.pais_nome pn ON pn.nome_origem = o.ship_country
-- Normalização de acento/caixa no casamento de nomes de cidade
LEFT JOIN Uf ubr
       ON COALESCE(pn.nome_padronizado, o.ship_country) = 'Brasil'
      AND ubr.SIGLA = o.ship_region
LEFT JOIN Cidades cid
       ON cid.ID_UF = ubr.ID_UF
      AND unaccent(lower(cid.NOME_CIDADE)) = unaccent(lower(o.ship_city))
LEFT JOIN ext.municipio_ibge m
       ON COALESCE(pn.nome_padronizado, o.ship_country) = 'Brasil'
      AND m.uf_sigla = o.ship_region
      AND unaccent(lower(m.nome)) = unaccent(lower(o.ship_city))
WHERE o.ship_city IS NOT NULL;

-- ---------------------------------------------------------------------
-- 3) DIM_PRODUTO - versão 1 (Mercearia + Northwind)
--    Atributo versionado: preco_venda
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_produto (id_produto, origem, nome_produto, categoria,
                            preco_venda, descontinuado, versao,
                            data_inicio, data_fim, flag_atual)
SELECT p.ID_PRODUTO, 'MERCEARIA', p.PRODUTO, cat.NOME_CATEGORIA,
       round(p.VALOR_VENDA::numeric, 2), FALSE, 1,
       DATE '1900-01-01', NULL, TRUE
FROM Produtos p
JOIN Categorias cat ON cat.ID_CATEGORIA = p.ID_CATEGORIA;

INSERT INTO dw.dim_produto (product_id, origem, nome_produto, categoria,
                            preco_venda, descontinuado, versao,
                            data_inicio, data_fim, flag_atual)
SELECT p.product_id, 'NORTHWIND', p.product_name, c.category_name,
       round(p.unit_price::numeric, 2), COALESCE(p.discontinued, 0) <> 0, 1,
       DATE '1900-01-01', NULL, TRUE
FROM products p
LEFT JOIN categories c ON c.category_id = p.category_id;

-- ---------------------------------------------------------------------
-- 4) DIM_CLIENTE - Mercearia (PF e PJ) + Northwind
--    LGPD: CPF/CNPJ mascarado (só os 2 últimos dígitos) e renda em FAIXA.
--    faixa_renda só para pessoa física: para PJ o campo RENDA da origem
--    representa faturamento, não renda -> fica NULL (evita erro semântico).
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_cliente (id_pessoa, origem, nome, cpf_cnpj_masked,
                            tipo_pessoa, sexo, estado_civil, faixa_renda,
                            data_nascimento, pais,
                            versao, data_inicio, data_fim, flag_atual)
SELECT p.ID_PESSOA,
       'MERCEARIA',
       p.NOME,
       '***.***.***-' || right(p.CPF_CNPJ, 2),          -- LGPD
       p.TIPO_PESSOA,
       p.SEXO,
       p.ESTADO_CIVIL,
       CASE
           WHEN p.TIPO_PESSOA = 2                THEN NULL
           WHEN p.RENDA IS NULL OR p.RENDA <= 0  THEN 'Não informado'
           WHEN p.RENDA <= 3000                  THEN 'Até R$ 3 mil'
           WHEN p.RENDA <= 7500                  THEN 'R$ 3 a 7,5 mil'
           WHEN p.RENDA <= 15000                 THEN 'R$ 7,5 a 15 mil'
           ELSE 'Acima de R$ 15 mil'
       END,
       p.DATA_NASCIMENTO,
       'Brasil',
       1, DATE '1900-01-01', NULL, TRUE
FROM Pessoas p
WHERE p.TIPO_PESSOA IN (1, 2);

INSERT INTO dw.dim_cliente (customer_id, origem, nome, pais,
                            versao, data_inicio, data_fim, flag_atual)
SELECT c.customer_id, 'NORTHWIND', c.company_name,
       COALESCE(pn.nome_padronizado, c.country),
       1, DATE '1900-01-01', NULL, TRUE
FROM customers c
LEFT JOIN ext.pais_nome pn ON pn.nome_origem = c.country;

-- ---------------------------------------------------------------------
-- 5) DIM_VENDEDOR - Northwind.employees
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_vendedor (employee_id, nome, cargo, cidade, pais, data_admissao)
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name,
       e.title,
       e.city,
       COALESCE(pn.nome_padronizado, e.country),
       e.hire_date
FROM employees e
LEFT JOIN ext.pais_nome pn ON pn.nome_origem = e.country;

-- ---------------------------------------------------------------------
-- 6) DIM_FORNECEDOR - Mercearia (TIPO_PESSOA = 3) + Northwind.suppliers
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_fornecedor (id_pessoa, origem, nome, cidade, pais)
SELECT p.ID_PESSOA, 'MERCEARIA', p.NOME, loc.nm_cidade, 'Brasil'
FROM Pessoas p
LEFT JOIN LATERAL (
    SELECT c.NOME_CIDADE AS nm_cidade
    FROM Enderecos e
    JOIN Logradouros l ON l.ID_LOGRADOURO = e.ID_LOGRADOURO
    JOIN Bairros b     ON b.ID_BAIRRO     = l.ID_BAIRRO
    JOIN Cidades c     ON c.ID_CIDADE     = b.ID_CIDADE
    WHERE e.ID_PESSOA = p.ID_PESSOA AND e.PREFERENCIAL = B'1'
    LIMIT 1
) loc ON TRUE
WHERE p.TIPO_PESSOA = 3;

INSERT INTO dw.dim_fornecedor (supplier_id, origem, nome, cidade, pais)
SELECT s.supplier_id, 'NORTHWIND', s.company_name, s.city,
       COALESCE(pn.nome_padronizado, s.country)
FROM suppliers s
LEFT JOIN ext.pais_nome pn ON pn.nome_origem = s.country;

-- ---------------------------------------------------------------------
-- 7) DIM_TRANSPORTADORA - Northwind.shippers
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_transportadora (shipper_id, nome, telefone)
SELECT shipper_id, company_name, phone
FROM shippers;

COMMIT;

ANALYZE dw.dim_tempo, dw.dim_localidade, dw.dim_produto, dw.dim_cliente,
        dw.dim_vendedor, dw.dim_fornecedor, dw.dim_transportadora;

-- ---------------------------------------------------------------------
-- Conferência
-- ---------------------------------------------------------------------
SELECT 'dim_localidade'   AS dimensao, count(*) AS linhas,
       count(*) FILTER (WHERE pais = 'Brasil') AS brasil,
       count(*) FILTER (WHERE pais <> 'Brasil') AS exterior
FROM dw.dim_localidade
UNION ALL
SELECT 'dim_produto', count(*), count(*) FILTER (WHERE origem='MERCEARIA'),
       count(*) FILTER (WHERE origem='NORTHWIND') FROM dw.dim_produto
UNION ALL
SELECT 'dim_cliente', count(*), count(*) FILTER (WHERE origem='MERCEARIA'),
       count(*) FILTER (WHERE origem='NORTHWIND') FROM dw.dim_cliente
UNION ALL
SELECT 'dim_fornecedor', count(*), count(*) FILTER (WHERE origem='MERCEARIA'),
       count(*) FILTER (WHERE origem='NORTHWIND') FROM dw.dim_fornecedor
UNION ALL
SELECT 'dim_vendedor', count(*), count(*), 0 FROM dw.dim_vendedor
UNION ALL
SELECT 'dim_transportadora', count(*), count(*), 0 FROM dw.dim_transportadora;
