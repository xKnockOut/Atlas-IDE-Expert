unit Atlas.UI.Debug.RuntimeReport.Strings;

// Texte zu eingefügten Leck- und Absturzberichten, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasRuntimeReportTextId = (
    RuntimeReportNoProject, RuntimeReportEmpty, RuntimeReportNoServer, RuntimeReportNone, RuntimeReportCrashTitle,
    RuntimeReportLeakTitle, RuntimeReportMapMissing, RuntimeReportMapDiffers, RuntimeReportGroup,
    RuntimeReportCrashedThread, RuntimeReportThread, RuntimeReportMore, RuntimeReportLine, RuntimeReportCrashSite,
    RuntimeReportLeakSite, RuntimeReportMarked, RuntimeReportCleared);

  TAtlasRuntimeReportStrings = class
  public
    class function Text(AId: TAtlasRuntimeReportTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasRuntimeReportTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasRuntimeReportTextId] of string = (
    ('Atlas: Kein Projekt geöffnet; der Bericht braucht das Projekt für Map-Datei und Quelltexte.',
     'Atlas: Die Zwischenablage enthält keinen Text. Bericht kopieren und den Befehl noch einmal wählen.',
     'Atlas: Der Server antwortet nicht; der Bericht wurde nicht ausgewertet.',
     'Atlas: Kein Leck- oder Absturzbericht erkannt (FastMM, ReportMemoryLeaksOnShutdown, madExcept, EurekaLog, ' +
     'JclDebug oder Meldung einer Exception).',
     'Atlas: Absturz (%s): %s',
     'Atlas: Lecks (%s): %s',
     'Atlas: Map-Datei %s fehlt; Zeilen ohne Debug-Informationen bleiben offen (Linker-Option „Map-Datei: ' +
     'Detailliert“).',
     'Atlas: Map-Datei %s gehört nicht zur EXE; Zeilen können falsch sein.',
     '  %s × %d (%d Bytes)',
     '  Thread der Exception: %s',
     '  Thread: %s',
     '  … %d weitere',
     ', Zeile %d',
     '  ← Absturzstelle',
     '  ← Erzeugungsstelle',
     'Atlas: %d Stellen im Editor markiert.',
     'Atlas: Markierungen des Laufzeitberichts entfernt.'),
    ('Atlas: No project is open; the report needs the project for the map file and sources.',
     'Atlas: The clipboard holds no text. Copy the report and choose the command again.',
     'Atlas: The server does not answer; the report was not analyzed.',
     'Atlas: No leak or crash report recognized (FastMM, ReportMemoryLeaksOnShutdown, madExcept, EurekaLog, ' +
     'JclDebug or an exception message).',
     'Atlas: Crash (%s): %s',
     'Atlas: Leaks (%s): %s',
     'Atlas: Map file %s is missing; lines without debug information stay open (linker option "Map file: ' +
     'Detailed").',
     'Atlas: Map file %s does not belong to the EXE; lines may be wrong.',
     '  %s × %d (%d bytes)',
     '  Thread of the exception: %s',
     '  Thread: %s',
     '  … %d more',
     ', line %d',
     '  ← crash site',
     '  ← creation site',
     'Atlas: %d locations marked in the editor.',
     'Atlas: Runtime report markers removed.'));

{ TAtlasRuntimeReportStrings }

class function TAtlasRuntimeReportStrings.Text(AId: TAtlasRuntimeReportTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasRuntimeReportStrings.Fmt(AId: TAtlasRuntimeReportTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
