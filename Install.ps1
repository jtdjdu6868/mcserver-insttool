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

$highestJavaVersion = $javaVersions[0]
if ($null -eq $highestJavaVersion -or $highestJavaVersion.VersionMajor -lt $targetJavaVersion) {
    $installPrompt = Read-Host -Prompt "Java version is not satisfied (at least $targetJavaVersion). Do you want to install Java? (YES/no)"
    if ($installPrompt -ine "no") {
        Write-Host "Downloading Java..."
        Invoke-WebRequest -Uri "https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.exe" -OutFile "jdk.exe" -ProgressPreference "Continue"
        Write-Host "Installing Java..."
        Start-Process -FilePath "jdk.exe" -ArgumentList "/s" -Wait
        Write-Host "Java installed!"

        # clear jdk.exe
        Remove-Item -Path "jdk.exe"

        # get highest version again
        $javaVersions = getJavaVersions
        $highestJavaVersion = $javaVersions[0]
        $javaInstallLocation = $highestJavaVersion.InstallLocation
    }
    else {
        Write-Host "Java version is not satisfied. Exiting..."
        Pause
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
Invoke-WebRequest -Uri $serverUrl -OutFile "server.jar"
Write-Host "Server jar downloaded!"

# create start script
Write-Host "Creating start script..."
$startbat = @"
set JAVA_HOME=$javaInstallLocation
set PATH=%JAVA_HOME%\bin;%PATH%
java -Xmx1024M -Xms1024M -jar server.jar nogui
"@

$startbat | Out-File -FilePath "start.bat" -Encoding default

# agree to eula
# Run server once to generate eula.txt
Write-Host "Initializing server..."
.\start.bat > $null
$agreeEula = Read-Host -Prompt "Agree to eula? (https://aka.ms/MinecraftEULA) (yes/NO)"
if ($agreeEula -ieq "yes") {
    (Get-Content eula.txt) -replace "eula=false", "eula=true" | Set-Content eula.txt
}
else {
    Write-Host "You need to agree to the EULA in order to run the server. Go to eula.txt for more info."
}

Write-Host "Server installed! Run start.bat to start the server."
Pause