#!/usr/bin/env bash
# Résolution du dossier serveur Zomboid (le ".cache" du volume Wings).
# À sourcer : source scripts/pzpath.sh
#   PZ_SERVER_DIR   surcharge directe du dossier .cache
#   PELICAN_VOLUMES racine des volumes Wings (défaut /var/lib/pelican/volumes)
#   PZ_SERVER_NAME  nom du serveur (défaut servertest)

pz_server_dir() {
  if [ -n "${PZ_SERVER_DIR:-}" ]; then
    printf '%s\n' "$PZ_SERVER_DIR"
    return 0
  fi
  local root="${PELICAN_VOLUMES:-/var/lib/pelican/volumes}"
  local found=()
  local d
  for d in "$root"/*/.cache; do
    [ -d "$d" ] && found+=("$d")
  done
  if [ "${#found[@]}" -eq 0 ]; then
    echo "Aucun serveur trouvé sous $root. Définis PZ_SERVER_DIR." >&2
    return 1
  fi
  if [ "${#found[@]}" -gt 1 ]; then
    echo "Plusieurs serveurs sous $root : ${found[*]}. Définis PZ_SERVER_DIR." >&2
    return 1
  fi
  printf '%s\n' "${found[0]}"
}

pz_ini_path() {
  local dir
  dir=$(pz_server_dir) || return 1
  printf '%s/Server/%s.ini\n' "$dir" "${PZ_SERVER_NAME:-servertest}"
}

pz_workshop_dir() {
  local dir
  dir=$(pz_server_dir) || return 1
  printf '%s/steamapps/workshop/content/108600\n' "$dir"
}
