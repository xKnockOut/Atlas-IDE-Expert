unit Atlas.Common.Logging.Providers.TransformSink;

// Senke, die den Text jedes Eintrags umschreibt und an eine andere Senke
// weitergibt, z. B. anonymisiert in die Logdatei (#647).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract;

type
  TLogTextTransform = reference to function(const AText: string): string;

  TTransformLogSink = class(TInterfacedObject, ILogSink)
  private
    FInner: ILogSink;
    FTransform: TLogTextTransform;
  public
    constructor Create(const AInner: ILogSink; const ATransform: TLogTextTransform);
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

{ TTransformLogSink }

constructor TTransformLogSink.Create(const AInner: ILogSink; const ATransform: TLogTextTransform);
begin
  inherited Create;
  FInner := AInner;
  FTransform := ATransform;
end;

procedure TTransformLogSink.Write(const AEntry: TLogEntry);
begin
  FInner.Write(TLogEntry.Create(AEntry.Timestamp, AEntry.Level, FTransform(AEntry.Text)));
end;

end.
