param (
    [string]$configPath = "../config.json"
)

# Load Config
$scriptDirectory = $PSScriptRoot
$configPath = Join-Path $scriptDirectory "..\config.json"
try {
    $configPath = Resolve-Path $configPath -ErrorAction Stop
}
catch {
    Write-Error "Config file not found at expected path: $configPath"
    exit 1
}
$config = Get-Content $configPath | ConvertFrom-Json

$reportServerUrl = $config.reportServerUrl
$sourceBranch = $config.sourceBranch
$targetBranch = $config.targetBranch

# Resolve Script Directory
$scriptDirectory = Split-Path `
    -Parent `
    $MyInvocation.MyCommand.Path

Set-Location $scriptDirectory

$ssrsProxy = New-WebServiceProxy `
    -Uri $reportServerUrl `
    -Namespace "SSRS" `
    -UseDefaultCredential

# Supported Extensions
function isDeployableAsset {

    param (
        [string]$filePath
    )

    $supportedExtensions = @(
        ".rdl",
        ".rds",
        ".rsds",
        ".rsd",
        ".png",
        ".jpg",
        ".jpeg"
    )

    $extension = [System.IO.Path]::GetExtension(
        $filePath
    ).ToLower()

    return $supportedExtensions -contains $extension
}

# Resolve SSRS Item Type
function resolveSsrsItemType {

    param (
        [string]$filePath
    )

    $extension = [System.IO.Path]::GetExtension(
        $filePath
    ).ToLower()

    switch ($extension) {

        ".rdl"  { return "Report" }
        ".rds"  { return "DataSource" }
        ".rsds" { return "DataSource" }
        ".rsd"  { return "DataSet" }

        ".png"  { return "Resource" }
        ".jpg"  { return "Resource" }
        ".jpeg" { return "Resource" }

        default {
            throw "Unsupported extension: $extension"
        }
    }
}

# Convert Git Path -> SSRS Path
function convertToSsrsPath {

    param (
        [string]$filePath
    )

    $normalizedPath = $filePath `
        -replace "\\", "/"

    $ssrsPath = "/" + $normalizedPath

    $extension = [System.IO.Path]::GetExtension(
        $ssrsPath
    )

    if ($extension -eq ".rdl") {

        $ssrsPath = $ssrsPath `
            -replace "\.rdl$", ""
    }

    return $ssrsPath
}

# Get Parent Folder
function getSsrsParentPath {

    param (
        [string]$ssrsPath
    )

    $parent = Split-Path `
        $ssrsPath `
        -Parent

    if ([string]::IsNullOrEmpty($parent)) {
        return "/"
    }

    return $parent.Replace("\", "/")
}

# Ensure Folder Exists
function ensureSsrsFolder {

    param (
        [string]$ssrsFolderPath
    )

    if ($ssrsFolderPath -eq "/") {
        return
    }

    $parts = $ssrsFolderPath.Trim("/").Split("/")

    $currentPath = ""

    foreach ($part in $parts) {

        $currentPath = "$currentPath/$part"

        try {

            $null = $ssrsProxy.ListChildren(
                $currentPath,
                $false
            )
        }
        catch {

            Write-Host "Creating folder:"
            Write-Host $currentPath
            Write-Host ""

            $parent = Split-Path `
                $currentPath `
                -Parent

            if ([string]::IsNullOrEmpty($parent)) {
                $parent = "/"
            }

            $parent = $parent.Replace("\", "/")

            $ssrsProxy.CreateFolder(
                $part,
                $parent,
                $null
            )
        }
    }
}

# Deploy Asset
function deployAsset {

    param (
        [string]$filePath
    )

    $ssrsPath = convertToSsrsPath `
        $filePath

    $parentPath = getSsrsParentPath `
        $ssrsPath

    $itemName = Split-Path `
        $ssrsPath `
        -Leaf

    $itemType = resolveSsrsItemType `
        $filePath

    ensureSsrsFolder `
        $parentPath

    Write-Host "Deploying:"
    Write-Host $ssrsPath
    Write-Host ""

    $fileBytes = [System.IO.File]::ReadAllBytes(
        $filePath
    )

    try {

        $ssrsProxy.CreateCatalogItem(
            $itemType,
            $itemName,
            $parentPath,
            $true,
            $fileBytes,
            $null
        )

        Write-Host "Created successfully."
        Write-Host ""
    }
    catch {

        Write-Host "Updating existing asset..."
        Write-Host ""

        if ($itemType -eq "Report") {

            $ssrsProxy.SetItemDefinition(
                $ssrsPath,
                $fileBytes
            )
        }
        else {

            $ssrsProxy.CreateCatalogItem(
                $itemType,
                $itemName,
                $parentPath,
                $true,
                $fileBytes,
                $null
            )
        }

        Write-Host "Updated successfully."
        Write-Host ""
    }
}

# Delete Asset
function deleteAsset {

    param (
        [string]$filePath
    )

    $ssrsPath = convertToSsrsPath `
        $filePath

    Write-Host "Deleting:"
    Write-Host $ssrsPath
    Write-Host ""

    try {

        $ssrsProxy.DeleteItem(
            $ssrsPath
        )

        Write-Host "Deleted successfully."
        Write-Host ""
    }
    catch {

        Write-Host "Delete failed or item missing."
        Write-Host ""
    }
}

# Get Git Diff
Write-Host ""
Write-Host "======================================"
Write-Host "SSRS Git Deployment"
Write-Host "======================================"
Write-Host ""

Write-Host "Comparing:"
Write-Host "$targetBranch -> $sourceBranch"
Write-Host ""

$diff = git diff `
    --name-status `
    $targetBranch `
    $sourceBranch

if (-not $diff) {
    Write-Host "No changes detected."
    Write-Host ""
    exit 0
}

# Process Git Changes
foreach ($line in $diff) {

    $parts = $line -split "`t"

    $changeType = $parts[0]

    # ========================================
    # RENAME
    # ========================================

    if ($changeType -like "R*") {

        $oldFile = $parts[1]
        $newFile = $parts[2]

        if (!(isDeployableAsset $oldFile)) {
            continue
        }

        Write-Host "RENAME"
        Write-Host "OLD:"
        Write-Host $oldFile
        Write-Host "NEW:"
        Write-Host $newFile
        Write-Host ""

        deleteAsset $oldFile
        deployAsset $newFile

        continue
    }

    # NORMAL FILE OPERATIONS
    $filePath = $parts[1]

    if (!(isDeployableAsset $filePath)) {

        Write-Host "Skipping unsupported asset:"
        Write-Host $filePath
        Write-Host ""

        continue
    }

    switch ($changeType) {

        "A" {
            Write-Host "CREATE"
            deployAsset $filePath
        }

        "M" {
            Write-Host "UPDATE"
            deployAsset $filePath
        }

        "D" {
            Write-Host "DELETE"
            deleteAsset $filePath
        }

        default {
            Write-Host "Skipping unsupported git operation:"
            Write-Host $changeType
            Write-Host ""
        }
    }
}

Write-Host ""
Write-Host "======================================"
Write-Host "SSRS Deployment Complete"
Write-Host "======================================"
Write-Host ""