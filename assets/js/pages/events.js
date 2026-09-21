window.PageModules = window.PageModules || {};
window.PageModules.events = {
  init() {
    const render = () => {
      const state = Store.getState();
      const events = state.events || [];
      const expenses = state.expenses || [];
      
      const totalInvested = expenses.filter(e => e.eventId).reduce((sum, e) => sum + Number(e.amount), 0);
      const concludedEvents = events.filter(e => e.status === 'Concluído');
      const upcomingEvents = events.filter(e => e.status !== 'Concluído');
      
      const getBaseName = (name) => name.replace(/\b(20\d{2}|\d{2})\b/g, '').trim().toUpperCase();
      const editionsCount = {};
      
      const eventsWithEditions = [...events].sort((a,b) => new Date(a.startDate) - new Date(b.startDate)).map(ev => {
          const base = getBaseName(ev.name);
          editionsCount[base] = (editionsCount[base] || 0) + 1;
          return { ...ev, _edition: editionsCount[base] };
      });

      const sortedEvents = [
        ...eventsWithEditions.filter(e => e.status !== 'Concluído').sort((a,b) => new Date(a.startDate) - new Date(b.startDate)),
        ...eventsWithEditions.filter(e => e.status === 'Concluído').sort((a,b) => new Date(b.startDate) - new Date(a.startDate))
      ];

      UI.$("#pageContent").innerHTML = `
        <section class="trip-quick-metrics reveal" style="margin-bottom: 24px;">
          <article><span>Investimento Global</span><strong style="color:var(--primary);">${UI.money(totalInvested)}</strong><small>Total alocado em eventos</small></article>
          <article><span>Histórico</span><strong>${concludedEvents.length}</strong><small>Eventos realizados</small></article>
          <article><span>Radar</span><strong>${upcomingEvents.length}</strong><small>Próximos eventos</small></article>
        </section>

        <section class="trip-board reveal">
          <button class="trip-create-card" id="newEventBtn" type="button" style="border-style:dashed;">${UI.icon("calendar", 22)}<span>Novo Evento</span></button>
          ${sortedEvents.length === 0 ? `
            <div style="grid-column:1/-1; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:12px; padding:48px 16px; color:var(--muted); text-align:center;">
              ${UI.icon("calendar", 40)}
              <p style="font-size:15px; font-weight:600;">Nenhum evento registrado ainda</p>
              <small>Clique em "Novo Evento" para começar, ou aguarde a sincronização com o banco de dados.</small>
            </div>` : sortedEvents.map(ev => {
            const evExpenses = expenses.filter(e => e.eventId === ev.id);
            const totalEvCost = evExpenses.reduce((s,e) => s + Number(e.amount), 0);
            const participants = (ev.participantIds || []).map(id => state.users.find(u => u.id === id)).filter(Boolean);
            const editionBadge = ev._edition > 1 ? `<span class="tag tag-accent" style="font-size:10px; padding:2px 6px;">${ev._edition}Âª Edição</span>` : "";
            
            return `
              <a class="trip-card ${ev.status === 'Concluído' ? 'opacity-80' : ''}" href="${UI.pageLink(`pages/evento.html?id=${ev.id}`)}">
                <div class="trip-card-top">
                  <div style="display:flex; gap:6px; align-items:center;">
                    ${UI.statusBadge(ev.status)}
                    ${editionBadge}
                  </div>
                  <div style="display:flex; gap:6px; align-items:center;">
                    <span class="date-chip">${UI.shortDate(ev.startDate)} → ${UI.shortDate(ev.endDate)}</span>
                  </div>
                </div>
                
                <div>
                  <h3 style="margin-top:6px;">${ev.name}</h3>
                  <div style="display:flex; gap:10px; margin-top:4px;">
                    <span style="color:var(--muted); font-size:11px;">${UI.icon("map", 12)} ${ev.location}</span>
                    <span style="color:var(--primary-2); font-size:11px; font-weight:800;">${ev.role === 'Expositor' ? UI.icon("star", 12) : UI.icon("briefcase", 12)} ${ev.role || 'Participante'}</span>
                  </div>
                  <p style="margin-top:6px; min-height: 40px;">${ev.notes}</p>
                </div>
                
                <div class="trip-stats" style="margin-top: 12px; grid-template-columns: 1fr 1.5fr; background: var(--bg-body); border-radius: 6px; padding: 8px;">
                  <span><small>Equipe</small><strong style="font-size:14px;">${participants.length}</strong></span>
                  <span><small>Investimento</small><strong style="font-size:14px; color:var(--primary);">${UI.money(totalEvCost)}</strong></span>
                </div>
                
                <div style="margin-top: auto; display: flex; flex-direction: column; gap: 6px;">
                  <div class="avatar-stack" style="margin-top: 10px;">${participants.length ? participants.map(u => `<span class="avatar mini" title="${u.name}">${u.initials}</span>`).join("") : `<span style="font-size:12px; color:var(--muted);">Equipe não definida</span>`}</div>
                </div>
              </a>`;
          }).join("")}
        </section>

        <dialog id="eventDialog" class="form-dialog large trip-dialog">
          <form method="dialog" id="eventForm">
            <div class="dialog-head trip-dialog-head"><div><span class="eyebrow">Planejamento</span><h2>Novo Evento</h2><p>Cadastre os dados de uma feira ou evento corporativo.</p></div><button class="icon-btn" value="cancel" aria-label="Fechar novo evento">${UI.icon("x")}</button></div>
            <div class="trip-form-scroll">
            <div class="form-grid trip-form-grid">
              <label class="field span-2"><span>Nome do Evento</span><input name="name" required placeholder="Ex.: Agrishow 2026"></label>
              <label class="field"><span>Data de início</span><input name="startDate" type="date" required></label>
              <label class="field"><span>Data final</span><input name="endDate" type="date" required></label>
              <label class="field"><span>Tipo de Participação</span><select name="role"><option>Participante</option><option>Expositor</option></select></label>
              <label class="field"><span>Local (Cidade/Estado)</span><input name="location" required placeholder="Ex.: Ribeirão Preto, SP"></label>
              <label class="field span-2"><span>Descrição Estratégica</span><textarea name="notes" rows="3" required placeholder="Qual o foco desta participação?"></textarea></label>
              <fieldset class="field span-2 checklist trip-checklist"><legend>Equipe Participante</legend><p class="checklist-hint">Selecione quem irá ao evento.</p>${(Store.getState().users || []).map(u => `<label><input type="checkbox" name="participant" value="${u.id}"><span class="avatar mini">${u.initials}</span><span class="checklist-name">${u.name}</span></label>`).join("")}</fieldset>
            </div>
            </div>
            <div class="dialog-actions trip-dialog-actions"><span class="trip-form-status" id="eventFormStatus">O evento será salvo no banco de dados.</span><div><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">Criar Evento</button></div></div>
          </form>
        </dialog>
      `;

      const eventDialog = UI.$("#eventDialog");
      const eventForm = UI.$("#eventForm");
      UI.$("#newEventBtn").addEventListener("click", () => {
        eventForm.reset();
        UI.openDialog("eventDialog");
        requestAnimationFrame(() => eventForm.querySelector("input[name=name]")?.focus());
      });
      
      eventDialog.addEventListener("close", () => eventForm.reset());
      eventForm.addEventListener("submit", async (e) => {
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
          location: fd.get("location"),
          role: fd.get("role") || "Participante",
          notes: fd.get("notes"),
          participantIds: fd.getAll("participant")
        };
        const submitButton = e.submitter || eventForm.querySelector('button[value="default"]');
        const originalLabel = submitButton?.textContent || "Salvar";
        if (submitButton) {
          submitButton.disabled = true;
          submitButton.textContent = "Salvandoâ€¦";
        }
        
        try {
          const created = await UI.createSupabaseEvent(payload);
          if (payload.participantIds.length) {
            await UI.updateSupabaseEvent(created.id, { participantIds: payload.participantIds });
          }
          await UI.hydrateSupabaseSnapshot();
          UI.toast("Evento criado no banco de dados.");
          UI.closeDialog("eventDialog");
          render();
        } catch (error) {
          console.error(error);
          UI.toast(error.message || "Não foi possível criar o evento.", "error");
        } finally {
          if (submitButton) {
            submitButton.disabled = false;
            submitButton.textContent = originalLabel;
          }
        }
      });
    };

    // Renderiza imediatamente com o que há no cache
    render();

    // Re-renderiza quando a hidratação remota concluir (evento store:changed)
    const onStoreChange = () => render();
    window.addEventListener("store:changed", onStoreChange, { once: true });

  }
};
