/**
 * Ponte CRM CNA Taquara <-> Google Agenda — v2.1 (08/09/2026)
 *
 * Muda em relacao a v1:
 *   1. aceita "convidados" (lista de e-mails) e envia o convite de verdade
 *   2. aceita "meet": true e cria a sala do Google Meet no evento
 *   3. devolve "meet_url" e "html_link" para o CRM guardar
 *   4. aceita "calendar_id" por requisicao: cada evento diz em qual calendario
 *      ele mora. Vazio = CALENDAR_ID padrao, que e' onde estao os eventos antigos
 *   5. continua aceitando o payload antigo sem mudanca de comportamento
 *
 * ANTES DE PUBLICAR:
 *   a) Servicos > + > "Google Calendar API" (identificador: Calendar).
 *      Sem isso o Meet nao e' criado.
 *   b) TOKEN: o mesmo que ja estava no codigo antigo.
 *   c) CALENDAR_ID: MANTENHA o valor que o codigo antigo usava. E' onde os 7
 *      eventos ja sincronizados vivem. Se voce trocar, editar ou cancelar
 *      qualquer um deles passa a falhar com "Not Found".
 *      O calendario de teste de nivel NAO entra aqui: ele vem por requisicao,
 *      do campo cal_testes em crm_agenda_config.
 *   d) Implantar > Gerenciar implantacoes > lapis > Versao: Nova versao >
 *      Implantar. Mantem a mesma URL, que ja esta gravada no CRM.
 */

var TOKEN       = 'COLE_AQUI_O_MESMO_TOKEN_DO_CODIGO_ANTIGO';
var CALENDAR_ID = 'primary';               // o mesmo do codigo antigo
var TZ          = 'America/Sao_Paulo';

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.token !== TOKEN) return out({ erro: 'token inválido' });

    var cal = req.calendar_id || CALENDAR_ID;
    var acao = req.acao || 'upsert';

    if (acao === 'delete') {
      if (req.gcal_id) {
        try { Calendar.Events.remove(cal, req.gcal_id, { sendUpdates: 'all' }); } catch (err) {}
      }
      return out({ ok: true });
    }

    var ev = req.evento || {};
    var recurso = montaEvento(ev);
    var salvo;

    if (!req.gcal_id) {
      salvo = Calendar.Events.insert(recurso, cal, {
        conferenceDataVersion: ev.meet ? 1 : 0,
        sendUpdates: temConvidado(ev) ? 'all' : 'none'
      });
    } else {
      salvo = Calendar.Events.patch(recurso, cal, req.gcal_id, {
        conferenceDataVersion: 1,
        sendUpdates: temConvidado(ev) ? 'all' : 'none'
      });
    }

    return out({
      ok: true,
      gcal_id: salvo.id,
      meet_url: meetDe(salvo),
      html_link: salvo.htmlLink || ''
    });

  } catch (err) {
    return out({ erro: String(err && err.message ? err.message : err) });
  }
}

function montaEvento(ev) {
  var r = {
    summary: ev.titulo || 'Evento CNA Taquara',
    description: descricao(ev)
  };

  if (ev.hora_inicio) {
    r.start = { dateTime: iso(ev.data, ev.hora_inicio), timeZone: TZ };
    r.end   = { dateTime: iso(ev.data, ev.hora_fim || somaMin(ev.hora_inicio, 60)), timeZone: TZ };
  } else {
    r.start = { date: ev.data };
    r.end   = { date: maisUmDia(ev.data) };
  }

  if (ev.local) r.location = ev.local;

  var conv = listaConvidados(ev);
  if (conv.length) {
    r.attendees = conv.map(function (mail) { return { email: mail }; });
    r.guestsCanInviteOthers = false;
    r.guestsCanModify = false;
  }

  if (ev.meet) {
    r.conferenceData = {
      createRequest: {
        requestId: 'cna-' + (ev.id || Utilities.getUuid()).toString().slice(0, 30),
        conferenceSolutionKey: { type: 'hangoutsMeet' }
      }
    };
  }

  return r;
}

/** Aceita convidados como array, string separada por virgula, ou campo unico. */
function listaConvidados(ev) {
  var bruto = ev.convidados || ev.convidado || '';
  var arr = Array.isArray(bruto) ? bruto : String(bruto).split(/[;,\s]+/);
  var vistos = {}, saida = [];
  arr.forEach(function (x) {
    var m = String(x || '').trim().toLowerCase();
    if (m && m.indexOf('@') > 0 && !vistos[m]) { vistos[m] = 1; saida.push(m); }
  });
  return saida;
}

function temConvidado(ev) { return listaConvidados(ev).length > 0; }

function descricao(ev) {
  var p = [];
  if (ev.descricao) p.push(ev.descricao);
  if (ev.responsavel) p.push('Responsável: ' + ev.responsavel);
  if (ev.participantes) p.push('Equipe: ' + ev.participantes);
  if (ev.categoria) p.push('Categoria: ' + ev.categoria);
  return p.join('\n');
}

function meetDe(evento) {
  if (evento.hangoutLink) return evento.hangoutLink;
  var cd = evento.conferenceData;
  if (cd && cd.entryPoints) {
    for (var i = 0; i < cd.entryPoints.length; i++) {
      if (cd.entryPoints[i].entryPointType === 'video') return cd.entryPoints[i].uri;
    }
  }
  return '';
}

function iso(data, hora) {
  var h = String(hora || '09:00').slice(0, 5);
  return data + 'T' + h + ':00';
}

function somaMin(hora, min) {
  var p = String(hora).split(':');
  var t = (+p[0]) * 60 + (+p[1]) + min;
  return pad(Math.floor(t / 60) % 24) + ':' + pad(t % 60);
}

function maisUmDia(data) {
  var d = new Date(data + 'T12:00:00');
  d.setDate(d.getDate() + 1);
  return Utilities.formatDate(d, TZ, 'yyyy-MM-dd');
}

function pad(n) { return (n < 10 ? '0' : '') + n; }

function out(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/* ---------------------------------------------------------------------------
   DIAGNOSTICO. Pode apagar depois que a ponte estiver funcionando.
   Roda direto no editor, nao interfere no web app.
--------------------------------------------------------------------------- */

/** Confirma que o calendario de teste de nivel aceita evento com Meet. */
function testeCalendarioTestes() {
  var cal = '8a84694af0b2b09f5c8df635c96b99bf44f6df1aa23f46fc8f318cd5fb4c42c8@group.calendar.google.com';
  var d = new Date(Date.now() + 86400000);
  var dia = Utilities.formatDate(d, TZ, 'yyyy-MM-dd');
  var ev = Calendar.Events.insert({
    summary: 'TESTE ponte v2.1 (apagar)',
    start: { dateTime: dia + 'T15:00:00', timeZone: TZ },
    end:   { dateTime: dia + 'T15:30:00', timeZone: TZ },
    conferenceData: { createRequest: {
      requestId: 'teste-' + Date.now(),
      conferenceSolutionKey: { type: 'hangoutsMeet' }
    }}
  }, cal, { conferenceDataVersion: 1 });
  Logger.log('Meet: ' + (ev.hangoutLink || 'NAO CRIOU'));
  Calendar.Events.remove(cal, ev.id);
  Logger.log('evento de teste removido');
}

/** Lista os calendarios que esta conta enxerga, com o nivel de acesso. */
function listaCalendarios() {
  Logger.log('Conta: ' + Session.getEffectiveUser().getEmail());
  (Calendar.CalendarList.list().items || []).forEach(function (c) {
    Logger.log(c.id + '  |  ' + c.summary + '  |  ' + c.accessRole);
  });
}
