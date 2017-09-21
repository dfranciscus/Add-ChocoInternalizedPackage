function Add-ChocoInternalizedPackage {
<#
.SYNOPSIS
Recompiles new Chocolatey packages to internal feed when new packages are released. This should be used on a test machine that has all of the packages that you want to recompile from the Chocolatey public feed.

.PARAMETER RepositoryURL
Your internal NuGet repository URL for pushing packages to. For Example https://yourfeed/chocolatey/

.PARAMETER WorkingDirectory
The directory you will be downloading and recompile packages to.

.PARAMETER APIKeyPath
Your API key for your internal NuGet feed

.PARAMETER PurgeWorkingDirectory
Use if you want to remove all contents currently in the $WorkDirectory path. Otherwse, choco download will fail if package exists.

.EXAMPLE
Add-ChocoInternalizedPackage -RepositoryURL 'https://yourfeed/chocolatey/' -WorkingDirectory 'C:\Example\' -PurgeWorkingDirectory -ApiKeyPath 'c:\ChocoKey\choco.txt'

Description
-----------  
This will remote the contents of c:\Example, get a list of outdated Chocolatey packages on the local machine, recompile them and then push to 'https://yourfeed/chocolatey/'.

#>
    param (
        [Parameter(Mandatory=$true)]
        [string]$RepositoryURL,
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -Path $_})]
        [string]$WorkingDirectory,
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -Path $_})]
        [string]$APIKeyPath,
        [Parameter(Mandatory=$false)]
        [switch]$PurgeWorkingDirectory
    )

    #Convert API Key Path for use in choco push
    $PushAPIKey = Get-Content $APIKeyPath | ConvertTo-SecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PushAPIKey )
    $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
      
    #Removes content of working directory which may include previously recompiled package data
    if ($PurgeWorkingDirectory)
    {
        Get-ChildItem -Path $WorkingDirectory -Recurse | Remove-Item -Recurse -Force
    }
    #Get outdated packages 
    Write-Output "Getting local outdated packages"
    $OutdatedPackages = (choco outdated -r --ignore-pinned)
    #If no updated packages are available then exit
    if (!$OutdatedPackages)
    {
        Write-Warning -Message 'No new packages available. Exiting'
        Exit
    }
    else
    {
        $NewPackages = foreach ($NewPackage in $OutdatedPackages) 
        {
            [PSCustomObject]@{
                Name = $NewPackage.Split('|')[0]
                CurrentVersion = $NewPackage.Split('|')[1]
                NewVersion = $NewPackage.Split('|')[2]
                Pinned = $NewPackage.Split('|')[3]
            }
        } 
        #If new packages are available then install, internalize, and push to local repository
        Set-Location -Path $WorkingDirectory
        [System.Collections.ArrayList]$Failure = @()
        [System.Collections.ArrayList]$Success = @()
        #Install new packages locally
        foreach ($InstallPackage in $NewPackages)
        {
            #Skip *.install packages due to redundancy in virtual package
            if ($InstallPackage.Name -like "*.install")
            {
                Write-Warning ($InstallPackage.Name + ' skipping')
                Continue
            }
            #Get time to use with choco push
            $DownloadTime = Get-Date
            Write-Output ("Downloading " + $InstallPackage.Name)
            choco download $InstallPackage.Name --internalize --no-progress --internalize-all-urls
            if ($LASTEXITCODE -ne 0)
            {
                Write-Warning ($InstallPackage.Name + ' internalize failed')
                $Failure.Add($InstallPackage.Name) | Out-Null
                Continue
            }
            Write-Output ("Upgrading " + $InstallPackage.Name)
            choco upgrade $InstallPackage.Name --source=$WorkingDirectory --no-progress -y
            #If failure detected in output continue to next package
            if ($LASTEXITCODE -ne 0)
            {
                Write-Warning ($InstallPackage.Name + ' install failed')
                $Failure.Add($InstallPackage.Name) | Out-Null
                Continue
            }
            #If no failure detected than push to hosted repository
            else 
            {
                #Get package and all dependency package paths for push
                $DownloadedPackages = Get-ChildItem -Path $WorkingDirectory | Where-Object {$_.Extension -eq '.nupkg' -AND $_.LastWriteTime -gt $DownloadTime} | Select-Object -ExpandProperty FullName
                foreach ($DownloadedPackage in $DownloadedPackages) 
                {
                    Write-Output ("Pushing " + $DownloadedPackage)
                    choco push $DownloadedPackage --source=$RepositoryURL -k=$ApiKey
                    if ($LASTEXITCODE -ne 0)
                    {
                        Write-Warning -Message "$DownloadedPackage failed push"
                        $Failure.Add($DownloadedPackage) | Out-Null
                    }
                    else 
                    {
                       Write-Output "$DownloadedPackage successfully pushed"
                       $Success.Add($DownloadedPackage) | Out-Null
                    }
                }
            }
        }
        #Write successes and failures to console and/or email
        Write-Output "Successful packages:"
        $Success
        Write-Output "Failed packages:"
        $Failure

    }
}
