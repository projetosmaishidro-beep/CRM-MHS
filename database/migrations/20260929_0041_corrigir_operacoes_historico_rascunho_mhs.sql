-- ============================================================================
-- PROPOSTAS MHS - OPERACOES DE RASCUNHO E NUMERACAO NO HISTORICO
-- Corrige a incompatibilidade introduzida pela criacao de rascunhos sem numero.
-- Execute depois de 20260929_0040_validar_integridade_producao_mhs.sql.
-- ============================================================================

begin;

alter table propostas_mhs.historico_acoes
  drop constraint if exists historico_acoes_operacao_check;

alter table propostas_mhs.historico_acoes
  add constraint historico_acoes_operacao_check check (
    operacao in (
      'CRIADA', 'RASCUNHO_CRIADO', 'NUMERADA', 'ATUALIZADA', 'ARQUIVADA',
      'RESTAURADA', 'REVISADA', 'EMITIDA', 'ENVIADA', 'APROVADA', 'RECUSADA',
      'FINALIZADA', 'EXCLUIDA_LOGICAMENTE'
    )
  );

create or replace function propostas_mhs.registrar_acao(
  p_entidade text,
  p_entidade_id uuid,
  p_operacao text,
  p_resumo text default null,
  p_metadados jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
begin
  if p_operacao not in (
    'CRIADA', 'RASCUNHO_CRIADO', 'NUMERADA', 'ATUALIZADA', 'ARQUIVADA',
    'RESTAURADA', 'REVISADA', 'EMITIDA', 'ENVIADA', 'APROVADA', 'RECUSADA',
    'FINALIZADA', 'EXCLUIDA_LOGICAMENTE'
  ) then
    raise exception 'Operacao de historico invalida: %', p_operacao using errcode = '22023';
  end if;

  insert into propostas_mhs.historico_acoes (
    entidade, entidade_id, operacao, resumo, metadados, usuario_id
  ) values (
    p_entidade, p_entidade_id, p_operacao, nullif(trim(p_resumo), ''),
    coalesce(p_metadados, '{}'::jsonb), auth.uid()
  );
end;
$$;

revoke all on function propostas_mhs.registrar_acao(text, uuid, text, text, jsonb)
from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
