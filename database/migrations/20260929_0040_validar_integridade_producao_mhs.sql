-- Validacao somente-leitura. Execute depois da migracao 0039.

select column_name from information_schema.columns
where table_schema = 'propostas_mhs' and table_name = 'propostas'
  and column_name = 'versao_edicao';

select routine_name from information_schema.routines
where routine_schema = 'api' and routine_name in (
  'salvar_proposta_transacional_mhs', 'salvar_conjunto_reutilizavel_mhs',
  'criar_revisao_idempotente_mhs', 'marcar_estado_revisao_mhs',
  'registrar_pdf_revisao_idempotente_mhs'
)
order by routine_name;

-- A criacao de rascunho e a reserva de numero precisam ser operacoes validas.
select con.conname, pg_get_constraintdef(con.oid) as definicao
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace ns on ns.oid = rel.relnamespace
where ns.nspname = 'propostas_mhs'
  and rel.relname = 'historico_acoes'
  and con.conname = 'historico_acoes_operacao_check';

-- Todas devem retornar zero.
select count(*) as grupos_sem_opcao
from propostas_mhs.propostas_grupos where proposta_opcao_id is null;

select count(*) as opcoes_sem_grupo
from propostas_mhs.propostas_opcoes_comerciais o
where not exists (select 1 from propostas_mhs.propostas_grupos g where g.proposta_opcao_id = o.proposta_opcao_id);

select count(*) as revisoes_confirmadas_sem_pdf
from propostas_mhs.propostas_revisoes r
where r.estado_emissao = 'CONFIRMADA'
  and not exists (
    select 1 from propostas_mhs.arquivos_proposta a
    where a.revisao_id = r.revisao_id and a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO'
  );

select count(*) as pdfs_ativos_duplicados
from (
  select revisao_id, caminho_storage
  from propostas_mhs.arquivos_proposta
  where categoria = 'PDF_GERADO' and estado = 'ATIVO'
  group by revisao_id, caminho_storage having count(*) > 1
) duplicados;

select count(*) as propostas_com_totais_divergentes_da_ultima_memoria
from propostas_mhs.propostas p
join lateral (
  select m.base_calculo, m.valor_resultado
  from propostas_mhs.memorias_calculo m
  where m.proposta_id = p.proposta_id
  order by m.numero_calculo desc limit 1
) memoria on true
where abs(coalesce(p.valor_base_calculo, 0) - coalesce(memoria.base_calculo, 0)) > 0.01
   or abs(coalesce(p.valor_proposta, 0) - coalesce(memoria.valor_resultado, 0)) > 0.01;
