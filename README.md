# 🏛️ ifg-atividade-dw-datamart

> Construção de um **Data Warehouse Organizacional** integrando duas bases distintas
> (**Northwind** e **Mercearia**) e derivação de **DataMarts** para análise de dados.

![Status](https://img.shields.io/badge/status-em%20andamento-yellow)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16+-336791?logo=postgresql&logoColor=white)
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
2. A partir do DW, apresentar **pelo menos 3 modelagens de DataMart** (assunto, fatos, dimensões e justificativa de uso).
3. Aplicar **ferramentas de análise de dados** sobre o DW e os DataMarts.

> **Requisitos do professor:** dados externos + dimensão Tempo, respeitando os conceitos de
> **granularidade**, **integração** e **historicidade**. Observar **LGPD** quando aplicado a dados reais.

---

## 🗂️ Estrutura do projeto

```
ifg-atividade-dw-datamart/
├── sql/
│   ├── northwind.sql                 # Fonte 1 — dump PostgreSQL (sample público)
│   ├── SQL criação DB Mercearia.sql  # Fonte 2 — DDL PostgreSQL (sem dados pessoais)
│   └── 01_dw_organizacional.sql      # DDL do Data Warehouse (dimensões + fatos)
├── ROADMAP.md                        # Roadmap/checklist das fases da atividade
├── README.md
└── temp/                             # Rascunhos locais (ignorado pelo git)
```

---

## 🏗️ Modelo do Data Warehouse (v1)

**Grão do fato de vendas:** 1 linha por **item de pedido** (atômico).

### Dimensões conformadas

| Dimensão | Origem — Mercearia | Origem — Northwind |
|---|---|---|
| `dim_tempo` | `Vendas.DATA_VENDA` / `DATA_FATURAMENTO` | `orders.order_date` |
| `dim_cliente` | `Pessoas` | `customers` |
| `dim_produto` | `Produtos` / `Categorias` | `products` / `categories` |
| `dim_localidade` | `Bairros → Cidades → Uf` | `ship_city` / `region` |
| `dim_vendedor` | — | `employees` |
| `dim_fornecedor` | `Pessoas` (fornecedor) | `suppliers` |

### Fatos

| Fato | Grão | Medidas |
|---|---|---|
| `fato_vendas` | item de pedido | `quantidade`, `vlr_unitario`, `pct_desconto`, `vlr_bruto`, `vlr_desconto`, `vlr_liquido` |
| `fato_compras` | item de compra | `quantidade`, `vlr_unitario`, `vlr_bruto` |

### Conceitos aplicados

- **Historicidade:** SCD Tipo 2 em `dim_produto` (preço) e `dim_cliente` (faixa de renda).
- **Dimensão com papéis (role-playing):** `dim_tempo` usada duas vezes (venda e faturamento).
- **Dimensão degenerada:** `num_pedido` no fato, sem virar tabela.
- **LGPD:** `cpf_cnpj_masked` e `faixa_renda` — CPF/renda nunca em claro.

---

## 🚀 Como executar

> Pré-requisito: PostgreSQL 14+ instalado.

```bash
# 1. criar o banco
createdb dw_atividade

# 2. carregar as fontes (staging no schema public)
psql -U postgres -d dw_atividade -f "sql/northwind.sql"
psql -U postgres -d dw_atividade -f "sql/SQL criação DB Mercearia.sql"

# 3. criar o data warehouse (schema dw)
psql -U postgres -d dw_atividade -f "sql/01_dw_organizacional.sql"
```

---

## 🗺️ Roadmap

O acompanhamento detalhado (fases, checklists e decisões) está em **[`ROADMAP.md`](ROADMAP.md)**.

| Fase | Descrição | Status |
|---|---|---|
| 0 | Ambiente e carga das fontes | ⬜ |
| 1 | Análise de integração das fontes | 🟡 |
| 2 | DDL do DW Organizacional | ✅ |
| 3 | Dim_Tempo · Dados externos · ETL | ⬜ |
| 4 | DataMarts (≥ 3) | ⬜ |
| 5 | Análise de dados | ⬜ |
| 6 | Relatório técnico | ⬜ |
| 7 | Entrega | ⬜ |

---

## 🔒 Privacidade e LGPD

- O arquivo da Mercearia contém **apenas DDL** (sem dados pessoais).
- O `northwind.sql` contém o *sample* público e amplamente conhecido (dados fictícios).
- No DW, atributos sensíveis são **mascarados** ou **generalizados** (`faixa_renda`).

---

## 🧠 Nota sobre o método

Este projeto é conduzido em **Modo Mentor (Aprendizado Guiado)**: os conceitos de modelagem
dimensional são discutidos e decididos pelo autor, enquanto os artefatos mecânicos são acelerados.
Detalhes do método e do histórico de decisões em [`ROADMAP.md`](ROADMAP.md).

---

## 📄 Licença

Projeto de uso **acadêmico**. As bases Northwind e Mercearia pertencem aos seus respectivos autores.
