# PowerShell Wrapper for MDT, Standalone and Chocolatey Installation - (C)2020 Jonathan Pitre, inspired by xenappblog.com
# Example 1 Install EXE:
# Execute-Process -Path .\appName.exe -Parameters "/silent"
# Example 2 Install MSI:
# Execute-MSI -Action Install -Path appName.msi -Parameters "/QB" -AddParameters "ALLUSERS=1"
# Example 3 Uninstall MSI:
# Remove-MSIApplications -Name "appName" -Parameters "/QB"
# Custom package providers list
$PackageProviders = @("PowerShellGet","Nuget")
# Custom modules list
$Modules = @("PSADT","Evergreen")

# Checking for elevated permissions...
If (-not([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Warning -Message "Insufficient permissions to continue! PowerShell must be run with admin rights."
	Break
}
Else {
	Write-Verbose -Message "Importing custom modules..." -Verbose

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [System.Net.WebRequest]::DefaultWebProxy.Credentials =  [System.Net.CredentialCache]::DefaultCredentials
	Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

	# Install custom package providers list
	Foreach ($PackageProvider in $PackageProviders) {
		If (-not(Get-PackageProvider -Name $PackageProvider)) {Find-PackageProvider -Name $PackageProvider -ForceBootstrap -IncludeDependencies | Install-PackageProvider -Force -Confirm:$False}
    }

	# Install and import custom modules list
	Foreach ($Module in $Modules) {
		If (-not(Get-Module -ListAvailable -Name $Module)) {Install-Module -Name $Module -AllowClobber -Force | Import-Module -Name $Module}
        Else {Update-Module -Name $Module -Force}
    }
	Write-Verbose -Message "Custom modules were successfully imported!" -Verbose
}

Function Get-ScriptDirectory {
    If ($psISE) {Split-Path $psISE.CurrentFile.FullPath}
    Else {$Global:PSScriptRoot}
}

# Variables Declaration
# Generic
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
$appScriptDirectory = Get-ScriptDirectory
$env:SEE_MASK_NOZONECHECKS = 1
# Application related
##*===============================================
Function Get-IrfanView {
    <#
        .NOTES
            Author: Trond Eirik Haavarstein
            Twitter: @xenappblog
    #>
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    Param()
        $url = "https://www.irfanview.com/"
    try {
        $web = Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction SilentlyContinue
    }
    catch {
        Throw "Failed to connect to URL: $url with error $_."
        Break
    }
    finally {
        $m = $web.ToString() -split "[`r`n]" | Select-String "Version" | Select-Object -First 1
        $m = $m -replace "<((?!@).)*?>"
        $m = $m.Replace(' ','')
        $Version = $m -replace "Version"
        $File = $Version -replace "\.",""
        $x32 = "http://download.betanews.com/download/967963863-1/iview$($File)_setup.exe"
        $x32plugin = "http://download.betanews.com/download/1099412658-1/iview$($File)_plugins_setup.exe"
        $x64 = "http://download.betanews.com/download/967963863-1/iview$($File)_x64_setup.exe"
        $x64plugin = "http://download.betanews.com/download/1099412658-1/iview$($File)_plugins_x64_setup.exe"
        $lang = "https://www.irfanview.net/lang/irfanview_lang_french.exe"

        $PSObjectx32 = [PSCustomObject] @{
        Version      = $Version
        Architecture = "x86"
        Language     = "neutral"
        URI          = $x32
        }

        $PSObjectx64 = [PSCustomObject] @{
        Version      = $Version
        Architecture = "x64"
        Language     = "neutral"
        URI          = $x64
        }

        $PSObjectx32plugin = [PSCustomObject] @{
        Version            = $Version
        Architecture       = "x86 Plugin"
        Language           = "neutral"
        URI                = $x32plugin
        }

        $PSObjectx64plugin = [PSCustomObject] @{
        Version            = $Version
        Architecture       = "x64 Plugin"
        Language           = "neutral"
        URI                = $x64plugin
        }

        $PSObjectLang = [PSCustomObject] @{
        Version            = $Version
        Architecture       = "any"
        Language           = "french"
        URI                = $lang
        }

        Write-Output -InputObject $PSObjectx32
        Write-Output -InputObject $PSObjectx64
        Write-Output -InputObject $PSObjectx32plugin
        Write-Output -InputObject $PSObjectx64plugin
        Write-Output -InputObject $PSObjectLang

    }
 }

$appName = "IrfanView"
$appProcess = @("i_view64")
$appInstallParameters = "/assoc=1 /group=1 /ini=%APPDATA%\IrfanView /silent"
$Evergreen = Get-IrfanView | Where-Object {$_.Architecture -eq "x64"}
$appVersion = $Evergreen.Version
$appURLSetup = $Evergreen.uri
$appSetup = $appURLSetup.Split("/")[5]
$Evergreen = Get-IrfanView | Where-Object {$_.Architecture -eq "x64 Plugin"}
$appURLSetupPlugin = $Evergreen.uri
$appSetupPlugin = $appURLSetupPlugin.Split("/")[5]
$Evergreen = Get-IrfanView | Where-Object {$_.Language -eq "french"}
$appURLSetupLang = $Evergreen.uri
$appSetupLang = $appURLSetupLang.Split("/")[4]
$appSource = $appVersion
$appDestination = "$envProgramFiles\IrfanView"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appName")
$appInstalledVersion = (Get-InstalledApplication -Name "$appName").DisplayVersion
##*===============================================

If ([version]$appVersion -gt [version]$appInstalledVersion) {
    Set-Location -Path $appScriptDirectory
    If (-Not(Test-Path -Path $appSource)) {New-Folder -Path $appSource}
    Set-Location -Path $appSource

    Write-Log -Message "Downloading $appName $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
    If (-Not(Test-Path -Path $appScriptDirectory\$appSource\$appSetup)) {
        Invoke-WebRequest -UseBasicParsing -Uri $appURLSetup -OutFile $appSetup
        Invoke-WebRequest -UseBasicParsing -Uri $appURLSetupPlugin -OutFile $appSetupPlugin
        Invoke-WebRequest -UseBasicParsing -Uri $appURLSetupLang -OutFile $appSetupLang
    }
    Else {
        Write-Log -Message "File already exists. Skipping Download" -Severity 1 -LogType CMTrace -WriteHost $True
    }

    Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    Get-Process -Name $appProcess | Stop-Process -Force

    Write-Log -Message "Installing $appName $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path .\$appSetup -Parameters $appInstallParameters
    Execute-Process -Path .\$appSetupPlugin -Parameters "/silent"
    Execute-Process -Path .\$appSetupLang -NoWait -PassThru
    Start-Sleep -Seconds 3
    Send-Keys -WindowTitle 'IrfanView Language Installer' -Keys "{ENTER}" -WaitSeconds 2
    Send-Keys -WindowTitle 'IrfanView Language Installer' -Keys "{ENTER}"

	Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True
    Remove-Folder -Path $envUserStartMenuPrograms\$appName
    New-Shortcut -Path $envCommonStartMenuPrograms\$appName.lnk -TargetPath $appDestination\$appProcess.exe -IconLocation $appDestination\$appProcess.exe -Description $appName -WorkingDirectory $appDestination
    Write-Log -Message "$appName $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True

}
Else {
    Write-Log -Message "$appName $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}

<#
Write-Verbose -Message "Uninstalling custom modules..." -Verbose
Foreach ($Module in $Modules) {
    If ((Get-Module -ListAvailable -Name $Module)) {Uninstall-Module -Name $Module -Force}
}
Write-Verbose -Message "Custom modules were succesfully uninstalled!" -Verbose
#>