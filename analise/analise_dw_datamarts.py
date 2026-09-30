"""
Analise de dados sobre o DW Organizacional e os 3 DataMarts.
IFG / Topicos Avancados em Inteligencia Artificial I - Daniel Flavio

Arquivo mantido em ASCII puro (sem caracteres fora de U+0000..U+007F),
por requisito de portabilidade do cenario de execucao.

O que este script faz:
  1. Conecta no PostgreSQL (localhost:5432, banco dw_atividade).
  2. Roda consultas de negocio sobre o DW e sobre os DataMarts.
  3. Exporta cada resultado em CSV (analise/resultados).
  4. Gera os graficos em PNG (analise/figuras).
  5. Aplica K-Means (RFM) para segmentar clientes e Regressao Linear
     simples para projetar vendas.

Uso:
    python analise/analise_dw_datamarts.py
"""

import os
from decimal import Decimal

import matplotlib
matplotlib.use("Agg")            # sem janela: salva direto em arquivo
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import psycopg2
from sklearn.cluster import KMeans
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler

RAIZ = os.path.dirname(os.path.abspath(__file__))
DIR_FIG = os.path.join(RAIZ, "figuras")
DIR_RES = os.path.join(RAIZ, "resultados")
os.makedirs(DIR_FIG, exist_ok=True)
os.makedirs(DIR_RES, exist_ok=True)

CONEXAO = dict(host="localhost", port=5432, dbname="dw_atividade",
               user="postgres", password="postgres")

COR_A = "#1f4e79"
COR_B = "#c0392b"
COR_C = "#2e7d32"


def conectar():
    return psycopg2.connect(**CONEXAO)


def consultar(conn, sql):
    """Executa SQL e devolve DataFrame, convertendo Decimal -> float."""
    with conn.cursor() as cur:
        cur.execute(sql)
        colunas = [d[0] for d in cur.description]
        linhas = cur.fetchall()
    dados = [[float(v) if isinstance(v, Decimal) else v for v in linha]
             for linha in linhas]
    return pd.DataFrame(dados, columns=colunas)


def titulo(texto):
    print("")
    print("=" * 78)
    print(texto)
    print("=" * 78)


def exportar(df, nome):
    caminho = os.path.join(DIR_RES, nome + ".csv")
    df.to_csv(caminho, index=False, sep=";", encoding="utf-8-sig")
    print(df.to_string(index=False))
    print("-> resultados/%s.csv" % nome)


def grafico_barras_h(valores, rotulos, titulo_fig, rotulo_x, nome_arquivo, cor=COR_A):
    valores = pd.to_numeric(pd.Series(valores), errors="coerce").fillna(0).tolist()
    rotulos = [str(r) for r in rotulos]      # NaN -> 'nan' (matplotlib exige texto)
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.barh(rotulos[::-1], valores[::-1], color=cor)
    ax.set_title(titulo_fig)
    ax.set_xlabel(rotulo_x)
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(DIR_FIG, nome_arquivo), dpi=140)
    plt.close(fig)


def main():
    conn = conectar()

    # =================================================================
    # 0) Visao geral: DW x DataMarts
    # =================================================================
    titulo("0) VISAO GERAL - VOLUME DE DADOS (DW x DATAMARTS)")
    df = consultar(conn, """
        SELECT 'dw.fato_vendas'              AS objeto, count(*) AS linhas FROM dw.fato_vendas
        UNION ALL SELECT 'dw.fato_compras',        count(*) FROM dw.fato_compras
        UNION ALL SELECT 'dw.fato_entregas',       count(*) FROM dw.fato_entregas
        UNION ALL SELECT 'dw.dim_tempo',           count(*) FROM dw.dim_tempo
        UNION ALL SELECT 'dm_vendas.fato_vendas',  count(*) FROM dm_vendas.fato_vendas
        UNION ALL SELECT 'dm_suprimentos.fato_compras', count(*) FROM dm_suprimentos.fato_compras
        UNION ALL SELECT 'dm_logistica.fato_entregas',  count(*) FROM dm_logistica.fato_entregas
        ORDER BY 1
    """)
    exportar(df, "00_visao_geral")

    # =================================================================
    # 1) DW: evolucao mensal do faturamento (por origem)
    # =================================================================
    titulo("1) DW - EVOLUCAO MENSAL DO FATURAMENTO (BRL), POR ORIGEM")
    df = consultar(conn, """
        SELECT t.ano, t.mes, t.nome_mes, f.origem,
               sum(f.vlr_liquido) AS faturamento,
               sum(f.quantidade)  AS itens
        FROM dw.fato_vendas f
        JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_venda
        GROUP BY 1, 2, 3, 4
        ORDER BY 1, 2
    """)
    df["periodo"] = df["ano"].astype(int).astype(str) + "-" + \
                    df["mes"].astype(int).astype(str).str.zfill(2)
    exportar(df, "01_evolucao_mensal")

    fig, ax = plt.subplots(figsize=(11, 5))
    for origem, cor in (("MERCEARIA", COR_A), ("NORTHWIND", COR_B)):
        parte = df[df["origem"] == origem]
        ax.plot(parte["periodo"], parte["faturamento"], marker="o",
                label=origem, color=cor)
    ax.set_title("Evolucao mensal do faturamento (BRL) por origem")
    ax.set_ylabel("Faturamento (BRL)")
    ax.grid(alpha=0.3)
    ax.legend()
    plt.xticks(rotation=90, fontsize=7)
    fig.tight_layout()
    fig.savefig(os.path.join(DIR_FIG, "01_evolucao_mensal.png"), dpi=140)
    plt.close(fig)

    # =================================================================
    # 2) DataMart de Vendas: top 10 produtos
    # =================================================================
    titulo("2) DATAMART VENDAS - TOP 10 PRODUTOS POR FATURAMENTO")
    df = consultar(conn, """
        SELECT p.nome_produto, p.categoria, p.origem,
               sum(f.quantidade)  AS unidades,
               sum(f.vlr_liquido) AS faturamento
        FROM dm_vendas.fato_vendas f
        JOIN dm_vendas.dim_produto p USING (sk_produto)
        GROUP BY 1, 2, 3
        ORDER BY 5 DESC
        LIMIT 10
    """)
    exportar(df, "02_top_produtos")
    grafico_barras_h(df["faturamento"].tolist(), df["nome_produto"].tolist(),
                     "Top 10 produtos por faturamento (BRL)",
                     "Faturamento (BRL)", "02_top_produtos.png")

    # =================================================================
    # 3) DataMart de Vendas: faturamento por UF (Brasil)
    # =================================================================
    titulo("3) DATAMART VENDAS - FATURAMENTO POR UF (BRASIL)")
    df = consultar(conn, """
        SELECT l.sigla_uf, l.nm_estado,
               sum(f.vlr_liquido) AS faturamento,
               count(DISTINCT f.origem || '|' || f.num_pedido) AS pedidos
        FROM dm_vendas.fato_vendas f
        JOIN dm_vendas.dim_localidade l USING (sk_localidade)
        WHERE l.pais = 'Brasil'
        GROUP BY 1, 2
        ORDER BY 3 DESC
        LIMIT 15
    """)
    exportar(df, "03_faturamento_uf")
    grafico_barras_h(df["faturamento"].tolist(),
                     (df["sigla_uf"].fillna("??") + " - " + df["nm_estado"].fillna("(sem estado)")).tolist(),
                     "Faturamento por UF (Brasil, BRL)",
                     "Faturamento (BRL)", "03_faturamento_uf.png")

    # =================================================================
    # 4) DW: sazonalidade - dia da semana e feriado (Mercearia)
    # =================================================================
    titulo("4) DW - VENDA MEDIA POR DIA: DIA DA SEMANA E FERIADO (MERCEARIA)")
    df_dia = consultar(conn, """
        SELECT t.nome_dia_semana, t.dia_semana,
               count(DISTINCT t.data) AS dias,
               sum(f.vlr_liquido)     AS faturamento
        FROM dw.fato_vendas f
        JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_venda
        WHERE f.origem = 'MERCEARIA'
        GROUP BY 1, 2
        ORDER BY 2
    """)
    df_dia["media_por_dia"] = df_dia["faturamento"] / df_dia["dias"]
    exportar(df_dia, "04a_por_dia_semana")

    df_fer = consultar(conn, """
        SELECT CASE WHEN t.eh_feriado THEN 'FERIADO'
                    WHEN t.eh_ponto_facultativo THEN 'PONTO FACULTATIVO'
                    ELSE 'DIA COMUM' END AS tipo_dia,
               count(DISTINCT t.data) AS dias,
               sum(f.vlr_liquido)     AS faturamento
        FROM dw.fato_vendas f
        JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_venda
        WHERE f.origem = 'MERCEARIA'
        GROUP BY 1
        ORDER BY 1
    """)
    df_fer["media_por_dia"] = df_fer["faturamento"] / df_fer["dias"]
    exportar(df_fer, "04b_feriado_vs_comum")

    fig, eixos = plt.subplots(1, 2, figsize=(12, 4.5))
    eixos[0].bar(df_dia["nome_dia_semana"], df_dia["media_por_dia"], color=COR_A)
    eixos[0].set_title("Venda media por dia da semana (BRL) - Mercearia")
    eixos[0].tick_params(axis="x", rotation=30)
    eixos[0].grid(axis="y", alpha=0.3)
    eixos[1].bar(df_fer["tipo_dia"], df_fer["media_por_dia"], color=COR_C)
    eixos[1].set_title("Venda media por dia: feriado x dia comum (BRL)")
    eixos[1].grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(DIR_FIG, "04_sazonalidade.png"), dpi=140)
    plt.close(fig)

    # =================================================================
    # 5) DataMart de Logistica: desempenho por transportadora
    # =================================================================
    titulo("5) DATAMART LOGISTICA - DESEMPENHO POR TRANSPORTADORA")
    df = consultar(conn, """
        SELECT tr.nome AS transportadora,
               count(*)                     AS pedidos,
               round(avg(fe.prazo_dias)::numeric, 1)  AS prazo_medio_dias,
               round(avg(fe.vlr_frete)::numeric, 2)   AS frete_medio,
               round(sum(fe.vlr_frete)::numeric, 2)   AS frete_total
        FROM dm_logistica.fato_entregas fe
        JOIN dm_logistica.dim_transportadora tr USING (sk_transportadora)
        GROUP BY 1
        ORDER BY 3
    """)
    exportar(df, "05_transportadoras")
    grafico_barras_h(df["prazo_medio_dias"].tolist(), df["transportadora"].tolist(),
                     "Prazo medio de entrega por transportadora (dias)",
                     "Dias (pedido -> expedicao)", "05_transportadoras.png", COR_C)

    # =================================================================
    # 6) Analise CRUZADA de DataMarts: margem (custo x preco de venda)
    #    So e possivel porque as dimensoes sao CONFORMADAS.
    # =================================================================
    titulo("6) ANALISE CRUZADA (SUPRIMENTOS x VENDAS) - MARGEM POR PRODUTO")
    df = consultar(conn, """
        WITH compra AS (
            SELECT p.id_produto,
                   sum(c.quantidade) AS qtd_comprada,
                   sum(c.vlr_bruto)  AS custo_total
            FROM dm_suprimentos.fato_compras c
            JOIN dm_suprimentos.dim_produto p USING (sk_produto)
            GROUP BY 1
        ), venda AS (
            SELECT p.id_produto,
                   sum(v.quantidade)  AS qtd_vendida,
                   sum(v.vlr_liquido) AS receita_total
            FROM dm_vendas.fato_vendas v
            JOIN dm_vendas.dim_produto p USING (sk_produto)
            WHERE v.origem = 'MERCEARIA'
            GROUP BY 1
        )
        SELECT p.nome_produto,
               co.qtd_comprada, ve.qtd_vendida,
               round((co.custo_total  / NULLIF(co.qtd_comprada, 0))::numeric, 2) AS custo_unit_medio,
               round((ve.receita_total / NULLIF(ve.qtd_vendida, 0))::numeric, 2) AS preco_unit_medio,
               round(((ve.receita_total / NULLIF(ve.qtd_vendida, 0))
                    - (co.custo_total  / NULLIF(co.qtd_comprada, 0)))::numeric, 2) AS margem_unit_media
        FROM compra co
        JOIN venda  ve ON ve.id_produto = co.id_produto
        JOIN dm_vendas.dim_produto p
             ON p.id_produto = co.id_produto AND p.origem = 'MERCEARIA' AND p.flag_atual
        ORDER BY 6 DESC
    """)
    df["margem_pct"] = (df["margem_unit_media"] / df["preco_unit_medio"] * 100).round(1)
    exportar(df, "06_margem_por_produto")
    topo = df.head(12)
    grafico_barras_h(topo["margem_unit_media"].tolist(),
                     (topo["nome_produto"] + " (" + topo["margem_pct"].astype(str) + "%)").tolist(),
                     "Margem unitaria media por produto (BRL) - top 12",
                     "Margem (BRL)", "06_margem.png", COR_B)

    # =================================================================
    # 7) IA 1: segmentacao de clientes com K-Means (RFM)
    # =================================================================
    titulo("7) IA - SEGMENTACAO DE CLIENTES (K-MEANS sobre RFM)")
    df = consultar(conn, """
        SELECT c.sk_cliente, c.nome,
               CASE WHEN c.tipo_pessoa = 2 THEN 'PJ' ELSE 'PF' END AS tipo,
               max(t.data)                    AS ultima_compra,
               count(DISTINCT f.num_pedido)   AS pedidos,
               sum(f.vlr_liquido)             AS valor_total
        FROM dm_vendas.fato_vendas f
        JOIN dm_vendas.dim_cliente c USING (sk_cliente)
        JOIN dm_vendas.dim_tempo t ON t.sk_tempo = f.sk_tempo_venda
        WHERE f.origem = 'MERCEARIA'
        GROUP BY 1, 2, 3
    """)
    data_ref = pd.to_datetime(df["ultima_compra"]).max()
    df["recencia_dias"] = (data_ref - pd.to_datetime(df["ultima_compra"])).dt.days

    atributos = df[["recencia_dias", "pedidos", "valor_total"]].astype(float)
    padronizado = StandardScaler().fit_transform(atributos)
    kmeans = KMeans(n_clusters=3, n_init=10, random_state=42)
    df["cluster"] = kmeans.fit_predict(padronizado)

    resumo = df.groupby("cluster").agg(
        clientes=("sk_cliente", "count"),
        recencia_media=("recencia_dias", "mean"),
        pedidos_medio=("pedidos", "mean"),
        valor_medio=("valor_total", "mean"),
    ).round(1).sort_values("valor_medio", ascending=False)

    # rotulos de negocio, na ordem do maior valor medio
    rotulos = {}
    for posicao, cluster in enumerate(resumo.index):
        rotulos[cluster] = ["A - alto valor", "B - intermediario", "C - baixo valor"][posicao]
    df["segmento"] = df["cluster"].map(rotulos)
    resumo.insert(0, "segmento", [rotulos[c] for c in resumo.index])

    exportar(resumo.reset_index(drop=True), "07a_segmentos_resumo")
    exportar(df[["sk_cliente", "nome", "tipo", "recencia_dias", "pedidos",
                 "valor_total", "segmento"]].sort_values("valor_total", ascending=False),
             "07b_clientes_segmentados")

    cores = {"A - alto valor": COR_B, "B - intermediario": COR_A,
             "C - baixo valor": COR_C}
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for rotulo, cor in cores.items():
        parte = df[df["segmento"] == rotulo]
        ax.scatter(parte["recencia_dias"], parte["valor_total"],
                   label="%s (%d clientes)" % (rotulo, len(parte)),
                   color=cor, alpha=0.75, s=45)
    ax.set_title("Segmentacao de clientes (K-Means, k=3) - Recencia x Valor")
    ax.set_xlabel("Recencia (dias desde a ultima compra)")
    ax.set_ylabel("Valor total comprado (BRL)")
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(DIR_FIG, "07_clusters_clientes.png"), dpi=140)
    plt.close(fig)

    # =================================================================
    # 8) IA 2: projecao de vendas por regressao linear
    # =================================================================
    titulo("8) IA - PROJECAO DE VENDAS MENSAIS (REGRESSAO LINEAR)")
    df = consultar(conn, """
        SELECT t.ano, t.mes, sum(f.vlr_liquido) AS faturamento
        FROM dw.fato_vendas f
        JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_venda
        WHERE f.origem = 'MERCEARIA'
        GROUP BY 1, 2
        ORDER BY 1, 2
    """)
    df["t"] = np.arange(len(df))
    df["dezembro"] = (df["mes"].astype(int) == 12).astype(int)
    X = df[["t", "dezembro"]]
    y = df["faturamento"].astype(float)

    modelo = LinearRegression().fit(X, y)
    r2 = modelo.score(X, y)

    futuros = pd.DataFrame({
        "t": np.arange(len(df), len(df) + 3),
        "dezembro": [1 if ((df["mes"].astype(int).iloc[-1] + passo) % 12 == 0)
                     else 0 for passo in (1, 2, 3)],
    })
    previsao = modelo.predict(futuros)
    tendencia = modelo.coef_[0]
    peso_dezembro = modelo.coef_[1]

    print("R2 do ajuste: %.3f  (1.0 = perfeito; quanto mais perto de 1, melhor explica)" % r2)
    print("Tendencia estimada de crescimento: BRL %.2f por mes" % tendencia)
    print("Efeito medio de dezembro: BRL %.2f acima dos meses comuns" % peso_dezembro)
    print("Projecao dos proximos 3 meses (BRL): %s"
          % ", ".join("%.2f" % v for v in previsao))

    tabela = pd.DataFrame({
        "mes_futuro": [1, 2, 3],
        "faturamento_previsto": previsao.round(2),
    })
    exportar(tabela, "08_previsao")

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(df["t"], df["faturamento"], marker="o", color=COR_A,
            label="Historico (Mercearia)")
    ax.plot(futuros["t"], previsao, marker="s", linestyle="--", color=COR_B,
            label="Projecao (regressao linear)")
    ax.set_title("Faturamento mensal (BRL) e projecao - R2 ajustado = %.3f" % r2)
    ax.set_xlabel("Meses a partir de out/2024")
    ax.set_ylabel("Faturamento (BRL)")
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(DIR_FIG, "08_previsao.png"), dpi=140)
    plt.close(fig)

    # =================================================================
    # Resumo executivo
    # =================================================================
    titulo("RESUMO EXECUTIVO")
    lacunas = consultar(conn, """
        SELECT
          (SELECT count(*) FROM dm_vendas.fato_vendas)                 AS linhas_vendas,
          (SELECT round(sum(vlr_liquido)::numeric, 2) FROM dm_vendas.fato_vendas) AS faturamento_brl,
          (SELECT round(avg(prazo_dias)::numeric, 1)
             FROM dm_logistica.fato_entregas)                          AS prazo_medio_geral,
          (SELECT round(avg(vlr_frete)::numeric, 2)
             FROM dm_logistica.fato_entregas)                          AS frete_medio_geral
    """)
    print(lacunas.to_string(index=False))
    print("")
    print("Figuras geradas em analise/figuras (%d arquivos PNG)."
          % len([a for a in os.listdir(DIR_FIG) if a.endswith(".png")]))
    print("Resultados em analise/resultados (%d arquivos CSV)."
          % len([a for a in os.listdir(DIR_RES) if a.endswith(".csv")]))

    conn.close()


if __name__ == "__main__":
    main()
