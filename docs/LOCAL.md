# Premier lancement en local (WSL Ubuntu)

Toutes les commandes se lancent dans un terminal Ubuntu (WSL), depuis `~/ProjectZomboid`.
Les commandes marquées `# root` se lancent avec `sudo`, ou depuis Windows avec `wsl -d Ubuntu -u root`.

## 1. Prérequis et démarrage du panel

- Docker CE natif dans la distro Ubuntu (`docker info` doit afficher `Operating System: Ubuntu`).
- Les ports 80 et 443 sont souvent occupés par un autre projet : le panel utilise donc 8081/8443 en local.
- Dossiers hôte pour Wings (une fois) :

```bash
mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican /tmp/pelican   # root
```

- Configuration et démarrage du panel :

```bash
cp .env.example .env          # APP_URL=http://localhost:8081, BEHIND_PROXY=true
docker compose config --quiet && docker compose up -d panel
docker compose logs panel | grep 'Generated app key'
```

Note la ligne « Generated app key » : c'est la clé de chiffrement de la base du panel. Sans elle, une base restaurée ailleurs est illisible.

Pourquoi `BEHIND_PROXY=true` en local : le Caddy du conteneur ne sert sinon que le nom d'hôte de `APP_URL` (`localhost:8081`) et renvoie une page vide à tout autre nom, y compris `panel`, que Wings utilise pour joindre le panel. En mode proxy, Caddy sert tout nom d'hôte sur le port 80 interne, mappé sur 8081.

Le premier démarrage applique les migrations : compte environ une minute, puis vérifie :

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/installer   # 200 attendu
```

## 2. Installeur

Ouvre `http://localhost:8081/installer` dans le navigateur Windows.

- Base de données : **SQLite**, chemin `/pelican-data/database/database.sqlite` (chemin absolu sur le volume ; le défaut `database.sqlite` fonctionne aussi car le conteneur le lie au volume)
- Cache : **filesystem**
- Session : **filesystem**
- Queue : **database**
- Compte admin : ton email, un mot de passe fort.

À la fin, tu es connecté au panel.

## 3. Nœud Wings et egg

### Créer le nœud (ligne de commande)

Le FQDN du nœud doit être joignable par ton navigateur Windows **et** par le conteneur panel : c'est l'IP WSL (`ip -4 addr show eth0`). `localhost` ne convient pas (dans le conteneur panel, c'est le conteneur lui-même).

```bash
FQDN=$(ip -4 addr show eth0 | awk '/inet /{print $2}' | cut -d/ -f1)
docker compose exec -T panel php artisan p:node:make -n \
  --name=local --description="WSL local" --fqdn="$FQDN" --public=1 --scheme=http --proxy=0 --maintenance=0 \
  --maxMemory=7168 --overallocateMemory=0 --maxDisk=40000 --overallocateDisk=0 --maxCpu=0 --overallocateCpu=0 \
  --uploadSize=256 --daemonListeningPort=8080 --daemonConnectingPort=8080 --daemonSFTPPort=2022 \
  --daemonBase=/var/lib/pelican/volumes
docker compose exec -T panel php artisan p:node:list
```

L'IP WSL peut changer après un redémarrage de Windows. Si le nœud passe au rouge, mets à jour le FQDN dans Admin > Nodes > local.

### Installer la config Wings

```bash
docker compose exec -T panel php artisan p:node:configuration 1 -n > /etc/pelican/config.yml   # root
sed -i -E "s|^(\s*remote:).*|\1 'http://panel'|" /etc/pelican/config.yml                      # root
grep -E '^\s*remote:' /etc/pelican/config.yml
```

La ligne `remote:` doit valoir `http://panel` (nom du service compose, port 80 interne).

```bash
docker compose up -d wings
sleep 8 && docker compose logs wings | tail -20
curl -s http://localhost:8080 ; echo
```

Attendu : logs `sftp server listening`, `configuring internal webserver`, sans `FATAL`. Le curl renvoie un JSON d'erreur d'autorisation (Wings répond, il refuse juste une requête sans jeton).

Dans le panel, la page Nodes affiche `local` avec une pastille verte. Si rouge : vérifier le FQDN et `docker compose logs wings`.

### Allocations de ports

Le serveur Zomboid a besoin des allocations `0.0.0.0:16261` et `0.0.0.0:16262` sur le nœud :

```bash
docker compose exec -T panel php artisan tinker --execute='
foreach ([16261, 16262] as $p) { App\Models\Allocation::firstOrCreate(["node_id" => 1, "ip" => "0.0.0.0", "port" => $p]); }'
```

(ou Admin > Nodes > local > Allocations dans le panel).

### Importer l'egg

Panel > Admin > Eggs > Import, onglet URL :

```
https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/project_zomboid/egg-project-zomboid.json
```

L'egg « Project Zomboid » apparaît, image `ghcr.io/parkervcp/steamcmd:debian`.

## 4. Créer le serveur Zomboid

Soit dans le panel (Admin > Servers > Create), soit en ligne de commande. Valeurs :

| Champ | Valeur |
|---|---|
| Name | `zomboid` |
| Owner | ton compte (id 1) |
| Egg | Project Zomboid |
| Allocation principale | `0.0.0.0:16261`, supplémentaire `0.0.0.0:16262` |
| Memory | `7168` MiB, Disk `30000` MiB, CPU `0` (illimité) |
| `SERVER_NAME` | `servertest` (donne `servertest.ini`) |
| `ADMIN_USER` / `ADMIN_PASSWORD` | `admin` / mot de passe fort (≤ 32 caractères) |
| `STEAM_PORT` | `16262` |
| `MAX_PLAYERS` | `8` |
| `SRCDS_BETAID` | vide (Build 42 stable) |
| `AUTO_UPDATE` | `1` |

En ligne de commande (remplacer le mot de passe) :

```bash
docker compose exec -T -e PW='MotDePasseAdmin' panel php artisan tinker --execute='
$egg = App\Models\Egg::find(1);
$startup = array_values($egg->startup_commands)[0];
$s = app(App\Services\Servers\ServerCreationService::class)->handle([
  "name" => "zomboid", "description" => "Project Zomboid B42 vanilla, 8 joueurs",
  "owner_id" => 1, "egg_id" => 1, "node_id" => 1, "allocation_id" => 1, "allocation_additional" => [2],
  "memory" => 7168, "swap" => 0, "disk" => 30000, "io" => 500, "cpu" => 0, "threads" => null, "oom_killer" => false,
  "startup" => $startup, "image" => "ghcr.io/parkervcp/steamcmd:debian",
  "environment" => ["SERVER_NAME" => "servertest", "ADMIN_USER" => "admin", "ADMIN_PASSWORD" => getenv("PW"),
    "STEAM_PORT" => "16262", "MAX_PLAYERS" => "8", "SRCDS_APPID" => "380870", "SRCDS_BETAID" => "", "AUTO_UPDATE" => "1"],
  "skip_scripts" => false, "start_on_completion" => false,
]);
echo $s->uuid, "\n";'
```

L'installation SteamCMD (~7 Go) prend quelques minutes. Suivre dans la console du panel ou avec `docker compose logs -f wings`. Le volume du serveur est `/var/lib/pelican/volumes/<uuid>/`.

Mémoire JVM (le binaire lit `ProjectZomboid64.json`, défaut `-Xmx8g`) :

```bash
V=/var/lib/pelican/volumes/<uuid>
sed -i -E 's/"-Xmx[0-9]+[mMgG]"/"-Xmx6g"/' $V/ProjectZomboid64.json   # root
```

## 5. Injecter la configuration et se connecter

1. Démarrer le serveur dans le panel, attendre `SERVER STARTED` (génère `.cache/Server/servertest.ini` et `servertest_SandboxVars.lua`), puis l'arrêter.
2. Fusionner les surcharges du dépôt (le fichier généré est complet, on remplace seulement nos clés) :

```bash
INI=$V/.cache/Server/servertest.ini                                     # root pour la suite
cp "$INI" "$INI.bak"
while IFS='=' read -r key val; do
  case "$key" in ''|'#'*) continue;; esac
  if grep -q "^$key=" "$INI"; then sed -i "s|^$key=.*|$key=$val|" "$INI"; else echo "$key=$val" >> "$INI"; fi
done < zomboid/servertest.ini
chown 988:988 "$INI"
grep -E '^(MaxPlayers|PVP|Public|Open|BackupsOnStart|Mods|WorkshopItems|RCONPort)=' "$INI"
```

3. Renseigner `Password=` (mot de passe des joueurs) et `RCONPassword=` dans ce même fichier, ou depuis le panel (Files > `.cache/Server/servertest.ini`). Jamais dans git.
4. Capturer le preset Apocalypse dans le dépôt (déjà fait, à refaire après une mise à jour du jeu) :

```bash
cat $V/.cache/Server/servertest_SandboxVars.lua > zomboid/servertest_SandboxVars.lua
```

5. Redémarrer, attendre `SERVER STARTED`. Les lignes `ERROR ... IsoMetaGrid.load` ou `Mannequin zone` sont des avertissements connus des données de carte, sans effet.
6. Depuis le client Steam (Build 42 stable) sur Windows : Rejoindre > Favoris > IP `127.0.0.1`, port `16261`, mot de passe serveur `Password=`. Si le client ne trouve pas le serveur, utiliser l'IP WSL à la place.
7. Dans la console du panel, donner les droits admin à ton personnage : `grantadmin "TonPseudo"`.

## 6. Planifications

Deux planifications sur le serveur `zomboid` (panel > serveur > Schedules), limite de sauvegardes du serveur fixée à 7 (Admin > Servers > zomboid > Backup limit) :

| Nom | Cron | Tâches |
|---|---|---|
| Sauvegarde nocturne | `0 4 * * *` | 1. Backup |
| Redémarrage quotidien | `55 4 * * *` | 1. Send command `servermsg "Redemarrage du serveur dans 5 minutes"` ; 2. Send command `servermsg "Redemarrage dans 1 minute, mettez-vous a l abri"` (délai 240 s) ; 3. Send command `save` (délai 50 s) ; 4. Power `restart` (délai 10 s) |

En ligne de commande, le script équivalent est celui-ci (idempotent) :

```bash
docker compose exec -T panel php artisan tinker --execute='
$server = App\Models\Server::find(1); $server->update(["backup_limit" => 7]);
function mk($server, $name, $h, $m, $tasks) {
  $s = App\Models\Schedule::firstOrCreate(["server_id" => $server->id, "name" => $name],
    ["cron_day_of_week" => "*", "cron_month" => "*", "cron_day_of_month" => "*", "cron_hour" => $h, "cron_minute" => $m, "is_active" => true, "only_when_online" => false]);
  if ($s->tasks()->count() === 0) { $i = 1; foreach ($tasks as [$a, $p, $o]) App\Models\Task::create(["schedule_id" => $s->id, "sequence_id" => $i++, "action" => $a, "payload" => $p, "time_offset" => $o, "continue_on_failure" => false]); }
  $s->next_run_at = App\Helpers\Utilities::getScheduleNextRunDate($m, $h, "*", "*", "*"); $s->save();
}
mk($server, "Sauvegarde nocturne", "4", "0", [["backup", "", 0]]);
mk($server, "Redémarrage quotidien", "4", "55", [["command", "servermsg \"Redemarrage du serveur dans 5 minutes\"", 0], ["command", "servermsg \"Redemarrage dans 1 minute, mettez-vous a l abri\"", 240], ["command", "save", 50], ["power", "restart", 10]]);'
```

Test : sur chaque planification, « Run now » dans le panel. La sauvegarde apparaît dans l'onglet Backups (réussie, ~2,6 Go pour un monde neuf). Le redémarrage affiche les messages dans la console puis relance le serveur après 5 minutes.
