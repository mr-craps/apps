# PowerShell Wrapper for MDT, Standalone and Chocolatey Installation - (C)2020 Jonathan Pitre, inspired by xenappblog.com
# Example 1 Install EXE:
# Execute-Process -Path .\appName.exe -Parameters "/silent"
# Example 2 Install MSI:
# Execute-MSI -Action Install -Path appName.msi -Parameters "/QB" -AddParameters "ALLUSERS=1"
# Example 3 Uninstall MSI:
# Remove-MSIApplications -Name "appName" -Parameters "/QB"

#Requires -Version 5.1

# Custom package providers list
$PackageProviders = @("Nuget")

# Custom modules list
$Modules = @("PSADT", "Evergreen")

Set-ExecutionPolicy -ExecutionPolicy Bypass -Force

# Checking for elevated permissions...
If (-not([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning -Message "Insufficient permissions to continue! PowerShell must be run with admin rights."
    Break
}
Else {
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
}

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
$appVendor = "Adobe"
$appName = "Acrobat"
$appShortVersion = "DC"
$appProcesses = @("Acrobat", "AcroBroker", "acrobat_sl", "AcroCEF", "acrodist", "acrotray", "AcroRd32", "Acrobat Elements", "AcroTextExtractor", "ADelRCP", "AdobeCollabSync", "arh", "FullTrustNotIfier", "LogTransport2", "wow_helper", "outlook", "chrome", "iexplore")
$appServices = @("AdobeUpdateService")
$appTransform = "AcroPro.mst"
$appSetup = "AcroPro.msi"
$appInstallParameters = "/QB"
#$appParameters = "--tool=VolumeSerialize --generate --serial=1016-1899-8440-6413-0576-7429 --leid=V7{}AcrobatCont-12-Win-GM --regsuppress=ss --eulasuppress --stream" #--provfile Optional; path of the folder where prov.xml is created. If this parameter is not specified, prov.xml is created in the folder in which APTEE resides.
$appAddParameters = "IGNOREVCRT64=1 EULA_ACCEPT=YES UPDATE_MODE=0 DISABLE_ARM_SERVICE_INSTALL=1 ROAMIDENTITY=1 ROAMLICENSING=1"
$Evergreen = Get-AdobeAcrobat| Where-Object {$_.Track -eq "DC"}
$appVersion = $Evergreen.Version
$appURLPatch = $Evergreen.URI
$appPatch = ($appURLPatch).Split("/")[9]
$appURLADMX = "ftp://ftp.adobe.com/pub/adobe/acrobat/win/AcrobatDC/misc/AcrobatADMTemplate.zip"
$appADMX = ($appURLADMX).Split("/")[9]
$appURLCustWiz = "ftp://ftp.adobe.com/pub/adobe/acrobat/win/AcrobatDC/misc/CustWiz2000920067_en_US_DC.exe"
$appCustWiz = ($appURLCustWiz).Split("/")[9]
$appCustWizVersion = $appCustWiz.Trim("CustWiz").Trim("_en_US_DC.exe")
$appSource = $appVersion
$appDestination = "${env:ProgramFiles(x86)}\$appVendor\$appName $appShortVersion\$appName"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName $appShortVersion")
$appInstalledVersion = (Get-InstalledApplication -Name "$appVendor $appName $appShortVersion").DisplayVersion
##*===============================================

If ([version]$appVersion -gt [version]$appInstalledVersion) {
    Set-Location -Path $appScriptDirectory

    # Uninstall previous versions
    Get-Process -Name $appProcesses | Stop-Process -Force
    If ($IsAppInstalled) {
        Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
        Remove-MSIApplications -Name "$appVendor $appName $appShortVersion"
    }

    # Download latest Adobe Acrobat Customization Wizard DC
    If (-Not(Test-Path -Path $appScriptDirectory\$appCustWiz)) {
        Write-Log -Message "Downloading $appVendor $appName Custimization Wizard $appShortVersion $appCustWizVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLCustWiz -OutFile $appCustWiz
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Download latest policy definitions
    Write-Log -Message "Downloading $appVendor $appName $appShortVersion ADMX templates..." -Severity 1 -LogType CMTrace -WriteHost $True
    Invoke-WebRequest -UseBasicParsing -Uri $appURLADMX -OutFile $appADMX
    New-Folder -Path "$appScriptDirectory\PolicyDefinitions"
    Expand-Archive -Path $appADMX -DestinationPath "$appScriptDirectory\PolicyDefinitions" -Force
    Remove-File -Path $appADMX, $appScriptDirectory\PolicyDefinitions\$appName$($appShortVersion).adm

    # Download latest patch file
    If (-Not(Test-Path -Path $appScriptDirectory\$appPatch)) {
        Write-Log -Message "Downloading $appVendor $appName $appShortVersion $appVersion patch..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURLPatch -OutFile $appPatch
        If (Test-Path -Path $appScriptDirectory\$appPatch) {
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Startup" -Key "CmdLine" -Value "/sPB /rs"
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Product" -Key "CmdLine" -Value "TRANSFORMS=`"$appTransform`""
            Set-IniValue -FilePath $appScriptDirectory\setup.ini -Section "Product" -Key "PATCH" -Value $appPatch
        }
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Install latest version
    If ((Test-Path -Path $appScriptDirectory\$appSetup) -and (Test-Path -Path $appScriptDirectory\$appTransform)) {
        Write-Log -Message "Installing $appVendor $appName $appShortVersion $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-MSI -Action Install -Path $appSetup -Transform $appTransform -Parameters $appInstallParameters -AddParameters $appAddParameters -Patch $appPatch -SkipMSIAlreadyInstalledCheck
    }
    Else {
        Write-Log -Message "Setup file(s) are missing." -Severity 1 -LogType CMTrace -WriteHost $True
        Exit-Script
    }

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Stop and disable unneeded scheduled tasks
    Get-ScheduledTask -TaskName "$appVendor $appName Update Task" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "$appVendor $appName Update Task" | Disable-ScheduledTask

    # Stop and disable unneeded services
    Stop-ServiceAndDependencies -Name $appServices[0]
    Set-ServiceStartMode -Name $appServices[0] -StartMode "Disabled"

    # Remove unneeded applications from running at start-up
    Remove-RegistryKey -Key "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "AdobeAAMUpdater-1.0" -ContinueOnError $True
    #Remove-RegistryKey -Key "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "AdobeGCInvoker-1.0" -ContinueOnError $True

    <# Needed for serial number install only
    Execute-Process -Path ".\adobe_prtk.exe" -Parameters $appParameters #logs located in %temp%\AdobeSerialization.log, and %temp%\oobelib.log
    Execute-Process -Path "$appDestination\Acrobat.exe" -WindowStyle Minimized -NoWait
    Start-Sleep -s 70
    Get-Process -Name $appProcesses | Stop-Process -Force
    #>

    If (-Not(Get-InstalledApplication -Name "Adobe Creative Cloud")) {
        Write-Log -Message "Adobe Creative Cloud must be installed in order for $appVendor $appName $appShortVersion licensing to work!" -Severity 2 -LogType CMTrace -WriteHost $True
    }
    Write-Log -Message "$appVendor $appName $appShortVersion $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True

}
Else {
    Write-Log -Message "$appVendor $appName $appShortVersion $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}

<#
Write-Verbose -Message "Uninstalling custom modules..." -Verbose
Foreach ($Module in $Modules) {
    If ((Get-Module -ListAvailable -Name $Module)) {Uninstall-Module -Name $Module -Force}
}
Write-Verbose -Message "Custom modules were succesfully uninstalled!" -Verbose
#>