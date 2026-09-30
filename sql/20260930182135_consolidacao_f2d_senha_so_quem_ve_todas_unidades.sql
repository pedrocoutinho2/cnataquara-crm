-- Consolidação · Fase 2d: correção de segurança em crm_equipe_definir_senha (achada pelo Claude Code
-- no mapeamento). A senha é da pessoa, vale em todas as unidades: um gestor de uma unidade não pode
-- redefinir a senha de quem também está em unidade que ele não enxerga (ex.: gestor de Queimados
-- trocando a senha do Pedro e entrando na Taquara). Mesma regra já usada para os dados da pessoa.
create or replace function public.crm_equipe_definir_senha(p_token uuid, p_usuario uuid, p_senha text, p_temporaria boolean default true)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_exige(p_token, 'equipe', 2);
  un := crm_sessao_unidade(p_token);
  if not exists (select 1 from crm_usuario_unidades where usuario_id = p_usuario and unidade = un) then
    raise exception 'usuario_de_outra_unidade' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from crm_usuario_unidades t
     where t.usuario_id = p_usuario and t.ativo
       and t.unidade not in (select m.unidade from crm_usuario_unidades m where m.usuario_id = u.id and m.ativo)
  ) then
    raise exception 'usuario_com_outras_unidades' using errcode = 'P0001';
  end if;
  if not crm_senha_valida(p_senha) then
    raise exception 'A senha precisa ter no minimo 8 caracteres, com pelo menos uma letra e um numero.';
  end if;
  update crm_usuarios
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
         senha_definida_em = now(),
         senha_temporaria = p_temporaria,
         pin_hash = null
   where id = p_usuario;
  return found;
end $function$;