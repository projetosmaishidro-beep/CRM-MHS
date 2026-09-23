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
      const action = (modal, icon, label, meta) => `<button class="trip-action-card" type="button" data-trip-modal="${modal}"><span class="trip-action-icon">${UI.icon(icon,21)}</span><span><strong>${label}</strong><small>${meta}</small></span>${UI.icon("chevron",16)}</button>`;

      UI.$("#pageContent").innerHTML = `
        <section class="trip-central-hero reveal">

          <div class="trip-central-heading">
            <div class="title-inline"><h2>${trip.name}</h2>${UI.statusBadge(trip.status)}</div>
            <p>${trip.objective || "Sem objetivo informado."}</p>
            <div class="trip-meta-line"><span>${UI.icon("clock",16)} ${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</span><span>${UI.icon("users",16)} ${participants.length} participantes</span><span>${UI.icon("route",16)} ${km} km</span></div>
          </div>
          <div class="trip-primary-actions">
            ${trip.status === "Planejada" ? `<button class="btn btn-secondary" id="statusTripBtn">${UI.icon("check",17)} Iniciar viagem</button>` : ""}
            ${trip.status === "Em andamento" ? `<button class="btn btn-secondary" id="statusTripBtn">${UI.icon("check",17)} Concluir viagem</button>` : ""}
            <a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("pin",17)} Nova visita</a>
            <button class="icon-btn trip-report-btn" id="reportBtn" type="button" aria-label="Gerar relatório" title="Gerar relatório">${UI.icon("file",19)}</button>
          </div>
        </section>

        <section class="trip-quick-metrics reveal">
          <article><span>Roteiro</span><strong>${progress}%</strong><small>${stops.filter(s => s.done).length}/${stops.length} paradas</small></article>
          <article><span>Visitas</span><strong>${visitedIds.size}</strong><small>${planned.length} planejados</small></article>
          <article><span>Gastos</span><strong>${UI.money(totalExpenses)}</strong><small>${expenses.length} registros</small></article>
        </section>

        <section class="trip-actions-grid reveal" aria-label="Gestão da viagem">
          ${action("routeDialog", "route", "Roteiro", `${stops.length} parada(s)`)}
          ${action("participantsDialog", "users", "Participantes", `${participants.length} na equipe`)}
          ${action("clientVisitsDialog", "pin", "Clientes e visitas", `${planned.length} planejados · ${visits.length} visita(s)`)}
          ${action("financeDialog", "wallet", "Financeiro", UI.money(totalExpenses))}
          ${action("kmDialog", "route", "Quilometragem", `${km} km registrados`)}
          ${action("notesDialog", "file", "Notas", noteBlocks.length ? `${noteBlocks.length} nota(s) registrada(s)` : "Sem notas")}
          ${action("attachmentsDialog", "paperclip", "Anexos", `${attachments.length} arquivo(s)`)}
        </section>

        <dialog id="routeDialog" class="form-dialog large trip-modal"><form method="dialog" id="routeStopForm">
          <div class="dialog-head"><div><span class="eyebrow">Roteiro</span><h2>Paradas e percurso</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="route-list modal-list">${stops.length ? stops.map((stop, index) => `<label class="route-stop ${stop.done ? "done" : ""}"><input type="checkbox" data-stop="${stop.id}" ${stop.done ? "checked" : ""}><span class="route-index">${stop.done ? UI.icon("check",15) : index + 1}</span><span><strong>${stop.label}</strong><small>${stop.place}</small></span></label>`).join("") : UI.empty("Roteiro vazio", "Adicione a primeira parada da viagem.")}</div>
          <div class="progress-row"><span>Progresso do roteiro</span><strong>${progress}%</strong></div><div class="progress"><span style="width:${progress}%"></span></div>
          <div class="trip-modal-divider"></div><div class="form-grid"><label class="field"><span>Nova parada</span><input name="label" required placeholder="Ex.: Visita Cliente X"></label><label class="field"><span>Local</span><input name="place" required placeholder="Cidade ou referência"></label></div><div class="dialog-actions"><button class="btn btn-primary" value="default">${UI.icon("plus",17)} Adicionar parada</button></div>
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
          <div class="mini-list modal-list">${visits.length ? visits.map(visit => { const client = state.clients.find(item => item.id === visit.clientId); return `<a href="${UI.pageLink(`pages/cliente.html?id=${client?.id || ""}`)}"><span class="mini-icon">${UI.icon("pin",15)}</span><span><strong>${client?.name || "Cliente"}</strong><small>${UI.date(visit.date)} - ${visit.type}</small></span></a>`; }).join("") : UI.empty("Nenhuma visita", "Registre a primeira visita desta viagem.")}</div>
          <div class="dialog-actions"><a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("plus",17)} Nova visita</a></div>
        </form></dialog>

        <dialog id="visitsDialog" class="form-dialog large trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Campo</span><h2>Visitas da viagem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="mini-list modal-list">${visits.length ? visits.map(visit => { const client = state.clients.find(item => item.id === visit.clientId); return `<a href="${UI.pageLink(`pages/cliente.html?id=${client?.id || ""}`)}"><span class="mini-icon">${UI.icon("pin",15)}</span><span><strong>${client?.name || "Cliente"}</strong><small>${UI.date(visit.date)} · ${visit.type}</small></span></a>`; }).join("") : UI.empty("Nenhuma visita", "Registre a primeira visita desta viagem.")}</div>
          <div class="dialog-actions"><a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?trip=${trip.id}`)}">${UI.icon("plus",17)} Nova visita</a></div>
        </form></dialog>

        <dialog id="financeDialog" class="form-dialog large trip-modal"><form method="dialog">
          <div class="dialog-head"><div><span class="eyebrow">Financeiro</span><h2>Despesas da viagem</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
          <div class="mini-list modal-list">${expenses.length ? expenses.map(expense => `<div><span class="mini-icon">${UI.icon("receipt",15)}</span><span><strong>${expense.category}</strong><small>${expense.place} · ${UI.date(expense.date)}</small></span><b>${UI.money(expense.amount)}</b></div>`).join("") : UI.empty("Sem despesas", "Os lançamentos financeiros aparecerão aqui.")}</div>
          <div class="dialog-actions"><a class="btn btn-secondary" href="${UI.pageLink(`pages/financeiro.html?trip=${trip.id}`)}">Abrir financeiro</a></div>
        </form></dialog>

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

      UI.$$('[data-trip-modal]').forEach(button => button.addEventListener("click", () => UI.openDialog(button.dataset.tripModal)));
      UI.$$('[data-stop]').forEach(input => input.addEventListener("change", async () => {
        const stops = (trip.stops || []).map(stop => stop.id === input.dataset.stop ? { ...stop, done: input.checked } : stop);
        try {
          await UI.updateSupabaseTrip(trip.id, { stops });
          await UI.hydrateSupabaseSnapshot();
          render();
          requestAnimationFrame(() => UI.openDialog("routeDialog"));
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
          requestAnimationFrame(() => UI.openDialog("routeDialog"));
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
      const lines = [`RELATÓRIO DE VIAGEM — ${trip.name}`, `Período: ${UI.shortDate(trip.startDate)} a ${UI.shortDate(trip.endDate)}`, `Status: ${trip.status}`, "", "Objetivo", trip.objective, "", "Participantes", ...participants.map(user => `- ${user.name} — ${user.role}`), "", "Roteiro", ...(trip.stops || []).map((stop, index) => `${index + 1}. ${stop.label} — ${stop.place} [${stop.done ? "concluída" : "pendente"}]`), "", "Visitas", ...visits.map(visit => { const client = state.clients.find(item => item.id === visit.clientId); return `- ${UI.date(visit.date)} — ${client?.name || "Cliente"} — ${visit.type}: ${visit.notes}`; }), "", "Financeiro", ...expenses.map(expense => `- ${expense.category} — ${expense.place} — ${UI.money(expense.amount)}`), `Total: ${UI.money(expenses.reduce((sum, expense) => sum + Number(expense.amount), 0))}`];
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
