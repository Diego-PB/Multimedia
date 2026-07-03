#!/bin/bash

cd "$(dirname "$0")" || exit

echo "========================================"
echo "    GESTION DU SERVEUR MULTIMEDIA"
echo "========================================"
echo "1 - Lancer tout"
echo "2 - Éteindre tout"
echo "3 - Mettre à jour tous les conteneurs"
echo "0 - Quitter"
echo "========================================"
read -p "Votre choix : " choix

case $choix in
  1)
    echo "🚀 Démarrage des services..."
    # Ordre strict : Réseau en premier, puis les autres
    for dossier in "reseau" "recuperation" "diffusion"; do
      if [ -d "$dossier" ]; then
        echo "-> Allumage de $dossier..."
        cd "$dossier" && docker compose up -d && cd ..
      fi
    done
    echo "✅ Serveur démarré avec succès !"
    ;;
    
  2)
    echo "🛑 Arrêt des services..."
    # On éteint dans l'ordre inverse pour éviter les erreurs réseau
    for dossier in "diffusion" "recuperation" "reseau"; do
      if [ -d "$dossier" ]; then
        echo "-> Extinction de $dossier..."
        cd "$dossier" && docker compose down && cd ..
      fi
    done
    echo "✅ Serveur éteint !"
    ;;
    
  3)
    echo "🔄 Mise à jour des services..."
    # Télécharge les nouvelles versions et relance uniquement ce qui a changé
    for dossier in "reseau" "recuperation" "diffusion"; do
      if [ -d "$dossier" ]; then
        echo "-> Mise à jour de $dossier..."
        cd "$dossier" 
        docker compose pull
        docker compose up -d
        cd ..
      fi
    done
    echo "🧹 Nettoyage des anciennes images pour libérer de la place..."
    docker image prune -f
    echo "✅ Mise à jour terminée !"
    ;;
    
  0)
    echo "À bientôt !"
    exit 0
    ;;
    
  *)
    echo "❌ Choix invalide."
    ;;
esac