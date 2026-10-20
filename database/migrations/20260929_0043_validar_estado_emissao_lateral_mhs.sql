-- Validacao somente-leitura. Execute depois da migracao 0042.

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in ('criar_revisao_idempotente_mhs', 'marcar_estado_revisao_mhs')
order by routine_name;

-- Todas devem retornar zero.
select count(*) as controles_sem_revisao
from propostas_mhs.propostas_revisoes_emissao e
where not exists (
  select 1 from propostas_mhs.propostas_revisoes r
  where r.revisao_id = e.revisao_id and r.proposta_id = e.proposta_id
);

select count(*) as revisoes_confirmadas_sem_pdf
from propostas_mhs.propostas_revisoes_emissao e
where e.estado = 'CONFIRMADA'
  and not exists (
    select 1 from propostas_mhs.arquivos_proposta a
    where a.proposta_id = e.proposta_id and a.revisao_id = e.revisao_id
      and a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO' and a.tamanho_bytes > 0
  );
