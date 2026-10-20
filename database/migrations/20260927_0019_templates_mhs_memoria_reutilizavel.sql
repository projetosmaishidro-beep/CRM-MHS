-- ============================================================================
-- PROPOSTAS MHS - TEMPLATE REUTILIZAVEL COM MEMORIA ATUAL DE CALCULO
-- Execute depois de 20260927_0018_estabilizacao_operacional_propostas_mhs.sql.
-- ============================================================================

begin;

-- O template recebe o modelo comercial completo, mas nunca a identidade do
-- cliente. A memoria armazenada e somente a memoria ATUAL da proposta de
-- origem, com seus componentes e valores, sem IDs ou autoria da proposta.
create or replace function propostas_mhs.montar_snapshot_template_proposta_mhs(
  p_proposta_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_snapshot jsonb;
  v_cabecalho jsonb;
  v_dados_adicionais jsonb;
  v_interface jsonb;
  v_memoria_atual jsonb;
begin
  v_snapshot := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);

  select coalesce(jsonb_agg(
    (to_jsonb(m) - 'memoria_calculo_id' - 'proposta_id' - 'criado_por') ||
    jsonb_build_object('linhas', coalesce((
      select jsonb_agg(to_jsonb(l) - 'memoria_calculo_linha_id' - 'memoria_calculo_id' order by l.ordem)
      from propostas_mhs.memorias_calculo_linhas l
      where l.memoria_calculo_id = m.memoria_calculo_id
    ), '[]'::jsonb))
  ), '[]'::jsonb)
  into v_memoria_atual
  from propostas_mhs.memorias_calculo m
  where m.proposta_id = p_proposta_id and m.situacao = 'ATUAL';

  v_cabecalho := coalesce(v_snapshot -> 'proposta', '{}'::jsonb)
    - 'proposta_id' - 'empresa_id' - 'local_obra_id' - 'visita_origem_id'
    - 'dados_cliente_snapshot' - 'codigo' - 'ano' - 'numero_sequencial'
    - 'criado_por' - 'atualizado_por' - 'criado_em' - 'atualizado_em';
  v_dados_adicionais := coalesce(v_cabecalho -> 'dados_adicionais', '{}'::jsonb);
  v_interface := coalesce(v_dados_adicionais -> 'mhs_ui_v1', '{}'::jsonb)
    - 'attentionTo' - 'firstPdfGeneratedAt';
  v_dados_adicionais := v_dados_adicionais || jsonb_build_object('mhs_ui_v1', v_interface);
  v_cabecalho := jsonb_set(v_cabecalho, '{dados_adicionais}', v_dados_adicionais, true);

  return (v_snapshot - 'cliente_atual' - 'local_obra' - 'memoria_calculo') ||
    jsonb_build_object('proposta', v_cabecalho, 'memoria_calculo', v_memoria_atual);
end;
$$;

create or replace function api.salvar_template_proposta_mhs_v2(
  p_proposta_id uuid,
  p_nome text,
  p_tema text default null,
  p_produto_referencia text default null,
  p_resumo_alteracao text default null,
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_template propostas_mhs.templates%rowtype;
  v_versao propostas_mhs.templates_versoes%rowtype;
  v_dados jsonb;
  v_numero integer;
begin
  perform api.exigir_editor();
  if nullif(trim(p_nome), '') is null then
    raise exception 'Informe um nome para o template.' using errcode = '22023';
  end if;

  v_dados := propostas_mhs.montar_snapshot_template_proposta_mhs(p_proposta_id);

  if p_template_id is null then
    insert into propostas_mhs.templates (nome, tema, produto_referencia, descricao, criado_por, atualizado_por)
    values (trim(p_nome), nullif(trim(p_tema), ''), nullif(trim(p_produto_referencia), ''), nullif(trim(p_resumo_alteracao), ''), auth.uid(), auth.uid())
    returning * into v_template;
  else
    select * into v_template from propostas_mhs.templates where template_id = p_template_id for update;
    if not found then raise exception 'Template nao encontrado.' using errcode = 'P0002'; end if;
    update propostas_mhs.templates
    set nome = trim(p_nome), tema = coalesce(nullif(trim(p_tema), ''), tema),
        produto_referencia = coalesce(nullif(trim(p_produto_referencia), ''), produto_referencia),
        descricao = coalesce(nullif(trim(p_resumo_alteracao), ''), descricao),
        atualizado_por = auth.uid(), atualizado_em = now()
    where template_id = p_template_id returning * into v_template;
  end if;

  v_numero := v_template.versao_atual + 1;
  insert into propostas_mhs.templates_versoes (template_id, numero_versao, resumo_alteracao, dados_modelo, criado_por)
  values (v_template.template_id, v_numero, nullif(trim(p_resumo_alteracao), ''), v_dados, auth.uid())
  returning * into v_versao;

  update propostas_mhs.templates
  set versao_atual = v_numero, situacao = 'ATIVO', atualizado_por = auth.uid(), atualizado_em = now()
  where template_id = v_template.template_id;

  perform propostas_mhs.registrar_acao('TEMPLATE', v_template.template_id, 'REVISADA', 'Template comercial completo salvo na versao ' || v_numero::text);
  return jsonb_build_object('template_id', v_template.template_id, 'template_versao_id', v_versao.template_versao_id, 'numero_versao', v_numero, 'dados_modelo', v_dados);
end;
$$;

revoke all on function propostas_mhs.montar_snapshot_template_proposta_mhs(uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
