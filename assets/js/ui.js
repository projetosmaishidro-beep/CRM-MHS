window.UI = (() => {
  const isSubpage = () => location.pathname.includes("/pages/");
  const root = () => (isSubpage() ? "../" : "./");
  const pageLink = (path) => `${root()}${path}`;
  const $ = (selector, parent = document) => parent.querySelector(selector);
  const $$ = (selector, parent = document) => [...parent.querySelectorAll(selector)];

  const icon = (name, size = 20) => {
    const paths = {
      home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/><path d="M9 20v-6h6v6"/>',
      users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
      user: '<path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="7" r="4"/>',
      briefcase: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M3 12h18"/>',
      map: '<polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21 3 6"/><path d="M9 3v15M15 6v15"/>',
      wallet: '<path d="M20 7V5a2 2 0 0 0-2-2H5a3 3 0 0 0 0 6h15v10H5a3 3 0 0 1-3-3V6"/><path d="M16 13h2"/>',
      chart: '<path d="M3 3v18h18"/><path d="m7 16 4-5 4 3 5-7"/>',
      plus: '<path d="M12 5v14M5 12h14"/>',
      search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
      filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
      grid: '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/>',
      list: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="18" r="1"/>',
      chevron: '<path d="m9 18 6-6-6-6"/>',
      pin: '<path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/>',
      camera: '<path d="M14.5 4 16 7h3a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h3l1.5-3h5Z"/><circle cx="12" cy="13" r="4"/>',
      paperclip: '<path d="m21.4 11.6-8.9 8.9a6 6 0 0 1-8.5-8.5l9.6-9.6a4 4 0 0 1 5.7 5.7l-9.6 9.6a2 2 0 0 1-2.8-2.8l8.9-8.9"/>',
      menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
      x: '<path d="m6 6 12 12M18 6 6 18"/>',
      check: '<path d="m20 6-11 11-5-5"/>',
      clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
      route: '<circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M6 17c0-6 12-4 12-10"/>',
      receipt: '<path d="M6 2h12v20l-3-2-3 2-3-2-3 2V2Z"/><path d="M9 7h6M9 11h6M9 15h4"/>',
      file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/>',
      arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
      arrow_left: '<path d="M19 12H5M11 18l-6-6 6-6"/>',
      bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 7h18s-3 0-3-7"/><path d="M10 19h4"/>',
      rotate: '<path d="M20 6v5h-5"/><path d="M4 18v-5h5"/><path d="M18 9a7 7 0 0 0-12-3L4 8M6 15a7 7 0 0 0 12 3l2-2"/>',
      database: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v7c0 1.66 3.58 3 8 3s8-1.34 8-3V5"/><path d="M4 12v7c0 1.66 3.58 3 8 3s8-1.34 8-3v-7"/>',
      eye: '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/>',
      calendar: '<rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>',
      globe: '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
      trash: '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/>',
      edit: '<path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/>',
      link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>'
    };
    return `<svg class="icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.file}</svg>`;
  };

  const nav = [
    { id: "dashboard", label: "Início", href: "index.html", icon: "home" },
    { id: "clients", label: "Clientes", href: "pages/clientes.html", icon: "users" },
    { id: "visits", label: "Visitas", href: "pages/visitas.html", icon: "pin" },
    { id: "trips", label: "Viagens", href: "pages/viagens.html", icon: "briefcase" },
    { id: "events", label: "Eventos", href: "pages/eventos.html", icon: "calendar" },
    { id: "map", label: "Mapa", href: "HANDOFF_MAPA_CLIENTES/02_PROJETO_ATUAL/index.html", icon: "map", target: "_blank" },
    { id: "finance", label: "Financeiro", href: "pages/financeiro.html", icon: "wallet" },
    { id: "reports", label: "Relatórios", href: "pages/relatorios.html", icon: "chart" },
    { id: "users", label: "Usuários", href: "pages/usuarios.html", icon: "user" }
  ];

  function mountShell() {
    const page = document.body.dataset.page || "";
    const title = document.body.dataset.title || "Central Comercial";
    const activePage = ({ client: "clients", "new-visit": "visits", trip: "trips", user: "users", event: "events" })[page] || page;
    const isSubpage = page !== activePage;
    const parentNav = nav.find(i => i.id === activePage) || nav[0];

    const app = document.querySelector("#app");
    const authUser = window.AuthUser || {};
    const profileInitials = authUser.initials || "MA";
    const profileName = authUser.name || "Marina Alves";
    const profileRole = authUser.isAdmin ? "Administrador" : "Equipe Comercial";
    const profileEmail = authUser.email || "";

    app.innerHTML = `
      <div class="app-shell">
        <div class="workspace">
          <header class="topbar">
            <div class="topbar-brand-area">
              ${isSubpage
                ? `<a class="icon-btn mobile-menu" href="${pageLink(parentNav.href)}" aria-label="Voltar">${icon("arrow_left")}</a>`
                : `<button class="icon-btn mobile-menu" id="mobileMenuBtn" aria-label="Abrir menu">${icon("menu")}</button>`
              }
              <a class="topbar-logo" href="${pageLink("index.html")}" aria-label="Mais Hidro Soluções - início">
                <img src="${pageLink("assets/images/logo-mais.jpg")}" alt="Mais Hidro Soluções" loading="eager">
              </a>
              <div class="topbar-title">
                <span class="eyebrow">Central comercial</span>
                <h1>${title}</h1>
              </div>
            </div>

            <nav class="desktop-nav" aria-label="Navegação principal">
              ${nav.map(item => `
                <a class="${activePage === item.id ? "active" : ""}" href="${pageLink(item.href)}" title="${item.label}" ${item.target ? `target="${item.target}" rel="noopener"` : ""}>
                  ${icon(item.icon, 17)}<span>${item.label}</span>
                </a>`).join("")}
            </nav>

            <div class="topbar-actions">
              <button class="icon-btn" id="globalSearchBtn" aria-label="Buscar">${icon("search")}</button>
              <button class="icon-btn hide-mobile" aria-label="Notificações">${icon("bell")}</button>
              <button class="avatar-btn" id="profileMenuBtn" aria-label="Menu do usuário" style="padding: 0; overflow: hidden; border: none; background: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.05);"><img src="${pageLink('assets/images/logo-mais.jpg')}" alt="Logo Mais Hidro" style="width: 100%; height: 100%; object-fit: contain;"></button>
            </div>
          </header>

          <main class="page-content" id="pageContent"></main>
        </div>

        <nav class="bottom-nav" aria-label="Navegação móvel">
          ${nav.slice(0, 5).map(item => `
            <a class="${activePage === item.id ? "active" : ""}" href="${pageLink(item.href)}" ${item.target ? `target="${item.target}" rel="noopener"` : ""}>
              ${icon(item.icon, 19)}<span>${item.label}</span>
            </a>`).join("")}
        </nav>

        <div class="mobile-drawer" id="mobileDrawer" aria-hidden="true">
          <div class="drawer-backdrop" data-close-drawer></div>
          <aside class="drawer-panel">
            <div class="drawer-brand">
              <img src="${pageLink("assets/images/logo-mais.jpg")}" alt="Mais Hidro Soluções">
            </div>
            <div class="drawer-head"><strong>Menu</strong><button class="icon-btn" data-close-drawer>${icon("x")}</button></div>
            <nav class="drawer-nav">
              ${nav.map(item => `
                <a class="${activePage === item.id ? "active" : ""}" href="${pageLink(item.href)}" ${item.target ? `target="${item.target}" rel="noopener"` : ""}>
                  ${icon(item.icon)}<span>${item.label}</span>
                </a>`).join("")}
            </nav>
          </aside>
        </div>

        <dialog class="search-dialog" id="searchDialog">
          <div class="dialog-head">
            <div><span class="eyebrow">Busca global</span><h2>Encontre rapidamente</h2></div>
            <button class="icon-btn" data-close-dialog>${icon("x")}</button>
          </div>
          <label class="search-field">${icon("search")}<input id="globalSearchInput" placeholder="Cliente, viagem, usuário..." autocomplete="off"></label>
          <div id="globalSearchResults" class="search-results"></div>
        </dialog>

        <div class="profile-popover" id="profilePopover">
          <div class="profile-chip large"><span class="avatar" style="padding: 0; overflow: hidden; border: 1px solid #e2e8f0; background: #fff;"><img src="${pageLink('assets/images/logo-mais.jpg')}" alt="Logo Mais Hidro" style="width: 100%; height: 100%; object-fit: contain;"></span><span><strong>${profileName}</strong><small>${profileRole}</small></span></div>
          <a href="${pageLink("pages/usuarios.html")}">${icon("user")} Meu perfil</a>
          ${authUser.isAdmin ? `<button id="connectionBtn">${icon("database")} Configurações do banco</button>` : ""}
          <button id="resetDemoBtn">${icon("rotate")} Restaurar demo</button>
          <button id="logoutBtn" style="color:var(--mais-red)">${icon("arrow")} Sair</button>
        </div>

        <dialog class="form-dialog connection-dialog" id="connectionDialog" aria-labelledby="connectionTitle">
          <form id="connectionForm" novalidate>
            <div class="dialog-head">
              <div>
                <span class="eyebrow">Integração</span>
                <h2 id="connectionTitle">Banco de dados</h2>
              </div>
              <button class="icon-btn" type="button" data-close-dialog aria-label="Fechar">${icon("x")}</button>
            </div>

            <p class="connection-intro">Informe a URL e a chave pública do projeto Supabase. Esta etapa só valida e guarda a conexão neste navegador; os dados locais continuam intactos.</p>

            <div class="connection-schema-list" aria-label="Estrutura preparada">
              <span>${icon("database", 16)} cadastro</span>
              <span>${icon("map", 16)} mapa</span>
              <span>${icon("briefcase", 16)} crm</span>
            </div>

            <div class="connection-fields">
              <label class="field">
                <span>URL do projeto</span>
                <input id="connectionUrl" type="url" inputmode="url" autocomplete="off" placeholder="https://seu-projeto.supabase.co" required>
              </label>
              <label class="field">
                <span>Chave pública (publishable ou anon)</span>
                <div class="connection-key-field">
                  <input id="connectionKey" type="password" autocomplete="off" spellcheck="false" placeholder="sb_publishable_..." required>
                  <button id="toggleConnectionKey" class="connection-key-toggle" type="button" aria-label="Mostrar chave">${icon("eye", 17)}</button>
                </div>
              </label>
            </div>

            <p class="connection-security-note">Nunca use aqui a chave <strong>secret</strong> ou <strong>service_role</strong>.</p>
            <p id="connectionStatus" class="connection-status" role="status">Nenhuma conexão salva neste navegador.</p>

            <section class="connection-auth" aria-labelledby="connectionAuthTitle">
              <div class="connection-auth-head">
                <div><span class="eyebrow">Acesso da equipe</span><strong id="connectionAuthTitle">Entrar para consultar a carteira</strong></div>
                <small id="connectionAuthStatus">Sem sessão iniciada.</small>
              </div>
              <div class="connection-auth-fields">
                <label class="field"><span>E-mail</span><input id="connectionEmail" type="email" autocomplete="username" placeholder="voce@empresa.com"></label>
                <label class="field"><span>Senha</span><input id="connectionPassword" type="password" autocomplete="current-password" placeholder="Sua senha"></label>
              </div>
              <div class="connection-auth-actions">
                <button id="connectionSignInBtn" class="btn btn-secondary" type="button">Entrar</button>
                <button id="connectionSignOutBtn" class="text-link connection-signout" type="button" hidden>Sair</button>
              </div>
            </section>

            <div class="dialog-actions connection-actions">
              <button id="clearConnectionBtn" class="btn btn-secondary" type="button">Limpar</button>
              <button id="testConnectionBtn" class="btn btn-secondary" type="button">Testar conexão</button>
              <button class="btn btn-primary" type="submit">Salvar conexão</button>
            </div>
          </form>
        </dialog>

        <div class="toast-region" id="toastRegion" aria-live="polite"></div>
      </div>
    `;

    $("#mobileMenuBtn")?.addEventListener("click", () => toggleDrawer(true));
    $$("[data-close-drawer]").forEach(el => el.addEventListener("click", () => toggleDrawer(false)));
    $("#globalSearchBtn")?.addEventListener("click", openSearch);
    $$("[data-close-dialog]").forEach(el => el.addEventListener("click", () => el.closest("dialog")?.close()));
    $("#profileMenuBtn")?.addEventListener("click", (event) => {
      event.stopPropagation();
      $("#profilePopover").classList.toggle("open");
    });
    document.addEventListener("click", () => $("#profilePopover")?.classList.remove("open"));
    $("#profilePopover")?.addEventListener("click", (e) => e.stopPropagation());
    $("#connectionBtn")?.addEventListener("click", openConnectionDialog);
    $("#connectionForm")?.addEventListener("submit", saveConnection);
    $("#testConnectionBtn")?.addEventListener("click", testConnection);
    $("#clearConnectionBtn")?.addEventListener("click", clearConnection);
    $("#toggleConnectionKey")?.addEventListener("click", toggleConnectionKeyVisibility);
    $("#connectionSignInBtn")?.addEventListener("click", signInToSupabase);
    $("#connectionSignOutBtn")?.addEventListener("click", signOutFromSupabase);
    $("#resetDemoBtn")?.addEventListener("click", () => {
      Store.reset();
      toast("Dados da demonstração restaurados.");
      setTimeout(() => location.reload(), 350);
    });

    $("#logoutBtn")?.addEventListener("click", async () => {
      try {
        const client = window.AuthClient || await getSupabaseClient();
        if (client) await client.auth.signOut();
      } catch { /* ignore */ }
      localStorage.removeItem(CONNECTION_STORAGE_KEY);
      const loginPath = isSubpage() ? "../login.html" : "login.html";
      window.location.replace(loginPath);
    });

    registerServiceWorker();
    initRevealObserver();
  }

  const CONNECTION_STORAGE_KEY = "mais_hidro_supabase_connection_v1";
  let supabaseClient = null;
  let supabaseClientFingerprint = "";

  function readConnection() {
    // Prefer centralized config over per-browser localStorage
    const config = window.SUPABASE_CONFIG || {};
    if (config.SUPABASE_URL && config.SUPABASE_ANON_KEY) {
      return { url: config.SUPABASE_URL, apiKey: config.SUPABASE_ANON_KEY };
    }
    try {
      const saved = JSON.parse(localStorage.getItem(CONNECTION_STORAGE_KEY) || "null");
      return saved && typeof saved === "object" ? saved : {};
    } catch {
      return {};
    }
  }

  function normalizeConnection() {
    const rawUrl = $("#connectionUrl")?.value.trim() || "";
    const apiKey = $("#connectionKey")?.value.trim() || "";
    let url;
    try {
      url = new URL(rawUrl);
    } catch {
      throw new Error("Informe uma URL válida do projeto Supabase.");
    }
    if (!/^https?:$/.test(url.protocol)) {
      throw new Error("A URL precisa começar com https:// ou http://.");
    }
    if (!apiKey || apiKey.length < 12) {
      throw new Error("Informe a chave pública do projeto.");
    }
    if (isRestrictedSupabaseKey(apiKey)) {
      throw new Error("Use somente uma chave pública publishable ou anon.");
    }
    return { url: url.href.replace(/\/$/, ""), apiKey };
  }

  function isRestrictedSupabaseKey(apiKey) {
    if (/service_role|sb_secret/i.test(apiKey)) return true;
    try {
      const [, encodedPayload, signature] = apiKey.split(".");
      if (!encodedPayload || !signature) return false;
      const payload = JSON.parse(atob(encodedPayload.replace(/-/g, "+").replace(/_/g, "/")));
      return payload.role === "service_role";
    } catch {
      return false;
    }
  }

  function setConnectionStatus(message, state = "neutral") {
    const status = $("#connectionStatus");
    if (!status) return;
    status.textContent = message;
    status.dataset.state = state;
  }

  async function openConnectionDialog() {
    const saved = readConnection();
    const dialog = $("#connectionDialog");
    if (!dialog) return;
    $("#connectionUrl").value = saved.url || "";
    $("#connectionKey").value = saved.apiKey || "";
    setConnectionStatus(
      saved.url && saved.apiKey
        ? "Conexão salva neste navegador. Teste-a antes de seguir para a integração dos dados."
        : "Nenhuma conexão salva neste navegador.",
      saved.url && saved.apiKey ? "ready" : "neutral"
    );
    $("#profilePopover")?.classList.remove("open");
    dialog.showModal();
    await renderConnectionAuthState();
    setTimeout(() => $("#connectionUrl")?.focus(), 40);
  }

  function saveConnection(event) {
    event.preventDefault();
    try {
      const connection = normalizeConnection();
      localStorage.setItem(CONNECTION_STORAGE_KEY, JSON.stringify(connection));
      setConnectionStatus("Conexão salva neste navegador. Nenhum dado foi migrado ou exposto.", "success");
      renderConnectionAuthState();
      toast("Conexão preparada.");
    } catch (error) {
      setConnectionStatus(error.message || "Não foi possível salvar a conexão.", "error");
    }
  }

  async function testConnection() {
    const button = $("#testConnectionBtn");
    let connection;
    try {
      if (location.protocol === "file:") {
        throw new Error("Abra o aplicativo por um servidor local (http://localhost), não diretamente pelo arquivo HTML.");
      }
      connection = normalizeConnection();
    } catch (error) {
      setConnectionStatus(error.message || "Revise a conexão.", "error");
      return;
    }

    button.disabled = true;
    button.textContent = "Testandoâ€¦";
    setConnectionStatus("Validando URL e chave pública sem consultar dados comerciaisâ€¦", "loading");
    try {
      const response = await fetch(`${connection.url}/auth/v1/settings`, {
        headers: { apikey: connection.apiKey }
      });
      if (!response.ok) throw new Error(`A API respondeu com código ${response.status}.`);
      setConnectionStatus("Projeto acessível. A leitura de clientes será liberada na próxima etapa, com autenticação e RLS.", "success");
    } catch (error) {
      setConnectionStatus(error.message || "Não foi possível alcançar o projeto. Confira a URL, a chave e sua internet.", "error");
    } finally {
      button.disabled = false;
      button.textContent = "Testar conexão";
    }
  }

  function clearConnection() {
    localStorage.removeItem(CONNECTION_STORAGE_KEY);
    $("#connectionUrl").value = "";
    $("#connectionKey").value = "";
    setConnectionStatus("Conexão removida deste navegador.", "neutral");
    renderConnectionAuthState();
  }

  function toggleConnectionKeyVisibility() {
    const input = $("#connectionKey");
    const button = $("#toggleConnectionKey");
    if (!input || !button) return;
    const reveal = input.type === "password";
    input.type = reveal ? "text" : "password";
    button.setAttribute("aria-label", reveal ? "Ocultar chave" : "Mostrar chave");
  }

  async function loadSupabaseLibrary() {
    if (window.supabase?.createClient) return window.supabase;
    if (!window.__centralSupabaseLibraryPromise) {
      window.__centralSupabaseLibraryPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
        script.async = true;
        script.onload = () => window.supabase?.createClient
          ? resolve(window.supabase)
          : reject(new Error("A biblioteca do Supabase não foi carregada."));
        script.onerror = () => reject(new Error("Não foi possível carregar a biblioteca do Supabase."));
        document.head.appendChild(script);
      });
    }
    return window.__centralSupabaseLibraryPromise;
  }

  async function getSupabaseClient(connection = readConnection()) {
    if (!connection?.url || !connection?.apiKey) return null;
    
    const config = window.SUPABASE_CONFIG || {};
    if (window.AuthClient && connection.url === config.SUPABASE_URL && connection.apiKey === config.SUPABASE_ANON_KEY) {
      return window.AuthClient;
    }

    const api = await loadSupabaseLibrary();
    const fingerprint = `${connection.url}|${connection.apiKey}`;
    if (!supabaseClient || supabaseClientFingerprint !== fingerprint) {
      supabaseClient = api.createClient(connection.url, connection.apiKey, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
      });
      supabaseClientFingerprint = fingerprint;
    }
    return supabaseClient;
  }

  async function renderConnectionAuthState() {
    const status = $("#connectionAuthStatus");
    const signIn = $("#connectionSignInBtn");
    const signOut = $("#connectionSignOutBtn");
    if (!status || !signIn || !signOut) return;
    const connection = readConnection();
    if (!connection.url || !connection.apiKey) {
      status.textContent = "Salve a conexão para entrar.";
      signIn.hidden = false;
      signOut.hidden = true;
      return;
    }
    try {
      const client = await getSupabaseClient(connection);
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      const email = data.session?.user?.email;
      status.textContent = email ? `Sessão ativa: ${email}` : "Sem sessão iniciada.";
      signIn.hidden = Boolean(email);
      signOut.hidden = !email;
    } catch {
      status.textContent = "Não foi possível consultar a sessão.";
      signIn.hidden = false;
      signOut.hidden = true;
    }
  }

  async function signInToSupabase() {
    const button = $("#connectionSignInBtn");
    try {
      const connection = normalizeConnection();
      const email = $("#connectionEmail")?.value.trim().toLowerCase() || "";
      const password = $("#connectionPassword")?.value || "";
      if (!email || !password) throw new Error("Informe e-mail e senha para entrar.");
      localStorage.setItem(CONNECTION_STORAGE_KEY, JSON.stringify(connection));
      button.disabled = true;
      button.textContent = "Entrandoâ€¦";
      const client = await getSupabaseClient(connection);
      const { error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      $("#connectionPassword").value = "";
      await renderConnectionAuthState();
      setConnectionStatus("Sessão iniciada. Atualizando a carteira comercialâ€¦", "success");
      toast("Sessão iniciada. Carregando dadosâ€¦");
      setTimeout(() => location.reload(), 450);
    } catch (error) {
      setConnectionStatus(error.message || "Não foi possível iniciar a sessão.", "error");
    } finally {
      if (button) {
        button.disabled = false;
        button.textContent = "Entrar";
      }
    }
  }

  async function signOutFromSupabase() {
    try {
      const client = await getSupabaseClient();
      if (client) await client.auth.signOut();
      Store.reset();
      toast("Sessão encerrada.");
      setTimeout(() => location.reload(), 300);
    } catch (error) {
      setConnectionStatus(error.message || "Não foi possível encerrar a sessão.", "error");
    }
  }

  const categoryLabels = {
    CARCINICULTOR: "Carcinicultor",
    IRRIGACAO: "Irrigação",
    CONSTRUCAO_CIVIL: "Construção civil",
    MINERACAO: "Mineração",
    CONDOMINIAL: "Condominial",
    OUTRO: "Outro",
    PENDENTE_CLASSIFICACAO: "Outro"
  };

  function mapRemoteClient(row) {
    const category = categoryLabels[row.categoria] || "Outro";
    return {
      id: row.empresa_id,
      name: row.empresa || row.nome_fantasia || row.razao_social || "Empresa sem nome",
      company: row.razao_social || row.empresa || "",
      contact: row.contato_nome || "",
      phone: row.whatsapp || row.telefone || "",
      email: row.email || "",
      city: row.municipio || "Não informado",
      state: row.uf || "",
      segment: category,
      category,
      status: row.tipo_relacionamento === "CLIENTE" ? "Cliente" : "Lead",
      lat: row.latitude === null ? null : Number(row.latitude),
      lng: row.longitude === null ? null : Number(row.longitude),
      notes: row.observacao_localizacao || "",
      needs: [],
      createdAt: row.relacionamento_criado_em || new Date().toISOString(),
      ownerId: row.responsavel_por || "",
      attachments: [],
      remote: true
    };
  }

  function mapRemoteTrip(row) {
    const participantRows = Array.isArray(row?.participantes) ? row.participantes : [];
    const clientRows = Array.isArray(row?.empresas_planejadas) ? row.empresas_planejadas : [];
    const statusMap = {
      PLANEJADA: "Planejada",
      EM_ANDAMENTO: "Em andamento",
      CONCLUIDA: "Concluída",
      CANCELADA: "Cancelada"
    };
    const snapshotId = (item) => typeof item === "string" ? item : item?.id;

    return {
      id: row.viagem_id,
      name: row.titulo || "Viagem sem título",
      status: statusMap[row.status] || row.status || "Planejada",
      startDate: row.inicio_em ? String(row.inicio_em).slice(0, 10) : "",
      endDate: row.fim_em ? String(row.fim_em).slice(0, 10) : "",
      objective: row.observacao || "",
      notes: row.observacao || "",
      participantIds: participantRows.map(snapshotId).filter(Boolean),
      plannedClientIds: clientRows.map(snapshotId).filter(Boolean),
      participantSnapshots: participantRows,
      plannedClientSnapshots: clientRows,
      startKm: row.km_inicial === null ? null : Number(row.km_inicial),
      currentKm: row.km_final === null ? null : Number(row.km_final),
      endKm: row.km_final === null ? null : Number(row.km_final),
      stops: [],
      attachments: [],
      createdAt: row.criado_em || new Date().toISOString(),
      ownerId: "",
      remote: true
    };
  }

  function mapRemoteUser(row) {
    const name = row.nome || row.email || "Membro da equipe";
    return {
      id: row.usuario_id || row.membro_id,
      name,
      role: row.cargo || "Equipe Comercial",
      initials: initials(name),
      phone: "",
      email: row.email || "",
      active: row.ativo !== false,
      remote: true
    };
  }

  async function hydrateRemoteClients() {
    const connection = readConnection();
    if (!connection.url || !connection.apiKey) return { skipped: true };
    try {
      const client = await getSupabaseClient(connection);
      const { data: sessionData, error: sessionError } = await client.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) return { signedOut: true };
      const { data, error } = await client
        .schema("api")
        .from("vw_carteira_crm")
        .select("*")
        .order("empresa", { ascending: true });
      if (error) throw error;
      let remoteTrips = [];
      let tripError = null;
      const tripsResult = await client
        .schema("api")
        .from("vw_viagens")
        .select("*")
        .order("inicio_em", { ascending: true, nullsFirst: false })
        .order("criado_em", { ascending: false });
      if (tripsResult.error) {
        tripError = tripsResult.error;
        console.warn("[Central Comercial] A view de viagens ainda não está disponível:", tripError);
      } else {
        remoteTrips = (tripsResult.data || []).map(mapRemoteTrip);
      }
      let remoteUsers = [];
      const teamResult = await client
        .schema("api")
        .from("vw_equipe")
        .select("membro_id,usuario_id,nome,email,cargo,ativo")
        .order("nome", { ascending: true });
      if (teamResult.error) {
        // A carteira continua funcionando se o cadastro opcional da equipe
        // ainda não tiver sido executado no Supabase.
        console.warn("[Central Comercial] O cadastro da equipe ainda não está disponível:", teamResult.error);
      } else {
        remoteUsers = (teamResult.data || []).map(mapRemoteUser);
      }
      Store.setRemoteClients((data || []).map(mapRemoteClient), remoteTrips, remoteUsers);
      return {
        count: data?.length || 0,
        tripCount: remoteTrips.length,
        userCount: remoteUsers.length,
        tripError: tripError?.message || ""
      };
    } catch (error) {
      console.error("[Central Comercial] Falha ao carregar a carteira remota:", error);
      return { error: "A sessão está ativa, mas a leitura ainda não foi liberada. Execute o SQL 01 de conexão e exponha somente o schema api." };
    }
  }

  async function createRemoteTrip(payload) {
    const connection = readConnection();
    if (!connection.url || !connection.apiKey) {
      throw new Error("Configure a conexão do Supabase antes de salvar a viagem.");
    }
    const client = await getSupabaseClient(connection);
    const { data: sessionData, error: sessionError } = await client.auth.getSession();
    if (sessionError) throw sessionError;
    if (!sessionData.session) throw new Error("Entre no Supabase antes de salvar a viagem.");

    const { data, error } = await client.schema("api").rpc("criar_viagem", {
      p_titulo: payload.name,
      p_inicio: payload.startDate,
      p_fim: payload.endDate,
      p_observacao: payload.objective,
      p_participantes: payload.participants || [],
      p_clientes: payload.clients || []
    });
    if (error) {
      if (/criar_viagem|schema cache|PGRST202|function .* does not exist/i.test(error.message || "")) {
        throw new Error("A escrita de viagens ainda não foi ativada. Execute 04_api_escrita_viagens.sql no Supabase.");
      }
      throw new Error(error.message || "Não foi possível salvar a viagem no Supabase.");
    }
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.viagem_id) throw new Error("O Supabase não retornou a viagem criada.");
    return mapRemoteTrip(row);
  }

  // ------------------------------------------------------------------
  // Eventos remotos (via schema api â€” views e RPCs)
  // ------------------------------------------------------------------

  async function hydrateRemoteEvents() {
    const client = window.AuthClient;
    if (!client) return { skipped: true };
    try {
      const { data: eventos, error: evError } = await client
        .schema("api")
        .from("vw_eventos")
        .select("*")
        .order("data_inicio", { ascending: false });
      if (evError) throw evError;

      const { data: despesas, error: depError } = await client
        .schema("api")
        .from("vw_despesas_eventos")
        .select("*");
      if (depError) console.warn("[Central] Despesas de evento:", depError);

      const state = Store.getState();

      state.events = (eventos || []).map(row => ({
        id: row.evento_id,
        name: row.nome,
        location: row.local || "",
        startDate: row.data_inicio ? String(row.data_inicio).slice(0, 10) : "",
        endDate: row.data_fim ? String(row.data_fim).slice(0, 10) : "",
        status: row.status === "PLANEJADO" ? "Planejado" : row.status === "EM_ANDAMENTO" ? "Em andamento" : row.status === "REALIZADO" ? "Realizado" : row.status || "Planejado",
        role: row.tipo_participacao === "EXPOSITOR" ? "Expositor" : "Participante",
        notes: row.notas_estrategicas || "",
        participantIds: Array.isArray(row.participantes) ? row.participantes : (typeof row.participantes === "string" ? JSON.parse(row.participantes || "[]") : []),
        attachments: Array.isArray(row.anexos) ? row.anexos : (typeof row.anexos === "string" ? JSON.parse(row.anexos || "[]") : []),
        links: Array.isArray(row.links) ? row.links : (typeof row.links === "string" ? JSON.parse(row.links || "[]") : []),
        contacts: Array.isArray(row.contatos) ? row.contatos : (typeof row.contatos === "string" ? JSON.parse(row.contatos || "[]") : []),
        createdAt: row.criado_em || new Date().toISOString(),
        remote: true
      }));

      // Mescla despesas de eventos ao array global, preservando despesas de viagem
      const despesasViagem = (state.expenses || []).filter(e => e.tripId && !e.eventId);
      const despesasEvento = (despesas || []).map(row => ({
        id: row.despesa_id,
        eventId: row.evento_id,
        tripId: null,
        userId: row.criado_por || "",
        category: row.categoria || "Outros",
        costCenter: row.centro_custo || "",
        amount: Number(row.valor) || 0,
        place: row.estabelecimento || "",
        notes: row.descricao || "",
        date: row.data_despesa || row.criado_em || new Date().toISOString(),
        remote: true
      }));
      state.expenses = [...despesasViagem, ...despesasEvento];

      Store.setState(state);
      return { eventCount: state.events.length };
    } catch (err) {
      console.error("[Central] Falha ao carregar eventos remotos:", err);
      return { error: err.message };
    }
  }

  async function saveRemoteEvent(payload) {
    const client = window.AuthClient;
    if (!client) return null;
    try {
      const { data, error } = await client
        .schema("api")
        .rpc("criar_evento", {
          p_nome: payload.name,
          p_local: payload.location || "Não informado",
          p_data_inicio: payload.startDate || new Date().toISOString().slice(0, 10),
          p_data_fim: payload.endDate || payload.startDate || new Date().toISOString().slice(0, 10),
          p_tipo_participacao: payload.role === "Expositor" ? "EXPOSITOR" : "PARTICIPANTE",
          p_notas: payload.notes || null
        });
      if (error) throw error;
      const result = typeof data === "string" ? JSON.parse(data) : data;
      console.log("[Central] Evento salvo no Supabase:", result);
      return result?.evento_id || null;
    } catch (err) {
      console.warn("[Central] Evento não salvo no Supabase:", err);
      toast("O evento foi criado localmente mas não foi salvo no banco. Verifique o console.", "error");
      return null;
    }
  }

  async function saveRemoteExpense(payload) {
    const client = window.AuthClient;
    if (!client || !payload.eventId) return null;
    try {
      const { data, error } = await client
        .schema("api")
        .rpc("criar_despesa_evento", {
          p_evento_id: payload.eventId,
          p_categoria: payload.category || "Outros",
          p_valor: payload.amount || 0,
          p_estabelecimento: payload.place || null,
          p_descricao: payload.notes || null,
          p_centro_custo: payload.costCenter || null,
          p_data_despesa: payload.date ? payload.date.slice(0, 10) : new Date().toISOString().slice(0, 10)
        });
      if (error) throw error;
      const result = typeof data === "string" ? JSON.parse(data) : data;
      console.log("[Central] Despesa salva no Supabase:", result);
      return result?.despesa_id || null;
    } catch (err) {
      console.warn("[Central] Despesa não salva no Supabase:", err);
      alert("ERRO SUPABASE (Criar Despesa): " + (err.message || JSON.stringify(err)));
      return null;
    }
  }

  async function uploadToStorage(bucket, path, file) {
    const client = window.AuthClient;
    if (!client) return null;
    try {
      const { data, error } = await client.storage
        .from(bucket)
        .upload(path, file, { cacheControl: "3600", upsert: false });
      
      if (error) throw error;
      
      const { data: publicUrlData } = client.storage
        .from(bucket)
        .getPublicUrl(data.path);
        
      return publicUrlData.publicUrl;
    } catch (err) {
      console.error("[Central] Erro de upload:", err);
      return null;
    }
  }

  async function updateRemoteEventMedia(eventId, { links, attachments }) {
    const client = window.AuthClient;
    if (!client || !eventId) return null;
    try {
      const { data, error } = await client
        .schema("api")
        .rpc("atualizar_evento_midia", {
          p_evento_id: eventId,
          p_links: links || null,
          p_anexos: attachments || null
        });
      if (error) throw error;
      console.log("[Central] Evento atualizado com mídia:", data);
      return true;
    } catch (err) {
      console.error("[Central] Erro ao atualizar mídia do evento:", err);
      return false;
    }
  }

  function toggleDrawer(open) {
    const drawer = $("#mobileDrawer");
    if (!drawer) return;
    
    drawer.classList.toggle("open", open);
    
    if (open) {
      drawer.setAttribute("aria-hidden", "false");
      drawer.inert = false;
    } else {
      // Remove focus from any active element inside the drawer to prevent WAI-ARIA focus warnings
      if (document.activeElement && drawer.contains(document.activeElement)) {
        document.activeElement.blur();
      }
      drawer.setAttribute("aria-hidden", "true");
      drawer.inert = true;
    }
    
    document.body.classList.toggle("no-scroll", open);
  }

  function openSearch() {
    const dialog = $("#searchDialog");
    dialog.showModal();
    setTimeout(() => $("#globalSearchInput")?.focus(), 50);
    renderGlobalSearch("");
  }

  function renderGlobalSearch(query) {
    const q = query.trim().toLowerCase();
    const state = Store.getState();
    const items = [
      ...state.clients.map(c => ({ type: "Cliente", label: c.name, meta: `${c.city}, ${c.state}`, href: pageLink(`pages/cliente.html?id=${c.id}`) })),
      ...state.trips.map(t => ({ type: "Viagem", label: t.name, meta: t.status, href: pageLink(`pages/viagem.html?id=${t.id}`) })),
      ...state.users.map(u => ({ type: "Usuário", label: u.name, meta: u.role, href: pageLink("pages/usuarios.html") }))
    ].filter(item => !q || `${item.label} ${item.meta}`.toLowerCase().includes(q)).slice(0, 8);

    $("#globalSearchResults").innerHTML = items.length ? items.map(item => `
      <a class="search-result" href="${item.href}">
        <span><small>${item.type}</small><strong>${item.label}</strong><em>${item.meta}</em></span>${icon("chevron")}
      </a>`).join("") : `<div class="empty-state compact"><strong>Nenhum resultado</strong><span>Tente outro termo.</span></div>`;
  }

  document.addEventListener("input", (e) => {
    if (e.target.id === "globalSearchInput") renderGlobalSearch(e.target.value);
  });

  function toast(message, type = "success") {
    const region = $("#toastRegion");
    if (!region) return;
    const el = document.createElement("div");
    el.className = `toast ${type}`;
    el.innerHTML = `${icon(type === "success" ? "check" : "file", 18)}<span>${message}</span>`;
    region.appendChild(el);
    requestAnimationFrame(() => el.classList.add("show"));
    setTimeout(() => {
      el.classList.remove("show");
      setTimeout(() => el.remove(), 250);
    }, 2800);
  }

  function money(value) {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(value || 0));
  }

  function date(value, withTime = false) {
    if (!value) return "â€”";
    const d = new Date(value);
    const opts = withTime
      ? { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }
      : { day: "2-digit", month: "short", year: "numeric" };
    return new Intl.DateTimeFormat("pt-BR", opts).format(d);
  }

  function shortDate(value) {
    if (!value) return "â€”";
    return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short" }).format(new Date(`${value}T12:00:00`));
  }

  function initials(name = "") {
    return name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join("").toUpperCase();
  }

  function skeleton(lines = 5) {
    return `
      <div class="skeleton-wrap">
        <div class="skeleton skeleton-title"></div>
        ${Array.from({ length: lines }).map((_, i) => `<div class="skeleton skeleton-line" style="width:${86 - i * 7}%"></div>`).join("")}
      </div>`;
  }

  function decorateVisuals() {
    const visualIcons = ["users", "pin", "briefcase", "wallet", "chart", "route"];
    $$(".metric-card").forEach((card, index) => {
      if (!card.querySelector(".metric-watermark")) {
        const mark = document.createElement("span");
        mark.className = "metric-watermark";
        mark.innerHTML = icon(visualIcons[index % visualIcons.length], 34);
        card.appendChild(mark);
      }
      card.classList.add(`metric-tone-${(index % 4) + 1}`);
    });
    $$(".panel").forEach((panel, index) => panel.classList.add(`panel-tone-${(index % 4) + 1}`));
  }

  function loadingRender(renderFn, delay = 220) {
    const content = $("#pageContent");
    content.innerHTML = `<section class="content-section">${skeleton(6)}</section>`;
    setTimeout(() => {
      renderFn();
      decorateVisuals();
      requestAnimationFrame(() => content.classList.add("ready"));
      initRevealObserver();
    }, delay);
  }

  function statusBadge(status) {
    const key = String(status || "").toLowerCase().replace(/\s+/g, "-");
    return `<span class="badge badge-${key}">${status || "â€”"}</span>`;
  }

  function empty(title, description, actionHtml = "") {
    return `<div class="empty-state">${icon("file", 28)}<strong>${title}</strong><span>${description}</span>${actionHtml}</div>`;
  }

  let revealObserver;
  let revealMutationObserver;

  function observeRevealItems(parent = document) {
    const items = $$(".reveal:not(.observed)", parent);
    if (!("IntersectionObserver" in window)) {
      items.forEach(el => el.classList.add("observed", "in-view"));
      return;
    }

    revealObserver ||= new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          revealObserver.unobserve(entry.target);
        }
      });
    }, { rootMargin: "80px" });

    items.forEach(el => {
      el.classList.add("observed");
      revealObserver.observe(el);
    });
  }

  function initRevealObserver() {
    observeRevealItems();

    // Re-renderizações de filtros e modos de visualização também recebem
    // animação sem ficarem presos em opacity: 0.
    const pageContent = $("#pageContent");
    if (pageContent && !revealMutationObserver && "MutationObserver" in window) {
      revealMutationObserver = new MutationObserver(() => observeRevealItems(pageContent));
      revealMutationObserver.observe(pageContent, { childList: true, subtree: true });
    }
  }

  function registerServiceWorker() {
    const isLocalDevelopment = ["localhost", "127.0.0.1"].includes(location.hostname);
    if (isLocalDevelopment && "serviceWorker" in navigator) {
      navigator.serviceWorker.getRegistrations()
        .then((registrations) => registrations.forEach((registration) => registration.unregister()))
        .catch(() => { });
      return;
    }
    if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
      navigator.serviceWorker.register(`${root()}sw.js`).catch(() => { });
    }
  }

  function openDialog(id) {
    const dialog = document.getElementById(id);
    dialog?.showModal();
  }

  function closeDialog(id) {
    document.getElementById(id)?.close();
  }

  async function filesToAttachments(fileList) {
    const files = [...fileList];
    const output = [];
    for (const file of files) {
      const item = { name: file.name, type: file.type, size: file.size };
      const canPersistMedia = (file.type.startsWith("image/") || file.type.startsWith("video/")) && file.size <= 900 * 1024;
      if (canPersistMedia) {
        item.dataUrl = await new Promise((resolve) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = () => resolve(null);
          reader.readAsDataURL(file);
        });
      }
      output.push(item);
    }
    return output;
  }

  function loadLeaflet() {
    return new Promise((resolve, reject) => {
      if (window.L) return resolve(window.L);
      if (document.getElementById("leaflet-css")) return resolve(null);

      const css = document.createElement("link");
      css.id = "leaflet-css";
      css.rel = "stylesheet";
      css.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      css.crossOrigin = "";

      const script = document.createElement("script");
      script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
      script.crossOrigin = "";

      script.onload = () => resolve(window.L);
      script.onerror = reject;

      document.head.appendChild(css);
      document.head.appendChild(script);
    });
  }

  function initMaps() {
    const mapElements = $$(".leaflet-mini-map");
    if (!mapElements.length) return;

    loadLeaflet().then((L) => {
      if (!L) return;
      mapElements.forEach(el => {
        if (el._leaflet_id) return;
        
        const lat = parseFloat(el.dataset.lat);
        const lng = parseFloat(el.dataset.lng);
        const isManual = el.dataset.manual === "true";
        const hasCoords = !isNaN(lat) && !isNaN(lng);
        
        const center = hasCoords ? [lat, lng] : [-15.7801, -47.9292];
        const zoom = hasCoords ? 14 : 4;
        
        const map = L.map(el, {
          zoomControl: false,
          attributionControl: false,
          dragging: isManual,
          scrollWheelZoom: isManual,
          doubleClickZoom: isManual
        }).setView(center, zoom);
        
        L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png").addTo(map);

        const customIcon = L.divIcon({
          html: `<span style="color:var(--mais-red);display:block;filter:drop-shadow(0 4px 6px rgba(0,0,0,0.3));">${icon("pin", 32)}</span>`,
          className: 'custom-leaflet-pin',
          iconSize: [32, 32],
          iconAnchor: [16, 32]
        });

        if (hasCoords) {
          const marker = L.marker(center, { icon: customIcon }).addTo(map);
          el._marker = marker;
        }

        if (isManual) {
          const latInput = document.getElementById(el.dataset.latInput);
          const lngInput = document.getElementById(el.dataset.lngInput);
          map.on("click", (e) => {
            const { lat, lng } = e.latlng;
            if (latInput) latInput.value = lat.toFixed(5);
            if (lngInput) lngInput.value = lng.toFixed(5);
            if (el._marker) {
              el._marker.setLatLng([lat, lng]);
            } else {
              el._marker = L.marker([lat, lng], { icon: customIcon }).addTo(map);
            }
          });
          
          setTimeout(() => map.invalidateSize(), 150);
        }
      });
    }).catch(console.error);
  }

  function miniMap(lat, lng, label = "Localização registrada", linkUrl = null) {
    const inner = `
      <div class="mini-map leaflet-mini-map" data-lat="${lat}" data-lng="${lng}" aria-label="${label}" style="z-index:1; isolation:isolate; height: clamp(140px, 30vh, 220px);">
        ${!lat || !lng ? `<div class="map-caption" style="position:absolute;bottom:10px;left:10px;z-index:900;background:rgba(255,255,255,0.9);padding:5px 8px;border-radius:6px;box-shadow:var(--shadow-sm);">${icon("pin", 16)}<span>Sem coordenadas</span></div>` : ""}
      </div>`;
    
    return linkUrl 
      ? `<a href="${linkUrl}" class="mini-map-link" title="Abrir no Mapa Interativo" target="_blank" rel="noopener">${inner}</a>` 
      : inner;
  }

  function setupManualMap(mapEl, latInput, lngInput, onChange) {
    if (!mapEl) return;
    mapEl.classList.add("leaflet-mini-map");
    mapEl.dataset.manual = "true";
    mapEl.dataset.lat = latInput.value;
    mapEl.dataset.lng = lngInput.value;
    if (latInput.id) mapEl.dataset.latInput = latInput.id;
    if (lngInput.id) mapEl.dataset.lngInput = lngInput.id;
    
    initMaps();
  }

  async function deleteRemoteExpense(id) {
    const client = window.AuthClient;
    if (!client) return false;
    try {
      const { error } = await client.schema("api").rpc("deletar_despesa_evento", { p_despesa_id: id });
      if (error) throw error;
      return true;
    } catch (err) {
      console.warn("[Central] Erro ao deletar despesa:", err); alert("ERRO SUPABASE (Deletar Despesa): " + (err.message || JSON.stringify(err))); return false;
    }
  }

  async function updateRemoteExpense(id, payload) {
    const client = window.AuthClient;
    if (!client) return false;
    try {
      const updateData = {};
      if (payload.category !== undefined) updateData.categoria = payload.category;
      if (payload.amount !== undefined) updateData.valor = payload.amount;
      if (payload.place !== undefined) updateData.estabelecimento = payload.place;
      if (payload.notes !== undefined) updateData.descricao = payload.notes;
      if (payload.costCenter !== undefined) updateData.centro_custo = payload.costCenter;
      if (payload.date !== undefined) updateData.data_despesa = payload.date.slice(0, 10);
      
      if (Object.keys(updateData).length === 0) return true;

      const { error } = await client.schema("api").rpc("atualizar_despesa_evento", { p_despesa_id: id, p_categoria: updateData.categoria || null, p_valor: updateData.valor || null, p_estabelecimento: updateData.estabelecimento || null, p_descricao: updateData.descricao || null, p_data_despesa: updateData.data_despesa || null, p_centro_custo: updateData.centro_custo || null });
      if (error) throw error;
      return true;
    } catch (err) {
      console.warn("[Central] Erro ao atualizar despesa:", err); alert("ERRO SUPABASE (Atualizar Despesa): " + (err.message || JSON.stringify(err))); return false;
    }
  }

  async function updateRemoteEvent(id, payload) {
    const client = window.AuthClient;
    if (!client) return false;
    try {
      const updateData = {};
      if (payload.name !== undefined) updateData.nome = payload.name;
      if (payload.location !== undefined) updateData.local = payload.location;
      if (payload.startDate !== undefined) updateData.data_inicio = payload.startDate;
      if (payload.endDate !== undefined) updateData.data_fim = payload.endDate;
      if (payload.status !== undefined) {
        updateData.status = payload.status === "Planejado" ? "PLANEJADO" : payload.status === "Em andamento" ? "EM_ANDAMENTO" : "REALIZADO";
      }
      if (payload.role !== undefined) {
        updateData.tipo_participacao = payload.role === "Expositor" ? "EXPOSITOR" : "PARTICIPANTE";
      }
      if (payload.notes !== undefined) updateData.notas_estrategicas = payload.notes;
      if (payload.links !== undefined) updateData.links = payload.links;
      if (payload.contacts !== undefined) updateData.contatos = payload.contacts;
      if (payload.attachments !== undefined) updateData.anexos = payload.attachments;

      if (Object.keys(updateData).length === 0) return true;

      const { error } = await client.schema("api").from("vw_eventos").update(updateData).eq("evento_id", id);
      if (error) throw error;
      return true;
    } catch (err) {
      console.warn("[Central] Erro ao atualizar evento:", err); alert("ERRO SUPABASE (Atualizar Evento): " + (err.message || JSON.stringify(err))); return false;
    }
  }

  // ------------------------------------------------------------------
  // API operacional: Supabase e a fonte de verdade. O Store recebe apenas
  // respostas confirmadas pelo banco e funciona como cache de renderizacao.
  // ------------------------------------------------------------------
  const asArray = (value) => {
    if (Array.isArray(value)) return value;
    if (typeof value !== "string") return [];
    try { const parsed = JSON.parse(value); return Array.isArray(parsed) ? parsed : []; } catch { return []; }
  };
  const rpcValue = (value) => {
    const item = Array.isArray(value) ? value[0] : value;
    if (typeof item !== "string") return item || null;
    try { return JSON.parse(item); } catch { return null; }
  };
  const externalUrl = (value) => {
    try { const url = new URL(String(value || ""), location.origin); return ["https:", "http:"].includes(url.protocol) ? url.href : "#"; } catch { return "#"; }
  };
  const escape = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  async function operationalClient() {
    const client = window.AuthClient || await getSupabaseClient(readConnection());
    if (!client) throw new Error("Conexão do Supabase não configurada.");
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    if (!data.session) throw new Error("Sua sessão expirou. Entre novamente.");
    return client;
  }

  async function operationalRpc(name, args) {
    const client = await operationalClient();
    const { data, error } = await client.schema("api").rpc(name, args);
    if (error) throw new Error(error.message || "Falha ao salvar no Supabase.");
    return rpcValue(data);
  }

  const tripFromApi = (row) => {
    const value = mapRemoteTrip(row);
    value.stops = asArray(row.paradas);
    value.odometerRecords = asArray(row.odometro_registros);
    value.attachments = asArray(row.anexos);
    value.ownerId = row.criado_por || "";
    return value;
  };
  const visitFromApi = (row) => {
    const needs = asArray(row.necessidades);
    return { id: row.visita_id, clientId: row.empresa_id, tripId: row.viagem_id || null, userId: row.criado_por || "", type: row.tipo || "Acompanhamento", notes: row.observacao || "", needs: needs.map((need) => need.category || need), needRecords: needs, lat: row.latitude === null ? null : Number(row.latitude), lng: row.longitude === null ? null : Number(row.longitude), attachments: asArray(row.anexos), date: row.realizada_em || row.criado_em, remote: true };
  };
  const expenseFromApi = (row) => ({ id: row.despesa_id, tripId: row.viagem_id || null, eventId: row.evento_id || null, userId: row.criado_por || "", category: row.categoria || "Outros", costCenter: row.centro_custo || "", amount: Number(row.valor) || 0, place: row.estabelecimento || "", notes: row.descricao || "", attachments: asArray(row.anexos), date: row.data_despesa || row.criado_em, remote: true });
  const eventFromApi = (row) => ({ id: row.evento_id, name: row.nome || "Evento", location: row.local || "", startDate: row.data_inicio ? String(row.data_inicio).slice(0, 10) : "", endDate: row.data_fim ? String(row.data_fim).slice(0, 10) : "", status: ({ PLANEJADO: "Planejado", EM_ANDAMENTO: "Em andamento", REALIZADO: "Realizado", CANCELADO: "Cancelado" })[row.status] || row.status || "Planejado", role: row.tipo_participacao === "EXPOSITOR" ? "Expositor" : "Participante", notes: row.notas_estrategicas || "", participantIds: asArray(row.participantes), attachments: asArray(row.anexos), links: asArray(row.links), contacts: asArray(row.contatos), createdAt: row.criado_em, userId: row.criado_por || "", remote: true });

  async function hydrateSupabaseSnapshot() {
    try {
      const client = await operationalClient();
      const api = client.schema("api");
      const [clients, trips, visits, needs, expenses, events, users] = await Promise.all([
        api.from("vw_carteira_crm").select("*").order("empresa"),
        api.from("vw_viagens").select("*").order("inicio_em"),
        api.from("vw_visitas_crm").select("*").order("realizada_em", { ascending: false }),
        api.from("vw_necessidades").select("*").order("criado_em", { ascending: false }),
        api.from("vw_despesas_crm").select("*").order("data_despesa", { ascending: false }),
        api.from("vw_eventos").select("*").order("data_inicio", { ascending: false }),
        api.from("vw_equipe").select("*").order("nome")
      ]);
      // Cada tela deve continuar recebendo os dados da sua própria view. Uma
      // falha pontual, por exemplo em despesas, não pode impedir o detalhe de
      // um evento já disponível em vw_eventos de ser exibido.
      const results = [clients, trips, visits, needs, expenses, events, users];
      const failed = results.find((result) => result.error);
      if (failed) console.error("[Central] Uma ou mais views não puderam ser carregadas:", failed.error);
      const remoteClients = (clients.data || []).map(mapRemoteClient);
      (needs.data || []).forEach((row) => {
        const clientRow = remoteClients.find((item) => item.id === row.empresa_id);
        if (!clientRow) return;
        const need = { id: row.necessidade_id, clientId: row.empresa_id, visitId: row.visita_id, category: row.categoria, description: row.descricao, priority: row.prioridade, status: row.status, date: row.criado_em };
        clientRow.needRecords.push(need);
        if (!clientRow.needs.includes(need.category)) clientRow.needs.push(need.category);
      });
      const remoteUsers = (users.data || []).map((row) => {
        const name = row.nome || row.email || "Membro da equipe";
        return { id: row.usuario_id || row.membro_id, name, role: row.cargo || row.papel || "Equipe Comercial", initials: initials(name), email: row.email || "", active: row.ativo !== false, remote: true };
      });
      Store.setRemoteSnapshot({ clients: remoteClients, trips: (trips.data || []).map(tripFromApi), visits: (visits.data || []).map(visitFromApi), expenses: (expenses.data || []).map(expenseFromApi), events: (events.data || []).map(eventFromApi), users: remoteUsers, activities: [] });
      return { count: remoteClients.length };
    } catch (error) {
      console.error("[Central] Falha no retrato remoto:", error);
      return { error: error.message || "Não foi possível carregar o Supabase." };
    }
  }

  const createSupabaseClientRecord = async (payload) => mapRemoteClient(await operationalRpc("cadastrar_cliente", { p_dados: payload }));
  const updateSupabaseClientRecord = async (id, payload) => await operationalRpc("atualizar_comunicacao", { p_cliente_id: id, p_dados: payload });
  const archiveSupabaseClientRecord = async (id) => operationalRpc("arquivar_cliente", { p_cliente_id: id });
  const createSupabaseVisit = async (payload) => visitFromApi(await operationalRpc("criar_visita", { p_dados: payload }));
  const createSupabaseNeed = async (payload) => operationalRpc("criar_necessidade", { p_dados: payload });
  const createSupabaseTrip = async (payload) => tripFromApi(await operationalRpc("criar_viagem", { p_titulo: payload.name, p_inicio: payload.startDate, p_fim: payload.endDate, p_observacao: payload.objective, p_participantes: payload.participants || [], p_clientes: payload.clients || [] }));
  const updateSupabaseTrip = async (id, payload) => await operationalRpc("atualizar_viagem", { p_viagem_id: id, p_dados: payload });
  const deleteSupabaseTrip = async (id) => operationalRpc("excluir_viagem", { p_viagem_id: id });
  const createSupabaseExpense = async (payload) => expenseFromApi(await operationalRpc("criar_despesa", { p_dados: payload }));
  const updateSupabaseExpense = async (id, payload) => await operationalRpc("atualizar_despesa", { p_despesa_id: id, p_dados: payload });
  const deleteSupabaseExpense = async (id) => operationalRpc("excluir_despesa", { p_despesa_id: id });
  const createSupabaseEvent = async (payload) => eventFromApi(await operationalRpc("criar_evento", { p_nome: payload.name, p_local: payload.location || null, p_data_inicio: payload.startDate, p_data_fim: payload.endDate || payload.startDate, p_tipo_participacao: payload.role === "Expositor" ? "EXPOSITOR" : "PARTICIPANTE", p_notas: payload.notes || null }));
  const updateSupabaseEvent = async (id, payload) => await operationalRpc("atualizar_evento", { p_evento_id: id, p_dados: payload });
  const deleteSupabaseEvent = async (id) => operationalRpc("excluir_evento", { p_evento_id: id });

  async function uploadPrivateFile(path, file) {
    const client = await operationalClient();
    if (!file || file.size > 20 * 1024 * 1024) throw new Error("O anexo deve ter no máximo 20 MB.");
    const { data, error } = await client.storage.from("crm-anexos").upload(path, file, { cacheControl: "3600", upsert: false, contentType: file.type || undefined });
    if (error) throw new Error(error.message || "Falha ao enviar o anexo.");
    const { data: signed, error: signedError } = await client.storage.from("crm-anexos").createSignedUrl(data.path, 3600);
    if (signedError) throw new Error(signedError.message || "Falha ao assinar o anexo.");
    return { bucket: "crm-anexos", path: data.path, url: signed.signedUrl };
  }

  return {
    $, $$, icon, root, pageLink, mountShell, toast, money, date, shortDate, initials,
    skeleton, loadingRender, statusBadge, empty, openDialog, closeDialog,
    filesToAttachments, miniMap, setupManualMap, initMaps, initRevealObserver, decorateVisuals,
    hydrateRemoteClients, createRemoteTrip,
    hydrateRemoteEvents, saveRemoteEvent, saveRemoteExpense, deleteRemoteExpense, updateRemoteExpense, updateRemoteEvent,
    uploadToStorage, updateRemoteEventMedia,
    escape, externalUrl, hydrateSupabaseSnapshot,
    createSupabaseClientRecord, updateSupabaseClientRecord, archiveSupabaseClientRecord,
    createSupabaseVisit, createSupabaseNeed,
    createSupabaseTrip, updateSupabaseTrip, deleteSupabaseTrip,
    createSupabaseExpense, updateSupabaseExpense, deleteSupabaseExpense,
    createSupabaseEvent, updateSupabaseEvent, deleteSupabaseEvent,
    uploadPrivateFile
  };
})();


