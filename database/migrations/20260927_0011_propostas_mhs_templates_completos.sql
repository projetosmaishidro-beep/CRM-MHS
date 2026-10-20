-- ============================================================================
-- PROPOSTAS MHS - TEMPLATES COMPLETOS COM GRUPOS COMERCIAIS
-- Execute apos 20260927_0010_propostas_mhs_recuperacao.sql.
-- ============================================================================

begin;

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
  v_cabecalho jsonb;
  v_numero integer;
begin
  perform api.exigir_editor();
  if nullif(trim(p_nome), '') is null then
    raise exception 'Informe um nome para o template.' using errcode = '22023';
  end if;

  v_dados := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);
  v_dados := v_dados - 'cliente_atual' - 'local_obra';
  v_cabecalho := coalesce(v_dados -> 'proposta', '{}'::jsonb)
    - 'proposta_id' - 'empresa_id' - 'local_obra_id' - 'visita_origem_id'
    - 'dados_cliente_snapshot' - 'codigo' - 'ano' - 'numero_sequencial'
    - 'criado_por' - 'atualizado_por' - 'criado_em' - 'atualizado_em';
  v_dados := jsonb_set(v_dados, '{proposta}', v_cabecalho, true);

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

  perform propostas_mhs.registrar_acao('TEMPLATE', v_template.template_id, 'REVISADA', 'Template completo salvo na versao ' || v_numero::text);
  return jsonb_build_object('template_id', v_template.template_id, 'template_versao_id', v_versao.template_versao_id, 'numero_versao', v_numero, 'dados_modelo', v_dados);
end;
$$;

revoke all on function api.salvar_template_proposta_mhs_v2(uuid, text, text, text, text, uuid) from public, anon;
grant execute on function api.salvar_template_proposta_mhs_v2(uuid, text, text, text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
