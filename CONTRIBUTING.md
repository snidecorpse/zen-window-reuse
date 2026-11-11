# Contributing

Report the Zen version, Windows version, PowerShell version, command used, and expected/actual window behavior. The [troubleshooting guide](docs/TROUBLESHOOTING.md) covers the startup-cache issue and update compatibility. Redact account names, profile paths, URLs, and browsing data from logs.

For the installer, preserve these guarantees:

- Unknown or ambiguous handler layouts stop before installation.
- Existing archive entries keep their exact names and unchanged decompressed contents.
- Apply and restore require Zen to be fully closed, keep matching backups, and detect concurrent changes.
- Browser code cache invalidation runs after apply, an already-patched repair, and restore.
- Preparation and checks do not change the installation or profiles.
- Default relaunches respect private-window separation and explicit new-window requests.

Run the fixture tests described in the README. Tests must use synthetic installations and profiles. Do not commit `omni.ja`, browser profiles, extracted full browser distributions, or machine-specific diagnostic files.

For a built-in Zen option, see [the upstream proposal](docs/UPSTREAM_PROPOSAL.md) and [the source contribution package](upstream/README.md). The local installer is a temporary workaround; the upstream feature should be an ordinary preference with a localized Settings control. Discuss the behavior with Zen maintainers before investing in a full build or opening a pull request.

Contributions are provided under MPL-2.0. Preserve the upstream notices on covered source.
