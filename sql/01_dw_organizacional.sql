-- =====================================================================
-- DW ORGANIZACIONAL  -  IFG / Tópicos Avançados em IA I
-- Fontes  : schema public (Northwind + Mercearia)  - staging
-- Externos: schema ext (IBGE + BCB/PTAX)
-- SGBD    : PostgreSQL
-- Autor(a): Daniel Flávio
-- ---------------------------------------------------------------------
-- Execução IDEMPOTENTE: o script derruba e recria o schema `dw` inteiro.
-- As fontes (public) e os dados externos (ext) NÃO são afetados.
-- =====================================================================

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;
SET search_path TO dw, public;

-- =====================================================================
-- DIMENSÕES
-- =====================================================================

-- ---------------------------------------------------------------------
-- DIM_TEMPO  (gerada por script -> dado derivado + calendário externo)
-- Grão: 1 linha por DIA | Período: 1996-01-01 a 2026-12-31
--   Cobre a UNIÃO dos períodos dos fatos (Northwind 1996-1998 +
--   Mercearia 2024-2026): dimensão conformada deve abranger tudo.
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_tempo (
    sk_tempo            INTEGER     NOT NULL,      -- surrogate = YYYYMMDD
    data                DATE        NOT NULL,
    ano                 SMALLINT    NOT NULL,
    semestre            SMALLINT    NOT NULL,
    trimestre           SMALLINT    NOT NULL,
    mes                 SMALLINT    NOT NULL,
    nome_mes            VARCHAR(15) NOT NULL,
    dia                 SMALLINT    NOT NULL,
    dia_semana          SMALLINT    NOT NULL,      -- 1=domingo .. 7=sábado
    nome_dia_semana     VARCHAR(15) NOT NULL,
    eh_fim_semana       BOOLEAN     NOT NULL,
    eh_feriado          BOOLEAN     NOT NULL DEFAULT FALSE,  -- feriado LEGAL
    eh_ponto_facultativo BOOLEAN    NOT NULL DEFAULT FALSE,  -- Carnaval/Corpus Christi
    nome_feriado        VARCHAR(60),
    CONSTRAINT pk_dim_tempo      PRIMARY KEY (sk_tempo),
    CONSTRAINT uq_dim_tempo_data UNIQUE (data)
);

-- ---------------------------------------------------------------------
-- DIM_LOCALIDADE
-- Granularidade: 1 linha por BAIRRO (Brasil) ou CIDADE (EUA).
-- Integra Mercearia (endereços BR) + Northwind (envio nos EUA) + IBGE.
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_localidade (
    sk_localidade   SERIAL       PRIMARY KEY,
    id_uf           INTEGER,
    id_cidade       INTEGER,
    id_bairro       INTEGER,
    nm_estado       VARCHAR(60),
    sigla_uf        VARCHAR(30),                    -- UF (BR) ou região/estado de envio (exterior)
    nm_cidade       VARCHAR(255),
    regiao_cidade   VARCHAR(255),
    nm_bairro       VARCHAR(255),
    cep             INTEGER,                        -- representativo do bairro
    pais            VARCHAR(40)  NOT NULL DEFAULT 'Brasil',
    codigo_ibge     VARCHAR(10),                    -- DADO EXTERNO (IBGE)
    populacao       INTEGER,                        -- DADO EXTERNO (IBGE)
    populacao_ano   SMALLINT                        -- DADO EXTERNO (IBGE)
);

-- Chave natural: combinação país + UF + cidade + bairro.
-- COALESCE impede que vários NULL (cidades dos EUA) burlem a unicidade.
CREATE UNIQUE INDEX uq_dim_local_natural ON dw.dim_localidade (
    pais, COALESCE(sigla_uf, ''), COALESCE(nm_cidade, ''), COALESCE(nm_bairro, '')
);

-- ---------------------------------------------------------------------
-- DIM_PRODUTO  com SCD TIPO 2 (histórico de preço)
-- Integra Mercearia.Produtos + Northwind.products
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_produto (
    sk_produto      SERIAL       PRIMARY KEY,
    id_produto      INTEGER,                        -- chave natural Mercearia
    product_id      SMALLINT,                       -- chave natural Northwind
    origem          VARCHAR(10)  NOT NULL,          -- 'MERCEARIA' | 'NORTHWIND'
    nome_produto    VARCHAR(255) NOT NULL,
    categoria       VARCHAR(255),
    preco_venda     NUMERIC(12,2),                  -- atributo versionado (SCD2)
    descontinuado   BOOLEAN      NOT NULL DEFAULT FALSE,
    -- controles de historicidade (SCD Tipo 2)
    versao          INTEGER      NOT NULL DEFAULT 1,
    data_inicio     DATE         NOT NULL,
    data_fim        DATE,
    flag_atual      BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_dim_produto_scd CHECK (flag_atual OR data_fim IS NOT NULL)
);

CREATE UNIQUE INDEX uq_dim_produto_versao ON dw.dim_produto (
    origem, COALESCE(id_produto::text, ''), COALESCE(product_id::text, ''), versao
);
CREATE UNIQUE INDEX uq_dim_produto_atual ON dw.dim_produto (
    origem, COALESCE(id_produto::text, ''), COALESCE(product_id::text, '')
) WHERE flag_atual;

-- ---------------------------------------------------------------------
-- DIM_CLIENTE  com SCD TIPO 2 (histórico de faixa de renda / endereço)
-- Integra Mercearia.Pessoas + Northwind.customers
-- [!] LGPD: dados sensíveis (CPF/CNPJ, renda) são mascarados/derivados
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_cliente (
    sk_cliente      SERIAL       PRIMARY KEY,
    id_pessoa       INTEGER,                        -- chave natural Mercearia
    customer_id     VARCHAR(5),                     -- chave natural Northwind
    origem          VARCHAR(10)  NOT NULL,
    nome            VARCHAR(255),
    cpf_cnpj_masked VARCHAR(20),                    -- LGPD: ex. '***.***.***-09'
    tipo_pessoa     INTEGER,
    sexo            VARCHAR(20),
    estado_civil    VARCHAR(20),
    faixa_renda     VARCHAR(20),                    -- LGPD: faixa, não valor exato
    data_nascimento DATE,
    pais            VARCHAR(40),
    versao          INTEGER      NOT NULL DEFAULT 1,
    data_inicio     DATE         NOT NULL,
    data_fim        DATE,
    flag_atual      BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_dim_cliente_scd CHECK (flag_atual OR data_fim IS NOT NULL)
);

CREATE UNIQUE INDEX uq_dim_cliente_versao ON dw.dim_cliente (
    origem, COALESCE(id_pessoa::text, ''), COALESCE(customer_id, ''), versao
);
CREATE UNIQUE INDEX uq_dim_cliente_atual ON dw.dim_cliente (
    origem, COALESCE(id_pessoa::text, ''), COALESCE(customer_id, '')
) WHERE flag_atual;

-- ---------------------------------------------------------------------
-- DIM_VENDEDOR  (só Northwind.employees)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_vendedor (
    sk_vendedor     SERIAL       PRIMARY KEY,
    employee_id     SMALLINT,
    nome            VARCHAR(120),
    cargo           VARCHAR(60),
    cidade          VARCHAR(40),
    pais            VARCHAR(40),
    data_admissao   DATE
);

-- ---------------------------------------------------------------------
-- DIM_FORNECEDOR  (Mercearia = Pessoas tipo fornecedor + Northwind.suppliers)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_fornecedor (
    sk_fornecedor   SERIAL       PRIMARY KEY,
    id_pessoa       INTEGER,
    supplier_id     SMALLINT,
    origem          VARCHAR(10)  NOT NULL,
    nome            VARCHAR(255) NOT NULL,
    cidade          VARCHAR(60),
    pais            VARCHAR(40)
);

-- ---------------------------------------------------------------------
-- DIM_TRANSPORTADORA  (só Northwind.shippers) - apoia o DataMart Logística
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_transportadora (
    sk_transportadora SERIAL     PRIMARY KEY,
    shipper_id        SMALLINT,
    nome              VARCHAR(80) NOT NULL,
    telefone          VARCHAR(40),
    CONSTRAINT uq_dim_transp_natural UNIQUE (shipper_id)
);

-- =====================================================================
-- FATOS
-- =====================================================================

-- ---------------------------------------------------------------------
-- FATO_VENDAS  - GRÃO: 1 linha por ITEM de venda/pedido
-- Medidas em BRL: o Northwind (USD) é convertido pela PTAX do dia,
-- e a taxa aplicada fica registrada em `taxa_cambio` (auditabilidade).
-- ---------------------------------------------------------------------
CREATE TABLE dw.fato_vendas (
    sk_fato_venda   BIGSERIAL    PRIMARY KEY,
    num_pedido      VARCHAR(20)  NOT NULL,          -- dimensão degenerada
    origem          VARCHAR(10)  NOT NULL,          -- 'MERCEARIA' | 'NORTHWIND'
    moeda_origem    VARCHAR(3)   NOT NULL,          -- 'BRL' | 'USD'
    taxa_cambio     NUMERIC(12,6),                  -- PTAX compra do dia (USD->BRL)
    -- chaves estrangeiras (com papel)
    sk_tempo_venda  INTEGER      NOT NULL REFERENCES dw.dim_tempo(sk_tempo),
    sk_tempo_fatura INTEGER                 REFERENCES dw.dim_tempo(sk_tempo),
    sk_cliente      INTEGER      NOT NULL REFERENCES dw.dim_cliente(sk_cliente),
    sk_produto      INTEGER      NOT NULL REFERENCES dw.dim_produto(sk_produto),
    sk_localidade   INTEGER                 REFERENCES dw.dim_localidade(sk_localidade),
    sk_vendedor     INTEGER                 REFERENCES dw.dim_vendedor(sk_vendedor),
    -- medidas (todas em BRL)
    quantidade      INTEGER      NOT NULL,
    vlr_unitario    NUMERIC(12,2) NOT NULL,         -- não-aditiva
    pct_desconto    NUMERIC(5,4)  NOT NULL DEFAULT 0,-- não-aditiva
    vlr_bruto       NUMERIC(14,2) NOT NULL,         -- aditiva
    vlr_desconto    NUMERIC(14,2) NOT NULL DEFAULT 0,-- aditiva
    vlr_liquido     NUMERIC(14,2) NOT NULL          -- aditiva
);

-- ---------------------------------------------------------------------
-- FATO_COMPRAS  - GRÃO: 1 linha por ITEM de compra  (só Mercearia)
-- ---------------------------------------------------------------------
CREATE TABLE dw.fato_compras (
    sk_fato_compra  BIGSERIAL    PRIMARY KEY,
    num_compra      VARCHAR(20)  NOT NULL,
    sk_tempo_pedido INTEGER      NOT NULL REFERENCES dw.dim_tempo(sk_tempo),
    sk_tempo_entrada INTEGER                REFERENCES dw.dim_tempo(sk_tempo),
    sk_produto      INTEGER      NOT NULL REFERENCES dw.dim_produto(sk_produto),
    sk_fornecedor   INTEGER                 REFERENCES dw.dim_fornecedor(sk_fornecedor),
    quantidade      INTEGER      NOT NULL,
    vlr_unitario    NUMERIC(12,2) NOT NULL,
    vlr_bruto       NUMERIC(14,2) NOT NULL
);

-- ---------------------------------------------------------------------
-- FATO_ENTREGAS  - GRÃO: 1 linha por PEDIDO/ENTREGA (só Northwind)
--
-- POR QUE UM FATO COM GRÃO DIFERENTE?
--   O frete (orders.freight) é medido no PEDIDO, não no item. Se fosse
--   colocado em fato_vendas (grão de item), o valor apareceria repetido
--   em cada item do pedido (dupla contagem) ou teria de ser rateado -
--   criando um número que não existe na origem. Solução clássica de
--   Kimball: um fato por grão, com dimensões CONFORMADAS (mesmo tempo,
--   cliente, localidade) e a transportadora como dimensão própria.
-- ---------------------------------------------------------------------
CREATE TABLE dw.fato_entregas (
    sk_fato_entrega    BIGSERIAL PRIMARY KEY,
    num_pedido         VARCHAR(20) NOT NULL,        -- dimensão degenerada
    sk_tempo_pedido    INTEGER NOT NULL REFERENCES dw.dim_tempo(sk_tempo),
    sk_tempo_expedicao INTEGER          REFERENCES dw.dim_tempo(sk_tempo),
    sk_cliente         INTEGER          REFERENCES dw.dim_cliente(sk_cliente),
    sk_localidade      INTEGER          REFERENCES dw.dim_localidade(sk_localidade),
    sk_transportadora  INTEGER          REFERENCES dw.dim_transportadora(sk_transportadora),
    vlr_frete          NUMERIC(14,2),               -- aditiva POR PEDIDO
    qtd_itens          INTEGER,                     -- nº de itens do pedido
    prazo_dias         INTEGER                      -- expedição - pedido (SLA)
);

-- =====================================================================
-- ÍNDICES nas chaves estrangeiras (performance de JOIN)
-- =====================================================================
CREATE INDEX idx_fv_tempo    ON dw.fato_vendas(sk_tempo_venda);
CREATE INDEX idx_fv_cliente  ON dw.fato_vendas(sk_cliente);
CREATE INDEX idx_fv_produto  ON dw.fato_vendas(sk_produto);
CREATE INDEX idx_fv_local    ON dw.fato_vendas(sk_localidade);
CREATE INDEX idx_fc_produto  ON dw.fato_compras(sk_produto);
CREATE INDEX idx_fe_tempo    ON dw.fato_entregas(sk_tempo_pedido);
CREATE INDEX idx_fe_transp   ON dw.fato_entregas(sk_transportadora);

-- =====================================================================
-- COMENTÁRIOS (dicionário de dados)
-- =====================================================================
COMMENT ON TABLE  dw.fato_vendas        IS 'Fato de vendas no grão de item de pedido (atômico)';
COMMENT ON COLUMN dw.fato_vendas.num_pedido   IS 'Dimensão degenerada: número do pedido de origem';
COMMENT ON COLUMN dw.fato_vendas.moeda_origem IS 'Moeda do documento original (BRL ou USD)';
COMMENT ON COLUMN dw.fato_vendas.taxa_cambio  IS 'PTAX compra do dia usada para converter USD->BRL';
COMMENT ON COLUMN dw.dim_produto.flag_atual   IS 'SCD Tipo 2: true = versão vigente';
COMMENT ON COLUMN dw.dim_cliente.cpf_cnpj_masked IS 'LGPD: CPF/CNPJ mascarado, nunca em claro';
COMMENT ON COLUMN dw.dim_tempo.eh_feriado     IS 'Feriado legal nacional';
COMMENT ON COLUMN dw.dim_tempo.eh_ponto_facultativo IS 'Carnaval e Corpus Christi (não são feriados por lei)';
COMMENT ON TABLE  dw.fato_entregas IS 'Fato de entregas no grão de pedido (frete), só Northwind';
