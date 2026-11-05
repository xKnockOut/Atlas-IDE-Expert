unit Atlas.IDE.Tracker.IssuesStatus;

// Anzeigen von „Meine Issues“ außerhalb der Kachel (aus
// Atlas.IDE.Tracker.MyIssues gelöst, #1455):
// - Statusfeld (#591): Zeile atlas.issue „Issue: ATL-123 Titel“ (Klick beendet
//   das Issue nach Rückfrage), darunter die Checkliste (#1273,
//   issues.checklistStatus) und „Anhängen …“ (#1276).
// - Commit-Präfix (issues.commitPattern), solange ein Issue aktuell ist: im
//   Commit-Dialog der IDE (das Nachrichtenfeld wird einmal je Dialog vorne
//   ergänzt) und über den Git-Hook prepare-commit-msg
//   (Atlas.Core.Tracker.CommitHook).
// - Titel der Kachel (TAtlasIdeIssuesTitle): „Meine Issues · Projekt“, mit
//   Punkt bei neuen Änderungen (#1271).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.IDE.Tracker.IssueCommands;

type
  TAtlasIdeIssuesStatus = class
  public const
    /// <summary>Takt für Commit-Dialog und Statuszeile.</summary>
    cWatchMs = 700;
    /// <summary>Alle so viele Takte die Statuszeile neu (Projekt- oder Branch-Wechsel).</summary>
    cStatusTicks = 7;
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FCommands: TAtlasIdeIssueCommands;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FChecklistLine: TAtlasStatusLine;
    FChecklistLineRef: IAtlasStatusItem;
    FAttachLine: TAtlasStatusLine;
    FAttachLineRef: IAtlasStatusItem;
    FWatch: TTimer;
    FTicks: Integer;
    FPrefix: string;
    // Nachrichtenfelder von Commit-Dialogen, die schon ergänzt wurden.
    FFilled: TList<THandle>;
    // Git-Ordner, in die diese Sitzung ein Präfix für den Hook geschrieben hat (Abschalten löscht es dort).
    FPrefixDirs: TList<string>;
    procedure Inactive;
    procedure EnsureLine;
    procedure UpdateChecklist(const AProject, AKey: string);
    procedure RemoveChecklist;
    procedure ChecklistClicked;
    procedure UpdateAttach(const AKey: string);
    procedure RemoveAttach;
    procedure WatchTick(Sender: TObject);
    procedure FillCommitDialog;
    procedure SyncPrefix(const AProject: string);
    procedure ClearPrefixes;
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
      ACommands: TAtlasIdeIssueCommands);
    destructor Destroy; override;
    /// <summary>Takt für Commit-Dialog und Statuszeile anlegen.</summary>
    procedure Start;
    /// <summary>Takt und Statuszeilen weg; das Präfix für den Hook bleibt (gilt außerhalb der IDE weiter).</summary>
    procedure Stop;
    /// <summary>Statuszeilen, Präfix und Uhr der Zeiterfassung auf das aktuelle Issue stellen.</summary>
    procedure Update;
    /// <summary>Alle Statuszeilen entfernen.</summary>
    procedure Remove;
  end;

  /// <summary>Titel der Kachel und Schalter welcomePage.issues, wie zuletzt an die Seite gemeldet.</summary>
  TAtlasIdeIssuesTitle = class
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FText: string;
    FActive: Boolean;
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
    /// <summary>„Meine Issues · Projekt“, mit Punkt bei neuen Änderungen (#1271).</summary>
    function Text: string;
    /// <summary>Titel oder Schalter geändert: der Willkommensseite melden.</summary>
    procedure Update;
    /// <summary>Update über die Nachrichtenschleife (nicht mitten im Zeichnen); hält den Besitzer bis dahin.
    /// </summary>
    procedure Queue;
    /// <summary>Neu beim Start: der erste Update meldet sich.</summary>
    procedure Reset;
    /// <summary>Zuletzt gemeldeter Titel.</summary>
    property Last: string read FText;
  end;

implementation

uses
  Winapi.Windows,
  System.StrUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Naming,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.MyIssues,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.Attach,
  Atlas.IDE.Tracker.IssueChecklists;

const
  // Commit-Dialog der Versionsverwaltung der IDE (Git, SVN, Mercurial): am Namen der Formularklasse erkannt.
  cCommitMark = 'Commit';
  cLogPrefixAdded = 'Meine Issues: Präfix im Commit-Dialog der IDE ergänzt';
  cLogPrefixNotWritten = 'Meine Issues: Präfix-Datei für den Git-Hook nicht geschrieben';
  cLogPrefixNotCleared = 'Meine Issues: Präfix-Datei für den Git-Hook nicht gelöscht';

type
  // Zugriff auf ReadOnly (geschützt in TCustomEdit) für das Nachrichtenfeld des Commit-Dialogs.
  TEditAccess = class(TCustomEdit);

/// <summary>Statuszeile AId mit Klick AAction neu anlegen und anmelden.</summary>
function NewLine(const AId: string; AOrder: Integer; const AAction: TProc; out ARef: IAtlasStatusItem):
  TAtlasStatusLine;
begin
  Result := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, AId, AOrder, AAction);
  ARef := Result;
  TAtlasStatusRegistry.Default.Add(ARef);
end;

/// <summary>Statuszeile AId abmelden; ALine und ARef sind danach nil.</summary>
procedure DropLine(const AId: string; var ALine: TAtlasStatusLine; var ARef: IAtlasStatusItem);
begin
  if ALine = nil then
  begin
    Exit;
  end;
  ALine.Detach;
  TAtlasStatusRegistry.Default.Remove(AId);
  ALine := nil;
  ARef := nil;
end;

/// <summary>Erstes beschreibbares, sichtbares Nachrichtenfeld (Memo) in AControl.</summary>
function FindMessageMemo(AControl: TWinControl): TCustomMemo;
var
  mIndex: Integer;
  mChild: TControl;
begin
  Result := nil;
  mIndex := 0;
  while (Result = nil) and (mIndex < AControl.ControlCount) do
  begin
    mChild := AControl.Controls[mIndex];
    Inc(mIndex);
    if not mChild.Visible then
    begin
      Continue;
    end;
    if (mChild is TCustomMemo) and mChild.Enabled and not TEditAccess(mChild).ReadOnly then
    begin
      Result := TCustomMemo(mChild);
    end
    else if mChild is TWinControl then
    begin
      Result := FindMessageMemo(TWinControl(mChild));
    end;
  end;
end;

/// <summary>Ist AForm ein Commit-Dialog der IDE?</summary>
function IsCommitDialog(AForm: TCustomForm): Boolean;
begin
  Result := (AForm <> nil) and (ContainsText(AForm.ClassName, cCommitMark) or ContainsText(AForm.Name, cCommitMark));
end;

{ TAtlasIdeIssuesStatus }

constructor TAtlasIdeIssuesStatus.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
  ACommands: TAtlasIdeIssueCommands);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
  FCommands := ACommands;
  FFilled := TList<THandle>.Create;
  FPrefixDirs := TList<string>.Create;
end;

destructor TAtlasIdeIssuesStatus.Destroy;
begin
  Stop;
  FFilled.Free;
  FPrefixDirs.Free;
  inherited;
end;

procedure TAtlasIdeIssuesStatus.Start;
begin
  if FWatch <> nil then
  begin
    Exit;
  end;
  FWatch := TTimer.Create(nil);
  FWatch.Interval := cWatchMs;
  FWatch.OnTimer := WatchTick;
end;

procedure TAtlasIdeIssuesStatus.Stop;
begin
  FreeAndNil(FWatch);
  Remove;
end;

procedure TAtlasIdeIssuesStatus.Inactive;
begin
  Remove;
  FServices.SyncTime('', '');
  FPrefix := '';
  // Beim Entladen (Stop) bleibt das Präfix, damit der Hook außerhalb der IDE weiter gilt.
  if FContext.Started then
  begin
    ClearPrefixes;
  end;
  if FWatch <> nil then
  begin
    FWatch.Enabled := False;
  end;
end;

procedure TAtlasIdeIssuesStatus.EnsureLine;
var
  mKeep: IAtlasIdeIssuesActions;
  mAction: TProc;
begin
  if FLine <> nil then
  begin
    Exit;
  end;
  mKeep := FContext.Actions;
  // Typisierte Variable: Der Konstruktor ist überladen.
  mAction := procedure
    begin
      if mKeep <> nil then
      begin
        mKeep.EndActive;
      end;
    end;
  FLine := NewLine(TAtlasMyIssues.cStatusId, TAtlasMyIssues.cStatusOrder, mAction, FLineRef);
end;

procedure TAtlasIdeIssuesStatus.Update;
var
  mProject, mText: string;
  mData: TAtlasIssuesView;
begin
  if not FContext.Started or not TAtlasIdeIssuesTargets.Active or (FContext.Actions = nil) then
  begin
    Inactive;
    Exit;
  end;
  if FWatch <> nil then
  begin
    FWatch.Enabled := True;
  end;
  mProject := FContext.CurrentProject;
  mData := FContext.Actions.ViewOf(mProject);
  FPrefix := TAtlasMyIssues.CommitPrefix(mData.Active, FServices.Options.CommitPattern);
  try
    SyncPrefix(mProject);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Tracker, E);
    end;
  end;
  if not mData.Active.Active then
  begin
    Remove;
    FServices.SyncTime('', '');
    Exit;
  end;
  FServices.SyncTime(mProject, mData.Active.Key);
  EnsureLine;
  mText := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusLine, [Trim(mData.Active.Key + ' ' + mData.Active.Title)]);
  FLine.Update(mText, TAtlasStatusState.Neutral, mData.Active.Key, TAtlasTrackerIssuesText.TileText(mData),
    TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStatusHint));
  UpdateChecklist(mProject, mData.Active.Key);
  UpdateAttach(mData.Active.Key);
end;

procedure TAtlasIdeIssuesStatus.Remove;
begin
  RemoveChecklist;
  RemoveAttach;
  DropLine(TAtlasMyIssues.cStatusId, FLine, FLineRef);
end;

procedure TAtlasIdeIssuesStatus.UpdateChecklist(const AProject, AKey: string);
var
  mTarget: TAtlasTrackerTarget;
  mProgress: TAtlasChecklistProgress;
  mText: string;
  mAction: TProc;
begin
  if (FServices.Preview = nil) or not TAtlasIdeSettings.Current.IssuesChecklistStatus or (Trim(AKey) = '') then
  begin
    RemoveChecklist;
    Exit;
  end;
  // Stand aus dem Zwischenspeicher der Vorschau; fehlt er oder ist er alt, frischt ihn Prefetch im Hintergrund auf.
  mTarget := FContext.TargetOf(AProject);
  FServices.Preview.Checklists.Prefetch(mTarget, AKey);
  // Ohne Checkliste kein Feld.
  if not FServices.Preview.Checklists.Progress(mTarget, AKey, mProgress) or not mProgress.Any then
  begin
    RemoveChecklist;
    Exit;
  end;
  if FChecklistLine = nil then
  begin
    // Typisierte Variable: Der Konstruktor ist überladen.
    mAction := ChecklistClicked;
    FChecklistLine := NewLine(TAtlasMyIssues.cChecklistStatusId, TAtlasMyIssues.cChecklistStatusOrder, mAction,
      FChecklistLineRef);
  end;
  mText := TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistStatusLine, [AKey, mProgress.Text]);
  FChecklistLine.Update(mText, TAtlasStatusState.Neutral, mText, mText,
    TAtlasStrings.Fmt(TAtlasTextId.IssueChecklistProgress, [mProgress.Done, mProgress.Total]) + sLineBreak +
    TAtlasStrings.Text(TAtlasTextId.IssueChecklistStatusHint));
end;

procedure TAtlasIdeIssuesStatus.RemoveChecklist;
begin
  DropLine(TAtlasMyIssues.cChecklistStatusId, FChecklistLine, FChecklistLineRef);
end;

procedure TAtlasIdeIssuesStatus.ChecklistClicked;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mData: TAtlasIssuesView;
      mIssue: TAtlasTrackerIssue;
    begin
      if not FContext.Started or (FContext.Actions = nil) then
      begin
        Exit;
      end;
      mData := FContext.Actions.ViewOf(FContext.CurrentProject);
      if not mData.Active.Active or (Trim(mData.Active.Key) = '') then
      begin
        Exit;
      end;
      // In der Vorschau an der Liste; ist sie aus, im Browser.
      if (FServices.Preview <> nil) and TAtlasIdeIssuePreview.Active then
      begin
        FServices.Preview.ShowChecklist(FContext.TargetOf(FContext.CurrentProject), mData.Active.Key);
      end
      else
      begin
        mIssue := Default(TAtlasTrackerIssue);
        mIssue.Key := mData.Active.Key;
        FCommands.Browse(mIssue);
      end;
    end);
end;

procedure TAtlasIdeIssuesStatus.UpdateAttach(const AKey: string);
var
  mAction: TProc;
begin
  if not TAtlasIdeIssueAttach.Active or (FServices.Attach = nil) then
  begin
    RemoveAttach;
    Exit;
  end;
  if FAttachLine = nil then
  begin
    // Typisierte Variable: Der Konstruktor ist überladen.
    mAction := FCommands.AttachPrompt;
    FAttachLine := NewLine(TAtlasMyIssues.cAttachStatusId, TAtlasMyIssues.cAttachStatusOrder, mAction,
      FAttachLineRef);
  end;
  FAttachLine.Update(TAtlasStrings.Fmt(TAtlasTextId.AttachStatusLine, [AKey]), TAtlasStatusState.Neutral, AKey,
    AKey, TAtlasStrings.Text(TAtlasTextId.AttachStatusHint));
end;

procedure TAtlasIdeIssuesStatus.RemoveAttach;
begin
  DropLine(TAtlasMyIssues.cAttachStatusId, FAttachLine, FAttachLineRef);
end;

procedure TAtlasIdeIssuesStatus.WatchTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      Inc(FTicks);
      if FTicks mod cStatusTicks = 0 then
      begin
        Update;
      end;
      FillCommitDialog;
    end);
end;

procedure TAtlasIdeIssuesStatus.FillCommitDialog;
var
  mForm: TCustomForm;
  mMemo: TCustomMemo;
  mIndex: Integer;
  mText: string;
begin
  // Vergessene Felder: Fenster gibt es nicht mehr.
  for mIndex := FFilled.Count - 1 downto 0 do
  begin
    if not IsWindow(FFilled[mIndex]) then
    begin
      FFilled.Delete(mIndex);
    end;
  end;
  mForm := Screen.ActiveForm;
  if (FPrefix = '') or not IsCommitDialog(mForm) then
  begin
    Exit;
  end;
  mMemo := FindMessageMemo(mForm);
  if (mMemo = nil) or not mMemo.HandleAllocated or FFilled.Contains(mMemo.Handle) then
  begin
    Exit;
  end;
  // Einmal je Dialog: Was der Benutzer danach ändert, bleibt.
  FFilled.Add(mMemo.Handle);
  mText := TAtlasTrackerNaming.Prefixed(TEditAccess(mMemo).Text, FPrefix);
  if mText <> TEditAccess(mMemo).Text then
  begin
    TEditAccess(mMemo).Text := mText;
    mMemo.SelStart := Length(mText);
    TAtlasGuard.Log(cLogPrefixAdded);
  end;
end;

procedure TAtlasIdeIssuesStatus.SyncPrefix(const AProject: string);
var
  mState: TAtlasIssuesState;
  mActive: TAtlasActiveIssue;
  mTarget: TAtlasTrackerTarget;
  mPrefix: string;
begin
  mState := FContext.StateOf(AProject);
  if (AProject = '') or (mState.GitDir = '') or (mState.Hook <> TAtlasMyIssues.cHookYes) or
    not DirectoryExists(mState.GitDir) then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AProject);
  mActive := TAtlasMyIssues.Effective(mState, mTarget.Provider, mTarget.Project, FContext.BranchOf(AProject));
  mPrefix := TAtlasMyIssues.CommitPrefix(mActive, FServices.Options.CommitPattern);
  if (mPrefix <> '') and not FPrefixDirs.Contains(mState.GitDir) then
  begin
    FPrefixDirs.Add(mState.GitDir);
  end;
  if (TAtlasCommitHook.ReadPrefix(mState.GitDir) <> mPrefix) and
    not TAtlasCommitHook.WritePrefix(mState.GitDir, mPrefix) then
  begin
    TAtlasGuard.Log(cLogPrefixNotWritten);
  end;
end;

procedure TAtlasIdeIssuesStatus.ClearPrefixes;
var
  mDir: string;
begin
  // Bereich abgeschaltet: Ohne aktuelles Issue soll der Hook auch außerhalb der IDE nichts mehr voranstellen.
  for mDir in FPrefixDirs do
  begin
    if not TAtlasCommitHook.WritePrefix(mDir, '') then
    begin
      TAtlasGuard.Log(cLogPrefixNotCleared);
    end;
  end;
  FPrefixDirs.Clear;
end;

{ TAtlasIdeIssuesTitle }

constructor TAtlasIdeIssuesTitle.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
end;

function TAtlasIdeIssuesTitle.Text: string;
var
  mProject: string;
begin
  mProject := '';
  if FContext.Started and TAtlasIdeIssuesTargets.Active then
  begin
    mProject := FContext.CurrentProject;
  end;
  Result := TAtlasTrackerIssuesText.TitleText(FContext.ProjectName(mProject), (mProject <> '') and
    (Length(FServices.UnseenOf(FContext.TargetOf(mProject))) > 0));
end;

procedure TAtlasIdeIssuesTitle.Update;
var
  mTitle: string;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  mTitle := Text;
  // Nur nach einem Sprachwechsel, mit anderem Projekt im Titel bzw. umgeschaltetem welcomePage.issues.
  if (mTitle <> FText) or (FActive <> TAtlasIdeIssuesTargets.Active) then
  begin
    FText := mTitle;
    FActive := TAtlasIdeIssuesTargets.Active;
    if FContext.Welcome <> nil then
    begin
      FContext.Welcome.TileInfoChanged(TAtlasIdeIssuesContext.cTileId);
    end;
  end;
end;

procedure TAtlasIdeIssuesTitle.Queue;
var
  mKeep: IAtlasIdeIssuesActions;
begin
  mKeep := FContext.Actions;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tracker,
    procedure
    begin
      if mKeep <> nil then
      begin
        mKeep.UpdateTileInfo;
      end;
    end);
end;

procedure TAtlasIdeIssuesTitle.Reset;
begin
  FText := '';
end;

end.
