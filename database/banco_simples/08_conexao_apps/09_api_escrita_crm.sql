begin;

-- ==============================================================================
-- 1. PERMISSÕES PARA TABELAS SECUNDÁRIAS DO CRM
-- ==============================================================================
grant select, insert, update, delete on table crm.visitas to authenticated, service_role;
grant select, insert, update, delete on table crm.necessidades to authenticated, service_role;
grant select, insert, update, delete on table crm.relacionamentos to authenticated, service_role;

-- RLS: Visitas
drop policy if exists visitas_le_todos on crm.visitas;
create policy visitas_le_todos on crm.visitas for select to authenticated using (true);
drop policy if exists visitas_insere on crm.visitas;
create policy visitas_insere on crm.visitas for insert to authenticated with check (auth.uid() is not null);
drop policy if exists visitas_atualiza on crm.visitas;
create policy visitas_atualiza on crm.visitas for update to authenticated using (auth.uid() is not null);
drop policy if exists visitas_deleta on crm.visitas;
create policy visitas_deleta on crm.visitas for delete to authenticated using (auth.uid() is not null);

-- RLS: Necessidades
drop policy if exists necessidades_le_todos on crm.necessidades;
create policy necessidades_le_todos on crm.necessidades for select to authenticated using (true);
drop policy if exists necessidades_insere on crm.necessidades;
create policy necessidades_insere on crm.necessidades for insert to authenticated with check (auth.uid() is not null);
drop policy if exists necessidades_atualiza on crm.necessidades;
create policy necessidades_atualiza on crm.necessidades for update to authenticated using (auth.uid() is not null);
drop policy if exists necessidades_deleta on crm.necessidades;
create policy necessidades_deleta on crm.necessidades for delete to authenticated using (auth.uid() is not null);

-- ==============================================================================
-- 2. VISITAS
-- ==============================================================================
drop function if exists api.criar_visita cascade;
create or replace function api.criar_visita(p_dados jsonb)
returns jsonb
language plpgsql
security invoker
as $$
declare
    v_visita_id uuid;
    cat text;
    p_cliente_id uuid;
    p_observacao text;
    p_necessidades jsonb;
begin
    p_cliente_id := (p_dados->>'clientId')::uuid;
    p_observacao := coalesce(p_dados->>'notes', '');
    p_necessidades := coalesce(p_dados->'needs', '[]'::jsonb);

    -- Insere a visita como REALIZADA
    insert into crm.visitas (
        empresa_id, status, realizada_em, observacao, criado_por
    ) values (
        p_cliente_id, 'REALIZADA', now(), p_observacao, auth.uid()
    ) returning visita_id into v_visita_id;

    -- Processa array de necessidades
    if jsonb_typeof(p_necessidades) = 'array' then
        for cat in select jsonb_array_elements_text(p_necessidades)
        loop
            insert into crm.necessidades (
                empresa_id, visita_id, categoria, descricao, prioridade
            ) values (
                p_cliente_id, v_visita_id, cat, 'Identificado em visita', 'MEDIA'
            );
        end loop;
    end if;

    return jsonb_build_object('visita_id', v_visita_id);
end;
$$;

-- ==============================================================================
-- 3. NECESSIDADES
-- ==============================================================================
drop function if exists api.criar_necessidade cascade;
create or replace function api.criar_necessidade(p_dados jsonb)
returns jsonb
language plpgsql
security invoker
as $$
declare
    v_necessidade_id uuid;
    p_cliente_id uuid;
    p_categoria text;
    p_descricao text;
    p_prioridade text;
begin
    p_cliente_id := (p_dados->>'clientId')::uuid;
    p_categoria := coalesce(p_dados->>'category', 'Outro');
    p_descricao := coalesce(p_dados->>'description', '');
    p_prioridade := coalesce(p_dados->>'priority', 'MEDIA');

    insert into crm.necessidades (
        empresa_id, categoria, descricao, prioridade
    ) values (
        p_cliente_id, p_categoria, p_descricao, p_prioridade
    ) returning necessidade_id into v_necessidade_id;

    return jsonb_build_object('necessidade_id', v_necessidade_id);
end;
$$;

-- ==============================================================================
-- 4. VIAGENS
-- ==============================================================================
drop function if exists api.atualizar_viagem cascade;
create or replace function api.atualizar_viagem(p_viagem_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security invoker
as $$
begin
    update crm.viagens
    set
        titulo = coalesce(p_dados->>'name', titulo),
        status = coalesce(upper(p_dados->>'status'), status),
        observacao = coalesce(p_dados->>'notes', observacao),
        km_inicial = coalesce((p_dados->>'startKm')::numeric, km_inicial),
        km_final = coalesce((p_dados->>'endKm')::numeric, km_final),
        atualizado_em = now()
    where viagem_id = p_viagem_id;

    return jsonb_build_object('viagem_id', p_viagem_id);
end;
$$;

drop function if exists api.excluir_viagem cascade;
create or replace function api.excluir_viagem(p_viagem_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
    delete from crm.viagens where viagem_id = p_viagem_id;
end;
$$;

-- ==============================================================================
-- 5. CLIENTES (ARQUIVAR)
-- ==============================================================================
drop function if exists api.arquivar_cliente cascade;
create or replace function api.arquivar_cliente(p_cliente_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
    update crm.relacionamentos
    set status = 'ARQUIVADO', atualizado_em = now()
    where empresa_id = p_cliente_id;
end;
$$;


-- ==============================================================================
-- 6. DESPESAS GERAIS (VIAGEM E EVENTOS)
-- ==============================================================================
drop function if exists api.criar_despesa cascade;
create or replace function api.criar_despesa(p_dados jsonb)
returns jsonb
language plpgsql
security invoker
as $
declare
    v_despesa_id uuid;
begin
    insert into crm.despesas (
        viagem_id, evento_id, categoria, valor,
        observacao, ocorrido_em, criado_por
    ) values (
        (p_dados->>'tripId')::uuid, (p_dados->>'eventId')::uuid,
        coalesce(p_dados->>'category', 'Outros'),
        coalesce((p_dados->>'amount')::numeric, 0),
        coalesce(p_dados->>'place', '') || ' - ' || coalesce(p_dados->>'notes', ''),
        coalesce((p_dados->>'date')::date, current_date),
        auth.uid()
    ) returning despesa_id into v_despesa_id;
    return jsonb_build_object('despesa_id', v_despesa_id);
end;
$;

drop function if exists api.atualizar_despesa cascade;
create or replace function api.atualizar_despesa(p_despesa_id uuid, p_dados jsonb)
returns void
language plpgsql
security invoker
as $
begin
    update crm.despesas
    set
        categoria = coalesce(p_dados->>'category', categoria),
        valor = coalesce((p_dados->>'amount')::numeric, valor),
        observacao = coalesce(p_dados->>'place', '') || ' - ' || coalesce(p_dados->>'notes', observacao),
        ocorrido_em = coalesce((p_dados->>'date')::date, ocorrido_em)
    where despesa_id = p_despesa_id;
end;
$;

drop function if exists api.excluir_despesa cascade;
create or replace function api.excluir_despesa(p_despesa_id uuid)
returns void
language plpgsql
security invoker
as $
begin
    delete from crm.despesas where despesa_id = p_despesa_id;
end;
$;

commit;