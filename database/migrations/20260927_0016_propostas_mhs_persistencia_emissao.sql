-- ============================================================================
-- PROPOSTAS MHS - CABECALHO, CAMPOS COMPLETOS E EMISSAO DE ARQUIVOS
-- Execute depois de 20260927_0015_propostas_mhs_numeracao_e_moeda.sql.
-- ============================================================================

begin;

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

  -- Persistencia do cabecalho e de todos os campos de interface que nao sao
  -- normalizados em tabelas proprias. Binarios permanecem no Storage; aqui
  -- ficam apenas caminhos, metadados e conteudo textual estruturado.
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
  perform api.registrar_memoria_calculo_proposta_mhs(p_proposta_id, p_dados -> 'memoria_calculo');
  perform propostas_mhs.sincronizar_historico_catalogo_da_proposta(p_proposta_id);
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.detalhar_proposta_mhs(p_proposta_id uuid)
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
  v_snapshot := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);
  return v_snapshot || jsonb_build_object('arquivos', coalesce((
    select jsonb_agg(to_jsonb(a) order by a.enviado_em, a.nome_original)
    from propostas_mhs.arquivos_proposta a
    where a.proposta_id = p_proposta_id and a.estado = 'ATIVO'
  ), '[]'::jsonb));
end;
$$;

revoke all on function api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb) from public, anon;
grant execute on function api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
