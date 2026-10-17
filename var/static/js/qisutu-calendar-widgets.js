/*
Qisutu - Open Source Ticket System
Copyright (C) 2026 Franziska Steps
Qisutu - Kim-KI, https://qisutu.de

This file is part of Qisutu.

Qisutu is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Qisutu is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Qisutu. If not, see <https://www.gnu.org/licenses/>.

SPDX-FileCopyrightText: 2026 Franziska Steps
SPDX-License-Identifier: AGPL-3.0-or-later
*/
(function(){
'use strict';
const tray=document.getElementById('qc-notifications');if(!tray)return;
const escDate=d=>{const t=new Date(d.replace(' ','T'));return Number.isNaN(t.getTime())?d:t.toLocaleString('de-DE',{dateStyle:'short',timeStyle:'short'});};
function el(tag,text){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
async function api(step,params={},data){const url=new URL('index.pl',location.href);url.searchParams.set('Page','AgentCalendar');url.searchParams.set('Step',step);for(const[k,v]of Object.entries(params))url.searchParams.set(k,v);const opt={credentials:'same-origin'};if(data){opt.method='POST';opt.body=new URLSearchParams({CSRFToken:tray.dataset.csrf,Data:JSON.stringify(data)});}const res=await fetch(url,opt);if(!res.ok)throw Error('Kalender konnte nicht geladen werden.');const result=await res.json();if(!result.success)throw Error(result.message||'Kalender konnte nicht geladen werden.');return result.data;}
function dates(){const now=new Date(),from=new Date(now),to=new Date(now);from.setDate(from.getDate()-1);to.setDate(to.getDate()+30);return {From:from.toISOString().slice(0,10),To:to.toISOString().slice(0,10)};}
async function widgets(){for(const box of document.querySelectorAll('[data-qc-upcoming],[data-qc-ticket]')){const content=box.querySelector('[data-qc-widget-content]');try{const p=dates();if(box.dataset.qcTicket)p.TicketID=box.dataset.qcTicket;else p.Mine=1;let events=await api('List',p);if(!box.dataset.qcTicket)events=events.filter(e=>new Date(e.end.replace(' ','T'))>=new Date());content.replaceChildren();if(!events.length){content.append(el('p','Keine Termine vorhanden.'));continue;}for(const e of events.slice(0,15)){const row=el('div');row.className='qc-widget-row';const a=el('a',e.title);a.href='index.pl?Page=AgentCalendar&EventID='+e.id+'&OccurrenceID='+e.occurrence_id;const when=el('time',e.all_day?e.start_local.slice(0,10)+' · Ganztägig':escDate(e.start.replace(' ','T')));row.append(a,when);content.append(row);}if(events.length>15)content.append(el('p',events.length+' verknüpfte Termine.'));}catch(e){content.textContent=e.message;}}}
let polling=false;
async function poll(){if(polling||document.hidden)return;polling=true;try{const notes=await api('Notifications');tray.replaceChildren();for(const n of notes.slice(0,5)){const box=el('section');box.className='qc-notification';const h=el('strong',n.notice);const a=el('a',n.title);a.href='index.pl?Page=AgentCalendar&EventID='+n.event_id+(n.occurrence_id?'&OccurrenceID='+n.occurrence_id:'');const p=el('p',n.start_local+' · '+n.timezone);box.append(h,el('br'),a,p);for(const[action,label]of [['read','Erledigt'],['snooze','In 10 Minuten']]){const b=el('button',label);b.type='button';b.onclick=async()=>{b.disabled=true;try{await api('NotificationRead',{}, {id:n.id,snooze:action==='snooze'?1:0});box.remove();}catch(e){p.textContent=e.message;b.disabled=false;}};box.append(b);}tray.append(box);}}catch(_){/* Keep the current page usable during a session timeout or an update. */}finally{polling=false;}}
widgets();poll();setInterval(poll,30000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll();});
})();
