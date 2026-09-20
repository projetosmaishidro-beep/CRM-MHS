window.PageModules = window.PageModules || {};
window.PageModules.trips = {
  init() {
    const render = () => {
      const state = Store.getState();
      const remoteMode = Boolean(state.remoteSource?.active);
      UI.$("#pageContent").innerHTML = `
        <section class="trip-board reveal">
          <button class="trip-create-card" id="newTripBtn" type="button">${UI.icon("plus", 22)}<span>Nova viagem</span></button>
          ${state.trips.map(trip => {
            const visits = state.visits.filter(v => v.tripId === trip.id);
            const expenses = state.expenses.filter(e => e.tripId === trip.id);
            const participants = trip.participantIds.map(id => state.users.find(u => u.id === id)).filter(Boolean);
            const progress = Math.round((trip.stops.filter(s => s.done).length / Math.max(trip.stops.length, 1)) * 100);
            return `
              <a class="trip-card" href="${UI.pageLink(`pages/viagem.html?id=${trip.id}`)}">
                <div class="trip-card-top">
                  <span>${UI.statusBadge(trip.status)}</span>
                  <div style="display:flex; gap:6px; align-items:center;">
                    <span class="date-chip">${UI.shortDate(trip.startDate)} â†’ ${UI.shortDate(trip.endDate)}</span>
                    ${window.AuthUser?.isAdmin ? `<button class="mini-trash-btn" data-delete-trip="${trip.id}" aria-label="Excluir viagem" title="Excluir viagem"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg></button>` : ""}
                  </div>
                </div>
                
                <div>
                  <h3>${trip.name}</h3>
                  <p>${trip.objective}</p>
                </div>
                
                <div class="trip-stats">
                  <span><small>participantes</small><strong>${participants.length}</strong></span>
                  <span><small>visitas</small><strong>${visits.length}</strong></span>
                  <span><small>gastos</small><strong>${UI.money(expenses.reduce((s,e)=>s+Number(e.amount),0))}</strong></span>
                </div>
                
                <div style="margin-top: auto; display: flex; flex-direction: column; gap: 6px;">
                  <div class="progress-row"><span>Roteiro</span><strong>${progress}%</strong></div>
                  <div class="progress"><span style="width:${progress}%"></span></div>
                  <div class="avatar-stack" style="margin-top: 2px;">${participants.map(u => `<span class="avatar mini">${u.initials}</span>`).join("")}</div>
                </div>
              </a>`;
          }).join("")}
        </section>

        <dialog id="tripDialog" class="form-dialog large trip-dialog">
          <form method="dialog" id="tripForm">
            <div class="dialog-head trip-dialog-head"><div><span class="eyebrow">Planejamento</span><h2>Nova viagem</h2><p>Monte a ficha da viagem com equipe e clientes antes de sair a campo.</p></div><button class="icon-btn" value="cancel" aria-label="Fechar nova viagem">${UI.icon("x")}</button></div>
            <div class="trip-form-scroll">
            <div class="form-grid trip-form-grid">
              <label class="field span-2"><span>Nome da viagem</span><input name="name" required placeholder="Ex.: Circuito Cariri"></label>
              <label class="field"><span>Data de inÃ­cio</span><input name="startDate" type="date" required></label>
              <label class="field"><span>Data final</span><input name="endDate" type="date" required></label>
              <label class="field span-2"><span>Objetivo</span><textarea name="objective" rows="3" required></textarea></label>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Participantes</legend><p class="checklist-hint">Selecione quem participa desta operaÃ§Ã£o.</p>${state.users.map(u => `<label><input type="checkbox" name="participant" value="${u.id}"><span class="avatar mini">${u.initials}</span><span class="checklist-name">${u.name}</span></label>`).join("")}</fieldset>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Clientes planejados</legend><p class="checklist-hint">Marque os clientes que entram no roteiro desta viagem.</p>${state.clients.map(c => `<label><input type="checkbox" name="client" value="${c.id}"><span class="checklist-name">${c.name}</span><small>${c.city || "Cidade nÃ£o informada"}</small></label>`).join("")}</fieldset>
            </div>
            </div>
            <div class="dialog-actions trip-dialog-actions"><span class="trip-form-status">${remoteMode ? "A viagem serÃ¡ gravada no banco unificado." : "Modo demonstraÃ§Ã£o: a viagem serÃ¡ gravada somente neste navegador."}</span><div><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">${remoteMode ? "Salvar no banco" : "Criar viagem"}</button></div></div>
          </form>
        </dialog>
      `;

      const tripDialog = UI.$("#tripDialog");
      const tripForm = UI.$("#tripForm");
      UI.$("#newTripBtn").addEventListener("click", () => {
        tripForm.reset();
        UI.openDialog("tripDialog");
        requestAnimationFrame(() => tripForm.querySelector("input[name=name]")?.focus());
      });
      
      UI.$(".trip-board")?.addEventListener("click", e => {
        const trashBtn = e.target.closest(".mini-trash-btn");
        if (trashBtn) {
          e.preventDefault();
          e.stopPropagation();
          const tripId = trashBtn.dataset.deleteTrip;
          if (confirm("Tem certeza que deseja excluir esta viagem? Esta aÃ§Ã£o apagarÃ¡ as visitas e despesas associadas e Ã© irreversÃ­vel.")) {
            Store.deleteTrip(tripId);
            UI.toast("Viagem excluÃ­da com sucesso.");
            render();
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
          UI.toast("A data final precisa ser posterior Ã  data inicial.", "error");
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
          submitButton.textContent = "Salvandoâ€¦";
        }
        try {
          if (Store.getState().remoteSource?.active) {
            const currentState = Store.getState();
            const participants = currentState.users
              .filter(user => payload.participantIds.includes(user.id))
              .map(user => ({ id: user.id, name: user.name, initials: user.initials, role: user.role }));
            const clients = currentState.clients
              .filter(client => payload.plannedClientIds.includes(client.id))
              .map(client => ({ id: client.id, name: client.name, city: client.city, state: client.state }));
            const created = await UI.createRemoteTrip({
              ...payload,
              participants,
              clients
            });
            Store.setRemoteTrips([created, ...Store.getState().trips]);
            UI.toast("Viagem salva no banco unificado.");
          } else {
            Store.addTrip(payload);
            UI.toast("Viagem criada localmente.");
          }
          UI.closeDialog("tripDialog");
          render();
        } catch (error) {
          UI.toast(error.message || "NÃ£o foi possÃ­vel salvar a viagem.", "error");
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
