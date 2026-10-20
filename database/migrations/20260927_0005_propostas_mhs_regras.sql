-- ============================================================================
-- PROPOSTAS MHS - REGRAS, HISTORICO E REVISOES IMUTAVEIS
--
-- Execute apos 20260927_0004_propostas_mhs_estrutura.sql.
-- Todas as funcoes usam o schema propostas_mhs de forma explicita e mantem
-- historico antes/depois para operacoes relevantes.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. METADADOS E AUDITORIA AUTOMATICA
-- ---------------------------------------------------------------------------
create or replace function propostas_mhs.preencher_atualizacao()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := coalesce(auth.uid(), new.atualizado_por);
  return new;
end;
$$;

create or replace function propostas_mhs.registrar_historico_linha()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_antes jsonb;
  v_depois jsonb;
  v_id uuid;
  v_operacao text;
begin
  if tg_op = 'INSERT' then
    v_depois := to_jsonb(new);
    v_id := nullif(v_depois ->> tg_argv[0], '')::uuid;
    v_operacao := 'CRIADA';
  elsif tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    v_depois := to_jsonb(new);
    v_id := nullif(v_depois ->> tg_argv[0], '')::uuid;
    v_operacao := 'ATUALIZADA';
  else
    v_antes := to_jsonb(old);
    v_id := nullif(v_antes ->> tg_argv[0], '')::uuid;
    v_operacao := 'EXCLUIDA_LOGICAMENTE';
  end if;

  if v_id is not null then
    insert into propostas_mhs.historico_acoes (
      entidade, entidade_id, operacao, resumo, dados_antes, dados_depois, usuario_id
    ) values (
      tg_table_schema || '.' || tg_table_name,
      v_id,
      v_operacao,
      coalesce(nullif(tg_argv[1], ''), tg_table_name),
      v_antes,
      v_depois,
      auth.uid()
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function propostas_mhs.registrar_acao(
  p_entidade text,
  p_entidade_id uuid,
  p_operacao text,
  p_resumo text default null,
  p_metadados jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
begin
  if p_operacao not in ('CRIADA', 'ATUALIZADA', 'ARQUIVADA', 'RESTAURADA', 'REVISADA', 'EMITIDA', 'ENVIADA', 'APROVADA', 'RECUSADA', 'FINALIZADA', 'EXCLUIDA_LOGICAMENTE') then
    raise exception 'Operacao de historico invalida: %', p_operacao using errcode = '22023';
  end if;

  insert into propostas_mhs.historico_acoes (
    entidade, entidade_id, operacao, resumo, metadados, usuario_id
  ) values (
    p_entidade, p_entidade_id, p_operacao, nullif(trim(p_resumo), ''),
    coalesce(p_metadados, '{}'::jsonb), auth.uid()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. PROTECOES DE DADOS HISTORICOS
-- ---------------------------------------------------------------------------
create or replace function propostas_mhs.impedir_alteracao_historica()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  raise exception 'O historico % e imutavel. Crie uma nova versao ou registro.', tg_table_name
    using errcode = '55000';
end;
$$;

create or replace function propostas_mhs.proteger_versao_composicao()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, propostas_mhs
as $$
begin
  if old.situacao <> 'RASCUNHO' then
    raise exception 'A versao % da composicao ja esta % e nao pode ser alterada.', old.numero_versao, old.situacao
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function propostas_mhs.proteger_componentes_composicao()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, propostas_mhs
as $$
declare
  v_versao_id uuid;
  v_situacao text;
begin
  if tg_op = 'INSERT' then
    v_versao_id := new.composicao_versao_id;
  else
    v_versao_id := old.composicao_versao_id;
  end if;

  select situacao into v_situacao
  from propostas_mhs.catalogo_composicoes_versoes
  where composicao_versao_id = v_versao_id;

  if v_situacao is not null and v_situacao <> 'RASCUNHO' then
    raise exception 'Os componentes so podem ser alterados enquanto a composicao estiver em RASCUNHO.'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function propostas_mhs.recalcular_cpmv_composicao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, propostas_mhs
as $$
declare
  v_versao_id uuid;
begin
  if tg_op = 'INSERT' then
    v_versao_id := new.composicao_versao_id;
  else
    v_versao_id := old.composicao_versao_id;
  end if;

  update propostas_mhs.catalogo_composicoes_versoes
  set cpmv_total = coalesce((
        select sum(c.cpmv_total)
        from propostas_mhs.catalogo_composicao_componentes c
        where c.composicao_versao_id = v_versao_id
      ), 0)
  where composicao_versao_id = v_versao_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. NUMERACAO E HISTORICO DE CUSTOS
-- ---------------------------------------------------------------------------
create or replace function propostas_mhs.proximo_numero_proposta(p_ano integer default extract(year from current_date)::integer)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, propostas_mhs
as $$
declare
  v_numero integer;
begin
  if p_ano not between 2000 and 2200 then
    raise exception 'Ano de proposta invalido: %', p_ano using errcode = '22023';
  end if;

  insert into propostas_mhs.numeracao_anual (ano, ultimo_numero)
  values (p_ano, 1)
  on conflict (ano) do update
    set ultimo_numero = propostas_mhs.numeracao_anual.ultimo_numero + 1,
        atualizado_em = now()
  returning ultimo_numero into v_numero;

  return v_numero;
end;
$$;

create or replace function propostas_mhs.registrar_cpmv(
  p_item_catalogo_id uuid,
  p_cpmv_unitario numeric,
  p_vigente_desde date default current_date,
  p_fonte text default null,
  p_documento_referencia text default null,
  p_observacao text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_atual propostas_mhs.historico_cpmv_produtos%rowtype;
  v_id uuid;
begin
  if p_item_catalogo_id is null or not exists (
    select 1 from propostas_mhs.catalogo_itens where item_catalogo_id = p_item_catalogo_id
  ) then
    raise exception 'Item de catalogo nao encontrado.' using errcode = '23503';
  end if;
  if p_cpmv_unitario is null or p_cpmv_unitario < 0 then
    raise exception 'CPMV unitario deve ser maior ou igual a zero.' using errcode = '22023';
  end if;

  select * into v_atual
  from propostas_mhs.historico_cpmv_produtos
  where item_catalogo_id = p_item_catalogo_id and vigente_ate is null
  order by vigente_desde desc, criado_em desc
  limit 1
  for update;

  if found then
    if p_vigente_desde <= v_atual.vigente_desde then
      raise exception 'A nova vigencia (%) deve ser posterior a vigencia atual (%).', p_vigente_desde, v_atual.vigente_desde
        using errcode = '22023';
    end if;
    update propostas_mhs.historico_cpmv_produtos
    set vigente_ate = p_vigente_desde - 1,
        atualizado_por = auth.uid(),
        atualizado_em = now()
    where historico_cpmv_id = v_atual.historico_cpmv_id;
  end if;

  insert into propostas_mhs.historico_cpmv_produtos (
    item_catalogo_id, cpmv_unitario, vigente_desde, fonte, documento_referencia,
    observacao, criado_por, atualizado_por
  ) values (
    p_item_catalogo_id, p_cpmv_unitario, coalesce(p_vigente_desde, current_date),
    nullif(trim(p_fonte), ''), nullif(trim(p_documento_referencia), ''),
    nullif(trim(p_observacao), ''), auth.uid(), auth.uid()
  ) returning historico_cpmv_id into v_id;

  perform propostas_mhs.registrar_acao(
    'CPMV', v_id, 'CRIADA', 'Novo CPMV registrado',
    jsonb_build_object('item_catalogo_id', p_item_catalogo_id, 'cpmv_unitario', p_cpmv_unitario)
  );
  return v_id;
end;
$$;

create or replace function propostas_mhs.registrar_preco_venda(
  p_item_catalogo_id uuid,
  p_preco_venda_unitario numeric,
  p_vigente_desde date default current_date,
  p_fonte text default null,
  p_observacao text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_atual propostas_mhs.historico_precos_venda%rowtype;
  v_id uuid;
begin
  if p_item_catalogo_id is null or not exists (
    select 1 from propostas_mhs.catalogo_itens where item_catalogo_id = p_item_catalogo_id
  ) then
    raise exception 'Item de catalogo nao encontrado.' using errcode = '23503';
  end if;
  if p_preco_venda_unitario is null or p_preco_venda_unitario < 0 then
    raise exception 'Preco de venda deve ser maior ou igual a zero.' using errcode = '22023';
  end if;

  select * into v_atual
  from propostas_mhs.historico_precos_venda
  where item_catalogo_id = p_item_catalogo_id and vigente_ate is null
  order by vigente_desde desc, criado_em desc
  limit 1
  for update;

  if found then
    if p_vigente_desde <= v_atual.vigente_desde then
      raise exception 'A nova vigencia (%) deve ser posterior a vigencia atual (%).', p_vigente_desde, v_atual.vigente_desde
        using errcode = '22023';
    end if;
    update propostas_mhs.historico_precos_venda
    set vigente_ate = p_vigente_desde - 1,
        atualizado_por = auth.uid(),
        atualizado_em = now()
    where historico_preco_id = v_atual.historico_preco_id;
  end if;

  insert into propostas_mhs.historico_precos_venda (
    item_catalogo_id, preco_venda_unitario, vigente_desde, fonte, observacao,
    criado_por, atualizado_por
  ) values (
    p_item_catalogo_id, p_preco_venda_unitario, coalesce(p_vigente_desde, current_date),
    nullif(trim(p_fonte), ''), nullif(trim(p_observacao), ''), auth.uid(), auth.uid()
  ) returning historico_preco_id into v_id;

  perform propostas_mhs.registrar_acao(
    'PRECO_VENDA', v_id, 'CRIADA', 'Novo preco de venda registrado',
    jsonb_build_object('item_catalogo_id', p_item_catalogo_id, 'preco_venda_unitario', p_preco_venda_unitario)
  );
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. SNAPSHOT COMPLETO E REVISAO DE PROPOSTA
-- ---------------------------------------------------------------------------
create or replace function propostas_mhs.montar_snapshot_proposta(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_snapshot jsonb;
begin
  if not exists (select 1 from propostas_mhs.propostas where proposta_id = p_proposta_id) then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'proposta', (select to_jsonb(p) from propostas_mhs.propostas p where p.proposta_id = p_proposta_id),
    'cliente_atual', (
      select jsonb_build_object(
        'empresa_id', e.empresa_id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia,
        'cnpj', e.cnpj, 'contato_nome', e.contato_nome, 'contato_cargo', e.contato_cargo,
        'telefone', e.telefone, 'whatsapp', e.whatsapp, 'email', e.email,
        'logradouro', e.logradouro, 'bairro', e.bairro, 'municipio', e.municipio, 'uf', e.uf, 'cep', e.cep
      )
      from propostas_mhs.propostas p
      join cadastro.empresas e on e.empresa_id = p.empresa_id
      where p.proposta_id = p_proposta_id
    ),
    'local_obra', (
      select to_jsonb(o) from propostas_mhs.propostas p
      join propostas_mhs.locais_obra o on o.local_obra_id = p.local_obra_id
      where p.proposta_id = p_proposta_id
    ),
    'itens', coalesce((
      select jsonb_agg(
        to_jsonb(i) || jsonb_build_object('componentes', coalesce((
          select jsonb_agg(to_jsonb(c) order by c.ordem)
          from propostas_mhs.propostas_itens_composicao c
          where c.proposta_item_id = i.proposta_item_id
        ), '[]'::jsonb))
        order by i.ordem
      )
      from propostas_mhs.propostas_itens i
      where i.proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'condicoes', coalesce((
      select to_jsonb(c) from propostas_mhs.propostas_condicoes c where c.proposta_id = p_proposta_id
    ), '{}'::jsonb),
    'pagamentos', coalesce((
      select jsonb_agg(to_jsonb(pg) order by pg.ordem)
      from propostas_mhs.propostas_pagamentos pg where pg.proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'escopo', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.inclusao desc, e.ordem)
      from propostas_mhs.propostas_escopo e where e.proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'referencias', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.criado_em)
      from propostas_mhs.propostas_referencias r where r.proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'blocos', coalesce((
      select jsonb_agg(to_jsonb(b) order by b.tipo, b.ordem)
      from propostas_mhs.propostas_blocos b where b.proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'memoria_calculo', coalesce((
      select jsonb_agg(
        to_jsonb(m) || jsonb_build_object('linhas', coalesce((
          select jsonb_agg(to_jsonb(l) order by l.ordem)
          from propostas_mhs.memorias_calculo_linhas l
          where l.memoria_calculo_id = m.memoria_calculo_id
        ), '[]'::jsonb))
        order by m.numero_calculo
      )
      from propostas_mhs.memorias_calculo m where m.proposta_id = p_proposta_id
    ), '[]'::jsonb)
  ) into v_snapshot;

  return v_snapshot;
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
  select * into v_proposta
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id
  for update;

  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  v_tipo := upper(coalesce(p_tipo, 'REVISAO'));
  if v_tipo not in ('PREVIA', 'EMISSAO', 'REVISAO', 'FINAL') then
    raise exception 'Tipo de revisao invalido.' using errcode = '22023';
  end if;

  v_numero := v_proposta.versao_atual + 1;
  v_snapshot := propostas_mhs.montar_snapshot_proposta(p_proposta_id);

  insert into propostas_mhs.propostas_revisoes (
    proposta_id, numero_revisao, tipo, motivo, status_proposta, valor_cpmv_total,
    valor_proposta, dados_snapshot, hash_integridade, criado_por
  ) values (
    p_proposta_id, v_numero, v_tipo, nullif(trim(p_motivo), ''), v_proposta.status,
    v_proposta.valor_cpmv_total, v_proposta.valor_proposta, v_snapshot,
    md5(v_snapshot::text), auth.uid()
  ) returning * into v_revisao;

  update propostas_mhs.propostas
  set versao_atual = v_numero,
      atualizado_por = auth.uid(),
      atualizado_em = now()
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

-- ---------------------------------------------------------------------------
-- 5. GATILHOS
-- ---------------------------------------------------------------------------
drop trigger if exists clientes_preencher_atualizacao on propostas_mhs.clientes;
create trigger clientes_preencher_atualizacao before update on propostas_mhs.clientes
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists locais_obra_preencher_atualizacao on propostas_mhs.locais_obra;
create trigger locais_obra_preencher_atualizacao before update on propostas_mhs.locais_obra
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists catalogo_itens_preencher_atualizacao on propostas_mhs.catalogo_itens;
create trigger catalogo_itens_preencher_atualizacao before update on propostas_mhs.catalogo_itens
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists catalogo_composicoes_preencher_atualizacao on propostas_mhs.catalogo_composicoes;
create trigger catalogo_composicoes_preencher_atualizacao before update on propostas_mhs.catalogo_composicoes
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists historico_cpmv_preencher_atualizacao on propostas_mhs.historico_cpmv_produtos;
create trigger historico_cpmv_preencher_atualizacao before update on propostas_mhs.historico_cpmv_produtos
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists historico_preco_preencher_atualizacao on propostas_mhs.historico_precos_venda;
create trigger historico_preco_preencher_atualizacao before update on propostas_mhs.historico_precos_venda
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists blocos_preencher_atualizacao on propostas_mhs.blocos_inteligentes;
create trigger blocos_preencher_atualizacao before update on propostas_mhs.blocos_inteligentes
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists templates_preencher_atualizacao on propostas_mhs.templates;
create trigger templates_preencher_atualizacao before update on propostas_mhs.templates
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists propostas_preencher_atualizacao on propostas_mhs.propostas;
create trigger propostas_preencher_atualizacao before update on propostas_mhs.propostas
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists propostas_itens_preencher_atualizacao on propostas_mhs.propostas_itens;
create trigger propostas_itens_preencher_atualizacao before update on propostas_mhs.propostas_itens
for each row execute function propostas_mhs.preencher_atualizacao();
drop trigger if exists condicoes_preencher_atualizacao on propostas_mhs.propostas_condicoes;
create trigger condicoes_preencher_atualizacao before update on propostas_mhs.propostas_condicoes
for each row execute function propostas_mhs.preencher_atualizacao();

drop trigger if exists composicao_versao_protegida on propostas_mhs.catalogo_composicoes_versoes;
create trigger composicao_versao_protegida before update or delete on propostas_mhs.catalogo_composicoes_versoes
for each row execute function propostas_mhs.proteger_versao_composicao();
drop trigger if exists componentes_composicao_protegidos on propostas_mhs.catalogo_composicao_componentes;
create trigger componentes_composicao_protegidos before update or delete on propostas_mhs.catalogo_composicao_componentes
for each row execute function propostas_mhs.proteger_componentes_composicao();
drop trigger if exists componentes_recalcular_cpmv on propostas_mhs.catalogo_composicao_componentes;
create trigger componentes_recalcular_cpmv after insert or update or delete on propostas_mhs.catalogo_composicao_componentes
for each row execute function propostas_mhs.recalcular_cpmv_composicao();

drop trigger if exists revisoes_imutaveis on propostas_mhs.propostas_revisoes;
create trigger revisoes_imutaveis before update or delete on propostas_mhs.propostas_revisoes
for each row execute function propostas_mhs.impedir_alteracao_historica();
drop trigger if exists template_versoes_imutaveis on propostas_mhs.templates_versoes;
create trigger template_versoes_imutaveis before update or delete on propostas_mhs.templates_versoes
for each row execute function propostas_mhs.impedir_alteracao_historica();
drop trigger if exists bloco_versoes_imutaveis on propostas_mhs.blocos_inteligentes_versoes;
create trigger bloco_versoes_imutaveis before update or delete on propostas_mhs.blocos_inteligentes_versoes
for each row execute function propostas_mhs.impedir_alteracao_historica();

drop trigger if exists propostas_auditar on propostas_mhs.propostas;
create trigger propostas_auditar after insert or update or delete on propostas_mhs.propostas
for each row execute function propostas_mhs.registrar_historico_linha('proposta_id', 'Proposta');
drop trigger if exists proposta_itens_auditar on propostas_mhs.propostas_itens;
create trigger proposta_itens_auditar after insert or update or delete on propostas_mhs.propostas_itens
for each row execute function propostas_mhs.registrar_historico_linha('proposta_item_id', 'Item de proposta');
drop trigger if exists proposta_composicao_auditar on propostas_mhs.propostas_itens_composicao;
create trigger proposta_composicao_auditar after insert or update or delete on propostas_mhs.propostas_itens_composicao
for each row execute function propostas_mhs.registrar_historico_linha('proposta_item_composicao_id', 'Componente de proposta');
drop trigger if exists proposta_memoria_auditar on propostas_mhs.memorias_calculo;
create trigger proposta_memoria_auditar after insert or update or delete on propostas_mhs.memorias_calculo
for each row execute function propostas_mhs.registrar_historico_linha('memoria_calculo_id', 'Memoria de calculo');
drop trigger if exists proposta_revisao_auditar on propostas_mhs.propostas_revisoes;
create trigger proposta_revisao_auditar after insert on propostas_mhs.propostas_revisoes
for each row execute function propostas_mhs.registrar_historico_linha('revisao_id', 'Revisao de proposta');
drop trigger if exists template_revisao_auditar on propostas_mhs.templates_versoes;
create trigger template_revisao_auditar after insert on propostas_mhs.templates_versoes
for each row execute function propostas_mhs.registrar_historico_linha('template_versao_id', 'Versao de template');
drop trigger if exists cpmv_auditar on propostas_mhs.historico_cpmv_produtos;
create trigger cpmv_auditar after insert or update on propostas_mhs.historico_cpmv_produtos
for each row execute function propostas_mhs.registrar_historico_linha('historico_cpmv_id', 'Historico CPMV');

commit;

