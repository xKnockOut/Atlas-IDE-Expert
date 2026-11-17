unit Atlas.Common.Diagnostics.ShutdownLeaks;

// Speicherrest beim Beenden melden, ohne Dialog (#177). ReportMemoryLeaksOnShutdown zeigt beim Speichermanager
// der RTL ein modales Fenster; im unsichtbar gestarteten Server blockiert das das Beenden, im Testlauf hängt der
// Job. Gemeldet wird nur die Zahl der Bytes, ohne Namen (#647).
//
// Gemessen wird in Atlas.Common.Diagnostics.ShutdownRest, das als erste Unit im uses der .dpr steht. Diese Unit
// liefert nur die Texte in der Sprache beim Einschalten; sie braucht SysUtils und die Texttabellen und darf
// deshalb nicht selbst messen.
//
// Mit Expect wird der Rest zum Kriterium (Testlauf): Die Messung je Test kann eine Belegung, die beim ersten
// Gebrauch entsteht und nie freigegeben wird, nicht von einem Zwischenspeicher unterscheiden, der bis zum
// Programmende lebt und dort freigegeben wird. Das kann nur diese Messung. Das Beenden meldet den Rest dann
// immer (auch 0, als Nachweis, dass gemessen wurde) samt Grenze und setzt über der Grenze den Exit-Code. Skripte,
// die den Lauf auswerten, lesen dieselbe Zeile, falls der Exit-Code den Prozess nicht erreicht.

interface

uses
  Atlas.Common.Diagnostics.ShutdownRest;

type
  TShutdownLeaks = record
  public
    /// <summary>Belegter Speicher des Speichermanagers in Bytes.</summary>
    class function AllocatedBytes: Int64; static;
    /// <summary>Meldetext, z. B. "Speicherrest beim Beenden: 128 Bytes".</summary>
    class function Describe(ABytes: Int64): string; static;
    /// <summary>Meldetext mit Grenze, z. B. "Speicherrest beim Beenden: 128 Bytes (erlaubt: 0)".</summary>
    class function DescribeLimit(ABytes, AMaxBytes: Int64): string; static;
    /// <summary>Melden einschalten (Debug-Build): Ein Rest über 0 geht beim Beenden als Zeile an AReport.
    /// </summary>
    class procedure Enable(AReport: TShutdownRestReport); static;
    /// <summary>Beim Beenden darf höchstens AMaxBytes mehr belegt sein als beim Start. Ab jetzt geht der Rest
    /// immer an den Empfänger aus Enable, mit Grenze; darüber setzt das Beenden, falls noch 0, den Exit-Code
    /// AExitCode.</summary>
    class procedure Expect(AMaxBytes: Int64; AExitCode: Integer); static;
    /// <summary>Datei, an die beim Beenden die Zeile angehängt wird; nur wenn sie dann existiert.</summary>
    class procedure SetLogFile(const AFileName: string); static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TShutdownLeaksText = (MemoryLeftAtShutdownBytes, MemoryLeftAtShutdownLimit);

const
  cTexts: array[TShutdownLeaksText] of TAtlasText = (
    (De: 'Speicherrest beim Beenden: %d Bytes'; En: 'Memory left at shutdown: %d bytes'),
    (De: 'Speicherrest beim Beenden: %d Bytes (erlaubt: %d)'; En: 'Memory left at shutdown: %d bytes (allowed: %d)'));

{$SCOPEDENUMS OFF}

{ TShutdownLeaks }

class function TShutdownLeaks.AllocatedBytes: Int64;
begin
  Result := TShutdownRest.AllocatedBytes;
end;

class function TShutdownLeaks.Describe(ABytes: Int64): string;
begin
  Result := TShutdownRest.Render(cTexts[TShutdownLeaksText.MemoryLeftAtShutdownBytes].Text, ABytes, 0);
end;

class function TShutdownLeaks.DescribeLimit(ABytes, AMaxBytes: Int64): string;
begin
  Result := TShutdownRest.Render(cTexts[TShutdownLeaksText.MemoryLeftAtShutdownLimit].Text, ABytes, AMaxBytes);
end;

class procedure TShutdownLeaks.Enable(AReport: TShutdownRestReport);
begin
  TShutdownRest.SetReport(cTexts[TShutdownLeaksText.MemoryLeftAtShutdownBytes].Text, AReport);
end;

class procedure TShutdownLeaks.Expect(AMaxBytes: Int64; AExitCode: Integer);
begin
  TShutdownRest.SetLimit(cTexts[TShutdownLeaksText.MemoryLeftAtShutdownLimit].Text, AMaxBytes, AExitCode);
end;

class procedure TShutdownLeaks.SetLogFile(const AFileName: string);
begin
  TShutdownRest.SetLogFile(AFileName);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Diagnostics.ShutdownLeaks', cTexts);

end.
