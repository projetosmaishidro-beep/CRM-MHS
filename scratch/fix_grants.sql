begin;

grant insert, update, delete on api.vw_eventos to authenticated, service_role;
grant insert, update, delete on api.vw_despesas_eventos to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
