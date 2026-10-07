unit BDLsp.Windows.Diagnostics.Adapters.DebugOutputSink;

// Log-Senke für BDLsp.Common.Logging: schreibt jeden Eintrag über
// OutputDebugString, sichtbar im Debugger oder in DebugView.

interface

uses
  BDLsp.Common.Logging.Contract;

type
  TDebugOutputLogSink = class(TInterfacedObject, ILogSink)
  public
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

uses
  BDLsp.Windows.Diagnostics.DebugOutput;

{ TDebugOutputLogSink }

procedure TDebugOutputLogSink.Write(const AEntry: TLogEntry);
begin
  TDebugOutput.Write(AEntry.ToText);
end;

end.
