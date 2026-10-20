-- ============================================================================
-- ACESSO OPERACIONAL MHS - PROJETOS1 COMO EDITOR
-- Execute apos 20260929_0031_validar_acesso_projetos1_mhs.sql.
-- Escopo estrito: ativa somente projetos1@maisintegradora.com.br como EDITOR.
-- Nao cria nem altera administradores; comercial3 permanece ADMIN master.
-- ============================================================================

begin;

insert into cadastro.equipe (usuario_id, nome, email, cargo, papel, ativo)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), split_part(u.email, '@', 1)),
  lower(u.email),
  'Comercial',
  'EDITOR',
  true
from auth.users u
where lower(u.email) = 'projetos2@maisintegradora.com.br'
on conflict (usuario_id) do update
set email = excluded.email,
    nome = excluded.nome,
    cargo = excluded.cargo,
    papel = 'EDITOR',
    ativo = true,
    atualizado_em = now();

do $$
begin
  if not exists (
    select 1 from cadastro.equipe e
    join auth.users u on u.id = e.usuario_id
    where lower(u.email) = 'projetos1@maisintegradora.com.br'
      and e.ativo and e.papel = 'EDITOR'
  ) then
    raise exception 'O usuario projetos1@maisintegradora.com.br nao foi localizado no Auth para ativacao.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
