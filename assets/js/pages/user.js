window.PageModules = window.PageModules || {};
window.PageModules.user = {
  init() {
    const state = Store.getState();
    const id = new URLSearchParams(location.search).get("id");
    const user = state.users.find(u => u.id === id) || state.users[0];
    const trips = state.trips.filter(t => t.participantIds.includes(user.id));
    const visits = state.visits.filter(v => v.userId === user.id).sort((a,b)=>new Date(b.date)-new Date(a.date));
    const expenses = state.expenses.filter(e => e.userId === user.id);
    const activities = state.activities.filter(a => a.userId === user.id).sort((a,b)=>new Date(b.date)-new Date(a.date));

    UI.$("#pageContent").innerHTML = `
      <section class="profile-hero reveal">
        <div class="profile-main">

          <div class="profile-title-row">
            <span class="avatar xl">${user.initials}</span>
            <div><div class="title-inline"><h2>${user.name}</h2><span class="badge badge-cliente">Ativo</span></div><p>${user.role}</p><span class="muted">${user.email} · ${user.phone}</span></div>
          </div>
        </div>
      </section>

      <section class="metric-grid reveal">
        <article class="metric-card"><span>Viagens</span><strong>${trips.length}</strong><small>Participações registradas</small></article>
        <article class="metric-card"><span>Visitas</span><strong>${visits.length}</strong><small>Registros em campo</small></article>
        <article class="metric-card"><span>Despesas</span><strong>${expenses.length}</strong><small>${UI.money(expenses.reduce((s,e)=>s+Number(e.amount),0))}</small></article>
        <article class="metric-card"><span>Atividades</span><strong>${activities.length}</strong><small>Eventos no histórico</small></article>
      </section>

      <section class="detail-grid reveal">
        <div class="panel span-2">
          <div class="panel-head"><div><span class="eyebrow">Histórico individual</span><h3>Atividades recentes</h3></div></div>
          <div class="timeline compact">
            ${activities.length ? activities.map(a => `<div class="timeline-item"><span class="avatar mini">${user.initials}</span><div><strong>${user.name}</strong><p>${a.text}</p><small>${UI.date(a.date,true)}</small></div></div>`).join("") : UI.empty("Sem atividades", "Os próximos registros deste usuário aparecerão aqui.")}
          </div>
        </div>
        <div class="panel">
          <div class="panel-head"><div><span class="eyebrow">Viagens</span><h3>Participações</h3></div></div>
          <div class="mini-list">
            ${trips.length ? trips.map(t => `<a href="${UI.pageLink(`pages/viagem.html?id=${t.id}`)}"><span class="mini-icon">${UI.icon("briefcase",15)}</span><span><strong>${t.name}</strong><small>${t.status} · ${UI.shortDate(t.startDate)}</small></span></a>`).join("") : `<span class="muted">Nenhuma viagem vinculada.</span>`}
          </div>
        </div>
      </section>

      <section class="panel reveal">
        <div class="panel-head"><div><span class="eyebrow">Clientes atendidos</span><h3>Visitas realizadas</h3></div></div>
        <div class="visit-list">
          ${visits.length ? visits.map(v => {
            const client = state.clients.find(c => c.id === v.clientId);
            return `<a class="visit-row" href="${UI.pageLink(`pages/cliente.html?id=${client?.id||""}`)}"><span class="visit-icon">${UI.icon("pin")}</span><div class="visit-main"><div class="row-inline"><strong>${client?.name||"Cliente"}</strong>${UI.statusBadge(v.type)}</div><p>${v.notes}</p><small>${UI.date(v.date,true)}</small></div><div class="visit-date">${UI.icon("chevron")}</div></a>`;
          }).join("") : UI.empty("Sem visitas", "Nenhuma visita realizada por este usuário.")}
        </div>
      </section>
    `;
  }
};
