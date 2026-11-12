unit Atlas.Core.Marks.Ids;

// Kennungen und Dateivergleich für Lesezeichen und Notizen, ohne VCL und Open
// Tools API. Beide Ablagen dieses Moduls hatten dieselben zwei Funktionen.
// - SameFile: gleicher Pfad nach TAtlasProjectSummaries.NormalizedPath
//   (Groß-/Kleinschreibung, „/“ und „\“ sowie Leerraum am Rand egal).
// - NewId: GUID in Kleinbuchstaben ohne Klammern. Liefert das System keine
//   GUID, Zeitpunkt in Millisekunden (12 Hex-Ziffern) und eine laufende
//   Nummer (8 Hex-Ziffern): eindeutig im Prozess, auch bei mehreren Aufrufen
//   in derselben Millisekunde und aus mehreren Threads. Kein Randomize, das
//   den globalen Zufallsgenerator anderer Units neu setzen würde.

interface

type
  TAtlasMarkIds = record
  strict private
    class var FSerial: Integer;
  public
    /// <summary>Gleiche Datei: Groß-/Kleinschreibung (ASCII), „/“ und „\“ sowie Leerraum am Rand egal.</summary>
    class function SameFile(const A, B: string): Boolean; static;
    /// <summary>Neue Kennung: GUID ohne Klammern, ohne GUID Fallback mit der nächsten laufenden Nummer.</summary>
    class function NewId: string; static;
    /// <summary>Kennung ohne GUID aus AStampMs (Millisekunden) und ASerial; 20 Hex-Ziffern, klein.</summary>
    class function Fallback(AStampMs: Int64; ASerial: Cardinal): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Projects.Summary;

const
  cMsPerDay = 86400000;
  cStampDigits = 12;
  cSerialDigits = 8;

class function TAtlasMarkIds.SameFile(const A, B: string): Boolean;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(A) = TAtlasProjectSummaries.NormalizedPath(B);
end;

class function TAtlasMarkIds.NewId: string;
var
  mGuid: TGUID;
begin
  if CreateGUID(mGuid) <> 0 then
  begin
    Exit(Fallback(Trunc(Now * cMsPerDay), Cardinal(TInterlocked.Increment(FSerial))));
  end;
  Result := LowerCase(GUIDToString(mGuid));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

class function TAtlasMarkIds.Fallback(AStampMs: Int64; ASerial: Cardinal): string;
begin
  Result := LowerCase(IntToHex(AStampMs, cStampDigits) + IntToHex(ASerial, cSerialDigits));
end;

end.
