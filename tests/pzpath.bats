#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export PELICAN_VOLUMES="$TMP/volumes"
  unset PZ_SERVER_DIR PZ_SERVER_NAME
  source "$BATS_TEST_DIRNAME/../scripts/pzpath.sh"
}

teardown() { rm -rf "$TMP"; }

@test "PZ_SERVER_DIR prime sur tout" {
  mkdir -p "$TMP/custom"
  export PZ_SERVER_DIR="$TMP/custom"
  run pz_server_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/custom" ]
}

@test "détecte l'unique volume contenant .cache" {
  mkdir -p "$PELICAN_VOLUMES/aaaa-1111/.cache"
  run pz_server_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$PELICAN_VOLUMES/aaaa-1111/.cache" ]
}

@test "échoue si aucun volume" {
  mkdir -p "$PELICAN_VOLUMES"
  run pz_server_dir
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aucun serveur"* ]]
}

@test "échoue si plusieurs volumes" {
  mkdir -p "$PELICAN_VOLUMES/a/.cache" "$PELICAN_VOLUMES/b/.cache"
  run pz_server_dir
  [ "$status" -eq 1 ]
  [[ "$output" == *"PZ_SERVER_DIR"* ]]
}

@test "pz_ini_path utilise servertest par défaut" {
  export PZ_SERVER_DIR="$TMP/s"
  run pz_ini_path
  [ "$output" = "$TMP/s/Server/servertest.ini" ]
}

@test "pz_ini_path respecte PZ_SERVER_NAME" {
  export PZ_SERVER_DIR="$TMP/s" PZ_SERVER_NAME=knox
  run pz_ini_path
  [ "$output" = "$TMP/s/Server/knox.ini" ]
}

@test "pz_workshop_dir pointe sur 108600" {
  export PZ_SERVER_DIR="$TMP/s"
  run pz_workshop_dir
  [ "$output" = "$TMP/s/steamapps/workshop/content/108600" ]
}
