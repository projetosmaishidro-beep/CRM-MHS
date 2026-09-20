const fs = require('fs');
const file = 'assets/js/pages/event.js';
let content = fs.readFileSync(file, 'utf8');

// Add edit functions
const editFunctions = `
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
`;

content = content.replace('window.deleteContact = (index) => {', editFunctions + '\n    window.deleteContact = (index) => {');

// Update Submit Handlers
content = content.replace(/const links = ev\.links \|\| \[\];\s*links\.push\(\{ title: fd\.get\("title"\), url: fd\.get\("url"\) \}\);\s*Store\.updateEvent\(eventId, \{ links \}\);\s*UI\.toast\("Link adicionado\."\);/, 
`const links = ev.links || [];
          const editIndex = fd.get("editIndex");
          if (editIndex && editIndex !== "-1") {
            links[parseInt(editIndex, 10)] = { title: fd.get("title"), url: fd.get("url") };
            UI.toast("Link atualizado.");
          } else {
            links.push({ title: fd.get("title"), url: fd.get("url") });
            UI.toast("Link adicionado.");
          }
          Store.updateEvent(eventId, { links });`);

content = content.replace(/const contacts = ev\.contacts \|\| \[\];\s*contacts\.push\(\{ name: fd\.get\("name"\), role: fd\.get\("role"\), phone: fd\.get\("phone"\) \}\);\s*Store\.updateEvent\(eventId, \{ contacts \}\);\s*UI\.toast\("Contato adicionado\."\);/,
`const contacts = ev.contacts || [];
          const editIndex = fd.get("editIndex");
          if (editIndex && editIndex !== "-1") {
            contacts[parseInt(editIndex, 10)] = { name: fd.get("name"), role: fd.get("role"), phone: fd.get("phone") };
            UI.toast("Contato atualizado.");
          } else {
            contacts.push({ name: fd.get("name"), role: fd.get("role"), phone: fd.get("phone") });
            UI.toast("Contato adicionado.");
          }
          Store.updateEvent(eventId, { contacts });`);

// Reset editIndex on close
content = content.replace(/UI\.closeDialog\("eventLinkDialog"\);\s*e\.target\.reset\(\);/,
`UI.closeDialog("eventLinkDialog");
          e.target.reset();
          let hiddenInput = e.target.querySelector('input[name="editIndex"]');
          if (hiddenInput) hiddenInput.value = "-1";`);

content = content.replace(/UI\.closeDialog\("eventContactDialog"\);\s*e\.target\.reset\(\);/,
`UI.closeDialog("eventContactDialog");
          e.target.reset();
          let hiddenInput = e.target.querySelector('input[name="editIndex"]');
          if (hiddenInput) hiddenInput.value = "-1";`);

// Render UI Update
content = content.replace(/<button type="button" class="icon-btn" style="color:var\(--mais-red\); padding:4px;" onclick="window\.deleteContact\(\$\{i\}\)" title="Excluir">\$\{UI\.icon\("trash", 14\)\}<\/button>/,
`<div style="display:flex; gap:4px; flex-shrink:0;">
                  <button type="button" class="icon-btn" style="color:var(--muted); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.editContact(\${i})" title="Editar">\${UI.icon("edit", 14)}</button>
                  <button type="button" class="icon-btn" style="color:var(--mais-red); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.deleteContact(\${i})" title="Excluir">\${UI.icon("trash", 14)}</button>
                </div>`);

content = content.replace(/<button type="button" class="icon-btn" style="color:var\(--mais-red\); padding:4px;" onclick="window\.deleteLink\(\$\{i\}\)" title="Excluir">\$\{UI\.icon\("trash", 14\)\}<\/button>/,
`<div style="display:flex; gap:4px; flex-shrink:0;">
                  <button type="button" class="icon-btn" style="color:var(--muted); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.editLink(\${i})" title="Editar">\${UI.icon("edit", 14)}</button>
                  <button type="button" class="icon-btn" style="color:var(--mais-red); padding:6px; background:#f7f9f8; border-radius:6px;" onclick="window.deleteLink(\${i})" title="Excluir">\${UI.icon("trash", 14)}</button>
                </div>`);

fs.writeFileSync(file, content);
console.log('Done');
