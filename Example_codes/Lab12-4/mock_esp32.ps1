# mock_esp32.ps1 - สคริปต์จำลองการทำงานของบอร์ด ESP32 บน PowerShell
param (
    [string]$Broker = "127.0.0.1",
    [int]$Port = 1883
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    [MOCK ESP32] สคริปต์จำลองพฤติกรรมบอร์ด ESP32 ครบวงจร   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ตรวจสอบการเชื่อมต่อกับ Broker ก่อนเริ่มทำงาน
function Test-BrokerConnection {
    param([string]$Server, [int]$TargetPort)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($Server, $TargetPort, $null, $null)
        $success = $connect.AsyncWaitHandle.WaitOne(1000)
        if ($success -and $tcpClient.Connected) {
            $tcpClient.EndConnect($connect)
            $tcpClient.Close()
            return $true
        }
        $tcpClient.Close()
        return $false
    } catch {
        return $false
    }
}

if (-not (Test-BrokerConnection -Server $Broker -TargetPort $Port)) {
    Write-Host "`n[ERROR] ไม่สามารถเชื่อมต่อไปยัง MQTT Broker ที่ ${Broker}:${Port} ได้!" -ForegroundColor Red
    Write-Host "สาเหตุ: ยังไม่ได้สตาร์ต Mosquitto Broker หรือระบุ IP / Port ไม่ถูกต้อง`n" -ForegroundColor Yellow
    Write-Host "วิธีแก้ไข:" -ForegroundColor White
    Write-Host "  1. เปิด PowerShell หน้าต่างใหม่ (ที่รูทโฟลเดอร์ของสัปดาห์ที่ 12)" -ForegroundColor Cyan
    Write-Host "  2. สั่งสตาร์ต Mosquitto Broker ด้วยคำสั่ง:" -ForegroundColor Cyan
    Write-Host "     mosquitto -c mosquitto.conf -v" -ForegroundColor Green
    Write-Host "     (หรือ: mosquitto -v)" -ForegroundColor DarkGray
    Write-Host "  3. จากนั้นจึงสั่งรันสคริปต์นี้ใหม่อีกครั้ง`n" -ForegroundColor Cyan
    exit 1
}

# 1. ส่งสถานะ Online เสมือนบอร์ดบูตเสร็จและเชื่อมต่อสำเร็จ
Write-Host "[1/3] ส่งสถานะ ONLINE ไปยัง iot/esp32/status (Retain)..." -ForegroundColor Green
mosquitto_pub -h $Broker -p $Port -t "iot/esp32/status" -m "online" -r

# 2. เริ่มส่ง Telemetry จำลองเซนเซอร์ใน Background Job
$job = Start-Job -ScriptBlock {
    param($b, $p)
    $t = 0
    while ($true) {
        $v = [Math]::Round(1.65 + 1.5 * [Math]::Sin($t * 0.2), 2)
        $raw = [int](($v / 3.3) * 4095)
        $payload = "{`"voltage`": $v, `"raw`": $raw, `"uptime`": $t}"
        mosquitto_pub -h $b -p $p -t "iot/esp32/telemetry" -m $payload
        $t++
        Start-Sleep -Milliseconds 500
    }
} -ArgumentList $Broker, $Port

Write-Host "[2/3] เริ่มสตรีมข้อมูล Telemetry จำลอง Sine Wave (ทุก 500 ms)..." -ForegroundColor Yellow
Write-Host "[3/3] กำลังดักฟังคำสั่งจากแอป Flutter บนหัวข้อ iot/esp32/control..." -ForegroundColor Magenta
Write-Host "      (แตะสวิตช์บน Flutter เพื่อทดสอบ หรือกด Ctrl+C เพื่อหยุดและส่งสถานะ OFFLINE)" -ForegroundColor Gray
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

try {
    # 3. ดักฟังคำสั่งควบคุม LED แล้วส่ง ACK ตอบกลับทันที
    & mosquitto_sub -h $Broker -p $Port -t "iot/esp32/control" | ForEach-Object {
        $cmd = $_
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ได้รับคำสั่ง: $cmd" -ForegroundColor White
        
        $ledState = $false
        if ($cmd -match '"ON"' -or $cmd -match 'ON') {
            $ledState = $true
            Write-Host "  -> เปิดไฟ LED (GPIO 2 = HIGH) และส่ง ACK ยืนยันสำเร็จ" -ForegroundColor Green
        } else {
            Write-Host "  -> ปิดไฟ LED (GPIO 2 = LOW) และส่ง ACK ยืนยันสำเร็จ" -ForegroundColor Red
        }

        $ackJson = "{`"led_state`": $(if($ledState){'true'}else{'false'}), `"ack`": true}"
        mosquitto_pub -h $Broker -p $Port -t "iot/esp32/led_ack" -m $ackJson
    }
}
finally {
    # เมื่อกด Ctrl+C ให้หยุด Job และส่งสถานะ OFFLINE เสมือนบอร์ดดับ
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    Write-Host "`n[STOP] หยุดการจำลอง: ส่งสถานะ OFFLINE ไปยัง iot/esp32/status..." -ForegroundColor Yellow
    mosquitto_pub -h $Broker -p $Port -t "iot/esp32/status" -m "offline" -r
    Write-Host "จำลองบอร์ดดับ/ตัดการเชื่อมต่อเรียบร้อยแล้ว!" -ForegroundColor Red
}
