function deleteAsset {
    param (
        $ssrs,
        $file
    )

    $file = [System.IO.Path]::GetFileNameWithoutExtension($file)
    try{
        $ssrs.DeleteItem('/' + $file)
    } catch{
        Write-Host("WARNING: Failed to delete " + $file)
    }
}

function addAsset {
    param (
        $ssrs,
        $file,
        $itemType
    )

    #Create Upload directory if it doesn't exist
    $parentFolder = $file.DirectoryName
    $pathToFile = Resolve-Path (Join-Path $PSScriptRoot "..\reports\$file")
    ensureSsrsFolder -ssrs $ssrs -path $parentFolder
    
    #Get absolute file path
    $path = Join-Path $PSScriptRoot "..\reports\$file"
    $path = [System.IO.Path]::GetFullPath($path)
    
    switch($itemType) {
        {$_ -in @("Report", "DataSet", "Component", "Model")}{
            $warnings = $ssrs.CreateCatalogItem(
                $_,    #Item type
                [System.IO.Path]::GetFileNameWithoutExtension($file),    #Name of file
                '/' + $parentFolder,    #Parent folder
                $true,    #Overwrite existing
                [System.IO.File]::ReadAllBytes($path),    #Report definition
                $null,    #Properties
                [ref]$null    #Warnings
            )
        }
        "DataSource"{
            
            [xml]$rds = Get-Content -Path $path -Raw
	        $connProps = $rds.RptDataSource.ConnectionProperties

	        $definition = New-Object ($ssrs.GetType().Namespace + ".DataSourceDefinition")
	        $definition.ConnectString = $connProps.ConnectString
	        $definition.Extension = $connProps.Extension

            $ssrs.CreateDataSource(
                [System.IO.Path]::GetFileNameWithoutExtension($file),    #Name of file
                '/' + $parentFolder,    #Parent folder
                $true,
                $definition,
                $null
            )
        }

        "Resource"{
            
            $property = New-Object ($ssrs.GetType().Namespace + ".Property")

            $property.Name = "MimeType"
            $property.Value = $mimeType

            $properties = @($property)

            $warnings = $ssrs.CreateCatalogItem(
                $_,    #Item type
                [System.IO.Path]::GetFileNameWithoutExtension($file),    #Name of file
                '/' + $parentFolder,    #Parent folder
                $true,    #Overwrite existing
                [System.IO.File]::ReadAllBytes($path),    #Report definition
                $properties,    #Properties
                [ref]$null    #Warnings
            )
        }
    }
}

function ensureSsrsFolder {
    param (
        $ssrs,
        $path
    )
    if (-not $path){
        return
    }
    $parts = $path.Trim('/').Split('/')
    $current = ""

    foreach ($part in $parts) {
        $parent = if ($current) { $current } else { "/" }
        $current = "$current/$part"

        try {
            $ssrs.GetItemType($current)
        }
        catch {
            $ssrs.CreateFolder($part, $parent, $null)
        }
    }
}

#Set current working directory to scipt path.
Set-Location $PSScriptRoot

#Read config
try{
    $config = Get-Content("..\config.json") -Raw | ConvertFrom-Json
} catch{
    Write-Host "ERROR: Config File not found"
    exit -1
}

#Load paramaters
$reportServerUrl = $config.reportServerUrl
$sourceBranch = $config.sourceBranch
$targetBranch = $config.targetBranch

#Check if current branch == source branch
$currentBranch = git rev-parse --abbrev-ref HEAD
if($currentBranch -ne $sourceBranch){
    Write-Host "Current branch (" $currentBranch ") != to source branch (" $sourceBranch ')'
    exit 0
}

#Get git diff
Write-Host "Comparing" $targetBranch" with "$sourceBranch
$diff = git diff --name-status $targetBranch -- ../reports/ $sourceBranch -- ../reports/
# Write-Host $diff
if (-not $diff){
    Write-Host "No changes detected"
    exit 0
}

$filesToPush = @()
$fileTypes = @()
#Loop over every change and check if extension is supported
foreach ($file in $diff.Split("`n")){
    $idx = $file.LastIndexOf('.') 
    if($idx -le 0){
        Write-Host "Warning: Skipping file" $_ "as it does not have a file-type"
        continue
    }
    switch ($file.Substring($idx)){
        ".rdl" {
            $filesToPush += $file
            $fileTypes += "Report"
        }

        # Shared Data Sources
        ".rds" {
            $filesToPush += $file
            $fileTypes += "DataSource"
        }

        # Shared Datasets
        ".rsd" {
            $filesToPush += $file
            $fileTypes += "DataSet"
        }

        # Report Parts / Components (untested)
        ".rsc" {
            $filesToPush += $file
            $fileTypes += "Component"
        }

        # Report Models (legacy) (untested)
        ".smdl" {
            $filesToPush += $file
            $fileTypes += "Model"
        }

        # Resources
        {$_ -in @(
            ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".svg",
            ".pdf", ".doc", ".docx", ".xls", ".xlsx",
            ".csv", ".txt", ".xml",
            ".js", ".css", ".html"
            )
        }{
            $filesToPush += $file
            $fileTypes += "Resource"
        }

        default {
            Write-Host "Warning: Skipping file" $file "as it's file-type is not supported"
        } 
    }
}

if ($filesToPush -le 0){
    Write-Host "0 changes detected"
    exit 0
}

Write-Host $filesToPush.Count "changes detected"

#Create SSRS instance connection
$cred = Get-Credential
$ssrs = New-WebServiceProxy -Uri $reportServerUrl -UseDefaultCredential
#$ssrs = New-WebServiceProxy -Uri $reportServerUrl -Credential $cred

for($i = 0; $i -lt $filesToPush.Count; $i++){

    #remove everything up to first '/'
    $file = $filesToPush[$i] -replace '^[^/]+/', ''
    
    switch($filesToPush[$i].Trim()[0]){
        {$_ -in @('M', 'A')}{
            Write-Host "Adding" $file
            addAsset -ssrs $ssrs -file $file -itemType $fileTypes[$i]
        }
        'D'{ 
            Write-Host "Deleting" $file
            deleteAsset -ssrs $ssrs -file $file
        }
        'R'{ 
            $file = $file -split '\s+'
            $oldFile = $file[0]
            $newFile = $file[1] -replace '^[^/]+/', ''

            Write-Host "Renaming" $oldFile "to" $newFile
            addAsset -ssrs $ssrs -file $newFile -itemType $fileTypes[$i]
            deleteAsset -ssrs $ssrs -file $oldFile
        }
        default{Write-Host "'$_'" "is not a supported git action"} 
    }
}





