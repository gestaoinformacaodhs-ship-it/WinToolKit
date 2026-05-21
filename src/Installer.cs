using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

namespace WinToolKit
{
    public class InstallerForm : Form
    {
        private string sourceDir;
        private string targetDir = @"C:\Program Files\WinToolKit";
        private int currentStep = 1;

        // Custom UI Controls
        private Panel headerPanel;
        private Panel leftBrandPanel;
        private Panel contentPanel;
        private Label titleLabel;
        private Button closeButton;

        // Welcome Step Controls
        private Label welcomeTitleLabel;
        private Label welcomeDescLabel;
        private Button nextButton;

        // Path Step Controls
        private Label pathTitleLabel;
        private TextBox pathTextBox;
        private Button browseButton;
        private Button installButton;
        private Button backButton;

        // Installing Step Controls
        private Label progressTitleLabel;
        private ProgressBar progressBar;
        private Label progressStatusLabel;

        // Finish Step Controls
        private Label finishTitleLabel;
        private CheckBox desktopShortcutCheck;
        private CheckBox startMenuShortcutCheck;
        private CheckBox runNowCheck;
        private Button finishButton;

        // Draggable window helpers
        private bool drag = false;
        private Point startPoint = new Point(0, 0);

        [STAThread]
        public static void Main()
        {
            if (!IsAdministrator())
            {
                ElevateAndExit();
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }

        public InstallerForm()
        {
            sourceDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            
            // Set form attributes
            this.Size = new Size(650, 400);
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(11, 15, 25); // Sleek Dark Canvas

            // Initialize Header
            InitializeHeader();

            // Initialize Left Branding Bar
            InitializeBrandingBar();

            // Initialize Content panel
            contentPanel = new Panel();
            contentPanel.Size = new Size(470, 310);
            contentPanel.Location = new Point(180, 50);
            this.Controls.Add(contentPanel);

            // Show Step 1 (Welcome)
            ShowStep1Welcome();
        }

        private void InitializeHeader()
        {
            headerPanel = new Panel();
            headerPanel.Size = new Size(650, 50);
            headerPanel.Location = new Point(0, 0);
            headerPanel.BackColor = Color.FromArgb(17, 24, 39); // Card Header Background
            headerPanel.MouseDown += Header_MouseDown;
            headerPanel.MouseMove += Header_MouseMove;
            headerPanel.MouseUp += Header_MouseUp;

            titleLabel = new Label();
            titleLabel.Text = "Instalação - WinToolKit Professional";
            titleLabel.Font = new Font("Segoe UI", 11, FontStyle.Bold);
            titleLabel.ForeColor = Color.White;
            titleLabel.Location = new Point(15, 13);
            titleLabel.AutoSize = true;
            headerPanel.Controls.Add(titleLabel);

            closeButton = new Button();
            closeButton.Text = "✕";
            closeButton.Font = new Font("Segoe UI", 12, FontStyle.Bold);
            closeButton.ForeColor = Color.FromArgb(156, 163, 175);
            closeButton.BackColor = Color.Transparent;
            closeButton.FlatStyle = FlatStyle.Flat;
            closeButton.FlatAppearance.BorderSize = 0;
            closeButton.FlatAppearance.MouseOverBackColor = Color.FromArgb(239, 68, 68);
            closeButton.FlatAppearance.MouseDownBackColor = Color.FromArgb(185, 28, 28);
            closeButton.Size = new Size(40, 50);
            closeButton.Location = new Point(610, 0);
            closeButton.Click += (s, e) => this.Close();
            headerPanel.Controls.Add(closeButton);

            this.Controls.Add(headerPanel);
        }

        private void InitializeBrandingBar()
        {
            leftBrandPanel = new Panel();
            leftBrandPanel.Size = new Size(180, 350);
            leftBrandPanel.Location = new Point(0, 50);
            leftBrandPanel.BackColor = Color.FromArgb(17, 24, 39);
            leftBrandPanel.Paint += LeftBrandPanel_Paint;

            Label brandText = new Label();
            brandText.Text = "WINTOOLKIT";
            brandText.Font = new Font("Segoe UI", 16, FontStyle.Bold);
            brandText.ForeColor = Color.White;
            brandText.Location = new Point(15, 30);
            brandText.AutoSize = true;
            leftBrandPanel.Controls.Add(brandText);

            Label brandSubText = new Label();
            brandSubText.Text = "DHS SUPORTE";
            brandSubText.Font = new Font("Segoe UI", 8, FontStyle.Regular);
            brandSubText.ForeColor = Color.FromArgb(6, 182, 212); // Cyan
            brandSubText.Location = new Point(17, 60);
            brandSubText.AutoSize = true;
            leftBrandPanel.Controls.Add(brandSubText);

            this.Controls.Add(leftBrandPanel);
        }

        private void LeftBrandPanel_Paint(object sender, PaintEventArgs e)
        {
            // Paint dynamic gradient on Left panel for premium look
            LinearGradientBrush brush = new LinearGradientBrush(
                new Point(0, 0), new Point(180, 350),
                Color.FromArgb(17, 24, 39),
                Color.FromArgb(30, 41, 59)
            );
            e.Graphics.FillRectangle(brush, 0, 0, 180, 350);

            // Draw a separator border
            using (Pen pen = new Pen(Color.FromArgb(6, 182, 212), 1))
            {
                e.Graphics.DrawLine(pen, 179, 0, 179, 350);
            }
        }

        private void ClearContentPanel()
        {
            contentPanel.Controls.Clear();
        }

        // --- STEP 1: WELCOME SCREEN ---
        private void ShowStep1Welcome()
        {
            ClearContentPanel();
            currentStep = 1;

            welcomeTitleLabel = new Label();
            welcomeTitleLabel.Text = "Bem-vindo à Instalação do WinToolKit";
            welcomeTitleLabel.Font = new Font("Segoe UI", 15, FontStyle.Bold);
            welcomeTitleLabel.ForeColor = Color.White;
            welcomeTitleLabel.Location = new Point(25, 30);
            welcomeTitleLabel.Size = new Size(420, 40);
            contentPanel.Controls.Add(welcomeTitleLabel);

            welcomeDescLabel = new Label();
            welcomeDescLabel.Text = "Este assistente guiará você na instalação do WinToolKit - o conjunto profissional de automação e diagnóstico para técnicos de suporte TI.\n\nO toolkit será implantado de forma nativa e integrada ao Windows, criando atalhos funcionais e registrando os arquivos do sistema na sua máquina.";
            welcomeDescLabel.Font = new Font("Segoe UI", 10, FontStyle.Regular);
            welcomeDescLabel.ForeColor = Color.FromArgb(156, 163, 175); // Slate
            welcomeDescLabel.Location = new Point(27, 85);
            welcomeDescLabel.Size = new Size(410, 130);
            contentPanel.Controls.Add(welcomeDescLabel);

            nextButton = CreateCyanButton("Avançar", new Point(310, 250), OnNextToPath);
            contentPanel.Controls.Add(nextButton);
        }

        private void OnNextToPath(object sender, EventArgs e)
        {
            ShowStep2Path();
        }

        // --- STEP 2: PATH SELECTION SCREEN ---
        private void ShowStep2Path()
        {
            ClearContentPanel();
            currentStep = 2;

            pathTitleLabel = new Label();
            pathTitleLabel.Text = "Escolha o local de instalação";
            pathTitleLabel.Font = new Font("Segoe UI", 14, FontStyle.Bold);
            pathTitleLabel.ForeColor = Color.White;
            pathTitleLabel.Location = new Point(25, 30);
            pathTitleLabel.Size = new Size(420, 35);
            contentPanel.Controls.Add(pathTitleLabel);

            Label pathDesc = new Label();
            pathDesc.Text = "O WinToolKit será instalado na pasta listada abaixo. Para instalar em outra pasta diferente, clique em Procurar.";
            pathDesc.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);
            pathDesc.ForeColor = Color.FromArgb(156, 163, 175);
            pathDesc.Location = new Point(27, 75);
            pathDesc.Size = new Size(410, 50);
            contentPanel.Controls.Add(pathDesc);

            pathTextBox = new TextBox();
            pathTextBox.Text = targetDir;
            pathTextBox.Font = new Font("Segoe UI", 10);
            pathTextBox.BackColor = Color.FromArgb(30, 41, 59);
            pathTextBox.ForeColor = Color.White;
            pathTextBox.BorderStyle = BorderStyle.FixedSingle;
            pathTextBox.Location = new Point(27, 140);
            pathTextBox.Size = new Size(300, 26);
            contentPanel.Controls.Add(pathTextBox);

            browseButton = CreateDarkButton("Procurar...", new Point(337, 139), OnBrowsePath);
            browseButton.Size = new Size(90, 28);
            contentPanel.Controls.Add(browseButton);

            backButton = CreateDarkButton("Voltar", new Point(190, 250), OnBackToWelcome);
            contentPanel.Controls.Add(backButton);

            installButton = CreateCyanButton("Instalar", new Point(310, 250), OnStartInstall);
            contentPanel.Controls.Add(installButton);
        }

        private void OnBackToWelcome(object sender, EventArgs e)
        {
            ShowStep1Welcome();
        }

        private void OnBrowsePath(object sender, EventArgs e)
        {
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Selecione a pasta de instalação do WinToolKit:";
                fbd.SelectedPath = targetDir;
                if (fbd.ShowDialog() == DialogResult.OK)
                {
                    pathTextBox.Text = fbd.SelectedPath;
                    targetDir = fbd.SelectedPath;
                }
            }
        }

        private void OnStartInstall(object sender, EventArgs e)
        {
            targetDir = pathTextBox.Text.Trim();
            ShowStep3Installing();
        }

        // --- STEP 3: INSTALLING PROGRESS SCREEN ---
        private void ShowStep3Installing()
        {
            ClearContentPanel();
            currentStep = 3;

            progressTitleLabel = new Label();
            progressTitleLabel.Text = "Instalando o WinToolKit...";
            progressTitleLabel.Font = new Font("Segoe UI", 14, FontStyle.Bold);
            progressTitleLabel.ForeColor = Color.White;
            progressTitleLabel.Location = new Point(25, 30);
            progressTitleLabel.Size = new Size(420, 35);
            contentPanel.Controls.Add(progressTitleLabel);

            progressBar = new ProgressBar();
            progressBar.Style = ProgressBarStyle.Continuous;
            progressBar.Size = new Size(400, 25);
            progressBar.Location = new Point(27, 100);
            // Customize look: custom Cyan painting for progress bar will be handled in separate thread or we use default WinForms bar
            contentPanel.Controls.Add(progressBar);

            progressStatusLabel = new Label();
            progressStatusLabel.Text = "Aguarde, copiando arquivos do sistema...";
            progressStatusLabel.Font = new Font("Segoe UI", 9.5f, FontStyle.Italic);
            progressStatusLabel.ForeColor = Color.FromArgb(156, 163, 175);
            progressStatusLabel.Location = new Point(27, 140);
            progressStatusLabel.Size = new Size(400, 25);
            contentPanel.Controls.Add(progressStatusLabel);

            // Execute installation asynchronously in a worker thread
            Thread worker = new Thread(DoInstallWork);
            worker.Start();
        }

        private void DoInstallWork()
        {
            try
            {
                UpdateProgress(10, "Criando diretório do sistema...");
                Thread.Sleep(400);

                if (!Directory.Exists(targetDir))
                {
                    Directory.CreateDirectory(targetDir);
                }

                UpdateProgress(30, "Copiando executáveis e scripts...");
                Thread.Sleep(300);

                // Copy files
                string sourceExe = Path.Combine(sourceDir, "WinToolKit.exe");
                string sourcePs1 = Path.Combine(sourceDir, "toolkit.ps1");
                
                if (File.Exists(sourceExe))
                {
                    File.Copy(sourceExe, Path.Combine(targetDir, "WinToolKit.exe"), true);
                }
                if (File.Exists(sourcePs1))
                {
                    File.Copy(sourcePs1, Path.Combine(targetDir, "toolkit.ps1"), true);
                }

                UpdateProgress(50, "Copiando interface Web e assets...");
                Thread.Sleep(300);

                string sourceWebDir = Path.Combine(sourceDir, "web");
                string targetWebDir = Path.Combine(targetDir, "web");

                if (Directory.Exists(sourceWebDir))
                {
                    CopyDirectory(sourceWebDir, targetWebDir);
                }

                UpdateProgress(75, "Registrando atalhos no Windows...");
                Thread.Sleep(400);

                // Shortcuts will be generated in Step 4 Finish callback to reflect checkboxes

                UpdateProgress(100, "Instalação concluída com sucesso!");
                Thread.Sleep(200);

                this.Invoke((MethodInvoker)delegate {
                    ShowStep4Finish();
                });
            }
            catch (Exception ex)
            {
                this.Invoke((MethodInvoker)delegate {
                    MessageBox.Show(
                        string.Format("Erro durante a instalação:\n{0}", ex.Message),
                        "Instalação Falhou",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    ShowStep2Path();
                });
            }
        }

        private void UpdateProgress(int value, string statusText)
        {
            if (this.IsDisposed) return;
            this.Invoke((MethodInvoker)delegate {
                progressBar.Value = value;
                progressStatusLabel.Text = statusText;
            });
        }

        private void CopyDirectory(string source, string target)
        {
            if (!Directory.Exists(target))
            {
                Directory.CreateDirectory(target);
            }

            foreach (string file in Directory.GetFiles(source))
            {
                string dest = Path.Combine(target, Path.GetFileName(file));
                File.Copy(file, dest, true);
            }

            foreach (string folder in Directory.GetDirectories(source))
            {
                string dest = Path.Combine(target, Path.GetFileName(folder));
                CopyDirectory(folder, dest);
            }
        }

        // --- STEP 4: FINISH SCREEN ---
        private void ShowStep4Finish()
        {
            ClearContentPanel();
            currentStep = 4;

            finishTitleLabel = new Label();
            finishTitleLabel.Text = "Instalação finalizada!";
            finishTitleLabel.Font = new Font("Segoe UI", 15, FontStyle.Bold);
            finishTitleLabel.ForeColor = Color.White;
            finishTitleLabel.Location = new Point(25, 30);
            finishTitleLabel.Size = new Size(420, 35);
            contentPanel.Controls.Add(finishTitleLabel);

            Label successLabel = new Label();
            successLabel.Text = "O WinToolKit foi instalado com sucesso em seu sistema.\n\nEscolha abaixo os atalhos adicionais que você deseja criar:";
            successLabel.Font = new Font("Segoe UI", 10, FontStyle.Regular);
            successLabel.ForeColor = Color.FromArgb(156, 163, 175);
            successLabel.Location = new Point(27, 75);
            successLabel.Size = new Size(410, 60);
            contentPanel.Controls.Add(successLabel);

            desktopShortcutCheck = new CheckBox();
            desktopShortcutCheck.Text = "Criar atalho na Área de Trabalho (Desktop)";
            desktopShortcutCheck.Font = new Font("Segoe UI", 9.5f);
            desktopShortcutCheck.ForeColor = Color.White;
            desktopShortcutCheck.Checked = true;
            desktopShortcutCheck.Location = new Point(35, 145);
            desktopShortcutCheck.Size = new Size(380, 25);
            contentPanel.Controls.Add(desktopShortcutCheck);

            startMenuShortcutCheck = new CheckBox();
            startMenuShortcutCheck.Text = "Criar atalho no Menu Iniciar (Programas)";
            startMenuShortcutCheck.Font = new Font("Segoe UI", 9.5f);
            startMenuShortcutCheck.ForeColor = Color.White;
            startMenuShortcutCheck.Checked = true;
            startMenuShortcutCheck.Location = new Point(35, 175);
            startMenuShortcutCheck.Size = new Size(380, 25);
            contentPanel.Controls.Add(startMenuShortcutCheck);

            runNowCheck = new CheckBox();
            runNowCheck.Text = "Executar o WinToolKit agora";
            runNowCheck.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            runNowCheck.ForeColor = Color.FromArgb(6, 182, 212); // Cyan
            runNowCheck.Checked = true;
            runNowCheck.Location = new Point(35, 205);
            runNowCheck.Size = new Size(380, 25);
            contentPanel.Controls.Add(runNowCheck);

            finishButton = CreateCyanButton("Concluir", new Point(310, 250), OnFinish);
            contentPanel.Controls.Add(finishButton);
        }

        private void OnFinish(object sender, EventArgs e)
        {
            try
            {
                string targetExe = Path.Combine(targetDir, "WinToolKit.exe");

                // 1. Create Desktop Shortcut
                if (desktopShortcutCheck.Checked)
                {
                    string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string shortcutPath = Path.Combine(desktopPath, "WinToolKit.lnk");
                    CreateWindowsShortcut(shortcutPath, targetExe, targetDir);
                }

                // 2. Create Start Menu Shortcut
                if (startMenuShortcutCheck.Checked)
                {
                    string startMenuPath = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), 
                        "WinToolKit"
                    );
                    if (!Directory.Exists(startMenuPath))
                    {
                        Directory.CreateDirectory(startMenuPath);
                    }
                    string shortcutPath = Path.Combine(startMenuPath, "WinToolKit.lnk");
                    CreateWindowsShortcut(shortcutPath, targetExe, targetDir);
                }

                // 3. Launch App if requested
                if (runNowCheck.Checked)
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = targetExe;
                    psi.WorkingDirectory = targetDir;
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    string.Format("Erro ao registrar atalhos:\n{0}", ex.Message),
                    "WinToolKit",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
            }

            this.Close();
        }

        private void CreateWindowsShortcut(string shortcutPath, string targetPath, string workingDir)
        {
            // Execute safe PowerShell shortcut generation script without adding assembly COM dependencies
            string psScript = string.Format("$s = (New-Object -ComObject WScript.Shell).CreateShortcut('{0}'); $s.TargetPath = '{1}'; $s.WorkingDirectory = '{2}'; $s.Save()", shortcutPath, targetPath, workingDir);
            
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -Command \"{0}\"", psScript);
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;

            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
            }
        }

        // --- Custom Component Builders ---
        
        private Button CreateCyanButton(string text, Point location, EventHandler onClick)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Size = new Size(115, 35);
            btn.Location = location;
            btn.FlatStyle = FlatStyle.Flat;
            btn.BackColor = Color.FromArgb(6, 182, 212); // Neon Cyan
            btn.ForeColor = Color.White;
            btn.Font = new Font("Segoe UI", 10, FontStyle.Bold);
            btn.Cursor = Cursors.Hand;
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(8, 145, 178);
            btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(14, 116, 144);
            btn.Click += onClick;
            return btn;
        }

        private Button CreateDarkButton(string text, Point location, EventHandler onClick)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Size = new Size(115, 35);
            btn.Location = location;
            btn.FlatStyle = FlatStyle.Flat;
            btn.BackColor = Color.FromArgb(30, 41, 59); // Slate Gray Dark
            btn.ForeColor = Color.FromArgb(209, 213, 219); // Light Gray
            btn.Font = new Font("Segoe UI", 10, FontStyle.Regular);
            btn.Cursor = Cursors.Hand;
            btn.FlatAppearance.BorderColor = Color.FromArgb(75, 85, 99);
            btn.FlatAppearance.BorderSize = 1;
            btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(51, 65, 85);
            btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(15, 23, 42);
            btn.Click += onClick;
            return btn;
        }

        // --- Draggable Header Controls ---
        
        private void Header_MouseDown(object sender, MouseEventArgs e)
        {
            drag = true;
            startPoint = new Point(e.X, e.Y);
        }

        private void Header_MouseMove(object sender, MouseEventArgs e)
        {
            if (drag)
            {
                Point p = PointToScreen(e.Location);
                this.Location = new Point(p.X - startPoint.X, p.Y - startPoint.Y);
            }
        }

        private void Header_MouseUp(object sender, MouseEventArgs e)
        {
            drag = false;
        }

        // --- Administrative Check & Elevation Helper ---

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
            psi.Verb = "runas"; // UAC Self-elevation trigger
            psi.UseShellExecute = true;

            try
            {
                Process.Start(psi);
            }
            catch {}
            Environment.Exit(0);
        }
    }
}
