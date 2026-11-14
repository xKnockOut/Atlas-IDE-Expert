unit Atlas.Core.Diagnostics.BoundedStream;

// Antwort-Stream mit Größengrenze für HTTP-Anfragen (Code-Review F-105):
// Vorher lag die ganze Antwort im Speicher, bevor ihre Größe geprüft wurde;
// eine sehr große oder endlose Antwort eines frei eingetragenen Servers wurde
// bis zur Zeitgrenze in der IDE gepuffert. Dieser Stream bricht schon beim
// Schreiben ab: Write löst EAtlasStreamLimit aus, sobald die Grenze
// überschritten würde, und Exceeded bleibt gesetzt. Die Anfrage endet damit
// mit einem Fehler, den der Aufrufer über Exceeded erkennt.

interface

uses
  System.SysUtils,
  System.Classes;

type
  /// <summary>Die Antwort ist größer als die Grenze des Streams.</summary>
  EAtlasStreamLimit = class(Exception);

  TAtlasBoundedStream = class(TBytesStream)
  private
    FMaxBytes: Int64;
    FExceeded: Boolean;
  public
    /// <summary>AMaxBytes: höchstens so viele Byte nimmt der Stream an.</summary>
    constructor Create(AMaxBytes: Int64);
    /// <summary>Wie TBytesStream; würde die Grenze überschritten, wird nichts geschrieben, Exceeded gesetzt und
    /// EAtlasStreamLimit ausgelöst.</summary>
    function Write(const ABuffer; ACount: Longint): Longint; overload; override;
{$IF RTLVersion >= 37.0}
    // Ab Delphi 13 ruft WriteBuffer unter Win64 die NativeInt-Überladung auf, die an der
    // Longint-Fassung vorbeigeht; ohne diese Überschreibung griff die Grenze nicht. Unter Win32
    // sind beide Signaturen gleich, dort genügt die obere.
  {$IF SizeOf(Longint) <> SizeOf(NativeInt)}
    function Write(const ABuffer; ACount: NativeInt): NativeInt; overload; override;
  {$IFEND}
{$IFEND}
    property MaxBytes: Int64 read FMaxBytes;
    /// <summary>Wurde versucht, mehr als MaxBytes zu schreiben?</summary>
    property Exceeded: Boolean read FExceeded;
  end;

implementation

{ TAtlasBoundedStream }

constructor TAtlasBoundedStream.Create(AMaxBytes: Int64);
begin
  inherited Create;
  FMaxBytes := AMaxBytes;
end;

function TAtlasBoundedStream.Write(const ABuffer; ACount: Longint): Longint;
begin
  if (ACount > 0) and (Position + ACount > FMaxBytes) then
  begin
    FExceeded := True;
    // Die Meldung ist die Grenze; was sie bedeutet, sagt die Klasse.
    raise EAtlasStreamLimit.Create(IntToStr(FMaxBytes));
  end;
  Result := inherited Write(ABuffer, ACount); // console-ok: TBytesStream.Write, nicht System.Write
end;

{$IF RTLVersion >= 37.0}
  {$IF SizeOf(Longint) <> SizeOf(NativeInt)}
function TAtlasBoundedStream.Write(const ABuffer; ACount: NativeInt): NativeInt;
begin
  if (ACount > 0) and (Position + ACount > FMaxBytes) then
  begin
    FExceeded := True;
    raise EAtlasStreamLimit.Create(IntToStr(FMaxBytes));
  end;
  Result := inherited Write(ABuffer, ACount); // console-ok: TBytesStream.Write, nicht System.Write
end;
  {$IFEND}
{$IFEND}

end.
