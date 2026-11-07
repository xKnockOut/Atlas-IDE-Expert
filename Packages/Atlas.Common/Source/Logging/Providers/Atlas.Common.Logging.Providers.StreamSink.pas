unit Atlas.Common.Logging.Providers.StreamSink;

// Senke, die Logeinträge zeilenweise als UTF-8 in einen Stream schreibt,
// z. B. in eine Logdatei oder auf stderr.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.RotatingFileStream;

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
    class function CreateForFile(const AFileName, AFallbackTag: string;
      AMaxBytes: Int64): TStreamLogSink; overload; static;
    /// <summary>Wie oben mit AMaxBytes = TRotatingFileStream.cDefaultMaxBytes.</summary>
    class function CreateForFile(const AFileName, AFallbackTag: string): TStreamLogSink; overload; static;
    /// <summary>Wie oben ohne Ausweichnamen (AFallbackTag = '').</summary>
    class function CreateForFile(const AFileName: string): TStreamLogSink; overload; static;
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

uses
  Atlas.Common.Logging.EntryText;

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
  begin
    FStream.Free;
  end;
  inherited;
end;

class function TStreamLogSink.CreateForFile(const AFileName, AFallbackTag: string): TStreamLogSink;
begin
  Result := CreateForFile(AFileName, AFallbackTag, TRotatingFileStream.cDefaultMaxBytes);
end;

class function TStreamLogSink.CreateForFile(const AFileName: string): TStreamLogSink;
begin
  Result := CreateForFile(AFileName, '', TRotatingFileStream.cDefaultMaxBytes);
end;

class function TStreamLogSink.CreateForFile(const AFileName, AFallbackTag: string;
  AMaxBytes: Int64): TStreamLogSink;
begin
  Result := TStreamLogSink.Create(TRotatingFileStream.Create(AFileName, True, AFallbackTag, AMaxBytes), True);
end;

procedure TStreamLogSink.Write(const AEntry: TLogEntry);
var
  mData: TBytes;
begin
  mData := TEncoding.UTF8.GetBytes(TLogEntryText.PlainLine(AEntry) + sLineBreak);
  FStream.WriteBuffer(mData, Length(mData));
end;

end.
