-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - PRONTIDAO OPERACIONAL MHS
-- Execute depois de 20260927_0021_propostas_mhs_integridade_revisao_atual.sql.
-- Nao cria, atualiza ou remove nenhum dado.
-- ============================================================================

-- 1. Confirma as funcoes e o trigger exigidos pela interface atual.
select routine_schema, routine_name
from information_schema.routines
where (routine_schema, routine_name) in (
  ('api', 'salvar_proposta_completa_com_historico_mhs'),
  ('api', 'registrar_arquivo_proposta_mhs'),
  ('api', 'arquivar_arquivo_proposta_mhs'),
  ('api', 'confirmar_revisao_proposta_mhs'),
  ('propostas_mhs', 'validar_pdf_revisao_atual')
)
order by routine_schema, routine_name;

select trigger_name, event_manipulation, action_timing
from information_schema.triggers
where event_object_schema = 'propostas_mhs'
  and event_object_table = 'propostas'
  and trigger_name = 'propostas_validar_pdf_revisao_atual';

-- 2. Nenhuma proposta finalizada deve ficar sem PDF na revisao atual.
select p.codigo, p.versao_atual, p.status
from propostas_mhs.propostas p
where p.status = 'FINALIZADA'
  and not exists (
    select 1
    from propostas_mhs.propostas_revisoes r
    join propostas_mhs.arquivos_proposta a on a.proposta_id = r.proposta_id and a.revisao_id = r.revisao_id
    join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
    where r.proposta_id = p.proposta_id
      and r.numero_revisao = p.versao_atual
      and a.categoria = 'PDF_GERADO'
      and a.estado = 'ATIVO'
      and a.tamanho_bytes > 0
  );

-- 3. Metadados ativos precisam apontar para objeto presente no Storage.
select p.codigo, a.arquivo_id, a.revisao_id, a.caminho_storage, a.categoria
from propostas_mhs.arquivos_proposta a
join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
left join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
where a.estado = 'ATIVO' and o.id is null
order by a.enviado_em desc;

-- 4. Rascunhos ativos sao esperados; eles evidenciam anexos preservados antes
-- da emissao e permitem acompanhamento operacional sem apagar dados.
select p.codigo, a.nome_original, a.categoria, a.enviado_em, a.caminho_storage
from propostas_mhs.arquivos_proposta a
join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
where a.estado = 'ATIVO'
  and a.revisao_id is null
  and a.caminho_storage like 'clientes/%/propostas/%/rascunhos/%'
order by a.enviado_em desc;

-- 5. A memoria atual deve existir para propostas que possuem itens comerciais.
select p.codigo
from propostas_mhs.propostas p
where exists (select 1 from propostas_mhs.propostas_itens i where i.proposta_id = p.proposta_id)
  and not exists (
    select 1 from propostas_mhs.memorias_calculo m
    where m.proposta_id = p.proposta_id and m.situacao = 'ATUAL'
  )
order by p.atualizado_em desc;
