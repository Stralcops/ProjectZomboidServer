# Premier lancement en local (WSL Ubuntu)

Toutes les commandes se lancent dans un terminal Ubuntu (WSL), depuis `~/ProjectZomboid`.

## 1. Prérequis et démarrage du panel

- Docker CE natif dans la distro Ubuntu (`docker info` doit afficher `Operating System: Ubuntu`).
- Les ports 80 et 443 sont souvent occupés par un autre projet : le panel utilise donc 8081/8443 en local.
- Dossiers hôte pour Wings (une fois) :

```bash
sudo mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican /tmp/pelican
```

- Configuration et démarrage du panel :

```bash
cp .env.example .env          # APP_URL=http://localhost:8081
docker compose config --quiet && docker compose up -d panel
docker compose logs panel | grep 'Generated app key'
```

Note la ligne « Generated app key » : c'est la clé de chiffrement de la base du panel. Sans elle, une base restaurée ailleurs est illisible.

Le premier démarrage applique les migrations : compte environ une minute, puis vérifie :

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/installer   # 200 attendu
```

## 2. Installeur

Ouvre `http://localhost:8081/installer` dans le navigateur Windows.

- Base de données : **SQLite**
- Cache : **filesystem**
- Session : **filesystem**
- Queue : **database**
- Compte admin : ton email, un mot de passe fort.

À la fin, tu es connecté au panel.

## 3. Nœud Wings et egg

### Créer le nœud

Panel > Admin > Nodes > Create :

| Champ | Valeur |
|---|---|
| Name | `local` |
| FQDN | `wings` |
| Communicate over SSL | Non |
| Port | `8080` |
| SFTP port | `2022` |
| Memory | `7168` MiB |
| Disk | `40000` MiB |
| Daemon data | `/var/lib/pelican/volumes` |

`wings` est l'alias réseau du conteneur Wings dans le compose : le panel le joint en interne.

Sauvegarde, puis onglet **Configuration** : copie le bloc YAML.

### Installer la config Wings

```bash
sudo nano /etc/pelican/config.yml     # coller le YAML, Ctrl+O, Entrée, Ctrl+X
sudo grep -E '^\s*remote:' /etc/pelican/config.yml
```

La ligne `remote:` doit valoir `http://panel:8081` (nom du service compose + port de `APP_URL`). Si le panel a généré `http://localhost:8081`, remplace `localhost` par `panel`.

```bash
docker compose up -d wings
sleep 5 && docker compose logs wings | tail -20
curl -s http://localhost:8080 ; echo
```

Attendu : logs sans `error`, et curl renvoie un JSON d'erreur d'autorisation (Wings répond, il refuse juste une requête sans jeton).

Dans le panel, la page Nodes affiche `local` avec une pastille verte. Si rouge : vérifier `remote:` et `docker compose logs wings`.

### Importer l'egg

Panel > Admin > Eggs > Import, URL :

```
https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/project_zomboid/egg-project-zomboid.json
```

L'egg « Project Zomboid » apparaît, image `ghcr.io/parkervcp/steamcmd:debian`.
