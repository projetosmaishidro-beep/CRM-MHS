-- ============================================================================
-- PROPOSTAS MHS - CANCELADAS FORA DA AREA OPERACIONAL
-- Execute apos 20260929_0033_responsavel_ultima_emissao_proposta_mhs.sql.
-- O cancelamento continua preservado no banco e na auditoria, mas propostas
-- canceladas nao sao devolvidas para a interface operacional.
-- ============================================================================

begin;

create or replace view api.vw_propostas_mhs as
select
  p.proposta_id, p.codigo, p.ano, p.numero_sequencial, p.empresa_id,
  coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
  e.razao_social, e.nome_fantasia, e.cnpj, e.municipio, e.uf,
  o.local_obra_id, o.nome as local_obra,
  p.assunto, p.obra, p.descricao, p.complexidade, p.status, p.tipo_fornecimento,
  p.moeda, p.valor_cpmv_total, p.valor_base_calculo, p.percentual_total,
  p.fator_venda, p.valor_proposta, p.versao_atual, p.enviada_em, p.finalizada_em,
  p.validade_ate, p.criado_por, p.atualizado_por, p.criado_em, p.atualizado_em,
  u.email as responsavel_email
from propostas_mhs.propostas p
join cadastro.empresas e on e.empresa_id = p.empresa_id
left join propostas_mhs.locais_obra o on o.local_obra_id = p.local_obra_id
left join auth.users u on u.id = p.atualizado_por
where api.eh_membro()
  and p.status <> 'CANCELADA';

comment on view api.vw_propostas_mhs is
  'Lista operacional autenticada de propostas ativas. Canceladas permanecem preservadas nas tabelas internas e na auditoria.';

grant select on api.vw_propostas_mhs to authenticated;

notify pgrst, 'reload schema';
commit;
