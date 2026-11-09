using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0")]

internal static class MultiInstanceLauncher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(directory, "MultiInstanceManager.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("找不到客户端所需的 MultiInstanceManager.ps1，请保持它与程序放在同一个文件夹。", script);

            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\" -HideConsole",
                WorkingDirectory = directory,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            if (Process.Start(start) == null)
                throw new InvalidOperationException("系统没有启动多开管理器。");
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "DarkWar 多开管理器", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
