-- Validacao somente-leitura da responsabilidade atual das propostas.
select
  p.codigo,
  p.versao_atual,
  criador.email as criado_por_email,
  responsavel.email as responsavel_ultima_gravacao,
  p.atualizado_em
from propostas_mhs.propostas p
left join auth.users criador on criador.id = p.criado_por
left join auth.users responsavel on responsavel.id = p.atualizado_por
order by p.atualizado_em desc
limit 50;
