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
  Shell.Composition,
  Shell.Mcp,
  Shell.ReplayServer,
  Shell.Linter;

class function TApplicationShell.Run: Integer;
var
  Options: TCommandLineOptions;
  Composition: TServerComposition;
begin
  try
    Options := TCommandLineOptions.FromProcess;
    TShutdownLeaks.SetLogFile(Options.LogFile);
    if Options.ClearCache then
    begin
      Exit(TLinterShell.ClearCache);
    end;
    // Absturzfall nachstellen (#1355): eigener Server im Prozess, Ergebnis auf stderr.
    if Options.ReplayFile <> '' then
    begin
      Exit(TShellReplayServer.Main(Options.ReplayFile));
    end;
    // Vor --check: Das Ziel aus --check ist hier nur das Projekt des Berichts.
    if Options.ArchitectureFile <> '' then
    begin
      Exit(TLinterShell.Architecture(Options));
    end;
    // Vor --check: Das Ziel aus --check ist hier das Testprojekt (#1353).
    if Options.AffectedTests then
    begin
      Exit(TLinterShell.AffectedTests(Options));
    end;
    // Code-Abfrage (#1351): das Ziel aus --check ist hier nur das Projekt der Abfrage.
    if Options.QueryText <> '' then
    begin
      Exit(TLinterShell.Query(Options));
    end;
    if Options.HotspotsFile <> '' then
    begin
      Exit(TLinterShell.Hotspots(Options));
    end;
    if Options.CheckTarget <> '' then
    begin
      Exit(TLinterShell.Run(Options));
    end;
    if Options.Mcp then
    begin
      Exit(TMcpShell.Run(Options));
    end;
    Composition := TServerComposition.CreateForStdio(Options);
    try
      Result := Composition.Run;
    finally
      Composition.Free;
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
