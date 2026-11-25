unit Atlas.IDE.Problems.Controller;

// Probleme im Editor (#398, Rest von #528/#548): Takt und Anzeige der
// Diagnosen des Servers. Was wann geholt und wie eingeordnet wird, entscheidet
// TAtlasProblemsFlow (Atlas.Core.Problems.Flow, ohne IDE testbar); hier
// laufen der Takt, die Zeichner und die Meldungsliste.
//   - Ein Timer (250 ms, kürzer bei kürzerer Verzögerung problems.liveDelayMs)
//     treibt den Ablauf; danach werden Wellenlinien, Meldungsliste (Gruppe
//     „Atlas-Probleme“, erst 800 ms nach der letzten Änderung) und Zähler
//     aktualisiert.
//   - Server und IDE erreicht der Ablauf über IAtlasProblemsServer und
//     IAtlasProblemsEditors (Atlas.Core.Problems.Contract.Sync). Die Adapter
//     (Atlas.IDE.Problems.Adapters.Server und .Editors) setzt die
//     Kompositionswurzel über ServerFactory und EditorsFactory ein.
// Zähler für die Statusleiste (#509): nach jeder Änderung des Speichers gehen
// Fehler, Warnungen und Hinweise wie in der Liste „Atlas-Probleme“ (ohne
// Compilermeldungen) an OnCounts; mit problems.statusCounter aus einmal
// AShow = False.
// Die letzte Prüfung einer Datei (Datei, Dauer, Zeitpunkt) steht in LastCheck
// für die Statuszeile des Fensters „Atlas-Prüfung“; Checking meldet eine
// laufende Anfrage für die Atlas-Statusleiste (#1155), ProjectRun den Stand der
// Projektprüfung des Servers (#1247).
// Antworten kommen im Hauptthread; der Speicher wird nur dort benutzt.
// BeginShutdown hält das Holen an, bevor die Sitzung endet: Der Manager
// schließt dazwischen die Verbindung, damit laufende Anfragen sofort
// zurückkehren, und wartet dann mit WaitShutdown.

interface

uses
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Plugin.Problems.Contract,
  Atlas.Core.Problems.Contract.Sync,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Problems.Flow,
  Atlas.IDE.Problems.Painter,
  Atlas.IDE.Problems.MessageList,
  Atlas.Plugin.Diagnostics.Deadline;

type
  /// <summary>Sitzung, auf Wunsch gestartet; nil, wenn keine läuft bzw. der Start scheitert.</summary>
  TAtlasProblemsSessionFunc = reference to function(AStart: Boolean): TLspSession;
  /// <summary>Zähler für die Statusleiste (#509); AShow False = Feld entfernen.</summary>
  TAtlasProblemCountsProc = reference to procedure(AShow: Boolean; const ACounts: TAtlasProblemCounts);
  /// <summary>Liegt im Ablauf; Alias für bestehende Nutzer.</summary>
  TAtlasProblemsCheck = Atlas.Core.Problems.Flow.TAtlasProblemsCheck;
  /// <summary>Legt den Server-Adapter an: ASession liefert die Sitzung, Antworten gehen an ADocument und AWorkspace.
  /// </summary>
  TAtlasProblemsServerFactory = reference to function(const ASession: TAtlasProblemsSessionFunc;
    const ADocument: TAtlasProblemsDocumentProc; const AWorkspace: TAtlasProblemsWorkspaceProc;
    const ALog: TAtlasProblemsLogProc): IAtlasProblemsServer;
  TAtlasProblemsEditorsFactory = reference to function: IAtlasProblemsEditors;

  TAtlasProblemsController = class
  public const
    cTickMs = 250;
    /// <summary>Meldungsliste erst so lange nach der letzten Änderung des Speichers neu aufbauen.</summary>
    cListDelayMs = 800;
  private
    FLog: TAtlasProblemsLogProc;
    FServer: IAtlasProblemsServer;
    FFlow: TAtlasProblemsFlow;
    FPainter: TAtlasProblemsPainter;
    FList: TAtlasProblemsList;
    FTimer: TTimer;
    FPaintedVersion: Integer;
    FListedVersion: Integer;
    // Stand des Schalters ProblemsMessageList beim letzten Aufbau der Liste.
    FListShown: Boolean;
    FListDue: TAtlasDeadline;
    class var FOnCounts: TAtlasProblemCountsProc;
    class var FServerFactory: TAtlasProblemsServerFactory;
    class var FEditorsFactory: TAtlasProblemsEditorsFactory;
    procedure Tick(Sender: TObject);
    procedure Publish;
    procedure PublishCounts;
    procedure DeliverDocument(const APull: TAtlasProblemsPull; const AReport: TLspDiagnosticReport);
    procedure DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>; const ARun: TLspWorkspaceRun);
    class function GetLastCheck: TAtlasProblemsCheck; static;
  public
    constructor Create(const ASession: TAtlasProblemsSessionFunc; const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    /// <summary>Holen anhalten (Teil 1); danach die Verbindung schließen und WaitShutdown aufrufen.</summary>
    procedure BeginShutdown;
    /// <summary>Auf das Holen warten (Teil 2); danach darf die Sitzung enden.</summary>
    procedure WaitShutdown;
    /// <summary>Probleme an der Stelle (0-basiert) für den Hover-Tooltip; mit Abblenden auch der Hinweis
    /// „Inaktiv: Bedingung … nicht erfüllt“ eines inaktiven Zweigs (#615) und mit DimUnusedUses der Grund eines
    /// auffälligen uses-Eintrags (#621).</summary>
    function ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
    /// <summary>Text zum uses-Hinweis in der Sprache des Plugins („Aus Vcl.Grids wird nichts verwendet“).</summary>
    class function UsesHint(const AProblem: TAtlasProblem): string; static;
    /// <summary>Speicher des laufenden Controllers für andere Zeichner (inaktive Zweige, #615); nil ohne.</summary>
    class function Current: TAtlasProblemStore; static;
    /// <summary>Läuft gerade eine Prüfung (textDocument/diagnostic) des laufenden Controllers? (#1155)</summary>
    class function Checking: Boolean; static;
    /// <summary>Läuft ein Programm im Debugger? Dann ruht die Prüfung (#1241).</summary>
    class function Paused: Boolean; static;
    /// <summary>Stand der Projektprüfung des Servers (#1247); AFinishedAgoMs = Zeit seit dem Ende des letzten Laufs
    /// (High(UInt64) ohne). False ohne laufenden Controller oder solange der Server keinen Stand gemeldet hat. Im
    /// Hauptthread.</summary>
    class function ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean; static;
    /// <summary>Letzte Prüfung einer Datei (#909) des laufenden Controllers; im Hauptthread.</summary>
    class property LastCheck: TAtlasProblemsCheck read GetLastCheck;
    /// <summary>Empfänger der Zähler (#509); setzt die Composition, nil = keiner. Im Hauptthread.</summary>
    class property OnCounts: TAtlasProblemCountsProc read FOnCounts write FOnCounts;
    /// <summary>Legen die Adapter an; setzt die Kompositionswurzel vor dem ersten Controller.</summary>
    class property ServerFactory: TAtlasProblemsServerFactory read FServerFactory write FServerFactory;
    class property EditorsFactory: TAtlasProblemsEditorsFactory read FEditorsFactory write FEditorsFactory;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Problems.Plan,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.UI.Problems.Strings,
  Atlas.IDE.Foundation.Settings;

const
  /// <summary>Programmierfehler beim Zusammenstecken, nie beim Benutzer.</summary>
  cNoAdapters = 'Problems: adapters not installed';

var
  // Laufender Controller für Current, Checking, LastCheck und ProjectRun (#615, #1155).
  CurrentController: TAtlasProblemsController = nil;

{ TAtlasProblemsController }

procedure TAtlasProblemsController.Tick(Sender: TObject);
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
  begin
    Exit;
  end;
  try
    FFlow.Tick(TAtlasIdeSettings.Current);
    // Kürzere Verzögerung als der Takt: öfter nachsehen.
    FTimer.Interval := FFlow.TickMs;
    Publish;
  except
    on E: Exception do
    begin
      FLog('Probleme: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

procedure TAtlasProblemsController.Publish;
var
  mShow: Boolean;
  mStore: TAtlasProblemStore;
begin
  PublishCounts;
  mStore := FFlow.Results.Store;
  if mStore.Version <> FPaintedVersion then
  begin
    FPaintedVersion := mStore.Version;
    TAtlasProblemsPainter.Invalidate;
    FListDue := TAtlasDeadline.After(cListDelayMs);
  end;
  mShow := TAtlasProblemsPlan.Active(TAtlasIdeSettings.Current) and TAtlasIdeSettings.Current.ProblemsMessageList;
  if (mShow <> FListShown) or ((FListedVersion <> mStore.Version) and FListDue.Reached) then
  begin
    FListedVersion := mStore.Version;
    FListShown := mShow;
    if mShow then
    begin
      FList.Update(mStore);
    end
    else
    begin
      FList.Clear;
    end;
  end;
end;

procedure TAtlasProblemsController.PublishCounts;
var
  mShow: Boolean;
  mCounts: TAtlasProblemCounts;
begin
  if Assigned(FOnCounts) and FFlow.Results.CountsDue(TAtlasIdeSettings.Current, mShow, mCounts) then
  begin
    FOnCounts(mShow, mCounts);
  end;
end;

procedure TAtlasProblemsController.DeliverDocument(const APull: TAtlasProblemsPull;
  const AReport: TLspDiagnosticReport);
begin
  FFlow.Results.Document(TAtlasIdeSettings.Current, APull, AReport);
end;

procedure TAtlasProblemsController.DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>;
  const ARun: TLspWorkspaceRun);
begin
  FFlow.Results.Workspace(TAtlasIdeSettings.Current, AReports, ARun);
end;

class function TAtlasProblemsController.GetLastCheck: TAtlasProblemsCheck;
begin
  Result := Default(TAtlasProblemsCheck);
  if CurrentController <> nil then
  begin
    Result := CurrentController.FFlow.Results.LastCheck;
  end;
end;

constructor TAtlasProblemsController.Create(const ASession: TAtlasProblemsSessionFunc;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  if not (Assigned(FServerFactory) and Assigned(FEditorsFactory)) then
  begin
    raise EInvalidOpException.Create(cNoAdapters);
  end;
  FLog := ALog;
  FServer := FServerFactory(ASession, DeliverDocument, DeliverWorkspace, ALog);
  FFlow := TAtlasProblemsFlow.Create(FServer, FEditorsFactory(), ALog);
  CurrentController := Self;
  FPainter := TAtlasProblemsPainter.Create(FFlow.Results.Store);
  FList := TAtlasProblemsList.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasProblemsController.Destroy;
begin
  if CurrentController = Self then
  begin
    CurrentController := nil;
  end;
  FTimer.Free;
  if FFlow <> nil then
  begin
    BeginShutdown;
    WaitShutdown;
  end;
  FList.Free;
  FPainter.Free;
  FFlow.Free;
  FServer := nil;
  inherited Destroy;
end;

procedure TAtlasProblemsController.BeginShutdown;
begin
  FFlow.StopPulls;
end;

procedure TAtlasProblemsController.WaitShutdown;
begin
  FServer.WaitStopped;
  FFlow.Stopped;
end;

function TAtlasProblemsController.ProblemsAt(const AFileName: string; ALine,
  ACharacter: Integer): TArray<TAtlasProblem>;
var
  mProblem: TAtlasProblem;
  mUnused: Integer;
  mStore: TAtlasProblemStore;
begin
  Result := nil;
  mStore := FFlow.Results.Store;
  if TAtlasProblemsPlan.Shown(TAtlasIdeSettings.Current) then
  begin
    Result := mStore.At(AFileName, ALine, ACharacter);
  end;
  if TAtlasProblemsPlan.InactiveShown(TAtlasIdeSettings.Current) then
  begin
    for mProblem in mStore.InactiveAt(AFileName, ALine, ACharacter) do
    begin
      Result := Result + [mProblem];
      // Hinweis in der Sprache des Plugins statt der Meldung des Servers.
      Result[High(Result)].Message := mProblem.InactiveHint(TAtlasProblemsStrings.Text(
        TAtlasProblemsTextId.InactiveCondition),
        TAtlasProblemsStrings.Text(TAtlasProblemsTextId.InactiveTarget),
        TAtlasProblemsStrings.Text(TAtlasProblemsTextId.InactiveRegion));
    end;
  end;
  // uses-Einträge (#621): Grund in der Sprache des Plugins, Zahl der ungenutzten für „Alle entfernen“.
  if not TAtlasProblemsPlan.UsesDimmed(TAtlasIdeSettings.Current) then
  begin
    Exit;
  end;
  mUnused := Length(mStore.UnusedUses(AFileName));
  for mProblem in mStore.UsesAt(AFileName, ALine, ACharacter) do
  begin
    Result := Result + [mProblem];
    Result[High(Result)].Message := UsesHint(mProblem);
    Result[High(Result)].UsesUnusedCount := mUnused;
  end;
end;

class function TAtlasProblemsController.UsesHint(const AProblem: TAtlasProblem): string;
const
  cHints: array[TAtlasProblemsUsesHint] of TAtlasProblemsTextId = (TAtlasProblemsTextId.UsesUnusedHint,
    TAtlasProblemsTextId.UsesInitializationHint, TAtlasProblemsTextId.UsesAllowlistHint,
    TAtlasProblemsTextId.UsesImplementationHint);
begin
  Result := TAtlasProblemsStrings.Fmt(cHints[TAtlasProblemsPlan.UsesHint(AProblem.UsesState)], [AProblem.UsesUnit]);
end;

class function TAtlasProblemsController.Current: TAtlasProblemStore;
begin
  Result := nil;
  if CurrentController <> nil then
  begin
    Result := CurrentController.FFlow.Results.Store;
  end;
end;

class function TAtlasProblemsController.Checking: Boolean;
begin
  Result := (CurrentController <> nil) and CurrentController.FFlow.Checking;
end;

class function TAtlasProblemsController.Paused: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

class function TAtlasProblemsController.ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean;
begin
  ARun := Default(TLspWorkspaceRun);
  AFinishedAgoMs := High(UInt64);
  Result := (CurrentController <> nil) and CurrentController.FFlow.Results.ProjectRun(ARun, AFinishedAgoMs);
end;

end.
