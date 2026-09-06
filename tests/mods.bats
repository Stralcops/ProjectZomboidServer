#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export PZ_SERVER_DIR="$TMP/srv"
  mkdir -p "$PZ_SERVER_DIR/Server"
  INI="$PZ_SERVER_DIR/Server/servertest.ini"
  printf 'PVP=false\nMods=\nWorkshopItems=\nMaxPlayers=8\n' > "$INI"
  WS="$PZ_SERVER_DIR/steamapps/workshop/content/108600"
  MODS="$BATS_TEST_DIRNAME/../scripts/mods.sh"
}

teardown() { rm -rf "$TMP"; }

fake_mod() { # fake_mod <workshop_id> <mod_id> [sousdossier]
  local dir="$WS/$1/mods/$2${3:+/$3}"
  mkdir -p "$dir"
  printf 'name=%s\nid=%s\n' "$2" "$2" > "$dir/mod.info"
}

@test "usage sans argument -> code 2" {
  run "$MODS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "add refuse un ID non numérique et ne touche pas au fichier" {
  cp "$INI" "$TMP/before"
  run "$MODS" add abc123
  [ "$status" -eq 2 ]
  cmp -s "$INI" "$TMP/before"
}

@test "add sans mod.info : ajoute WorkshopItems seulement et demande un redémarrage" {
  run "$MODS" add 111
  [ "$status" -eq 0 ]
  grep -q '^WorkshopItems=111$' "$INI"
  grep -q '^Mods=$' "$INI"
  [[ "$output" == *"redémarre"* ]]
}

@test "add avec mod.info à plat : remplit Mods" {
  fake_mod 111 CoolMod
  run "$MODS" add 111
  [ "$status" -eq 0 ]
  grep -q '^WorkshopItems=111$' "$INI"
  grep -q '^Mods=CoolMod$' "$INI"
}

@test "add avec layout B42 (mods/<Nom>/42/mod.info) : remplit Mods" {
  fake_mod 222 Better42 42
  run "$MODS" add 222
  [ "$status" -eq 0 ]
  grep -q '^Mods=Better42$' "$INI"
}

@test "add est idempotent" {
  fake_mod 111 CoolMod
  "$MODS" add 111
  "$MODS" add 111
  grep -q '^WorkshopItems=111$' "$INI"
  grep -q '^Mods=CoolMod$' "$INI"
}

@test "add concatène avec ; et préserve les autres clés" {
  fake_mod 111 CoolMod
  fake_mod 222 Other
  "$MODS" add 111
  "$MODS" add 222
  grep -q '^WorkshopItems=111;222$' "$INI"
  grep -q '^Mods=CoolMod;Other$' "$INI"
  grep -q '^PVP=false$' "$INI"
  grep -q '^MaxPlayers=8$' "$INI"
}

@test "un item Workshop avec deux mods ajoute les deux IDs" {
  fake_mod 333 PackA
  fake_mod 333 PackB
  "$MODS" add 333
  grep -q '^Mods=PackA;PackB$' "$INI"
}

@test "remove retire des deux listes" {
  fake_mod 111 CoolMod
  fake_mod 222 Other
  "$MODS" add 111; "$MODS" add 222
  run "$MODS" remove 111
  [ "$status" -eq 0 ]
  grep -q '^WorkshopItems=222$' "$INI"
  grep -q '^Mods=Other$' "$INI"
}

@test "remove d'un ID absent : succès sans changement, avertissement" {
  cp "$INI" "$TMP/before"
  run "$MODS" remove 999
  [ "$status" -eq 0 ]
  cmp -s "$INI" "$TMP/before"
  [[ "$output" == *"absent"* ]]
}

@test "list affiche les deux lignes" {
  fake_mod 111 CoolMod
  "$MODS" add 111
  run "$MODS" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"WorkshopItems=111"* ]]
  [[ "$output" == *"Mods=CoolMod"* ]]
}

@test "ini introuvable -> code 1, message" {
  rm "$INI"
  run "$MODS" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"introuvable"* ]]
}

@test "écriture atomique : aucun fichier temporaire ne reste" {
  fake_mod 111 CoolMod
  "$MODS" add 111
  [ "$(ls "$PZ_SERVER_DIR/Server" | wc -l)" -eq 1 ]
}
