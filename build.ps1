# WinToolKit Native C# Compilation Script
# Orchestrated by Antigravity

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     COMPILADOR NATIVO WINTOOLKIT - INICIALIZANDO" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Locate csc.exe
$cscPaths = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$csc = $null
foreach ($path in $cscPaths) {
    if (Test-Path $path) {
        $csc = $path
        break
    }
}

if (-not $csc) {
    Write-Error "Erro: O compilador C# nativo (csc.exe) não foi encontrado no sistema!"
    exit 1
}

Write-Host "[OK] Compilador C# localizado em: $csc" -ForegroundColor Green
Write-Host ""

# Define workspace directories
$baseDir = Get-Location
$srcDir = Join-Path $baseDir "src"
$launcherSrc = Join-Path $srcDir "Launcher.cs"
$installerSrc = Join-Path $srcDir "Installer.cs"

# Output Executables
$launcherOut = Join-Path $baseDir "WinToolKit.exe"
$installerOut = Join-Path $baseDir "Instalar.exe"

# 2. Compile WinToolKit Launcher
Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[Compilando] Launcher Tray (WinToolKit.exe)..." -ForegroundColor Yellow
Write-Host "------------------------------------------------------------" -ForegroundColor Yellow

$launcherArgs = @(
    "/target:winexe",
    "/out:$launcherOut",
    "/optimize+",
    "/reference:System.Windows.Forms.dll,System.Drawing.dll,System.Management.dll",
    $launcherSrc
)

& $csc $launcherArgs
if ($LASTEXITCODE -eq 0 -and (Test-Path $launcherOut)) {
    Write-Host "[OK] WinToolKit.exe compilado com sucesso!" -ForegroundColor Green
    $size = (Get-Item $launcherOut).Length / 1KB
    Write-Host "     Tamanho do arquivo: {0:N2} KB" -f $size -ForegroundColor Gray
} else {
    Write-Error "Falha ao compilar WinToolKit.exe!"
    exit 1
}
Write-Host ""

# 3. Compile Installer Wizard
Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[Compilando] Instalador Personalizado (Instalar.exe)..." -ForegroundColor Yellow
Write-Host "------------------------------------------------------------" -ForegroundColor Yellow

$installerArgs = @(
    "/target:winexe",
    "/out:$installerOut",
    "/optimize+",
    "/reference:System.Windows.Forms.dll,System.Drawing.dll",
    $installerSrc
)

& $csc $installerArgs
if ($LASTEXITCODE -eq 0 -and (Test-Path $installerOut)) {
    Write-Host "[OK] Instalar.exe compilado com sucesso!" -ForegroundColor Green
    $size = (Get-Item $installerOut).Length / 1KB
    Write-Host "     Tamanho do arquivo: {0:N2} KB" -f $size -ForegroundColor Gray
} else {
    Write-Error "Falha ao compilar Instalar.exe!"
    exit 1
}
Write-Host ""

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     COMPILAÇÃO NATIVA CONCLUÍDA COM SUCESSO!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Os executáveis já estão disponíveis no diretório raiz:" -ForegroundColor Gray
Write-Host " -> WinToolKit.exe (Launcher na Bandeja do Sistema)" -ForegroundColor Gray
Write-Host " -> Instalar.exe (Assistente de Instalação Profissional)" -ForegroundColor Gray
Write-Host ""
