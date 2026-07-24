#!/bin/bash
# =============================================================================
# LANCER.SH — Lance le panneau de contrôle (Linux / Mac / NAS)
# =============================================================================

set -e
cd "$(dirname "$0")" || exit 1

echo "========================================"
echo "   SERVEUR MULTIMÉDIA"
echo "   Panneau de Contrôle"
echo "========================================"
echo ""

# --- Vérification de Docker ---
if ! command -v docker &> /dev/null; then
  echo "❌ Docker n'est pas installé."
  echo "   Installez Docker : https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "❌ Docker n'est pas démarré."
  echo "   Lancez le service Docker et réessayez."
  exit 1
fi

# --- Détection d'archive ---
ARCHIVE=$(ls multimedia-config-*.tar.gz 2>/dev/null | head -n 1)
if [ -n "$ARCHIVE" ]; then
  echo "📦 Archive détectée : $ARCHIVE"
  echo "   Elle sera importable depuis le panneau de contrôle."
  echo ""
fi

# --- Création du réseau Docker ---
if ! docker network ls | grep -q "multimedia_net"; then
  echo "🌐 Création du réseau Docker..."
  docker network create multimedia_net
fi

# --- Build et démarrage du panneau ---
echo "🔧 Démarrage du panneau de contrôle..."
echo "   (Premier lancement : le build peut prendre 1-2 minutes)"
echo ""

cd panneau
docker compose up -d --build
cd ..

echo ""
echo "========================================"
echo "   ✅ Panneau de contrôle démarré !"
echo "========================================"
echo ""
echo "   👉  http://localhost:3000"
echo ""
echo "========================================"

# --- Ouverture du navigateur ---
sleep 2
if command -v xdg-open &> /dev/null; then
  xdg-open "http://localhost:3000" 2>/dev/null &
elif command -v open &> /dev/null; then
  open "http://localhost:3000" 2>/dev/null &
fi
