#!/usr/bin/env bats

@test "bats fonctionne" {
  run echo ok
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
