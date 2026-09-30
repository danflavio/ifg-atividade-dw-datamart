# 📦 DataMarts — modelagem e justificativa

> Fase 4 da atividade. Documento pronto para virar seção do relatório técnico.

## O que é um DataMart (e por que não é o DW)

O **DW Organizacional** guarda o dado no menor grão, integrado e histórico — serve à organização inteira.
Um **DataMart** é um **recorte por assunto**: contém apenas o que um grupo de decisão precisa, no
formato que ele entende (estrela simples), sem navegar pelo DW inteiro.

Aqui os três DataMarts foram **materializados como esquemas independentes** (`dm_vendas`,
`dm_suprimentos`, `dm_logistica`) e **carregados a partir do DW** (`etl/30_carga_datamarts.sql`),
porque o entregável pede **DDL dos DataMarts**. As dimensões são **conformadas**: mantêm a
**mesma chave surrogate** do DW, então o mesmo produto/cliente/localidade é o mesmo membro nos
três DataMarts (verificado por teste automatizado em `etl/40_validacao_datamarts.sql`, bloco D3).

**Recorte aplicado:**
- em **linhas** → cada DataMart carrega só os membros de dimensão **usados pelos seus fatos**;
- em **colunas** → somente em `dm_logistica.dim_cliente`, onde CPF mascarado, faixa de renda e data de
  nascimento foram **omitidos** (princípio de **minimização** da LGPD: o assunto é entrega, não perfil);
- **SCD2 preservado** → entram **todas as versões** referenciadas pelos fatos. Se carregássemos só a
  versão vigente, as vendas antigas ficariam órfãs dentro do DataMart.

---

## 📊 DataMart 1 — VENDAS

| Item | Definição |
|---|---|
| **Assunto** | Desempenho comercial (o que vende, para quem, onde, por quem e quando) |
| **Fato** | `dm_vendas.fato_vendas` |
| **Grão** | 1 linha por **item de pedido/venda** (atômico) |
| **Dimensões** | `dim_tempo` (papel duplo: venda e faturamento) · `dim_produto` · `dim_cliente` · `dim_localidade` · `dim_vendedor` |
| **Medidas** | quantidade, vlr_unitario, pct_desconto, vlr_bruto, vlr_desconto, vlr_liquido (BRL) |
| **Volume** | 11.651 linhas (9.496 Mercearia + 2.155 Northwind) |

**Justificativa de uso.** É o DataMart de maior alcance: apoia decisões de **preço, mix de produtos,
campanhas e alocação de vendedor**. Perguntas típicas que ele responde:

1. Quais produtos/categorias mais faturam e quais giram em quantidade mas rendem pouco?
2. Como as vendas variam por mês, por **feriado** e por fim de semana (sazonalidade)?
3. Qual o desconto médio e quanto ele custa em receita (`vlr_desconto`)?
4. Atinge-se mais clientes PJ ou PF? (com duas fontes de origens diferentes: varejo BR e exportação)
5. Qual vendedor/região converte melhor?

**Uso do papel duplo de tempo:** permite medir o **tempo até o faturamento** e separar competência
de venda de competência de recebimento.

---

## 🛒 DataMart 2 — SUPRIMENTOS / COMPRAS

| Item | Definição |
|---|---|
| **Assunto** | Abastecimento e custo de aquisição |
| **Fato** | `dm_suprimentos.fato_compras` |
| **Grão** | 1 linha por **item de compra** |
| **Dimensões** | `dim_tempo` (papel duplo: data do pedido e data de entrada) · `dim_produto` · `dim_fornecedor` |
| **Medidas** | quantidade, vlr_unitario (custo), vlr_bruto |
| **Volume** | 302 linhas (somente Mercearia) |

**Justificativa de uso.** O professor exige integração entre as duas bases; o Northwind **não possui
compras** (só cadastro de fornecedores), então este DataMart é naturalmente da operação da Mercearia,
mas **compartilha a mesma `dim_produto` e a mesma `dim_tempo`** do DataMart de Vendas — o que permite
o cruzamento mais valioso do trabalho: **custo × preço de venda e margem por produto**.

Perguntas que responde:

1. Qual fornecedor oferece o **menor custo** por produto?
2. Qual é o **prazo de entrega do fornecedor** (pedido → entrada) e quem atrasa?
3. A compra foi feita **antes ou depois** de um aumento de preço na fonte (histórico SCD2 do produto)?
4. Qual a **margem bruta** por produto (`preco de venda` − `custo de aquisição`)?

---

## 🚚 DataMart 3 — LOGÍSTICA / ENTREGAS

| Item | Definição |
|---|---|
| **Assunto** | Distribuição, frete e prazo de entrega |
| **Fato** | `dm_logistica.fato_entregas` |
| **Grão** | 1 linha por **pedido/entrega** (agregado — e **é isso que importa aqui**) |
| **Dimensões** | `dim_tempo` (papel duplo: pedido e expedição) · `dim_cliente` (minimizada) · `dim_localidade` · `dim_transportadora` |
| **Medidas** | vlr_frete (BRL), qtd_itens, prazo_dias |
| **Volume** | 830 linhas (somente Northwind) |

**Justificativa de uso.** Existe por uma razão técnica que vale nota: o **frete é medido no pedido**, não
no item. Se ele morasse no `fato_vendas` (grão de item), o valor seria **repetido em cada item** do
mesmo pedido — dupla contagem — ou teria de ser rateado, criando um número que não existe na origem.
Em vez de distorcer o dado, criou-se **um fato no grão correto**. É a demonstração prática do
conceito de **granularidade** exigido pelo professor.

Perguntas que responde:

1. Qual **transportadora** tem o melhor **prazo médio** e o maior custo de frete?
2. O frete por pedido **cresce com o número de itens** (`qtd_itens`)?
3. Quais **destinos** concentram pedidos e quais têm prazo pior?
4. O prazo estoura em períodos de **feriado** (cruzando com `dim_tempo`)?

---

## 🔗 Comparativo (o "barramento" de dimensões conformadas)

| Dimensão | Vendas | Suprimentos | Logística |
|---|:---:|:---:|:---:|
| `dim_tempo` (papel duplo em todos) | ✅ | ✅ | ✅ |
| `dim_produto` (com SCD2) | ✅ | ✅ | — |
| `dim_cliente` (minimizada na logística) | ✅ | — | ✅ |
| `dim_localidade` | ✅ | — | ✅ |
| `dim_fornecedor` | — | ✅ | — |
| `dim_vendedor` | ✅ | — | — |
| `dim_transportadora` | — | — | ✅ |

**Consequência positiva:** um produto tem a **mesma chave** em Vendas e Suprimentos, e uma localidade
tem a **mesma chave** em Vendas e Logística. Portanto é possível combinar fatos (ex.: vendas por
transportadora que atendeu a região) sem depender de nomes — que é justamente o que a
**conformidade de dimensões** pretende garantir.
