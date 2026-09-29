# Roadmap — Atividade DW / DataMarts (IFG)

| Campo | Valor |
|---|---|
| Instituição | IFG — Campus Goiânia |
| Disciplina | Tópicos Avançados em Inteligência Artificial I |
| Professor | Sirlon Diniz |
| Entrega | 30/09/2026 |
| Início | 28/09/2026 |
| Prazo restante | ~2 dias |

**Fontes:** `sql/northwind.sql` (PostgreSQL) + `sql/SQL criação DB Mercearia.sql` (PostgreSQL)
**Entregáveis:** DDLs do DW e dos DataMarts + Relatório Técnico do processo

---

## 📌 Modelo decidido (v1) — Fato de Vendas

**Grão:** 1 linha por **ITEM de pedido** (atômico)

**Dimensões (conformadas):**

| Dimensão | Origem Mercearia | Origem Northwind |
|---|---|---|
| Tempo | `Vendas.DATA_VENDA` / `DATA_FATURAMENTO` | `orders.order_date` |
| Cliente | `Vendas.ID_PESSOA` → `Pessoas` | `orders.customer_id` |
| Produto | `Itens_Vendas.ID_PRODUTO` → `Produtos`/`Categorias` | `order_details.product_id` |
| Localidade | `Pessoas→Enderecos→Logradouros→Bairros→Cidades→Uf` | `orders.ship_city/ship_region` |
| Vendedor | (não existe na Mercearia) | `orders.employee_id` |

**Medidas:**

| Medida | Tipo | Fórmula |
|---|---|---|
| quantidade | aditiva | direta |
| valor_bruto | derivada | `quantity * unit_price` |
| desconto | não-aditiva (%) | direta |
| valor_liquido | derivada | `quantity * unit_price * (1 - discount)` |

**Papel duplo:** `Dim_Tempo` usada 2x (data da venda · data do faturamento).

---

> ⚠️ **Regra de ouro do prazo:** com 2 dias, o escopo é *definir bem* e *executar o essencial*.
> Melhor entregar 3 DataMarts sólidos e justificados do que 5 pela metade.

---

## Fase 0 — Ambiente e estrutura (HOJE · ~1h)

- [ ] Confirmar PostgreSQL instalado e acessível (psql / pgAdmin / DBeaver)
- [ ] Criar banco de **staging (ODS)**: `dw_atividade` (onde Northwind e Mercearia convivem)
- [ ] Carregar `northwind.sql` — validar contagem de linhas nas tabelas
- [ ] Carregar `SQL criação DB Mercearia.sql` — validar contagem de linhas
- [ ] Criar esquemas no mesmo banco: `stg_northwind`, `stg_mercearia`, `dw`, `dm`
- [ ] Definir ferramenta de modelagem (draw.io / dbdiagram.io) para o relatório
- [ ] Estrutura de pastas do projeto: `sql/` (já existe) · `docs/` · `modelos/` · `etl/`

**✅ Concluída quando:** os dois bancos carregam sem erro e você consegue fazer `SELECT COUNT(*)` nas tabelas principais.

---

## Fase 1 — Análise das fontes e pontos de integração (HOJE · ~2–3h) 🔴 *etapa crítica*

- [ ] Inventariar as tabelas das duas fontes
  - Northwind (14): customers, employees, products, categories, suppliers, shippers, orders, order_details, territories, region, us_states, customer_demographics, customer_customer_demo, employee_territories
  - Mercearia (14): Pessoas, Profissoes, Uf, Cidades, Bairros, Logradouros, Enderecos, Telefones, Categorias, Produtos, Compras, Itens_compras, Vendas, Itens_Vendas
- [ ] **Mapear equivalentes entre as fontes** (o coração da integração):
  - Produto: `northwind.products` ↔ `mercearia.Produtos`
  - Categoria: `northwind.categories` ↔ `mercearia.Categorias`
  - Cliente: `northwind.customers` ↔ `mercearia.Pessoas` (TIPO_PESSOA = cliente?)
  - Fornecedor: `northwind.suppliers` ↔ `mercearia.Pessoas` (fornecedor em Compras?)
  - Localidade: `northwind.region/territories/us_states` ↔ `mercearia.Uf/Cidades/Bairros` ⚠️ *granularidades e países diferentes — decidir como conciliar*
- [ ] Definir **chaves de integração** (surrogate keys + tabelas de correspondência/crosswalk)
- [ ] Definir **Dados Externos** (obrigatório na atividade) — candidatos:
  - IBGE: códigos de município, população, PIB (enriquece Localidade)
  - CEP / Correios (padronização de endereço)
  - Tabela de feriados nacionais (enriquece Tempo)
  - Câmbio USD→BRL (Northwind é em USD; Mercearia em BRL) — *justificar no relatório*
- [ ] Definir **granularidade** do DW (menor nível de detalhe que se deseja guardar)
- [ ] Documentar decisões (vira seção do relatório)

**✅ Concluída quando:** existe uma tabela/matriz "atributo da fonte A → atributo da fonte B → dimensão do DW".

---

## Fase 2 — Modelagem do DW Organizacional (HOJE/amanhã · ~3h)

- [ ] Escolher abordagem de modelagem (Kimball estrela + barramento de dimensões conformadas ← recomendado)
- [ ] Definir o **barramento de dimensões conformadas**:
  - [ ] Dim_Tempo (granularidade: dia) — *gerar via script*
  - [ ] Dim_Produto (+ Dim_Categoria)
  - [ ] Dim_Cliente / Pessoa (⚠️ LGPD — dados sensíveis)
  - [ ] Dim_Localidade (UF → Cidade → Bairro/Região)
  - [ ] Dim_Vendedor / Funcionário
  - [ ] Dim_Fornecedor
- [ ] Definir **historicidade** (SCD Tipo 2 em pelo menos uma dimensão — ex.: Cliente ou Produto)
- [ ] Definir fatos do DW: Vendas, Compras (movimentos de negócio)
- [ ] Desenhar o diagrama do DW (estrela/galáxia) para o relatório
- [ ] **Escrever a DDL do DW** → `sql/dw_organizacional.sql`

**✅ Concluída quando:** a DDL do DW roda, cria dimensões + fatos e respeita grão, integração e histórico.

---

## Fase 3 — ETL (amanhã · ~3–4h)

- [ ] Decidir a estratégia: SQL puro (recomendado pelo prazo) ou ferramenta (Pentaho/Talend/SSIS)
- [ ] **Extract:** ler de `stg_northwind` e `stg_mercearia`
- [ ] **Transform:** limpeza, padronização, deduplicação, tratamento de nulos, integração de códigos
- [ ] **Load:** carga das dimensões primeiro, depois dos fatos (respeitar FKs)
- [ ] Carregar Dados Externos
- [ ] Testes de integridade: contagens origem×destino, registros órfãos, valores nulos indevidos
- [ ] Scripts em `etl/`

**✅ Concluída quando:** as consultas de validação batem entre origem e DW.

---

## Fase 4 — DataMarts (>= 3) (amanhã · ~3h)

Escolher **3+ assuntos** e, para cada um, documentar: **assunto · fato · dimensões · grão · justificativa de uso**.

- [ ] **DM 1 — Vendas** (análise comercial): fato Vendas × Tempo, Produto, Cliente, Localidade, Vendedor
- [ ] **DM 2 — Compras/Estoque** (suprimentos): fato Compras × Tempo, Produto, Fornecedor
- [ ] **DM 3 — Logística/Entregas**: fato Entregas × Tempo, Transportadora (shippers), Localidade
- [ ] *Alternativas:* DM Clientes/CRM (demografia, renda), DM RH (desempenho de funcionários)
- [ ] Justificar cada DM (para quem serve, que decisão apoia)
- [ ] **Escrever a DDL de cada DataMart** → `sql/dm_*.sql`

**✅ Concluída quando:** cada DM tem DDL própria, roda e há justificativa escrita.

---

## Fase 5 — Análise de Dados (amanhã/30 · ~2h)

> 💡 **Contexto da disciplina (IA I):** a atividade pede "ferramentas de análise de dados", mas o curso é de IA.
> Usar Python (pandas + scikit-learn) conectado ao DW tende a valorizar mais o trabalho do que um BI puramente visual —
> e ainda abre espaço para um modelo simples (ex.: previsão de vendas / clusterização de clientes) como diferencial.

- [ ] Escolher ferramenta (Metabase/Superset/Power BI/Excel/**Python + SQL**)
- [ ] Conectar a ferramenta ao DW e aos DataMarts
- [ ] Criar consultas/visualizações que respondam perguntas de negócio (ex.: top produtos, evolução de vendas, sazonalidade)
- [ ] *(Opcional/diferencial alinhado à IA)*: aplicar técnica de ML (regressão, clusterização) sobre um DataMart
- [ ] Exportar prints/tabelas para o relatório

**✅ Concluída quando:** há evidência visual (gráfico/tabela) de análise sobre DW/DM.

---

## Fase 6 — Relatório Técnico (30/09 · ~3h)

- [ ] Introdução e objetivo
- [ ] Descrição das fontes (Northwind e Mercearia)
- [ ] Arquitetura do DW (diagrama) + decisões de modelagem
- [ ] Justificativa de granularidade, integração, historicidade e dados externos
- [ ] Modelagem dos DataMarts (assunto/fato/dimensão/justificativa)
- [ ] Processo de ETL (etapas, transformações, testes)
- [ ] Análises realizadas (resultados)
- [ ] **LGPD:** se aplicado a dados reais/da sua área, descrever mascaramento/anonimização
- [ ] Conclusão e referências

---

## Fase 7 — Entrega (30/09)

- [ ] Revisar todos os scripts (rodam do zero sem erro?)
- [ ] Organizar pacote: DDLs (`sql/`) + relatório (`docs/`)
- [ ] Conferir se atende aos 3 itens da atividade e às OBS.
- [ ] Entregar **até 30/09/2026**

---

## Distribuição no prazo (2 dias)

| Dia | Foco |
|-----|------|
| **28/09 (hoje)** | Fases 0 e 1 (ambiente + integração) e começar Fase 2 |
| **29/09** | Fase 2 (DDL DW), Fase 3 (ETL) e Fase 4 (DataMarts) |
| **30/09** | Fase 5 (análise), Fase 6 (relatório), Fase 7 (entrega) |

---

## Decisões que VOCÊ precisa tomar (não pule)

1. **Grão do DW:** qual o menor nível de detalhe? (item de pedido? pedido? dia?)
   → ✅ **DECIDIDO: uma linha por ITEM DE PEDIDO (atômico)**
2. **Como conciliar as localidades** (EUA do Northwind × Brasil da Mercearia)? É uma dimensão conformada ou duas?
3. **Quais dados externos** entram e por quê?
4. **Onde aplicar SCD Tipo 2?** (ex.: preço do produto muda com o tempo)
5. **Quais 3 DataMarts** fazem sentido para o negócio?
