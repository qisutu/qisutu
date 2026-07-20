/*
 * Qisutu - Open Source Ticket System
 * Copyright (C) 2026 Franziska Steps
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

(function () {
    'use strict';

    function renderQRCode(Container) {
        var URI = Container.getAttribute('data-qisutu-two-factor-uri') || '';
        var Label = Container.getAttribute('data-qisutu-two-factor-label') || '';

        if (!URI || typeof window.qrcode !== 'function') {
            return;
        }

        try {
            var QRCode = window.qrcode(0, 'M');
            QRCode.addData(URI, 'Byte');
            QRCode.make();
            Container.innerHTML = QRCode.createSvgTag({
                cellSize: 5,
                margin: 4,
                scalable: true
            });

            var SVG = Container.querySelector('svg');
            if (SVG) {
                SVG.setAttribute('role', 'img');
                SVG.setAttribute('aria-label', Label);
                SVG.setAttribute('focusable', 'false');
            }

            Container.classList.add('qisutu-two-factor-qr-ready');
        }
        catch (Error) {
            // The manual secret remains available when QR rendering fails.
        }
    }

    var Containers = document.querySelectorAll('[data-qisutu-two-factor-uri]');
    for (var Index = 0; Index < Containers.length; Index += 1) {
        renderQRCode(Containers[Index]);
    }
}());
