window.PageModules = window.PageModules || {};
window.PageModules.users = {
  init() {
    const state = Store.getState();
    UI.$("#pageContent").innerHTML = `
      <section class="user-grid reveal">
        ${state.users && state.users.length ? state.users.map(u => {
          const trips = state.trips.filter(t => t.participantIds.includes(u.id));
          const visits = state.visits.filter(v => v.userId === u.id);
          const expenses = state.expenses.filter(e => e.userId === u.id);
          return `<a class="user-card" href="${UI.pageLink(`pages/usuario.html?id=${u.id}`)}" style="display:flex; flex-direction:column; gap:18px;">
            <div style="display:flex; gap:14px; align-items:center;">
              <div style="position:relative;">
                <span class="avatar xl" style="margin:0; box-shadow:0 4px 12px rgba(0,0,0,0.05);">${u.initials}</span>
                <span class="status-dot" style="position:absolute; bottom:2px; right:0; width:12px; height:12px;"></span>
              </div>
              <div style="overflow:hidden;">
                <h3 style="margin:0 0 2px; font-size:17px; white-space:nowrap; text-overflow:ellipsis; overflow:hidden;">${u.name}</h3>
                <p style="margin:0; color:var(--muted); font-size:12px;">${u.role}</p>
                <div style="display:flex; gap:6px; margin-top:4px; font-size:11px; color:#64748b;">
                  <span style="white-space:nowrap; text-overflow:ellipsis; overflow:hidden;">${u.email}</span>
                </div>
              </div>
            </div>
            
            <div style="display:flex; justify-content:space-between; background:#f8fafc; border-radius:12px; padding:12px; border:1px solid #e2e8f0; box-shadow:inset 0 1px 2px rgba(0,0,0,0.02);">
              <div style="text-align:center; flex:1; border-right:1px solid #e2e8f0;">
                <strong style="display:block; font-size:17px; color:var(--mais-navy);">${trips.length}</strong>
                <small style="color:#64748b; font-size:9.5px; font-weight:800; letter-spacing:0.5px;">VIAGENS</small>
              </div>
              <div style="text-align:center; flex:1; border-right:1px solid #e2e8f0;">
                <strong style="display:block; font-size:17px; color:var(--mais-navy);">${visits.length}</strong>
                <small style="color:#64748b; font-size:9.5px; font-weight:800; letter-spacing:0.5px;">VISITAS</small>
              </div>
              <div style="text-align:center; flex:1;">
                <strong style="display:block; font-size:17px; color:var(--mais-navy);">${expenses.length}</strong>
                <small style="color:#64748b; font-size:9.5px; font-weight:800; letter-spacing:0.5px;">GASTOS</small>
              </div>
            </div>

            <div style="border-top:1px dashed #cbd5e1; padding-top:14px;">
              <small style="display:block; color:#94a3b8; font-weight:800; font-size:9.5px; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:8px;">Última movimentação</small>
              ${state.activities.filter(a=>a.userId===u.id).slice(0,1).map(a=>`<div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px; font-size:11px; color:#334155;"><span style="line-height:1.4;">${a.text}</span><span style="white-space:nowrap; color:#94a3b8;">${UI.shortDate(a.date)}</span></div>`).join("") || `<span style="font-size:11px; color:#94a3b8;">Sem atividade recente no sistema.</span>`}
            </div>
          </a>`;
        }).join("") : UI.empty("Nenhum usuário", "A equipe comercial ainda não possui usuários cadastrados na base de dados.")}
      </section>
    `;
  }
};
