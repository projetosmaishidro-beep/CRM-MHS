-- Execute apos 20260920_0002_api_operacional_supabase.sql.
-- Todas as consultas sao somente leitura.

select table_schema, table_name
from information_schema.tables
where table_schema in ('cadastro', 'mapa', 'crm', 'api')
  and table_name in ('empresas', 'equipe', 'pontos', 'relacionamentos', 'viagens',
    'visitas', 'necessidades', 'despesas', 'eventos', 'auditoria_api')
order by 1, 2;

select routine_schema, routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in ('criar_cliente', 'atualizar_cliente', 'criar_visita',
    'criar_necessidade', 'criar_viagem', 'atualizar_viagem', 'criar_despesa',
    'atualizar_despesa', 'criar_evento', 'atualizar_evento')
order by routine_name;

select table_name, privilege_type, grantee
from information_schema.role_table_grants
where table_schema in ('cadastro', 'mapa', 'crm')
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type;

select id, public, file_size_limit, allowed_mime_types
from storage.buckets where id = 'crm-anexos';

begin;
set local role anon;
select has_schema_privilege('anon', 'api', 'USAGE') as anon_tem_api;
rollback;
