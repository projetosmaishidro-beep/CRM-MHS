document.addEventListener("DOMContentLoaded", async () => {
  if (window.__authGuardReady) {
    try {
      await window.__authGuardReady;
    } catch {
      return; // O redirecionamento já ocorreu no auth-guard
    }
  }
  UI.mountShell();

  // O Store recebe apenas o retrato remoto do schema api.
  const remote = await UI.hydrateSupabaseSnapshot?.();
  if (remote?.error) UI.toast(remote.error, "error");

  const page = document.body.dataset.page;
  const module = window.PageModules?.[page];
  if (module?.init) UI.loadingRender(() => module.init());
  else UI.$("#pageContent").innerHTML = `<section class="content-section">${UI.empty("Página não configurada", "O módulo desta página não foi encontrado.")}</section>`;
});
