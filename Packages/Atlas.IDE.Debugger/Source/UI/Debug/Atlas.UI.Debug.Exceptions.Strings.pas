unit Atlas.UI.Debug.Exceptions.Strings;

// Texte zu Exceptions: Fenster „Exceptions“, Exception-Leiste im Editor, nur eigener Code und Debug-Notiz, auf
// Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasExceptionsTextId = (
    DebugExceptionsCaption, DebugExceptionsFilterHint, DebugExceptionsGoTo, DebugExceptionsIgnoreClass,
    DebugExceptionsStopAgain, DebugExceptionsIgnoreClassNamed, DebugExceptionsStopAgainNamed, DebugExceptionsCopy,
    DebugExceptionsClear, DebugExceptionsColumnTime, DebugExceptionsColumnClass, DebugExceptionsColumnMessage,
    DebugExceptionsColumnCount, DebugExceptionsColumnLocation, DebugExceptionsColumnThread, DebugExceptionsEmpty,
    DebugExceptionsIgnored, DebugExceptionsThread, DebugExceptionsAllClasses, DebugExceptionsSummary,
    DebugExceptionsFault, DebugExceptionsUnknownClass, DebugExceptionsIgnoredClassSaid, DebugExceptionsStopAgainSaid,
    DebugExceptionsNoSource, DebugJustMyCodeOn, DebugJustMyCodeOff, DebugJustMyCodeJumped, DebugExceptionsStackCaption,
    DebugExceptionsStackLibrary, DebugExceptionsStackEmpty, DebugBannerBreak, DebugBannerContinue,
    DebugBannerIgnoreClass, DebugBannerIgnoreLocation, DebugBannerCopy, DebugBannerThread, DebugBannerCount,
    DebugBannerHidden, DebugBannerKeys, DebugBannerOpenHint, DebugBannerIdeDialogOn, DebugBannerIdeDialogOff,
    DebugBannerIgnoredLocationSaid, DebugBannerUnknownVersion, DebugBannerUnknownVersionSummary, DebugNoteTitle,
    DebugNoteProject, DebugNoteConfiguration, DebugNotePlatform, DebugNoteTime, DebugNoteThread, DebugNoteLocation,
    DebugNoteCallStack, DebugNoteLastException, DebugNoteCount, DebugNoteNoLocation, DebugNoteFileStem,
    DebugBannerCreateTest, DebugKnownFound, DebugKnownResolved, DebugKnownOpen, DebugKnownComment, DebugKnownReopen,
    DebugKnownNew);

  TAtlasExceptionsStrings = class
  public
    class function Text(AId: TAtlasExceptionsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasExceptionsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasExceptionsTextId] of string = (
    ('Atlas: Exceptions',
     'Filtern nach Klasse, Meldung, Ort',
     'Zur Stelle springen',
     'Klasse künftig ignorieren',
     'Bei dieser Klasse wieder anhalten',
     '%s künftig ignorieren',
     'Bei %s wieder anhalten',
     'Kopieren (Klasse, Meldung, Aufrufstapel)',
     'Verlauf leeren',
     'Zeit',
     'Klasse',
     'Meldung',
     'Anzahl',
     'Ort',
     'Thread',
     'Noch keine Exception in dieser Debug-Sitzung.'#13#10#13#10 +
     'Hier sammelt Atlas jede Exception, die der Debugger beim Lauf Ihres Programms meldet, auch abgefangene. ' +
     'Gleiche Exceptions (Klasse, Meldung, Ort) stehen in einer Zeile mit Anzahl.'#13#10#13#10 +
     'Oben filtern Sie nach Text oder Klasse. Ein Doppelklick springt zur Stelle im Quelltext, darunter steht der ' +
     'Aufrufstapel der gewählten Exception. Über das Kontextmenü ignorieren Sie eine Klasse künftig (Atlas setzt ' +
     'dann still fort), lassen den Debugger bei ihr wieder anhalten, kopieren Klasse, Meldung und Aufrufstapel oder ' +
     'leeren den Verlauf.',
     'ignoriert',
     'Hauptthread',
     'Alle Klassen',
     '%d Einträge, %d Exceptions in dieser Sitzung',
     'Fehler des Betriebssystems',
     'Exception',
     'Atlas: %s wird künftig ignoriert; Atlas setzt bei dieser Klasse still fort.',
     'Atlas: Bei %s hält der Debugger wieder an.',
     'Atlas: Quelltext %s nicht gefunden.',
     'Atlas: Nur eigener Code beim Debuggen ist an.',
     'Atlas: Nur eigener Code beim Debuggen ist aus; die IDE verhält sich wie ohne Atlas.',
     'Atlas: Exception in Bibliothekscode; eigener Code: %s:%d (%d Ebenen darüber, Ursprung im Aufrufstapel).',
     'Aufrufstapel',
     '… %d Bibliotheksrahmen',
     'Kein Aufrufstapel bekannt.',
     'Anhalten',
     'Fortsetzen',
     'Klasse ignorieren',
     'Nur an dieser Stelle ignorieren',
     'Meldung kopieren',
     'Thread: %s',
     '%d× an dieser Stelle',
     '%d Ebenen ausgeblendet',
     'F9 Fortsetzen · F8/Esc Anhalten',
     'Zur Zeile springen',
     'Atlas: Bis zum Ende der Debug-Sitzung zeigt die IDE ihren Exception-Dialog; die Leiste kommt danach dazu.',
     'Atlas: Die Exception-Leiste ersetzt wieder den Dialog der IDE.',
     'Atlas: %s an %s wird in diesem Projekt künftig still fortgesetzt (im Verlauf gezählt).',
     'Exception-Leiste: IDE-Version nicht geprüft, der Dialog der IDE bleibt (Leiste danach)',
     'Exception-Dialog bleibt',
     'Debug-Notiz',
     'Projekt',
     'Konfiguration',
     'Plattform',
     'Zeit',
     'Thread',
     'Ort',
     'Aufrufstapel',
     'Letzte Exception',
     '%d x an dieser Stelle',
     'Kein Halt mit Quelltext.',
     'debug-notiz',
     'Test daraus anlegen …',
     #$2691 + ' Bekannter Fehler: %s',
     #$2691 + ' Erledigt: %s ' + #$2013 + ' wieder aufgetreten?',
     'Issue öffnen',
     'Als Kommentar anhängen',
     'Wieder öffnen …',
     'Neues Issue …'),
    ('Atlas: Exceptions',
     'Filter by class, message, location',
     'Go to location',
     'Ignore class from now on',
     'Stop again on this class',
     'Ignore %s from now on',
     'Stop again on %s',
     'Copy (class, message, call stack)',
     'Clear history',
     'Time',
     'Class',
     'Message',
     'Count',
     'Location',
     'Thread',
     'No exception in this debug session yet.'#13#10#13#10 +
     'Atlas collects every exception the debugger reports while your program runs, including handled ones. ' +
     'Identical exceptions (class, message, location) share one row with a count.'#13#10#13#10 +
     'Filter by text or class at the top. A double-click goes to the source location; below, you see the call stack ' +
     'of the selected exception. The context menu ignores a class from now on (Atlas then continues silently), ' +
     'stops on it again, copies class, message and call stack, or clears the history.',
     'ignored',
     'Main thread',
     'All classes',
     '%d entries, %d exceptions in this session',
     'Operating system fault',
     'Exception',
     'Atlas: %s is ignored from now on; Atlas continues silently on this class.',
     'Atlas: The debugger stops on %s again.',
     'Atlas: Source %s not found.',
     'Atlas: Just my code while debugging is on.',
     'Atlas: Just my code while debugging is off; the IDE behaves as without Atlas.',
     'Atlas: Exception in library code; own code: %s:%d (%d levels up, origin in the call stack).',
     'Call stack',
     '… %d library frames',
     'No call stack known.',
     'Break',
     'Continue',
     'Ignore class',
     'Ignore only here',
     'Copy message',
     'Thread: %s',
     '%d× at this location',
     '%d levels hidden',
     'F9 Continue · F8/Esc Break',
     'Go to line',
     'Atlas: Until the debug session ends, the IDE shows its exception dialog; the bar follows it.',
     'Atlas: The exception bar replaces the IDE dialog again.',
     'Atlas: %s at %s is continued silently in this project from now on (counted in the history).',
     'Exception bar: IDE version not verified, the IDE dialog stays (bar afterwards)',
     'Exception dialog stays',
     'Debug note',
     'Project',
     'Configuration',
     'Platform',
     'Time',
     'Thread',
     'Location',
     'Call stack',
     'Last exception',
     '%d times at this location',
     'Not stopped in source code.',
     'debug-note',
     'Create test …',
     #$2691 + ' Known error: %s',
     #$2691 + ' Resolved: %s ' + #$2013 + ' occurred again?',
     'Open issue',
     'Add as comment',
     'Reopen …',
     'New issue …'));

{ TAtlasExceptionsStrings }

class function TAtlasExceptionsStrings.Text(AId: TAtlasExceptionsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasExceptionsStrings.Fmt(AId: TAtlasExceptionsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
