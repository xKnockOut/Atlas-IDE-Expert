unit Atlas.Common.Logging.RotatingFileStream;

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
      AMaxBytes: Int64); overload;
    /// <summary>Wie oben mit AMaxBytes = DefaultMaxBytes.</summary>
    constructor Create(const AFileName: string; AAppend: Boolean; const AFallbackTag: string); overload;
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
  System.IOUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRotatingFileStreamText = (LogStreamIsWriteOnly);

const
  cTexts: array[TRotatingFileStreamText] of TAtlasText = (
    (De: 'Logstrom ist nur zum Schreiben'; En: 'Log stream is write-only'));

{$SCOPEDENUMS OFF}

function OpenFile(const AFileName: string; AAppend: Boolean): TFileStream;
begin
  if AAppend and FileExists(AFileName) then
  begin
    Result := TFileStream.Create(AFileName, fmOpenWrite or fmShareDenyWrite);
    Result.Seek(0, soEnd);
  end
  else
  begin
    Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  end;
end;

{ TRotatingFileStream }

class function TRotatingFileStream.FallbackName(const AFileName, ATag: string): string;
begin
  Result := ChangeFileExt(AFileName, '') + '.' + ATag + ExtractFileExt(AFileName);
end;

constructor TRotatingFileStream.Create(const AFileName: string; AAppend: Boolean; const AFallbackTag: string);
begin
  Create(AFileName, AAppend, AFallbackTag, DefaultMaxBytes);
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
  begin
    ForceDirectories(Directory);
  end;
  try
    FStream := OpenFile(FFileName, AAppend);
  except
    on EFOpenError do
    begin
      // Belegt, z. B. von einem zweiten Server mit derselben Logdatei.
      if AFallbackTag = '' then
      begin
        raise;
      end;
      FFileName := FallbackName(AFileName, AFallbackTag);
      FStream := OpenFile(FFileName, AAppend);
    end;
    on EFCreateError do
    begin
      if AFallbackTag = '' then
      begin
        raise;
      end;
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
  begin
    System.SysUtils.DeleteFile(Previous);
  end;
  // Klappt das Umbenennen nicht, beginnt die Datei eben von vorn.
  RenameFile(FFileName, Previous); // lsp-ignore: inline-not-expanded -- Common ohne Winapi
  FStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyWrite);
end;

function TRotatingFileStream.GetSize: Int64;
begin
  Result := FStream.Size;
end;

function TRotatingFileStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create(cTexts[TRotatingFileStreamText.LogStreamIsWriteOnly].Text);
end;

function TRotatingFileStream.Write(const Buffer; Count: Longint): Longint;
begin
  if (FMaxBytes > 0) and (FStream.Size > 0) and (FStream.Size + Count > FMaxBytes) then
  begin
    Rotate;
  end;
  Result := FStream.Write(Buffer, Count);
end;

function TRotatingFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FStream.Seek(Offset, Origin);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Logging.RotatingFileStream', cTexts);

end.
