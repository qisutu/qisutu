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

    var StorageKey = 'qisutu.sidebar.collapsed';
    var DesktopMediaQuery = window.matchMedia('(min-width: 901px)');

    function IsCollapsed() {
        return document.documentElement.classList.contains('qisutu-sidebar-collapsed');
    }

    function SetStoredState(Collapsed) {
        try {
            window.localStorage.setItem(StorageKey, Collapsed ? '1' : '0');
        }
        catch (Error) {
            // The navigation still works when browser storage is unavailable.
        }
    }

    document.addEventListener('DOMContentLoaded', function () {
        var Sidebar = document.getElementById('QisutuSidebar');
        var Toggle = document.getElementById('QisutuSidebarToggle');

        if (!Sidebar || !Toggle) {
            return;
        }

        var ToggleIcon = Toggle.querySelector('.qisutu-sidebar-toggle-icon');
        var ToggleLabel = Toggle.querySelector('.qisutu-sidebar-toggle-label');
        var CollapseLabel = Toggle.getAttribute('data-collapse-label') || 'Collapse navigation';
        var ExpandLabel = Toggle.getAttribute('data-expand-label') || 'Expand navigation';
        var NavigationGroups = Array.prototype.slice.call(
            Sidebar.querySelectorAll('.qisutu-nav-group')
        );
        var UserArea = Sidebar.querySelector('.qisutu-sidebar-user');
        var UserButton = Sidebar.querySelector('.qisutu-sidebar-user-avatar');

        function CloseNavigationFlyouts(ExceptGroup) {
            NavigationGroups.forEach(function (Group) {
                if (Group === ExceptGroup) {
                    return;
                }

                Group.classList.remove('qisutu-flyout-open');

                var ParentItem = Group.querySelector('.qisutu-nav-item-parent');
                var SubNavigation = Group.querySelector('.qisutu-subnav');

                if (ParentItem) {
                    ParentItem.setAttribute('aria-expanded', 'false');
                }

                if (SubNavigation) {
                    SubNavigation.style.transform = '';
                }
            });
        }

        function CloseUserFlyout() {
            if (!UserArea) {
                return;
            }

            UserArea.classList.remove('qisutu-user-flyout-open');

            if (UserButton) {
                UserButton.setAttribute('aria-expanded', 'false');
            }
        }

        function CloseAllFlyouts() {
            CloseNavigationFlyouts();
            CloseUserFlyout();
        }

        function PositionFlyout(SubNavigation) {
            if (!SubNavigation) {
                return;
            }

            SubNavigation.style.transform = '';

            window.requestAnimationFrame(function () {
                var Rect = SubNavigation.getBoundingClientRect();
                var ViewportPadding = 12;
                var Shift = 0;

                if (Rect.bottom > window.innerHeight - ViewportPadding) {
                    Shift -= Rect.bottom - (window.innerHeight - ViewportPadding);
                }

                if (Rect.top + Shift < ViewportPadding) {
                    Shift += ViewportPadding - (Rect.top + Shift);
                }

                if (Shift) {
                    SubNavigation.style.transform = 'translateY(' + Shift + 'px)';
                }
            });
        }

        function UpdateToggle() {
            var Collapsed = IsCollapsed();
            var Label = Collapsed ? ExpandLabel : CollapseLabel;

            Toggle.setAttribute('aria-expanded', Collapsed ? 'false' : 'true');
            Toggle.setAttribute('aria-label', Label);
            Toggle.setAttribute('title', Label);

            if (ToggleIcon) {
                ToggleIcon.textContent = Collapsed ? '›' : '‹';
            }

            if (ToggleLabel) {
                ToggleLabel.textContent = Label;
            }
        }

        function SetCollapsed(Collapsed, Persist) {
            document.documentElement.classList.toggle('qisutu-sidebar-collapsed', Collapsed);
            CloseAllFlyouts();
            UpdateToggle();

            if (Persist) {
                SetStoredState(Collapsed);
            }
        }

        Toggle.addEventListener('click', function () {
            if (!DesktopMediaQuery.matches) {
                return;
            }

            SetCollapsed(!IsCollapsed(), true);
        });

        NavigationGroups.forEach(function (Group) {
            var ParentItem = Group.querySelector('.qisutu-nav-item-parent');
            var SubNavigation = Group.querySelector('.qisutu-subnav');

            if (!ParentItem || !SubNavigation) {
                return;
            }

            function ToggleFlyout(Event) {
                if (!DesktopMediaQuery.matches || !IsCollapsed()) {
                    return;
                }

                Event.preventDefault();
                Event.stopPropagation();

                var Open = !Group.classList.contains('qisutu-flyout-open');

                CloseNavigationFlyouts(Group);
                CloseUserFlyout();
                Group.classList.toggle('qisutu-flyout-open', Open);
                ParentItem.setAttribute('aria-expanded', Open ? 'true' : 'false');

                if (Open) {
                    PositionFlyout(SubNavigation);
                }
                else {
                    SubNavigation.style.transform = '';
                }
            }

            ParentItem.addEventListener('click', ToggleFlyout);
            ParentItem.addEventListener('keydown', function (Event) {
                if (Event.key !== 'Enter' && Event.key !== ' ') {
                    return;
                }

                ToggleFlyout(Event);
            });
        });

        if (UserArea && UserButton) {
            UserButton.addEventListener('click', function (Event) {
                if (!DesktopMediaQuery.matches || !IsCollapsed()) {
                    return;
                }

                Event.preventDefault();
                Event.stopPropagation();

                var Open = !UserArea.classList.contains('qisutu-user-flyout-open');

                CloseNavigationFlyouts();
                UserArea.classList.toggle('qisutu-user-flyout-open', Open);
                UserButton.setAttribute('aria-expanded', Open ? 'true' : 'false');
            });
        }

        document.addEventListener('click', function (Event) {
            if (!IsCollapsed() || Sidebar.contains(Event.target)) {
                return;
            }

            CloseAllFlyouts();
        });

        document.addEventListener('keydown', function (Event) {
            if (Event.key !== 'Escape') {
                return;
            }

            CloseAllFlyouts();
        });

        window.addEventListener('resize', function () {
            CloseAllFlyouts();
        });

        if (typeof DesktopMediaQuery.addEventListener === 'function') {
            DesktopMediaQuery.addEventListener('change', CloseAllFlyouts);
        }
        else if (typeof DesktopMediaQuery.addListener === 'function') {
            DesktopMediaQuery.addListener(CloseAllFlyouts);
        }

        UpdateToggle();
    });
}());
