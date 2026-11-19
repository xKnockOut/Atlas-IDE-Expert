unit Atlas.Core.Tasks.Contract;

// Verträge der Projektaufgaben (#900), die andere Teile erfüllen: die
// Aufgabe selbst (TAtlasTaskDefinition, gelesen von TAtlasTasks in
// Atlas.Core.Tasks.Definitions), der Prozess einer Aufgabe (IAtlasTaskProcess,
// Atlas.Core.Tasks.Providers.Process) und der Starter der Läufe für den Ablauf
// (IAtlasTaskLauncher, in der IDE Atlas.IDE.BuildTools.Adapters.TaskLauncher, in den
// Tests eine Fälschung).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasTaskGroup = (Check, Build, Test, Other);
  /// <summary>tasks.beforeBuild bzw. beforeBuild einer Aufgabe.</summary>
  TAtlasTaskBeforeBuild = (Off, Warn, Block);
  /// <summary>Eingebaute Muster für Fundstellen; None = keine Auswertung, Custom = eigener regulärer Ausdruck.
  /// </summary>
  TAtlasTaskMatcherKind = (None, Dcc, Pwsh, MsBuild, Generic, Custom);
  TAtlasTaskSeverity = (Error, Warning, Info);
  TAtlasTaskOutcome = (Finished, ProgramMissing, StartFailed, TimedOut, Cancelled);
{$SCOPEDENUMS OFF}

  /// <summary>Muster einer Aufgabe; bei Custom mit regulärem Ausdruck und Zuordnung eigener Wörter.</summary>
  TAtlasTaskMatcher = record
    Kind: TAtlasTaskMatcherKind;
    /// <summary>Custom: Ausdruck mit den benannten Gruppen file, line, column, severity, code, message.</summary>
    Regex: string;
    /// <summary>Custom: Wörter aus severityMap (klein) und ihre Schwere, gleich lang.</summary>
    SeverityWords: TArray<string>;
    SeverityValues: TArray<TAtlasTaskSeverity>;
    /// <summary>Schwere ohne erkennbares Wort (severity, Vorgabe error).</summary>
    DefaultSeverity: TAtlasTaskSeverity;
    class function Create(AKind: TAtlasTaskMatcherKind): TAtlasTaskMatcher; static;
  end;

  TAtlasTaskDefinition = record
    Name: string;
    Command: string;
    Args: TArray<string>;
    /// <summary>Arbeitsordner; '' = Projektordner.</summary>
    Cwd: string;
    EnvNames: TArray<string>;
    EnvValues: TArray<string>;
    Group: TAtlasTaskGroup;
    Matcher: TAtlasTaskMatcher;
    /// <summary>Taste wie geschrieben und als TShortCut (0 = keine oder unlesbar).</summary>
    KeyText: string;
    Key: Word;
    /// <summary>Sekunden bis zum Abbruch; 0 = ohne Zeitlimit.</summary>
    TimeoutSec: Integer;
    /// <summary>beforeBuild der Aufgabe; nur mit HasBeforeBuild.</summary>
    HasBeforeBuild: Boolean;
    BeforeBuild: TAtlasTaskBeforeBuild;
    /// <summary>Aus der globalen Datei (%APPDATA%\Atlas\settings.json).</summary>
    Global: Boolean;
    /// <summary>Verhalten vor dem Build: eigenes beforeBuild, sonst AGlobal für Gruppe check, sonst Off.</summary>
    function BeforeBuildFor(AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskBeforeBuild;
    /// <summary>Befehlszeile zum Anzeigen: Programm und Argumente mit Leerzeichen.</summary>
    function CommandLine: string;
  end;

  TAtlasTaskDefinitions = TArray<TAtlasTaskDefinition>;

  TAtlasTaskLineProc = reference to procedure(const ALine: string);

  /// <summary>Ergebnis des Prozesses einer Aufgabe (IAtlasTaskProcess).</summary>
  TAtlasTaskProcessResult = record
    Outcome: TAtlasTaskOutcome;
    ExitCode: Integer;
    /// <summary>StartFailed: Grund oder fehlender Arbeitsordner; ProgramMissing: der Befehl.</summary>
    Error: string;
  end;

  /// <summary>Prozess einer Aufgabe.</summary>
  IAtlasTaskProcess = interface
    ['{8951B667-C12B-4F1E-B939-AD3C86D5FD52}']
    /// <summary>Führt die (mit Variablen eingesetzte) Aufgabe aus, nicht im Hauptthread. ACancelled wird im Takt
    /// gefragt; ACodePage für Ausgaben, die kein UTF-8 sind (0 = OEM-Codepage); jede Zeile geht an AOnLine.
    /// </summary>
    function Run(const ATask: TAtlasTaskDefinition; ACodePage: Integer; const ACancelled: TFunc<Boolean>;
      const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult;
  end;

  /// <summary>Startet und beendet die Prozesse der Läufe.</summary>
  IAtlasTaskLauncher = interface
    ['{86D5C598-12BC-476D-AA52-9D4C01ED9763}']
    /// <summary>Kann ATask hier gar nicht laufen? AReason nennt den Grund.</summary>
    function Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
    /// <summary>ATask für AProject als Lauf AId starten; AShow: Ausgabe zeigen. Das Ende kommt später über
    /// TAtlasTaskFlow.Finished, auch wenn der Prozess nicht startet.</summary>
    procedure Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition; AShow: Boolean);
    /// <summary>Lauf AId abbrechen; sein Ende kommt wie sonst.</summary>
    procedure Cancel(AId: Integer);
    /// <summary>Lauf AId ist fertig gemeldet: aufräumen.</summary>
    procedure Release(AId: Integer);
  end;

implementation

{ TAtlasTaskMatcher }

class function TAtlasTaskMatcher.Create(AKind: TAtlasTaskMatcherKind): TAtlasTaskMatcher;
begin
  Result := Default(TAtlasTaskMatcher);
  Result.Kind := AKind;
  Result.DefaultSeverity := TAtlasTaskSeverity.Error;
end;

{ TAtlasTaskDefinition }

function TAtlasTaskDefinition.BeforeBuildFor(AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskBeforeBuild;
begin
  if HasBeforeBuild then
  begin
    Result := BeforeBuild;
  end
  else if Group = TAtlasTaskGroup.Check then
  begin
    Result := AGlobal;
  end
  else
  begin
    Result := TAtlasTaskBeforeBuild.Off;
  end;
end;

function TAtlasTaskDefinition.CommandLine: string;
var
  mArg: string;
begin
  Result := Command;
  for mArg in Args do
  begin
    if Pos(' ', mArg) > 0 then
    begin
      Result := Result + ' "' + mArg + '"';
    end
    else
    begin
      Result := Result + ' ' + mArg;
    end;
  end;
end;

end.
