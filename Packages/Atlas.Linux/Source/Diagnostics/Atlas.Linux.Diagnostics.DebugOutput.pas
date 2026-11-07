unit Atlas.Linux.Diagnostics.DebugOutput;

// Platform-Feature "Diagnostics" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Diagnostics.DebugOutput. Linux hat keinen Kanal wie
// OutputDebugString; der Text geht als eine Zeile nach stderr, wo ein MCP-Client
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
  cStdErrorFd = 2;

class procedure TDebugOutput.Write(const AText: string);
var
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText + #10);
  if Length(mBytes) > 0 then
  begin
    FpWrite(cStdErrorFd, mBytes[0], Length(mBytes));
  end;
end;

end.
