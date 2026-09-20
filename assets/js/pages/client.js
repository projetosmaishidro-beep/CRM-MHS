
window.PageModules = window.PageModules || {};
window.PageModules.client = {
  init() {
    const params = new URLSearchParams(location.search);
    const requestedId = params.get("id");

    const render = () => {
      const state = Store.getState();
      const client = state.clients.find(c => c.id === requestedId) || state.clients[0];
      const visits = state.visits
        .filter(v => v.clientId === client.id)
        .sort((a,b) => new Date(b.date) - new Date(a.date));
      const owner = state.users.find(u => u.id === client.ownerId);
      const needRecords = client.needRecords || [];

      const media = [
        ...(client.attachments || []).map(a => ({ ...a, source: "Perfil do cliente", date: client.createdAt })),
        ...visits.flatMap(v => (v.attachments || []).map(a => ({
          ...a,
          source: `Visita de ${UI.date(v.date)}`,
          visitId: v.id,
          date: v.date
        })))
      ].filter(a => a.type?.startsWith("image/") || a.type?.startsWith("video/"));

      UI.$("#pageContent").innerHTML = `
        <section class="profile-hero client-profile-hero reveal">
          <div class="profile-main">

            <div class="client-profile-heading">
              <div class="title-inline"><h2>${client.name}</h2>${UI.statusBadge(client.status)}</div>
              <p class="client-company">${client.company}</p>
              <span class="client-location">${client.segment} Â· ${client.city}, ${client.state}</span>
            </div>
          </div>
          <div class="profile-actions">
            <a class="btn btn-primary" href="${UI.pageLink(`pages/nova-visita.html?client=${client.id}`)}">${UI.icon("plus")} Registrar visita</a>
            <button class="btn btn-need" id="openNeedBtn">${UI.icon("plus", 18)} Necessidade</button>
            <a class="btn btn-ghost" href="${UI.pageLink(`HANDOFF_MAPA_CLIENTES/02_PROJETO_ATUAL/index.html?cliente=${client.id}`)}" target="_blank" rel="noopener">${UI.icon("pin")} Abrir no mapa</a>
            <button class="btn btn-secondary" id="clientHistoryPdfBtn">${UI.icon("file")} PDF de visitas</button>
          </div>
        </section>

        <section class="client-overview-grid reveal">
          <div class="panel panel-contact">
            <div class="panel-head">
              <div><span class="eyebrow">Dados essenciais</span><h3>Contato e relacionamento</h3></div>
              <span class="panel-symbol">${UI.icon("user", 23)}</span>
            </div>
            <div class="info-grid compact-info">
              <div><small>Contato</small><strong>${client.contact || "NÃ£o informado"}</strong><span>${client.phone || "â€”"}</span></div>
              <div><small>E-mail</small><strong>${client.email || "NÃ£o informado"}</strong><span>${client.city}, ${client.state}</span></div>
              <div><small>ResponsÃ¡vel interno</small><strong>${owner?.name || "â€”"}</strong><span>${owner?.role || ""}</span></div>
              <div><small>Relacionamento desde</small><strong>${UI.date(client.createdAt)}</strong><span>${visits.length} visita(s)</span></div>
            </div>
            <div class="note-box"><small>ObservaÃ§Ãµes gerais</small><p>${client.notes || "Sem observaÃ§Ãµes."}</p></div>
          </div>

          <div class="panel location-panel">
            <div class="panel-head">
              <div><span class="eyebrow">LocalizaÃ§Ã£o rural</span><h3>Ponto do cliente</h3></div>
              <span class="panel-symbol">${UI.icon("pin", 23)}</span>
            </div>
            ${UI.miniMap(client.lat, client.lng, "Ponto do cliente", UI.pageLink("HANDOFF_MAPA_CLIENTES/02_PROJETO_ATUAL/index.html?cliente=" + client.id))}
            <div class="coord-row" style="margin-top: 16px; padding: 12px 14px; background: rgba(0,0,0,0.02); border-radius: 10px; border: 1px solid var(--line);">
              <div><span class="eyebrow">Coordenadas (Lat / Lng)</span><br><strong style="font-size: 13px; font-family: monospace;">${client.lat && client.lng ? `${Number(client.lat).toFixed(5)}, ${Number(client.lng).toFixed(5)}` : "NÃ£o definidas"}</strong></div>
              <div><span class="eyebrow">MunicÃ­pio base</span><br><strong style="font-size: 13px;">${client.municipio || "NÃ£o informado"} - ${client.uf || "--"}</strong></div>
            </div>
          </div>
        </section>

        <section class="panel media-panel reveal">
          <div class="panel-head">
            <div><span class="eyebrow">Registro visual</span><h3>Fotos e vÃ­deos das visitas</h3><p class="panel-subtitle">Todo material capturado pelos usuÃ¡rios aparece reunido aqui, em ordem cronolÃ³gica.</p></div>
            <div class="carousel-actions">
              <span class="count-pill">${media.length} mÃ­dia(s)</span>
              <button class="icon-btn carousel-prev" aria-label="Imagem anterior">${UI.icon("chevron",18)}</button>
              <button class="icon-btn carousel-next" aria-label="PrÃ³xima imagem">${UI.icon("chevron",18)}</button>
            </div>
          </div>
          ${media.length ? `
            <div class="media-carousel" id="clientMediaCarousel">
              <div class="media-track">
                ${media.map((item, index) => {
                  const src = item.dataUrl || item.url || "";
                  const isVideo = item.type?.startsWith("video/");
                  const isImage = item.type?.startsWith("image/");
                  return `
                  <article class="media-slide" data-media-index="${index}">
                    <div class="media-frame">
                      ${src && isImage
                        ? `<img src="${src}" alt="${item.name}" loading="lazy">`
                        : src && isVideo
                          ? `<video src="${src}" controls preload="metadata" playsinline></video>`
                          : `<div class="media-placeholder">${UI.icon(isVideo ? "camera" : "file", 36)}<strong>${item.name}</strong><small>PrÃ©via indisponÃ­vel.</small></div>`
                      }
                      <span class="media-type">${isVideo ? "VÃ­deo" : "Foto"}</span>
                    </div>
                    <div class="media-caption"><strong>${item.name}</strong><span>${item.source}</span></div>
                  </article>`;
                }).join("")}
              </div>
            </div>` :
            `<div class="media-empty">
              <span class="media-empty-icon">${UI.icon("camera", 34)}</span>
              <div><strong>A galeria comeÃ§a na prÃ³xima visita.</strong><p>Fotos e vÃ­deos capturados pelo celular serÃ£o exibidos neste carrossel automaticamente.</p></div>
              <a class="btn btn-secondary" href="${UI.pageLink(`pages/nova-visita.html?client=${client.id}`)}">${UI.icon("plus",16)} Registrar mÃ­dia</a>
            </div>`
          }
        </section>

        <section class="client-history-layout reveal">
          <div class="panel history-panel">
            <div class="panel-head">
              <div><span class="eyebrow">HistÃ³rico completo</span><h3>Visitas realizadas</h3></div>
              <span class="count-pill">${visits.length} visitas</span>
            </div>
            <div class="visit-report-list">
              ${visits.length ? visits.map((v, index) => {
                const user = state.users.find(u => u.id === v.userId);
                const trip = state.trips.find(t => t.id === v.tripId);
                const images = (v.attachments || []).filter(a => a.type?.startsWith("image/")).length;
                const files = (v.attachments || []).length;
                return `
                  <article class="visit-report-card">
                    <div class="visit-report-index"><span>${String(visits.length - index).padStart(2,"0")}</span></div>
                    <div class="visit-report-content">
                      <div class="timeline-top">
                        <div class="row-inline">${UI.statusBadge(v.type)}<span class="visit-state-dot" title="Registro concluÃ­do"></span></div>
                        <time>${UI.date(v.date, true)}</time>
                      </div>
                      <h4>${v.type} por ${user?.name || "UsuÃ¡rio"}</h4>
                      <p>${v.notes}</p>
                      ${v.needs?.length ? `<div class="tag-row">${v.needs.map(n => `<span class="tag">${n}</span>`).join("")}</div>` : ""}
                      <div class="visit-report-meta">
                        ${trip ? `<a class="context-link" href="${UI.pageLink(`pages/viagem.html?id=${trip.id}`)}">${UI.icon("briefcase", 15)} ${trip.name}</a>` : `<span>${UI.icon("briefcase",15)} Sem viagem</span>`}
                        <span>${UI.icon("camera",15)} ${images} foto(s)</span>
                        <span>${UI.icon("paperclip",15)} ${files} anexo(s)</span>
                        ${v.lat && v.lng ? `<span>${UI.icon("pin",15)} localizaÃ§Ã£o registrada</span>` : ""}
                      </div>
                    </div>
                    <button class="btn btn-pdf" data-pdf-visit="${v.id}" aria-label="Gerar PDF desta visita">${UI.icon("file",16)} PDF da visita</button>
                  </article>`;
              }).join("") : UI.empty("Ainda sem histÃ³rico", "A primeira visita aparecerÃ¡ aqui.")}
            </div>
          </div>

          <div class="client-side-stack">
            <div class="panel needs-history-panel">
              <div class="panel-head"><div><span class="eyebrow">Mapa de necessidades</span><h3>Interesses registrados</h3></div><span class="panel-symbol">${UI.icon("chart",21)}</span></div>
              <div class="tag-row">${(client.needs || []).length ? client.needs.map(n => `<span class="tag tag-accent">${n}</span>`).join("") : `<span class="muted">Nenhuma necessidade registrada.</span>`}</div>
              ${needRecords.length ? `<div class="need-records">${needRecords.slice(0,5).map(n => `
                <div class="need-record">
                  <span class="need-priority priority-${n.priority?.toLowerCase()}"></span>
                  <div><strong>${n.category}</strong><p>${n.description}</p><small>${UI.date(n.date, true)} Â· ${n.priority || "Normal"}</small></div>
                </div>`).join("")}</div>` : ""}
            </div>

            <div class="panel attachments-panel">
              <div class="panel-head"><div><span class="eyebrow">Documentos gerais</span><h3>Anexos do cliente</h3></div><span class="panel-symbol">${UI.icon("paperclip",21)}</span></div>
              ${client.attachments?.length
                ? client.attachments.map(a => `<div class="file-row">${UI.icon("paperclip")}<span><strong>${a.name}</strong><small>${Math.round(a.size/1024)} KB</small></span></div>`).join("")
                : UI.empty("Sem anexos gerais", "Os anexos especÃ­ficos de cada visita ficam preservados no respectivo relatÃ³rio.")}
            </div>
          </div>
        </section>



        <dialog id="needDialog" class="form-dialog">
          <form method="dialog" id="needForm" class="need-dialog-form">
            <div class="dialog-head"><div><span class="eyebrow">Cliente</span><h2>Registrar necessidade</h2></div><button class="icon-btn" value="cancel" aria-label="Fechar">${UI.icon("x")}</button></div>
            <div class="form-grid">
              <label class="field span-2"><span>Tipo de interesse / necessidade</span><select name="category" required><option value="Produto / Equipamento">Produto / Equipamento</option><option value="ServiÃ§o / Projeto">ServiÃ§o / Projeto</option><option value="ManutenÃ§Ã£o / Suporte">ManutenÃ§Ã£o / Suporte</option><option value="OrÃ§amento / Proposta">OrÃ§amento / Proposta</option><option value="Prazo / Entrega">Prazo / Entrega</option><option value="Outro">Outro</option></select></label>
              <label class="field span-2"><span>DescriÃ§Ã£o</span><textarea name="description" rows="4" required placeholder="Descreva o problema, interesse ou prÃ³ximo passo necessÃ¡rio."></textarea></label>
              <label class="field"><span>Prioridade</span><select name="priority"><option>Normal</option><option>Alta</option><option>Baixa</option></select></label>
            </div>
            <div class="dialog-actions"><button class="btn btn-secondary" value="cancel">Cancelar</button><button class="btn btn-primary" value="default">${UI.icon("check",17)} Registrar</button></div>
          </form>
        </dialog>
      `;

      UI.$("#openNeedBtn")?.addEventListener("click", () => UI.openDialog("needDialog"));
            UI.$("#needForm")?.addEventListener("submit", async (e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        const desc = String(fd.get("description") || "").trim();
        if (!desc) {
          UI.toast("Informe a descrição da necessidade.", "error");
          return;
        }
        
        const btn = e.currentTarget.querySelector("button[type='submit']");
        if (btn) btn.disabled = true;

        try {
          const payload = {
            clientId: client.id,
            category: fd.get("category"),
            description: desc,
            priority: fd.get("priority")
          };
          await UI.createSupabaseNeed(payload);
          UI.toast("Necessidade registrada com sucesso.");
          setTimeout(() => location.reload(), 350);
        } catch (err) {
          console.error(err);
          UI.toast("Erro ao registrar necessidade.", "error");
          if (btn) btn.disabled = false;
        }
      });



      const track = UI.$("#clientMediaCarousel .media-track");
      const scrollCarousel = (direction) => {
        if (!track) return;
        const slide = track.querySelector(".media-slide");
        const amount = (slide?.getBoundingClientRect().width || 320) + 14;
        track.scrollBy({ left: amount * direction, behavior: "smooth" });
      };
      UI.$(".carousel-prev")?.addEventListener("click", () => scrollCarousel(-1));
      UI.$(".carousel-next")?.addEventListener("click", () => scrollCarousel(1));

      UI.$("#clientHistoryPdfBtn")?.addEventListener("click", async (e) => {
        const button = e.currentTarget;
        const original = button.innerHTML;
        button.disabled = true;
        button.innerHTML = `${UI.icon("clock",16)} Gerando PDF...`;
        try {
          await PDFReport.downloadClientHistory({
            client,
            visits,
            state,
            logoUrl: UI.pageLink("assets/images/logo-mais.jpg")
          });
          UI.toast("PDF do histÃ³rico de visitas gerado.");
        } catch (error) {
          console.error(error);
          UI.toast("NÃ£o foi possÃ­vel gerar o PDF.", "error");
        } finally {
          button.disabled = false;
          button.innerHTML = original;
        }
      });

      UI.$$("[data-pdf-visit]").forEach(button => {
        button.addEventListener("click", async () => {
          const visit = visits.find(v => v.id === button.dataset.pdfVisit);
          if (!visit) return;
          const original = button.innerHTML;
          button.disabled = true;
          button.innerHTML = `${UI.icon("clock",15)} Gerando...`;
          try {
            await PDFReport.downloadVisit({
              client,
              visit,
              state,
              logoUrl: UI.pageLink("assets/images/logo-mais.jpg")
            });
            UI.toast("PDF da visita gerado.");
          } catch (error) {
            console.error(error);
            UI.toast("Falha ao gerar o PDF da visita.", "error");
          } finally {
            button.disabled = false;
            button.innerHTML = original;
          }
        });
      });

      UI.initMaps();
      UI.decorateVisuals();
      UI.initRevealObserver();
    };

    render();
  }
};
