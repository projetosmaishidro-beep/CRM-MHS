/*
 * Camada de dados da Central Comercial.
 *
 * Unico ponto do frontend que fala com o Supabase: cliente autenticado,
 * leitura das views do schema api, RPCs de escrita e upload no Storage.
 * As paginas nao usam este modulo diretamente: o UI reexpoe estas funcoes
 * com os nomes UI.*Supabase* (ver AGENTS.md, "Contrato entre as camadas").
 *
 * Depende de: SUPABASE_CONFIG (supabase-config.js), AuthClient
 * (auth-guard.js) e Store (store.js). Deve ser carregado antes de ui.js.
 */
window.Api = (() => {
  const CONNECTION_STORAGE_KEY = "mais_hidro_supabase_connection_v1";
  const initials = (name = "") => name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();

  let supabaseClient = null;
  let supabaseClientFingerprint = "";

  function readConnection() {
    // Prefer centralized config over per-browser localStorage
    const config = window.SUPABASE_CONFIG || {};
    if (config.SUPABASE_URL && config.SUPABASE_ANON_KEY) {
      return { url: config.SUPABASE_URL, apiKey: config.SUPABASE_ANON_KEY };
    }
    try {
      const saved = JSON.parse(localStorage.getItem(CONNECTION_STORAGE_KEY) || "null");
      return saved && typeof saved === "object" ? saved : {};
    } catch {
      return {};
    }
  }

  function isRestrictedSupabaseKey(apiKey) {
    if (/service_role|sb_secret/i.test(apiKey)) return true;
    try {
      const [, encodedPayload, signature] = apiKey.split(".");
      if (!encodedPayload || !signature) return false;
      const payload = JSON.parse(atob(encodedPayload.replace(/-/g, "+").replace(/_/g, "/")));
      return payload.role === "service_role";
    } catch {
      return false;
    }
  }

  async function loadSupabaseLibrary() {
    if (window.supabase?.createClient) return window.supabase;
    if (!window.__centralSupabaseLibraryPromise) {
      window.__centralSupabaseLibraryPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
        script.async = true;
        script.onload = () => window.supabase?.createClient
          ? resolve(window.supabase)
          : reject(new Error("A biblioteca do Supabase não foi carregada."));
        script.onerror = () => reject(new Error("Não foi possível carregar a biblioteca do Supabase."));
        document.head.appendChild(script);
      });
    }
    return window.__centralSupabaseLibraryPromise;
  }

  async function getSupabaseClient(connection = readConnection()) {
    if (!connection?.url || !connection?.apiKey) return null;
    
    const config = window.SUPABASE_CONFIG || {};
    if (window.AuthClient && connection.url === config.SUPABASE_URL && connection.apiKey === config.SUPABASE_ANON_KEY) {
      return window.AuthClient;
    }

    const api = await loadSupabaseLibrary();
    const fingerprint = `${connection.url}|${connection.apiKey}`;
    if (!supabaseClient || supabaseClientFingerprint !== fingerprint) {
      supabaseClient = api.createClient(connection.url, connection.apiKey, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
      });
      supabaseClientFingerprint = fingerprint;
    }
    return supabaseClient;
  }

  const categoryLabels = {
    CARCINICULTOR: "Carcinicultor",
    IRRIGACAO: "Irrigação",
    CONSTRUCAO_CIVIL: "Construção civil",
    MINERACAO: "Mineração",
    CONDOMINIAL: "Condominial",
    OUTRO: "Outro",
    PENDENTE_CLASSIFICACAO: "Outro"
  };

  function mapRemoteClient(row) {
    const category = categoryLabels[row.categoria] || "Outro";
    return {
      id: row.empresa_id,
      name: row.empresa || row.nome_fantasia || row.razao_social || "Empresa sem nome",
      company: row.razao_social || row.empresa || "",
      contact: row.contato_nome || "",
      phone: row.whatsapp || row.telefone || "",
      email: row.email || "",
      city: row.municipio || "Não informado",
      state: row.uf || "",
      segment: category,
      category,
      status: row.tipo_relacionamento === "CLIENTE" ? "Cliente" : "Lead",
      lat: row.latitude === null ? null : Number(row.latitude),
      lng: row.longitude === null ? null : Number(row.longitude),
      notes: row.observacao_localizacao || "",
      needs: [],
      needRecords: [],
      createdAt: row.relacionamento_criado_em || new Date().toISOString(),
      ownerId: row.responsavel_por || "",
      attachments: [],
      remote: true
    };
  }

  function mapRemoteTrip(row) {
    const participantRows = Array.isArray(row?.participantes) ? row.participantes : [];
    const clientRows = Array.isArray(row?.empresas_planejadas) ? row.empresas_planejadas : [];
    const statusMap = {
      PLANEJADA: "Planejada",
      EM_ANDAMENTO: "Em andamento",
      CONCLUIDA: "Concluída",
      CANCELADA: "Cancelada"
    };
    const snapshotId = (item) => typeof item === "string" ? item : item?.id;

    return {
      id: row.viagem_id,
      name: row.titulo || "Viagem sem título",
      status: statusMap[row.status] || row.status || "Planejada",
      startDate: row.inicio_em ? String(row.inicio_em).slice(0, 10) : "",
      endDate: row.fim_em ? String(row.fim_em).slice(0, 10) : "",
      objective: row.observacao || "",
      notes: row.observacao || "",
      participantIds: participantRows.map(snapshotId).filter(Boolean),
      plannedClientIds: clientRows.map(snapshotId).filter(Boolean),
      participantSnapshots: participantRows,
      plannedClientSnapshots: clientRows,
      startKm: row.km_inicial === null ? null : Number(row.km_inicial),
      currentKm: row.km_final === null ? null : Number(row.km_final),
      endKm: row.km_final === null ? null : Number(row.km_final),
      stops: [],
      attachments: [],
      createdAt: row.criado_em || new Date().toISOString(),
      ownerId: "",
      remote: true
    };
  }

  // ------------------------------------------------------------------
  // API operacional: Supabase e a fonte de verdade. O Store recebe apenas
  // respostas confirmadas pelo banco e funciona como cache de renderizacao.
  // ------------------------------------------------------------------
  const asArray = (value) => {
    if (Array.isArray(value)) return value;
    if (typeof value !== "string") return [];
    try { const parsed = JSON.parse(value); return Array.isArray(parsed) ? parsed : []; } catch { return []; }
  };
  const rpcValue = (value) => {
    const item = Array.isArray(value) ? value[0] : value;
    if (typeof item !== "string") return item || null;
    try { return JSON.parse(item); } catch { return null; }
  };

  async function operationalClient() {
    const client = window.AuthClient || await getSupabaseClient(readConnection());
    if (!client) throw new Error("Conexão do Supabase não configurada.");
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    if (!data.session) throw new Error("Sua sessão expirou. Entre novamente.");
    return client;
  }

  async function operationalRpc(name, args) {
    const client = await operationalClient();
    const { data, error } = await client.schema("api").rpc(name, args);
    if (error) throw new Error(error.message || "Falha ao salvar no Supabase.");
    // Toda escrita invalida o retrato em cache: a proxima leitura (inclusive
    // a recarga que as telas fazem depois de salvar) busca o banco.
    await invalidateSnapshotCache();
    return rpcValue(data);
  }

  // Executa tarefas assincronas com no maximo `limit` em andamento.
  async function runLimited(tasks, limit) {
    const results = new Array(tasks.length);
    let next = 0;
    const worker = async () => {
      while (next < tasks.length) {
        const index = next++;
        results[index] = await tasks[index]();
      }
    };
    await Promise.all(Array.from({ length: Math.min(limit, tasks.length) }, worker));
    return results;
  }

  const tripFromApi = (row) => {
    const value = mapRemoteTrip(row);
    value.stops = asArray(row.paradas);
    value.odometerRecords = asArray(row.odometro_registros);
    value.attachments = asArray(row.anexos);
    value.noteBlocks = asArray(row.notas);
    value.ownerId = row.criado_por || "";
    return value;
  };
  const visitFromApi = (row) => {
    const needs = asArray(row.necessidades);
    return { id: row.visita_id, clientId: row.empresa_id, tripId: row.viagem_id || null, userId: row.criado_por || "", type: row.tipo || "Acompanhamento", notes: row.observacao || "", needs: needs.map((need) => need.category || need), needRecords: needs, lat: row.latitude === null ? null : Number(row.latitude), lng: row.longitude === null ? null : Number(row.longitude), attachments: asArray(row.anexos), date: row.realizada_em || row.criado_em, remote: true };
  };
  const expenseFromApi = (row) => ({ id: row.despesa_id, tripId: row.viagem_id || null, eventId: row.evento_id || null, userId: row.criado_por || "", category: row.categoria || "Outros", costCenter: row.centro_custo || "", amount: Number(row.valor) || 0, place: row.estabelecimento || "", notes: row.descricao || "", attachments: asArray(row.anexos), date: row.data_despesa || row.criado_em, remote: true });
  // URLs assinadas do Storage expiram. O banco guarda o caminho do anexo e a
  // URL é renovada a cada carga; anexos antigos que só têm a URL têm o
  // caminho recuperado a partir dela.
  const ATTACHMENT_BUCKET = "crm-anexos";
  const SIGNED_URL_TTL_SECONDS = 3600;
  const storageUrlPattern = new RegExp(`/storage/v1/object/(?:sign|public|authenticated)/${ATTACHMENT_BUCKET}/([^?#]+)`);

  function attachmentPath(item) {
    if (!item || typeof item !== "object") return null;
    if (item.path && (!item.bucket || item.bucket === ATTACHMENT_BUCKET)) return item.path;
    const match = typeof item.url === "string" ? item.url.match(storageUrlPattern) : null;
    return match ? decodeURIComponent(match[1]) : null;
  }

  const SIGN_BATCH_SIZE = 500;
  const SIGN_CONCURRENCY = 4;

  async function refreshAttachmentUrls(client, attachmentLists) {
    const items = attachmentLists.flat().filter((item) => attachmentPath(item));
    const paths = [...new Set(items.map(attachmentPath))];
    if (!paths.length) return;
    const signed = new Map();
    const batches = [];
    for (let index = 0; index < paths.length; index += SIGN_BATCH_SIZE) batches.push(paths.slice(index, index + SIGN_BATCH_SIZE));
    await runLimited(batches.map((batch) => async () => {
      const { data, error } = await client.storage.from(ATTACHMENT_BUCKET).createSignedUrls(batch, SIGNED_URL_TTL_SECONDS);
      if (error) {
        console.warn("[Central] Não foi possível renovar os links dos anexos:", error);
        return;
      }
      (data || []).forEach((row) => { if (row.signedUrl && !row.error) signed.set(row.path, row.signedUrl); });
    }), SIGN_CONCURRENCY);
    items.forEach((item) => {
      const path = attachmentPath(item);
      if (!signed.has(path)) return;
      item.bucket = ATTACHMENT_BUCKET;
      item.path = path;
      item.url = signed.get(path);
    });
  }

  const eventFromApi = (row) => ({ id: row.evento_id, name: row.nome || "Evento", location: row.local || "", startDate: row.data_inicio ? String(row.data_inicio).slice(0, 10) : "", endDate: row.data_fim ? String(row.data_fim).slice(0, 10) : "", status: ({ PLANEJADO: "Planejado", EM_ANDAMENTO: "Em andamento", REALIZADO: "Realizado", CANCELADO: "Cancelado" })[row.status] || row.status || "Planejado", role: row.tipo_participacao === "EXPOSITOR" ? "Expositor" : "Participante", notes: row.notas_estrategicas || "", participantIds: asArray(row.participantes), attachments: asArray(row.anexos), links: asArray(row.links), contacts: asArray(row.contatos), createdAt: row.criado_em, userId: row.criado_por || "", remote: true });

  // ------------------------------------------------------------------
  // Leitura paginada das views
  // ------------------------------------------------------------------
  // O PostgREST limita cada resposta (max rows; 1000 no padrão do Supabase).
  // Sem paginar, carteira e visitas eram cortadas em silêncio. Cada view é
  // lida em blocos paralelos até o total informado pelo banco, com ordenação
  // estável (desempate pela chave) para nenhuma linha ser pulada ou repetida.
  const PAGE_SIZE = 1000;
  const PAGE_CONCURRENCY = 6;
  const SNAPSHOT_VIEWS = [
    { key: "clients", view: "vw_carteira_crm", id: "empresa_id", order: "empresa", ascending: true },
    { key: "trips", view: "vw_viagens", id: "viagem_id", order: "inicio_em", ascending: true },
    { key: "visits", view: "vw_visitas_crm", id: "visita_id", order: "realizada_em", ascending: false },
    { key: "needs", view: "vw_necessidades", id: "necessidade_id", order: "criado_em", ascending: false },
    { key: "expenses", view: "vw_despesas_crm", id: "despesa_id", order: "data_despesa", ascending: false },
    { key: "events", view: "vw_eventos", id: "evento_id", order: "data_inicio", ascending: false },
    { key: "users", view: "vw_equipe", id: "membro_id", order: "nome", ascending: true }
  ];

  async function fetchAllRows(api, spec) {
    const page = (from, to, withCount) => api.from(spec.view)
      .select("*", withCount ? { count: "exact" } : undefined)
      .order(spec.order, { ascending: spec.ascending })
      .order(spec.id, { ascending: true })
      .range(from, to);

    const first = await page(0, PAGE_SIZE - 1, true);
    if (first.error) return { error: first.error, rows: [] };
    const rows = [...(first.data || [])];
    const total = Number.isFinite(first.count) ? first.count : null;
    // O servidor pode limitar abaixo de PAGE_SIZE: o passo real é o que veio.
    const step = rows.length;
    if (step === 0) return { rows, total: total ?? 0 };

    if (total !== null && total > rows.length) {
      const ranges = [];
      for (let from = step; from < total; from += step) ranges.push([from, Math.min(from + step, total) - 1]);
      const pages = await runLimited(ranges.map(([from, to]) => () => page(from, to, false)), PAGE_CONCURRENCY);
      for (const result of pages) {
        if (result.error) return { error: result.error, rows };
        rows.push(...(result.data || []));
      }
    }
    // Sem contagem, ou se o total mudou durante a leitura: continua em
    // sequência enquanto vierem páginas cheias.
    while (total === null ? rows.length % step === 0 : rows.length < total) {
      const result = await page(rows.length, rows.length + step - 1, false);
      if (result.error) return { error: result.error, rows };
      if (!result.data?.length) break;
      rows.push(...result.data);
      if (result.data.length < step) break;
    }
    // Inserções durante a leitura podem deslocar o offset: remove repetidos.
    const seen = new Set();
    const unique = rows.filter((row) => {
      const id = row[spec.id];
      if (id === null || id === undefined) return true;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    return { rows: unique, total: total ?? unique.length };
  }

  // ------------------------------------------------------------------
  // Retrato em cache local (IndexedDB), separado por usuário
  // ------------------------------------------------------------------
  // Até SNAPSHOT_FRESH_MS o retrato é usado sem consultar o banco. Depois,
  // e até SNAPSHOT_MAX_AGE_MS, a tela abre com ele e o banco é lido em
  // segundo plano para a próxima navegação. Qualquer escrita invalida o
  // cache (em todas as abas, via localStorage) e o logout o apaga.
  const CACHE_DB_NAME = "central-comercial-cache";
  const CACHE_STORE = "snapshots";
  const CACHE_SCHEMA = 1;
  const SNAPSHOT_FRESH_MS = 2 * 60 * 1000;
  const SNAPSHOT_MAX_AGE_MS = 12 * 60 * 60 * 1000;
  const RESIGN_AFTER_MS = 45 * 60 * 1000;
  const INVALIDATED_KEY = "central_comercial_cache_invalidated_at";
  let cacheDbPromise = null;
  let backgroundRefresh = null;

  function openCacheDb() {
    if (!cacheDbPromise) {
      cacheDbPromise = new Promise((resolve) => {
        try {
          if (!window.indexedDB) return resolve(null);
          const request = indexedDB.open(CACHE_DB_NAME, CACHE_SCHEMA);
          request.onupgradeneeded = () => {
            if (!request.result.objectStoreNames.contains(CACHE_STORE)) request.result.createObjectStore(CACHE_STORE);
          };
          request.onsuccess = () => resolve(request.result);
          request.onerror = () => resolve(null);
          request.onblocked = () => resolve(null);
        } catch {
          resolve(null);
        }
      });
    }
    return cacheDbPromise;
  }

  async function cacheOperation(mode, run) {
    const db = await openCacheDb();
    if (!db) return null;
    return new Promise((resolve) => {
      try {
        const transaction = db.transaction(CACHE_STORE, mode);
        const request = run(transaction.objectStore(CACHE_STORE));
        transaction.oncomplete = () => resolve(request?.result ?? null);
        transaction.onerror = () => resolve(null);
        transaction.onabort = () => resolve(null);
      } catch {
        resolve(null);
      }
    });
  }

  const readSnapshotCache = (userId) => cacheOperation("readonly", (store) => store.get(userId));
  const lastInvalidation = () => { try { return Number(localStorage.getItem(INVALIDATED_KEY)) || 0; } catch { return 0; } };

  async function invalidateSnapshotCache() {
    try { localStorage.setItem(INVALIDATED_KEY, String(Date.now())); } catch { /* armazenamento indisponível */ }
    await cacheOperation("readwrite", (store) => store.clear());
  }

  async function saveSnapshot(userId, record) {
    // Uma leitura iniciada antes de uma escrita não pode sobrescrever o cache.
    if (!userId || record.fetchedAt <= lastInvalidation()) return;
    await cacheOperation("readwrite", (store) => store.put(record, userId));
  }

  async function fingerprintOf(raw) {
    const text = JSON.stringify(raw);
    try {
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
      return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
    } catch {
      return `len:${text.length}`;
    }
  }

  // ------------------------------------------------------------------
  // Montagem do retrato usado pelas telas
  // ------------------------------------------------------------------
  const ACTIVITY_LIMIT = 20;
  const moneyFormat = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
  const timeOf = (value) => { const time = new Date(value).getTime(); return Number.isFinite(time) ? time : -Infinity; };
  const latest = (rows, dateOf, limit) => rows
    .map((row) => [timeOf(dateOf(row)), row])
    .filter(([time]) => time > -Infinity)
    .sort((left, right) => right[0] - left[0])
    .slice(0, limit)
    .map(([, row]) => row);

  // "Últimos registros" do painel: derivado das visitas, despesas e viagens.
  function buildActivities({ clientsById, trips, visits, expenses }) {
    const items = [
      ...latest(visits, (visit) => visit.date, ACTIVITY_LIMIT).map((visit) => ({ id: `visit-${visit.id}`, userId: visit.userId, date: visit.date, text: `Visita (${visit.type}) em ${clientsById.get(visit.clientId)?.name || "cliente não identificado"}` })),
      ...latest(expenses, (expense) => expense.date, ACTIVITY_LIMIT).map((expense) => ({ id: `expense-${expense.id}`, userId: expense.userId, date: expense.date, text: `Despesa de ${moneyFormat.format(expense.amount)} em ${expense.category}` })),
      ...latest(trips, (trip) => trip.createdAt, ACTIVITY_LIMIT).map((trip) => ({ id: `trip-${trip.id}`, userId: trip.ownerId, date: trip.createdAt, text: `Viagem cadastrada: ${trip.name}` }))
    ];
    return latest(items, (item) => item.date, ACTIVITY_LIMIT);
  }

  function buildSnapshot(raw) {
    const clients = raw.clients.map(mapRemoteClient);
    const clientsById = new Map(clients.map((client) => [client.id, client]));
    raw.needs.forEach((row) => {
      const client = clientsById.get(row.empresa_id);
      if (!client) return;
      const need = { id: row.necessidade_id, clientId: row.empresa_id, visitId: row.visita_id, category: row.categoria, description: row.descricao, priority: row.prioridade, status: row.status, date: row.criado_em };
      client.needRecords.push(need);
      if (!client.needs.includes(need.category)) client.needs.push(need.category);
    });
    const users = raw.users.map((row) => {
      const name = row.nome || row.email || "Membro da equipe";
      return { id: row.usuario_id || row.membro_id, name, role: row.cargo || row.papel || "Equipe Comercial", initials: initials(name), email: row.email || "", active: row.ativo !== false, remote: true };
    });
    const trips = raw.trips.map(tripFromApi);
    const visits = raw.visits.map(visitFromApi);
    const expenses = raw.expenses.map(expenseFromApi);
    const events = raw.events.map(eventFromApi);
    return { clients, trips, visits, expenses, events, users, activities: buildActivities({ clientsById, trips, visits, expenses }) };
  }

  const attachmentListsOf = (snapshot) => [snapshot.trips, snapshot.visits, snapshot.expenses, snapshot.events].flat().map((row) => row.attachments || []);

  async function fetchSnapshot(client) {
    const fetchedAt = Date.now();
    const api = client.schema("api");
    const results = await Promise.all(SNAPSHOT_VIEWS.map((spec) => fetchAllRows(api, spec)));
    const raw = {};
    const failures = [];
    SNAPSHOT_VIEWS.forEach((spec, index) => {
      raw[spec.key] = results[index].rows;
      if (results[index].error) failures.push({ view: spec.view, error: results[index].error });
    });
    // Cada tela continua recebendo os dados das views que responderam: uma
    // falha pontual (ex.: despesas) não impede as demais de serem exibidas.
    if (failures.length) console.error("[Central] Views que não puderam ser carregadas:", failures);
    const snapshot = buildSnapshot(raw);
    try {
      await refreshAttachmentUrls(client, attachmentListsOf(snapshot));
    } catch (error) {
      console.warn("[Central] Falha ao renovar os links dos anexos:", error);
    }
    return { snapshot, failures, record: { schema: CACHE_SCHEMA, fetchedAt, signedAt: Date.now(), fingerprint: await fingerprintOf(raw), snapshot } };
  }

  function startBackgroundRefresh(client, userId, previousFingerprint) {
    if (backgroundRefresh) return backgroundRefresh;
    backgroundRefresh = (async () => {
      try {
        const { failures, record } = await fetchSnapshot(client);
        if (failures.length) return;
        await saveSnapshot(userId, record);
        // O Store da tela aberta não é trocado em segundo plano: as telas
        // guardam referências (ex.: índices de lista) ao retrato atual.
        if (record.fingerprint !== previousFingerprint) window.dispatchEvent(new CustomEvent("api:snapshot-updated"));
      } catch (error) {
        console.warn("[Central] Atualização em segundo plano falhou:", error);
      } finally {
        backgroundRefresh = null;
      }
    })();
    return backgroundRefresh;
  }

  async function hydrateSupabaseSnapshot() {
    try {
      const client = await operationalClient();
      const { data: sessionData } = await client.auth.getSession();
      const userId = sessionData.session?.user?.id || null;
      const now = Date.now();
      const cached = userId ? await readSnapshotCache(userId) : null;
      const usable = cached && cached.schema === CACHE_SCHEMA && cached.fetchedAt > lastInvalidation() && now - cached.fetchedAt < SNAPSHOT_MAX_AGE_MS;

      if (usable) {
        if (now - cached.signedAt > RESIGN_AFTER_MS) {
          try {
            await refreshAttachmentUrls(client, attachmentListsOf(cached.snapshot));
            cached.signedAt = Date.now();
            await saveSnapshot(userId, cached);
          } catch (error) {
            console.warn("[Central] Falha ao renovar os links dos anexos do cache:", error);
          }
        }
        Store.setRemoteSnapshot(cached.snapshot);
        const ageMs = now - cached.fetchedAt;
        if (ageMs > SNAPSHOT_FRESH_MS) startBackgroundRefresh(client, userId, cached.fingerprint);
        return { count: cached.snapshot.clients.length, source: "cache", ageMs };
      }

      const { snapshot, failures, record } = await fetchSnapshot(client);
      Store.setRemoteSnapshot(snapshot);
      if (!failures.length) await saveSnapshot(userId, record);
      return {
        count: snapshot.clients.length,
        source: "network",
        ...(failures.length ? { warning: `Falha ao carregar: ${failures.map((failure) => failure.view).join(", ")}. Consulte o Console para o detalhe retornado pelo Supabase.` } : {})
      };
    } catch (error) {
      console.error("[Central] Falha no retrato remoto:", error);
      return { error: error.message || "Não foi possível carregar o Supabase." };
    }
  }

  const createClientRecord = async (payload) => mapRemoteClient(await operationalRpc("cadastrar_cliente", { p_dados: payload }));
  const updateClientRecord = async (id, payload) => await operationalRpc("atualizar_comunicacao", { p_cliente_id: id, p_dados: payload });
  const archiveClientRecord = async (id) => operationalRpc("arquivar_cliente", { p_cliente_id: id });
  const createVisit = async (payload) => visitFromApi(await operationalRpc("criar_visita", { p_dados: payload }));
  const createNeed = async (payload) => operationalRpc("criar_necessidade", { p_dados: payload });
  const createTrip = async (payload) => tripFromApi(await operationalRpc("criar_viagem", { p_titulo: payload.name, p_inicio: payload.startDate, p_fim: payload.endDate, p_observacao: payload.objective, p_participantes: payload.participants || [], p_clientes: payload.clients || [] }));
  const updateTrip = async (id, payload) => await operationalRpc("atualizar_viagem", { p_viagem_id: id, p_dados: payload });
  const deleteTrip = async (id) => operationalRpc("excluir_viagem", { p_viagem_id: id });
  const createExpense = async (payload) => expenseFromApi(await operationalRpc("criar_despesa", { p_dados: payload }));
  const updateExpense = async (id, payload) => await operationalRpc("atualizar_despesa", { p_despesa_id: id, p_dados: payload });
  const deleteExpense = async (id) => operationalRpc("excluir_despesa", { p_despesa_id: id });
  const createEvent = async (payload) => eventFromApi(await operationalRpc("criar_evento", { p_nome: payload.name, p_local: payload.location || null, p_data_inicio: payload.startDate, p_data_fim: payload.endDate || payload.startDate, p_tipo_participacao: payload.role === "Expositor" ? "EXPOSITOR" : "PARTICIPANTE", p_notas: payload.notes || null }));
  const updateEvent = async (id, payload) => await operationalRpc("atualizar_evento", { p_evento_id: id, p_dados: payload });
  const deleteEvent = async (id) => operationalRpc("excluir_evento", { p_evento_id: id });

  async function uploadPrivateFile(path, file) {
    const client = await operationalClient();
    if (!file || file.size > 20 * 1024 * 1024) throw new Error("O anexo deve ter no máximo 20 MB.");
    const { data, error } = await client.storage.from(ATTACHMENT_BUCKET).upload(path, file, { cacheControl: "3600", upsert: false, contentType: file.type || undefined });
    if (error) throw new Error(error.message || "Falha ao enviar o anexo.");
    const { data: signed, error: signedError } = await client.storage.from(ATTACHMENT_BUCKET).createSignedUrl(data.path, SIGNED_URL_TTL_SECONDS);
    if (signedError) throw new Error(signedError.message || "Falha ao assinar o anexo.");
    // A URL serve para a exibição imediata; o que vale de forma permanente é o path.
    return { bucket: ATTACHMENT_BUCKET, path: data.path, url: signed.signedUrl };
  }

  return {
    CONNECTION_STORAGE_KEY, readConnection, isRestrictedSupabaseKey,
    loadSupabaseLibrary, getSupabaseClient,
    mapRemoteClient, mapRemoteTrip,
    hydrateSupabaseSnapshot, clearSnapshotCache: invalidateSnapshotCache,
    createClientRecord, updateClientRecord, archiveClientRecord, createVisit, createNeed, createTrip, updateTrip, deleteTrip, createExpense, updateExpense, deleteExpense, createEvent, updateEvent, deleteEvent,
    uploadPrivateFile
  };
})();
