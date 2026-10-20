-- ============================================================================
-- PROPOSTAS MHS - ORIGEM VERSIONADA DE TEMPLATE
-- Execute depois de 20260927_0021_propostas_mhs_integridade_revisao_atual.sql.
-- ============================================================================

begin;

-- A proposta pode registrar de qual template foi criada para permitir uma
-- atualizacao versionada. O proprio template, entretanto, nunca herda essa
-- referencia para evitar encadeamento ou autorreferencia entre modelos.
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
  v_proposta_meta jsonb;
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
  v_proposta_meta := coalesce(v_interface -> 'proposalMeta', '{}'::jsonb) - 'templateSource';
  v_interface := v_interface || jsonb_build_object('proposalMeta', v_proposta_meta);
  v_dados_adicionais := v_dados_adicionais || jsonb_build_object('mhs_ui_v1', v_interface);
  v_cabecalho := jsonb_set(v_cabecalho, '{dados_adicionais}', v_dados_adicionais, true);

  return (v_snapshot - 'cliente_atual' - 'local_obra' - 'memoria_calculo') ||
    jsonb_build_object('proposta', v_cabecalho, 'memoria_calculo', v_memoria_atual);
end;
$$;

revoke all on function propostas_mhs.montar_snapshot_template_proposta_mhs(uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
