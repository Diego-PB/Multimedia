#!/bin/bash

cd "$(dirname "$0")" || exit

# Vérifie si un paramètre a été passé au lancement (ex: ./script.sh 1)
if [ -n "$1" ]; then
  choix=$1
else
  # Sinon, affiche le menu classique
  echo "========================================"
  echo "    GESTION DU SERVEUR MULTIMEDIA"
  echo "========================================"
  echo "1 - Lancer tout (Mise à jour incluse)"
  echo "2 - Éteindre tout"
  echo "3 - Mettre à jour et nettoyer les images"
  echo "4 - Sauvegarder la configuration"
  echo "5 - Restaurer une sauvegarde"
  echo "0 - Quitter"
  echo "========================================"
  read -p "Votre choix : " choix
fi

case $choix in
  1)
    echo "🚀 Démarrage des services..."

    echo "🌐 Vérification du réseau partagé 'multimedia_net'..."
    docker network ls | grep -q "multimedia_net" || docker network create multimedia_net

    # Ordre strict : Réseau en premier, puis les autres
    for dossier in "reseau" "recuperation" "diffusion"; do
      if [ -d "$dossier" ]; then
        echo "-> Mise à jour et allumage de $dossier..."
        cd "$dossier" 
        docker compose pull # Assure que l'image est à jour avant de lancer
        docker compose up -d 
        cd ..
      fi
    done
    echo "✅ Serveur démarré avec succès sur les dernières versions !"
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
    echo "🔄 Mise à jour et nettoyage complet..."

    docker network ls | grep -q "multimedia_net" || docker network create multimedia_net
    
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
    echo "✅ Mise à jour et nettoyage terminés !"
    ;;

  4)
    echo "📦 Lancement de la sauvegarde..."
    ./sauvegarder.sh
    ;;

  5)
    if [ -n "${2:-}" ]; then
      ./restaurer.sh "$2"
    else
      # Cherche les archives disponibles
      archives=( multimedia_backup_*.tar.gz )
      if [ ! -f "${archives[0]}" ]; then
        echo "❌ Aucune archive trouvée dans ce dossier."
        echo "   Placez un fichier multimedia_backup_*.tar.gz ici."
        exit 1
      fi

      echo "📋 Archives disponibles :"
      echo ""
      for i in "${!archives[@]}"; do
        taille=$(du -sh "${archives[$i]}" | cut -f1)
        echo "  $((i+1))) ${archives[$i]}  (${taille})"
      done
      echo ""

      if [ ${#archives[@]} -eq 1 ]; then
        read -p "Restaurer cette archive ? (O/n) : " reponse
        if [[ "$reponse" =~ ^[nN]$ ]]; then
          echo "Annulé."
          exit 0
        fi
        ./restaurer.sh "${archives[0]}"
      else
        read -p "Numéro de l'archive à restaurer (1-${#archives[@]}) : " num
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#archives[@]} ]; then
          ./restaurer.sh "${archives[$((num-1))]}"
        else
          echo "❌ Choix invalide."
        fi
      fi
    fi
    ;;
    
  0)
    echo "À bientôt !"
    exit 0
    ;;
    
  *)
    echo "❌ Choix invalide."
    ;;
esac