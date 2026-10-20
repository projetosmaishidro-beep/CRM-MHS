-- ============================================================================
-- PROPOSTAS MHS - RECUPERACAO SEGURA DE TEMPLATES E BLOCOS TECNICOS
-- Execute apos 20260927_0009_propostas_mhs_grupos_comerciais.sql.
-- ============================================================================

begin;

create or replace view api.vw_blocos_inteligentes_mhs as
select
  b.bloco_id, b.tipo, b.titulo, b.tema, b.item_catalogo_id, b.ativo,
  b.versao_atual, b.criado_em, b.atualizado_em,
  v.bloco_versao_id, v.conteudo, v.conteudo_rico, v.descricao_alteracao,
  v.criado_por, v.criado_em as versao_criada_em
from propostas_mhs.blocos_inteligentes b
join propostas_mhs.blocos_inteligentes_versoes v
  on v.bloco_id = b.bloco_id and v.numero_versao = b.versao_atual
where b.ativo and api.eh_membro();
comment on view api.vw_blocos_inteligentes_mhs is
'Blocos tecnicos e comerciais recuperaveis, sempre na versao atual e somente para membros autenticados.';

grant select on api.vw_blocos_inteligentes_mhs to authenticated;

notify pgrst, 'reload schema';
commit;
