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
