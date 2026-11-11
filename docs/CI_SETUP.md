# Enable GitHub Actions

The workflow definition is distributed as an **inactive template** in [`ci/windows-tests.yml`](../ci/windows-tests.yml). It is not under `.github/workflows`, so it does not run automatically.

The GitHub credential used for the initial publication could create and push source but lacked the OAuth `workflow` scope. GitHub rejected an active workflow. No hosted test result is claimed; all 29 cases passed locally, with PowerShell fixtures checked in Windows PowerShell 5.1 and PowerShell 7.

To activate CI from your own authenticated checkout, authorize workflow access using GitHub's normal flow:

```powershell
gh auth refresh --hostname github.com --scopes workflow
```

Complete any sign-in/authorization yourself. Alternatively, use a GitHub credential permitted to manage Actions workflows for this repository. Then move the template into the active workflow directory and push:

```powershell
New-Item -ItemType Directory -Path .github\workflows -Force
Move-Item -LiteralPath ci\windows-tests.yml -Destination .github\workflows\test.yml
git add -- ci\windows-tests.yml .github\workflows\test.yml
git commit -m "Enable Windows test workflow"
git push
```

The workflow runs on Windows with PowerShell 5.1 and PowerShell 7, checks script syntax, and runs the cache, installer, and Node handler tests using synthetic inputs. It requires no Zen installation, browser profiles, or repository secrets, and grants the job only `contents: read`.
