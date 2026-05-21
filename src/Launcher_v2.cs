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
