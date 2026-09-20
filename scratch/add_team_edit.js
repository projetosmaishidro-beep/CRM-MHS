const fs = require('fs');

// 1. Update ui.js
const uiFile = 'assets/js/ui.js';
let uiContent = fs.readFileSync(uiFile, 'utf8');

// Add participantes to hydrate
uiContent = uiContent.replace(/participantIds: \[\]\,/, 
`participantIds: Array.isArray(row.participantes) ? row.participantes : (typeof row.participantes === "string" ? JSON.parse(row.participantes || "[]") : []),`);

// Update updateRemoteEvent to handle participantIds
if (!uiContent.includes('if (payload.participantIds !== undefined) updateData.participantes = payload.participantIds;')) {
    uiContent = uiContent.replace(/if \(payload\.role !== undefined\) updateData\.tipo_participacao = payload\.role === "Expositor" \? "EXPOSITOR" : "PARTICIPANTE";/,
    `if (payload.role !== undefined) updateData.tipo_participacao = payload.role === "Expositor" ? "EXPOSITOR" : "PARTICIPANTE";
      if (payload.participantIds !== undefined) updateData.participantes = payload.participantIds;
      if (payload.contacts !== undefined) updateData.contatos = payload.contacts;
      if (payload.links !== undefined) updateData.links = payload.links;`);
}

fs.writeFileSync(uiFile, uiContent);


// 2. Update event.js
const eventFile = 'assets/js/pages/event.js';
let eventContent = fs.readFileSync(eventFile, 'utf8');

// Add editParticipants function
if (!eventContent.includes('window.editParticipants')) {
    const editFunc = `
    window.editParticipants = () => {
      const state = Store.getState();
      const ev = state.events.find(e => e.id === eventId);
      if (!ev) return;
      const currentIds = ev.participantIds || [];
      const users = state.users || [];
      
      const listEl = document.getElementById("participantsList");
      listEl.innerHTML = users.map(u => \`
        <label style="display:flex; align-items:center; gap:10px; padding:10px; border:1px solid var(--line); border-radius:10px; cursor:pointer; background:#fbfcfb; transition:border-color 0.2s;">
          <input type="checkbox" name="participants" value="\${u.id}" \${currentIds.includes(u.id) ? 'checked' : ''} style="width:18px; height:18px; accent-color:var(--primary);">
          <div style="display:flex; align-items:center; gap:12px;">
            <span class="avatar mini" style="min-width:36px; width:36px; height:36px; font-size:12px; background:#e8f4ed; color:#235b46;">\${u.initials}</span>
            <div style="display:flex; flex-direction:column;">
              <strong style="font-size:14px; color:var(--text);">\${u.name}</strong>
              <small style="color:var(--muted); font-size:12px;">\${u.role}</small>
            </div>
          </div>
        </label>
      \`).join("");
      
      UI.openDialog('eventParticipantsDialog');
    };
`;
    eventContent = eventContent.replace('window.editContact = (index) => {', editFunc + '\n    window.editContact = (index) => {');
}

// Add Dialog to renderGeneralInfo
if (!eventContent.includes('id="eventParticipantsDialog"')) {
    eventContent = eventContent.replace('</dialog>\n\n        <dialog id="galleryDialog"',
    `</dialog>

        <dialog id="eventParticipantsDialog" class="form-dialog">
          <form method="dialog" id="eventParticipantsForm">
            <div class="dialog-head"><div><span class="eyebrow">Equipe CRM</span><h2>Gerenciar Equipe</h2></div><button class="icon-btn" type="button" onclick="UI.closeDialog('eventParticipantsDialog')">\${UI.icon("x")}</button></div>
            <div class="form-grid" id="participantsList" style="display:flex; flex-direction:column; gap:10px; max-height:400px; overflow-y:auto; padding-right:8px; padding-bottom:8px;">
               <!-- Preenchido via JS -->
            </div>
            <div class="dialog-actions" style="margin-top:20px; border-top:1px solid var(--line); padding-top:16px;">
              <button class="btn btn-secondary" type="button" onclick="UI.closeDialog('eventParticipantsDialog')">Cancelar</button>
              <button class="btn btn-primary" type="submit">Salvar Equipe</button>
            </div>
          </form>
        </dialog>

        <dialog id="galleryDialog"`);
}

// Add the button to the Equipe CRM header
if (!eventContent.includes('window.editParticipants()')) {
    eventContent = eventContent.replace('<small style="margin-bottom: 12px; display: block; border-bottom: 1px solid var(--line); padding-bottom: 8px;">Equipe CRM</small>',
    `<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; border-bottom:1px solid var(--line); padding-bottom:8px;">
              <small style="margin:0;">Equipe CRM</small>
              <button type="button" class="icon-btn" style="color:var(--muted); padding:4px 8px; font-size:11px; font-weight:700; background:#f7f9f8; border-radius:6px; display:flex; align-items:center; gap:6px;" onclick="window.editParticipants()" title="Gerenciar Equipe">\${UI.icon("edit", 12)} Gerenciar</button>
            </div>`);
}

// Add submit handler
if (!eventContent.includes('id === "eventParticipantsForm"')) {
    const handler = `
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
`;
    eventContent = eventContent.replace('if (e.target.id === "eventContactForm") {', handler + '\n      if (e.target.id === "eventContactForm") {');
}

fs.writeFileSync(eventFile, eventContent);
console.log('Done');
