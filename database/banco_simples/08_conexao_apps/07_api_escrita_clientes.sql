begin;

-- ==============================================================================
-- 1. CADASTRAR CLIENTE (NOVO PONTO MAPA)
-- ==============================================================================
create or replace function api.cadastrar_cliente(p_dados jsonb)
returns uuid
language plpgsql
security invoker
as $$
declare
    v_empresa_id uuid;
begin
    insert into cadastro.empresas (
        razao_social, nome_fantasia, cnpj,
        contato_nome, telefone, whatsapp, email,
        uf, municipio, bairro, cep, logradouro,
        origem, criado_por
    ) values (
        p_dados->>'razao_social', p_dados->>'nome_fantasia', p_dados->>'cnpj',
        p_dados->>'contato_nome', p_dados->>'telefone', p_dados->>'whatsapp', p_dados->>'email',
        p_dados->>'uf', p_dados->>'municipio', p_dados->>'bairro', p_dados->>'cep', p_dados->>'logradouro',
        coalesce(p_dados->>'localizacao_fonte', 'APP_MAPA'), auth.uid()
    ) returning empresa_id into v_empresa_id;

    if p_dados->>'latitude' is not null and p_dados->>'longitude' is not null then
        insert into mapa.pontos (
            empresa_id, latitude, longitude,
            fonte_localizacao, precisao_m, observacao, status_confirmacao,
            criado_por
        ) values (
            v_empresa_id, (p_dados->>'latitude')::numeric, (p_dados->>'longitude')::numeric,
            coalesce(p_dados->>'localizacao_fonte', 'APP_MAPA'),
            (p_dados->>'localizacao_precisao_m')::numeric,
            p_dados->>'localizacao_observacao', 'CONFIRMADO_CAMPO',
            auth.uid()
        );
    end if;

    return v_empresa_id;
end;
$$;

-- ==============================================================================
-- 2. ATUALIZAR COMUNICACAO E CADASTRO (EDIÇÃO)
-- ==============================================================================
create or replace function api.atualizar_comunicacao(p_cliente_id uuid, p_dados jsonb)
returns void
language plpgsql
security invoker
as $$
begin
    update cadastro.empresas
    set
        contato_nome = coalesce(p_dados->>'contato_nome', contato_nome),
        telefone = coalesce(p_dados->>'telefone', telefone),
        whatsapp = coalesce(p_dados->>'whatsapp', whatsapp),
        email = coalesce(p_dados->>'email', email),
        razao_social = coalesce(p_dados->>'razao_social', razao_social),
        nome_fantasia = coalesce(p_dados->>'nome_fantasia', nome_fantasia),
        cnpj = coalesce(p_dados->>'cnpj', cnpj),
        uf = coalesce(p_dados->>'uf', uf),
        municipio = coalesce(p_dados->>'municipio', municipio),
        bairro = coalesce(p_dados->>'bairro', bairro),
        cep = coalesce(p_dados->>'cep', cep),
        logradouro = coalesce(p_dados->>'logradouro', logradouro),
        atualizado_em = now()
    where empresa_id = p_cliente_id;
end;
$$;

-- ==============================================================================
-- 3. CONFIRMAR LOCALIZACAO (MAPA / CHECK-IN)
-- ==============================================================================
create or replace function api.confirmar_localizacao(
    p_cliente_id uuid,
    p_latitude float8,
    p_longitude float8,
    p_fonte text,
    p_precisao_m float8,
    p_observacao text
)
returns void
language plpgsql
security invoker
as $$
begin
    insert into mapa.pontos (
        empresa_id, latitude, longitude,
        fonte_localizacao, precisao_m, observacao, status_confirmacao,
        atualizado_em, confirmado_em, confirmado_por, criado_por
    ) values (
        p_cliente_id, p_latitude, p_longitude,
        p_fonte, p_precisao_m, p_observacao, 'CONFIRMADO_CAMPO',
        now(), now(), auth.uid(), auth.uid()
    )
    on conflict (empresa_id) do update set
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        fonte_localizacao = excluded.fonte_localizacao,
        precisao_m = excluded.precisao_m,
        observacao = coalesce(excluded.observacao, mapa.pontos.observacao),
        status_confirmacao = 'CONFIRMADO_CAMPO',
        atualizado_em = now(),
        confirmado_em = now(),
        confirmado_por = auth.uid();
end;
$$;

-- ==============================================================================
-- 4. ROTAS (MAPA)
-- ==============================================================================
create or replace function api.criar_rota_visita(
    p_titulo text,
    p_data_planejada date,
    p_observacao text
)
returns uuid
language plpgsql
security invoker
as $$
declare
    v_viagem_id uuid;
begin
    insert into crm.viagens (
        titulo, inicio_em, observacao, status,
        criado_por
    ) values (
        coalesce(p_titulo, 'Rota de Visitas'), p_data_planejada, p_observacao, 'PLANEJADA',
        auth.uid()
    ) returning viagem_id into v_viagem_id;
    return v_viagem_id;
end;
$$;

create or replace function api.definir_paradas_rota(
    p_rota_id uuid,
    p_paradas jsonb
)
returns void
language plpgsql
security invoker
as $$
declare
    item jsonb;
begin
    delete from crm.visitas where viagem_id = p_rota_id and status = 'PLANEJADA';

    for item in select * from jsonb_array_elements(p_paradas)
    loop
        insert into crm.visitas (
            viagem_id, empresa_id, status, agendada_para,
            criado_por
        ) values (
            p_rota_id, (item->>'cliente_id')::uuid, 'PLANEJADA', null,
            auth.uid()
        );
    end loop;
end;
$$;

commit;