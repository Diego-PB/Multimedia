#!/bin/bash
# =============================================================================
# EXPORTER.SH — Exporte toutes les configurations dans une archive portable
# =============================================================================
# Crée un fichier .tar.gz contenant toutes les configs applicatives
# (clés API, indexeurs, profils, logins...) prêtes à être restaurées
# sur une autre machine via le panneau de contrôle.
# =============================================================================

cd "$(dirname "$0")" || exit 1

DATE=$(date +%Y-%m-%d_%H%M%S)
NOM_ARCHIVE="multimedia-config-${DATE}.tar.gz"

echo "========================================"
echo "   EXPORT DES CONFIGURATIONS"
echo "========================================"
echo ""

# --- Étape 1 : Arrêt propre des conteneurs ---
echo "🛑 Arrêt des conteneurs pour éviter la corruption des bases de données..."
for dossier in "diffusion" "recuperation" "reseau"; do
  if [ -d "$dossier" ] && [ -f "$dossier/compose.yaml" ]; then
    echo "  → Arrêt de $dossier..."
    (cd "$dossier" && docker compose down 2>/dev/null) || true
  fi
done
echo ""

# --- Étape 2 : Création de l'archive ---
echo "📦 Création de l'archive ${NOM_ARCHIVE}..."

# On exporte les configs en excluant :
# - Les caches Jellyfin (se régénèrent automatiquement)
# - Les fichiers de log (inutiles pour la migration)
# - Les fichiers de verrouillage (lockfiles)
tar czf "${NOM_ARCHIVE}" \
  --ignore-failed-read \
  --warning=no-file-changed \
  --exclude="*/cache/*" \
  --exclude="*/temp/*" \
  --exclude="*/Backups/*" \
  --exclude="*/logs/*" \
  --exclude="*/log/*" \
  --exclude="*logs.db*" \
  --exclude="*lockfile*" \
  --exclude="*.log" \
  reseau/config/ \
  recuperation/config/ \
  diffusion/config/ \
  2>/dev/null || true

TAILLE=$(du -h "${NOM_ARCHIVE}" | cut -f1)
echo ""

# --- Étape 3 : Redémarrage des conteneurs ---
echo "🚀 Redémarrage des conteneurs..."
docker network ls | grep -q "multimedia_net" || docker network create multimedia_net
for dossier in "reseau" "recuperation" "diffusion"; do
  if [ -d "$dossier" ] && [ -f "$dossier/compose.yaml" ]; then
    echo "  → Démarrage de $dossier..."
    (cd "$dossier" && docker compose up -d 2>/dev/null) || true
  fi
done
echo ""

# --- Résumé ---
echo "========================================"
echo "   ✅ EXPORT TERMINÉ"
echo "========================================"
echo ""
echo "  📁 Fichier : ${NOM_ARCHIVE}"
echo "  📏 Taille  : ${TAILLE}"
echo ""
echo "  Pour importer sur une autre machine :"
echo "  1. Copier ce fichier dans le dossier du projet"
echo "  2. Lancer lancer.bat (Windows) ou lancer.sh (Linux)"
echo "  3. Le panneau de contrôle le détectera automatiquement"
echo ""
echo "  ⚠️  Cette archive contient des données sensibles"
echo "      (clés API, config VPN). Transmettez-la de"
echo "      manière sécurisée (clé USB, transfert direct)."
echo "========================================"
