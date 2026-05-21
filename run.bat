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
title WinToolKit - Servidor de Suporte Técnico
cls
echo ============================================================
echo      WINTOOLKIT - SISTEMA DE AUTOMAÇÃO DE SUPORTE
echo      DHS SUPORTE TÉCNICO - AMBIENTE OPERACIONAL WINDOWS
echo ============================================================
echo.
echo [SERVIDO] Inicializando o servidor web interno do toolkit...
echo [AVISO] Mantenha esta janela aberta enquanto utiliza a ferramenta.
echo [AVISO] Feche esta janela para encerrar o servidor e liberar as portas.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolkit.ps1"
echo.
echo [TERMINADO] Servidor finalizado.
pause
