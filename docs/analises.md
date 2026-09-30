# 📈 Análise de Dados — DW e DataMarts

> Fase 5 da atividade. Resultados gerados por `analise/analise_dw_datamarts.py`
> (Python 3.13 + pandas + matplotlib + scikit-learn + psycopg2), conectado direto
> ao PostgreSQL `dw_atividade`.

**Como reproduzir:**

```bash
docker compose up -d
docker compose exec -T db sh /etl/00_carga_inicial.sh   # carrega fontes, DW e DataMarts
python analise/analise_dw_datamarts.py                  # gera resultados/ e figuras/
```

**Saídas:** 8 figuras em `analise/figuras/` e 11 tabelas em `analise/resultados/`.

---

## Visão geral (base de todas as análises)

| Objeto | Linhas |
|---|---|
| `dw.fato_vendas` = `dm_vendas.fato_vendas` | 11.651 |
| `dw.fato_compras` = `dm_suprimentos.fato_compras` | 302 |
| `dw.fato_entregas` = `dm_logistica.fato_entregas` | 830 |
| `dw.dim_tempo` | 11.323 |

Faturamento total: **R$ 1.991.124,46** (Mercearia R$ 613.837,33 · Northwind R$ 1.377.287,13, já convertido de USD pela PTAX do dia).
Prazo médio de entrega: **8,5 dias** · frete médio: **R$ 85,20** por pedido.

---

## 1. Evolução mensal do faturamento — `figuras/01_evolucao_mensal.png`

O gráfico mais importante do trabalho: mostra as **duas fontes no tempo**. O Northwind cobre 1996–1998;
a Mercearia, 2024–2026. Dezembro é o pico nas duas bases (sazonalidade consistente).

## 2. Top produtos por faturamento — `figuras/02_top_produtos.png`

| Produto | Origem | Faturamento (BRL) |
|---|---|---|
| Côte de Blaye | Northwind | 153.783,11 |
| Thüringer Rostbratwurst | Northwind | 88.077,39 |
| Fralda Descartável P 20un | Mercearia | 82.957,30 |
| Raclette Courdavault | Northwind | 77.630,11 |
| Tarte au sucre | Northwind | 51.231,83 |

**Achado:** o topo é dominado pelo Northwind, onde produtos alimentícios de alto valor unitário
(vinho, queijo francês) sustentam o faturamento. Na Mercearia, o faturamento é puxado por **volume** —
a fralda lidera, e os itens de mercearia aparecem muito atrás (Molho de Tomate, 4º no volume, fatura
apenas R$ 7.527,52). É o contraste clássico **valor unitário × giro**.

## 3. Faturamento por UF — `figuras/03_faturamento_uf.png`

| UF | Faturamento (BRL) | Pedidos |
|---|---|---|
| SP | 107.813,44 | 312 |
| RJ | 86.318,68 | 195 |
| GO | 57.938,17 | 295 |
| PR | 41.058,59 | 212 |
| RS | 36.789,29 | 176 |

**Achado:** SP e RJ lideram, mas repare em **GO**: 2º lugar em número de pedidos com o 3º faturamento
— ticket médio menor, comportamento de mercado local (a Mercearia é sediada em Goiás).
Esse cruzamento só existe porque a `dim_localidade` é **conformada** entre as duas fontes.

## 4. Sazonalidade — `figuras/04_sazonalidade.png`

| Dia da semana | Venda média/dia (BRL) |
|---|---|
| sábado | 1.143,19 |
| domingo | 1.139,02 |
| quinta-feira | 764,85 |
| segunda-feira | 749,24 |

| Tipo de dia | Venda média/dia (BRL) |
|---|---|
| Dia comum | 846,29 |
| **Feriado** | **670,76** |
| Ponto facultativo | 947,02 |

**Achado:** fim de semana vende **~1,5×** mais que um dia útil. Já o **feriado vende 21% menos** que um
dia comum — o oposto do senso comum. Explicação plausível: são feriados de calendário nacional e, no
caso da Mercearia, o consumidor antecipa a compra. Ponto facultativo (Carnaval/Corpus Christi) vende
**mais** — comportamento diferente de feriado legal, o que justifica a flag separada na `dim_tempo`.

## 5. Desempenho das transportadoras — `figuras/05_transportadoras.png`

| Transportadora | Pedidos | Prazo médio (dias) | Frete médio (BRL) | Frete total (BRL) |
|---|---|---|---|---|
| Federal Shipping | 255 | **7,5** | 87,00 | 22.183,97 |
| Speedy Express | 249 | 8,6 | **70,79** | 17.627,60 |
| United Package | 326 | 9,2 | 94,80 | 30.903,48 |

**Achado:** **United Package** carrega o maior volume de pedidos (326), tem o **pior prazo** (9,2 dias) e o
**maior frete médio** (R$ 94,80) — é a candidata natural a renegociação. **Federal Shipping** é a mais
rápida com frete intermediário. Não há trade-off "rápido x barato" nos dados: dá para barganhar preço
com a United sem perder prazo, ou migrar volume para a Federal.

## 6. Margem por produto (análise cruzada de DataMarts) — `figuras/06_margem.png`

O cruzamento entre `dm_suprimentos` (custo de compra) e `dm_vendas` (preço de venda) só é possível
porque as dimensões são **conformadas** — o mesmo `id_produto` existe nos dois DataMarts.

### ⚠️ Limitação (declarada de propósito)

**Todos os produtos apareceram com exatamente 35,0% de margem.** Isso **não é um achado de negócio** —
é um **artefato dos dados sintéticos**: no `sql/seed_mercearia.sql` o custo de compra foi gerado como
sempre 65% do preço de venda. Com dados reais, a margem variaria por produto e categoria.
O **método** está correto (o cruzamento roda e prova a conformidade); o **número** não é interpretável.

## 7. IA — Segmentação de clientes com K-Means (RFM) — `figuras/07_clusters_clientes.png`

Variáveis: **R**ecência (dias desde a última compra), **F**requência (nº de pedidos) e
**M**onetary (valor total). Padronizadas (`StandardScaler`), agrupadas em **k=3**.

| Segmento | Clientes | Recência média (dias) | Pedidos (médio) | Valor médio (BRL) |
|---|---|---|---|---|
| A — alto valor | 22 | 9,5 | 60,7 | 11.791,44 |
| B — intermediário | 13 | 46,2 | 51,0 | 10.035,22 |
| C — baixo valor | 25 | 9,3 | 46,9 | 8.958,80 |

**Achado:** o segmento **A** concentra os clientes que compram mais **e** recentemente. O segmento **B** é
o caso mais acionável: valor parecido com A, mas **46 dias** de recência — clientes que estavam
comprando bem e **esfriaram**; são o alvo natural de uma campanha de reativação.

### ⚠️ Limitação (declarada)

No seed sintético **todos** os clientes compram com frequência parecida (~50 pedidos em 2 anos), então a
frequência **F** quase não discrimina — os grupos acabaram separados sobretudo por **valor**. Com dados
reais, o RFM tende a separar melhor (é justamente o ponto forte dele).

## 8. IA — Projeção de vendas mensais — `figuras/08_previsao.png`

Regressão linear com duas variáveis: **tendência temporal** e **indicador de dezembro**.

| Métrica | Valor |
|---|---|
| R² do ajuste | **0,866** |
| Tendência | −31,76 BRL/mês (praticamente estável) |
| Efeito de dezembro | **+ R$ 21.686,08** acima dos meses comuns |
| Previsão (3 meses) | R$ 23.372,34 · R$ 23.340,58 · **R$ 44.994,89** (dezembro) |

**Achado:** o R² alto **não** vem de tendência de crescimento (que é praticamente zero), e sim do
**efeito de dezembro**. Ou seja: o modelo aprendeu que o negócio é estável com um pico anual — o que
reforça o achado de sazonalidade do item 4.

### ⚠️ Limitação (declarada)

É um modelo **didático** com 24 pontos e 2 variáveis. Não é um modelo de produção: não considera
feriados móveis, estoque, preço, promoção nem fatores externos. Um passo seguinte seria SARIMA ou
Prophet com as *features* de `dim_tempo` (feriados, dia da semana).

---

## ✅ Síntese dos achados

1. **Fim de semana vende ~1,5× mais** que dia útil, e **feriado legal vende 21% menos**.
2. **Dezembro** é o pico em **ambas** as bases — sazonalidade consistente entre fontes de épocas diferentes.
3. A Mercearia fatura por **volume**; o Northwind, por **valor unitário**.
4. **United Package**: maior volume, pior prazo e maior frete — prioridade de renegociação.
5. **13 clientes** (segmento B) com recência de 46 dias são a melhor oportunidade de reativação.
6. **SP** lidera faturamento, mas **GO** é o 2º em pedidos — efeito da base local.

## 🔎 O que a análise revelou sobre o **modelo** (e virou correção)

A execução da análise **encontrou dois defeitos** que a validação por contagem não pegaria:

| Defeito | Correção aplicada |
|---|---|
| `Sao Paulo` (Northwind) e `São Paulo` (Mercearia) como cidades diferentes | normalização de acento/caixa com `unaccent()` no ETL |
| UF `SP` aparecendo **duas vezes** (uma sem nome de estado) | preenchimento de `nm_estado` a partir da tabela `Uf` para destinos brasileiros |

Isso demonstra um princípio de qualidade de dados: **teste de contagem não substitui teste de uso** —
usar o dado é que revela inconsistência de rótulo.
