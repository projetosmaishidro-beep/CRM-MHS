window.PageModules = window.PageModules || {};
window.PageModules["new-visit"] = {
  init() {
    const state = Store.getState();
    const params = new URLSearchParams(location.search);
    const preselected = params.get("client") || "";
    const preselectedTrip = params.get("trip") || "";
    let attachments = [];
    let geo = { lat: null, lng: null };

    UI.$("#pageContent").innerHTML = `
      <section class="form-page reveal">
        <div class="form-page-head">
          <div><h2>Nova visita</h2></div>
        </div>

        <form id="visitForm" class="smart-form">
          <section class="form-section">
            <div class="section-number">1</div>
            <div class="section-body">
              <h3>Quem foi visitado?</h3>
              <p>Selecione um cliente ou registre um novo lead sem sair da tela.</p>
              <div class="segmented" role="tablist">
                <button type="button" class="active" data-mode="existing">Cliente existente</button>
                <button type="button" data-mode="lead">Novo lead</button>
              </div>
              <div id="existingClientFields">
                <label class="field" style="position: relative;">
                  <span>Buscar cliente</span>
                  <input type="text" id="clientSearchInput" placeholder="Digite nome ou cidade..." autocomplete="off">
                  <input type="hidden" name="clientId" id="clientSelect" value="${preselected}">
                  <div id="clientAutocompleteList" style="display:none; position:absolute; top:100%; left:0; right:0; max-height:240px; overflow-y:auto; background:#fff; border:1px solid var(--line); border-radius:12px; box-shadow:0 8px 30px rgba(0,0,0,0.15); z-index:50; margin-top:6px;"></div>
                </label>
              </div>
              <div id="newLeadFields" class="hidden">
                <div class="form-grid">
                  <label class="field span-2"><span>Nome / propriedade</span><input name="leadName" placeholder="Nome do novo lead"></label>
                  <label class="field"><span>Contato</span><input name="leadContact"></label>
                  <label class="field"><span>Telefone</span><input name="leadPhone" inputmode="tel"></label>
                  <label class="field"><span>Cidade</span><input name="leadCity"></label>
                  <label class="field"><span>Estado</span><input name="leadState" value="CE" maxlength="2"></label>
                </div>
              </div>
            </div>
          </section>

          <section class="form-section">
            <div class="section-number">2</div>
            <div class="section-body">
              <h3>Contexto da visita</h3>
              <div class="form-grid">
                <label class="field"><span>Tipo</span><select name="type"><option>Acompanhamento</option><option>Prospecção</option><option>Relacionamento</option><option>Suporte</option></select></label>
                <label class="field"><span>Viagem relacionada</span><select name="tripId"><option value="">Sem viagem</option>${state.trips.map(t => `<option value="${t.id}" ${t.id === preselectedTrip ? "selected" : ""}>${t.name}</option>`).join("")}</select></label>
                <label class="field span-2"><span>O que aconteceu?</span><textarea name="notes" rows="4" required placeholder="Resumo curto da conversa, observações e próximos passos."></textarea></label>
                <label class="field span-2"><span>Necessidades identificadas</span><input name="needs" placeholder="Separe por vírgulas: logística, proposta, acompanhamento..."></label>
              </div>
            </div>
          </section>

          <section class="form-section">
            <div class="section-number">3</div>
            <div class="section-body">
              <h3>Evidências e localização</h3>
              <p>Use a câmera do celular ou selecione arquivos já existentes.</p>
              <div class="upload-grid">
                <label class="upload-card">${UI.icon("camera", 26)}<span><strong>Tirar foto</strong><small>Abre a câmera quando suportado</small></span><input type="file" id="cameraInput" accept="image/*" capture="environment" hidden></label>
                <label class="upload-card">${UI.icon("paperclip", 26)}<span><strong>Anexar arquivos</strong><small>Fotos, vídeos e documentos</small></span><input type="file" id="fileInput" accept="image/*,video/*,.pdf" multiple hidden></label>
              </div>
              <div id="attachmentPreview" class="attachment-preview"></div>

              <div class="geo-row">
                <button class="btn btn-secondary" type="button" id="geoBtn">${UI.icon("pin")} Usar localização atual</button>
                <span id="geoStatus" class="muted">Opcional. Requer permissão do dispositivo.</span>
              </div>
            </div>
          </section>

          <div class="sticky-submit">
            <span><strong>Pronto para salvar?</strong><small>O registro será incluído no histórico do cliente e da viagem.</small></span>
            <button class="btn btn-primary btn-large" type="submit">${UI.icon("check")} Salvar visita</button>
          </div>
        </form>
      </section>
    `;

    const setMode = (mode) => {
      UI.$$("[data-mode]").forEach(b => b.classList.toggle("active", b.dataset.mode === mode));
      UI.$("#existingClientFields").classList.toggle("hidden", mode !== "existing");
      UI.$("#newLeadFields").classList.toggle("hidden", mode !== "lead");
      UI.$("#visitForm").dataset.mode = mode;
    };
    UI.$$("[data-mode]").forEach(b => b.addEventListener("click", () => setMode(b.dataset.mode)));
    setMode("existing");

    // Lógica do Autocomplete de Cliente
    const searchInput = UI.$("#clientSearchInput");
    const hiddenInput = UI.$("#clientSelect");
    const autocompleteList = UI.$("#clientAutocompleteList");
    const allClients = state.clients || [];

    if (preselected && searchInput) {
      const preClient = allClients.find(c => c.id === preselected);
      if (preClient) searchInput.value = `${preClient.name} â€” ${preClient.city}`;
    }

    function renderAutocomplete(query) {
      if (!autocompleteList) return;
      const lower = (query || "").toLowerCase();
      let matches = allClients;
      if (lower) {
        matches = allClients.filter(c => c.name.toLowerCase().includes(lower) || (c.city && c.city.toLowerCase().includes(lower)));
      }
      matches = matches.slice(0, 50); // limita a 50 para não travar o celular
      
      if (matches.length === 0) {
        autocompleteList.innerHTML = `<div style="padding:12px 14px; color:var(--muted); font-size:12px;">Nenhum cliente encontrado.</div>`;
      } else {
        autocompleteList.innerHTML = matches.map(c => `<button type="button" class="autocomplete-item" data-id="${c.id}" style="display:block; width:100%; text-align:left; padding:12px 14px; border:none; background:transparent; border-bottom:1px solid var(--line); font-size:13px; cursor:pointer;"><strong>${c.name}</strong><br><small style="color:var(--muted);">${c.city || "Cidade não informada"}</small></button>`).join("");
      }
      autocompleteList.style.display = "block";
    }

    searchInput?.addEventListener("input", (e) => {
      if (hiddenInput) hiddenInput.value = "";
      renderAutocomplete(e.target.value.trim());
    });
    
    searchInput?.addEventListener("focus", (e) => {
      renderAutocomplete(e.target.value.trim());
    });

    document.addEventListener("click", (e) => {
      if (searchInput && autocompleteList && !searchInput.contains(e.target) && !autocompleteList.contains(e.target)) {
        autocompleteList.style.display = "none";
      }
    });

    autocompleteList?.addEventListener("click", (e) => {
      const item = e.target.closest(".autocomplete-item");
      if (item) {
        const id = item.dataset.id;
        const client = allClients.find(c => c.id === id);
        if (client && hiddenInput && searchInput) {
          hiddenInput.value = client.id;
          searchInput.value = `${client.name} â€” ${client.city}`;
          autocompleteList.style.display = "none";
        }
      }
    });

    const ingestFiles = (files) => {
      attachments.push(...Array.from(files));
      UI.$("#attachmentPreview").innerHTML = attachments.map(a => `
        <div class="file-chip">${UI.icon(a.type.startsWith("image/") ? "camera" : "file", 16)}<span>${a.name}</span><small>${Math.round(a.size/1024)} KB</small></div>`).join("");
      UI.toast(`${files.length} arquivo(s) adicionado(s).`);
    };
    UI.$("#cameraInput").addEventListener("change", (e) => ingestFiles(e.target.files));
    UI.$("#fileInput").addEventListener("change", (e) => ingestFiles(e.target.files));

    UI.$("#geoBtn").addEventListener("click", () => {
      const status = UI.$("#geoStatus");
      if (!navigator.geolocation) {
        status.textContent = "Geolocalização não disponível neste navegador.";
        return;
      }
      status.textContent = "Obtendo localização...";
      navigator.geolocation.getCurrentPosition(
        pos => {
          geo = { lat: pos.coords.latitude, lng: pos.coords.longitude };
          status.textContent = `Localização capturada: ${geo.lat.toFixed(5)}, ${geo.lng.toFixed(5)}`;
          UI.toast("Localização capturada.");
        },
        () => { status.textContent = "Não foi possível acessar a localização. Você pode salvar sem ela."; },
        { enableHighAccuracy: true, timeout: 7000 }
      );
    });

        UI.$("#visitForm").addEventListener("submit", async (e) => {
      e.preventDefault();
      const fd = new FormData(e.currentTarget);
      const mode = e.currentTarget.dataset.mode;
      let clientId = fd.get("clientId");
      const btn = e.currentTarget.querySelector("button[type='submit']");

      try {
        if (btn) btn.disabled = true;

        if (mode === "lead") {
          const name = String(fd.get("leadName") || "").trim();
          if (!name) {
            UI.toast("Informe o nome do novo lead.", "error");
            if (btn) btn.disabled = false;
            return;
          }
          const leadPayload = {
            razao_social: name,
            nome_fantasia: name,
            contato_nome: fd.get("leadContact"),
            telefone: fd.get("leadPhone"),
            municipio: fd.get("leadCity") || "Nǜo informado",
            uf: fd.get("leadState") || "CE",
            latitude: geo.lat,
            longitude: geo.lng
          };
          const createdLead = await UI.createSupabaseClientRecord(leadPayload);
          if (!createdLead || !createdLead.id) throw new Error("Falha ao cadastrar lead remoto.");
          clientId = createdLead.id;
        }

        if (!clientId) {
          UI.toast("Selecione um cliente.", "error");
          if (btn) btn.disabled = false;
          return;
        }

        const needs = String(fd.get("needs") || "").split(",").map(s => s.trim()).filter(Boolean);
        const visitPayload = {
          clientId,
          tripId: fd.get("tripId") || null,
          notes: fd.get("notes"),
          needs,
          attachments: await Promise.all(attachments.map(async (file, index) => ({
            name: file.name,
            size: file.size,
            type: file.type,
            ...(await UI.uploadPrivateFile(`visitas/${clientId}/${Date.now()}-${index}-${encodeURIComponent(file.name)}`, file))
          })))
        };

        const createdVisit = await UI.createSupabaseVisit(visitPayload);
        if (!createdVisit) throw new Error("Falha ao registrar visita remota.");

        UI.toast("Visita salva com sucesso!");
        setTimeout(() => location.href = UI.pageLink("pages/cliente.html?id=" + clientId), 350);
      } catch (err) {
        console.error(err);
        UI.toast("Erro ao salvar visita no servidor.", "error");
        if (btn) btn.disabled = false;
      }
    });
  }
};
