-- ============================================================================
-- PROPOSTAS MHS - OPERACOES TRANSACIONAIS DE CONTEUDO
--
-- Execute apos 20260927_0006_propostas_mhs_api_storage.sql.
-- Esta camada evita escrita direta do navegador nas tabelas privadas.
-- ============================================================================

begin;

-- Salva o conteudo editavel de uma proposta em uma unica transacao.
-- Se uma revisao ja existir, ela permanece intocada: somente o rascunho atual e alterado.
create or replace function api.salvar_conteudo_proposta_mhs(p_proposta_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_status text;
  v_item jsonb;
  v_componente jsonb;
  v_pagamento jsonb;
  v_escopo jsonb;
  v_referencia jsonb;
  v_bloco jsonb;
  v_linha jsonb;
  v_proposta_item_id uuid;
  v_memoria_id uuid;
  v_ordem integer;
  v_ordem_item integer;
  v_ordem_componente integer;
  v_numero_memoria integer;
  v_cpmv_total numeric(19,4);
  v_preco_total numeric(19,4);
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_dados, '{}'::jsonb)) <> 'object' then
    raise exception 'O conteudo da proposta deve ser um objeto JSON.' using errcode = '22023';
  end if;

  select status into v_status
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id
  for update;
  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;
  if v_status in ('CANCELADA', 'FINALIZADA') then
    raise exception 'A proposta esta % e nao pode receber alteracoes.', v_status using errcode = '55000';
  end if;

  if p_dados ? 'itens' then
    if jsonb_typeof(p_dados -> 'itens') <> 'array' then
      raise exception 'itens deve ser uma lista.' using errcode = '22023';
    end if;

    delete from propostas_mhs.propostas_itens where proposta_id = p_proposta_id;
    v_ordem_item := 0;
    for v_item in select value from jsonb_array_elements(p_dados -> 'itens') loop
      v_ordem_item := v_ordem_item + 1;
      insert into propostas_mhs.propostas_itens (
        proposta_id, item_catalogo_id, composicao_versao_id, ordem, modalidade,
        codigo_referencia, descricao_comercial, especificacao_tecnica, especificacao_rica,
        ncm, unidade, quantidade, ipi_percentual, cpmv_unitario, cpmv_total,
        preco_venda_unitario, preco_venda_total, dados_adicionais, criado_por, atualizado_por
      ) values (
        p_proposta_id,
        nullif(v_item ->> 'item_catalogo_id', '')::uuid,
        nullif(v_item ->> 'composicao_versao_id', '')::uuid,
        coalesce(nullif(v_item ->> 'ordem', '')::integer, v_ordem_item),
        case upper(coalesce(v_item ->> 'modalidade', v_item ->> 'tipo', 'PRODUTO'))
          when 'SERVICO' then 'SERVICO' when 'COMPOSTO' then 'COMPOSTO' else 'PRODUTO' end,
        nullif(trim(v_item ->> 'codigo_referencia'), ''),
        coalesce(nullif(trim(coalesce(v_item ->> 'descricao_comercial', v_item ->> 'descricao', v_item ->> 'description')), ''), 'Item sem descricao'),
        nullif(trim(coalesce(v_item ->> 'especificacao_tecnica', v_item ->> 'technicalSpecification')), ''),
        coalesce(v_item -> 'especificacao_rica', v_item -> 'technicalSpecificationRich', '{}'::jsonb),
        nullif(trim(v_item ->> 'ncm'), ''),
        coalesce(nullif(trim(v_item ->> 'unidade'), ''), 'UN'),
        coalesce(nullif(v_item ->> 'quantidade', '')::numeric, 1),
        coalesce(nullif(coalesce(v_item ->> 'ipi_percentual', v_item ->> 'ipiPct'), '')::numeric, 0),
        coalesce(nullif(v_item ->> 'cpmv_unitario', '')::numeric, 0),
        coalesce(nullif(v_item ->> 'cpmv_total', '')::numeric,
          coalesce(nullif(v_item ->> 'quantidade', '')::numeric, 1) * coalesce(nullif(v_item ->> 'cpmv_unitario', '')::numeric, 0)),
        coalesce(nullif(v_item ->> 'preco_venda_unitario', '')::numeric, 0),
        coalesce(nullif(v_item ->> 'preco_venda_total', '')::numeric,
          coalesce(nullif(v_item ->> 'quantidade', '')::numeric, 1) * coalesce(nullif(v_item ->> 'preco_venda_unitario', '')::numeric, 0)),
        coalesce(v_item -> 'dados_adicionais', '{}'::jsonb), auth.uid(), auth.uid()
      ) returning proposta_item_id into v_proposta_item_id;

      if jsonb_typeof(coalesce(v_item -> 'componentes', '[]'::jsonb)) <> 'array' then
        raise exception 'componentes deve ser uma lista.' using errcode = '22023';
      end if;
      v_ordem_componente := 0;
      for v_componente in select value from jsonb_array_elements(coalesce(v_item -> 'componentes', '[]'::jsonb)) loop
        v_ordem_componente := v_ordem_componente + 1;
        insert into propostas_mhs.propostas_itens_composicao (
          proposta_item_id, item_catalogo_id, ordem, codigo_referencia, descricao,
          unidade, quantidade, cpmv_unitario, cpmv_total, observacao
        ) values (
          v_proposta_item_id, nullif(v_componente ->> 'item_catalogo_id', '')::uuid,
          coalesce(nullif(v_componente ->> 'ordem', '')::integer, v_ordem_componente),
          nullif(trim(v_componente ->> 'codigo_referencia'), ''),
          coalesce(nullif(trim(coalesce(v_componente ->> 'descricao', v_componente ->> 'description')), ''), 'Componente sem descricao'),
          coalesce(nullif(trim(v_componente ->> 'unidade'), ''), 'UN'),
          coalesce(nullif(v_componente ->> 'quantidade', '')::numeric, 1),
          coalesce(nullif(v_componente ->> 'cpmv_unitario', '')::numeric, 0),
          coalesce(nullif(v_componente ->> 'cpmv_total', '')::numeric,
            coalesce(nullif(v_componente ->> 'quantidade', '')::numeric, 1) * coalesce(nullif(v_componente ->> 'cpmv_unitario', '')::numeric, 0)),
          nullif(trim(v_componente ->> 'observacao'), '')
        );
      end loop;
    end loop;

    select coalesce(sum(cpmv_total), 0), coalesce(sum(preco_venda_total), 0)
    into v_cpmv_total, v_preco_total
    from propostas_mhs.propostas_itens
    where proposta_id = p_proposta_id and ativo;

    update propostas_mhs.propostas
    set valor_cpmv_total = v_cpmv_total,
        valor_base_calculo = v_cpmv_total,
        valor_proposta = v_preco_total,
        atualizado_por = auth.uid(), atualizado_em = now()
    where proposta_id = p_proposta_id;
  end if;

  if p_dados ? 'condicoes' then
    insert into propostas_mhs.propostas_condicoes (
      proposta_id, modalidade_frete, local_frete, prazo_entrega, garantia,
      validade_dias, observacoes, atualizado_por
    ) values (
      p_proposta_id,
      case upper(coalesce(p_dados #>> '{condicoes,modalidade_frete}', p_dados #>> '{condicoes,frete}', ''))
        when 'FOB' then 'FOB' when 'CIF' then 'CIF' when 'RETIRADA' then 'RETIRADA' when 'A_COMBINAR' then 'A_COMBINAR' else null end,
      nullif(trim(coalesce(p_dados #>> '{condicoes,local_frete}', p_dados #>> '{condicoes,freiLocal}')), ''),
      nullif(trim(coalesce(p_dados #>> '{condicoes,prazo_entrega}', p_dados #>> '{condicoes,deliveryTerm}')), ''),
      nullif(trim(coalesce(p_dados #>> '{condicoes,garantia}', p_dados #>> '{condicoes,warranty}')), ''),
      nullif(coalesce(p_dados #>> '{condicoes,validade_dias}', p_dados #>> '{condicoes,validityDays}'), '')::integer,
      nullif(trim(coalesce(p_dados #>> '{condicoes,observacoes}', p_dados #>> '{condicoes,notes}')), ''), auth.uid()
    ) on conflict (proposta_id) do update set
      modalidade_frete = excluded.modalidade_frete,
      local_frete = excluded.local_frete,
      prazo_entrega = excluded.prazo_entrega,
      garantia = excluded.garantia,
      validade_dias = excluded.validade_dias,
      observacoes = excluded.observacoes,
      atualizado_por = auth.uid(), atualizado_em = now();
  end if;

  if p_dados ? 'pagamentos' then
    if jsonb_typeof(p_dados -> 'pagamentos') <> 'array' then
      raise exception 'pagamentos deve ser uma lista.' using errcode = '22023';
    end if;
    delete from propostas_mhs.propostas_pagamentos where proposta_id = p_proposta_id;
    v_ordem := 0;
    for v_pagamento in select value from jsonb_array_elements(p_dados -> 'pagamentos') loop
      v_ordem := v_ordem + 1;
      insert into propostas_mhs.propostas_pagamentos (proposta_id, ordem, descricao, percentual, prazo, observacao)
      values (
        p_proposta_id, coalesce(nullif(v_pagamento ->> 'ordem', '')::integer, v_ordem),
        coalesce(nullif(trim(coalesce(v_pagamento ->> 'descricao', v_pagamento ->> 'description')), ''), 'Etapa de pagamento'),
        coalesce(nullif(coalesce(v_pagamento ->> 'percentual', v_pagamento ->> 'percentage'), '')::numeric, 0),
        nullif(trim(coalesce(v_pagamento ->> 'prazo', v_pagamento ->> 'term')), ''),
        nullif(trim(v_pagamento ->> 'observacao'), '')
      );
    end loop;
  end if;

  if p_dados ? 'escopo' then
    if jsonb_typeof(p_dados -> 'escopo') <> 'array' then
      raise exception 'escopo deve ser uma lista.' using errcode = '22023';
    end if;
    delete from propostas_mhs.propostas_escopo where proposta_id = p_proposta_id;
    v_ordem := 0;
    for v_escopo in select value from jsonb_array_elements(p_dados -> 'escopo') loop
      v_ordem := v_ordem + 1;
      insert into propostas_mhs.propostas_escopo (proposta_id, ordem, inclusao, descricao)
      values (
        p_proposta_id, coalesce(nullif(v_escopo ->> 'ordem', '')::integer, v_ordem),
        coalesce(nullif(v_escopo ->> 'inclusao', '')::boolean, true),
        coalesce(nullif(trim(coalesce(v_escopo ->> 'descricao', v_escopo ->> 'description')), ''), 'Sem descricao')
      );
    end loop;
  end if;

  if p_dados ? 'referencias' then
    if jsonb_typeof(p_dados -> 'referencias') <> 'array' then
      raise exception 'referencias deve ser uma lista.' using errcode = '22023';
    end if;
    delete from propostas_mhs.propostas_referencias where proposta_id = p_proposta_id;
    for v_referencia in select value from jsonb_array_elements(p_dados -> 'referencias') loop
      insert into propostas_mhs.propostas_referencias (proposta_id, titulo, url, observacao, criado_por)
      values (
        p_proposta_id,
        coalesce(nullif(trim(coalesce(v_referencia ->> 'titulo', v_referencia ->> 'title')), ''), 'Referencia'),
        nullif(trim(coalesce(v_referencia ->> 'url', v_referencia ->> 'link')), ''),
        nullif(trim(v_referencia ->> 'observacao'), ''), auth.uid()
      );
    end loop;
  end if;

  if p_dados ? 'blocos' then
    if jsonb_typeof(p_dados -> 'blocos') <> 'array' then
      raise exception 'blocos deve ser uma lista.' using errcode = '22023';
    end if;
    delete from propostas_mhs.propostas_blocos where proposta_id = p_proposta_id;
    v_ordem := 0;
    for v_bloco in select value from jsonb_array_elements(p_dados -> 'blocos') loop
      v_ordem := v_ordem + 1;
      insert into propostas_mhs.propostas_blocos (
        proposta_id, bloco_versao_id, tipo, ordem, titulo, conteudo, conteudo_rico
      ) values (
        p_proposta_id, nullif(v_bloco ->> 'bloco_versao_id', '')::uuid,
        case upper(coalesce(v_bloco ->> 'tipo', 'OUTRO'))
          when 'TEXTO_TECNICO' then 'TEXTO_TECNICO' when 'ESCOPO' then 'ESCOPO'
          when 'CONDICAO' then 'CONDICAO' when 'OBSERVACAO' then 'OBSERVACAO'
          when 'PAGAMENTO' then 'PAGAMENTO' else 'OUTRO' end,
        coalesce(nullif(v_bloco ->> 'ordem', '')::integer, v_ordem),
        coalesce(nullif(trim(coalesce(v_bloco ->> 'titulo', v_bloco ->> 'title')), ''), 'Bloco'),
        coalesce(nullif(trim(coalesce(v_bloco ->> 'conteudo', v_bloco ->> 'content')), ''), ''),
        coalesce(v_bloco -> 'conteudo_rico', v_bloco -> 'richContent', '{}'::jsonb)
      );
    end loop;
  end if;

  if p_dados ? 'memoria_calculo' then
    if jsonb_typeof(p_dados -> 'memoria_calculo') <> 'object' then
      raise exception 'memoria_calculo deve ser um objeto.' using errcode = '22023';
    end if;
    update propostas_mhs.memorias_calculo
    set situacao = 'HISTORICA'
    where proposta_id = p_proposta_id and situacao = 'ATUAL';

    select coalesce(max(numero_calculo), 0) + 1 into v_numero_memoria
    from propostas_mhs.memorias_calculo where proposta_id = p_proposta_id;

    insert into propostas_mhs.memorias_calculo (
      proposta_id, numero_calculo, situacao, base_calculo, percentual_total,
      fator_venda, valor_resultado, observacao, criado_por
    ) values (
      p_proposta_id, v_numero_memoria, 'ATUAL',
      coalesce(nullif(p_dados #>> '{memoria_calculo,base_calculo}', '')::numeric, 0),
      coalesce(nullif(p_dados #>> '{memoria_calculo,percentual_total}', '')::numeric, 0),
      coalesce(nullif(p_dados #>> '{memoria_calculo,fator_venda}', '')::numeric, 1),
      coalesce(nullif(p_dados #>> '{memoria_calculo,valor_resultado}', '')::numeric, 0),
      nullif(trim(p_dados #>> '{memoria_calculo,observacao}'), ''), auth.uid()
    ) returning memoria_calculo_id into v_memoria_id;

    if jsonb_typeof(coalesce(p_dados #> '{memoria_calculo,linhas}', '[]'::jsonb)) <> 'array' then
      raise exception 'linhas da memoria_calculo deve ser uma lista.' using errcode = '22023';
    end if;
    v_ordem := 0;
    for v_linha in select value from jsonb_array_elements(coalesce(p_dados #> '{memoria_calculo,linhas}', '[]'::jsonb)) loop
      v_ordem := v_ordem + 1;
      insert into propostas_mhs.memorias_calculo_linhas (
        memoria_calculo_id, ordem, componente, aliquota_percentual, valor_calculado, valor_texto, aplicacao
      ) values (
        v_memoria_id, coalesce(nullif(v_linha ->> 'ordem', '')::integer, v_ordem),
        coalesce(nullif(trim(v_linha ->> 'componente'), ''), 'Componente'),
        nullif(v_linha ->> 'aliquota_percentual', '')::numeric,
        nullif(v_linha ->> 'valor_calculado', '')::numeric,
        nullif(trim(v_linha ->> 'valor_texto'), ''),
        nullif(trim(v_linha ->> 'aplicacao'), '')
      );
    end loop;
  end if;

  perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'ATUALIZADA', 'Conteudo da proposta salvo');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.salvar_item_catalogo_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_item_id uuid := nullif(p_dados ->> 'item_catalogo_id', '')::uuid;
  v_modalidade text := upper(coalesce(p_dados ->> 'modalidade', ''));
  v_item propostas_mhs.catalogo_itens%rowtype;
begin
  perform api.exigir_editor();
  if nullif(trim(p_dados ->> 'codigo'), '') is null or nullif(trim(p_dados ->> 'nome'), '') is null then
    raise exception 'Codigo e nome sao obrigatorios no catalogo.' using errcode = '22023';
  end if;
  if v_modalidade not in ('PRODUTO', 'SERVICO', 'COMPOSTO') then
    raise exception 'Modalidade deve ser PRODUTO, SERVICO ou COMPOSTO.' using errcode = '22023';
  end if;

  if v_item_id is null then
    insert into propostas_mhs.catalogo_itens (
      codigo, modalidade, nome, descricao_comercial, descricao_tecnica, ncm,
      unidade_padrao, ipi_padrao_percentual, dados_tecnicos, criado_por, atualizado_por
    ) values (
      trim(p_dados ->> 'codigo'), v_modalidade, trim(p_dados ->> 'nome'),
      nullif(trim(p_dados ->> 'descricao_comercial'), ''), nullif(trim(p_dados ->> 'descricao_tecnica'), ''),
      nullif(trim(p_dados ->> 'ncm'), ''), coalesce(nullif(trim(p_dados ->> 'unidade_padrao'), ''), 'UN'),
      coalesce(nullif(p_dados ->> 'ipi_padrao_percentual', '')::numeric, 0),
      coalesce(p_dados -> 'dados_tecnicos', '{}'::jsonb), auth.uid(), auth.uid()
    ) returning * into v_item;
  else
    update propostas_mhs.catalogo_itens
    set codigo = trim(p_dados ->> 'codigo'), modalidade = v_modalidade, nome = trim(p_dados ->> 'nome'),
        descricao_comercial = nullif(trim(p_dados ->> 'descricao_comercial'), ''),
        descricao_tecnica = nullif(trim(p_dados ->> 'descricao_tecnica'), ''),
        ncm = nullif(trim(p_dados ->> 'ncm'), ''),
        unidade_padrao = coalesce(nullif(trim(p_dados ->> 'unidade_padrao'), ''), unidade_padrao),
        ipi_padrao_percentual = coalesce(nullif(p_dados ->> 'ipi_padrao_percentual', '')::numeric, ipi_padrao_percentual),
        dados_tecnicos = coalesce(p_dados -> 'dados_tecnicos', dados_tecnicos),
        atualizado_por = auth.uid(), atualizado_em = now()
    where item_catalogo_id = v_item_id
    returning * into v_item;
    if not found then
      raise exception 'Item de catalogo nao encontrado.' using errcode = 'P0002';
    end if;
  end if;

  perform propostas_mhs.registrar_acao('CATALOGO_ITEM', v_item.item_catalogo_id, 'ATUALIZADA', 'Item de catalogo salvo');
  return to_jsonb(v_item);
end;
$$;

create or replace function api.criar_versao_composicao_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_item_id uuid := nullif(p_dados ->> 'item_catalogo_id', '')::uuid;
  v_composicao propostas_mhs.catalogo_composicoes%rowtype;
  v_versao_id uuid;
  v_numero integer;
  v_componente jsonb;
  v_ordem integer := 0;
  v_modalidade text;
begin
  perform api.exigir_editor();
  select modalidade into v_modalidade from propostas_mhs.catalogo_itens
  where item_catalogo_id = v_item_id for update;
  if not found then
    raise exception 'Item de catalogo nao encontrado.' using errcode = 'P0002';
  end if;
  if v_modalidade <> 'COMPOSTO' then
    raise exception 'Somente item com modalidade COMPOSTO pode receber composicao.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_dados -> 'componentes', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_dados -> 'componentes', '[]'::jsonb)) = 0 then
    raise exception 'Uma composicao exige ao menos um componente.' using errcode = '22023';
  end if;

  select * into v_composicao from propostas_mhs.catalogo_composicoes
  where item_catalogo_id = v_item_id for update;
  if not found then
    insert into propostas_mhs.catalogo_composicoes (
      item_catalogo_id, nome, descricao, criado_por, atualizado_por
    ) values (
      v_item_id, coalesce(nullif(trim(p_dados ->> 'nome'), ''), 'Composicao'),
      nullif(trim(p_dados ->> 'descricao'), ''), auth.uid(), auth.uid()
    ) returning * into v_composicao;
  end if;

  select coalesce(max(numero_versao), 0) + 1 into v_numero
  from propostas_mhs.catalogo_composicoes_versoes
  where composicao_id = v_composicao.composicao_id;

  insert into propostas_mhs.catalogo_composicoes_versoes (
    composicao_id, numero_versao, situacao, descricao_alteracao, criado_por
  ) values (
    v_composicao.composicao_id, v_numero, 'RASCUNHO',
    nullif(trim(p_dados ->> 'descricao_alteracao'), ''), auth.uid()
  ) returning composicao_versao_id into v_versao_id;

  for v_componente in select value from jsonb_array_elements(p_dados -> 'componentes') loop
    v_ordem := v_ordem + 1;
    if nullif(v_componente ->> 'item_catalogo_id', '')::uuid = v_item_id then
      raise exception 'Uma composicao nao pode conter ela mesma.' using errcode = '22023';
    end if;
    insert into propostas_mhs.catalogo_composicao_componentes (
      composicao_versao_id, item_catalogo_id, ordem, codigo_referencia, descricao,
      unidade, quantidade, cpmv_unitario, cpmv_total, observacao
    ) values (
      v_versao_id, nullif(v_componente ->> 'item_catalogo_id', '')::uuid,
      coalesce(nullif(v_componente ->> 'ordem', '')::integer, v_ordem),
      nullif(trim(v_componente ->> 'codigo_referencia'), ''),
      coalesce(nullif(trim(coalesce(v_componente ->> 'descricao', v_componente ->> 'description')), ''), 'Componente'),
      coalesce(nullif(trim(v_componente ->> 'unidade'), ''), 'UN'),
      coalesce(nullif(v_componente ->> 'quantidade', '')::numeric, 1),
      coalesce(nullif(v_componente ->> 'cpmv_unitario', '')::numeric, 0),
      coalesce(nullif(v_componente ->> 'cpmv_total', '')::numeric,
        coalesce(nullif(v_componente ->> 'quantidade', '')::numeric, 1) * coalesce(nullif(v_componente ->> 'cpmv_unitario', '')::numeric, 0)),
      nullif(trim(v_componente ->> 'observacao'), '')
    );
  end loop;

  update propostas_mhs.catalogo_composicoes_versoes
  set situacao = 'VIGENTE'
  where composicao_versao_id = v_versao_id;

  perform propostas_mhs.registrar_acao(
    'COMPOSICAO', v_composicao.composicao_id, 'REVISADA',
    'Composicao salva na versao ' || v_numero::text,
    jsonb_build_object('composicao_versao_id', v_versao_id)
  );
  return (select to_jsonb(v) from propostas_mhs.catalogo_composicoes_versoes v where v.composicao_versao_id = v_versao_id);
end;
$$;

create or replace function api.salvar_bloco_inteligente_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_bloco_id uuid := nullif(p_dados ->> 'bloco_id', '')::uuid;
  v_tipo text := upper(coalesce(p_dados ->> 'tipo', 'OUTRO'));
  v_bloco propostas_mhs.blocos_inteligentes%rowtype;
  v_versao propostas_mhs.blocos_inteligentes_versoes%rowtype;
  v_numero integer;
begin
  perform api.exigir_editor();
  if v_tipo not in ('TEXTO_TECNICO', 'ESCOPO', 'CONDICAO', 'OBSERVACAO', 'PAGAMENTO', 'OUTRO') then
    raise exception 'Tipo de bloco invalido.' using errcode = '22023';
  end if;
  if nullif(trim(p_dados ->> 'titulo'), '') is null then
    raise exception 'Titulo do bloco e obrigatorio.' using errcode = '22023';
  end if;

  if v_bloco_id is null then
    insert into propostas_mhs.blocos_inteligentes (
      tipo, titulo, tema, item_catalogo_id, criado_por, atualizado_por
    ) values (
      v_tipo, trim(p_dados ->> 'titulo'), nullif(trim(p_dados ->> 'tema'), ''),
      nullif(p_dados ->> 'item_catalogo_id', '')::uuid, auth.uid(), auth.uid()
    ) returning * into v_bloco;
  else
    select * into v_bloco from propostas_mhs.blocos_inteligentes
    where bloco_id = v_bloco_id for update;
    if not found then
      raise exception 'Bloco inteligente nao encontrado.' using errcode = 'P0002';
    end if;
    update propostas_mhs.blocos_inteligentes
    set tipo = v_tipo, titulo = trim(p_dados ->> 'titulo'),
        tema = coalesce(nullif(trim(p_dados ->> 'tema'), ''), tema),
        item_catalogo_id = coalesce(nullif(p_dados ->> 'item_catalogo_id', '')::uuid, item_catalogo_id),
        atualizado_por = auth.uid(), atualizado_em = now()
    where bloco_id = v_bloco_id returning * into v_bloco;
  end if;

  v_numero := v_bloco.versao_atual + 1;
  insert into propostas_mhs.blocos_inteligentes_versoes (
    bloco_id, numero_versao, titulo, conteudo, conteudo_rico, descricao_alteracao, criado_por
  ) values (
    v_bloco.bloco_id, v_numero, trim(p_dados ->> 'titulo'),
    coalesce(p_dados ->> 'conteudo', p_dados ->> 'content', ''),
    coalesce(p_dados -> 'conteudo_rico', p_dados -> 'richContent', '{}'::jsonb),
    nullif(trim(p_dados ->> 'descricao_alteracao'), ''), auth.uid()
  ) returning * into v_versao;

  update propostas_mhs.blocos_inteligentes
  set versao_atual = v_numero, atualizado_por = auth.uid(), atualizado_em = now()
  where bloco_id = v_bloco.bloco_id;

  perform propostas_mhs.registrar_acao('BLOCO_INTELIGENTE', v_bloco.bloco_id, 'REVISADA', 'Bloco salvo na versao ' || v_numero::text);
  return to_jsonb(v_versao);
end;
$$;

create or replace function api.detalhar_revisao_proposta_mhs(p_revisao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_snapshot jsonb;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  select dados_snapshot into v_snapshot from propostas_mhs.propostas_revisoes where revisao_id = p_revisao_id;
  if v_snapshot is null then
    raise exception 'Revisao nao encontrada.' using errcode = 'P0002';
  end if;
  return v_snapshot;
end;
$$;

revoke all on function
  api.salvar_conteudo_proposta_mhs(uuid, jsonb),
  api.salvar_item_catalogo_mhs(jsonb),
  api.criar_versao_composicao_mhs(jsonb),
  api.salvar_bloco_inteligente_mhs(jsonb),
  api.detalhar_revisao_proposta_mhs(uuid)
from public, anon;
grant execute on function
  api.salvar_conteudo_proposta_mhs(uuid, jsonb),
  api.salvar_item_catalogo_mhs(jsonb),
  api.criar_versao_composicao_mhs(jsonb),
  api.salvar_bloco_inteligente_mhs(jsonb),
  api.detalhar_revisao_proposta_mhs(uuid)
to authenticated;

notify pgrst, 'reload schema';
commit;

