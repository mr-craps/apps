# Standalone application install script for VDI environment - (C)2021 Jonathan Pitre & Owen Reynolds, inspired by xenappblog.com

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Custom package providers list
$PackageProviders = @("Nuget")

# Custom modules list
$Modules = @("PSADT", "Nevergreen")

Write-Verbose -Message "Importing custom modules..." -Verbose

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# Install custom package providers list
Foreach ($PackageProvider in $PackageProviders)
{
    If (-not(Get-PackageProvider -ListAvailable -Name $PackageProvider -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name $PackageProvider -Force }
}

# Add the Powershell Gallery as trusted repository
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

# Update PowerShellGet
$InstalledPSGetVersion = (Get-PackageProvider -Name PowerShellGet).Version
$PSGetVersion = [version](Find-PackageProvider -Name PowerShellGet).Version
If ($PSGetVersion -gt $InstalledPSGetVersion) { Install-PackageProvider -Name PowerShellGet -Force }

# Install and import custom modules list
Foreach ($Module in $Modules)
{
    If (-not(Get-Module -ListAvailable -Name $Module)) { Install-Module -Name $Module -AllowClobber -Force | Import-Module -Name $Module -Force }
    Else
    {
        $InstalledModuleVersion = (Get-InstalledModule -Name $Module).Version
        $ModuleVersion = (Find-Module -Name $Module).Version
        $ModulePath = (Get-InstalledModule -Name $Module).InstalledLocation
        $ModulePath = (Get-Item -Path $ModulePath).Parent.FullName
        If ([version]$ModuleVersion -gt [version]$InstalledModuleVersion)
        {
            Update-Module -Name $Module -Force
            Remove-Item -Path $ModulePath\$InstalledModuleVersion -Force -Recurse
        }
    }
}

Write-Verbose -Message "Custom modules were successfully imported!" -Verbose

# Get the current script directory
Function Get-ScriptDirectory
{
    Remove-Variable appScriptDirectory
    Try
    {
        If ($psEditor) { Split-Path $psEditor.GetEditorContext().CurrentFile.Path } # Visual Studio Code Host
        ElseIf ($psISE) { Split-Path $psISE.CurrentFile.FullPath } # Windows PowerShell ISE Host
        ElseIf ($PSScriptRoot) { $PSScriptRoot } # Windows PowerShell 3.0-5.1
        Else
        {
            Write-Host -ForegroundColor Red "Cannot resolve script file's path"
            Exit 1
        }
    }
    Catch
    {
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
Function Test-FTPConnection
{
    <#
    .SYNOPSIS
        The Test-FTPConnection function allows you to test an FTP connection.

    .DESCRIPTION
        The Test-FTPConnection function allows you to test an FTP connection.

    .PARAMETER URL

    .EXAMPLE
        Test-FTPConnection -URL "ftp.adobe.com"

        This will test the ftp connection for URL ftp.adobe.com.

    .NOTES
        Author: Jonathan Pitre
        Twitter: @PitreJonathan
    #>

    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true)]
        [String]$URL,

        [Alias("RunAs")]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty

    ) #Param

    Process
    {
        If ($URL)
        {
            Write-Verbose -Message "One or more URL specified" -Verbose
            Try
            {
                Test-NetConnection -ComputerName $URL -Port 21 | Select-Object -ExpandProperty TcpTestSucceeded
            } #Try
            Catch
            {
                Throw "Failed to connect to URL: $URL with error $_."
                Break
            } #Catch
        } # If
    } #Process
}

$appVendor = "Adobe"
$appName = "Acrobat Reader"
$appShortVersion = "DC"
$appProcesses = @("AcroRd32", "AcroBroker", "AcroTextExtractor", "ADelRCP", "AdobeCollabSync", "arh", "Eula", "FullTrustNotIfier", "LogTransport2", "reader_sl", "wow_helper")
$appTransform = "AcroRead.mst"
$appSetup = "AcroRead.msi"
$appInstallParameters = "/QB"
$appAddParameters = "EULA_ACCEPT=YES DISABLE_CACHE=1 DISABLE_PDFMAKER=YES DISABLEDESKTOPSHORTCUT=0 UPDATE_MODE=0 DISABLE_ARM_SERVICE_INSTALL=1"
$appAddParameters2 = "ALLUSERS=1"
$Nevergreen = Get-NevergreenApp -Name AdobeAcrobatReader| Where-Object { $_.Architecture -eq "x86" -and $_.Language -eq "Multi"}
$appVersion = $Nevergreen.Version
$appURLPatch = $Nevergreen.URI
$appPatch = Split-Path -Path $appURLPatch -Leaf
$appURLMUI = "ftp://ftp.adobe.com/pub/adobe/reader/win/AcrobatDC/1500720033/AcroRdrDC1500720033_MUI.exe"
$appMUI = Split-Path -Path $appURLMUI -Leaf
$appURLFont = "ftp://ftp.adobe.com/pub/adobe/reader/win/AcrobatDC/misc/FontPack1902120058_XtdAlf_Lang_DC.msi"
$appFont = Split-Path -Path $appURLFont -Leaf
$appURLDic = "ftp://ftp.adobe.com/pub/adobe/reader/win/AcrobatDC/misc/AcroRdrSD1900820071_all_DC.msi"
$appDic = Split-Path -Path $appURLDic -Leaf
$appURLADMX = "ftp://ftp.adobe.com/pub/adobe/reader/win/AcrobatDC/misc/ReaderADMTemplate.zip"
$appADMX = Split-Path -Path $appURLADMX -Leaf
$appFTP = Test-FTPConnection -URL "ftp.adobe.com"
$appDestination = "${env:ProgramFiles(x86)}\$appVendor\$appName $appShortVersion\Reader"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName $appShortVersion MUI")
$appInstalledVersion = (Get-InstalledApplication -Name "$appVendor $appName $appShortVersion MUI").DisplayVersion
##*===============================================

If ([version]$appVersion -gt [version]$appInstalledVersion)
{
    Set-Location -Path $appScriptDirectory

    # Download latest setup file(s)
    If (-Not(Test-Path -Path $appScriptDirectory\$appSetup) -and ($appFTP))
    {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion MUI..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLMUI -OutFile $appMUI
        Write-Log -Message "Extracting $appVendor $appName $appShortVersion MSI..." -Severity 1 -LogType CMTrace -WriteHost $True
        New-Folder -Path "$appScriptDirectory\MSI"
        Execute-Process -Path .\$appMUI -Parameters "-sfx_o`"$appScriptDirectory\MSI`" -sfx_ne"
        Copy-File -Path "$appScriptDirectory\MSI\*" -Destination $appScriptDirectory -Recurse
        Remove-Folder -Path "$appScriptDirectory\MSI"
        Remove-File -Path "$appScriptDirectory\$appMUI"
    }
    ElseIf (-not($appFTP))
    {
        Write-Log -Message "FTP URL is unreachable, $appVendor $appName $appShortVersion MUI setup won't be downloaded." -Severity 2 -LogType CMTrace -WriteHost $True
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }


    # Download latest policy definitions

    If ($appFTP)
    {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion ADMX templates..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLADMX -OutFile $appADMX
        New-Folder -Path "$appScriptDirectory\PolicyDefinitions"
        Expand-Archive -Path $appADMX -DestinationPath "$appScriptDirectory\PolicyDefinitions" -Force
        Remove-File -Path $appADMX, $appScriptDirectory\PolicyDefinitions\*.adm
    }
    ElseIf (-not($appFTP))
    {
        Write-Log -Message "FTP URL is unreachable, $appVendor $appName $appShortVersion MUI setup won't be downloaded." -Severity 2 -LogType CMTrace -WriteHost $True
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Uninstall previous versions
    Get-Process -Name $appProcesses | Stop-Process -Force
    If (($IsAppInstalled) -and (Test-Path -Path $appSetup))
    {
        Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
        Remove-MSIApplications -Name "$appVendor $appName $appShortVersion MUI"
    }

    If (-Not(Test-Path -Path $appScriptDirectory\$appDIC) -and ($appFTP))
    {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion Spelling Dictionaries..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLDic -OutFile $appDic
        Write-Log -Message "Installing $appVendor $appName $appShortVersion Spelling Dictionaries..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appDic -Parameters $appInstallParameters -AddParameters $appAddParameters2
    }
    ElseIf (-not($appFTP))
    {
        Write-Log -Message "FTP URL is unreachable, $appVendor $appName $appShortVersion Spelling Dictionaries won't be downloaded. " -Severity 2 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing $appVendor $appName $appShortVersion Spelling Dictionaries..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appDic -Parameters $appInstallParameters -AddParameters $appAddParameters2
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    If (-Not(Test-Path -Path $appScriptDirectory\$appFont) -and ($appFTP))
    {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion Extended Asian Language Font Pack..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLFont -OutFile $appFont
        Write-Log -Message "Installing $appVendor $appName $appShortVersion Extended Asian Language Font Pack..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appFont -Parameters $appInstallParameters -AddParameters $appAddParameters2
    }
    ElseIf (-not($appFTP))
    {
        Write-Log -Message "FTP URL is unreachable, $appVendor $appName $appShortVersion Extended Asian Language Font Pack won't be downloaded. " -Severity 2 -LogType CMTrace -WriteHost $True
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing $appVendor $appName $appShortVersion Extended Asian Language Font Pack..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appFont -Parameters $appInstallParameters -AddParameters $appAddParameters2
    }

    # Download latest patch file
    If (-Not(Test-Path -Path $appScriptDirectory\$appPatch))
    {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion $appVersion patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLPatch -OutFile $appPatch
        If ((Test-Path -Path $appScriptDirectory\$appPatch) -and (Test-Path -Path $appScriptDirectory\$appPatch\setup.ini))
        {
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Startup" -Key "CmdLine" -Value "/sPB /rs /msi $appAddParameters"
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Product" -Key "CmdLine" -Value "TRANSFORMS=`"$appTransform`""
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Product" -Key "PATCH" -Value $appPatch
        }
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }


    If ((Test-Path -Path $appScriptDirectory\$appSetup) -and (Test-Path -Path $appScriptDirectory\$appPatch))
    {
        # Download required transform file
        If (-Not(Test-Path -Path $appScriptDirectory\$appTransform))
        {
            Write-Log -Message "Downloading $appVendor $appName $appShortVersion Transform.." -Severity 1 -LogType CMTrace -WriteHost $True
            Invoke-WebRequest -UseBasicParsing -Uri $appTransformURL -OutFile $appScriptDirectory\$appTransform
        }
        Else
        {
            Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
        }
        # Install latest version
        Write-Log -Message "Installing $appVendor $appName $appShortVersion $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appSetup -Transform $appTransform -Parameters $appInstallParameters -AddParameters $appAddParameters -Patch $appPatch -SkipMSIAlreadyInstalledCheck
    }
    ElseIf (($IsAppInstalled) -and (Test-Path -Path $appScriptDirectory\$appPatch))
    {
        # Install latest patch
        Write-Log -Message "Setup file(s) are missing, MSP file will be installed." -Severity 1 -LogType CMTrace -WriteHost $True
        Write-Log -Message "Installing $appVendor $appName $appShortVersion $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSP -Path $appPatch -Parameters $appInstallParameters
    }
    Else
    {
        Write-Log -Message "Setup file(s) are missing" -Severity 2 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Stop and disable unneeded scheduled tasks
    Get-ScheduledTask -TaskName "$appVendor Acrobat Update Task" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "$appVendor Acrobat Update Task" | Disable-ScheduledTask

    # Fix application Start Menu shorcut
    Copy-File -Path "$envCommonStartMenuPrograms\$appName $appShortVersion.lnk" -Destination "$envCommonStartMenuPrograms\$appVendor $appName $appShortVersion.lnk" -ContinueFileCopyOnError $True
    Remove-File -Path "$envCommonStartMenuPrograms\$appName $appShortVersion.lnk" -ContinueOnError $True

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appVendor $appName $appShortVersion $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else
{
    Write-Log -Message "$appVendor $appName $appShortVersion $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}