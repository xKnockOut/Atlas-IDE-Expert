unit Atlas.Windows.Diagnostics.DebugOutput;

// Platform-Feature "Diagnostics", Root: Ausgabe von Diagnosemeldungen über
// OutputDebugString. Berührt stdout nicht, das ausschließlich dem
// LSP-Protokoll gehört (Spezifikation, Abschnitt 9).

interface

type
  /// <summary>Schreibt Diagnosemeldungen an den Debugger bzw. einen Debug-Output-Viewer.</summary>
  TDebugOutput = record
  public
    class procedure Write(const AText: string); static;
  end;

implementation

uses
  Winapi.Windows;

class procedure TDebugOutput.Write(const AText: string);
begin
  OutputDebugString(PChar('[Atlas] ' + AText));
end;

end.
