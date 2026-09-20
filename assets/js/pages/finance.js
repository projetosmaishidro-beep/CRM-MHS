window.PageModules = window.PageModules || {};
window.PageModules.finance = {
  init() {
    const params = new URLSearchParams(location.search);
    let selectedTrip = params.get("trip") || "all";
    let attachment = null;

    const render = () => {
      const state = Store.getState();
      const events = state.events || [];
      const list = state.expenses.filter(e => {
        if (selectedTrip === "all") return true;
        if (selectedTrip.startsWith("t_") && e.tripId === selectedTrip.slice(2)) return true;
        if (selectedTrip.startsWith("e_") && e.eventId === selectedTrip.slice(2)) return true;
        if (selectedTrip === e.tripId) return true; // fallback
        return false;
      });
      const total = list.reduce((s,e)=>s+Number(e.amount),0);
      const byCategory = Object.entries(list.reduce((acc,e) => {
        acc[e.category] = (acc[e.category] || 0) + Number(e.amount);
        return acc;
      }, {})).sort((a,b)=>b[1]-a[1]);

      UI.$("#pageContent").innerHTML = `
        <section class="filter-bar finance-filter-bar reveal">
          <label class="field trip-filter"><span>Referência (Viagem ou Evento)</span>
            <select id="tripFilter">
              <option value="all">Todas as despesas</option>
              <optgroup label="Viagens">
                ${state.trips.map(t=>`<option value="t_${t.id}" ${"t_"+t.id===selectedTrip || t.id===selectedTrip ? "selected" : ""}>${t.name}</option>`).join("")}
              </optgroup>
              <optgroup label="Eventos">
                ${events.map(ev=>`<option value="e_${ev.id}" ${"e_"+ev.id===selectedTrip ? "selected" : ""}>${ev.name}</option>`).join("")}
              </optgroup>
            </select>
          </label>
          <div class="finance-total"><small>Total no filtro</small><strong>${UI.money(total)}</strong></div>
          <button class="btn btn-primary btn-small" id="newExpenseBtn">${UI.icon("plus", 17)} Nova despesa</button>
        </section>

        <section class="finance-layout reveal">
          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Resumo</span><h3>Por categoria</h3></div></div>
            <div class="category-bars">
              ${byCategory.length ? byCategory.map(([cat,value]) => {
                const pct = total ? Math.round(value/total*100) : 0;
                return `<div class="category-row"><div><span>${cat}</span><strong>${UI.money(value)}</strong></div><div class="progress"><span style="width:${pct}%"></span></div><small>${pct}%</small></div>`;
              }).join("") : `<span class="muted">Sem despesas neste filtro.</span>`}
            </div>
          </div>

          <div class="panel">
            <div class="panel-head"><div><span class="eyebrow">Lançamentos</span><h3>Histórico de despesas</h3></div><span class="count-pill">${list.length} registros</span></div>
            <div class="expense-list">
              ${list.length ? list.map(e => {
                const trip = state.trips.find(t=>t.id===e.tripId);
                const event = events.find(ev=>ev.id===e.eventId);
                const user = state.users.find(u=>u.id===e.userId);
                const refName = event ? event.name : (trip ? trip.name : "Avulsa");
                const iconTag = event ? UI.icon("calendar", 12) : UI.icon("briefcase", 12);
                
                return `<div class="expense-row"><span class="expense-icon">${UI.icon("receipt")}</span><div><div class="row-inline"><strong>${e.category}</strong><span class="tag subtle" style="display:flex; align-items:center; gap:4px;">${iconTag} ${refName}</span>${e.costCenter ? `<span class="tag subtle" style="background:#eef2f6; color:#475569; margin-left:6px;">${e.costCenter}</span>` : ""}</div><p>${e.place}${e.notes ? ` · ${e.notes}` : ""}</p><small>${UI.date(e.date)} · ${user?.name || "Usuário"} ${e.attachment ? "· comprovante anexado" : ""}</small></div><b>${UI.money(e.amount)}</b></div>`;
              }).join("") : UI.empty("Nenhuma despesa", "Adicione uma despesa para iniciar o controle financeiro.")}
            </div>
          </div>
        </section>

        <dialog id="expenseDialog" class="form-dialog">
          <form method="dialog" id="expenseForm">
            <div class="dialog-head"><div><span class="eyebrow">Lançamento rápido</span><h2>Nova despesa</h2></div><button class="icon-btn" value="cancel">${UI.icon("x")}</button></div>
            <div class="form-grid">
              <label class="field span-2"><span>Referência (Viagem ou Evento)</span>
                <select name="referenceId" required>
                  <option value="">Selecione...</option>
                  <optgroup label="Viagens">
                    ${state.trips.map(t=>`<option value="t_${t.id}">${t.name}</option>`).join("")}
                  </optgroup>
                  <optgroup label="Eventos">
                    ${events.map(ev=>`<option value="e_${ev.id}">${ev.name}</option>`).join("")}
                  </optgroup>
                </select>
              </label>
              <label class="field"><span>Categoria</span><select name="category"><option>Combustível</option><option>Alimentação</option><option>Hospedagem</option><option>Pedágio</option><option>Estacionamento</option><option>Outros</option></select></label>
              <label class="field"><span>Centro de Custo</span><select name="costCenter" required><option value="">Selecione...</option><option>Previsto em Margem Operacional</option><option>Prospecção (Novos Clientes)</option><option>Captação / Retenção</option><option>Verba de Manutenção (Frota)</option><option>Outros</option></select></label>
              <label class="field span-2"><span>Valor e Local</span><div style="display:grid; grid-template-columns:1fr 2fr; gap:10px;"><input name="amount" type="number" step="0.01" min="0" required inputmode="decimal" placeholder="R$ 0,00"><input name="place" required placeholder="Local ou estabelecimento"></div></label>
              <label class="field span-2"><span>Observações</span><textarea name="notes" rows="2"></textarea></label>
            </div>
            <label class="upload-card full">${UI.icon("camera",26)}<span><strong>Anexar comprovante ou nota fiscal</strong><small id="receiptLabel">Use a câmera ou selecione um arquivo</small></span><input type="file" id="receiptInput" accept="image/*,.pdf" capture="environment" hidden></label>
            <div class="dialog-actions"><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">Salvar despesa</button></div>
          </form>
        </dialog>
      `;

      UI.$("#tripFilter").addEventListener("change", e => { selectedTrip = e.target.value; render(); });
      UI.$("#newExpenseBtn").addEventListener("click", () => UI.openDialog("expenseDialog"));
      UI.$("#receiptInput").addEventListener("change", async e => {
        const arr = await UI.filesToAttachments(e.target.files);
        attachment = arr[0] || null;
        UI.$("#receiptLabel").textContent = attachment ? attachment.name : "Use a câmera ou selecione um arquivo";
      });
            UI.$("#expenseForm").addEventListener("submit", async e => {
        if (e.submitter?.value === "cancel") return;
        e.preventDefault();
        const btn = e.currentTarget.querySelector("button[type='submit']");
        const fd = new FormData(e.currentTarget);
        
        const refId = fd.get("referenceId");
        let tripId = null;
        let eventId = null;
        if (refId.startsWith("t_")) tripId = refId.slice(2);
        if (refId.startsWith("e_")) eventId = refId.slice(2);
        
        if (!tripId && !eventId) {
           UI.toast("Despesa deve estar vinculada a viagem ou evento.", "error");
           return;
        }

        if (btn) btn.disabled = true;

        try {
          const payload = {
            tripId,
            eventId,
            userId: "u1",
            category: fd.get("category"),
            costCenter: fd.get("costCenter"),
            amount: Number(fd.get("amount")),
            place: fd.get("place"),
            notes: fd.get("notes")
          };
          
          await UI.createSupabaseExpense(payload);
          UI.toast("Despesa salva com sucesso.");
          setTimeout(() => location.reload(), 350);
        } catch (err) {
          console.error(err);
          UI.toast("Erro ao salvar despesa.", "error");
          if (btn) btn.disabled = false;
        }
      });
        UI.toast("Despesa registrada.");
        attachment = null;
        UI.closeDialog("expenseDialog");
        render();
      });
    };

    render();
  }
};
