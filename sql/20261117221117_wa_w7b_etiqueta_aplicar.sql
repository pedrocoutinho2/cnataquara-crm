-- W7b (17/11/2026): aplica o dono pela etiqueta do WhatsApp.
-- Exatamente uma etiqueta de consultor na conversa -> ela é dona (conversa e responsável do lead).
-- Nenhuma ou duas+ etiquetas de consultor: não mexe. Tirar etiqueta não troca o dono.
create or replace function crm_wa_etiqueta_aplicar(p_conta uuid, p_lid text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_conv uuid; v_ags uuid[]; v_ag uuid; v_nome text; v_atual uuid; v_lead uuid; v_un text;
begin
  select conversa_id into v_conv from crm_wa_lids where conta_id = p_conta and lid = p_lid;
  if v_conv is null then return 'sem_conversa'; end if;
  select array_agg(distinct e.usuario_id) into v_ags
    from crm_wa_lid_etiquetas le
    join crm_wa_etiquetas e on e.conta_id = le.conta_id and e.label_id = le.label_id
   where le.conta_id = p_conta and le.lid = p_lid and e.usuario_id is not null and not e.apagada;
  if v_ags is null or array_length(v_ags, 1) = 0 then return 'sem_etiqueta_de_consultor'; end if;
  if array_length(v_ags, 1) > 1 then return 'ambigua'; end if;
  v_ag := v_ags[1];
  select atendente_id, lead_id, unidade into v_atual, v_lead, v_un from crm_wa_conversas where id = v_conv;
  if v_atual is not distinct from v_ag then return 'ja_certa'; end if;
  select nome into v_nome from crm_usuarios where id = v_ag;
  update crm_wa_conversas set atendente_id = v_ag, atribuicao = 'etiqueta', atribuida_em = now(),
         transf_para = null, transf_de = null, transf_em = null
   where id = v_conv;
  if v_lead is not null then
    update crm_leads set responsavel = v_nome
     where id = v_lead and unidade = v_un and responsavel is distinct from v_nome;
  end if;
  return 'aplicada';
end $$;
revoke all on function crm_wa_etiqueta_aplicar(uuid, text) from public, anon, authenticated;

-- quando o LID ganha conversa (ou troca), aplica o dono da etiqueta
create or replace function crm_wa_lids_tg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.conversa_id is not null and (tg_op = 'INSERT' or new.conversa_id is distinct from old.conversa_id) then
    perform crm_wa_etiqueta_aplicar(new.conta_id, new.lid);
  end if;
  return new;
end $$;
drop trigger if exists z_wa_lids_aplicar on crm_wa_lids;
create trigger z_wa_lids_aplicar after insert or update of conversa_id on crm_wa_lids
  for each row execute function crm_wa_lids_tg();
notify pgrst, 'reload schema';