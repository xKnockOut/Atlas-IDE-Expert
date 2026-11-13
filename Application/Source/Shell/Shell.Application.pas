unit Shell.Application;

// Host-Rolle Shell: Einstiegspunkt der Anwendung. stdout gehört ausschließlich
// dem LSP-Protokoll; Diagnosemeldungen laufen über das Logging der Komposition.
// LSP-Server, MCP-Server und Läufe ohne Editor schreiben ihre Statusdatei für
// AtlasMonitor (#1901, TServerStatusHeartbeat); --clear-cache und --replay nicht.

interface

type
  /// <summary>Einstiegspunkt des Servers.</summary>
  TApplicationShell = class
  public
    /// <summary>Komponiert die Features, startet den Server und liefert den Exit-Code.</summary>
    class function Run: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Lsp.PublishedMembers,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Lsp.StatusHeartbeat,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Shell.Platform,
  Shell.CommandLine,
  Shell.Bootstrap,
  Shell.Composition,
  Shell.Mcp,
  Shell.ReplayServer,
  Shell.Linter;

function RunServer(const AOptions: TCommandLineOptions): Integer;
var
  mComposition: TServerComposition;
begin
  mComposition := TServerComposition.CreateForStdio(AOptions);
  try
    Result := mComposition.Run;
  finally
    mComposition.Free;
  end;
end;

// Führt den Modus aus AOptions aus; ohne Modus läuft der Server über stdio.
function RunMode(const AOptions: TCommandLineOptions): Integer;
begin
  if AOptions.ClearCache then
  begin
    Result := TLinterShell.ClearCache;
  end
  // Absturzfall nachstellen (#1355): eigener Server im Prozess, Ergebnis auf stderr.
  else if AOptions.ReplayFile <> '' then
  begin
    Result := TShellReplayServer.Main(AOptions.ReplayFile);
  end
  // Vor --check: Das Ziel aus --check ist hier nur das Projekt des Berichts.
  else if AOptions.ArchitectureFile <> '' then
  begin
    Result := TLinterShell.Architecture(AOptions);
  end
  // Vor --check: Das Ziel aus --check ist hier das Testprojekt (#1353).
  else if AOptions.AffectedTests then
  begin
    Result := TLinterShell.AffectedTests(AOptions);
  end
  // Code-Abfrage (#1351): das Ziel aus --check ist hier nur das Projekt der Abfrage.
  else if AOptions.QueryText <> '' then
  begin
    Result := TLinterShell.Query(AOptions);
  end
  else if AOptions.HotspotsFile <> '' then
  begin
    Result := TLinterShell.Hotspots(AOptions);
  end
  // Mutanten (#1460): das Ziel aus --check ist hier nur das Projekt der Symbole.
  else if AOptions.MutateFile <> '' then
  begin
    Result := TLinterShell.Mutate(AOptions);
  end
  else if AOptions.CheckTarget <> '' then
  begin
    Result := TLinterShell.Run(AOptions);
  end
  else if AOptions.Mcp then
  begin
    Result := TMcpShell.Run(AOptions);
  end
  else
  begin
    Result := RunServer(AOptions);
  end;
end;

/// <summary>Statusdatei des Prozesses (#1901) mit Art, Befehl und Ziel; nil für --clear-cache und --replay.
/// </summary>
function StartHeartbeat(const AOptions: TCommandLineOptions): TServerStatusHeartbeat;
var
  mKind: string;
begin
  Result := nil;
  if AOptions.ClearCache or (AOptions.ReplayFile <> '') then
  begin
    Exit;
  end;
  mKind := TServerStatusEntry.cKindLsp;
  if AOptions.RunCommand <> '' then
  begin
    mKind := TServerStatusEntry.cKindCli;
  end
  else if AOptions.Mcp then
  begin
    mKind := TServerStatusEntry.cKindMcp;
  end;
  // Das Ziel des MCP-Servers setzt TMcpShell (Ordner aus --root bzw. dem Arbeitsordner).
  TServerActivity.Shared.Describe(mKind, AOptions.RunCommand, AOptions.CheckTarget);
  if AOptions.LogFile <> '' then
  begin
    TServerActivity.Shared.SetLogFile(ExpandFileName(AOptions.LogFile));
  end;
  Result := TServerStatusHeartbeat.Create(TIndexCacheDirectory.DefaultRoot, TShellPlatform.CurrentProcessId,
    TServerActivity.Shared, TServerStatusHeartbeat.cIntervalMs);
end;

class function TApplicationShell.Run: Integer;
var
  mOptions: TCommandLineOptions;
  mHeartbeat: TServerStatusHeartbeat;
begin
  try
    mOptions := TCommandLineOptions.FromProcess;
    TShutdownLeaks.SetLogFile(mOptions.LogFile);
    // Sprache der Texte (#1458) für alle Modi: --locale, sonst language aus settings.json, sonst Englisch. Der
    // LSP-Server wählt nach initialize mit der Sprache des Clients neu.
    TShellBootstrap.UseTextLanguage(mOptions.Locale);
    // Liste der published-Mitglieder je Klasse merken (Hover auf VCL-Klassen kostet sonst jedes Mal rund 1 s).
    TPublishedMembers.UseCache(True);
    mHeartbeat := StartHeartbeat(mOptions);
    try
      Result := RunMode(mOptions);
    finally
      mHeartbeat.Free;
    end;
  except
    // Letzte Auffangstelle, falls schon der Aufbau scheitert und kein Logger existiert.
    on E: Exception do
    begin
      TDebugOutput.Write(Format('Unbehandelte Exception %s: %s', [E.ClassName, E.Message]));
      Result := 1;
    end;
  end;
end;

end.
