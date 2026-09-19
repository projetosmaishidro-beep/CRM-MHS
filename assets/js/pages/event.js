window.PageModules = window.PageModules || {};
window.PageModules.event = {
  init() {
    const params = new URLSearchParams(location.search);
    const eventId = params.get("id");
    let activeTab = "details"; // details, gallery, costs

    window.deleteExpense = (id) => {
      if (!confirm("Excluir este custo?")) return;
      Store.deleteExpense(id);
      UI.toast("Custo excluído.");
      render();
    };

    window.deleteLink = (index) => {
      if (!confirm("Remover este link?")) return;
      const ev = Store.getState().events.find(e => e.id === eventId);
      if (!ev) return;
      const newLinks = [...(ev.links || [])];
      newLinks.splice(index, 1);
      Store.updateEvent(eventId, { links: newLinks });
      UI.toast("Link removido.");
      render();
    };

    
    window.editLink = (index) => {
      const ev = Store.getState().events.find(e => e.id === eventId);
      if (!ev) return;
      const lnk = (ev.links || [])[index];
      if (!lnk) return;
      const form = UI.$("#eventLinkForm");
      form.elements["title"].value = lnk.title;
      form.elements["url"].value = lnk.url;
      let hiddenInput = form.querySelector('input[name="editIndex"]');
      if (!hiddenInput) {
        hiddenInput = document.createElement('input');
        hiddenInput.type = 'hidden';
        hiddenInput.name = 'editIndex';
        form.appendChild(hiddenInput);
      }
      hiddenInput.value = index;
      UI.openDialog('eventLinkDialog');
    };

    
    window.editParticipants = () => {
      const state = Store.getState();
      const ev = state.events.find(e => e.id === eventId);
      if (!ev) return;
      const currentIds = ev.participantIds || [];
      const users = state.users || [];
      
      const listEl = document.getElementById("participantsList");
      listEl.innerHTML = users.map(u => `
        <label style="display:flex; align-items:center; gap:10px; padding:10px; border:1px solid var(--line); border-radius:10px; cursor:pointer; background:#fbfcfb; transition:border-color 0.2s;">
          <input type="checkbox" name="participants" value="${u.id}" ${currentIds.includes(u.id) ? 'checked' : ''} style="width:18px; height:18px; accent-color:var(--primary);">
          <div style="display:flex; align-items:center; gap:12px;">
            <span class="avatar mini" style="min-width:36px; width:36px; height:36px; font-size:12px; background:#e8f4ed; color:#235b46;">${u.initials}</span>
            <div style="display:flex; flex-direction:column;">
              <strong style="font-size:14px; color:var(--text);">${u.name}</strong>
              <small style="color:var(--muted); font-size:12px;">${u.role}</small>
            </div>
          </div>
        </label>
      `).join("");
      
      UI.openDialog('eventParticipantsDialog');
    };

    window.editContact = (index) => {
      const ev = Store.getState().events.find(e => e.id === eventId);
      if (!ev) return;
      const ctc = (ev.contacts || [])[index];
      if (!ctc) return;
      const form = UI.$("#eventContactForm");
      form.elements["name"].value = ctc.name;
      form.elements["role"].value = ctc.role;
      form.elements["phone"].value = ctc.phone || "";
      let hiddenInput = form.querySelector('input[name="editIndex"]');
      if (!hiddenInput) {
        hiddenInput = document.createElement('input');
        hiddenInput.type = 'hidden';
        hiddenInput.name = 'editIndex';
        form.appendChild(hiddenInput);
      }
      hiddenInput.value = index;
      UI.openDialog('eventContactDialog');
    };

    window.deleteContact = (index) => {
      if (!confirm("Remover este contato?")) return;
      const ev = Store.getState().events.find(e => e.id === eventId);
      if (!ev) return;
      const newContacts = [...(ev.contacts || [])];
      newContacts.splice(index, 1);
      Store.updateEvent(eventId, { contacts: newContacts });
      UI.toast("Contato removido.");
      render();
    };

    window.editExpense = (id) => {
      const state = Store.getState();
      const exp = state.expenses.find(e => e.id === id);
      if (!exp) return;
      const form = UI.$("#eventExpenseForm");
      if (!form) return;
      form.elements["id"].value = exp.id;
      form.elements["category"].value = exp.category || "Outros";
      form.elements["costCenter"].value = exp.costCenter || "";
      form.elements["amount"].value = exp.amount;
      form.elements["place"].value = exp.place || "";
      form.elements["notes"].value = exp.notes || "";
      UI.openDialog('eventExpenseDialog');
    };

    const render = () => {
      const state = Store.getState();
      const event = state.events?.find(e => e.id === eventId);
      if (!event) {
        UI.$("#pageContent").innerHTML = UI.empty("Evento não encontrado", "O evento que você procura não existe ou foi excluído.");
        return;
      }

      const participants = (event.participantIds || []).map(id => state.users.find(u => u.id === id)).filter(Boolean);
      const expenses = state.expenses.filter(e => e.eventId === event.id);
      const attachments = event.attachments || [];
      const costsTotal = expenses.reduce((s, e) => s + Number(e.amount), 0);
      const leadsCount = (state.clients || []).filter(c => c.originEventId === event.id).length;

      UI.$("#pageContent").innerHTML = `
        <section class="trip-central-hero reveal">
          <a class="profile-back-link" href="#" onclick="history.back(); return false;"><span class="back-arrow">${UI.icon("arrow",15)}</span>Voltar</a>
          <div class="trip-central-heading">
            <div class="title-inline"><h2>${event.name}</h2>${UI.statusBadge(event.status)}</div>
            <div class="trip-meta-line" style="margin-top:6px;">
              <span>${UI.icon("map", 14)} ${event.location}</span>
              <span>${UI.icon("calendar", 14)} ${UI.shortDate(event.startDate)} → ${UI.shortDate(event.endDate)}</span>
              <span>${event.role === 'Expositor' ? UI.icon("star", 14) : UI.icon("briefcase", 14)} ${event.role || 'Participante'}</span>
              <span>${UI.icon("users", 14)} ${leadsCount} leads captados</span>
            </div>
          </div>
        </section>

        <div class="reveal" style="margin-top:24px; display:flex; flex-direction:column; gap:24px;">
          ${renderGeneralInfo(event, participants)}
          ${renderGallery(event, attachments)}
          ${renderCosts(expenses)}
        </div>

        
        <dialog id="eventLinkDialog" class="form-dialog">
          <form method="dialog" id="eventLinkForm">
            <div class="dialog-head"><div><span class="eyebrow">Acessos</span><h2>Novo Link</h2></div><button class="icon-btn" type="button" onclick="UI.closeDialog('eventLinkDialog')">${UI.icon("x")}</button></div>
            <div class="form-grid">
              <label class="field"><span>Título</span><input name="title" required placeholder="Ex.: Site Oficial da Feira"></label>
              <label class="field"><span>URL (Link)</span><input name="url" type="url" required placeholder="https://..."></label>
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" type="button" onclick="UI.closeDialog('eventLinkDialog')">Cancelar</button><button class="btn btn-primary" type="submit">Salvar Link</button></div>
          </form>
        </dialog>
  
        <dialog id="eventContactDialog" class="form-dialog">
          <form method="dialog" id="eventContactForm">
            <div class="dialog-head"><div><span class="eyebrow">Networking</span><h2>Novo Contato</h2></div><button class="icon-btn" type="button" onclick="UI.closeDialog('eventContactDialog')">${UI.icon("x")}</button></div>
            <div class="form-grid">
              <label class="field"><span>Nome</span><input name="name" required placeholder="Ex.: Maria (Organização)"></label>
              <label class="field"><span>Cargo / Função</span><input name="role" required placeholder="Ex.: Produtora"></label>
              <label class="field span-2"><span>Telefone ou E-mail</span><input name="phone" placeholder="Ex.: (11) 99999-9999"></label>
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" type="button" onclick="UI.closeDialog('eventContactDialog')">Cancelar</button><button class="btn btn-primary" type="submit">Salvar Contato</button></div>
          </form>
        </dialog>
  \n        <dialog id="eventExpenseDialog" class="form-dialog">
          <form method="dialog" id="eventExpenseForm">
            <input type="hidden" name="id" value="">
            <div class="dialog-head"><div><span class="eyebrow">Financeiro</span><h2>Custo</h2></div><button class="icon-btn" type="button" onclick="UI.closeDialog('eventExpenseDialog')">${UI.icon("x")}</button></div>
            <div class="form-grid">
              <label class="field"><span>Categoria</span><select name="category"><option>Alimentação</option><option>Hospedagem</option><option>Transporte / Voo</option><option>Material de Estande</option><option>Ingressos / Inscrição</option><option>Outros</option></select></label>
              <label class="field"><span>Centro de Custo</span><select name="costCenter" required><option value="">Selecione...</option><option>Prospecção (Novos Clientes)</option><option>Captação / Retenção</option><option>Marketing / Eventos</option><option>Outros</option></select></label>
              <label class="field span-2"><span>Valor e Local</span><div style="display:grid; grid-template-columns:1fr 2fr; gap:10px;"><input name="amount" type="text" required inputmode="decimal" placeholder="R$ 0,00"><input name="place" required placeholder="Estabelecimento ou Fornecedor"></div></label>
              <label class="field span-2"><span>Observações</span><textarea name="notes" rows="2"></textarea></label>
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" type="button" onclick="UI.closeDialog('eventExpenseDialog')">Cancelar</button><button class="btn btn-primary" type="submit">Salvar custo</button></div>
          </form>
        </dialog>
        </dialog>

        <dialog id="eventParticipantsDialog" class="form-dialog">
          <form method="dialog" id="eventParticipantsForm">
            <div class="dialog-head"><div><span class="eyebrow">Equipe CRM</span><h2>Gerenciar Equipe</h2></div><button class="icon-btn" type="button" onclick="UI.closeDialog('eventParticipantsDialog')">${UI.icon("x")}</button></div>
            <div class="form-grid" id="participantsList" style="display:flex; flex-direction:column; gap:10px; max-height:400px; overflow-y:auto; padding-right:8px; padding-bottom:8px;">
               <!-- Preenchido via JS -->
            </div>
            <div class="dialog-actions" style="margin-top:20px; border-top:1px solid var(--line); padding-top:16px;">
              <button class="btn btn-secondary" type="button" onclick="UI.closeDialog('eventParticipantsDialog')">Cancelar</button>
              <button class="btn btn-primary" type="submit">Salvar Equipe</button>
            </div>
          </form>
        </dialog>

        <dialog id="galleryDialog" style="border:none; padding:0; background:transparent; width:100vw; max-width:100vw; height:100vh; max-height:100vh; overflow:hidden;">
          <form method="dialog" style="width:100%; height:100%; display:flex; flex-direction:column; background:rgba(0,0,0,0.9); backdrop-filter:blur(8px);">
            <div style="display:flex; justify-content:space-between; align-items:center; padding:16px 24px; color:#fff;">
              <span id="galleryCount" style="font-size:14px; font-weight:600;"></span>
              <div style="display:flex; gap:12px;">
                <button class="icon-btn" type="button" onclick="window.deleteAttachment()" style="color:var(--mais-red); background:rgba(255,255,255,0.1); border-radius:50%;" title="Excluir">${UI.icon("trash")}</button>
                <button class="icon-btn" type="button" onclick="UI.closeDialog('galleryDialog')" style="color:#fff; background:rgba(255,255,255,0.1); border-radius:50%;" title="Fechar">${UI.icon("x")}</button>
              </div>
            </div>
            
            <div style="flex:1; display:flex; align-items:center; justify-content:center; position:relative; padding:16px;">
              <button type="button" onclick="window.navGallery(-1)" style="position:absolute; left:16px; top:50%; transform:translateY(-50%); width:44px; height:44px; border-radius:50%; border:none; background:rgba(255,255,255,0.1); color:#fff; cursor:pointer; display:grid; place-items:center; z-index:10;">&larr;</button>
              
              <div id="galleryContent" style="display:flex; justify-content:center; align-items:center; width:100%; height:100%;"></div>
              
              <button type="button" onclick="window.navGallery(1)" style="position:absolute; right:16px; top:50%; transform:translateY(-50%); width:44px; height:44px; border-radius:50%; border:none; background:rgba(255,255,255,0.1); color:#fff; cursor:pointer; display:grid; place-items:center; z-index:10;">&rarr;</button>
            </div>
          </form>
        </dialog>
      `;
    };

    const renderGeneralInfo = (event, participants) => {
      const links = event.links || [];
      const contacts = event.contacts || [];
      
      return `
      <div class="panel" style="margin-bottom: 24px;">
        <div class="panel-head">
          <div><span class="eyebrow">Informações Gerais</span><h3>Detalhes e Networking</h3></div>
          <div style="display:flex; gap:8px;">
            <button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventLinkDialog')" title="Adicionar Link">${UI.icon("link", 18)}</button>
            <button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventContactDialog')" title="Adicionar Contato">${UI.icon("user-plus", 18)}</button>
          </div>
        </div>

        <div class="info-grid compact-info" style="align-items: start;">
          <div>
            <small style="margin-bottom: 12px; display: block; border-bottom: 1px solid var(--line); padding-bottom: 8px;">Contatos Chave</small>
            ${contacts.length ? contacts.map((ctc, i) => `
              <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div style="display:flex; align-items:center; gap:10px; overflow:hidden;">
                  <span class="avatar mini" style="min-width:32px; width:32px; height:32px; font-size:11px;">${UI.initials(ctc.name)}</span>
                  <div style="overflow:hidden;">
                    <strong style="display:block; font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${ctc.name}</strong>
                    <span style="color:var(--muted); font-size:12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:block;">${ctc.role} ${ctc.phone ? `· ${ctc.phone}` : ''}</span>
                  </div>
                </div>
                <div style="display:flex; gap:4px; flex-shrink:0;">
                  <button type="button" class="icon-btn" style="color:var(--muted); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.editContact(${i})" title="Editar">${UI.icon("edit", 14)}</button>
                  <button type="button" class="icon-btn" style="color:var(--mais-red); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.deleteContact(${i})" title="Excluir">${UI.icon("trash", 14)}</button>
                </div>
              </div>
            `).join("") : '<span style="color:var(--muted); font-size:13px;">Nenhum contato adicionado.</span>'}
          </div>

          <div>
            <small style="margin-bottom: 12px; display: block; border-bottom: 1px solid var(--line); padding-bottom: 8px;">Links e Acessos</small>
            ${links.length ? links.map((lnk, i) => `
              <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                <div style="display:flex; align-items:center; gap:10px; overflow:hidden;">
                  <span style="color:var(--muted); min-width:20px; display:flex;">${UI.icon("globe", 20)}</span>
                  <div style="overflow:hidden;">
                    <strong style="display:block; font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${lnk.title}</strong>
                    <a href="${lnk.url}" target="_blank" rel="noopener" style="color:var(--mais-blue); font-size:12px; text-decoration:none; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:block;">${lnk.url}</a>
                  </div>
                </div>
                <div style="display:flex; gap:4px; flex-shrink:0;">
                  <button type="button" class="icon-btn" style="color:var(--muted); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.editLink(${i})" title="Editar">${UI.icon("edit", 14)}</button>
                  <button type="button" class="icon-btn" style="color:var(--mais-red); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.deleteLink(${i})" title="Excluir">${UI.icon("trash", 14)}</button>
                </div>
              </div>
            `).join("") : '<span style="color:var(--muted); font-size:13px;">Nenhum link adicionado.</span>'}
          </div>

          <div>
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom:1px solid var(--line); padding-bottom:8px;">
              <small style="margin:0;">Equipe CRM</small>
              <button type="button" class="icon-btn action-circle" style="width:28px; height:28px;" onclick="window.editParticipants()" title="Gerenciar Equipe">${UI.icon("users", 14)}</button>
            </div>
            ${participants.length ? participants.map(u => `
              <div style="display:flex; align-items:center; gap:10px; margin-bottom:12px;">
                <span class="avatar mini" style="min-width:32px; width:32px; height:32px; font-size:11px;">${u.initials}</span>
                <div style="overflow:hidden;">
                  <strong style="display:block; font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${u.name}</strong>
                  <span style="color:var(--muted); font-size:12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:block;">${u.role}</span>
                </div>
              </div>
            `).join("") : '<span style="color:var(--muted); font-size:13px;">Nenhum participante.</span>'}
          </div>
        </div>

        <div class="note-box" style="margin-top: 0; border-top: 1px solid var(--line); border-radius: 0 0 12px 12px;">
          <small>Foco e Anotações Estratégicas</small>
          <p style="white-space:pre-wrap; line-height:1.6;">${event.notes || "Nenhuma anotação estratégica informada para este evento."}</p>
        </div>
      </div>
      `;
    };

    const renderGallery = (event, attachments) => `
      <div class="panel">
        <div class="panel-head">
          <div><span class="eyebrow">Registros</span><h3>Arquivos e Fotos do Evento</h3></div>
          <label class="btn btn-secondary btn-small" style="cursor:pointer;">
            ${UI.icon("camera", 16)} Adicionar
            <input type="file" id="eventUpload" multiple accept="image/*,.pdf" hidden>
          </label>
        </div>
        <div style="padding:16px;">
          ${attachments.length ? `
            <div style="display:grid; grid-template-columns:repeat(auto-fill, minmax(120px, 1fr)); gap:10px;">
              ${attachments.map((att, index) => {
                const src = att.dataUrl || att.url || "";
                const isImage = att.type?.startsWith("image");
                return `
                <button type="button" onclick="window.openGallery(${index})" style="display:block; width:100%; border:none; text-align:left; cursor:pointer; padding:0; background:#f1f5f9; border-radius:8px; overflow:hidden; border:1px solid #e2e8f0; text-decoration:none;">
                  ${isImage && src
                    ? `<div style="height:100px; background:url('${src}') center/cover no-repeat;"></div>`
                    : `<div style="height:100px; display:flex; align-items:center; justify-content:center; color:#94a3b8;">${UI.icon("file", 32)}</div>`
                  }
                  <div style="padding:8px; font-size:10px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${att.name}</div>
                </button>`;
              }).join("")}
            </div>
          ` : UI.empty("Nenhum arquivo", "Adicione fotos do estande, panfletos ou comprovantes de inscrição.")}
        </div>
      </div>
    `;

    const renderCosts = (expenses) => `
      <div class="panel">
        <div class="panel-head"><div><span class="eyebrow">Financeiro</span><h3>Custos Lançados neste Evento</h3></div><button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventExpenseDialog')" title="Lançar Custo">${UI.icon("dollar-sign", 18)}</button></div>
        <div class="expense-list">
          ${expenses.length ? expenses.map(e => {
            const user = Store.getState().users.find(u=>u.id===e.userId);
            return `
              <div style="display:flex; justify-content:space-between; align-items:center; padding:13px 0; border-bottom:1px solid var(--line); gap:12px;">
                <div style="display:flex; align-items:center; gap:12px; flex:1; min-width:0;">
                  <span class="expense-icon" style="flex-shrink:0;">${UI.icon("receipt")}</span>
                  <div style="min-width:0; flex:1;">
                    <div class="row-inline" style="flex-wrap:nowrap; overflow:hidden;">
                      <strong style="white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${e.category}</strong>
                      ${e.costCenter ? `<span class="tag subtle" style="background:#eef2f6; color:#475569; margin-left:6px; flex-shrink:0;">${e.costCenter}</span>` : ""}
                    </div>
                    <p style="margin:4px 0; color:var(--muted); font-size:11px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${e.place}${e.notes ? ` · ${e.notes}` : ""}</p>
                    <small style="color:#8a9790; font-size:9px;">${UI.date(e.date)} · ${user?.name || "Usuário"}</small>
                  </div>
                </div>
                <div style="display:flex; align-items:center; gap:12px; flex-shrink:0;">
                  <b style="font-size:13px;">${UI.money(e.amount)}</b>
                  <div style="display:flex; gap:4px;">
                    <button type="button" class="icon-btn" style="color:var(--muted); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.editExpense('${e.id}')" title="Editar">${UI.icon("edit", 14)}</button>
                    <button type="button" class="icon-btn" style="color:var(--mais-red); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.deleteExpense('${e.id}')" title="Excluir">${UI.icon("trash", 14)}</button>
                  </div>
                </div>
              </div>
            `;
          }).join("") : UI.empty("Sem despesas", "Nenhum custo registrado para este evento ainda.")}
        </div>
      </div>
    `;

    window.setEventTab = (tab) => {
      activeTab = tab;
      render();
    };

    let currentGalleryIndex = 0;
    
    window.openGallery = (index) => {
      const state = Store.getState();
      const event = state.events?.find(ev => ev.id === eventId);
      if (!event || !event.attachments || !event.attachments.length) return;
      
      currentGalleryIndex = index;
      
      window.navGallery = (dir) => {
        currentGalleryIndex = (currentGalleryIndex + dir + event.attachments.length) % event.attachments.length;
        updateGallery();
      };

      window.deleteAttachment = () => {
        if (!confirm("Excluir este arquivo?")) return;
        const ev = Store.getState().events.find(e => e.id === eventId);
        if (!ev) return;
        const newAttachments = [...(ev.attachments || [])];
        newAttachments.splice(currentGalleryIndex, 1);
        Store.updateEvent(eventId, { attachments: newAttachments });
        
        UI.toast("Arquivo excluído.");
        UI.closeDialog('galleryDialog');
        render();
      };

      const updateGallery = () => {
        const att = event.attachments[currentGalleryIndex];
        const src = att.dataUrl || att.url || "";
        const isImage = att.type?.startsWith("image");
        const total = event.attachments.length;
        
        const galleryContent = UI.$("#galleryContent");
        if (isImage) {
          galleryContent.innerHTML = `<img src="${src}" style="max-width:100%; max-height:calc(100vh - 120px); object-fit:contain; border-radius:8px; box-shadow:0 10px 40px rgba(0,0,0,0.5);">`;
        } else {
          galleryContent.innerHTML = `
            <div style="background:#fff; padding:32px; border-radius:12px; text-align:center; max-width:400px; width:100%;">
              ${UI.icon("file", 48)}
              <h3 style="margin:16px 0 8px; color:var(--text);">${att.name}</h3>
              <a href="${src}" target="_blank" rel="noopener" class="btn btn-primary" style="text-decoration:none;">Abrir Documento</a>
            </div>
          `;
        }
        
        UI.$("#galleryCount").textContent = `Mídia ${currentGalleryIndex + 1} de ${total}`;
      };

      updateGallery();
      UI.openDialog("galleryDialog");
    };

    document.addEventListener("change", async (e) => {
      if (e.target.id === "eventUpload") {
        const files = Array.from(e.target.files);
        if (!files.length) return;
        
        const state = Store.getState();
        const event = state.events?.find(ev => ev.id === eventId);
        if (!event) return;

        UI.toast(`Fazendo upload de ${files.length} arquivo(s)...`);
        
        const uploadedAttachments = [];
        for (const file of files) {
          const ext = file.name.split('.').pop();
          const path = `evento_${eventId}_${Date.now()}.${ext}`;
          const url = await UI.uploadToStorage("eventos-anexos", path, file);
          if (url) {
            uploadedAttachments.push({
              name: file.name,
              size: file.size,
              type: file.type,
              url: url
            });
          }
        }

        if (uploadedAttachments.length) {
          const newAttachments = [...(event.attachments || []), ...uploadedAttachments];
          
          Store.updateEvent(eventId, { attachments: newAttachments });
          render();
          
          const success = await UI.updateRemoteEventMedia(eventId, { attachments: newAttachments });
          if (success) {
             UI.toast(`${uploadedAttachments.length} arquivo(s) salvo(s) na nuvem.`);
          } else {
             UI.toast("Erro ao salvar arquivos no banco de dados.", "error");
          }
        } else {
          UI.toast("Falha no upload dos arquivos.", "error");
        }
      }
    });

    document.addEventListener("submit", (e) => {
      if (e.target.id === "eventLinkForm") {
        e.preventDefault();
        const fd = new FormData(e.target);
        const state = Store.getState();
        const ev = state.events.find(ev => ev.id === eventId);
        if (ev) {
          const links = ev.links || [];
          const editIndex = fd.get("editIndex");
          if (editIndex && editIndex !== "-1") {
            links[parseInt(editIndex, 10)] = { title: fd.get("title"), url: fd.get("url") };
            UI.toast("Link atualizado.");
          } else {
            links.push({ title: fd.get("title"), url: fd.get("url") });
            UI.toast("Link adicionado.");
          }
          Store.updateEvent(eventId, { links });
          UI.closeDialog("eventLinkDialog");
          e.target.reset();
          let hiddenInput = e.target.querySelector('input[name="editIndex"]');
          if (hiddenInput) hiddenInput.value = "-1";
          render();
        }
      }

      
      if (e.target.id === "eventParticipantsForm") {
        e.preventDefault();
        const fd = new FormData(e.target);
        const state = Store.getState();
        const ev = state.events.find(ev => ev.id === eventId);
        if (ev) {
          const participantIds = fd.getAll("participants");
          Store.updateEvent(eventId, { participantIds });
          UI.toast("Equipe do evento atualizada.");
          UI.closeDialog("eventParticipantsDialog");
          render();
        }
      }

      if (e.target.id === "eventContactForm") {
        e.preventDefault();
        const fd = new FormData(e.target);
        const state = Store.getState();
        const ev = state.events.find(ev => ev.id === eventId);
        if (ev) {
          const contacts = ev.contacts || [];
          const editIndex = fd.get("editIndex");
          if (editIndex && editIndex !== "-1") {
            contacts[parseInt(editIndex, 10)] = { name: fd.get("name"), role: fd.get("role"), phone: fd.get("phone") };
            UI.toast("Contato atualizado.");
          } else {
            contacts.push({ name: fd.get("name"), role: fd.get("role"), phone: fd.get("phone") });
            UI.toast("Contato adicionado.");
          }
          Store.updateEvent(eventId, { contacts });
          UI.closeDialog("eventContactDialog");
          e.target.reset();
          let hiddenInput = e.target.querySelector('input[name="editIndex"]');
          if (hiddenInput) hiddenInput.value = "-1";
          render();
        }
      }

      if (e.target.id === "eventExpenseForm") {
        e.preventDefault();
        const btn = e.target.querySelector("button[type=submit]");
        const originalText = btn ? btn.textContent : "Salvar";
        if (btn) { btn.disabled = true; btn.textContent = "Salvando..."; }
        
        const fd = new FormData(e.target);
        const expenseId = fd.get("id");
        
        const payload = {
          eventId: eventId,
          userId: Store.getState().session?.user?.id || "u1",
          category: fd.get("category"),
          costCenter: fd.get("costCenter"),
          amount: Number(String(fd.get("amount")).replace(/\./g, '').replace(',', '.')),
          place: fd.get("place"),
          notes: fd.get("notes"),
          date: new Date().toISOString()
        };

        if (expenseId) {
          Store.updateExpense(expenseId, payload);
          UI.toast("Custo atualizado.");
        } else {
          Store.addExpense(payload);
          UI.toast("Custo registrado no evento.");
        }
        
        UI.closeDialog("eventExpenseDialog");
        if (btn) { btn.disabled = false; btn.textContent = originalText; }
        e.target.reset();
        e.target.elements["id"].value = "";
        render();
      }
    });

    window.addEventListener("store:changed", render);

    render();
  }
};

