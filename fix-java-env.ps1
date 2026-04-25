#Requires -RunAsAdministrator
# Fix JAVA_HOME to point to JDK 21 for Android/Gradle compatibility
# Run this script as Administrator

$jdkPath = "C:\jdk-21"

if (-not (Test-Path "$jdkPath\bin\java.exe")) {
    Write-Error "JDK 21 not found at $jdkPath"
    exit 1
}

# Set system-level JAVA_HOME
[System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkPath, [System.EnvironmentVariableTarget]::Machine)
Write-Host "Set system JAVA_HOME = $jdkPath" -ForegroundColor Green

# Also ensure jdk-21\bin is on PATH (remove jdk-26\bin if present)
$sysPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
$pathParts = $sysPath -split ";" | Where-Object { $_ -ne "" }

# Remove any old JDK bin entries (jdk-26, jdk-21 duplicates)
$pathParts = $pathParts | Where-Object { $_ -notmatch "\\jdk-\d+\\bin" }

# Add jdk-21\bin
$pathParts = @("$jdkPath\bin") + $pathParts
$newPath = $pathParts -join ";"
[System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
Write-Host "Updated system PATH: added $jdkPath\bin, removed old JDK entries" -ForegroundColor Green

Write-Host ""
Write-Host "Done! Close and reopen all terminals/IDE windows for changes to take effect." -ForegroundColor Cyan
