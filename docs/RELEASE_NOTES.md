Zen Window Reuse 0.1.0 brings an existing suitable Zen window forward when Zen is launched again without a URL on Windows.

- Reversible PowerShell installer with exact archive-content verification, matching backups, restore, and automatic browser code-cache invalidation.
- An unofficial `zen.window-reuse-on-launch` Boolean to enable or disable the installed workaround.
- Optional configuration for external links and Windows virtual desktops.
- Setup, troubleshooting, forum-post text, and an upstream contribution draft for a localized, default-off Settings checkbox.
- A Windows CI template and 29 automated cases using synthetic installations/profiles and mocked browser services.

Manually verified with Zen 1.24.1b on Windows. Close Zen before applying. Keep the generated artifacts for rollback and reapply after browser updates. The native Settings draft is separately documented and still needs a full Zen build and browser integration tests.

Only source is distributed; browser archives, profiles, and local debugging files are excluded. Licensed under MPL-2.0.
