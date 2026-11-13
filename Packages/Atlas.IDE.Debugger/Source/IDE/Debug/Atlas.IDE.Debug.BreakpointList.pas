unit Atlas.IDE.Debug.BreakpointList;

// Haltepunktfenster (#863), IDE-Seite: liest die Quelltext-Haltepunkte der IDE
// (IOTADebuggerServices.SourceBkpts) in Zeilen (Atlas.Core.Debug.BreakpointList),
// ergänzt Methode (Atlas.Core.Editor.MethodToggle über den Text aus Puffer oder
// Platte), Trefferzahl dieser Sitzung und Etiketten
// (Atlas.Core.Debug.BreakpointTags, persönlich unter %LOCALAPPDATA%\Atlas) und
// führt die Befehle des Fensters aus.
// - Änderungen der IDE (angelegt, gelöscht, geändert) meldet die Debug-Sitzung
//   über IAtlasIdeDebugBreakpointListener; gelesen wird danach gesammelt über
//   einen Zeitgeber, nicht im Notifier.
// - Trefferzahl: Beginn einer Sitzung setzt auf 0; jeder Halt an einer Zeile
//   mit Quelltext-Haltepunkt zählt eins dazu.
// - Löschen merkt sich Ort, Eigenschaften und Etiketten; „Rückgängig“ legt die
//   zuletzt gelöschten Haltepunkte wieder an, solange das Modul läuft.
// Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeDebugBreakpointList = class
  public
    /// <summary>Fenster anmelden (Register), damit der Desktop es wiederherstellt.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Teil DebugBreakpointsWindow: Sitzung beobachten, Etiketten laden.</summary>
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl „Haltepunkte (Atlas)“.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Debug.BreakpointList,
  Atlas.Core.Debug.BreakpointTags,
  Atlas.Core.Debug.BreakpointCheck,
  Atlas.Core.Debug.BreakpointRules,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.BreakpointCheck,
  Atlas.IDE.Debug.BreakpointSets,
  Atlas.IDE.Debug.BreakpointRules,
  Atlas.UI.Debug.BreakpointCheck,
  Atlas.UI.Debug.BreakpointRules,
  Atlas.IDE.Debug.BreakpointsWindow,
  Atlas.UI.Debug.BreakpointsFrame,
  Atlas.UI.Debug.Strings;

const
  cRefreshMs = 150;
  cAtlasFolder = 'Atlas';
  cLocalAppData = 'LOCALAPPDATA';

type
  /// <summary>Gelöschter Haltepunkt für „Rückgängig“.</summary>
  TDeleted = record
    Project: string;
    FileName: string;
    Line: Integer;
    Condition: string;
    PassCount: Integer;
    Group: string;
    Enabled: Boolean;
    Tags: TArray<string>;
  end;

  TListener = class(TAtlasIdeDebugListener, IAtlasIdeDebugBreakpointListener)
  public
    procedure DebugStarted; override;
    procedure DebugStopped(AStop: TAtlasDebugStop); override;
    procedure DebugEnded; override;
    procedure BreakpointsChanged;
  end;

  TTicker = class
  public
    procedure Tick(Sender: TObject);
  end;

var
  GMessage: TProc<string>;
  GListener: IAtlasIdeDebugListener;
  GHits: TAtlasBreakpointHits;
  GTags: TAtlasBreakpointTags;
  GTimer: TTimer;
  GTicker: TTicker;
  GUndo: TArray<TDeleted>;

function TagFolder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable(cLocalAppData), cAtlasFolder);
end;

function ProjectOf(const AFileName: string): string;
begin
  Result := TAtlasIdeFiles.ProjectOfFile(AFileName);
  if Result = '' then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
  end;
end;

function Frame: TAtlasDebugBreakpointsFrame;
begin
  Result := TAtlasIdeDebugBreakpointsWindow.ExistingFrame;
end;

procedure ScheduleRefresh;
begin
  if GTimer <> nil then
  begin
    GTimer.Enabled := False;
    GTimer.Enabled := True;
  end;
end;

{ Lesen }

/// <summary>Methodenrümpfe je Datei, einmal je Auffrischen gelesen.</summary>
function MethodOf(APlaces: TDictionary<string, TArray<TAtlasMethodPlace>>; const AFileName: string;
  ALine: Integer): string;
var
  mPlaces: TArray<TAtlasMethodPlace>;
  mText: string;
  mPlace: TAtlasMethodPlace;
begin
  if not APlaces.TryGetValue(AFileName.ToLower, mPlaces) then
  begin
    mPlaces := nil;
    if TAtlasIdeFiles.SourceText(AFileName, mText) then
    begin
      mPlaces := TAtlasMethodToggle.Places(mText);
    end;
    APlaces.Add(AFileName.ToLower, mPlaces);
  end;
  Result := '';
  if TAtlasMethodToggle.BodyAt(mPlaces, ALine - 1, mPlace) then
  begin
    Result := mPlace.Name;
  end;
end;

/// <summary>Befund der letzten Prüfung (#577) für die Stelle (Zeile ab 1); False ohne Befund.</summary>
function ProblemAt(const AProblems: TAtlasBreakpointProblems; const AFileName: string; ALine: Integer;
  out AProblem: TAtlasBreakpointProblem): Boolean;
var
  mProblem: TAtlasBreakpointProblem;
  mFileName: string;
begin
  mFileName := AFileName.Replace('/', PathDelim);
  for mProblem in AProblems do
  begin
    if (mProblem.Line = ALine - 1) and SameText(mProblem.FileName.Replace('/', PathDelim), mFileName) then
    begin
      AProblem := mProblem;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Regeln (#864) an der Stelle (Zeile ab 1) als Text; '' ohne.</summary>
function RulesOf(const AFileName: string; ALine: Integer): string;
var
  mRule: TAtlasBreakpointRule;
begin
  Result := '';
  if TAtlasIdeBreakpointRules.RuleAt(AFileName, ALine - 1, mRule) and not mRule.IsEmpty then
  begin
    Result := TAtlasBreakpointTexts.RuleText(mRule,
      TAtlasBreakpointRuleDialog.TriggerText(TAtlasRuleTrigger.Create(mRule.TriggerFile, mRule.TriggerLine)));
  end;
end;

function RowOf(const ABreakpoint: IOTASourceBreakpoint;
  APlaces: TDictionary<string, TArray<TAtlasMethodPlace>>;
  const AProblems: TAtlasBreakpointProblems): TAtlasBreakpointRow;
var
  mProblem: TAtlasBreakpointProblem;
begin
  Result := TAtlasBreakpointRow.Create(ABreakpoint.FileName, ABreakpoint.LineNumber);
  Result.Enabled := ABreakpoint.Enabled;
  Result.Condition := ABreakpoint.Expression;
  Result.PassCount := ABreakpoint.PassCount;
  Result.Group := ABreakpoint.GroupName;
  Result.Method := MethodOf(APlaces, Result.FileName, Result.Line);
  if GHits <> nil then
  begin
    Result.Hits := GHits.Count(Result.FileName, Result.Line);
  end;
  Result.Tags := GTags.TagsOf(ProjectOf(Result.FileName), Result.FileName, Result.Line);
  // Satz (#586): Sätze des Projekts, in denen die Stelle steht.
  Result.SetName := string.Join(', ', TAtlasIdeBreakpointSets.SetNamesAt(Result.FileName, Result.Line - 1));
  // Greift nicht (#577): Befund der letzten Prüfung.
  if ProblemAt(AProblems, Result.FileName, Result.Line, mProblem) then
  begin
    Result.NotEffective := True;
    Result.Reason := TAtlasBreakpointCheckDialog.ReasonText(mProblem);
  end;
  Result.Rules := RulesOf(Result.FileName, Result.Line);
end;

function ReadRows: TArray<TAtlasBreakpointRow>;
var
  mServices: IOTADebuggerServices;
  mPlaces: TDictionary<string, TArray<TAtlasMethodPlace>>;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
  mProblems: TAtlasBreakpointProblems;
begin
  Result := nil;
  mProblems := TAtlasIdeBreakpointCheck.LastProblems;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mPlaces := TDictionary<string, TArray<TAtlasMethodPlace>>.Create;
  try
    for mIndex := 0 to mServices.SourceBkptCount - 1 do
    begin
      mBreakpoint := mServices.SourceBkpts[mIndex];
      if mBreakpoint <> nil then
      begin
        Result := Result + [RowOf(mBreakpoint, mPlaces, mProblems)];
      end;
    end;
  finally
    mPlaces.Free;
  end;
end;

function KnownTags: TArray<string>;
begin
  Result := GTags.AllTags(TAtlasIdeFiles.ActiveProjectFile);
end;

procedure Refresh;
var
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFrame.SetRows(ReadRows, (GHits <> nil) and GHits.HasRun);
  mFrame.SetKnownTags(KnownTags);
  mFrame.SetUndoCount(Length(GUndo));
end;

{ Befehle }

procedure Toggle(const ARows: TArray<TAtlasBreakpointRow>; AEnable: Boolean);
var
  mRow: TAtlasBreakpointRow;
  mBreakpoint: IOTABreakpoint;
begin
  for mRow in ARows do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Find(mRow.FileName, mRow.Line - 1);
    if mBreakpoint <> nil then
    begin
      mBreakpoint.Enabled := AEnable;
    end;
  end;
  Refresh;
end;

function Remember(const ABreakpoint: IOTABreakpoint; const ARow: TAtlasBreakpointRow): TDeleted;
begin
  Result.Project := ProjectOf(ARow.FileName);
  Result.FileName := ARow.FileName;
  Result.Line := ARow.Line;
  Result.Condition := ABreakpoint.Expression;
  Result.PassCount := ABreakpoint.PassCount;
  Result.Group := ABreakpoint.GroupName;
  Result.Enabled := ABreakpoint.Enabled;
  Result.Tags := GTags.TagsOf(Result.Project, ARow.FileName, ARow.Line);
end;

procedure DeleteRows(const ARows: TArray<TAtlasBreakpointRow>);
var
  mServices: IOTADebuggerServices;
  mRow: TAtlasBreakpointRow;
  mBreakpoint: IOTABreakpoint;
  mDeleted: TArray<TDeleted>;
  mEntry: TDeleted;
begin
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mDeleted := nil;
  for mRow in ARows do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Find(mRow.FileName, mRow.Line - 1);
    if mBreakpoint <> nil then
    begin
      mEntry := Remember(mBreakpoint, mRow);
      mServices.RemoveBreakpoint(mBreakpoint);
      GTags.Forget(mEntry.Project, mEntry.FileName, mEntry.Line);
      mDeleted := mDeleted + [mEntry];
    end;
  end;
  if Length(mDeleted) > 0 then
  begin
    GUndo := mDeleted;
    TAtlasBreakpointTags.Save(TagFolder, GTags);
  end;
  Refresh;
end;

procedure Restore(const AEntry: TDeleted);
var
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoint := TAtlasIdeBreakpoints.Add(AEntry.FileName, AEntry.Line - 1);
  if mBreakpoint = nil then
  begin
    Exit;
  end;
  mBreakpoint.Expression := AEntry.Condition;
  mBreakpoint.PassCount := AEntry.PassCount;
  mBreakpoint.GroupName := AEntry.Group;
  mBreakpoint.Enabled := AEntry.Enabled;
  GTags.SetTags(AEntry.Project, AEntry.FileName, AEntry.Line, AEntry.Tags);
end;

procedure UndoDelete;
var
  mEntry: TDeleted;
begin
  for mEntry in GUndo do
  begin
    Restore(mEntry);
  end;
  GUndo := nil;
  TAtlasBreakpointTags.Save(TagFolder, GTags);
  Refresh;
end;

procedure Open(const ARows: TArray<TAtlasBreakpointRow>);
begin
  if Length(ARows) > 0 then
  begin
    TAtlasIdeNavigation.GoToLocation(ARows[0].FileName, ARows[0].Line - 1, 0);
  end;
end;

procedure Properties(const ARows: TArray<TAtlasBreakpointRow>);
var
  mBreakpoint: IOTABreakpoint;
begin
  if Length(ARows) = 0 then
  begin
    Exit;
  end;
  mBreakpoint := TAtlasIdeBreakpoints.Find(ARows[0].FileName, ARows[0].Line - 1);
  if mBreakpoint <> nil then
  begin
    // Eigenschaften-Dialog der IDE; Änderungen meldet der Notifier.
    mBreakpoint.Edit(True);
  end;
end;

procedure ChangeTag(const ARows: TArray<TAtlasBreakpointRow>; const ATag: string; AAdd: Boolean);
var
  mRow: TAtlasBreakpointRow;
  mProject: string;
begin
  for mRow in ARows do
  begin
    mProject := ProjectOf(mRow.FileName);
    if AAdd then
    begin
      GTags.AddTag(mProject, mRow.FileName, mRow.Line, ATag);
    end
    else
    begin
      GTags.RemoveTag(mProject, mRow.FileName, mRow.Line, ATag);
    end;
  end;
  TAtlasBreakpointTags.Save(TagFolder, GTags);
  Refresh;
end;

procedure ResetHits;
begin
  if GHits <> nil then
  begin
    GHits.Reset;
  end;
  Refresh;
end;

procedure WireFrame(AFrame: TAtlasDebugBreakpointsFrame);
begin
  AFrame.Events.OnToggle := Toggle;
  AFrame.Events.OnDelete := DeleteRows;
  AFrame.Events.OnOpen := Open;
  AFrame.Events.OnProperties := Properties;
  AFrame.Events.OnTag := ChangeTag;
  AFrame.Events.OnUndo := UndoDelete;
  AFrame.Events.OnResetHits := ResetHits;
  Refresh;
end;

{ TListener }

procedure TListener.DebugStarted;
begin
  if GHits <> nil then
  begin
    GHits.Start;
  end;
  ScheduleRefresh;
end;

procedure TListener.DebugStopped(AStop: TAtlasDebugStop);
var
  mFileName: string;
  mLine: Integer;
begin
  if (AStop <> TAtlasDebugStop.Paused) or (GHits = nil) then
  begin
    Exit;
  end;
  if TAtlasIdeBreakpoints.Position(TAtlasIdeDebugSession.StoppedThread, mFileName, mLine) and
    TAtlasIdeBreakpoints.Exists(mFileName, mLine) then
  begin
    GHits.Hit(mFileName, mLine + 1);
    ScheduleRefresh;
  end;
end;

procedure TListener.DebugEnded;
begin
  ScheduleRefresh;
end;

procedure TListener.BreakpointsChanged;
begin
  ScheduleRefresh;
end;

{ TTicker }

procedure TTicker.Tick(Sender: TObject);
begin
  GTimer.Enabled := False;
  Refresh;
end;

{ TAtlasIdeDebugBreakpointList }

class procedure TAtlasIdeDebugBreakpointList.Install(const AMessage: TProc<string>);
begin
  GMessage := AMessage;
  TAtlasIdeDebugBreakpointsWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugBreakpointsFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugBreakpointsWindow.Prepare;
end;

class procedure TAtlasIdeDebugBreakpointList.Uninstall;
begin
  Release;
  TAtlasIdeDebugBreakpointsWindow.Release;
  GMessage := nil;
end;

class procedure TAtlasIdeDebugBreakpointList.Start;
begin
  if GListener <> nil then
  begin
    Exit;
  end;
  GTags := TAtlasBreakpointTags.Load(TagFolder);
  GHits := TAtlasBreakpointHits.Create;
  GTicker := TTicker.Create;
  GTimer := TTimer.Create(nil);
  GTimer.Enabled := False;
  GTimer.Interval := cRefreshMs;
  GTimer.OnTimer := GTicker.Tick;
  GListener := TListener.Create;
  TAtlasIdeDebugSession.AddListener(GListener);
  TAtlasIdeDebugSession.Start;
  ScheduleRefresh;
end;

class procedure TAtlasIdeDebugBreakpointList.Release;
begin
  if GListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(GListener);
  end;
  GListener := nil;
  FreeAndNil(GTimer);
  FreeAndNil(GTicker);
  FreeAndNil(GHits);
  GTags := TAtlasBreakpointTags.Empty;
  GUndo := nil;
end;

class function TAtlasIdeDebugBreakpointList.Started: Boolean;
begin
  Result := GListener <> nil;
end;

class procedure TAtlasIdeDebugBreakpointList.ShowWindow;
begin
  if not Started then
  begin
    if Assigned(GMessage) then
    begin
      GMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsOff));
    end;
    Exit;
  end;
  if TAtlasIdeDebugBreakpointsWindow.Show <> nil then
  begin
    Refresh;
  end;
end;

class procedure TAtlasIdeDebugBreakpointList.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugBreakpointsWindow then
  begin
    TAtlasIdeDebugBreakpointsWindow.Hide;
  end;
end;

class procedure TAtlasIdeDebugBreakpointList.ThemeChanged;
begin
  TAtlasIdeDebugBreakpointsWindow.ApplyTheme;
end;

end.
