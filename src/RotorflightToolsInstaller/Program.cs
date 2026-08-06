using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RotorflightToolsInstaller;

internal sealed record AppDefinition(
  string Name,
  string Repository,
  string AssetPattern,
  string? Directory = null,
  string? Executable = null,
  bool Portable = false);

internal sealed record Release(
  string Tag,
  DateTime Published,
  bool Prerelease,
  string AssetName,
  string Url);

internal static class Program
{
  private static readonly HttpClient Http = CreateHttpClient();
  private static readonly Dictionary<string, AppDefinition> Apps = new()
  {
    ["configurator"] = new("Rotorflight Configurator", "rotorflight/rotorflight-configurator",
      @"rotorflight-configurator_[^/]+_win_x86_64\.zip$", "Rotorflight Configurator", "rotorflight-configurator.exe", true),
    ["blackbox"] = new("Rotorflight Blackbox", "rotorflight/rotorflight-blackbox",
      @"rotorflight-blackbox-installer_[^/]+_win64\.exe$"),
    ["expresslrs"] = new("ExpressLRS Configurator", "ExpressLRS/ExpressLRS-Configurator",
      @"ExpressLRS-Configurator-Setup-[^/]+\.exe$"),
    ["blackbox_lab"] = new("Blackbox Lab", "hillbilly1975/Blackbox_Lab",
      @"Blackbox\.Lab-win32-x64-[^/]+\.zip$", "Blackbox Lab", "Blackbox Lab.exe", true),
    ["radio_updater"] = new("Rotorflight Radio Updater", "rotorflight/rotorflight-lua-edgetx-updater",
      @"rotorflight-lua-edgetx-updater-[^/]+-windows-x64\.zip$", "Rotorflight Radio Updater",
      "rotorflight-lua-edgetx-updater.exe", true)
  };

  private static int ReleaseLimit { get; set; } = 10;
  private static string InstallRoot { get; set; } = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Rotorflight Tools");

  public static async Task<int> Main(string[] args)
  {
    try
    {
      if (!ParseArguments(args)) return 0;
      if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Este instalador executa somente no Windows.");

      Console.WriteLine("Rotorflight Tools Installer para Windows");
      Console.WriteLine($"Aplicativos portateis: {InstallRoot}");

      var (selected, latestStable) = SelectApps();
      foreach (var appId in selected)
      {
        if (appId == "drivers") ShowDriverInfo();
        else if (appId == "helix") await InstallHelixAsync();
        else await InstallGitHubAppAsync(appId, latestStable);
      }

      Console.WriteLine("\nConcluido.");
      return 0;
    }
    catch (Exception exception)
    {
      Console.Error.WriteLine($"\nErro: {exception.Message}");
      Console.Error.WriteLine("Pressione Enter para sair.");
      Console.ReadLine();
      return 1;
    }
  }

  private static bool ParseArguments(string[] args)
  {
    for (var i = 0; i < args.Length; i++)
    {
      switch (args[i].ToLowerInvariant())
      {
        case "-h": case "--help": case "/?":
          ShowHelp();
          return false;
        case "--release-limit" when i + 1 < args.Length && int.TryParse(args[++i], out var limit) && limit is >= 1 and <= 100:
          ReleaseLimit = limit;
          break;
        case "--install-root" when i + 1 < args.Length:
          InstallRoot = Path.GetFullPath(args[++i]);
          break;
        default:
          throw new ArgumentException($"Opcao desconhecida ou incompleta: {args[i]}");
      }
    }
    return true;
  }

  private static void ShowHelp()
  {
    Console.WriteLine("""
      Rotorflight Tools Installer para Windows

      Uso:
        RotorflightToolsInstaller.exe
        RotorflightToolsInstaller.exe --release-limit 20
        RotorflightToolsInstaller.exe --install-root "D:\Apps\Rotorflight"
      """);
  }

  private static (string[] Apps, bool LatestStable) SelectApps()
  {
    while (true)
    {
      Console.WriteLine("""

        O que deseja instalar/atualizar?
          1) Rotorflight Configurator
          2) Rotorflight Blackbox
          3) ExpressLRS Configurator
          4) Rotorflight Configurator + Blackbox (padrao)
          5) Informacoes sobre drivers USB/DFU
          6) HELI-X 11
          7) Rotorflight Radio Updater (EdgeTX/OpenTX)
          8) Blackbox Lab
          9) Todos - ultima versao estavel, sem perguntar a release
          q) Sair
        """);
      Console.Write("Escolha [4]: ");
      var choice = Console.ReadLine()?.Trim();
      switch (string.IsNullOrEmpty(choice) ? "4" : choice.ToLowerInvariant())
      {
        case "1": return (["configurator"], false);
        case "2": return (["blackbox"], false);
        case "3": return (["expresslrs"], false);
        case "4": return (["configurator", "blackbox"], false);
        case "5": return (["drivers"], false);
        case "6": return (["helix"], false);
        case "7": return (["radio_updater"], false);
        case "8": return (["blackbox_lab"], false);
        case "9": return (["configurator", "blackbox", "expresslrs", "blackbox_lab", "radio_updater", "helix"], true);
        case "q": return ([], false);
        default: Console.WriteLine("Opcao invalida."); break;
      }
    }
  }

  private static async Task InstallGitHubAppAsync(string appId, bool latestStable)
  {
    var app = Apps[appId];
    var release = await SelectReleaseAsync(app, latestStable);
    if (release is null) return;

    if (app.Portable) await InstallPortableAsync(app, release);
    else await DownloadAndRunInstallerAsync(app.Name, release.Url, release.AssetName);

    Console.WriteLine($"{app.Name} instalado/atualizado para {release.Tag}.");
  }

  private static async Task<Release?> SelectReleaseAsync(AppDefinition app, bool latestStable)
  {
    Console.WriteLine($"\nBuscando releases de {app.Name}...");
    var releases = await GetReleasesAsync(app);
    if (releases.Count == 0) throw new InvalidOperationException($"Nenhum pacote Windows x64 encontrado para {app.Name}.");

    if (latestStable)
    {
      var stable = releases.FirstOrDefault(release => !release.Prerelease)
        ?? throw new InvalidOperationException($"Nenhuma release estavel encontrada para {app.Name}.");
      Console.WriteLine($"Selecionada automaticamente: {stable.Tag} ({stable.AssetName})");
      return stable;
    }

    Console.WriteLine("Releases disponiveis:");
    for (var i = 0; i < releases.Count; i++)
      Console.WriteLine($"  {i + 1,2}) {releases[i].Tag,-24} {(releases[i].Prerelease ? "pre-release" : "estavel"),-12} {releases[i].Published:yyyy-MM-dd}\n      {releases[i].AssetName}");

    while (true)
    {
      Console.Write($"Escolha a release de {app.Name} [1] (q cancela): ");
      var choice = Console.ReadLine()?.Trim();
      if (string.Equals(choice, "q", StringComparison.OrdinalIgnoreCase)) return null;
      if (string.IsNullOrEmpty(choice)) return releases[0];
      if (int.TryParse(choice, out var number) && number >= 1 && number <= releases.Count) return releases[number - 1];
      Console.WriteLine("Escolha invalida.");
    }
  }

  private static async Task<List<Release>> GetReleasesAsync(AppDefinition app)
  {
    using var response = await Http.GetAsync($"https://api.github.com/repos/{app.Repository}/releases?per_page={ReleaseLimit}");
    response.EnsureSuccessStatusCode();
    await using var stream = await response.Content.ReadAsStreamAsync();
    using var document = await JsonDocument.ParseAsync(stream);
    var pattern = new Regex(app.AssetPattern, RegexOptions.IgnoreCase);
    var result = new List<Release>();

    foreach (var item in document.RootElement.EnumerateArray())
    {
      var asset = item.GetProperty("assets").EnumerateArray().FirstOrDefault(candidate =>
        pattern.IsMatch(candidate.GetProperty("name").GetString() ?? ""));
      if (asset.ValueKind == JsonValueKind.Undefined) continue;
      result.Add(new Release(
        item.GetProperty("tag_name").GetString() ?? "",
        item.GetProperty("published_at").GetDateTime(),
        item.GetProperty("prerelease").GetBoolean(),
        asset.GetProperty("name").GetString() ?? "download",
        asset.GetProperty("browser_download_url").GetString() ?? throw new InvalidOperationException("URL de download ausente.")));
    }
    return result;
  }

  private static async Task InstallPortableAsync(AppDefinition app, Release release)
  {
    var temp = Path.Combine(Path.GetTempPath(), $"rotorflight-tools-{Guid.NewGuid():N}");
    try
    {
      var archive = Path.Combine(temp, release.AssetName);
      var extract = Path.Combine(temp, "extract");
      Directory.CreateDirectory(extract);
      await DownloadAsync(release.Url, archive);
      Console.WriteLine("Extraindo...");
      ZipFile.ExtractToDirectory(archive, extract, true);
      var executable = Directory.EnumerateFiles(extract, app.Executable!, SearchOption.AllDirectories).FirstOrDefault()
        ?? throw new FileNotFoundException($"{app.Executable} nao foi encontrado em {release.AssetName}.");
      var payload = Path.GetDirectoryName(executable)!;
      var destination = Path.Combine(InstallRoot, app.Directory!);
      Directory.CreateDirectory(InstallRoot);
      if (Directory.Exists(destination))
      {
        var backup = $"{destination}.bak-{DateTime.Now:yyyyMMdd-HHmmss}";
        Directory.Move(destination, backup);
        Console.WriteLine($"Backup criado em {backup}");
      }
      Directory.Move(payload, destination);
      CreateShortcuts(app.Name, Path.Combine(destination, app.Executable!));
    }
    finally { TryDeleteDirectory(temp); }
  }

  private static async Task InstallHelixAsync()
  {
    var arm64 = RuntimeInformation.OSArchitecture == Architecture.Arm64;
    var file = arm64 ? "setupHeli-X11_arm64.exe" : "setupHeli-X11_win64.exe";
    await DownloadAndRunInstallerAsync("HELI-X 11", $"https://www.heli-x.info/2675/{file}", file);
  }

  private static async Task DownloadAndRunInstallerAsync(string name, string url, string fileName)
  {
    var temp = Path.Combine(Path.GetTempPath(), $"rotorflight-tools-{Guid.NewGuid():N}");
    try
    {
      Directory.CreateDirectory(temp);
      var installer = Path.Combine(temp, fileName);
      await DownloadAsync(url, installer);
      Console.WriteLine($"Iniciando o instalador de {name}...");
      using var process = Process.Start(new ProcessStartInfo(installer) { UseShellExecute = true })
        ?? throw new InvalidOperationException($"Nao foi possivel iniciar {fileName}.");
      await process.WaitForExitAsync();
      if (process.ExitCode != 0) throw new InvalidOperationException($"O instalador terminou com o codigo {process.ExitCode}.");
    }
    finally { TryDeleteDirectory(temp); }
  }

  private static async Task DownloadAsync(string url, string destination)
  {
    Console.WriteLine($"Baixando {Path.GetFileName(destination)}...");
    using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
    response.EnsureSuccessStatusCode();
    await using var source = await response.Content.ReadAsStreamAsync();
    await using var target = File.Create(destination);
    await source.CopyToAsync(target);
  }

  private static void CreateShortcuts(string name, string executable)
  {
    var startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "Rotorflight Tools");
    var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    Directory.CreateDirectory(startMenu);
    foreach (var shortcut in new[] { Path.Combine(startMenu, $"{name}.lnk"), Path.Combine(desktop, $"{name}.lnk") })
    {
      var escapedShortcut = shortcut.Replace("'", "''");
      var escapedExecutable = executable.Replace("'", "''");
      var command = $"$s=(New-Object -ComObject WScript.Shell).CreateShortcut('{escapedShortcut}');$s.TargetPath='{escapedExecutable}';$s.WorkingDirectory=[IO.Path]::GetDirectoryName('{escapedExecutable}');$s.IconLocation='{escapedExecutable},0';$s.Save()";
      using var process = Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -NonInteractive -Command \"{command}\"")
      { UseShellExecute = false, CreateNoWindow = true }) ?? throw new InvalidOperationException("Nao foi possivel criar o atalho.");
      process.WaitForExit();
      if (process.ExitCode != 0) throw new InvalidOperationException($"Nao foi possivel criar o atalho {shortcut}.");
    }
  }

  private static void ShowDriverInfo() => Console.WriteLine("""

    O Windows nao usa regras udev. Se o modo DFU nao for detectado, instale o
    driver STM32 bootloader/WinUSB recomendado pelo Rotorflight e reconecte a
    controladora. Portas COM virtuais normalmente sao configuradas pelo Windows.
    """);

  private static HttpClient CreateHttpClient()
  {
    var client = new HttpClient();
    client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("rotorflight-tools-installer", "1.0"));
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
    client.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28");
    return client;
  }

  private static void TryDeleteDirectory(string path)
  {
    try { if (Directory.Exists(path)) Directory.Delete(path, true); }
    catch (IOException) { }
    catch (UnauthorizedAccessException) { }
  }
}
