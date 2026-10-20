  -- ============================================================================
  -- PROPOSTAS MHS - ARQUIVOS DURAVEIS DE RASCUNHO
  -- Execute depois de 20260927_0019_templates_mhs_memoria_reutilizavel.sql.
  -- ============================================================================

  begin;

  -- Permite registrar anexos privados antes da emissao. O binario fica em
  -- rascunhos e o metadado nao recebe revisao ate a emissao comercial.
  create or replace function api.registrar_arquivo_proposta_mhs(p_dados jsonb)
  returns jsonb
  language plpgsql
  security definer
  set search_path = pg_catalog, public, api, propostas_mhs
  as $$
  declare
    v_proposta_id uuid := nullif(p_dados ->> 'proposta_id', '')::uuid;
    v_revisao_id uuid := nullif(p_dados ->> 'revisao_id', '')::uuid;
    v_empresa_id uuid;
    v_numero_revisao integer;
    v_prefixo text;
    v_arquivo_id uuid;
    v_categoria text := upper(coalesce(p_dados ->> 'categoria', 'OUTRO'));
  begin
    perform api.exigir_editor();
    select empresa_id into v_empresa_id from propostas_mhs.propostas where proposta_id = v_proposta_id;
    if v_empresa_id is null then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

    v_prefixo := 'clientes/' || v_empresa_id::text || '/propostas/' || v_proposta_id::text || '/';
    if v_revisao_id is null then
      v_prefixo := v_prefixo || 'rascunhos/';
    else
      select numero_revisao into v_numero_revisao from propostas_mhs.propostas_revisoes
      where revisao_id = v_revisao_id and proposta_id = v_proposta_id;
      if v_numero_revisao is null then raise exception 'A revisao nao pertence a proposta informada.' using errcode = '23503'; end if;
      v_prefixo := v_prefixo || 'revisoes/R' || v_numero_revisao::text || '/';
    end if;

    if coalesce(p_dados ->> 'caminho_storage', '') not like v_prefixo || '%' then
      raise exception 'O caminho do arquivo deve iniciar com %', v_prefixo using errcode = '22023';
    end if;
    if v_revisao_id is null and (p_dados ->> 'caminho_storage') !~ '/rascunhos/(anexos|imagens|tecnicos)/[^/]+$' then
      raise exception 'Arquivo de rascunho deve usar anexos, imagens ou tecnicos.' using errcode = '22023';
    end if;
    if v_categoria = 'PDF_GERADO' and (v_revisao_id is null or (p_dados ->> 'caminho_storage') not like v_prefixo || 'pdf/%') then
      raise exception 'PDF gerado deve pertencer a uma revisao e ficar na pasta pdf.' using errcode = '22023';
    end if;

    insert into propostas_mhs.arquivos_proposta (
      proposta_id, revisao_id, caminho_storage, categoria, nome_original, tipo_mime,
      tamanho_bytes, checksum_sha256, observacao, enviado_por
    ) values (
      v_proposta_id, v_revisao_id, p_dados ->> 'caminho_storage', v_categoria,
      nullif(trim(p_dados ->> 'nome_original'), ''), nullif(trim(p_dados ->> 'tipo_mime'), ''),
      nullif(p_dados ->> 'tamanho_bytes', '')::bigint, nullif(trim(p_dados ->> 'checksum_sha256'), ''),
      nullif(trim(p_dados ->> 'observacao'), ''), auth.uid()
    ) returning arquivo_id into v_arquivo_id;

    perform propostas_mhs.registrar_acao('ARQUIVO_PROPOSTA', v_arquivo_id, 'CRIADA', case when v_revisao_id is null then 'Arquivo de rascunho registrado' else 'Arquivo registrado' end);
    return (select to_jsonb(a) from propostas_mhs.arquivos_proposta a where a.arquivo_id = v_arquivo_id);
  end;
  $$;

  -- Mantem o arquivo fisico de rascunho para recuperacao, mas o retira da lista
  -- ativa depois que sua copia vinculada a revisao for confirmada.
  create or replace function api.arquivar_arquivo_proposta_mhs(
    p_proposta_id uuid,
    p_caminho_storage text
  )
  returns jsonb
  language plpgsql
  security definer
  set search_path = pg_catalog, public, api, propostas_mhs
  as $$
  declare
    v_arquivo propostas_mhs.arquivos_proposta%rowtype;
  begin
    perform api.exigir_editor();
    update propostas_mhs.arquivos_proposta
    set estado = 'ARQUIVADO'
    where proposta_id = p_proposta_id
      and revisao_id is null
      and caminho_storage = p_caminho_storage
      and caminho_storage like 'clientes/%/propostas/%/rascunhos/%'
      and estado = 'ATIVO'
    returning * into v_arquivo;
    if not found then raise exception 'Arquivo de rascunho ativo nao encontrado.' using errcode = 'P0002'; end if;
    perform propostas_mhs.registrar_acao('ARQUIVO_PROPOSTA', v_arquivo.arquivo_id, 'ARQUIVADA', 'Arquivo de rascunho vinculado a revisao');
    return to_jsonb(v_arquivo);
  end;
  $$;

  drop policy if exists propostas_mhs_envio_editores on storage.objects;
  create policy propostas_mhs_envio_editores on storage.objects for insert to authenticated
  with check (
    bucket_id = 'propostas-mhs' and api.eh_editor() and name ~
    '^(clientes/[0-9a-fA-F-]+/propostas/[0-9a-fA-F-]+/(rascunhos/(anexos|imagens|tecnicos)|revisoes/R[0-9]+/(pdf|anexos|imagens|tecnicos))/[^/]+|templates/[0-9a-fA-F-]+/versoes/V[0-9]+/(anexos|imagens|tecnicos)/[^/]+)$'
  );
  drop policy if exists propostas_mhs_atualizacao_editores on storage.objects;
  create policy propostas_mhs_atualizacao_editores on storage.objects for update to authenticated
  using (bucket_id = 'propostas-mhs' and api.eh_editor())
  with check (
    bucket_id = 'propostas-mhs' and api.eh_editor() and name ~
    '^(clientes/[0-9a-fA-F-]+/propostas/[0-9a-fA-F-]+/(rascunhos/(anexos|imagens|tecnicos)|revisoes/R[0-9]+/(pdf|anexos|imagens|tecnicos))/[^/]+|templates/[0-9a-fA-F-]+/versoes/V[0-9]+/(anexos|imagens|tecnicos)/[^/]+)$'
  );

  revoke all on function api.arquivar_arquivo_proposta_mhs(uuid, text) from public, anon;
  grant execute on function api.arquivar_arquivo_proposta_mhs(uuid, text) to authenticated;

  notify pgrst, 'reload schema';
  commit;
