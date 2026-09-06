# Serveur Project Zomboid B42 + Pelican — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un dépôt qui lance, en une commande, Pelican Panel + Wings en Docker, héberge un serveur Project Zomboid Build 42 stable vanilla pour 8 joueurs, et fournit des scripts testés pour les mods et les sauvegardes, identiques en local (WSL) et sur OVH.

**Architecture:** `compose.yml` décrit deux services (panel Pelican avec SQLite, agent Wings). Wings crée lui-même le conteneur Zomboid à partir de l'egg officiel `pelican-eggs/games-steamcmd/project_zomboid`. Les scripts shell agissent sur le volume Wings du serveur (`/var/lib/pelican/volumes/<uuid>/`), jamais sur le conteneur.

**Tech Stack:** Docker CE 29 + compose v2, Pelican Panel (`ghcr.io/pelican/panel:latest`), Wings (`ghcr.io/pelican/wings:latest`), egg SteamCMD (`ghcr.io/parkervcp/steamcmd:debian`), Bash, bats (tests), shellcheck.

**Spec:** `docs/superpowers/specs/2026-09-06-zomboid-server-pelican-design.md`

## Global Constraints

- Project Zomboid **Build 42 stable** : app Steam `380870`, variable `SRCDS_BETAID` laissée vide.
- Serveur nommé `servertest` (variable `SERVER_NAME=servertest` de l'egg) pour que les fichiers soient `servertest.ini` et `servertest_SandboxVars.lua`.
- Ports : panel 80 (local) / 443 (OVH), Wings 8080 et 2022, Zomboid UDP 16261 (`SERVER_PORT`) et 16262 (`STEAM_PORT`), RCON TCP 27015 jamais exposé.
- Mémoire Zomboid `-Xmx6g`. `MaxPlayers=8`. `PVP=false`. `Public=false`. `Open=false`. `BackupsOnStart=false`.
- Réglages de jeu : preset Apocalypse, aucune valeur modifiée.
- Toute écriture de fichier de config par script est atomique (fichier temporaire puis `mv`).
- Les scripts tournent sur WSL Ubuntu 24.04 et sur Ubuntu 24.04 OVH sans modification ; ils lisent `PZ_SERVER_DIR` pour surcharger le chemin du serveur.
- Environnement d'exécution : les commandes se lancent **dans WSL** (`wsl.exe -d Ubuntu -- bash -c "..."` depuis Windows, ou un terminal Ubuntu). Le dépôt est `/home/antoinem/ProjectZomboid`. Les chemins `/var/lib/pelican` exigent `sudo`.
- Commits en français, préfixe conventionnel (`feat:`, `docs:`, `test:`, `chore:`), avec le trailer :
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SztU1kHQtbPiaA19Fxhmgh
  ```

## Statut d'exécution (2026-09-06)

| Tâche | État | Notes |
|---|---|---|
| 1 Amorçage | fait | bats/shellcheck installés sous `~/.local/bin` (pas d'apt : sudo à mot de passe) |
| 2 Compose | fait | ports 80/443 pris par un autre projet → 8081/8443 ; `BEHIND_PROXY=true` en local (Caddy ne sert sinon que l'hôte de `APP_URL`) |
| 3 Installeur, nœud, egg | fait | nœud créé en CLI (`p:node:make`), FQDN = IP WSL, allocations via tinker |
| 4 Serveur Zomboid | fait | créé via `ServerCreationService`, `-Xmx6g`, config vanilla fusionnée, SandboxVars capturé, `SERVER STARTED` |
| 5 pzpath.sh | fait | correctif : le dossier Workshop est `<volume>/steamapps/workshop/content/108600`, pas sous `.cache` |
| 6 mods.sh | fait | correctif : conserver droits/propriétaire (uid 988) ; test réel avec Minimap Style Options (3526517370), `loading MinimapStyleOptions.` dans le journal |
| 7 backup/restore | scripts faits | test réel en cours |
| 8 Planifications | fait | créées via tinker, `next_run_at` calculé avec `Utilities::getScheduleNextRunDate` ; « Run now » validé pour les deux |
| 9 Docs | fait | LOCAL/OVH/MODS |
| 10 Vérification finale | à faire | test de connexion client Steam par l'utilisateur |

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `compose.yml` | Services `panel` et `wings`, volumes, réseau `pelican` |
| `.env.example` | `APP_URL`, `ADMIN_EMAIL`, `TZ` ; copié en `.env` (ignoré par git) |
| `.gitignore` | `.env`, `backups/`, `wings/config.yml` |
| `wings/config.yml.example` | Gabarit commenté : d'où vient le vrai `config.yml` |
| `zomboid/servertest.ini` | Surcharges de config serveur (le jeu complète les clés manquantes) |
| `zomboid/servertest_SandboxVars.lua` | Preset Apocalypse capturé depuis le serveur après premier lancement |
| `scripts/pzpath.sh` | Fonction `pz_server_dir` : résout le dossier `.cache` du serveur (sourcé par les autres scripts) |
| `scripts/mods.sh` | `add <id>` / `remove <id>` / `list` sur `Mods=` et `WorkshopItems=` |
| `scripts/backup.sh` | Archive volume Zomboid + volume `pelican-data`, rotation 7 |
| `scripts/restore.sh` | Restaure une archive de `backup.sh` |
| `scripts/test.sh` | `shellcheck` + `bats tests/` |
| `tests/mods.bats`, `tests/pzpath.bats`, `tests/backup.bats` | Tests des scripts sur des arborescences factices |
| `docs/LOCAL.md` | Premier lancement pas à pas (installer, nœud, egg, serveur, planifications) |
| `docs/OVH.md` | Migration et checklist réseau |
| `docs/MODS.md` | Choisir et ajouter un mod B42 |
| `README.md` | Vue d'ensemble et liens vers les docs |

---

### Task 1 : Amorçage du dépôt et outillage de test

**Files:**
- Create: `.gitignore`, `README.md`, `scripts/test.sh`, `tests/smoke.bats`

**Interfaces:**
- Produces: `scripts/test.sh` (exécute shellcheck sur `scripts/*.sh` puis `bats tests/`). Tous les tests suivants passent par lui.

- [ ] **Step 1 : Installer bats et shellcheck dans WSL**

```bash
sudo apt-get update && sudo apt-get install -y bats shellcheck
bats --version && shellcheck --version | head -2
```
Attendu : `Bats 1.x` et `ShellCheck - shell script analysis tool`.

- [ ] **Step 2 : Écrire `.gitignore`**

```gitignore
.env
backups/
wings/config.yml
```

- [ ] **Step 3 : Écrire le test de fumée `tests/smoke.bats`**

```bash
#!/usr/bin/env bats

@test "bats fonctionne" {
  run echo ok
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
```

- [ ] **Step 4 : Écrire `scripts/test.sh`**

```bash
#!/usr/bin/env bash
# Lance shellcheck sur les scripts puis les tests bats.
set -euo pipefail
cd "$(dirname "$0")/.."
shellcheck scripts/*.sh
bats tests/
```

- [ ] **Step 5 : Rendre exécutable et lancer**

```bash
chmod +x scripts/test.sh && scripts/test.sh
```
Attendu : shellcheck silencieux, `1 test, 0 failures`.

- [ ] **Step 6 : Écrire `README.md`**

```markdown
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
```

- [ ] **Step 7 : Commit**

```bash
git add .gitignore README.md scripts/test.sh tests/smoke.bats
git commit -m "chore: amorçage du dépôt et outillage de test (bats, shellcheck)"
```

---

### Task 2 : compose.yml, .env.example et démarrage du panel

**Files:**
- Create: `compose.yml`, `.env.example`, `wings/config.yml.example`

**Interfaces:**
- Produces: service `panel` joignable sur `http://localhost`, service `wings` avec alias réseau `wings` (le panel joindra le nœud en `http://wings:8080`). Le réseau compose s'appelle `pelican`. Wings crée ses propres réseaux pour les serveurs de jeu (`pelican_nw`, sous-réseau 172.18.0.0/16 par défaut) : le réseau compose utilise 172.20.0.0/16 pour ne pas entrer en collision.

- [ ] **Step 1 : Écrire `.env.example`**

```dotenv
# URL complète du panel, protocole inclus. Local : http://localhost. OVH : https://zomboid.mondomaine.fr
APP_URL=http://localhost
# Email pour Let's Encrypt (utilisé seulement si APP_URL est en https)
ADMIN_EMAIL=stralcops@gmail.com
TZ=Europe/Paris
```

- [ ] **Step 2 : Écrire `compose.yml`**

```yaml
services:
  panel:
    image: ghcr.io/pelican/panel:latest
    restart: unless-stopped
    networks:
      - pelican
    ports:
      - "80:80"
      - "443:443"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - pelican-data:/pelican-data
      - pelican-logs:/var/www/html/storage/logs
    environment:
      XDG_DATA_HOME: /pelican-data
      APP_URL: "${APP_URL}"
      ADMIN_EMAIL: "${ADMIN_EMAIL}"
      TZ: "${TZ}"

  wings:
    image: ghcr.io/pelican/wings:latest
    restart: unless-stopped
    networks:
      pelican:
        aliases:
          - wings
    ports:
      - "8080:8080"
      - "2022:2022"
    tty: true
    environment:
      TZ: "${TZ}"
      WINGS_UID: 988
      WINGS_GID: 988
      WINGS_USERNAME: pelican
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/var/lib/docker/containers/:/var/lib/docker/containers/"
      - "/etc/pelican/:/etc/pelican/"
      - "/var/lib/pelican/:/var/lib/pelican/"
      - "/var/log/pelican/:/var/log/pelican/"
      - "/tmp/pelican/:/tmp/pelican/"
      - "/etc/ssl/certs:/etc/ssl/certs:ro"

volumes:
  pelican-data:
  pelican-logs:

networks:
  pelican:
    name: pelican
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

- [ ] **Step 3 : Écrire `wings/config.yml.example`**

```yaml
# Ce fichier n'est PAS lu par Wings. Le vrai fichier est /etc/pelican/config.yml sur l'hôte.
# Il est généré par le panel : Admin > Nodes > (ton nœud) > onglet "Configuration".
# Copie ce contenu tel quel dans /etc/pelican/config.yml (sudo), puis `docker compose restart wings`.
#
# Points à vérifier dans le fichier généré :
#   api.host: 0.0.0.0
#   api.port: 8080
#   system.data: /var/lib/pelican/volumes
#   remote: doit être joignable DEPUIS le conteneur wings. En local : http://panel (alias compose),
#           pas http://localhost. Sur OVH : https://<domaine>.
```

- [ ] **Step 4 : Créer les dossiers hôte et le `.env`, valider le compose**

```bash
sudo mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican /tmp/pelican
cp .env.example .env
docker compose config --quiet && echo COMPOSE_OK
```
Attendu : `COMPOSE_OK`.

- [ ] **Step 5 : Démarrer le panel seul et vérifier l'installeur**

```bash
docker compose up -d panel
sleep 60
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/installer
docker compose logs panel | grep -i 'app key' || true
```
Attendu : code `200`. Note la ligne « Generated app key » : c'est la clé de chiffrement de la base, à conserver.

- [ ] **Step 6 : Commit**

```bash
git add compose.yml .env.example wings/config.yml.example
git commit -m "feat: compose Pelican panel + wings"
```

---

### Task 3 : Installation du panel, nœud Wings, import de l'egg (manuel, vérifié)

**Files:**
- Create: `docs/LOCAL.md` (sections 1 à 3)

**Interfaces:**
- Produces: un nœud Wings en ligne dans le panel, l'egg « Project Zomboid » importé, un compte admin. Les tâches 4 et suivantes supposent ce nœud.

- [ ] **Step 1 : Finir l'installeur web**

Ouvrir `http://localhost/installer` depuis Windows. Choisir : base de données **SQLite**, cache **filesystem**, session **filesystem**, queue **database**. Créer le compte admin (email `stralcops@gmail.com`). À la fin, tu es connecté au panel.

- [ ] **Step 2 : Créer le nœud**

Panel > Admin > Nodes > Create. Valeurs :
- Name : `local`
- FQDN : `wings` (résolu par l'alias compose ; le panel joint Wings en interne)
- Communicate over SSL : **Non** (local en http)
- Port : `8080`, SFTP port : `2022`
- Memory : `7168` MiB, Disk : `40000` MiB
- Daemon data : `/var/lib/pelican/volumes` (défaut)

Sauvegarder. Onglet **Configuration** : copier le bloc YAML.

- [ ] **Step 3 : Installer la config Wings et démarrer Wings**

```bash
sudo tee /etc/pelican/config.yml > /dev/null   # coller le YAML, terminer par Ctrl+D
sudo grep -E '^\s*remote:' /etc/pelican/config.yml
```
La ligne `remote:` doit être `http://panel` (le nom du service compose), pas `http://localhost`. Si ce n'est pas le cas, l'éditer avec `sudo nano /etc/pelican/config.yml`.

```bash
docker compose up -d wings
sleep 5
docker compose logs wings | tail -20
curl -s http://localhost:8080 | head -c 200; echo
```
Attendu : logs sans `error`, et curl renvoie un JSON `{"error":"The required authorization heads were not present in the request."}` (401 = Wings répond).

Dans le panel, la page Nodes doit afficher le nœud `local` avec une pastille verte (heartbeat OK). Si rouge : vérifier `remote:` et `docker compose logs wings`.

- [ ] **Step 4 : Importer l'egg**

Panel > Admin > Eggs > Import. Coller l'URL :
`https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/project_zomboid/egg-project-zomboid.json`
Vérifier que l'egg « Project Zomboid » apparaît avec l'image `ghcr.io/parkervcp/steamcmd:debian`.

- [ ] **Step 5 : Rédiger `docs/LOCAL.md` sections 1 à 3**

Écrire, en français, les trois sections ci-dessus (Prérequis + `docker compose up -d panel`, Installeur, Nœud + Wings, Egg) avec exactement les valeurs et commandes des étapes 1 à 4, plus la note sur la clé « Generated app key ». Titres : `## 1. Prérequis et démarrage du panel`, `## 2. Installeur`, `## 3. Nœud Wings et egg`.

- [ ] **Step 6 : Commit**

```bash
git add docs/LOCAL.md
git commit -m "docs: LOCAL.md — installeur, nœud Wings, import de l'egg"
```

---

### Task 4 : Configuration Zomboid, création et premier démarrage du serveur

**Files:**
- Create: `zomboid/servertest.ini`, `zomboid/servertest_SandboxVars.lua`
- Modify: `docs/LOCAL.md` (sections 4 et 5)

**Interfaces:**
- Produces: un serveur Zomboid démarré, son UUID de volume, `.cache/Server/servertest.ini` conforme aux contraintes globales, et le preset Apocalypse capturé dans le dépôt. Les scripts des tâches 5 à 7 lisent `/var/lib/pelican/volumes/<uuid>/.cache/`.

- [ ] **Step 1 : Écrire `zomboid/servertest.ini` (surcharges seulement)**

Le serveur complète les clés absentes avec ses défauts au premier démarrage, puis réécrit le fichier complet.

```ini
# Surcharges du serveur Zomboid. Le jeu ajoute les clés manquantes au démarrage.
PVP=false
PauseEmpty=true
GlobalChat=true
Open=false
ServerWelcomeMessage=Bienvenue dans Knox County. Restez groupés, restez discrets.
Public=false
PublicName=
PublicDescription=
MaxPlayers=8
PingLimit=400
SafetySystem=false
BackupsOnStart=false
BackupsOnVersionChange=true
BackupsCount=5
Mods=
WorkshopItems=
Map=Muldraugh, KY
RCONPort=27015
RCONPassword=
Password=
DoLuaChecksum=true
```

- [ ] **Step 2 : Créer le serveur dans le panel**

Panel > Admin > Servers > Create :
- Name : `zomboid`, Owner : ton compte, Node : `local`
- Egg : Project Zomboid
- Allocation principale : IP `0.0.0.0`, port `16261` (créer l'allocation dans le nœud si besoin, onglet Allocations), allocation supplémentaire : `16262`
- Memory : `7168` MiB, Disk : `30000` MiB, CPU : `0` (illimité)
- Variables : `SERVER_NAME=servertest`, `ADMIN_USER=admin`, `ADMIN_PASSWORD=<choisir, ≤32 car.>`, `STEAM_PORT=16262`, `MAX_PLAYERS=8`, `SRCDS_BETAID` vide, `AUTO_UPDATE=1`

L'installation (SteamCMD, ~4 Go) démarre. Suivre dans l'onglet Console. Attendu à la fin : `Install script completed` ou équivalent, serveur en état « Offline ».

- [ ] **Step 3 : Retrouver l'UUID et le volume**

```bash
UUID=$(sudo ls /var/lib/pelican/volumes/ | head -1); echo "$UUID"
sudo ls /var/lib/pelican/volumes/"$UUID"/ | head
```
Attendu : un seul dossier UUID, contenant `ProjectZomboid64`, `ProjectZomboid64.json`, `jre64/`, `steamapps/`.

- [ ] **Step 4 : Régler la mémoire JVM à 6 Go**

```bash
sudo grep -n 'Xm' /var/lib/pelican/volumes/"$UUID"/ProjectZomboid64.json
```
Noter la valeur actuelle de `-Xmx`. Puis :

```bash
sudo sed -i -E 's/"-Xmx[0-9]+[mMgG]"/"-Xmx6g"/' /var/lib/pelican/volumes/"$UUID"/ProjectZomboid64.json
sudo grep -n 'Xmx' /var/lib/pelican/volumes/"$UUID"/ProjectZomboid64.json
```
Attendu : `"-Xmx6g"`.

- [ ] **Step 5 : Premier démarrage, puis injection de la config**

Dans le panel : Start. Attendre `SERVER STARTED` dans la console (la première génération du monde prend plusieurs minutes). Puis Stop.

```bash
sudo ls /var/lib/pelican/volumes/"$UUID"/.cache/Server/
```
Attendu : `servertest.ini`, `servertest_SandboxVars.lua`, `servertest_spawnregions.lua`.

Injecter les surcharges en fusionnant clé par clé (le fichier généré est complet, on remplace seulement nos clés) :

```bash
INI=/var/lib/pelican/volumes/$UUID/.cache/Server/servertest.ini
sudo cp "$INI" "$INI.bak"
while IFS='=' read -r key val; do
  case "$key" in ''|'#'*) continue;; esac
  if sudo grep -q "^$key=" "$INI"; then
    sudo sed -i "s|^$key=.*|$key=$val|" "$INI"
  else
    echo "$key=$val" | sudo tee -a "$INI" > /dev/null
  fi
done < zomboid/servertest.ini
sudo grep -E '^(MaxPlayers|PVP|Public|Open|BackupsOnStart|Mods|WorkshopItems|RCONPort)=' "$INI"
```
Attendu : `MaxPlayers=8`, `PVP=false`, `Public=false`, `Open=false`, `BackupsOnStart=false`, `Mods=`, `WorkshopItems=`, `RCONPort=27015`.

Renseigner ensuite `Password=` et `RCONPassword=` depuis le gestionnaire de fichiers du panel (Files > `.cache/Server/servertest.ini`). Ces valeurs ne vont jamais dans git.

- [ ] **Step 6 : Capturer le preset Apocalypse**

```bash
sudo cat /var/lib/pelican/volumes/"$UUID"/.cache/Server/servertest_SandboxVars.lua > zomboid/servertest_SandboxVars.lua
head -5 zomboid/servertest_SandboxVars.lua
grep -c '=' zomboid/servertest_SandboxVars.lua
```
Attendu : le fichier commence par `SandboxVars = {` et contient plusieurs dizaines de clés. Ajouter en première ligne un commentaire Lua :
```lua
-- Preset Apocalypse (défaut serveur dédié B42), capturé sans modification le 2026-09-06.
```

- [ ] **Step 7 : Redémarrer, vérifier, se connecter**

Panel : Start. Attendu dans la console : `SERVER STARTED`, aucune ligne `Mods=` en erreur.

```bash
sudo ss -lunp | grep -E '1626[12]'
```
Attendu : deux sockets UDP écoutés sur 16261 et 16262.

Depuis le client Steam sur Windows (Build 42 stable) : Rejoindre > Favoris > IP `127.0.0.1`, port `16261`, mot de passe serveur. Attendu : connexion et apparition en jeu. Si le client ne trouve pas le serveur, essayer l'IP WSL (`ip -4 addr show eth0`) à la place de 127.0.0.1.

Créer le compte admin en jeu, via la console du panel :
```
grantadmin "admin"
```

- [ ] **Step 8 : Documenter dans `docs/LOCAL.md` sections 4 et 5**

Titres : `## 4. Créer le serveur Zomboid` (valeurs exactes de l'étape 2, UUID, JVM), `## 5. Injecter la configuration et se connecter` (boucle de fusion de l'étape 5, mots de passe via le panel, capture SandboxVars, test client).

- [ ] **Step 9 : Commit**

```bash
git add zomboid/servertest.ini zomboid/servertest_SandboxVars.lua docs/LOCAL.md
git commit -m "feat: configuration serveur Zomboid vanilla Apocalypse et procédure de premier lancement"
```

---

### Task 5 : `scripts/pzpath.sh` — résolution du dossier serveur

**Files:**
- Create: `scripts/pzpath.sh`, `tests/pzpath.bats`

**Interfaces:**
- Produces: fonction shell `pz_server_dir` (à sourcer). Affiche sur stdout le chemin du dossier `.cache` du serveur ; code retour 1 avec message sur stderr si introuvable ou ambigu. Variables lues : `PZ_SERVER_DIR` (surcharge directe), `PELICAN_VOLUMES` (défaut `/var/lib/pelican/volumes`).
- Produces: fonction `pz_ini_path` : `"$(pz_server_dir)/Server/${PZ_SERVER_NAME:-servertest}.ini"`.
- Produces: fonction `pz_workshop_dir` : `"$(pz_server_dir)/steamapps/workshop/content/108600"`.

- [ ] **Step 1 : Écrire les tests `tests/pzpath.bats`**

```bash
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
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

```bash
bats tests/pzpath.bats
```
Attendu : échecs `No such file or directory` sur le `source`.

- [ ] **Step 3 : Écrire `scripts/pzpath.sh`**

```bash
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
```

- [ ] **Step 4 : Lancer les tests**

```bash
scripts/test.sh
```
Attendu : shellcheck silencieux, tous les tests passent (`8 tests, 0 failures` avec le smoke).

- [ ] **Step 5 : Commit**

```bash
git add scripts/pzpath.sh tests/pzpath.bats
git commit -m "feat: pzpath.sh — résolution du dossier serveur Zomboid"
```

---

### Task 6 : `scripts/mods.sh` — gestion des mods par ID Workshop

**Files:**
- Create: `scripts/mods.sh`, `tests/mods.bats`

**Interfaces:**
- Consumes: `pz_ini_path`, `pz_workshop_dir` de `scripts/pzpath.sh`.
- Produces: CLI `scripts/mods.sh add <id> | remove <id> | list`. Codes retour : 0 succès, 2 usage/ID invalide, 1 erreur fichier. Écriture atomique du `.ini`.
- Comportement `add` : ajoute l'ID à `WorkshopItems=` s'il est absent ; cherche `mod.info` sous `<workshop>/<id>/mods/` (profondeur ≤ 4, couvre `mods/<Nom>/mod.info` et `mods/<Nom>/42/mod.info`) ; pour chaque ligne `id=` trouvée, ajoute la valeur à `Mods=`. Si aucun `mod.info` : message « redémarre le serveur pour télécharger le mod, puis relance add ».
- Comportement `remove` : retire l'ID de `WorkshopItems=` ; retire de `Mods=` les IDs résolus via `mod.info` ; si non résolus, avertit et affiche `Mods=` courant.

- [ ] **Step 1 : Écrire `tests/mods.bats`**

```bash
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
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

```bash
bats tests/mods.bats
```
Attendu : tous en échec (`mods.sh: No such file`).

- [ ] **Step 3 : Écrire `scripts/mods.sh`**

```bash
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
```

- [ ] **Step 4 : Rendre exécutable et lancer les tests**

```bash
chmod +x scripts/mods.sh && scripts/test.sh
```
Attendu : shellcheck silencieux, `21 tests, 0 failures`. Si shellcheck signale `SC1091` sur le `source`, la directive `# shellcheck source=pzpath.sh` doit être présente juste au-dessus.

- [ ] **Step 5 : Test réel sur le serveur (mod B42 connu)**

Choisir un mod marqué Build 42 sur le Workshop (par exemple un mod de la collection « Build 42 Server Mods », `https://steamcommunity.com/sharedfiles/filedetails/?id=3625770866`). Noter son ID numérique `<id>`.

```bash
sudo -E scripts/mods.sh add <id>
```
Attendu : « redémarre le serveur ». Redémarrer via le panel, attendre `SERVER STARTED`, puis :

```bash
sudo -E scripts/mods.sh add <id>
sudo -E scripts/mods.sh list
```
Attendu : `Mods=<ModID>` rempli. Redémarrer encore ; la console du panel doit lister le mod au chargement (ligne `Mod loaded:` ou équivalent). Puis :

```bash
sudo -E scripts/mods.sh remove <id>
sudo -E scripts/mods.sh list
```
Attendu : `Mods=` et `WorkshopItems=` vides. Redémarrer pour revenir au vanilla.

- [ ] **Step 6 : Commit**

```bash
git add scripts/mods.sh tests/mods.bats
git commit -m "feat: mods.sh — ajout/retrait de mods Workshop dans servertest.ini"
```

---

### Task 7 : `scripts/backup.sh` et `scripts/restore.sh`

**Files:**
- Create: `scripts/backup.sh`, `scripts/restore.sh`, `tests/backup.bats`

**Interfaces:**
- Consumes: `pz_server_dir` de `scripts/pzpath.sh` (le volume à archiver est son parent, `/var/lib/pelican/volumes/<uuid>`).
- Produces: `scripts/backup.sh` crée `BACKUP_DIR/zomboid-<YYYYmmdd-HHMMSS>.tar.gz` contenant `meta.env` (UUID, date), `volume/` (copie du volume Wings) et `panel.tar` (export du volume Docker `pelican-data`). Garde les `KEEP` (défaut 7) plus récentes. Variables : `BACKUP_DIR` (défaut `./backups`), `KEEP`, `SKIP_PANEL=1` (n'exporte pas `pelican-data`, utilisé par les tests), `SKIP_RUNNING_CHECK=1`.
- Produces: `scripts/restore.sh <archive>` restaure `volume/` dans `PELICAN_VOLUMES/<uuid>` et `panel.tar` dans `pelican-data`. Refuse si le conteneur du serveur tourne.

- [ ] **Step 1 : Écrire `tests/backup.bats`**

```bash
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
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

```bash
bats tests/backup.bats
```
Attendu : tous en échec.

- [ ] **Step 3 : Écrire `scripts/backup.sh`**

```bash
#!/usr/bin/env bash
# Sauvegarde complète : volume Wings du serveur Zomboid + volume Docker pelican-data.
#   BACKUP_DIR          dossier de sortie (défaut ./backups)
#   KEEP                nombre d'archives conservées (défaut 7)
#   SKIP_PANEL=1        n'exporte pas pelican-data (tests)
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
tar czf "$archive" -C "$staging" .
echo "Sauvegarde : $archive ($(du -h "$archive" | cut -f1))"

# rotation
ls -1t "$BACKUP_DIR"/zomboid-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
  rm -f -- "$old"
  echo "Supprimé : $old"
done
```

- [ ] **Step 4 : Écrire `scripts/restore.sh`**

```bash
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
```

- [ ] **Step 5 : Rendre exécutables, lancer les tests**

```bash
chmod +x scripts/backup.sh scripts/restore.sh && scripts/test.sh
```
Attendu : `27 tests, 0 failures`, shellcheck silencieux.

- [ ] **Step 6 : Test réel de bout en bout**

Serveur arrêté dans le panel. Puis :

```bash
sudo -E scripts/backup.sh
ls -la backups/
tar tzf backups/zomboid-*.tar.gz | head
```
Attendu : archive de plusieurs Go (installation SteamCMD incluse), contenant `meta.env`, `panel.tar`, `volume/`.

Test de restauration sur le même hôte : renommer le volume, restaurer, vérifier.
```bash
UUID=$(sudo ls /var/lib/pelican/volumes/ | head -1)
sudo mv /var/lib/pelican/volumes/"$UUID" /tmp/pelican-volume-avant
docker compose stop panel
sudo -E scripts/restore.sh backups/zomboid-*.tar.gz
docker compose start panel
sudo diff -rq /tmp/pelican-volume-avant /var/lib/pelican/volumes/"$UUID" && echo IDENTIQUE
```
Attendu : `IDENTIQUE`. Démarrer le serveur depuis le panel, `SERVER STARTED`, le monde est intact. Puis `sudo rm -rf /tmp/pelican-volume-avant`.

- [ ] **Step 7 : Commit**

```bash
git add scripts/backup.sh scripts/restore.sh tests/backup.bats
git commit -m "feat: backup.sh / restore.sh — archive complète serveur + panel avec rotation"
```

---

### Task 8 : Planifications du panel (sauvegarde nocturne, redémarrage 5h)

**Files:**
- Modify: `docs/LOCAL.md` (section 6)

**Interfaces:**
- Produces: deux Schedules Pelican sur le serveur `zomboid`.

- [ ] **Step 1 : Créer la planification de sauvegarde**

Panel > serveur `zomboid` > Schedules > New : nom `Sauvegarde nocturne`, cron `0 4 * * *`. Tâche 1 : action **Backup**, ignored files vide. Onglet Backups du serveur : limite de sauvegardes fixée à `7` (Admin > Servers > zomboid > Backup limit).

- [ ] **Step 2 : Créer la planification de redémarrage**

Schedules > New : nom `Redémarrage quotidien`, cron `55 4 * * *`. Tâches dans l'ordre :
1. **Send command** : `servermsg "Redemarrage du serveur dans 5 minutes"`
2. **Send command** : `servermsg "Redemarrage dans 1 minute, mettez-vous a l'abri"`, délai `240` s
3. **Send command** : `save`, délai `50` s
4. **Send power action** : `restart`, délai `10` s

- [ ] **Step 3 : Tester manuellement**

Serveur démarré. Sur `Redémarrage quotidien`, cliquer « Run now ». Attendu : le message apparaît dans la console (et en jeu si connecté), puis après ~5 minutes le serveur redémarre et affiche `SERVER STARTED`. Sur `Sauvegarde nocturne`, « Run now » : une sauvegarde apparaît dans l'onglet Backups avec un statut réussi.

- [ ] **Step 4 : Documenter dans `docs/LOCAL.md` section 6**

Titre `## 6. Planifications`. Reprendre les valeurs exactes des étapes 1 et 2, et le test « Run now ».

- [ ] **Step 5 : Commit**

```bash
git add docs/LOCAL.md
git commit -m "docs: planifications sauvegarde nocturne et redémarrage quotidien"
```

---

### Task 9 : `docs/OVH.md` et `docs/MODS.md`

**Files:**
- Create: `docs/OVH.md`, `docs/MODS.md`
- Modify: `README.md` (si liens à ajuster)

**Interfaces:**
- Consumes: `scripts/backup.sh`, `scripts/restore.sh`, `scripts/mods.sh` tels que définis en tâches 6 et 7.

- [ ] **Step 1 : Écrire `docs/OVH.md`**

```markdown
# Déploiement sur VPS OVH

Cible : VPS OVH, Ubuntu 24.04, 8 Go RAM minimum (12 Go conseillés si mods), 80 Go disque.
Un nom de domaine pointant sur l'IP du VPS (enregistrement A), par exemple `zomboid.mondomaine.fr`.

## 1. Préparer le VPS

```bash
sudo apt-get update && sudo apt-get install -y git ufw
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER" && newgrp docker
docker compose version
```

## 2. Pare-feu

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw allow 2022/tcp
sudo ufw allow 16261/udp
sudo ufw allow 16262/udp
sudo ufw enable
sudo ufw status
```
Ne jamais ouvrir 8080 (API Wings, joint en interne) ni 27015 (RCON).
Note : Docker contourne ufw pour les ports publiés par les conteneurs. Les ports ci-dessus sont ceux réellement exposés par le compose et par Wings ; ne publie rien d'autre.

## 3. Déployer

```bash
git clone <url-du-depot> ~/ProjectZomboid && cd ~/ProjectZomboid
cp .env.example .env
```
Éditer `.env` : `APP_URL=https://zomboid.mondomaine.fr`, `ADMIN_EMAIL=<ton email>`.
Dans `compose.yml`, ajouter au service `wings` le volume `- "/etc/letsencrypt/:/etc/letsencrypt/"` si Wings doit servir en SSL.

```bash
sudo mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican /tmp/pelican
docker compose up -d panel
```
Ouvrir `https://zomboid.mondomaine.fr/installer` et suivre `docs/LOCAL.md` section 2. Le certificat Let's Encrypt est demandé automatiquement par le conteneur panel (port 80 et 443 doivent être joignables depuis Internet pendant cette étape : ouvrir temporairement 80/tcp puis le refermer).

## 4. Nœud Wings en SSL

Le panel est en https, donc Wings doit l'être aussi. Créer le nœud avec FQDN `zomboid.mondomaine.fr`, SSL **Oui**, port 8080. Copier la configuration dans `/etc/pelican/config.yml`, puis suivre la page « SSL Certificates » de la documentation Pelican (pelican.dev/docs, section Guides) pour fournir le certificat à Wings (montage `/etc/letsencrypt`, clés `api.ssl.cert` et `api.ssl.key` dans `config.yml`). `docker compose up -d wings`. Nœud vert dans le panel.

Importer l'egg (LOCAL.md section 3), créer le serveur (LOCAL.md section 4) **sans le démarrer**.

## 5. Restaurer le monde local

Copier la dernière archive depuis WSL :
```bash
scp backups/zomboid-<date>.tar.gz user@vps:~/ProjectZomboid/backups/
```
Sur le VPS, serveur arrêté :
```bash
docker compose stop panel
sudo -E scripts/restore.sh backups/zomboid-<date>.tar.gz
docker compose start panel
```
Attention : `panel.tar` restaure aussi la base du panel (comptes, nœud `local`, serveur). Après restauration, dans Admin > Nodes, corriger le FQDN du nœud en `zomboid.mondomaine.fr` avec SSL, régénérer la configuration Wings et la recopier dans `/etc/pelican/config.yml`, puis `docker compose restart wings`. Vérifier que l'UUID du serveur correspond au dossier restauré sous `/var/lib/pelican/volumes/`.

Alternative plus simple si le panel a été installé proprement à l'étape 3 : restaurer seulement le volume avec `SKIP_PANEL=1 sudo -E scripts/restore.sh <archive>`, puis dans le panel, créer le serveur en réutilisant l'UUID (champ UUID à la création) ou copier le contenu du volume restauré dans celui du nouveau serveur.

## 6. Vérifier

- Démarrer le serveur : `SERVER STARTED`.
- Un joueur se connecte depuis l'extérieur sur `zomboid.mondomaine.fr:16261` avec le mot de passe.
- Les planifications (LOCAL.md section 6) existent ; sinon les recréer.
- `free -h` pendant le jeu : la mémoire disponible reste > 500 Mo. Sinon, passer le VPS à 12 Go ou baisser `-Xmx` à 5g.
```

- [ ] **Step 2 : Écrire `docs/MODS.md`**

```markdown
# Ajouter des mods (Build 42)

## Choisir un mod compatible
- Sur la page Workshop, la section « Build » ou les tags doivent mentionner **Build 42** (ou 42.x). Un mod « B41 » seul ne charge pas.
- Lire les commentaires récents : « ne marche plus depuis 42.20 » est un signal.
- Commencer par des mods de confort (UI, tri d'inventaire) avant les mods qui ajoutent des objets ou des cartes, qui changent l'équilibre vanilla.
- Un mod qui modifie la carte ou les recettes ne se retire pas proprement d'un monde existant.

## Ajouter
1. Noter l'ID Workshop (chiffres à la fin de l'URL `?id=...`).
2. `sudo -E scripts/mods.sh add <id>` : l'ID est ajouté à `WorkshopItems=`.
3. Redémarrer le serveur depuis le panel : il télécharge l'item.
4. `sudo -E scripts/mods.sh add <id>` une seconde fois : le script lit `mod.info` et remplit `Mods=`.
5. Redémarrer. Vérifier dans la console que le mod est chargé.
6. Les joueurs : le client Steam télécharge le mod automatiquement à la connexion (l'abonnement Workshop se fait tout seul si « Mods du serveur » est accepté).

## Retirer
`sudo -E scripts/mods.sh remove <id>` puis redémarrage.

## Voir l'état
`sudo -E scripts/mods.sh list`

## Ordre de chargement
`Mods=` est chargé dans l'ordre d'écriture. Si un mod dépend d'un autre (indiqué sur sa page Workshop), ajouter la dépendance d'abord.

## Sauvegarde avant tout changement
`sudo -E scripts/backup.sh` (serveur arrêté).
```

- [ ] **Step 3 : Vérifier les liens du README**

```bash
grep -o 'docs/[A-Za-z/._-]*' README.md | while read -r f; do [ -f "$f" ] && echo "OK $f" || echo "MANQUE $f"; done
```
Attendu : que des `OK`.

- [ ] **Step 4 : Commit**

```bash
git add docs/OVH.md docs/MODS.md README.md
git commit -m "docs: migration OVH et guide des mods B42"
```

---

### Task 10 : Vérification finale

**Files:** aucun nouveau.

- [ ] **Step 1 : Suite de tests complète**

```bash
scripts/test.sh
```
Attendu : shellcheck silencieux, `27 tests, 0 failures`.

- [ ] **Step 2 : Parcours de validation de la spec (section 9)**

Cocher chaque point, avec la preuve (commande + sortie ou capture) :
1. `docker compose ps` : `panel` et `wings` en `running` ; `curl -s -o /dev/null -w '%{http_code}' http://localhost` → `200`.
2. Panel > Nodes : `local` vert. Panel > Eggs : Project Zomboid présent.
3. Serveur `zomboid` : `SERVER STARTED` ; connexion client réussie.
4. Tâche 6 étape 5 exécutée avec succès (mod chargé puis retiré).
5. `scripts/mods.sh remove` a laissé `Mods=` et `WorkshopItems=` vides.
6. Tâche 7 étape 6 : `IDENTIQUE`.
7. `scripts/test.sh` vert.

- [ ] **Step 3 : Arbre git propre**

```bash
git status --short
git log --oneline
```
Attendu : aucun fichier non suivi hormis `.env`, `backups/`, `wings/config.yml` (ignorés). Historique de 9 commits environ après la spec.
