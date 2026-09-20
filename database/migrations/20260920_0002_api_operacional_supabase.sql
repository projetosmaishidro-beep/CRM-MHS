-- ============================================================================
-- API OPERACIONAL DA CENTRAL COMERCIAL
--
-- Fonte unica de dados para CRM e Mapa. Esta migracao e ADITIVA e foi escrita
-- para a base atualmente usada pelo front-end: cadastro, mapa, crm e api.
-- Execute UMA VEZ no SQL Editor do Supabase, depois de:
--   database/banco_simples/01_cadastro/01_cadastro.sql
--   database/banco_simples/02_mapa/02_mapa.sql
--   database/banco_simples/03_crm/03_crm.sql
--
-- Nao execute junto com a fundacao "core" de 20260919_0001. Sao modelos de
-- dados diferentes. Esta aplicacao passa a ter esta migracao como contrato.
-- ============================================================================

begin;

create schema if not exists api;

-- ---------------------------------------------------------------------------
-- 1. Estrutura complementar, sem eliminar dados existentes
-- ---------------------------------------------------------------------------

alter table cadastro.equipe
  add column if not exists papel text not null default 'LEITOR';

alter table cadastro.equipe
  drop constraint if exists equipe_papel_check;
alter table cadastro.equipe
  add constraint equipe_papel_check
  check (papel in ('LEITOR', 'EDITOR', 'ADMIN'));

alter table crm.viagens
  add column if not exists participantes jsonb not null default '[]'::jsonb,
  add column if not exists empresas_planejadas jsonb not null default '[]'::jsonb,
  add column if not exists paradas jsonb not null default '[]'::jsonb,
  add column if not exists odometro_registros jsonb not null default '[]'::jsonb,
  add column if not exists anexos jsonb not null default '[]'::jsonb,
  add column if not exists criado_por uuid references auth.users(id) on delete set null;

alter table crm.visitas
  add column if not exists tipo text not null default 'ACOMPANHAMENTO',
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists anexos jsonb not null default '[]'::jsonb;

alter table crm.despesas
  alter column viagem_id drop not null;
alter table crm.despesas
  add column if not exists evento_id uuid,
  add column if not exists centro_custo text,
  add column if not exists estabelecimento text,
  add column if not exists anexos jsonb not null default '[]'::jsonb,
  add column if not exists criado_por uuid references auth.users(id) on delete set null,
  add column if not exists atualizado_em timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'despesas_evento_id_fkey'
      and conrelid = 'crm.despesas'::regclass
  ) then
    alter table crm.despesas
      add constraint despesas_evento_id_fkey
      foreign key (evento_id) references crm.eventos(evento_id) on delete cascade;
  end if;
exception when undefined_table then
  -- crm.eventos e criada logo abaixo em bancos que ainda nao a possuem.
  null;
end $$;

create table if not exists crm.eventos (
  evento_id uuid primary key default gen_random_uuid(),
  nome text not null,
  local text,
  data_inicio date not null,
  data_fim date not null,
  status text not null default 'PLANEJADO',
  tipo_participacao text not null default 'PARTICIPANTE',
  notas_estrategicas text,
  participantes jsonb not null default '[]'::jsonb,
  anexos jsonb not null default '[]'::jsonb,
  links jsonb not null default '[]'::jsonb,
  contatos jsonb not null default '[]'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint eventos_data_check check (data_fim >= data_inicio),
  constraint eventos_status_check check (status in ('PLANEJADO', 'EM_ANDAMENTO', 'REALIZADO', 'CANCELADO'))
);

alter table crm.eventos
  add column if not exists participantes jsonb not null default '[]'::jsonb,
  add column if not exists anexos jsonb not null default '[]'::jsonb,
  add column if not exists links jsonb not null default '[]'::jsonb,
  add column if not exists contatos jsonb not null default '[]'::jsonb,
  add column if not exists criado_por uuid references auth.users(id) on delete set null,
  add column if not exists criado_em timestamptz not null default now(),
  add column if not exists atualizado_em timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'despesas_evento_id_fkey'
      and conrelid = 'crm.despesas'::regclass
  ) then
    alter table crm.despesas
      add constraint despesas_evento_id_fkey
      foreign key (evento_id) references crm.eventos(evento_id) on delete cascade;
  end if;
end $$;

alter table crm.anexos
  add column if not exists evento_id uuid references crm.eventos(evento_id) on delete cascade;
alter table crm.anexos drop constraint if exists anexos_destino_check;
alter table crm.anexos add constraint anexos_destino_check check (
  empresa_id is not null or visita_id is not null or viagem_id is not null
  or despesa_id is not null or evento_id is not null
);

create table if not exists crm.auditoria_api (
  auditoria_id uuid primary key default gen_random_uuid(),
  entidade text not null,
  entidade_id uuid not null,
  acao text not null,
  detalhes jsonb not null default '{}'::jsonb,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now()
);

create index if not exists auditoria_api_entidade_idx
  on crm.auditoria_api (entidade, entidade_id, criado_em desc);
create index if not exists visitas_viagem_realizada_idx
  on crm.visitas (viagem_id, realizada_em desc);
create index if not exists despesas_referencia_idx
  on crm.despesas (viagem_id, evento_id, ocorrido_em desc);

-- ---------------------------------------------------------------------------
-- 2. Autorizacao centralizada. A interface nunca decide permissoes.
-- ---------------------------------------------------------------------------

create or replace function api.eh_membro()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, cadastro
as $$
  select auth.uid() is not null and exists (
    select 1 from cadastro.equipe e
    where e.usuario_id = auth.uid() and e.ativo
  );
$$;

create or replace function api.eh_editor()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, cadastro
as $$
  select auth.uid() is not null and exists (
    select 1 from cadastro.equipe e
    where e.usuario_id = auth.uid()
      and e.ativo
      and e.papel in ('EDITOR', 'ADMIN')
  );
$$;

create or replace function api.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, cadastro
as $$
  select auth.uid() is not null and exists (
    select 1 from cadastro.equipe e
    where e.usuario_id = auth.uid() and e.ativo and e.papel = 'ADMIN'
  );
$$;

create or replace function api.exigir_editor()
returns void
language plpgsql
security definer
set search_path = pg_catalog, api
as $$
begin
  if not api.eh_editor() then
    raise exception 'Seu perfil nao possui permissao de edicao.' using errcode = '42501';
  end if;
end;
$$;

create or replace function api.registrar_auditoria(
  p_entidade text, p_entidade_id uuid, p_acao text, p_detalhes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, crm
as $$
begin
  insert into crm.auditoria_api (entidade, entidade_id, acao, detalhes, criado_por)
  values (p_entidade, p_entidade_id, p_acao, coalesce(p_detalhes, '{}'::jsonb), auth.uid());
end;
$$;

-- O administrador inicial precisa existir no Auth antes desta migracao.
insert into cadastro.equipe (usuario_id, nome, email, cargo, papel)
select u.id,
       coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), split_part(u.email, '@', 1)),
       lower(u.email),
       'Administrador',
       'ADMIN'
from auth.users u
where lower(u.email) in (
  'comercial3@maisintegradora.com',
  'comercial3@maisintegradora.com.br'
)
on conflict (email) do update
set usuario_id = excluded.usuario_id,
    nome = excluded.nome,
    cargo = excluded.cargo,
    papel = 'ADMIN',
    ativo = true,
    atualizado_em = now();

-- ---------------------------------------------------------------------------
-- 3. Superficie de leitura. As tabelas continuam privadas.
-- ---------------------------------------------------------------------------

create or replace view api.vw_equipe as
select membro_id, usuario_id, nome, email, cargo, papel, ativo
from cadastro.equipe
where ativo;

create or replace view api.vw_carteira_crm as
select
  e.empresa_id,
  r.relacionamento_id,
  r.tipo as tipo_relacionamento,
  r.status as status_relacionamento,
  coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Empresa sem nome') as empresa,
  e.razao_social, e.nome_fantasia, e.cnpj, e.categoria, e.situacao_cadastral,
  e.logradouro, e.bairro, e.municipio, e.uf, e.cep,
  e.contato_nome, e.contato_cargo, e.telefone, e.whatsapp, e.email,
  e.origem as origem_registro,
  p.ponto_id, p.latitude, p.longitude, p.status_confirmacao, p.fonte_localizacao,
  p.precisao_m, p.confirmado_em, p.observacao as observacao_localizacao,
  r.cliente_desde, r.responsavel_por, r.observacao,
  r.criado_em as relacionamento_criado_em,
  r.atualizado_em as relacionamento_atualizado_em
from crm.relacionamentos r
join cadastro.empresas e on e.empresa_id = r.empresa_id
left join mapa.pontos p on p.empresa_id = e.empresa_id
where r.status = 'ATIVO';

create or replace view api.vw_mapa_clientes as
select
  empresa_id as cliente_id, empresa_id, relacionamento_id,
  tipo_relacionamento as tipo_crm,
  empresa as nome_exibicao, razao_social, nome_fantasia, cnpj, categoria,
  situacao_cadastral, uf, municipio, bairro, logradouro, cep, contato_nome,
  contato_cargo, telefone, telefone as telefone_1, whatsapp, email,
  latitude, longitude,
  case when status_confirmacao = 'CONFIRMADO_CAMPO' then latitude end as latitude_confirmada,
  case when status_confirmacao = 'CONFIRMADO_CAMPO' then longitude end as longitude_confirmada,
  case when status_confirmacao = 'CONFIRMADO_CAMPO' then 'CONFIRMADA_CAMPO'
       when status_confirmacao = 'APROXIMADO_MUNICIPIO' then 'APROX_SEDE_MUNICIPIO'
       else coalesce(status_confirmacao, 'SEM_CONFIRMACAO') end as localizacao_status,
  fonte_localizacao as localizacao_fonte, precisao_m as precisao_efetiva,
  observacao_localizacao as localizacao_observacao, origem_registro,
  case when origem_registro = 'CADASTRO_CAMPO' then 'NOVO' else 'BASE_ORIGINAL' end as classificacao_registro,
  1 as revisao, relacionamento_atualizado_em as reposicionado_em,
  status_confirmacao, confirmado_em, cliente_desde
from api.vw_carteira_crm;

create or replace view api.vw_viagens as
select viagem_id, titulo, status, inicio_em, fim_em, km_inicial, km_final,
       observacao, participantes, empresas_planejadas, paradas,
       odometro_registros, anexos, criado_por, criado_em, atualizado_em
from crm.viagens;

create or replace view api.vw_visitas_crm as
select
  v.visita_id, v.empresa_id, v.viagem_id, v.status, v.tipo, v.agendada_para,
  v.realizada_em, v.resultado, v.observacao, v.latitude, v.longitude, v.anexos,
  v.criado_por, v.criado_em, v.atualizado_em,
  coalesce(jsonb_agg(jsonb_build_object(
    'id', n.necessidade_id, 'category', n.categoria, 'description', n.descricao,
    'priority', n.prioridade, 'status', n.status, 'date', n.criado_em
  ) order by n.criado_em desc) filter (where n.necessidade_id is not null), '[]'::jsonb) as necessidades
from crm.visitas v
left join crm.necessidades n on n.visita_id = v.visita_id
group by v.visita_id;

create or replace view api.vw_necessidades as
select necessidade_id, empresa_id, visita_id, categoria, descricao, prioridade,
       status, criado_em, atualizado_em
from crm.necessidades;

create or replace view api.vw_despesas_crm as
select despesa_id, viagem_id, evento_id, categoria, centro_custo, valor,
       estabelecimento, observacao as descricao, ocorrido_em as data_despesa,
       anexos, criado_por, criado_em, atualizado_em
from crm.despesas;

create or replace view api.vw_despesas_eventos as
select * from api.vw_despesas_crm where evento_id is not null;

create or replace view api.vw_eventos as
select evento_id, nome, local, data_inicio, data_fim, status, tipo_participacao,
       notas_estrategicas, participantes, anexos, links, contatos,
       criado_por, criado_em, atualizado_em
from crm.eventos;

create or replace view api.vw_rotas_visitas as
select viagem_id as rota_id, titulo, inicio_em::date as data_planejada, status,
       jsonb_array_length(paradas) as total_paradas,
       coalesce((select count(*) from jsonb_array_elements(paradas) p where coalesce((p ->> 'done')::boolean, false)), 0) as paradas_visitadas,
       jsonb_array_length(paradas) - coalesce((select count(*) from jsonb_array_elements(paradas) p where coalesce((p ->> 'done')::boolean, false)), 0) as paradas_pendentes,
       criado_em
from crm.viagens;

create or replace view api.vw_atividade_clientes as
select auditoria_id, entidade, entidade_id as cliente_id, acao, detalhes,
       criado_por, criado_em
from crm.auditoria_api
where entidade in ('CLIENTE', 'LOCALIZACAO', 'VISITA');

-- ---------------------------------------------------------------------------
-- 4. Escrita autenticada. Toda operacao valida a sessao e o papel no banco.
-- ---------------------------------------------------------------------------

create or replace function api.criar_cliente(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, cadastro, crm, mapa
as $$
declare
  v_empresa_id uuid;
  v_cnpj text := nullif(regexp_replace(coalesce(p_dados ->> 'cnpj', ''), '[^0-9]', '', 'g'), '');
  v_categoria text;
  v_tipo text;
begin
  perform api.exigir_editor();
  if nullif(trim(coalesce(p_dados ->> 'name', p_dados ->> 'nome_fantasia', p_dados ->> 'razao_social')), '') is null then
    raise exception 'Informe o nome do cliente.' using errcode = '22023';
  end if;
  if v_cnpj is not null and v_cnpj !~ '^\d{14}$' then
    raise exception 'CNPJ deve conter 14 digitos.' using errcode = '22023';
  end if;
  if v_cnpj is not null and exists (select 1 from cadastro.empresas where cnpj = v_cnpj) then
    raise exception 'Ja existe um cliente com este CNPJ.' using errcode = '23505';
  end if;
  v_categoria := case upper(coalesce(p_dados ->> 'category', p_dados ->> 'segment', 'OUTRO'))
    when 'CARCINICULTOR' then 'CARCINICULTOR' when 'IRRIGACAO' then 'IRRIGACAO'
    when 'CONSTRUCAO_CIVIL' then 'CONSTRUCAO_CIVIL' when 'MINERACAO' then 'MINERACAO'
    when 'CONDOMINIAL' then 'CONDOMINIAL' else 'OUTRO' end;
  v_tipo := case upper(coalesce(p_dados ->> 'status', 'LEAD')) when 'CLIENTE' then 'CLIENTE' else 'LEAD' end;

  insert into cadastro.empresas (
    cnpj, razao_social, nome_fantasia, categoria, contato_nome, telefone,
    whatsapp, email, municipio, uf, bairro, cep, logradouro, origem
  ) values (
    v_cnpj, nullif(trim(coalesce(p_dados ->> 'company', p_dados ->> 'razao_social')), ''),
    nullif(trim(coalesce(p_dados ->> 'name', p_dados ->> 'nome_fantasia')), ''),
    v_categoria, nullif(trim(coalesce(p_dados ->> 'contact', p_dados ->> 'contato_nome')), ''),
    nullif(trim(coalesce(p_dados ->> 'phone', p_dados ->> 'telefone')), ''),
    nullif(trim(p_dados ->> 'whatsapp'), ''), nullif(trim(p_dados ->> 'email'), ''),
    nullif(trim(coalesce(p_dados ->> 'city', p_dados ->> 'municipio')), ''),
    nullif(upper(trim(coalesce(p_dados ->> 'state', p_dados ->> 'uf'))), ''),
    nullif(trim(p_dados ->> 'bairro'), ''),
    nullif(regexp_replace(coalesce(p_dados ->> 'cep', ''), '[^0-9]', '', 'g'), ''),
    nullif(trim(p_dados ->> 'logradouro'), ''), 'CADASTRO_CAMPO'
  ) returning empresa_id into v_empresa_id;

  insert into crm.relacionamentos (empresa_id, tipo, status, responsavel_por, origem, observacao, cliente_desde)
  values (v_empresa_id, v_tipo, 'ATIVO', auth.uid(),
          coalesce(nullif(trim(p_dados ->> 'origin'), ''), 'CADASTRO_CAMPO'),
          nullif(trim(coalesce(p_dados ->> 'notes', p_dados ->> 'observacoes_comerciais')), ''),
          case when v_tipo = 'CLIENTE' then now() else null end);

  if nullif(p_dados ->> 'lat', '') is not null or nullif(p_dados ->> 'latitude', '') is not null then
    insert into mapa.pontos (empresa_id, latitude, longitude, fonte_localizacao,
      precisao_m, observacao, status_confirmacao, confirmado_em, confirmado_por, criado_por)
    values (v_empresa_id,
      coalesce((p_dados ->> 'lat')::numeric, (p_dados ->> 'latitude')::numeric),
      coalesce((p_dados ->> 'lng')::numeric, (p_dados ->> 'longitude')::numeric),
      coalesce(nullif(trim(p_dados ->> 'localizacao_fonte'), ''), 'CADASTRO_CAMPO'),
      nullif(p_dados ->> 'localizacao_precisao_m', '')::numeric,
      nullif(trim(coalesce(p_dados ->> 'localizacao_observacao', p_dados ->> 'notes')), ''),
      'CONFIRMADO_CAMPO', now(), auth.uid(), auth.uid());
  end if;
  perform api.registrar_auditoria('CLIENTE', v_empresa_id, 'CRIADO', jsonb_build_object('origem', 'CRM'));
  return (select to_jsonb(x) from api.vw_carteira_crm x where x.empresa_id = v_empresa_id);
end;
$$;

create or replace function api.atualizar_cliente(p_cliente_id uuid, p_dados jsonb)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, api, cadastro, crm, mapa
as $$
begin
  perform api.exigir_editor();
  update cadastro.empresas set
    razao_social = coalesce(nullif(trim(coalesce(p_dados ->> 'company', p_dados ->> 'razao_social')), ''), razao_social),
    nome_fantasia = coalesce(nullif(trim(coalesce(p_dados ->> 'name', p_dados ->> 'nome_fantasia')), ''), nome_fantasia),
    contato_nome = coalesce(nullif(trim(coalesce(p_dados ->> 'contact', p_dados ->> 'contato_nome')), ''), contato_nome),
    telefone = coalesce(nullif(trim(coalesce(p_dados ->> 'phone', p_dados ->> 'telefone')), ''), telefone),
    whatsapp = coalesce(nullif(trim(p_dados ->> 'whatsapp'), ''), whatsapp),
    email = coalesce(nullif(trim(p_dados ->> 'email'), ''), email),
    municipio = coalesce(nullif(trim(coalesce(p_dados ->> 'city', p_dados ->> 'municipio')), ''), municipio),
    uf = coalesce(nullif(upper(trim(coalesce(p_dados ->> 'state', p_dados ->> 'uf'))), ''), uf),
    atualizado_em = now()
  where empresa_id = p_cliente_id;
  if not found then raise exception 'Cliente nao encontrado.' using errcode = 'P0002'; end if;
  update crm.relacionamentos set observacao = coalesce(nullif(trim(p_dados ->> 'notes'), ''), observacao), atualizado_em = now()
  where empresa_id = p_cliente_id;
  perform api.registrar_auditoria('CLIENTE', p_cliente_id, 'ATUALIZADO');
  return (select to_jsonb(x) from api.vw_carteira_crm x where x.empresa_id = p_cliente_id);
end;
$$;

create or replace function api.arquivar_cliente(p_cliente_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, api, crm
as $$
begin
  perform api.exigir_editor();
  update crm.relacionamentos set status = 'ARQUIVADO', atualizado_em = now() where empresa_id = p_cliente_id;
  if not found then raise exception 'Cliente nao encontrado.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('CLIENTE', p_cliente_id, 'ARQUIVADO');
end;
$$;

create or replace function api.confirmar_localizacao(
  p_cliente_id uuid, p_latitude float8, p_longitude float8, p_fonte text,
  p_precisao_m float8 default null, p_observacao text default null
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, mapa
as $$
begin
  perform api.exigir_editor();
  if p_latitude not between -34.2 and 5.4 or p_longitude not between -74.1 and -32.2 then
    raise exception 'Coordenada fora do territorio brasileiro.' using errcode = '22023';
  end if;
  insert into mapa.pontos (empresa_id, latitude, longitude, fonte_localizacao, precisao_m,
    observacao, status_confirmacao, confirmado_em, confirmado_por, criado_por)
  values (p_cliente_id, p_latitude, p_longitude, coalesce(nullif(trim(p_fonte), ''), 'AJUSTE_MANUAL'),
    p_precisao_m, nullif(trim(p_observacao), ''), 'CONFIRMADO_CAMPO', now(), auth.uid(), auth.uid())
  on conflict (empresa_id) do update set latitude = excluded.latitude, longitude = excluded.longitude,
    fonte_localizacao = excluded.fonte_localizacao, precisao_m = excluded.precisao_m,
    observacao = excluded.observacao, status_confirmacao = 'CONFIRMADO_CAMPO',
    confirmado_em = now(), confirmado_por = auth.uid(), atualizado_em = now();
  perform api.registrar_auditoria('LOCALIZACAO', p_cliente_id, 'CONFIRMADA');
  return (select to_jsonb(x) from api.vw_carteira_crm x where x.empresa_id = p_cliente_id);
end;
$$;

create or replace function api.criar_visita(p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_visita_id uuid; v_need jsonb; v_cliente_id uuid := (p_dados ->> 'clientId')::uuid;
begin
  perform api.exigir_editor();
  if not exists (select 1 from crm.relacionamentos where empresa_id = v_cliente_id and status = 'ATIVO') then
    raise exception 'Cliente da visita nao existe ou esta arquivado.' using errcode = '23503';
  end if;
  insert into crm.visitas (empresa_id, viagem_id, status, tipo, realizada_em, resultado,
    observacao, latitude, longitude, anexos, criado_por)
  values (v_cliente_id, nullif(p_dados ->> 'tripId', '')::uuid, 'REALIZADA',
    upper(coalesce(nullif(trim(p_dados ->> 'type'), ''), 'ACOMPANHAMENTO')),
    now(), 'REGISTRADA', nullif(trim(p_dados ->> 'notes'), ''),
    nullif(p_dados ->> 'lat', '')::float8, nullif(p_dados ->> 'lng', '')::float8,
    coalesce(p_dados -> 'attachments', '[]'::jsonb), auth.uid())
  returning visita_id into v_visita_id;
  for v_need in select value from jsonb_array_elements(coalesce(p_dados -> 'needs', '[]'::jsonb)) loop
    insert into crm.necessidades (empresa_id, visita_id, categoria, descricao, prioridade, status)
    values (v_cliente_id, v_visita_id,
      coalesce(nullif(trim(v_need ->> 'category'), ''), nullif(trim(v_need #>> '{}'), ''), 'Outro'),
      coalesce(nullif(trim(v_need ->> 'description'), ''), nullif(trim(v_need #>> '{}'), ''), 'Registrada na visita'),
      case upper(coalesce(v_need ->> 'priority', 'MEDIA')) when 'ALTA' then 'ALTA' when 'BAIXA' then 'BAIXA' else 'MEDIA' end,
      'ABERTA');
  end loop;
  perform api.registrar_auditoria('VISITA', v_visita_id, 'CRIADA', jsonb_build_object('cliente_id', v_cliente_id));
  return (select to_jsonb(x) from api.vw_visitas_crm x where x.visita_id = v_visita_id);
end;
$$;

create or replace function api.criar_necessidade(p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_id uuid;
begin
  perform api.exigir_editor();
  insert into crm.necessidades (empresa_id, visita_id, categoria, descricao, prioridade, status)
  values ((p_dados ->> 'clientId')::uuid, nullif(p_dados ->> 'visitId', '')::uuid,
    nullif(trim(p_dados ->> 'category'), ''), nullif(trim(p_dados ->> 'description'), ''),
    case upper(coalesce(p_dados ->> 'priority', 'MEDIA')) when 'ALTA' then 'ALTA' when 'BAIXA' then 'BAIXA' else 'MEDIA' end,
    'ABERTA') returning necessidade_id into v_id;
  perform api.registrar_auditoria('NECESSIDADE', v_id, 'CRIADA');
  return (select to_jsonb(x) from api.vw_necessidades x where x.necessidade_id = v_id);
end;
$$;

create or replace function api.criar_viagem(
  p_titulo text, p_inicio date, p_fim date, p_observacao text default null,
  p_participantes jsonb default '[]'::jsonb, p_clientes jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_id uuid;
begin
  perform api.exigir_editor();
  if nullif(trim(p_titulo), '') is null or p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Informe titulo e um periodo de viagem valido.' using errcode = '22023';
  end if;
  insert into crm.viagens (titulo, inicio_em, fim_em, observacao, participantes, empresas_planejadas, criado_por)
  values (trim(p_titulo), p_inicio, p_fim, nullif(trim(p_observacao), ''),
    case when jsonb_typeof(coalesce(p_participantes, '[]')) = 'array' then p_participantes else '[]'::jsonb end,
    case when jsonb_typeof(coalesce(p_clientes, '[]')) = 'array' then p_clientes else '[]'::jsonb end,
    auth.uid()) returning viagem_id into v_id;
  perform api.registrar_auditoria('VIAGEM', v_id, 'CRIADA');
  return (select to_jsonb(x) from api.vw_viagens x where x.viagem_id = v_id);
end;
$$;

create or replace function api.atualizar_viagem(p_viagem_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_status text;
begin
  perform api.exigir_editor();
  v_status := case upper(coalesce(p_dados ->> 'status', ''))
    when 'PLANEJADA' then 'PLANEJADA' when 'EM ANDAMENTO' then 'EM_ANDAMENTO'
    when 'EM_ANDAMENTO' then 'EM_ANDAMENTO' when 'CONCLUIDA' then 'CONCLUIDA'
    when 'CONCLUÍDA' then 'CONCLUIDA' when 'CANCELADA' then 'CANCELADA' else null end;
  update crm.viagens set
    status = coalesce(v_status, status),
    observacao = coalesce(nullif(trim(coalesce(p_dados ->> 'notes', p_dados ->> 'objective')), ''), observacao),
    participantes = coalesce(p_dados -> 'participants', participantes),
    empresas_planejadas = coalesce(p_dados -> 'clients', empresas_planejadas),
    paradas = coalesce(p_dados -> 'stops', paradas),
    odometro_registros = coalesce(p_dados -> 'odometerRecords', odometro_registros),
    anexos = coalesce(p_dados -> 'attachments', anexos),
    km_inicial = coalesce(nullif(p_dados ->> 'startKm', '')::numeric, km_inicial),
    km_final = coalesce(nullif(p_dados ->> 'endKm', '')::numeric, km_final),
    atualizado_em = now()
  where viagem_id = p_viagem_id;
  if not found then raise exception 'Viagem nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('VIAGEM', p_viagem_id, 'ATUALIZADA');
  return (select to_jsonb(x) from api.vw_viagens x where x.viagem_id = p_viagem_id);
end;
$$;

create or replace function api.excluir_viagem(p_viagem_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, api, crm
as $$
begin
  perform api.exigir_editor();
  delete from crm.viagens where viagem_id = p_viagem_id;
  if not found then raise exception 'Viagem nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('VIAGEM', p_viagem_id, 'EXCLUIDA');
end;
$$;

create or replace function api.criar_despesa(p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_id uuid; v_viagem uuid := nullif(p_dados ->> 'tripId', '')::uuid; v_evento uuid := nullif(p_dados ->> 'eventId', '')::uuid;
begin
  perform api.exigir_editor();
  if v_viagem is null and v_evento is null then raise exception 'Informe a viagem ou o evento da despesa.' using errcode = '22023'; end if;
  if coalesce((p_dados ->> 'amount')::numeric, 0) < 0 then raise exception 'O valor nao pode ser negativo.' using errcode = '22023'; end if;
  insert into crm.despesas (viagem_id, evento_id, categoria, centro_custo, valor, estabelecimento, observacao, ocorrido_em, anexos, criado_por)
  values (v_viagem, v_evento, coalesce(nullif(trim(p_dados ->> 'category'), ''), 'Outros'),
    nullif(trim(p_dados ->> 'costCenter'), ''), coalesce((p_dados ->> 'amount')::numeric, 0),
    nullif(trim(p_dados ->> 'place'), ''), nullif(trim(p_dados ->> 'notes'), ''),
    coalesce(nullif(p_dados ->> 'date', '')::date, current_date), coalesce(p_dados -> 'attachments', '[]'::jsonb), auth.uid())
  returning despesa_id into v_id;
  perform api.registrar_auditoria('DESPESA', v_id, 'CRIADA');
  return (select to_jsonb(x) from api.vw_despesas_crm x where x.despesa_id = v_id);
end;
$$;

create or replace function api.atualizar_despesa(p_despesa_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
begin
  perform api.exigir_editor();
  update crm.despesas set
    categoria = coalesce(nullif(trim(p_dados ->> 'category'), ''), categoria),
    centro_custo = coalesce(nullif(trim(p_dados ->> 'costCenter'), ''), centro_custo),
    valor = coalesce(nullif(p_dados ->> 'amount', '')::numeric, valor),
    estabelecimento = coalesce(nullif(trim(p_dados ->> 'place'), ''), estabelecimento),
    observacao = coalesce(nullif(trim(p_dados ->> 'notes'), ''), observacao),
    ocorrido_em = coalesce(nullif(p_dados ->> 'date', '')::date, ocorrido_em),
    anexos = coalesce(p_dados -> 'attachments', anexos), atualizado_em = now()
  where despesa_id = p_despesa_id;
  if not found then raise exception 'Despesa nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('DESPESA', p_despesa_id, 'ATUALIZADA');
  return (select to_jsonb(x) from api.vw_despesas_crm x where x.despesa_id = p_despesa_id);
end;
$$;

create or replace function api.excluir_despesa(p_despesa_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, api, crm
as $$
begin
  perform api.exigir_editor();
  delete from crm.despesas where despesa_id = p_despesa_id;
  if not found then raise exception 'Despesa nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('DESPESA', p_despesa_id, 'EXCLUIDA');
end;
$$;

create or replace function api.criar_evento(
  p_nome text, p_local text, p_data_inicio date, p_data_fim date,
  p_tipo_participacao text, p_notas text
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_id uuid;
begin
  perform api.exigir_editor();
  if nullif(trim(p_nome), '') is null or p_data_inicio is null or p_data_fim is null or p_data_fim < p_data_inicio then
    raise exception 'Informe nome e periodo valido para o evento.' using errcode = '22023';
  end if;
  insert into crm.eventos (nome, local, data_inicio, data_fim, tipo_participacao, notas_estrategicas, criado_por)
  values (trim(p_nome), nullif(trim(p_local), ''), p_data_inicio, p_data_fim,
    case upper(coalesce(p_tipo_participacao, 'PARTICIPANTE')) when 'EXPOSITOR' then 'EXPOSITOR' else 'PARTICIPANTE' end,
    nullif(trim(p_notas), ''), auth.uid()) returning evento_id into v_id;
  perform api.registrar_auditoria('EVENTO', v_id, 'CRIADO');
  return (select to_jsonb(x) from api.vw_eventos x where x.evento_id = v_id);
end;
$$;

create or replace function api.atualizar_evento(p_evento_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_status text;
begin
  perform api.exigir_editor();
  v_status := case upper(coalesce(p_dados ->> 'status', ''))
    when 'PLANEJADO' then 'PLANEJADO' when 'EM ANDAMENTO' then 'EM_ANDAMENTO'
    when 'EM_ANDAMENTO' then 'EM_ANDAMENTO' when 'REALIZADO' then 'REALIZADO'
    when 'CANCELADO' then 'CANCELADO' else null end;
  update crm.eventos set
    nome = coalesce(nullif(trim(p_dados ->> 'name'), ''), nome),
    local = coalesce(nullif(trim(p_dados ->> 'location'), ''), local),
    data_inicio = coalesce(nullif(p_dados ->> 'startDate', '')::date, data_inicio),
    data_fim = coalesce(nullif(p_dados ->> 'endDate', '')::date, data_fim),
    status = coalesce(v_status, status),
    tipo_participacao = case upper(coalesce(p_dados ->> 'role', '')) when 'EXPOSITOR' then 'EXPOSITOR' when 'PARTICIPANTE' then 'PARTICIPANTE' else tipo_participacao end,
    notas_estrategicas = coalesce(nullif(trim(p_dados ->> 'notes'), ''), notas_estrategicas),
    participantes = coalesce(p_dados -> 'participantIds', participantes),
    anexos = coalesce(p_dados -> 'attachments', anexos), links = coalesce(p_dados -> 'links', links),
    contatos = coalesce(p_dados -> 'contacts', contatos), atualizado_em = now()
  where evento_id = p_evento_id;
  if not found then raise exception 'Evento nao encontrado.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('EVENTO', p_evento_id, 'ATUALIZADO');
  return (select to_jsonb(x) from api.vw_eventos x where x.evento_id = p_evento_id);
end;
$$;

create or replace function api.excluir_evento(p_evento_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, api, crm
as $$
begin
  perform api.exigir_editor();
  delete from crm.eventos where evento_id = p_evento_id;
  if not found then raise exception 'Evento nao encontrado.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('EVENTO', p_evento_id, 'EXCLUIDO');
end;
$$;

-- Compatibilidade para o mapa e para chamadas antigas: ambas usam a API nova.
create or replace function api.cadastrar_cliente(p_dados jsonb) returns jsonb
language sql security definer set search_path = pg_catalog, api as $$ select api.criar_cliente(p_dados); $$;
create or replace function api.atualizar_comunicacao(p_cliente_id uuid, p_dados jsonb) returns jsonb
language sql security definer set search_path = pg_catalog, api as $$ select api.atualizar_cliente(p_cliente_id, p_dados); $$;
create or replace function api.criar_rota_visita(p_titulo text, p_data_planejada date, p_observacao text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, api, crm as $$
declare v_id uuid;
begin
  perform api.exigir_editor();
  insert into crm.viagens(titulo, inicio_em, fim_em, observacao, criado_por)
  values (coalesce(nullif(trim(p_titulo), ''), 'Rota de visitas'), coalesce(p_data_planejada, current_date), coalesce(p_data_planejada, current_date), nullif(trim(p_observacao), ''), auth.uid())
  returning viagem_id into v_id;
  perform api.registrar_auditoria('VIAGEM', v_id, 'CRIADA_PELO_MAPA');
  return jsonb_build_object('rota_id', v_id);
end;
$$;
create or replace function api.definir_paradas_rota(p_rota_id uuid, p_paradas jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, api, crm as $$
declare v_stops jsonb;
begin
  perform api.exigir_editor();
  select coalesce(jsonb_agg(jsonb_build_object('id', gen_random_uuid(), 'label', coalesce(c.empresa, 'Cliente'), 'place', concat_ws(', ', c.municipio, c.uf), 'clientId', x.value ->> 'cliente_id', 'done', false)), '[]'::jsonb)
  into v_stops from jsonb_array_elements(coalesce(p_paradas, '[]'::jsonb)) x
  left join api.vw_carteira_crm c on c.empresa_id = nullif(x.value ->> 'cliente_id', '')::uuid;
  update crm.viagens set paradas = v_stops, atualizado_em = now() where viagem_id = p_rota_id;
  if not found then raise exception 'Rota nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('VIAGEM', p_rota_id, 'PARADAS_DEFINIDAS');
  return (select to_jsonb(x) from api.vw_viagens x where x.viagem_id = p_rota_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. RLS, grants e Storage privado. Acesso direto a tabelas e proibido.
-- ---------------------------------------------------------------------------

revoke all on schema cadastro, mapa, crm from public, anon, authenticated;
grant usage on schema api to authenticated;
revoke all on all tables in schema cadastro, mapa, crm from public, anon, authenticated;

alter table cadastro.empresas enable row level security;
alter table cadastro.equipe enable row level security;
alter table mapa.pontos enable row level security;
alter table crm.relacionamentos enable row level security;
alter table crm.viagens enable row level security;
alter table crm.visitas enable row level security;
alter table crm.necessidades enable row level security;
alter table crm.despesas enable row level security;
alter table crm.anexos enable row level security;
alter table crm.eventos enable row level security;
alter table crm.auditoria_api enable row level security;

revoke all on all tables in schema api from public, anon;
grant select on api.vw_equipe, api.vw_carteira_crm, api.vw_mapa_clientes,
  api.vw_viagens, api.vw_visitas_crm, api.vw_necessidades, api.vw_despesas_crm,
  api.vw_despesas_eventos, api.vw_eventos, api.vw_rotas_visitas,
  api.vw_atividade_clientes to authenticated;

revoke all on all functions in schema api from public, anon;
grant execute on function api.eh_membro(), api.eh_editor(), api.eh_admin(),
  api.criar_cliente(jsonb), api.atualizar_cliente(uuid, jsonb), api.arquivar_cliente(uuid),
  api.confirmar_localizacao(uuid, float8, float8, text, float8, text),
  api.criar_visita(jsonb), api.criar_necessidade(jsonb),
  api.criar_viagem(text, date, date, text, jsonb, jsonb), api.atualizar_viagem(uuid, jsonb), api.excluir_viagem(uuid),
  api.criar_despesa(jsonb), api.atualizar_despesa(uuid, jsonb), api.excluir_despesa(uuid),
  api.criar_evento(text, text, date, date, text, text), api.atualizar_evento(uuid, jsonb), api.excluir_evento(uuid),
  api.cadastrar_cliente(jsonb), api.atualizar_comunicacao(uuid, jsonb),
  api.criar_rota_visita(text, date, text), api.definir_paradas_rota(uuid, jsonb)
to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('crm-anexos', 'crm-anexos', false, 20971520,
  array['image/jpeg','image/png','image/webp','application/pdf','video/mp4'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists crm_anexos_leitura_equipe on storage.objects;
create policy crm_anexos_leitura_equipe on storage.objects for select to authenticated
using (bucket_id = 'crm-anexos' and api.eh_membro());
drop policy if exists crm_anexos_envio_editor on storage.objects;
create policy crm_anexos_envio_editor on storage.objects for insert to authenticated
with check (bucket_id = 'crm-anexos' and api.eh_editor() and name ~ '^(eventos|visitas|viagens|despesas)/');
drop policy if exists crm_anexos_exclusao_editor on storage.objects;
create policy crm_anexos_exclusao_editor on storage.objects for delete to authenticated
using (bucket_id = 'crm-anexos' and api.eh_editor());

commit;
notify pgrst, 'reload schema';
