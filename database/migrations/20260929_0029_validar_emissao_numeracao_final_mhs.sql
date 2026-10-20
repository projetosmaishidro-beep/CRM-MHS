-- Validacao somente-leitura apos 20260929_0028_propostas_mhs_numeracao_na_emissao.sql.

select column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'propostas_mhs' and table_name = 'propostas'
  and column_name in ('ano', 'numero_sequencial', 'codigo')
order by ordinal_position;

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in ('criar_proposta_mhs', 'reservar_numeracao_proposta_mhs', 'criar_revisao_proposta_mhs')
order by routine_name;

select codigo, status, criado_em, atualizado_em
from propostas_mhs.propostas
where numero_sequencial is null
order by atualizado_em desc
limit 50;
