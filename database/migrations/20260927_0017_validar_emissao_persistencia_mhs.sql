-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - EMISSAO, ARQUIVOS E CAMPOS DA PROPOSTA MHS
-- Execute depois de 20260927_0016_propostas_mhs_persistencia_emissao.sql.
-- Nao cria, atualiza ou remove nenhum dado.
-- ============================================================================

-- 1. Confirma as funcoes que a interface usa para salvar e emitir.
select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in (
    'salvar_proposta_completa_com_historico_mhs',
    'detalhar_proposta_mhs',
    'criar_revisao_proposta_mhs',
    'registrar_arquivo_proposta_mhs',
    'atualizar_cabecalho_proposta_mhs'
  )
order by routine_name;

-- 2. Para cada proposta recente, evidencia se os grupos de campos foram
-- persistidos: cabecalho, cliente, calculo, revisao, anexos e PDF no bucket.
select
  p.codigo,
  p.status,
  p.moeda,
  p.valor_cpmv_total as cpmv_reais,
  p.valor_proposta as preco_reais,
  p.atualizado_em,
  (p.dados_cliente_snapshot is not null) as cliente_snapshot_salvo,
  (coalesce(p.dados_adicionais, '{}'::jsonb) ? 'mhs_ui_v1') as campos_interface_salvos,
  (coalesce(p.dados_adicionais #> '{mhs_ui_v1,commercialTerms}', '{}'::jsonb) ? 'bankDetails') as dados_bancarios_salvos,
  (coalesce(p.dados_adicionais #> '{mhs_ui_v1,technicalContent}', '{}'::jsonb) ? 'scopeAssets') as referencias_escopo_salvas,
  (coalesce(p.dados_adicionais #> '{mhs_ui_v1}', '{}'::jsonb) ? 'attachments') as anexos_metadata_salvos,
  count(distinct m.memoria_calculo_id) as memorias_calculo,
  count(distinct r.revisao_id) as revisoes,
  count(distinct a.arquivo_id) filter (where a.estado = 'ATIVO') as arquivos_registrados,
  count(distinct a.arquivo_id) filter (where a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO') as pdfs_registrados,
  count(distinct o.id) filter (where o.bucket_id = 'propostas-mhs') as objetos_confirmados_bucket
from propostas_mhs.propostas p
left join propostas_mhs.memorias_calculo m on m.proposta_id = p.proposta_id
left join propostas_mhs.propostas_revisoes r on r.proposta_id = p.proposta_id
left join propostas_mhs.arquivos_proposta a on a.proposta_id = p.proposta_id
left join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
group by p.proposta_id
order by p.atualizado_em desc
limit 50;

-- 3. Mostra cada arquivo e aponta qualquer divergencia entre metadado e bucket.
select
  p.codigo,
  r.numero_revisao,
  a.categoria,
  a.nome_original,
  a.tipo_mime,
  a.tamanho_bytes,
  a.caminho_storage,
  a.enviado_em,
  (o.id is not null) as existe_no_bucket
from propostas_mhs.arquivos_proposta a
join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
left join propostas_mhs.propostas_revisoes r on r.revisao_id = a.revisao_id
left join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
where a.estado = 'ATIVO'
order by a.enviado_em desc
limit 100;

-- 4. Uma emissao integra e aquela sem linhas retornadas abaixo.
select
  p.codigo,
  a.arquivo_id,
  a.caminho_storage,
  case
    when o.id is null then 'ARQUIVO_AUSENTE_NO_BUCKET'
    when a.categoria = 'PDF_GERADO' and a.revisao_id is null then 'PDF_SEM_REVISAO'
    when a.tamanho_bytes <= 0 then 'TAMANHO_INVALIDO'
    else null
  end as falha
from propostas_mhs.arquivos_proposta a
join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
left join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
where a.estado = 'ATIVO'
  and (o.id is null or (a.categoria = 'PDF_GERADO' and a.revisao_id is null) or a.tamanho_bytes <= 0)
order by a.enviado_em desc;
