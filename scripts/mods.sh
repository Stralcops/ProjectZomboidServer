#!/usr/bin/env bash
# Gestion des mods Steam Workshop du serveur Zomboid.
#   mods.sh add <workshop_id>     ajoute l'item (WorkshopItems=) et ses Mod IDs (Mods=)
#   mods.sh remove <workshop_id>  retire l'item et ses Mod IDs
#   mods.sh list                  affiche Mods= et WorkshopItems=
# Le serveur doit être redémarré après chaque changement.
set -euo pipefail

# shellcheck source=pzpath.sh
source "$(dirname "$0")/pzpath.sh"

usage() {
  echo "Usage: $0 add <workshop_id> | remove <workshop_id> | list" >&2
  exit 2
}

# --- helpers ini ---------------------------------------------------------

ini_get() { # ini_get <key> <file>
  local line
  line=$(grep -m1 "^$1=" "$2" || true)
  printf '%s\n' "${line#"$1="}"
}

ini_set() { # ini_set <key> <value> <file>  (atomique)
  local key=$1 val=$2 file=$3 tmp
  tmp=$(mktemp "$(dirname "$file")/.ini.XXXXXX")
  if grep -q "^$key=" "$file"; then
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k && !done {print k"="v; done=1; next} {print}' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

# --- helpers listes "a;b;c" ----------------------------------------------

list_has() { # list_has <list> <item>
  case ";$1;" in *";$2;"*) return 0;; esac
  return 1
}

list_add() { # list_add <list> <item>
  if [ -z "$1" ]; then printf '%s\n' "$2"
  elif list_has "$1" "$2"; then printf '%s\n' "$1"
  else printf '%s;%s\n' "$1" "$2"; fi
}

list_remove() { # list_remove <list> <item>
  local out="" x
  local -a parts
  IFS=';' read -r -a parts <<< "$1"
  for x in "${parts[@]}"; do
    [ -z "$x" ] && continue
    [ "$x" = "$2" ] && continue
    out=$(list_add "$out" "$x")
  done
  printf '%s\n' "$out"
}

# --- résolution des Mod IDs ---------------------------------------------

resolve_mod_ids() { # resolve_mod_ids <workshop_id> -> une ligne par id, ordre stable
  local dir
  dir="$(pz_workshop_dir)/$1/mods"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 4 -name mod.info -print0 | sort -z \
    | xargs -0r grep -h '^id=' 2>/dev/null | sed 's/^id=//; s/\r$//' | awk '!seen[$0]++' || true
}

# --- commandes ------------------------------------------------------------

require_ini() {
  INI=$(pz_ini_path) || exit 1
  if [ ! -f "$INI" ]; then
    echo "Fichier introuvable : $INI" >&2
    exit 1
  fi
}

require_id() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "ID Workshop invalide : '${1:-}' (numérique attendu)" >&2; exit 2; }
}

cmd_add() {
  require_id "$1"; require_ini
  local ws mods id resolved
  ws=$(ini_get WorkshopItems "$INI")
  mods=$(ini_get Mods "$INI")
  ws=$(list_add "$ws" "$1")
  resolved=$(resolve_mod_ids "$1")
  if [ -z "$resolved" ]; then
    ini_set WorkshopItems "$ws" "$INI"
    echo "Item $1 ajouté à WorkshopItems. Mod non encore téléchargé :"
    echo "redémarre le serveur (il télécharge l'item), puis relance : $0 add $1"
    return 0
  fi
  while IFS= read -r id; do
    [ -n "$id" ] && mods=$(list_add "$mods" "$id")
  done <<< "$resolved"
  ini_set WorkshopItems "$ws" "$INI"
  ini_set Mods "$mods" "$INI"
  echo "Ajouté : WorkshopItems+=$1, Mods+=$(printf '%s' "$resolved" | paste -sd';')"
  echo "Redémarre le serveur pour appliquer."
}

cmd_remove() {
  require_id "$1"; require_ini
  local ws mods id resolved
  ws=$(ini_get WorkshopItems "$INI")
  mods=$(ini_get Mods "$INI")
  if ! list_has "$ws" "$1"; then
    echo "Item $1 absent de WorkshopItems, rien à faire."
    return 0
  fi
  ws=$(list_remove "$ws" "$1")
  resolved=$(resolve_mod_ids "$1")
  if [ -n "$resolved" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] && mods=$(list_remove "$mods" "$id")
    done <<< "$resolved"
  else
    echo "Attention : mod.info introuvable pour $1, Mods= n'a pas été modifié. Mods=$mods" >&2
  fi
  ini_set WorkshopItems "$ws" "$INI"
  ini_set Mods "$mods" "$INI"
  echo "Retiré : $1. Redémarre le serveur pour appliquer."
}

cmd_list() {
  require_ini
  echo "Mods=$(ini_get Mods "$INI")"
  echo "WorkshopItems=$(ini_get WorkshopItems "$INI")"
}

case "${1:-}" in
  add)    [ $# -eq 2 ] || usage; cmd_add "$2" ;;
  remove) [ $# -eq 2 ] || usage; cmd_remove "$2" ;;
  list)   cmd_list ;;
  *)      usage ;;
esac
