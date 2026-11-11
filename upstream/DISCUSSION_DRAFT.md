# Idea: optionally focus an existing Zen window when launched again on Windows

Launching Zen again from Windows Search currently opens another main window even when a suitable Zen window is already open. I would like an opt-in Startup setting named **“Focus an existing window when Zen is launched again.”**

With the option enabled, an argument-free relaunch would restore and focus a suitable existing main window, including one on another virtual desktop. A cold launch would still open Zen. Explicit New Window/private-window/kiosk commands and external-link routing would keep their current behavior. Ordinary launches should not reveal a private session.

I have a working local workaround for Zen `1.24.1b` and a draft source patch that adds a default-off preference and a localized Settings checkbox. The source candidate targets a pinned `dev` commit and passes patch-application/syntax checks; it still needs a complete Zen build and browser tests. The local workaround required startup-cache invalidation after changing the browser archive.

Would this behavior be welcome upstream, and is the Startup group the preferred place for the control? I propose Windows-only initially, because that is the platform whose relaunch behavior has been tested. I am happy to adjust the preference name, UI wording, scope, and tests to fit the project.

Related report: https://github.com/zen-browser/desktop/issues/13469

Before posting, add a link to this repository's `upstream/` directory and describe the exact Windows/Zen version used for your tests.
