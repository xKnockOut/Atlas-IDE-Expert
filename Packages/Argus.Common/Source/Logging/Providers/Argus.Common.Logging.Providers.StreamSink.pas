unit Argus.Common.Logging.Providers.StreamSink;

// Senke, die Logeinträge zeilenweise als UTF-8 in einen Stream schreibt,
// z. B. in eine Logdatei oder auf stderr.

interface

uses
  System.SysUtils,
  System.Classes,
  Argus.Common.Logging.Contract;

type
  TStreamLogSink = class(TInterfacedObject, ILogSink)
  private
    FStream: TStream;
    FOwnsStream: Boolean;
  public
    constructor Create(AStream: TStream; AOwnsStream: Boolean);
    destructor Destroy; override;
    /// <summary>Senke auf eine Logdatei; eine vorhandene Datei wird fortgeschrieben.</summary>
    class function CreateForFile(const AFileName: string): TStreamLogSink; static;
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

uses
  System.IOUtils;

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

class function TStreamLogSink.CreateForFile(const AFileName: string): TStreamLogSink;
var
  Directory: string;
  Stream: TFileStream;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  if FileExists(AFileName) then
  begin
    Stream := TFileStream.Create(AFileName, fmOpenWrite or fmShareDenyWrite);
    Stream.Seek(0, soEnd);
  end
  else
    Stream := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  Result := TStreamLogSink.Create(Stream, True);
end;

procedure TStreamLogSink.Write(const AEntry: TLogEntry);
var
  Data: TBytes;
begin
  Data := TEncoding.UTF8.GetBytes(AEntry.ToText + sLineBreak);
  FStream.WriteBuffer(Data, Length(Data));
end;

end.
