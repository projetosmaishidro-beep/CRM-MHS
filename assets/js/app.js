document.addEventListener("DOMContentLoaded", async () => {
  if (window.__authGuardReady) {
    try {
      await window.__authGuardReady;
    } catch {
      return; // O redirecionamento já ocorreu no auth-guard
    }
  }
  UI.mountShell();

  // Hidrata clientes e viagens do schema api
  const remote = await UI.hydrateRemoteClients?.();
  if (remote?.error) UI.toast(remote.error, "error");
  if (remote?.tripError) UI.toast("A persistência de viagens ainda não foi ativada. Execute o SQL 04 da conexão de aplicativos.", "error");

  // Hidrata eventos e despesas do schema crm (em paralelo, sem bloquear a UI)
  UI.hydrateRemoteEvents?.().then(result => {
    if (result?.error) console.warn("[Central] Eventos remotos:", result.error);
  });

  const page = document.body.dataset.page;
  const module = window.PageModules?.[page];
  if (module?.init) UI.loadingRender(() => module.init());
  else UI.$("#pageContent").innerHTML = `<section class="content-section">${UI.empty("Página não configurada", "O módulo desta página não foi encontrado.")}</section>`;
});

