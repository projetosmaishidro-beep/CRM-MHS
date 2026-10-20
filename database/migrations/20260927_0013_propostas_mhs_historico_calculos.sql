-- ============================================================================
-- PROPOSTAS MHS - MEMORIA DE CALCULO COMPLETA E HISTORICO DE CUSTOS
--
-- Execute depois de 20260927_0012_validar_integracao_mhs.sql.
-- Esta migracao torna o salvamento comercial atomico: itens, composicoes,
-- condicoes, grupos e memoria de calculo sao gravados juntos. Uma memoria nova
-- somente e criada quando os dados de calculo efetivamente mudarem.
-- ============================================================================

begin;

alter table propostas_mhs.memorias_calculo
  add column if not exists assinatura_calculo text;

comment on column propostas_mhs.memorias_calculo.assinatura_calculo is
  'Hash do conteudo financeiro da memoria. Evita criar historico duplicado em autosaves sem alteracao de calculo.';

create index if not exists memorias_calculo_proposta_assinatura_idx
  on propostas_mhs.memorias_calculo (proposta_id, assinatura_calculo)
  where assinatura_calculo is not null;

create or replace function api.registrar_memoria_calculo_proposta_mhs(
  p_proposta_id uuid,
  p_memoria_calculo jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_proposta propostas_mhs.propostas%rowtype;
  v_atual propostas_mhs.memorias_calculo%rowtype;
  v_memoria propostas_mhs.memorias_calculo%rowtype;
  v_linha jsonb;
  v_ordem integer := 0;
  v_numero integer;
  v_assinatura text;
  v_base numeric(19,4);
  v_percentual numeric(19,6);
  v_fator numeric(19,10);
  v_resultado numeric(19,4);
  v_linhas jsonb;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_memoria_calculo, '{}'::jsonb)) <> 'object' then
    raise exception 'memoria_calculo deve ser um objeto.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_memoria_calculo -> 'linhas', '[]'::jsonb)) <> 'array' then
    raise exception 'linhas da memoria_calculo deve ser uma lista.' using errcode = '22023';
  end if;

  select * into v_proposta
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id
  for update;
  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;
  if v_proposta.status in ('CANCELADA', 'FINALIZADA') then
    raise exception 'A proposta esta % e nao pode receber alteracoes.', v_proposta.status using errcode = '55000';
  end if;

  v_base := coalesce(nullif(p_memoria_calculo ->> 'base_calculo', '')::numeric, 0);
  v_percentual := coalesce(nullif(p_memoria_calculo ->> 'percentual_total', '')::numeric, 0);
  v_fator := coalesce(nullif(p_memoria_calculo ->> 'fator_venda', '')::numeric, 1);
  v_resultado := coalesce(nullif(p_memoria_calculo ->> 'valor_resultado', '')::numeric, 0);
  v_linhas := coalesce(p_memoria_calculo -> 'linhas', '[]'::jsonb);
  v_assinatura := md5(jsonb_build_object(
    'base_calculo', v_base,
    'percentual_total', v_percentual,
    'fator_venda', v_fator,
    'valor_resultado', v_resultado,
    'observacao', coalesce(nullif(trim(p_memoria_calculo ->> 'observacao'), ''), ''),
    'linhas', v_linhas
  )::text);

  select * into v_atual
  from propostas_mhs.memorias_calculo
  where proposta_id = p_proposta_id and situacao = 'ATUAL'
  order by numero_calculo desc
  limit 1
  for update;

  if found and v_atual.assinatura_calculo = v_assinatura then
    return to_jsonb(v_atual) || jsonb_build_object('alterada', false);
  end if;

  update propostas_mhs.memorias_calculo
  set situacao = 'HISTORICA'
  where proposta_id = p_proposta_id and situacao = 'ATUAL';

  select coalesce(max(numero_calculo), 0) + 1 into v_numero
  from propostas_mhs.memorias_calculo
  where proposta_id = p_proposta_id;

  insert into propostas_mhs.memorias_calculo (
    proposta_id, numero_calculo, situacao, base_calculo, percentual_total,
    fator_venda, valor_resultado, observacao, assinatura_calculo, criado_por
  ) values (
    p_proposta_id, v_numero, 'ATUAL', v_base, v_percentual, v_fator, v_resultado,
    nullif(trim(p_memoria_calculo ->> 'observacao'), ''), v_assinatura, auth.uid()
  ) returning * into v_memoria;

  for v_linha in select value from jsonb_array_elements(v_linhas) loop
    v_ordem := v_ordem + 1;
    insert into propostas_mhs.memorias_calculo_linhas (
      memoria_calculo_id, ordem, componente, aliquota_percentual,
      valor_calculado, valor_texto, aplicacao
    ) values (
      v_memoria.memoria_calculo_id,
      coalesce(nullif(v_linha ->> 'ordem', '')::integer, v_ordem),
      coalesce(nullif(trim(v_linha ->> 'componente'), ''), 'Componente'),
      nullif(v_linha ->> 'aliquota_percentual', '')::numeric,
      nullif(v_linha ->> 'valor_calculado', '')::numeric,
      nullif(trim(v_linha ->> 'valor_texto'), ''),
      nullif(trim(v_linha ->> 'aplicacao'), '')
    );
  end loop;

  perform propostas_mhs.registrar_acao(
    'MEMORIA_CALCULO', v_memoria.memoria_calculo_id, 'CRIADA',
    'Memoria de calculo ' || v_numero::text || ' registrada',
    jsonb_build_object('proposta_id', p_proposta_id, 'assinatura', v_assinatura)
  );
  return to_jsonb(v_memoria) || jsonb_build_object('alterada', true);
end;
$$;

-- Sincroniza o historico global somente quando a proposta aponta para um item
-- real do catalogo e possui um unico valor unitario para ele. Se o mesmo item
-- foi negociado com valores diferentes em grupos distintos, a memoria da
-- proposta preserva todos os valores e o catalogo nao e contaminado.
create or replace function propostas_mhs.sincronizar_historico_catalogo_da_proposta(
  p_proposta_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_item record;
  v_proposta_codigo text;
  v_cpmv_atual propostas_mhs.historico_cpmv_produtos%rowtype;
  v_preco_atual propostas_mhs.historico_precos_venda%rowtype;
  v_fonte text;
begin
  select codigo into v_proposta_codigo
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id;
  if v_proposta_codigo is null then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;
  v_fonte := 'Proposta ' || v_proposta_codigo;

  for v_item in
    select
      item_catalogo_id,
      min(cpmv_unitario) filter (where cpmv_unitario is not null) as cpmv_unitario,
      min(preco_venda_unitario) filter (where preco_venda_unitario is not null) as preco_venda_unitario,
      count(distinct cpmv_unitario) filter (where cpmv_unitario is not null) as cpmv_distintos,
      count(distinct preco_venda_unitario) filter (where preco_venda_unitario is not null) as preco_distintos
    from propostas_mhs.propostas_itens
    where proposta_id = p_proposta_id and item_catalogo_id is not null and ativo
    group by item_catalogo_id
  loop
    if v_item.cpmv_distintos = 1 then
      select * into v_cpmv_atual
      from propostas_mhs.historico_cpmv_produtos
      where item_catalogo_id = v_item.item_catalogo_id and vigente_ate is null
      order by vigente_desde desc, criado_em desc
      limit 1
      for update;
      if not found or v_cpmv_atual.cpmv_unitario is distinct from v_item.cpmv_unitario then
        if found then
          update propostas_mhs.historico_cpmv_produtos
          set vigente_ate = case when vigente_desde < current_date then current_date - 1 else current_date end,
              atualizado_por = auth.uid(), atualizado_em = now()
          where historico_cpmv_id = v_cpmv_atual.historico_cpmv_id;
        end if;
        insert into propostas_mhs.historico_cpmv_produtos (
          item_catalogo_id, cpmv_unitario, vigente_desde, fonte, documento_referencia,
          observacao, criado_por, atualizado_por
        ) values (
          v_item.item_catalogo_id, v_item.cpmv_unitario, current_date, v_fonte,
          v_proposta_codigo, 'Valor unitario confirmado no salvamento da proposta.', auth.uid(), auth.uid()
        );
      end if;
    end if;

    if v_item.preco_distintos = 1 then
      select * into v_preco_atual
      from propostas_mhs.historico_precos_venda
      where item_catalogo_id = v_item.item_catalogo_id and vigente_ate is null
      order by vigente_desde desc, criado_em desc
      limit 1
      for update;
      if not found or v_preco_atual.preco_venda_unitario is distinct from v_item.preco_venda_unitario then
        if found then
          update propostas_mhs.historico_precos_venda
          set vigente_ate = case when vigente_desde < current_date then current_date - 1 else current_date end,
              atualizado_por = auth.uid(), atualizado_em = now()
          where historico_preco_id = v_preco_atual.historico_preco_id;
        end if;
        insert into propostas_mhs.historico_precos_venda (
          item_catalogo_id, preco_venda_unitario, vigente_desde, fonte, observacao,
          criado_por, atualizado_por
        ) values (
          v_item.item_catalogo_id, v_item.preco_venda_unitario, current_date, v_fonte,
          'Preco unitario confirmado no salvamento da proposta.', auth.uid(), auth.uid()
        );
      end if;
    end if;
  end loop;
end;
$$;

create or replace function api.salvar_proposta_completa_com_historico_mhs(
  p_proposta_id uuid,
  p_dados jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_dados_sem_memoria jsonb;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_dados, '{}'::jsonb)) <> 'object' then
    raise exception 'Os dados da proposta devem ser um objeto JSON.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_dados -> 'memoria_calculo', '{}'::jsonb)) <> 'object' then
    raise exception 'memoria_calculo deve ser um objeto.' using errcode = '22023';
  end if;

  -- A rotina anterior salva o rascunho. A memoria e removida aqui para que a
  -- rotina idempotente abaixo seja a unica responsavel pelo historico.
  v_dados_sem_memoria := p_dados - 'memoria_calculo';
  perform api.salvar_proposta_completa_mhs(p_proposta_id, v_dados_sem_memoria);
  perform api.registrar_memoria_calculo_proposta_mhs(p_proposta_id, p_dados -> 'memoria_calculo');
  perform propostas_mhs.sincronizar_historico_catalogo_da_proposta(p_proposta_id);
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.listar_memorias_calculo_proposta_mhs(p_proposta_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
  select coalesce(jsonb_agg(
    to_jsonb(m) || jsonb_build_object('linhas', coalesce((
      select jsonb_agg(to_jsonb(l) order by l.ordem)
      from propostas_mhs.memorias_calculo_linhas l
      where l.memoria_calculo_id = m.memoria_calculo_id
    ), '[]'::jsonb))
    order by m.numero_calculo desc
  ), '[]'::jsonb)
  from propostas_mhs.memorias_calculo m
  where m.proposta_id = p_proposta_id
    and api.eh_membro();
$$;

revoke all on function
  api.registrar_memoria_calculo_proposta_mhs(uuid, jsonb),
  api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb),
  api.listar_memorias_calculo_proposta_mhs(uuid)
from public, anon;

grant execute on function
  api.registrar_memoria_calculo_proposta_mhs(uuid, jsonb),
  api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb),
  api.listar_memorias_calculo_proposta_mhs(uuid)
to authenticated;

notify pgrst, 'reload schema';
commit;
