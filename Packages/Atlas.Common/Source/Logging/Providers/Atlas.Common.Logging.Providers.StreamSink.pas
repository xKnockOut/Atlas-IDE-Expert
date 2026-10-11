unit Atlas.Common.Logging.Providers.StreamSink;

// Senke, die Logeinträge zeilenweise als UTF-8 in einen Stream schreibt,
// z. B. in eine Logdatei oder auf stderr.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RotatingFileStream;

type
  TStreamLogSink = class(TInterfacedObject, ILogSink)
  private
    FStream: TStream;
    FOwnsStream: Boolean;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean);
    destructor Destroy; override;
    /// <summary>Senke auf eine Logdatei; eine vorhandene Datei wird fortgeschrieben. Mit
    /// AFallbackTag weicht sie auf "Name.Tag.log" aus, wenn die Datei belegt ist; ab
    /// AMaxBytes wird rotiert (#283).</summary>
    class function CreateForFile(const AFileName: string; const AFallbackTag: string = '';
      AMaxBytes: Int64 = TRotatingFileStream.DefaultMaxBytes): TStreamLogSink; static;
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

{ TStreamLogSink }

constructor TStreamLogSink.Create(AStream: TStream; AOwnsStream: Boolean);
begin
  inherited Create;
  FStream := AStream;
  FOwnsStream := AOwnsStream;
end;

destructor TStreamLogSink.Destroy;
begin
  if FOwnsStream then
    FStream.Free;
  inherited;
end;

class function TStreamLogSink.CreateForFile(const AFileName, AFallbackTag: string;
  AMaxBytes: Int64): TStreamLogSink;
begin
  Result := TStreamLogSink.Create(TRotatingFileStream.Create(AFileName, True, AFallbackTag, AMaxBytes), True);
end;

procedure TStreamLogSink.Write(const AEntry: TLogEntry);
var
  Data: TBytes;
begin
  Data := TEncoding.UTF8.GetBytes(AEntry.ToText + sLineBreak);
  FStream.WriteBuffer(Data, Length(Data));
end;

end.
