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
  BDLsp.Windows.Diagnostics.DebugOutput,
  Shell.CommandLine,
  Shell.Composition;

class function TApplicationShell.Run: Integer;
var
  Composition: TServerComposition;
begin
  try
    Composition := TServerComposition.CreateForStdio(TCommandLineOptions.FromProcess);
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
