-- ============================================================================
-- HISTÓRICO E REGRA ENTRE SCHEMAS
--
-- Histórico: guarda antes/depois de cada alteração relevante.
-- Regra: somente ponto confirmado em campo, com coordenadas, torna a empresa
-- CLIENTE. Ponto aproximado, pendente ou ambíguo mantém a empresa como LEAD.
-- Execute após os três schemas principais.
-- ============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Histórico único e simples para auditoria do ecossistema
-- -----------------------------------------------------------------------------

create table if not exists cadastro.historico (
    historico_id                uuid primary key default gen_random_uuid(),
    schema_origem               text not null,
    tabela_origem               text not null,
    registro_id                 uuid not null,
    acao                        text not null,
    dados_antes                 jsonb,
    dados_depois                jsonb,
    usuario_id                  uuid references auth.users(id) on delete set null,
    origem_evento               text not null,
    ocorrido_em                 timestamptz not null default now(),
    constraint historico_acao_check
        check (acao in ('CRIACAO', 'ALTERACAO', 'EXCLUSAO')),
    constraint historico_origem_evento_check
        check (origem_evento in ('USUARIO', 'SISTEMA'))
);

comment on table cadastro.historico is
'Auditoria central. Registra o que mudou, antes/depois, data e autor sem duplicar tabelas de histórico.';
comment on column cadastro.historico.dados_antes is
'Fotografia JSON do registro antes da alteração. Vazio em uma criação.';
comment on column cadastro.historico.dados_depois is
'Fotografia JSON do registro depois da alteração. Vazio em uma exclusão.';
comment on column cadastro.historico.origem_evento is
'USUARIO quando existe sessão autenticada; SISTEMA para importações e automações.';

create index if not exists historico_registro_data_idx
    on cadastro.historico (schema_origem, tabela_origem, registro_id, ocorrido_em desc);

create index if not exists historico_ocorrido_em_idx
    on cadastro.historico (ocorrido_em desc);

revoke all on cadastro.historico from public, anon, authenticated;
grant all privileges on cadastro.historico to service_role;
alter table cadastro.historico enable row level security;

create or replace function cadastro.registrar_historico()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, cadastro
as $$
declare
    v_antes jsonb;
    v_depois jsonb;
    v_registro_id uuid;
    v_acao text;
    v_usuario_id uuid := auth.uid();
begin
    if tg_op = 'INSERT' then
        v_acao := 'CRIACAO';
        v_depois := to_jsonb(new);
        v_registro_id := (v_depois ->> tg_argv[0])::uuid;
    elsif tg_op = 'UPDATE' then
        v_acao := 'ALTERACAO';
        v_antes := to_jsonb(old);
        v_depois := to_jsonb(new);
        v_registro_id := (v_depois ->> tg_argv[0])::uuid;
    else
        v_acao := 'EXCLUSAO';
        v_antes := to_jsonb(old);
        v_registro_id := (v_antes ->> tg_argv[0])::uuid;
    end if;

    if v_registro_id is null then
        raise exception 'Não foi possível identificar o registro para auditoria.';
    end if;

    insert into cadastro.historico (
        schema_origem,
        tabela_origem,
        registro_id,
        acao,
        dados_antes,
        dados_depois,
        usuario_id,
        origem_evento
    ) values (
        tg_table_schema,
        tg_table_name,
        v_registro_id,
        v_acao,
        v_antes,
        v_depois,
        v_usuario_id,
        case when v_usuario_id is null then 'SISTEMA' else 'USUARIO' end
    );

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$$;

revoke all on function cadastro.registrar_historico() from public;

-- -----------------------------------------------------------------------------
-- Regra comercial mapa -> CRM
-- -----------------------------------------------------------------------------

-- Compatibilidade para quem executou os três schemas antes desta versão.
-- O identificador do usuário antigo é suficiente para preservar uma confirmação
-- histórica até o operador ser criado no novo Supabase.
alter table mapa.pontos
    add column if not exists confirmado_por_legado text;

alter table mapa.pontos
    drop constraint if exists pontos_confirmado_tem_registro_check;

alter table mapa.pontos
    add constraint pontos_confirmado_tem_registro_check check (
        status_confirmacao <> 'CONFIRMADO_CAMPO'
        or (
            confirmado_em is not null
            and (
                confirmado_por is not null
                or nullif(trim(confirmado_por_legado), '') is not null
            )
        )
    );

create or replace function mapa.sincronizar_relacionamento_crm()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, mapa, crm
as $$
declare
    v_tipo text;
begin
    -- A única condição que promove para CLIENTE é um ponto realmente confirmado.
    v_tipo := case
        when new.status_confirmacao = 'CONFIRMADO_CAMPO'
         and new.latitude is not null
         and new.longitude is not null
         and new.confirmado_em is not null
         and (
             new.confirmado_por is not null
             or nullif(trim(new.confirmado_por_legado), '') is not null
         )
            then 'CLIENTE'
        else 'LEAD'
    end;

    insert into crm.relacionamentos (
        empresa_id,
        tipo,
        origem,
        cliente_desde
    ) values (
        new.empresa_id,
        v_tipo,
        'MAPA',
        case when v_tipo = 'CLIENTE' then now() else null end
    )
    on conflict (empresa_id) do update
    set tipo = excluded.tipo,
        -- Nunca apaga a primeira data em que a empresa se tornou cliente.
        cliente_desde = case
            when excluded.tipo = 'CLIENTE'
                then coalesce(crm.relacionamentos.cliente_desde, now())
            else crm.relacionamentos.cliente_desde
        end,
        atualizado_em = now();

    return new;
end;
$$;

revoke all on function mapa.sincronizar_relacionamento_crm() from public;

-- A auditoria fica em gatilhos separados. Os nomes ordenados deixam o histórico
-- ser escrito antes da sincronização comercial do mesmo evento.
drop trigger if exists auditar_empresa on cadastro.empresas;
create trigger auditar_empresa
after insert or update or delete on cadastro.empresas
for each row execute function cadastro.registrar_historico('empresa_id');

drop trigger if exists auditar_ponto on mapa.pontos;
create trigger auditar_ponto
after insert or update or delete on mapa.pontos
for each row execute function cadastro.registrar_historico('ponto_id');

drop trigger if exists auditar_evidencia_ponto on mapa.evidencias_ponto;
create trigger auditar_evidencia_ponto
after insert or update or delete on mapa.evidencias_ponto
for each row execute function cadastro.registrar_historico('evidencia_id');

drop trigger if exists auditar_relacionamento on crm.relacionamentos;
create trigger auditar_relacionamento
after insert or update or delete on crm.relacionamentos
for each row execute function cadastro.registrar_historico('relacionamento_id');

drop trigger if exists auditar_viagem on crm.viagens;
create trigger auditar_viagem
after insert or update or delete on crm.viagens
for each row execute function cadastro.registrar_historico('viagem_id');

drop trigger if exists auditar_visita on crm.visitas;
create trigger auditar_visita
after insert or update or delete on crm.visitas
for each row execute function cadastro.registrar_historico('visita_id');

drop trigger if exists auditar_necessidade on crm.necessidades;
create trigger auditar_necessidade
after insert or update or delete on crm.necessidades
for each row execute function cadastro.registrar_historico('necessidade_id');

drop trigger if exists auditar_despesa on crm.despesas;
create trigger auditar_despesa
after insert or update or delete on crm.despesas
for each row execute function cadastro.registrar_historico('despesa_id');

drop trigger if exists auditar_anexo on crm.anexos;
create trigger auditar_anexo
after insert or update or delete on crm.anexos
for each row execute function cadastro.registrar_historico('anexo_id');

drop trigger if exists sincronizar_relacionamento_crm on mapa.pontos;

create trigger sincronizar_relacionamento_crm
after insert or update of status_confirmacao, latitude, longitude
on mapa.pontos
for each row
execute function mapa.sincronizar_relacionamento_crm();

commit;
