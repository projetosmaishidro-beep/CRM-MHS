document.addEventListener("DOMContentLoaded", async () => {
  if (window.__authGuardReady) {
    try {
      await window.__authGuardReady;
    } catch {
      return; // O redirecionamento já ocorreu no auth-guard
    }
  }
  UI.mountShell();

  // O Store recebe apenas o retrato remoto do schema api. A página só é
  // desenhada com os dados em mãos: abrir antes mostraria um CRM vazio que
  // não se atualiza sozinho. Cargas lentas exibem um aviso e continuam; o
  // limite final existe apenas para uma rede que deixou de responder.
  const remoteLoad = UI.hydrateSupabaseSnapshot?.() || Promise.resolve({});
  const slowNotice = setTimeout(() => UI.toast("Carregando um volume grande de dados. Aguarde…"), 8000);
  const remote = await Promise.race([
    remoteLoad,
    new Promise((resolve) => setTimeout(() => resolve({ error: "O Supabase não respondeu. Verifique sua conexão e atualize a página." }), 120000))
  ]);
  clearTimeout(slowNotice);
  if (remote?.error) UI.toast(remote.error, "error");
  if (remote?.warning) UI.toast(remote.warning, "error");

  // Dados mais novos chegaram em segundo plano (o cache já foi atualizado).
  window.addEventListener("api:snapshot-updated", () => {
    UI.toast("Há atualizações da equipe. Atualize a página para vê-las.");
  });

  const page = document.body.dataset.page;
  const module = window.PageModules?.[page];
  if (module?.init) UI.loadingRender(() => module.init());
  else UI.$("#pageContent").innerHTML = `<section class="content-section">${UI.empty("Página não configurada", "O módulo desta página não foi encontrado.")}</section>`;
});
