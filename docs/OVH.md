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

Éditer `.env` :

```dotenv
APP_URL=https://zomboid.mondomaine.fr
PANEL_HTTP_PORT=80
PANEL_HTTPS_PORT=443
ADMIN_EMAIL=<ton email>
```

Dans `compose.yml`, ajouter au service `wings` le volume `- "/etc/letsencrypt/:/etc/letsencrypt/"` si Wings doit servir en SSL (cas OVH).

```bash
sudo mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican /tmp/pelican
sudo ufw allow 80/tcp        # temporaire, pour Let's Encrypt
docker compose up -d panel
```

Ouvrir `https://zomboid.mondomaine.fr/installer` et suivre `docs/LOCAL.md` section 2. Le certificat Let's Encrypt est demandé automatiquement par Caddy dans le conteneur panel (80 et 443 doivent être joignables depuis Internet à ce moment). Une fois le certificat obtenu : `sudo ufw delete allow 80/tcp`.

## 4. Nœud Wings en SSL

Le panel est en https, donc Wings doit l'être aussi. Créer le nœud avec FQDN `zomboid.mondomaine.fr`, SSL **Oui**, port 8080. Copier la configuration dans `/etc/pelican/config.yml`, puis suivre la page « SSL Certificates » de la documentation Pelican (pelican.dev/docs, section Guides) pour fournir le certificat à Wings (montage `/etc/letsencrypt`, clés `api.ssl.cert` et `api.ssl.key` dans `config.yml`). Vérifier `remote: https://zomboid.mondomaine.fr`. Puis `docker compose up -d wings`. Nœud vert dans le panel.

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

Attention : `panel.tar` restaure aussi la base du panel (comptes, nœud `local`, serveur, clé de chiffrement). Après restauration, dans Admin > Nodes, corriger le FQDN du nœud en `zomboid.mondomaine.fr` avec SSL, régénérer la configuration Wings et la recopier dans `/etc/pelican/config.yml`, puis `docker compose restart wings`. Vérifier que l'UUID du serveur correspond au dossier restauré sous `/var/lib/pelican/volumes/`.

Alternative plus simple si le panel a été installé proprement à l'étape 3 : restaurer seulement le volume avec `SKIP_PANEL=1 sudo -E scripts/restore.sh <archive>`, puis copier le contenu du volume restauré dans celui du nouveau serveur (`sudo cp -a /var/lib/pelican/volumes/<ancien-uuid>/. /var/lib/pelican/volumes/<nouveau-uuid>/`), et régler `ADMIN_PASSWORD` dans le panel.

## 6. Vérifier

- Démarrer le serveur : `SERVER STARTED`.
- Un joueur se connecte depuis l'extérieur sur `zomboid.mondomaine.fr:16261` avec le mot de passe.
- Les planifications (LOCAL.md section 6) existent ; sinon les recréer.
- `free -h` pendant le jeu : la mémoire disponible reste > 500 Mo. Sinon, passer le VPS à 12 Go ou baisser `-Xmx` à 5g.
