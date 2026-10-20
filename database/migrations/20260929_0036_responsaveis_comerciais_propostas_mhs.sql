-- ============================================================================
-- PROPOSTAS MHS - NOMES DOS RESPONSAVEIS COMERCIAIS
-- Execute apos 20260929_0035_ocultar_propostas_canceladas_mhs.sql.
-- Atualiza somente o nome de membros ja vinculados ao respectivo usuario Auth.
-- Papeis, status e permissoes permanecem inalterados.
-- ============================================================================

begin;

update cadastro.equipe e
set nome = case split_part(lower(u.email), '@', 1)
  when 'comercial1' then 'Ricardo Lopes de Castro Alves'
  when 'comercial2' then 'Bárbara Leteicia Vieira'
  when 'comercial3' then 'Jefferson Ramires'
  when 'projetos1' then 'Luan'
  when 'projetos2' then 'Sebastião'
  when 'automacao' then 'Francis Ramire Segóvia'
  else e.nome
end,
atualizado_em = now()
from auth.users u
where e.usuario_id = u.id
  and lower(u.email) in (
    'comercial1@maisintegradora.com.br',
    'comercial2@maisintegradora.com.br',
    'comercial3@maisintegradora.com.br',
    'projetos1@maisintegradora.com.br',
    'projetos2@maisintegradora.com.br',
    'automacao@maisintegradora.com.br'
  );

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
  u.email as responsavel_email,
  coalesce(responsavel.nome, u.email, 'Responsavel nao identificado') as responsavel_nome
from propostas_mhs.propostas p
join cadastro.empresas e on e.empresa_id = p.empresa_id
left join propostas_mhs.locais_obra o on o.local_obra_id = p.local_obra_id
left join auth.users u on u.id = p.atualizado_por
left join cadastro.equipe responsavel on responsavel.usuario_id = p.atualizado_por and responsavel.ativo
where api.eh_membro()
  and p.status <> 'CANCELADA';

create or replace function api.detalhar_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_snapshot jsonb;
  v_responsavel jsonb;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;

  v_snapshot := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);
  if v_snapshot is null then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'responsavel_nome', coalesce(e.nome, u.email, 'Responsavel nao identificado'),
    'responsavel_email', u.email
  ) into v_responsavel
  from propostas_mhs.propostas p
  left join auth.users u on u.id = p.atualizado_por
  left join cadastro.equipe e on e.usuario_id = p.atualizado_por and e.ativo
  where p.proposta_id = p_proposta_id;

  v_snapshot := jsonb_set(
    v_snapshot,
    '{proposta}',
    coalesce(v_snapshot -> 'proposta', '{}'::jsonb) || coalesce(v_responsavel, '{}'::jsonb),
    true
  );

  return v_snapshot || jsonb_build_object('arquivos', coalesce((
    select jsonb_agg(to_jsonb(a) order by a.enviado_em, a.nome_original)
    from propostas_mhs.arquivos_proposta a
    where a.proposta_id = p_proposta_id and a.estado = 'ATIVO'
  ), '[]'::jsonb));
end;
$$;

grant select on api.vw_propostas_mhs to authenticated;
grant execute on function api.detalhar_proposta_mhs(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
