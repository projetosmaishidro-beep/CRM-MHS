
window.PDFReport = (() => {
  const PAGE_W = 595.28;
  const PAGE_H = 841.89;
  const MARGIN = 42;
  const NAVY = [0.094, 0.153, 0.263];
  const CYAN = [0.055, 0.584, 0.710];
  const RED = [0.882, 0.169, 0.184];
  const INK = [0.11, 0.15, 0.22];
  const MUTED = [0.37, 0.43, 0.48];
  const LIGHT = [0.95, 0.97, 0.98];

  const replaceUnsupported = (value) => String(value ?? "")
    .replace(/[–—]/g, "-")
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/…/g, "...")
    .replace(/[^\u0000-\u00FF]/g, "");

  function pdfEscape(value) {
    return replaceUnsupported(value).replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
  }

  function cp1252Bytes(value) {
    const s = replaceUnsupported(value);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 255;
    return out;
  }

  function asciiBytes(value) {
    return new TextEncoder().encode(value);
  }

  function concatBytes(chunks) {
    const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const out = new Uint8Array(total);
    let offset = 0;
    chunks.forEach(chunk => { out.set(chunk, offset); offset += chunk.length; });
    return out;
  }

  function streamObjectBytes(dictionary, dataBytes) {
    return concatBytes([
      asciiBytes(`${dictionary} /Length ${dataBytes.length} >>\nstream\n`),
      dataBytes,
      asciiBytes("\nendstream")
    ]);
  }

  function colorCmd(rgb, stroke = false) {
    return `${rgb.map(n => Number(n).toFixed(3)).join(" ")} ${stroke ? "RG" : "rg"}`;
  }

  class Builder {
    constructor() {
      this.pages = [];
      this.images = [];
      this.imageCache = new Map();
      this.newPage();
    }

    newPage() {
      const page = { ops: [], images: new Set() };
      this.pages.push(page);
      this.page = page;
      return page;
    }

    rect(x, yTop, w, h, fill) {
      const y = PAGE_H - yTop - h;
      this.page.ops.push(`${colorCmd(fill)} ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f`);
    }

    line(x1, y1Top, x2, y2Top, color = MUTED, width = 0.6) {
      this.page.ops.push(`${colorCmd(color, true)} ${width.toFixed(2)} w ${x1.toFixed(2)} ${(PAGE_H-y1Top).toFixed(2)} m ${x2.toFixed(2)} ${(PAGE_H-y2Top).toFixed(2)} l S`);
    }

    text(x, yTop, text, size = 10, bold = false, color = INK) {
      const y = PAGE_H - yTop - size;
      this.page.ops.push(`${colorCmd(color)} BT /${bold ? "F2" : "F1"} ${size.toFixed(2)} Tf ${x.toFixed(2)} ${y.toFixed(2)} Td (${pdfEscape(text)}) Tj ET`);
    }

    wrap(text, maxWidth, size = 10) {
      const maxChars = Math.max(12, Math.floor(maxWidth / (size * 0.53)));
      const paragraphs = String(text ?? "").split(/\n/);
      const lines = [];
      for (const paragraph of paragraphs) {
        const words = paragraph.split(/\s+/).filter(Boolean);
        if (!words.length) { lines.push(""); continue; }
        let line = "";
        for (const word of words) {
          const next = line ? `${line} ${word}` : word;
          if (next.length > maxChars && line) {
            lines.push(line);
            line = word;
          } else {
            line = next;
          }
        }
        if (line) lines.push(line);
      }
      return lines;
    }

    paragraph(x, yTop, text, maxWidth, size = 10, lineHeight = 14, color = INK, bold = false) {
      const lines = this.wrap(text, maxWidth, size);
      lines.forEach((line, idx) => this.text(x, yTop + idx * lineHeight, line, size, bold, color));
      return yTop + lines.length * lineHeight;
    }

    addImage(imageIndex, x, yTop, w, h) {
      const image = this.images[imageIndex];
      if (!image) return;
      const scale = Math.min(w / image.width, h / image.height);
      const drawW = image.width * scale;
      const drawH = image.height * scale;
      const y = PAGE_H - yTop - drawH;
      const name = `Im${imageIndex + 1}`;
      this.page.images.add(imageIndex);
      this.page.ops.push(`q ${drawW.toFixed(2)} 0 0 ${drawH.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)} cm /${name} Do Q`);
      return { width: drawW, height: drawH };
    }

    async registerImage(src) {
      if (!src) return null;
      const dataUrl = src.startsWith("http") ? await fetchAsDataUrl(src) : src;
      if (!dataUrl) return null;
      if (this.imageCache.has(dataUrl)) return this.imageCache.get(dataUrl);
      const prepared = await normalizeToJpeg(dataUrl);
      if (!prepared) return null;
      const index = this.images.length;
      this.images.push(prepared);
      this.imageCache.set(dataUrl, index);
      return index;
    }

    build() {
      const nImages = this.images.length;
      const pageObjStart = 5 + nImages;
      const pageRefs = this.pages.map((_, i) => pageObjStart + i * 2);
      const objects = new Map();

      objects.set(1, asciiBytes("<< /Type /Catalog /Pages 2 0 R >>"));
      objects.set(2, asciiBytes(`<< /Type /Pages /Count ${this.pages.length} /Kids [${pageRefs.map(n => `${n} 0 R`).join(" ")}] >>`));
      objects.set(3, asciiBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"));
      objects.set(4, asciiBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"));

      this.images.forEach((img, i) => {
        const id = 5 + i;
        objects.set(id, streamObjectBytes(
          `<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode`,
          img.bytes
        ));
      });

      this.pages.forEach((page, i) => {
        const pageId = pageObjStart + i * 2;
        const contentId = pageId + 1;
        const xObjects = [...page.images].map(index => `/Im${index+1} ${5+index} 0 R`).join(" ");
        const resources = `<< /Font << /F1 3 0 R /F2 4 0 R >>${xObjects ? ` /XObject << ${xObjects} >>` : ""} >>`;
        objects.set(pageId, asciiBytes(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] /Resources ${resources} /Contents ${contentId} 0 R >>`));
        const content = cp1252Bytes(page.ops.join("\n"));
        objects.set(contentId, streamObjectBytes("<<", content));
      });

      const maxId = Math.max(...objects.keys());
      const chunks = [asciiBytes("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")];
      const offsets = new Array(maxId + 1).fill(0);
      let offset = chunks[0].length;

      for (let id = 1; id <= maxId; id++) {
        offsets[id] = offset;
        const body = objects.get(id) || asciiBytes("<<>>");
        const objBytes = concatBytes([asciiBytes(`${id} 0 obj\n`), body, asciiBytes("\nendobj\n")]);
        chunks.push(objBytes);
        offset += objBytes.length;
      }

      const xrefOffset = offset;
      let xref = `xref\n0 ${maxId + 1}\n0000000000 65535 f \n`;
      for (let id = 1; id <= maxId; id++) xref += `${String(offsets[id]).padStart(10, "0")} 00000 n \n`;
      xref += `trailer\n<< /Size ${maxId + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
      chunks.push(asciiBytes(xref));

      return new Blob([concatBytes(chunks)], { type: "application/pdf" });
    }
  }

  function dataUrlBytes(dataUrl) {
    const base64 = String(dataUrl).split(",")[1] || "";
    const raw = atob(base64);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return bytes;
  }

  function jpegDimensions(bytes) {
    if (!bytes || bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
    let offset = 2;
    while (offset + 8 < bytes.length) {
      if (bytes[offset] !== 0xff) { offset++; continue; }
      const marker = bytes[offset + 1];
      const length = (bytes[offset + 2] << 8) + bytes[offset + 3];
      if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {
        return {
          height: (bytes[offset + 5] << 8) + bytes[offset + 6],
          width: (bytes[offset + 7] << 8) + bytes[offset + 8]
        };
      }
      if (!length || length < 2) break;
      offset += 2 + length;
    }
    return null;
  }

  async function normalizeToJpeg(dataUrl) {
    try {
      if (/^data:image\/jpe?g;base64,/i.test(dataUrl)) {
        const bytes = dataUrlBytes(dataUrl);
        const dims = jpegDimensions(bytes);
        if (dims) return { bytes, width: dims.width, height: dims.height };
      }

      const img = await new Promise((resolve, reject) => {
        const el = new Image();
        el.onload = () => resolve(el);
        el.onerror = reject;
        el.src = dataUrl;
      });
      const max = 1400;
      const ratio = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
      const width = Math.max(1, Math.round(img.naturalWidth * ratio));
      const height = Math.max(1, Math.round(img.naturalHeight * ratio));
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, width, height);
      ctx.drawImage(img, 0, 0, width, height);
      const jpeg = canvas.toDataURL("image/jpeg", 0.84);
      return { bytes: dataUrlBytes(jpeg), width, height };
    } catch {
      return null;
    }
  }

  async function fetchAsDataUrl(url) {
    try {
      const response = await fetch(url);
      const blob = await response.blob();
      return await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsDataURL(blob);
      });
    } catch {
      return null;
    }
  }

  function safeFilename(value) {
    return String(value || "relatorio")
      .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  }

  function download(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }

  function dateText(value) {
    try {
      return new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeStyle: "short" }).format(new Date(value));
    } catch {
      return String(value || "");
    }
  }

  async function renderVisit(builder, ctx, firstVisit = false) {
    const { client, visit, user, trip, logoIndex } = ctx;
    if (!firstVisit) builder.newPage();

    builder.rect(0, 0, PAGE_W, 116, NAVY);
    builder.rect(0, 116, PAGE_W, 5, CYAN);
    builder.rect(0, 121, PAGE_W, 3, RED);

    if (logoIndex !== null) {
      builder.rect(MARGIN - 4, 18, 122, 78, [1,1,1]);
      builder.addImage(logoIndex, MARGIN, 22, 114, 70);
    }

    builder.text(180, 32, "RELATÓRIO DE VISITA", 19, true, [1,1,1]);
    builder.text(180, 58, client.name, 13, true, [1,1,1]);
    builder.text(180, 78, `${client.city || ""}${client.state ? ` - ${client.state}` : ""}`, 9, false, [0.82,0.88,0.92]);

    let y = 148;
    builder.text(MARGIN, y, "Resumo da visita", 14, true, NAVY);
    y += 22;

    builder.rect(MARGIN, y, PAGE_W - MARGIN * 2, 72, LIGHT);
    builder.text(MARGIN + 14, y + 13, "Data", 8, true, CYAN);
    builder.text(MARGIN + 14, y + 29, dateText(visit.date), 10, true, INK);
    builder.text(MARGIN + 240, y + 13, "Responsável", 8, true, CYAN);
    builder.text(MARGIN + 240, y + 29, user?.name || "Não informado", 10, true, INK);
    builder.text(MARGIN + 14, y + 49, `Tipo: ${visit.type || "Visita"}`, 9, false, MUTED);
    builder.text(MARGIN + 240, y + 49, `Viagem: ${trip?.name || "Sem viagem vinculada"}`, 9, false, MUTED);
    y += 95;

    builder.text(MARGIN, y, "Informações registradas", 12, true, NAVY);
    y += 20;
    y = builder.paragraph(MARGIN, y, visit.notes || "Sem observações registradas.", PAGE_W - MARGIN * 2, 10, 14, INK);
    y += 12;

    if (visit.needs?.length) {
      builder.text(MARGIN, y, "Necessidades / interesses", 10, true, CYAN);
      y += 16;
      y = builder.paragraph(MARGIN, y, visit.needs.join(" • "), PAGE_W - MARGIN * 2, 9, 13, INK);
      y += 10;
    }

    builder.text(MARGIN, y, "Localização", 10, true, CYAN);
    y += 15;
    builder.text(MARGIN, y, (visit.lat && visit.lng) ? `${Number(visit.lat).toFixed(5)}, ${Number(visit.lng).toFixed(5)}` : "Não registrada", 9, false, INK);
    y += 24;

    const attachments = visit.attachments || [];
    builder.text(MARGIN, y, `Anexos (${attachments.length})`, 10, true, CYAN);
    y += 16;
    if (attachments.length) {
      attachments.forEach((a) => {
        builder.text(MARGIN + 8, y, `• ${a.name} (${Math.round((a.size || 0)/1024)} KB)`, 8.5, false, MUTED);
        y += 13;
      });
    } else {
      builder.text(MARGIN + 8, y, "Nenhum anexo nesta visita.", 8.5, false, MUTED);
      y += 14;
    }
    y += 12;

    const photos = attachments.filter(a => a.type?.startsWith("image/") && (a.dataUrl || a.url));
    if (photos.length) {
      builder.text(MARGIN, y, "Registro fotográfico", 12, true, NAVY);
      y += 18;
      for (const photo of photos) {
        const src = photo.dataUrl || photo.url;
        const idx = await builder.registerImage(src);
        if (idx === null) continue;
        if (y > 560) {
          builder.newPage();
          builder.rect(0, 0, PAGE_W, 54, NAVY);
          builder.text(MARGIN, 18, `${client.name} - continuação`, 12, true, [1,1,1]);
          y = 80;
        }
        builder.rect(MARGIN, y, PAGE_W - MARGIN*2, 285, [0.97,0.98,0.99]);
        const box = builder.addImage(idx, MARGIN + 10, y + 10, PAGE_W - MARGIN*2 - 20, 245);
        builder.text(MARGIN + 10, y + 265, photo.name, 8, false, MUTED);
        y += 300;
      }
    } else {
      builder.rect(MARGIN, y, PAGE_W - MARGIN*2, 62, [0.98,0.98,0.99]);
      builder.text(MARGIN + 14, y + 18, "Sem fotos armazenadas nesta visita.", 9, true, MUTED);
      builder.text(MARGIN + 14, y + 36, "Novas fotos capturadas pelo usuário aparecerão automaticamente no relatório.", 8, false, MUTED);
      y += 78;
    }

    builder.line(MARGIN, 797, PAGE_W - MARGIN, 797, [0.82,0.85,0.88], 0.5);
    builder.text(MARGIN, 806, "Mais Hidro Soluções • Central Comercial", 7.5, true, NAVY);
    builder.text(PAGE_W - 178, 806, "Documento gerado pela demonstração local", 7.2, false, MUTED);
  }

  async function buildReport({ client, visits, state, logoUrl }) {
    const builder = new Builder();
    const logoDataUrl = await fetchAsDataUrl(logoUrl);
    const logoIndex = logoDataUrl ? await builder.registerImage(logoDataUrl) : null;

    const items = visits.map(v => ({
      visit: v,
      user: state.users.find(u => u.id === v.userId),
      trip: state.trips.find(t => t.id === v.tripId)
    }));

    if (!items.length) {
      builder.rect(0, 0, PAGE_W, 124, NAVY);
      if (logoIndex !== null) builder.addImage(logoIndex, MARGIN, 22, 114, 70);
      builder.text(MARGIN, 160, "Relatório de visitas", 18, true, NAVY);
      builder.text(MARGIN, 190, client.name, 13, true, INK);
      builder.text(MARGIN, 225, "Nenhuma visita registrada para este cliente.", 10, false, MUTED);
    } else {
      for (let i = 0; i < items.length; i++) {
        await renderVisit(builder, { client, ...items[i], logoIndex }, i === 0);
      }
    }
    return builder.build();
  }

  async function downloadVisit({ client, visit, state, logoUrl }) {
    const blob = await buildReport({ client, visits: [visit], state, logoUrl });
    download(blob, `visita-${safeFilename(client.name)}-${new Date(visit.date).toISOString().slice(0,10)}.pdf`);
  }

  async function downloadClientHistory({ client, visits, state, logoUrl }) {
    const blob = await buildReport({ client, visits, state, logoUrl });
    download(blob, `historico-visitas-${safeFilename(client.name)}.pdf`);
  }

  return { downloadVisit, downloadClientHistory, buildReport };
})();
