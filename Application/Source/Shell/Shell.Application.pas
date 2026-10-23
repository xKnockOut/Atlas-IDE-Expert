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
      Exit(TLinterShell.ClearCache);
    if Options.CheckTarget <> '' then
      Exit(TLinterShell.Run(Options));
    if Options.Mcp then
      Exit(TMcpShell.Run(Options));
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
