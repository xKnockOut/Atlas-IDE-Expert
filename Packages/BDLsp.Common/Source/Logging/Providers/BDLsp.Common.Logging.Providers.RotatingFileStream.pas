unit BDLsp.Common.Logging.Providers.RotatingFileStream;

// Schreibstrom für Logdatei und Mitschnitt (#283).
//
// - Andere Prozesse dürfen die Datei lesen, aber nicht gleichzeitig hinein-
//   schreiben, damit sich Zeilen nicht mischen. Ist die Datei schon von einem
//   zweiten Server belegt, weicht der Strom auf "<Name>.<Kennung>.<Endung>"
//   aus (die Kennung ist üblicherweise die Prozess-ID).
// - Überschreitet die Datei MaxBytes, wird sie zu "<Datei>.1" (ein Vorgänger,
//   ein älterer entfällt) und neu begonnen.
// - Nicht threadsicher; der Logger serialisiert die Aufrufe.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TRotatingFileStream = class(TStream)
  public const
    DefaultMaxBytes = 10 * 1024 * 1024;
  private
    FFileName: string;
    FMaxBytes: Int64;
    FStream: TFileStream;
    procedure Rotate;
  protected
    function GetSize: Int64; override;
  public
    /// <summary>AAppend: vorhandene Datei fortschreiben, sonst neu beginnen.
    /// AFallbackTag: Kennung für den Ausweichnamen; '' = kein Ausweichen.
    /// AMaxBytes = 0 schaltet die Rotation ab.</summary>
    constructor Create(const AFileName: string; AAppend: Boolean; const AFallbackTag: string;
      AMaxBytes: Int64 = DefaultMaxBytes);
    destructor Destroy; override;
    /// <summary>Tatsächlich benutzte Datei (nach einem Ausweichen die mit Kennung).</summary>
    property FileName: string read FFileName;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    /// <summary>Ausweichname: "server.log" mit Kennung 42 wird "server.42.log".</summary>
    class function FallbackName(const AFileName, ATag: string): string; static;
  end;

implementation

uses
  System.IOUtils;

function OpenFile(const AFileName: string; AAppend: Boolean): TFileStream;
begin
  if AAppend and FileExists(AFileName) then
  begin
    Result := TFileStream.Create(AFileName, fmOpenWrite or fmShareDenyWrite);
    Result.Seek(0, soEnd);
  end
  else
    Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
end;

{ TRotatingFileStream }

class function TRotatingFileStream.FallbackName(const AFileName, ATag: string): string;
begin
  Result := ChangeFileExt(AFileName, '') + '.' + ATag + ExtractFileExt(AFileName);
end;

constructor TRotatingFileStream.Create(const AFileName: string; AAppend: Boolean; const AFallbackTag: string;
  AMaxBytes: Int64);
var
  Directory: string;
begin
  inherited Create;
  FMaxBytes := AMaxBytes;
  FFileName := AFileName;
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  try
    FStream := OpenFile(FFileName, AAppend);
  except
    on EFOpenError do
    begin
      // Belegt, z. B. von einem zweiten Server mit derselben Logdatei.
      if AFallbackTag = '' then
        raise;
      FFileName := FallbackName(AFileName, AFallbackTag);
      FStream := OpenFile(FFileName, AAppend);
    end;
    on EFCreateError do
    begin
      if AFallbackTag = '' then
        raise;
      FFileName := FallbackName(AFileName, AFallbackTag);
      FStream := OpenFile(FFileName, AAppend);
    end;
  end;
end;

destructor TRotatingFileStream.Destroy;
begin
  FStream.Free;
  inherited;
end;

procedure TRotatingFileStream.Rotate;
var
  Previous: string;
begin
  Previous := FFileName + '.1';
  FreeAndNil(FStream);
  if FileExists(Previous) then
    System.SysUtils.DeleteFile(Previous);
  // Klappt das Umbenennen nicht, beginnt die Datei eben von vorn.
  RenameFile(FFileName, Previous);
  FStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyWrite);
end;

function TRotatingFileStream.GetSize: Int64;
begin
  Result := FStream.Size;
end;

function TRotatingFileStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create('Logstrom ist nur zum Schreiben');
end;

function TRotatingFileStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (FMaxBytes > 0) and (FStream.Size > 0) and (FStream.Size + Count > FMaxBytes) then
    Rotate;
  Result := FStream.Write(Buffer, Count);
end;

function TRotatingFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FStream.Seek(Offset, Origin);
end;

end.
