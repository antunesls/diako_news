# Lê agente.json sem expor credenciais; corrige apenas barras simples no caminho de imagens.
function Ler-ConfigAgente([string]$Arquivo) {
    $original = [System.IO.File]::ReadAllText($Arquivo, [System.Text.Encoding]::UTF8)
    $normalizado = [regex]::Replace($original, '("pastaImagensHolyrics"\s*:\s*")([^"\r\n]*)(")', {
        param($trecho)
        $caminho = [regex]::Replace($trecho.Groups[2].Value, '(?<!\\)\\(?!\\)', '\\')
        return $trecho.Groups[1].Value + $caminho + $trecho.Groups[3].Value
    })
    try {
        $dados = $normalizado | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'agente.json inválido. Corrija a sintaxe do JSON e execute o instalador novamente (o arquivo não foi alterado).'
    }
    if ($normalizado -cne $original) {
        [System.IO.File]::WriteAllText($Arquivo, $normalizado, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'Caminho de imagens do Holyrics normalizado no agente.json.'
    }
    return $dados
}
