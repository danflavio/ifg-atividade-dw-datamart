-- =====================================================================
-- DADOS EXTERNOS - schema `ext`
-- ---------------------------------------------------------------------
-- Fontes (dados públicos REAIS), extraídas por:
--   etl/05_extrair_dados_externos.ps1   (accesso em 2026-09-29)
--
--   * IBGE (Localidades) : código do município, 7 dígitos
--   * IBGE (Agregados)   : agregado 6579, variável 9324
--                          "População residente estimada"
--   * BCB  (PTAX/OLINDA) : cotação USD->BRL do boletim de fechamento
--
-- Regra de negócio do CÂMBIO (decisão registrada):
--   1. converte-se o valor em USD para BRL pela cotação de **compra** do dia;
--   2. quando não existe boletim no dia (fim de semana/feriado), usa-se a
--      ÚLTIMA cotação disponível ("carry forward") - materializado em
--      ext.cotacao_dolar_dia, para o ETL não repetir essa regra.
--   3. a taxa aplicada é gravada em dw.fato_vendas.taxa_cambio (auditoria).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ext;

-- Extensão para normalizar texto (remoção de acento) na integração:
-- 'Sao Paulo' (Northwind) e 'São Paulo' (Mercearia) são a MESMA cidade.
CREATE EXTENSION IF NOT EXISTS unaccent;

DROP TABLE IF EXISTS ext.municipio_ibge;
DROP TABLE IF EXISTS ext.cotacao_dolar;
DROP TABLE IF EXISTS ext.cotacao_dolar_dia;

-- ---------------------------------------------------------------------
-- IBGE: municípios usados pela Mercearia
-- ---------------------------------------------------------------------
CREATE TABLE ext.municipio_ibge (
    codigo_ibge VARCHAR(10) PRIMARY KEY,   -- código IBGE do município
    nome        VARCHAR(120) NOT NULL,
    uf_sigla    CHAR(2)      NOT NULL,
    populacao   INTEGER,                   -- população residente estimada
    ano_ref     SMALLINT                   -- ano de referência da estimativa
);

-- ---------------------------------------------------------------------
-- BCB/PTAX: cotações diárias USD->BRL (apenas os dias com boletim)
-- ---------------------------------------------------------------------
CREATE TABLE ext.cotacao_dolar (
    data           DATE PRIMARY KEY,
    cotacao_compra NUMERIC(12,6) NOT NULL,
    cotacao_venda  NUMERIC(12,6) NOT NULL
);

-- COPY lê o arquivo do ponto de vista do SERVIDOR (o container), e os CSVs
-- ficam montados em /dados_externos (ver docker-compose.yml).
-- Os arquivos são UTF-8 SEM BOM e usam ';' como separador.
COPY ext.municipio_ibge (codigo_ibge, nome, uf_sigla, populacao, ano_ref)
     FROM '/dados_externos/ibge_municipios.csv'
     WITH (FORMAT csv, HEADER true, DELIMITER ';');

COPY ext.cotacao_dolar (data, cotacao_compra, cotacao_venda)
     FROM '/dados_externos/ptax_dolar_1996_1998.csv'
     WITH (FORMAT csv, HEADER true, DELIMITER ';');

-- ---------------------------------------------------------------------
-- Calendário de câmbio: 1 linha para TODOS os dias do período, com a
-- última cotação conhecida (carry forward)
-- ---------------------------------------------------------------------
CREATE TABLE ext.cotacao_dolar_dia (
    data           DATE PRIMARY KEY,
    cotacao_compra NUMERIC(12,6) NOT NULL,
    cotacao_venda  NUMERIC(12,6) NOT NULL
);

INSERT INTO ext.cotacao_dolar_dia (data, cotacao_compra, cotacao_venda)
SELECT g.d::date, c.cotacao_compra, c.cotacao_venda
FROM generate_series(
        (SELECT min(data) FROM ext.cotacao_dolar)::timestamp,
        (SELECT max(data) FROM ext.cotacao_dolar)::timestamp,
        INTERVAL '1 day') AS g(d)
CROSS JOIN LATERAL (
    SELECT cd.cotacao_compra, cd.cotacao_venda
    FROM ext.cotacao_dolar cd
    WHERE cd.data <= g.d::date
    ORDER BY cd.data DESC
    LIMIT 1
) c;

-- ---------------------------------------------------------------------
-- Tabela AUXILIAR de padronização (NÃO é dado externo: é um de-para nosso)
-- Motivo: o Northwind rotula em inglês ('Brazil', 'USA', 'Germany') e a
-- Mercearia em português ('Brasil'). Sem padronizar, o MESMO país viraria
-- duas linhas diferentes na dim_localidade - quebrando a integração.
-- Rótulos fora deste de-para passam como estão (COALESCE no ETL).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ext.pais_nome;
CREATE TABLE ext.pais_nome (
    nome_origem      VARCHAR(40) PRIMARY KEY,
    nome_padronizado VARCHAR(40) NOT NULL
);
INSERT INTO ext.pais_nome (nome_origem, nome_padronizado) VALUES
 ('Brazil','Brasil'),        ('USA','Estados Unidos'),  ('UK','Reino Unido'),
 ('Germany','Alemanha'),     ('France','França'),       ('Venezuela','Venezuela'),
 ('Austria','Áustria'),      ('Sweden','Suécia'),       ('Canada','Canadá'),
 ('Italy','Itália'),         ('Mexico','México'),       ('Spain','Espanha'),
 ('Finland','Finlândia'),    ('Ireland','Irlanda'),     ('Belgium','Bélgica'),
 ('Denmark','Dinamarca'),    ('Switzerland','Suíça'),   ('Argentina','Argentina'),
 ('Portugal','Portugal'),    ('Poland','Polônia'),      ('Norway','Noruega');

ANALYZE ext.municipio_ibge, ext.cotacao_dolar, ext.cotacao_dolar_dia, ext.pais_nome;

-- ---------------------------------------------------------------------
-- Conferência
-- ---------------------------------------------------------------------
SELECT 'IBGE municipios'                     AS conjunto,
       count(*)::text                        AS linhas,
       min(populacao)::text || ' a ' || max(populacao)::text AS detalhe
  FROM ext.municipio_ibge
UNION ALL
SELECT 'PTAX dias com boletim', count(*)::text, min(data)::text || ' a ' || max(data)::text
  FROM ext.cotacao_dolar
UNION ALL
SELECT 'calendario de cambio (todos os dias)', count(*)::text,
       min(data)::text || ' a ' || max(data)::text
  FROM ext.cotacao_dolar_dia;
