-- ============================================================================
-- PROPOSTAS MHS - ESTRUTURA PERSISTENTE
--
-- Pre-requisito: 20260920_0002_api_operacional_supabase.sql.
-- Este arquivo pertence ao modelo cadastro/mapa/crm/api e NAO deve ser usado
-- junto ao modelo alternativo core da migracao 20260919_0001.
-- A migracao e exclusivamente aditiva: nao altera nem remove dados existentes.
-- ============================================================================

begin;

-- Falha cedo se a base ativa nao for a fundacao operacional do CRM.
do $$
begin
  if to_regclass('cadastro.empresas') is null
     or to_regclass('crm.relacionamentos') is null
     or to_regclass('cadastro.equipe') is null then
    raise exception using message =
      'A estrutura propostas_mhs exige o contrato cadastro/mapa/crm/api da migracao 20260920_0002.';
  end if;
end $$;

create schema if not exists propostas_mhs;
comment on schema propostas_mhs is
'Modulo de propostas da Mais Hidro. Mantem precificacao, revisoes, templates, arquivos e auditoria sem duplicar o cadastro mestre do CRM.';

-- ---------------------------------------------------------------------------
-- 1. CLIENTE E LOCAL DA OBRA
-- ---------------------------------------------------------------------------
-- cadastro.empresas continua sendo a fonte oficial de CNPJ, razao social,
-- comunicacao e endereco cadastral. Esta tabela guarda somente extensoes
-- necessarias ao ciclo de propostas.
create table if not exists propostas_mhs.clientes (
  empresa_id uuid primary key references cadastro.empresas(empresa_id) on delete restrict,
  relacionamento_id uuid references crm.relacionamentos(relacionamento_id) on delete set null,
  contato_preferencial_nome text,
  contato_preferencial_cargo text,
  contato_preferencial_canal text,
  observacao_comercial text,
  dados_adicionais jsonb not null default '{}'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint clientes_canal_check check (
    contato_preferencial_canal is null
    or contato_preferencial_canal in ('TELEFONE', 'WHATSAPP', 'EMAIL', 'OUTRO')
  )
);
comment on table propostas_mhs.clientes is
'Extensao comercial de uma empresa do CRM. Nao duplica dados cadastrais oficiais.';

create table if not exists propostas_mhs.locais_obra (
  local_obra_id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references cadastro.empresas(empresa_id) on delete restrict,
  nome text not null,
  codigo_referencia text,
  logradouro text,
  numero text,
  complemento text,
  bairro text,
  municipio text,
  uf text,
  cep text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  observacao text,
  ativo boolean not null default true,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint locais_obra_nome_empresa_uidx unique (empresa_id, nome),
  constraint locais_obra_uf_check check (uf is null or uf ~ '^[A-Z]{2}$'),
  constraint locais_obra_cep_check check (cep is null or cep ~ '^\d{8}$'),
  constraint locais_obra_latitude_check check (latitude is null or latitude between -34.2 and 5.4),
  constraint locais_obra_longitude_check check (longitude is null or longitude between -74.1 and -32.2)
);
comment on table propostas_mhs.locais_obra is
'Locais de entrega ou execucao. Permite varias obras para o mesmo cliente.';

-- ---------------------------------------------------------------------------
-- 2. CATALOGO, COMPOSICOES E HISTORICO DE CPMV/PRECOS
-- ---------------------------------------------------------------------------
create table if not exists propostas_mhs.catalogo_itens (
  item_catalogo_id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  modalidade text not null,
  nome text not null,
  descricao_comercial text,
  descricao_tecnica text,
  ncm text,
  unidade_padrao text not null,
  ipi_padrao_percentual numeric(9,4) not null default 0,
  ativo boolean not null default true,
  dados_tecnicos jsonb not null default '{}'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint catalogo_modalidade_check check (modalidade in ('PRODUTO', 'SERVICO', 'COMPOSTO')),
  constraint catalogo_ipi_check check (ipi_padrao_percentual between 0 and 100)
);
comment on table propostas_mhs.catalogo_itens is
'Catalogo unico de produtos, servicos e itens compostos reutilizaveis.';

create table if not exists propostas_mhs.catalogo_composicoes (
  composicao_id uuid primary key default gen_random_uuid(),
  item_catalogo_id uuid not null unique references propostas_mhs.catalogo_itens(item_catalogo_id) on delete restrict,
  nome text not null,
  descricao text,
  ativa boolean not null default true,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table propostas_mhs.catalogo_composicoes is
'Cabecalho de um item composto. Seus componentes pertencem a versoes numeradas.';

create table if not exists propostas_mhs.catalogo_composicoes_versoes (
  composicao_versao_id uuid primary key default gen_random_uuid(),
  composicao_id uuid not null references propostas_mhs.catalogo_composicoes(composicao_id) on delete restrict,
  numero_versao integer not null,
  situacao text not null default 'RASCUNHO',
  descricao_alteracao text,
  cpmv_total numeric(19,4) not null default 0,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint composicao_versao_uidx unique (composicao_id, numero_versao),
  constraint composicao_versao_situacao_check check (situacao in ('RASCUNHO', 'VIGENTE', 'ARQUIVADA')),
  constraint composicao_versao_cpmv_check check (cpmv_total >= 0)
);
comment on table propostas_mhs.catalogo_composicoes_versoes is
'Historico imutavel das composicoes. Uma nova alteracao cria outra versao.';

create table if not exists propostas_mhs.catalogo_composicao_componentes (
  componente_id uuid primary key default gen_random_uuid(),
  composicao_versao_id uuid not null references propostas_mhs.catalogo_composicoes_versoes(composicao_versao_id) on delete cascade,
  item_catalogo_id uuid references propostas_mhs.catalogo_itens(item_catalogo_id) on delete restrict,
  ordem integer not null default 1,
  codigo_referencia text,
  descricao text not null,
  unidade text not null,
  quantidade numeric(19,6) not null default 1,
  cpmv_unitario numeric(19,4) not null default 0,
  cpmv_total numeric(19,4) not null default 0,
  observacao text,
  constraint componente_ordem_uidx unique (composicao_versao_id, ordem),
  constraint componente_quantidade_check check (quantidade > 0),
  constraint componente_custos_check check (cpmv_unitario >= 0 and cpmv_total >= 0)
);
comment on table propostas_mhs.catalogo_composicao_componentes is
'Componentes e custos fotografados em cada versao de composicao.';

create table if not exists propostas_mhs.historico_cpmv_produtos (
  historico_cpmv_id uuid primary key default gen_random_uuid(),
  item_catalogo_id uuid not null references propostas_mhs.catalogo_itens(item_catalogo_id) on delete restrict,
  cpmv_unitario numeric(19,4) not null,
  moeda char(3) not null default 'BRL',
  vigente_desde date not null default current_date,
  vigente_ate date,
  fonte text,
  documento_referencia text,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_por uuid references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  constraint historico_cpmv_valor_check check (cpmv_unitario >= 0),
  constraint historico_cpmv_periodo_check check (vigente_ate is null or vigente_ate >= vigente_desde),
  constraint historico_cpmv_moeda_check check (moeda ~ '^[A-Z]{3}$')
);
comment on table propostas_mhs.historico_cpmv_produtos is
'Historico temporal do CPMV unitario de produtos, servicos e componentes de composicao.';

create table if not exists propostas_mhs.historico_precos_venda (
  historico_preco_id uuid primary key default gen_random_uuid(),
  item_catalogo_id uuid not null references propostas_mhs.catalogo_itens(item_catalogo_id) on delete restrict,
  preco_venda_unitario numeric(19,4) not null,
  moeda char(3) not null default 'BRL',
  vigente_desde date not null default current_date,
  vigente_ate date,
  fonte text,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_por uuid references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  constraint historico_preco_valor_check check (preco_venda_unitario >= 0),
  constraint historico_preco_periodo_check check (vigente_ate is null or vigente_ate >= vigente_desde),
  constraint historico_preco_moeda_check check (moeda ~ '^[A-Z]{3}$')
);
comment on table propostas_mhs.historico_precos_venda is
'Historico temporal de preco de venda sugerido, independente do CPMV.';

-- ---------------------------------------------------------------------------
-- 3. BLOCOS INTELIGENTES E TEMPLATES VERSIONADOS
-- ---------------------------------------------------------------------------
create table if not exists propostas_mhs.blocos_inteligentes (
  bloco_id uuid primary key default gen_random_uuid(),
  tipo text not null,
  titulo text not null,
  tema text,
  item_catalogo_id uuid references propostas_mhs.catalogo_itens(item_catalogo_id) on delete set null,
  ativo boolean not null default true,
  versao_atual integer not null default 0,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint blocos_tipo_check check (tipo in ('TEXTO_TECNICO', 'ESCOPO', 'CONDICAO', 'OBSERVACAO', 'PAGAMENTO', 'OUTRO'))
);

create table if not exists propostas_mhs.blocos_inteligentes_versoes (
  bloco_versao_id uuid primary key default gen_random_uuid(),
  bloco_id uuid not null references propostas_mhs.blocos_inteligentes(bloco_id) on delete restrict,
  numero_versao integer not null,
  titulo text not null,
  conteudo text not null,
  conteudo_rico jsonb not null default '{}'::jsonb,
  descricao_alteracao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint bloco_versao_uidx unique (bloco_id, numero_versao)
);
comment on table propostas_mhs.blocos_inteligentes_versoes is
'Conteudo versionado para recuperacao rapida de textos tecnicos, escopos e condicoes.';

create table if not exists propostas_mhs.templates (
  template_id uuid primary key default gen_random_uuid(),
  nome text not null,
  tema text,
  produto_referencia text,
  descricao text,
  situacao text not null default 'ATIVO',
  versao_atual integer not null default 0,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint templates_nome_uidx unique (nome),
  constraint templates_situacao_check check (situacao in ('RASCUNHO', 'ATIVO', 'ARQUIVADO'))
);
comment on table propostas_mhs.templates is
'Modelos reutilizaveis sem dados comerciais ou identificadores de clientes.';

create table if not exists propostas_mhs.templates_versoes (
  template_versao_id uuid primary key default gen_random_uuid(),
  template_id uuid not null references propostas_mhs.templates(template_id) on delete restrict,
  numero_versao integer not null,
  resumo_alteracao text,
  dados_modelo jsonb not null,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint template_versao_uidx unique (template_id, numero_versao),
  constraint template_dados_modelo_check check (jsonb_typeof(dados_modelo) = 'object')
);
comment on table propostas_mhs.templates_versoes is
'Fotografia integral e imutavel de cada versao de template.';

-- ---------------------------------------------------------------------------
-- 4. PROPOSTA, FORNECIMENTO, CONDICOES E MEMORIA DE CALCULO
-- ---------------------------------------------------------------------------
create table if not exists propostas_mhs.numeracao_anual (
  ano integer primary key,
  ultimo_numero integer not null default 0,
  atualizado_em timestamptz not null default now(),
  constraint numeracao_anual_ano_check check (ano between 2000 and 2200),
  constraint numeracao_anual_numero_check check (ultimo_numero >= 0)
);
comment on table propostas_mhs.numeracao_anual is
'Controle transacional da numeracao sequencial de propostas por ano.';

create table if not exists propostas_mhs.propostas (
  proposta_id uuid primary key default gen_random_uuid(),
  ano integer not null,
  numero_sequencial integer not null,
  codigo text generated always as ('MHS-' || ano::text || '-' || lpad(numero_sequencial::text, 5, '0')) stored,
  empresa_id uuid not null references cadastro.empresas(empresa_id) on delete restrict,
  local_obra_id uuid references propostas_mhs.locais_obra(local_obra_id) on delete set null,
  visita_origem_id uuid references crm.visitas(visita_id) on delete set null,
  template_versao_origem_id uuid references propostas_mhs.templates_versoes(template_versao_id) on delete set null,
  obra text,
  assunto text not null,
  descricao text,
  complexidade text not null default 'MEDIA',
  status text not null default 'RASCUNHO',
  tipo_fornecimento text not null default 'MISTO',
  moeda char(3) not null default 'BRL',
  valor_cpmv_total numeric(19,4) not null default 0,
  valor_base_calculo numeric(19,4) not null default 0,
  percentual_total numeric(9,6) not null default 0,
  fator_venda numeric(14,6) not null default 1,
  valor_proposta numeric(19,4) not null default 0,
  versao_atual integer not null default 0,
  enviada_em timestamptz,
  finalizada_em timestamptz,
  validade_ate date,
  dados_cliente_snapshot jsonb not null default '{}'::jsonb,
  dados_adicionais jsonb not null default '{}'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_numero_uidx unique (ano, numero_sequencial),
  constraint propostas_ano_check check (ano between 2000 and 2200),
  constraint propostas_numero_check check (numero_sequencial > 0),
  constraint propostas_complexidade_check check (complexidade in ('BAIXA', 'MEDIA', 'ALTA', 'ESPECIAL')),
  constraint propostas_status_check check (status in ('RASCUNHO', 'EM_EDICAO', 'EM_REVISAO', 'ENVIADA', 'APROVADA', 'RECUSADA', 'CANCELADA', 'FINALIZADA')),
  constraint propostas_fornecimento_check check (tipo_fornecimento in ('PRODUTOS', 'SERVICOS', 'COMPOSTOS', 'MISTO')),
  constraint propostas_valores_check check (valor_cpmv_total >= 0 and valor_base_calculo >= 0 and valor_proposta >= 0 and percentual_total >= 0 and fator_venda > 0),
  constraint propostas_moeda_check check (moeda ~ '^[A-Z]{3}$')
);
comment on table propostas_mhs.propostas is
'Cabecalho operacional da proposta. Os valores historicos oficiais ficam em propostas_revisoes.';

create table if not exists propostas_mhs.propostas_itens (
  proposta_item_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  item_catalogo_id uuid references propostas_mhs.catalogo_itens(item_catalogo_id) on delete set null,
  composicao_versao_id uuid references propostas_mhs.catalogo_composicoes_versoes(composicao_versao_id) on delete set null,
  ordem integer not null default 1,
  modalidade text not null,
  codigo_referencia text,
  descricao_comercial text not null,
  especificacao_tecnica text,
  especificacao_rica jsonb not null default '{}'::jsonb,
  ncm text,
  unidade text not null,
  quantidade numeric(19,6) not null default 1,
  ipi_percentual numeric(9,4) not null default 0,
  cpmv_unitario numeric(19,4) not null default 0,
  cpmv_total numeric(19,4) not null default 0,
  preco_venda_unitario numeric(19,4) not null default 0,
  preco_venda_total numeric(19,4) not null default 0,
  ativo boolean not null default true,
  dados_adicionais jsonb not null default '{}'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint proposta_item_ordem_uidx unique (proposta_id, ordem),
  constraint proposta_item_modalidade_check check (modalidade in ('PRODUTO', 'SERVICO', 'COMPOSTO')),
  constraint proposta_item_quantidade_check check (quantidade > 0),
  constraint proposta_item_ipi_check check (ipi_percentual between 0 and 100),
  constraint proposta_item_valores_check check (cpmv_unitario >= 0 and cpmv_total >= 0 and preco_venda_unitario >= 0 and preco_venda_total >= 0)
);
comment on table propostas_mhs.propostas_itens is
'Fornecimentos comerciais da proposta. Cada valor e uma fotografia independente do catalogo.';

create table if not exists propostas_mhs.propostas_itens_composicao (
  proposta_item_composicao_id uuid primary key default gen_random_uuid(),
  proposta_item_id uuid not null references propostas_mhs.propostas_itens(proposta_item_id) on delete cascade,
  item_catalogo_id uuid references propostas_mhs.catalogo_itens(item_catalogo_id) on delete set null,
  ordem integer not null default 1,
  codigo_referencia text,
  descricao text not null,
  unidade text not null,
  quantidade numeric(19,6) not null default 1,
  cpmv_unitario numeric(19,4) not null default 0,
  cpmv_total numeric(19,4) not null default 0,
  observacao text,
  constraint proposta_item_composicao_ordem_uidx unique (proposta_item_id, ordem),
  constraint proposta_item_composicao_quantidade_check check (quantidade > 0),
  constraint proposta_item_composicao_valor_check check (cpmv_unitario >= 0 and cpmv_total >= 0)
);
comment on table propostas_mhs.propostas_itens_composicao is
'Detalhamento congelado dos subitens de um item composto na proposta.';

create table if not exists propostas_mhs.propostas_condicoes (
  proposta_id uuid primary key references propostas_mhs.propostas(proposta_id) on delete cascade,
  modalidade_frete text,
  local_frete text,
  prazo_entrega text,
  garantia text,
  validade_dias integer,
  observacoes text,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_condicoes_frete_check check (modalidade_frete is null or modalidade_frete in ('FOB', 'CIF', 'RETIRADA', 'A_COMBINAR')),
  constraint propostas_condicoes_validade_check check (validade_dias is null or validade_dias > 0)
);

create table if not exists propostas_mhs.propostas_pagamentos (
  pagamento_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  ordem integer not null default 1,
  descricao text not null,
  percentual numeric(9,4) not null,
  prazo text,
  observacao text,
  constraint propostas_pagamentos_ordem_uidx unique (proposta_id, ordem),
  constraint propostas_pagamentos_percentual_check check (percentual > 0 and percentual <= 100)
);

create table if not exists propostas_mhs.propostas_escopo (
  escopo_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  ordem integer not null default 1,
  inclusao boolean not null,
  descricao text not null,
  constraint propostas_escopo_ordem_uidx unique (proposta_id, inclusao, ordem)
);

create table if not exists propostas_mhs.propostas_referencias (
  referencia_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  titulo text not null,
  url text,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint propostas_referencias_url_check check (url is null or url ~* '^https?://')
);

create table if not exists propostas_mhs.memorias_calculo (
  memoria_calculo_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  numero_calculo integer not null,
  situacao text not null default 'ATUAL',
  base_calculo numeric(19,4) not null default 0,
  percentual_total numeric(9,6) not null default 0,
  fator_venda numeric(14,6) not null default 1,
  valor_resultado numeric(19,4) not null default 0,
  observacao text,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint memoria_calculo_numero_uidx unique (proposta_id, numero_calculo),
  constraint memoria_calculo_situacao_check check (situacao in ('ATUAL', 'HISTORICA', 'APLICADA_EM_REVISAO')),
  constraint memoria_calculo_valores_check check (base_calculo >= 0 and percentual_total >= 0 and fator_venda > 0 and valor_resultado >= 0)
);
comment on table propostas_mhs.memorias_calculo is
'Historico de calculos de preco. Alteracoes criam uma nova numeracao de memoria.';

create table if not exists propostas_mhs.memorias_calculo_linhas (
  memoria_linha_id uuid primary key default gen_random_uuid(),
  memoria_calculo_id uuid not null references propostas_mhs.memorias_calculo(memoria_calculo_id) on delete cascade,
  ordem integer not null default 1,
  componente text not null,
  aliquota_percentual numeric(9,6),
  valor_calculado numeric(19,4),
  valor_texto text,
  aplicacao text,
  constraint memoria_linha_ordem_uidx unique (memoria_calculo_id, ordem),
  constraint memoria_linha_aliquota_check check (aliquota_percentual is null or aliquota_percentual >= 0),
  constraint memoria_linha_valor_check check (valor_calculado is null or valor_calculado >= 0)
);
comment on table propostas_mhs.memorias_calculo_linhas is
'Impostos, margem, lucro, comissao, financeiro, prazo e fator que formam cada memoria de calculo.';

create table if not exists propostas_mhs.propostas_blocos (
  proposta_bloco_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  bloco_versao_id uuid references propostas_mhs.blocos_inteligentes_versoes(bloco_versao_id) on delete set null,
  tipo text not null,
  ordem integer not null default 1,
  titulo text not null,
  conteudo text not null,
  conteudo_rico jsonb not null default '{}'::jsonb,
  constraint proposta_bloco_ordem_uidx unique (proposta_id, tipo, ordem),
  constraint proposta_bloco_tipo_check check (tipo in ('TEXTO_TECNICO', 'ESCOPO', 'CONDICAO', 'OBSERVACAO', 'PAGAMENTO', 'OUTRO'))
);
comment on table propostas_mhs.propostas_blocos is
'Blocos aplicados na proposta como copia independente do bloco inteligente de origem.';

-- ---------------------------------------------------------------------------
-- 5. REVISOES, ARQUIVOS E AUDITORIA
-- ---------------------------------------------------------------------------
create table if not exists propostas_mhs.propostas_revisoes (
  revisao_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete restrict,
  numero_revisao integer not null,
  tipo text not null default 'REVISAO',
  motivo text,
  status_proposta text not null,
  valor_cpmv_total numeric(19,4) not null,
  valor_proposta numeric(19,4) not null,
  dados_snapshot jsonb not null,
  hash_integridade text not null,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint proposta_revisao_uidx unique (proposta_id, numero_revisao),
  constraint proposta_revisao_chave_uidx unique (revisao_id, proposta_id),
  constraint proposta_revisao_tipo_check check (tipo in ('PREVIA', 'EMISSAO', 'REVISAO', 'FINAL')),
  constraint proposta_revisao_status_check check (status_proposta in ('RASCUNHO', 'EM_EDICAO', 'EM_REVISAO', 'ENVIADA', 'APROVADA', 'RECUSADA', 'CANCELADA', 'FINALIZADA')),
  constraint proposta_revisao_valores_check check (valor_cpmv_total >= 0 and valor_proposta >= 0),
  constraint proposta_revisao_snapshot_check check (jsonb_typeof(dados_snapshot) = 'object')
);
comment on table propostas_mhs.propostas_revisoes is
'Fotografia imutavel de toda proposta em cada emissao ou revisao.';

create table if not exists propostas_mhs.arquivos_proposta (
  arquivo_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete restrict,
  revisao_id uuid,
  bucket_id text not null default 'propostas-mhs',
  caminho_storage text not null unique,
  categoria text not null,
  nome_original text not null,
  tipo_mime text not null,
  tamanho_bytes bigint not null,
  checksum_sha256 text,
  observacao text,
  estado text not null default 'ATIVO',
  enviado_por uuid references auth.users(id) on delete set null,
  enviado_em timestamptz not null default now(),
  constraint arquivo_proposta_revisao_fk foreign key (revisao_id, proposta_id)
    references propostas_mhs.propostas_revisoes(revisao_id, proposta_id) on delete restrict,
  constraint arquivo_proposta_categoria_check check (categoria in ('PDF_GERADO', 'ANEXO_CLIENTE', 'IMAGEM_ESCOPO', 'IMAGEM_PRODUTO', 'DOCUMENTO_TECNICO', 'PLANILHA', 'OUTRO')),
  constraint arquivo_proposta_estado_check check (estado in ('ATIVO', 'ARQUIVADO')),
  constraint arquivo_proposta_tamanho_check check (tamanho_bytes > 0),
  constraint arquivo_proposta_checksum_check check (checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$')
);
comment on table propostas_mhs.arquivos_proposta is
'Metadados de PDFs, anexos e imagens. O binario fica no bucket privado propostas-mhs.';

create table if not exists propostas_mhs.arquivos_template (
  arquivo_template_id uuid primary key default gen_random_uuid(),
  template_versao_id uuid not null references propostas_mhs.templates_versoes(template_versao_id) on delete restrict,
  bucket_id text not null default 'propostas-mhs',
  caminho_storage text not null unique,
  categoria text not null,
  nome_original text not null,
  tipo_mime text not null,
  tamanho_bytes bigint not null,
  checksum_sha256 text,
  enviado_por uuid references auth.users(id) on delete set null,
  enviado_em timestamptz not null default now(),
  constraint arquivo_template_categoria_check check (categoria in ('ANEXO_TEMPLATE', 'IMAGEM_TEMPLATE', 'DOCUMENTO_TECNICO', 'OUTRO')),
  constraint arquivo_template_tamanho_check check (tamanho_bytes > 0),
  constraint arquivo_template_checksum_check check (checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$')
);

create table if not exists propostas_mhs.historico_acoes (
  acao_id uuid primary key default gen_random_uuid(),
  entidade text not null,
  entidade_id uuid not null,
  operacao text not null,
  resumo text,
  dados_antes jsonb,
  dados_depois jsonb,
  metadados jsonb not null default '{}'::jsonb,
  usuario_id uuid references auth.users(id) on delete set null,
  ocorrido_em timestamptz not null default now(),
  constraint historico_acoes_operacao_check check (operacao in ('CRIADA', 'ATUALIZADA', 'ARQUIVADA', 'RESTAURADA', 'REVISADA', 'EMITIDA', 'ENVIADA', 'APROVADA', 'RECUSADA', 'FINALIZADA', 'EXCLUIDA_LOGICAMENTE'))
);
comment on table propostas_mhs.historico_acoes is
'Trilha de auditoria detalhada do modulo de propostas, com usuario, horario e antes/depois.';

-- Indices de leitura operacional, recuperacao e auditoria.
create index if not exists locais_obra_empresa_ativa_idx on propostas_mhs.locais_obra (empresa_id, ativo, nome);
create index if not exists catalogo_itens_modalidade_ativo_idx on propostas_mhs.catalogo_itens (modalidade, ativo, nome);
create index if not exists composicao_componentes_item_idx on propostas_mhs.catalogo_composicao_componentes (item_catalogo_id);
create index if not exists historico_cpmv_item_vigencia_idx on propostas_mhs.historico_cpmv_produtos (item_catalogo_id, vigente_desde desc, criado_em desc);
create unique index if not exists historico_cpmv_atual_uidx on propostas_mhs.historico_cpmv_produtos (item_catalogo_id) where vigente_ate is null;
create index if not exists historico_preco_item_vigencia_idx on propostas_mhs.historico_precos_venda (item_catalogo_id, vigente_desde desc, criado_em desc);
create unique index if not exists historico_preco_atual_uidx on propostas_mhs.historico_precos_venda (item_catalogo_id) where vigente_ate is null;
create index if not exists blocos_tipo_tema_ativo_idx on propostas_mhs.blocos_inteligentes (tipo, tema, ativo, titulo);
create index if not exists templates_tema_situacao_idx on propostas_mhs.templates (tema, produto_referencia, situacao, atualizado_em desc);
create index if not exists propostas_empresa_status_atualizada_idx on propostas_mhs.propostas (empresa_id, status, atualizado_em desc);
create index if not exists propostas_status_atualizada_idx on propostas_mhs.propostas (status, atualizado_em desc);
create index if not exists propostas_itens_proposta_ordem_idx on propostas_mhs.propostas_itens (proposta_id, ordem);
create index if not exists memorias_calculo_proposta_numero_idx on propostas_mhs.memorias_calculo (proposta_id, numero_calculo desc);
create index if not exists propostas_revisoes_proposta_numero_idx on propostas_mhs.propostas_revisoes (proposta_id, numero_revisao desc);
create index if not exists arquivos_proposta_proposta_revisao_idx on propostas_mhs.arquivos_proposta (proposta_id, revisao_id, enviado_em desc);
create index if not exists historico_acoes_entidade_idx on propostas_mhs.historico_acoes (entidade, entidade_id, ocorrido_em desc);
create index if not exists historico_acoes_usuario_idx on propostas_mhs.historico_acoes (usuario_id, ocorrido_em desc);

commit;
