<#
.SYNOPSIS
    Nexus Sandbox dev-env launcher for Docker Desktop.
    Tunnels ADB + Dart VM service, supports Emulator, Physical target, or Skip.

.PARAMETER Mode
    "Emulator", "Physical", or "Skip".
#>
param(
    [ValidateSet("Emulator", "Physical", "Skip")]
    [string]$Mode
)

$ContainerName = "Nexus_Sandbox"
$User          = "vscode"
$VmServicePort = 8181

# Ensure WSL SSH agent socket is initialized before Docker mounts it
Write-Host "🔑 Initializing WSL SSH Relay..." -ForegroundColor Cyan
wsl --exec bash -c 'source ~/.bashrc'

Write-Host "🔧 Verifying Docker Desktop..." -ForegroundColor Cyan
if (!(docker info 2>$null)) {
    Write-Host "❌ Docker Desktop is not running." -ForegroundColor Red
    exit 1
}

$Status = (docker inspect -f '{{.State.Status}}' $ContainerName 2>$null).Trim()
if ($Status -ne "running") {
    Write-Host "🚀 Starting container..." -ForegroundColor Cyan
    wsl --exec bash -ic "docker start $ContainerName" > $null
    Start-Sleep -Seconds 2
}

if (-not $Mode) {
    Write-Host "`n🤖 Select Debug Target Environment:" -ForegroundColor Magenta
    Write-Host " [1] Emulator" -ForegroundColor Cyan
    Write-Host " [2] Physical Device (Wi-Fi ADB)" -ForegroundColor Cyan
    Write-Host " [3] Skip ADB (Container Only)" -ForegroundColor Cyan
    $Choice = Read-Host "Enter selection (1, 2, or 3)"
    
    if ($Choice -eq "3") { $Mode = "Skip" }
    elseif ($Choice -eq "2") { $Mode = "Physical" }
    else { $Mode = "Emulator" }
}

if ($Mode -ne "Skip") {
    docker exec -u root $ContainerName bash -c "adb kill-server"

    if ($Mode -eq "Physical") {
        adb start-server | Out-Null
        adb tcpip 5555 | Out-Null
        Start-Sleep -Seconds 2

        $DeviceIp = (adb shell ip route 2>$null) -match "src\s+(\d+\.\d+\.\d+\.\d+)" | % { $Matches[1] }
        
        if (-not $DeviceIp) {
            Write-Host "❌ Could not determine device's Wi-Fi IP." -ForegroundColor Red
            exit 1
        }

        Write-Host "📱 Connecting container directly to Device IP: $DeviceIp" -ForegroundColor Green
        docker exec -u $User $ContainerName adb connect "${DeviceIp}:5555" | Out-Null
        
    } else {
        Write-Host "📱 Launching Local Emulator..."
        $EmulatorProc = Start-Process emulator -ArgumentList "-avd Pixel_10_Pro_XL -netdelay none -netspeed full" -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 15

        Write-Host "🛡️ Bridging Windows Emulator to Docker Network..." -ForegroundColor Cyan
        $RelayCmd = "netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=5555 connectaddress=127.0.0.1 connectport=5555"
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"$RelayCmd`"" -Verb RunAs -Wait

        Write-Host "🔌 Connecting container to host emulator..."
        docker exec -u $User $ContainerName adb connect host.docker.internal:5555 | Out-Null
    }

    $retryCount = 0
    while ($retryCount -lt 15) {
        # If checking a physical device, match the exact IP. If emulator, match host.docker.internal.
        $Target = if ($Mode -eq "Physical") { "${DeviceIp}:5555" } else { "host.docker.internal:5555" }
        
        if ((docker exec -u $User $ContainerName adb -s $Target get-state 2>$null) -eq "device") {
            Write-Host "✅ ADB Connected & Authorized!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
        $retryCount++
    }
} else {
    Write-Host "⏭️ Skipping ADB configuration." -ForegroundColor Cyan
}

Write-Host "`n🎯 All systems go!" -ForegroundColor Magenta
Write-Host "💡 App Port 8000 and Dart VM Port 8181 are natively exposed via Docker."
Write-Host "   flutter run --host-vmservice-port=$VmServicePort" -ForegroundColor Cyan
Read-Host "🛑 PRESS ENTER TO TEARDOWN ENVIRONMENT 🛑"

Write-Host "🗑️ Tearing down..." -ForegroundColor Cyan

if ($Mode -eq "Emulator") {
    Write-Host "🛑 Terminating emulator..." -ForegroundColor Cyan
    # Send graceful shutdown signal to the emulator before killing the ADB server
    adb -e emu kill 2>$null
    Start-Sleep -Seconds 5

    if ($EmulatorProc) { Stop-Process -Id $EmulatorProc.Id -Force -ErrorAction SilentlyContinue }
    $RelayCleanupCmd = "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=5555"
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"$RelayCleanupCmd`"" -Verb RunAs
} elseif ($Mode -eq "Physical") {
    adb usb 2>$null | Out-Null
}

if ($Mode -ne "Skip") {
    adb kill-server 2>$null
    docker exec -u $User $ContainerName adb kill-server 2>$null
}

Write-Host "✅ Environment sanitized. gg." -ForegroundColor Green

# SIG # Begin signature block
# MIIFfQYJKoZIhvcNAQcCoIIFbjCCBWoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAy5AQBWxJv76/0
# hV1kkDwiiSdXv68i8iwXTXkNHWIRcKCCAvowggL2MIIB3qADAgECAhAmKGzz2Y/i
# k00s+ReTOHmTMA0GCSqGSIb3DQEBCwUAMBMxETAPBgNVBAMMCGRldmFrZXN1MB4X
# DTI2MDYwNzEzNTA0MloXDTI3MDYwNzE0MTA0MlowEzERMA8GA1UEAwwIZGV2YWtl
# c3UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDEoLmTS8czHXtaQFpw
# 6w6gmTU9ciThCmc2H78V47zO+J+3NrdSHRx5jqT/liWIQ8konlM+DiozDx4TXz8U
# LBbI1UJTR7lbTUJayzy7d59NzVD9YKLBvfw/KAleMFaAIPbM1xMfZnHreppsnMMj
# rh/N1XmO7/0sLa2F9vV4xGhM17b24U/bnozmP3Gtm+kxO5j4XCr1vX3H9JDcBAPl
# Cuu3YQASdN/iOtLZ4Qu25R8onqzYF4vv4pFtaQSpD2b/WX/KJ2kKKAsK2bdBgQlF
# ETXhRN40OoT3oULKS+rEGnisvJ6wVdC5kScXYy0M+OE9tdU+DO+B3w3ui+6ztAYp
# YKXdAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUhlC/oAYJSIGNOeB4Lq85vZb8y5AwDQYJKoZIhvcNAQELBQAD
# ggEBAC8BtGR3ct33qhR0mW1K8NnVa1YRYiQ3Jl9hh7z7Z+NZ3X2VFzECuAx4wlki
# SjVIGxmWiMt51kxDPo8G9If1b6lvH7ukbVOlw/30AvyL0SDj1v9E9rAKzTaDhN9k
# wgTUZ+nxbCsX1uRrV6Nik3d/juOKpXvWAhWHmDn/qIaYqmmLoABsgrWyhZxUzTSV
# 6xCoxlJcCUIB5jicAUqmq4JAyID2ARYCi8FjdxX3+i0PoV/403+WTZgMVbwZFJBf
# G8oP+3TfnrI3X24woPZnyV+OeuLibsSFXq8qmrARY8lWrmT+m3Vl86ibtjj8ppFm
# 05EwtDcUqVGObcNhvsYrTipXJR0xggHZMIIB1QIBATAnMBMxETAPBgNVBAMMCGRl
# dmFrZXN1AhAmKGzz2Y/ik00s+ReTOHmTMA0GCWCGSAFlAwQCAQUAoIGEMBgGCisG
# AQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIF0f
# LbWwVdXFPFbmkCg9krK3+sII2m5+zU658JQBojeBMA0GCSqGSIb3DQEBAQUABIIB
# ADN+v2Yx28YAOJkUYf3DGI72usPLmzlxN4rbqsjySdooR8tPqP+uzy5pK4yCKtpX
# 7Ewxg/UKMPZRAc6eLC25Ar9qTjbtQkqxIRIptQu+2ky7AhOm2T6P0HMoSc5NlpX4
# bPoxZEG20QYmv1sw/TmDpRWckRcw7A/Cla2LTJTIh2VydnO3cy9tVW9RZ7faInWO
# lX73TGTcqJAK2GBjKVE68hhcsj4nKLJKAaNZTuM84YyIPTq/VBpzlT91kgTd3xPS
# qCiltsXpwB43u9I1C4E87MsRuiGDYysTzUIUiZPd59g433IFMuMncuIRIh2xpp3T
# cZV1/ba1+cgevtSFacP+tXk=
# SIG # End signature block
