-- ============================================================================
-- PROPOSTAS MHS - GRUPOS COMERCIAIS E SNAPSHOTS COMPLETOS
-- Execute apos 20260927_0007_propostas_mhs_operacoes.sql.
-- Aditiva e segura para bancos que ja receberam as migracoes anteriores.
-- ============================================================================

begin;

create table if not exists propostas_mhs.propostas_grupos (
  proposta_grupo_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  ordem integer not null default 1,
  titulo text not null,
  descricao text,
  modalidade text not null default 'COMPOSTOS',
  quantidade numeric(19,6) not null default 1,
  unidade text not null default 'CJ',
  impostos_percentual numeric(9,6) not null default 0,
  margem_operacional_percentual numeric(9,6) not null default 0,
  lucro_percentual numeric(9,6) not null default 0,
  comissao_percentual numeric(9,6) not null default 0,
  financeiro_mensal_percentual numeric(9,6) not null default 0,
  prazo_medio_dias numeric(12,4) not null default 0,
  modo_preco text not null default 'SOMA_ITENS',
  preco_manual_total numeric(19,4),
  justificativa_preco_manual text,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint proposta_grupo_ordem_uidx unique (proposta_id, ordem),
  constraint proposta_grupo_modalidade_check check (modalidade in ('PRODUTOS', 'SERVICOS', 'COMPOSTOS', 'MISTO')),
  constraint proposta_grupo_quantidade_check check (quantidade > 0),
  constraint proposta_grupo_percentuais_check check (
    impostos_percentual >= 0 and margem_operacional_percentual >= 0 and lucro_percentual >= 0
    and comissao_percentual >= 0 and financeiro_mensal_percentual >= 0 and prazo_medio_dias >= 0
  ),
  constraint proposta_grupo_preco_check check (
    (modo_preco = 'SOMA_ITENS' and preco_manual_total is null)
    or (modo_preco = 'MANUAL' and preco_manual_total is not null and preco_manual_total >= 0)
  )
);
comment on table propostas_mhs.propostas_grupos is
'Grupos comerciais da proposta. Preserva modalidade, quantidade, memoria de margem e preco manual por conjunto.';

alter table propostas_mhs.propostas_itens
  add column if not exists proposta_grupo_id uuid references propostas_mhs.propostas_grupos(proposta_grupo_id) on delete cascade;
comment on column propostas_mhs.propostas_itens.proposta_grupo_id is
'Grupo comercial ao qual o item pertence. Itens legados sem grupo continuam validos.';

create index if not exists propostas_grupos_proposta_ordem_idx
  on propostas_mhs.propostas_grupos (proposta_id, ordem);
create index if not exists propostas_itens_grupo_ordem_idx
  on propostas_mhs.propostas_itens (proposta_grupo_id, ordem);

alter table propostas_mhs.propostas_grupos enable row level security;
revoke all on propostas_mhs.propostas_grupos from public, anon, authenticated;

drop trigger if exists propostas_grupos_preencher_atualizacao on propostas_mhs.propostas_grupos;
create trigger propostas_grupos_preencher_atualizacao before update on propostas_mhs.propostas_grupos
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists propostas_grupos_auditar on propostas_mhs.propostas_grupos;
create trigger propostas_grupos_auditar after insert or update or delete on propostas_mhs.propostas_grupos
for each row execute function propostas_mhs.registrar_historico_linha('proposta_grupo_id', 'Grupo comercial');

create or replace function propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_snapshot jsonb;
begin
  v_snapshot := propostas_mhs.montar_snapshot_proposta(p_proposta_id);
  return v_snapshot || jsonb_build_object('grupos', coalesce((
    select jsonb_agg(
      to_jsonb(g) || jsonb_build_object('itens', coalesce((
        select jsonb_agg(
          to_jsonb(i) || jsonb_build_object('componentes', coalesce((
            select jsonb_agg(to_jsonb(c) order by c.ordem)
            from propostas_mhs.propostas_itens_composicao c
            where c.proposta_item_id = i.proposta_item_id
          ), '[]'::jsonb))
          order by i.ordem
        )
        from propostas_mhs.propostas_itens i
        where i.proposta_grupo_id = g.proposta_grupo_id
      ), '[]'::jsonb))
      order by g.ordem
    )
    from propostas_mhs.propostas_grupos g
    where g.proposta_id = p_proposta_id
  ), '[]'::jsonb));
end;
$$;

create or replace function propostas_mhs.criar_revisao_proposta(
  p_proposta_id uuid,
  p_tipo text default 'REVISAO',
  p_motivo text default null
)
returns propostas_mhs.propostas_revisoes
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_proposta propostas_mhs.propostas%rowtype;
  v_revisao propostas_mhs.propostas_revisoes%rowtype;
  v_snapshot jsonb;
  v_numero integer;
  v_tipo text;
begin
  select * into v_proposta from propostas_mhs.propostas
  where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  v_tipo := upper(coalesce(p_tipo, 'REVISAO'));
  if v_tipo not in ('PREVIA', 'EMISSAO', 'REVISAO', 'FINAL') then
    raise exception 'Tipo de revisao invalido.' using errcode = '22023';
  end if;

  v_numero := v_proposta.versao_atual + 1;
  v_snapshot := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);

  insert into propostas_mhs.propostas_revisoes (
    proposta_id, numero_revisao, tipo, motivo, status_proposta, valor_cpmv_total,
    valor_proposta, dados_snapshot, hash_integridade, criado_por
  ) values (
    p_proposta_id, v_numero, v_tipo, nullif(trim(p_motivo), ''), v_proposta.status,
    v_proposta.valor_cpmv_total, v_proposta.valor_proposta, v_snapshot,
    md5(v_snapshot::text), auth.uid()
  ) returning * into v_revisao;

  update propostas_mhs.propostas
  set versao_atual = v_numero, atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id;

  perform propostas_mhs.registrar_acao(
    'PROPOSTA', p_proposta_id,
    case when v_tipo in ('EMISSAO', 'FINAL') then 'EMITIDA' else 'REVISADA' end,
    'Revisao ' || v_numero::text || ' criada',
    jsonb_build_object('revisao_id', v_revisao.revisao_id, 'tipo', v_tipo, 'hash_integridade', v_revisao.hash_integridade)
  );
  return v_revisao;
end;
$$;

create or replace function api.detalhar_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  return propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);
end;
$$;

create or replace function api.salvar_grupos_proposta_mhs(p_proposta_id uuid, p_grupos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_grupo jsonb;
  v_item jsonb;
  v_grupo_id uuid;
  v_ordem_grupo integer := 0;
  v_ordem_item integer;
  v_inicio_item integer := 0;
  v_total_itens integer := 0;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_grupos, '[]'::jsonb)) <> 'array' then
    raise exception 'grupos deve ser uma lista.' using errcode = '22023';
  end if;
  if not exists (select 1 from propostas_mhs.propostas where proposta_id = p_proposta_id for update) then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  -- Desvincula antes de substituir os grupos para preservar os itens do rascunho.
  update propostas_mhs.propostas_itens
  set proposta_grupo_id = null
  where proposta_id = p_proposta_id;
  delete from propostas_mhs.propostas_grupos where proposta_id = p_proposta_id;
  v_ordem_item := 0;
  for v_grupo in select value from jsonb_array_elements(p_grupos) loop
    v_ordem_grupo := v_ordem_grupo + 1;
    insert into propostas_mhs.propostas_grupos (
      proposta_id, ordem, titulo, descricao, modalidade, quantidade, unidade,
      impostos_percentual, margem_operacional_percentual, lucro_percentual,
      comissao_percentual, financeiro_mensal_percentual, prazo_medio_dias,
      modo_preco, preco_manual_total, justificativa_preco_manual, criado_por, atualizado_por
    ) values (
      p_proposta_id, coalesce(nullif(v_grupo ->> 'ordem', '')::integer, v_ordem_grupo),
      coalesce(nullif(trim(coalesce(v_grupo ->> 'titulo', v_grupo ->> 'title')), ''), 'Grupo sem titulo'),
      nullif(trim(v_grupo ->> 'descricao'), ''),
      case upper(coalesce(v_grupo ->> 'modalidade', 'COMPOSTOS'))
        when 'PRODUTOS' then 'PRODUTOS' when 'SERVICOS' then 'SERVICOS'
        when 'MISTO' then 'MISTO' else 'COMPOSTOS' end,
      coalesce(nullif(v_grupo ->> 'quantidade', '')::numeric, 1),
      coalesce(nullif(trim(v_grupo ->> 'unidade'), ''), 'CJ'),
      coalesce(nullif(v_grupo #>> '{margem,impostos_percentual}', '')::numeric, 0),
      coalesce(nullif(v_grupo #>> '{margem,margem_operacional_percentual}', '')::numeric, 0),
      coalesce(nullif(v_grupo #>> '{margem,lucro_percentual}', '')::numeric, 0),
      coalesce(nullif(v_grupo #>> '{margem,comissao_percentual}', '')::numeric, 0),
      coalesce(nullif(v_grupo #>> '{margem,financeiro_mensal_percentual}', '')::numeric, 0),
      coalesce(nullif(v_grupo #>> '{margem,prazo_medio_dias}', '')::numeric, 0),
      case lower(coalesce(v_grupo ->> 'modo_preco', 'soma_itens')) when 'manual' then 'MANUAL' else 'SOMA_ITENS' end,
      case when lower(coalesce(v_grupo ->> 'modo_preco', 'soma_itens')) = 'manual'
        then coalesce(nullif(v_grupo ->> 'preco_manual_total', '')::numeric, 0) else null end,
      nullif(trim(v_grupo ->> 'justificativa_preco_manual'), ''), auth.uid(), auth.uid()
    ) returning proposta_grupo_id into v_grupo_id;

    v_inicio_item := v_ordem_item;
    for v_item in select value from jsonb_array_elements(coalesce(v_grupo -> 'itens', '[]'::jsonb)) loop
      v_ordem_item := v_ordem_item + 1;
    end loop;
    update propostas_mhs.propostas_itens
    set proposta_grupo_id = v_grupo_id
    where proposta_id = p_proposta_id
      and ordem > v_inicio_item and ordem <= v_ordem_item;
  end loop;

  select count(*) into v_total_itens from propostas_mhs.propostas_itens where proposta_id = p_proposta_id;
  if v_total_itens <> v_ordem_item then
    raise exception 'A quantidade de itens salvos nao corresponde aos itens informados nos grupos.' using errcode = '22023';
  end if;
  perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'ATUALIZADA', 'Grupos comerciais salvos');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.salvar_proposta_completa_mhs(p_proposta_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_itens jsonb;
  v_conteudo jsonb;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_dados -> 'grupos', '[]'::jsonb)) <> 'array' then
    raise exception 'grupos deve ser uma lista.' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(i.value - 'ordem'), '[]'::jsonb) into v_itens
  from jsonb_array_elements(p_dados -> 'grupos') g
  cross join lateral jsonb_array_elements(coalesce(g.value -> 'itens', '[]'::jsonb)) i;

  v_conteudo := jsonb_set(p_dados - 'grupos', '{itens}', v_itens, true);
  perform api.salvar_conteudo_proposta_mhs(p_proposta_id, v_conteudo);
  perform api.salvar_grupos_proposta_mhs(p_proposta_id, p_dados -> 'grupos');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

revoke all on function
  api.salvar_grupos_proposta_mhs(uuid, jsonb),
  api.salvar_proposta_completa_mhs(uuid, jsonb)
from public, anon;
grant execute on function
  api.salvar_grupos_proposta_mhs(uuid, jsonb),
  api.salvar_proposta_completa_mhs(uuid, jsonb)
to authenticated;

notify pgrst, 'reload schema';
commit;

