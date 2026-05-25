@echo off
:: Configura console para UTF-8
chcp 65001 > nul

:: Verifica privilégios de Administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run_script
) else (
    goto :elevate
)

:elevate
echo [INFO] Requisitando privilégios administrativos (UAC)...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:run_script
cd /d "%~dp0"
title DHS Suporte Técnico - Importador de Certificado
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstalarCertificado.ps1"
