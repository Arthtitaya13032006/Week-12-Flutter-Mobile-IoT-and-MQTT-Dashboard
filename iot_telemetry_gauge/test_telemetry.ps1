1..30 | ForEach-Object {
    $v = [Math]::Round(1.65 + 1.5 * [Math]::Sin($_ * 0.4), 2)
    $raw = [int](($v / 3.3) * 4095)
    $json = "{\`"voltage\`": $v, \`"raw\`": $raw, \`"uptime\`": $_}"
    mosquitto_pub -h 127.0.0.1 -p 1883 -t "iot/esp32/telemetry" -m $json
    Start-Sleep -Milliseconds 400
}
