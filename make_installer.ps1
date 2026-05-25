# ============================================================
# WinToolKit - Make Self-Contained Installer
# Generates Instalar.exe with ALL files embedded inside
# ============================================================

$ErrorActionPreference = "Stop"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    Write-Error "csc.exe nao encontrado! Instale o .NET Framework 4."
    exit 1
}

$base = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- STEP -1: Certificate Generation & Executable Signing Routine ----
function Sign-Executable {
    param (
        [string]$filePath
    )
    Write-Host "Assinando digitalmente: $filePath..." -ForegroundColor Yellow
    
    # 1. Localizar ou criar o certificado autoassinado
    $certSubject = "CN=DHS Suporte Tecnico"
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$certSubject*" } | Select-Object -First 1
    
    if (-not $cert) {
        Write-Host "Criando novo certificado digital autoassinado em CurrentUser\My..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Type CodeSigning -Subject $certSubject -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(5)
        Write-Host "Certificado criado com sucesso! Impressao digital: $($cert.Thumbprint)" -ForegroundColor Green
    } else {
        Write-Host "Certificado existente localizado! Impressao digital: $($cert.Thumbprint)" -ForegroundColor Gray
    }
    
    # 2. Exportar o certificado público (.cer) para distribuição se ainda não exportado
    $cerPath = Join-Path $base "wintoolkit.cer"
    if (-not (Test-Path $cerPath)) {
        Write-Host "Exportando certificado publico para $cerPath..." -ForegroundColor Yellow
        $bytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        [System.IO.File]::WriteAllBytes($cerPath, $bytes)
        Write-Host "Certificado publico exportado com sucesso!" -ForegroundColor Green
    }
    
    # 3. Assinar o executável
    try {
        # Tenta assinar com carimbo de data/hora (timestamp)
        Set-AuthenticodeSignature -FilePath $filePath -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -ErrorAction Stop | Out-Null
        Write-Host "  [OK] Assinado com sucesso (com Timestamp)!" -ForegroundColor Green
    }
    catch {
        Write-Warning "Falha ao assinar com timestamp: $_. Tentando assinar sem timestamp..."
        try {
            Set-AuthenticodeSignature -FilePath $filePath -Certificate $cert -ErrorAction Stop | Out-Null
            Write-Host "  [OK] Assinado com sucesso (sem Timestamp)!" -ForegroundColor Green
        }
        catch {
            Write-Error "Falha critica ao aplicar assinatura digital em ${filePath}. Erro: $_"
        }
    }
}

# ---- STEP 0: Generate app.ico from logo.png ----
$pngPath = Join-Path $base "logo.png"
$icoPath = Join-Path $base "app.ico"

if (Test-Path $pngPath) {
    Write-Host "Convertendo logo.png para app.ico..." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName System.Drawing
        $original = [System.Drawing.Image]::FromFile($pngPath)
        $resized = New-Object System.Drawing.Bitmap(256, 256)
        $graphics = [System.Drawing.Graphics]::FromImage($resized)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($original, 0, 0, 256, 256)
        $graphics.Dispose()
        
        $ms = New-Object System.IO.MemoryStream
        $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBytes = $ms.ToArray()
        $ms.Dispose()
        $original.Dispose()
        $resized.Dispose()
        $pngSize = $pngBytes.Length
        
        $stream = New-Object System.IO.FileStream($icoPath, [System.IO.FileMode]::Create)
        $writer = New-Object System.IO.BinaryWriter($stream)
        
        # ICO Header
        $writer.Write([UInt16]0)      # Reserved
        $writer.Write([UInt16]1)      # Type (1 = Icon)
        $writer.Write([UInt16]1)      # Count (1 image)
        
        # Icon Directory Entry
        $writer.Write([Byte]0)        # Width (0 = 256)
        $writer.Write([Byte]0)        # Height (0 = 256)
        $writer.Write([Byte]0)        # ColorCount
        $writer.Write([Byte]0)        # Reserved
        $writer.Write([UInt16]1)      # Planes
        $writer.Write([UInt16]32)     # BitCount (32 bits)
        $writer.Write([UInt32]$pngSize) # BytesInRes
        $writer.Write([UInt32]22)     # ImageOffset (6 bytes header + 16 bytes directory entry = 22)
        
        # Image Data
        $writer.Write($pngBytes, 0, $pngSize)
        
        $writer.Close()
        $stream.Close()
        Write-Host "  [OK] app.ico gerado com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Warning "Falha ao converter logo.png para app.ico: $_"
    }
} else {
    Write-Warning "logo.png nao encontrado no diretorio raiz. A compilacao sera feita sem icone personalizado."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   WINTOOLKIT - GERANDO INSTALADOR AUTO-CONTIDO" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- STEP 1: Fix and compile WinToolKit.exe launcher ----
Write-Host "[1/4] Compilando WinToolKit.exe (launcher)..." -ForegroundColor Yellow

$launcherSrc = Join-Path $base "src\Launcher_v2.cs"

# Write a clean C# 5 compatible launcher
$launcherCode = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

namespace WinToolKit
{
    public class Launcher : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private ContextMenu trayMenu;
        private Process backendProcess;
        private string appDir;
        private string scriptPath;
        private string sessionToken;
        private const string MutexName = "WinToolKit_SingleInstance_Mutex";

        [STAThread]
        public static void Main(string[] args)
        {
            if (!IsAdministrator())
            {
                ElevateAndExit();
                return;
            }

            bool createdNew;
            Mutex mutex = new Mutex(true, MutexName, out createdNew);
            if (!createdNew)
            {
                MessageBox.Show(
                    "O WinToolKit ja esta em execucao. Verifique a bandeja do sistema.",
                    "WinToolKit",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information
                );
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            var launcher = new Launcher();
            Application.Run(launcher);
        }

        public Launcher()
        {
            sessionToken = Guid.NewGuid().ToString("N");
            appDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            scriptPath = Path.Combine(appDir, "toolkit.ps1");

            if (!File.Exists(scriptPath))
            {
                string parent = Directory.GetParent(appDir).FullName;
                string fallback = Path.Combine(parent, "toolkit.ps1");
                if (File.Exists(fallback))
                {
                    scriptPath = fallback;
                    appDir = parent;
                }
                else
                {
                    MessageBox.Show(
                        "Erro: toolkit.ps1 nao encontrado. Reinstale o WinToolKit.",
                        "WinToolKit - Erro",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    Environment.Exit(1);
                    return;
                }
            }

            InitializeTray();
            StartBackend();
            Thread.Sleep(3000);
            OpenDashboard();

            trayIcon.ShowBalloonTip(
                3000,
                "WinToolKit Ativo",
                "Painel iniciado. Clique no icone da bandeja para acessar.",
                ToolTipIcon.Info
            );
        }

        private void InitializeTray()
        {
            trayMenu = new ContextMenu();
            trayMenu.MenuItems.Add(new MenuItem("Abrir Painel", OnOpenDashboard) { DefaultItem = true });
            trayMenu.MenuItems.Add(new MenuItem("Reiniciar Servidor", OnRestartServer));
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add(new MenuItem("Sair do WinToolKit", OnExit));

            trayIcon = new NotifyIcon();
            trayIcon.Text = "WinToolKit - Suporte Tecnico";
            trayIcon.Icon = CreateTrayIcon();
            trayIcon.ContextMenu = trayMenu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += OnOpenDashboard;
        }

        private static Icon CreateTrayIcon()
        {
            try
            {
                return Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
            }
            catch
            {
                try
                {
                    Bitmap bmp = new Bitmap(16, 16);
                Graphics g = Graphics.FromImage(bmp);
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                System.Drawing.Drawing2D.LinearGradientBrush brush =
                    new System.Drawing.Drawing2D.LinearGradientBrush(
                        new Point(0, 0), new Point(16, 16),
                        Color.FromArgb(6, 182, 212),
                        Color.FromArgb(99, 102, 241)
                    );
                g.FillEllipse(brush, 0, 0, 15, 15);
                Pen pen = new Pen(Color.White, 1.5f);
                g.DrawLine(pen, 4, 4, 7, 7);
                g.DrawLine(pen, 7, 7, 4, 10);
                g.DrawLine(pen, 7, 10, 11, 10);
                pen.Dispose();
                brush.Dispose();
                g.Dispose();
                Icon icon = Icon.FromHandle(bmp.GetHicon());
                return icon;
            }
            catch
            {
                return SystemIcons.Application;
            }
            }
        }

        private void StartBackend()
        {
            try
            {
                KillBackendProcess();
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Token \"{1}\"", scriptPath, sessionToken);
                psi.WorkingDirectory = appDir;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                backendProcess = Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    string.Format("Falha ao iniciar o backend:\n{0}", ex.Message),
                    "WinToolKit - Erro",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }

        private void OpenDashboard()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "msedge.exe";
                psi.Arguments = string.Format("--app=http://localhost:4040/?token={0} --window-size=1280,720", sessionToken);
                try { Process.Start(psi); }
                catch { Process.Start(string.Format("http://localhost:4040/?token={0}", sessionToken)); }
            }
            catch { }
        }

        private void KillBackendProcess()
        {
            if (backendProcess != null && !backendProcess.HasExited)
            {
                try { backendProcess.Kill(); backendProcess.Dispose(); } catch { }
                backendProcess = null;
            }
        }

        private void OnOpenDashboard(object sender, EventArgs e) { OpenDashboard(); }

        private void OnRestartServer(object sender, EventArgs e)
        {
            trayIcon.ShowBalloonTip(2000, "WinToolKit", "Reiniciando servidor...", ToolTipIcon.Info);
            StartBackend();
            Thread.Sleep(1500);
            OpenDashboard();
        }

        private void OnExit(object sender, EventArgs e)
        {
            if (trayIcon != null) { trayIcon.Visible = false; trayIcon.Dispose(); }
            KillBackendProcess();
            Application.ExitThread();
            Environment.Exit(0);
        }

        private static bool IsAdministrator()
        {
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private static void ElevateAndExit()
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Assembly.GetExecutingAssembly().Location;
            psi.Verb = "runas";
            psi.UseShellExecute = true;
            try { Process.Start(psi); } catch { }
            Environment.Exit(0);
        }
    }
}
'@

Set-Content -Path $launcherSrc -Value $launcherCode -Encoding UTF8

$launcherOut = Join-Path $base "WinToolKit.exe"
$launcherArgs = "/target:winexe /out:`"$launcherOut`" /win32icon:`"$icoPath`" /optimize+ /reference:System.Windows.Forms.dll,System.Drawing.dll `"$launcherSrc`""

$result = Start-Process -FilePath $csc -ArgumentList $launcherArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\csc_out.txt" -RedirectStandardError "$env:TEMP\csc_err.txt"
$cscOut = Get-Content "$env:TEMP\csc_out.txt" -Raw -ErrorAction SilentlyContinue
$cscErr = Get-Content "$env:TEMP\csc_err.txt" -Raw -ErrorAction SilentlyContinue

if ($result.ExitCode -ne 0 -or -not (Test-Path $launcherOut)) {
    Write-Host "ERRO ao compilar WinToolKit.exe:" -ForegroundColor Red
    Write-Host $cscOut -ForegroundColor Red
    Write-Host $cscErr -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] WinToolKit.exe compilado!" -ForegroundColor Green

# Assinar digitalmente o Launcher
Sign-Executable -filePath $launcherOut

# ---- STEP 1.5: Compile Desinstalar.exe ----
Write-Host "[1.5/4] Compilando Desinstalar.exe..." -ForegroundColor Yellow
$uninstallSrc = Join-Path $base "src\Uninstall.cs"
$uninstallCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WinToolKit
{
    class Uninstaller
    {
        static void Main()
        {
            if (MessageBox.Show("Deseja realmente remover o WinToolKit do seu computador?", "Desinstalar WinToolKit", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
            {
                try {
                    string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string lnk1 = Path.Combine(desktop, "WinToolKit.lnk");
                    if (File.Exists(lnk1)) File.Delete(lnk1);
                    
                    string sm = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "WinToolKit");
                    if (Directory.Exists(sm)) Directory.Delete(sm, true);
                    
                    Registry.LocalMachine.DeleteSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinToolKit", false);
                } catch { }

                string appDir = AppDomain.CurrentDomain.BaseDirectory;
                string batch = Path.Combine(Path.GetTempPath(), "remove_wintoolkit.bat");
                File.WriteAllText(batch, "@echo off\r\ntimeout /t 2 /nobreak >nul\r\nrmdir /s /q \"" + appDir + "\"\r\ndel \"%~f0\"");
                
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "cmd.exe";
                psi.Arguments = "/c \"" + batch + "\"";
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                Process.Start(psi);
                
                Environment.Exit(0);
            }
        }
    }
}
'@

Set-Content -Path $uninstallSrc -Value $uninstallCode -Encoding UTF8
$uninstallOut = Join-Path $base "Desinstalar.exe"
$uninstArgs = "/target:winexe /out:`"$uninstallOut`" /win32icon:`"$icoPath`" /optimize+ /reference:System.Windows.Forms.dll `"$uninstallSrc`""

$resU = Start-Process -FilePath $csc -ArgumentList $uninstArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\csc_u_out.txt" -RedirectStandardError "$env:TEMP\csc_u_err.txt"
if ($resU.ExitCode -ne 0 -or -not (Test-Path $uninstallOut)) {
    Write-Host "ERRO ao compilar Desinstalar.exe" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Desinstalar.exe compilado!" -ForegroundColor Green

# Assinar digitalmente o Desinstalador
Sign-Executable -filePath $uninstallOut

# ---- STEP 2: Read all files and encode as Base64 ----
Write-Host "[2/4] Lendo e codificando todos os arquivos..." -ForegroundColor Yellow

function Get-FileBase64($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    return [System.Convert]::ToBase64String($bytes)
}

$b64_launcher  = Get-FileBase64 (Join-Path $base "WinToolKit.exe")
$b64_uninstaller = Get-FileBase64 (Join-Path $base "Desinstalar.exe")
$b64_toolkit   = Get-FileBase64 (Join-Path $base "toolkit.ps1")
$b64_html      = Get-FileBase64 (Join-Path $base "web\index.html")
$b64_css       = Get-FileBase64 (Join-Path $base "web\style.css")
$b64_js        = Get-FileBase64 (Join-Path $base "web\app.js")

Write-Host "  [OK] WinToolKit.exe : $($b64_launcher.Length) chars base64" -ForegroundColor Gray
Write-Host "  [OK] toolkit.ps1    : $($b64_toolkit.Length) chars base64" -ForegroundColor Gray
Write-Host "  [OK] index.html     : $($b64_html.Length) chars base64" -ForegroundColor Gray
Write-Host "  [OK] style.css      : $($b64_css.Length) chars base64" -ForegroundColor Gray
Write-Host "  [OK] app.js         : $($b64_js.Length) chars base64" -ForegroundColor Gray

# ---- STEP 3: Generate self-contained Installer C# source ----
Write-Host "[3/4] Gerando codigo-fonte do instalador auto-contido..." -ForegroundColor Yellow

$installerSrc = Join-Path $base "src\SelfInstaller.cs"

$csCode = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace WinToolKit
{
    public class InstallerForm : Form
    {
        // ===== EMBEDDED FILES (Base64) =====
        private static readonly string B64_LAUNCHER    = "$b64_launcher";
        private static readonly string B64_UNINSTALLER = "$b64_uninstaller";
        private static readonly string B64_TOOLKIT     = "$b64_toolkit";
        private static readonly string B64_HTML     = "$b64_html";
        private static readonly string B64_CSS      = "$b64_css";
        private static readonly string B64_JS       = "$b64_js";

        private string targetDir = @"C:\Program Files\WinToolKit";
        private int currentStep = 1;

        private Panel headerPanel;
        private Panel leftPanel;
        private Panel contentPanel;
        private Label titleLabel;
        private bool drag = false;
        private Point dragStart = new Point(0, 0);
        private ProgressBar progressBar;
        private Label progressStatus;
        private TextBox pathBox;
        private CheckBox chkDesktop;
        private CheckBox chkStartMenu;
        private CheckBox chkRunNow;

        private static void Log(string message)
        {
            try
            {
                string logPath = Path.Combine(Path.GetTempPath(), "wintoolkit_install.log");
                File.AppendAllText(logPath, string.Format("[{0}] {1}\r\n", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"), message));
            }
            catch { }
        }

        public static bool IsSilentUpdate = false;

        [STAThread]
        public static void Main()
        {
            Log("=== INSTALADOR INICIADO ===");
            IsSilentUpdate = Path.GetFileNameWithoutExtension(Assembly.GetExecutingAssembly().Location).Equals("WinToolKit_Update", StringComparison.OrdinalIgnoreCase);
            
            Log("IsAdministrator: " + IsAdministrator());
            if (!IsAdministrator()) 
            { 
                Log("Nao e Administrador. Solicitando UAC...");
                ElevateAndExit(); 
                return; 
            }
            Log("Iniciando Form...");
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            
            InstallerForm form = new InstallerForm();
            if (IsSilentUpdate) {
                form.Opacity = 0;
                form.ShowInTaskbar = false;
                form.Load += (s, e) => {
                    form.Hide();
                    // Start install directly
                    form.ShowInstalling();
                };
            }
            Application.Run(form);
            Log("=== INSTALADOR FINALIZADO ===");
        }

        public InstallerForm()
        {
            try { this.Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); } catch { }
            this.Text = "WinToolKit - Instalacao";
            this.Size = new Size(680, 420);
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(11, 15, 25);

            BuildHeader();
            BuildLeftPanel();

            contentPanel = new Panel();
            contentPanel.Size = new Size(490, 340);
            contentPanel.Location = new Point(190, 50);
            contentPanel.BackColor = Color.Transparent;
            this.Controls.Add(contentPanel);
            this.Controls.SetChildIndex(contentPanel, 0);

            ShowWelcome();
        }

        private void BuildHeader()
        {
            headerPanel = new Panel();
            headerPanel.Size = new Size(680, 50);
            headerPanel.Location = new Point(0, 0);
            headerPanel.BackColor = Color.FromArgb(15, 20, 35);
            headerPanel.Paint += (s, e) => {
                using (Pen p = new Pen(Color.FromArgb(6, 182, 212), 1))
                    e.Graphics.DrawLine(p, 0, 49, 680, 49);
            };
            headerPanel.MouseDown += (s, e) => { drag = true; dragStart = new Point(e.X, e.Y); };
            headerPanel.MouseMove += (s, e) => { if (drag) { Point p = PointToScreen(e.Location); this.Location = new Point(p.X - dragStart.X, p.Y - dragStart.Y); } };
            headerPanel.MouseUp   += (s, e) => drag = false;

            Label logo = new Label();
            logo.Text = "  > WinToolKit  -  Assistente de Instalacao";
            logo.Font = new Font("Segoe UI", 11, FontStyle.Bold);
            logo.ForeColor = Color.White;
            logo.Location = new Point(10, 12);
            logo.AutoSize = true;
            logo.MouseDown += (s, e) => { drag = true; dragStart = new Point(e.X + logo.Left, e.Y + logo.Top); };
            logo.MouseMove += (s, e) => { if (drag) { Point p = PointToScreen(e.Location); this.Location = new Point(p.X - dragStart.X, p.Y - dragStart.Y); } };
            logo.MouseUp   += (s, e) => drag = false;
            headerPanel.Controls.Add(logo);

            Button btnClose = new Button();
            btnClose.Text = "✕";
            btnClose.Font = new Font("Segoe UI", 13, FontStyle.Bold);
            btnClose.ForeColor = Color.FromArgb(150, 150, 160);
            btnClose.BackColor = Color.Transparent;
            btnClose.FlatStyle = FlatStyle.Flat;
            btnClose.FlatAppearance.BorderSize = 0;
            btnClose.FlatAppearance.MouseOverBackColor = Color.FromArgb(220, 38, 38);
            btnClose.Size = new Size(42, 50);
            btnClose.Location = new Point(638, 0);
            btnClose.Cursor = Cursors.Hand;
            btnClose.Click += (s, e) => this.Close();
            headerPanel.Controls.Add(btnClose);

            this.Controls.Add(headerPanel);
        }

        private void BuildLeftPanel()
        {
            leftPanel = new Panel();
            leftPanel.Size = new Size(190, 370);
            leftPanel.Location = new Point(0, 50);
            leftPanel.Paint += (s, e) => {
                LinearGradientBrush bg = new LinearGradientBrush(
                    new Point(0,0), new Point(190, 370),
                    Color.FromArgb(15, 20, 35), Color.FromArgb(20, 30, 55));
                e.Graphics.FillRectangle(bg, 0, 0, 190, 370);
                bg.Dispose();
                using (Pen p = new Pen(Color.FromArgb(6, 182, 212), 1))
                    e.Graphics.DrawLine(p, 189, 0, 189, 370);

                // Draw decorative circles
                using (SolidBrush c = new SolidBrush(Color.FromArgb(20, 6, 182, 212)))
                {
                    e.Graphics.FillEllipse(c, -30, 200, 120, 120);
                    e.Graphics.FillEllipse(c, 80, 280, 160, 160);
                }
            };

            Label brand = new Label();
            brand.Text = "WIN\nTOOL\nKIT";
            brand.Font = new Font("Segoe UI", 20, FontStyle.Bold);
            brand.ForeColor = Color.White;
            brand.Location = new Point(18, 30);
            brand.AutoSize = true;
            leftPanel.Controls.Add(brand);

            Label sub = new Label();
            sub.Text = "DHS SUPORTE";
            sub.Font = new Font("Segoe UI", 8, FontStyle.Regular);
            sub.ForeColor = Color.FromArgb(6, 182, 212);
            sub.Location = new Point(20, 110);
            sub.AutoSize = true;
            leftPanel.Controls.Add(sub);

            // Step indicators
            string[] steps = { "1  Boas-vindas", "2  Destino", "3  Instalando", "4  Concluido" };
            for (int i = 0; i < steps.Length; i++)
            {
                Label lbl = new Label();
                lbl.Text = steps[i];
                lbl.Font = new Font("Segoe UI", 8.5f, FontStyle.Regular);
                lbl.ForeColor = Color.FromArgb(80, 180, 180);
                lbl.Location = new Point(20, 165 + i * 28);
                lbl.AutoSize = true;
                lbl.Tag = i + 1;
                leftPanel.Controls.Add(lbl);
            }

            this.Controls.Add(leftPanel);
        }

        private void UpdateStepIndicators()
        {
            foreach (Control c in leftPanel.Controls)
            {
                if (c is Label && c.Tag is int)
                {
                    int step = (int)c.Tag;
                    c.ForeColor = (step == currentStep)
                        ? Color.FromArgb(6, 182, 212)
                        : (step < currentStep ? Color.FromArgb(60, 130, 130) : Color.FromArgb(60, 80, 100));
                    c.Font = new Font("Segoe UI", 8.5f, step == currentStep ? FontStyle.Bold : FontStyle.Regular);
                }
            }
            leftPanel.Invalidate();
        }

        // ===== STEP 1: WELCOME =====
        private void ShowWelcome()
        {
            contentPanel.Controls.Clear();
            currentStep = 1;
            UpdateStepIndicators();

            Label title = MakeLabel("Bem-vindo ao WinToolKit!", new Font("Segoe UI", 17, FontStyle.Bold), Color.White, new Point(20, 20));
            contentPanel.Controls.Add(title);

            Label desc = MakeLabel(
                "Este assistente instalara o WinToolKit Professional em seu computador.\n\n" +
                "Conteudo incluido neste pacote:\n" +
                "  - WinToolKit.exe - Launcher com icone na bandeja\n" +
                "  - toolkit.ps1    - Motor de automacao Windows\n" +
                "  - Interface Web  - Painel de controle moderno\n\n" +
                "Clique em Avancar para continuar.",
                new Font("Segoe UI", 9.5f, FontStyle.Regular),
                Color.FromArgb(160, 170, 190),
                new Point(22, 75));
            desc.Size = new Size(440, 190);
            contentPanel.Controls.Add(desc);

            contentPanel.Controls.Add(MakeCyanBtn("Avancar  >>", new Point(340, 290), (s, e) => ShowPath()));
        }

        // ===== STEP 2: PATH =====
        private void ShowPath()
        {
            contentPanel.Controls.Clear();
            currentStep = 2;
            UpdateStepIndicators();

            contentPanel.Controls.Add(MakeLabel("Local de Instalacao", new Font("Segoe UI", 16, FontStyle.Bold), Color.White, new Point(20, 20)));
            contentPanel.Controls.Add(MakeLabel("O WinToolKit sera instalado na pasta abaixo.\nClique em Procurar para alterar o destino.", new Font("Segoe UI", 9.5f), Color.FromArgb(160, 170, 190), new Point(22, 68)));

            pathBox = new TextBox();
            pathBox.Text = targetDir;
            pathBox.Font = new Font("Segoe UI", 10);
            pathBox.BackColor = Color.FromArgb(25, 35, 55);
            pathBox.ForeColor = Color.White;
            pathBox.BorderStyle = BorderStyle.FixedSingle;
            pathBox.Location = new Point(22, 130);
            pathBox.Size = new Size(320, 28);
            contentPanel.Controls.Add(pathBox);

            Button browse = MakeDarkBtn("Procurar...", new Point(350, 129), (s, e) => {
                FolderBrowserDialog fbd = new FolderBrowserDialog();
                fbd.Description = "Selecione o destino da instalacao:";
                fbd.SelectedPath = targetDir;
                if (fbd.ShowDialog() == DialogResult.OK) { pathBox.Text = fbd.SelectedPath; targetDir = fbd.SelectedPath; }
            });
            browse.Size = new Size(100, 30);
            contentPanel.Controls.Add(browse);

            contentPanel.Controls.Add(MakeDarkBtn("<<  Voltar", new Point(190, 290), (s, e) => ShowWelcome()));
            contentPanel.Controls.Add(MakeCyanBtn("Instalar  >>", new Point(340, 290), (s, e) => { targetDir = pathBox.Text.Trim(); ShowInstalling(); }));
        }

        // ===== STEP 3: INSTALLING =====
        public void ShowInstalling()
        {
            contentPanel.Controls.Clear();
            currentStep = 3;
            UpdateStepIndicators();

            contentPanel.Controls.Add(MakeLabel("Instalando...", new Font("Segoe UI", 16, FontStyle.Bold), Color.White, new Point(20, 20)));

            progressBar = new ProgressBar();
            progressBar.Style = ProgressBarStyle.Continuous;
            progressBar.Size = new Size(440, 22);
            progressBar.Location = new Point(22, 90);
            progressBar.Maximum = 100;
            progressBar.Value = 0;
            contentPanel.Controls.Add(progressBar);

            progressStatus = MakeLabel("Iniciando...", new Font("Segoe UI", 9, FontStyle.Italic), Color.FromArgb(100, 200, 210), new Point(22, 120));
            contentPanel.Controls.Add(progressStatus);

            Thread t = new Thread(DoInstall);
            t.IsBackground = true;
            t.Start();
        }

        private void DoInstall()
        {
            Log("Thread DoInstall iniciada.");
            Log("Pasta de destino: " + targetDir);
            try
            {
                SetProgress(2, "Fechando versoes antigas em execucao...");
                Log("Fechando versoes antigas...");
                
                // 1. Fechar a janela do navegador (Edge/Chrome em modo app)
                int currentPid = Process.GetCurrentProcess().Id;
                foreach (Process p in Process.GetProcesses())
                {
                    try {
                        if (p.Id != currentPid && !string.IsNullOrEmpty(p.MainWindowTitle) && p.MainWindowTitle.Contains("WinToolKit")) {
                            Log("Fechando janela do WinToolKit: " + p.MainWindowTitle);
                            p.CloseMainWindow();
                            p.WaitForExit(1000);
                        }
                    } catch (Exception ex) {
                        Log("Erro ao fechar janela de processo: " + ex.Message);
                    }
                }

                // 2. Matar o processo WinToolKit (Launcher) e seus filhos (backend)
                try {
                    Log("Finalizando WinToolKit.exe via C#...");
                    foreach (Process proc in Process.GetProcessesByName("WinToolKit")) {
                        if (proc.Id != currentPid) {
                            try {
                                proc.Kill();
                                proc.WaitForExit(3000);
                            } catch (Exception pk) { Log("Falha kill direto: " + pk.Message); }
                        }
                    }
                    Log("Executando taskkill backup para WinToolKit.exe...");
                    ProcessStartInfo psi = new ProcessStartInfo("taskkill", "/F /T /IM WinToolKit.exe");
                    psi.CreateNoWindow = true;
                    psi.UseShellExecute = false;
                    Process pkProc = Process.Start(psi);
                    if (pkProc != null) {
                        pkProc.WaitForExit(3000);
                    }
                    Thread.Sleep(1000); // Give OS time to release file handles
                } catch (Exception ex) {
                    Log("Erro ao finalizar WinToolKit: " + ex.Message);
                }

                SetProgress(5, "Criando pasta de instalacao...");
                Log("Criando pasta: " + targetDir);
                if (!Directory.Exists(targetDir)) {
                    Directory.CreateDirectory(targetDir);
                    Log("Pasta de destino criada.");
                } else {
                    Log("Pasta de destino ja existe.");
                }

                string webDir = Path.Combine(targetDir, "web");
                Log("Criando pasta web: " + webDir);
                if (!Directory.Exists(webDir)) {
                    Directory.CreateDirectory(webDir);
                    Log("Pasta web criada.");
                }

                // Helper to write files with retry
                Action<string, string> WriteFileWithRetry = (path, b64) => {
                    for (int i = 0; i < 5; i++) {
                        try {
                            File.WriteAllBytes(path, Convert.FromBase64String(b64));
                            Log("Gravado com sucesso: " + path);
                            return;
                        } catch (IOException ioEx) {
                            Log(string.Format("Tentativa {0} falhou para {1}: {2}", i+1, path, ioEx.Message));
                            Thread.Sleep(1500);
                        }
                    }
                    // Last try without catch to let it throw and fail the install
                    File.WriteAllBytes(path, Convert.FromBase64String(b64));
                };

                SetProgress(20, "Extraindo WinToolKit.exe...");
                Log("Extraindo WinToolKit.exe...");
                WriteFileWithRetry(Path.Combine(targetDir, "WinToolKit.exe"), B64_LAUNCHER);

                SetProgress(40, "Extraindo toolkit.ps1...");
                Log("Extraindo toolkit.ps1...");
                WriteFileWithRetry(Path.Combine(targetDir, "toolkit.ps1"), B64_TOOLKIT);

                SetProgress(55, "Extraindo interface Web — index.html...");
                Log("Extraindo index.html...");
                WriteFileWithRetry(Path.Combine(webDir, "index.html"), B64_HTML);

                SetProgress(68, "Extraindo interface Web — style.css...");
                Log("Extraindo style.css...");
                WriteFileWithRetry(Path.Combine(webDir, "style.css"), B64_CSS);
                Log("style.css extraido.");

                SetProgress(80, "Extraindo interface Web — app.js...");
                Log("Extraindo app.js...");
                WriteFileWithRetry(Path.Combine(webDir, "app.js"), B64_JS);
                Log("app.js extraido.");

                SetProgress(88, "Extraindo Desinstalar.exe...");
                Log("Extraindo Desinstalar.exe...");
                WriteFileWithRetry(Path.Combine(targetDir, "Desinstalar.exe"), B64_UNINSTALLER);
                Log("Desinstalar.exe extraido.");

                SetProgress(92, "Finalizando extraindo...");
                Thread.Sleep(300);

                SetProgress(100, "Instalacao concluida!");
                Thread.Sleep(400);

                Log("Chamando ShowFinish na thread UI...");
                this.Invoke((MethodInvoker)(() => {
                    Log("ShowFinish sendo executado.");
                    ShowFinish();
                }));
            }
            catch (Exception ex)
            {
                Log("ERRO CRITICO DOINSTALL: " + ex.ToString());
                if (!this.IsDisposed && this.IsHandleCreated)
                {
                    try {
                        this.Invoke((MethodInvoker)(() => {
                            MessageBox.Show(string.Format("Erro na instalacao:\n{0}", ex.Message), "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            ShowPath();
                        }));
                    } catch (Exception invEx) {
                        Log("Erro ao invocar dialog de erro: " + invEx.Message);
                        MessageBox.Show(string.Format("Erro na instalacao:\n{0}", ex.Message), "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                } else {
                    MessageBox.Show(string.Format("Erro na instalacao:\n{0}", ex.Message), "Erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void SetProgress(int val, string msg)
        {
            if (this.IsDisposed) return;
            try
            {
                this.Invoke((MethodInvoker)(() => {
                    progressBar.Value = val;
                    progressStatus.Text = msg;
                }));
            }
            catch (Exception ex)
            {
                Log("Erro em SetProgress (" + val + ", " + msg + "): " + ex.Message);
            }
        }

        // ===== STEP 4: FINISH =====
        private void ShowFinish()
        {
            if (IsSilentUpdate) {
                // Auto-finish without showing the screen
                chkDesktop = new CheckBox() { Checked = false };
                chkStartMenu = new CheckBox() { Checked = false };
                chkRunNow = new CheckBox() { Checked = true };
                OnFinish(null, null);
                return;
            }

            contentPanel.Controls.Clear();
            currentStep = 4;
            UpdateStepIndicators();

            contentPanel.Controls.Add(MakeLabel("[OK]  Instalacao Concluida!", new Font("Segoe UI", 16, FontStyle.Bold), Color.FromArgb(6, 182, 212), new Point(20, 20)));
            contentPanel.Controls.Add(MakeLabel(
                string.Format("WinToolKit instalado em:\n{0}", targetDir),
                new Font("Segoe UI", 9.5f), Color.FromArgb(160, 170, 190), new Point(22, 68)));

            chkDesktop = MakeCheck("Criar atalho na Area de Trabalho", new Point(30, 130), true);
            chkStartMenu = MakeCheck("Criar atalho no Menu Iniciar", new Point(30, 160), true);
            chkRunNow = MakeCheck("Executar WinToolKit agora", new Point(30, 190), true);
            chkRunNow.ForeColor = Color.FromArgb(6, 182, 212);
            chkRunNow.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);

            contentPanel.Controls.Add(chkDesktop);
            contentPanel.Controls.Add(chkStartMenu);
            contentPanel.Controls.Add(chkRunNow);

            contentPanel.Controls.Add(MakeCyanBtn("Concluir", new Point(340, 290), OnFinish));
        }

        private void OnFinish(object sender, EventArgs e)
        {
            Log("OnFinish iniciado.");
            try
            {
                string targetExe = Path.Combine(targetDir, "WinToolKit.exe");

                if (chkDesktop.Checked)
                {
                    Log("Criando atalho na Area de Trabalho.");
                    string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    CreateShortcut(Path.Combine(desktop, "WinToolKit.lnk"), targetExe, targetDir);
                }

                if (chkStartMenu.Checked)
                {
                    Log("Criando atalhos no Menu Iniciar.");
                    string sm = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "WinToolKit");
                    if (!Directory.Exists(sm)) Directory.CreateDirectory(sm);
                    CreateShortcut(Path.Combine(sm, "WinToolKit.lnk"), targetExe, targetDir);
                    CreateShortcut(Path.Combine(sm, "Desinstalar.lnk"), Path.Combine(targetDir, "Desinstalar.exe"), targetDir);
                }

                try {
                    Log("Registrando no Painel de Controle...");
                    using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinToolKit"))
                    {
                        key.SetValue("DisplayName", "WinToolKit");
                        key.SetValue("DisplayIcon", targetExe);
                        key.SetValue("UninstallString", Path.Combine(targetDir, "Desinstalar.exe"));
                        key.SetValue("DisplayVersion", "1.0.0");
                        key.SetValue("Publisher", "Suporte TI");
                        key.SetValue("InstallLocation", targetDir);
                    }
                    Log("Registro concluido.");
                } catch (Exception exReg) { 
                    Log("Erro ao registrar Uninstall: " + exReg.Message);
                }

                if (chkRunNow.Checked)
                {
                    Log("Executando WinToolKit agora...");
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = targetExe;
                    psi.WorkingDirectory = targetDir;
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                    Log("Execucao iniciada.");
                }
            }
            catch (Exception ex)
            {
                Log("ERRO EM ONFINISH: " + ex.ToString());
                MessageBox.Show(string.Format("Aviso ao criar atalhos:\n{0}", ex.Message), "WinToolKit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            Log("Fechando form.");
            this.Close();
        }

        private void CreateShortcut(string lnkPath, string target, string workDir)
        {
            string ps = string.Format(
                "`$s=(New-Object -ComObject WScript.Shell).CreateShortcut('{0}');`$s.TargetPath='{1}';`$s.WorkingDirectory='{2}';`$s.IconLocation='{1},0';`$s.Save()",
                lnkPath, target, workDir);
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -Command \"{0}\"", ps);
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            Process proc = Process.Start(psi);
            proc.WaitForExit();
        }

        // ===== UI HELPERS =====
        private Label MakeLabel(string text, Font font, Color color, Point loc)
        {
            Label lbl = new Label();
            lbl.Text = text;
            lbl.Font = font;
            lbl.ForeColor = color;
            lbl.Location = loc;
            lbl.AutoSize = true;
            lbl.BackColor = Color.Transparent;
            return lbl;
        }

        private Button MakeCyanBtn(string text, Point loc, EventHandler onClick)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Size = new Size(130, 36);
            btn.Location = loc;
            btn.FlatStyle = FlatStyle.Flat;
            btn.BackColor = Color.FromArgb(6, 182, 212);
            btn.ForeColor = Color.White;
            btn.Font = new Font("Segoe UI", 10, FontStyle.Bold);
            btn.Cursor = Cursors.Hand;
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(8, 145, 178);
            btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(14, 116, 144);
            btn.Click += onClick;
            return btn;
        }

        private Button MakeDarkBtn(string text, Point loc, EventHandler onClick)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Size = new Size(115, 36);
            btn.Location = loc;
            btn.FlatStyle = FlatStyle.Flat;
            btn.BackColor = Color.FromArgb(30, 41, 59);
            btn.ForeColor = Color.FromArgb(210, 215, 225);
            btn.Font = new Font("Segoe UI", 10);
            btn.Cursor = Cursors.Hand;
            btn.FlatAppearance.BorderColor = Color.FromArgb(75, 85, 100);
            btn.FlatAppearance.BorderSize = 1;
            btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(51, 65, 85);
            btn.Click += onClick;
            return btn;
        }

        private CheckBox MakeCheck(string text, Point loc, bool chk)
        {
            CheckBox cb = new CheckBox();
            cb.Text = text;
            cb.Font = new Font("Segoe UI", 9.5f);
            cb.ForeColor = Color.White;
            cb.BackColor = Color.Transparent;
            cb.Checked = chk;
            cb.Location = loc;
            cb.AutoSize = true;
            cb.Cursor = Cursors.Hand;
            return cb;
        }

        private static bool IsAdministrator()
        {
            WindowsIdentity id = WindowsIdentity.GetCurrent();
            WindowsPrincipal p = new WindowsPrincipal(id);
            return p.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private static void ElevateAndExit()
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Assembly.GetExecutingAssembly().Location;
            psi.Verb = "runas";
            psi.UseShellExecute = true;
            try { Process.Start(psi); } catch { }
            Environment.Exit(0);
        }
    }
}
"@

# Write the generated C# to file
Set-Content -Path $installerSrc -Value $csCode -Encoding UTF8
Write-Host "  [OK] Codigo-fonte gerado: $installerSrc" -ForegroundColor Green
Write-Host "       Tamanho: $([Math]::Round((Get-Item $installerSrc).Length / 1KB, 1)) KB" -ForegroundColor Gray

# ---- STEP 4: Compile self-contained Instalar.exe ----
Write-Host "[4/4] Compilando Instalar.exe auto-contido..." -ForegroundColor Yellow

$installerOut = Join-Path $base "Instalar.exe"
$instArgs = "/target:winexe /out:`"$installerOut`" /win32icon:`"$icoPath`" /optimize+ /reference:System.Windows.Forms.dll,System.Drawing.dll `"$installerSrc`""

$result2 = Start-Process -FilePath $csc -ArgumentList $instArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\csc_inst_out.txt" -RedirectStandardError "$env:TEMP\csc_inst_err.txt"
$instOut = Get-Content "$env:TEMP\csc_inst_out.txt" -Raw -ErrorAction SilentlyContinue
$instErr = Get-Content "$env:TEMP\csc_inst_err.txt" -Raw -ErrorAction SilentlyContinue

if ($result2.ExitCode -ne 0 -or -not (Test-Path $installerOut)) {
    Write-Host "ERRO ao compilar Instalar.exe:" -ForegroundColor Red
    Write-Host $instOut -ForegroundColor Red
    Write-Host $instErr -ForegroundColor Red
    exit 1
}

# Assinar digitalmente o Instalador Auto-Contido final
Sign-Executable -filePath $installerOut

$sizeMB = [Math]::Round((Get-Item $installerOut).Length / 1MB, 2)
Write-Host "  [OK] Instalar.exe gerado com sucesso!" -ForegroundColor Green
Write-Host "       Tamanho: $sizeMB MB (inclui TODOS os arquivos)" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   PRONTO! Instalar.exe esta na pasta:" -ForegroundColor Cyan
Write-Host "   $base" -ForegroundColor White
Write-Host "   Distribua APENAS o arquivo Instalar.exe" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
