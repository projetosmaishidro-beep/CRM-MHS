window.PageModules = window.PageModules || {};
window.PageModules.trips = {
  init() {
    // Quantidade de viagens desenhadas por vez e de clientes sugeridos no
    // formulário. Desenhar tudo travava a tela com centenas de viagens e
    // milhares de clientes.
    const PAGE_STEP = 24;
    const CLIENT_SUGGESTIONS = 50;
    const escape = UI.escape;
    let viewMode = "cards";
    let searchText = "";
    let statusFilter = "";
    let visibleCount = PAGE_STEP;
    const normalize = value => String(value || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    const trashIcon = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>';

    const render = () => {
      const state = Store.getState();
      const isAdmin = !!window.AuthUser?.isAdmin;
      const visitsByTrip = Store.groupBy("visits", "tripId");
      const expensesByTrip = Store.groupBy("expenses", "tripId");
      const usersById = Store.byId("users");

      // Estatísticas de cada viagem calculadas uma única vez por render.
      const stats = new Map(state.trips.map(trip => {
        const stops = trip.stops || [];
        return [trip.id, {
          visits: (visitsByTrip.get(trip.id) || []).length,
          amount: (expensesByTrip.get(trip.id) || []).reduce((sum, expense) => sum + (Number(expense.amount) || 0), 0),
          participants: (trip.participantIds || []).filter(id => usersById.has(id)).length,
          progress: Math.round((stops.filter(stop => stop.done).length / Math.max(stops.length, 1)) * 100),
          searchable: normalize(`${trip.name} ${trip.objective}`)
        }];
      }));
      const planned = state.trips.filter(trip => trip.status === "Planejada").length;
      const active = state.trips.filter(trip => trip.status === "Em andamento").length;
      let tripVisits = 0;
      let tripExpenses = 0;
      stats.forEach(item => { tripVisits += item.visits; tripExpenses += item.amount; });

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
        <section class="trip-board" aria-label="Viagens cadastradas"></section>
        <div class="trips-table-wrap" hidden><table class="trips-table"><thead><tr><th>Viagem</th><th>Situação</th><th>Período</th><th>Participantes</th><th>Visitas</th><th>Gastos</th><th>Roteiro</th>${isAdmin ? "<th><span class=\"sr-only\">Ações</span></th>" : ""}</tr></thead><tbody></tbody></table></div>
        <div class="trips-empty" hidden><strong>Nenhuma viagem encontrada</strong><span>Experimente ajustar a busca ou a situação.</span></div>
        <div class="trips-more" hidden style="display:flex; justify-content:center; margin-top:16px;"><button type="button" class="btn btn-secondary" id="tripsMoreBtn"></button></div>
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
              <fieldset class="field span-2 checklist trip-checklist"><legend>Participantes</legend><p class="checklist-hint">Selecione quem participa desta operação.</p>${state.users.map(u => `<label><input type="checkbox" name="participant" value="${escape(u.id)}"><span class="avatar mini">${escape(u.initials)}</span><span class="checklist-name">${escape(u.name)}</span></label>`).join("")}</fieldset>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Clientes planejados</legend><p class="checklist-hint" id="tripClientHint">Marque os clientes que entram no roteiro desta viagem.</p><input type="search" id="tripClientSearch" placeholder="Buscar cliente por nome ou cidade" autocomplete="off" aria-label="Buscar cliente planejado"><div id="tripClientOptions"></div></fieldset>
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
      const tableBody = table.querySelector("tbody");
      const more = results.querySelector(".trips-more");
      const moreButton = UI.$("#tripsMoreBtn");
      const search = UI.$("#tripSearch");
      const status = UI.$("#tripStatus");
      const viewButtons = UI.$(".trips-view-switch").querySelectorAll("[data-view]");

      const cardHtml = trip => {
        const item = stats.get(trip.id);
        return `
              <article class="trip-card">
                <div class="trip-card-top">
                  <span>${UI.statusBadge(trip.status)}</span>
                  <div class="trip-card-actions">
                    <span class="date-chip">${UI.icon("calendar", 14)} ${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</span>
                    ${isAdmin ? `<button class="mini-trash-btn" data-delete-trip="${escape(trip.id)}" aria-label="Excluir viagem" title="Excluir viagem">${trashIcon}</button>` : ""}
                  </div>
                </div>
                <a class="trip-card-content" href="${UI.pageLink(`pages/viagem.html?id=${encodeURIComponent(trip.id)}`)}">
                  <h3>${escape(trip.name)}</h3>
                  <p>${escape(trip.objective)}</p>
                  <div class="trips-card-stats">
                    <span>${UI.icon("users", 17)}<span><small>Participantes</small><strong>${item.participants}</strong></span></span>
                    <span>${UI.icon("calendar", 17)}<span><small>Visitas</small><strong>${item.visits}</strong></span></span>
                    <span>${UI.icon("wallet", 17)}<span><small>Gastos</small><strong>${UI.money(item.amount)}</strong></span></span>
                  </div>
                  <div class="trips-card-progress"><span>Roteiro <strong>${item.progress}%</strong></span><span class="trips-progress-track"><span style="width:${item.progress}%"></span></span></div>
                </a>
              </article>`;
      };
      const rowHtml = trip => {
        const item = stats.get(trip.id);
        return `<tr><td><a href="${UI.pageLink(`pages/viagem.html?id=${encodeURIComponent(trip.id)}`)}">${escape(trip.name)}</a><small>${escape(trip.objective)}</small></td><td>${UI.statusBadge(trip.status)}</td><td>${UI.shortDate(trip.startDate)} → ${UI.shortDate(trip.endDate)}</td><td>${item.participants}</td><td>${item.visits}</td><td>${UI.money(item.amount)}</td><td>${item.progress}%</td>${isAdmin ? `<td><button type="button" class="mini-trash-btn" data-delete-trip="${escape(trip.id)}" aria-label="Excluir viagem" title="Excluir viagem">${UI.icon("trash", 16)}</button></td>` : ""}</tr>`;
      };

      // Apenas a visão ativa é desenhada, e só até `visibleCount` itens.
      const updateResults = () => {
        const query = normalize(searchText.trim());
        const matches = state.trips.filter(trip => (!statusFilter || trip.status === statusFilter) && (!query || stats.get(trip.id).searchable.includes(query)));
        const visible = matches.slice(0, visibleCount);
        const count = matches.length;
        if (viewMode === "table") { tableBody.innerHTML = visible.map(rowHtml).join(""); board.innerHTML = ""; }
        else { board.innerHTML = visible.map(cardHtml).join(""); tableBody.innerHTML = ""; }
        board.hidden = viewMode === "table" || count === 0;
        table.hidden = viewMode !== "table" || count === 0;
        board.classList.toggle("trips-blocks", viewMode === "blocks");
        results.querySelector(".trips-empty").hidden = count !== 0;
        const remaining = count - visible.length;
        more.hidden = remaining <= 0;
        moreButton.textContent = `Mostrar mais ${Math.min(PAGE_STEP, remaining)} de ${remaining} restantes`;
        results.querySelector("#tripResultCount").textContent = `${count} ${count === 1 ? "viagem encontrada" : "viagens encontradas"}${remaining > 0 ? ` · exibindo ${visible.length}` : ""}`;
        viewButtons.forEach(button => {
          const isActive = button.dataset.view === viewMode;
          button.classList.toggle("active", isActive);
          button.setAttribute("aria-pressed", String(isActive));
        });
      };
      search.value = searchText;
      status.value = statusFilter;
      search.addEventListener("input", () => { searchText = search.value; visibleCount = PAGE_STEP; updateResults(); });
      status.addEventListener("change", () => { statusFilter = status.value; visibleCount = PAGE_STEP; updateResults(); });
      viewButtons.forEach(button => button.addEventListener("click", () => { viewMode = button.dataset.view; updateResults(); }));
      moreButton.addEventListener("click", () => { visibleCount += PAGE_STEP; updateResults(); });
      updateResults();

      // Clientes planejados: os selecionados ficam sempre visíveis; os demais
      // aparecem pela busca, limitados a CLIENT_SUGGESTIONS por vez.
      const selectedClients = new Set();
      const clientSearch = UI.$("#tripClientSearch");
      const clientOptions = UI.$("#tripClientOptions");
      const clientHint = UI.$("#tripClientHint");
      const clientsById = Store.byId("clients");
      const clientLabel = (client, checked) => `<label><input type="checkbox" name="client" value="${escape(client.id)}" ${checked ? "checked" : ""}><span class="checklist-name">${escape(client.name)}</span><small>${escape(client.city || "Cidade não informada")}</small></label>`;
      const renderClientOptions = () => {
        const query = normalize(clientSearch.value.trim());
        const selected = [...selectedClients].map(id => clientsById.get(id)).filter(Boolean);
        const suggestions = [];
        for (const client of state.clients) {
          if (suggestions.length >= CLIENT_SUGGESTIONS) break;
          if (selectedClients.has(client.id)) continue;
          if (!query || normalize(`${client.name} ${client.city}`).includes(query)) suggestions.push(client);
        }
        clientOptions.innerHTML = selected.map(client => clientLabel(client, true)).join("") + suggestions.map(client => clientLabel(client, false)).join("");
        clientHint.textContent = `${selectedClients.size} selecionado(s). ${query ? "Resultados da busca" : `Mostrando ${suggestions.length} de ${state.clients.length} clientes`}; use a busca para encontrar outros.`;
      };
      clientSearch.addEventListener("input", renderClientOptions);
      clientOptions.addEventListener("change", event => {
        const input = event.target.closest('input[name="client"]');
        if (!input) return;
        if (input.checked) selectedClients.add(input.value); else selectedClients.delete(input.value);
      });

      UI.$("#newTripBtn").addEventListener("click", () => {
        tripForm.reset();
        selectedClients.clear();
        renderClientOptions();
        UI.openDialog("tripDialog");
        requestAnimationFrame(() => tripForm.querySelector("input[name=name]")?.focus());
      });

      results.addEventListener("click", async e => {
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
        const participantIds = fd.getAll("participant");
        // União da seleção acumulada pela busca com o que está marcado na tela.
        const plannedClientIds = [...new Set([...selectedClients, ...fd.getAll("client")])];
        const submitButton = e.submitter || tripForm.querySelector('button[value="default"]');
        const originalLabel = submitButton?.textContent || "Salvar";
        if (submitButton) {
          submitButton.disabled = true;
          submitButton.textContent = "Salvando…";
        }
        try {
          const participants = participantIds.map(id => usersById.get(id)).filter(Boolean)
            .map(user => ({ id: user.id, name: user.name, initials: user.initials, role: user.role }));
          const clients = plannedClientIds.map(id => clientsById.get(id)).filter(Boolean)
            .map(client => ({ id: client.id, name: client.name, city: client.city, state: client.state }));
          await UI.createSupabaseTrip({ name: fd.get("name"), startDate, endDate, objective: fd.get("objective"), participants, clients });
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
