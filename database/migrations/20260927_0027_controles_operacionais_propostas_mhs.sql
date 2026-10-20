-- ============================================================================
-- PROPOSTAS MHS - CONTROLES OPERACIONAIS ADMINISTRATIVOS
-- Execute depois de 20260927_0026_galeria_pdfs_propostas_agrupada.sql.
-- A numeracao somente pode avancar: numeros existentes nunca sao reutilizados.
-- ============================================================================

begin;

-- A autorizacao efetiva permanece no banco. A interface somente oculta o
-- painel; esta funcao tambem impede chamadas diretas por perfis nao-admin.
create or replace function api.exigir_admin()
returns void
language plpgsql
security definer
set search_path = pg_catalog, api
as $$
begin
  if not api.eh_admin() then
    raise exception 'Seu perfil nao possui permissao administrativa.' using errcode = '42501';
  end if;
end;
$$;

create or replace function api.obter_controles_operacionais_propostas_mhs(
  p_ano integer default extract(year from current_date)::integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare
  v_ultimo_numero integer := 0;
  v_maior_emitido integer := 0;
  v_finalizadas_sem_pdf integer := 0;
  v_arquivos_sem_storage integer := 0;
  v_propostas_sem_memoria integer := 0;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  if p_ano not between 2000 and 2200 then
    raise exception 'Ano de proposta invalido: %', p_ano using errcode = '22023';
  end if;

  select coalesce(n.ultimo_numero, 0)
    into v_ultimo_numero
  from propostas_mhs.numeracao_anual n
  where n.ano = p_ano;

  select coalesce(max(p.numero_sequencial), 0)
    into v_maior_emitido
  from propostas_mhs.propostas p
  where p.ano = p_ano;

  select count(*) into v_finalizadas_sem_pdf
  from propostas_mhs.propostas p
  where p.status = 'FINALIZADA'
    and not exists (
      select 1
      from propostas_mhs.propostas_revisoes r
      join propostas_mhs.arquivos_proposta a
        on a.proposta_id = r.proposta_id and a.revisao_id = r.revisao_id
      join storage.objects o
        on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
      where r.proposta_id = p.proposta_id
        and r.numero_revisao = p.versao_atual
        and a.categoria = 'PDF_GERADO'
        and a.estado = 'ATIVO'
        and a.tamanho_bytes > 0
    );

  select count(*) into v_arquivos_sem_storage
  from propostas_mhs.arquivos_proposta a
  left join storage.objects o
    on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
  where a.estado = 'ATIVO' and o.id is null;

  select count(*) into v_propostas_sem_memoria
  from propostas_mhs.propostas p
  where exists (
      select 1 from propostas_mhs.propostas_itens i where i.proposta_id = p.proposta_id
    )
    and not exists (
      select 1
      from propostas_mhs.memorias_calculo m
      where m.proposta_id = p.proposta_id and m.situacao = 'ATUAL'
    );

  return jsonb_build_object(
    'ano', p_ano,
    'ultimo_numero_registrado', v_ultimo_numero,
    'maior_numero_emitido', v_maior_emitido,
    'proximo_numero_seguro', greatest(v_ultimo_numero, v_maior_emitido) + 1,
    'propostas_no_ano', (select count(*) from propostas_mhs.propostas p where p.ano = p_ano),
    'finalizadas_sem_pdf', v_finalizadas_sem_pdf,
    'arquivos_ativos_sem_storage', v_arquivos_sem_storage,
    'propostas_com_itens_sem_memoria_atual', v_propostas_sem_memoria
  );
end;
$$;

create or replace function api.definir_proxima_numeracao_proposta_mhs(
  p_ano integer,
  p_proximo_numero integer,
  p_justificativa text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_ultimo_numero integer;
  v_maior_emitido integer;
  v_proximo_minimo integer;
begin
  perform api.exigir_admin();
  if p_ano not between 2000 and 2200 then
    raise exception 'Ano de proposta invalido: %', p_ano using errcode = '22023';
  end if;
  if p_proximo_numero < 1 then
    raise exception 'Informe um proximo numero maior que zero.' using errcode = '22023';
  end if;

  -- Garante uma linha bloqueavel mesmo no primeiro uso do ano. O FOR UPDATE
  -- abaixo serializa este ajuste com a proxima emissao da proposta.
  insert into propostas_mhs.numeracao_anual (ano, ultimo_numero)
  values (p_ano, 0)
  on conflict (ano) do nothing;

  select n.ultimo_numero
    into v_ultimo_numero
  from propostas_mhs.numeracao_anual n
  where n.ano = p_ano
  for update;

  select coalesce(max(p.numero_sequencial), 0)
    into v_maior_emitido
  from propostas_mhs.propostas p
  where p.ano = p_ano;

  v_proximo_minimo := greatest(v_ultimo_numero, v_maior_emitido) + 1;
  if p_proximo_numero < v_proximo_minimo then
    raise exception 'A proxima proposta deve ser no minimo %. Numeros ja emitidos ou reservados nao podem ser reutilizados.', v_proximo_minimo
      using errcode = '22023';
  end if;

  update propostas_mhs.numeracao_anual
  set ultimo_numero = p_proximo_numero - 1,
      atualizado_em = now()
  where ano = p_ano;

  perform api.registrar_auditoria(
    'NUMERACAO_PROPOSTAS',
    auth.uid(),
    'ATUALIZADA',
    jsonb_build_object(
      'ano', p_ano,
      'ultimo_numero_anterior', v_ultimo_numero,
      'maior_numero_emitido', v_maior_emitido,
      'proximo_numero_definido', p_proximo_numero,
      'justificativa', nullif(trim(p_justificativa), '')
    )
  );

  return jsonb_build_object(
    'ano', p_ano,
    'proximo_numero_seguro', p_proximo_numero,
    'codigo_proxima_proposta', lpad((p_ano % 100)::text, 2, '0') || '.' || lpad(p_proximo_numero::text, 3, '0')
  );
end;
$$;

revoke all on function api.obter_controles_operacionais_propostas_mhs(integer) from public, anon;
revoke all on function api.definir_proxima_numeracao_proposta_mhs(integer, integer, text) from public, anon;
grant execute on function api.obter_controles_operacionais_propostas_mhs(integer) to authenticated;
grant execute on function api.definir_proxima_numeracao_proposta_mhs(integer, integer, text) to authenticated;

notify pgrst, 'reload schema';
commit;
