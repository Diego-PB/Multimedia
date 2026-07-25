#!/bin/bash

# Se place dans le dossier du script
cd "$(dirname "$0")" || exit 1

echo "========================================"
echo "   ARRÊT DES DOCKERS"
echo "========================================"
echo ""

# Arrêt du panneau de contrôle s'il a été lancé avec lancer.sh
if [ -d "panneau" ]; then
  echo "🛑 Arrêt du panneau de contrôle..."
  cd panneau
  docker compose down
  cd ..
fi

echo ""
# Utilisation de votre script gestion.sh pour arrêter le reste des applications
if [ -f "gestion.sh" ]; then
  ./gestion.sh 2
fi

echo ""
echo "========================================"
echo "   ✅ Tous les dockers sont éteints !"
echo "========================================"
