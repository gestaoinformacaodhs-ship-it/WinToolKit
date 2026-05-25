# Script de Importação de Certificado Digital do WinToolKit
# Desenvolvido para DHS Suporte Técnico

$ErrorActionPreference = "Stop"

# 1. Verificar privilégios de administrador
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " ERRO: Este script requer privilégios de Administrador!" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "Por favor, execute o arquivo 'InstalarCertificado.bat' ou"
    Write-Host "execute este console do PowerShell como Administrador."
    Write-Host ""
    Start-Sleep -Seconds 3
    exit 1
}

# 2. Localizar o arquivo do certificado
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certPath = Join-Path $scriptDir "wintoolkit.cer"

if (-not (Test-Path $certPath)) {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " ERRO: Arquivo 'wintoolkit.cer' nao foi encontrado!" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "Local esperado: $certPath"
    Write-Host "Certifique-se de que o arquivo 'wintoolkit.cer' está na mesma pasta."
    Write-Host ""
    Start-Sleep -Seconds 5
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   INSTALADOR DE CERTIFICADO CONFIAVEL - DHS SUPORTE TECNICO" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Importando certificado de assinatura de codigo..." -ForegroundColor Yellow

try {
    # Carregar o certificado
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)

    # 3. Importar para Root (Autoridades de Certificação Raiz Confiáveis)
    $storeRoot = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $storeRoot.Open("ReadWrite")
    $storeRoot.Add($cert)
    $storeRoot.Close()
    Write-Host "[OK] Adicionado as Autoridades de Certificacao Raiz Confiaveis da maquina." -ForegroundColor Green

    # 4. Importar para TrustedPublisher (Editores Confiáveis)
    $storePub = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
    $storePub.Open("ReadWrite")
    $storePub.Add($cert)
    $storePub.Close()
    Write-Host "[OK] Adicionado aos Editores Confiaveis da maquina." -ForegroundColor Green

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " SUCESSO! O WinToolKit agora e 100% confiavel neste PC." -ForegroundColor Green
    Write-Host " Os executaveis assinados rodarao sem alertas do SmartScreen." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " FALHA CRITICA ao importar certificado: $_" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
}

Start-Sleep -Seconds 3
