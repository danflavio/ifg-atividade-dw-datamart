-- =====================================================================
-- DIM_TEMPO - carga (dado derivado + calendário)
-- ---------------------------------------------------------------------
-- Granularidade : 1 linha por DIA
-- Período       : 1996-01-01 a 2026-12-31  ( = UNIÃO dos períodos dos fatos )
--     Northwind : pedidos de 1996-07-04 a 1998-05-06
--     Mercearia : vendas de 2024-10-01 a 2026-09-29
--   Gerar apenas o período recente deixaria as vendas do Northwind SEM
--   linha na dimensão (FK órfã). Dimensão conformada cobre a união.
--
-- Feriados: calculados a partir da Páscoa (Meeus/Jones/Butcher) + fixos.
--   * Feriado legal     -> eh_feriado = TRUE
--   * Carnaval e Corpus Christi são PONTO FACULTATIVO (não feriado legal)
--     -> eh_ponto_facultativo = TRUE
--   * Lei 14.759/2023: 20/11 (Consciência Negra) é feriado nacional
--     a partir de 2024 - antes disso NÃO é marcado.
-- =====================================================================
SET search_path TO dw, public;

-- ---------------------------------------------------------------------
-- Base dos feriados móveis: Páscoa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dw.fn_pascoa(ano integer) RETURNS date AS $$
DECLARE
    a int; b int; c int; d int; e int; f int; g int;
    h int; i int; k int; l int; m int; mes int; dia int;
BEGIN
    a := ano % 19;
    b := ano / 100;
    c := ano % 100;
    d := b / 4;
    e := b % 4;
    f := (b + 8) / 25;
    g := (b - f + 1) / 3;
    h := (19 * a + b - d - g + 15) % 30;
    i := c / 4;
    k := c % 4;
    l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;
    mes := (h + l - 7 * m + 114) / 31;
    dia := ((h + l - 7 * m + 114) % 31) + 1;
    RETURN make_date(ano, mes, dia);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ---------------------------------------------------------------------
-- 1) Um registro por dia (nomes de mês/dia em português: o banco está em
--    locale C, então to_char devolveria inglês - por isso ARRAY explícito)
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_tempo (sk_tempo, data, ano, semestre, trimestre, mes,
                          nome_mes, dia, dia_semana, nome_dia_semana,
                          eh_fim_semana, eh_feriado, eh_ponto_facultativo,
                          nome_feriado)
SELECT
    to_char(g.d, 'YYYYMMDD')::int,
    g.d::date,
    EXTRACT(YEAR    FROM g.d)::smallint,
    CASE WHEN EXTRACT(MONTH FROM g.d) <= 6 THEN 1 ELSE 2 END,
    EXTRACT(QUARTER FROM g.d)::smallint,
    EXTRACT(MONTH   FROM g.d)::smallint,
    (ARRAY['janeiro','fevereiro','março','abril','maio','junho',
           'julho','agosto','setembro','outubro','novembro','dezembro']
    )[EXTRACT(MONTH FROM g.d)::int],
    EXTRACT(DAY FROM g.d)::smallint,
    EXTRACT(DOW FROM g.d)::smallint + 1,          -- 1=domingo .. 7=sábado
    (ARRAY['domingo','segunda-feira','terça-feira','quarta-feira',
           'quinta-feira','sexta-feira','sábado']
    )[EXTRACT(DOW FROM g.d)::int + 1],
    EXTRACT(DOW FROM g.d) IN (0, 6),
    FALSE, FALSE, NULL
FROM generate_series(DATE '1996-01-01', DATE '2026-12-31', INTERVAL '1 day') AS g(d);

-- ---------------------------------------------------------------------
-- 2) Feriados fixos (feriados legais nacionais)
-- ---------------------------------------------------------------------
WITH f(data, nome) AS (
              SELECT make_date(a, 1, 1),  'Confraternização Universal' FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 4, 21), 'Tiradentes'                 FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 5, 1),  'Dia do Trabalho'            FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 9, 7),  'Independência do Brasil'    FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 10, 12),'Nossa Senhora Aparecida'    FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 11, 2), 'Finados'                    FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 11, 15),'Proclamação da República'   FROM generate_series(1996, 2026) a
    UNION ALL SELECT make_date(a, 12, 25),'Natal'                      FROM generate_series(1996, 2026) a
    -- Lei 14.759/2023: nacional a partir de 2024
    UNION ALL SELECT make_date(a, 11, 20),'Consciência Negra'          FROM generate_series(2024, 2026) a
)
UPDATE dw.dim_tempo t
   SET eh_feriado = TRUE, nome_feriado = f.nome
  FROM f
 WHERE t.data = f.data;

-- ---------------------------------------------------------------------
-- 3) Feriados móveis: Sexta-feira Santa = Páscoa - 2 dias
-- ---------------------------------------------------------------------
UPDATE dw.dim_tempo t
   SET eh_feriado = TRUE,
       nome_feriado = 'Sexta-feira Santa (Paixão de Cristo)'
 WHERE t.data IN (SELECT dw.fn_pascoa(a) - 2 FROM generate_series(1996, 2026) a);

-- ---------------------------------------------------------------------
-- 4) Ponto facultativo: terça de Carnaval (Páscoa - 47) e Corpus Christi
--    (Páscoa + 60). NÃO são feriados legais - por isso flag separada.
-- ---------------------------------------------------------------------
UPDATE dw.dim_tempo t
   SET eh_ponto_facultativo = TRUE,
       nome_feriado = 'Carnaval (ponto facultativo)'
 WHERE t.data IN (SELECT dw.fn_pascoa(a) - 47 FROM generate_series(1996, 2026) a);

UPDATE dw.dim_tempo t
   SET eh_ponto_facultativo = TRUE,
       nome_feriado = 'Corpus Christi (ponto facultativo)'
 WHERE t.data IN (SELECT dw.fn_pascoa(a) + 60 FROM generate_series(1996, 2026) a);

ANALYZE dw.dim_tempo;

-- ---------------------------------------------------------------------
-- Conferência
-- ---------------------------------------------------------------------
SELECT count(*)                                        AS dias_gerados,
       min(data)                                       AS primeiro_dia,
       max(data)                                       AS ultimo_dia,
       count(*) FILTER (WHERE eh_feriado)              AS feriados,
       count(*) FILTER (WHERE eh_ponto_facultativo)    AS pontos_facultativos
FROM dw.dim_tempo;

-- Amostra (Semana Santa de 2026 e Natal)
SELECT data, nome_dia_semana, eh_feriado, eh_ponto_facultativo, nome_feriado
FROM dw.dim_tempo
WHERE data IN (DATE '2026-02-17', DATE '2026-04-03', DATE '2026-04-04',
               DATE '2026-06-04', DATE '2026-12-25', DATE '2025-11-20',
               DATE '2023-11-20')
ORDER BY data;
