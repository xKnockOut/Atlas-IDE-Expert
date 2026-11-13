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
    function Write(const ABuffer; ACount: Longint): Longint; override;
    property MaxBytes: Int64 read FMaxBytes;
    /// <summary>Wurde versucht, mehr als MaxBytes zu schreiben?</summary>
    property Exceeded: Boolean read FExceeded;
  end;

implementation

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
  Result := inherited Write(ABuffer, ACount);
end;

end.
