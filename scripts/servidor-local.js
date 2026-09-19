#!/usr/bin/env node

/*
 * Servidor estático local, sem dependências externas.
 *
 * Uso:
 *   node scripts/servidor-local.js
 *   node scripts/servidor-local.js 8080
 */

const http = require("http");
const fs = require("fs");
const path = require("path");

const rootDirectory = path.resolve(__dirname, "..");
const requestedPort = Number(process.argv[2] || 8080);
const port = Number.isInteger(requestedPort) && requestedPort > 0 && requestedPort < 65536
  ? requestedPort
  : 8080;

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".webp": "image/webp"
};

function resolveFile(requestUrl) {
  const pathname = decodeURIComponent(new URL(requestUrl, "http://localhost").pathname);
  const cleanPathname = pathname.replace(/\\/g, "/");
  const absolutePath = path.resolve(rootDirectory, `.${cleanPathname}`);

  if (absolutePath !== rootDirectory && !absolutePath.startsWith(`${rootDirectory}${path.sep}`)) {
    return null;
  }

  try {
    const stat = fs.statSync(absolutePath);
    return stat.isDirectory() ? path.join(absolutePath, "index.html") : absolutePath;
  } catch {
    return absolutePath;
  }
}

function redirectMapAlias(requestUrl) {
  const parsed = new URL(requestUrl, "http://localhost");
  const pathname = parsed.pathname.replace(/\/+$/, "") || "/";
  const aliases = new Set(["/mapa", "/HANDOFF_MAPA_CLIENTES"]);
  if (!aliases.has(pathname)) return null;

  if (!parsed.searchParams.has("app_version")) {
    parsed.searchParams.set("app_version", "20260919-conexao");
  }
  return `/HANDOFF_MAPA_CLIENTES/02_PROJETO_ATUAL/?${parsed.searchParams.toString()}`;
}

const server = http.createServer((request, response) => {
  if (!request.url || !["GET", "HEAD"].includes(request.method || "")) {
    response.writeHead(405, { Allow: "GET, HEAD" });
    response.end("Método não permitido");
    return;
  }

  try {
    const redirect = redirectMapAlias(request.url);
    if (redirect) {
      response.writeHead(302, { Location: redirect, "Cache-Control": "no-store" });
      response.end();
      return;
    }
  } catch {
    response.writeHead(400);
    response.end("Endereço inválido");
    return;
  }

  let filePath;
  try {
    filePath = resolveFile(request.url);
  } catch {
    response.writeHead(400);
    response.end("Endereço inválido");
    return;
  }

  if (!filePath) {
    response.writeHead(403);
    response.end("Acesso não permitido");
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      response.writeHead(error.code === "ENOENT" ? 404 : 500, { "Content-Type": "text/plain; charset=utf-8" });
      response.end(error.code === "ENOENT" ? "Arquivo não encontrado" : "Erro ao ler o arquivo");
      return;
    }

    const contentType = contentTypes[path.extname(filePath).toLowerCase()] || "application/octet-stream";
    response.writeHead(200, {
      "Content-Type": contentType,
      "Cache-Control": "no-store"
    });
    if (request.method === "HEAD") {
      response.end();
      return;
    }
    response.end(content);
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log("Central Comercial disponível em:");
  console.log(`  http://localhost:${port}/`);
  console.log("Mapa disponível em:");
  console.log(`  http://localhost:${port}/HANDOFF_MAPA_CLIENTES/02_PROJETO_ATUAL/`);
  console.log(`  http://localhost:${port}/mapa/`);
  console.log("Use Ctrl+C para encerrar.");
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    console.error(`A porta ${port} já está em uso. Tente: node scripts/servidor-local.js 8081`);
  } else {
    console.error(error.message);
  }
  process.exitCode = 1;
});
