window.PageModules = window.PageModules || {};
window.PageModules.trips = {
  init() {
    let viewMode = "cards";
    let searchText = "";
    let statusFilter = "";
    const render = () => {
      const state = Store.getState();
      const tripIds = new Set(state.trips.map(trip => trip.id));
      const planned = state.trips.filter(trip => trip.status === "Planejada").length;
      const active = state.trips.filter(trip => trip.status === "Em andamento").length;
      const tripVisits = state.visits.filter(visit => tripIds.has(visit.tripId)).length;
      const tripExpenses = state.expenses.filter(expense => tripIds.has(expense.tripId)).reduce((total, expense) => total + (Number(expense.amount) || 0), 0);
      UI.$("#pageContent").innerHTML = `
        <section class="trips-filters reveal" aria-label="Filtros e visualização de viagens">
          <label class="trips-search"><span class="sr-only">Buscar viagens</span>${UI.icon("search", 18)}<input id="tripSearch" type="search" placeholder="Buscar por viagem ou objetivo" autocomplete="off"></label>
          <label class="trips-status-filter"><span class="sr-only">Filtrar por situação</span><select id="tripStatus"><option value="">Todas as situações</option><option>Planejada</option><option>Em andamento</option><option>Concluída</option><option>Cancelada</option></select></label>
          <div class="trips-view-switch" role="group" aria-label="Visualização"><button type="button" data-view="cards">Cartões</button><button type="button" data-view="blocks">Blocos</button><button type="button" data-view="table">Tabela</button></div>
          <button class="btn btn-primary trips-create-btn" id="newTripBtn" type="button">${UI.icon("plus", 18)}<span>Nova viagem</span></button>
        </section>
        <section class="trips-summary reveal" aria-label="Resumo das viagens">
          <div class="trips-summary-item"><span class="trips-summary-icon">${UI.icon("briefcase", 20)}</span><div><small>Viagens planejadas</small><strong>${planned}</strong><span>de ${state.trips.length} viagens</span></div></div>
          <div class="trips-summary-item"><span class="trips-summary-icon is-active">${UI.icon("route", 20)}</span><div><small>Em andamento</small><strong>${active}</strong><span>de ${state.trips.length} viagens</span></div></div>
          <div class="trips-summary-item"><span class="trips-summary-icon is-visits">${UI.icon("users", 20)}</span><div><small>Total de visitas</small><strong>${tripVisits}</strong><span>em todas as viagens</span></div></div>
          <div class="trips-summary-item"><span class="trips-summary-icon is-cost">${UI.icon("wallet", 20)}</span><div><small>Gastos totais</small><strong>${UI.money(tripExpenses)}</strong><span>em todas as viagens</span></div></div>
        </section>
        <div class="trips-results reveal">
        <div class="trips-results-heading"><span id="tripResultCount" aria-live="polite"></span></div>
        <section class="trip-board" aria-label="Viagens cadastradas">
          ${state.trips.map((trip, index) => {
            const visits = state.visits.filter(v => v.tripId === trip.id);
            const expenses = state.expenses.filter(e => e.tripId === trip.id);
            const participants = trip.participantIds.map(id => state.users.find(u => u.id === id)).filter(Boolean);
            const progress = Math.round((trip.stops.filter(s => s.done).length / Math.max(trip.stops.length, 1)) * 100);
            return `
              <article class="trip-card" data-trip-index="${index}">
                <div class="trip-card-top">
                  <span>${UI.statusBadge(trip.status)}</span>
                  <div class="trip-card-actions">
                    <span class="date-chip">${UI.icon("calendar", 14)} ${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</span>
                    ${window.AuthUser?.isAdmin ? `<button class="mini-trash-btn" data-delete-trip="${trip.id}" aria-label="Excluir viagem" title="Excluir viagem"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>` : ""}
                  </div>
                </div>
                
                <a class="trip-card-content" href="${UI.pageLink(`pages/viagem.html?id=${trip.id}`)}">
                  <h3>${trip.name}</h3>
                  <p>${trip.objective}</p>
                  <div class="trips-card-stats">
                    <span>${UI.icon("users", 17)}<span><small>Participantes</small><strong>${participants.length}</strong></span></span>
                    <span>${UI.icon("calendar", 17)}<span><small>Visitas</small><strong>${visits.length}</strong></span></span>
                    <span>${UI.icon("wallet", 17)}<span><small>Gastos</small><strong>${UI.money(expenses.reduce((s,e)=>s+Number(e.amount),0))}</strong></span></span>
                  </div>
                  <div class="trips-card-progress"><span>Roteiro <strong>${progress}%</strong></span><span class="trips-progress-track"><span style="width:${progress}%"></span></span></div>
                </a>
              </article>`;
          }).join("")}
        </section>
        <div class="trips-table-wrap" hidden><table class="trips-table"><thead><tr><th>Viagem</th><th>Situação</th><th>Período</th><th>Participantes</th><th>Visitas</th><th>Gastos</th><th>Roteiro</th>${window.AuthUser?.isAdmin ? "<th><span class=\"sr-only\">Ações</span></th>" : ""}</tr></thead><tbody>${state.trips.map((trip, index) => {
          const visits = state.visits.filter(v => v.tripId === trip.id).length;
          const amount = state.expenses.filter(e => e.tripId === trip.id).reduce((sum, e) => sum + Number(e.amount), 0);
          const participants = trip.participantIds.map(id => state.users.find(u => u.id === id)).filter(Boolean).length;
          const progress = Math.round(trip.stops.filter(s => s.done).length / Math.max(trip.stops.length, 1) * 100);
          return `<tr data-trip-index="${index}"><td><a href="${UI.pageLink(`pages/viagem.html?id=${trip.id}`)}">${trip.name}</a><small>${trip.objective}</small></td><td>${UI.statusBadge(trip.status)}</td><td>${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</td><td>${participants}</td><td>${visits}</td><td>${UI.money(amount)}</td><td>${progress}%</td>${window.AuthUser?.isAdmin ? `<td><button type="button" class="mini-trash-btn" data-delete-trip="${trip.id}" aria-label="Excluir viagem" title="Excluir viagem">${UI.icon("trash", 16)}</button></td>` : ""}</tr>`;
        }).join("")}</tbody></table></div>
        <div class="trips-empty" hidden><strong>Nenhuma viagem encontrada</strong><span>Experimente ajustar a busca ou a situação.</span></div>
        </div>

        <dialog id="tripDialog" class="form-dialog large trip-dialog">
          <form method="dialog" id="tripForm">
            <div class="dialog-head trip-dialog-head"><div><span class="eyebrow">Planejamento</span><h2>Nova viagem</h2><p>Monte a ficha da viagem com equipe e clientes antes de sair a campo.</p></div><button class="icon-btn" value="cancel" aria-label="Fechar nova viagem">${UI.icon("x")}</button></div>
            <div class="trip-form-scroll">
            <div class="form-grid trip-form-grid">
              <label class="field span-2"><span>Nome da viagem</span><input name="name" required placeholder="Ex.: Circuito Cariri"></label>
              <label class="field"><span>Data de início</span><input name="startDate" type="date" required></label>
              <label class="field"><span>Data final</span><input name="endDate" type="date" required></label>
              <label class="field span-2"><span>Objetivo</span><textarea name="objective" rows="3" required></textarea></label>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Participantes</legend><p class="checklist-hint">Selecione quem participa desta operação.</p>${state.users.map(u => `<label><input type="checkbox" name="participant" value="${u.id}"><span class="avatar mini">${u.initials}</span><span class="checklist-name">${u.name}</span></label>`).join("")}</fieldset>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Clientes planejados</legend><p class="checklist-hint">Marque os clientes que entram no roteiro desta viagem.</p>${state.clients.map(c => `<label><input type="checkbox" name="client" value="${c.id}"><span class="checklist-name">${c.name}</span><small>${c.city || "Cidade não informada"}</small></label>`).join("")}</fieldset>
            </div>
            </div>
            <div class="dialog-actions trip-dialog-actions"><span class="trip-form-status">A viagem será gravada no banco unificado.</span><div><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">Salvar no banco</button></div></div>
          </form>
        </dialog>
      `;

      const tripDialog = UI.$("#tripDialog");
      const tripForm = UI.$("#tripForm");
      const results = UI.$(".trips-results");
      const board = results.querySelector(".trip-board");
      const table = results.querySelector(".trips-table-wrap");
      const search = UI.$("#tripSearch");
      const status = UI.$("#tripStatus");
      const viewButtons = UI.$(".trips-view-switch").querySelectorAll("[data-view]");
      const normalize = value => String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
      const updateResults = () => {
        const query = normalize(searchText.trim());
        let count = 0;
        const matches = state.trips.map(trip => {
          const match = (!statusFilter || trip.status === statusFilter) &&
            (!query || normalize(`${trip.name} ${trip.objective}`).includes(query));
          if (match) count++;
          return match;
        });
        results.querySelectorAll("[data-trip-index]").forEach(item => { item.hidden = !matches[Number(item.dataset.tripIndex)]; });
        board.hidden = viewMode === "table" || count === 0;
        table.hidden = viewMode !== "table" || count === 0;
        board.classList.toggle("trips-blocks", viewMode === "blocks");
        results.querySelector(".trips-empty").hidden = count !== 0;
        results.querySelector("#tripResultCount").textContent = `${count} ${count === 1 ? "viagem encontrada" : "viagens encontradas"}`;
        viewButtons.forEach(button => {
          const active = button.dataset.view === viewMode;
          button.classList.toggle("active", active);
          button.setAttribute("aria-pressed", String(active));
        });
      };
      search.value = searchText;
      status.value = statusFilter;
      search.addEventListener("input", () => { searchText = search.value; updateResults(); });
      status.addEventListener("change", () => { statusFilter = status.value; updateResults(); });
      viewButtons.forEach(button => button.addEventListener("click", () => { viewMode = button.dataset.view; updateResults(); }));
      updateResults();
      UI.$("#newTripBtn").addEventListener("click", () => {
        tripForm.reset();
        UI.openDialog("tripDialog");
        requestAnimationFrame(() => tripForm.querySelector("input[name=name]")?.focus());
      });
      
      UI.$(".trips-results")?.addEventListener("click", async e => {
        const trashBtn = e.target.closest(".mini-trash-btn");
        if (trashBtn) {
          e.preventDefault();
          e.stopPropagation();
          const tripId = trashBtn.dataset.deleteTrip;
          if (confirm("Tem certeza que deseja excluir esta viagem? Esta ação apagará as visitas e despesas associadas e é irreversível.")) {
            try {
              await UI.deleteSupabaseTrip(tripId);
              await UI.hydrateSupabaseSnapshot();
              UI.toast("Viagem excluída com sucesso.");
              render();
            } catch (error) {
              console.error(error);
              UI.toast(error.message || "Não foi possível excluir a viagem.", "error");
            }
          }
        }
      });
      tripDialog.addEventListener("close", () => tripForm.reset());
      tripForm.addEventListener("submit", async (e) => {
        if (e.submitter?.value === "cancel") return;
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        const startDate = String(fd.get("startDate") || "");
        const endDate = String(fd.get("endDate") || "");
        if (startDate && endDate && endDate < startDate) {
          UI.toast("A data final precisa ser posterior à data inicial.", "error");
          return;
        }
        const payload = {
          name: fd.get("name"),
          startDate,
          endDate,
          objective: fd.get("objective"),
          participantIds: fd.getAll("participant"),
          plannedClientIds: fd.getAll("client"),
          ownerId: "u1",
          startKm: null,
          currentKm: null,
          endKm: null,
          stops: [],
          notes: ""
        };
        const submitButton = e.submitter || tripForm.querySelector('button[value="default"]');
        const originalLabel = submitButton?.textContent || "Salvar";
        if (submitButton) {
          submitButton.disabled = true;
          submitButton.textContent = "Salvando…";
        }
        try {
          const currentState = Store.getState();
          const participants = currentState.users
            .filter(user => payload.participantIds.includes(user.id))
            .map(user => ({ id: user.id, name: user.name, initials: user.initials, role: user.role }));
          const clients = currentState.clients
            .filter(client => payload.plannedClientIds.includes(client.id))
            .map(client => ({ id: client.id, name: client.name, city: client.city, state: client.state }));
          await UI.createSupabaseTrip({ ...payload, participants, clients });
          await UI.hydrateSupabaseSnapshot();
          UI.toast("Viagem salva no banco unificado.");
          UI.closeDialog("tripDialog");
          render();
        } catch (error) {
          UI.toast(error.message || "Não foi possível salvar a viagem.", "error");
        } finally {
          if (submitButton) {
            submitButton.disabled = false;
            submitButton.textContent = originalLabel;
          }
        }
      });
    };
    render();
  }
};
