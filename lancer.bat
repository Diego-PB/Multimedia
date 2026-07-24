@echo off
chcp 65001 >nul 2>&1
title Serveur Multimedia - Panneau de Controle

echo ========================================
echo    SERVEUR MULTIMEDIA
echo    Panneau de Controle
echo ========================================
echo.

REM --- Vérification de Docker ---
docker version >nul 2>&1
if errorlevel 1 (
    echo ❌ Docker n'est pas detecte ou n'est pas demarre.
    echo.
    echo    Assurez-vous que Docker Desktop est installe et en cours d'execution.
    echo    Telechargement : https://www.docker.com/products/docker-desktop
    echo.
    pause
    exit /b 1
)

REM --- Détection et import automatique d'une archive ---
for %%f in (multimedia-config-*.tar.gz) do (
    if exist "%%f" (
        echo 📦 Archive de configuration detectee : %%f
        echo    Elle sera importable depuis le panneau de controle.
        echo.
    )
)

REM --- Création du réseau Docker ---
docker network ls | findstr "multimedia_net" >nul 2>&1
if errorlevel 1 (
    echo 🌐 Creation du reseau Docker...
    docker network create multimedia_net >nul 2>&1
)

REM --- Build et démarrage du panneau ---
echo 🔧 Demarrage du panneau de controle...
echo    (Premier lancement : le build peut prendre 1-2 minutes)
echo.

cd panneau
docker compose up -d --build
cd ..

if errorlevel 1 (
    echo.
    echo ❌ Erreur lors du demarrage. Verifiez les logs avec :
    echo    docker logs multimedia-panneau
    pause
    exit /b 1
)

echo.
echo ========================================
echo    ✅ Panneau de controle demarre !
echo ========================================
echo.
echo    Ouverture du navigateur...
echo    Si rien ne s'ouvre, allez sur :
echo.
echo    👉 http://localhost:3000
echo.
echo ========================================
echo.

REM --- Ouverture du navigateur ---
timeout /t 3 /nobreak >nul
start http://localhost:3000

echo Appuyez sur une touche pour fermer cette fenetre...
echo (Le serveur continue de tourner en arriere-plan)
pause >nul
