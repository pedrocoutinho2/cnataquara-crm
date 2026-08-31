-- O cron roda 02:30 UTC = 23:30 de Brasilia do MESMO dia D.
-- A versao anterior fechava D-1, entao o snapshot de cada dia so era tirado
-- quase 24h depois do dia terminar, ja com reagendamentos por cima.
-- Agora fecha D (dia que esta acabando) e, por seguranca, D-1 se tiver ficado pendente.
create or replace function public.crm_fechar_pendentes()
returns integer
language plpgsql
as $function$
declare d date; alvo date; n int := 0; u record;
begin
  d := (now() at time zone 'America/Sao_Paulo')::date;
  foreach alvo in array array[d, d - 1] loop
    for u in select nome from crm_usuarios where ativo and consultor loop
      if not exists (select 1 from crm_relatorio_diario r
                      where r.data = alvo and r.consultor = u.nome) then
        perform crm_fechar_dia(alvo, u.nome, 'automático');
        n := n + 1;
      end if;
    end loop;
  end loop;
  return n;
end;
$function$;

notify pgrst, 'reload schema';