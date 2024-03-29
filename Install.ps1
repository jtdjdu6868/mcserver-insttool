Write-Host "Fetching Minecraft server versions..."

$versionsUrl = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

$versionsRes = Invoke-WebRequest -Uri $versionsUrl

$versionJSON = $versionsRes.Content | ConvertFrom-Json

[System.Array]::Reverse($versionJSON.versions)

# ask for snapshot visibility
$showSnapshotPrompt = Read-Host -Prompt "Do you want to show snapshot versions? (yes/NO)"
if ($showSnapshotPrompt -ieq "yes") {
    # Code to show snapshot versions
    $showSnapshot = $true
} else {
    # Code to not show snapshot versions
    $showSnapshot = $false
}

# choose a version
while ($true) {
    $versionPrompt = Read-Host -Prompt "Which version do you want to install?`n('latest' for the latest release version, 'list' to list the versions, 'quit' to exit script)"
    if ($versionPrompt -ieq "latest") {
        $versionPrompt = $versionJSON.latest.release
    }
    elseif ($versionPrompt -ieq "list") {
        Write-Host "Available versions:"
        foreach ($version in $versionJSON.versions) {
            if ($version.type -eq "release" -or $showSnapshot) {
                Write-Host $version.id
            }
        }
        continue
    }
    elseif ($versionPrompt -ieq "quit") {
        Pause
        exit
    }
    $version = $versionJSON.versions | Where-Object { $_.id -eq $versionPrompt }
    if ($null -ne $version) {
        break
    }
    Write-Host "Invalid version"
}

# download version manifest
$versionManifestUrl = $version.url
$versionManifestRes = Invoke-WebRequest -Uri $versionManifestUrl
$versionManifestJSON = $versionManifestRes.Content | ConvertFrom-Json

# check java version
$targetJavaVersion = $versionManifestJSON.javaVersion.majorVersion
function getJavaVersions {
    $javaVersions = "", "Wow6432Node\" |
    ForEach-Object {Get-ItemProperty -Path HKLM:\SOFTWARE\$($_)Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object {(($_.DisplayName -like "*Java *") -or ($_.DisplayName -like "*Java(TM) *")) -and (-not $_.SystemComponent)}} |
    Sort-Object -Property DisplayVersion
    return $javaVersions
}

$javaVersions = getJavaVersions

if($javaVersions.Count -eq 0) {
    $highestJavaVersion = $null
}
else {
    $highestJavaVersion = $javaVersions[0]
}

if ($null -eq $highestJavaVersion -or $highestJavaVersion.VersionMajor -lt $targetJavaVersion) {
    $installPrompt = Read-Host -Prompt "Required Java version is not satisfied (at least $targetJavaVersion). Do you want to install Java? (YES/no)"
    if ($installPrompt -ine "no") {
        Write-Host "Downloading Java..."
        Start-Process -FilePath "curl" -ArgumentList "-# https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.exe -o jdk.exe" -NoNewWindow -Wait
        Write-Host "Installing Java..."
        Start-Process -FilePath "jdk.exe" -ArgumentList "/s" -Wait
        Write-Host "Java installation completed."

        # clear jdk.exe
        Remove-Item -Path "jdk.exe"

        # get highest version again
        $javaVersions = getJavaVersions
        $highestJavaVersion = $javaVersions[0]
        $javaInstallLocation = $highestJavaVersion.InstallLocation
    }
    else {
        Write-Host "Java version is not satisfied. Exiting..."
        exit
    }
}
else {
    $javaInstallLocation = $highestJavaVersion.InstallLocation
    Write-Host "Required Java $targetJavaVersion is satisfied (Java $($highestJavaVersion.VersionMajor) at $javaInstallLocation)"
}


# download server jar
Write-Host "Downloading server jar..."
$serverUrl = $versionManifestJSON.downloads.server.url
Start-Process -FilePath "curl" -ArgumentList "-# $serverUrl -o server.jar" -NoNewWindow -Wait
Write-Host "Server jar downloaded successfully."

# create start script
$guiPrompt = Read-Host -Prompt "Do you want to run the server with GUI? (yes/NO)"
if ($guiPrompt -ieq "yes") {
    $nogui = ""
}
else {
    $nogui = "nogui"
}
Write-Host "Creating start script..."
$startbat = @"
@echo off
set JAVA_HOME=$javaInstallLocation
set PATH=%JAVA_HOME%\bin;%PATH%
java -Xmx1024M -Xms1024M -jar server.jar $nogui
pause
"@

$startbat | Out-File -FilePath "start.bat" -Encoding default

# agree to eula
# remove eula.txt if exists
if (Test-Path "eula.txt") {
    Remove-Item -Path "eula.txt"
}
# Run server once to generate eula.txt
Write-Host "Initializing server..."
Start-Process -FilePath "cmd" -ArgumentList "/C ""$($javaInstallLocation)bin\java.exe"" -Xmx1024M -Xms1024M -jar server.jar nogui > nul" -NoNewWindow -Wait
$agreeEula = Read-Host -Prompt "Agree to eula? (https://aka.ms/MinecraftEULA) (yes/NO)"
if ($agreeEula -ieq "yes") {
    (Get-Content eula.txt) -replace "eula=false", "eula=true" | Set-Content eula.txt
}
else {
    Write-Host "You need to agree to the EULA in order to run the server. Go to eula.txt for more info."
}

Write-Host "Server installed! Run start.bat to start the server."