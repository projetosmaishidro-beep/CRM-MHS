-- ============================================================================
-- Fundação unificada: Mapa de Clientes + Central Comercial
--
-- Pré-requisito de carga: mapa_clientes.base_mapa já deve conter a base legada
-- e as colunas criadas por supabase_operacao_feira_v1.sql.
--
-- Esta migração é aditiva. Ela preserva a base bruta e cria o modelo canônico
-- para a futura conexão dos dois aplicativos.
-- ============================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists core;
create schema if not exists crm;
create schema if not exists integracao;
create schema if not exists mapa_clientes;

-- -----------------------------------------------------------------------------
-- Funções de normalização sem perda do valor de origem
-- -----------------------------------------------------------------------------

create or replace function core.apenas_digitos(p_valor text)
returns text
language sql
immutable
parallel safe
as $$
    select nullif(regexp_replace(coalesce(p_valor, ''), '[^0-9]', '', 'g'), '');
$$;

create or replace function core.data_br(p_valor text)
returns date
language plpgsql
immutable
parallel safe
as $$
declare
    v_valor text := nullif(trim(p_valor), '');
begin
    if v_valor is null or v_valor !~ '^\d{2}/\d{2}/\d{4}$' then
        return null;
    end if;

    return to_date(v_valor, 'DD/MM/YYYY');
exception when others then
    return null;
end;
$$;

create or replace function core.numero_br(p_valor text)
returns double precision
language plpgsql
immutable
parallel safe
as $$
declare
    v_valor text := nullif(replace(trim(p_valor), ',', '.'), '');
begin
    if v_valor is null or v_valor !~ '^-?\d+(\.\d+)?$' then
        return null;
    end if;

    return v_valor::double precision;
exception when others then
    return null;
end;
$$;

create or replace function core.booleano_br(p_valor text)
returns boolean
language sql
immutable
parallel safe
as $$
    select case lower(trim(coalesce(p_valor, '')))
        when 'sim' then true
        when 's' then true
        when 'true' then true
        when '1' then true
        when 'não' then false
        when 'nao' then false
        when 'n' then false
        when 'false' then false
        when '0' then false
        else null
    end;
$$;

-- -----------------------------------------------------------------------------
-- CORE: identidade jurídica e operacional
-- -----------------------------------------------------------------------------

create table if not exists core.empresas (
    empresa_id              uuid primary key default gen_random_uuid(),
    cnpj_raiz               text unique,
    razao_social            text,
    nome_preferencial       text,
    situacao_cadastral      text,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint empresas_cnpj_raiz_check
        check (cnpj_raiz is null or cnpj_raiz ~ '^\d{8}$')
);

comment on table core.empresas is
'Pessoa jurídica agrupada pela raiz de oito dígitos do CNPJ.';

create table if not exists core.estabelecimentos (
    estabelecimento_id      uuid primary key default gen_random_uuid(),
    empresa_id              uuid references core.empresas(empresa_id) on delete set null,
    cnpj_normalizado        text unique,
    razao_social            text,
    nome_fantasia           text,
    situacao_cadastral      text,
    motivo_situacao         text,
    data_abertura           date,
    porte                   text,
    capital_social          numeric(18,2),
    optante_simples         boolean,
    optante_mei             boolean,
    quantidade_socios       integer,
    origem_principal        text not null default 'MAPA_CLIENTES',
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint estabelecimentos_cnpj_check
        check (cnpj_normalizado is null or cnpj_normalizado ~ '^\d{14}$'),
    constraint estabelecimentos_quantidade_socios_check
        check (quantidade_socios is null or quantidade_socios >= 0)
);

comment on table core.estabelecimentos is
'Unidade visitável/comercial. É a identidade usada pelo mapa, CRM e visitas.';

create table if not exists core.cnaes (
    cnae_codigo             text primary key,
    descricao               text,
    criado_em               timestamptz not null default now(),
    constraint cnaes_codigo_check check (cnae_codigo ~ '^\d{5,7}$')
);

create table if not exists core.estabelecimento_cnaes (
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    cnae_codigo             text not null references core.cnaes(cnae_codigo) on delete restrict,
    principal               boolean not null default false,
    fonte                   text not null default 'IMPORTACAO_MAPA',
    criado_em               timestamptz not null default now(),
    primary key (estabelecimento_id, cnae_codigo)
);

create unique index if not exists estabelecimento_um_cnae_principal_uidx
    on core.estabelecimento_cnaes (estabelecimento_id)
    where principal;

create table if not exists core.enderecos (
    endereco_id             uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    logradouro              text,
    bairro                  text,
    municipio               text,
    uf                      text,
    cep_normalizado         text,
    origem                  text not null default 'IMPORTACAO_MAPA',
    principal               boolean not null default true,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint enderecos_uf_check check (uf is null or uf ~ '^[A-Z]{2}$'),
    constraint enderecos_cep_check check (cep_normalizado is null or cep_normalizado ~ '^\d{8}$')
);

create unique index if not exists endereco_principal_por_estabelecimento_uidx
    on core.enderecos (estabelecimento_id)
    where principal;

create table if not exists core.localizacoes (
    localizacao_id          uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    endereco_id             uuid references core.enderecos(endereco_id) on delete set null,
    latitude                double precision not null,
    longitude               double precision not null,
    qualidade               text not null,
    fonte                   text not null,
    precisao_m              double precision,
    observacao              text,
    confirmada_em           timestamptz,
    confirmada_por          uuid references auth.users(id) on delete set null,
    atual                   boolean not null default true,
    criado_em               timestamptz not null default now(),
    constraint localizacoes_latitude_check check (latitude between -34.2 and 5.4),
    constraint localizacoes_longitude_check check (longitude between -74.1 and -32.2),
    constraint localizacoes_qualidade_check check (
        qualidade in ('CONFIRMADA_CAMPO', 'GEOCODIFICADA', 'APROX_SEDE_MUNICIPIO', 'PENDENTE_REVISAO')
    )
);

create unique index if not exists localizacao_atual_por_estabelecimento_uidx
    on core.localizacoes (estabelecimento_id)
    where atual;

create unique index if not exists localizacao_origem_sem_duplicata_uidx
    on core.localizacoes (estabelecimento_id, latitude, longitude, fonte);

create table if not exists core.contatos (
    contato_id              uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    nome                    text,
    cargo                   text,
    canal_preferido         text,
    principal               boolean not null default false,
    origem                  text not null default 'IMPORTACAO_MAPA',
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now()
);

create unique index if not exists contato_principal_por_estabelecimento_uidx
    on core.contatos (estabelecimento_id)
    where principal;

create table if not exists core.canais_contato (
    canal_id                uuid primary key default gen_random_uuid(),
    contato_id              uuid not null references core.contatos(contato_id) on delete cascade,
    tipo                    text not null,
    valor                   text not null,
    valor_normalizado       text,
    principal               boolean not null default false,
    verificado_em           timestamptz,
    criado_em               timestamptz not null default now(),
    constraint canais_contato_tipo_check check (tipo in ('TELEFONE', 'WHATSAPP', 'EMAIL'))
);

create unique index if not exists canal_contato_sem_duplicata_uidx
    on core.canais_contato (contato_id, tipo, valor_normalizado);

create table if not exists core.categorias_clientes (
    categoria_id            uuid primary key default gen_random_uuid(),
    codigo                  text not null unique,
    nome                    text not null,
    eixo                    text not null default 'SEGMENTO',
    categoria_pai_id        uuid references core.categorias_clientes(categoria_id) on delete restrict,
    ativa                   boolean not null default true,
    ordem                   smallint not null default 0,
    constraint categorias_clientes_eixo_check check (eixo in ('SEGMENTO', 'PAPEL_NA_CADEIA'))
);

create table if not exists core.estabelecimento_categorias (
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    categoria_id            uuid not null references core.categorias_clientes(categoria_id) on delete restrict,
    fonte                   text not null,
    confianca               text not null default 'PENDENTE',
    principal               boolean not null default false,
    definido_em             timestamptz not null default now(),
    definido_por            uuid references auth.users(id) on delete set null,
    primary key (estabelecimento_id, categoria_id),
    constraint estabelecimento_categorias_confianca_check
        check (confianca in ('ALTA', 'MEDIA', 'BAIXA', 'PENDENTE'))
);

create unique index if not exists categoria_principal_por_estabelecimento_uidx
    on core.estabelecimento_categorias (estabelecimento_id)
    where principal;

-- Taxonomia inicial. OUTRO é escolha humana; não é classificação automática.
insert into core.categorias_clientes (codigo, nome, eixo, ordem)
values
    ('CARCINICULTOR', 'Carcinicultor', 'SEGMENTO', 10),
    ('IRRIGACAO', 'Irrigação', 'SEGMENTO', 20),
    ('CONSTRUCAO_CIVIL', 'Construção civil', 'SEGMENTO', 30),
    ('MINERACAO', 'Mineração', 'SEGMENTO', 40),
    ('CONDOMINIAL', 'Condominial', 'SEGMENTO', 50),
    ('OUTRO', 'Outro', 'SEGMENTO', 99),
    ('PRODUTOR', 'Produtor', 'PAPEL_NA_CADEIA', 10),
    ('BENEFICIADOR', 'Beneficiador', 'PAPEL_NA_CADEIA', 20),
    ('COMERCIALIZADOR', 'Comercializador', 'PAPEL_NA_CADEIA', 30),
    ('FORNECEDOR', 'Fornecedor de serviços/insumos', 'PAPEL_NA_CADEIA', 40)
on conflict (codigo) do update
set nome = excluded.nome,
    eixo = excluded.eixo,
    ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- MAPA: linhagem de importação e geocodificação, sem repetir o cadastro mestre
-- -----------------------------------------------------------------------------

create table if not exists mapa_clientes.lotes_importacao (
    lote_id                 uuid primary key default gen_random_uuid(),
    fonte                   text not null,
    arquivo                 text,
    checksum                text,
    total_registros         integer,
    importado_em            timestamptz not null default now(),
    importado_por           uuid references auth.users(id) on delete set null,
    observacao              text
);

create table if not exists mapa_clientes.registros_origem (
    registro_origem_id      uuid primary key default gen_random_uuid(),
    lote_id                 uuid not null references mapa_clientes.lotes_importacao(lote_id) on delete cascade,
    linha_origem            integer,
    cnpj_origem             text,
    dados_brutos            jsonb not null,
    importado_em            timestamptz not null default now(),
    unique (lote_id, linha_origem)
);

create table if not exists mapa_clientes.geocodificacoes (
    geocodificacao_id       uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    endereco_consultado     text,
    provedor                text not null,
    status                  text not null,
    latitude                double precision,
    longitude               double precision,
    precisao                text,
    resposta                jsonb,
    erro                    text,
    consultado_em           timestamptz not null default now(),
    expira_em               timestamptz,
    validado_em             timestamptz,
    validado_por            uuid references auth.users(id) on delete set null
);

create index if not exists geocodificacoes_estabelecimento_idx
    on mapa_clientes.geocodificacoes (estabelecimento_id, consultado_em desc);

-- -----------------------------------------------------------------------------
-- CRM: relação comercial. O estágio comercial nunca é inferido da Receita/CNPJ.
-- -----------------------------------------------------------------------------

create table if not exists crm.contas (
    conta_id                uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null unique references core.estabelecimentos(estabelecimento_id) on delete restrict,
    estagio                 text not null default 'POTENCIAL',
    responsavel_id          uuid references auth.users(id) on delete set null,
    origem                  text not null default 'MAPA_CLIENTES',
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint contas_estagio_check check (estagio in ('POTENCIAL', 'LEAD', 'CLIENTE', 'INATIVO'))
);

create table if not exists crm.oportunidades (
    oportunidade_id         uuid primary key default gen_random_uuid(),
    conta_id                uuid not null references crm.contas(conta_id) on delete cascade,
    titulo                  text not null,
    etapa                   text not null default 'ABERTA',
    valor_estimado          numeric(18,2),
    previsao_fechamento     date,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint oportunidades_etapa_check check (etapa in ('ABERTA', 'QUALIFICADA', 'PROPOSTA', 'GANHA', 'PERDIDA'))
);

create table if not exists crm.viagens (
    viagem_id               uuid primary key default gen_random_uuid(),
    titulo                  text not null,
    status                  text not null default 'PLANEJADA',
    inicio_em               timestamptz,
    fim_em                  timestamptz,
    descricao               text,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint viagens_status_check check (status in ('PLANEJADA', 'EM_ANDAMENTO', 'CONCLUIDA', 'CANCELADA'))
);

create table if not exists crm.viagem_participantes (
    viagem_id               uuid not null references crm.viagens(viagem_id) on delete cascade,
    usuario_id              uuid not null references auth.users(id) on delete restrict,
    papel                   text not null default 'PARTICIPANTE',
    primary key (viagem_id, usuario_id)
);

create table if not exists crm.visitas (
    visita_id               uuid primary key default gen_random_uuid(),
    conta_id                uuid not null references crm.contas(conta_id) on delete restrict,
    viagem_id               uuid references crm.viagens(viagem_id) on delete set null,
    localizacao_id          uuid references core.localizacoes(localizacao_id) on delete set null,
    status                  text not null default 'PLANEJADA',
    agendada_para           timestamptz,
    realizada_em            timestamptz,
    resultado               text,
    observacao              text,
    criado_por              uuid references auth.users(id) on delete set null,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint visitas_status_check check (status in ('PLANEJADA', 'REALIZADA', 'CANCELADA'))
);

create index if not exists visitas_conta_realizada_idx
    on crm.visitas (conta_id, realizada_em desc);

create table if not exists crm.necessidades (
    necessidade_id          uuid primary key default gen_random_uuid(),
    conta_id                uuid not null references crm.contas(conta_id) on delete cascade,
    visita_id               uuid references crm.visitas(visita_id) on delete set null,
    categoria               text not null,
    descricao               text not null,
    prioridade              text not null default 'MEDIA',
    status                  text not null default 'ABERTA',
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now(),
    constraint necessidades_prioridade_check check (prioridade in ('BAIXA', 'MEDIA', 'ALTA')),
    constraint necessidades_status_check check (status in ('ABERTA', 'EM_ANALISE', 'ATENDIDA', 'CANCELADA'))
);

create table if not exists crm.despesas_viagem (
    despesa_id              uuid primary key default gen_random_uuid(),
    viagem_id               uuid not null references crm.viagens(viagem_id) on delete cascade,
    categoria               text not null,
    valor                   numeric(18,2) not null check (valor >= 0),
    ocorrido_em             date not null default current_date,
    descricao               text,
    criado_em               timestamptz not null default now()
);

create table if not exists crm.notas_conta (
    nota_id                 uuid primary key default gen_random_uuid(),
    conta_id                uuid not null references crm.contas(conta_id) on delete cascade,
    conteudo                text not null,
    conteudo_hash           text generated always as (md5(conteudo)) stored,
    origem                  text not null default 'CRM',
    criado_por              uuid references auth.users(id) on delete set null,
    criado_em               timestamptz not null default now(),
    atualizado_em           timestamptz not null default now()
);

create unique index if not exists notas_conta_origem_conteudo_uidx
    on crm.notas_conta (conta_id, origem, conteudo_hash);

-- -----------------------------------------------------------------------------
-- INTEGRAÇÃO: o UUID legado nunca é descartado; ele apenas deixa de ser mestre.
-- -----------------------------------------------------------------------------

create table if not exists integracao.referencias_origem (
    referencia_id           uuid primary key default gen_random_uuid(),
    estabelecimento_id      uuid not null references core.estabelecimentos(estabelecimento_id) on delete cascade,
    sistema                 text not null,
    tipo_entidade           text not null,
    identificador_externo   text not null,
    criado_em               timestamptz not null default now(),
    unique (sistema, tipo_entidade, identificador_externo)
);

create index if not exists referencias_origem_estabelecimento_idx
    on integracao.referencias_origem (estabelecimento_id);

create table if not exists integracao.eventos_outbox (
    evento_id               uuid primary key default gen_random_uuid(),
    agregado                text not null,
    agregado_id             uuid not null,
    tipo                    text not null,
    payload                 jsonb not null default '{}'::jsonb,
    criado_em               timestamptz not null default now(),
    publicado_em            timestamptz,
    tentativas              integer not null default 0
);

-- -----------------------------------------------------------------------------
-- Carga canônica da base atual do mapa
-- -----------------------------------------------------------------------------

do $$
begin
    if to_regclass('mapa_clientes.base_mapa') is null then
        raise exception 'Pré-requisito ausente: mapa_clientes.base_mapa.';
    end if;
end;
$$;

insert into core.empresas (cnpj_raiz, razao_social, nome_preferencial, situacao_cadastral)
select
    left(b.cnpj_normalizado, 8),
    max(nullif(trim(b.razao_social), '')),
    max(nullif(trim(b.nome_fantasia), '')),
    max(nullif(trim(b.situacao_cadastral), ''))
from mapa_clientes.base_mapa b
where b.cnpj_normalizado ~ '^\d{14}$'
group by left(b.cnpj_normalizado, 8)
on conflict (cnpj_raiz) do update
set razao_social = coalesce(core.empresas.razao_social, excluded.razao_social),
    nome_preferencial = coalesce(core.empresas.nome_preferencial, excluded.nome_preferencial),
    situacao_cadastral = coalesce(core.empresas.situacao_cadastral, excluded.situacao_cadastral),
    atualizado_em = now();

insert into core.estabelecimentos (
    estabelecimento_id, empresa_id, cnpj_normalizado, razao_social, nome_fantasia, situacao_cadastral,
    motivo_situacao, data_abertura, porte, capital_social, optante_simples,
    optante_mei, quantidade_socios, origem_principal
)
select
    case
        when b.cnpj_normalizado ~ '^\d{14}$' then gen_random_uuid()
        else b.cliente_id
    end,
    e.empresa_id,
    case when b.cnpj_normalizado ~ '^\d{14}$' then b.cnpj_normalizado end,
    nullif(trim(b.razao_social), ''),
    nullif(trim(b.nome_fantasia), ''),
    nullif(trim(b.situacao_cadastral), ''),
    nullif(trim(b.motivo_situacao), ''),
    core.data_br(b.abertura),
    nullif(trim(b.porte), ''),
    core.numero_br(b.capital_social)::numeric(18,2),
    core.booleano_br(b.optante_simples),
    core.booleano_br(b.optante_mei),
    b.qtd_socios,
    'MAPA_CLIENTES'
from mapa_clientes.base_mapa b
left join core.empresas e on e.cnpj_raiz = left(b.cnpj_normalizado, 8)
on conflict do update
set empresa_id = coalesce(core.estabelecimentos.empresa_id, excluded.empresa_id),
    razao_social = coalesce(core.estabelecimentos.razao_social, excluded.razao_social),
    nome_fantasia = coalesce(core.estabelecimentos.nome_fantasia, excluded.nome_fantasia),
    situacao_cadastral = excluded.situacao_cadastral,
    motivo_situacao = excluded.motivo_situacao,
    data_abertura = coalesce(core.estabelecimentos.data_abertura, excluded.data_abertura),
    porte = coalesce(core.estabelecimentos.porte, excluded.porte),
    capital_social = coalesce(core.estabelecimentos.capital_social, excluded.capital_social),
    optante_simples = coalesce(core.estabelecimentos.optante_simples, excluded.optante_simples),
    optante_mei = coalesce(core.estabelecimentos.optante_mei, excluded.optante_mei),
    quantidade_socios = coalesce(core.estabelecimentos.quantidade_socios, excluded.quantidade_socios),
    atualizado_em = now();

-- Esta visão resolve a mesma identidade mesmo quando o cadastro de campo ainda
-- não tem CNPJ: nesses casos, o UUID técnico legado é a ponte de migração.
create or replace view integracao.vw_mapa_estabelecimentos_vinculados
with (security_invoker = true)
as
select b.*, e.estabelecimento_id
from mapa_clientes.base_mapa b
join core.estabelecimentos e on (
    b.cnpj_normalizado ~ '^\d{14}$'
    and e.cnpj_normalizado = b.cnpj_normalizado
) or (
    coalesce(b.cnpj_normalizado, '') !~ '^\d{14}$'
    and e.estabelecimento_id = b.cliente_id
);

insert into core.cnaes (cnae_codigo, descricao)
select distinct
    substring(b.cnae from '^\s*([0-9]{5,7})'),
    nullif(trim(regexp_replace(b.cnae, '^\s*[0-9]{5,7}\s*-?\s*', '')), '')
from mapa_clientes.base_mapa b
where b.cnae ~ '^\s*[0-9]{5,7}'
on conflict (cnae_codigo) do update
set descricao = coalesce(core.cnaes.descricao, excluded.descricao);

insert into core.estabelecimento_cnaes (estabelecimento_id, cnae_codigo, principal, fonte)
select
    b.estabelecimento_id,
    substring(b.cnae from '^\s*([0-9]{5,7})'),
    true,
    'IMPORTACAO_MAPA'
from integracao.vw_mapa_estabelecimentos_vinculados b
where b.cnae ~ '^\s*[0-9]{5,7}'
on conflict (estabelecimento_id, cnae_codigo) do update
set principal = excluded.principal;

insert into core.enderecos (
    estabelecimento_id, logradouro, bairro, municipio, uf, cep_normalizado, origem, principal
)
select
    b.estabelecimento_id,
    nullif(trim(b.logradouro), ''),
    nullif(trim(b.bairro), ''),
    nullif(trim(b.municipio), ''),
    nullif(upper(trim(b.uf)), ''),
    core.apenas_digitos(b.cep),
    'IMPORTACAO_MAPA',
    true
from integracao.vw_mapa_estabelecimentos_vinculados b
where not exists (
    select 1 from core.enderecos x
    where x.estabelecimento_id = b.estabelecimento_id and x.principal
);

-- A aproximação de sede é preservada, mas nunca recebe qualidade de campo.
insert into core.localizacoes (
    estabelecimento_id, endereco_id, latitude, longitude, qualidade, fonte,
    precisao_m, observacao, confirmada_em, confirmada_por, atual
)
select
    b.estabelecimento_id,
    a.endereco_id,
    core.numero_br(b.latitude),
    core.numero_br(b.longitude),
    case
        when coalesce(b.geocode_status, b.localizacao_status) = 'CONFIRMADA_CAMPO' then 'CONFIRMADA_CAMPO'
        when coalesce(b.geocode_status, b.localizacao_status) = 'APROX_SEDE_MUNICIPIO' then 'APROX_SEDE_MUNICIPIO'
        else 'PENDENTE_REVISAO'
    end,
    coalesce(nullif(trim(b.localizacao_fonte), ''), 'IMPORTACAO_MAPA'),
    b.localizacao_precisao_m,
    b.localizacao_observacao,
    b.localizacao_confirmada_em,
    b.localizacao_confirmada_por,
    b.latitude_confirmada is null or b.longitude_confirmada is null
from integracao.vw_mapa_estabelecimentos_vinculados b
left join core.enderecos a on a.estabelecimento_id = b.estabelecimento_id and a.principal
where core.numero_br(b.latitude) is not null
  and core.numero_br(b.longitude) is not null
on conflict (estabelecimento_id, latitude, longitude, fonte) do nothing;

-- Pontos confirmados em campo são uma segunda evidência, e tornam-se atuais.
update core.localizacoes l
set atual = false
from integracao.vw_mapa_estabelecimentos_vinculados b
where l.estabelecimento_id = b.estabelecimento_id
  and b.latitude_confirmada is not null
  and b.longitude_confirmada is not null;

insert into core.localizacoes (
    estabelecimento_id, endereco_id, latitude, longitude, qualidade, fonte,
    precisao_m, observacao, confirmada_em, confirmada_por, atual
)
select
    b.estabelecimento_id,
    a.endereco_id,
    b.latitude_confirmada,
    b.longitude_confirmada,
    'CONFIRMADA_CAMPO',
    coalesce(nullif(trim(b.localizacao_fonte), ''), 'CAMPO'),
    b.localizacao_precisao_m,
    b.localizacao_observacao,
    b.localizacao_confirmada_em,
    b.localizacao_confirmada_por,
    true
from integracao.vw_mapa_estabelecimentos_vinculados b
left join core.enderecos a on a.estabelecimento_id = b.estabelecimento_id and a.principal
where b.latitude_confirmada is not null
  and b.longitude_confirmada is not null
on conflict (estabelecimento_id, latitude, longitude, fonte) do update
set qualidade = 'CONFIRMADA_CAMPO',
    atual = true,
    precisao_m = excluded.precisao_m,
    observacao = excluded.observacao,
    confirmada_em = excluded.confirmada_em,
    confirmada_por = excluded.confirmada_por;

insert into core.contatos (estabelecimento_id, nome, cargo, canal_preferido, principal, origem)
select
    b.estabelecimento_id,
    nullif(trim(b.contato_nome), ''),
    nullif(trim(b.contato_cargo), ''),
    nullif(trim(b.canal_preferido), ''),
    true,
    'IMPORTACAO_MAPA'
from integracao.vw_mapa_estabelecimentos_vinculados b
where nullif(trim(coalesce(b.contato_nome, '')), '') is not null
   or nullif(trim(coalesce(b.email, '')), '') is not null
   or core.apenas_digitos(b.telefone) is not null
   or core.apenas_digitos(b.telefone_1) is not null
   or core.apenas_digitos(b.whatsapp) is not null
on conflict (estabelecimento_id) where principal do update
set nome = coalesce(core.contatos.nome, excluded.nome),
    cargo = coalesce(core.contatos.cargo, excluded.cargo),
    canal_preferido = coalesce(core.contatos.canal_preferido, excluded.canal_preferido),
    atualizado_em = now();

insert into core.canais_contato (contato_id, tipo, valor, valor_normalizado, principal)
select c.contato_id, v.tipo, v.valor, v.valor_normalizado, v.principal
from integracao.vw_mapa_estabelecimentos_vinculados b
join core.contatos c on c.estabelecimento_id = b.estabelecimento_id and c.principal
cross join lateral (
    values
        ('EMAIL', nullif(trim(b.email), ''), lower(nullif(trim(b.email), '')), true),
        ('TELEFONE', nullif(trim(b.telefone), ''), core.apenas_digitos(b.telefone), false),
        ('TELEFONE', nullif(trim(b.telefone_1), ''), core.apenas_digitos(b.telefone_1), true),
        ('WHATSAPP', nullif(trim(b.whatsapp), ''), core.apenas_digitos(b.whatsapp), true)
) as v(tipo, valor, valor_normalizado, principal)
where v.valor is not null
on conflict (contato_id, tipo, valor_normalizado) do nothing;

insert into integracao.referencias_origem (
    estabelecimento_id, sistema, tipo_entidade, identificador_externo
)
select
    b.estabelecimento_id,
    'MAPA_CLIENTES_LEGADO',
    'CLIENTE',
    b.cliente_id::text
from integracao.vw_mapa_estabelecimentos_vinculados b
where b.cliente_id is not null
on conflict (sistema, tipo_entidade, identificador_externo) do update
set estabelecimento_id = excluded.estabelecimento_id;

-- Regra objetiva: CNAEs de criação de camarões. A classificação continua
-- auditável e pode ser substituída pela equipe comercial no CRM.
insert into core.estabelecimento_categorias (
    estabelecimento_id, categoria_id, fonte, confianca, principal
)
select
    ec.estabelecimento_id,
    cat.categoria_id,
    'REGRA_CNAE_INICIAL',
    'ALTA',
    true
from core.estabelecimento_cnaes ec
join core.categorias_clientes cat on cat.codigo = 'CARCINICULTOR'
where ec.cnae_codigo in ('321302', '322102')
on conflict (estabelecimento_id, categoria_id) do update
set confianca = excluded.confianca,
    principal = excluded.principal;

-- Contas são criadas como potenciais; não se chama uma empresa de cliente só
-- porque consta na fonte do mapa.
insert into crm.contas (estabelecimento_id, estagio, origem)
select estabelecimento_id, 'POTENCIAL', 'MAPA_CLIENTES'
from core.estabelecimentos
where origem_principal = 'MAPA_CLIENTES'
on conflict (estabelecimento_id) do nothing;

-- Observações comerciais pertencem ao CRM e não devem permanecer achatadas na
-- tabela geográfica. A origem mantém o texto importado distinguível de notas novas.
insert into crm.notas_conta (conta_id, conteudo, origem)
select
    c.conta_id,
    trim(b.observacoes_comerciais),
    'IMPORTACAO_MAPA'
from integracao.vw_mapa_estabelecimentos_vinculados b
join crm.contas c on c.estabelecimento_id = b.estabelecimento_id
where nullif(trim(b.observacoes_comerciais), '') is not null
on conflict (conta_id, origem, conteudo_hash) do nothing;

-- Consulta estável para o aplicativo de mapa. Ela exibe a coordenada atual e
-- deixa explícita sua qualidade para a interface nunca tratá-la como certeza.
create or replace view mapa_clientes.vw_clientes_mapa
with (security_invoker = true)
as
select
    e.estabelecimento_id as cliente_id,
    e.cnpj_normalizado,
    e.razao_social,
    e.nome_fantasia,
    e.situacao_cadastral,
    e.porte,
    a.logradouro,
    a.bairro,
    a.municipio,
    a.uf,
    a.cep_normalizado as cep,
    l.latitude,
    l.longitude,
    l.qualidade as localizacao_status,
    l.fonte as localizacao_fonte,
    l.precisao_m as localizacao_precisao_m,
    cat.codigo as categoria_codigo,
    cat.nome as categoria,
    c.conta_id,
    c.estagio as estagio_comercial
from core.estabelecimentos e
left join core.enderecos a
    on a.estabelecimento_id = e.estabelecimento_id and a.principal
left join core.localizacoes l
    on l.estabelecimento_id = e.estabelecimento_id and l.atual
left join core.estabelecimento_categorias ec
    on ec.estabelecimento_id = e.estabelecimento_id and ec.principal
left join core.categorias_clientes cat on cat.categoria_id = ec.categoria_id
left join crm.contas c on c.estabelecimento_id = e.estabelecimento_id;

create or replace view mapa_clientes.vw_fila_classificacao
with (security_invoker = true)
as
select
    e.estabelecimento_id,
    e.cnpj_normalizado,
    coalesce(e.nome_fantasia, e.razao_social) as nome,
    a.municipio,
    a.uf,
    string_agg(cn.cnae_codigo, ', ' order by cn.cnae_codigo) as cnaes
from core.estabelecimentos e
left join core.enderecos a
    on a.estabelecimento_id = e.estabelecimento_id and a.principal
left join core.estabelecimento_cnaes cn on cn.estabelecimento_id = e.estabelecimento_id
where not exists (
    select 1
    from core.estabelecimento_categorias ec
    where ec.estabelecimento_id = e.estabelecimento_id
      and ec.principal
)
group by e.estabelecimento_id, e.cnpj_normalizado, e.nome_fantasia, e.razao_social, a.municipio, a.uf;

-- Não existe acesso público aos dados empresariais, geográficos ou comerciais.
revoke all on schema core, crm, integracao from public;
revoke all on all tables in schema core, crm, integracao from public, anon;
revoke all on all tables in schema mapa_clientes from anon;
grant usage on schema core, crm, integracao, mapa_clientes to authenticated, service_role;
grant all privileges on all tables in schema core, crm, integracao, mapa_clientes to service_role;

alter table core.empresas enable row level security;
alter table core.estabelecimentos enable row level security;
alter table core.cnaes enable row level security;
alter table core.estabelecimento_cnaes enable row level security;
alter table core.enderecos enable row level security;
alter table core.localizacoes enable row level security;
alter table core.contatos enable row level security;
alter table core.canais_contato enable row level security;
alter table core.categorias_clientes enable row level security;
alter table core.estabelecimento_categorias enable row level security;
alter table crm.contas enable row level security;
alter table crm.oportunidades enable row level security;
alter table crm.viagens enable row level security;
alter table crm.viagem_participantes enable row level security;
alter table crm.visitas enable row level security;
alter table crm.necessidades enable row level security;
alter table crm.despesas_viagem enable row level security;
alter table crm.notas_conta enable row level security;
alter table integracao.referencias_origem enable row level security;
alter table integracao.eventos_outbox enable row level security;
alter table mapa_clientes.lotes_importacao enable row level security;
alter table mapa_clientes.registros_origem enable row level security;
alter table mapa_clientes.geocodificacoes enable row level security;

commit;
