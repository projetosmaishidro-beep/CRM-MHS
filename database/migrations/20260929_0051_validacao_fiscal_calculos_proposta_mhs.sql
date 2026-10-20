-- ============================================================================
-- PROPOSTAS MHS - GUARDA FISCAL DOS CALCULOS COMERCIAIS
-- Execute depois de 20260929_0050_comissoes_destinos_proposta_mhs.sql.
-- Rejeita snapshots cuja matemática não reproduza o CPMV e as margens gravadas.
-- ============================================================================

begin;

create or replace function propostas_mhs.validar_calculos_comerciais_proposta_mhs(p_proposta_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_item record;
  v_partilha_comissao numeric := 0;
  v_tem_partilha boolean := false;
  v_financeiro_cobrado boolean;
  v_percentual numeric;
  v_fator numeric;
  v_cpmv_esperado numeric;
  v_preco_unitario_manual numeric;
  v_preco_unitario_esperado numeric;
  v_preco_total_esperado numeric;
begin
  select coalesce(sum(percentual_lucro), 0), count(*) > 0
  into v_partilha_comissao, v_tem_partilha
  from propostas_mhs.propostas_comissoes
  where proposta_id = p_proposta_id;

  for v_item in
    select i.proposta_item_id, i.cpmv_unitario, i.cpmv_total,
           i.preco_venda_unitario, i.preco_venda_total, i.quantidade as quantidade_item,
           i.dados_adicionais, g.proposta_grupo_id, g.ordem as grupo_ordem, g.quantidade as quantidade_grupo,
           g.modo_preco, g.impostos_percentual, g.margem_operacional_percentual,
           g.lucro_percentual, g.comissao_percentual, g.financeiro_mensal_percentual,
           g.prazo_medio_dias, p.dados_adicionais as proposta_dados
    from propostas_mhs.propostas_itens i
    join propostas_mhs.propostas_grupos g on g.proposta_grupo_id = i.proposta_grupo_id
    join propostas_mhs.propostas p on p.proposta_id = g.proposta_id
    where i.proposta_id = p_proposta_id
  loop
    v_cpmv_esperado := round(v_item.cpmv_unitario * v_item.quantidade_item * v_item.quantidade_grupo, 4);
    if abs(v_item.cpmv_total - v_cpmv_esperado) > 0.0001 then
      raise exception 'CPMV do item % diverge da quantidade e do custo unitario.', v_item.proposta_item_id
        using errcode = '23514';
    end if;

    v_financeiro_cobrado := coalesce(
      lower(v_item.proposta_dados #>> array['mhs_ui_v1', 'groupMetadata', (v_item.grupo_ordem - 1)::text, 'chargeFinanceToClient']) <> 'false',
      true
    );

    v_percentual := v_item.impostos_percentual
      + v_item.margem_operacional_percentual
      + v_item.lucro_percentual
      + case
          when v_tem_partilha then v_item.lucro_percentual * v_partilha_comissao / 100
          when jsonb_typeof(v_item.proposta_dados #> array['mhs_ui_v1', 'groupMetadata', (v_item.grupo_ordem - 1)::text, 'commissionProfitSharePct']) = 'number'
            then v_item.lucro_percentual * (v_item.proposta_dados #>> array['mhs_ui_v1', 'groupMetadata', (v_item.grupo_ordem - 1)::text, 'commissionProfitSharePct'])::numeric / 100
          else v_item.comissao_percentual
        end
      + case when v_financeiro_cobrado then v_item.financeiro_mensal_percentual * v_item.prazo_medio_dias / 30 else 0 end;
    if v_percentual >= 100 then
      raise exception 'As alíquotas do grupo % atingem ou ultrapassam 100%%.', v_item.proposta_grupo_id
        using errcode = '23514';
    end if;
    v_fator := 1 / (1 - v_percentual / 100);

    if jsonb_typeof(v_item.dados_adicionais #> '{mhs_ui_v1,manualUnitPrice}') = 'number' then
      v_preco_unitario_manual := (v_item.dados_adicionais #>> '{mhs_ui_v1,manualUnitPrice}')::numeric;
    else
      v_preco_unitario_manual := null;
    end if;
    v_preco_unitario_esperado := coalesce(v_preco_unitario_manual, ceil(v_item.cpmv_unitario * v_fator * 10) / 10);
    v_preco_total_esperado := ceil(v_preco_unitario_esperado * v_item.quantidade_item * v_item.quantidade_grupo * 10) / 10;

    -- Preço total manual do grupo é uma exceção comercial explícita e já possui
    -- fluxo de justificativa próprio. Os itens continuam auditados pelo CPMV.
    if v_item.modo_preco <> 'MANUAL' and (
      abs(v_item.preco_venda_unitario - v_preco_unitario_esperado) > 0.0001
      or abs(v_item.preco_venda_total - v_preco_total_esperado) > 0.0001
    ) then
      raise exception 'Preço calculado do item % não corresponde ao CPMV e às alíquotas da proposta.', v_item.proposta_item_id
        using errcode = '23514';
    end if;
  end loop;
end;
$$;

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
  perform propostas_mhs.validar_calculos_comerciais_proposta_mhs(p_proposta_id);
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

revoke all on function propostas_mhs.validar_calculos_comerciais_proposta_mhs(uuid) from public, anon, authenticated;
grant execute on function api.salvar_proposta_transacional_mhs(uuid, jsonb, jsonb, jsonb, bigint) to authenticated;

notify pgrst, 'reload schema';
commit;
