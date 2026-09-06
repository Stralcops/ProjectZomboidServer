# Serveur Project Zomboid Build 42 — Pelican

Serveur dédié Project Zomboid (Build 42 stable) géré par Pelican Panel, en Docker.
Même déploiement en local (WSL) et sur VPS OVH.

- Premier lancement : `docs/LOCAL.md`
- Migration OVH : `docs/OVH.md`
- Mods : `docs/MODS.md`
- Design : `docs/superpowers/specs/2026-09-06-zomboid-server-pelican-design.md`

## Commandes

| Action | Commande |
|---|---|
| Démarrer panel + wings | `docker compose up -d` |
| Ajouter un mod | `scripts/mods.sh add <workshop_id>` |
| Sauvegarder | `scripts/backup.sh` |
| Restaurer | `scripts/restore.sh backups/<archive>.tar.gz` |
| Tests | `scripts/test.sh` |
