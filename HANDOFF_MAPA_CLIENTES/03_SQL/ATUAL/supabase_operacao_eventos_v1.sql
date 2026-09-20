-- ============================================================================
-- SCHEMA: crm
-- FUNCIONALIDADE: Gestão de Eventos, Feiras e Origem de Captação
-- OBJETIVO: Criar tabelas de eventos, vincular despesas a eventos e 
--           adicionar rastreamento de captação de clientes.
-- ============================================================================

begin;

-- 1. Criação das Tabelas de Eventos
create table if not exists crm.eventos (
    evento_id                   uuid primary key default gen_random_uuid(),
    nome                        text not null,
    data_inicio                 timestamptz not null,
    data_fim                    timestamptz not null,
    local                       text not null,
    tipo_participacao           text not null default 'PARTICIPANTE',
    status                      text not null default 'PLANEJADO',
    notas_estrategicas          text,
    criado_por                  uuid references auth.users(id) on delete set null,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint eventos_status_check
        check (status in ('PLANEJADO', 'EM_ANDAMENTO', 'REALIZADO', 'CANCELADO')),
    constraint eventos_tipo_participacao_check
        check (tipo_participacao in ('EXPOSITOR', 'PARTICIPANTE')),
    constraint eventos_datas_check
        check (data_fim >= data_inicio)
);

comment on table crm.eventos is 'Feiras e eventos corporativos para participação comercial.';

create table if not exists crm.evento_participantes (
    evento_id                   uuid not null references crm.eventos(evento_id) on delete cascade,
    user_id                     uuid not null references auth.users(id) on delete cascade,
    adicionado_em               timestamptz not null default now(),
    primary key (evento_id, user_id)
);

comment on table crm.evento_participantes is 'Membros da equipe escalados para o evento.';


-- 2. Atualização da Tabela de Despesas
-- Remover o not null da viagem_id para suportar despesas isoladas de eventos
alter table crm.despesas alter column viagem_id drop not null;

-- Adicionar novas colunas
alter table crm.despesas 
    add column if not exists evento_id uuid references crm.eventos(evento_id) on delete cascade,
    add column if not exists centro_custo text;

-- Atualizar/adicionar constraint para garantir que a despesa tenha ou Viagem ou Evento, mas não os dois vazios nem os dois preenchidos
alter table crm.despesas drop constraint if exists despesas_referencia_check;
alter table crm.despesas 
    add constraint despesas_referencia_check 
    check (
        (viagem_id is not null and evento_id is null) or 
        (viagem_id is null and evento_id is not null)
    );

-- Para Centro de Custo, deixamos livre inicialmente para evolucao


-- 3. Atualização da Tabela de Relacionamentos (Captação)
-- Permitir novas origens expandindo ou removendo constraint (caso houvesse check)
alter table crm.relacionamentos
    add column if not exists evento_id_origem uuid references crm.eventos(evento_id) on delete set null;

-- Atualizar o comentário da origem
comment on column crm.relacionamentos.origem is 'Ex: MAPA, INBOUND, INDICACAO, EVENTO/FEIRA, PROSPECCAO_ATIVA.';


-- 4. Segurança (RLS)
alter table crm.eventos enable row level security;
alter table crm.evento_participantes enable row level security;

-- Policies (Exemplo: todos os usuários autenticados da empresa podem ver eventos)
drop policy if exists "Equipe pode ver eventos" on crm.eventos;
create policy "Equipe pode ver eventos"
    on crm.eventos for select
    to authenticated
    using (true);

drop policy if exists "Equipe pode gerenciar eventos" on crm.eventos;
create policy "Equipe pode gerenciar eventos"
    on crm.eventos for all
    to authenticated
    using (true)
    with check (true);

drop policy if exists "Equipe pode ver participantes" on crm.evento_participantes;
create policy "Equipe pode ver participantes"
    on crm.evento_participantes for select
    to authenticated
    using (true);

drop policy if exists "Equipe pode gerenciar participantes" on crm.evento_participantes;
create policy "Equipe pode gerenciar participantes"
    on crm.evento_participantes for all
    to authenticated
    using (true)
    with check (true);

-- 5. Storage (Buckets para Anexos do Evento)
-- Tornando o bucket público para permitir preview direto das imagens no Front-end
insert into storage.buckets (id, name, public) 
values ('eventos-anexos', 'eventos-anexos', true)
on conflict (id) do update set public = true;

drop policy if exists "Equipe pode ver anexos de eventos" on storage.objects;
create policy "Equipe pode ver anexos de eventos"
    on storage.objects for select
    to public
    using ( bucket_id = 'eventos-anexos' );

drop policy if exists "Equipe pode subir anexos de eventos" on storage.objects;
create policy "Equipe pode subir anexos de eventos"
    on storage.objects for insert
    to authenticated
    with check ( bucket_id = 'eventos-anexos' );

commit;
