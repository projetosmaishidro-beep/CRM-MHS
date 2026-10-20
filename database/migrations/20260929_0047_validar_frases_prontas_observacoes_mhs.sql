-- Validacao somente-leitura. Execute depois da migracao 0046.

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in (
    'listar_frases_prontas_observacoes_mhs',
    'salvar_frase_pronta_observacao_mhs'
  )
order by routine_name;

select frase_pronta_id, ordem, conteudo, ativo, criado_em, atualizado_em
from propostas_mhs.frases_prontas_observacoes
order by ativo desc, ordem, criado_em;

-- Deve retornar zero: a biblioteca nao pode conter frases vazias ou excessivas.
select count(*) as frases_invalidas
from propostas_mhs.frases_prontas_observacoes
where length(trim(conteudo)) = 0 or length(conteudo) > 1000 or ordem <= 0;
