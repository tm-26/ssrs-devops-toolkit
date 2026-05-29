# SSRS Git CI/CD Deployment Tool

This repository provides a lightweight CI/CD workflow for Native Mode SSRS using Git and PowerShell.

The solution integrates with Git using a `pre-push` [hook](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks). Whenever reports are modified locally and pushed to Git, the changes are also automatically deployed to the SSRS server.

## Features

* One-time extraction of all reports from an SSRS server
* Automatic deployment during `git push`
* Handles:

  * Report additions
  * Report deletions
  * Report renames
  * Folder structure synchronization
* Supports all item types supported by Native SSRS
* Uses existing Windows credentials during extraction/deployment

> **Note:**
> This solution was tested on **SSRS Native Mode** only.
> SharePoint-integrated mode is not officially supported.

---

# Setup Instructions

## Step 0 - Create a Git Repository

Create a new Git repository for storing your SSRS reports.

If your organization already has a repository structure for SSRS deployments, you should integrate this solution into it.

---

## Step 1 - Export Reports from SSRS

Copy the `scripts` folder into your Git repository.

Run the following script:

```powershell
.\scripts\ssrsExport.ps1
```

The script will:

* Connect to the SSRS server
* Extract all reports and supported assets
* Create an export folder named:

```text
Export_<timestamp>
```

The extraction process uses your default Windows credentials.

---

## Step 2 — Create the Reports Folder

Inside the root of your Git repository, create a folder named:

```text
reports
```

Copy all exported content from the generated export folder into the `reports` folder.

Your repository structure should now look similar to:

```text
repo-root/
│
├── reports/
├── scripts/
└── .git/
```

---
## Step 3 — Configure the Deployment Settings

Inside the `scripts` folder, locate the configuration file and update it to match your environment:

```json
{
    "reportServerURL": "http://localhost/reportserver/ReportService2010.asmx?wsdl",
    "sourceBranch": "main",
    "targetBranch": "origin/main"
}
```

### Configuration Options

| Setting           | Description                                                      |
| ----------------- | ---------------------------------------------------------------- |
| `reportServerURL` | URL of the target SSRS Report Service endpoint.                  |
| `sourceBranch`    | Local Git branch that will be monitored for changes.             |
| `targetBranch`    | Remote Git branch used when comparing changes during deployment. |

### Example

For a typical deployment to a production SSRS server:

```json
{
    "reportServerURL": "http://my-ssrs-server/reportserver/ReportService2010.asmx?wsdl",
    "sourceBranch": "main",
    "targetBranch": "origin/main"
}
```

Ensure the URL is reachable from the machine performing the deployment and that the executing user has sufficient permissions on the SSRS server.

## Step 4 — Install the Git Hook

Copy the following file:

```text
scripts/pre-push
```

Into:

```text
.git/hooks/
```

After this step, the deployment automation is fully configured.

---

# Workflow

Once setup is complete, you can work with SSRS reports normally.

Make any changes locally:

* Add reports
* Modify reports
* Rename reports
* Delete reports
* Reorganize folders

Then use the standard Git workflow:

```bash
git add .
git commit -m "feat(reports): Updated reports"
git push
```

During `git push`, the pre-push hook will automatically:

1. Detect SSRS changes
2. Deploy updates to the SSRS server
3. Push commits to the remote Git repository

This keeps Git and SSRS synchronized simultaneously.

---

# Recommended Best Practice

To avoid accidental overwrites or configuration drift:

> It is strongly recommended to restrict or lock direct manual changes on the SSRS server.

All report modifications should ideally flow through Git so the repository remains the single source of truth.

---

# Disclaimer

While the deployment scripts handle many scenarios automatically, including additions, deletions, and renames, there may still be edge cases where manual intervention is required.

Always validate deployments in lower environments before using in production.
