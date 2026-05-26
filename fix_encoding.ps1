$content = Get-Content -Path '.\web\index.html' -Encoding Default
Set-Content -Path '.\web\index.html' -Value $content -Encoding UTF8
