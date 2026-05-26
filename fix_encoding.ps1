# Script definitivo para corrigir encoding do index.html
# Le o arquivo como Windows-1252 (ANSI) e salva como UTF-8

$inputFile  = Join-Path $PSScriptRoot "web\index.html"
$outputFile = $inputFile

# Ler como ANSI (Windows-1252) que e o encoding atual
$content = [System.IO.File]::ReadAllText($inputFile, [System.Text.Encoding]::GetEncoding(1252))

Write-Host "Arquivo lido. Tamanho: $($content.Length) chars"
Write-Host "Exemplo antes: $($content.Substring(0, 200))"

# Salvar como UTF-8 sem BOM (para browser nao ter problemas)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($outputFile, $content, $utf8NoBom)

Write-Host "Arquivo salvo como UTF-8 sem BOM."

# Verificar resultado
$check = Get-Content $outputFile -Raw -Encoding UTF8 | Select-String "Atualiza" | Select-Object -First 3
Write-Host "Verificacao: $check"
