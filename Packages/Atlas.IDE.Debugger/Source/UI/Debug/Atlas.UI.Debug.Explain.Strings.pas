unit Atlas.UI.Debug.Explain.Strings;

// Erklärungen im Editor: warum ein Wert nicht verfügbar ist, warum der Debugger hier steht und welche Zweige folgen,
// auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasExplainTextId = (
    DebugUnavailableCaption, DebugUnavailableRelease, DebugUnavailableNoDebugInfo, DebugUnavailableNoLocalSymbols,
    DebugUnavailableOptimization, DebugUnavailableLifetime, DebugUnavailableNotYet, DebugUnavailableNoLonger,
    DebugUnavailableUnused, DebugUnavailableInline, DebugUnavailableLibrary, DebugUnavailableUnknown,
    DebugUnavailableOriginDirective, DebugUnavailableOriginProject, DebugUnavailableOriginDefault,
    DebugUnavailableCheckConfiguration, DebugUnavailableCheckSymbols, DebugUnavailableCheckOptimization,
    DebugUnavailableCheckLifetime, DebugUnavailableCheckInline, DebugUnavailableCheckLibrary,
    DebugUnavailableFixRestart, DebugUnavailableFixRoutine, DebugUnavailableFixUnit, DebugUnavailableFixDcus,
    DebugUnavailableFixDirective, DebugUnavailableConfirmEdit, DebugUnavailableConfirmRestart,
    DebugUnavailableConfirmDcus, DebugUnavailableDcusDone, DebugUnavailableEditDone,
    DebugUnavailableNoDebugConfiguration, DebugUnavailableNoResetAction, WhyHereNotNeeded, WhyHereNotEvaluated,
    WhyHereElseBranch, WhyHereOf, WhyHereConfirmCalls, PredictNoBranch, PredictOffForSession);

  TAtlasExplainStrings = class
  public
    class function Text(AId: TAtlasExplainTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasExplainTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasExplainTextId] of string = (
    ('‹kein Zugriff›',
     'Das Programm läuft in der Konfiguration „%s“ ohne Debug-Informationen.',
     'Die Unit ist an dieser Stelle ohne Debug-Informationen übersetzt ($D-).',
     'Die Unit ist an dieser Stelle ohne lokale Symbole übersetzt ($L-); lokale Variablen kennt der Debugger nicht.',
     'Die Optimierung ist an ($O+): Die Variable liegt vermutlich in einem Register, das gerade anders belegt ist.',
     'Vermutlich ist die Lebensdauer der Variablen hier überschritten oder noch nicht begonnen.',
     'Sie wird erst ab Zeile %d gebraucht.',
     'Nach Zeile %d wird sie nicht mehr gebraucht.',
     'Sie wird in der Routine nicht verwendet.',
     'Die Routine %s ist inline: Eingebettet kennt der Debugger ihre Variablen nicht. Zum Debuggen {$INLINE OFF} setzen oder in der aufrufenden Routine anhalten.',
     'Der Halt liegt in Bibliothekscode (RTL, VCL), übersetzt ohne Debug-DCUs.',
     'Ursache unbekannt.',
     '%s in %s, Zeile %d',
     '%s in der Konfiguration „%s“',
     'Vorgabe des Compilers',
     'Start mit Debug-Informationen',
     'Schalter $D und $L an der Stelle',
     'Optimierung ($O) an der Stelle',
     'Lebensdauer der Variablen am Halt',
     'Routine nicht inline',
     'Halt im eigenen Code oder mit Debug-DCUs',
     'Mit Debug neu starten',
     'Optimierung für die Routine aus',
     '{$O-} am Unit-Anfang',
     'Debug-DCUs verwenden',
     'Zur Direktive',
     'Atlas fügt in %s ein:%s%s%sZurücknehmen mit Strg+Z oder „Letzte Atlas-Änderung zurücknehmen“.',
     'Atlas setzt das laufende Programm zurück, wählt die Konfiguration „%s“ (bisher „%s“) und startet neu.%sZurück: die frühere Konfiguration in der Projektverwaltung wieder wählen.',
     'Atlas schaltet in der Konfiguration „%s“ von %s „Debug-DCUs verwenden“ ein (DCC_DebugDCUs, bisher %s). Das wirkt beim nächsten Übersetzen.%sZurück: in den Projektoptionen „Debug-DCUs verwenden“ wieder ausschalten (Strg+Z gibt es dort nicht).',
     'Atlas: Debug-DCUs in „%s“ eingeschaltet (vorher %s); zurück in den Projektoptionen.',
     'Atlas: %s in %s eingefügt; Strg+Z nimmt es zurück.',
     'Atlas: Das Projekt hat keine Konfiguration mit Debug-Informationen.',
     'Atlas: „Programm zurücksetzen“ der IDE nicht gefunden.',
     'nicht nötig',
     '‹Aufruf›',
     'else-Zweig',
     'von',
     'Diese Aufrufe im Programm ausführen, um die Bedingung zu zeigen?'#13#10#13#10'%s'#13#10#13#10'Sie können Nebenwirkungen haben.',
     'kein Zweig',
     'Vorhersage für diese Sitzung aus'),
    ('‹no access›',
     'The program runs in configuration "%s" without debug information.',
     'This unit is compiled without debug information here ($D-).',
     'This unit is compiled without local symbols here ($L-); the debugger does not know local variables.',
     'Optimization is on ($O+): the variable probably lives in a register that currently holds something else.',
     'The variable''s lifetime has probably ended here or not yet begun.',
     'It is first needed in line %d.',
     'It is no longer needed after line %d.',
     'It is not used in the routine.',
     'Routine %s is inline: once inlined, the debugger does not know its variables. Set {$INLINE OFF} for debugging or stop in the calling routine.',
     'Execution stopped in library code (RTL, VCL) compiled without debug DCUs.',
     'Cause unknown.',
     '%s in %s, line %d',
     '%s in configuration "%s"',
     'Compiler default',
     'Started with debug information',
     'Switches $D and $L at this position',
     'Optimization ($O) at this position',
     'Lifetime of the variable at the stop',
     'Routine not inline',
     'Stopped in own code or with debug DCUs',
     'Restart with Debug',
     'Optimization off for the routine',
     '{$O-} at the start of the unit',
     'Use debug DCUs',
     'Go to directive',
     'Atlas inserts into %s:%s%s%sUndo with Ctrl+Z or "Undo last Atlas change".',
     'Atlas resets the running program, selects configuration "%s" (was "%s") and starts again.%sTo go back, select the previous configuration in the Projects window.',
     'Atlas turns on "Use debug DCUs" in configuration "%s" of %s (DCC_DebugDCUs, was %s). It takes effect on the next compile.%sTo go back, turn "Use debug DCUs" off again in the project options (there is no Ctrl+Z there).',
     'Atlas: debug DCUs turned on in "%s" (was %s); revert in the project options.',
     'Atlas: %s inserted into %s; Ctrl+Z undoes it.',
     'Atlas: the project has no configuration with debug information.',
     'Atlas: the IDE''s "Program Reset" was not found.',
     'not needed',
     '‹call›',
     'else branch',
     'of',
     'Run these calls in the program to show the condition?'#13#10#13#10'%s'#13#10#13#10'They may have side effects.',
     'no branch',
     'Turn off the forecast for this session'));

{ TAtlasExplainStrings }

class function TAtlasExplainStrings.Text(AId: TAtlasExplainTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasExplainStrings.Fmt(AId: TAtlasExplainTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
