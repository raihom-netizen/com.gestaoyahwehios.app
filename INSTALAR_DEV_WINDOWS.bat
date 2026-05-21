@echo off
title Gestao YAHWEH - Instalar ambiente dev
echo.
echo Este script pede permissao de Administrador (UAC).
echo Instala: Git, JDK 17, Node, Android Studio, Cloud SDK, Flutter, Firebase CLI.
echo Log: _setup_log.txt na raiz do projeto.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup_dev_machine_windows.ps1"
echo.
echo Concluido. Reinicie o Cursor e abra um terminal novo.
echo Depois: flutter doctor -v
pause
