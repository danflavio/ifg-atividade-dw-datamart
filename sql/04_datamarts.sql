-- =====================================================================
-- DATAMARTS - DDL (Fase 4)
-- ---------------------------------------------------------------------
-- Três assuntos de negócio, cada um em seu PRÓPRIO ESQUEMA (esquema
-- estrela independente), carregado a partir do DW Organizacional:
--
--   dm_vendas       -> assunto: desempenho comercial
--   dm_suprimentos  -> assunto: compras e abastecimento
--   dm_logistica    -> assunto: entregas e frete
--
-- Decisões de modelagem (justificativa em docs/datamarts.md):
--   1. As dimensões dos DataMarts são RECORTES CONFORMADOS do DW:
--      mantêm a MESMA chave surrogate do DW, garantindo que os três
--      DataMarts falem a mesma língua (mesmo membro = mesma chave).
--   2. O recorte é feito em LINHAS (só os membros que o fato usa), não em
--      colunas - exceto em dm_logistica.dim_cliente, onde atributos
--      sensíveis (CPF mascarado e faixa de renda) foram deliberadamente
--      OMITIDOS: não há uso analítico para eles nesse assunto
--      (princípio de minimização da LGPD).
--   3. As chaves dos fatos também são as mesmas do DW -> rastreabilidade
--      ponta a ponta (DataMart -> DW -> fonte).
--
-- Execução idempotente: recria os três esquemas do zero.
-- =====================================================================

DROP SCHEMA IF EXISTS dm_vendas      CASCADE;
DROP SCHEMA IF EXISTS dm_suprimentos CASCADE;
DROP SCHEMA IF EXISTS dm_logistica   CASCADE;

CREATE SCHEMA dm_vendas;
CREATE SCHEMA dm_suprimentos;
CREATE SCHEMA dm_logistica;


-- =====================================================================
-- DATAMART 1 - VENDAS  (assunto: desempenho comercial)
-- Pergunta de negócio: o que vende, para quem, onde, por quem e quando.
-- =====================================================================
CREATE TABLE dm_vendas.dim_tempo (
    sk_tempo             INTEGER     NOT NULL,     -- YYYYMMDD (igual ao DW)
    data                 DATE        NOT NULL,
    ano                  SMALLINT    NOT NULL,
    semestre             SMALLINT    NOT NULL,
    trimestre            SMALLINT    NOT NULL,
    mes                  SMALLINT    NOT NULL,
    nome_mes             VARCHAR(15) NOT NULL,
    dia                  SMALLINT    NOT NULL,
    dia_semana           SMALLINT    NOT NULL,
    nome_dia_semana      VARCHAR(15) NOT NULL,
    eh_fim_semana        BOOLEAN     NOT NULL,
    eh_feriado           BOOLEAN     NOT NULL,
    eh_ponto_facultativo BOOLEAN     NOT NULL,
    nome_feriado         VARCHAR(60),
    CONSTRAINT pk_dmv_tempo PRIMARY KEY (sk_tempo)
);

CREATE TABLE dm_vendas.dim_produto (
    sk_produto    INTEGER      NOT NULL,
    id_produto    INTEGER,
    product_id    SMALLINT,
    origem        VARCHAR(10)  NOT NULL,
    nome_produto  VARCHAR(255) NOT NULL,
    categoria     VARCHAR(255),
    preco_venda   NUMERIC(12,2),
    descontinuado BOOLEAN      NOT NULL,
    versao        INTEGER      NOT NULL,      -- SCD2 preservado no DataMart
    data_inicio   DATE         NOT NULL,
    data_fim      DATE,
    flag_atual    BOOLEAN      NOT NULL,
    CONSTRAINT pk_dmv_produto PRIMARY KEY (sk_produto)
);

CREATE TABLE dm_vendas.dim_cliente (
    sk_cliente      INTEGER      NOT NULL,
    id_pessoa       INTEGER,
    customer_id     VARCHAR(5),
    origem          VARCHAR(10)  NOT NULL,
    nome            VARCHAR(255),
    cpf_cnpj_masked VARCHAR(20),               -- LGPD
    tipo_pessoa     INTEGER,
    sexo            VARCHAR(20),
    estado_civil    VARCHAR(20),
    faixa_renda     VARCHAR(20),               -- LGPD
    data_nascimento DATE,
    pais            VARCHAR(40),
    versao          INTEGER      NOT NULL,
    data_inicio     DATE         NOT NULL,
    data_fim        DATE,
    flag_atual      BOOLEAN      NOT NULL,
    CONSTRAINT pk_dmv_cliente PRIMARY KEY (sk_cliente)
);

CREATE TABLE dm_vendas.dim_localidade (
    sk_localidade INTEGER      NOT NULL,
    id_uf         INTEGER,
    id_cidade     INTEGER,
    id_bairro     INTEGER,
    nm_estado     VARCHAR(60),
    sigla_uf      VARCHAR(30),
    nm_cidade     VARCHAR(255),
    regiao_cidade VARCHAR(255),
    nm_bairro     VARCHAR(255),
    cep           INTEGER,
    pais          VARCHAR(40)  NOT NULL,
    codigo_ibge   VARCHAR(10),
    populacao     INTEGER,
    populacao_ano SMALLINT,
    CONSTRAINT pk_dmv_local PRIMARY KEY (sk_localidade)
);

CREATE TABLE dm_vendas.dim_vendedor (
    sk_vendedor   INTEGER      NOT NULL,
    employee_id   SMALLINT,
    nome          VARCHAR(120),
    cargo         VARCHAR(60),
    cidade        VARCHAR(40),
    pais          VARCHAR(40),
    data_admissao DATE,
    CONSTRAINT pk_dmv_vendedor PRIMARY KEY (sk_vendedor)
);

CREATE TABLE dm_vendas.fato_vendas (
    sk_fato_venda   BIGINT        NOT NULL,
    num_pedido      VARCHAR(20)   NOT NULL,
    origem          VARCHAR(10)   NOT NULL,
    moeda_origem    VARCHAR(3)    NOT NULL,
    taxa_cambio     NUMERIC(12,6),
    sk_tempo_venda  INTEGER       NOT NULL,
    sk_tempo_fatura INTEGER,
    sk_cliente      INTEGER       NOT NULL,
    sk_produto      INTEGER       NOT NULL,
    sk_localidade   INTEGER,
    sk_vendedor     INTEGER,
    quantidade      INTEGER       NOT NULL,
    vlr_unitario    NUMERIC(12,2) NOT NULL,
    pct_desconto    NUMERIC(5,4)  NOT NULL,
    vlr_bruto       NUMERIC(14,2) NOT NULL,
    vlr_desconto    NUMERIC(14,2) NOT NULL,
    vlr_liquido     NUMERIC(14,2) NOT NULL,
    CONSTRAINT pk_dmv_fato_vendas PRIMARY KEY (sk_fato_venda),
    CONSTRAINT fk_dmv_fv_tempo_venda  FOREIGN KEY (sk_tempo_venda)  REFERENCES dm_vendas.dim_tempo(sk_tempo),
    CONSTRAINT fk_dmv_fv_tempo_fatura FOREIGN KEY (sk_tempo_fatura) REFERENCES dm_vendas.dim_tempo(sk_tempo),
    CONSTRAINT fk_dmv_fv_cliente      FOREIGN KEY (sk_cliente)      REFERENCES dm_vendas.dim_cliente(sk_cliente),
    CONSTRAINT fk_dmv_fv_produto      FOREIGN KEY (sk_produto)      REFERENCES dm_vendas.dim_produto(sk_produto),
    CONSTRAINT fk_dmv_fv_localidade   FOREIGN KEY (sk_localidade)   REFERENCES dm_vendas.dim_localidade(sk_localidade),
    CONSTRAINT fk_dmv_fv_vendedor     FOREIGN KEY (sk_vendedor)     REFERENCES dm_vendas.dim_vendedor(sk_vendedor)
);

CREATE INDEX idx_dmv_fv_tempo   ON dm_vendas.fato_vendas(sk_tempo_venda);
CREATE INDEX idx_dmv_fv_produto ON dm_vendas.fato_vendas(sk_produto);
CREATE INDEX idx_dmv_fv_cliente ON dm_vendas.fato_vendas(sk_cliente);


-- =====================================================================
-- DATAMART 2 - SUPRIMENTOS / COMPRAS  (assunto: abastecimento)
-- Pergunta de negócio: de quem compramos, a que custo e com que atraso.
-- =====================================================================
CREATE TABLE dm_suprimentos.dim_tempo (
    sk_tempo             INTEGER     NOT NULL,
    data                 DATE        NOT NULL,
    ano                  SMALLINT    NOT NULL,
    semestre             SMALLINT    NOT NULL,
    trimestre            SMALLINT    NOT NULL,
    mes                  SMALLINT    NOT NULL,
    nome_mes             VARCHAR(15) NOT NULL,
    dia                  SMALLINT    NOT NULL,
    dia_semana           SMALLINT    NOT NULL,
    nome_dia_semana      VARCHAR(15) NOT NULL,
    eh_fim_semana        BOOLEAN     NOT NULL,
    eh_feriado           BOOLEAN     NOT NULL,
    eh_ponto_facultativo BOOLEAN     NOT NULL,
    nome_feriado         VARCHAR(60),
    CONSTRAINT pk_dms_tempo PRIMARY KEY (sk_tempo)
);

CREATE TABLE dm_suprimentos.dim_produto (
    sk_produto    INTEGER      NOT NULL,
    id_produto    INTEGER,
    product_id    SMALLINT,
    origem        VARCHAR(10)  NOT NULL,
    nome_produto  VARCHAR(255) NOT NULL,
    categoria     VARCHAR(255),
    preco_venda   NUMERIC(12,2),
    descontinuado BOOLEAN      NOT NULL,
    versao        INTEGER      NOT NULL,
    data_inicio   DATE         NOT NULL,
    data_fim      DATE,
    flag_atual    BOOLEAN      NOT NULL,
    CONSTRAINT pk_dms_produto PRIMARY KEY (sk_produto)
);

CREATE TABLE dm_suprimentos.dim_fornecedor (
    sk_fornecedor INTEGER      NOT NULL,
    id_pessoa     INTEGER,
    supplier_id   SMALLINT,
    origem        VARCHAR(10)  NOT NULL,
    nome          VARCHAR(255) NOT NULL,
    cidade        VARCHAR(60),
    pais          VARCHAR(40),
    CONSTRAINT pk_dms_fornecedor PRIMARY KEY (sk_fornecedor)
);

CREATE TABLE dm_suprimentos.fato_compras (
    sk_fato_compra   BIGINT        NOT NULL,
    num_compra       VARCHAR(20)   NOT NULL,
    sk_tempo_pedido  INTEGER       NOT NULL,
    sk_tempo_entrada INTEGER,
    sk_produto       INTEGER       NOT NULL,
    sk_fornecedor    INTEGER,
    quantidade       INTEGER       NOT NULL,
    vlr_unitario     NUMERIC(12,2) NOT NULL,
    vlr_bruto        NUMERIC(14,2) NOT NULL,
    CONSTRAINT pk_dms_fato_compras PRIMARY KEY (sk_fato_compra),
    CONSTRAINT fk_dms_fc_tempo_pedido  FOREIGN KEY (sk_tempo_pedido)  REFERENCES dm_suprimentos.dim_tempo(sk_tempo),
    CONSTRAINT fk_dms_fc_tempo_entrada FOREIGN KEY (sk_tempo_entrada) REFERENCES dm_suprimentos.dim_tempo(sk_tempo),
    CONSTRAINT fk_dms_fc_produto       FOREIGN KEY (sk_produto)       REFERENCES dm_suprimentos.dim_produto(sk_produto),
    CONSTRAINT fk_dms_fc_fornecedor    FOREIGN KEY (sk_fornecedor)    REFERENCES dm_suprimentos.dim_fornecedor(sk_fornecedor)
);

CREATE INDEX idx_dms_fc_produto    ON dm_suprimentos.fato_compras(sk_produto);
CREATE INDEX idx_dms_fc_fornecedor ON dm_suprimentos.fato_compras(sk_fornecedor);


-- =====================================================================
-- DATAMART 3 - LOGÍSTICA / ENTREGAS  (assunto: distribuição)
-- Pergunta de negócio: qual transportadora entrega mais rápido e a que
-- frete; onde estão os destinos e como o prazo se comporta.
-- =====================================================================
CREATE TABLE dm_logistica.dim_tempo (
    sk_tempo             INTEGER     NOT NULL,
    data                 DATE        NOT NULL,
    ano                  SMALLINT    NOT NULL,
    semestre             SMALLINT    NOT NULL,
    trimestre            SMALLINT    NOT NULL,
    mes                  SMALLINT    NOT NULL,
    nome_mes             VARCHAR(15) NOT NULL,
    dia                  SMALLINT    NOT NULL,
    dia_semana           SMALLINT    NOT NULL,
    nome_dia_semana      VARCHAR(15) NOT NULL,
    eh_fim_semana        BOOLEAN     NOT NULL,
    eh_feriado           BOOLEAN     NOT NULL,
    eh_ponto_facultativo BOOLEAN     NOT NULL,
    nome_feriado         VARCHAR(60),
    CONSTRAINT pk_dml_tempo PRIMARY KEY (sk_tempo)
);

-- LGPD: versão MINIMIZADA - sem CPF mascarado e sem faixa de renda,
-- porque o assunto é entrega, não perfil de consumo.
CREATE TABLE dm_logistica.dim_cliente (
    sk_cliente  INTEGER      NOT NULL,
    id_pessoa   INTEGER,
    customer_id VARCHAR(5),
    origem      VARCHAR(10)  NOT NULL,
    nome        VARCHAR(255),
    tipo_pessoa INTEGER,
    pais        VARCHAR(40),
    versao      INTEGER      NOT NULL,
    data_inicio DATE         NOT NULL,
    data_fim    DATE,
    flag_atual  BOOLEAN      NOT NULL,
    CONSTRAINT pk_dml_cliente PRIMARY KEY (sk_cliente)
);

CREATE TABLE dm_logistica.dim_localidade (
    sk_localidade INTEGER      NOT NULL,
    nm_estado     VARCHAR(60),
    sigla_uf      VARCHAR(30),
    nm_cidade     VARCHAR(255),
    pais          VARCHAR(40)  NOT NULL,
    codigo_ibge   VARCHAR(10),
    populacao     INTEGER,
    populacao_ano SMALLINT,
    CONSTRAINT pk_dml_local PRIMARY KEY (sk_localidade)
);

CREATE TABLE dm_logistica.dim_transportadora (
    sk_transportadora INTEGER     NOT NULL,
    shipper_id        SMALLINT,
    nome              VARCHAR(80) NOT NULL,
    telefone          VARCHAR(40),
    CONSTRAINT pk_dml_transportadora PRIMARY KEY (sk_transportadora)
);

CREATE TABLE dm_logistica.fato_entregas (
    sk_fato_entrega    BIGINT        NOT NULL,
    num_pedido         VARCHAR(20)   NOT NULL,
    sk_tempo_pedido    INTEGER       NOT NULL,
    sk_tempo_expedicao INTEGER,
    sk_cliente         INTEGER,
    sk_localidade      INTEGER,
    sk_transportadora  INTEGER,
    vlr_frete          NUMERIC(14,2),
    qtd_itens          INTEGER,
    prazo_dias         INTEGER,
    CONSTRAINT pk_dml_fato_entregas PRIMARY KEY (sk_fato_entrega),
    CONSTRAINT fk_dml_fe_tempo_pedido  FOREIGN KEY (sk_tempo_pedido)    REFERENCES dm_logistica.dim_tempo(sk_tempo),
    CONSTRAINT fk_dml_fe_tempo_exped   FOREIGN KEY (sk_tempo_expedicao) REFERENCES dm_logistica.dim_tempo(sk_tempo),
    CONSTRAINT fk_dml_fe_cliente       FOREIGN KEY (sk_cliente)         REFERENCES dm_logistica.dim_cliente(sk_cliente),
    CONSTRAINT fk_dml_fe_localidade    FOREIGN KEY (sk_localidade)      REFERENCES dm_logistica.dim_localidade(sk_localidade),
    CONSTRAINT fk_dml_fe_transportadora FOREIGN KEY (sk_transportadora) REFERENCES dm_logistica.dim_transportadora(sk_transportadora)
);

CREATE INDEX idx_dml_fe_tempo  ON dm_logistica.fato_entregas(sk_tempo_pedido);
CREATE INDEX idx_dml_fe_transp ON dm_logistica.fato_entregas(sk_transportadora);

-- =====================================================================
-- DICIONÁRIO (comentários)
-- =====================================================================
COMMENT ON SCHEMA dm_vendas      IS 'DataMart de Vendas: desempenho comercial (fato no grão de item)';
COMMENT ON SCHEMA dm_suprimentos IS 'DataMart de Suprimentos: compras e abastecimento (grão de item)';
COMMENT ON SCHEMA dm_logistica   IS 'DataMart de Logistica: entregas e frete (grão de pedido)';

COMMENT ON TABLE dm_vendas.fato_vendas       IS 'Medidas em BRL; taxa_cambio registra a PTAX aplicada ao Northwind';
COMMENT ON TABLE dm_suprimentos.fato_compras IS 'Compras da Mercearia; vlr_unitario e o custo de aquisicao';
COMMENT ON TABLE dm_logistica.fato_entregas  IS 'Frete por pedido; prazo_dias = expedicao - pedido (SLA)';
COMMENT ON COLUMN dm_vendas.dim_produto.versao IS 'SCD2 preservado: o DataMart guarda TODAS as versoes usadas pelos fatos';
COMMENT ON COLUMN dm_logistica.dim_cliente.pais IS 'LGPD: dimensao minimizada (sem CPF e sem faixa de renda)';
