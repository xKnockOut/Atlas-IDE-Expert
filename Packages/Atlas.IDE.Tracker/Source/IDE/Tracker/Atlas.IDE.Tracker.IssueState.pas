unit Atlas.IDE.Tracker.IssueState;

// Zustand des aktuellen Issues im Statusfeld (#2124, issues.statusState):
// - Ein Feld für Zustand und Zeit: „ATL-2052 · In Bearbeitung · 1:25“, ohne
//   Zeiterfassung „ATL-2052 · In Bearbeitung“, mit issues.statusState aus nur
//   „ATL-2052 · 1:25“ wie bisher (TAtlasIssueStatus.Text). Der Zustand kommt
//   aus „Meine Issues“ (SetIssue) und nach jedem Lesen vom Tracker; lange
//   Namen gekürzt, der volle im Hinweis.
// - Klick: die erlaubten Übergänge, beim Öffnen frisch gelesen (ohne
//   Zustandsmaschine die Werte des Zustandsfeldes), „Mit Kommentar …“
//   (TAtlasTrackerStateDialog mit Kommentar-Editor #1278), „Beenden …“ wie die
//   Zeile atlas.issue, darunter die Einträge der Zeiterfassung.
// - Befehlspalette: dieselben Übergänge als „ATL-2052: Zur Prüfung geben“
//   (PaletteRows, PaletteRun) aus dem zuletzt gelesenen Stand; gelesen wird
//   beim Wechsel des Issues, beim Öffnen des Menüs und nach jedem Übergang.
// - Geschrieben wird über TAtlasIdeTrackerSync.Apply; das Ergebnis steht als
//   Zeile in der Meldungsansicht.
// Zustand nur mit issues.syncState und einem Anbieter, der schreiben kann.
// Nach Stop erreicht nichts mehr das Feld: Lesen läuft über einen eigenen
// TAtlasVcsWorker, Klicks und Antworten prüfen FStopped.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.StatusState,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.VersionControl.Worker,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.Workflow;

type
  TAtlasIdeIssueStateHooks = record
    /// <summary>Anbieter zum Namen; nil ohne.</summary>
    Provider: TAtlasIdeTimeProvider;
    /// <summary>Transport mit dem Token aus dem Anmeldespeicher (Hintergrund); nil ohne Token.</summary>
    Transport: TAtlasIdeTrackerTransport;
    /// <summary>Zusatzfeld im Statusfeld setzen; Text '' entfernt es.</summary>
    Field: TAtlasIdeTimeStatus;
    /// <summary>Zeile in der Meldungsansicht.</summary>
    Report: TProc<string>;
    /// <summary>„Beenden …“ des aktuellen Issues wie die Zeile atlas.issue.</summary>
    EndIssue: TProc;
    /// <summary>Kommentar-Editor für „Mit Kommentar …“ (#1278); nil mit issues.commentEditor aus.</summary>
    Assist: TAtlasIdeTrackerAssist;
  end;

  /// <summary>Vom Tracker gelesen: Regeln des Zustandsfeldes und seine Werte.</summary>
  TAtlasIssueStateRead = record
    Key: string;
    Succeeded: Boolean;
    Rules: TAtlasTrackerStateRules;
    States: TArray<string>;
  end;

  TAtlasIdeIssueState = class
  public const
    /// <summary>So lange wartet Stop höchstens auf laufendes Lesen.</summary>
    cStopWaitMs = 1000;
  private
    FSync: TAtlasIdeTrackerSync;
    FHooks: TAtlasIdeIssueStateHooks;
    FWorker: TAtlasVcsWorker;
    FMenu: TPopupMenu;
    FIssue: TAtlasTimeIssue;
    // Zustand aus „Meine Issues“ (wie zuletzt gemeldet) und der angezeigte (nach Lesen bzw. Übergang neuer).
    FListState: string;
    FState: string;
    FTime: TAtlasIdeTimeField;
    FRead: TAtlasIssueStateRead;
    FEntries: TArray<TAtlasIssueStateEntry>;
    // Zuletzt gesetzter Text und Hinweis; '' = kein Feld.
    FShown: string;
    FStopped: Boolean;
    procedure Render;
    function ShowsState: Boolean;
    function Writable(out AProvider: IAtlasTrackerProvider; out ATarget: TAtlasTrackerTarget): Boolean;
    procedure Read(const ADone: TProc);
    procedure Readed(const ARead: TAtlasIssueStateRead);
    procedure Clicked(const APoint: TPoint);
    procedure ShowMenu(const APoint: TPoint);
    procedure AddStateItems;
    /// <summary>Übergang bzw. Wert des Menüs; Tag ist die Nummer in FEntries.</summary>
    procedure EntryClick(Sender: TObject);
    procedure CommentClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    procedure Run(const AEntry: TAtlasIssueStateEntry; const AComment: string);
    procedure Applied(const AKey: string; const AChange: TAtlasTrackerWrite; const AAfter: string;
      const AResult: TAtlasTrackerWriteResult);
  public
    constructor Create(ASync: TAtlasIdeTrackerSync; const AHooks: TAtlasIdeIssueStateHooks);
    destructor Destroy; override;
    /// <summary>Feld weg, kein Lesen und kein Menü mehr; danach wirkungslos (beim Entladen).</summary>
    procedure Stop;
    /// <summary>issues.statusState an?</summary>
    class function Active: Boolean; static;
    /// <summary>Aktuelles Issue (TAtlasTimeIssue.None = keins) mit seinem Zustand aus „Meine Issues“.</summary>
    procedure SetIssue(const AIssue: TAtlasTimeIssue; const AState: string);
    /// <summary>Zeit der Zeiterfassung fürs Feld (TAtlasIdeTrackerTime.OnStatus).</summary>
    procedure TimeChanged(const AField: TAtlasIdeTimeField);
    /// <summary>Übergänge des aktuellen Issues für die Befehlspalette, die zu APattern passen.</summary>
    function PaletteRows(const APattern: string): TArray<TAtlasCommand>;
    /// <summary>Zeile AId aus PaletteRows ausführen; False, wenn sie nicht von hier stammt.</summary>
    function PaletteRun(const AId: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.UITypes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.StateDialog,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeIssueState }

constructor TAtlasIdeIssueState.Create(ASync: TAtlasIdeTrackerSync; const AHooks: TAtlasIdeIssueStateHooks);
begin
  inherited Create;
  FSync := ASync;
  FHooks := AHooks;
  FWorker := TAtlasVcsWorker.Create;
  FIssue := TAtlasTimeIssue.None;
  FTime := TAtlasIdeTimeField.None;
end;

destructor TAtlasIdeIssueState.Destroy;
begin
  Stop;
  FWorker.Free;
  inherited;
end;

procedure TAtlasIdeIssueState.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FWorker.Stop(cStopWaitMs);
  if (FShown <> '') and Assigned(FHooks.Field) then
  begin
    FHooks.Field('', '', nil);
  end;
  FStopped := True;
  FShown := '';
  // Das Menü löst auch die Einträge der Zeiterfassung.
  FreeAndNil(FMenu);
  FTime := TAtlasIdeTimeField.None;
  FHooks := Default(TAtlasIdeIssueStateHooks);
  FSync := nil;
end;

class function TAtlasIdeIssueState.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesStatusState;
end;

function TAtlasIdeIssueState.Writable(out AProvider: IAtlasTrackerProvider;
  out ATarget: TAtlasTrackerTarget): Boolean;
begin
  AProvider := nil;
  ATarget := TAtlasTrackerTarget.Create(FIssue.Provider, FIssue.Url, FIssue.Project, '');
  if not FStopped and not FIssue.IsEmpty and Assigned(FHooks.Provider) then
  begin
    AProvider := FHooks.Provider(FIssue.Provider);
  end;
  Result := (AProvider <> nil) and (FSync <> nil) and FSync.Enabled(AProvider, ATarget);
end;

function TAtlasIdeIssueState.ShowsState: Boolean;
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
begin
  Result := Active and Writable(mProvider, mTarget);
end;

procedure TAtlasIdeIssueState.SetIssue(const AIssue: TAtlasTimeIssue; const AState: string);
begin
  if FStopped then
  begin
    Exit;
  end;
  if not FIssue.Same(AIssue) then
  begin
    FIssue := AIssue;
    FListState := AState;
    FState := AState;
    FRead := Default(TAtlasIssueStateRead);
    FEntries := nil;
    if ShowsState then
    begin
      Read(nil);
    end;
  end
  else if not SameText(FListState, AState) then
  begin
    // „Meine Issues“ kennt einen neueren Stand (anderswo geändert).
    FListState := AState;
    FState := AState;
  end
  else if (FRead.Key = '') and (FWorker.Pending = 0) and ShowsState then
  begin
    // Erst später eingeschaltet (issues.statusState, issues.syncState): einmal lesen.
    Read(nil);
  end;
  Render;
end;

procedure TAtlasIdeIssueState.TimeChanged(const AField: TAtlasIdeTimeField);
begin
  if FStopped then
  begin
    Exit;
  end;
  FTime := AField;
  Render;
end;

procedure TAtlasIdeIssueState.Render;
var
  mKey, mState, mText, mHint: string;
  mOwner: TAtlasIdeIssueState;
begin
  if FStopped or not Assigned(FHooks.Field) then
  begin
    Exit;
  end;
  mKey := FIssue.Key;
  if mKey = '' then
  begin
    mKey := FTime.Key;
  end;
  mState := '';
  if ShowsState then
  begin
    mState := FState;
  end;
  mText := TAtlasIssueStatus.Text(mKey, mState, FTime.Clock);
  mHint := FTime.Hint;
  if mState <> '' then
  begin
    mHint := Trim(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.StatusStateHint, [mKey, mState]) + sLineBreak +
      FTime.Hint);
  end;
  if (mKey = '') or ((mState = '') and (FTime.Key = '')) then
  begin
    if FShown <> '' then
    begin
      FHooks.Field('', '', nil);
    end;
    FShown := '';
    Exit;
  end;
  // Unverändert: nicht neu setzen (SetIssue und der Takt der Uhr kommen oft).
  if mText + #0 + mHint = FShown then
  begin
    Exit;
  end;
  FShown := mText + #0 + mHint;
  mOwner := Self;
  FHooks.Field(mText, mHint,
    procedure(APoint: TPoint)
    begin
      if not mOwner.FStopped then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tracker,
          procedure
          begin
            mOwner.Clicked(APoint);
          end);
      end;
    end);
end;

/// <summary>Im Hintergrund: Regeln und Werte des Zustandsfeldes von AKey; ohne Regeln (GitHub) nur die Werte.
/// </summary>
procedure ReadState(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AField: string; var ARead: TAtlasIssueStateRead);
var
  mRules: IAtlasTrackerStateRules;
  mWriter: IAtlasTrackerWriter;
begin
  mWriter := TAtlasIdeTrackerSync.WriterOf(AProvider);
  mRules := TAtlasIdeTrackerSync.RulesOf(AProvider);
  if (ATransport = nil) or (mWriter = nil) then
  begin
    Exit;
  end;
  ARead.Succeeded := mWriter.Values(ATarget, ATransport, TAtlasTrackerValueKind.States, AField,
    TAtlasTrackerWorkflow.cWriteTimeoutMs, ARead.States).Succeeded;
  if mRules <> nil then
  begin
    ARead.Succeeded := mRules.StateRules(ATarget, ATransport, ARead.Key, AField, TAtlasTrackerWorkflow.cWriteTimeoutMs,
      ARead.Rules).Succeeded;
  end;
end;

procedure TAtlasIdeIssueState.Read(const ADone: TProc);
var
  mOwner: TAtlasIdeIssueState;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mTransports: TAtlasIdeTrackerTransport;
  mField: string;
  mRead: TAtlasIssueStateRead;
  mDone: TProc;
begin
  mOwner := Self;
  mDone := ADone;
  mTransports := FHooks.Transport;
  mRead := Default(TAtlasIssueStateRead);
  mRead.Key := FIssue.Key;
  // Ohne Lesen (kein Anbieter, Entladen) kommt ADone sofort: Das Menü erscheint trotzdem.
  if not Writable(mProvider, mTarget) or not Assigned(mTransports) then
  begin
    if Assigned(ADone) then
    begin
      ADone();
    end;
    Exit;
  end;
  mField := TAtlasIdeTrackerSync.Options(mTarget).StateField;
  if not FWorker.Run(
    procedure
    begin
      try
        ReadState(mProvider, mTarget, mTransports(mProvider, mTarget), mField, mRead);
      except
        on E: Exception do
        begin
          mRead.Succeeded := False;
          TAtlasGuard.Log(Format('Zustand im Statusfeld: Lesen mit %s abgebrochen', [E.ClassName])); // german-ok: Protokoll
        end;
      end;
    end,
    procedure
    begin
      mOwner.Readed(mRead);
      if Assigned(mDone) then
      begin
        mDone();
      end;
    end) and Assigned(ADone) then
  begin
    ADone();
  end;
end;

procedure TAtlasIdeIssueState.Readed(const ARead: TAtlasIssueStateRead);
var
  mCurrent: string;
begin
  // Inzwischen ein anderes Issue: Die Antwort gilt nicht mehr.
  if FStopped or not SameText(ARead.Key, FIssue.Key) then
  begin
    Exit;
  end;
  FRead := ARead;
  if ARead.Succeeded and (ARead.Rules.Current <> '') then
  begin
    FState := ARead.Rules.Current;
  end;
  mCurrent := FState;
  FEntries := nil;
  if ARead.Succeeded then
  begin
    FEntries := TAtlasIssueStatus.Entries(ARead.Rules, ARead.States, mCurrent);
  end;
  Render;
end;

procedure TAtlasIdeIssueState.Clicked(const APoint: TPoint);
var
  mOwner: TAtlasIdeIssueState;
  mPoint: TPoint;
begin
  if not ShowsState then
  begin
    ShowMenu(APoint);
    Exit;
  end;
  // Übergänge frisch lesen, dann das Menü an derselben Stelle.
  mOwner := Self;
  mPoint := APoint;
  Read(
    procedure
    begin
      if not mOwner.FStopped then
      begin
        mOwner.ShowMenu(mPoint);
      end;
    end);
end;

/// <summary>Eintrag mit Text ACaption an AParent; ohne AClick grau.</summary>
function AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer; const AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  Result.Enabled := Assigned(AClick);
  AParent.Add(Result);
end;

procedure TAtlasIdeIssueState.AddStateItems;
var
  mIndex: Integer;
begin
  if not FRead.Succeeded then
  begin
    AddItem(FMenu.Items, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.StatusMenuFailed), 0, nil);
  end
  else if Length(FEntries) = 0 then
  begin
    AddItem(FMenu.Items, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.StatusMenuNone), 0, nil);
  end;
  for mIndex := 0 to High(FEntries) do
  begin
    AddItem(FMenu.Items, FEntries[mIndex].Caption, mIndex, EntryClick);
  end;
  AddItem(FMenu.Items, cLineCaption, 0, nil);
  AddItem(FMenu.Items, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.StatusMenuComment), 0, CommentClick);
  AddItem(FMenu.Items, TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewEnd), 0, EndClick);
end;

procedure TAtlasIdeIssueState.ShowMenu(const APoint: TPoint);
var
  mStates: Boolean;
begin
  // Ein Menü für die ganze Sitzung: Die Klicks kommen erst nach Popup an.
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
  end;
  FMenu.Items.Clear;
  mStates := ShowsState;
  if mStates then
  begin
    AddStateItems;
  end;
  if Assigned(FTime.Menu) then
  begin
    if mStates then
    begin
      AddItem(FMenu.Items, cLineCaption, 0, nil);
    end;
    FTime.Menu(FMenu.Items);
  end;
  if FMenu.Items.Count > 0 then
  begin
    FMenu.Popup(APoint.X, APoint.Y);
  end;
end;

procedure TAtlasIdeIssueState.EntryClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := (Sender as TMenuItem).Tag;
  if not FStopped and (mIndex >= 0) and (mIndex <= High(FEntries)) then
  begin
    Run(FEntries[mIndex], '');
  end;
end;

/// <summary>Texte der Einträge für die Auswahl im Dialog.</summary>
function Captions(const AEntries: TArray<TAtlasIssueStateEntry>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result[mIndex] := AEntries[mIndex].Caption;
  end;
end;

procedure TAtlasIdeIssueState.CommentClick(Sender: TObject);
var
  mDialog: TAtlasTrackerStateDialog;
  mAssist: IAtlasCommentAssist;
  mEntry: TAtlasIssueStateEntry;
begin
  if FStopped then
  begin
    Exit;
  end;
  mAssist := nil;
  if Assigned(FHooks.Assist) then
  begin
    mAssist := FHooks.Assist(TAtlasTrackerTarget.Create(FIssue.Provider, FIssue.Url, FIssue.Project, ''), FIssue.Key,
      TAtlasCommentDrafts.cFieldState);
  end;
  mDialog := TAtlasTrackerStateDialog.CreateDialog(nil, FIssue.Key, Captions(FEntries), -1);
  try
    mDialog.Editor.Enhanced := mAssist <> nil;
    mDialog.Editor.Bind(mAssist);
    if (mDialog.ShowModal <> mrOk) or FStopped then
    begin
      mDialog.Editor.Unbind;
      Exit;
    end;
    mEntry := Default(TAtlasIssueStateEntry);
    if (mDialog.Entry >= 0) and (mDialog.Entry <= High(FEntries)) then
    begin
      mEntry := FEntries[mDialog.Entry];
    end;
    Run(mEntry, mDialog.Comment);
    mDialog.Editor.Sent;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasIdeIssueState.EndClick(Sender: TObject);
begin
  if not FStopped and Assigned(FHooks.EndIssue) then
  begin
    FHooks.EndIssue();
  end;
end;

procedure TAtlasIdeIssueState.Run(const AEntry: TAtlasIssueStateEntry; const AComment: string);
var
  mOwner: TAtlasIdeIssueState;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mChange: TAtlasTrackerWrite;
  mKey, mAfter: string;
begin
  if not Writable(mProvider, mTarget) then
  begin
    Exit;
  end;
  mChange := TAtlasIssueStatus.Change(AEntry, TAtlasIdeTrackerSync.Options(mTarget).StateField, FRead.Rules.FieldId,
    AComment);
  if not mChange.HasWork then
  begin
    Exit;
  end;
  mOwner := Self;
  mKey := FIssue.Key;
  mAfter := TAtlasIssueStatus.After(AEntry, FRead.States);
  FSync.Apply(mProvider, mTarget, mKey, mChange,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      mOwner.Applied(mKey, mChange, mAfter, AResult);
    end);
end;

procedure TAtlasIdeIssueState.Applied(const AKey: string; const AChange: TAtlasTrackerWrite; const AAfter: string;
  const AResult: TAtlasTrackerWriteResult);
begin
  if FStopped or not Assigned(FHooks.Report) then
  begin
    Exit;
  end;
  if not AResult.Succeeded then
  begin
    FHooks.Report(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.StatusStateFailed,
      [AKey, TAtlasTrackerEndDialog.ErrorText(AKey, AResult)]));
    Exit;
  end;
  FHooks.Report(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.TrackerStartSynced,
    [AKey, TAtlasTrackerEndDialog.SummaryText(AChange, AAfter)]));
  if not SameText(AKey, FIssue.Key) then
  begin
    Exit;
  end;
  if AAfter <> '' then
  begin
    FState := AAfter;
    Render;
  end;
  // Neuer Zustand und die ab hier erlaubten Übergänge (benannte Ereignisse verraten ihr Ziel nicht).
  Read(nil);
end;

function TAtlasIdeIssueState.PaletteRows(const APattern: string): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mRow: TAtlasCommand;
begin
  Result := nil;
  if FStopped or not ShowsState then
  begin
    Exit;
  end;
  for mIndex in TAtlasIssueStatus.Matching(FIssue.Key, FEntries, APattern) do
  begin
    mRow := Default(TAtlasCommand);
    mRow.Id := TAtlasIssueStatus.RowId(mIndex);
    mRow.Caption := TAtlasIssueStatus.RowCaption(FIssue.Key, FEntries[mIndex]);
    mRow.Badge := FState;
    Result := Result + [mRow];
  end;
end;

function TAtlasIdeIssueState.PaletteRun(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TAtlasIssueStatus.IndexOf(AId);
  Result := mIndex >= 0;
  if Result and not FStopped and (mIndex <= High(FEntries)) then
  begin
    Run(FEntries[mIndex], '');
  end;
end;

end.
