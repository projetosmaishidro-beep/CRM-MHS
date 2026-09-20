-- ============================================================================
-- PROXY DE EVENTOS E DESPESAS NO SCHEMA API
-- O schema 'api' já está exposto e funcionando. Criamos views e funções
-- aqui para que o front-end acesse eventos e despesas sem precisar
-- expor o schema 'crm' diretamente.
-- ============================================================================

begin;

-- Garante GRANTs no crm para que as views security_invoker funcionem
grant select, insert, update, delete on crm.eventos to authenticated;
grant select, insert, update, delete on crm.evento_participantes to authenticated;
grant select, insert, update, delete on crm.despesas to authenticated;

-- Colunas extras para eventos (links e contatos)
alter table crm.eventos
    add column if not exists links jsonb default '[]'::jsonb,
    add column if not exists contatos jsonb default '[]'::jsonb,
    add column if not exists participantes jsonb default '[]'::jsonb;

-- Colunas extras que o front-end precisa e que podem não existir ainda
alter table crm.despesas
    alter column viagem_id drop not null,
    add column if not exists estabelecimento text,
    add column if not exists descricao text,
    add column if not exists data_despesa date default current_date,
    add column if not exists criado_por uuid references auth.users(id) on delete set null;

-- Policies para despesas (podem não existir)
drop policy if exists "Equipe pode ver despesas" on crm.despesas;
create policy "Equipe pode ver despesas"
    on crm.despesas for select to authenticated using (true);

drop policy if exists "Equipe pode gerenciar despesas" on crm.despesas;
create policy "Equipe pode gerenciar despesas"
    on crm.despesas for all to authenticated
    using (true) with check (true);


-- Colunas que podem não existir em crm.eventos (caso tenha sido criada por script antigo)
alter table crm.eventos
    add column if not exists tipo_participacao text not null default 'PARTICIPANTE',
    add column if not exists notas_estrategicas text,
    add column if not exists links jsonb default '[]'::jsonb,
    add column if not exists anexos jsonb default '[]'::jsonb;

-- Constraints que podem não existir
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'eventos_tipo_participacao_check'
          and conrelid = 'crm.eventos'::regclass
    ) then
        alter table crm.eventos
            add constraint eventos_tipo_participacao_check
            check (tipo_participacao in ('EXPOSITOR', 'PARTICIPANTE'));
    end if;
end;
$$;


-- ============================
-- VIEWS DE LEITURA NO SCHEMA API
-- ============================

drop view if exists api.vw_eventos cascade;
create or replace view api.vw_eventos
with (security_invoker = true)
as
select
    evento_id,
    nome,
    local,
    data_inicio,
    data_fim,
    tipo_participacao,
    status,
    notas_estrategicas,
    links,
    contatos,
    participantes,
    anexos,
    criado_por,
    criado_em,
    atualizado_em
from crm.eventos;

grant select, insert, update, delete on api.vw_eventos to authenticated;

comment on view api.vw_eventos is 'Leitura de eventos para o front-end.';

create or replace view api.vw_despesas_eventos
with (security_invoker = true)
as
select
    despesa_id,
    viagem_id,
    evento_id,
    categoria,
    valor,
    ocorrido_em,
    observacao,
    estabelecimento,
    descricao,
    data_despesa,
    centro_custo,
    criado_por,
    criado_em
from crm.despesas
where evento_id is not null;

comment on view api.vw_despesas_eventos is 'Despesas vinculadas a eventos.';


-- ============================
-- RPCs DE ESCRITA NO SCHEMA API
-- ============================

create or replace function api.criar_evento(
    p_nome text,
    p_local text,
    p_data_inicio text,
    p_data_fim text,
    p_tipo_participacao text default 'PARTICIPANTE',
    p_notas text default null
)
returns json
language plpgsql
security definer
set search_path = pg_catalog, crm
as $$
declare
    v_row crm.eventos%rowtype;
begin
    insert into crm.eventos (
        nome, local, data_inicio, data_fim,
        tipo_participacao, notas_estrategicas,
        status, criado_por
    ) values (
        p_nome,
        p_local,
        p_data_inicio::timestamptz,
        p_data_fim::timestamptz,
        coalesce(upper(p_tipo_participacao), 'PARTICIPANTE'),
        p_notas,
        'PLANEJADO',
        auth.uid()
    ) returning * into v_row;

    return json_build_object(
        'evento_id', v_row.evento_id,
        'nome', v_row.nome,
        'status', v_row.status
    );
end;
$$;

create or replace function api.atualizar_evento_midia(
    p_evento_id uuid,
    p_links jsonb default null,
    p_anexos jsonb default null
)
returns json
language plpgsql
security definer
set search_path = pg_catalog, crm
as $$
declare
    v_row crm.eventos%rowtype;
begin
    update crm.eventos
    set
        links = coalesce(p_links, links),
        anexos = coalesce(p_anexos, anexos),
        atualizado_em = now()
    where evento_id = p_evento_id
    returning * into v_row;

    if not found then
        raise exception 'Evento não encontrado';
    end if;

    return json_build_object(
        'evento_id', v_row.evento_id,
        'links', v_row.links,
        'anexos', v_row.anexos
    );
end;
$$;

create or replace function api.criar_despesa_evento(
    p_evento_id uuid,
    p_categoria text,
    p_valor numeric,
    p_estabelecimento text default null,
    p_descricao text default null,
    p_centro_custo text default null,
    p_data_despesa date default current_date
)
returns json
language plpgsql
security definer
set search_path = pg_catalog, crm
as $$
declare
    v_row crm.despesas%rowtype;
begin
    insert into crm.despesas (
        evento_id, categoria, valor,
        estabelecimento, descricao, centro_custo,
        data_despesa, criado_por, ocorrido_em
    ) values (
        p_evento_id,
        p_categoria,
        p_valor,
        p_estabelecimento,
        p_descricao,
        p_centro_custo,
        p_data_despesa,
        auth.uid(),
        p_data_despesa
    ) returning * into v_row;

    return json_build_object(
        'despesa_id', v_row.despesa_id,
        'evento_id', v_row.evento_id
    );
end;
$$;


-- ============================
-- PERMISSÕES
-- ============================

revoke all on api.vw_eventos from public, anon;
revoke all on api.vw_despesas_eventos from public, anon;
grant select, insert, update, delete on api.vw_eventos to authenticated, service_role;
grant select, insert, update, delete on api.vw_despesas_eventos to authenticated, service_role;

revoke all on function api.criar_evento from public, anon;
revoke all on function api.criar_despesa_evento from public, anon;
grant execute on function api.criar_evento to authenticated;
grant execute on function api.atualizar_evento_midia to authenticated;
grant execute on function api.criar_despesa_evento to authenticated;

notify pgrst, 'reload schema';

commit;

-- VERIFICAÇÃO
select * from api.vw_eventos limit 1;
