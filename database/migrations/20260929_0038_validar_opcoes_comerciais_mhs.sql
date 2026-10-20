-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - OPCOES COMERCIAIS MHS
-- Execute depois de 20260929_0037_opcoes_comerciais_propostas_mhs.sql.
-- ============================================================================

select table_name
from information_schema.tables
where table_schema = 'propostas_mhs'
  and table_name = 'propostas_opcoes_comerciais';

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in ('sincronizar_opcoes_comerciais_proposta_mhs', 'detalhar_proposta_mhs');

-- Nenhuma linha deve ser retornada: todo grupo precisa apontar para uma opcao.
select p.codigo, g.proposta_grupo_id, g.ordem, g.titulo
from propostas_mhs.propostas_grupos g
join propostas_mhs.propostas p on p.proposta_id = g.proposta_id
where g.proposta_opcao_id is null;

-- Evidencia cada alternativa e os grupos que a compoem.
select
  p.codigo,
  o.ordem as ordem_opcao,
  o.titulo as opcao,
  count(g.proposta_grupo_id) as grupos,
  coalesce(sum(case when g.modo_preco = 'MANUAL' then g.preco_manual_total else 0 end), 0) as totais_manuais_reais
from propostas_mhs.propostas_opcoes_comerciais o
join propostas_mhs.propostas p on p.proposta_id = o.proposta_id
left join propostas_mhs.propostas_grupos g on g.proposta_opcao_id = o.proposta_opcao_id
group by p.codigo, o.proposta_opcao_id
order by p.codigo, o.ordem;
