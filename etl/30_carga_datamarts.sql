-- =====================================================================
-- ETL DOS DATAMARTS (Fase 4) - carga a partir do DW Organizacional
-- ---------------------------------------------------------------------
-- Regra do recorte:
--   * DIMENSÕES: carrega somente os MEMBROS USADOS pelos fatos do mart.
--     Isso preserva o SCD2 (todas as versões referenciadas pelos fatos
--     entram, inclusive as já fechadas) - se carregássemos só a versão
--     vigente, as vendas antigas ficariam órfãs no DataMart.
--   * FATOS: carregados integralmente (é o mesmo universo do DW).
--   * As chaves surrogate são as MESMAS do DW (rastreabilidade).
-- =====================================================================
SET search_path TO dm_vendas, dm_suprimentos, dm_logistica, dw, public, ext;

BEGIN;

-- =====================================================================
-- DATAMART 1 - VENDAS
-- =====================================================================

-- Tempo: dias usados como data de venda OU de faturamento
INSERT INTO dm_vendas.dim_tempo
SELECT t.sk_tempo, t.data, t.ano, t.semestre, t.trimestre, t.mes, t.nome_mes,
       t.dia, t.dia_semana, t.nome_dia_semana, t.eh_fim_semana,
       t.eh_feriado, t.eh_ponto_facultativo, t.nome_feriado
FROM dw.dim_tempo t
WHERE EXISTS (
    SELECT 1 FROM dw.fato_vendas f
    WHERE f.sk_tempo_venda = t.sk_tempo OR f.sk_tempo_fatura = t.sk_tempo
);

INSERT INTO dm_vendas.dim_produto
SELECT d.sk_produto, d.id_produto, d.product_id, d.origem, d.nome_produto,
       d.categoria, d.preco_venda, d.descontinuado, d.versao,
       d.data_inicio, d.data_fim, d.flag_atual
FROM dw.dim_produto d
WHERE EXISTS (SELECT 1 FROM dw.fato_vendas f WHERE f.sk_produto = d.sk_produto);

INSERT INTO dm_vendas.dim_cliente
SELECT d.sk_cliente, d.id_pessoa, d.customer_id, d.origem, d.nome,
       d.cpf_cnpj_masked, d.tipo_pessoa, d.sexo, d.estado_civil, d.faixa_renda,
       d.data_nascimento, d.pais, d.versao, d.data_inicio, d.data_fim, d.flag_atual
FROM dw.dim_cliente d
WHERE EXISTS (SELECT 1 FROM dw.fato_vendas f WHERE f.sk_cliente = d.sk_cliente);

INSERT INTO dm_vendas.dim_localidade
SELECT d.sk_localidade, d.id_uf, d.id_cidade, d.id_bairro, d.nm_estado,
       d.sigla_uf, d.nm_cidade, d.regiao_cidade, d.nm_bairro, d.cep, d.pais,
       d.codigo_ibge, d.populacao, d.populacao_ano
FROM dw.dim_localidade d
WHERE EXISTS (SELECT 1 FROM dw.fato_vendas f WHERE f.sk_localidade = d.sk_localidade);

INSERT INTO dm_vendas.dim_vendedor
SELECT d.sk_vendedor, d.employee_id, d.nome, d.cargo, d.cidade, d.pais, d.data_admissao
FROM dw.dim_vendedor d
WHERE EXISTS (SELECT 1 FROM dw.fato_vendas f WHERE f.sk_vendedor = d.sk_vendedor);

INSERT INTO dm_vendas.fato_vendas
SELECT f.sk_fato_venda, f.num_pedido, f.origem, f.moeda_origem, f.taxa_cambio,
       f.sk_tempo_venda, f.sk_tempo_fatura, f.sk_cliente, f.sk_produto,
       f.sk_localidade, f.sk_vendedor, f.quantidade, f.vlr_unitario,
       f.pct_desconto, f.vlr_bruto, f.vlr_desconto, f.vlr_liquido
FROM dw.fato_vendas f;

-- =====================================================================
-- DATAMART 2 - SUPRIMENTOS / COMPRAS
-- =====================================================================
INSERT INTO dm_suprimentos.dim_tempo
SELECT t.sk_tempo, t.data, t.ano, t.semestre, t.trimestre, t.mes, t.nome_mes,
       t.dia, t.dia_semana, t.nome_dia_semana, t.eh_fim_semana,
       t.eh_feriado, t.eh_ponto_facultativo, t.nome_feriado
FROM dw.dim_tempo t
WHERE EXISTS (
    SELECT 1 FROM dw.fato_compras f
    WHERE f.sk_tempo_pedido = t.sk_tempo OR f.sk_tempo_entrada = t.sk_tempo
);

INSERT INTO dm_suprimentos.dim_produto
SELECT d.sk_produto, d.id_produto, d.product_id, d.origem, d.nome_produto,
       d.categoria, d.preco_venda, d.descontinuado, d.versao,
       d.data_inicio, d.data_fim, d.flag_atual
FROM dw.dim_produto d
WHERE EXISTS (SELECT 1 FROM dw.fato_compras f WHERE f.sk_produto = d.sk_produto);

INSERT INTO dm_suprimentos.dim_fornecedor
SELECT d.sk_fornecedor, d.id_pessoa, d.supplier_id, d.origem, d.nome,
       d.cidade, d.pais
FROM dw.dim_fornecedor d
WHERE EXISTS (SELECT 1 FROM dw.fato_compras f WHERE f.sk_fornecedor = d.sk_fornecedor);

INSERT INTO dm_suprimentos.fato_compras
SELECT f.sk_fato_compra, f.num_compra, f.sk_tempo_pedido, f.sk_tempo_entrada,
       f.sk_produto, f.sk_fornecedor, f.quantidade, f.vlr_unitario, f.vlr_bruto
FROM dw.fato_compras f;

-- =====================================================================
-- DATAMART 3 - LOGÍSTICA / ENTREGAS
-- =====================================================================
INSERT INTO dm_logistica.dim_tempo
SELECT t.sk_tempo, t.data, t.ano, t.semestre, t.trimestre, t.mes, t.nome_mes,
       t.dia, t.dia_semana, t.nome_dia_semana, t.eh_fim_semana,
       t.eh_feriado, t.eh_ponto_facultativo, t.nome_feriado
FROM dw.dim_tempo t
WHERE EXISTS (
    SELECT 1 FROM dw.fato_entregas f
    WHERE f.sk_tempo_pedido = t.sk_tempo OR f.sk_tempo_expedicao = t.sk_tempo
);

-- LGPD: dimensão MINIMIZADA (sem cpf_cnpj_masked e sem faixa_renda)
INSERT INTO dm_logistica.dim_cliente
SELECT d.sk_cliente, d.id_pessoa, d.customer_id, d.origem, d.nome,
       d.tipo_pessoa, d.pais, d.versao, d.data_inicio, d.data_fim, d.flag_atual
FROM dw.dim_cliente d
WHERE EXISTS (SELECT 1 FROM dw.fato_entregas f WHERE f.sk_cliente = d.sk_cliente);

INSERT INTO dm_logistica.dim_localidade
SELECT d.sk_localidade, d.nm_estado, d.sigla_uf, d.nm_cidade, d.pais,
       d.codigo_ibge, d.populacao, d.populacao_ano
FROM dw.dim_localidade d
WHERE EXISTS (SELECT 1 FROM dw.fato_entregas f WHERE f.sk_localidade = d.sk_localidade);

INSERT INTO dm_logistica.dim_transportadora
SELECT d.sk_transportadora, d.shipper_id, d.nome, d.telefone
FROM dw.dim_transportadora d
WHERE EXISTS (SELECT 1 FROM dw.fato_entregas f WHERE f.sk_transportadora = d.sk_transportadora);

INSERT INTO dm_logistica.fato_entregas
SELECT f.sk_fato_entrega, f.num_pedido, f.sk_tempo_pedido, f.sk_tempo_expedicao,
       f.sk_cliente, f.sk_localidade, f.sk_transportadora, f.vlr_frete,
       f.qtd_itens, f.prazo_dias
FROM dw.fato_entregas f;

COMMIT;

ANALYZE dm_vendas.dim_tempo, dm_vendas.dim_produto, dm_vendas.dim_cliente,
        dm_vendas.dim_localidade, dm_vendas.dim_vendedor, dm_vendas.fato_vendas,
        dm_suprimentos.dim_tempo, dm_suprimentos.dim_produto,
        dm_suprimentos.dim_fornecedor, dm_suprimentos.fato_compras,
        dm_logistica.dim_tempo, dm_logistica.dim_cliente,
        dm_logistica.dim_localidade, dm_logistica.dim_transportadora,
        dm_logistica.fato_entregas;
