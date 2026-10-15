// DevSetup.exe - abre o DevSetup (PowerShell + WPF) sem exibir janela de console.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("DevSetup")]
[assembly: AssemblyProduct("DevSetup")]
[assembly: AssemblyDescription("Instalador de ferramentas de desenvolvimento")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Launcher
{
    [STAThread]
    static int Main(string[] args)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(baseDir, "app", "DevSetup.ps1");
        if (!File.Exists(script)) script = Path.Combine(baseDir, "DevSetup.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Arquivos do DevSetup não encontrados. Reinstale o aplicativo.", "DevSetup",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        string extra = string.Join(" ", args.Select(a => "\"" + a.Replace("\"", "\\\"") + "\""));

        var psi = new ProcessStartInfo(powershell,
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" " + extra)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(script)
        };

        try
        {
            using (var p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Não foi possível iniciar o DevSetup:\n\n" + ex.Message, "DevSetup",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
