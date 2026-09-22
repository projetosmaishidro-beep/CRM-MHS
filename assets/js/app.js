document.addEventListener("DOMContentLoaded", async () => {
  if (window.__authGuardReady) {
    try {
      await window.__authGuardReady;
    } catch {
      return; // O redirecionamento já ocorreu no auth-guard
    }
  }
  UI.mountShell();

  // O Store recebe apenas o retrato remoto do schema api. A interface não
  // pode permanecer bloqueada indefinidamente quando a rede ou uma view não
  // responde; nesse caso, a página abre com um aviso explícito.
  const remoteLoad = UI.hydrateSupabaseSnapshot?.() || Promise.resolve({});
  const remote = await Promise.race([
    remoteLoad,
    new Promise((resolve) => setTimeout(() => resolve({ error: "O Supabase demorou para responder. Verifique sua conexão e atualize a página." }), 15000))
  ]);
  if (remote?.error) UI.toast(remote.error, "error");
  if (remote?.warning) UI.toast(remote.warning, "error");

  const page = document.body.dataset.page;
  const module = window.PageModules?.[page];
  if (module?.init) UI.loadingRender(() => module.init());
  else UI.$("#pageContent").innerHTML = `<section class="content-section">${UI.empty("Página não configurada", "O módulo desta página não foi encontrado.")}</section>`;
});
