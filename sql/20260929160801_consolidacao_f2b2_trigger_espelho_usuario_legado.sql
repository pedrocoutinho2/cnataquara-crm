create trigger z90_espelho_vinculo_legado
after insert or update of papel, admin, consultor, permissoes, ativo on public.crm_usuarios
for each row execute function public.crm_usuario_espelho_legado();