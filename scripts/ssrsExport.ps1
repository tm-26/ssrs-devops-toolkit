# ============================================
# SSRS Report Export Script
# ============================================

param (
    [string]$configPath = "../config.json"
)

# Set Working Directory To Script Location
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-Location $scriptDirectory

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$exportRoot = Join-Path $scriptDirectory "..\exports"

$exportPath = Join-Path $exportRoot $timestamp

# Ensure directories exist
if (!(Test-Path $exportRoot)) {
    New-Item -ItemType Directory -Path $exportRoot | Out-Null
}

if (!(Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}


# Load Config
$config = Get-Content $configPath | ConvertFrom-Json

$reportServerUrl = $config.reportServerUrl
$rootFolder = $config.rootFolder

# Create Export Folder
if (!(Test-Path $exportPath)) {

    New-Item `
        -ItemType Directory `
        -Path $exportPath | Out-Null
}

# Create SSRS Web Service Proxy

$ssrsProxy = New-WebServiceProxy `
    -Uri $reportServerUrl `
    -Namespace "SSRS" `
    -UseDefaultCredential

# Recursive Export Function
function exportSsrsFolder {

    param (
        [string]$folderPath
    )

    Write-Host "Scanning folder: $folderPath"

    $items = $ssrsProxy.ListChildren(
        $folderPath,
        $false
    )

    foreach ($item in $items) {

        $cleanPath = $item.Path.TrimStart("/")

        $localPath = Join-Path `
            $exportPath `
            $cleanPath

        if ($item.TypeName -eq "Folder") {

            if (!(Test-Path $localPath)) {

                New-Item `
                    -ItemType Directory `
                    -Path $localPath | Out-Null
            }

            exportSsrsFolder `
                -folderPath $item.Path
        }

        elseif ($item.TypeName -eq "Report") {

            Write-Host "Exporting report: $($item.Path)"

            $reportDefinition = $ssrsProxy.GetItemDefinition(
                $item.Path
            )

            $reportFile = "$localPath.rdl"

            $directory = Split-Path $reportFile

            if (!(Test-Path $directory)) {

                New-Item `
                    -ItemType Directory `
                    -Path $directory `
                    -Force | Out-Null
            }

            [System.IO.File]::WriteAllBytes(
                $reportFile,
                $reportDefinition
            )
        }
    }
}

# Start Export

Write-Host ""
Write-Host "Starting SSRS export..."
Write-Host "Export Path: $exportPath"
Write-Host ""

exportSsrsFolder `
    -folderPath '/'

Write-Host ""
Write-Host "Export complete."
Write-Host ""