# 🎒 Guia de Bolso — Defesa do Trabalho

> Uma página para revisar antes de apresentar. Cada resposta abaixo é **a do SEU projeto** — não é teoria solta.

---

## 1. Os 5 conceitos obrigatórios do enunciado (e onde estão no SEU trabalho)

| Conceito | O que é | Onde está no seu trabalho |
|---|---|---|
| **Granularidade** | o que cada linha da tabela de fatos representa | `fato_vendas` = **1 item** de pedido; `fato_entregas` = **1 pedido** (porque o frete é do pedido) |
| **Integração** | juntar fontes diferentes numa visão única | de-para de país (`Brazil`=`Brasil`), normalização de acento (`Sao Paulo`=`São Paulo`), código IBGE, dimensões conformadas |
| **Historicidade** | o passado não é reescrito quando o cadastro muda | **SCD Tipo 2** em `dim_produto` (preço) e `dim_cliente` (faixa de renda) |
| **Dimensão Tempo** | calendário pronto para analisar | `dim_tempo` com 11.323 dias (1996–2026), 281 feriados, 62 pontos facultativos, **papel duplo** |
| **Dados Externos** | dado de fora enriquece o DW | **IBGE** (código do município + população) e **BCB/PTAX** (dólar do dia) |

---

## 2. As 4 frases de ouro (decore estas)

1. **"O grão do meu fato de vendas é o item do pedido, e o frete ficou num fato separado porque ele é medido no pedido, não no item."**
2. **"A dimensão tempo cobre 1996 a 2026 porque é a união dos períodos das duas fontes — se eu gerasse só o período recente, as vendas do Northwind ficariam órfãs."**
3. **"O Northwind está em dólar, então converti para real pela PTAX do dia do pedido e gravei a taxa usada na própria linha, para poder auditar."**
4. **"Usei dimensões conformadas: o mesmo produto tem a mesma chave nos DataMarts de Vendas e de Suprimentos — é isso que me permite cruzar custo com preço de venda."**

---

## 3. Vocabulário mínimo (se ele usar o termo, você sabe o que é)

| Termo | Tradução simples |
|---|---|
| **Fato** | a tabela com os números que aconteceram (venda, compra, entrega) |
| **Dimensão** | a tabela que descreve o "quem, quando, onde, o quê" |
| **Dimensão conformada** | dimensão compartilhada por vários fatos, com a **mesma chave** |
| **Dimensão degenerada** | um atributo do fato que virou chave (ex.: `num_pedido`), sem tabela própria |
| **Papel duplo** | a mesma dimensão usada 2× no mesmo fato (data da venda e do faturamento) |
| **Medida aditiva** | pode somar (quantidade, valor) |
| **Medida não-aditiva** | não pode somar (preço unitário, percentual de desconto) |
| **SCD Tipo 2** | guarda histórico: cria nova versão e fecha a anterior, sem apagar |
| **DataMart** | recorte do DW para um assunto (estrela menor, mais simples) |
| **DW** | base integrada da organização inteira, no menor grão |
| **ETL** | extrair → transformar → carregar |

---

## 4. Números do seu projeto (se pedir "me dá um número")

| | |
|---|---|
| Fontes | Northwind **14 tabelas com dados** · Mercearia **14 tabelas só DDL** (massa sintética declarada) |
| Vendas carregadas | **11.651** linhas (9.496 Mercearia + 2.155 Northwind) |
| Faturamento total | **R$ 1.991.124,46** (USD já convertido pela PTAX) |
| `dim_tempo` | **11.323** dias · 281 feriados · 62 pontos facultativos |
| DataMarts | **3**: Vendas (11.651) · Suprimentos (302) · Logística (830) |
| Câmbio aplicado | de **1,0040** a **1,1445** BRL/USD |
| Testes | 13 contagens origem×DW iguais · **0 órfãos** · **0 divergência de conformidade** |
| Achado de análise | fim de semana vende **1,5×** mais; **feriado legal vende 21% menos** |

---

## 5. Perguntas prováveis do professor (com resposta curta)

**"Por que três fatos e não um?"**
Porque os grãos são diferentes. O frete é do pedido; se entrasse no fato de item, apareceria repetido em cada item do mesmo pedido (dupla contagem). Um fato por grão, com dimensões conformadas.

**"Onde está a historicidade?"**
No SCD Tipo 2 de `dim_produto` e `dim_cliente`: `versao`, `data_inicio`, `data_fim`, `flag_atual`. E eu testei: mudei o preço do Arroz, a versão 1 foi fechada, a versão 2 abriu — e as **324 vendas antigas continuaram ligadas à versão 1**, com o preço antigo.

**"Por que converter o dólar?"**
Porque somar dólar com real dá um número sem sentido (homogeneidade das medidas). Converti pela PTAX de compra do dia e **gravei a taxa na linha do fato** para poder auditar depois.

**"Isso aqui é dado real?"**
O Northwind é um *sample* público e fictício. A Mercearia veio **só com a estrutura**, então gerei uma massa **sintética declarada** — CPF inválido por construção, só para exercitar o mascaramento da LGPD. Está declarado no cabeçalho do script e no relatório.

**"Onde entra a LGPD?"**
Em quatro decisões: (1) telefone **não** vai para o DW; (2) CPF vira `***.***.***-XX`; (3) renda exata vira **faixa**; (4) no DataMart de Logística, CPF e renda nem existem — o assunto é entrega.

**"Por que a margem deu 35% para todo mundo?"**
Porque é **artefato da massa sintética** (gerei o custo como 65% do preço). O método do cruzamento está correto e provado; o número não é interpretável. Com dados reais a margem variaria.

**"O que você aprendeu de mais importante?"**
Que **teste de contagem não substitui teste de uso**: dois defeitos de integração (cidade com e sem acento, e a UF `SP` duplicada) passaram por todos os testes de contagem e só apareceram quando eu **usei** o dado na análise.

---

## 6. Se ele pedir para ver funcionando

```bash
docker compose up -d
docker compose exec -T db sh /etl/00_carga_inicial.sh     # carrega tudo do zero
python analise/analise_dw_datamarts.py                    # roda a analise e gera os graficos
```

No DBeaver, conecte no banco **`dw_atividade`** (não no `postgres`) e rode:

```sql
SET search_path TO dw, public, ext;
SELECT count(*) FROM fato_vendas;                      -- 11651
SELECT * FROM dim_tempo WHERE eh_feriado LIMIT 5;
```

---

## 7. Os 3 cuidados que evitam gafe na apresentação

1. **Não chame o DataMart de "relatório"** — é uma **estrutura de dados** (esquema estrela).
2. **Não diga que a Mercearia tem dados reais** — a massa é sintética e declarada.
3. **Não diga que "o DW é a soma das duas bases"** — o DW **integra** as duas por dimensões conformadas; `fato_compras` é só Mercearia e `fato_entregas` é só Northwind, e isso é esperado.
