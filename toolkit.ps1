param(
    [string]$Token = $null
)

# ===== EMBEDDED WEB ASSETS (injected at compile time) =====
$EMBEDDED_HTML = "__INJECT_HTML__"
$EMBEDDED_CSS  = "__INJECT_CSS__"
$EMBEDDED_JS   = "__INJECT_JS__"

# Start transcript logging to diagnose silent crashes
try {
    Start-Transcript -Path "$env:TEMP\WinToolKit_server.log" -Force -Append | Out-Null
} catch {}
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WinToolKit Backend iniciando... Token=$($Token -ne $null)" -ForegroundColor Cyan

# 1. Administrator Check & Self-Elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevando permissões para Administrador..." -ForegroundColor Yellow
    try {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($Token) {
            $argList += " -Token `"$Token`""
        }
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Host "ERRO: O toolkit necessita de direitos administrativos para executar limpezas, reparos e escaneamentos." -ForegroundColor Red
        Read-Host "Pressione Enter para fechar..."
    }
    exit
}

# Clear active job tables
$global:ActiveJobs = @{}

# 2. Server Configuration
$port = 4040
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

# Check if port is available
try {
    $listener.Start()
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "   WinToolKit Backend iniciado com sucesso na porta $port" -ForegroundColor Green
    Write-Host "   Acesse: http://localhost:$port/ no seu navegador" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
} catch {
    Write-Host "ERRO: A porta $port já está em uso por outra aplicação." -ForegroundColor Red
    Write-Host "Tentando encontrar uma porta alternativa..." -ForegroundColor Yellow
    
    # Simple rollover to find a free port
    for ($i = 4041; $i -le 4050; $i++) {
        try {
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add("http://localhost:$i/")
            $listener.Start()
            $port = $i
            Write-Host "WinToolKit alocado com sucesso na porta alternativa: $port" -ForegroundColor Green
            break
        } catch {
            continue
        }
    }
}

if (-not $listener.IsListening) {
    Write-Host "FALHA CRITICA: Nao foi possivel alocar nenhuma porta local (4040-4050)." -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# Auto-launch default browser pointing to the dashboard if no token is enforced
if (-not $Token) {
    try {
        Start-Process "http://localhost:$port/"
    } catch {
        Write-Host "Não foi possível abrir o navegador padrão automaticamente. Acesse http://localhost:$port/ manualmente." -ForegroundColor Yellow
    }
}

# 3. Response Helpers
function Send-JsonResponse($context, $obj) {
    $json = ConvertTo-Json $obj -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    
    $context.Response.ContentType = "application/json; charset=utf-8"
    $context.Response.ContentLength64 = $bytes.Length
    
    $context.Response.Headers.Add("X-Content-Type-Options", "nosniff")
    $context.Response.Headers.Add("X-Frame-Options", "DENY")
    $context.Response.Headers.Add("Content-Security-Policy", "default-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.gstatic.com https://cdnjs.cloudflare.com")
    
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.Close()
}

function Send-HtmlResponse($context, $filePath, $mimeType) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $context.Response.ContentType = $mimeType
        $context.Response.ContentLength64 = $bytes.Length
        
        $context.Response.Headers.Add("X-Content-Type-Options", "nosniff")
        $context.Response.Headers.Add("X-Frame-Options", "DENY")
        $context.Response.Headers.Add("Content-Security-Policy", "default-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.gstatic.com https://cdnjs.cloudflare.com")
        
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        $context.Response.StatusCode = 500
    }
    $context.Response.Close()
}

function Send-EmbeddedResponse($context, $base64Content, $mimeType) {
    try {
        $bytes = [System.Convert]::FromBase64String($base64Content)
        $context.Response.ContentType = $mimeType
        $context.Response.ContentLength64 = $bytes.Length
        
        $context.Response.Headers.Add("X-Content-Type-Options", "nosniff")
        $context.Response.Headers.Add("X-Frame-Options", "DENY")
        $context.Response.Headers.Add("Content-Security-Policy", "default-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.gstatic.com https://cdnjs.cloudflare.com")
        
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        $context.Response.StatusCode = 500
    }
    $context.Response.Close()
}

$isEmbedded = ($EMBEDDED_HTML -ne "__INJECT_HTML__")

# 4. Main Request Listener Loop
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $url = $request.RawUrl
        $method = $request.HttpMethod
        
        # --- Security Token Check ---
        if ($Token) {
            $requestToken = $request.QueryString["token"]
            $cookieToken = $null
            if ($request.Cookies) {
                $cookie = $request.Cookies["session_token"]
                if ($cookie) {
                    $cookieToken = $cookie.Value
                }
            }
            
            if ($requestToken -ne $Token -and $cookieToken -ne $Token) {
                $context.Response.StatusCode = 403
                $context.Response.ContentType = "text/html; charset=utf-8"
                $html = "<html><head><script>window.close();</script></head><body style='background:#0b0f19;color:#ef4444;font-family:sans-serif;padding:20px;'>Acesso nao autorizado (403 Forbidden).<br><br><small>Esta janela expirou e deve ser fechada automaticamente.</small></body></html>"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
                continue
            }
            
            # Set Session Cookie if the request authenticated via Query String
            if ($requestToken -eq $Token) {
                $context.Response.Headers.Add("Set-Cookie", "session_token=$Token; Path=/; HttpOnly; SameSite=Strict")
            }
        }
        # -----------------------------
        
        # Check API routes
        if ($url.StartsWith("/api/diagnostics") -and $method -eq "GET") {
            # Real-Time Diagnostic data
            
            # Hostname & User
            $hostname = $env:COMPUTERNAME
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            
            # OS details
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $osName = $os.Caption
            $osVersion = "$($os.Version) (Build $($os.BuildNumber))"
            
            # Safe date parse
            $installDate = "N/A"
            if ($os.InstallDate) {
                $installDate = $os.InstallDate.ToString("dd/MM/yyyy HH:mm")
            }
            
            # Uptime calculation
            $uptime = "N/A"
            if ($os.LastBootUpTime) {
                $uptimeTimespan = (Get-Date) - $os.LastBootUpTime
                $uptime = "$($uptimeTimespan.Days)d $($uptimeTimespan.Hours)h $($uptimeTimespan.Minutes)m"
            }
            
            # CPU Specs & load
            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            $cpuModel = $cpu.Name.Trim()
            $cpuPercent = $cpu.LoadPercentage
            if ($null -eq $cpuPercent) { $cpuPercent = 0 }
            
            # GPU Specs
            $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
            $gpuModel = if ($null -ne $gpu) { $gpu.Name } else { "N/A" }
            
            # RAM specs
            $ramTotalBytes = $os.TotalVisibleMemorySize * 1KB
            $ramFreeBytes = $os.FreePhysicalMemory * 1KB
            $ramUsedBytes = $ramTotalBytes - $ramFreeBytes
            $ramPercent = ($ramUsedBytes / $ramTotalBytes) * 100
            
            # Storage (C:)
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            $diskTotalBytes = $disk.Size
            $diskFreeBytes = $disk.FreeSpace
            $diskUsedBytes = $diskTotalBytes - $diskFreeBytes
            $diskPercent = ($diskUsedBytes / $diskTotalBytes) * 100
            
            # Net IP
            $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi", "Ethernet" -ErrorAction SilentlyContinue | 
                  Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*" } | 
                  Select-Object -First 1
            if ($null -eq $ip) {
                $ip = Get-NetIPAddress -InterfaceFilterIsPresent -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                      Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | 
                      Select-Object -First 1
            }
            $ipAddress = if ($null -ne $ip) { $ip.IPAddress } else { "Desconectado" }
            
            # Ping Google DNS
            $pingLatency = -1
            try {
                $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction SilentlyContinue
                if ($ping) {
                    $pingLatency = $ping.ResponseTime
                }
            } catch {}
            
            $diagResponse = @{
                hostname = $hostname
                currentUser = $currentUser
                osName = $osName
                osVersion = $osVersion
                installDate = $installDate
                uptime = $uptime
                cpuModel = $cpuModel
                cpuPercent = $cpuPercent
                ramPercent = $ramPercent
                ramTotalGb = [Math]::Round($ramTotalBytes / 1GB, 1)
                ramUsedGb = [Math]::Round($ramUsedBytes / 1GB, 1)
                ramFreeGb = [Math]::Round($ramFreeBytes / 1GB, 1)
                diskPercent = $diskPercent
                diskTotalGb = [Math]::Round($diskTotalBytes / 1GB, 0)
                diskUsedGb = [Math]::Round($diskUsedBytes / 1GB, 0)
                diskFreeGb = [Math]::Round($diskFreeBytes / 1GB, 0)
                ipAddress = $ipAddress
                pingLatency = $pingLatency
                gpuModel = $gpuModel
            }
            
            Send-JsonResponse $context $diagResponse
            
        } elseif ($url.StartsWith("/api/services") -and $method -eq "GET") {
            # List of core services
            $serviceNames = @("Spooler", "wuauserv", "CryptSvc", "Dhcp", "Winmgmt", "BITS", "SysMain", "TermService", "EventLog")
            $servicesList = Get-Service -Name $serviceNames -ErrorAction SilentlyContinue | ForEach-Object {
                @{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    Status = $_.Status.ToString()
                }
            }
            
            Send-JsonResponse $context $servicesList
            
        } elseif ($url.StartsWith("/api/settings") -and $method -eq "GET") {
            # Settings state
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            $regValue = "WinToolKit"
            $autostart = $false
            if ((Get-ItemProperty -Path $regPath -Name $regValue -ErrorAction SilentlyContinue) -ne $null) {
                $autostart = $true
            }
            Send-JsonResponse $context @{ autostart = $autostart }
            
        } elseif ($url.StartsWith("/api/service-control") -and $method -eq "POST") {
            # Start/Stop/Restart services
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            
            $params = $body | ConvertFrom-Json
            $serviceName = $params.service
            $action = $params.action
            
            $success = $false
            $message = ""
            
            try {
                if ($action -eq "start") {
                    Start-Service -Name $serviceName -Force -ErrorAction Stop
                    $message = "Serviço '$serviceName' iniciado com sucesso."
                    $success = $true
                } elseif ($action -eq "stop") {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $message = "Serviço '$serviceName' interrompido com sucesso."
                    $success = $true
                } elseif ($action -eq "restart") {
                    Restart-Service -Name $serviceName -Force -ErrorAction Stop
                    $message = "Serviço '$serviceName' reiniciado com sucesso."
                    $success = $true
                } else {
                    $message = "Ação de serviço inválida."
                }
            } catch {
                $message = "Erro ao controlar serviço: $_"
            }
            
            Send-JsonResponse $context @{ success = $success; message = $message }
            
        } elseif ($url.StartsWith("/api/check-update") -and $method -eq "GET") {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $timestamp = [Math]::Floor([decimal](Get-Date (Get-Date).ToUniversalTime() -UFormat "%s") * 1000)
                $updateUrl = "https://raw.githubusercontent.com/gestaoinformacaodhs-ship-it/WinToolKit/main/version.json?t=$timestamp"
                $response = Invoke-WebRequest -Uri $updateUrl -UseBasicParsing -ErrorAction Stop
                $jsonStr = $response.Content.Trim([char]0xFEFF).Trim('?')
                
                # Send raw string out as json object (or parse and re-send to ensure validation)
                $jsonObj = $jsonStr | ConvertFrom-Json
                Send-JsonResponse $context $jsonObj
            } catch {
                Send-JsonResponse $context @{ error = $true; message = $_.Exception.Message }
            }
            
        } elseif ($url.StartsWith("/api/action") -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            
            $params = $body | ConvertFrom-Json
            $action = $params.action
            
            # Handle synchronous actions like toggle_autostart
            if ($action -eq "toggle_autostart") {
                $enabled = $params.enabled
                $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
                $regValue = "WinToolKit"
                $exePath = Join-Path $PSScriptRoot "WinToolKit.exe"
                
                try {
                    if ($enabled) {
                        Set-ItemProperty -Path $regPath -Name $regValue -Value "`"$exePath`" -silent"
                    } else {
                        Remove-ItemProperty -Path $regPath -Name $regValue -ErrorAction SilentlyContinue
                    }
                    Send-JsonResponse $context @{ status = "success" }
                } catch {
                    Send-JsonResponse $context @{ status = "error"; message = $_.Exception.Message }
                }
                return # Exit this request
            }
            
            # Run Technical operations asynchronously
            $jobId = [Guid]::NewGuid().ToString()
            
            $scriptBlock = $null
            
            switch ($action) {
                "cleanup_temp" {
                    $scriptBlock = {
                        Write-Output "Iniciando exclusão de arquivos temporários..."
                        $tempFolders = @(
                            "$env:TEMP",
                            "C:\Windows\Temp",
                            "C:\Windows\Prefetch",
                            "C:\Windows\SoftwareDistribution\Download"
                        )
                        $bytesFreed = 0
                        foreach ($folder in $tempFolders) {
                            if (Test-Path $folder) {
                                Write-Output "Limpando diretório: $folder"
                                $files = Get-ChildItem -Path $folder -Recurse -File -ErrorAction SilentlyContinue
                                foreach ($file in $files) {
                                    try {
                                        $size = $file.Length
                                        Remove-Item $file.FullName -Force -ErrorAction Stop
                                        $bytesFreed += $size
                                    } catch {
                                        # File in use, ignore
                                    }
                                }
                            }
                        }
                        
                        try {
                            Write-Output "Esvaziando Lixeira..."
                            Clear-RecycleBin -Force -ErrorAction Stop
                            Write-Output "Lixeira limpa."
                        } catch {
                            Write-Output "[AVISO] Lixeira vazia ou inacessível."
                        }
                        
                        $mb = [Math]::Round($bytesFreed / 1MB, 2)
                        Write-Output "[SUCESSO] Limpeza concluída. Foram liberados $mb MB de espaço em disco."
                    }
                }
                "repair_network" {
                    $scriptBlock = {
                        Write-Output "Executando procedimentos de reparo de rede..."
                        
                        Write-Output "-> Redefinindo WinSock Catalog..."
                        try { netsh winsock reset | Out-String | Write-Output } catch { Write-Output "[AVISO] winsock reset: $_" }
                        
                        Write-Output "-> Redefinindo pilha TCP/IP..."
                        try { netsh int ip reset | Out-String | Write-Output } catch { Write-Output "[AVISO] ip reset: $_" }
                        
                        Write-Output "-> Liberando concessoes IP..."
                        try { ipconfig /release | Out-String | Write-Output } catch { Write-Output "[AVISO] release: $_" }
                        
                        Write-Output "-> Renovando concessoes IP..."
                        try { ipconfig /renew | Out-String | Write-Output } catch { Write-Output "[AVISO] renew: $_" }
                        
                        Write-Output "-> Limpando cache do cliente DNS..."
                        try { ipconfig /flushdns | Out-String | Write-Output } catch {}
                        try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {}
                        
                        Write-Output "-> Limpando tabela ARP..."
                        try { arp -d * } catch {}
                        
                        Write-Output "[SUCESSO] Reparo e calibracao de rede executados com exito."
                    }
                }
                "gpupdate" {
                    $scriptBlock = {
                        Write-Output "Forçando atualização de GPOs locais..."
                        gpupdate /force
                        Write-Output "[SUCESSO] Diretivas de políticas de grupo atualizadas."
                    }
                }
                "sfc_scan" {
                    $scriptBlock = {
                        Write-Output "Iniciando verificação do Verificador de Arquivos do Windows (SFC)..."
                        Write-Output "Aguarde, varredura de arquivos protegidos em andamento..."
                        sfc /scannow
                        Write-Output "[SUCESSO] Execução do SFC Scan concluída."
                    }
                }
                "dism_repair" {
                    $scriptBlock = {
                        Write-Output "Iniciando reparo de imagem do Windows via DISM..."
                        Write-Output "Buscando arquivos íntegros nos servidores do Windows Update (pode demorar)..."
                        DISM /Online /Cleanup-Image /RestoreHealth
                        Write-Output "[SUCESSO] Execução de integridade de imagem DISM concluída."
                    }
                }
                "optimize_power" {
                    $scriptBlock = {
                        Write-Output "Iniciando otimização de energia..."
                        Write-Output "Alterando o plano de energia para Alto Desempenho..."
                        try {
                            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
                            Write-Output "[SUCESSO] Plano de energia configurado para Alto Desempenho."
                        } catch {
                            Write-Output "[ERRO] Falha ao configurar plano de energia."
                        }
                    }
                }
                "install_update" {
                    # Legacy fallback
                    $scriptBlock = {
                        Write-Output "[INFO] Redirecionando para atualizacao automatica..."
                        Write-Output "[SUCESSO] Use o botao 'Atualizar Automaticamente' para atualizar sem abrir o instalador."
                    }
                }
                "download_update" {
                    $scriptBlock = {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $repoBase   = "https://github.com/gestaoinformacaodhs-ship-it/WinToolKit/releases/latest/download"
                        $tempDir    = $env:TEMP
                        $installerPath = "$tempDir\WinToolKit_Update.exe"

                        Write-Output "Iniciando download do instalador atualizado..."
                        
                        $attempts = 0
                        $downloaded = $false
                        do {
                            $attempts++
                            try {
                                Write-Output "  Tentativa $attempts de 3..."
                                Invoke-WebRequest -Uri "$repoBase/Instalar.exe" -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
                                Write-Output "  [SUCESSO] Instalador baixado com sucesso."
                                $downloaded = $true
                            } catch {
                                if ($attempts -ge 3) {
                                    Write-Output "[ERRO] Falha ao baixar instalador apos $attempts tentativas: $_"
                                    throw "Falha no download do instalador"
                                }
                                Write-Output "  [AVISO] Tentativa $attempts falhou. Tentando novamente..."
                                Start-Sleep -Seconds 2
                            }
                        } while (-not $downloaded)

                        Write-Output "[SUCESSO] Todos os arquivos estao prontos para a atualizacao."
                    }
                }
                "apply_update" {
                    $scriptBlock = {
                        $tempDir = $env:TEMP
                        $installerPath = "$tempDir\WinToolKit_Update.exe"
                        if (Test-Path $installerPath) {
                            Write-Output "Executando instalador silencioso..."
                            Start-Process -FilePath $installerPath -WindowStyle Hidden
                            Start-Sleep -Seconds 2
                            
                            Get-Process "WinToolKit" -ErrorAction SilentlyContinue | Stop-Process -Force
                        } else {
                            Write-Output "[ERRO] Instalador nao encontrado em $installerPath"
                        }
                    }
                }
            }
            
            if ($null -ne $scriptBlock) {
                # Launch the background job
                $job = Start-Job -ScriptBlock $scriptBlock
                $global:ActiveJobs[$jobId] = $job
                Send-JsonResponse $context @{ success = $true; jobId = $jobId }
            } else {
                Send-JsonResponse $context @{ success = $false; message = "Acao desconhecida." }
            }
            
        } elseif ($url.StartsWith("/api/job-status") -and $method -eq "GET") {
            # Check async execution status and output logs
            $jobId = $context.Request.QueryString["jobId"]
            $job = $global:ActiveJobs[$jobId]
            
            if ($null -eq $job) {
                Send-JsonResponse $context @{ status = "failed"; message = "Job não cadastrado." }
            } else {
                # Capture standard outputs since last check
                $outputLines = [System.Collections.Generic.List[string]]::new()
                
                $jobData = Receive-Job -Job $job
                if ($null -ne $jobData) {
                    foreach ($line in $jobData) {
                        if ($null -ne $line) {
                            # Convert line objects or strings to plain text
                            $outputLines.Add($line.ToString())
                        }
                    }
                }
                
                $status = "running"
                if ($job.State -eq "Completed") {
                    $status = "completed"
                    Remove-Job -Job $job -Force
                    $global:ActiveJobs.Remove($jobId)
                } elseif ($job.State -eq "Failed") {
                    $status = "failed"
                    Remove-Job -Job $job -Force
                    $global:ActiveJobs.Remove($jobId)
                }
                
                Send-JsonResponse $context @{
                    status = $status
                    newLogs = $outputLines
                    totalLogsCount = 0
                }
            }
            
        } elseif ($url -eq "/favicon.ico") {
            # Evita avisos de 404 no console do navegador servindo um favicon vazio
            $context.Response.StatusCode = 200
            $context.Response.ContentType = "image/x-icon"
            $context.Response.Close()
            
        } else {
            # Serve Static Web Assets (from memory if embedded, from disk otherwise)
            $cleanPath = $url.Split('?')[0]
            
            if ($isEmbedded) {
                # --- ENTERPRISE MODE: serve from RAM ---
                if ($cleanPath -eq "/" -or $cleanPath -eq "/index.html" -or [string]::IsNullOrEmpty($cleanPath.Trim('/'))) {
                    Send-EmbeddedResponse $context $EMBEDDED_HTML "text/html; charset=utf-8"
                } elseif ($cleanPath -eq "/style.css") {
                    Send-EmbeddedResponse $context $EMBEDDED_CSS "text/css"
                } elseif ($cleanPath -eq "/app.js") {
                    Send-EmbeddedResponse $context $EMBEDDED_JS "application/javascript"
                } else {
                    $context.Response.StatusCode = 404
                    $context.Response.Close()
                }
            } else {
                # --- DEV MODE: serve from disk (web/ folder) ---
                $webDir = Join-Path $PSScriptRoot "web"
                $fullWebDir = (Resolve-Path $webDir).Path
                $mimeType = "application/octet-stream"
                $resolvedPath = ""
                
                if ($cleanPath -eq "/" -or $cleanPath -eq "/index.html" -or [string]::IsNullOrEmpty($cleanPath.Trim('/'))) {
                    $resolvedPath = Join-Path $webDir "index.html"
                    $mimeType = "text/html; charset=utf-8"
                } else {
                    $cleanUrl = $cleanPath.TrimStart('/')
                    $resolvedPath = Join-Path $webDir $cleanUrl
                    
                    if ($cleanPath.Contains(".css")) { $mimeType = "text/css" }
                    elseif ($cleanPath.Contains(".js")) { $mimeType = "application/javascript" }
                    elseif ($cleanPath.Contains(".png")) { $mimeType = "image/png" }
                    elseif ($cleanPath.Contains(".ico")) { $mimeType = "image/x-icon" }
                }
                
                if (Test-Path $resolvedPath -PathType Leaf) {
                    $canonicalPath = (Resolve-Path $resolvedPath).Path
                    if ($canonicalPath.StartsWith($fullWebDir)) {
                        Send-HtmlResponse $context $canonicalPath $mimeType
                    } else {
                        $context.Response.StatusCode = 403
                        $context.Response.Close()
                    }
                } else {
                    $context.Response.StatusCode = 404
                    $context.Response.Close()
                }
            }
        }
    }
} finally {
    # Port release insurance on break
    $listener.Stop()
    $listener.Close()
    
    # Remove active background jobs
    foreach ($job in $global:ActiveJobs.Values) {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "WinToolKit Server finalizado com sucesso." -ForegroundColor Yellow
}
