begin;

-- ==============================================================================
-- 1. PERMISSÕES DA TABELA DE EVENTOS
-- ==============================================================================
grant select, insert, update, delete on table crm.eventos to authenticated, service_role;
grant usage on schema crm to authenticated, service_role;

alter table crm.eventos enable row level security;
drop policy if exists eventos_le_todos on crm.eventos;
create policy eventos_le_todos on crm.eventos for select to authenticated using (true);

drop policy if exists eventos_insere on crm.eventos;
create policy eventos_insere on crm.eventos for insert to authenticated with check (auth.uid() is not null);

drop policy if exists eventos_atualiza on crm.eventos;
create policy eventos_atualiza on crm.eventos for update to authenticated using (auth.uid() is not null);

drop policy if exists eventos_deleta on crm.eventos;
create policy eventos_deleta on crm.eventos for delete to authenticated using (auth.uid() is not null);

-- Permissões para despesas
grant select, insert, update, delete on table crm.despesas to authenticated, service_role;
alter table crm.despesas enable row level security;
drop policy if exists despesas_le_todos on crm.despesas;
create policy despesas_le_todos on crm.despesas for select to authenticated using (true);
drop policy if exists despesas_insere on crm.despesas;
create policy despesas_insere on crm.despesas for insert to authenticated with check (auth.uid() is not null);
drop policy if exists despesas_atualiza on crm.despesas;
create policy despesas_atualiza on crm.despesas for update to authenticated using (auth.uid() is not null);
drop policy if exists despesas_deleta on crm.despesas;
create policy despesas_deleta on crm.despesas for delete to authenticated using (auth.uid() is not null);

-- E não esquecer de garantir acesso às views
grant select, insert, update, delete on api.vw_eventos to authenticated, service_role;
grant select, insert, update, delete on api.vw_despesas_eventos to authenticated, service_role;

-- ==============================================================================
-- 2. CRIAR EVENTO
-- ==============================================================================
create or replace function api.criar_evento(
    p_nome text,
    p_local text,
    p_data_inicio date,
    p_data_fim date,
    p_tipo_participacao text,
    p_notas text
)
returns jsonb
language plpgsql
security invoker
as $$
declare
    v_evento_id uuid;
begin
    insert into crm.eventos (
        nome, local, data_inicio, data_fim,
        tipo_participacao, notas_estrategicas, status, criado_por
    ) values (
        p_nome, p_local, p_data_inicio, p_data_fim,
        p_tipo_participacao, p_notas, 'PLANEJADO', auth.uid()
    ) returning evento_id into v_evento_id;

    return jsonb_build_object('evento_id', v_evento_id);
end;
$$;

-- ==============================================================================
-- 3. CRIAR DESPESA DE EVENTO
-- ==============================================================================
create or replace function api.criar_despesa_evento(
    p_evento_id uuid,
    p_categoria text,
    p_centro_custo text,
    p_valor numeric,
    p_estabelecimento text,
    p_descricao text,
    p_data_despesa date
)
returns void
language plpgsql
security invoker
as $$
begin
    insert into crm.despesas (
        evento_id, categoria, valor,
        observacao, ocorrido_em, criado_por
    ) values (
        p_evento_id, coalesce(p_categoria, 'Outros'), p_valor,
        coalesce(p_estabelecimento, '') || ' - ' || coalesce(p_descricao, ''),
        coalesce(p_data_despesa, current_date), auth.uid()
    );
end;
$$;

-- ==============================================================================
-- 4. ATUALIZAR EVENTO MIDIA
-- ==============================================================================
create or replace function api.atualizar_evento_midia(
    p_evento_id uuid,
    p_links jsonb,
    p_anexos jsonb
)
returns void
language plpgsql
security invoker
as $$
begin
    update crm.eventos
    set
        links = coalesce(p_links, links),
        anexos = coalesce(p_anexos, anexos),
        atualizado_em = now()
    where evento_id = p_evento_id;
end;
$$;


-- ==============================================================================
-- 5. ATUALIZAR E DELETAR DESPESAS
-- ==============================================================================
create or replace function api.atualizar_despesa_evento(
    p_despesa_id uuid,
    p_categoria text,
    p_valor numeric,
    p_estabelecimento text,
    p_descricao text,
    p_data_despesa date,
    p_centro_custo text
)
returns void
language plpgsql
security invoker
as $$
begin
    update crm.despesas
    set
        categoria = coalesce(p_categoria, categoria),
        valor = coalesce(p_valor, valor),
        observacao = coalesce(p_estabelecimento, '') || ' - ' || coalesce(p_descricao, observacao),
        ocorrido_em = coalesce(p_data_despesa, ocorrido_em)
    where despesa_id = p_despesa_id;
end;
$$;

create or replace function api.deletar_despesa_evento(p_despesa_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
    delete from crm.despesas where despesa_id = p_despesa_id;
end;
$$;

commit;

