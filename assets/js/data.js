window.MockData = (() => {
  const iso = (daysAgo, hour = 10) => {
    const d = new Date();
    d.setDate(d.getDate() - daysAgo);
    d.setHours(hour, 0, 0, 0);
    return d.toISOString();
  };

  return {
    users: [
      { id: "u1", name: "Jefferson Ramires", role: "Equipe Comercial", initials: "JR", phone: "", email: "comercial3@maisintegradora.com.br", active: true },
      { id: "u2", name: "Bárbara Vieira", role: "Equipe Comercial", initials: "BV", phone: "", email: "comercial2@maisintegradora.com.br", active: true },
      { id: "u3", name: "Ricardo Castro Alves", role: "Equipe Comercial", initials: "RC", phone: "", email: "comercial1@maisintegradora.com.br", active: true }
    ],
    clients: [
      {
        id: "c1",
        name: "Fazenda Boa Esperança",
        company: "Boa Esperança Agropecuária",
        contact: "Carlos Menezes",
        phone: "(88) 99811-2020",
        email: "contato@boaesperanca.demo",
        city: "Quixeramobim",
        state: "CE",
        segment: "Agropecuária",
        category: "Irrigação",
        status: "Cliente",
        lat: -5.201,
        lng: -39.294,
        notes: "Cliente com interesse em expansão e modernização da operação.",
        needs: ["Melhoria logística", "Automação de controle"],
        createdAt: iso(210),
        ownerId: "u1",
        attachments: []
      },
      {
        id: "c2",
        name: "Sítio Lagoa Verde",
        company: "Lagoa Verde Produção Rural",
        contact: "Ana Beatriz Lima",
        phone: "(85) 99818-7720",
        email: "ana@lagoaverde.demo",
        city: "Canindé",
        state: "CE",
        segment: "Produção rural",
        category: "Irrigação",
        status: "Cliente",
        lat: -4.358,
        lng: -39.312,
        notes: "Relacionamento recorrente. Prioridade para atendimento em campo.",
        needs: ["Acompanhamento técnico"],
        createdAt: iso(170),
        ownerId: "u3",
        attachments: []
      },
      {
        id: "c3",
        name: "Cooperativa Vale Norte",
        company: "Cooperativa Vale Norte",
        contact: "Paulo Sérgio",
        phone: "(88) 99777-3020",
        email: "paulo@valenorte.demo",
        city: "Limoeiro do Norte",
        state: "CE",
        segment: "Cooperativa",
        category: "Outro",
        status: "Lead",
        lat: -5.145,
        lng: -38.098,
        notes: "Lead captado em visita de prospecção.",
        needs: ["Proposta institucional", "Diagnóstico inicial"],
        createdAt: iso(36),
        ownerId: "u2",
        attachments: []
      },
      {
        id: "c4",
        name: "Grupo Serra Azul",
        company: "Serra Azul Negócios Rurais",
        contact: "Marta Diniz",
        phone: "(85) 99654-6100",
        email: "marta@serraazul.demo",
        city: "Baturité",
        state: "CE",
        segment: "Agronegócio",
        category: "Outro",
        status: "Prospect",
        lat: -4.328,
        lng: -38.883,
        notes: "Primeiro contato realizado por indicação.",
        needs: ["Apresentação comercial"],
        createdAt: iso(12),
        ownerId: "u3",
        attachments: []
      }
    ],
    trips: [
      {
        id: "t1",
        name: "Rota Sertão Central",
        status: "Em andamento",
        startDate: new Date(Date.now() - 86400000).toISOString().slice(0, 10),
        endDate: new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10),
        participantIds: ["u1", "u2"],
        plannedClientIds: ["c1", "c2", "c3"],
        objective: "Acompanhamento de clientes e prospecção regional.",
        startKm: 48210,
        currentKm: 48642,
        endKm: null,
        stops: [
          { id: "s1", label: "Saída do escritório", place: "Fortaleza, CE", done: true },
          { id: "s2", label: "Visita Fazenda Boa Esperança", place: "Quixeramobim, CE", done: true },
          { id: "s3", label: "Visita Sítio Lagoa Verde", place: "Canindé, CE", done: false }
        ],
        notes: "Manter flexibilidade de rota conforme condições de estrada.",
        createdAt: iso(5),
        ownerId: "u1"
      },
      {
        id: "t2",
        name: "Circuito Vale do Jaguaribe",
        status: "Planejada",
        startDate: new Date(Date.now() + 6 * 86400000).toISOString().slice(0, 10),
        endDate: new Date(Date.now() + 8 * 86400000).toISOString().slice(0, 10),
        participantIds: ["u2", "u3"],
        plannedClientIds: ["c3"],
        objective: "Diagnóstico de oportunidades e relacionamento com leads.",
        startKm: null,
        currentKm: null,
        endKm: null,
        stops: [
          { id: "s4", label: "Reunião Cooperativa Vale Norte", place: "Limoeiro do Norte, CE", done: false }
        ],
        notes: "",
        createdAt: iso(2),
        ownerId: "u2"
      }
    ],
    visits: [
      {
        id: "v1",
        clientId: "c1",
        tripId: "t1",
        userId: "u1",
        date: iso(0, 9),
        type: "Acompanhamento",
        notes: "Revisamos prioridades e próximos passos do atendimento.",
        needs: ["Melhoria logística"],
        lat: -5.201,
        lng: -39.294,
        attachments: []
      },
      {
        id: "v2",
        clientId: "c3",
        tripId: "t1",
        userId: "u2",
        date: iso(0, 14),
        type: "Prospecção",
        notes: "Primeiro levantamento de cenário e identificação dos decisores.",
        needs: ["Diagnóstico inicial", "Proposta institucional"],
        lat: -5.145,
        lng: -38.098,
        attachments: []
      },
      {
        id: "v3",
        clientId: "c2",
        tripId: null,
        userId: "u3",
        date: iso(7, 11),
        type: "Acompanhamento",
        notes: "Visita técnica de rotina.",
        needs: ["Acompanhamento técnico"],
        lat: -4.358,
        lng: -39.312,
        attachments: []
      },
      {
        id: "v4",
        clientId: "c1",
        tripId: null,
        userId: "u1",
        date: iso(21, 10),
        type: "Relacionamento",
        notes: "Alinhamento sobre cronograma interno do cliente.",
        needs: [],
        lat: -5.201,
        lng: -39.294,
        attachments: []
      }
    ],
    events: [
      {
        id: "ev1",
        name: "Agrishow 2026",
        startDate: iso(-2, 8),
        endDate: iso(3, 18),
        location: "Ribeirão Preto, SP",
        status: "Planejado",
        notes: "Maior feira agrícola do Brasil. Foco em captação de grandes contas.",
        participantIds: ["u1", "u2"],
        createdAt: iso(-10, 9),
        attachments: []
      }
    ],
    expenses: [
      { id: "e1", tripId: "t1", userId: "u1", date: iso(0, 8), category: "Combustível", amount: 318.42, place: "Posto Rodoviário", costCenter: "Verba de Manutenção (Frota)", notes: "Abastecimento inicial", attachment: null },
      { id: "e2", tripId: "t1", userId: "u2", date: iso(0, 12), category: "Alimentação", amount: 96.8, place: "Restaurante regional", costCenter: "Prospecção (Novos Clientes)", notes: "Almoço da equipe", attachment: null },
      { id: "e3", tripId: "t1", userId: "u1", date: iso(1, 19), category: "Hospedagem", amount: 420, place: "Hotel Central", costCenter: "Captação / Retenção", notes: "Duas diárias", attachment: null },
      { id: "e4", tripId: "t2", userId: "u2", date: iso(0, 9), category: "Outros", amount: 65, place: "Papelaria", costCenter: "Previsto em Margem Operacional", notes: "Material de apoio", attachment: null }
    ],
    activities: [
      { id: "a1", type: "visit", date: iso(0, 14), userId: "u2", text: "registrou uma visita na Cooperativa Vale Norte", targetId: "c3" },
      { id: "a2", type: "expense", date: iso(0, 12), userId: "u2", text: "registrou uma despesa na Rota Sertão Central", targetId: "t1" },
      { id: "a3", type: "visit", date: iso(0, 9), userId: "u1", text: "registrou uma visita na Fazenda Boa Esperança", targetId: "c1" },
      { id: "a4", type: "trip", date: iso(2, 15), userId: "u2", text: "planejou a viagem Circuito Vale do Jaguaribe", targetId: "t2" }
    ]
  };
})();
