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
