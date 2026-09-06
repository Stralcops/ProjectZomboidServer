#!/usr/bin/env bats

setup() {
  TMP=$(mktemp -d)
  export PELICAN_VOLUMES="$TMP/volumes"
  export BACKUP_DIR="$TMP/backups"
  export SKIP_PANEL=1 SKIP_RUNNING_CHECK=1
  unset PZ_SERVER_DIR
  UUID=1234abcd-0000-4000-8000-000000000001
  mkdir -p "$PELICAN_VOLUMES/$UUID/.cache/Server" "$PELICAN_VOLUMES/$UUID/.cache/Saves/Multiplayer/servertest"
  echo 'MaxPlayers=8' > "$PELICAN_VOLUMES/$UUID/.cache/Server/servertest.ini"
  echo 'world' > "$PELICAN_VOLUMES/$UUID/.cache/Saves/Multiplayer/servertest/map.bin"
  BACKUP="$BATS_TEST_DIRNAME/../scripts/backup.sh"
  RESTORE="$BATS_TEST_DIRNAME/../scripts/restore.sh"
}

teardown() { rm -rf "$TMP"; }

@test "backup crée une archive avec meta.env et le volume" {
  run "$BACKUP"
  [ "$status" -eq 0 ]
  archive=$(ls "$BACKUP_DIR"/zomboid-*.tar.gz)
  [ -f "$archive" ]
  tar tzf "$archive" | grep -q '^meta.env$'
  tar tzf "$archive" | grep -q '^volume/.cache/Server/servertest.ini$'
  tar xzf "$archive" -C "$TMP" meta.env
  grep -q "^UUID=$UUID$" "$TMP/meta.env"
}

@test "backup garde KEEP archives" {
  export KEEP=2
  for i in 1 2 3; do
    "$BACKUP" > /dev/null
    sleep 1
  done
  [ "$(ls "$BACKUP_DIR"/zomboid-*.tar.gz | wc -l)" -eq 2 ]
}

@test "restore recrée le volume à partir de l'archive" {
  "$BACKUP" > /dev/null
  archive=$(ls "$BACKUP_DIR"/zomboid-*.tar.gz)
  rm -rf "$PELICAN_VOLUMES/$UUID"
  run "$RESTORE" "$archive"
  [ "$status" -eq 0 ]
  [ "$(cat "$PELICAN_VOLUMES/$UUID/.cache/Saves/Multiplayer/servertest/map.bin")" = "world" ]
}

@test "restore remplace un volume existant" {
  "$BACKUP" > /dev/null
  archive=$(ls "$BACKUP_DIR"/zomboid-*.tar.gz)
  echo 'corrompu' > "$PELICAN_VOLUMES/$UUID/.cache/Saves/Multiplayer/servertest/map.bin"
  touch "$PELICAN_VOLUMES/$UUID/.cache/parasite"
  "$RESTORE" "$archive"
  [ "$(cat "$PELICAN_VOLUMES/$UUID/.cache/Saves/Multiplayer/servertest/map.bin")" = "world" ]
  [ ! -e "$PELICAN_VOLUMES/$UUID/.cache/parasite" ]
}

@test "restore sans argument -> code 2" {
  run "$RESTORE"
  [ "$status" -eq 2 ]
}

@test "restore avec archive inexistante -> code 1" {
  run "$RESTORE" "$TMP/nope.tar.gz"
  [ "$status" -eq 1 ]
}
