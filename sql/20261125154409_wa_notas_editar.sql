-- Notas internas: edição pelo autor (rede: vale para as três unidades)
alter table public.crm_wa_notas add column if not exists editada_em timestamptz;

create or replace function public.crm_wa_notas_listar(p_token uuid, p_conversa_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 1);
  perform crm_wa_conversa_do(s, p_conversa_id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', n.id, 'conversa_id', n.conversa_id, 'autor_id', n.autor_id, 'autor_nome', a.nome,
      'texto', case when n.apagada then null else n.texto end, 'apagada', n.apagada,
      'created_at', n.created_at, 'editada_em', n.editada_em,
      'mencoes', coalesce((select jsonb_agg(jsonb_build_object('usuario_id', m.usuario_id, 'nome', u.nome, 'lida_em', m.lida_em))
                   from crm_wa_notas_mencoes m join crm_usuarios u on u.id = m.usuario_id
                  where m.nota_id = n.id), '[]'::jsonb)
    ) order by n.created_at)
    from crm_wa_notas n join crm_usuarios a on a.id = n.autor_id
   where n.conversa_id = p_conversa_id and n.unidade = s->>'unidade'), '[]'::jsonb);
end $$;

-- Só o autor edita. Menção nova vira pendente (e seguidor, se preciso);
-- menção retirada some; menção mantida conserva o estado de lida.
create or replace function public.crm_wa_nota_editar(p_token uuid, p_nota_id uuid, p_texto text, p_mencoes uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s jsonb; un text; uid uuid; n crm_wa_notas; c crm_wa_conversas; m uuid; v_ment uuid[] := '{}';
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  select * into n from crm_wa_notas where id = p_nota_id and unidade = un for update;
  if not found or n.autor_id <> uid or n.apagada then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  c := crm_wa_conversa_do(s, n.conversa_id);
  if p_texto is null or length(btrim(p_texto)) = 0 then raise exception 'texto_vazio' using errcode = 'P0001'; end if;

  foreach m in array coalesce(p_mencoes, '{}') loop
    if m = uid or m = any(v_ment) then continue; end if;
    if not exists (select 1 from crm_usuario_unidades uu join crm_usuarios u on u.id = uu.usuario_id
                    where uu.usuario_id = m and uu.unidade = un and uu.ativo and u.ativo
                      and crm_nivel_num(m, 'conversas', un) >= 1) then
      raise exception 'mencao_invalida' using errcode = 'P0001';
    end if;
    v_ment := v_ment || m;
  end loop;

  update crm_wa_notas set texto = btrim(p_texto), mencoes = v_ment, editada_em = now()
   where id = p_nota_id;

  delete from crm_wa_notas_mencoes where nota_id = p_nota_id and not (usuario_id = any(v_ment));
  foreach m in array v_ment loop
    insert into crm_wa_notas_mencoes (nota_id, usuario_id, unidade) values (p_nota_id, m, un)
      on conflict do nothing;
    if c.atendente_id is distinct from m and c.transf_para is distinct from m
       and not crm_wa_ve_tudo(m, un) then
      insert into crm_wa_seguidores (conversa_id, usuario_id, adicionado_por)
        values (n.conversa_id, m, uid) on conflict do nothing;
    end if;
  end loop;

  return jsonb_build_object('id', p_nota_id, 'mencoes', to_jsonb(v_ment));
end $$;

revoke all on function public.crm_wa_nota_editar(uuid, uuid, text, uuid[]) from public;
grant execute on function public.crm_wa_nota_editar(uuid, uuid, text, uuid[]) to anon, authenticated;

notify pgrst, 'reload schema';
