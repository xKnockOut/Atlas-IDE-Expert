unit Atlas.Core.Problems.Contract.Sync;

// Verträge des Abgleichs der Probleme mit dem Server (#398): Was der Ablauf
// TAtlasProblemsFlow (Atlas.Core.Problems.Flow) vom Server und von der IDE
// braucht. In der IDE erfüllen sie Atlas.IDE.Problems.Adapters.Server
// (Sitzung, Holthreads) und Atlas.IDE.Problems.Adapters.Editors (Editor,
// Module, Debugger, Fehler der IDE), in den Tests eine Fälschung.

interface

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Contract;

type
  /// <summary>Ein Auftrag an textDocument/diagnostic: Datei, abgeglichener Text, vorige Ergebnis-Id ('' = alles
  /// neu) und ob die Compilermeldungen der Datei mit ersetzt werden.</summary>
  TAtlasProblemsPull = record
    FileName: string;
    Text: string;
    PreviousId: string;
    ReplaceCompiler: Boolean;
    /// <summary>Dauer der Anfrage; setzt, wer sie stellt.</summary>
    DurationMs: Cardinal;
  end;

  TAtlasProblemsPulls = TArray<TAtlasProblemsPull>;

  /// <summary>Oberer Editor mit Fokus: Datei, Text und Stand des Puffers (wechselt mit jeder Änderung), ungespeichert,
  /// Code vorn (nicht Designer oder Willkommensseite).</summary>
  TAtlasProblemsEditor = record
    FileName: string;
    Text: string;
    Version: Cardinal;
    Modified: Boolean;
    CodeInFront: Boolean;
  end;

  TAtlasProblemsLogProc = reference to procedure(const AMessage: string);
  /// <summary>Antwort auf einen Auftrag; im Hauptthread.</summary>
  TAtlasProblemsDocumentProc = reference to procedure(const APull: TAtlasProblemsPull;
    const AReport: TLspDiagnosticReport);
  /// <summary>Geänderte Berichte der übrigen Projektdateien und Stand der Projektprüfung; im Hauptthread.</summary>
  TAtlasProblemsWorkspaceProc = reference to procedure(const AReports: TArray<TLspDiagnosticReport>;
    const ARun: TLspWorkspaceRun);

  /// <summary>Der Server, wie ihn der Ablauf sieht. Connect wählt die Sitzung, die übrigen Aufrufe gelten ihr.
  /// Antworten auf Pull und die der Projektdateien kommen über die Rückrufe, die der Erzeuger mitgibt. Nur im
  /// Hauptthread.</summary>
  IAtlasProblemsServer = interface
    ['{DA3F5D7A-0BEA-469D-979F-DAFC65AA476F}']
    /// <summary>Laufende Sitzung, auf Wunsch gestartet; Kennung der Sitzung (wechselt nach einem Neustart) oder 0
    /// ohne.</summary>
    function Connect(AStart: Boolean): Integer;
    /// <summary>Text von AFileName an den Server geben (didOpen bzw. didChange).</summary>
    procedure Sync(const AFileName, AText: string);
    /// <summary>AFileName schließen (didClose).</summary>
    procedure Close(const AFileName: string);
    /// <summary>Abgeglichene Dateien der Sitzung.</summary>
    function SyncedFiles: TArray<string>;
    /// <summary>Abgeglichener Text von AFileName; False, wenn die Sitzung die Datei nicht kennt.</summary>
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Wie oft der Server um neues Holen gebeten hat (workspace/diagnostic/refresh).</summary>
    function RefreshCount: Integer;
    /// <summary>Wie oft Projekte weggefallen sind (Projektgruppe geschlossen oder gewechselt).</summary>
    function ProjectsRemoved: Integer;
    /// <summary>Projektprüfung des Servers ruhen lassen bzw. fortsetzen (Debuggen, #1247).</summary>
    procedure PauseProjectCheck(APaused: Boolean);
    /// <summary>Konfiguration, Plattform und Defines der IDE melden, wenn sie sich geändert haben (#615).</summary>
    procedure UpdateTarget;
    /// <summary>Holen für die Sitzung von Connect bereitstellen; AWorkspace: auch die übrigen Projektdateien
    /// (Long-Polling), sonst diese Abfrage beenden.</summary>
    procedure StartPulls(AWorkspace: Boolean);
    /// <summary>Holen beenden, ohne zu warten; laufende Anfragen enden mit dem Schließen der Verbindung.</summary>
    procedure StopPulls;
    /// <summary>Ist das Holen bereitgestellt?</summary>
    function Pulling: Boolean;
    /// <summary>Aufträge anhängen; nur nach StartPulls.</summary>
    procedure Pull(const APulls: TAtlasProblemsPulls);
    /// <summary>Kein Auftrag offen oder in Arbeit.</summary>
    function Idle: Boolean;
    /// <summary>Beendetes Holen aufräumen; im Takt.</summary>
    procedure Collect;
    /// <summary>Auf beendetes Holen warten (Ende der Sitzung).</summary>
    procedure WaitStopped;
  end;

  /// <summary>Was der Ablauf von der IDE liest. Nur im Hauptthread.</summary>
  IAtlasProblemsEditors = interface
    ['{263522D1-36F9-4752-89EE-87D0EEA17FB5}']
    /// <summary>Oberer Editor, wenn die IDE den Fokus hat; False ohne.</summary>
    function ActiveEditor(out AEditor: TAtlasProblemsEditor): Boolean;
    /// <summary>Ist AFileName in der IDE geöffnet?</summary>
    function IsOpen(const AFileName: string): Boolean;
    /// <summary>Text von AFileName aus dem Puffer, sonst von der Platte; False, wenn er sich nicht lesen lässt.
    /// </summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Läuft ein Programm im Debugger? Dann ruht die Prüfung (#1241).</summary>
    function Debugging: Boolean;
    /// <summary>Fehler der IDE abfragen (#1819, problems.ideErrors)?</summary>
    function IdeErrorsEnabled: Boolean;
    /// <summary>Fehler der IDE zu AFileName als Probleme; False ohne Modul oder wenn die IDE die Datei nicht kennt.
    /// </summary>
    function IdeErrors(const AFileName: string; out AErrors: TArray<TAtlasProblem>): Boolean;
  end;

implementation

end.
