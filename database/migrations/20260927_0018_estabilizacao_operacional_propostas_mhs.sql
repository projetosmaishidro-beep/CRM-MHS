-- ============================================================================
-- PROPOSTAS MHS - ESTABILIZACAO OPERACIONAL DE EMISSAO E TOTAIS
-- Execute depois de 20260927_0017_validar_emissao_persistencia_mhs.sql.
-- Aditiva: nao altera nem reaplica o historico de migracoes anterior.
-- ============================================================================

begin;

-- O cabecalho e a memoria passam a refletir os grupos e itens que efetivamente
-- foram persistidos. Preco manual vale somente para grupos sem item composto,
-- reproduzindo a mesma regra usada pela interface comercial.
create or replace function propostas_mhs.recalcular_totais_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_base numeric(19,4);
  v_valor numeric(19,4);
  v_percentual numeric(19,6);
  v_fator numeric(19,10);
begin
  select
    coalesce(sum(g.base_cpmv), 0),
    coalesce(sum(case
      when g.modo_preco = 'MANUAL' and not g.tem_item_composto
        then g.preco_manual_total
      else g.preco_calculado
    end), 0)
  into v_base, v_valor
  from (
    select
      pg.proposta_grupo_id,
      pg.modo_preco,
      pg.preco_manual_total,
      coalesce(sum(i.cpmv_total), 0) as base_cpmv,
      coalesce(sum(i.preco_venda_total), 0) as preco_calculado,
      coalesce(bool_or(i.modalidade = 'COMPOSTO'), false) as tem_item_composto
    from propostas_mhs.propostas_grupos pg
    left join propostas_mhs.propostas_itens i on i.proposta_grupo_id = pg.proposta_grupo_id
    where pg.proposta_id = p_proposta_id
    group by pg.proposta_grupo_id, pg.modo_preco, pg.preco_manual_total
  ) g;

  v_fator := case when v_base > 0 then v_valor / v_base else 1 end;
  v_percentual := case when v_base > 0 then (v_fator - 1) * 100 else 0 end;

  update propostas_mhs.propostas
  set valor_cpmv_total = v_base,
      valor_base_calculo = v_base,
      percentual_total = v_percentual,
      fator_venda = v_fator,
      valor_proposta = v_valor,
      atualizado_por = auth.uid(),
      atualizado_em = now()
  where proposta_id = p_proposta_id;

  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'valor_base_calculo', v_base,
    'percentual_total', v_percentual,
    'fator_venda', v_fator,
    'valor_proposta', v_valor
  );
end;
$$;

-- O autosave comercial nao pode alterar o catalogo mestre. Atualizacoes de
-- CPMV e preco de catalogo continuam exclusivas das APIs explicitas de catalogo.
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
  v_totais jsonb;
  v_memoria jsonb;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_dados, '{}'::jsonb)) <> 'object' then
    raise exception 'Os dados da proposta devem ser um objeto JSON.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_dados -> 'memoria_calculo', '{}'::jsonb)) <> 'object' then
    raise exception 'memoria_calculo deve ser um objeto.' using errcode = '22023';
  end if;

  update propostas_mhs.propostas
  set assunto = coalesce(nullif(trim(p_dados #>> '{cabecalho,assunto}'), ''), assunto),
      descricao = coalesce(nullif(trim(p_dados #>> '{cabecalho,notas_internas}'), ''), descricao),
      dados_cliente_snapshot = coalesce(p_dados -> 'cliente_snapshot', dados_cliente_snapshot),
      dados_adicionais = coalesce(dados_adicionais, '{}'::jsonb) || jsonb_build_object(
        'mhs_ui_v1', coalesce(p_dados -> 'mhs_ui_v1', '{}'::jsonb),
        'atencao_a', nullif(trim(p_dados #>> '{cabecalho,atencao_a}'), ''),
        'previsao_conclusao', nullif(trim(p_dados #>> '{cabecalho,previsao_conclusao}'), '')
      ),
      atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  v_dados_sem_memoria := p_dados - 'memoria_calculo';
  perform api.salvar_proposta_completa_mhs(p_proposta_id, v_dados_sem_memoria);
  v_totais := propostas_mhs.recalcular_totais_proposta_mhs(p_proposta_id);
  v_memoria := coalesce(p_dados -> 'memoria_calculo', '{}'::jsonb) || jsonb_build_object(
    'base_calculo', v_totais -> 'valor_base_calculo',
    'percentual_total', v_totais -> 'percentual_total',
    'fator_venda', v_totais -> 'fator_venda',
    'valor_resultado', v_totais -> 'valor_proposta'
  );
  perform api.registrar_memoria_calculo_proposta_mhs(p_proposta_id, v_memoria);
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

-- Confirma que a revisao pertence a proposta e que o PDF registrado existe no
-- bucket antes que a interface permita a finalizacao.
create or replace function api.confirmar_revisao_proposta_mhs(
  p_proposta_id uuid,
  p_revisao_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare
  v_revisao propostas_mhs.propostas_revisoes%rowtype;
begin
  perform api.exigir_editor();
  select * into v_revisao
  from propostas_mhs.propostas_revisoes
  where revisao_id = p_revisao_id and proposta_id = p_proposta_id;
  if not found then
    raise exception 'Revisao nao pertence a proposta informada.' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from propostas_mhs.arquivos_proposta a
    join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
    where a.proposta_id = p_proposta_id
      and a.revisao_id = p_revisao_id
      and a.categoria = 'PDF_GERADO'
      and a.estado = 'ATIVO'
      and a.tamanho_bytes > 0
  ) then
    raise exception 'A revisao nao possui PDF confirmado no bucket.' using errcode = '55000';
  end if;

  return jsonb_build_object('revisao_id', v_revisao.revisao_id, 'numero_revisao', v_revisao.numero_revisao, 'confirmada', true);
end;
$$;

-- A finalizacao e bloqueada sem uma revisao com PDF efetivamente presente.
create or replace function api.atualizar_cabecalho_proposta_mhs(p_proposta_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare
  v_status text;
begin
  perform api.exigir_editor();
  v_status := case upper(coalesce(p_dados ->> 'status', ''))
    when 'RASCUNHO' then 'RASCUNHO' when 'EM_EDICAO' then 'EM_EDICAO'
    when 'EM REVISAO' then 'EM_REVISAO' when 'EM_REVISAO' then 'EM_REVISAO'
    when 'ENVIADA' then 'ENVIADA' when 'APROVADA' then 'APROVADA'
    when 'RECUSADA' then 'RECUSADA' when 'CANCELADA' then 'CANCELADA'
    when 'FINALIZADA' then 'FINALIZADA' else null
  end;

  if v_status = 'FINALIZADA' and not exists (
    select 1
    from propostas_mhs.propostas_revisoes r
    join propostas_mhs.arquivos_proposta a on a.revisao_id = r.revisao_id and a.proposta_id = r.proposta_id
    join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
    where r.proposta_id = p_proposta_id
      and a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO' and a.tamanho_bytes > 0
  ) then
    raise exception 'Uma proposta so pode ser finalizada depois que o PDF da revisao estiver confirmado no bucket.' using errcode = '55000';
  end if;

  update propostas_mhs.propostas
  set assunto = coalesce(nullif(trim(coalesce(p_dados ->> 'assunto', p_dados ->> 'subject')), ''), assunto),
      obra = coalesce(nullif(trim(coalesce(p_dados ->> 'obra', p_dados ->> 'project')), ''), obra),
      descricao = coalesce(nullif(trim(coalesce(p_dados ->> 'descricao', p_dados ->> 'description')), ''), descricao),
      complexidade = case upper(coalesce(p_dados ->> 'complexidade', '')) when 'BAIXA' then 'BAIXA' when 'MEDIA' then 'MEDIA' when 'ALTA' then 'ALTA' when 'ESPECIAL' then 'ESPECIAL' else complexidade end,
      tipo_fornecimento = case upper(coalesce(p_dados ->> 'tipo_fornecimento', '')) when 'PRODUTOS' then 'PRODUTOS' when 'SERVICOS' then 'SERVICOS' when 'COMPOSTOS' then 'COMPOSTOS' when 'MISTO' then 'MISTO' else tipo_fornecimento end,
      status = coalesce(v_status, status),
      validade_ate = coalesce(nullif(p_dados ->> 'validade_ate', '')::date, validade_ate),
      valor_cpmv_total = coalesce(nullif(p_dados ->> 'valor_cpmv_total', '')::numeric, valor_cpmv_total),
      valor_base_calculo = coalesce(nullif(p_dados ->> 'valor_base_calculo', '')::numeric, valor_base_calculo),
      percentual_total = coalesce(nullif(p_dados ->> 'percentual_total', '')::numeric, percentual_total),
      fator_venda = coalesce(nullif(p_dados ->> 'fator_venda', '')::numeric, fator_venda),
      valor_proposta = coalesce(nullif(p_dados ->> 'valor_proposta', '')::numeric, valor_proposta),
      enviada_em = case when v_status = 'ENVIADA' then coalesce(enviada_em, now()) else enviada_em end,
      finalizada_em = case when v_status = 'FINALIZADA' then coalesce(finalizada_em, now()) else finalizada_em end,
      atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'ATUALIZADA', 'Cabecalho atualizado');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

revoke all on function propostas_mhs.recalcular_totais_proposta_mhs(uuid) from public, anon, authenticated;
revoke all on function api.confirmar_revisao_proposta_mhs(uuid, uuid) from public, anon;
grant execute on function api.confirmar_revisao_proposta_mhs(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
