/*
 * Auth Guard — roda antes de qualquer módulo de página.
 *
 * Responsabilidades:
 * 1. Verificar se SUPABASE_CONFIG está configurado
 * 2. Verificar sessão ativa via Supabase Auth
 * 3. Se não autenticado → redireciona para login.html
 * 4. Se autenticado → expõe window.AuthUser e window.AuthClient
 * 5. Detecta se o usuário é admin
 */
window.__authGuardReady = (async () => {
  const config = window.SUPABASE_CONFIG || {};
  const isSubpage = location.pathname.includes("/pages/");
  const loginPath = isSubpage ? "../login.html" : "login.html";

  // If Supabase is not configured, redirect to login (which will show config error)
  if (!config.SUPABASE_URL || !config.SUPABASE_ANON_KEY) {
    window.location.replace(loginPath);
    // Block further execution
    await new Promise(() => {});
  }

  // Load Supabase library
  async function loadLib() {
    if (window.supabase?.createClient) return window.supabase;
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
      script.async = true;
      script.onload = () => window.supabase?.createClient
        ? resolve(window.supabase)
        : reject(new Error("Supabase library failed"));
      script.onerror = () => reject(new Error("Supabase library failed"));
      document.head.appendChild(script);
    });
  }

  try {
    const lib = await loadLib();
    const client = lib.createClient(config.SUPABASE_URL, config.SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });

    const { data, error } = await client.auth.getSession();

    if (error || !data.session?.user) {
      window.location.replace(loginPath);
      await new Promise(() => {});
    }

    const user = data.session.user;
    const email = (user.email || "").toLowerCase();
    const adminEmails = (config.ADMIN_EMAILS || []).map(e => e.toLowerCase().trim());
    const isAdmin = adminEmails.includes(email);

    // Extract display name from email or user metadata
    const metaName = user.user_metadata?.full_name || user.user_metadata?.name || "";
    const displayName = metaName || email.split("@")[0].replace(/[._]/g, " ").replace(/\b\w/g, c => c.toUpperCase());
    const initials = displayName.split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]).join("").toUpperCase() || "U";

    // Expose globally
    window.AuthUser = Object.freeze({
      id: user.id,
      email,
      name: displayName,
      initials,
      isAdmin,
      session: data.session
    });

    window.AuthClient = client;

    // Also ensure localStorage connection is in sync (for backward compat with ui.js)
    localStorage.setItem("mais_hidro_supabase_connection_v1", JSON.stringify({
      url: config.SUPABASE_URL,
      apiKey: config.SUPABASE_ANON_KEY
    }));

    return { user: window.AuthUser, client };

  } catch (err) {
    console.error("[Auth Guard]", err);
    window.location.replace(loginPath);
    await new Promise(() => {});
  }
})();
