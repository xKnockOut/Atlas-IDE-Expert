unit Atlas.Core.Settings.Plugin.Debug;

// Einstellungen des IDE-Plugins, Bereich Debuggen (debug.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen für debug.inlineValuesPerLine (#508).</summary>
  cMinInlineValuesPerLine = 1;
  cMaxInlineValuesPerLine = 20;
  /// <summary>Grenzen für debug.whyHere.depth (#1878).</summary>
  cMinWhyHereDepth = 1;
  cMaxWhyHereDepth = 10;
  cDefaultWhyHereDepth = 3;
  /// <summary>Vorgabe von debug.eventLogColors (#580): Muster=Farbe, durch „;“ getrennt.</summary>
  cDefaultEventLogColors = '[FEHLER]=#D13438; [ERROR]=#D13438; [WARN]=#C19C00';
  /// <summary>Grenzen für debug.parallelStacks.maxThreads (#837).</summary>
  cMinParallelStacksThreads = 1;
  cMaxParallelStacksThreads = 1024;
  /// <summary>Vorgabe von debug.parallelStacks.maxThreads.</summary>
  cDefaultParallelStacksThreads = 64;
  /// <summary>Vorgabe von debug.logpointPrefix (#583).</summary>
  cDefaultLogpointPrefix = '[LOG]';
  /// <summary>Grenzen und Vorgabe für debug.asyncOrigin.maxPerSite (#859).</summary>
  cMinAsyncOriginPerSite = 1;
  cMaxAsyncOriginPerSite = 1000;
  cDefaultAsyncOriginPerSite = 20;
  /// <summary>Vorgabe von debug.reattach.key (#2171): Umschalt+Alt+P.</summary>
  cDefaultReattachKey = $A050;
  /// <summary>Vorgabe und Grenzen von debug.reattach.waitIntervalMs (#2171).</summary>
  cDefaultReattachWaitMs = 100;
  cMinReattachWaitMs = 20;
  cMaxReattachWaitMs = 2000;

type
  /// <summary>Plugin-Einstellungen: Debuggen.</summary>
  TAtlasPluginDebugSettings = record
    /// <summary>Einzelnen Test im Debugger starten (#585, tests.debug): Befehl „Test am Cursor debuggen“
    /// (Atlas.DebugTest) mit Tipp, Eintrag im Kontextmenü und Marke „Debuggen“ der Code Lens; braucht TestRun. Aus
    /// = Befehl, Tipp und Marke verschwinden.</summary>
    TestDebug: Boolean;
    /// <summary>Beim Test-Debuggen am Anfang der Methode anhalten (#585, debug.testBreakAtStart): einmaliger
    /// Haltepunkt an der ersten Anweisung, nach dem Halt entfernt.</summary>
    TestBreakAtStart: Boolean;
    /// <summary>Variablenwerte im Hover beim Debuggen (#891, debug.hoverValues): Bei angehaltenem Prozess wertet
    /// Atlas den Ausdruck unter der Maus über den Debugger der IDE aus und zeigt den Wert oben im Tooltip (bzw.
    /// im Tooltip der IDE, wenn der eigene aus ist); aus = kein Wert.</summary>
    DebugHoverValues: Boolean;
    /// <summary>Visualisierer für häufige Typen (#835, debug.visualizers): Ersatztexte für Listen, Dictionaries,
    /// Datenmengen, Bytes und Streams, JSON, Farben, TGUID, Geometrie und Grafiken im Hover, in Überwachten
    /// Ausdrücken und Lokalen Variablen, dazu das Ansichtsfenster über die Lupe; aus = die IDE zeigt ihre Texte.
    /// </summary>
    DebugVisualizers: Boolean;
    /// <summary>Arten der Visualisierer (debug.visualizers.types), kommagetrennt, normalisiert.</summary>
    DebugVisualizerTypes: string;
    /// <summary>Namensfelder für Objekte in Listen (debug.visualizers.nameFields).</summary>
    DebugVisualizerNameFields: string;
    /// <summary>Höchstlänge des Ersatztexts (debug.visualizers.maxLength).</summary>
    DebugVisualizerMaxLength: Integer;
    /// <summary>Zeitlimit je Auswertung in ms (debug.visualizers.timeoutMs).</summary>
    DebugVisualizerTimeoutMs: Integer;
    /// <summary>Größtes gelesenes Bild in Pixeln (debug.visualizers.maxImagePixels).</summary>
    DebugVisualizerMaxImagePixels: Integer;
    /// <summary>fields, properties oder calls (debug.visualizers.evaluation).</summary>
    DebugVisualizerEvaluation: string;
    /// <summary>Eigene Wertdarstellungen (#854, debug.displayRules): Regeln aus // atlas-debug:,
    /// [AtlasDebugDisplay] und der Projektdatei .atlas im Hover, in Überwachten Ausdrücken und Lokalen Variablen;
    /// aus = die IDE zeigt ihre eigenen Werte.</summary>
    DebugDisplayRules: Boolean;
    /// <summary>Getter und Funktionsaufrufe in Vorlagen auswerten (debug.displayRules.allowCalls); aus = nur Felder
    /// und Eigenschaften mit direktem Feldzugriff.</summary>
    DebugDisplayRulesAllowCalls: Boolean;
    /// <summary>Gezielt hineinspringen (#836, debug.stepIntoTarget): Befehl mit Tastenkürzel, Kontextmenü und
    /// Befehlspalette, der im angehaltenen Zustand die Aufrufe der Anweisung zur Wahl stellt; aus = Kürzel frei, kein
    /// Menüeintrag.</summary>
    DebugStepIntoTarget: Boolean;
    /// <summary>debug.stepFilters (#850): F7 überspringt eigene Routinen der Arten aus debug.stepFilters.kinds und
    /// Methoden nach debug.stepFilters.patterns und hält in der Routine, um die es geht; Umschalt+F7 springt ohne
    /// Filter hinein.</summary>
    DebugStepFilters: Boolean;
    /// <summary>Gefilterte Arten (debug.stepFilters.kinds, kommagetrennt): getters, setters, trivial, operators,
    /// emptyConstructors; Vorgabe getters,trivial.</summary>
    DebugStepFilterKinds: string;
    /// <summary>Gefilterte Methoden nach Muster (debug.stepFilters.patterns): Unit.Klasse.Methode mit * als
    /// Platzhalter, durch ; getrennt.</summary>
    DebugStepFilterPatterns: string;
    /// <summary>Tastenkürzel „Gezielt hineinspringen“ (debug.stepIntoTarget.key, 0 = keins).</summary>
    DebugStepIntoTargetKey: Integer;
    /// <summary>Beim nächsten Ereignis anhalten (#856, debug.breakOnNextEvent): Befehl im Menü Start und in der
    /// Befehlspalette, der vorübergehende Haltepunkte auf die Ereignis-Handler setzt; aus = kein Befehl, kein
    /// Menüeintrag.</summary>
    DebugBreakOnNextEvent: Boolean;
    /// <summary>Häufige Ereignisse, die nur auf ausdrückliche Wahl beobachtet werden
    /// (debug.breakOnNextEvent.excluded, kommagetrennt).</summary>
    DebugBreakOnNextEventExcluded: string;
    /// <summary>Haltepunkte, die nicht greifen werden (#577, debug.checkBreakpoints): Vor dem Start einer
    /// Debug-Sitzung meldet Atlas Haltepunkte auf Zeilen ohne Code, in inaktiven Zweigen, unter {$D-} und in Units
    /// anderer Projekte der Gruppe, mit Verschieben auf die nächste Codezeile; dazu der Befehl „Haltepunkte prüfen“.
    /// Aus = keine Prüfung, kein Befehl.</summary>
    DebugCheckBreakpoints: Boolean;
    /// <summary>Haltepunkt nur für ein Objekt (#857, debug.instanceBreakpoints): Befehle „Haltepunkt nur für dieses
    /// Objekt“ (Bedingung auf die Adresse von Self) und „Haltepunkt nur wenn …“ (Feldwert von Self) im Kontextmenü
    /// des Editors; vor dem nächsten Start die Frage zu Adressbedingungen der letzten Sitzung. Aus = keine Befehle,
    /// keine Frage.</summary>
    DebugInstanceBreakpoints: Boolean;
    /// <summary>Haltepunkt-Sätze (#586, debug.breakpointSetPerBranch): Ein Satz mit Branch wird beim Wechsel der
    /// Arbeitskopie auf diesen Branch aktiv. Aus = Sätze nur über die Befehle.</summary>
    DebugBreakpointSetPerBranch: Boolean;
    /// <summary>„kein Zugriff auf Wert“ erklären (#840, debug.explainUnavailable): Scheitert die Auswertung im Hover
    /// oder in den Werten im Editor mit einem bekannten Text der IDE, zeigt Atlas „‹kein Zugriff›“ mit Ursache
    /// (Release-Start, $D-/$L-, $O+, Lebensdauer, inline, Bibliothek ohne Debug-DCUs), Herkunft des Schalters und
    /// Korrekturen. Aus = Fehler wie bisher ausgeblendet, keine Anfrage.</summary>
    DebugExplainUnavailable: Boolean;
    /// <summary>Vervollständigung in Debugger-Dialogen (#538, debug.completionInDialogs): In „Auswerten/Ändern“, im
    /// Überwachungsausdruck und in Bedingung und Log-Ausdruck eines Haltepunkts bietet Atlas Bezeichner aus dem
    /// Gültigkeitsbereich des Ausführungspunkts bzw. der Haltepunktzeile an; Pfeil nach unten im leeren Feld zeigt
    /// die letzten 20 Ausdrücke des Projekts. Aus = kein Zeitgeber, keine Anfrage, kein Verlauf.</summary>
    DebugCompletionInDialogs: Boolean;
    /// <summary>Fenster „Auswerten“ (#784, debug.evaluateWindow): andockbares Fenster mit mehreren Ausdrücken, die
    /// bei jedem Halt neu ausgewertet werden; Objekte, Records und Arrays klappen auf (Felder aus dem Atlas-Index),
    /// geänderte Werte sind markiert, Ansichten Text, Zeilen, JSON und Hex, Ändern, Festheften, Verlauf mit 50
    /// Ausdrücken je Projekt. Aus = kein Fenster, kein Befehl, Strg+F7 bleibt bei der IDE.</summary>
    DebugEvaluateWindow: Boolean;
    /// <summary>Strg+F7 öffnet das Fenster „Auswerten“ (#784, debug.evaluateWindow.replaceCtrlF7) mit dem Ausdruck
    /// unter dem Cursor statt des Dialogs „Auswerten/Ändern“; mit Umschalttaste bzw. Befehl
    /// Atlas.DebugEvaluateIdeDialog kommt der Dialog der IDE. Aus = Strg+F7 gehört der IDE.</summary>
    DebugEvaluateReplaceCtrlF7: Boolean;
    /// <summary>debug.explainAccessViolation (#865): Beim Halt wegen einer Zugriffsverletzung in eigenem Code die
    /// Zugriffsketten der Zeile auswerten und das nil-Glied, ein freigegebenes Objekt oder einen Index außerhalb in
    /// der Exception-Leiste bzw. in den Meldungen nennen.</summary>
    DebugExplainAccessViolation: Boolean;
    /// <summary>debug.explainAccessViolation.allowCalls (#865): Glieder mit Getter oder Funktionsaufruf auswerten;
    /// aus bleiben sie „nicht ausgewertet“.</summary>
    DebugExplainAccessViolationAllowCalls: Boolean;
    /// <summary>debug.moduleOfAddress (#1820): Modul der Fehleradresse (Programm, RTL/VCL, Windows, Fremdmodul) in
    /// der Erklärung einer Zugriffsverletzung nennen, bei Fremdmodulen mit der letzten eigenen Stelle.</summary>
    DebugModuleOfAddress: Boolean;
    /// <summary>debug.deadlocks (#587): Befehl „Was wartet worauf?“: Wartepunkte aller Threads eines
    /// angehaltenen Programms und bekannte Muster von Verklemmungen im Ergebnisfenster.</summary>
    DebugDeadlocks: Boolean;
    /// <summary>debug.leakReport (#1875): Leckbericht am Ende einer Debug-Sitzung einsammeln (Meldungsfenster von
    /// ReportMemoryLeaksOnShutdown, FastMM-Logdatei) und im Fenster „Atlas-Lecks“ zeigen.</summary>
    DebugLeakReport: Boolean;
    /// <summary>debug.leakReport.compare (#1875): mit dem letzten Lauf je Projekt und Konfiguration vergleichen.
    /// </summary>
    DebugLeakReportCompare: Boolean;
    /// <summary>debug.leakReport.window (#1875): Fenster „Atlas-Lecks“ bei Lecks öffnen.</summary>
    DebugLeakReportWindow: Boolean;
    /// <summary>debug.parallelStacks (#837): Fenster „Parallele Aufrufstapel“: die Stapel aller Threads beim Halt als
    /// Baum, gemeinsame Rahmen einmal mit der Zahl der Threads, wartende hervorgehoben.</summary>
    DebugParallelStacks: Boolean;
    /// <summary>debug.threadsInSource (#852): beim Halt im Rand jeder Zeile, an der andere Threads stehen, ein
    /// Zeichen mit Anzahl; Threads markieren.</summary>
    DebugThreadsInSource: Boolean;
    /// <summary>debug.threadFreeze (#852, experimentell): Threads einfrieren und auftauen
    /// (SuspendThread/ResumeThread).</summary>
    DebugThreadFreeze: Boolean;
    /// <summary>debug.asyncOrigin (#859, experimentell): Herkunft von TThread.Queue, Synchronize und TTask merken und
    /// beim Halt in der eingereihten Methode zeigen.</summary>
    DebugAsyncOrigin: Boolean;
    /// <summary>debug.asyncOrigin.maxPerSite (#859): gemerkte Einreihungen je Aufrufstelle.</summary>
    DebugAsyncOriginMaxPerSite: Integer;
    /// <summary>debug.parallelStacks.waitRoutines (#837): Warte-Routinen, durch ; getrennt; '' = Vorgabe.</summary>
    DebugParallelStacksWaitRoutines: string;
    /// <summary>debug.parallelStacks.maxThreads (#837): ab so vielen Threads abschnittsweise lesen.</summary>
    DebugParallelStacksMaxThreads: Integer;
    /// <summary>Exception-Verlauf beim Debuggen (#517, debug.exceptionHistory): Jeder Halt wegen einer Exception
    /// landet mit Klasse, Meldung, Ort, Thread und Anzahl im Fenster „Atlas: Exceptions“ (Befehl
    /// Atlas.DebugExceptions); Klassen lassen sich dort ignorieren, Atlas setzt dann still fort. Aus = kein Verlauf,
    /// kein Beobachter.</summary>
    DebugExceptionHistory: Boolean;
    /// <summary>Nur eigener Code beim Debuggen (#578, debug.justMyCode): Nach einer Exception in Bibliothekscode
    /// springt Atlas zur ersten eigenen Zeile des Aufrufstapels und markiert sie; landet F7 in Code ohne Quelltext,
    /// setzt Atlas „Bis zur Rückkehr“ fort; der Exception-Verlauf nennt den ersten eigenen Rahmen als Ort und fasst
    /// Bibliotheksrahmen zusammen. Eigener Code: Projektordner der Gruppe und debug.ownCodeFolders. Aus = IDE wie
    /// bisher.</summary>
    DebugJustMyCode: Boolean;
    /// <summary>Exception-Leiste beim Debuggen (#783, debug.exceptionBanner): Hält der Debugger wegen einer
    /// Exception, zeigt Atlas oben im Editor eine Leiste mit Klasse, Meldung, Thread, Anzahl an dieser Stelle und
    /// der ersten eigenen Zeile; in Delphi 12 und 13 schließt Atlas den Dialog der IDE dafür über „Anhalten“, sonst
    /// bleibt er und die Leiste kommt danach. Baut auf debug.exceptionHistory auf. Vorgabe aus bis zur
    /// Studie.</summary>
    DebugExceptionBanner: Boolean;
    /// <summary>Knopf „Nur an dieser Stelle ignorieren“ der Exception-Leiste (#783,
    /// debug.exceptionBanner.ignoreAtLocation): merkt Klasse, Datei und Zeile je Projekt; trifft dieselbe
    /// Kombination erneut ein, setzt Atlas still fort und zählt nur im Verlauf. Aus = kein Knopf, gemerkte Orte
    /// wirken nicht.</summary>
    DebugExceptionBannerIgnoreAtLocation: Boolean;
    /// <summary>Werte im Editor beim Debuggen (#508, debug.inlineValues): Steht der Prozess, zeigt Atlas am Ende der
    /// Zeilen der Routine mit dem Ausführungspunkt gedimmt die Werte der lokalen Variablen, Parameter und Felder von
    /// Self (Count = 3, Name = 'Meier'); seit dem letzten Halt geänderte Werte hervorgehoben. Aus = keine Anfrage,
    /// keine Auswertung, nichts gezeichnet.</summary>
    DebugInlineValues: Boolean;
    /// <summary>Höchstens so viele Werte je Zeile (#508, debug.inlineValuesPerLine, 1 bis 20).</summary>
    DebugInlineValuesPerLine: Integer;
    /// <summary>„Warum bin ich hier?“ (#1878, debug.whyHere): Beim Halt zeigt Atlas am Ende der Kopfzeilen der
    /// umgebenden if, while, repeat, for und case die Werte ihrer Bedingungen („True and (1200 > 1000) → True“,
    /// „I = 3 von 7“); Aufrufe nur auf Klick. Aus = keine Anfrage, keine Werte.</summary>
    DebugWhyHere: Boolean;
    /// <summary>So viele umgebende Blöcke (#1878, debug.whyHere.depth, 1 bis 10).</summary>
    DebugWhyHereDepth: Integer;
    /// <summary>Weitere Ordner mit eigenem Code (#578, debug.ownCodeFolders), durch „;“ getrennt; die Projektordner
    /// der Gruppe gelten immer.</summary>
    DebugOwnCodeFolders: string;
    /// <summary>Ereignisprotokoll beim Debuggen (#580, debug.eventLog): Fenster „Atlas: Ereignisprotokoll“ (Befehl
    /// Atlas.DebugEventLog) mit Ausgaben, Modulen, Threads und Logpunkten der Sitzung, Filter nach Text, Ausdruck und
    /// Art, Farben und Sprung zum Quelltext. Aus = kein Fenster, kein Mitlesen.</summary>
    DebugEventLog: Boolean;
    /// <summary>Farben im Ereignisprotokoll (#580, debug.eventLogColors): „Muster=Farbe“, durch „;“ getrennt; Farbe
    /// als #RRGGBB oder Name (rot, gelb, grün, blau, orange, grau). Erstes passendes Muster gewinnt.</summary>
    DebugEventLogColors: string;
    /// <summary>Logpunkte (#583, debug.logpoints): Befehl „Logpunkt setzen“ (Umschalt+F5, Kontextmenü am Rand) legt
    /// einen Haltepunkt ohne Anhalten an, der einen Text mit Werten ins Ereignisprotokoll schreibt; Raute in der
    /// Rinne; Befehle für alle Logpunkte. Aus = keine Befehle, keine Raute.</summary>
    DebugLogpoints: Boolean;
    /// <summary>Präfix vor jeder Logpunkt-Ausgabe (#583, debug.logpointPrefix).</summary>
    DebugLogpointPrefix: string;
    /// <summary>Fenster „Kein Quelltext“ (#869, debug.noSourcePage): Hält der Debugger in Code ohne Quelltext, nennt
    /// ein kleines Fenster Routine, Modul, Adresse, Grund und Auswege. Aus = nur das CPU-Fenster der IDE.</summary>
    DebugNoSourcePage: Boolean;
    /// <summary>Units ohne Fenster „Kein Quelltext“ (#869, debug.noSourcePage.ignoredUnits), durch „;“ getrennt.
    /// </summary>
    DebugNoSourceIgnoredUnits: string;
    /// <summary>Neu starten (#872, debug.restart): Befehl „Neu starten“ (Strg+Umschalt+F2) beendet das Programm, baut
    /// nur nach Änderungen, startet und kehrt an die Stelle im Editor zurück. Aus = kein Befehl, keine Taste.</summary>
    DebugRestart: Boolean;
    /// <summary>Beim Neustart Haltepunkte wieder einschalten, die in der Sitzung abgeschaltet wurden (#872,
    /// debug.restart.reenableBreakpoints).</summary>
    DebugRestartReenableBreakpoints: Boolean;
    /// <summary>Erneut anhängen (#2171, debug.reattach): Atlas merkt den Pfad angehängter Prozesse je
    /// Projektgruppe; Befehle „Erneut an … anhängen“ und „Anhängen, sobald gestartet …“ im Menü Start. Aus = keine
    /// Einträge, kein Merken, kein Warten.</summary>
    DebugReattach: Boolean;
    /// <summary>Tastenkürzel „Erneut anhängen“ (#2171, debug.reattach.key; 0 = keins).</summary>
    DebugReattachKey: Integer;
    /// <summary>Abstand der Abfragen der Prozessliste beim Warten in ms (#2171, debug.reattach.waitIntervalMs).
    /// </summary>
    DebugReattachWaitIntervalMs: Integer;
    /// <summary>Startverbünde (#867, debug.launchGroups): Verbünde aus der Projektdatei .atlas ("launchGroups"),
    /// Fenster „Startverbünde“; F9 startet den aktiven Verbund, Strg+F2 beendet alle seine Programme. Aus = F9
    /// startet nur das aktive Projekt.</summary>
    DebugLaunchGroups: Boolean;
    /// <summary>Startprofile (#575, startProfiles.enabled): Befehl „Startprofil: …“ (Atlas.StartProfile) mit Tipp,
    /// Feld in der Statusleiste und Setzen der Startoptionen des Projekts; aus = Befehl, Tipp und Feld
    /// verschwinden, die Startoptionen der IDE bleiben, wie sie sind.</summary>
    StartProfiles: Boolean;
    /// <summary>Aktives Startprofil als Feld in der Statusleiste des Editors (#575, startProfiles.statusField);
    /// Klick öffnet die Auswahl.</summary>
    StartProfilesStatusField: Boolean;
    /// <summary>Modul-Schalter debug.enabled (#1454): Debugger; aus = die wirksamen Werte aller Einstellungen des
    /// Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    DebugEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginDebugSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
    /// <summary>Vorgaben ab debug.whyHere (Halt, Protokoll, Neustart, Anhängen, Start); Teil von Defaults.</summary>
    procedure SetStopAndLaunchDefaults;
    /// <summary>Werte ab debug.whyHere über AIo lesen bzw. schreiben; Teil von Exchange.</summary>
    procedure ExchangeStopAndLaunch(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Atlas.Core.Settings.EventBreakNames,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Text.StepFilter;

{ TAtlasPluginDebugSettings }

class function TAtlasPluginDebugSettings.Defaults: TAtlasPluginDebugSettings;
begin
  Result.TestDebug := True;
  Result.TestBreakAtStart := True;
  Result.DebugHoverValues := True;
  Result.DebugVisualizers := True;
  Result.DebugVisualizerTypes := TAtlasVisualizerSettings.KindsText(TAtlasVisualizerSettings.cAllKinds);
  Result.DebugVisualizerNameFields := TAtlasVisualizerSettings.cDefaultNameFields;
  Result.DebugVisualizerMaxLength := TAtlasVisualizerSettings.cDefaultMaxLength;
  Result.DebugVisualizerTimeoutMs := TAtlasVisualizerSettings.cDefaultTimeoutMs;
  Result.DebugVisualizerMaxImagePixels := TAtlasVisualizerSettings.cDefaultMaxImagePixels;
  Result.DebugVisualizerEvaluation := TAtlasVisualizerSettings.cEvaluationNames[TAtlasVisualizerEvaluation.Properties];
  Result.DebugDisplayRules := True;
  Result.DebugDisplayRulesAllowCalls := False;
  Result.DebugStepIntoTarget := True;
  Result.DebugStepFilters := True;
  Result.DebugStepFilterKinds := TStepFilterNames.KindsText(TStepFilterNames.cDefaultKinds);
  Result.DebugStepFilterPatterns := '';
  Result.DebugStepIntoTargetKey := $C076; // Strg+Alt+F7
  Result.DebugBreakOnNextEvent := True;
  Result.DebugBreakOnNextEventExcluded := TAtlasEventBreakSettings.cDefaultExcluded;
  Result.DebugCheckBreakpoints := True;
  Result.DebugInstanceBreakpoints := True;
  Result.DebugBreakpointSetPerBranch := True;
  Result.DebugExplainUnavailable := True;
  Result.DebugCompletionInDialogs := True;
  Result.DebugEvaluateWindow := True;
  Result.DebugEvaluateReplaceCtrlF7 := True;
  Result.DebugExplainAccessViolation := True;
  Result.DebugExplainAccessViolationAllowCalls := False;
  Result.DebugAsyncOrigin := False;
  Result.DebugAsyncOriginMaxPerSite := cDefaultAsyncOriginPerSite;
  Result.DebugThreadFreeze := False;
  Result.DebugThreadsInSource := True;
  Result.DebugParallelStacks := True;
  Result.DebugParallelStacksWaitRoutines := '';
  Result.DebugParallelStacksMaxThreads := cDefaultParallelStacksThreads;
  Result.DebugDeadlocks := True;
  Result.DebugLeakReport := True;
  Result.DebugLeakReportCompare := True;
  Result.DebugLeakReportWindow := True;
  Result.DebugModuleOfAddress := True;
  Result.DebugExceptionHistory := True;
  Result.DebugJustMyCode := True;
  Result.DebugExceptionBanner := False;
  Result.DebugExceptionBannerIgnoreAtLocation := True;
  Result.DebugInlineValues := True;
  Result.DebugInlineValuesPerLine := 5;
  Result.SetStopAndLaunchDefaults;
end;

procedure TAtlasPluginDebugSettings.Normalize;
begin
  // Bereinigt (Trenner, doppelte) wird beim Speichern der Seite und beim Lesen in TAtlasFolderList.Parse (#1455).
  DebugOwnCodeFolders := Trim(DebugOwnCodeFolders);
  DebugEventLogColors := Trim(DebugEventLogColors);
  DebugParallelStacksWaitRoutines := Trim(DebugParallelStacksWaitRoutines);
  DebugParallelStacksMaxThreads := EnsureRange(DebugParallelStacksMaxThreads, cMinParallelStacksThreads,
    cMaxParallelStacksThreads);
  DebugLogpointPrefix := Trim(DebugLogpointPrefix);
  DebugAsyncOriginMaxPerSite := EnsureRange(DebugAsyncOriginMaxPerSite, cMinAsyncOriginPerSite,
    cMaxAsyncOriginPerSite);
  DebugNoSourceIgnoredUnits := Trim(DebugNoSourceIgnoredUnits);
  DebugInlineValuesPerLine := EnsureRange(DebugInlineValuesPerLine, cMinInlineValuesPerLine, cMaxInlineValuesPerLine);
  DebugWhyHereDepth := EnsureRange(DebugWhyHereDepth, cMinWhyHereDepth, cMaxWhyHereDepth);
  DebugStepIntoTargetKey := EnsureRange(DebugStepIntoTargetKey, 0, $FFFF);
  DebugReattachKey := EnsureRange(DebugReattachKey, 0, $FFFF);
  DebugReattachWaitIntervalMs := EnsureRange(DebugReattachWaitIntervalMs, cMinReattachWaitMs, cMaxReattachWaitMs);
  DebugVisualizerTypes := TAtlasVisualizerSettings.NormalizeKinds(DebugVisualizerTypes);
  DebugStepFilterKinds := TStepFilterNames.NormalizeKinds(DebugStepFilterKinds);
  DebugStepFilterPatterns := TStepFilterNames.NormalizePatterns(DebugStepFilterPatterns);
  DebugBreakOnNextEventExcluded := TAtlasEventBreakSettings.NormalizeExcluded(DebugBreakOnNextEventExcluded);
  DebugVisualizerNameFields := TAtlasVisualizerSettings.NormalizeNameFields(DebugVisualizerNameFields);
  DebugVisualizerMaxLength := EnsureRange(DebugVisualizerMaxLength, TAtlasVisualizerSettings.cMinMaxLength,
    TAtlasVisualizerSettings.cMaxMaxLength);
  DebugVisualizerTimeoutMs := EnsureRange(DebugVisualizerTimeoutMs, TAtlasVisualizerSettings.cMinTimeoutMs,
    TAtlasVisualizerSettings.cMaxTimeoutMs);
  DebugVisualizerMaxImagePixels := EnsureRange(DebugVisualizerMaxImagePixels,
    TAtlasVisualizerSettings.cMinMaxImagePixels, TAtlasVisualizerSettings.cMaxMaxImagePixels);
  DebugVisualizerEvaluation := Choice(DebugVisualizerEvaluation, TAtlasVisualizerSettings.cEvaluationNames);
end;

procedure TAtlasPluginDebugSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('TestDebug', TestDebug);
  AIo.Flag('TestBreakAtStart', TestBreakAtStart);
  AIo.Flag('DebugHoverValues', DebugHoverValues);
  AIo.Flag('DebugVisualizers', DebugVisualizers);
  AIo.Text('DebugVisualizerTypes', DebugVisualizerTypes);
  AIo.Text('DebugVisualizerNameFields', DebugVisualizerNameFields);
  AIo.Number('DebugVisualizerMaxLength', DebugVisualizerMaxLength);
  AIo.Number('DebugVisualizerTimeoutMs', DebugVisualizerTimeoutMs);
  AIo.Number('DebugVisualizerMaxImagePixels', DebugVisualizerMaxImagePixels);
  AIo.Text('DebugVisualizerEvaluation', DebugVisualizerEvaluation);
  AIo.Flag('DebugDisplayRules', DebugDisplayRules);
  AIo.Flag('DebugDisplayRulesAllowCalls', DebugDisplayRulesAllowCalls);
  AIo.Flag('DebugStepIntoTarget', DebugStepIntoTarget);
  AIo.Flag('DebugStepFilters', DebugStepFilters);
  AIo.Text('DebugStepFilterKinds', DebugStepFilterKinds);
  AIo.Text('DebugStepFilterPatterns', DebugStepFilterPatterns);
  AIo.Number('DebugStepIntoTargetKey', DebugStepIntoTargetKey);
  AIo.Flag('DebugBreakOnNextEvent', DebugBreakOnNextEvent);
  AIo.Text('DebugBreakOnNextEventExcluded', DebugBreakOnNextEventExcluded);
  AIo.Flag('DebugCheckBreakpoints', DebugCheckBreakpoints);
  AIo.Flag('DebugInstanceBreakpoints', DebugInstanceBreakpoints);
  AIo.Flag('DebugBreakpointSetPerBranch', DebugBreakpointSetPerBranch);
  AIo.Flag('DebugExplainUnavailable', DebugExplainUnavailable);
  AIo.Flag('DebugCompletionInDialogs', DebugCompletionInDialogs);
  AIo.Flag('DebugEvaluateWindow', DebugEvaluateWindow);
  AIo.Flag('DebugEvaluateReplaceCtrlF7', DebugEvaluateReplaceCtrlF7);
  AIo.Flag('DebugExplainAccessViolation', DebugExplainAccessViolation);
  AIo.Flag('DebugExplainAccessViolationAllowCalls', DebugExplainAccessViolationAllowCalls);
  AIo.Flag('DebugModuleOfAddress', DebugModuleOfAddress);
  AIo.Flag('DebugDeadlocks', DebugDeadlocks);
  AIo.Flag('DebugLeakReport', DebugLeakReport);
  AIo.Flag('DebugLeakReportCompare', DebugLeakReportCompare);
  AIo.Flag('DebugLeakReportWindow', DebugLeakReportWindow);
  AIo.Flag('DebugParallelStacks', DebugParallelStacks);
  AIo.Flag('DebugThreadsInSource', DebugThreadsInSource);
  AIo.Flag('DebugThreadFreeze', DebugThreadFreeze);
  AIo.Flag('DebugAsyncOrigin', DebugAsyncOrigin);
  AIo.Text('DebugParallelStacksWaitRoutines', DebugParallelStacksWaitRoutines);
  AIo.Number('DebugParallelStacksMaxThreads', DebugParallelStacksMaxThreads);
  AIo.Number('DebugAsyncOriginMaxPerSite', DebugAsyncOriginMaxPerSite);
  AIo.Flag('DebugExceptionHistory', DebugExceptionHistory);
  AIo.Flag('DebugJustMyCode', DebugJustMyCode);
  AIo.Flag('DebugExceptionBanner', DebugExceptionBanner);
  AIo.Flag('DebugExceptionBannerIgnoreAtLocation', DebugExceptionBannerIgnoreAtLocation);
  AIo.Flag('DebugInlineValues', DebugInlineValues);
  AIo.Number('DebugInlineValuesPerLine', DebugInlineValuesPerLine);
  ExchangeStopAndLaunch(AIo);
end;

procedure TAtlasPluginDebugSettings.SetStopAndLaunchDefaults;
begin
  DebugWhyHere := True;
  DebugWhyHereDepth := cDefaultWhyHereDepth;
  DebugOwnCodeFolders := '';
  DebugEventLog := True;
  DebugEventLogColors := cDefaultEventLogColors;
  DebugLogpoints := True;
  DebugLogpointPrefix := cDefaultLogpointPrefix;
  DebugNoSourcePage := True;
  DebugNoSourceIgnoredUnits := '';
  DebugRestart := True;
  DebugRestartReenableBreakpoints := False;
  DebugReattach := True;
  DebugReattachKey := cDefaultReattachKey;
  DebugReattachWaitIntervalMs := cDefaultReattachWaitMs;
  DebugLaunchGroups := True;
  StartProfiles := True;
  StartProfilesStatusField := True;
  DebugEnabled := True;
end;

procedure TAtlasPluginDebugSettings.ExchangeStopAndLaunch(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('DebugWhyHere', DebugWhyHere);
  AIo.Number('DebugWhyHereDepth', DebugWhyHereDepth);
  AIo.Text('DebugOwnCodeFolders', DebugOwnCodeFolders);
  AIo.Flag('DebugEventLog', DebugEventLog);
  AIo.Text('DebugEventLogColors', DebugEventLogColors);
  AIo.Flag('DebugLogpoints', DebugLogpoints);
  AIo.Text('DebugLogpointPrefix', DebugLogpointPrefix);
  AIo.Flag('DebugNoSourcePage', DebugNoSourcePage);
  AIo.Text('DebugNoSourceIgnoredUnits', DebugNoSourceIgnoredUnits);
  AIo.Flag('DebugRestart', DebugRestart);
  AIo.Flag('DebugRestartReenableBreakpoints', DebugRestartReenableBreakpoints);
  AIo.Flag('DebugReattach', DebugReattach);
  AIo.Number('DebugReattachKey', DebugReattachKey);
  AIo.Number('DebugReattachWaitIntervalMs', DebugReattachWaitIntervalMs);
  AIo.Flag('DebugLaunchGroups', DebugLaunchGroups);
  AIo.Flag('StartProfiles', StartProfiles);
  AIo.Flag('StartProfilesStatusField', StartProfilesStatusField);
  AIo.Flag('DebugEnabled', DebugEnabled);
end;

end.
