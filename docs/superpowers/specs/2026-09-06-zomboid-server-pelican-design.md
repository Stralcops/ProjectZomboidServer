# Serveur Project Zomboid Build 42 avec panel Pelican — Design

Date : 2026-09-06
Statut : validé en brainstorming, en attente de relecture avant plan d'implémentation.

## 1. Objectif

Héberger un serveur dédié Project Zomboid **Build 42 stable** (42.20.x, stable depuis le
29 juillet 2026) pour un petit groupe d'amis (2 à 8 joueurs, sur invitation), avec :

- un panel d'administration web (Pelican Panel) pour start/stop, console, fichiers,
  sauvegardes planifiées, redémarrages planifiés ;
- un moyen simple d'ajouter ou retirer des mods Steam Workshop par leur ID ;
- une configuration de jeu **Apocalypse vanilla**, PVE, coopération ;
- un déploiement identique en local (WSL2 Ubuntu 24.04, test uniquement) puis sur un
  **VPS OVH Linux ~8 Go RAM** (jeu réel).

Hors périmètre : exposition du serveur local à Internet, bot Discord, multi-jeux,
sélection de mods (on démarre vanilla, le pipeline d'ajout est fourni).

## 2. Décisions

| Sujet | Décision | Raison |
|---|---|---|
| Panel | Pelican (successeur de Pterodactyl, même mainteneur, mêmes eggs) | Projet actif, UI moderne, Pterodactyl en maintenance |
| Base de données du panel | SQLite intégrée | Un conteneur de moins, suffisant pour un usage mono-admin |
| Orchestration | Un `compose.yml` unique (panel + wings), identique local/OVH | Portabilité, un seul `.env` à adapter |
| Serveur Zomboid | Conteneur créé par Wings à partir de l'egg officiel `pelican-eggs/games-steamcmd/project_zomboid` | Egg maintenu, installe l'app Steam 380870 branche par défaut (B42 stable) |
| Mods | Édition de `Mods=` / `WorkshopItems=` dans `servertest.ini` via script | L'egg n'expose pas de variable mods ; le script évite les erreurs de saisie |
| Réglages de jeu | Preset Apocalypse sans modification, PVP off | Choix de l'utilisateur : "le vrai jeu" |

## 3. Architecture

Trois conteneurs sur un même hôte Docker :

```
[navigateur] --80/443--> [panel: Pelican + SQLite]
                              |  API (8080, réseau interne)
                              v
                         [wings] --docker.sock--> crée/gère --> [zomboid]
                                                                 UDP 16261, 16262
                                                                 TCP 27015 (RCON, interne)
```

- **panel** : image `ghcr.io/pelican-dev/panel`. Volume `pelican-data` (SQLite, plugins,
  config). Ports 80 (local) et 443 (OVH, Let's Encrypt via `LE_EMAIL`).
- **wings** : image `ghcr.io/pelican-dev/wings`. Monte `/var/run/docker.sock`,
  `/var/lib/pelican` (données des serveurs), `/etc/pelican` (config.yml), `/tmp/pelican`.
  Ports 8080 (API) et 2022 (SFTP). Sur OVH, 8080 n'est pas exposé publiquement : le panel
  joint Wings par le réseau Docker interne.
- **zomboid** : géré par Wings, pas décrit dans le compose. Image SteamCMD de l'egg.
  Mémoire allouée 6 Go (`-Xmx6g`), 8 slots.

Résolution d'adresses : le panel joint Wings via un alias réseau Docker (`wings`) déclaré
dans le compose ; le nœud est enregistré dans le panel avec ce nom. Le navigateur Windows
atteint le panel sur `http://localhost` grâce au forwarding WSL2.

## 4. Structure du dépôt

```
ProjectZomboid/
├── compose.yml                # services panel + wings, volumes, réseau
├── .env.example               # APP_URL, LE_EMAIL, TZ
├── wings/config.yml.example   # gabarit, rempli après création du nœud dans le panel
├── zomboid/
│   ├── servertest.ini         # 8 joueurs, mot de passe, PVP=false, Mods=, WorkshopItems=
│   └── SandboxVars.lua        # preset Apocalypse, valeurs par défaut explicitées
├── scripts/
│   ├── mods.sh                # add <id> | remove <id> | list
│   ├── backup.sh              # archive volume zomboid + pelican-data
│   └── restore.sh             # restaure une archive de backup.sh
└── docs/
    ├── LOCAL.md               # premier lancement pas à pas
    ├── OVH.md                 # migration et checklist réseau
    └── MODS.md                # choisir un mod compatible B42
```

## 5. Composants

### 5.1 compose.yml et .env
- Variables : `APP_URL` (http://localhost en local, https://<domaine> sur OVH), `LE_EMAIL`,
  `TZ=Europe/Paris`.
- `restart: unless-stopped` sur panel et wings.
- Un seul réseau bridge avec sous-réseau fixe pour que Wings sache quelle plage attribuer
  aux serveurs.

### 5.2 Fichiers de configuration Zomboid
- `servertest.ini` : `MaxPlayers=8`, `Password=` (renseigné par l'admin), `PVP=false`,
  `SafetySystem=false`, `Public=false`, `Open=false` (whitelist active : les comptes sont
  créés via la console admin), `Mods=`, `WorkshopItems=`, `RCONPort=27015`,
  `BackupsOnStart=false`.
- `SandboxVars.lua` : copie du preset Apocalypse. Aucune valeur modifiée ; le fichier est
  livré pour rendre les réglages lisibles et versionnés.
- Ces fichiers sont copiés dans le volume du serveur après la première installation
  (documenté dans LOCAL.md), puis modifiables depuis le gestionnaire de fichiers du panel.

### 5.3 scripts/mods.sh
- Interface : `mods.sh add <workshop_id>`, `mods.sh remove <workshop_id>`, `mods.sh list`.
- `add` : vérifie que l'ID est numérique, puis résout le **Mod ID interne** en lisant
  `mod.info` dans le dossier Workshop téléchargé par le serveur
  (`steamapps/workshop/content/108600/<id>/mods/*/mod.info`). Si le dossier n'existe pas
  encore, ajoute l'ID à `WorkshopItems=` seul, signale qu'un redémarrage téléchargera le
  mod, et demande de relancer `add` pour compléter `Mods=`.
- Refuse un ID non numérique, ne modifie jamais le fichier en cas d'erreur (écriture
  atomique via fichier temporaire puis `mv`).
- Rappelle qu'un redémarrage est nécessaire après chaque changement.
- Chemin du `servertest.ini` déduit du volume Wings ; surcharge possible par variable
  d'environnement `PZ_SERVER_DIR`.

### 5.4 scripts/backup.sh et restore.sh
- `backup.sh` : archive `/var/lib/pelican/volumes/<uuid>` et le volume `pelican-data`
  dans `backups/<date>.tar.gz`. Avertit si le serveur Zomboid tourne (sauvegarde
  incohérente possible) et propose de l'arrêter d'abord depuis le panel. Conserve les
  7 dernières archives.
- `restore.sh <archive>` : restaure les deux volumes sur un compose arrêté.
- Les sauvegardes planifiées internes du panel (quotidiennes, rotation 7) restent actives
  en complément.

## 6. Flux de données

1. L'admin se connecte au panel, démarre le serveur ; Wings lance le conteneur Zomboid.
2. Les joueurs se connectent en UDP 16261 avec le mot de passe. Le monde est écrit dans
   le volume Wings du serveur.
3. Ajout de mod : `mods.sh add` modifie `servertest.ini` ; redémarrage via le panel ;
   SteamCMD télécharge les items Workshop au démarrage.
4. Sauvegarde : planification du panel chaque nuit ; `backup.sh` à la demande avant toute
   migration ou changement risqué.

## 7. Gestion des erreurs

- Serveur Zomboid crash : Wings le relance (crash detection du panel).
- Redémarrage quotidien planifié à 5h avec annonce en jeu 5 minutes avant, pour limiter
  les fuites mémoire B42.
- Espace disque : `BackupsOnStart=false` (l'egg documente des pannes « No space left on
  device » causées par les sauvegardes internes du jeu au démarrage).
- Mod invalide : `mods.sh` refuse et laisse le fichier intact.
- Mot de passe admin absent : l'egg exige `ADMIN_PASSWORD`, LOCAL.md le rappelle.

## 8. Migration vers OVH

Cible : VPS OVH Ubuntu 24.04, 8 Go RAM, Docker CE.

1. Cloner le dépôt, copier `.env.example` en `.env`, renseigner `APP_URL` et `LE_EMAIL`.
2. `docker compose up -d`, finir l'installation du panel, créer le nœud, copier
   `config.yml` dans `wings/`.
3. `restore.sh <archive>` produite en local.
4. Pare-feu : ouvrir TCP 443 et 2022, UDP 16261 et 16262. Ne pas exposer 8080 ni 27015.
5. Contrôle : un joueur se connecte depuis l'extérieur, le monde est celui du local.

Dimensionnement : `-Xmx6g` pour Zomboid, ~1 Go pour panel + Wings. Passer à 12 Go si les
mods s'accumulent ou au-delà de 8 joueurs.

## 9. Tests de validation (local)

1. `docker compose up -d` : le panel répond sur http://localhost, l'admin se connecte.
2. Le nœud Wings apparaît en ligne, l'egg Project Zomboid est importé.
3. Le serveur Zomboid s'installe, démarre, un client Steam sur le PC Windows se connecte
   avec le mot de passe.
4. `mods.sh add` sur un mod B42 connu, redémarrage, le mod apparaît dans la console.
5. `mods.sh remove` remet le fichier à l'état initial.
6. `backup.sh` puis `restore.sh` sur une seconde instance du compose reproduit le monde.
7. Les scripts ont des tests shell (bats) sur les cas : ID invalide, mod déjà présent,
   mod absent du Workshop local, écriture atomique.

## 10. Risques et points ouverts

- **Egg et B42 stable** : un ticket Pterodactyl (mars 2026) signalait des crashs sur la
  branche unstable, pas sur la stable. À confirmer au premier démarrage ; repli possible
  sur un egg communautaire B42.
- **Wings en conteneur sur WSL2** : Wings a besoin du socket Docker et de chemins
  identiques hôte/conteneur pour `/var/lib/pelican`. Docker est natif dans WSL (pas
  Docker Desktop), ce qui simplifie.
- **Mémoire sur VPS 8 Go** : marge faible. Surveiller au premier mois.
