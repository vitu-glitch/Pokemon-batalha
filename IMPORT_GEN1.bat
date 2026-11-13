@echo off
setlocal
cd /d "%~dp0"
title PokeBrawl - Gen 1 Import

echo ==========================================
echo       POKEBRAWL - IMPORTAR GEN 1
echo ==========================================
echo.
echo O importador vai baixar e converter os 151 Pokemon.
echo Os 11 modelos que ja existem serao preservados.
echo Mantenha a internet conectada durante o processo.
echo.

where py >nul 2>nul
if %errorlevel%==0 (
    py game\tools\import_gen1.py
) else (
    python game\tools\import_gen1.py
)

if errorlevel 1 (
    echo.
    echo O importador encontrou um erro.
    echo Os arquivos ja baixados foram mantidos. Corrija a conexao e tente novamente.
) else (
    echo.
    echo Importacao concluida. Abra a pasta game no Godot.
)
echo.
pause
endlocal
