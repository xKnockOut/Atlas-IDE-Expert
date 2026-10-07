unit Shell.Application;

// Host-Rolle Shell: Einstiegspunkt der Anwendung und Komposition der Features.
// stdout gehört ausschließlich dem LSP-Protokoll; Diagnosemeldungen laufen
// über TDebugOutput.

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
  BDLsp.Common.Product.Version,
  BDLsp.Windows.Diagnostics.DebugOutput,
  Shell.Composition;

class function TApplicationShell.Run: Integer;
var
  Composition: TServerComposition;
begin
  try
    TDebugOutput.Write(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
    Composition := TServerComposition.CreateForStdio;
    try
      Result := Composition.Run;
    finally
      Composition.Free;
    end;
    TDebugOutput.Write(Format('Beendet mit Exit-Code %d', [Result]));
  except
    on E: Exception do
    begin
      TDebugOutput.Write(Format('Unbehandelte Exception %s: %s', [E.ClassName, E.Message]));
      Result := 1;
    end;
  end;
end;

end.
