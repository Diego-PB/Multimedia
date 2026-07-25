#!/bin/bash
# =============================================================================
#  RESTAURATION DE L'INFRASTRUCTURE MULTIMEDIA
#  Restaure une archive créée par sauvegarder.sh sur une nouvelle machine.
#  Usage : ./restaurer.sh <archive.tar.gz>
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")" || exit 1

# Couleurs
VERT='\033[0;32m'
JAUNE='\033[1;33m'
ROUGE='\033[0;31m'
BLEU='\033[0;34m'
RESET='\033[0m'

info()  { echo -e "${BLEU}ℹ️  $1${RESET}"; }
ok()    { echo -e "${VERT}✅ $1${RESET}"; }
warn()  { echo -e "${JAUNE}⚠️  $1${RESET}"; }
erreur(){ echo -e "${ROUGE}❌ $1${RESET}" >&2; }

# --- Vérification des arguments ---
if [ $# -lt 1 ]; then
  erreur "Usage : $0 <archive.tar.gz>"
  echo ""
  echo "  Restaure une archive créée par sauvegarder.sh"
  echo "  L'archive contient la configuration de tous les services."
  echo ""
  echo "  ⚠️  IMPORTANT : les services doivent être ÉTEINTS avant la restauration."
  echo "     Utilisez : ./gestion.sh 2"
  exit 1
fi

ARCHIVE="$1"
if [ ! -f "$ARCHIVE" ]; then
  erreur "Archive introuvable : ${ARCHIVE}"
  exit 1
fi

echo ""
echo "=========================================="
echo "  RESTAURATION INFRASTRUCTURE MULTIMEDIA"
echo "=========================================="
echo ""

# --- Vérification que les services sont éteints ---
SERVICES_ACTIFS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^(radarr|sonarr|prowlarr|bazarr|qbittorrent|jellyfin|jellyseerr|gluetun)$' || true)
if [ -n "$SERVICES_ACTIFS" ]; then
  erreur "Des services sont encore actifs ! Éteignez-les d'abord :"
  echo "   ./gestion.sh 2"
  echo ""
  echo "  Services actifs :"
  echo "$SERVICES_ACTIFS" | sed 's/^/    - /'
  echo ""
  read -p "Continuer quand même ? (o/N) : " reponse
  if [[ ! "$reponse" =~ ^[oOyY]$ ]]; then
    echo "Restauration annulée."
    exit 1
  fi
fi

# --- Extraction de l'archive ---
DOSSIER_TEMP=$(mktemp -d)
cleanup() { rm -rf "${DOSSIER_TEMP}"; }
trap cleanup EXIT

info "Extraction de l'archive..."
tar -xzf "$ARCHIVE" -C "${DOSSIER_TEMP}"

# Trouve le dossier racine de l'archive
DOSSIER_BACKUP=$(find "${DOSSIER_TEMP}" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$DOSSIER_BACKUP" ]; then
  erreur "Archive invalide : aucun dossier trouvé"
  exit 1
fi

ok "Archive extraite"
echo ""

# --- Mapping des services vers leur dossier config dans le projet ---
declare -A CONFIG_MAP=(
  ["radarr"]="recuperation/config/radarr"
  ["sonarr"]="recuperation/config/sonarr"
  ["prowlarr"]="recuperation/config/prowlarr"
  ["bazarr"]="recuperation/config/bazarr"
  ["qbittorrent"]="recuperation/config/qbittorrent"
  ["jellyfin"]="diffusion/config/jellyfin"
  ["jellyseerr"]="diffusion/config/jellyseerr"
  ["gluetun"]="reseau/config/gluetun"
)

# API versions pour les *arr apps
declare -A API_VERSIONS=(
  ["radarr"]="v3"
  ["sonarr"]="v3"
  ["prowlarr"]="v3"
  ["bazarr"]="v1"
)

# Ports pour les *arr apps (pour la restauration via API)
declare -A PORTS=(
  ["radarr"]="7878"
  ["sonarr"]="8989"
  ["prowlarr"]="9696"
  ["bazarr"]="6767"
)

# --- Fonction de restauration d'un backup API (*arr) ---
restaurer_arr_backup() {
  local nom="$1"
  local backup_zip="$2"
  local config_dest="$3"

  info "${nom} : restauration du backup API..."

  # Crée le dossier config s'il n'existe pas
  mkdir -p "$config_dest"

  # Extrait le backup zip dans le dossier config
  # Les backups *arr contiennent les fichiers à la racine
  unzip -o "$backup_zip" -d "$config_dest" > /dev/null 2>&1

  ok "${nom} : backup restauré"
}

# --- Restauration de chaque service ---
for nom in "${!CONFIG_MAP[@]}"; do
  config_dest="${CONFIG_MAP[$nom]}"
  backup_source="${DOSSIER_BACKUP}/${nom}"

  if [ ! -d "$backup_source" ]; then
    warn "${nom} : pas de backup trouvé dans l'archive, ignoré"
    continue
  fi

  # Vérifie s'il y a un backup API (fichier .zip) ou une copie directe
  backup_zip=$(find "$backup_source" -name "*.zip" -type f 2>/dev/null | head -1)

  if [ -n "$backup_zip" ] && [[ -v "API_VERSIONS[$nom]" ]]; then
    # Backup API disponible — méthode préférée
    restaurer_arr_backup "$nom" "$backup_zip" "$config_dest"
  else
    # Copie directe
    info "${nom} : restauration par copie directe..."
    mkdir -p "$config_dest"

    # Si le dossier config existe déjà, on le sauvegarde
    if [ "$(ls -A "$config_dest" 2>/dev/null)" ]; then
      warn "${nom} : le dossier config existant sera écrasé"
    fi

    cp -rf "${backup_source}/." "$config_dest/"
    ok "${nom} : configuration restaurée"
  fi
done

# --- Affichage des .env de référence ---
echo ""
if [ -d "${DOSSIER_BACKUP}/_env_reference" ]; then
  echo "=========================================="
  echo "  FICHIERS .env À ADAPTER"
  echo "=========================================="
  echo ""
  echo "  L'archive contient les .env de l'ancienne machine."
  echo "  Ils sont dans l'archive à titre de référence."
  echo ""
  echo "  Les valeurs à adapter sur cette machine :"
  echo "    - PUID / PGID  →  lancez 'id' pour trouver les vôtres"
  echo "    - CHEMIN_ABSOLU_MEDIA  →  chemin vers vos médias ici"
  echo "    - VPN_CLE_PRIVEE  →  votre clé WireGuard"
  echo ""

  for env_file in "${DOSSIER_BACKUP}/_env_reference"/*.env; do
    stack_name=$(basename "$env_file" .env)
    echo -e "  ${BLEU}--- ${stack_name}/.env ---${RESET}"
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
      echo "    $line"
    done < "$env_file"
    echo ""
  done

  # Propose de copier les .env
  read -p "Voulez-vous copier ces .env tels quels ? (o/N) : " reponse
  if [[ "$reponse" =~ ^[oOyY]$ ]]; then
    for env_file in "${DOSSIER_BACKUP}/_env_reference"/*.env; do
      stack_name=$(basename "$env_file" .env)
      if [ -d "$stack_name" ]; then
        cp "$env_file" "${stack_name}/.env"
        ok "${stack_name}/.env copié"
      fi
    done
    warn "N'oubliez pas d'adapter PUID, PGID et CHEMIN_ABSOLU_MEDIA !"
  else
    info "Copiez-les manuellement depuis les .env.example"
  fi
fi

echo ""
echo "=========================================="
echo -e "  ${VERT}RESTAURATION TERMINÉE !${RESET}"
echo "=========================================="
echo ""
echo "  Prochaines étapes :"
echo "    1. Vérifiez/adaptez les fichiers .env de chaque stack"
echo "    2. Lancez les services : ./gestion.sh 1"
echo "    3. Vérifiez que tout fonctionne dans les interfaces web"
echo ""
