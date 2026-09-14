(() => {
  'use strict';
  const REPO = 'https://repo.nextjailbreak.com/';
  const grid = document.querySelector('#package-grid');
  const stats = document.querySelector('#repo-stats');
  const search = document.querySelector('#package-search');
  const filterButtons = [...document.querySelectorAll('[data-filter]')];
  const copy = document.querySelector('#copy-repo');
  let packages = [];
  let activeFilter = 'all';

  copy?.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(REPO);
      const previous = copy.textContent;
      copy.textContent = 'Copied';
      setTimeout(() => { copy.textContent = previous; }, 1400);
    } catch {
      window.prompt('Copy the repository URL:', REPO);
    }
  });

  const parseStanzas = text => text.trim().split(/\n\s*\n/).map(block => {
    const item = {};
    let lastKey = '';
    block.split(/\r?\n/).forEach(line => {
      if (/^\s/.test(line) && lastKey) {
        item[lastKey] = `${item[lastKey]} ${line.trim()}`.trim();
        return;
      }
      const index = line.indexOf(':');
      if (index < 1) return;
      lastKey = line.slice(0, index).trim();
      item[lastKey] = line.slice(index + 1).trim();
    });
    return item;
  }).filter(item => item.Package && item.Name);

  const compareVersions = (a, b) => {
    const ax = String(a || '').split(/[^0-9A-Za-z]+/).filter(Boolean);
    const bx = String(b || '').split(/[^0-9A-Za-z]+/).filter(Boolean);
    for (let i = 0; i < Math.max(ax.length, bx.length); i++) {
      const av = ax[i] ?? '0';
      const bv = bx[i] ?? '0';
      const an = /^\d+$/.test(av) ? Number(av) : NaN;
      const bn = /^\d+$/.test(bv) ? Number(bv) : NaN;
      const cmp = Number.isFinite(an) && Number.isFinite(bn) ? an - bn : av.localeCompare(bv, undefined, {numeric:true});
      if (cmp) return cmp;
    }
    return 0;
  };

  const normalize = stanzas => {
    const grouped = new Map();
    for (const item of stanzas) {
      const section = String(item.Section || '').toLowerCase();
      if (!['tweaks', 'applications'].includes(section)) continue;
      const id = item.Package;
      const current = grouped.get(id) || {
        id,
        name: item.Name,
        version: item.Version || '',
        section,
        description: item.Description || '',
        depiction: item.Depiction || '',
        homepage: item.Homepage || '',
        architectures: new Set(),
        variants: new Set()
      };
      if (compareVersions(item.Version, current.version) > 0) {
        current.version = item.Version || current.version;
        current.name = item.Name || current.name;
        current.description = item.Description || current.description;
        current.depiction = item.Depiction || current.depiction;
        current.homepage = item.Homepage || current.homepage;
      }
      if (item.Architecture) current.architectures.add(item.Architecture);
      const file = String(item.Filename || '').toLowerCase();
      if (file.includes('roothide') || item.Architecture === 'iphoneos-arm64e') current.variants.add('RootHide');
      if (file.includes('rootless') || item.Architecture === 'iphoneos-arm64') current.variants.add('Rootless');
      if (file.includes('rootful') || item.Architecture === 'iphoneos-arm') current.variants.add('Rootful');
      grouped.set(id, current);
    }
    return [...grouped.values()].sort((a, b) => a.name.localeCompare(b.name, undefined, {numeric:true}));
  };

  const card = item => {
    const article = document.createElement('article');
    article.className = 'package-card';
    article.dataset.section = item.section;
    article.dataset.search = `${item.name} ${item.id} ${item.description} ${item.version}`.toLowerCase();

    const meta = document.createElement('div');
    meta.className = 'package-meta';
    const version = document.createElement('span');
    version.className = 'pill';
    version.textContent = `v${item.version}`;
    meta.appendChild(version);
    for (const variant of item.variants) {
      const pill = document.createElement('span');
      pill.className = 'pill';
      pill.textContent = variant;
      meta.appendChild(pill);
    }

    const title = document.createElement('h3');
    title.textContent = item.name;
    const id = document.createElement('div');
    id.className = 'package-id';
    id.textContent = item.id;
    const description = document.createElement('p');
    description.textContent = item.description || 'Official Next Jailbreak package.';

    const actions = document.createElement('div');
    actions.className = 'package-actions';
    const sileo = document.createElement('a');
    sileo.className = 'primary';
    sileo.href = `sileo://package/${encodeURIComponent(item.id)}`;
    sileo.textContent = 'Open in Sileo';
    actions.appendChild(sileo);
    if (item.depiction) {
      const details = document.createElement('a');
      try {
        const url = new URL(item.depiction);
        details.href = `${url.pathname}${url.search}${url.hash}`;
      } catch {
        details.href = item.depiction;
      }
      details.textContent = 'Details';
      actions.appendChild(details);
    }
    article.append(meta, title, id, description, actions);
    return article;
  };

  const applyFilter = () => {
    const term = String(search?.value || '').trim().toLowerCase();
    let visible = 0;
    document.querySelectorAll('.package-card').forEach(node => {
      const sectionMatch = activeFilter === 'all' || node.dataset.section === activeFilter;
      const textMatch = !term || node.dataset.search.includes(term);
      const show = sectionMatch && textMatch;
      node.classList.toggle('hidden', !show);
      if (show) visible++;
    });
    if (stats) {
      const tweaks = packages.filter(item => item.section === 'tweaks').length;
      const apps = packages.filter(item => item.section === 'applications').length;
      stats.textContent = `${visible} shown · ${tweaks} tweaks · ${apps} applications`;
    }
  };

  filterButtons.forEach(button => button.addEventListener('click', () => {
    activeFilter = button.dataset.filter || 'all';
    filterButtons.forEach(item => item.classList.toggle('active', item === button));
    applyFilter();
  }));
  search?.addEventListener('input', applyFilter);

  const load = async () => {
    try {
      const response = await fetch('/Packages', {headers:{'Accept':'text/plain'}, cache:'no-store'});
      if (!response.ok) throw new Error(`Repository metadata returned HTTP ${response.status}`);
      packages = normalize(parseStanzas(await response.text()));
      grid.replaceChildren(...packages.map(card));
      if (!packages.length) {
        grid.innerHTML = '<div class="empty">No public tweak or application packages were found.</div>';
      }
      applyFilter();
    } catch (error) {
      console.error(error);
      grid.innerHTML = '<div class="empty">Package list is temporarily unavailable. The repository can still be added using the buttons above.</div>';
      if (stats) stats.textContent = '';
    }
  };
  load();
})();
