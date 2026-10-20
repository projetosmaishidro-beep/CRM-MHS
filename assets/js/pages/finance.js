window.PageModules = window.PageModules || {};
window.PageModules.finance = {
  init() {
    const params = new URLSearchParams(location.search);
    let selectedTrip = params.get("trip") || "all";
    let attachment = null;

    const XLSX_CDN = "https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js";
    let xlsxLoader = null;

    const loadXlsx = () => {
      if (window.XLSX) return Promise.resolve(window.XLSX);
      if (xlsxLoader) return xlsxLoader;
      xlsxLoader = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = XLSX_CDN;
        script.async = true;
        script.onload = () => window.XLSX ? resolve(window.XLSX) : reject(new Error("Biblioteca de exportação não foi carregada."));
        script.onerror = () => reject(new Error("Não foi possível carregar a biblioteca de exportação."));
        document.head.appendChild(script);
      });
      return xlsxLoader;
    };

    const exportTripCosts = async (tripIds, state) => {
      const trips = state.trips.filter((trip) => tripIds.includes(String(trip.id)));
      const expenses = state.expenses
        .filter((expense) => expense.tripId && tripIds.includes(String(expense.tripId)))
        .sort((left, right) => new Date(left.date) - new Date(right.date));

      if (!trips.length) throw new Error("Selecione ao menos uma viagem.");

      const tripById = new Map(trips.map((trip) => [String(trip.id), trip]));
      const usersById = new Map((state.users || []).map((user) => [String(user.id), user]));
      const clientsById = new Map((state.clients || []).map((client) => [String(client.id), client]));
      const totals = new Map(trips.map((trip) => [String(trip.id), 0]));
      expenses.forEach((expense) => totals.set(String(expense.tripId), (totals.get(String(expense.tripId)) || 0) + Number(expense.amount || 0)));

      const namesFromSnapshot = (items, lookup) => (items || []).map((item) => {
        const id = typeof item === "string" ? item : item?.id;
        return lookup.get(String(id))?.name || item?.name || item?.nome || item?.empresa || id || "";
      }).filter(Boolean).join(", ");
      const tripContext = (trip) => ({
        id: trip?.id || "",
        name: trip?.name || "Viagem sem título",
        status: trip?.status || "",
        startDate: trip?.startDate || "",
        endDate: trip?.endDate || "",
        objective: trip?.objective || trip?.notes || "",
        participants: namesFromSnapshot(trip?.participantSnapshots?.length ? trip.participantSnapshots : trip?.participantIds, usersById),
        plannedClients: namesFromSnapshot(trip?.plannedClientSnapshots?.length ? trip.plannedClientSnapshots : trip?.plannedClientIds, clientsById),
        startKm: trip?.startKm ?? "",
        endKm: trip?.endKm ?? ""
      });
      const attachmentNames = (attachments) => (attachments || []).map((item) => typeof item === "string" ? item : item?.name || item?.path || "").filter(Boolean).join(" | ");

      const summaryRows = trips.map((trip) => {
        const context = tripContext(trip);
        return {
        "ID da viagem": context.id,
        "Viagem": context.name,
        "Status": context.status,
        "Início": context.startDate,
        "Fim": context.endDate,
        "Objetivo / observações": context.objective,
        "Participantes": context.participants,
        "Clientes planejados": context.plannedClients,
        "KM inicial": context.startKm,
        "KM final": context.endKm,
        "KM percorridos": Number.isFinite(Number(context.startKm)) && Number.isFinite(Number(context.endKm)) ? Number(context.endKm) - Number(context.startKm) : "",
        "Quantidade de despesas": expenses.filter((expense) => String(expense.tripId) === String(trip.id)).length,
        "Total (R$)": totals.get(String(trip.id)) || 0
        };
      });
      summaryRows.push({
        "ID da viagem": "",
        "Viagem": "TOTAL SELECIONADO",
        "Status": "",
        "Início": "",
        "Fim": "",
        "Objetivo / observações": "",
        "Participantes": "",
        "Clientes planejados": "",
        "KM inicial": "",
        "KM final": "",
        "KM percorridos": "",
        "Quantidade de despesas": expenses.length,
        "Total (R$)": expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0)
      });

      const detailRows = expenses.map((expense) => {
        const context = tripContext(tripById.get(String(expense.tripId)));
        return {
        "ID da despesa": expense.id || "",
        "Data": expense.date ? String(expense.date).slice(0, 10) : "",
        "ID da viagem": context.id,
        "Viagem": context.name,
        "Status da viagem": context.status,
        "Período da viagem": [context.startDate, context.endDate].filter(Boolean).join(" até "),
        "Objetivo / observações da viagem": context.objective,
        "Participantes da viagem": context.participants,
        "Clientes planejados": context.plannedClients,
        "Categoria": expense.category || "",
        "Centro de custo": expense.costCenter || "",
        "Estabelecimento": expense.place || "",
        "Observações": expense.notes || "",
        "Responsável": usersById.get(String(expense.userId))?.name || "",
        "Comprovantes / anexos": attachmentNames(expense.attachments),
        "Valor (R$)": Number(expense.amount || 0)
        };
      });

      const XLSX = await loadXlsx();
      const workbook = XLSX.utils.book_new();
      const summarySheet = XLSX.utils.json_to_sheet(summaryRows);
      const detailSheet = XLSX.utils.json_to_sheet(detailRows.length ? detailRows : [{ "ID da despesa": "", "Data": "", "ID da viagem": "", "Viagem": "Nenhuma despesa nas viagens selecionadas", "Status da viagem": "", "Período da viagem": "", "Objetivo / observações da viagem": "", "Participantes da viagem": "", "Clientes planejados": "", "Categoria": "", "Centro de custo": "", "Estabelecimento": "", "Observações": "", "Responsável": "", "Comprovantes / anexos": "", "Valor (R$)": "" }]);
      summarySheet["!cols"] = [{ wch: 18 }, { wch: 34 }, { wch: 18 }, { wch: 13 }, { wch: 13 }, { wch: 45 }, { wch: 36 }, { wch: 42 }, { wch: 13 }, { wch: 13 }, { wch: 16 }, { wch: 22 }, { wch: 16 }];
      detailSheet["!cols"] = [{ wch: 18 }, { wch: 13 }, { wch: 18 }, { wch: 34 }, { wch: 18 }, { wch: 26 }, { wch: 45 }, { wch: 36 }, { wch: 42 }, { wch: 18 }, { wch: 30 }, { wch: 30 }, { wch: 45 }, { wch: 26 }, { wch: 42 }, { wch: 16 }];
      XLSX.utils.book_append_sheet(workbook, summarySheet, "Resumo por viagem");
      XLSX.utils.book_append_sheet(workbook, detailSheet, "Despesas");
      XLSX.writeFile(workbook, `custos-viagens-${new Date().toISOString().slice(0, 10)}.xlsx`);
    };

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
          <button class="btn btn-secondary btn-small" id="exportTripCostsBtn" type="button">${UI.icon("download", 17)} Exportar viagens</button>
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

        <dialog id="tripExportDialog" class="form-dialog">
          <form method="dialog" id="tripExportForm">
            <div class="dialog-head"><div><span class="eyebrow">Exportação financeira</span><h2>Custos de viagens</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
            <p class="muted" style="margin:0 0 16px;">Selecione as viagens que devem entrar no arquivo Excel. Despesas de eventos não serão incluídas.</p>
            <label class="check-row" style="margin-bottom:10px;"><input type="checkbox" id="selectAllTrips" checked> <strong>Todas as viagens (${state.trips.length})</strong></label>
            <div class="expense-list" style="max-height:290px; overflow:auto; border:1px solid #e2e8f0; border-radius:12px; padding:4px 14px;">
              ${state.trips.length ? state.trips.map((trip, index) => `<label class="check-row" style="display:flex; gap:10px; padding:12px 0; border-bottom:1px solid #eef2f6;"><input class="trip-export-choice" type="checkbox" value="${UI.escape(String(trip.id))}" data-trip-index="${index}" checked><span><strong>${UI.escape(trip.name || "Viagem sem título")}</strong><small style="display:block;">${UI.escape(trip.startDate || "Sem data")} · ${UI.escape(trip.status || "Sem status")}</small></span></label>`).join("") : UI.empty("Nenhuma viagem", "Cadastre uma viagem para exportar seus custos.")}
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" id="confirmTripExportBtn" value="default" ${state.trips.length ? "" : "disabled"}>${UI.icon("download", 17)} Baixar Excel</button></div>
          </form>
        </dialog>
      `;

      UI.$("#tripFilter").addEventListener("change", e => { selectedTrip = e.target.value; render(); });
      UI.$("#newExpenseBtn").addEventListener("click", () => UI.openDialog("expenseDialog"));
      UI.$("#exportTripCostsBtn").addEventListener("click", () => UI.openDialog("tripExportDialog"));
      const selectAllTrips = UI.$("#selectAllTrips");
      const tripChoices = [...document.querySelectorAll(".trip-export-choice")];
      selectAllTrips?.addEventListener("change", () => tripChoices.forEach((choice) => { choice.checked = selectAllTrips.checked; }));
      tripChoices.forEach((choice) => choice.addEventListener("change", () => {
        if (!selectAllTrips) return;
        selectAllTrips.checked = tripChoices.length > 0 && tripChoices.every((item) => item.checked);
        selectAllTrips.indeterminate = !selectAllTrips.checked && tripChoices.some((item) => item.checked);
      }));
      UI.$("#tripExportForm").addEventListener("submit", async (event) => {
        if (event.submitter?.value === "cancel") return;
        event.preventDefault();
        const button = UI.$("#confirmTripExportBtn");
        const tripIds = tripChoices.filter((choice) => choice.checked).map((choice) => choice.value);
        if (!tripIds.length) {
          UI.toast("Selecione ao menos uma viagem para exportar.", "error");
          return;
        }
        try {
          button.disabled = true;
          button.textContent = "Gerando arquivo…";
          await exportTripCosts(tripIds, state);
          UI.closeDialog("tripExportDialog");
          UI.toast("Planilha de custos baixada com sucesso.");
        } catch (error) {
          console.error("[Central] Falha ao exportar custos de viagens:", error);
          UI.toast(error.message || "Não foi possível gerar a planilha.", "error");
        } finally {
          button.disabled = false;
          button.innerHTML = `${UI.icon("download", 17)} Baixar Excel`;
        }
      });
      UI.$("#receiptInput").addEventListener("change", e => {
        attachment = e.target.files?.[0] || null;
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
          const attachments = attachment ? [{
            name: attachment.name,
            size: attachment.size,
            type: attachment.type,
            ...(await UI.uploadPrivateFile(`despesas/${tripId || eventId}/${Date.now()}-${encodeURIComponent(attachment.name)}`, attachment))
          }] : [];
          const payload = {
            tripId,
            eventId,
            userId: "u1",
            category: fd.get("category"),
            costCenter: fd.get("costCenter"),
            amount: Number(fd.get("amount")),
            place: fd.get("place"),
            notes: fd.get("notes"),
            attachments
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
    };

    render();
  }
};
