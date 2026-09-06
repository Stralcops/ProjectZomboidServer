#!/usr/bin/env bash
# Restaure une archive produite par backup.sh.
#   restore.sh <archive.tar.gz>
#   PELICAN_VOLUMES  racine des volumes Wings (défaut /var/lib/pelican/volumes)
#   SKIP_PANEL=1     ne restaure pas pelican-data (tests)
#   SKIP_RUNNING_CHECK=1
# Le serveur doit être arrêté (panel) et `docker compose stop panel` conseillé avant de restaurer pelican-data.
set -euo pipefail

archive=${1:-}
if [ -z "$archive" ]; then
  echo "Usage: $0 <archive.tar.gz>" >&2
  exit 2
fi
if [ ! -f "$archive" ]; then
  echo "Archive introuvable : $archive" >&2
  exit 1
fi

PELICAN_VOLUMES=${PELICAN_VOLUMES:-/var/lib/pelican/volumes}
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

tar xzf "$archive" -C "$staging"
# shellcheck source=/dev/null
source "$staging/meta.env"
: "${UUID:?meta.env sans UUID}"

if [ "${SKIP_RUNNING_CHECK:-0}" != "1" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$UUID"; then
  echo "Le serveur $UUID tourne. Arrête-le depuis le panel avant de restaurer." >&2
  exit 1
fi

target="$PELICAN_VOLUMES/$UUID"
mkdir -p "$PELICAN_VOLUMES"
rm -rf "$target"
cp -a "$staging/volume" "$target"
echo "Volume restauré : $target"

if [ "${SKIP_PANEL:-0}" != "1" ] && [ -f "$staging/panel.tar" ]; then
  docker run --rm -v pelican-data:/pelican-data -v "$staging:/in:ro" alpine \
    sh -c 'rm -rf /pelican-data/* /pelican-data/.[!.]* 2>/dev/null; tar xf /in/panel.tar -C /'
  echo "pelican-data restauré. Redémarre le panel : docker compose restart panel"
fi
