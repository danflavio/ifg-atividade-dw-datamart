# Roadmap — Atividade DW / DataMarts (IFG)

| Campo | Valor |
|---|---|
| Instituição | IFG — Campus Goiânia |
| Disciplina | Tópicos Avançados em Inteligência Artificial I |
| Professor | Sirlon Diniz |
| Entrega | 30/09/2026 |
| Status | Fases 0 a 6 concluídas · Fase 7 (revisão e entrega) em aberto |

**Fontes:** `sql/northwind.sql` (COM dados) + `sql/SQL criação DB Mercearia.sql` (SÓ DDL) + `sql/seed_mercearia.sql` (dados sintéticos declarados)
**Externos:** IBGE (município/população) e BCB/PTAX (USD→BRL), em `dados_externos/`
**Entregáveis:** DDLs do DW e dos DataMarts + Relatório Técnico

---

## 📌 Modelo implementado (v2)

**Grão dos fatos:** item de venda/pedido · item de compra · pedido/entrega

| Fato | Grão | Origem | Medidas |
|---|---|---|---|
| `dw.fato_vendas` | item de pedido | Mercearia + Northwind | quantidade, vlr_unitario*, pct_desconto*, vlr_bruto, vlr_desconto, vlr_liquido |
| `dw.fato_compras` | item de compra | Mercearia | quantidade, vlr_unitario*, vlr_bruto |
| `dw.fato_entregas` | pedido/entrega | Northwind | vlr_frete, qtd_itens, prazo_dias |

\* não-aditivas (não somar).

**Dimensões:** `dim_tempo` (dia) · `dim_localidade` · `dim_produto` · `dim_cliente` · `dim_vendedor` · `dim_fornecedor` · `dim_transportadora`

**Decisões-chave já registradas:**
- **Moeda:** tudo em **BRL**; o Northwind (USD) é convertido pela **PTAX de compra do dia**, e `taxa_cambio` + `moeda_origem` ficam gravados na linha do fato (auditabilidade).
- **Historicidade:** SCD Tipo 2 em `dim_produto` (preço) e `dim_cliente` (faixa de renda), **demonstrada** por `etl/90_teste_scd2.sql`.
- **Papel duplo:** `dim_tempo` usada 2x (venda/pedido e faturamento/expedição).
- **Dimensão degenerada:** `num_pedido` / `num_compra`.
- **Localidade conformada:** granularidade **bairro** no Brasil (enriquecida com código IBGE e população) e **cidade/região** no exterior — o Northwind envia para **21 países**, não apenas EUA.
- **Dados externos também exigem padronização:** `Brazil` (Northwind) e `Brasil` (Mercearia) viram o mesmo país via `ext.pais_nome`.

---

## Fase 0 — Ambiente e estrutura ✅ CONCLUÍDA

- [x] PostgreSQL 16 via **Docker** (`docker-compose.yml`, container `dw_atividade_db`)
- [x] Staging = schema **`public`** (Northwind + Mercearia; não há colisão de nomes)
- [x] Dados externos no schema **`ext`**; DW no schema **`dw`**
- [x] Carga reprodutível em **1 comando**: `etl/00_carga_inicial.sh`
- [x] Estrutura: `sql/` · `etl/` · `dados_externos/` · `docs/` (a criar) · `modelos/` (a criar)

**Contagens validadas:** Northwind 830 pedidos/2.155 itens · Mercearia 3.171 vendas/9.496 itens · DW 11.651 linhas de venda.

---

## Fase 1 — Análise das fontes e integração ✅ CONCLUÍDA

- [x] Inventário das 14 + 14 tabelas
- [x] Mapa de equivalências (Produto, Categoria, Cliente, Fornecedor, Localidade)
- [x] Chaves de integração: surrogate keys + chaves naturais com índice único
- [x] **Achados que mudaram o desenho:**
  - a Mercearia é **DDL sem dados** → resolvido com seed sintético declarado;
  - o Northwind **não é só EUA**: 21 países de destino; `ship_region` chega a 11 caracteres (ex.: `Brandenburg`) → `sigla_uf` foi ampliado para `VARCHAR(30)`;
  - 507 de 830 pedidos **não têm região** e 21 não têm expedição → nuláveis tratados no ETL;
  - rótulos de país em idiomas diferentes → tabela de padronização `ext.pais_nome`.

---

## Fase 2 — Modelagem do DW ✅ CONCLUÍDA

- [x] Kimball (estrela) + barramento de dimensões conformadas
- [x] DDL: `sql/01_dw_organizacional.sql` (idempotente: `DROP SCHEMA dw CASCADE`)
- [x] 7 dimensões + 3 fatos + índices + comentários (dicionário de dados)
- [x] Correções feitas após teste: índices únicos por chave natural, colunas de moeda, flag de ponto facultativo, `fato_entregas` em grão próprio

---

## Fase 3 — Dados externos, Dim_Tempo e ETL ✅ CONCLUÍDA

- [x] `dim_tempo`: 11.323 dias (1996-01-01 a 2026-12-31 = **união** dos períodos dos fatos), com 281 feriados legais e 62 pontos facultativos (`sql/02_dim_tempo.sql`)
- [x] Feriados calculados (Páscoa por Meeus/Jones/Butcher); Carnaval e Corpus Christi como **ponto facultativo** (não são feriados por lei); 20/11 como feriado só a partir de 2024 (Lei 14.759/2023)
- [x] **Dados externos reais:** `etl/05_extrair_dados_externos.ps1` → 39 municípios (IBGE) + 750 cotações PTAX
- [x] Câmbio: calendário com *carry forward* (`ext.cotacao_dolar_dia`)
- [x] ETL em 4 scripts: dimensões · fatos · teste SCD2 · validação
- [x] Testes: 13 contagens origem×DW iguais · 0 órfãos · 0 erro de identidade contábil · SCD2 com 1 versão vigente por chave

---

## Fase 4 — DataMarts (≥ 3) ✅ CONCLUÍDA

Três assuntos, cada um em **esquema estrela próprio**, carregado a partir do DW:

- [x] **DM 1 — Vendas** (`dm_vendas`): fato no grão de **item**; tempo (papel duplo), produto, cliente, localidade, vendedor — 11.651 linhas
- [x] **DM 2 — Suprimentos/Compras** (`dm_suprimentos`): grão de **item de compra**; tempo (papel duplo), produto, fornecedor — 302 linhas
- [x] **DM 3 — Logística/Entregas** (`dm_logistica`): grão de **pedido**; tempo (papel duplo), cliente (minimizado), localidade, transportadora — 830 linhas
- [x] DDL: `sql/04_datamarts.sql` · ETL: `etl/30_carga_datamarts.sql` · Validação: `etl/40_validacao_datamarts.sql`
- [x] Justificativa escrita (assunto · fato · dimensões · grão · uso): `docs/datamarts.md`
- [x] Diagramas (DW galáxia + 3 DataMarts): `docs/diagramas.md`

**Decisões registradas:**
- Dimensões **conformadas** com a **mesma chave surrogate** do DW → testes D3 confirmam 0 divergências entre DataMarts.
- Recorte em **linhas** (só os membros usados pelos fatos) e, na Logística, também em **colunas** (LGPD: sem CPF mascarado, faixa de renda e data de nascimento).
- **SCD2 preservado** nos DataMarts: entram todas as versões referenciadas pelos fatos.

---

## Fase 5 — Análise de dados ✅ CONCLUÍDA

- [x] Ferramenta: **Python 3.13** (pandas, matplotlib, scikit-learn, psycopg2) conectando direto no banco
- [x] Análise aplicada **ao DW e aos DataMarts** (8 gráficos + 11 tabelas)
- [x] Análises: evolução mensal, top produtos, faturamento por UF, sazonalidade (dia da semana/feriado), transportadoras, margem por produto (cruzamento de DataMarts)
- [x] Diferencial de IA: **K-Means (RFM)** para segmentação de clientes e **regressão linear** para projeção de vendas
- [x] Achados com número + limitações declaradas → `docs/analises.md`

**Script:** `analise/analise_dw_datamarts.py` · **Saídas:** `analise/figuras/` e `analise/resultados/`

**Achados que a análise revelou (viraram correção do modelo):** cidade com/sem acento duplicada e UF `SP` com dois rótulos — nenhum dos dois aparecia nos testes de contagem.

---

## Fase 6 — Relatório Técnico ✅ CONCLUÍDA (falta exportar)

- [x] **`docs/RELATORIO-TECNICO.md`** — todas as seções do enunciado: objetivo, fontes, arquitetura, granularidade, integração, historicidade, dados externos, dimensão tempo, LGPD, DataMarts, ETL + testes, análise, limitações, conclusão e referências
- [x] Declaração de integridade sobre os dados sintéticos da Mercearia
- [x] Tabela de defeitos encontrados e corrigidos durante a execução (evidência de processo)
- [x] Referências (Kimball, IBGE, BCB/PTAX, LGPD, Lei 14.759/2023)
- [ ] Exportar para DOCX/PDF e anexar/inserir os gráficos e diagramas

---

## Fase 7 — Entrega ⬜

- [ ] Roteiro de execução do zero (um comando) conferido
- [ ] DDLs em `sql/` + relatório em `docs/`
- [ ] Conferir os 3 itens da atividade e as OBS (dados externos, dimensão tempo, granularidade/integração/historicidade, LGPD)
- [ ] Entregar até **30/09/2026**

---

## Decisões que VOCÊ precisa tomar (não pule)

1. **Grão do DW** → ✅ decidido: item de pedido (+ pedido para frete)
2. **Localidade** → ✅ decidido: uma dimensão conformada com profundidade variável (bairro no BR, cidade/região no exterior)
3. **Dados externos** → ✅ decidido: IBGE + PTAX + feriados
4. **SCD Tipo 2** → ✅ decidido e demonstrado: preço do produto e faixa de renda
5. **Quais 3 DataMarts** → ✅ decidido e implementado: Vendas · Suprimentos/Compras · Logística
