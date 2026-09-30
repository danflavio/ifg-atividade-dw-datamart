"""
Gera o RELATORIO-TECNICO.docx a partir de:
  - modelo:  Desktop/modelo_docx_limpo.docx  (capa de estilos + cabecalho/rodape com logo)
  - conteudo: docs/RELATORIO-TECNICO.md

Estrategia: preservar TODOS os arquivos do modelo (styles.xml, numbering.xml,
cabecalhos, rodapes, tema, logo) e substituir apenas word/document.xml pelo
conteudo convertido. As imagens dos graficos sao injetadas como partes novas
(word/media) + relacionamentos + [Content_Types].

Uso:
    python docs/gerar_relatorio_docx.py
"""

import os
import re
import zipfile
from xml.sax.saxutils import escape
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELO = os.path.join(os.path.expanduser("~"), "Desktop", "modelo_docx_limpo.docx")
MARKDOWN = os.path.join(RAIZ, "docs", "RELATORIO-TECNICO.md")
SAIDA = os.path.join(RAIZ, "docs", "RELATORIO-TECNICO.docx")

LARGURA_UTIL_TWIPS = 10546          # A4 (11906) - margens (680 + 680)
EMU_POR_TWIP = 635
LARGURA_IMAGEM_TWIPS = 9500         # imagem ocupa quase toda a largura util

ESTILO_TITULO = {1: "Ttulo", 2: "Ttulo1", 3: "Ttulo2", 4: "Ttulo3", 5: "Ttulo4"}


# ---------------------------------------------------------------- inline
def runs_inline(texto):
    """Converte **negrito**, `codigo` e *italico* em runs do Word."""
    texto = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", texto)   # links -> texto
    partes = re.split(r"(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)", texto)
    xml = []
    for parte in partes:
        if not parte:
            continue
        if parte.startswith("**") and parte.endswith("**"):
            conteudo, props = parte[2:-2], "<w:b/>"
        elif parte.startswith("`") and parte.endswith("`"):
            conteudo, props = parte[1:-1], '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
        elif parte.startswith("*") and parte.endswith("*"):
            conteudo, props = parte[1:-1], "<w:i/>"
        else:
            conteudo, props = parte, ""
        xml.append(
            '<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>'
            % (props, escape(conteudo))
        )
    return "".join(xml) or '<w:r><w:t xml:space="preserve"></w:t></w:r>'


def paragrafo(texto, estilo="Normal", extra_pPr="", quebra=False):
    ppr = '<w:pPr><w:pStyle w:val="%s"/>%s</w:pPr>' % (estilo, extra_pPr)
    corpo = runs_inline(texto)
    if quebra:
        corpo = '<w:r><w:br w:type="page"/></w:r>' + corpo
    return "<w:p>%s%s</w:p>" % (ppr, corpo)


# ---------------------------------------------------------------- tabelas
def tabela_xml(linhas):
    """linhas: lista de listas de celulas (a primeira e o cabecalho)."""
    colunas = max(len(l) for l in linhas)
    largura = LARGURA_UTIL_TWIPS // colunas
    xml = ['<w:tbl><w:tblPr><w:tblStyle w:val="Tabelacomgrade"/>'
           '<w:tblW w:w="%d" w:type="dxa"/><w:tblLook w:val="04A0"/></w:tblPr>'
           % LARGURA_UTIL_TWIPS]
    xml.append("<w:tblGrid>" + ("<w:gridCol w:w=\"%d\"/>" % largura) * colunas + "</w:tblGrid>")
    for indice, linha in enumerate(linhas):
        celulas = []
        for posicao in range(colunas):
            valor = linha[posicao] if posicao < len(linha) else ""
            if indice == 0:
                conteudo = '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % escape(valor)
                sombra = '<w:shd w:val="clear" w:color="auto" w:fill="DCE6F1"/>'
                principal = indice == 0
            else:
                conteudo = runs_inline(valor)
                sombra = ""
                principal = False
            repetir = '<w:tblHeader/>' if principal else ""
            celulas.append(
                '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s%s</w:tcPr>'
                '<w:p><w:pPr><w:pStyle w:val="Normal"/></w:pPr>%s</w:p></w:tc>'
                % (largura, sombra, repetir, conteudo)
            )
        xml.append("<w:tr>%s</w:tr>" % "".join(celulas))
    xml.append("</w:tbl>")
    return "".join(xml)


def imagem_xml(rel_id, doc_pr_id, caminho):
    with Image.open(caminho) as img:
        largura_px, altura_px = img.size
    largura_emu = LARGURA_IMAGEM_TWIPS * EMU_POR_TWIP
    altura_emu = int(largura_emu * altura_px / largura_px)
    return (
        '<w:p><w:pPr><w:pStyle w:val="Normal"/><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
        '<wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="Figura %d"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="%d" name="%s"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
        % (largura_emu, altura_emu, doc_pr_id, doc_pr_id, doc_pr_id,
           os.path.basename(caminho), rel_id, largura_emu, altura_emu)
    )


# ---------------------------------------------------------------- markdown
def parsear_markdown(texto):
    """Devolve lista de blocos: (tipo, dado)."""
    blocos, linhas = [], texto.splitlines()
    indice, dentro_codigo, buffer_par, tabela = 0, False, [], []
    while indice < len(linhas):
        linha = linhas[indice]

        if linha.strip().startswith("```"):
            if dentro_codigo:
                blocos.append(("codigo", "\n".join(buffer_par)))
                buffer_par, dentro_codigo = [], False
            else:
                if buffer_par:
                    blocos.append(("paragrafo", " ".join(buffer_par)))
                    buffer_par = []
                dentro_codigo = True
            indice += 1
            continue
        if dentro_codigo:
            buffer_par.append(linha)
            indice += 1
            continue

        if linha.startswith("|"):
            celulas = [c.strip() for c in linha.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-{2,}:?", c) for c in celulas if c):
                tabela.append(celulas)
            indice += 1
            continue
        elif tabela:
            blocos.append(("tabela", tabela))
            tabela = []

        casado = re.match(r"^(#{1,6})\s+(.*)$", linha)
        if casado:
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("titulo", (len(casado.group(1)), casado.group(2))))
            indice += 1
            continue

        casado = re.match(r"^!\[[^\]]*\]\(([^)]+)\)", linha.strip())
        if casado:
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("imagem", casado.group(1)))
            indice += 1
            continue

        casado = re.match(r"^\s*[-*]\s+(.*)$", linha)
        if casado:
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("bullet", casado.group(1)))
            indice += 1
            continue

        casado = re.match(r"^\s*\d+\.\s+(.*)$", linha)
        if casado:
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("numerado", casado.group(1)))
            indice += 1
            continue

        if re.match(r"^>\s?", linha):
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("citacao", linha.lstrip("> ").strip()))
            indice += 1
            continue

        if re.match(r"^\s*---+\s*$", linha):
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            blocos.append(("regua", ""))
            indice += 1
            continue

        if not linha.strip():
            if buffer_par:
                blocos.append(("paragrafo", " ".join(buffer_par)))
                buffer_par = []
            indice += 1
            continue

        buffer_par.append(linha.strip())
        indice += 1

    if buffer_par:
        blocos.append(("paragrafo", " ".join(buffer_par)))
    if tabela:
        blocos.append(("tabela", tabela))
    return blocos


def corpo_xml(blocos, midias):
    """Monta o XML do corpo e registra as imagens em `midias`."""
    partes, primeira_regua = [], True
    for tipo, dado in blocos:
        if tipo == "titulo":
            nivel, texto = dado
            estilo = ESTILO_TITULO.get(nivel, "Ttulo4")
            partes.append(paragrafo(texto, estilo))
        elif tipo == "paragrafo":
            if re.match(r"^\*Figura", dado.strip()):
                # legenda de figura: centralizada
                partes.append(paragrafo(dado, "Normal", '<w:jc w:val="center"/>'))
            else:
                partes.append(paragrafo(dado, "Normal", '<w:jc w:val="both"/>'))
        elif tipo == "bullet":
            partes.append(paragrafo(
                dado, "PargrafodaLista",
                '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
                '<w:jc w:val="both"/>'))
        elif tipo == "numerado":
            partes.append(paragrafo(dado, "PargrafodaLista", '<w:jc w:val="both"/>'))
        elif tipo == "citacao":
            partes.append(paragrafo(dado, "CitaoIntensa", '<w:jc w:val="both"/>'))
        elif tipo == "codigo":
            for linha in dado.splitlines():
                partes.append(
                    '<w:p><w:pPr><w:pStyle w:val="Normal"/>'
                    '<w:shd w:val="clear" w:fill="F2F2F2"/></w:pPr>'
                    '<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>'
                    '<w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>'
                    '<w:t xml:space="preserve">%s</w:t></w:r></w:p>'
                    % escape(linha.replace(" ", "\u00a0")))
        elif tipo == "tabela":
            partes.append(tabela_xml(dado))
            partes.append(paragrafo("", "Normal"))
        elif tipo == "imagem":
            caminho = os.path.normpath(os.path.join(RAIZ, "docs", dado))
            if os.path.exists(caminho):
                indice = len(midias) + 1
                rel_id = "rIdImg%d" % indice
                midias.append((rel_id, caminho, "image%d.png" % indice))
                partes.append(imagem_xml(rel_id, 100 + indice, caminho))
            else:
                partes.append(paragrafo("[imagem nao encontrada: %s]" % dado, "Normal"))
        elif tipo == "regua":
            if primeira_regua:
                # apos a folha de identificacao: comeca o relatorio em nova pagina
                partes.append(paragrafo("", "Normal"))
                primeira_regua = False
            else:
                partes.append(paragrafo("", "Normal"))
    return "".join(partes)


def main():
    with zipfile.ZipFile(MODELO) as zip_modelo:
        arquivos = {nome: zip_modelo.read(nome) for nome in zip_modelo.namelist()}

    doc_xml = arquivos["word/document.xml"].decode("utf-8")
    cabecalho = doc_xml[: doc_xml.index("<w:body>") + len("<w:body>")]
    sect_pr = re.search(r"<w:sectPr.*?</w:sectPr>", doc_xml, re.S).group(0)

    with open(MARKDOWN, encoding="utf-8") as arquivo:
        markdown = arquivo.read()
    blocos = parsear_markdown(markdown)
    midias = []
    corpo = corpo_xml(blocos, midias)

    novo_doc = cabecalho + corpo + sect_pr + "</w:body></w:document>"
    arquivos["word/document.xml"] = novo_doc.encode("utf-8")

    # relacionamentos das imagens
    rels_nome = "word/_rels/document.xml.rels"
    rels = arquivos[rels_nome].decode("utf-8")
    novos = []
    for rel_id, caminho, nome_parte in midias:
        novos.append('<Relationship Id="%s" Type="http://schemas.openxmlformats.org/'
                     'officeDocument/2006/relationships/image" Target="media/%s"/>'
                     % (rel_id, nome_parte))
        with open(caminho, "rb") as imagem:
            arquivos["word/media/" + nome_parte] = imagem.read()
    rels = rels.replace("</Relationships>", "".join(novos) + "</Relationships>")
    arquivos[rels_nome] = rels.encode("utf-8")

    # tipo de conteudo para PNG
    tipos = arquivos["[Content_Types].xml"].decode("utf-8")
    if 'Extension="png"' not in tipos:
        tipos = tipos.replace(
            '<Default Extension="jpeg" ContentType="image/jpeg"/>',
            '<Default Extension="jpeg" ContentType="image/jpeg"/>'
            '<Default Extension="png" ContentType="image/png"/>')
    arquivos["[Content_Types].xml"] = tipos.encode("utf-8")

    with zipfile.ZipFile(SAIDA, "w", zipfile.ZIP_DEFLATED) as destino:
        for nome, conteudo in arquivos.items():
            destino.writestr(nome, conteudo)

    print("Gerado: %s" % SAIDA)
    print("Blocos convertidos: %d | imagens embutidas: %d" % (len(blocos), len(midias)))
    print("Titulos: %d | tabelas: %d | listas: %d"
          % (sum(1 for t, _ in blocos if t == "titulo"),
             sum(1 for t, _ in blocos if t == "tabela"),
             sum(1 for t, _ in blocos if t in ("bullet", "numerado"))))


if __name__ == "__main__":
    main()
