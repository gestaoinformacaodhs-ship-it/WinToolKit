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
        private Mutex singleInstanceMutex;
        private const string MutexName = "WinToolKit_SingleInstance_Mutex";

        [STAThread]
        public static void Main(string[] args)
        {
            // 1. Check for Admin rights
            if (!IsAdministrator())
            {
                ElevateAndExit();
                return;
            }

            // 2. Prevent multiple instances
            bool createdNew;
            using (Mutex mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show(
                        "O WinToolKit já está em execução no sistema. Verifique a bandeja do sistema (perto do relógio).",
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
        }

        public Launcher()
        {
            appDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            scriptPath = Path.Combine(appDir, "toolkit.ps1");

            // Verify backend script exists
            if (!File.Exists(scriptPath))
            {
                // Fallback to check parent folder (in case we are running in a build/src subfolder)
                string fallbackPath = Path.Combine(Directory.GetParent(appDir).FullName, "toolkit.ps1");
                if (File.Exists(fallbackPath))
                {
                    scriptPath = fallbackPath;
                    appDir = Directory.GetParent(appDir).FullName;
                }
                else
                {
                    MessageBox.Show(
                        string.Format("Erro Crítico: O arquivo backend 'toolkit.ps1' não foi encontrado em '{0}'.\nPor favor, reinstale a ferramenta.", scriptPath),
                        "WinToolKit - Erro",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    ExitApplication();
                    return;
                }
            }

            // Initialize System Tray
            InitializeTray();

            // Start backend
            StartBackend();

            // Open Dashboard
            OpenDashboard();

            // Show startup notification
            trayIcon.ShowBalloonTip(
                3000,
                "WinToolKit Ativo",
                "O painel de suporte foi inicializado em segundo plano. Clique no ícone para acessar.",
                ToolTipIcon.Info
            );
        }

        private void InitializeTray()
        {
            trayMenu = new ContextMenu();
            trayMenu.MenuItems.Add(new MenuItem("Abrir Painel", OnOpenDashboard) { DefaultItem = true, BarBreak = false });
            trayMenu.MenuItems.Add(new MenuItem("Reiniciar Servidor", OnRestartServer));
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add(new MenuItem("Sair do WinToolKit", OnExit));

            trayIcon = new NotifyIcon();
            trayIcon.Text = "WinToolKit - Suporte Técnico";
            trayIcon.Icon = CreateTrayIcon();
            trayIcon.ContextMenu = trayMenu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += OnOpenDashboard;
        }

        private static Icon CreateTrayIcon()
        {
            try
            {
                using (Bitmap bmp = new Bitmap(16, 16))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                        
                        // Draw beautiful gradient circle
                        using (var brush = new System.Drawing.Drawing2D.LinearGradientBrush(
                            new Point(0, 0), new Point(16, 16),
                            Color.FromArgb(6, 182, 212),  // Cyan
                            Color.FromArgb(99, 102, 241) // Indigo
                        ))
                        {
                            g.FillEllipse(brush, 0, 0, 15, 15);
                        }

                        // Draw a sleek white ">_" terminal prompt
                        using (var pen = new Pen(Color.White, 1.5f))
                        {
                            g.DrawLine(pen, 4, 4, 7, 7);
                            g.DrawLine(pen, 7, 7, 4, 10);
                            g.DrawLine(pen, 7, 10, 11, 10);
                        }
                    }
                    return Icon.FromHandle(bmp.GetHicon());
                }
            }
            catch
            {
                // Fallback to default system icon if drawing fails
                return SystemIcons.Application;
            }
        }

        private void StartBackend()
        {
            try
            {
                // Stop any running backend first
                KillBackendProcess();

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                // Bypass execution policy and run script silently in background
                psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\"", scriptPath);
                psi.WorkingDirectory = appDir;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                backendProcess = Process.Start(psi);
                
                // Give it a brief moment to boot up
                Thread.Sleep(1000);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    string.Format("Falha ao iniciar o backend do PowerShell:\n{0}", ex.Message),
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
                // Launch Microsoft Edge in App Mode (chromeless, native app visual)
                // Window size is set to a spacious, modern layout
                string arguments = "--app=http://localhost:4040/ --window-size=1280,720";
                
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "msedge.exe";
                psi.Arguments = arguments;
                
                try
                {
                    Process.Start(psi);
                }
                catch
                {
                    // Fallback to default browser if msedge launch fails
                    Process.Start("http://localhost:4040/");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    string.Format("Erro ao abrir a interface gráfica do painel:\n{0}", ex.Message),
                    "WinToolKit - Erro",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
            }
        }

        private void KillBackendProcess()
        {
            // First, kill the managed process reference
            if (backendProcess != null && !backendProcess.HasExited)
            {
                try
                {
                    backendProcess.Kill();
                    backendProcess.Dispose();
                }
                catch {}
                backendProcess = null;
            }

            // Fallback insurance: ensure all orphaned instances running toolkit.ps1 on this port are terminated
            try
            {
                Process[] psProcesses = Process.GetProcessesByName("powershell");
                foreach (var proc in psProcesses)
                {
                    try
                    {
                        string cmdLine = GetCommandLine(proc);
                        if (cmdLine != null && cmdLine.Contains("toolkit.ps1"))
                        {
                            proc.Kill();
                        }
                    }
                    catch {}
                }
            }
            catch {}
        }

        private string GetCommandLine(Process process)
        {
            try
            {
                using (var searcher = new System.Management.ManagementObjectSearcher(
                    string.Format("SELECT CommandLine FROM Win32_Process WHERE ProcessId = {0}", process.Id)))
                {
                    foreach (var obj in searcher.Get())
                    {
                        object val = obj["CommandLine"];
                        return val != null ? val.ToString() : null;
                    }
                }
            }
            catch {}
            return null;
        }

        private void OnOpenDashboard(object sender, EventArgs e)
        {
            OpenDashboard();
        }

        private void OnRestartServer(object sender, EventArgs e)
        {
            trayIcon.ShowBalloonTip(
                2000,
                "WinToolKit",
                "Reiniciando o servidor interno em segundo plano...",
                ToolTipIcon.Info
            );
            StartBackend();
            Thread.Sleep(1000);
            OpenDashboard();
        }

        private void OnExit(object sender, EventArgs e)
        {
            ExitApplication();
        }

        private void ExitApplication()
        {
            // Clean up resources
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
            }

            KillBackendProcess();
            Application.ExitThread();
            Environment.Exit(0);
        }

        // --- Helper Methods ---

        private static bool IsAdministrator()
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        private static void ElevateAndExit()
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Assembly.GetExecutingAssembly().Location;
            psi.Verb = "runas"; // Requests UAC self-elevation
            psi.UseShellExecute = true;

            try
            {
                Process.Start(psi);
            }
            catch (Exception)
            {
                MessageBox.Show(
                    "Esta aplicação necessita de permissões de Administrador para ser executada.",
                    "WinToolKit - Permissão Requerida",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
            }
            Environment.Exit(0);
        }
    }
}
