# 🗺️ Diagramas do DW e dos DataMarts

> Diagramas em **Mermaid** (renderizam direto no GitHub e no VS Code).
> Os diagramas podem ser copiados para o relatório ou colados no <https://mermaid.live>.
> O dicionário completo de atributos está na DDL: `sql/01_dw_organizacional.sql` e `sql/04_datamarts.sql`.

---

## 1. DW Organizacional (modelo galáxia / constelação de fatos)

Três fatos em **grãos diferentes**, compartilhando **dimensões conformadas**.

```mermaid
erDiagram
    DIM_TEMPO          ||--o{ FATO_VENDAS      : "sk_tempo_venda"
    DIM_CLIENTE        ||--o{ FATO_VENDAS      : "sk_cliente"
    DIM_PRODUTO        ||--o{ FATO_VENDAS      : "sk_produto"
    DIM_LOCALIDADE     ||--o{ FATO_VENDAS      : "sk_localidade"
    DIM_VENDEDOR       ||--o{ FATO_VENDAS      : "sk_vendedor"

    DIM_TEMPO          ||--o{ FATO_COMPRAS     : "sk_tempo_pedido"
    DIM_PRODUTO        ||--o{ FATO_COMPRAS     : "sk_produto"
    DIM_FORNECEDOR     ||--o{ FATO_COMPRAS     : "sk_fornecedor"

    DIM_TEMPO          ||--o{ FATO_ENTREGAS    : "sk_tempo_pedido"
    DIM_CLIENTE        ||--o{ FATO_ENTREGAS    : "sk_cliente"
    DIM_LOCALIDADE     ||--o{ FATO_ENTREGAS    : "sk_localidade"
    DIM_TRANSPORTADORA ||--o{ FATO_ENTREGAS    : "sk_transportadora"

    DIM_LOCALIDADE     ||--o| EXT_MUNICIPIO_IBGE : "codigo_ibge"
    EXT_COTACAO_DOLAR  ||--o{ FATO_VENDAS      : "taxa_cambio (PTAX)"

    FATO_VENDAS {
        bigint  sk_fato_venda PK
        varchar num_pedido
        varchar origem
        varchar moeda_origem
        numeric taxa_cambio
        int     sk_tempo_venda FK
        int     sk_tempo_fatura FK
        int     sk_cliente FK
        int     sk_produto FK
        int     sk_localidade FK
        int     sk_vendedor FK
        int     quantidade
        numeric vlr_unitario
        numeric pct_desconto
        numeric vlr_bruto
        numeric vlr_desconto
        numeric vlr_liquido
    }
    FATO_COMPRAS {
        bigint  sk_fato_compra PK
        varchar num_compra
        int     sk_tempo_pedido FK
        int     sk_tempo_entrada FK
        int     sk_produto FK
        int     sk_fornecedor FK
        int     quantidade
        numeric vlr_unitario
        numeric vlr_bruto
    }
    FATO_ENTREGAS {
        bigint  sk_fato_entrega PK
        varchar num_pedido
        int     sk_tempo_pedido FK
        int     sk_tempo_expedicao FK
        int     sk_cliente FK
        int     sk_localidade FK
        int     sk_transportadora FK
        numeric vlr_frete
        int     qtd_itens
        int     prazo_dias
    }
    DIM_TEMPO {
        int     sk_tempo PK
        date    data
        smallint ano
        smallint trimestre
        smallint mes
        smallint dia
        boolean eh_fim_semana
        boolean eh_feriado
        boolean eh_ponto_facultativo
    }
    DIM_PRODUTO {
        int     sk_produto PK
        int     id_produto
        smallint product_id
        varchar origem
        varchar nome_produto
        varchar categoria
        numeric preco_venda
        int     versao
        date    data_inicio
        date    data_fim
        boolean flag_atual
    }
    DIM_CLIENTE {
        int     sk_cliente PK
        int     id_pessoa
        varchar customer_id
        varchar origem
        varchar nome
        varchar cpf_cnpj_masked
        varchar faixa_renda
        int     versao
        boolean flag_atual
    }
    DIM_LOCALIDADE {
        int     sk_localidade PK
        varchar nm_estado
        varchar sigla_uf
        varchar nm_cidade
        varchar nm_bairro
        int     cep
        varchar pais
        varchar codigo_ibge
        int     populacao
    }
    DIM_VENDEDOR {
        int     sk_vendedor PK
        smallint employee_id
        varchar nome
        varchar cargo
        varchar pais
    }
    DIM_FORNECEDOR {
        int     sk_fornecedor PK
        int     id_pessoa
        smallint supplier_id
        varchar origem
        varchar nome
        varchar pais
    }
    DIM_TRANSPORTADORA {
        int     sk_transportadora PK
        smallint shipper_id
        varchar nome
        varchar telefone
    }
    EXT_MUNICIPIO_IBGE {
        varchar codigo_ibge PK
        varchar nome
        varchar uf_sigla
        int     populacao
        smallint ano_ref
    }
    EXT_COTACAO_DOLAR {
        date    data PK
        numeric cotacao_compra
        numeric cotacao_venda
    }
```

> **Papel duplo:** `dim_tempo` aparece **duas vezes em cada fato** (ex.: `sk_tempo_venda` e
> `sk_tempo_fatura`). O diagrama mostra apenas o primeiro papel para não duplicar setas — os dois
> relacionamentos existem no DDL.

---

## 2. DataMart de Vendas (`dm_vendas`)

```mermaid
erDiagram
    DIM_TEMPO      ||--o{ FATO_VENDAS : "venda / faturamento"
    DIM_PRODUTO    ||--o{ FATO_VENDAS : ""
    DIM_CLIENTE    ||--o{ FATO_VENDAS : ""
    DIM_LOCALIDADE ||--o{ FATO_VENDAS : ""
    DIM_VENDEDOR   ||--o{ FATO_VENDAS : ""
```

## 3. DataMart de Suprimentos (`dm_suprimentos`)

```mermaid
erDiagram
    DIM_TEMPO      ||--o{ FATO_COMPRAS : "pedido / entrada"
    DIM_PRODUTO    ||--o{ FATO_COMPRAS : ""
    DIM_FORNECEDOR ||--o{ FATO_COMPRAS : ""
```

## 4. DataMart de Logística (`dm_logistica`)

```mermaid
erDiagram
    DIM_TEMPO          ||--o{ FATO_ENTREGAS : "pedido / expedicao"
    DIM_CLIENTE        ||--o{ FATO_ENTREGAS : "minimizada (LGPD)"
    DIM_LOCALIDADE     ||--o{ FATO_ENTREGAS : ""
    DIM_TRANSPORTADORA ||--o{ FATO_ENTREGAS : ""
```

---

## 5. Conformidade entre os DataMarts

O mesmo membro tem a **mesma chave surrogate** nos três DataMarts, o que permite combinar fatos:

```mermaid
flowchart LR
    subgraph DW
        P["dw.dim_produto<br/>sk_produto"]
        L["dw.dim_localidade<br/>sk_localidade"]
        C["dw.dim_cliente<br/>sk_cliente"]
        T["dw.dim_tempo<br/>sk_tempo"]
    end
    subgraph DM1["dm_vendas"]
        FV["fato_vendas"]
    end
    subgraph DM2["dm_suprimentos"]
        FC["fato_compras"]
    end
    subgraph DM3["dm_logistica"]
        FE["fato_entregas"]
    end
    P --> FV
    P --> FC
    L --> FV
    L --> FE
    C --> FV
    C --> FE
    T --> FV
    T --> FC
    T --> FE
```

**Exemplo de análise cruzada permitida:** vendas por transportadora, ligando `dm_vendas.fato_vendas`
a `dm_logistica.fato_entregas` pela localidade conformada (`sk_localidade`).
