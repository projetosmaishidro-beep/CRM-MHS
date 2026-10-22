window.PageModules = window.PageModules || {};
window.PageModules.clients = {
  init() {
    let state = Store.getState();
    let category = "Todos";
    let viewMode = "cards";
    let search = "";
    let region = "";
    let statusFilter = "Todos";
    let page = 1;
    const pageSize = 12;
    const categories = ["Todos", "Carcinicultor", "Irrigação", "Construção civil", "Mineração", "Condominial", "Outro"];
    const clientCategory = (client) => {
      if (categories.includes(client.category)) return client.category;
      if (["Agropecuária", "Produção rural"].includes(client.segment)) return "Irrigação";
      return "Outro";
    };

    const applyViewMode = () => {
      const grid = UI.$("#clientGrid");
      const table = UI.$("#clientTableWrap");
      if (!grid || !table) return;
      const isList = viewMode === "list";
      grid.hidden = isList;
      table.hidden = !isList;
      UI.$$('[data-view]').forEach(button => { const active = button.dataset.view === viewMode; button.classList.toggle("active", active); button.setAttribute("aria-pressed", String(active)); });
    };

    const render = () => {
      state = Store.getState();
      const visitsByClient = new Map();
      state.visits.forEach(visit => { if (!visitsByClient.has(visit.clientId)) visitsByClient.set(visit.clientId, []); visitsByClient.get(visit.clientId).push(visit); });
      const normalize = value => String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
      const counts = { Todos: state.clients.length, Cliente: 0, Lead: 0, "Sem visitas": 0 };
      state.clients.forEach(client => { if (client.status === "Cliente") counts.Cliente++; if (["Lead", "Prospect"].includes(client.status)) counts.Lead++; if (!visitsByClient.get(client.id)?.length) counts["Sem visitas"]++; });
      const regions = [...new Set(state.clients.map(client => String(client.state || "").trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt-BR"));
      const query = normalize(search.trim());
      const usersById = new Map(state.users.map(user => [user.id, user]));
      const list = state.clients.filter(client => {
        const matchesText = !query || normalize([client.name, client.company, client.city, client.segment, clientCategory(client)].join(" ")).includes(query);
        const matchesStatus = statusFilter === "Todos" || (statusFilter === "Sem visitas" ? !visitsByClient.get(client.id)?.length : statusFilter === "Lead" ? ["Lead", "Prospect"].includes(client.status) : client.status === statusFilter);
        return matchesText && matchesStatus && (category === "Todos" || clientCategory(client) === category) && (!region || String(client.state || "").trim() === region);
      });
      const pages = Math.max(1, Math.ceil(list.length / pageSize));
      page = Math.min(page, pages);
      const visible = list.slice((page - 1) * pageSize, page * pageSize);
      const escape = UI.escape;
      const displayed = visible.map(client => {
        const visits = visitsByClient.get(client.id) || [];
        const validDates = visits.map(visit => visit.date ? new Date(/^\d{4}-\d{2}-\d{2}$/.test(String(visit.date)) ? `${visit.date}T12:00:00` : visit.date) : null).filter(date => date && Number.isFinite(date.getTime())).sort((a, b) => b - a);
        const last = validDates[0];
        return {
          client,
          visitCount: visits.length,
          lastLabel: last ? new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" }).format(last) : visits.length ? "Data indisponível" : "Sem visitas",
          ownerName: usersById.get(client.ownerId)?.name || "Não informado",
          location: [client.city, client.state].filter(value => value && value !== "Não informado").join(", ") || "Local não informado"
        };
      });

      UI.$("#pageContent").innerHTML = `
        <section class="clients-overview" aria-label="Resumo da carteira">
          <div class="clients-overview-item"><span class="clients-overview-icon clients-icon-blue">${UI.icon("users", 21)}</span><div><small>Total de clientes</small><strong>${counts.Todos}</strong><span>Na carteira</span></div></div>
          <div class="clients-overview-item"><span class="clients-overview-icon clients-icon-green">${UI.icon("user", 21)}</span><div><small>Clientes</small><strong>${counts.Cliente}</strong><span>Relacionamento cliente</span></div></div>
          <div class="clients-overview-item"><span class="clients-overview-icon clients-icon-amber">${UI.icon("grid", 21)}</span><div><small>Leads e prospects</small><strong>${counts.Lead}</strong><span>Oportunidades na carteira</span></div></div>
          <div class="clients-overview-item"><span class="clients-overview-icon clients-icon-red">${UI.icon("pin", 21)}</span><div><small>Sem visitas</small><strong>${counts["Sem visitas"]}</strong><span>Sem registros de visita</span></div></div>
        </section>
        <section class="clients-controls" aria-label="Filtros de clientes">
          <label class="clients-search">${UI.icon("search", 18)}<span class="clients-sr-only">Buscar clientes</span><input id="clientSearch" type="search" placeholder="Buscar por nome, cidade ou segmento" autocomplete="off"></label>
          <label><span class="clients-sr-only">Filtrar por segmento</span><select id="clientCategory"><option value="Todos">Todos os segmentos</option>${categories.slice(1).map(item => `<option value="${escape(item)}">${escape(item)}</option>`).join("")}</select></label>
          <label><span class="clients-sr-only">Filtrar por estado</span><select id="clientRegion"><option value="">Todos os estados</option>${regions.map(item => `<option value="${escape(item)}">${escape(item)}</option>`).join("")}</select></label>
          <div class="client-browser-actions"><div class="view-mode-toggle" role="group" aria-label="Modo de visualização"><button class="icon-btn ${viewMode === "cards" ? "active" : ""}" data-view="cards" type="button" aria-label="Exibir em cartões" title="Cartões">${UI.icon("grid", 17)}</button><button class="icon-btn ${viewMode === "list" ? "active" : ""}" data-view="list" type="button" aria-label="Exibir em tabela" title="Tabela">${UI.icon("list", 18)}</button></div><button class="compact-create-btn" id="newClientBtn" type="button" title="Novo cliente">${UI.icon("plus", 18)}<span>Novo cliente</span></button></div>
        </section>
        <nav class="clients-tabs" aria-label="Filtrar carteira por situação">${[["Todos", "Todos"], ["Cliente", "Clientes"], ["Lead", "Leads e prospects"], ["Sem visitas", "Sem visitas"]].map(([value, label]) => `<button type="button" data-client-status="${value}" class="${statusFilter === value ? "active" : ""}" aria-pressed="${statusFilter === value}"><span>${label}</span><strong>${counts[value]}</strong></button>`).join("")}</nav>
        <section class="client-grid" id="clientGrid" aria-label="Clientes encontrados">
          ${displayed.length ? displayed.map(({ client: c, visitCount, lastLabel, ownerName, location }) => {
            return `<a class="client-card" href="${UI.pageLink(`pages/cliente.html?id=${encodeURIComponent(c.id)}`)}">
              <div class="client-card-heading"><span class="avatar client-avatar">${escape(UI.initials(c.name || "Cliente"))}</span><div class="client-card-name"><h3>${escape(c.name || "Cliente")}</h3><p>${escape(c.company || "")}</p></div><div class="client-card-tags">${UI.statusBadge(c.status)}<span class="client-category-tag">${escape(clientCategory(c))}</span></div></div>
              <div class="client-card-location">${UI.icon("pin", 16)}<span>${escape(location)}</span></div>
              <div class="client-card-details"><div>${UI.icon("calendar", 16)}<span><strong>${visitCount}</strong><small>Visitas</small></span></div><div>${UI.icon("clock", 16)}<span><strong>${escape(lastLabel)}</strong><small>Última visita</small></span></div><div>${UI.icon("user", 16)}<span><strong>${escape(ownerName)}</strong><small>Responsável</small></span></div><span class="client-card-arrow">${UI.icon("chevron", 17)}</span></div>
            </a>`;
          }).join("") : UI.empty("Nenhum cliente encontrado", "Ajuste os filtros ou cadastre um novo cliente.")}
        </section>
        <div class="clients-table-wrap" id="clientTableWrap" role="region" aria-label="Lista de clientes" tabindex="0" hidden>
          ${displayed.length ? `<table class="clients-table">
            <thead><tr><th scope="col">Cliente</th><th scope="col">Situação / segmento</th><th scope="col">Localização</th><th scope="col">Visitas</th><th scope="col">Última visita</th><th scope="col">Responsável</th><th scope="col"><span class="clients-sr-only">Abrir ficha</span></th></tr></thead>
            <tbody>${displayed.map(({ client: c, visitCount, lastLabel, ownerName, location }) => {
              const href = UI.pageLink(`pages/cliente.html?id=${encodeURIComponent(c.id)}`);
              return `<tr>
                <th scope="row"><a class="clients-table-client" href="${href}"><span class="avatar client-avatar">${escape(UI.initials(c.name || "Cliente"))}</span><span class="clients-table-client-name"><strong>${escape(c.name || "Cliente")}</strong><small>${escape(c.company || "")}</small></span></a></th>
                <td><span class="clients-table-tags">${UI.statusBadge(c.status)}<span class="client-category-tag">${escape(clientCategory(c))}</span></span></td>
                <td>${escape(location)}</td><td class="clients-table-number">${visitCount}</td><td>${escape(lastLabel)}</td><td>${escape(ownerName)}</td>
                <td><a class="clients-table-open" href="${href}" aria-label="Abrir ficha de ${escape(c.name || "Cliente")}">${UI.icon("chevron", 17)}</a></td>
              </tr>`;
            }).join("")}</tbody>
          </table>` : UI.empty("Nenhum cliente encontrado", "Ajuste os filtros ou cadastre um novo cliente.")}
        </div>
        <div class="clients-pagination"><span>${list.length ? `Mostrando ${(page - 1) * pageSize + 1} a ${Math.min(page * pageSize, list.length)} de ${list.length}` : "Nenhum cliente encontrado"}</span><div><button type="button" id="clientsPrev" aria-label="Página anterior" ${page <= 1 ? "disabled" : ""}>${UI.icon("arrow_left", 16)}</button><strong>${page} / ${pages}</strong><button type="button" id="clientsNext" aria-label="Próxima página" ${page >= pages ? "disabled" : ""}>${UI.icon("arrow", 16)}</button></div></div>

        <dialog id="clientDialog" class="form-dialog large client-create-dialog">
          <form method="dialog" id="clientForm">
            <div class="dialog-head"><div><span class="eyebrow">Cadastro rápido</span><h2>Novo cliente</h2></div><button class="icon-btn" value="cancel">${UI.icon("x")}</button></div>
            <div class="client-create-scroll">
            <div class="form-grid">
              <label class="field span-2"><span>Nome do cliente / propriedade</span><input name="name" required placeholder="Ex.: Fazenda Santa Clara"></label>
              <label class="field span-2"><span>Razão ou nome empresarial</span><input name="company" placeholder="Opcional"></label>
              <label class="field"><span>Contato principal</span><input name="contact"></label>
              <label class="field"><span>Telefone</span><input name="phone" inputmode="tel"></label>
              <label class="field"><span>Cidade</span><input name="city" required></label>
              <label class="field"><span>Estado</span><input name="state" value="CE" maxlength="2"></label>
              <label class="field"><span>Categoria</span><select name="category">${categories.slice(1).map(item => `<option>${item}</option>`).join("")}</select></label>
              <label class="field"><span>Status</span><select name="status"><option>Lead</option><option>Prospect</option><option>Cliente</option></select></label>
              <label class="field"><span>Origem da Captação</span><select id="originSelect" name="origin"><option>Prospecção Ativa</option><option>Indicação</option><option>Inbound Marketing</option><option>Feira / Evento</option><option>Mapa</option><option>Outros</option></select></label>
              <label class="field" id="originEventField" style="display:none;"><span>Evento de Origem</span><select name="originEventId"><option value="">Selecione a feira...</option>${(state.events||[]).map(ev => `<option value="${ev.id}">${ev.name}</option>`).join("")}</select></label>
              <label class="field span-2"><span>Observação inicial</span><textarea name="notes" rows="3"></textarea></label>
            </div>
            <div class="location-card">
              <div><span class="eyebrow">Localização rural</span><h3>Marque manualmente no mapa</h3><p>Clique no mapa para marcar a localização aproximada do cliente.</p></div>
              <div class="manual-map" id="manualMap"><div class="map-grid"></div><span class="manual-pin">${UI.icon("pin", 20)}</span></div>
              <div class="coord-row"><label class="field"><span>Latitude</span><input id="latInput" name="lat" readonly></label><label class="field"><span>Longitude</span><input id="lngInput" name="lng" readonly></label></div>
            </div>
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">Salvar cliente</button></div>
          </form>
        </dialog>
      `;

      UI.$("#originSelect")?.addEventListener("change", e => {
        const evField = UI.$("#originEventField");
        if (evField) {
          evField.style.display = e.target.value === "Feira / Evento" ? "flex" : "none";
          if (e.target.value !== "Feira / Evento") evField.querySelector("select").value = "";
        }
      });

      const searchInput = UI.$("#clientSearch");
      searchInput.value = search;
      UI.$("#clientCategory").value = category;
      UI.$("#clientRegion").value = region;
      searchInput.addEventListener("input", () => {
        const position = searchInput.selectionStart;
        search = searchInput.value; page = 1; render();
        const input = UI.$("#clientSearch");
        input.focus();
        if (position != null) input.setSelectionRange(position, position);
      });
      UI.$("#clientCategory").addEventListener("change", e => { category = e.target.value; page = 1; render(); });
      UI.$("#clientRegion").addEventListener("change", e => { region = e.target.value; page = 1; render(); });
      UI.$$('[data-client-status]').forEach(button => button.addEventListener("click", () => { statusFilter = button.dataset.clientStatus; page = 1; render(); }));
      UI.$("#clientsPrev").addEventListener("click", () => { if (page > 1) { page--; render(); } });
      UI.$("#clientsNext").addEventListener("click", () => { if (page < pages) { page++; render(); } });
      UI.$$('[data-view]').forEach(button => button.addEventListener("click", () => {
        viewMode = button.dataset.view === "list" ? "list" : "cards";
        applyViewMode();
      }));
      applyViewMode();
      UI.$("#newClientBtn").addEventListener("click", () => {
        UI.openDialog("clientDialog");
        UI.setupManualMap(UI.$("#manualMap"), UI.$("#latInput"), UI.$("#lngInput"));
      });
      UI.$("#clientForm").addEventListener("submit", async (e) => {
        if (e.submitter?.value === "cancel") return;
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        const payload = {
          name: fd.get("name"),
          company: fd.get("company") || fd.get("name"),
          contact: fd.get("contact"),
          phone: fd.get("phone"),
          email: "",
          city: fd.get("city"),
          state: fd.get("state") || "CE",
          segment: fd.get("category"),
          category: fd.get("category"),
          status: fd.get("status"),
          origin: fd.get("origin"),
          originEventId: fd.get("originEventId") || null,
          lat: Number(fd.get("lat")) || null,
          lng: Number(fd.get("lng")) || null,
          notes: fd.get("notes"),
          needs: []
        };
        const submitButton = e.submitter || e.currentTarget.querySelector('button[value="default"]');
        try {
          if (submitButton) submitButton.disabled = true;
          await UI.createSupabaseClientRecord(payload);
          await UI.hydrateSupabaseSnapshot();
          UI.toast("Cliente cadastrado com sucesso.");
          UI.closeDialog("clientDialog");
          render();
        } catch (error) {
          console.error(error);
          UI.toast(error.message || "Não foi possível cadastrar o cliente.", "error");
        } finally {
          if (submitButton) submitButton.disabled = false;
        }
      });
    };

    render();
  }
};
