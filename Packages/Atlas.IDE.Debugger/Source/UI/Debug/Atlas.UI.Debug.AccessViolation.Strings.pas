unit Atlas.UI.Debug.AccessViolation.Strings;

// Texte der Erklärung von Zugriffsverletzungen, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasAccessViolationTextId = (
    DebugAvAnalysing, DebugAvNil, DebugAvField, DebugAvFieldEstimated, DebugAvOffset, DebugAvVmt, DebugAvFreed,
    DebugAvFreedPattern, DebugAvFreedHeader, DebugAvFreedMemory, DebugAvFreedMemoryDetail, DebugAvInvalid,
    DebugAvOutOfRange, DebugAvAmbiguous, DebugAvAmbiguousSeveral, DebugAvAmbiguousNone, DebugAvStatements,
    DebugAvNoChains, DebugAvNoServer, DebugAvStateCall, DebugAvStateNotEvaluated, DebugAvStateNotReached,
    DebugAvStateFailed, DebugAvStateFreed, DebugAvStateInvalid, DebugAvStateOutOfRange, DebugAvWhereAssigned,
    DebugAvEvaluate, DebugAvCopy, DebugAvMore, DebugAvMessage, DebugAvCopyHeader, DebugAvCopyChecked,
    DebugAvModuleProgram, DebugAvModuleRuntime, DebugAvModuleSystem, DebugAvModuleForeign, DebugAvModuleNoDebugInfo,
    DebugAvModuleOwnFrame, DebugAvModuleNoOwnFrame, DebugAvNoAnswer);

  TAtlasAccessViolationStrings = class
  public
    class function Text(AId: TAtlasAccessViolationTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasAccessViolationTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasAccessViolationTextId] of string = (
    ('Atlas prüft, welcher Teil der Zeile nil war …',
     '%s ist nil',
     'Zugriff auf Feld %s (Versatz %s)',
     'Zugriff auf Feld %s (Versatz %s, geschätzt)',
     'Versatz %s, kein Feld bekannt',
     'Zugriff auf die VMT (virtuelle Methode, is/as oder ClassType)',
     '%s ist bereits freigegeben',
     'Füllmuster des Speichermanagers %s',
     'Kopf des Objekts trägt das Füllmuster des Speichermanagers',
     'Zugriff auf freigegebenen Speicher',
     'Adresse %s liegt im Füllmuster des Speichermanagers; vermutlich ist ein Objekt der Zeile freigegeben',
     '%s zeigt ins Leere (%s)',
     'Index %s = %d liegt außerhalb von %s (Länge %d)',
     'Ursache nicht eindeutig',
     '%d Glieder kommen in Frage',
     'kein geprüftes Glied ist nil oder freigegeben',
     '%d Anweisungen in der Zeile',
     'keine Zugriffskette in der Zeile',
     'Atlas-Server antwortet nicht',
     'nicht ausgewertet: ruft etwas auf (debug.explainAccessViolation.allowCalls)',
     'nicht ausgewertet',
     'nicht erreicht',
     'nicht auswertbar',
     'freigegeben',
     'ungültig',
     'Index außerhalb',
     'Wo wird %s zugewiesen?',
     'Ausdruck auswerten',
     'Erklärung kopieren',
     '… %d weitere',
     'Zugriffsverletzung in %s: %s',
     'Zugriffsverletzung erklärt (Atlas)',
     'Geprüft:',
     'Adresse liegt in deinem Programm (%s)',
     'Adresse liegt in %s (RTL/VCL)',
     'Adresse liegt in %s (Windows)',
     'Adresse liegt in %s',
     'Adresse liegt in %s (keine Debug-Infos)',
     'zuletzt in deinem Code: %s:%d (%s)',
     'kein eigener Code im Aufrufstapel',
     '‹keine Antwort des Debuggers›'),
    ('Atlas is checking which part of the line was nil …',
     '%s is nil',
     'Access to field %s (offset %s)',
     'Access to field %s (offset %s, estimated)',
     'Offset %s, no known field',
     'Access to the VMT (virtual method, is/as or ClassType)',
     '%s has already been freed',
     'Memory manager fill pattern %s',
     'The object header carries the memory manager fill pattern',
     'Access to freed memory',
     'Address %s lies in the memory manager fill pattern; an object on the line has probably been freed',
     '%s points nowhere (%s)',
     'Index %s = %d is outside %s (length %d)',
     'Cause not clear',
     '%d links are candidates',
     'no checked link is nil or freed',
     '%d statements on the line',
     'no access chain on the line',
     'Atlas server does not answer',
     'not evaluated: calls code (debug.explainAccessViolation.allowCalls)',
     'not evaluated',
     'not reached',
     'cannot be evaluated',
     'freed',
     'invalid',
     'index out of range',
     'Where is %s assigned?',
     'Evaluate expression',
     'Copy explanation',
     '… %d more',
     'Access violation in %s: %s',
     'Access violation explained (Atlas)',
     'Checked:',
     'The address lies in your program (%s)',
     'The address lies in %s (RTL/VCL)',
     'The address lies in %s (Windows)',
     'The address lies in %s',
     'The address lies in %s (no debug information)',
     'last in your code: %s:%d (%s)',
     'no own code in the call stack',
     '‹no answer from the debugger›'));

{ TAtlasAccessViolationStrings }

class function TAtlasAccessViolationStrings.Text(AId: TAtlasAccessViolationTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasAccessViolationStrings.Fmt(AId: TAtlasAccessViolationTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
