#!/bin/bash
# =============================================================================
#  SAUVEGARDE COMPLÈTE DE L'INFRASTRUCTURE MULTIMEDIA
#  Crée une archive portable contenant toute la configuration des services.
#  Usage : ./sauvegarder.sh [dossier_de_sortie]
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")" || exit 1

# --- Configuration ---
DOSSIER_SORTIE="${1:-.}"
HORODATAGE=$(date +%Y%m%d_%H%M%S)
NOM_ARCHIVE="multimedia_backup_${HORODATAGE}"
DOSSIER_TEMP=$(mktemp -d)
DOSSIER_BACKUP="${DOSSIER_TEMP}/${NOM_ARCHIVE}"

# Couleurs
VERT='\033[0;32m'
JAUNE='\033[1;33m'
ROUGE='\033[0;31m'
BLEU='\033[0;34m'
RESET='\033[0m'

info()  { echo -e "${BLEU}ℹ️  $1${RESET}"; }
ok()    { echo -e "${VERT}✅ $1${RESET}"; }
warn()  { echo -e "${JAUNE}⚠️  $1${RESET}"; }
erreur(){ echo -e "${ROUGE}❌ $1${RESET}"; }

# Nettoyage à la sortie
cleanup() { rm -rf "${DOSSIER_TEMP}"; }
trap cleanup EXIT

mkdir -p "${DOSSIER_BACKUP}"

echo ""
echo "=========================================="
echo "  SAUVEGARDE INFRASTRUCTURE MULTIMEDIA"
echo "=========================================="
echo ""

# --- Fonctions utilitaires ---

# Récupère l'API key depuis le config.xml d'un service *arr
get_api_key() {
  local config_xml="$1"
  if [ -f "$config_xml" ]; then
    grep -oP '<ApiKey>\K[^<]+' "$config_xml" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Vérifie si un conteneur tourne
est_actif() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# Sauvegarde un service *arr via son API de backup intégrée
sauvegarder_arr() {
  local nom="$1"
  local port="$2"
  local config_dir="$3"
  local api_version="${4:-v3}"

  info "Sauvegarde de ${nom}..."

  if ! est_actif "$nom"; then
    warn "${nom} n'est pas en cours d'exécution — copie directe des fichiers config"
    copie_directe "$nom" "$config_dir"
    return
  fi

  local api_key
  api_key=$(get_api_key "${config_dir}/config.xml")

  if [ -z "$api_key" ]; then
    warn "${nom} : impossible de trouver l'API key — copie directe"
    copie_directe "$nom" "$config_dir"
    return
  fi

  # Déclenche un backup via l'API
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:${port}/api/${api_version}/command" \
    -H "X-Api-Key: ${api_key}" \
    -H "Content-Type: application/json" \
    -d '{"name":"Backup"}' 2>/dev/null) || true

  if [ "$response" = "201" ] || [ "$response" = "200" ]; then
    info "${nom} : backup API déclenché, attente de la fin..."
    sleep 5  # Les backups sont rapides (quelques secondes)

    # Récupère le dernier backup créé
    local backup_dir="${config_dir}/Backups/scheduled"
    if [ ! -d "$backup_dir" ]; then
      backup_dir="${config_dir}/Backups/manual"
    fi

    if [ -d "$backup_dir" ]; then
      local dernier_backup
      dernier_backup=$(ls -t "${backup_dir}"/*.zip 2>/dev/null | head -1)
      if [ -n "$dernier_backup" ]; then
        mkdir -p "${DOSSIER_BACKUP}/${nom}"
        cp "$dernier_backup" "${DOSSIER_BACKUP}/${nom}/"
        ok "${nom} : backup API sauvegardé ($(basename "$dernier_backup"))"
        return
      fi
    fi

    warn "${nom} : backup API réussi mais fichier introuvable — copie directe"
  else
    warn "${nom} : API indisponible (HTTP ${response}) — copie directe"
  fi

  copie_directe "$nom" "$config_dir"
}

# Copie directe des fichiers de configuration essentiels (sans les gros caches/logs)
copie_directe() {
  local nom="$1"
  local config_dir="$2"

  if [ ! -d "$config_dir" ]; then
    erreur "${nom} : dossier config introuvable (${config_dir})"
    return
  fi

  mkdir -p "${DOSSIER_BACKUP}/${nom}"

  # On copie tout sauf les fichiers volumineux inutiles
  rsync -a \
    --exclude='logs/' \
    --exclude='Logs/' \
    --exclude='log/' \
    --exclude='cache/' \
    --exclude='Cache/' \
    --exclude='transcodes/' \
    --exclude='Backups/' \
    --exclude='MediaCover/' \
    --exclude='metadata/' \
    --exclude='*.log' \
    --exclude='*.log.*' \
    --exclude='.nfo' \
    "${config_dir}/" "${DOSSIER_BACKUP}/${nom}/" 2>/dev/null || \
  cp -r "${config_dir}/" "${DOSSIER_BACKUP}/${nom}/" 2>/dev/null

  ok "${nom} : copie directe effectuée"
}

# =============================================================================
#  SAUVEGARDE DE CHAQUE SERVICE
# =============================================================================

# --- Apps *arr (avec backup API intégré) ---
# Radarr (port 7878)
sauvegarder_arr "radarr" "7878" "recuperation/config/radarr"

# Sonarr (port 8989)
sauvegarder_arr "sonarr" "8989" "recuperation/config/sonarr"

# Prowlarr (port 9696)
sauvegarder_arr "prowlarr" "9696" "recuperation/config/prowlarr"

# Bazarr (port 6767) — API légèrement différente (v1)
sauvegarder_arr "bazarr" "6767" "recuperation/config/bazarr" "v1"

# --- Services sans API de backup ---

# qBittorrent
info "Sauvegarde de qBittorrent..."
copie_directe "qbittorrent" "recuperation/config/qbittorrent"

# Jellyfin
info "Sauvegarde de Jellyfin..."
copie_directe "jellyfin" "diffusion/config/jellyfin"

# Jellyseerr
info "Sauvegarde de Jellyseerr..."
copie_directe "jellyseerr" "diffusion/config/jellyseerr"

# Gluetun (très petit, juste des fichiers de statut)
info "Sauvegarde de Gluetun..."
copie_directe "gluetun" "reseau/config/gluetun"

# =============================================================================
#  SAUVEGARDE DES .env (pour référence — à adapter sur la nouvelle machine)
# =============================================================================

info "Sauvegarde des fichiers .env..."
mkdir -p "${DOSSIER_BACKUP}/_env_reference"
for dossier in diffusion recuperation reseau; do
  if [ -f "${dossier}/.env" ]; then
    cp "${dossier}/.env" "${DOSSIER_BACKUP}/_env_reference/${dossier}.env"
  fi
done
ok "Fichiers .env sauvegardés (dans _env_reference/)"

# =============================================================================
#  CRÉATION DE L'ARCHIVE
# =============================================================================

echo ""
info "Création de l'archive..."

ARCHIVE_FINALE="${DOSSIER_SORTIE}/${NOM_ARCHIVE}.tar.gz"
tar -czf "${ARCHIVE_FINALE}" -C "${DOSSIER_TEMP}" "${NOM_ARCHIVE}"

TAILLE=$(du -sh "${ARCHIVE_FINALE}" | cut -f1)

echo ""
echo "=========================================="
echo -e "  ${VERT}SAUVEGARDE TERMINÉE !${RESET}"
echo "=========================================="
echo ""
echo -e "  📦 Archive : ${BLEU}${ARCHIVE_FINALE}${RESET}"
echo -e "  📏 Taille  : ${TAILLE}"
echo ""
echo "  Pour restaurer sur une autre machine :"
echo "    1. Copie l'archive + le repo sur la nouvelle machine"
echo "    2. Lance : ./restaurer.sh ${NOM_ARCHIVE}.tar.gz"
echo ""
