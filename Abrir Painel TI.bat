@echo off
rem Abre o Painel de Suporte da TI como administrador.
rem O PainelTI.ps1 precisa estar na mesma pasta deste arquivo.
if not exist "%~dp0PainelTI.ps1" (
  echo Nao achei o PainelTI.ps1 nesta pasta. Extraia o .zip inteiro antes de abrir.
  pause
  exit /b 1
)
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + [char]34 + '%~dp0PainelTI.ps1' + [char]34)"
