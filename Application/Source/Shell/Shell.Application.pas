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
  BDLsp.Windows.Diagnostics.DebugOutput;

class function TApplicationShell.Run: Integer;
begin
  try
    TDebugOutput.Write(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
    // Die Protokollschicht (#2) wird hier komponiert und gestartet.
    Result := 0;
  except
    on E: Exception do
    begin
      TDebugOutput.Write(Format('Unbehandelte Exception %s: %s', [E.ClassName, E.Message]));
      Result := 1;
    end;
  end;
end;

end.
