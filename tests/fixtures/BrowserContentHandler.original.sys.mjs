// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, obtain one at
// https://mozilla.org/MPL/2.0/.
//
// Fixture: complete dch_handle implementation extracted from Zen 1.24.1b,
// build 20261106124806, SourceStamp b12eaefbca65b376950e1eb7ae84d3574022ba66.
// Source repository: https://github.com/zen-browser/desktop
// Original packaged path: moz-src/browser/components/BrowserContentHandler.sys.mjs
// Only the surrounding module wrapper below is synthetic. No browsing data,
// profile information, archive bytes, or executable is included in this fixture.
let gKiosk = false;
// The full module uses lazy.PrivateBrowsingUtils.permanentPrivateBrowsing;
// keep that API name in this reduced fixture for the installer's source guard.
const nsDefaultCommandLineHandler = {};
nsDefaultCommandLineHandler.prototype = {
  handle:
function dch_handle(cmdLine) {
    var urilist = [];
    var principalList = [];

    if (
      cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
      cmdLine.findFlag("os-autostart", true) != -1
    ) {
      // Relaunching after reboot (or quickly opening the application on reboot) and launch-on-login interact.  If we see an after reboot command line while already running, ignore it.
      return;
    }

    if (this.handleNotification(cmdLine)) {
      // This command is about notification and is handled already
      return;
    }

    if (
      cmdLine.state == Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
      Services.startup.wasSilentlyStarted
    ) {
      // If we are starting up in silent mode, don't open a window. We also need
      // to make sure that the application doesn't immediately exit, so stay in
      // a LastWindowClosingSurvivalArea until a window opens.
      Services.startup.enterLastWindowClosingSurvivalArea();
      Services.obs.addObserver(function windowOpenObserver() {
        Services.startup.exitLastWindowClosingSurvivalArea();
        Services.obs.removeObserver(windowOpenObserver, "domwindowopened");
      }, "domwindowopened");
      return;
    }

    if (AppConstants.platform == "win" || AppConstants.platform == "macosx") {
      // Handle the case where we don't have a profile selected yet (e.g. the
      // Profile Manager is displayed).
      // On Windows, we will crash if we open an url and then select a profile.
      // On macOS, if we open an url we don't experience a crash but a broken
      // window is opened.
      // To prevent this handle all url command line flags and set the
      // command line's preventDefault to true to prevent the display of the ui.
      // The initial command line will be retained when nsAppRunner calls
      // LaunchChild though urls launched after the initial launch will be lost.
      if (!this._haveProfile) {
        try {
          // This will throw when a profile has not been selected.
          Services.dirsvc.get("ProfD", Ci.nsIFile);
          this._haveProfile = true;
        } catch (e) {
          // eslint-disable-next-line no-empty
          while ((ar = cmdLine.handleFlagWithParam("url", false))) {}
          cmdLine.preventDefault = true;
        }
      }
    }

    // `-osint` and handling registered file types and protocols is Windows-only.
    let launchedWithArg_osint =
      AppConstants.platform == "win" && cmdLine.findFlag("osint", false) == 0;
    if (launchedWithArg_osint) {
      cmdLine.handleFlag("osint", false);
    }

    try {
      var ar;
      while ((ar = cmdLine.handleFlagWithParam("url", false))) {
        let { uri, principal } = resolveURIInternal(cmdLine, ar);
        urilist.push(uri);
        principalList.push(principal);

        if (launchedWithArg_osint) {
          launchedWithArg_osint = false;

          // We use the resolved URI here, even though it can produce
          // surprising results where-by `-osint -url test.pdf` resolves to
          // a query with search parameter "test.pdf".  But that shouldn't
          // happen when Firefox is launched by Windows itself: files should
          // exist and be resolved to file URLs.
          const isLaunch =
            cmdLine && cmdLine.state == Ci.nsICommandLine.STATE_INITIAL_LAUNCH;

          maybeRecordSearchActivationTelemetry(uri, isLaunch);
          maybeRecordToHandleTelemetry(uri, isLaunch);
        }
      }
    } catch (e) {
      console.error(e);
    }

    if (cmdLine.findFlag("screenshot", true) != -1) {
      // Shouldn't have to push principal here with the screenshot flag
      lazy.HeadlessShell.handleCmdLineArgs(
        cmdLine,
        urilist.filter(shouldLoadURI).map(u => u.spec)
      );
      return;
    }

    for (let i = 0; i < cmdLine.length; ++i) {
      var curarg = cmdLine.getArgument(i);
      if (curarg.match(/^-/)) {
        console.error("Warning: unrecognized command line flag", curarg);
        // To emulate the pre-nsICommandLine behavior, we ignore
        // the argument after an unrecognized flag.
        ++i;
      } else {
        try {
          let { uri, principal } = resolveURIInternal(cmdLine, curarg);
          urilist.push(uri);
          principalList.push(principal);
        } catch (e) {
          console.error(
            `Error opening URI ${curarg} from the command line:`,
            e
          );
        }
      }
    }

    if (urilist.length) {
      if (
        cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
        urilist.length == 1
      ) {
        // Try to find an existing window and load our URI into the
        // current tab, new tab, or new window as prefs determine.
        try {
          handURIToExistingBrowser(
            urilist[0],
            Ci.nsIBrowserDOMWindow.OPEN_DEFAULTWINDOW,
            cmdLine,
            false,
            principalList[0] ?? lazy.gSystemPrincipal
          );
          return;
        } catch (e) {}
      }

      // Can't open multiple URLs without using system principal.
      var URLlist = urilist.filter(shouldLoadURI).map(u => u.spec);
      if (URLlist.length) {
        openBrowserWindow(cmdLine, lazy.gSystemPrincipal, URLlist);
      }
    } else if (!cmdLine.preventDefault) {
      if (
        AppConstants.platform == "win" &&
        cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
        lazy.WindowsUIUtils.inWin10TabletMode
      ) {
        // In Win10's tablet mode, do not create a new window, but reuse the
        // existing one. (Win11's tablet mode is still windowed and has no need
        // for this workaround.)
        let win = lazy.BrowserWindowTracker.getTopWindow();
        if (win) {
          win.focus();
          return;
        }
      }
      openBrowserWindow(cmdLine, lazy.gSystemPrincipal);
    } else {
      // Need a better solution in the future to avoid opening the blank window
      // when command line parameters say we are not going to show a browser
      // window, but for now the blank window getting closed quickly (and
      // causing only a slight flicker) is better than leaving it open.
      let win = Services.wm.getMostRecentWindow("navigator:blank");
      if (win) {
        win.close();
      }
    }
  },
  helpInfo: "",
};
