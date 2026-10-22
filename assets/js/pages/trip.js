window.PageModules = window.PageModules || {};
window.PageModules.trip = {
  init() {
    const id = new URLSearchParams(location.search).get("id");
    let routeSynchronizationRunning = false;

    const synchronizeRouteFromVisits = async () => {
      if (routeSynchronizationRunning) return;
      const state = Store.getState();
      const trips = Array.isArray(state.trips) ? state.trips : [];
      const trip = trips.find(item => String(item.id) === String(id));
      if (!trip) return;

      const currentStops = Array.isArray(trip.stops) ? trip.stops : [];
      // Uma parada sem a marca de origem foi criada manualmente e deve ser
      // preservada; a sincronizacao automatica só opera roteiros gerados por visitas.
      if (currentStops.some(stop => stop.source !== "visit")) return;

      const clients = Array.isArray(state.clients) ? state.clients : [];
      const visits = (Array.isArray(state.visits) ? state.visits : [])
        .filter(visit => String(visit.tripId) === String(trip.id))
        .sort((left, right) => new Date(left.date) - new Date(right.date));
      if (!visits.length) return;

      const stops = visits.map(visit => {
        const client = clients.find(item => String(item.id) === String(visit.clientId));
        if (!client) return null;
        return {
          id: `visit-${visit.id}`,
          visitId: visit.id,
          clientId: client.id,
          label: client.name,
          place: [client.city, client.state].filter(Boolean).join(", ") || "Local não informado",
          latitude: Number.isFinite(Number(client.lat)) ? Number(client.lat) : null,
          longitude: Number.isFinite(Number(client.lng)) ? Number(client.lng) : null,
          done: true,
          source: "visit"
        };
      }).filter(Boolean);

      const unchanged = currentStops.length === stops.length && currentStops.every((stop, index) => stop.visitId === stops[index].visitId);
      if (unchanged) return;

      routeSynchronizationRunning = true;
      try {
        await UI.updateSupabaseTrip(trip.id, { stops });
        await UI.hydrateSupabaseSnapshot();
        render();
      } catch (error) {
        console.error("[Viagem] Não foi possível sincronizar o roteiro pelas visitas:", error);
      } finally {
        routeSynchronizationRunning = false;
      }
    };

    const render = () => {
      const state = Store.getState();
      const trips = Array.isArray(state.trips) ? state.trips : [];
      const trip = trips.find(t => String(t.id) === String(id)) || trips[0];
      if (!trip) {
        UI.$("#pageContent").innerHTML = `<section class="content-section">${UI.empty("Viagem não encontrada", "Nenhuma viagem está disponível para exibir.")}</section>`;
        return;
      }
      const visits = (Array.isArray(state.visits) ? state.visits : []).filter(v => String(v.tripId) === String(trip.id));
      const expenses = (Array.isArray(state.expenses) ? state.expenses : []).filter(e => String(e.tripId) === String(trip.id));
      const users = Array.isArray(state.users) ? state.users : [];
      const clients = Array.isArray(state.clients) ? state.clients : [];
      const participantIds = Array.isArray(trip.participantIds) ? trip.participantIds : [];
      const plannedClientIds = Array.isArray(trip.plannedClientIds) ? trip.plannedClientIds : [];
      const participants = participantIds.map(uid => users.find(u => String(u.id) === String(uid))).filter(Boolean);
      const planned = plannedClientIds.map(cid => clients.find(c => String(c.id) === String(cid))).filter(Boolean);
      const visitedIds = new Set(visits.map(v => v.clientId));
      const stops = Array.isArray(trip.stops) ? trip.stops : [];
      const attachments = Array.isArray(trip.attachments) ? trip.attachments : [];
      const noteBlocks = Array.isArray(trip.noteBlocks) ? trip.noteBlocks : [];
      const progress = Math.round((stops.filter(s => s.done).length / Math.max(stops.length, 1)) * 100);
      const records = Array.isArray(trip.odometerRecords) ? trip.odometerRecords : [];
      const legacyKm = trip.startKm && trip.currentKm ? trip.currentKm - trip.startKm : 0;
      const km = records.length >= 2 ? Math.max(...records.map(r => r.km)) - Math.min(...records.map(r => r.km)) : (records.length === 1 ? 0 : legacyKm);
      const totalExpenses = expenses.reduce((sum, expense) => sum + Number(expense.amount), 0);
      const action = (modal, icon, label, meta, content, buttonLabel) => `<article class="trip-detail-panel"><button class="trip-detail-panel-head" type="button" data-trip-modal="${modal}"><span class="trip-action-icon">${UI.icon(icon,20)}</span><span><strong>${label}</strong><small>${meta}</small></span>${UI.icon("chevron",16)}</button><div class="trip-detail-panel-body">${content}</div><button class="trip-detail-panel-action" type="button" data-trip-modal="${modal}">${UI.icon(buttonLabel.startsWith("Ver ") ? "chevron" : buttonLabel === "Gerenciar roteiro" ? "map" : "plus",15)} ${buttonLabel}</button></article>`;
      const previewRow = (icon, title, detail) => `<div class="trip-detail-preview"><span class="trip-detail-preview-icon">${UI.icon(icon,16)}</span><span><strong>${UI.escape(title || "N\u00e3o informado")}</strong><small>${UI.escape(detail || "")}</small></span></div>`;
      const emptyPreview = (text, icon = "file", description = "") => `<div class="trip-detail-empty"><span>${UI.icon(icon, 26)}</span><strong>${text}</strong>${description ? `<p>${description}</p>` : ""}</div>`;
      const expenseIcon = (category, size = 16) => {
        const key = String(category || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
        const icons = [
          ["aliment", "food", '<path d="M4 3v5a3 3 0 0 0 6 0V3M7 3v18M16 3c-2 3-2 7 1 9h1V3zM18 12v9"/>'],
          ["hosped", "lodging", '<path d="M3 18V8M3 15h18v3M21 15v-4a2 2 0 0 0-2-2h-8v6M3 15h8V8H6a3 3 0 0 0-3 3"/>'],
          ["combust", "fuel", '<path d="M4 21h12M6 21V4a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v17M6 11h9M18 7l2 2v9a2 2 0 0 1-4 0v-3h-1"/>'],
          ["pedagio", "toll", '<path d="M4 21h16M7 21V9h10v12M4 9h16M9 9V5h6v4M12 13v4"/>'],
          ["estacion", "parking", '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M9 17V7h4a3 3 0 0 1 0 6H9"/>'],
          ["transporte", "transport", '<rect x="4" y="9" width="16" height="8" rx="2"/><path d="m6 9 2-4h8l2 4M6 17v2M18 17v2M7 13h.01M17 13h.01"/>']
        ];
        const match = icons.find(([term]) => key.includes(term));
        const tone = match ? match[1] : "other";
        const path = match ? match[2] : '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>';
        return `<svg class="icon trip-expense-icon expense-icon-${tone}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
      };
      const expenseGroups = [...expenses.reduce((groups, expense) => {
        const category = expense.category || "Outros";
        groups.set(category, (groups.get(category) || 0) + (Number(expense.amount) || 0));
        return groups;
      }, new Map())];

      UI.$("#pageContent").innerHTML = `
        <section class="trip-central-hero reveal">

          <div class="trip-central-heading"><span class="trip-hero-icon">${UI.icon("briefcase",24)}</span><div class="trip-hero-copy">
            <div class="title-inline"><h2>${trip.name}</h2>${UI.statusBadge(trip.status)}</div>
            <p>${trip.objective || "Sem objetivo informado."}</p>
            <div class="trip-meta-line"><span>${UI.icon("calendar",16)} ${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</span><span>${UI.icon("users",16)} ${participants.length} ${participants.length === 1 ? "participante" : "participantes"}</span><span>${UI.icon("route",16)} ${km} km</span></div>
          </div>
          </div>
          <div class="trip-primary-actions">
            ${trip.status === "Planejada" ? `<button class="btn btn-secondary" id="statusTripBtn"><svg class="icon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 4v16l13-8z"/></svg> Iniciar viagem</button>` : ""}
            ${trip.status === "Em andamento" ? `<button class="btn btn-secondary" id="statusTripBtn">${UI.icon("check",17)} Concluir viagem</button>` : ""}
            <a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("pin",17)} Nova visita</a>
            <details class="trip-document-menu"><summary>${UI.icon("file",17)} <span>Documentos</span>${UI.icon("chevron",14)}</summary><div class="trip-document-options"><button type="button" data-trip-modal="attachmentsDialog">${UI.icon("paperclip",16)} Anexos da viagem</button><button id="reportBtn" type="button">${UI.icon("file",16)} Gerar relatório</button></div></details>
          </div>
        </section>

        <section class="trip-actions-grid reveal" aria-label="Gestão da viagem">
          <section class="trip-operations-panel trip-operations-overview" aria-label="Operação da viagem">
            <div class="trip-operations-heading"><div><span class="eyebrow">Operação</span><h3>Roteiro e equipe</h3></div><button type="button" data-trip-modal="routeDialog">Gerenciar roteiro ${UI.icon("arrow",15)}</button></div>
            <div class="trip-operations-summary">
              <button type="button" data-trip-modal="routeDialog"><span>${UI.icon("route",18)}</span><span><small>Paradas</small><strong>${stops.length}</strong></span></button>
              <button type="button" data-trip-modal="clientVisitsDialog"><span>${UI.icon("pin",18)}</span><span><small>Clientes planejados</small><strong>${planned.length}</strong></span></button>
              <button type="button" data-trip-modal="participantsDialog"><span>${UI.icon("users",18)}</span><span><small>Participantes</small><strong>${participants.length}</strong></span></button>
              <button type="button" data-trip-modal="kmDialog"><span>${UI.icon("route",18)}</span><span><small>Quilometragem</small><strong>${km} km</strong></span></button>
            </div>
            <div class="trip-operations-detail">
              <div class="trip-operation-block"><div class="trip-operations-detail-head"><div class="trip-operation-title"><span class="trip-operation-title-icon">${UI.icon("route",22)}</span><span><strong>Paradas e clientes</strong><small>Gerencie as paradas e visualize os clientes planejados.</small></span></div><div class="trip-operation-header-actions"><button type="button" data-trip-modal="clientVisitsDialog">Ver clientes ${UI.icon("arrow",15)}</button><button class="trip-operation-add" type="button" data-trip-modal="routeDialog">${UI.icon("plus",16)} Adicionar parada</button></div></div>
                ${stops.length ? `<div class="trip-operations-label">Paradas do roteiro</div><div class="trip-operations-stops">${stops.slice(0,3).map((stop,index) => `<div><span class="trip-route-number ${stop.done ? "is-done" : ""}">${index + 1}</span><span><strong>${UI.escape(stop.label || "Parada")}</strong><small>${UI.escape(stop.place || "Local n\u00e3o informado")}</small></span><small class="trip-operations-status ${stop.done ? "is-done" : "is-pending"}">${stop.done ? "Conclu\u00edda" : "Pendente"}</small></div>`).join("")}</div>${stops.length > 3 ? `<button class="trip-operations-more" type="button" data-trip-modal="routeDialog">Ver todas as ${stops.length} paradas</button>` : ""}` : `<div class="trip-operation-empty"><span class="trip-operation-empty-illustration">${UI.icon("map",42)}<span>${UI.icon("pin",22)}</span></span><strong>Nenhuma parada no roteiro</strong><p>Adicione paradas para organizar os locais que serão visitados nesta viagem.</p></div>`}
                ${planned.length ? `<div class="trip-operations-planned-list"><div class="trip-operations-label">Clientes planejados</div>${planned.slice(0,3).map(client => { const visited = visits.some(visit => String(visit.clientId) === String(client.id)); return `<div class="trip-operations-planned"><span class="trip-planned-icon">${UI.icon("briefcase",19)}</span><span class="trip-planned-details"><strong>${UI.escape(client.name)}</strong><small>Cliente planejado</small></span><span class="trip-operations-status ${visited ? "is-done" : "is-pending"}">${visited ? "Visita realizada" : "Sem visita registrada"}</span></div>`; }).join("")}${planned.length > 3 ? `<button class="trip-operations-more" type="button" data-trip-modal="clientVisitsDialog">Ver todos os ${planned.length} clientes</button>` : ""}</div>` : ""}
              </div>
              <div class="trip-operation-block"><div class="trip-operations-detail-head"><div class="trip-operation-title"><span class="trip-operation-title-icon">${UI.icon("users",22)}</span><span><strong>Equipe</strong><small>Visualize os participantes da viagem.</small></span></div><button type="button" data-trip-modal="participantsDialog">Ver equipe ${UI.icon("arrow",15)}</button></div>
                ${participants.length ? `<div class="trip-operations-people">${participants.slice(0,3).map(user => `<span class="trip-operations-person"><span class="trip-person-avatar">${UI.escape(user.initials || UI.initials(user.name || ""))}</span><span><strong>${UI.escape(user.name || "Participante")}</strong><small>${UI.escape(user.role || "Equipe")}</small></span></span>`).join("")}</div>` : `<p class="trip-operations-empty">Nenhum participante nesta viagem.</p>`}
              </div>
              <div class="trip-operation-block trip-operation-km-block"><div class="trip-operations-detail-head"><div class="trip-operation-title"><span class="trip-operation-title-icon">${UI.icon("route",20)}</span><span><strong>Quilometragem</strong><small>Registros de odômetro da viagem.</small></span></div></div><button class="trip-operations-km" type="button" data-trip-modal="kmDialog"><span><strong>${km} km</strong><small>${records.length} registro(s) de odômetro</small></span>${UI.icon("chevron",18)}</button></div>
            </div>
          </section>
          ${action("financeDialog", "wallet", "Financeiro", `${expenses.length} registro(s)`, `<div class="trip-detail-total"><small>Total de gastos</small><strong>${UI.money(totalExpenses)}</strong><span>${expenses.length} registro(s)</span></div>${expenseGroups.slice(0,4).map(([category, amount]) => `<div class="trip-expense-category"><span>${expenseIcon(category,16)} ${UI.escape(category)}</span><strong>${UI.money(amount)}</strong></div>`).join("")}`, "Ver financeiro")}
          ${action("notesDialog", "file", "Notas", noteBlocks.length ? `${noteBlocks.length} nota(s)` : "Sem notas", noteBlocks.length ? noteBlocks.slice(0,2).map(note => previewRow("file", note.author || "Participante", note.text)).join("") : emptyPreview("Adicione observações importantes da viagem", "file", "Registre informações, lembretes e outros detalhes relevantes."), "Nova nota")}
          ${action("attachmentsDialog", "paperclip", "Anexos", `${attachments.length} arquivo(s)`, attachments.length ? attachments.slice(0,2).map(file => previewRow("file", file.name, "Arquivo da viagem")).join("") : emptyPreview("Sem arquivos enviados", "paperclip", "Anexe fotos, documentos e outros arquivos da viagem."), "Adicionar anexo")}
        </section>

        <dialog id="routeDialog" class="form-dialog large trip-modal route-workspace-dialog" aria-labelledby="routeDialogTitle"><form method="dialog" id="routeStopForm">
          <div class="dialog-head route-workspace-head"><div><span class="eyebrow">Roteiro</span><h2 id="routeDialogTitle">Paradas e percurso</h2><p>Adicione e acompanhe as paradas da viagem.</p></div><button type="button" id="closeRouteDialog" class="icon-btn" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="route-workspace-summary"><div><span>${UI.icon("pin", 20)}</span><div><strong>${stops.length} ${stops.length === 1 ? "parada" : "paradas"}</strong><small>No roteiro</small></div></div><div><span>${UI.icon("check", 20)}</span><div><strong>${stops.filter(stop => stop.done).length} concluída(s)</strong><small>Paradas realizadas</small></div></div><div><span>${UI.icon("route", 20)}</span><div><strong>${km} km</strong><small>Registrados na viagem</small></div></div></div>
          <div class="route-workspace-layout">
            <div class="route-workspace-sidebar"><div class="route-workspace-list-panel"><div class="route-workspace-list-title">${UI.icon("route",16)} Roteiro <span>${stops.length}</span></div>
              <div class="route-list modal-list">${stops.length ? stops.map((stop, index) => `<label class="route-stop ${stop.done ? "done" : ""}"><input type="checkbox" data-stop="${UI.escape(stop.id)}" ${stop.done ? "checked" : ""}><span class="route-index">${stop.done ? UI.icon("check",15) : index + 1}</span><span><strong>${UI.escape(stop.label || "Parada")}</strong><small>${UI.escape(stop.place || "Local não informado")}</small></span><span class="route-stop-status">${stop.done ? "Concluída" : "Pendente"}</span></label>`).join("") : `<div class="route-workspace-empty">${UI.icon("map",24)}<strong>Nenhuma parada</strong><span>As paradas adicionadas aparecem aqui.</span></div>`}</div>
              <button class="route-add-shortcut" type="button" id="routeFocusNew">${UI.icon("plus",16)} Adicionar parada</button></div>
              <div class="route-workspace-map" id="routeWorkspaceMap" aria-label="Mapa das paradas">Verificando localizações...</div>
            </div>
            <div class="route-workspace-form"><span class="eyebrow">Nova parada</span><h3>Detalhes da parada</h3><p>Informe os dados para adicionar uma parada ao roteiro.</p>
              <div class="route-workspace-fields"><label class="field"><span>Nome da parada <b>*</b></span><input name="label" required placeholder="Ex.: Visita ao cliente"></label><label class="field"><span>Local <b>*</b></span><input name="place" required placeholder="Cidade ou referência"></label></div>
              <div class="route-workspace-form-footer"><button class="btn btn-secondary" type="reset">${UI.icon("rotate",15)} Limpar</button><button class="btn btn-primary" type="submit" value="default">${UI.icon("check",16)} Salvar parada</button></div>
            </div>
          </div>
        </form></dialog>

        <dialog id="participantsDialog" class="form-dialog trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Equipe</span><h2>Participantes</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="people-list modal-list">${participants.length ? participants.map(user => `<div class="person-row"><span class="avatar">${user.initials}</span><span><strong>${user.name}</strong><small>${user.role}</small></span></div>`).join("") : UI.empty("Sem participantes", "Inclua participantes no planejamento da viagem.")}</div>
        </form></dialog>

        <dialog id="clientVisitsDialog" class="form-dialog large trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Planejamento e campo</span><h2>Clientes e visitas</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="check-list modal-list">${planned.length ? planned.map(client => `<a href="${UI.pageLink(`pages/cliente.html?id=${client.id}`)}"><span class="check-state ${visitedIds.has(client.id) ? "ok" : ""}">${visitedIds.has(client.id) ? UI.icon("check",14) : ""}</span><span><strong>${client.name}</strong><small>${client.city}, ${client.state}</small></span></a>`).join("") : UI.empty("Sem clientes planejados", "Adicione clientes no planejamento da viagem.")}</div>
          <div class="trip-modal-divider"></div>
          <h3>Visitas registradas</h3>
          <div class="mini-list modal-list">${visits.length ? visits.map(visit => { const client = Store.byId("clients").get(visit.clientId); return `<a href="${UI.pageLink(`pages/cliente.html?id=${client?.id || ""}`)}"><span class="mini-icon">${UI.icon("pin",15)}</span><span><strong>${client?.name || "Cliente"}</strong><small>${UI.date(visit.date)} - ${visit.type}</small></span></a>`; }).join("") : UI.empty("Nenhuma visita", "Registre a primeira visita desta viagem.")}</div>
          <div class="dialog-actions"><a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("plus",17)} Nova visita</a></div>
        </form></dialog>

        <dialog id="visitsDialog" class="form-dialog large trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Campo</span><h2>Visitas da viagem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="mini-list modal-list">${visits.length ? visits.map(visit => { const client = Store.byId("clients").get(visit.clientId); return `<a href="${UI.pageLink(`pages/cliente.html?id=${client?.id || ""}`)}"><span class="mini-icon">${UI.icon("pin",15)}</span><span><strong>${client?.name || "Cliente"}</strong><small>${UI.date(visit.date)} · ${visit.type}</small></span></a>`; }).join("") : UI.empty("Nenhuma visita", "Registre a primeira visita desta viagem.")}</div>
          <div class="dialog-actions"><a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("plus",17)} Nova visita</a></div>
        </form></dialog>

        <dialog id="financeDialog" class="form-dialog trip-modal trip-finance-dialog" aria-labelledby="tripFinanceTitle">
          <div class="trip-finance-inner">
            <div class="trip-finance-header"><div><span class="eyebrow">Financeiro</span><h2 id="tripFinanceTitle">Despesas da viagem</h2><p>Registre e acompanhe os gastos da viagem.</p></div><button class="icon-btn" type="button" id="closeTripFinance" aria-label="Fechar">${UI.icon("x")}</button></div>
            <div class="trip-finance-summary"><div class="trip-finance-total"><small>Total de despesas</small><strong>${UI.money(totalExpenses)}</strong></div>${expenseGroups.map(([category, amount]) => `<div class="trip-finance-category-total"><span>${expenseIcon(category,16)}</span><div><small>${UI.escape(category)}</small><strong>${UI.money(amount)}</strong></div></div>`).join("")}</div>
            <div class="trip-finance-layout"><div class="trip-finance-history"><div class="trip-finance-toolbar"><div class="trip-finance-filters" role="group" aria-label="Filtrar despesas por categoria"><button type="button" data-expense-filter="all" aria-pressed="true">Todas (${expenses.length})</button>${expenseGroups.map(([category]) => `<button type="button" data-expense-filter="${UI.escape(category)}" aria-pressed="false">${UI.escape(category)} (${expenses.filter(expense => (expense.category || "Outros") === category).length})</button>`).join("")}</div><a class="btn btn-primary trip-finance-add" href="${UI.pageLink(`pages/financeiro.html?trip=${encodeURIComponent(trip.id)}&nova=1`)}">${UI.icon("plus",16)} Adicionar despesa</a></div>
              <div class="trip-finance-table-wrap"><table class="trip-finance-table"><thead><tr><th>Data</th><th>Categoria</th><th>Local / observações</th><th>Valor</th></tr></thead><tbody>${expenses.map(expense => { const rawDate = expense.date; const parsed = rawDate ? new Date(/^\d{4}-\d{2}-\d{2}$/.test(String(rawDate)) ? `${rawDate}T12:00:00` : rawDate) : null; const dateText = parsed && Number.isFinite(parsed.getTime()) ? new Intl.DateTimeFormat("pt-BR", {day:"2-digit",month:"short",year:"numeric"}).format(parsed) : "N\u00e3o informada"; return `<tr data-expense-category="${UI.escape(expense.category || "Outros")}"><td>${UI.escape(dateText)}</td><td><span class="trip-finance-row-icon">${expenseIcon(expense.category,16)}</span>${UI.escape(expense.category || "Outros")}</td><td><strong>${UI.escape(expense.place || "N\u00e3o informado")}</strong>${expense.notes ? `<small>${UI.escape(expense.notes)}</small>` : ""}</td><td><strong>${UI.money(expense.amount)}</strong></td></tr>`; }).join("")}</tbody></table><p class="trip-finance-empty" ${expenses.length ? "hidden" : ""}>Nenhuma despesa nesta categoria.</p></div>
            </div></div>
          </div>
        </dialog>

        <dialog id="kmDialog" class="form-dialog trip-modal"><form method="dialog" id="kmForm">
          <div class="dialog-head"><div><span class="eyebrow">Odômetro</span><h2>Quilometragem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="km-quick-read"><span>Distância rodada calculada</span><strong>${km} km</strong></div>
          <div class="form-grid" style="align-items: end; grid-template-columns: 1fr auto; margin-bottom: 20px;"><label class="field"><span>${records.length ? "Próximo registro do odômetro (km)" : "KM inicial do odômetro"}</span><input name="kmValue" type="number" min="${records.length ? Math.max(...records.map(record => Number(record.km) || 0)) : 0}" step="0.1" required placeholder="Ex.: 125400"></label><button class="btn btn-primary" value="default">${UI.icon("plus", 17)} ${records.length ? "Registrar" : "Definir KM inicial"}</button></div>
          ${records.length ? `<div class="mini-list modal-list">${records.map((r, i) => `<div><span class="mini-icon">${UI.icon("route", 15)}</span><span><strong>${r.km} km</strong><small>${UI.shortDate(r.date)} às ${new Date(r.date).toLocaleTimeString("pt-BR", {hour:"2-digit", minute:"2-digit"})}</small></span>${i === 0 ? `<b>Último</b>` : ""}</div>`).join("")}</div>` : UI.empty("Nenhum registro", "Insira o km atual do painel do carro para começar.")}
        </form></dialog>

        <dialog id="notesDialog" class="form-dialog trip-modal"><form method="dialog" id="notesForm">
          <div class="dialog-head"><div><span class="eyebrow">Registro interno</span><h2>Notas da viagem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="mini-list modal-list">${noteBlocks.length ? noteBlocks.map(note => `<div><span class="mini-icon">${UI.icon("file", 15)}</span><span><strong>${note.author || "Participante"}</strong><small>${UI.shortDate(note.createdAt)} às ${new Date(note.createdAt).toLocaleTimeString("pt-BR", {hour:"2-digit", minute:"2-digit"})}</small><p>${UI.escape(note.text || "")}</p></span></div>`).join("") : UI.empty("Sem notas", "Registre a primeira observação desta viagem.")}</div>
          <label class="field"><span>Nova observação</span><textarea name="noteText" rows="4" required placeholder="Registre decisões, observações e próximos passos."></textarea></label><div class="dialog-actions"><button class="btn btn-primary" value="default">Adicionar nota</button></div>
        </form></dialog>

        <dialog id="attachmentsDialog" class="form-dialog trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Documentação</span><h2>Anexos da viagem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <label class="upload-card full">${UI.icon("paperclip",26)}<span><strong>Adicionar arquivos</strong><small>Fotos, vídeos ou documentos</small></span><input type="file" id="tripFiles" accept="image/*,video/*,.pdf" multiple hidden></label>
          <div class="attachment-preview modal-list">${attachments.length ? attachments.map(file => `<div class="file-chip">${UI.icon(file.type?.startsWith("image/") ? "camera" : "file",16)}<span>${file.name}</span><small>${Math.round((file.size || 0) / 1024)} KB</small></div>`).join("") : `<span class="muted">Nenhum anexo geral nesta viagem.</span>`}</div>
        </form></dialog>
      `;

      let routeMap = null;
      let routeMapPending = false;
      const routeMapElement = UI.$("#routeWorkspaceMap");
      const routeMapPoints = stops.filter(stop => stop.latitude != null && stop.longitude != null && Number.isFinite(Number(stop.latitude)) && Number.isFinite(Number(stop.longitude)) && Math.abs(Number(stop.latitude)) <= 90 && Math.abs(Number(stop.longitude)) <= 180).map(stop => ({ lat: Number(stop.latitude), lng: Number(stop.longitude), name: stop.label || "Parada", detail: stop.place || "" }));
      const showRouteMap = () => {
        if (!routeMapPoints.length) { routeMapElement.textContent = "Nenhuma parada com coordenadas registradas."; return; }
        if (routeMap) { routeMap.invalidateSize(); return; }
        if (routeMapPending) return;
        routeMapPending = true;
        UI.initVisitsMap(routeMapElement, routeMapPoints).then(instance => { routeMapPending = false; if (routeMapElement.isConnected) routeMap = instance; else instance?.remove(); });
      };
      UI.$$('[data-trip-modal]').forEach(button => button.addEventListener("click", () => { UI.openDialog(button.dataset.tripModal); if (button.dataset.tripModal === "routeDialog") requestAnimationFrame(showRouteMap); }));
      UI.$("#closeTripFinance").addEventListener("click", () => UI.closeDialog("financeDialog"));
      UI.$$('[data-expense-filter]').forEach(button => button.addEventListener("click", () => {
        const category = button.dataset.expenseFilter;
        let count = 0;
        UI.$$('[data-expense-category]').forEach(row => { const visible = category === "all" || row.dataset.expenseCategory === category; row.hidden = !visible; if (visible) count++; });
        UI.$$('[data-expense-filter]').forEach(item => item.setAttribute("aria-pressed", String(item === button)));
        UI.$('.trip-finance-empty').hidden = count > 0;
      }));
      UI.$("#closeRouteDialog").addEventListener("click", () => UI.closeDialog("routeDialog"));
      UI.$("#routeFocusNew").addEventListener("click", () => UI.$('#routeStopForm input[name="label"]').focus());
      UI.$$('[data-stop]').forEach(input => input.addEventListener("change", async () => {
        const stops = (trip.stops || []).map(stop => stop.id === input.dataset.stop ? { ...stop, done: input.checked } : stop);
        try {
          await UI.updateSupabaseTrip(trip.id, { stops });
          await UI.hydrateSupabaseSnapshot();
          render();
          requestAnimationFrame(() => { UI.openDialog("routeDialog"); showRouteMap(); });
        } catch (error) {
          console.error(error);
          UI.toast("Erro ao atualizar a parada.", "error");
        }
      }));
      UI.$("#routeStopForm")?.addEventListener("submit", async event => {
        if (event.submitter?.value === "cancel") return;
        event.preventDefault();
        const data = new FormData(event.currentTarget);
        const stops = [...(trip.stops || []), { id: Store.uid("stop"), label: data.get("label"), place: data.get("place"), done: false }];
        try {
          await UI.updateSupabaseTrip(trip.id, { stops });
          await UI.hydrateSupabaseSnapshot();
          UI.toast("Parada adicionada ao roteiro.");
          render();
          requestAnimationFrame(() => { UI.openDialog("routeDialog"); showRouteMap(); });
        } catch (error) {
          console.error(error);
          UI.toast("Erro ao adicionar a parada.", "error");
        }
      });
      UI.$("#kmForm")?.addEventListener("submit", async event => {
        if (event.submitter?.value === "cancel") return;
        event.preventDefault();
        const data = new FormData(event.currentTarget);
        const kmValue = Number(data.get("kmValue"));
        if (kmValue > 0) {
          try {
            const currentRecords = Array.isArray(trip.odometerRecords) ? trip.odometerRecords : [];
            const latestKm = currentRecords.length ? Math.max(...currentRecords.map(record => Number(record.km) || 0)) : null;
            if (latestKm !== null && kmValue < latestKm) {
              UI.toast("O próximo KM não pode ser menor que o último registro.", "error");
              return;
            }
            const odometerRecords = [{
              id: Store.uid("km"),
              date: new Date().toISOString(),
              km: kmValue,
              type: currentRecords.length ? "REGISTRO" : "INICIAL"
            }, ...currentRecords];
            await UI.updateSupabaseTrip(trip.id, {
              odometerRecords,
              ...(currentRecords.length ? {} : { startKm: kmValue })
            });
            await UI.hydrateSupabaseSnapshot();
            UI.toast(currentRecords.length ? "Registro salvo no histórico do odômetro." : "KM inicial salvo no histórico do odômetro.");
          } catch (error) {
            console.error(error);
            UI.toast("Erro ao salvar o odômetro.", "error");
          }
        }
        render();
        requestAnimationFrame(() => {
          UI.openDialog("kmDialog");
          UI.$("#kmForm input[name=kmValue]")?.focus();
        });
      });
              UI.$("#notesForm")?.addEventListener("submit", async event => {
          if (event.submitter?.value === "cancel") return;
          event.preventDefault();
          try {
            const text = String(new FormData(event.currentTarget).get("noteText") || "").trim();
            if (!text) return;
            const noteBlocks = [{
              id: Store.uid("note"),
              text,
              authorId: window.AuthUser?.id || "",
              author: window.AuthUser?.name || "Participante",
              createdAt: new Date().toISOString()
            }, ...(Array.isArray(trip.noteBlocks) ? trip.noteBlocks : [])];
            const updatedTrip = await UI.updateSupabaseTrip(trip.id, { noteBlocks });
            if (!Array.isArray(updatedTrip?.notas)) {
              throw new Error("A estrutura de notas da viagem ainda não foi criada no banco.");
            }
            await UI.hydrateSupabaseSnapshot();
            UI.toast("Nota adicionada ao histórico da viagem.");
            render();
            requestAnimationFrame(() => UI.openDialog("notesDialog"));
          } catch(err) {
            console.error(err);
            UI.toast(err.message || "Erro ao atualizar notas.", "error");
          }
        });
      UI.$("#statusTripBtn")?.addEventListener("click", async () => {
        const nextStatus = trip.status === "Planejada" ? "Em andamento" : "Concluída";
        const patch = { status: nextStatus };
        if (nextStatus === "Concluída" && trip.currentKm && !trip.endKm) patch.endKm = trip.currentKm;
        try {
          await UI.updateSupabaseTrip(trip.id, patch);
          await UI.hydrateSupabaseSnapshot();
          UI.toast(nextStatus === "Em andamento" ? "Viagem iniciada." : "Viagem concluída.");
          render();
        } catch (error) {
          console.error(error);
          UI.toast("Erro ao atualizar a viagem.", "error");
        }
      });
      UI.$("#tripFiles")?.addEventListener("change", async event => {
          try {
             const added = await Promise.all(Array.from(event.target.files || []).map(async (file, index) => ({
               name: file.name,
               size: file.size,
               type: file.type,
               ...(await UI.uploadPrivateFile(`viagens/${trip.id}/${Date.now()}-${index}-${encodeURIComponent(file.name)}`, file))
             })));
             await UI.updateSupabaseTrip(trip.id, { attachments: [...(trip.attachments || []), ...added] });
             UI.toast(`${added.length} anexo(s) adicionado(s) à viagem.`);
             setTimeout(() => location.reload(), 350);
          } catch(err) {
             console.error(err);
             UI.toast("Erro ao anexar arquivo.", "error");
          }
        });
      UI.$("#reportBtn")?.addEventListener("click", () => generateReport(trip, state, visits, expenses, participants));
    };

    function generateReport(trip, state, visits, expenses, participants) {
      const lines = [`RELATÓRIO DE VIAGEM — ${trip.name}`, `Período: ${UI.shortDate(trip.startDate)} a ${UI.shortDate(trip.endDate)}`, `Status: ${trip.status}`, "", "Objetivo", trip.objective, "", "Participantes", ...participants.map(user => `- ${user.name} — ${user.role}`), "", "Roteiro", ...(trip.stops || []).map((stop, index) => `${index + 1}. ${stop.label} — ${stop.place} [${stop.done ? "concluída" : "pendente"}]`), "", "Visitas", ...visits.map(visit => { const client = Store.byId("clients").get(visit.clientId); return `- ${UI.date(visit.date)} — ${client?.name || "Cliente"} — ${visit.type}: ${visit.notes}`; }), "", "Financeiro", ...expenses.map(expense => `- ${expense.category} — ${expense.place} — ${UI.money(expense.amount)}`), `Total: ${UI.money(expenses.reduce((sum, expense) => sum + Number(expense.amount), 0))}`];
      const blob = new Blob([lines.join("\n")], { type: "text/plain;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `relatorio-${trip.name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}.txt`;
      link.click();
      URL.revokeObjectURL(url);
      UI.toast("Relatório gerado.");
    }

    render();
    void synchronizeRouteFromVisits();
  }
};
