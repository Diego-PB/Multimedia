# Serveur Multimédia - Infrastructure Docker

## 🚀 Démarrage Rapide

### Première installation (ami / nouveau PC)

1. **Installer Docker Desktop** : [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
2. **Récupérer ce projet** (cloner ou décompresser le zip)
3. **Placer l'archive de configs** `multimedia-config-*.tar.gz` dans le dossier du projet (si fournie)
4. **Lancer le panneau de contrôle** :
   - 🪟 **Windows** : Double-cliquer sur `lancer.bat`
   - 🐧 **Linux / NAS** : `./lancer.sh`
5. Le navigateur s'ouvre sur `http://localhost:3000`
6. **Importer les configs** si une archive est détectée (bandeau bleu en haut)
7. Aller dans **⚙️ Configuration** et remplir :
   - Le **chemin des médias** (ex: `C:/Users/VotreNom/Videos/media`)
   - Les infos **VPN** (fournisseur, clé WireGuard)
8. Cliquer sur **🚀 Tout Démarrer**

### Utilisation quotidienne

- **Ouvrir le panneau** : `http://localhost:3000` (ou relancer `lancer.bat`)
- **Démarrer / Arrêter** l'infrastructure depuis le dashboard
- La configuration est **sauvegardée automatiquement** entre les redémarrages

---

## 📁 Architecture des dossiers

### 1. 🛡️ reseau/ (Sécurité & VPN)
Gère la connexion sécurisée vers l'extérieur. C'est la porte d'entrée obligatoire pour les applications de téléchargement.
* **Gluetun :** Client VPN (configuré avec WireGuard). Il crée un tunnel chiffré et agit comme un bouclier de sécurité (Kill Switch). Il gère également l'ouverture des ports réseau pour les conteneurs qui sont cachés derrière lui (qBittorrent et Prowlarr).

### 2. 📥 recuperation/ (Téléchargement & Automatisation)
L'usine en arrière-plan qui automatise la recherche, le téléchargement, le renommage et le tri des fichiers.
* **qBittorrent :** Le client de téléchargement torrent. Son trafic internet est intégralement forcé dans le tunnel de Gluetun pour masquer l'adresse IP publique.
* **Prowlarr :** Le gestionnaire d'indexeurs. Il cherche les sources de téléchargement sur internet et les synchronise automatiquement avec Radarr et Sonarr. Également sécurisé derrière Gluetun.
* **Radarr :** Le gestionnaire de films. Il reçoit les requêtes, envoie les ordres de téléchargement à qBittorrent, puis déplace et renomme le fichier final dans le bon dossier.
* **Sonarr :** Le gestionnaire de séries. Rôle identique à Radarr, mais adapté à la gestion complexe des saisons et des épisodes.
* **Bazarr :** Le chercheur de sous-titres. Il analyse la bibliothèque en tâche de fond et télécharge automatiquement les sous-titres manquants dans les langues paramétrées.
* **Profilarr :** L'optimiseur de qualité. Il injecte automatiquement des règles strictes (profils TRaSH Guides) dans Radarr et Sonarr pour garantir les meilleures versions possibles (ex: 1080p, 4K, VF/VOSTFR).

### 3. 🍿 diffusion/ (Lecture & Requêtes)
La partie visible et interactive pour les utilisateurs.
* **Jellyfin :** Le serveur multimédia. Il scanne le dossier de médias triés, récupère les affiches/résumés, et permet de visionner le contenu depuis n'importe quel écran (TV, PC, Smartphone).
* **Jellyseerr :** Le portail de requêtes. Interface web intuitive permettant de découvrir les tendances et de demander l'ajout d'un film ou d'une série en un clic. Il transmet directement l'ordre à Radarr ou Sonarr.

### 4. 🎛️ panneau/ (Panneau de Contrôle)
Interface web de gestion. Permet de configurer et piloter toute l'infrastructure depuis un navigateur, sans connaissances Docker.

---

## 🔌 Récapitulatif des Ports Locaux

Pour accéder aux interfaces d'administration depuis votre navigateur (via `http://localhost:PORT` ou l'adresse IP de votre serveur), voici la cartographie des ports attribués :

| Application | Port | Rôle |
|---|---|---|
| **Panneau** | `3000` | Interface de gestion |
| **Jellyfin** | `8096` | Interface principale de visionnage |
| **Sonarr** | `8989` | Administration des séries |
| **Radarr** | `7878` | Administration des films |
| **Jellyseerr** | `5055` | Portail des demandes d'ajouts |
| **Bazarr** | `6767` | Administration des sous-titres |
| **Prowlarr** | `9696` | Routé via le bouclier Gluetun |
| **qBittorrent** | `8080` | Routé via le bouclier Gluetun |

> **Note réseau & sécurité :** Les ports `8080` (qBittorrent) et `9696` (Prowlarr) n'existent pas directement sur leurs conteneurs respectifs. Ils ont été dépouillés de leur accès direct au réseau. C'est le conteneur **Gluetun** qui expose ces ports sur le réseau local et redirige le trafic entrant vers eux à l'intérieur du tunnel VPN.

---

## 📦 Migration / Partage

### Exporter les configs (depuis la machine source)

```bash
./exporter.sh
```

Cela crée une archive `multimedia-config-*.tar.gz` contenant toutes les configurations (clés API, indexeurs, profils qualité, logins...).

### Importer sur une nouvelle machine

1. Placer l'archive `.tar.gz` dans le dossier du projet
2. Lancer le panneau (`lancer.bat` ou `lancer.sh`)
3. Le panneau détecte l'archive et propose l'import
4. Configurer les chemins et le VPN → Démarrer

> **⚠️ Sécurité :** L'archive contient des données sensibles (clés API, config VPN). Transmettez-la de manière sécurisée.
