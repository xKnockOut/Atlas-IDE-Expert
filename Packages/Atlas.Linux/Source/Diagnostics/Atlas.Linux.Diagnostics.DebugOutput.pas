unit Atlas.Linux.Diagnostics.DebugOutput;

// Platform-Feature "Diagnostics" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Diagnostics.DebugOutput. Linux hat keinen Kanal wie
// OutputDebugString; der Text geht als eine Zeile nach stderr, wo Claude Code
// und andere Clients die Ausgabe eines Servers mitschreiben. stdout bleibt dem
// Protokoll vorbehalten.

interface

type
  TDebugOutput = record
  public
    /// <summary>Schreibt AText als eine Zeile nach stderr.</summary>
    class procedure Write(const AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  BaseUnix;

const
  StdErrorFd = 2;

class procedure TDebugOutput.Write(const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText + #10);
  if Length(Bytes) > 0 then
    FpWrite(StdErrorFd, Bytes[0], Length(Bytes));
end;

end.
