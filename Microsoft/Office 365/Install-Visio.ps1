﻿# Standalone application install script for VDI environment - (C)2021 Jonathan Pitre & Owen Reynolds, inspired by xenappblog.com

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Custom package providers list
$PackageProviders = @("Nuget")

# Custom modules list
$Modules = @("PSADT", "Evergreen")

Write-Verbose -Message "Importing custom modules..." -Verbose

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# Install custom package providers list
Foreach ($PackageProvider in $PackageProviders) {
    If (-not(Get-PackageProvider -ListAvailable -Name $PackageProvider -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name $PackageProvider -Force }
}

# Add the Powershell Gallery as trusted repository
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

# Update PowerShellGet
$InstalledPSGetVersion = (Get-PackageProvider -Name PowerShellGet).Version
$PSGetVersion = [version](Find-PackageProvider -Name PowerShellGet).Version
If ($PSGetVersion -gt $InstalledPSGetVersion) { Install-PackageProvider -Name PowerShellGet -Force }

# Install and import custom modules list
Foreach ($Module in $Modules) {
    If (-not(Get-Module -ListAvailable -Name $Module)) { Install-Module -Name $Module -AllowClobber -Force | Import-Module -Name $Module -Force }
    Else {
        $InstalledModuleVersion = (Get-InstalledModule -Name $Module).Version
        $ModuleVersion = (Find-Module -Name $Module).Version
        $ModulePath = (Get-InstalledModule -Name $Module).InstalledLocation
        $ModulePath = (Get-Item -Path $ModulePath).Parent.FullName
        If ([version]$ModuleVersion -gt [version]$InstalledModuleVersion) {
            Update-Module -Name $Module -Force
            Remove-Item -Path $ModulePath\$InstalledModuleVersion -Force -Recurse
        }
    }
}

Write-Verbose -Message "Custom modules were successfully imported!" -Verbose

# Get the current script directory
Function Get-ScriptDirectory {
    Remove-Variable appScriptDirectory
    Try {
        If ($psEditor) { Split-Path $psEditor.GetEditorContext().CurrentFile.Path } # Visual Studio Code Host
        ElseIf ($psISE) { Split-Path $psISE.CurrentFile.FullPath } # Windows PowerShell ISE Host
        ElseIf ($PSScriptRoot) { $PSScriptRoot } # Windows PowerShell 3.0-5.1
        Else {
            Write-Host -ForegroundColor Red "Cannot resolve script file's path"
            Exit 1
        }
    }
    Catch {
        Write-Host -ForegroundColor Red "Caught Exception: $($Error[0].Exception.Message)"
        Exit 2
    }
}

# Variables Declaration
# Generic
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
$env:SEE_MASK_NOZONECHECKS = 1
$appScriptDirectory = Get-ScriptDirectory

# Application related
##*===============================================
$appVendor = "Microsoft"
$appName = "Office"
$appName2 = "Visio"
$appMajorVersion = "365"
$appSetup = "setup.exe"
$appProcesses = @("VISIO")
$appConfig = "Visio365-x64-VDI.xml"
$appBitness = ([xml](Get-Content $appConfig)).SelectNodes("//Add/@OfficeClientEdition").Value
$appDownloadParameters = "/download .\$appConfig"
$appInstallParameters = "/configure .\$appConfig"
$Evergreen = Get-EvergreenApp -Name Microsoft365Apps | Where-Object {$_.Channel -eq "Semi-Annual Channel"}
$appVersion = $Evergreen.Version
$appURL = $Evergreen.URI
$appDestination = "$env:ProgramFiles\Microsoft Office\root\Office16"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName2 .+$appMajorVersion" -RegEx)
$appInstalledVersion = (Get-InstalledApplication -Name "$appVendor $appName2 .*$appMajorVersion" -RegEx).DisplayVersion
##*===============================================

If ([version]$appVersion -gt [version]$appInstalledVersion) {
    Set-Location -Path $appScriptDirectory

    If (-Not(Test-Path -Path $appScriptDirectory\$appSetup)) {
        Write-Log -Message "Downloading the latest version of $appVendor $appName 365 Deployment Tool (ODT)..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURL -OutFile $appSetup
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }
    $appSetupVersion = (Get-Command .\$appSetup).FileVersionInfo.FileVersion

    Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    Get-Process -Name $appProcesses | Stop-Process -Force
    # https://github.com/OfficeDev/Office-IT-Pro-Deployment-Scripts/blob/master/Office-ProPlus-Deployment/Remove-PreviousOfficeInstalls/Remove-PreviousOfficeInstalls.ps1
    .\Remove-PreviousOfficeInstalls\Remove-PreviousOfficeInstalls.ps1 -RemoveClickToRunVersions $true -Force $true -Remove2016Installs $true -NoReboot $true -ProductsToRemove $appName2

    If (-Not(Test-Path -Path .\$appSetupVersion)) {New-Folder -Path $appSetupVersion}
    Copy-File .\$appConfig, $appSetup -Destination $appSetupVersion -ContinueFileCopyOnError $True
    Set-Location -Path .\$appSetupVersion

    If (-Not(Test-Path -Path .\Office\Data\v$appBitness.cab)) {
        Write-Log -Message "Downloading $appVendor $appName $appMajorVersion $appBitness via ODT $appSetupVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-Process -Path .\$appSetup -Parameters $appDownloadParameters -PassThru
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    Write-Log -Message "Installing $appVendor $appName2 $appMajorVersion $appBitness..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path .\$appSetup -Parameters $appInstallParameters -Passthru
    Get-Process -Name OfficeC2RClient | Stop-Process -Force

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True
    Rename-Item -Path "$envCommonStartMenuPrograms\OneNote 2016.lnk" -NewName "$envCommonStartMenuPrograms\OneNote.lnk"
    Get-ScheduledTask -TaskName "$appName*" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "$appName*" | Disable-ScheduledTask

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appVendor $appName2 $appMajorVersion $appBitness was successfully installed!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else {
    Write-Log -Message "$appVendor $appName2 $appMajorVersion $appBitness is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}