window.Store = (() => {
  const clone = (value) => JSON.parse(JSON.stringify(value));
  let state = null;

  /* Estado vazio para sessões autenticadas — sem dados mock. */
  function emptyState() {
    return { users: [], clients: [], trips: [], events: [], visits: [], expenses: [], activities: [] };
  }

  function seed() {
    state = window.AuthUser ? emptyState() : clone(window.MockData);
    return state;
  }

  function getState() {
    if (!state || !Array.isArray(state.clients) || !Array.isArray(state.trips)) return seed();
    return state;
  }

  function setState(nextState) {
    state = nextState;
    window.dispatchEvent(new CustomEvent("store:changed", { detail: state }));
    return state;
  }

  function update(mutator) {
    const state = getState();
    mutator(state);
    return setState(state);
  }

  function reset() {
    return seed();
  }

  function setRemoteClients(clients, trips = [], users = null) {
    const state = getState();
    state.clients = Array.isArray(clients) ? clients : [];
    state.trips = Array.isArray(trips) ? trips : [];
    if (Array.isArray(users) && users.length) state.users = users;
    state.remoteSource = {
      active: true,
      syncedAt: new Date().toISOString()
    };
    return setState(state);
  }

  // O estado local e apenas um cache de renderizacao. Esta funcao sempre recebe
  // um retrato completo retornado pelo Supabase; nenhum dado de negocio e
  // inventado ou preservado aqui entre sincronizacoes.
  function setRemoteSnapshot(snapshot = {}) {
    const state = getState();
    ["users", "clients", "trips", "visits", "expenses", "events", "activities"].forEach((key) => {
      if (Array.isArray(snapshot[key])) state[key] = snapshot[key];
    });
    state.remoteSource = {
      active: true,
      syncedAt: new Date().toISOString()
    };
    return setState(state);
  }

  function upsert(collection, record) {
    if (!record?.id || !Array.isArray(getState()[collection])) return getState();
    return update((state) => {
      const rows = state[collection];
      const index = rows.findIndex((item) => item.id === record.id);
      if (index === -1) rows.unshift(record);
      else rows[index] = { ...rows[index], ...record };
    });
  }

  function remove(collection, id) {
    return update((state) => {
      if (!Array.isArray(state[collection])) return;
      state[collection] = state[collection].filter((item) => item.id !== id);
    });
  }

  function setRemoteUsers(users) {
    if (!Array.isArray(users) || !users.length) return getState();
    const state = getState();
    state.users = users;
    state.remoteSource = {
      ...(state.remoteSource || {}),
      active: true,
      syncedAt: new Date().toISOString()
    };
    return setState(state);
  }

  function setRemoteTrips(trips) {
    const state = getState();
    state.trips = Array.isArray(trips) ? trips : [];
    state.remoteSource = {
      ...(state.remoteSource || {}),
      active: true,
      syncedAt: new Date().toISOString()
    };
    return setState(state);
  }

  function uid(prefix) {
    if (window.crypto?.randomUUID) return `${prefix}_${crypto.randomUUID().slice(0, 8)}`;
    return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  }

  function addActivity(state, data) {
    state.activities.unshift({
      id: uid("a"),
      date: new Date().toISOString(),
      ...data
    });
  }

  function addClient(client, userId = "u1") {
    return update((state) => {
      state.clients.unshift({
        id: uid("c"),
        createdAt: new Date().toISOString(),
        status: "Lead",
        ownerId: userId,
        attachments: [],
        needs: [],
        ...client
      });
      addActivity(state, {
        type: "client",
        userId,
        text: `cadastrou ${client.name}`,
        targetId: state.clients[0].id
      });
    });
  }

  function addVisit(visit) {
    return update((state) => {
      const record = {
        id: uid("v"),
        date: new Date().toISOString(),
        attachments: [],
        needs: [],
        ...visit
      };
      state.visits.unshift(record);
      const client = state.clients.find((c) => c.id === record.clientId);
      if (client && record.needs?.length) {
        client.needs = [...new Set([...(client.needs || []), ...record.needs])];
      }
      addActivity(state, {
        type: "visit",
        userId: record.userId,
        text: `registrou uma visita em ${client?.name || "cliente"}`,
        targetId: record.clientId
      });
    });
  }

  function addTrip(trip) {
    return update((state) => {
      const record = {
        id: uid("t"),
        status: "Planejada",
        participantIds: [],
        plannedClientIds: [],
        stops: [],
        createdAt: new Date().toISOString(),
        ...trip
      };
      state.trips.unshift(record);
      addActivity(state, {
        type: "trip",
        userId: record.ownerId || "u1",
        text: `planejou a viagem ${record.name}`,
        targetId: record.id
      });
    });
  }

  function addEvent(event) {
    return update((state) => {
      const record = {
        id: uid("ev"),
        status: "Planejado",
        participantIds: [],
        createdAt: new Date().toISOString(),
        ...event
      };
      if (!state.events) state.events = [];
      state.events.unshift(record);
      addActivity(state, {
        type: "event",
        userId: "u1",
        text: `registrou o evento ${record.name}`,
        targetId: record.id
      });
    });
  }

  function updateEvent(eventId, patch) {
    return update((state) => {
      if (!state.events) state.events = [];
      const ev = state.events.find((e) => e.id === eventId);
      if (ev) {
        Object.assign(ev, patch);
      }
    });
  }

  function updateTrip(tripId, patch) {
    return update((state) => {
      const trip = state.trips.find((t) => t.id === tripId);
      if (trip) Object.assign(trip, patch);
    });
  }

  function addStop(tripId, stop) {
    return update((state) => {
      const trip = state.trips.find((t) => t.id === tripId);
      if (!trip) return;
      trip.stops.push({ id: uid("s"), done: false, ...stop });
      addActivity(state, {
        type: "route",
        userId: trip.ownerId || "u1",
        text: `adicionou uma parada em ${trip.name}`,
        targetId: tripId
      });
    });
  }

  function toggleStop(tripId, stopId) {
    return update((state) => {
      const trip = state.trips.find((t) => t.id === tripId);
      const stop = trip?.stops.find((s) => s.id === stopId);
      if (stop) stop.done = !stop.done;
    });
  }

  function addExpense(expense) {
    return update((state) => {
      const record = {
        id: uid("e"),
        date: new Date().toISOString(),
        ...expense
      };
      state.expenses.unshift(record);
      const trip = state.trips.find((t) => t.id === record.tripId);
      const event = state.events?.find((e) => e.id === record.eventId);
      const refName = event ? event.name : (trip ? trip.name : "registro");
      const targetId = event ? record.eventId : record.tripId;
      addActivity(state, {
        type: "expense",
        userId: record.userId,
        text: `registrou uma despesa em ${refName}`,
        targetId: targetId
      });
    });
  }

  function deleteExpense(id) {
    return update((state) => {
      const index = state.expenses.findIndex(e => e.id === id);
      if (index !== -1) {
        state.expenses.splice(index, 1);
      }
    });
  }

  function addClientNeed(clientId, need, userId = "u1") {
    return update((state) => {
      const client = state.clients.find((c) => c.id === clientId);
      if (!client) return;
      client.needs = client.needs || [];
      client.needRecords = client.needRecords || [];
      const record = {
        id: uid("n"),
        date: new Date().toISOString(),
        userId,
        category: need.category || "Outro",
        description: need.description || "",
        priority: need.priority || "Normal"
      };
      client.needRecords.unshift(record);
      if (record.category && !client.needs.includes(record.category)) {
        client.needs.push(record.category);
      }
      addActivity(state, {
        type: "need",
        userId,
        text: `registrou uma necessidade em ${client.name}`,
        targetId: clientId
      });
    });
  }

  function updateClient(clientId, patch) {
    return update((state) => {
      const client = state.clients.find((c) => c.id === clientId);
      if (client) Object.assign(client, patch);
    });
  }

  function addOdometerRecord(tripId, kmValue) {
    return update((state) => {
      const trip = state.trips.find((t) => t.id === tripId);
      if (!trip) return;
      if (!Array.isArray(trip.odometerRecords)) {
        trip.odometerRecords = [];
      }
      trip.odometerRecords.unshift({
        id: uid("km"),
        date: new Date().toISOString(),
        km: Number(kmValue)
      });
      // Legacy reset
      trip.startKm = null;
      trip.currentKm = null;
      trip.endKm = null;
    });
  }

  function updateExpense(id, patch) {
    return update((state) => {
      const exp = state.expenses.find(e => e.id === id);
      if (exp) {
        Object.assign(exp, patch);
      }
    });
  }

  function deleteTrip(tripId) {
    return update((state) => {
      state.trips = state.trips.filter((t) => t.id !== tripId);
      state.visits = state.visits.filter((v) => v.tripId !== tripId);
      state.expenses = state.expenses.filter((e) => e.tripId !== tripId);
    });
  }

  return {
    getState,
    setState,
    reset,
    setRemoteClients,
    setRemoteSnapshot,
    setRemoteUsers,
    setRemoteTrips,
    upsert,
    remove,
    uid,
    addClient,
    addVisit,
    addTrip,
    updateTrip,
    deleteTrip,
    addOdometerRecord,
    addStop,
    toggleStop,
    addExpense,
    updateExpense,
    deleteExpense,
    addClientNeed,
    updateClient,
    addEvent,
    updateEvent
  };
})();
