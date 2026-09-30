# 🏛️ ifg-atividade-dw-datamart

> Construção de um **Data Warehouse Organizacional** integrando duas bases distintas
> (**Northwind** e **Mercearia**) e derivação de **DataMarts** para análise de dados.

![Status](https://img.shields.io/badge/status-Fases%200--3%20concluídas-yellow)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-compose-2496ED?logo=docker&logoColor=white)
![Licença](https://img.shields.io/badge/licen%C3%A7a-acad%C3%AAmica-lightgrey)

---

## 📚 Contexto acadêmico

| Campo | Valor |
|---|---|
| **Instituição** | IFG — Campus Goiânia |
| **Disciplina** | Tópicos Avançados em Inteligência Artificial I |
| **Professor** | Sirlon Diniz |
| **Entrega** | 30/09/2026 |
| **Autor** | Daniel Flávio |

### 🎯 Objetivo da atividade

1. Construir um **DW Organizacional** integrando os DDLs **Northwind** e **Mercearia**.
2. A partir do DW, apresentar **pelo menos 3 modelagens de DataMart** (assunto, fatos, dimensões e justificativa).
3. Aplicar **ferramentas de análise de dados** sobre o DW e os DataMarts.

> **Requisitos do professor:** dados externos + dimensão Tempo, respeitando **granularidade**,
> **integração** e **historicidade**. Observar **LGPD** quando aplicado a dados reais.

---

## 🗂️ Estrutura do projeto

```
ifg-atividade-dw-datamart/
├── docker-compose.yml                  # PostgreSQL 16 local (ambiente reprodutível)
├── sql/
│   ├── northwind.sql                   # Fonte 1 — dump COM dados (sample público)
│   ├── SQL criação DB Mercearia.sql    # Fonte 2 — apenas DDL (sem dados)
│   ├── seed_mercearia.sql              # Fonte 2 — dados SINTÉTICOS declarados
│   ├── 01_dw_organizacional.sql        # DDL do DW (7 dimensões + 3 fatos)
│   ├── 02_dim_tempo.sql                # Dim_Tempo (1996-2026) + feriados
│   └── 03_dados_externos.sql           # Schema ext: IBGE + PTAX + de-para de país
├── etl/
│   ├── 00_carga_inicial.sh             # Carga COMPLETA em 1 comando
│   ├── 05_extrair_dados_externos.ps1   # Extração IBGE/BCB (documentada)
│   ├── 10_carga_dimensoes.sql          # ETL — dimensões
│   ├── 20_carga_fatos.sql              # ETL — fatos (conversão de moeda)
│   ├── 90_teste_scd2.sql               # Teste de historicidade (SCD Tipo 2)
│   └── 99_validacao.sql                # Testes de integridade origem x DW
├── dados_externos/
│   ├── README.md                       # fontes, endpoints e data de acesso
│   ├── ibge_municipios.csv
│   └── ptax_dolar_1996_1998.csv
├── analise/
│   ├── analise_dw_datamarts.py         # Python + SQL sobre o DW e os DataMarts
│   ├── figuras/                        # 8 graficos gerados (PNG)
│   └── resultados/                     # 11 tabelas geradas (CSV)
├── docs/
│   ├── RELATORIO-TECNICO.md            # RELATORIO TECNICO (entregavel)
│   ├── datamarts.md                    # modelagem e justificativa dos 3 DataMarts
│   ├── analises.md                     # resultados das analises
│   ├── diagramas.md                    # diagramas Mermaid (DW e DataMarts)
│   └── guia-de-bolso.md                # resumo de defesa (conceitos + numeros)
├── ROADMAP.md                          # Checklist das fases + decisões
├── README.md
└── temp/                               # Rascunhos locais (ignorado pelo git)
```

---

## 🏗️ Modelo do Data Warehouse

### Fatos

| Fato | Grão | Origem | Medidas (BRL) |
|---|---|---|---|
| `fato_vendas` | **item** de pedido | Mercearia + Northwind | quantidade, vlr_unitario\*, pct_desconto\*, vlr_bruto, vlr_desconto, vlr_liquido |
| `fato_compras` | **item** de compra | Mercearia | quantidade, vlr_unitario\*, vlr_bruto |
| `fato_entregas` | **pedido**/entrega | Northwind | vlr_frete, qtd_itens, prazo_dias |

\* medidas **não-aditivas** (não podem ser somadas).

> **Por que três fatos e não um?** O frete é medido no **pedido**; colocá-lo no fato de item
> duplicaria o valor a cada item. Grãos diferentes exigem fatos diferentes — com dimensões
> **conformadas** (mesmo tempo, cliente e localidade nos três).

### Dimensões

| Dimensão | Origem — Mercearia | Origem — Northwind | Recursos |
|---|---|---|---|
| `dim_tempo` | `Vendas.DATA_VENDA`/`DATA_FATURAMENTO` | `orders.order_date`/`shipped_date` | 11.323 dias, feriados e pontos facultativos |
| `dim_cliente` | `Pessoas` | `customers` | SCD2 (faixa de renda) · LGPD |
| `dim_produto` | `Produtos`/`Categorias` | `products`/`categories` | SCD2 (preço) |
| `dim_localidade` | `Bairros→Cidades→Uf` | `ship_city`/`ship_region` (21 países) | IBGE, população |
| `dim_vendedor` | — | `employees` | |
| `dim_fornecedor` | `Pessoas` (tipo 3) | `suppliers` | |
| `dim_transportadora` | — | `shippers` | apoia o DataMart Logística |

### Conceitos aplicados

- **Granularidade:** item de pedido (vendas/compras) e pedido (entregas).
- **Integração:** chaves naturais por origem + de-para de país (`Brazil` ≠ `Brasil`) + código IBGE.
- **Historicidade:** SCD Tipo 2 em produto e cliente, **demonstrada** em `etl/90_teste_scd2.sql`.
- **Dimensão com papéis:** `dim_tempo` usada 2× em cada fato.
- **Dimensão degenerada:** `num_pedido` / `num_compra` dentro do fato.
- **Homogeneidade das medidas:** tudo em BRL; USD convertido pela PTAX do dia, com `taxa_cambio` gravada.
- **LGPD:** `cpf_cnpj_masked`, `faixa_renda`; a tabela `Telefones` **não** entra no DW.

---

## 🚀 Como executar

> Pré-requisito: **Docker Desktop** em execução.

```bash
# 1. subir o PostgreSQL 16 (cria o banco dw_atividade)
docker compose up -d

# 2. carga completa: fontes -> externos -> DW -> dim_tempo -> ETL -> validação
docker compose exec -T db sh /etl/00_carga_inicial.sh
```

| Comando | Efeito |
|---|---|
| `docker compose exec -T db psql -U postgres -d dw_atividade` | abre o `psql` no banco |
| `docker compose exec -T db psql -U postgres -d dw_atividade -f /etl/90_teste_scd2.sql` | roda o teste de historicidade (destrutivo) |
| `docker compose down` | derruba o container **mantendo** os dados |
| `docker compose down -v` | derruba e **apaga** (carga limpa) |

Conexão por ferramenta externa (DBeaver/pgAdmin/Python): **`localhost:5432`, banco `dw_atividade`,
usuário `postgres`, senha `postgres`**.

> ⚠️ **Pegadinha comum:** conecte no banco **`dw_atividade`** — no banco `postgres` (padrão do DBeaver)
> as tabelas não existem. Se der `relation does not exist`, rode:
> `SELECT current_database();` e lembre que nomes de tabela **não** levam aspas.

Sugestão de `search_path` para consultar tudo sem prefixo:

```sql
SET search_path TO dw, public, ext;
```

---

## 📊 O que já está carregado

| Conjunto | Linhas |
|---|---|
| `dw.fato_vendas` (9.496 Mercearia + 2.155 Northwind) | **11.651** |
| `dw.fato_compras` | 302 |
| `dw.fato_entregas` | 830 |
| `dw.dim_tempo` | 11.323 |
| `dw.dim_localidade` (121 Brasil + 66 exterior) | 187 |
| `dw.dim_cliente` / `dim_produto` | 151 / 107 |
| Total vendido (BRL, já convertido) | **R$ 1.991.124,46** |

---

## 🗺️ Roadmap

O acompanhamento detalhado está em **[`ROADMAP.md`](ROADMAP.md)**.

| Fase | Descrição | Status |
|---|---|---|
| 0 | Ambiente e carga das fontes | ✅ |
| 1 | Análise de integração das fontes | ✅ |
| 2 | DDL do DW Organizacional | ✅ |
| 3 | Dim_Tempo · Dados externos · ETL | ✅ |
| 4 | DataMarts (≥ 3) | ✅ |
| 5 | Análise de dados | ✅ |
| 6 | Relatório técnico | ✅ |
| 7 | Entrega | ⬜ |

---

## 🔒 Privacidade e LGPD

- O arquivo original da Mercearia contém **apenas DDL** (sem dados pessoais).
- Os dados da Mercearia usados aqui são **sintéticos e declarados** (`sql/seed_mercearia.sql`):
  CPF/CNPJ são **inválidos por construção** (dígitos verificadores não calculados) e nomes/empresas são fictícios.
- O `northwind.sql` é o *sample* público e fictício.
- No DW, atributos sensíveis são **mascarados** (`cpf_cnpj_masked`) ou **generalizados** (`faixa_renda`).
- A tabela `Telefones` **não** é carregada no DW — não há justificativa analítica para telefone.

---

## 🧠 Nota sobre o método

O projeto foi conduzido em **Modo Mentor (Aprendizado Guiado)**: os conceitos de modelagem
dimensional (grão, integração, historicidade, dados externos) foram discutidos e decididos pelo
autor; os artefatos mecânicos (DDL, ETL, documentação) foram acelerados com o agente.
O histórico de decisões está em [`ROADMAP.md`](ROADMAP.md).

---

## 📄 Licença

Projeto de uso **acadêmico**. As bases Northwind e Mercearia pertencem aos seus respectivos autores.
