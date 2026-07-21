/*
 * Qisutu - Open Source Ticket System
 * Copyright (C) 2026 Franziska Steps
 * Qisutu - Kim-KI, https://qisutu.de
 *
 * This file is part of Qisutu.
 *
 * Qisutu is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Qisutu is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-FileCopyrightText: 2026 Franziska Steps
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

(function () {
    'use strict';
    var modal = document.querySelector('[data-api-user-modal]');
    if (!modal) { return; }
    var search = modal.querySelector('[data-api-user-search]');
    var results = modal.querySelector('[data-api-user-results]');
    var idInput = document.querySelector('[data-api-user-id]');
    var display = document.querySelector('[data-api-user-display]');
    var timer = 0;
    function esc(value) { var node=document.createElement('span');node.textContent=value==null?'':String(value);return node.innerHTML; }
    function close() { modal.classList.add('qisutu-hidden');modal.setAttribute('aria-hidden','true'); }
    function load() {
        window.clearTimeout(timer);timer=window.setTimeout(function(){
            results.innerHTML='<p>…</p>';
            fetch('index.pl?Page=AdminAPI&Step=APIUserSearch&Search='+encodeURIComponent(search.value||''),{credentials:'same-origin',headers:{'Accept':'application/json'}})
                .then(function(r){return r.json();}).then(function(data){
                    var items=data&&data.items?data.items:[];
                    if(!items.length){results.innerHTML='<p>'+esc(modal.getAttribute('data-no-results'))+'</p>';return;}
                    results.innerHTML=items.map(function(item){var account=item.account_type==='customer'?modal.getAttribute('data-customer-label'):modal.getAttribute('data-agent-label');var customer=item.customer_name?' · '+item.customer_name:'';return '<button type="button" class="qisutu-api-user-result" data-id="'+item.id+'" data-label="'+esc(item.name+' — '+item.login)+'"><strong>'+esc(item.name)+'</strong><span>'+esc(account+' · '+item.login+' · '+(item.email||'')+customer)+'</span></button>';}).join('');
                }).catch(function(){results.innerHTML='<p>'+esc(modal.getAttribute('data-search-error'))+'</p>';});
        },200);
    }
    document.querySelector('[data-api-open-users]').addEventListener('click',function(){modal.classList.remove('qisutu-hidden');modal.setAttribute('aria-hidden','false');search.focus();load();});
    modal.querySelector('[data-api-close-users]').addEventListener('click',close);
    modal.addEventListener('click',function(e){if(e.target===modal){close();}var row=e.target.closest('[data-id]');if(row){idInput.value=row.getAttribute('data-id');display.value=row.getAttribute('data-label');close();}});
    search.addEventListener('input',load);
    document.addEventListener('keydown',function(e){if(e.key==='Escape'&&!modal.classList.contains('qisutu-hidden')){close();}});
    var copy=document.querySelector('[data-api-copy-token]');if(copy){copy.addEventListener('click',function(){var value=document.getElementById('qisutu-api-new-token').textContent;navigator.clipboard.writeText(value).then(function(){copy.textContent=copy.getAttribute('data-copied-label');});});}
    document.querySelectorAll('[data-api-deactivate]').forEach(function(form){form.addEventListener('submit',function(e){if(!window.confirm(modal.getAttribute('data-confirm-deactivate'))){e.preventDefault();}});});
}());
