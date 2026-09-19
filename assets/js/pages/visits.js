window.PageModules = window.PageModules || {};
window.PageModules.visits = {
  init() {
    const state = Store.getState();
    const sorted = [...state.visits].sort((a,b) => new Date(b.date)-new Date(a.date));

    UI.$("#pageContent").innerHTML = `
      <section class="metric-grid reveal">
        <article class="metric-card"><span>Total de visitas</span><strong>${state.visits.length}</strong><small>Histórico local</small></article>
        <article class="metric-card"><span>Prospecções</span><strong>${state.visits.filter(v => v.type === "Prospecção").length}</strong><small>Registros de abertura</small></article>
        <article class="metric-card"><span>Com viagem</span><strong>${state.visits.filter(v => v.tripId).length}</strong><small>Relacionadas a roteiro</small></article>
        <article class="metric-card"><span>Leads ativos</span><strong>${state.clients.filter(c => c.status === "Lead" || c.status === "Prospect").length}</strong><small>Oportunidades abertas</small></article>
      </section>

      <section class="panel visits-history-panel reveal">
        <div class="panel-head visits-history-head"><div><span class="eyebrow">Histórico recente</span><h3>Últimas visitas</h3></div><a class="btn btn-primary btn-small" href="${UI.pageLink("pages/nova-visita.html")}">${UI.icon("plus", 17)} Nova visita</a></div>
        <div class="visit-list">
          ${sorted.map(v => {
            const client = state.clients.find(c => c.id === v.clientId);
            const user = state.users.find(u => u.id === v.userId);
            const trip = state.trips.find(t => t.id === v.tripId);
            return `
              <a class="visit-row" href="${UI.pageLink(`pages/cliente.html?id=${client?.id || ""}`)}">
                <span class="visit-icon">${UI.icon("pin")}</span>
                <div class="visit-main"><div class="row-inline"><strong>${client?.name || "Cliente"}</strong>${UI.statusBadge(v.type)}</div><p>${v.notes}</p><small>${user?.name || "Usuário"}${trip ? ` · ${trip.name}` : ""}</small></div>
                <div class="visit-date"><strong>${UI.date(v.date)}</strong>${UI.icon("chevron")}</div>
              </a>`;
          }).join("")}
        </div>
      </section>
    `;
  }
};
