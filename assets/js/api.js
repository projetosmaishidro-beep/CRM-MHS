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
    return rpcValue(data);
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
  const eventFromApi = (row) => ({ id: row.evento_id, name: row.nome || "Evento", location: row.local || "", startDate: row.data_inicio ? String(row.data_inicio).slice(0, 10) : "", endDate: row.data_fim ? String(row.data_fim).slice(0, 10) : "", status: ({ PLANEJADO: "Planejado", EM_ANDAMENTO: "Em andamento", REALIZADO: "Realizado", CANCELADO: "Cancelado" })[row.status] || row.status || "Planejado", role: row.tipo_participacao === "EXPOSITOR" ? "Expositor" : "Participante", notes: row.notas_estrategicas || "", participantIds: asArray(row.participantes), attachments: asArray(row.anexos), links: asArray(row.links), contacts: asArray(row.contatos), createdAt: row.criado_em, userId: row.criado_por || "", remote: true });

  async function hydrateSupabaseSnapshot() {
    try {
      const client = await operationalClient();
      const api = client.schema("api");
      const [clients, trips, visits, needs, expenses, events, users] = await Promise.all([
        api.from("vw_carteira_crm").select("*").order("empresa"),
        api.from("vw_viagens").select("*").order("inicio_em"),
        api.from("vw_visitas_crm").select("*").order("realizada_em", { ascending: false }),
        api.from("vw_necessidades").select("*").order("criado_em", { ascending: false }),
        api.from("vw_despesas_crm").select("*").order("data_despesa", { ascending: false }),
        api.from("vw_eventos").select("*").order("data_inicio", { ascending: false }),
        api.from("vw_equipe").select("*").order("nome")
      ]);
      // Cada tela deve continuar recebendo os dados da sua própria view. Uma
      // falha pontual, por exemplo em despesas, não pode impedir o detalhe de
      // um evento já disponível em vw_eventos de ser exibido.
      const viewNames = ["vw_carteira_crm", "vw_viagens", "vw_visitas_crm", "vw_necessidades", "vw_despesas_crm", "vw_eventos", "vw_equipe"];
      const results = [clients, trips, visits, needs, expenses, events, users];
      const failures = results
        .map((result, index) => ({ view: viewNames[index], error: result.error }))
        .filter((result) => result.error);
      if (failures.length) console.error("[Central] Views que não puderam ser carregadas:", failures);
      const remoteClients = (clients.data || []).map(mapRemoteClient);
      (needs.data || []).forEach((row) => {
        const clientRow = remoteClients.find((item) => item.id === row.empresa_id);
        if (!clientRow) return;
        const need = { id: row.necessidade_id, clientId: row.empresa_id, visitId: row.visita_id, category: row.categoria, description: row.descricao, priority: row.prioridade, status: row.status, date: row.criado_em };
        clientRow.needRecords.push(need);
        if (!clientRow.needs.includes(need.category)) clientRow.needs.push(need.category);
      });
      const remoteUsers = (users.data || []).map((row) => {
        const name = row.nome || row.email || "Membro da equipe";
        return { id: row.usuario_id || row.membro_id, name, role: row.cargo || row.papel || "Equipe Comercial", initials: initials(name), email: row.email || "", active: row.ativo !== false, remote: true };
      });
      Store.setRemoteSnapshot({ clients: remoteClients, trips: (trips.data || []).map(tripFromApi), visits: (visits.data || []).map(visitFromApi), expenses: (expenses.data || []).map(expenseFromApi), events: (events.data || []).map(eventFromApi), users: remoteUsers, activities: [] });
      return {
        count: remoteClients.length,
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
    const { data, error } = await client.storage.from("crm-anexos").upload(path, file, { cacheControl: "3600", upsert: false, contentType: file.type || undefined });
    if (error) throw new Error(error.message || "Falha ao enviar o anexo.");
    const { data: signed, error: signedError } = await client.storage.from("crm-anexos").createSignedUrl(data.path, 3600);
    if (signedError) throw new Error(signedError.message || "Falha ao assinar o anexo.");
    return { bucket: "crm-anexos", path: data.path, url: signed.signedUrl };
  }

  return {
    CONNECTION_STORAGE_KEY, readConnection, isRestrictedSupabaseKey,
    loadSupabaseLibrary, getSupabaseClient,
    mapRemoteClient, mapRemoteTrip,
    hydrateSupabaseSnapshot,
    createClientRecord, updateClientRecord, archiveClientRecord, createVisit, createNeed, createTrip, updateTrip, deleteTrip, createExpense, updateExpense, deleteExpense, createEvent, updateEvent, deleteEvent,
    uploadPrivateFile
  };
})();
