window.PageModules = window.PageModules || {};
window.PageModules.reports = {
  init() {
    const state = Store.getState();
    const container = UI.$("#pageContent");

    const headerHtml = `
      <div class="form-page-head" style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom: 20px; flex-wrap: wrap; gap: 15px;">
        <div>
          <span class="eyebrow">Análise de Dados</span>
          <h2>Relatórios e Auditoria</h2>
        </div>
        <div class="field" style="max-width: 320px; width: 100%; margin: 0;">
          <select id="reportContextSelect" class="select-compact">
            <option value="ALL">Visão Geral da Empresa</option>
            <optgroup label="Relatório Individual de Viagem">
              ${state.trips.map(t => `<option value="${t.id}">${t.name} (${t.status})</option>`).join("")}
            </optgroup>
          </select>
        </div>
      </div>
      <div id="reportContainer"></div>
    `;
    container.innerHTML = headerHtml;

    const reportContainer = UI.$("#reportContainer");
    const select = UI.$("#reportContextSelect");

    function renderGeneral() {
      const totalExpenses = state.expenses.reduce((s,e)=>s+Number(e.amount),0);
      const km = state.trips.reduce((sum,t) => {
        const records = t.odometerRecords || [];
        const tkm = records.length >= 2 ? Math.max(...records.map(r=>r.km)) - Math.min(...records.map(r=>r.km)) : (t.startKm && t.currentKm ? t.currentKm - t.startKm : 0);
        return sum + tkm;
      }, 0);
      const visitsByUser = state.users.map(u => ({
        user: u,
        visits: state.visits.filter(v => v.userId === u.id).length,
        trips: state.trips.filter(t => t.participantIds.includes(u.id)).length
      }));
      const maxVisits = Math.max(...visitsByUser.map(x=>x.visits), 1);

      reportContainer.innerHTML = `
        <section class="metric-grid reveal">
          <article class="metric-card"><span>Clientes cadastrados</span><strong>${state.clients.length}</strong><small>${state.clients.filter(c=>c.status==="Cliente").length} ativos</small></article>
          <article class="metric-card"><span>Visitas registradas</span><strong>${state.visits.length}</strong><small>${state.visits.filter(v=>v.type==="Prospecção").length} prospecções</small></article>
          <article class="metric-card"><span>Km registrados</span><strong>${km.toFixed(1)}</strong><small>Total rodado</small></article>
          <article class="metric-card"><span>Gasto acumulado</span><strong>${UI.money(totalExpenses)}</strong><small>${state.expenses.length} lançamentos</small></article>
        </section>

        <section class="report-grid reveal">
          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Atividade por usuário</span><h3>Visitas registradas</h3></div></div>
            <div class="bar-chart">
              ${visitsByUser.map(item => `<div class="bar-row"><span class="avatar mini">${item.user.initials}</span><div><div class="bar-label"><strong>${item.user.name}</strong><span>${item.visits}</span></div><div class="progress"><span style="width:${item.visits/maxVisits*100}%"></span></div></div></div>`).join("")}
            </div>
          </div>

          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Pipeline simples</span><h3>Situação dos contatos</h3></div></div>
            <div class="donut-summary">
              ${["Cliente","Lead","Prospect"].map(status => {
                const n = state.clients.filter(c=>c.status===status).length;
                const pct = Math.round(n/Math.max(state.clients.length,1)*100);
                return `<div><span class="donut-dot"></span><span><strong>${status}</strong><small>${n} registros</small></span><b>${pct}%</b></div>`;
              }).join("")}
            </div>
          </div>

          <div class="panel span-2">
            <div class="panel-head"><div><span class="eyebrow">Viagens</span><h3>Resumo operacional</h3></div><button class="btn btn-secondary btn-small" id="exportCsvBtn">${UI.icon("file", 17)} Exportar CSV</button></div>
            <div class="table-wrap"><table>
              <thead><tr><th>Viagem</th><th>Status</th><th>Participantes</th><th>Visitas</th><th>Km</th><th>Gastos</th></tr></thead>
              <tbody>${state.trips.map(t => {
                const visits = state.visits.filter(v=>v.tripId===t.id).length;
                const expenses = state.expenses.filter(e=>e.tripId===t.id).reduce((s,e)=>s+Number(e.amount),0);
                const records = t.odometerRecords || [];
                const tkm = records.length >= 2 ? Math.max(...records.map(r=>r.km)) - Math.min(...records.map(r=>r.km)) : (t.startKm && t.currentKm ? t.currentKm-t.startKm : 0);
                return `<tr><td><a href="${UI.pageLink(`pages/viagem.html?id=${t.id}`)}"><strong>${t.name}</strong></a></td><td>${UI.statusBadge(t.status)}</td><td>${t.participantIds.length}</td><td>${visits}</td><td>${tkm.toFixed(1)}</td><td>${UI.money(expenses)}</td></tr>`;
              }).join("")}</tbody>
            </table></div>
          </div>
        </section>
      `;

      UI.$("#exportCsvBtn")?.addEventListener("click", () => {
        const rows = [["Viagem","Status","Participantes","Visitas","Quilometros","Gastos"]];
        state.trips.forEach(t => {
          const visits = state.visits.filter(v=>v.tripId===t.id).length;
          const expenses = state.expenses.filter(e=>e.tripId===t.id).reduce((s,e)=>s+Number(e.amount),0);
          const records = t.odometerRecords || [];
          const tkm = records.length >= 2 ? Math.max(...records.map(r=>r.km)) - Math.min(...records.map(r=>r.km)) : (t.startKm && t.currentKm ? t.currentKm-t.startKm : 0);
          rows.push([t.name,t.status,t.participantIds.length,visits,tkm.toFixed(1),expenses.toFixed(2)]);
        });
        const csv = rows.map(r => r.map(v => `"${String(v).replace(/"/g,'""')}"`).join(";")).join("\n");
        const blob = new Blob(["\ufeff"+csv], {type:"text/csv;charset=utf-8"});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url; a.download = "relatorio-viagens.csv"; a.click(); URL.revokeObjectURL(url);
        UI.toast("CSV exportado.");
      });
    }

    function renderTrip(tripId) {
      const trip = state.trips.find(t => t.id === tripId);
      if(!trip) return;

      const visits = state.visits.filter(v => v.tripId === trip.id);
      const expenses = state.expenses.filter(e => e.tripId === trip.id);
      const participants = state.users.filter(u => trip.participantIds.includes(u.id));
      
      const records = trip.odometerRecords || [];
      const tkm = records.length >= 2 ? Math.max(...records.map(r=>r.km)) - Math.min(...records.map(r=>r.km)) : (trip.startKm && trip.currentKm ? trip.currentKm-trip.startKm : 0);
      const totalSpent = expenses.reduce((s,e)=>s+Number(e.amount),0);
      
      const startD = new Date(trip.startDate);
      const endD = new Date(trip.endDate || trip.startDate);
      const tripDays = Math.max(1, Math.ceil((endD - startD) / (1000 * 60 * 60 * 24)) + 1);

      reportContainer.innerHTML = `
        <section class="metric-grid reveal">
          <article class="metric-card"><span>Período</span><strong>${tripDays} dia${tripDays > 1 ? 's' : ''}</strong><small>corridos de viagem</small></article>
          <article class="metric-card"><span>Visitas realizadas</span><strong>${visits.length}</strong><small>Interações com clientes</small></article>
          <article class="metric-card"><span>Quilometragem</span><strong>${tkm.toFixed(1)} km</strong><small>Distância total percorrida</small></article>
          <article class="metric-card"><span>Investimento</span><strong>${UI.money(totalSpent)}</strong><small>${expenses.length} lançamento(s)</small></article>
        </section>

        <section class="report-grid reveal">
          <div class="panel span-2">
            <div class="panel-head"><div><span class="eyebrow">Relatório de Campo</span><h3>Diário de Visitas Realizadas</h3></div><button class="btn btn-secondary btn-small hide-print" onclick="window.print()">${UI.icon("printer", 17) || "🖨️"} Imprimir / PDF</button></div>
            <div class="table-wrap">
              ${visits.length ? `
                <table style="width: 100%; border-collapse: collapse;">
                  <thead><tr><th style="width:140px;">Data/Hora</th><th style="width:250px;">Cliente Visitado</th><th style="width:130px;">Contexto</th><th>Anotações e Relatório</th></tr></thead>
                  <tbody>
                    ${visits.map(v => {
                      const client = state.clients.find(c => c.id === v.clientId);
                      return `<tr>
                        <td style="white-space:nowrap; vertical-align:top;"><strong>${UI.date(v.date)}</strong><br><small style="color:var(--muted)">${new Date(v.date).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}</small></td>
                        <td style="vertical-align:top; white-space:normal;"><strong>${client?.name || 'Desconhecido'}</strong><br><small style="color:var(--muted)">${client?.city || ''}</small></td>
                        <td style="vertical-align:top;"><span style="display:inline-block; padding:4px 8px; background:#f0f4f8; color:#475569; border-radius:6px; font-size:10px; font-weight:700;">${v.type}</span></td>
                        <td style="white-space:normal; line-height:1.6; color:#334155;">${v.notes || "Sem observações detalhadas."}</td>
                      </tr>`;
                    }).join("")}
                  </tbody>
                </table>
              ` : UI.empty("Nenhuma visita", "Nenhum relatório de visita foi registrado nesta viagem ainda.")}
            </div>
          </div>

          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Prestação de Contas</span><h3>Despesas Registradas</h3></div></div>
            <div class="expense-list">
              ${expenses.length ? expenses.map(e => `
                <div class="expense-row">
                  <span class="mini-icon">${UI.icon("receipt", 16)}</span>
                  <div><div class="row-inline" style="display:flex; align-items:center;"><strong>${e.category}</strong>${e.costCenter ? `<span class="tag subtle" style="background:#eef2f6; color:#475569; margin-left:6px; font-size:9.5px; padding:2px 6px; border-radius:4px;">${e.costCenter}</span>` : ""}</div><p>${e.place}</p><small>${UI.date(e.date)}</small></div>
                  <b>${UI.money(e.amount)}</b>
                </div>
              `).join("") : UI.empty("Sem despesas", "Nenhum gasto lançado.", "compact")}
            </div>
          </div>

          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Equipe</span><h3>Participantes da Viagem</h3></div></div>
            <div class="mini-list">
              ${participants.map(u => `
                <div>
                  <span class="avatar mini">${u.initials}</span>
                  <span><strong>${u.name}</strong><small>${u.role}</small></span>
                </div>
              `).join("")}
            </div>
          </div>
        </section>
        
        <style>
          @media print {
            .sidebar, .topbar, .bottom-nav, .form-page-head, .hide-print { display: none !important; }
            .workspace { margin: 0 !important; padding: 0 !important; }
            .panel { box-shadow: none !important; border: 1px solid #ddd !important; break-inside: avoid; }
            body { background: #fff !important; }
            * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
          }
        </style>
      `;
    }

    select.addEventListener("change", (e) => {
      const val = e.target.value;
      if (val === "ALL") {
        renderGeneral();
      } else {
        renderTrip(val);
      }
    });

    renderGeneral();
  }
};
