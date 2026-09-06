#!/usr/bin/env bash
# Sauvegarde complète : volume Wings du serveur Zomboid + volume Docker pelican-data.
#   BACKUP_DIR           dossier de sortie (défaut ./backups)
#   KEEP                 nombre d'archives conservées (défaut 7)
#   SKIP_PANEL=1         n'exporte pas pelican-data (tests)
#   SKIP_RUNNING_CHECK=1 ne vérifie pas si le serveur tourne (tests)
# Lancer avec sudo -E en production (lecture de /var/lib/pelican).
set -euo pipefail

# shellcheck source=pzpath.sh
source "$(dirname "$0")/pzpath.sh"

BACKUP_DIR=${BACKUP_DIR:-./backups}
KEEP=${KEEP:-7}

server_dir=$(pz_server_dir)
volume_dir=$(dirname "$server_dir")
uuid=$(basename "$volume_dir")

if [ "${SKIP_RUNNING_CHECK:-0}" != "1" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$uuid"; then
  echo "Attention : le serveur $uuid tourne. Arrête-le depuis le panel pour une sauvegarde cohérente." >&2
  echo "Relance avec SKIP_RUNNING_CHECK=1 pour forcer." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
stamp=$(date +%Y%m%d-%H%M%S)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

printf 'UUID=%s\nDATE=%s\n' "$uuid" "$stamp" > "$staging/meta.env"
cp -a "$volume_dir" "$staging/volume"

if [ "${SKIP_PANEL:-0}" != "1" ]; then
  docker run --rm -v pelican-data:/pelican-data:ro -v "$staging:/out" alpine \
    tar cf /out/panel.tar -C / pelican-data
fi

archive="$BACKUP_DIR/zomboid-$stamp.tar.gz"
members=(meta.env volume)
[ -f "$staging/panel.tar" ] && members+=(panel.tar)
tar czf "$archive" -C "$staging" "${members[@]}"
echo "Sauvegarde : $archive ($(du -h "$archive" | cut -f1))"

# rotation
find "$BACKUP_DIR" -maxdepth 1 -name 'zomboid-*.tar.gz' -printf '%T@ %p\n' \
  | sort -rn | cut -d' ' -f2- | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
  rm -f -- "$old"
  echo "Supprimé : $old"
done
