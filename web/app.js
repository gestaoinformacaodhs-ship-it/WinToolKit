// Global Variables & Configuration
const API_BASE = ''; // Same host as the dashboard
const DIAGNOSTICS_POLL_INTERVAL = 3000; // 3 seconds
const CIRCUMFERENCE = 2 * Math.PI * 70; // 439.822

let diagnosticsTimer = null;
let activePollingJobs = new Map(); // jobId -> intervalId

// Initialize the Application
document.addEventListener('DOMContentLoaded', () => {
    setupNavigation();
    initProgressRings();
    
    // Start diagnostics loop
    fetchDiagnostics();
    diagnosticsTimer = setInterval(fetchDiagnostics, DIAGNOSTICS_POLL_INTERVAL);
    
    // Load services list
    loadServices();
    
    // Log startup
    logToConsole('Sistema carregado e conectado ao servidor local.', 'success');
});

// 1. Navigation System
function setupNavigation() {
    const navItems = document.querySelectorAll('.sidebar-nav .nav-item');
    const sections = {
        'nav-dashboard': document.getElementById('sect-dashboard'),
        'nav-cleanup': document.getElementById('sect-cleanup'),
        'nav-services': document.getElementById('sect-services'),
        'nav-console': document.getElementById('sect-console'),
        'nav-updates': document.getElementById('sect-updates')
    };

    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            
            // Remove active classes
            navItems.forEach(nav => nav.classList.remove('active'));
            
            // Add active to current
            item.classList.add('active');
            
            // Hide all sections, show clicked one
            Object.values(sections).forEach(sect => sect.classList.add('hidden'));
            
            const section = sections[item.id];
            if (section) {
                section.classList.remove('hidden');
                
                // If console section, autoscroll to bottom
                if (item.id === 'nav-console') {
                    scrollConsoleToBottom();
                }
            }
        });
    });
}

// 2. SVG Health Rings
function initProgressRings() {
    const rings = ['cpu-ring', 'ram-ring', 'disk-ring'];
    rings.forEach(ringId => {
        const ring = document.getElementById(ringId);
        if (ring) {
            ring.style.strokeDasharray = CIRCUMFERENCE;
            ring.style.strokeDashoffset = CIRCUMFERENCE;
        }
    });
}

function updateRingProgress(ringId, percent) {
    const ring = document.getElementById(ringId);
    if (!ring) return;
    
    // Bounds check
    const value = Math.max(0, Math.min(100, percent));
    const offset = CIRCUMFERENCE - (value / 100) * CIRCUMFERENCE;
    ring.style.strokeDashoffset = offset;
}

// 3. Diagnostics and Dashboard Polling
async function fetchDiagnostics() {
    try {
        const response = await fetch(`${API_BASE}/api/diagnostics`);
        if (!response.ok) throw new Error('API server returned error status');
        const data = await response.json();
        
        // Update System Info
        document.getElementById('info-hostname').textContent = data.hostname || '--';
        document.getElementById('info-username').textContent = data.currentUser || '--';
        document.getElementById('info-os-name').textContent = data.osName || '--';
        document.getElementById('info-os-version').textContent = data.osVersion || '--';
        document.getElementById('info-uptime').textContent = data.uptime || '--';
        document.getElementById('info-install-date').textContent = data.installDate || '--';
        document.getElementById('info-ipv4').textContent = data.ipAddress || 'Desconectado';
        
        // Update Gauges (CPU, RAM, DISK)
        const cpuPercent = Math.round(data.cpuPercent) || 0;
        document.getElementById('cpu-text').textContent = `${cpuPercent}%`;
        document.getElementById('cpu-badge').textContent = `${cpuPercent}%`;
        updateRingProgress('cpu-ring', cpuPercent);
        document.getElementById('info-cpu-model').textContent = data.cpuModel || 'Processador Genérico';
        
        const ramPercent = Math.round(data.ramPercent) || 0;
        document.getElementById('ram-text').textContent = `${ramPercent}%`;
        document.getElementById('ram-badge').textContent = `${data.ramUsedGb.toFixed(1)} / ${data.ramTotalGb.toFixed(1)} GB`;
        updateRingProgress('ram-ring', ramPercent);
        document.getElementById('ram-used').textContent = `${data.ramUsedGb.toFixed(1)} GB`;
        document.getElementById('ram-free').textContent = `${data.ramFreeGb.toFixed(1)} GB`;
        
        const diskPercent = Math.round(data.diskPercent) || 0;
        document.getElementById('disk-text').textContent = `${diskPercent}%`;
        document.getElementById('disk-badge').textContent = `${data.diskUsedGb} / ${data.diskTotalGb} GB`;
        updateRingProgress('disk-ring', diskPercent);
        document.getElementById('disk-free').textContent = `${data.diskFreeGb} GB`;
        
        // Connection Latency Panel
        const pingVal = data.pingLatency;
        const pingEl = document.getElementById('net-ping');
        const pingBadge = document.getElementById('ping-status-badge');
        
        if (pingVal !== null && pingVal >= 0) {
            pingEl.textContent = pingVal;
            pingEl.style.color = 'var(--emerald)';
            pingBadge.textContent = 'Estável';
            pingBadge.className = 'net-val-badge badge-running';
        } else {
            pingEl.textContent = '--';
            pingEl.style.color = 'var(--red)';
            pingBadge.textContent = 'Sem Conexão';
            pingBadge.className = 'net-val-badge badge-stopped';
        }
        
        // Server Active Indicator update
        document.getElementById('server-status-text').textContent = 'Servidor Ativo';
        document.querySelector('.status-dot').style.backgroundColor = 'var(--emerald)';
        document.querySelector('.status-dot').style.boxShadow = '0 0 10px var(--emerald)';
        
    } catch (error) {
        console.error('Error fetching diagnostics:', error);
        
        // Mark server as disconnected in the footer
        document.getElementById('server-status-text').textContent = 'Servidor Offline';
        document.querySelector('.status-dot').style.backgroundColor = 'var(--red)';
        document.querySelector('.status-dot').style.boxShadow = '0 0 10px var(--red)';
        
        document.getElementById('net-ping').textContent = '--';
        document.getElementById('ping-status-badge').textContent = 'Desconectado';
        document.getElementById('ping-status-badge').className = 'net-val-badge badge-stopped';
    }
}

// 4. Executing Technical Tools
async function runTool(toolKey) {
    let actionFriendlyName = '';
    switch(toolKey) {
        case 'cleanup_temp': actionFriendlyName = 'Limpeza de Arquivos Temporários'; break;
        case 'repair_network': actionFriendlyName = 'Reparo de Rede (Winsock/DNS)'; break;
        case 'gpupdate': actionFriendlyName = 'Atualização de Políticas (GPUPDATE)'; break;
        case 'sfc_scan': actionFriendlyName = 'Verificação de Arquivos de Sistema (SFC)'; break;
        case 'dism_repair': actionFriendlyName = 'Reparo de Imagem do Windows (DISM)'; break;
        default: actionFriendlyName = 'Operação do Sistema';
    }
    
    // Jump to Console view to show logs
    document.getElementById('nav-console').click();
    
    logToConsole(`[GATILHO] Iniciando ação: "${actionFriendlyName}"...`, 'command');
    
    try {
        const response = await fetch(`${API_BASE}/api/action`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: toolKey })
        });
        
        if (!response.ok) throw new Error('Falha ao iniciar processo no servidor');
        const data = await response.json();
        
        if (data.success && data.jobId) {
            logToConsole(`Processo alocado com ID do Job: ${data.jobId}. Monitorando execução...`, 'info');
            startJobPolling(data.jobId, actionFriendlyName);
        } else {
            throw new Error(data.message || 'Resposta inesperada do servidor.');
        }
    } catch (error) {
        logToConsole(`[FALHA] Não foi possível iniciar "${actionFriendlyName}": ${error.message}`, 'error');
    }
}

// Job Polling System (simulating stream through buffers using recursive setTimeout)
function startJobPolling(jobId, actionName) {
    if (activePollingJobs.has(jobId)) return;
    
    let lastLogIndex = 0;
    
    async function poll() {
        try {
            const response = await fetch(`${API_BASE}/api/job-status?jobId=${jobId}&lastIndex=${lastLogIndex}`);
            if (!response.ok) throw new Error('Perda de contato com o monitor do Job');
            const data = await response.json();
            
            // Print new logs
            if (data.newLogs && data.newLogs.length > 0) {
                data.newLogs.forEach(logLine => {
                    let logClass = 'line-info';
                    if (logLine.includes('[SUCESSO]') || logLine.includes('com êxito') || logLine.includes('com sucesso')) {
                        logClass = 'line-success';
                    } else if (logLine.includes('[ERRO]') || logLine.includes('falhou') || logLine.includes('Access Denied')) {
                        logClass = 'line-error';
                    } else if (logLine.includes('[AVISO]')) {
                        logClass = 'line-warning';
                    }
                    logToConsole(logLine, logClass);
                });
            }
            
            // Check completed status
            if (data.status === 'completed') {
                activePollingJobs.delete(jobId);
                logToConsole(`[FINALIZADO] Ação "${actionName}" concluída com sucesso!`, 'success');
                fetchDiagnostics(); // Refresh data in case disk space was freed
            } else if (data.status === 'failed') {
                activePollingJobs.delete(jobId);
                logToConsole(`[FALHA] Ação "${actionName}" terminou com erros.`, 'error');
            } else {
                // Task is still running, schedule next poll ONLY after this one resolved
                const timeoutId = setTimeout(poll, 700);
                activePollingJobs.set(jobId, timeoutId);
            }
        } catch (error) {
            activePollingJobs.delete(jobId);
            logToConsole(`[MONITOR] Erro ao obter atualizações do processo: ${error.message}`, 'error');
        }
    }
    
    // Schedule the first poll
    const timeoutId = setTimeout(poll, 700);
    activePollingJobs.set(jobId, timeoutId);
}

// 5. Windows Services Management
async function loadServices() {
    const tbody = document.getElementById('services-list-tbody');
    try {
        const response = await fetch(`${API_BASE}/api/services`);
        if (!response.ok) throw new Error('Erro ao listar serviços');
        const data = await response.json();
        
        tbody.innerHTML = '';
        document.getElementById('srv-count').textContent = data.length;
        
        data.forEach(service => {
            const tr = document.createElement('tr');
            
            // Status badge class mapping
            let badgeClass = 'badge-other';
            let statusLabel = service.Status;
            
            if (service.Status === 'Running') {
                badgeClass = 'badge-running';
                statusLabel = 'Executando';
            } else if (service.Status === 'Stopped') {
                badgeClass = 'badge-stopped';
                statusLabel = 'Parado';
            }
            
            tr.innerHTML = `
                <td style="font-weight:600;">${service.DisplayName}</td>
                <td style="font-family:'JetBrains Mono'; font-size:12px; color:var(--text-secondary);">${service.Name}</td>
                <td>
                    <span class="service-status-badge ${badgeClass}">
                        <span class="status-dot"></span>
                        ${statusLabel}
                    </span>
                </td>
                <td class="actions-cell">
                    <button class="btn-action-circle start" title="Iniciar Serviço" onclick="controlService('${service.Name}', 'start')">
                        <i class="fa-solid fa-play"></i>
                    </button>
                    <button class="btn-action-circle stop" title="Parar Serviço" onclick="controlService('${service.Name}', 'stop')">
                        <i class="fa-solid fa-stop"></i>
                    </button>
                    <button class="btn-action-circle restart" title="Reiniciar Serviço" onclick="controlService('${service.Name}', 'restart')">
                        <i class="fa-solid fa-rotate-left"></i>
                    </button>
                </td>
            `;
            tbody.appendChild(tr);
        });
    } catch (error) {
        console.error('Error loading services:', error);
        tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color:var(--red);">Falha ao obter lista de serviços: ${error.message}</td></tr>`;
    }
}

async function controlService(serviceName, action) {
    let actionFriendly = '';
    if (action === 'start') actionFriendly = 'iniciar';
    else if (action === 'stop') actionFriendly = 'parar';
    else if (action === 'restart') actionFriendly = 'reiniciar';
    
    logToConsole(`[SERVICO] Solicitando ${actionFriendly} do serviço "${serviceName}"...`, 'command');
    
    try {
        const response = await fetch(`${API_BASE}/api/service-control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ service: serviceName, action: action })
        });
        
        if (!response.ok) throw new Error('Falha na comunicação com o servidor de serviços');
        const data = await response.json();
        
        if (data.success) {
            logToConsole(`[SERVICO] ${data.message}`, 'success');
            loadServices(); // reload the UI list
        } else {
            throw new Error(data.message || 'Sem retorno de sucesso.');
        }
    } catch (error) {
        logToConsole(`[SERVICO ERRO] Falha ao tentar alterar o serviço "${serviceName}": ${error.message}`, 'error');
    }
}

// 6. Inline Terminal Console Logs
function logToConsole(message, type = 'line-info') {
    const consoleOut = document.getElementById('console-output');
    if (!consoleOut) return;
    
    const line = document.createElement('div');
    line.className = `console-line ${type}`;
    
    // Prepend dynamic timestamp
    const now = new Date();
    const ts = `[${now.toLocaleTimeString()}] `;
    
    line.textContent = ts + message;
    consoleOut.appendChild(line);
    
    // Cap log lines to 1000 to prevent layout lag
    while (consoleOut.childElementCount > 1000) {
        consoleOut.removeChild(consoleOut.firstChild);
    }
    
    scrollConsoleToBottom();
}

function scrollConsoleToBottom() {
    const consoleOut = document.getElementById('console-output');
    if (consoleOut) {
        consoleOut.scrollTop = consoleOut.scrollHeight;
    }
}

function clearConsole() {
    const consoleOut = document.getElementById('console-output');
    if (consoleOut) {
        consoleOut.innerHTML = '';
        logToConsole('Console limpo pelo operador.', 'info');
    }
}

function copyConsoleLogs() {
    const consoleOut = document.getElementById('console-output');
    if (!consoleOut) return;
    
    const lines = Array.from(consoleOut.querySelectorAll('.console-line'))
        .map(el => el.textContent)
        .join('\n');
        
    navigator.clipboard.writeText(lines)
        .then(() => {
            alert('Logs copiados para a área de transferência com sucesso!');
        })
        .catch(err => {
            console.error('Falha ao copiar logs:', err);
            alert('Falha ao copiar logs. Verifique permissões do navegador.');
        });
}

// 7. Updates System
async function checkUpdates() {
    const msgEl = document.getElementById('update-status-msg');
    const latestVersionEl = document.getElementById('latest-version-text');
    const btnUpdate = document.getElementById('btn-do-update');
    
    msgEl.textContent = "Verificando servidor de atualizações...";
    msgEl.style.color = "var(--text-muted)";
    
    try {
        // Consultar o repositório GitHub para pegar o version.json
        const timestamp = new Date().getTime();
        const response = await fetch(`https://raw.githubusercontent.com/gestaoinformacaodhs-ship-it/WinToolKit/main/version.json?t=${timestamp}`, { cache: 'no-store' });
        
        if (!response.ok) {
            throw new Error(`Servidor retornou erro ${response.status}. Certifique-se de que o repositório no GitHub é Público e não Privado.`);
        }
        
        const data = await response.json();
        const latestVersion = data.version; 
        
        const currentVersion = "v1.0.4";
        
        latestVersionEl.textContent = latestVersion;
        
        if (latestVersion !== currentVersion) {
            msgEl.textContent = "Uma nova versão está disponível! Clique em Baixar e Instalar Agora.";
            msgEl.style.color = "var(--cyan)";
            btnUpdate.classList.remove('hidden');
        } else {
            msgEl.textContent = "Você já possui a versão mais recente do WinToolKit.";
            msgEl.style.color = "var(--emerald)";
            btnUpdate.classList.add('hidden');
        }
    } catch (error) {
        msgEl.textContent = "Erro ao verificar atualizações: " + error.message;
        msgEl.style.color = "var(--red)";
    }
}

