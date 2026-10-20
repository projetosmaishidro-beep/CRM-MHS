-- ============================================================================
-- PROPOSTAS MHS - RESPONSAVEL PELA ULTIMA GRAVACAO/EMISSAO
-- Execute apos 20260929_0032_autorizar_projetos1_editor_mhs.sql.
-- O criador e mantido para auditoria; o responsavel exibido e quem realizou a
-- ultima alteracao autenticada, inclusive a emissao da revisao vigente.
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
where api.eh_membro();

comment on view api.vw_propostas_mhs is
  'Lista autenticada de propostas. responsavel_email aponta para o ultimo usuario autenticado que gravou ou emitiu a proposta.';

grant select on api.vw_propostas_mhs to authenticated;

notify pgrst, 'reload schema';
commit;
