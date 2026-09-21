window.PageModules = window.PageModules || {};
window.PageModules.clients = {
  init() {
    let state = Store.getState();
    let category = "Todos";
    let viewMode = "cards";
    let filtersOpen = false;
    const categories = ["Todos", "Carcinicultor", "Irrigação", "Construção civil", "Mineração", "Condominial", "Outro"];
    const clientCategory = (client) => {
      if (categories.includes(client.category)) return client.category;
      if (["Agropecuária", "Produção rural"].includes(client.segment)) return "Irrigação";
      return "Outro";
    };

    const applyViewMode = () => {
      const grid = UI.$("#clientGrid");
      if (!grid) return;
      const isList = viewMode === "list";
      grid.classList.toggle("client-list", isList);
      UI.$$("#clientGrid .client-card").forEach(card => card.classList.toggle("client-list-row", isList));
      UI.$$('[data-view]').forEach(button => button.classList.toggle("active", button.dataset.view === viewMode));
    };

    const render = () => {
      state = Store.getState();
      const list = state.clients.filter(c => {
        return category === "Todos" || clientCategory(c) === category;
      });
      const categoryCounts = Object.fromEntries(categories.map(item => [item, item === "Todos" ? state.clients.length : state.clients.filter(c => clientCategory(c) === item).length]));
      const browserLabel = category === "Todos" ? "Todos os clientes" : category;

      UI.$("#pageContent").innerHTML = `
        <style>
          #clientCategoryPanel {
            opacity: 0;
            pointer-events: none;
            transform: translateY(-8px);
            transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
          }
          #clientCategoryPanel.open {
            opacity: 1;
            pointer-events: auto;
            transform: translateY(0);
          }
          #clientFilterToggle .dropdown-icon {
            transition: transform 0.2s ease;
          }
          #clientFilterToggle.active .dropdown-icon {
            transform: rotate(180deg);
          }
        </style>
        <section class="client-browser-bar reveal" style="position:relative; z-index:20;">
          <div class="modern-dropdown-wrapper" style="position:relative; width:100%;">
            <button class="modern-dropdown-trigger ${filtersOpen ? "active" : ""}" id="clientFilterToggle" type="button" aria-expanded="${filtersOpen}" style="display:flex; justify-content:space-between; align-items:center; width:100%; max-width:100%; background:#fff; border:1px solid var(--line); border-radius:12px; padding:10px 14px; cursor:pointer; text-align:left; box-shadow:0 2px 5px rgba(0,0,0,0.02); transition:all 0.2s ease;">
              <span style="display:flex; flex-direction:column; align-items:flex-start; line-height:1.2;">
                <small style="font-size:10px; color:var(--muted); font-weight:800; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:2px;">Segmento de Clientes</small>
                <strong style="font-size:15px; color:var(--text);">${browserLabel}</strong>
              </span>
              <span class="dropdown-icon" style="color:var(--muted);">${UI.icon("chevron-down", 16)}</span>
            </button>
            
            <div class="modern-dropdown-menu ${filtersOpen ? "open" : ""}" id="clientCategoryPanel" style="position:absolute; top:calc(100% + 8px); left:0; width:100%; min-width:100%; max-width:100vw; background:#fff; border-radius:14px; box-shadow:0 12px 40px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.04); padding:8px; display:flex; flex-direction:column; gap:2px;">
              ${categories.map(item => `
                <button class="modern-dropdown-item ${item === category ? "active" : ""}" data-category="${item}" type="button" style="width:100%; display:flex; justify-content:space-between; align-items:center; padding:10px 14px; border:none; background:${item === category ? '#f3f8f5' : 'transparent'}; border-radius:8px; cursor:pointer; text-align:left; transition:background 0.15s ease;" onmouseover="this.style.background='${item === category ? '#f3f8f5' : '#f9fafa'}'" onmouseout="this.style.background='${item === category ? '#f3f8f5' : 'transparent'}'">
                  <span style="font-size:13px; font-weight:${item === category ? '750' : '500'}; color:${item === category ? 'var(--primary)' : 'var(--text)'};">${item}</span>
                  <small style="background:${item === category ? '#e1ecdf' : '#f0f3f1'}; padding:4px 8px; border-radius:999px; font-size:10px; font-weight:800; color:${item === category ? 'var(--primary-2)' : 'var(--muted)'};">${categoryCounts[item]}</small>
                </button>
              `).join("")}
            </div>
          </div>

          <div class="client-browser-actions">
            <div class="view-mode-toggle" aria-label="Modo de visualização">
              <button class="icon-btn ${viewMode === "cards" ? "active" : ""}" data-view="cards" type="button" aria-label="Exibir em cards" title="Cards">${UI.icon("grid", 17)}</button>
              <button class="icon-btn ${viewMode === "list" ? "active" : ""}" data-view="list" type="button" aria-label="Exibir em lista" title="Lista">${UI.icon("list", 18)}</button>
            </div>
            <button class="compact-create-btn" id="newClientBtn" type="button" title="Novo cliente">${UI.icon("plus", 18)}<span>Novo cliente</span></button>
          </div>
        </section>

        <section class="client-grid ${viewMode === "list" ? "client-list" : ""} reveal" id="clientGrid">
          ${list.length ? list.map(c => {
            const visits = state.visits.filter(v => v.clientId === c.id);
            const last = visits.sort((a,b) => new Date(b.date)-new Date(a.date))[0];
            return `
              <a class="client-card ${viewMode === "list" ? "client-list-row" : ""}" href="${UI.pageLink(`pages/cliente.html?id=${c.id}`)}">
                <div class="client-card-head"><span class="avatar client-avatar">${UI.initials(c.name)}</span><span>${UI.statusBadge(c.status)}</span></div>
                <div class="client-card-title"><h3>${c.name}</h3><span class="client-category-tag">${clientCategory(c)}</span></div>
                <p>${c.company}</p>
                <div class="client-meta"><span>${UI.icon("pin", 15)} ${c.city}, ${c.state}</span><span>${visits.length} visita(s)</span></div>
                <div class="client-card-foot"><span>${last ? `Última visita ${UI.date(last.date)}` : "Sem visitas"}</span>${UI.icon("chevron")}</div>
              </a>`;
          }).join("") : UI.empty("Nenhum cliente encontrado", "Ajuste a busca ou cadastre um novo cliente.")}
        </section>

        <dialog id="clientDialog" class="form-dialog large">
          <form method="dialog" id="clientForm">
            <div class="dialog-head"><div><span class="eyebrow">Cadastro rápido</span><h2>Novo cliente</h2></div><button class="icon-btn" value="cancel">${UI.icon("x")}</button></div>
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
              <div><span class="eyebrow">Localização rural</span><h3>Marque manualmente no mapa</h3><p>Clique na área aproximada para registrar coordenadas simuladas nesta demonstração.</p></div>
              <div class="manual-map" id="manualMap"><div class="map-grid"></div><span class="manual-pin">${UI.icon("pin", 20)}</span></div>
              <div class="coord-row"><label class="field"><span>Latitude</span><input id="latInput" name="lat" readonly></label><label class="field"><span>Longitude</span><input id="lngInput" name="lng" readonly></label></div>
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

      UI.$("#clientFilterToggle").addEventListener("click", () => {
        filtersOpen = !filtersOpen;
        UI.$("#clientCategoryPanel")?.classList.toggle("open", filtersOpen);
        const button = UI.$("#clientFilterToggle");
        button?.classList.toggle("active", filtersOpen);
        button?.setAttribute("aria-expanded", String(filtersOpen));
      });
      UI.$$('[data-category]').forEach(button => button.addEventListener("click", () => { category = button.dataset.category; filtersOpen = false; render(); }));
      UI.$$('[data-view]').forEach(button => button.addEventListener("click", () => {
        viewMode = button.dataset.view === "list" ? "list" : "cards";
        applyViewMode();
      }));
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
