-- ============================================================================
-- STORAGE PRIVADO
-- Execute em um projeto Supabase após criar os schemas.
-- Nenhum bucket abaixo é público.
-- ============================================================================

begin;

insert into storage.buckets (id, name, public, file_size_limit)
values
    ('importacoes-privadas', 'importacoes-privadas', false, 52428800),
    ('mapa-evidencias', 'mapa-evidencias', false, 10485760),
    ('crm-anexos', 'crm-anexos', false, 20971520),
    ('financeiro-comprovantes', 'financeiro-comprovantes', false, 10485760)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

-- Convenção obrigatória de caminhos:
-- importacoes-privadas/mapa/AAAA-MM-DD/arquivo-original.csv
-- mapa-evidencias/empresa/{empresa_id}/confirmacao/{arquivo}
-- crm-anexos/empresa/{empresa_id}/visita/{visita_id}/{arquivo}
-- crm-anexos/empresa/{empresa_id}/documentos/{arquivo}
-- financeiro-comprovantes/viagem/{viagem_id}/despesa/{despesa_id}/{arquivo}

commit;
