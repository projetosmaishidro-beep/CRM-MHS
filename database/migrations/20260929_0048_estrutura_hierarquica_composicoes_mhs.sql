-- ============================================================================
-- PROPOSTAS MHS - MODULOS, ITENS-CABECA E SUBITENS HIERARQUICOS
-- Execute depois de 20260929_0047_validar_frases_prontas_observacoes_mhs.sql.
-- A migracao e aditiva: preserva propostas e componentes existentes.
-- ============================================================================

begin;

create table if not exists propostas_mhs.propostas_composicao_modulos (
  proposta_composicao_modulo_id uuid primary key default gen_random_uuid(),
  proposta_grupo_id uuid not null references propostas_mhs.propostas_grupos(proposta_grupo_id) on delete cascade,
  chave_externa text not null,
  codigo text not null,
  titulo text,
  ordem integer not null,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_composicao_modulos_chave_uidx unique (proposta_grupo_id, chave_externa),
  constraint propostas_composicao_modulos_codigo_uidx unique (proposta_grupo_id, codigo),
  constraint propostas_composicao_modulos_ordem_uidx unique (proposta_grupo_id, ordem),
  constraint propostas_composicao_modulos_codigo_check check (length(trim(codigo)) between 1 and 8),
  constraint propostas_composicao_modulos_ordem_check check (ordem > 0)
);

create index if not exists propostas_composicao_modulos_grupo_idx
  on propostas_mhs.propostas_composicao_modulos (proposta_grupo_id, ordem);

alter table propostas_mhs.propostas_itens
  add column if not exists proposta_composicao_modulo_id uuid
  references propostas_mhs.propostas_composicao_modulos(proposta_composicao_modulo_id) on delete set null;

alter table propostas_mhs.propostas_itens_composicao
  add column if not exists proposta_item_composicao_pai_id uuid
  references propostas_mhs.propostas_itens_composicao(proposta_item_composicao_id) on delete cascade,
  add column if not exists incluir_no_cpmv boolean not null default true;

create index if not exists propostas_itens_modulo_idx
  on propostas_mhs.propostas_itens (proposta_composicao_modulo_id);
create index if not exists propostas_itens_composicao_pai_idx
  on propostas_mhs.propostas_itens_composicao (proposta_item_composicao_pai_id, ordem);
create unique index if not exists propostas_itens_composicao_codigo_uidx
  on propostas_mhs.propostas_itens_composicao (proposta_item_id, codigo_referencia)
  where codigo_referencia is not null;

alter table propostas_mhs.propostas_composicao_modulos enable row level security;
revoke all on propostas_mhs.propostas_composicao_modulos from public, anon, authenticated;

drop trigger if exists propostas_composicao_modulos_preencher_atualizacao
  on propostas_mhs.propostas_composicao_modulos;
create trigger propostas_composicao_modulos_preencher_atualizacao
before update on propostas_mhs.propostas_composicao_modulos
for each row execute function propostas_mhs.preencher_atualizacao();

create or replace function propostas_mhs.validar_vinculo_estrutura_composicao_mhs()
returns trigger
language plpgsql
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_grupo_item uuid;
  v_grupo_modulo uuid;
  v_item_pai uuid;
begin
  if tg_table_name = 'propostas_itens' and new.proposta_composicao_modulo_id is not null then
    select proposta_grupo_id into v_grupo_modulo
    from propostas_mhs.propostas_composicao_modulos
    where proposta_composicao_modulo_id = new.proposta_composicao_modulo_id;
    if v_grupo_modulo is null or new.proposta_grupo_id is distinct from v_grupo_modulo then
      raise exception 'O modulo deve pertencer ao mesmo grupo comercial do item.' using errcode = '23514';
    end if;
  end if;

  if tg_table_name = 'propostas_itens_composicao' and new.proposta_item_composicao_pai_id is not null then
    select proposta_item_id into v_item_pai
    from propostas_mhs.propostas_itens_composicao
    where proposta_item_composicao_id = new.proposta_item_composicao_pai_id;
    if v_item_pai is null or v_item_pai <> new.proposta_item_id then
      raise exception 'O subitem-pai deve pertencer ao mesmo item-cabeca.' using errcode = '23514';
    end if;
    if new.proposta_item_composicao_pai_id = new.proposta_item_composicao_id then
      raise exception 'Um subitem nao pode ser pai de si mesmo.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists propostas_itens_validar_modulo_composicao on propostas_mhs.propostas_itens;
create trigger propostas_itens_validar_modulo_composicao
before insert or update of proposta_composicao_modulo_id, proposta_grupo_id on propostas_mhs.propostas_itens
for each row execute function propostas_mhs.validar_vinculo_estrutura_composicao_mhs();

drop trigger if exists propostas_itens_composicao_validar_pai on propostas_mhs.propostas_itens_composicao;
create trigger propostas_itens_composicao_validar_pai
before insert or update of proposta_item_composicao_pai_id, proposta_item_id on propostas_mhs.propostas_itens_composicao
for each row execute function propostas_mhs.validar_vinculo_estrutura_composicao_mhs();

create or replace function propostas_mhs.inserir_linha_estrutura_composicao_mhs(
  p_proposta_item_id uuid,
  p_linha_pai_id uuid,
  p_linha jsonb,
  p_ordem integer,
  p_nivel integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_linha_id uuid;
  v_filho jsonb;
  v_ordem_filho integer := 0;
  v_codigo text := nullif(trim(coalesce(p_linha ->> 'code', p_linha ->> 'codigo_referencia')), '');
  v_descricao text := nullif(trim(coalesce(p_linha ->> 'description', p_linha ->> 'descricao')), '');
  v_unidade text := coalesce(nullif(trim(coalesce(p_linha ->> 'unit', p_linha ->> 'unidade')), ''), 'UN');
  v_quantidade numeric := coalesce(nullif(p_linha ->> 'quantity', '')::numeric, nullif(p_linha ->> 'quantidade', '')::numeric, 1);
  v_custo numeric := coalesce(nullif(p_linha ->> 'unitCost', '')::numeric, nullif(p_linha ->> 'cpmv_unitario', '')::numeric, 0);
  v_ordem_global integer;
begin
  if p_nivel > 8 then
    raise exception 'A composicao aceita no maximo oito niveis de subitens.' using errcode = '22023';
  end if;
  if v_descricao is null then
    raise exception 'Todo subitem precisa de descricao.' using errcode = '22023';
  end if;
  if v_quantidade <= 0 or v_custo < 0 then
    raise exception 'Quantidade e custo do subitem devem ser validos.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_linha -> 'children', '[]'::jsonb)) <> 'array' then
    raise exception 'children deve ser uma lista.' using errcode = '22023';
  end if;
  -- A tabela legada mantem a ordem unica por item-cabeca. A sequencia global
  -- preserva a ordem entre irmaos e permite varios niveis sem colisao.
  select coalesce(max(ordem), 0) + 1 into v_ordem_global
  from propostas_mhs.propostas_itens_composicao
  where proposta_item_id = p_proposta_item_id;

  insert into propostas_mhs.propostas_itens_composicao (
    proposta_item_id, proposta_item_composicao_pai_id, item_catalogo_id,
    ordem, codigo_referencia, descricao, unidade, quantidade,
    cpmv_unitario, cpmv_total, observacao, incluir_no_cpmv
  ) values (
    p_proposta_item_id, p_linha_pai_id,
    nullif(p_linha ->> 'catalogItemId', '')::uuid,
    v_ordem_global, v_codigo, v_descricao, v_unidade, v_quantidade,
    v_custo, v_quantidade * v_custo,
    nullif(trim(coalesce(p_linha ->> 'notes', p_linha ->> 'observacao')), ''),
    coalesce(nullif(p_linha ->> 'includeInCpmv', '')::boolean, true)
  ) returning proposta_item_composicao_id into v_linha_id;

  for v_filho in select value from jsonb_array_elements(coalesce(p_linha -> 'children', '[]'::jsonb)) loop
    v_ordem_filho := v_ordem_filho + 1;
    perform propostas_mhs.inserir_linha_estrutura_composicao_mhs(
      p_proposta_item_id, v_linha_id, v_filho, v_ordem_filho, p_nivel + 1
    );
  end loop;
  return v_linha_id;
end;
$$;

create or replace function api.sincronizar_estrutura_composicao_proposta_mhs(
  p_proposta_id uuid,
  p_estrutura jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_grupo jsonb;
  v_modulo jsonb;
  v_item jsonb;
  v_linha jsonb;
  v_grupo_id uuid;
  v_modulo_id uuid;
  v_item_id uuid;
  v_ordem_modulo integer;
  v_ordem_linha integer;
  v_chave_modulo text;
  v_codigo_modulo text;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_estrutura, '[]'::jsonb)) <> 'array' then
    raise exception 'estrutura_composicao deve ser uma lista.' using errcode = '22023';
  end if;
  perform 1 from propostas_mhs.propostas where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  for v_grupo in select value from jsonb_array_elements(coalesce(p_estrutura, '[]'::jsonb)) loop
    select proposta_grupo_id into v_grupo_id
    from propostas_mhs.propostas_grupos
    where proposta_id = p_proposta_id
      and ordem = nullif(v_grupo ->> 'ordem_grupo', '')::integer
    for update;
    if v_grupo_id is null then
      raise exception 'Grupo da composicao nao encontrado.' using errcode = 'P0002';
    end if;
    if coalesce(nullif(v_grupo ->> 'composto', '')::boolean, false) is not true then
      -- Se um grupo deixar de ser conjunto, remove somente sua estrutura
      -- interna obsoleta; os itens comerciais continuam no salvamento normal.
      delete from propostas_mhs.propostas_composicao_modulos where proposta_grupo_id = v_grupo_id;
      continue;
    end if;
    if jsonb_typeof(coalesce(v_grupo -> 'modulos', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(v_grupo -> 'modulos', '[]'::jsonb)) = 0 then
      raise exception 'Todo conjunto precisa de ao menos um modulo.' using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(v_grupo -> 'itens', '[]'::jsonb)) <> 'array' then
      raise exception 'itens da composicao deve ser uma lista.' using errcode = '22023';
    end if;

    delete from propostas_mhs.propostas_itens_composicao c
    using propostas_mhs.propostas_itens i
    where c.proposta_item_id = i.proposta_item_id and i.proposta_grupo_id = v_grupo_id;
    update propostas_mhs.propostas_itens
    set proposta_composicao_modulo_id = null
    where proposta_grupo_id = v_grupo_id;
    delete from propostas_mhs.propostas_composicao_modulos where proposta_grupo_id = v_grupo_id;

    v_ordem_modulo := 0;
    for v_modulo in select value from jsonb_array_elements(v_grupo -> 'modulos') loop
      v_ordem_modulo := v_ordem_modulo + 1;
      v_chave_modulo := nullif(trim(v_modulo ->> 'id'), '');
      v_codigo_modulo := nullif(trim(v_modulo ->> 'code'), '');
      if v_chave_modulo is null or v_codigo_modulo is null then
        raise exception 'Todo modulo precisa de identificador e codigo.' using errcode = '22023';
      end if;
      insert into propostas_mhs.propostas_composicao_modulos (
        proposta_grupo_id, chave_externa, codigo, titulo, ordem, criado_por, atualizado_por
      ) values (
        v_grupo_id, v_chave_modulo, upper(v_codigo_modulo), nullif(trim(v_modulo ->> 'title'), ''),
        coalesce(nullif(v_modulo ->> 'order', '')::integer, v_ordem_modulo), auth.uid(), auth.uid()
      );
    end loop;

    for v_item in select value from jsonb_array_elements(v_grupo -> 'itens') loop
      select proposta_item_id into v_item_id
      from propostas_mhs.propostas_itens
      where proposta_grupo_id = v_grupo_id
        and dados_adicionais #>> '{mhs_ui_v1,id}' = nullif(trim(v_item ->> 'id'), '')
      for update;
      if v_item_id is null then
        raise exception 'Item-cabeca da composicao nao encontrado.' using errcode = 'P0002';
      end if;
      select proposta_composicao_modulo_id into v_modulo_id
      from propostas_mhs.propostas_composicao_modulos
      where proposta_grupo_id = v_grupo_id
        and chave_externa = nullif(trim(v_item ->> 'modulo_id'), '');
      if v_modulo_id is null then
        raise exception 'Modulo do item-cabeca nao encontrado.' using errcode = '22023';
      end if;
      update propostas_mhs.propostas_itens
      set proposta_composicao_modulo_id = v_modulo_id,
          codigo_referencia = coalesce(nullif(trim(v_item ->> 'codigo'), ''), codigo_referencia),
          atualizado_por = auth.uid(), atualizado_em = now()
      where proposta_item_id = v_item_id;

      if jsonb_typeof(coalesce(v_item -> 'componentes', '[]'::jsonb)) <> 'array' then
        raise exception 'componentes deve ser uma lista.' using errcode = '22023';
      end if;
      v_ordem_linha := 0;
      for v_linha in select value from jsonb_array_elements(coalesce(v_item -> 'componentes', '[]'::jsonb)) loop
        v_ordem_linha := v_ordem_linha + 1;
        perform propostas_mhs.inserir_linha_estrutura_composicao_mhs(v_item_id, null, v_linha, v_ordem_linha);
      end loop;
    end loop;
  end loop;
end;
$$;

-- O salvamento da arvore ocorre dentro da mesma transacao que grava cabecalho,
-- grupos, itens, memoria e opcoes comerciais. Nenhuma estrutura parcial fica
-- persistida se uma validacao falhar.
create or replace function api.salvar_proposta_transacional_mhs(
  p_proposta_id uuid,
  p_dados jsonb,
  p_opcoes jsonb,
  p_grupo_opcoes jsonb,
  p_versao_esperada bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare v_versao bigint; v_resultado jsonb; v_totais jsonb; v_memoria jsonb;
begin
  perform api.exigir_editor();
  select versao_edicao into v_versao from propostas_mhs.propostas
  where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;
  if v_versao <> coalesce(p_versao_esperada, 0) then
    raise exception 'A proposta foi atualizada em outra operacao. Recarregue antes de salvar novamente.'
      using errcode = '40001', detail = format('versao_atual=%s; versao_recebida=%s', v_versao, p_versao_esperada);
  end if;

  perform api.atualizar_cabecalho_proposta_mhs(p_proposta_id, coalesce(p_dados -> 'cabecalho', '{}'::jsonb));
  perform api.salvar_proposta_completa_com_historico_mhs(p_proposta_id, p_dados);
  perform api.sincronizar_opcoes_comerciais_proposta_mhs(p_proposta_id, p_opcoes, p_grupo_opcoes);
  perform api.sincronizar_estrutura_composicao_proposta_mhs(p_proposta_id, coalesce(p_dados -> 'estrutura_composicao', '[]'::jsonb));
  v_totais := propostas_mhs.recalcular_totais_proposta_mhs(p_proposta_id);
  v_memoria := coalesce(p_dados -> 'memoria_calculo', '{}'::jsonb) || jsonb_build_object(
    'base_calculo', v_totais -> 'valor_base_calculo',
    'percentual_total', v_totais -> 'percentual_total',
    'fator_venda', v_totais -> 'fator_venda',
    'valor_resultado', v_totais -> 'valor_proposta'
  );
  perform api.registrar_memoria_calculo_proposta_mhs(p_proposta_id, v_memoria);
  update propostas_mhs.propostas
  set versao_edicao = versao_edicao + 1, atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id returning versao_edicao into v_versao;
  v_resultado := api.detalhar_proposta_mhs(p_proposta_id);
  return v_resultado || jsonb_build_object('versao_persistencia', v_versao);
end;
$$;

revoke all on function api.sincronizar_estrutura_composicao_proposta_mhs(uuid, jsonb) from public, anon;
grant execute on function api.sincronizar_estrutura_composicao_proposta_mhs(uuid, jsonb) to authenticated;
grant execute on function api.salvar_proposta_transacional_mhs(uuid, jsonb, jsonb, jsonb, bigint) to authenticated;

notify pgrst, 'reload schema';
commit;
