// =============================================================================
// APP.JS — Logique Frontend du Panneau de Contrôle Multimédia
// =============================================================================

// --- État global ---
let configActuelle = {};
let archiveDetectee = null;
let pollingInterval = null;

// =============================================================================
// INITIALISATION
// =============================================================================

document.addEventListener('DOMContentLoaded', () => {
  // Navigation par onglets
  document.querySelectorAll('.nav-tab').forEach(tab => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
  });

  // Chargement initial
  chargerStatut();
  chargerConfig();
  verifierArchive();

  // Polling du statut toutes les 5 secondes
  pollingInterval = setInterval(chargerStatut, 5000);
});

// =============================================================================
// NAVIGATION
// =============================================================================

function switchTab(tabId) {
  // Mettre à jour les onglets
  document.querySelectorAll('.nav-tab').forEach(t => t.classList.remove('active'));
  document.querySelector(`[data-tab="${tabId}"]`).classList.add('active');

  // Mettre à jour le contenu
  document.querySelectorAll('.tab-content').forEach(s => s.classList.remove('active'));
  document.getElementById(`section-${tabId}`).classList.add('active');
}

// =============================================================================
// STATUT DES SERVICES
// =============================================================================

async function chargerStatut() {
  try {
    const response = await fetch('/api/status');
    if (!response.ok) throw new Error('Erreur réseau');
    const statuts = await response.json();
    afficherServices(statuts);
    mettreAJourStatutGlobal(statuts);
  } catch (e) {
    console.error('Erreur chargement statut:', e);
  }
}

function afficherServices(statuts) {
  const grid = document.getElementById('services-grid');
  grid.innerHTML = statuts.map(s => {
    const etatClasse = s.etat === 'running' ? 'running' : 'stopped';
    const etatTexte = traductionEtat(s.etat);
    const portHtml = s.port
      ? `<span class="service-port"><a href="http://localhost:${s.port}" target="_blank">:${s.port}</a></span>`
      : '';

    return `
      <div class="service-card ${etatClasse}">
        <div class="service-header">
          <div class="service-icon">${s.icone}</div>
          <div>
            <div class="service-name">${s.nom}</div>
            <div class="service-desc">${s.description}</div>
          </div>
        </div>
        <div class="service-meta">
          <div class="service-status ${etatClasse}">
            <span class="dot"></span>
            ${etatTexte}
          </div>
          <div class="service-actions">
            ${portHtml}
            <button class="btn-icon-small" onclick="ouvrirLogs('${s.id}', '${s.nom}')" title="Voir les logs">📄</button>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

function traductionEtat(etat) {
  const traductions = {
    'running': 'En marche',
    'exited': 'Arrêté',
    'created': 'Créé',
    'paused': 'En pause',
    'restarting': 'Redémarre...',
    'removing': 'Suppression...',
    'dead': 'Mort',
    'absent': 'Non déployé',
  };
  return traductions[etat] || etat;
}

function mettreAJourStatutGlobal(statuts) {
  const dot = document.getElementById('global-dot');
  const text = document.getElementById('global-text');

  const enMarche = statuts.filter(s => s.etat === 'running').length;
  const total = statuts.length;

  // Retirer toutes les classes
  dot.classList.remove('running', 'partial', 'stopped');

  if (enMarche === total) {
    dot.classList.add('running');
    text.textContent = 'Tout est en marche';
  } else if (enMarche > 0) {
    dot.classList.add('partial');
    text.textContent = `${enMarche}/${total} services actifs`;
  } else {
    dot.classList.add('stopped');
    text.textContent = 'Infrastructure éteinte';
  }
}

// =============================================================================
// CONTRÔLE DE L'INFRASTRUCTURE
// =============================================================================

async function demarrerTout() {
  const btn = document.getElementById('btn-demarrer');
  btn.disabled = true;
  afficherChargement('Démarrage de l\'infrastructure...\nCela peut prendre 1 à 2 minutes.');

  try {
    const response = await fetch('/api/demarrer', { method: 'POST' });
    const data = await response.json();

    if (response.ok) {
      toast('success', '🚀', data.message);
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  masquerChargement();
  btn.disabled = false;
  chargerStatut();
}

async function arreterTout() {
  const btn = document.getElementById('btn-arreter');
  btn.disabled = true;
  afficherChargement('Arrêt de l\'infrastructure...');

  try {
    const response = await fetch('/api/arreter', { method: 'POST' });
    const data = await response.json();

    if (response.ok) {
      toast('success', '🛑', data.message);
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  masquerChargement();
  btn.disabled = false;
  chargerStatut();
}

async function mettreAJour() {
  const btn = document.getElementById('btn-update');
  btn.disabled = true;
  afficherChargement('Mise à jour des images Docker...\nCela peut prendre plusieurs minutes. Ne fermez pas la page.');

  try {
    const response = await fetch('/api/update', { method: 'POST' });
    const data = await response.json();

    if (response.ok) {
      toast('success', '🔄', data.message);
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  masquerChargement();
  btn.disabled = false;
  chargerStatut();
}

async function exporterConfigs() {
  const btn = document.getElementById('btn-exporter');
  btn.disabled = true;
  afficherChargement('Export des configurations...\nArrêt, archivage, puis redémarrage.');

  try {
    const response = await fetch('/api/exporter', { method: 'POST' });
    const data = await response.json();

    if (response.ok) {
      toast('success', '📦', data.message);
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  masquerChargement();
  btn.disabled = false;
  chargerStatut();
}

// =============================================================================
// CONFIGURATION
// =============================================================================

async function chargerConfig() {
  try {
    const response = await fetch('/api/config');
    if (!response.ok) throw new Error('Erreur réseau');
    configActuelle = await response.json();

    // Remplir les champs
    const champs = {
      'cfg-puid': 'PUID',
      'cfg-pgid': 'PGID',
      'cfg-tz': 'TZ',
      'cfg-config-path': 'CHEMIN_RELATIF_CONFIG',
      'cfg-media-path': 'CHEMIN_ABSOLU_MEDIA',
      'cfg-vpn-provider': 'VPN_FOURNISSEUR',
      'cfg-vpn-type': 'VPN_TYPE',
      'cfg-vpn-key': 'VPN_CLE_PRIVEE',
      'cfg-vpn-country': 'VPN_PAYS',
    };

    for (const [id, cle] of Object.entries(champs)) {
      const input = document.getElementById(id);
      if (input && configActuelle[cle] !== undefined) {
        input.value = configActuelle[cle];
      }
    }
  } catch (e) {
    console.error('Erreur chargement config:', e);
  }
}

async function sauvegarderConfig(event) {
  event.preventDefault();

  const btn = document.getElementById('btn-save');
  btn.disabled = true;

  // Collecter les valeurs du formulaire
  const config = {
    PUID: document.getElementById('cfg-puid').value || '1000',
    PGID: document.getElementById('cfg-pgid').value || '1000',
    TZ: document.getElementById('cfg-tz').value || 'Europe/Paris',
    CHEMIN_RELATIF_CONFIG: document.getElementById('cfg-config-path').value || './config',
    CHEMIN_ABSOLU_MEDIA: document.getElementById('cfg-media-path').value,
    VPN_FOURNISSEUR: document.getElementById('cfg-vpn-provider').value || 'custom',
    VPN_TYPE: document.getElementById('cfg-vpn-type').value || 'wireguard',
    VPN_CLE_PRIVEE: document.getElementById('cfg-vpn-key').value,
    VPN_PAYS: document.getElementById('cfg-vpn-country').value || 'Switzerland',
  };

  try {
    const response = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(config),
    });
    const data = await response.json();

    if (response.ok) {
      toast('success', '💾', data.message);
      configActuelle = config;
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  btn.disabled = false;
}

// =============================================================================
// IMPORT D'ARCHIVE
// =============================================================================

async function verifierArchive() {
  try {
    const response = await fetch('/api/archive');
    const data = await response.json();

    if (data.archives && data.archives.length > 0) {
      archiveDetectee = data.archives[0]; // Prendre la plus récente
      document.getElementById('import-banner').style.display = 'block';
    }
  } catch (e) {
    console.error('Erreur vérification archive:', e);
  }
}

async function importerArchive() {
  if (!archiveDetectee) return;

  const btn = document.getElementById('btn-importer');
  btn.disabled = true;
  afficherChargement('Importation des configurations...');

  try {
    const response = await fetch('/api/importer', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archive: archiveDetectee }),
    });
    const data = await response.json();

    if (response.ok) {
      toast('success', '📦', data.message);
      document.getElementById('import-banner').style.display = 'none';
    } else {
      toast('error', '❌', data.error);
    }
  } catch (e) {
    toast('error', '❌', 'Erreur de connexion au serveur');
  }

  masquerChargement();
  btn.disabled = false;
}

// =============================================================================
// UI HELPERS
// =============================================================================

function afficherChargement(message) {
  document.getElementById('loading-message').textContent = message;
  document.getElementById('loading-overlay').style.display = 'flex';
}

function masquerChargement() {
  document.getElementById('loading-overlay').style.display = 'none';
}

function toast(type, icon, message) {
  const container = document.getElementById('toast-container');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<span class="toast-icon">${icon}</span><span>${message}</span>`;
  container.appendChild(el);

  // Auto-dismiss après 5s
  setTimeout(() => {
    el.classList.add('fade-out');
    setTimeout(() => el.remove(), 300);
  }, 5000);
}

// =============================================================================
// LOGS
// =============================================================================

async function ouvrirLogs(serviceId, serviceNom) {
  const modal = document.getElementById('logs-modal');
  const title = document.getElementById('logs-title');
  const output = document.getElementById('logs-output');

  title.textContent = `Logs : ${serviceNom}`;
  output.textContent = 'Chargement...';
  modal.style.display = 'flex';

  try {
    const response = await fetch(`/api/logs/${serviceId}`);
    const data = await response.json();
    if (response.ok) {
      output.textContent = data.logs || 'Aucun log disponible.';
    } else {
      output.textContent = `Erreur: ${data.error}`;
    }
  } catch (e) {
    output.textContent = 'Erreur de connexion au serveur.';
  }
}

function fermerLogs() {
  document.getElementById('logs-modal').style.display = 'none';
}
