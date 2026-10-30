# Diagnostico da API local do Holyrics. Projecao opcional, com confirmacao.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\diagnosticar_holyrics.ps1
# Somente porta: -SemToken. Teste de texto: -ProjetarTexto (somente com tela livre).
param(
    [int]$Porta = 8091,
    [switch]$SemToken,
    [switch]$ProjetarTexto
)

$ErrorActionPreference = 'Stop'
if ($Porta -lt 1 -or $Porta -gt 65535) {
    Write-Host 'Porta invalida: informe um numero entre 1 e 65535.' -ForegroundColor Red
    exit 2
}
if ($SemToken -and $ProjetarTexto) {
    Write-Host 'Nao e possivel projetar sem token: retire -SemToken.' -ForegroundColor Red
    exit 2
}

Write-Host "Diagnostico do Holyrics em 127.0.0.1:$Porta"
if (-not $ProjetarTexto) { Write-Host 'Modo somente leitura: nenhuma projecao sera enviada.' }

function Testar-Porta([int]$Numero) {
    $cliente = New-Object System.Net.Sockets.TcpClient
    try {
        $pendente = $cliente.BeginConnect('127.0.0.1', $Numero, $null, $null)
        if (-not $pendente.AsyncWaitHandle.WaitOne(2500)) { return $false }
        $cliente.EndConnect($pendente)
        return $true
    } catch {
        return $false
    } finally {
        $cliente.Close()
    }
}

if (-not (Testar-Porta $Porta)) {
    Write-Host '[FALHA] Porta TCP indisponivel. Abra o Holyrics e confira Configuracoes > API Server > porta.' -ForegroundColor Red
    exit 1
}
Write-Host '[OK] A porta TCP responde.' -ForegroundColor Green

if ($SemToken) {
    Write-Host 'Autenticacao e API nao testadas (-SemToken). Porta aberta nao prova que o servico e o Holyrics.'
    exit 0
}

$seguro = Read-Host 'Digite o token NOVO do Holyrics (entrada oculta)' -AsSecureString
if ($seguro.Length -eq 0) {
    Write-Host '[FALHA] Token vazio. Gere um token no API Server do Holyrics.' -ForegroundColor Red
    exit 2
}

# A API do Holyrics exige token na query. Nunca imprima a URL, o token ou a excecao HTTP.
$ponteiro = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ponteiro)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ponteiro)
    $seguro.Dispose()
}

function Consultar-Api([string]$Acao, [string]$Corpo = '{}') {
    $uri = 'http://127.0.0.1:{0}/api/{1}?token={2}' -f $Porta, $Acao, [Uri]::EscapeDataString($token)
    try {
        $resposta = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $uri -Body $Corpo -ContentType 'application/json' -TimeoutSec 5
        $dados = $resposta.Content | ConvertFrom-Json
        if ($dados.status -eq 'ok') { return @{ Resultado = 'ok'; Dados = $dados.data } }
        if ($dados.error -eq 'invalid token') { return @{ Resultado = 'token' } }
        return @{ Resultado = 'api' }
    } catch [System.Net.WebException] {
        $codigo = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($codigo -eq 401 -or $codigo -eq 403) { return @{ Resultado = 'token' } }
        return @{ Resultado = 'http'; Codigo = $codigo }
    } catch {
        return @{ Resultado = 'resposta' }
    }
}

try {
    $info = Consultar-Api 'GetCPInfo'
    switch ($info.Resultado) {
        'token' {
            Write-Host '[FALHA] A API recusou o token. Confira o token habilitado no Holyrics.' -ForegroundColor Red
            exit 3
        }
        'ok' { Write-Host '[OK] GetCPInfo autenticado.' -ForegroundColor Green }
        default {
            Write-Host '[FALHA] GetCPInfo nao respondeu com status ok. Confira API Server e permissoes de GetCPInfo.' -ForegroundColor Red
            exit 4
        }
    }

    $atual = Consultar-Api 'GetCurrentPresentation'
    if ($atual.Resultado -ne 'ok') {
        Write-Host '[FALHA] GetCurrentPresentation nao respondeu com status ok. Libere essa acao no token.' -ForegroundColor Red
        exit 4
    }
    Write-Host '[OK] GetCurrentPresentation autenticado (nenhuma projecao foi iniciada).' -ForegroundColor Green
    if ($ProjetarTexto) {
        if ($atual.Dados -ne $null) {
            Write-Host '[BLOQUEADO] Ja existe uma apresentacao ativa. Libere o telao antes do teste; nada foi projetado.' -ForegroundColor Yellow
            exit 5
        }
        Write-Host 'O texto "TESTE DIAKOHUB - HOLYRICS" sera projetado no telao.' -ForegroundColor Yellow
        $confirmacao = Read-Host 'Digite SIM para projetar (qualquer outra resposta cancela)'
        if ($confirmacao -cne 'SIM') {
            Write-Host 'Teste cancelado; nada foi projetado.'
            exit 0
        }
        # Reconfere apos a confirmacao: alguem pode ter iniciado outra apresentacao enquanto isso.
        $atual = Consultar-Api 'GetCurrentPresentation'
        if ($atual.Resultado -ne 'ok' -or $atual.Dados -ne $null) {
            Write-Host '[BLOQUEADO] Nao foi possivel confirmar que o telao continua livre; nada foi projetado.' -ForegroundColor Yellow
            exit 5
        }
        $corpo = @{ text = 'TESTE DIAKOHUB - HOLYRICS' } | ConvertTo-Json -Compress
        $projecao = Consultar-Api 'ShowQuickPresentation' $corpo
        if ($projecao.Resultado -ne 'ok') {
            Write-Host '[FALHA] Holyrics nao confirmou a projecao. Confira a permissao ShowQuickPresentation do token.' -ForegroundColor Red
            exit 4
        }
        Write-Host '[OK] Holyrics aceitou o comando. Confira o texto no telao; o script nao fecha a apresentacao.' -ForegroundColor Green
    }
    Write-Host 'API local funcionando. Se o DiakoHub ainda mostrar desconectado, confira host, porta e token na configuracao dele.'
    exit 0
} finally {
    $token = $null
}
