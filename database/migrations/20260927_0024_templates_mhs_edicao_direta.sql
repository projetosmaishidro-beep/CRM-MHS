-- ============================================================================
-- PROPOSTAS MHS - EDICAO DIRETA DE TEMPLATES SEM PROPOSTA OU CLIENTE
-- Execute depois de 20260927_0023_templates_mhs_origem_versionada.sql.
-- ============================================================================

begin;

create or replace function api.salvar_template_direto_mhs(
  p_nome text,
  p_modelo jsonb,
  p_template_id uuid default null,
  p_tema text default null,
  p_produto_referencia text default null,
  p_resumo_alteracao text default null
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
  if jsonb_typeof(coalesce(p_modelo, '{}'::jsonb)) <> 'object' then
    raise exception 'O modelo do template deve ser um objeto JSON.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_modelo -> 'groups', '[]'::jsonb)) <> 'array' then
    raise exception 'groups deve ser uma lista no modelo do template.' using errcode = '22023';
  end if;

  -- O contrato mhs_template_v1 guarda somente o modelo comercial da interface;
  -- nao contem cliente, proposta, numeracao nem campos de emissao.
  v_dados := jsonb_build_object('mhs_template_v1', p_modelo - 'templateSource' - 'templateEditorMode');

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

  perform propostas_mhs.registrar_acao('TEMPLATE', v_template.template_id, 'REVISADA', 'Template salvo pelo editor direto na versao ' || v_numero::text);
  return jsonb_build_object('template_id', v_template.template_id, 'template_versao_id', v_versao.template_versao_id, 'numero_versao', v_numero, 'dados_modelo', v_dados);
end;
$$;

revoke all on function api.salvar_template_direto_mhs(text, jsonb, uuid, text, text, text) from public, anon;
grant execute on function api.salvar_template_direto_mhs(text, jsonb, uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
