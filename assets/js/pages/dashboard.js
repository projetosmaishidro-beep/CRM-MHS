window.PageModules = window.PageModules || {};
window.PageModules.dashboard = {
  init() {
    const state = Store.getState();
    const activeTrips = state.trips.filter(t => t.status === "Em andamento");
    const visitsThisMonth = state.visits.filter(v => {
      const d = new Date(v.date), now = new Date();
      return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    });
    const leads = state.clients.filter(c => c.status === "Lead" || c.status === "Prospect");
    const activeTrip = activeTrips[0];

    UI.$("#pageContent").innerHTML = `
      <section class="metric-grid reveal">
        <article class="metric-card"><span>Clientes</span><strong>${state.clients.length}</strong><small>${leads.length} oportunidades abertas</small></article>
        <article class="metric-card"><span>Visitas no mês</span><strong>${visitsThisMonth.length}</strong><small>${state.visits.length} no histórico</small></article>
        <article class="metric-card"><span>Viagens ativas</span><strong>${activeTrips.length}</strong><small>${state.trips.filter(t => t.status === "Planejada").length} planejada(s)</small></article>
        <article class="metric-card"><span>Gastos em viagens</span><strong>${UI.money(state.expenses.reduce((s, e) => s + Number(e.amount), 0))}</strong><small>Registros consolidados no banco</small></article>
      </section>

      <section class="two-col reveal">
        <div class="panel">
          <div class="panel-head"><div><span class="eyebrow">Prioridade</span><h3>Viagem em andamento</h3></div><a class="text-link" href="${UI.pageLink("pages/viagens.html")}">Ver todas ${UI.icon("arrow", 16)}</a></div>
          ${activeTrip ? `
            <a class="trip-focus" href="${UI.pageLink(`pages/viagem.html?id=${activeTrip.id}`)}">
              <div class="trip-focus-top"><span>${UI.statusBadge(activeTrip.status)}</span><small>${UI.shortDate(activeTrip.startDate)} → ${UI.shortDate(activeTrip.endDate)}</small></div>
              <h4>${activeTrip.name}</h4>
              <p>${activeTrip.objective}</p>
              <div class="trip-stats show-mobile" style="margin-top: 15px;"><span><small>Visitas</small><strong>${activeTrip.stops.filter(s => s.done).length}</strong></span><span><small>KM rodados</small><strong>${activeTrip.currentKm && activeTrip.startKm ? activeTrip.currentKm - activeTrip.startKm : 0}</strong></span><span><small>Participantes</small><strong>${activeTrip.participantIds ? activeTrip.participantIds.length : 1}</strong></span></div>
              <div class="progress-row hide-mobile"><span><b>${activeTrip.stops.filter(s => s.done).length}</b> de ${activeTrip.stops.length} paradas concluídas</span><strong>${Math.round((activeTrip.stops.filter(s => s.done).length / Math.max(activeTrip.stops.length, 1)) * 100)}%</strong></div>
              <div class="progress hide-mobile"><span style="width:${(activeTrip.stops.filter(s => s.done).length / Math.max(activeTrip.stops.length, 1)) * 100}%"></span></div>
            </a>` : UI.empty("Nenhuma viagem em andamento", "Planeje uma viagem para começar.")}
        </div>

        <div class="panel">
          <div class="panel-head"><div><span class="eyebrow">Atividade</span><h3>Últimos registros</h3></div></div>
          <div class="timeline compact">
            ${state.activities.slice(0, 5).map(a => {
              const user = state.users.find(u => u.id === a.userId);
              return `<div class="timeline-item"><span class="avatar mini">${user?.initials || "?"}</span><div><strong>${user?.name || "Usuário"}</strong><p>${a.text}</p><small>${UI.date(a.date, true)}</small></div></div>`;
            }).join("")}
          </div>
        </div>
      </section>

      <section class="panel reveal">
        <div class="panel-head"><div><span class="eyebrow">Acesso rápido</span><h3>Continue de onde parou</h3></div></div>
        <div class="shortcut-grid">
          <a class="shortcut" href="${UI.pageLink("pages/clientes.html")}">${UI.icon("users")}<span><strong>Clientes</strong><small>Perfis e histórico</small></span>${UI.icon("chevron")}</a>
          <a class="shortcut" href="${UI.pageLink("pages/nova-visita.html")}">${UI.icon("pin")}<span><strong>Registrar visita</strong><small>Cliente ou novo lead</small></span>${UI.icon("chevron")}</a>
          <a class="shortcut" href="${UI.pageLink("pages/financeiro.html")}">${UI.icon("receipt")}<span><strong>Nova despesa</strong><small>Com comprovante</small></span>${UI.icon("chevron")}</a>
          <a class="shortcut" href="${UI.pageLink("pages/relatorios.html")}">${UI.icon("chart")}<span><strong>Relatórios</strong><small>Consolidação comercial</small></span>${UI.icon("chevron")}</a>
        </div>
      </section>
    `;
  }
};
