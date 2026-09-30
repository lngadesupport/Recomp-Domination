using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

class Recompiler : Form {
    TextBox folder = new TextBox(), log = new TextBox();
    Button start = new Button(), browse = new Button(), output = new Button();
    CheckBox probe = new CheckBox();
    bool busy;
    public Recompiler() {
        Text = "Recomp Domination — Recompilador"; Size = new Size(860, 610);
        MinimumSize = Size; StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);
        var title = new Label { Text = "Downhill Domination • Windows x64", Left = 20, Top = 16, Width = 780, Height = 30 };
        bool portable = Directory.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "tools"));
        var info = new Label { Text = portable ? "Versão portátil: ferramentas incluídas, sem instalação.\nSelecione a pasta com SCUS_971.77 e os dados do disco. Requer internet no primeiro build." : "Selecione a pasta com SCUS_971.77 e os dados do disco.\nO programa instala as ferramentas que faltarem. Requer internet e vários GB livres.", Left = 20, Top = 54, Width = 780, Height = 52 };
        folder.SetBounds(20, 114, 660, 30); folder.Text = @"D:\Recomp Domination";
        browse.SetBounds(690, 112, 130, 32); browse.Text = "Selecionar...";
        browse.Click += delegate { using (var d = new FolderBrowserDialog()) { if (d.ShowDialog() == DialogResult.OK) folder.Text = d.SelectedPath; } };
        probe.SetBounds(20, 157, 790, 28); probe.Text = "Executar teste de boot por 90 segundos após compilar"; probe.Checked = true;
        start.SetBounds(20, 197, 280, 40); start.Text = portable ? "Recompilar e testar" : "Instalar ferramentas e recompilar";
        output.SetBounds(315, 197, 200, 40); output.Text = "Abrir pasta do jogo";
        output.Click += delegate { if (Directory.Exists(folder.Text)) Process.Start("explorer.exe", Quote(folder.Text)); };
        log.SetBounds(20, 252, 800, 300); log.Multiline = true; log.ReadOnly = true; log.ScrollBars = ScrollBars.Vertical;
        log.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        Controls.AddRange(new Control[] {title, info, folder, browse, probe, start, output, log});
        start.Click += async delegate {
            string game = folder.Text; bool runProbe = probe.Checked;
            if (!File.Exists(Path.Combine(game, "SCUS_971.77"))) { MessageBox.Show("SCUS_971.77 não encontrado na pasta selecionada."); return; }
            busy = true; start.Enabled = browse.Enabled = folder.Enabled = probe.Enabled = false; log.Clear();
            try { await Task.Run(() => Run(game, runProbe)); }
            catch (Exception e) { Append("ERRO: " + e.Message); }
            finally { busy = false; start.Enabled = browse.Enabled = folder.Enabled = probe.Enabled = true; }
        };
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) { e.Cancel = true; MessageBox.Show("Aguarde a instalação ou compilação terminar. O teste do jogo tem timeout automático."); } };
    }
    static string Quote(string s) { return "\"" + s.Replace("\"", "") + "\""; }
    void Append(string line) { if (line != null) BeginInvoke((Action)(() => { if (log.TextLength > 200000) log.Text = log.Text.Substring(log.TextLength - 100000); log.AppendText(line + Environment.NewLine); })); }
    void Run(string game, bool runProbe) {
        string work = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RecompDomination", "sessions", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        var assembly = Assembly.GetExecutingAssembly();
        string zip = Path.Combine(work, "payload.zip");
        using (var input = assembly.GetManifestResourceStream("payload.zip")) using (var dest = File.Create(zip)) { input.CopyTo(dest); }
        ZipFile.ExtractToDirectory(zip, work); File.Delete(zip);
        string tools = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "tools");
        bool portable = Directory.Exists(tools);
        string script = Path.Combine(work, "launcher", portable ? "setup_portable.ps1" : "setup_and_compile.ps1");
        Append(portable ? "Usando ferramentas portáteis. Nenhum instalador será executado." : "Preparando ferramentas e recompilação. A instalação pode pedir autorização do Windows.");
        Append("Arquivos de trabalho: " + work);
        var psi = new ProcessStartInfo("powershell.exe", "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + Quote(script) + " -GameRoot " + Quote(game) + (portable ? " -ToolRoot " + Quote(tools) : "") + (runProbe ? " -RunProbe" : ""));
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.RedirectStandardOutput = psi.RedirectStandardError = true;
        using (var p = new Process()) {
            p.StartInfo = psi; p.OutputDataReceived += (s,e) => Append(e.Data); p.ErrorDataReceived += (s,e) => Append(e.Data);
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); p.WaitForExit();
            Append(p.ExitCode == 0 ? "Concluído. Abra a pasta do jogo para acessar DownhillRecompiled e os diagnósticos." : "Processo terminou com código " + p.ExitCode + ". Veja o log e o ZIP de diagnóstico na pasta do jogo.");
        }
    }
    [STAThread] static void Main() { Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false); Application.Run(new Recompiler()); }
}
