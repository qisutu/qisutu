/* Qisutu - Open Source Ticket System; SPDX-License-Identifier: AGPL-3.0-or-later */
(function () {
    'use strict';
    function update() {
        var visibility = document.querySelector('[data-qisutu-knowledge-visibility]');
        var scope = document.querySelector('[data-qisutu-knowledge-customer-scope]');
        var block = document.querySelector('[data-qisutu-knowledge-customer-block]');
        if (!visibility || !scope || !block) { return; }
        var customer = visibility.value === 'customer';
        scope.disabled = !customer;
        block.classList.toggle('qisutu-hidden', !customer || scope.value !== 'selected');
    }
    document.addEventListener('DOMContentLoaded', function () {
        var visibility = document.querySelector('[data-qisutu-knowledge-visibility]');
        var scope = document.querySelector('[data-qisutu-knowledge-customer-scope]');
        if (visibility) { visibility.addEventListener('change', update); }
        if (scope) { scope.addEventListener('change', update); }
        update();
    });
}());
