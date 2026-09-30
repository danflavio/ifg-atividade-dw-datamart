# 📡 Dados Externos

Dados **públicos e reais** usados para enriquecer o DW. Não há dado pessoal
aqui — nada de CPF, renda ou endereço de pessoas.

| Arquivo | Origem | Conteúdo | Linhas |
|---|---|---|---|
| `ibge_municipios.csv` | IBGE — Localidades + Agregados | código do município (7 dígitos), UF e população residente estimada | 39 |
| `ptax_dolar_1996_1998.csv` | BCB — PTAX/OLINDA | cotação USD→BRL (compra e venda) do boletim de fechamento | 750 |

**Data de acesso:** 2026-09-29

## Endpoints utilizados

```
# 1) Código do município
https://servicodados.ibge.gov.br/api/v1/localidades/estados/{UF}/municipios

# 2) População residente estimada (agregado 6579, variável 9324)
https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/-1/variaveis/9324?localidades=N6[{codigo_ibge}]

# 3) Câmbio USD→BRL (boletim de fechamento)
https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(
    dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao
)?@dataInicial='01-01-1996'&@dataFinalCotacao='12-31-1998'&$format=json
```

## Como regerar

```powershell
pwsh -File .\etl\05_extrair_dados_externos.ps1
```

O script sobrescreve os dois CSVs (UTF-8 **sem BOM**, separador `;` — o BOM
quebraria o `HEADER` do `COPY`, e a vírgula decimal quebraria os `NUMERIC`).

## Por que estes dados

| Dado externo | Onde entra no DW | Justificativa |
|---|---|---|
| Código IBGE do município | `dw.dim_localidade.codigo_ibge` | chave estável de integração entre bases e com sistemas oficiais |
| População estimada | `dw.dim_localidade.populacao` | permite normalizar análises por habitante (ex.: venda per capita) |
| PTAX USD→BRL | `dw.fato_vendas.taxa_cambio` | o Northwind está em USD e a Mercearia em BRL; sem conversão as medidas não são comparáveis |
| Páscoa/feriados (calculados) | `dw.dim_tempo.eh_feriado` | sazonalidade do comércio depende de feriado; Carnaval e Corpus Christi entram como ponto facultativo |

## Tratamento do câmbio (regra registrada)

1. Converte-se o valor em **USD** para **BRL** pela **cotação de compra** do dia da venda.
2. Sem boletim no dia (fim de semana/feriado), usa-se a **última cotação disponível** (*carry forward*) — materializada em `ext.cotacao_dolar_dia`.
3. A taxa efetivamente aplicada é gravada em `dw.fato_vendas.taxa_cambio`, permitindo auditar e reproduzir cada valor.
