<#
.SYNOPSIS
    Extrai os DADOS EXTERNOS (públicos e reais) usados no DW da atividade.

.DESCRIPTION
    Fontes:
      [1] IBGE - Localidades (código do município com 7 dígitos)
          https://servicodados.ibge.gov.br/api/v1/localidades/estados/{UF}/municipios
      [2] IBGE - Agregados
          Agregado 6579, variável 9324 = "População residente estimada"
          https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/-1/variaveis/9324?localidades=N6[{codigo}]
      [3] BCB - PTAX (câmbio USD->BRL, boletim de fechamento)
          https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(...)

    Saída (UTF-8 sem BOM, delimitador ';'):
      dados_externos/ibge_municipios.csv       -> codigo_ibge;nome;uf;populacao;ano_ref
      dados_externos/ptax_dolar_1996_1998.csv  -> data;cotacao_compra;cotacao_venda

    Os municípios extraídos são exatamente os usados no seed sintético da
    Mercearia (sql/seed_mercearia.sql), para permitir o enriquecimento da
    dim_localidade por JOIN com ext.municipio_ibge.

.NOTES
    Uso:  pwsh -File .\etl\05_extrair_dados_externos.ps1
#>

$ErrorActionPreference = 'Stop'

$raiz    = Split-Path -Parent $PSScriptRoot
$destino = Join-Path $raiz 'dados_externos'
New-Item -ItemType Directory -Force -Path $destino | Out-Null

$tmp  = Join-Path $env:TEMP 'dw_fetch_http.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)          # sem BOM
$inv  = [System.Globalization.CultureInfo]::InvariantCulture # ponto decimal

function Get-Json([string]$url) {
    # -g: desativa o "globbing" do curl, que trata [ ] como curinga
    curl.exe -g -s -m 60 -o $tmp $url
    if ($LASTEXITCODE -ne 0) { throw "Falha de rede ao baixar: $url" }
    $texto = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($texto)) { throw "Resposta vazia: $url" }
    return ($texto | ConvertFrom-Json)
}

Write-Host ">> [1/2] IBGE - codigo do municipio + populacao estimada"

# Municípios presentes no seed sintético (nome exatamente como no IBGE)
$cidadesPorUf = [ordered]@{
    '52' = @('Goiânia','Aparecida de Goiânia','Anápolis','Rio Verde')
    '53' = @('Brasília')
    '35' = @('São Paulo','Campinas','Santos')
    '33' = @('Rio de Janeiro','Niterói')
    '31' = @('Belo Horizonte','Uberlândia')
    '41' = @('Curitiba','Londrina')
    '43' = @('Porto Alegre','Caxias do Sul')
    '29' = @('Salvador','Feira de Santana')
    '26' = @('Recife','Olinda')
    '23' = @('Fortaleza')
    '13' = @('Manaus')
    '15' = @('Belém')
    '24' = @('Natal')
    '25' = @('João Pessoa')
    '27' = @('Maceió')
    '28' = @('Aracaju')
    '22' = @('Teresina')
    '21' = @('São Luís')
    '51' = @('Cuiabá')
    '50' = @('Campo Grande')
    '42' = @('Florianópolis','Joinville')
    '32' = @('Vitória')
    '17' = @('Palmas')
    '11' = @('Porto Velho')
    '12' = @('Rio Branco')
    '16' = @('Macapá')
    '14' = @('Boa Vista')
}

$linhas = [System.Collections.Generic.List[string]]::new()
$linhas.Add('codigo_ibge;nome;uf;populacao;ano_ref')
$total = 0

foreach ($uf in $cidadesPorUf.Keys) {
    $municipios = Get-Json "https://servicodados.ibge.gov.br/api/v1/localidades/estados/$uf/municipios"

    foreach ($nome in $cidadesPorUf[$uf]) {
        $m = $municipios | Where-Object { $_.nome -eq $nome }
        if (-not $m) { throw "Municipio nao encontrado no IBGE: '$nome' (UF $uf)" }

        $codigo = [string]$m.id
        $sigla  = $m.microrregiao.mesorregiao.UF.sigla

        $agregado = Get-Json "https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/-1/variaveis/9324?localidades=N6%5B$codigo%5D"
        $serie    = $agregado[0].resultados[0].series[0].serie

        $populacao = ''
        $anoRef    = ''
        if ($serie) {
            $prop      = $serie.PSObject.Properties | Select-Object -First 1
            $anoRef    = $prop.Name
            $populacao = $prop.Value
        }

        $linhas.Add(('{0};{1};{2};{3};{4}' -f $codigo, $nome, $sigla, $populacao, $anoRef))
        $total++
        Write-Host ("   {0,-24} {1}  {2} hab ({3})" -f $nome, $sigla, $populacao, $anoRef)
    }
}

[System.IO.File]::WriteAllLines((Join-Path $destino 'ibge_municipios.csv'), $linhas, $utf8)
Write-Host "   -> dados_externos/ibge_municipios.csv  ($total municipios)"

Write-Host ">> [2/2] BCB/PTAX - cotacao USD->BRL (jan/1996 a dez/1998)"

$urlPtax = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)?@dataInicial='01-01-1996'&@dataFinalCotacao='12-31-1998'&`$format=json&`$top=20000"
$ptax    = Get-Json $urlPtax

# Um registro por dia (se houver mais de um boletim no dia, prevalece o ultimo)
$porDia = @{}
foreach ($x in $ptax.value) {
    $dia = ($x.dataHoraCotacao -split ' ')[0]
    $porDia[$dia] = $x
}

$linhas = [System.Collections.Generic.List[string]]::new()
$linhas.Add('data;cotacao_compra;cotacao_venda')
$dias = $porDia.Keys | Sort-Object
foreach ($dia in $dias) {
    $x = $porDia[$dia]
    $compra = ([double]$x.cotacaoCompra).ToString('F6', $inv)
    $venda  = ([double]$x.cotacaoVenda ).ToString('F6', $inv)
    $linhas.Add("$dia;$compra;$venda")
}

[System.IO.File]::WriteAllLines((Join-Path $destino 'ptax_dolar_1996_1998.csv'), $linhas, $utf8)
Write-Host "   -> dados_externos/ptax_dolar_1996_1998.csv  ($($dias.Count) cotacoes, de $($dias[0]) a $($dias[-1]))"

Write-Host ""
Write-Host "Extracao concluida. Fonte: IBGE (Localidades/Agregados) e BCB (PTAX)."
Write-Host ("Data de acesso: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
