unit Shell.Application;

// Host-Rolle Shell: Einstiegspunkt der Anwendung. stdout gehört ausschließlich
// dem LSP-Protokoll; Diagnosemeldungen laufen über das Logging der Komposition.

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

class function TApplicationShell.Run: Integer;
var
  mOptions: TCommandLineOptions;
begin
  try
    mOptions := TCommandLineOptions.FromProcess;
    TShutdownLeaks.SetLogFile(mOptions.LogFile);
    // Sprache der Texte (#1458) für alle Modi: --locale, sonst language aus settings.json, sonst Englisch. Der
    // LSP-Server wählt nach initialize mit der Sprache des Clients neu.
    TShellBootstrap.UseTextLanguage(mOptions.Locale);
    Result := RunMode(mOptions);
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
