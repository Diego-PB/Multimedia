// =============================================================================
// SERVER.JS — Backend du Panneau de Contrôle Multimédia
// =============================================================================

const express = require('express');
const Docker = require('dockerode');
const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const PORT = 3000;

// Chemins
const PROJET_DIR = '/projet';
const DATA_DIR = '/app/data';
const CONFIG_FILE = path.join(DATA_DIR, 'config.json');

// Services gérés et leurs conteneurs
const SERVICES = [
  { id: 'gluetun',      nom: 'Gluetun',      groupe: 'reseau',       icone: '🛡️', port: null,  description: 'VPN / Kill Switch' },
  { id: 'qbittorrent',  nom: 'qBittorrent',  groupe: 'recuperation', icone: '📥', port: 8080,  description: 'Client torrent' },
  { id: 'prowlarr',     nom: 'Prowlarr',     groupe: 'recuperation', icone: '🔍', port: 9696,  description: 'Indexeurs torrent' },
  { id: 'radarr',       nom: 'Radarr',       groupe: 'recuperation', icone: '🎬', port: 7878,  description: 'Gestionnaire films' },
  { id: 'sonarr',       nom: 'Sonarr',       groupe: 'recuperation', icone: '📺', port: 8989,  description: 'Gestionnaire séries' },
  { id: 'bazarr',       nom: 'Bazarr',       groupe: 'recuperation', icone: '💬', port: 6767,  description: 'Sous-titres' },
  { id: 'jellyfin',     nom: 'Jellyfin',     groupe: 'diffusion',    icone: '🍿', port: 8096,  description: 'Serveur médias' },
  { id: 'jellyseerr',   nom: 'Jellyseerr',   groupe: 'diffusion',    icone: '⭐', port: 5055,  description: 'Portail demandes' },
];

// Ordre de démarrage et d'arrêt
const ORDRE_DEMARRAGE = ['reseau', 'recuperation', 'diffusion'];
const ORDRE_ARRET = ['diffusion', 'recuperation', 'reseau'];

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// =============================================================================
// UTILITAIRES
// =============================================================================

/**
 * Charge la config sauvegardée ou retourne la config par défaut
 */
function chargerConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
    }
  } catch (e) {
    console.error('Erreur lecture config:', e.message);
  }

  // Config par défaut
  return {
    PUID: '1000',
    PGID: '1000',
    TZ: 'Europe/Paris',
    CHEMIN_RELATIF_CONFIG: './config',
    CHEMIN_ABSOLU_MEDIA: '',
    VPN_FOURNISSEUR: 'custom',
    VPN_TYPE: 'wireguard',
    VPN_CLE_PRIVEE: '',
    VPN_PAYS: 'Switzerland',
  };
}

/**
 * Sauvegarde la config dans le fichier persistant
 */
function sauvegarderConfig(config) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

/**
 * Génère les 3 fichiers .env à partir de la config sauvegardée
 */
function genererEnvFiles(config) {
  // reseau/.env
  const envReseau = `# Généré automatiquement par le Panneau de Contrôle
PUID=${config.PUID}
PGID=${config.PGID}
TZ=${config.TZ}
CHEMIN_RELATIF_CONFIG=${config.CHEMIN_RELATIF_CONFIG}

# VPN
VPN_FOURNISSEUR=${config.VPN_FOURNISSEUR}
VPN_TYPE=${config.VPN_TYPE}
VPN_CLE_PRIVEE=${config.VPN_CLE_PRIVEE}
VPN_PAYS=${config.VPN_PAYS}
`;

  // recuperation/.env et diffusion/.env
  const envCommun = `# Généré automatiquement par le Panneau de Contrôle
PUID=${config.PUID}
PGID=${config.PGID}
TZ=${config.TZ}
CHEMIN_RELATIF_CONFIG=${config.CHEMIN_RELATIF_CONFIG}
CHEMIN_ABSOLU_MEDIA=${config.CHEMIN_ABSOLU_MEDIA}
`;

  try {
    fs.writeFileSync(path.join(PROJET_DIR, 'reseau', '.env'), envReseau);
    fs.writeFileSync(path.join(PROJET_DIR, 'recuperation', '.env'), envCommun);
    fs.writeFileSync(path.join(PROJET_DIR, 'diffusion', '.env'), envCommun);
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

/**
 * Exécute une commande shell et retourne le résultat
 */
function execCommand(cmd, cwd) {
  return new Promise((resolve, reject) => {
    exec(cmd, { cwd, timeout: 120000 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(stderr || error.message));
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

/**
 * Crée la structure de dossiers média si elle n'existe pas
 */
function creerStructureMedia(cheminMedia) {
  if (!cheminMedia) return;
  const dossiers = [
    cheminMedia,
    path.join(cheminMedia, 'films'),
    path.join(cheminMedia, 'series'),
    path.join(cheminMedia, 'telechargements'),
  ];
  for (const d of dossiers) {
    try {
      fs.mkdirSync(d, { recursive: true });
    } catch (e) {
      console.warn(`Impossible de créer ${d}:`, e.message);
    }
  }
}

// =============================================================================
// ROUTES API
// =============================================================================

/**
 * GET /api/services — Liste des services avec infos statiques
 */
app.get('/api/services', (req, res) => {
  res.json(SERVICES);
});

/**
 * GET /api/status — Statut de tous les conteneurs
 */
app.get('/api/status', async (req, res) => {
  try {
    const containers = await docker.listContainers({ all: true });
    const statuts = SERVICES.map(service => {
      const container = containers.find(c =>
        c.Names.some(n => n === `/${service.id}`)
      );
      return {
        id: service.id,
        nom: service.nom,
        icone: service.icone,
        port: service.port,
        description: service.description,
        groupe: service.groupe,
        etat: container ? container.State : 'absent',
        status: container ? container.Status : 'Non déployé',
      };
    });
    res.json(statuts);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/**
 * POST /api/demarrer — Démarrer toute l'infrastructure
 */
app.post('/api/demarrer', async (req, res) => {
  try {
    const config = chargerConfig();

    // Vérifier que la config minimale est remplie
    if (!config.CHEMIN_ABSOLU_MEDIA) {
      return res.status(400).json({
        error: 'Le chemin des médias n\'est pas configuré. Allez dans Configuration d\'abord.'
      });
    }
    if (!config.VPN_CLE_PRIVEE) {
      return res.status(400).json({
        error: 'La clé VPN n\'est pas configurée. Allez dans Configuration d\'abord.'
      });
    }

    // Générer les .env
    const envResult = genererEnvFiles(config);
    if (!envResult.success) {
      return res.status(500).json({ error: 'Erreur génération .env: ' + envResult.error });
    }

    // Créer la structure de dossiers média
    creerStructureMedia(config.CHEMIN_ABSOLU_MEDIA);

    // Créer le réseau Docker s'il n'existe pas
    try {
      await docker.getNetwork('multimedia_net').inspect();
    } catch {
      await docker.createNetwork({ Name: 'multimedia_net', Driver: 'bridge' });
    }

    // Démarrer dans l'ordre
    for (const groupe of ORDRE_DEMARRAGE) {
      const composePath = path.join(PROJET_DIR, groupe);
      if (fs.existsSync(path.join(composePath, 'compose.yaml'))) {
        console.log(`▶ Démarrage de ${groupe}...`);
        await execCommand('docker compose up -d', composePath);
      }
    }

    res.json({ success: true, message: 'Infrastructure démarrée !' });
  } catch (e) {
    console.error('Erreur démarrage:', e);
    res.status(500).json({ error: e.message });
  }
});

/**
 * POST /api/arreter — Arrêter toute l'infrastructure
 */
app.post('/api/arreter', async (req, res) => {
  try {
    for (const groupe of ORDRE_ARRET) {
      const composePath = path.join(PROJET_DIR, groupe);
      if (fs.existsSync(path.join(composePath, 'compose.yaml'))) {
        console.log(`■ Arrêt de ${groupe}...`);
        await execCommand('docker compose down', composePath);
      }
    }
    res.json({ success: true, message: 'Infrastructure arrêtée !' });
  } catch (e) {
    console.error('Erreur arrêt:', e);
    res.status(500).json({ error: e.message });
  }
});

/**
 * POST /api/update — Mettre à jour (pull) les images Docker et redémarrer
 */
app.post('/api/update', async (req, res) => {
  try {
    for (const groupe of ORDRE_DEMARRAGE) {
      const composePath = path.join(PROJET_DIR, groupe);
      if (fs.existsSync(path.join(composePath, 'compose.yaml'))) {
        console.log(`🔄 Mise à jour de ${groupe}...`);
        await execCommand('docker compose pull', composePath);
        await execCommand('docker compose up -d', composePath);
      }
    }
    res.json({ success: true, message: 'Infrastructure mise à jour !' });
  } catch (e) {
    console.error('Erreur update:', e);
    res.status(500).json({ error: e.message });
  }
});

/**
 * GET /api/logs/:serviceId — Récupérer les 100 dernières lignes de logs
 */
app.get('/api/logs/:serviceId', async (req, res) => {
  try {
    const { serviceId } = req.params;
    const containers = await docker.listContainers({ all: true });
    const container = containers.find(c => c.Names.some(n => n === `/${serviceId}`));
    
    if (!container) {
      return res.status(404).json({ error: 'Conteneur introuvable ou non créé.' });
    }

    try {
      const logOutput = await execCommand(`docker logs --tail 100 ${serviceId}`, PROJET_DIR);
      res.json({ logs: logOutput });
    } catch (cmdError) {
      // Si execCommand fail (ex: container en erreur sans stdout), on renvoie l'erreur en texte
      res.json({ logs: cmdError.message });
    }
  } catch (e) {
    console.error(`Erreur logs pour ${req.params.serviceId}:`, e);
    res.status(500).json({ error: e.message });
  }
});

/**
 * GET /api/config — Récupérer la configuration actuelle
 */
app.get('/api/config', (req, res) => {
  res.json(chargerConfig());
});

/**
 * POST /api/config — Sauvegarder la configuration
 */
app.post('/api/config', (req, res) => {
  try {
    const config = req.body;
    sauvegarderConfig(config);
    const envResult = genererEnvFiles(config);
    if (!envResult.success) {
      return res.status(500).json({ error: 'Config sauvegardée mais erreur .env: ' + envResult.error });
    }
    res.json({ success: true, message: 'Configuration sauvegardée !' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/**
 * GET /api/archive — Vérifie si une archive de config existe
 */
app.get('/api/archive', (req, res) => {
  try {
    const fichiers = fs.readdirSync(PROJET_DIR)
      .filter(f => f.startsWith('multimedia-config-') && f.endsWith('.tar.gz'));
    res.json({ archives: fichiers });
  } catch (e) {
    res.json({ archives: [] });
  }
});

/**
 * POST /api/importer — Importer une archive de configuration
 */
app.post('/api/importer', async (req, res) => {
  try {
    const { archive } = req.body;
    if (!archive) {
      return res.status(400).json({ error: 'Nom d\'archive requis' });
    }

    const archivePath = path.join(PROJET_DIR, archive);
    if (!fs.existsSync(archivePath)) {
      return res.status(404).json({ error: 'Archive non trouvée' });
    }

    console.log(`📦 Import de ${archive}...`);
    await execCommand(`tar xzf "${archivePath}"`, PROJET_DIR);

    res.json({ success: true, message: 'Configurations importées avec succès !' });
  } catch (e) {
    console.error('Erreur import:', e);
    res.status(500).json({ error: e.message });
  }
});

/**
 * POST /api/exporter — Exporter les configs dans une archive
 * Tourne dans le conteneur (accès root) pour éviter les problèmes de permissions
 */
app.post('/api/exporter', async (req, res) => {
  try {
    // Arrêter l'infrastructure d'abord (éviter corruption SQLite)
    console.log('📦 Export : arrêt des conteneurs...');
    for (const groupe of ORDRE_ARRET) {
      const composePath = path.join(PROJET_DIR, groupe);
      if (fs.existsSync(path.join(composePath, 'compose.yaml'))) {
        try {
          await execCommand('docker compose down', composePath);
        } catch (e) {
          console.warn(`Avertissement arrêt ${groupe}:`, e.message);
        }
      }
    }

    // Créer l'archive
    const date = new Date().toISOString().slice(0, 10);
    const nomArchive = `multimedia-config-${date}.tar.gz`;
    const archivePath = path.join(PROJET_DIR, nomArchive);

    console.log(`📦 Création de ${nomArchive}...`);
    const excludes = [
      '--exclude=*/cache/*',
      '--exclude=*/temp/*',
      '--exclude=*/Backups/*',
      '--exclude=*/logs/*',
      '--exclude=*/log/*',
      '--exclude=*logs.db*',
      '--exclude=*lockfile*',
      '--exclude=*.log',
    ].join(' ');

    await execCommand(
      `tar czf "${archivePath}" ${excludes} reseau/config/ recuperation/config/ diffusion/config/`,
      PROJET_DIR
    );

    // Redémarrer l'infrastructure
    console.log('📦 Export : redémarrage des conteneurs...');
    try {
      await docker.getNetwork('multimedia_net').inspect();
    } catch {
      await docker.createNetwork({ Name: 'multimedia_net', Driver: 'bridge' });
    }

    for (const groupe of ORDRE_DEMARRAGE) {
      const composePath = path.join(PROJET_DIR, groupe);
      if (fs.existsSync(path.join(composePath, 'compose.yaml'))) {
        try {
          await execCommand('docker compose up -d', composePath);
        } catch (e) {
          console.warn(`Avertissement démarrage ${groupe}:`, e.message);
        }
      }
    }

    // Taille du fichier
    const stats = fs.statSync(archivePath);
    const tailleMo = (stats.size / 1024 / 1024).toFixed(1);

    res.json({
      success: true,
      message: `Archive créée : ${nomArchive} (${tailleMo} Mo)`,
      archive: nomArchive,
      taille: `${tailleMo} Mo`,
    });
  } catch (e) {
    console.error('Erreur export:', e);
    res.status(500).json({ error: e.message });
  }
});

// =============================================================================
// DÉMARRAGE DU SERVEUR
// =============================================================================

app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('========================================');
  console.log('  🎛️  PANNEAU DE CONTRÔLE MULTIMÉDIA');
  console.log('========================================');
  console.log(`  → Interface : http://localhost:${PORT}`);
  console.log('========================================');
  console.log('');
});
