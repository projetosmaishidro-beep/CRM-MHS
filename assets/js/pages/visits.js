window.PageModules = window.PageModules || {};
window.PageModules.visits = {
  init() {
    const state = Store.getState();
    let period = "30";
    let page = 1;
    let map = null;
    const pageSize = 5;
    const escape = UI.escape;
    const clientsById = new Map(state.clients.map(client => [client.id, client]));
    const usersById = new Map(state.users.map(user => [user.id, user]));
    const clientFor = visit => clientsById.get(visit.clientId);
    const userFor = visit => usersById.get(visit.userId);
    const parseVisitDate = value => {
      if (!value) return null;
      const date = new Date(/^\d{4}-\d{2}-\d{2}$/.test(String(value)) ? `${value}T12:00:00` : value);
      return Number.isFinite(date.getTime()) ? date : null;
    };
    const formatVisitDate = (value, short = false) => {
      const date = parseVisitDate(value);
      return date ? new Intl.DateTimeFormat("pt-BR", short ? { day: "2-digit", month: "short" } : { day: "2-digit", month: "short", year: "numeric" }).format(date) : "Data não informada";
    };
    const hasCoordinates = visit => visit.lat != null && visit.lng != null && Number.isFinite(Number(visit.lat)) && Number.isFinite(Number(visit.lng)) && Math.abs(Number(visit.lat)) <= 90 && Math.abs(Number(visit.lng)) <= 180;
    const clientLink = visit => UI.pageLink(`pages/cliente.html?id=${encodeURIComponent(visit.clientId || "")}`);

    // Datas convertidas e ordenadas uma única vez: trocar o período ou a
    // página passa a ser só um filtro sobre esta lista.
    const MAP_POINT_LIMIT = 500;
    const timed = state.visits
      .map(visit => ({ visit, time: parseVisitDate(visit.date)?.getTime() ?? NaN }))
      .sort((a, b) => (Number.isFinite(b.time) ? b.time : -Infinity) - (Number.isFinite(a.time) ? a.time : -Infinity));

    function render() {
      if (map) { map.remove(); map = null; }
      const now = Date.now();
      const visits = (period === "all"
        ? timed
        : timed.filter(({ time }) => Number.isFinite(time) && time <= now && time >= now - Number(period) * 86400000)
      ).map(({ visit }) => visit);
      const withTrip = visits.filter(visit => visit.tripId).length;
      const withoutTrip = visits.length - withTrip;
      const prospecting = visits.filter(visit => visit.type === "Prospecção").length;
      const located = visits.filter(hasCoordinates);
      const missingLocation = visits.length - located.length;
      const pages = Math.max(1, Math.ceil(visits.length / pageSize));
      page = Math.min(page, pages);
      const rows = visits.slice((page - 1) * pageSize, page * pageSize);
      const periodText = period === "all" ? "Todo o histórico" : `Últimos ${period} dias`;

      UI.$("#pageContent").innerHTML = `
        <div class="visits-dashboard">
          <div class="visits-dashboard-toolbar"><div><span class="eyebrow">Central comercial</span><h2>Visitas</h2></div><div class="visits-dashboard-actions"><label><span class="visits-sr-only">Período das visitas</span><select id="visitsPeriod"><option value="30">Últimos 30 dias</option><option value="90">Últimos 90 dias</option><option value="all">Todo o histórico</option></select></label><a class="btn btn-primary" href="${UI.pageLink("pages/nova-visita.html")}">${UI.icon("plus", 17)} Nova visita</a></div></div>
          <div class="visits-overview-grid">
            <section class="visits-summary" aria-label="Indicadores de visitas">
              <div class="visits-summary-item"><span class="visits-summary-icon visits-icon-cyan">${UI.icon("pin", 21)}</span><div><small>Visitas registradas</small><strong>${visits.length}</strong><span>${periodText}</span></div></div>
              <div class="visits-summary-item"><span class="visits-summary-icon visits-icon-blue">${UI.icon("briefcase", 21)}</span><div><small>Com viagem</small><strong>${withTrip}</strong><span>Visitas vinculadas</span></div></div>
              <div class="visits-summary-item"><span class="visits-summary-icon visits-icon-red">${UI.icon("users", 21)}</span><div><small>Prospecções</small><strong>${prospecting}</strong><span>Visitas de prospecção</span></div></div>
            </section>
            <section class="visits-panel visits-map-panel"><div class="visits-panel-head"><div><h3>Distribuição das visitas</h3><p>${located.length} com localização registrada${located.length > MAP_POINT_LIMIT ? ` · mapa exibe as ${MAP_POINT_LIMIT} mais recentes` : ""}</p></div><span class="visits-period-label">${periodText}</span></div><div id="visitsMap" class="visits-map" aria-label="Mapa das visitas registradas">${located.length ? "Carregando mapa…" : "Nenhuma visita com localização registrada neste período."}</div></section>
            <section class="visits-panel visits-attention"><div class="visits-panel-head"><div><h3>Pontos de atenção</h3><p>Dados do período selecionado</p></div></div><div class="visits-attention-list"><div><span class="visits-attention-icon">${UI.icon("pin", 18)}</span><p><strong>${missingLocation} ${missingLocation === 1 ? "visita sem localização" : "visitas sem localização"}</strong><small>Sem coordenadas registradas</small></p></div><div><span class="visits-attention-icon">${UI.icon("briefcase", 18)}</span><p><strong>${withoutTrip} ${withoutTrip === 1 ? "visita sem viagem" : "visitas sem viagem"}</strong><small>Não vinculadas a uma viagem</small></p></div></div></section>
          </div>
          <section class="visits-panel visits-history-dashboard" id="visitsHistory"><div class="visits-panel-head"><div><h3>Últimas visitas</h3><p>Histórico do período selecionado</p></div><span class="visits-period-label">${visits.length} ${visits.length === 1 ? "registro" : "registros"}</span></div><div class="visits-table-wrap"><table class="visits-table"><thead><tr><th>Cliente</th><th>Tipo</th><th>Vínculo</th><th>Data</th><th>Responsável</th><th><span class="visits-sr-only">Abrir cliente</span></th></tr></thead><tbody>${rows.map(visit => { const client = clientFor(visit); const user = userFor(visit); return `<tr><td><a href="${clientLink(visit)}">${escape(client?.name || "Cliente não identificado")}</a></td><td><span class="visits-type">${escape(visit.type || "Visita")}</span></td><td>${visit.tripId ? "Com viagem" : "Sem viagem"}</td><td>${escape(formatVisitDate(visit.date))}</td><td>${escape(user?.name || "Não informado")}</td><td><a class="visits-row-link" href="${clientLink(visit)}" aria-label="Abrir cliente ${escape(client?.name || "da visita")}">${UI.icon("chevron", 16)}</a></td></tr>`; }).join("")}</tbody></table>${rows.length ? "" : '<p class="visits-empty-inline">Nenhuma visita registrada neste período.</p>'}</div><div class="visits-pagination"><span>${visits.length ? `Mostrando ${(page - 1) * pageSize + 1} a ${Math.min(page * pageSize, visits.length)} de ${visits.length}` : "Nenhum registro"}</span><div><button type="button" id="visitsPrev" aria-label="Página anterior" ${page <= 1 ? "disabled" : ""}>${UI.icon("arrow_left", 16)}</button><strong>${page} / ${pages}</strong><button type="button" id="visitsNext" aria-label="Próxima página" ${page >= pages ? "disabled" : ""}>${UI.icon("arrow", 16)}</button></div></div></section>
        </div>`;

      const select = UI.$("#visitsPeriod");
      select.value = period;
      select.addEventListener("change", () => { period = select.value; page = 1; render(); });
      UI.$("#visitsPrev").addEventListener("click", () => { if (page > 1) { page--; render(); } });
      UI.$("#visitsNext").addEventListener("click", () => { if (page < pages) { page++; render(); } });
      if (located.length) {
        const element = UI.$("#visitsMap");
        const points = located.slice(0, MAP_POINT_LIMIT).map(visit => ({ lat: Number(visit.lat), lng: Number(visit.lng), name: clientFor(visit)?.name || "Cliente não identificado", detail: formatVisitDate(visit.date) }));
        UI.initVisitsMap(element, points).then(instance => { if (element.isConnected) map = instance; else instance?.remove(); });
      }
    }
    render();
  }
};
