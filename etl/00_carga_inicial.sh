#!/bin/sh
# =====================================================================
# CARGA COMPLETA do ambiente (Fases 0, 3 e 4 da atividade)
#   staging (fontes) -> dados externos -> DDL do DW -> dim_tempo
#   -> ETL das dimensoes -> ETL dos fatos -> validacao
#   -> DDL dos DataMarts -> ETL dos DataMarts -> validacao dos DataMarts
#
# Uso (na raiz do projeto, com o container no ar):
#   docker compose exec -T db sh /etl/00_carga_inicial.sh
# =====================================================================
set -eu

PSQL="psql -v ON_ERROR_STOP=1 -q -U postgres -d dw_atividade"

echo ">> [1/12] Staging: Northwind"
$PSQL -f /sql/northwind.sql

echo ">> [2/12] Staging: Mercearia (DDL)"
# o nome do arquivo tem acento; o glob evita problemas de encoding no shell
for f in /sql/*Mercearia*.sql; do
    $PSQL -f "$f"
done

echo ">> [3/12] Staging: Mercearia (dados SINTETICOS - ver cabecalho do arquivo)"
$PSQL -f /sql/seed_mercearia.sql

echo ">> [4/12] DW: dimensoes e fatos (DDL)"
$PSQL -f /sql/01_dw_organizacional.sql

echo ">> [5/12] Dados externos (schema ext: IBGE + PTAX)"
$PSQL -f /sql/03_dados_externos.sql

echo ">> [6/12] Dimensao tempo (1996-2026 + feriados)"
$PSQL -f /sql/02_dim_tempo.sql

echo ">> [7/12] ETL: dimensoes"
$PSQL -f /etl/10_carga_dimensoes.sql

echo ">> [8/12] ETL: fatos"
$PSQL -f /etl/20_carga_fatos.sql

echo ">> [9/12] Validacao do DW"
$PSQL -f /etl/99_validacao.sql

echo ">> [10/12] DataMarts (DDL)"
$PSQL -f /sql/04_datamarts.sql

echo ">> [11/12] ETL: DataMarts"
$PSQL -f /etl/30_carga_datamarts.sql

echo ">> [12/12] Validacao dos DataMarts"
$PSQL -f /etl/40_validacao_datamarts.sql

echo ">> OK: carga completa concluida"
