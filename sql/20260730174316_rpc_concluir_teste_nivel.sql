-- Conclusão do teste via RPC segura (corrige update silenciosamente bloqueado pelo RLS)
create or replace function public.fn_concluir_teste_nivel(
  p_id uuid,
  p_resultado_nivel text,
  p_curso text,
  p_acertos int,
  p_total int,
  p_respostas jsonb,
  p_respostas_abertas jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update leads_teste_nivel
  set resultado_nivel   = p_resultado_nivel,
      curso_recomendado = p_curso,
      acertos           = p_acertos,
      total_perguntas   = p_total,
      respostas         = p_respostas,
      respostas_abertas = p_respostas_abertas,
      concluido         = true,
      concluido_em      = now()
  where id = p_id
    and concluido = false;   -- só conclui uma vez; ninguém sobrescreve resultado
end;
$$;

revoke all on function public.fn_concluir_teste_nivel(uuid,text,text,int,int,jsonb,jsonb) from public;
grant execute on function public.fn_concluir_teste_nivel(uuid,text,text,int,int,jsonb,jsonb) to anon, authenticated, service_role;

-- a policy de UPDATE para anon não é mais necessária (e não funcionava): remove para fechar a superfície
drop policy if exists "anon pode atualizar resultado" on public.leads_teste_nivel;