-- =====================================================================
-- SEED SINTÉTICO - FONTE "MERCEARIA"  (staging: schema public)
-- IFG / Tópicos Avançados em IA I - Daniel Flávio
-- =====================================================================
--
--  [!]  DECLARAÇÃO OBRIGATÓRIA - DADOS SINTÉTICOS
--
--  Este arquivo NÃO contém dados reais e não foi extraído de nenhuma base
--  em produção. O material de origem da Mercearia
--  (sql/SQL criação DB Mercearia.sql) traz apenas DDL, sem registros.
--  Para que a integração das duas fontes seja DEMONSTRÁVEL (e não apenas
--  desenhada), os registros abaixo são GERADOS por script, com finalidade
--  exclusivamente didática.
--
--    * Nomes de pessoas e de empresas são fictícios.
--    * CPF/CNPJ são INVÁLIDOS por construção (dígitos verificadores não
--      calculados). Existem apenas para exercitar o mascaramento (LGPD).
--    * CEPs e nomes de bairros/logradouros são genéricos e sintéticos.
--    * As UFs usam os códigos reais do IBGE (dado público).
--    * A série de vendas cobre 24 meses (2024-10-01 a 2026-09-29) com
--      sazonalidade simulada (dezembro e fins de semana vendem mais).
--
--  Geração pseudoaleatória com `setseed`, para ser aproximadamente
--  reprodutível. Rodar este script de novo APAGA e recria os dados.
--
--  Convenções de domínio adotadas (o DDL original não as documenta):
--    Pessoas.TIPO_PESSOA    1 = cliente pessoa física
--                           2 = cliente pessoa jurídica
--                           3 = fornecedor (pessoa jurídica)
--    Vendas.TIPO_VENDA      1 = balcão | 2 = telefone | 3 = online
--    Enderecos.TIPO_ENDERECO 1 = residencial | 2 = comercial | 3 = cobrança
--    Logradouros.TIPO       1 = rua | 2 = avenida | 3 = praça
--    Telefones.TIPO         1 = celular | 2 = fixo
--    Categorias (1..6)      Bebidas | Mercearia | Limpeza | Higiene |
--                           Padaria | Hortifruti
--
--  Uso:
--    docker compose exec -T db psql -U postgres -d dw_atividade \
--        -f /sql/seed_mercearia.sql
-- =====================================================================

BEGIN;
SET search_path TO public;

-- ---------------------------------------------------------------------
-- 0. Limpeza (idempotência): zera as tabelas da Mercearia
-- ---------------------------------------------------------------------
TRUNCATE TABLE Itens_Vendas, Vendas, Itens_compras, Compras,
               Telefones, Enderecos, Logradouros,
               Bairros, Cidades, Uf, Pessoas, Profissoes,
               Produtos, Categorias
    CASCADE;

-- ---------------------------------------------------------------------
-- 1. UF - códigos reais do IBGE (dado público)
-- ---------------------------------------------------------------------
INSERT INTO Uf (ID_UF, NOME_ESTADO, SIGLA) VALUES
 (11,'Rondônia','RO'),          (12,'Acre','AC'),
 (13,'Amazonas','AM'),          (14,'Roraima','RR'),
 (15,'Pará','PA'),              (16,'Amapá','AP'),
 (17,'Tocantins','TO'),         (21,'Maranhão','MA'),
 (22,'Piauí','PI'),             (23,'Ceará','CE'),
 (24,'Rio Grande do Norte','RN'),(25,'Paraíba','PB'),
 (26,'Pernambuco','PE'),        (27,'Alagoas','AL'),
 (28,'Sergipe','SE'),           (29,'Bahia','BA'),
 (31,'Minas Gerais','MG'),      (32,'Espírito Santo','ES'),
 (33,'Rio de Janeiro','RJ'),    (35,'São Paulo','SP'),
 (41,'Paraná','PR'),            (42,'Santa Catarina','SC'),
 (43,'Rio Grande do Sul','RS'), (50,'Mato Grosso do Sul','MS'),
 (51,'Mato Grosso','MT'),       (52,'Goiás','GO'),
 (53,'Distrito Federal','DF');

-- ---------------------------------------------------------------------
-- 2. Cidades (ID próprio; nomes reais, apenas como referência geográfica)
-- ---------------------------------------------------------------------
INSERT INTO Cidades (ID_CIDADE, NOME_CIDADE, ID_UF) VALUES
 (1,'Goiânia',52),                (2,'Aparecida de Goiânia',52),
 (3,'Anápolis',52),               (4,'Rio Verde',52),
 (5,'Brasília',53),               (6,'São Paulo',35),
 (7,'Campinas',35),               (8,'Santos',35),
 (9,'Rio de Janeiro',33),         (10,'Niterói',33),
 (11,'Belo Horizonte',31),        (12,'Uberlândia',31),
 (13,'Curitiba',41),              (14,'Londrina',41),
 (15,'Porto Alegre',43),          (16,'Caxias do Sul',43),
 (17,'Salvador',29),              (18,'Feira de Santana',29),
 (19,'Recife',26),                (20,'Olinda',26),
 (21,'Fortaleza',23),             (22,'Manaus',13),
 (23,'Belém',15),                 (24,'Natal',24),
 (25,'João Pessoa',25),           (26,'Maceió',27),
 (27,'Aracaju',28),               (28,'Teresina',22),
 (29,'São Luís',21),              (30,'Cuiabá',51),
 (31,'Campo Grande',50),          (32,'Florianópolis',42),
 (33,'Joinville',42),             (34,'Vitória',32),
 (35,'Palmas',17),                (36,'Porto Velho',11),
 (37,'Rio Branco',12),            (38,'Macapá',16),
 (39,'Boa Vista',14);

-- ---------------------------------------------------------------------
-- 3. Bairros: 3 por cidade (nomes genéricos, sintéticos)
-- ---------------------------------------------------------------------
INSERT INTO Bairros (ID_BAIRRO, NOME_BAIRRO, REGIAOCIDADE, ID_CIDADE)
SELECT (c.ID_CIDADE - 1) * 3 + b.idx,
       (ARRAY['Centro','Jardim Primavera','Vila Nova'])[b.idx],
       (ARRAY['Região Central','Zona Norte','Zona Sul'])[b.idx],
       c.ID_CIDADE
FROM Cidades c
CROSS JOIN (VALUES (1),(2),(3)) AS b(idx);

-- ---------------------------------------------------------------------
-- 4. Logradouros: 3 por bairro (CEP sintético)
-- ---------------------------------------------------------------------
INSERT INTO Logradouros (ID_LOGRADOURO, TIPO, LOGRADOURO, CEP,
                         NUMEROINICIAL, NUMEROFINAL, ID_BAIRRO)
SELECT (b.ID_BAIRRO - 1) * 3 + t.idx,
       t.idx,
       (ARRAY['Rua das Palmeiras','Avenida Central','Praça da Matriz'])[t.idx],
       70000000 + ((b.ID_BAIRRO * 37 + t.idx) % 2000000),
       1, 999,
       b.ID_BAIRRO
FROM Bairros b
CROSS JOIN (VALUES (1),(2),(3)) AS t(idx);

-- ---------------------------------------------------------------------
-- 5. Profissões (ID_PROFISSAO é NOT NULL em Pessoas)
-- ---------------------------------------------------------------------
INSERT INTO Profissoes (ID_PROFISSAO, NOME_PROFISSAO) VALUES
 (1,'Comerciante'),   (2,'Professor(a)'),  (3,'Analista'),
 (4,'Autônomo(a)'),   (5,'Aposentado(a)'), (6,'Estudante'),
 (7,'Motorista'),     (8,'Técnico(a)'),    (9,'Empresário(a)'),
 (10,'Não informado');

-- ---------------------------------------------------------------------
-- 6. Clientes pessoa física - IDs 1..48
-- ---------------------------------------------------------------------
DO $$
DECLARE
    nomes      text[] := ARRAY['Ana','Bruno','Carla','Daniel','Eduardo',
        'Fernanda','Gustavo','Helena','Igor','Juliana','Leandro','Mariana',
        'Nelson','Olívia','Patrícia','Rafael','Simone','Thiago','Vanessa',
        'Wagner','Camila','Diego','Eliane','Fábio','Gabriela','Henrique',
        'Isabela','Jonas','Kelly','Lucas'];
    sobrenomes text[] := ARRAY['Almeida','Barbosa','Cardoso','Dias','Esteves',
        'Ferreira','Gonçalves','Martins','Nogueira','Oliveira','Pereira',
        'Queiroz','Ribeiro','Santos','Teixeira','Vasconcelos','Xavier',
        'Zanetti','Amorim','Braga','Castro','Duarte','Fonseca','Gomes',
        'Lima','Moraes','Neves','Pacheco','Rocha','Silveira'];
    civis      text[] := ARRAY['Solteiro(a)','Casado(a)','Divorciado(a)','Viúvo(a)'];
    id         integer;
BEGIN
    FOR id IN 1..48 LOOP
        INSERT INTO Pessoas (ID_PESSOA, ID_PROFISSAO, TIPO_PESSOA, NOME,
                             CPF_CNPJ, SEXO, RENDA, ESTADO_CIVIL, DATA_NASCIMENTO)
        VALUES (
            id,
            1 + ((id * 3) % 9),
            1,
            nomes[1 + ((id * 7)  % 30)] || ' ' || sobrenomes[1 + ((id * 11) % 30)],
            -- CPF SINTÉTICO E INVÁLIDO (verificação nunca calculada)
            '999.999.999-' || lpad(id::text, 2, '0'),
            CASE WHEN id % 2 = 0 THEN 'Masculino' ELSE 'Feminino' END,
            1500 + ((id * 733) % 20000),          -- renda exata (fictícia)
            civis[1 + (id % 4)],
            DATE '1960-01-01' + ((id * 217) % 16000)
        );
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 7. Clientes pessoa jurídica (IDs 49..60) e Fornecedores (IDs 61..72)
--    Razões sociais fictícias. CPF_CNPJ inválido por construção.
-- ---------------------------------------------------------------------
INSERT INTO Pessoas (ID_PESSOA, ID_PROFISSAO, TIPO_PESSOA, NOME, CPF_CNPJ,
                     SEXO, RENDA, ESTADO_CIVIL, DATA_NASCIMENTO)
VALUES
 (49,9,2,'Supermercado Aurora Ltda',        '99.999.999/0001-01','Jurídica',185000,'Não aplicável',DATE '1998-03-12'),
 (50,9,2,'Padaria Pão Dourado Ltda',        '99.999.999/0001-02','Jurídica', 96000,'Não aplicável',DATE '2004-07-01'),
 (51,9,2,'Mercado Bom Preço Ltda',          '99.999.999/0001-03','Jurídica',142000,'Não aplicável',DATE '2001-11-23'),
 (52,9,2,'Restaurante Sabor Caseiro Ltda',  '99.999.999/0001-04','Jurídica', 78000,'Não aplicável',DATE '2010-02-15'),
 (53,9,2,'Empório da Serra Ltda',           '99.999.999/0001-05','Jurídica', 61000,'Não aplicável',DATE '2013-09-30'),
 (54,9,2,'Lanchonete Estrela Ltda',         '99.999.999/0001-06','Jurídica', 45000,'Não aplicável',DATE '2016-05-20'),
 (55,9,2,'Distribuidora Vale Verde Ltda',   '99.999.999/0001-07','Jurídica',210000,'Não aplicável',DATE '1996-08-08'),
 (56,9,2,'Comercial Três Irmãos Ltda',      '99.999.999/0001-08','Jurídica', 88000,'Não aplicável',DATE '2008-12-05'),
 (57,9,2,'Hipermercado Central Ltda',       '99.999.999/0001-09','Jurídica',320000,'Não aplicável',DATE '1994-04-18'),
 (58,9,2,'Cafeteria Grão Fino Ltda',        '99.999.999/0001-10','Jurídica', 39000,'Não aplicável',DATE '2018-01-09'),
 (59,9,2,'Casa de Carnes Boi Forte Ltda',   '99.999.999/0001-11','Jurídica',124000,'Não aplicável',DATE '2006-06-27'),
 (60,9,2,'Rotisseria Bella Massa Ltda',     '99.999.999/0001-12','Jurídica', 52000,'Não aplicável',DATE '2015-10-14'),
 (61,9,3,'Atacado Aliança Ltda',            '99.999.999/0001-13','Jurídica',450000,'Não aplicável',DATE '1993-05-02'),
 (62,9,3,'Indústria Alimentícia Bonança S.A.','99.999.999/0001-14','Jurídica',780000,'Não aplicável',DATE '1988-09-19'),
 (63,9,3,'Distribuidora Bebidas Centro-Oeste Ltda','99.999.999/0001-15','Jurídica',360000,'Não aplicável',DATE '1997-02-11'),
 (64,9,3,'Laticínios Vale do Leite Ltda',   '99.999.999/0001-16','Jurídica',290000,'Não aplicável',DATE '2000-07-25'),
 (65,9,3,'Moinho Trigo Bom Ltda',           '99.999.999/0001-17','Jurídica',215000,'Não aplicável',DATE '1995-03-07'),
 (66,9,3,'Frigorífico Boi Branco S.A.',     '99.999.999/0001-18','Jurídica',690000,'Não aplicável',DATE '1991-11-29'),
 (67,9,3,'Higiene Total Distribuidora Ltda','99.999.999/0001-19','Jurídica',175000,'Não aplicável',DATE '2003-04-03'),
 (68,9,3,'Hortifruti Cerrado Ltda',         '99.999.999/0001-20','Jurídica',130000,'Não aplicável',DATE '2009-08-16'),
 (69,9,3,'Padaria Industrial Pão Nobre Ltda','99.999.999/0001-21','Jurídica',98000,'Não aplicável',DATE '2007-01-22'),
 (70,9,3,'Bebidas Sul Brasil Ltda',         '99.999.999/0001-22','Jurídica',240000,'Não aplicável',DATE '1999-06-10'),
 (71,9,3,'Alimentos Nutri Vida Ltda',       '99.999.999/0001-23','Jurídica',310000,'Não aplicável',DATE '2002-10-04'),
 (72,9,3,'Limpeza Brilho Ltda',             '99.999.999/0001-24','Jurídica',165000,'Não aplicável',DATE '2011-12-01');

-- ---------------------------------------------------------------------
-- 8. Endereços: 1 preferencial por pessoa + 20% com secundário
-- ---------------------------------------------------------------------
INSERT INTO Enderecos (ID_ENDERECO, ID_PESSOA, ID_LOGRADOURO, TIPO_ENDERECO,
                       COMPLEMENTO, PREFERENCIAL)
SELECT p.ID_PESSOA,
       p.ID_PESSOA,
       1 + ((p.ID_PESSOA * 17) % 351),
       CASE WHEN p.TIPO_PESSOA = 3 THEN 2 ELSE 1 END,
       NULL,
       B'1'
FROM Pessoas p;
-- (ID_ENDERECO = ID_PESSOA no endereço principal, para facilitar a leitura)

INSERT INTO Enderecos (ID_ENDERECO, ID_PESSOA, ID_LOGRADOURO, TIPO_ENDERECO,
                       COMPLEMENTO, PREFERENCIAL)
SELECT 1000 + p.ID_PESSOA,
       p.ID_PESSOA,
       1 + ((p.ID_PESSOA * 29) % 351),
       3,
       'Unidade 2',
       B'0'
FROM Pessoas p
WHERE (p.ID_PESSOA * 5) % 10 < 2;      -- ~20% das pessoas

-- ---------------------------------------------------------------------
-- 9. Telefones (1 celular + 1 fixo para ~50%) - NÃO vão para o DW (LGPD)
-- ---------------------------------------------------------------------
INSERT INTO Telefones (ID_TELEFONE, ID_PESSOA, DDD, TELEFONE, TIPO,
                       PREFERENCIAL, STATUS)
SELECT p.ID_PESSOA * 10 + t.idx,
       p.ID_PESSOA,
       ddd.ddd,
       CASE WHEN t.idx = 1
            THEN '9' || lpad(((p.ID_PESSOA * 7919 + 13) % 100000000)::text, 8, '0')
            ELSE lpad(((p.ID_PESSOA * 104729) % 10000000)::text, 8, '0')
       END,
       t.idx,
       CASE WHEN t.idx = 1 THEN B'1' ELSE B'0' END,
       'A'
FROM Pessoas p
JOIN Enderecos   e ON e.ID_PESSOA = p.ID_PESSOA AND e.PREFERENCIAL = B'1'
JOIN Logradouros l ON l.ID_LOGRADOURO = e.ID_LOGRADOURO
JOIN Bairros     b ON b.ID_BAIRRO = l.ID_BAIRRO
JOIN Cidades     c ON c.ID_CIDADE = b.ID_CIDADE
JOIN (VALUES (11,69),(12,68),(13,92),(14,95),(15,91),(16,96),(17,63),
             (21,98),(22,86),(23,85),(24,84),(25,83),(26,81),(27,82),
             (28,79),(29,71),(31,31),(32,27),(33,21),(35,11),(41,41),
             (42,48),(43,51),(50,67),(51,65),(52,62),(53,61)) AS ddd(id_uf, ddd)
     ON ddd.id_uf = c.ID_UF
CROSS JOIN (VALUES (1),(2)) AS t(idx)
WHERE t.idx = 1 OR (p.ID_PESSOA % 2 = 0);

-- ---------------------------------------------------------------------
-- 10. Categorias e Produtos
-- ---------------------------------------------------------------------
INSERT INTO Categorias (ID_CATEGORIA, NOME_CATEGORIA) VALUES
 (1,'Bebidas'), (2,'Mercearia'), (3,'Limpeza'),
 (4,'Higiene e Beleza'), (5,'Padaria'), (6,'Hortifruti');

INSERT INTO Produtos (ID_PRODUTO, ID_CATEGORIA, PRODUTO, VALOR_VENDA) VALUES
 (1,2,'Arroz Tipo 1 5kg',              24.90),
 (2,2,'Feijão Carioca 1kg',             8.49),
 (3,2,'Açúcar Refinado 1kg',            4.79),
 (4,2,'Óleo de Soja 900ml',             7.29),
 (5,2,'Café Torrado e Moído 500g',     17.90),
 (6,2,'Leite Integral 1L',              5.39),
 (7,2,'Macarrão Espaguete 500g',        4.29),
 (8,2,'Farinha de Trigo 1kg',           5.19),
 (9,2,'Sal Refinado 1kg',               2.49),
 (10,2,'Molho de Tomate 340g',          3.29),
 (11,1,'Refrigerante Cola 2L',          9.99),
 (12,1,'Suco de Laranja 1L',            7.49),
 (13,1,'Água Mineral 1,5L',             3.19),
 (14,1,'Cerveja Lata 350ml',            4.19),
 (15,1,'Energético 473ml',              9.49),
 (16,3,'Sabão em Pó 1,6kg',            18.90),
 (17,3,'Detergente 500ml',              2.99),
 (18,3,'Desinfetante 1L',               6.49),
 (19,3,'Amaciante 2L',                 12.90),
 (20,3,'Água Sanitária 1L',             4.49),
 (21,4,'Papel Higiênico 12 rolos',     22.90),
 (22,4,'Sabonete 90g',                  2.79),
 (23,4,'Creme Dental 90g',              5.29),
 (24,4,'Shampoo 350ml',                16.90),
 (25,4,'Fralda Descartável P 20un',    34.90),
 (26,5,'Pão de Queijo Congelado 400g', 14.90),
 (27,5,'Pão Francês 1kg',              12.90),
 (28,5,'Bolo de Cenoura 400g',         11.90),
 (29,6,'Banana Prata 1kg',              4.99),
 (30,6,'Tomate 1kg',                    5.99);

-- ---------------------------------------------------------------------
-- 11. Vendas + Itens_Vendas  (24 meses, com sazonalidade)
--     Clientes: IDs 1..60
-- ---------------------------------------------------------------------
SELECT setseed(0.42);

DO $$
DECLARE
    precos   numeric[] := ARRAY(SELECT VALOR_VENDA FROM Produtos ORDER BY ID_PRODUTO);
    v_venda  integer := 0;
    v_item   integer := 0;
    d        date;
    n_vendas integer;
    k        integer;
    v_prod   integer;
BEGIN
    FOR d IN SELECT generate_series(DATE '2024-10-01', DATE '2026-09-29',
                                    INTERVAL '1 day')::date LOOP
        n_vendas := CASE
            WHEN EXTRACT(MONTH FROM d) = 12   THEN 5 + floor(random() * 6)::int
            WHEN EXTRACT(ISODOW FROM d) >= 6  THEN 3 + floor(random() * 6)::int
            ELSE 1 + floor(random() * 6)::int
        END;

        FOR k IN 1..n_vendas LOOP
            v_venda := v_venda + 1;

            INSERT INTO Vendas (ID_VENDA, ID_PESSOA, DATA_VENDA,
                                DATA_FATURAMENTO, TIPO_VENDA)
            VALUES (v_venda,
                    1 + floor(random() * 60)::int,
                    d,
                    CASE WHEN random() < 0.92
                         THEN d + floor(random() * 13)::int
                    END,
                    1 + floor(random() * 3)::int);

            FOR k IN 1..(1 + floor(random() * 5)::int) LOOP
                v_item := v_item + 1;
                v_prod := 1 + floor(random() * 30)::int;
                INSERT INTO Itens_Vendas (ID_ITEMVENDA, ID_VENDA, ID_PRODUTO,
                                          QUANTIDADE, VLR_UNITARIO)
                VALUES (v_item, v_venda, v_prod,
                        1 + floor(random() * 12)::int,
                        precos[v_prod]);
            END LOOP;
        END LOOP;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 12. Compras + Itens_compras  (fornecedores: IDs 61..72)
--     Custo de aquisição ~ 65% do preço de venda
-- ---------------------------------------------------------------------
SELECT setseed(0.77);

DO $$
DECLARE
    precos     numeric[] := ARRAY(SELECT VALOR_VENDA FROM Produtos ORDER BY ID_PRODUTO);
    v_compra   integer;
    v_item     integer := 0;
    k          integer;
    v_prod     integer;
    v_pedido   date;
BEGIN
    FOR v_compra IN 1..150 LOOP
        v_pedido := DATE '2024-09-15' + floor(random() * 745)::int;

        INSERT INTO Compras (ID_COMPRA, DATA_PEDIDO, DATA_ENTRADA, ID_PESSOA)
        VALUES (v_compra,
                v_pedido,
                CASE WHEN random() < 0.95
                     THEN v_pedido + 2 + floor(random() * 19)::int
                END,
                61 + floor(random() * 12)::int);

        FOR k IN 1..(1 + floor(random() * 3)::int) LOOP
            v_item := v_item + 1;
            v_prod := 1 + floor(random() * 30)::int;
            INSERT INTO Itens_compras (ID_ITEMCOMPRA, ID_COMPRA, ID_PRODUTO,
                                       QUANTIDADE, VLR_UNITARIO)
            VALUES (v_item, v_compra, v_prod,
                    10 + floor(random() * 190)::int,
                    round(precos[v_prod] * 0.65, 2));
        END LOOP;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 13. Estatísticas para o planejador de consultas
-- ---------------------------------------------------------------------
ANALYZE Uf, Cidades, Bairros, Logradouros, Enderecos, Pessoas, Telefones,
        Categorias, Produtos, Vendas, Itens_Vendas, Compras, Itens_compras;

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência rápida (opcional)
-- ---------------------------------------------------------------------
SELECT 'Uf' AS tabela, count(*) FROM Uf
UNION ALL SELECT 'Cidades',      count(*) FROM Cidades
UNION ALL SELECT 'Bairros',      count(*) FROM Bairros
UNION ALL SELECT 'Logradouros',  count(*) FROM Logradouros
UNION ALL SELECT 'Enderecos',    count(*) FROM Enderecos
UNION ALL SELECT 'Pessoas',      count(*) FROM Pessoas
UNION ALL SELECT 'Telefones',    count(*) FROM Telefones
UNION ALL SELECT 'Produtos',     count(*) FROM Produtos
UNION ALL SELECT 'Vendas',       count(*) FROM Vendas
UNION ALL SELECT 'Itens_Vendas', count(*) FROM Itens_Vendas
UNION ALL SELECT 'Compras',      count(*) FROM Compras
UNION ALL SELECT 'Itens_compras',count(*) FROM Itens_compras
ORDER BY 1;
