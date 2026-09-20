const fs = require('fs');
const file = 'assets/js/pages/event.js';
let content = fs.readFileSync(file, 'utf8');

// Replace Links & Contatos buttons
content = content.replace(
  /<div style="display:flex; gap:8px;">\s*<button class="btn btn-secondary btn-small" onclick="UI\.openDialog\('eventLinkDialog'\)">\$\{UI\.icon\("plus", 14\)\} Link<\/button>\s*<button class="btn btn-secondary btn-small" onclick="UI\.openDialog\('eventContactDialog'\)">\$\{UI\.icon\("plus", 14\)\} Contato<\/button>\s*<\/div>/,
  `<div style="display:flex; gap:8px;">
            <button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventLinkDialog')" title="Adicionar Link">\${UI.icon("link", 18)}</button>
            <button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventContactDialog')" title="Adicionar Contato">\${UI.icon("user-plus", 18)}</button>
          </div>`
);

// Replace Camera button
content = content.replace(
  /<div class="panel-head"><div><span class="eyebrow">Galeria<\/span><h3>Fotos e Anexos<\/h3><\/div><button class="btn btn-secondary btn-small" onclick="document\.getElementById\('galleryInput'\)\.click\(\)">\$\{UI\.icon\("camera", 16\)\} Adicionar<\/button><\/div>/,
  `<div class="panel-head"><div><span class="eyebrow">Galeria</span><h3>Fotos e Anexos</h3></div><button type="button" class="icon-btn action-circle" onclick="document.getElementById('galleryInput').click()" title="Adicionar Foto">\${UI.icon("camera", 18)}</button></div>`
);

// Replace Expense button
content = content.replace(
  /<div class="panel-head"><div><span class="eyebrow">Financeiro<\/span><h3>Custos Lançados neste Evento<\/h3><\/div><button class="btn btn-secondary btn-small" onclick="UI\.openDialog\('eventExpenseDialog'\)">\$\{UI\.icon\("plus", 16\)\} Lançar Custo<\/button><\/div>/,
  `<div class="panel-head"><div><span class="eyebrow">Financeiro</span><h3>Custos Lançados neste Evento</h3></div><button type="button" class="icon-btn action-circle" onclick="UI.openDialog('eventExpenseDialog')" title="Lançar Custo">\${UI.icon("dollar-sign", 18)}</button></div>`
);

fs.writeFileSync(file, content);
console.log('event.js updated');

// Add CSS to styles.css
const cssFile = 'assets/css/styles.css';
let cssContent = fs.readFileSync(cssFile, 'utf8');

if (!cssContent.includes('.action-circle')) {
  cssContent += `
/* Action Circle Buttons */
.action-circle {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: #f0f4f2;
  color: #173e30;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
  border: 1px solid transparent;
}
.action-circle:hover {
  background: #e1e9e5;
  color: #0d231b;
  transform: translateY(-3px) scale(1.05);
  box-shadow: 0 6px 16px rgba(24,67,50,0.12);
  border-color: #cdd8d2;
}
.action-circle:active {
  transform: translateY(0) scale(0.95);
  box-shadow: 0 2px 6px rgba(24,67,50,0.1);
}
`;
  fs.writeFileSync(cssFile, cssContent);
  console.log('styles.css updated');
}

