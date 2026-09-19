-- ============================================================================
-- EQUIPE COMERCIAL
--
-- O Supabase Authentication cria as contas e guarda as credenciais.
-- Esta tabela guarda somente o perfil que o CRM precisa exibir.
--
-- Pré-requisito: convide os e-mails em Authentication > Users e execute este
-- arquivo depois que os usuários existirem. Se executar antes, a estrutura
-- será criada e o bloco de vinculação poderá ser executado novamente sem risco.
-- ============================================================================

begin;

create schema if not exists cadastro;
create schema if not exists api;

create table if not exists cadastro.equipe (
    membro_id       uuid primary key default gen_random_uuid(),
    usuario_id      uuid not null unique references auth.users(id) on delete cascade,
    nome            text not null,
    email           text not null unique,
    cargo           text not null default 'Equipe Comercial',
    ativo           boolean not null default true,
    criado_em       timestamptz not null default now(),
    atualizado_em   timestamptz not null default now(),
    constraint equipe_nome_check check (length(trim(nome)) >= 2),
    constraint equipe_email_check check (position('@' in email) > 1)
);

comment on table cadastro.equipe is
'Perfis simples da equipe. A autenticação continua exclusivamente no Supabase Auth.';
comment on column cadastro.equipe.usuario_id is
'Identificador do usuário autenticado; nunca é substituído por e-mail no relacionamento.';
comment on column cadastro.equipe.nome is
'Nome exibido em participantes, auditorias e registros comerciais.';

create index if not exists equipe_ativa_idx
    on cadastro.equipe (ativo, nome);

revoke all on table cadastro.equipe from public, anon;
grant select on table cadastro.equipe to authenticated, service_role;
grant usage on schema cadastro, api to authenticated, service_role;

alter table cadastro.equipe enable row level security;
drop policy if exists equipe_le_perfis on cadastro.equipe;
create policy equipe_le_perfis
on cadastro.equipe
for select
to authenticated
using (auth.uid() is not null and ativo = true);

create or replace view api.vw_equipe
with (security_invoker = true)
as
select
    membro_id,
    usuario_id,
    nome,
    email,
    cargo,
    ativo
from cadastro.equipe
where ativo = true;

comment on view api.vw_equipe is
'Equipe ativa para participantes de viagens e identificação de registros.';

revoke all on api.vw_equipe from public, anon;
grant select on api.vw_equipe to authenticated, service_role;

-- Vincula os perfis apenas quando as contas já tiverem sido criadas pelo Auth.
-- Não cria senha, não insere em auth.users e não expõe a tabela de autenticação.
insert into cadastro.equipe (usuario_id, nome, email, cargo)
select
    usuario.id,
    dados.nome,
    lower(usuario.email),
    'Equipe Comercial'
from auth.users usuario
join (
    values
        ('comercial3@maisintegradora.com.br', 'Jefferson Ramires'),
        ('comercial2@maisintegradora.com.br', 'Bárbara Vieira'),
        ('comercial1@maisintegradora.com.br', 'Ricardo Castro Alves')
) as dados(email, nome)
    on lower(usuario.email) = dados.email
on conflict (email) do update
set usuario_id = excluded.usuario_id,
    nome = excluded.nome,
    atualizado_em = now();

-- Conferência segura: deve retornar os três perfis depois dos convites aceitos.
select nome, email, cargo, ativo
from cadastro.equipe
where email in (
    'comercial3@maisintegradora.com.br',
    'comercial2@maisintegradora.com.br',
    'comercial1@maisintegradora.com.br'
)
order by nome;

commit;

notify pgrst, 'reload schema';
