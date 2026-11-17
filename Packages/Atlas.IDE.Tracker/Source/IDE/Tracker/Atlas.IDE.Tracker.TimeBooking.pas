unit Atlas.IDE.Tracker.TimeBooking;

// Erfasste Zeit buchen (#1267), nur mit issues.timeTracking. Die Uhr und das
// Statusfeld stehen in Atlas.IDE.Tracker.TimeTracking, die Ablage in
// Atlas.Core.Tracker.TimeStore.
// - Der Dialog „… buchen?“ (TAtlasTrackerTimeDialog) mit Dauer, Arbeitstyp
//   (YouTrack, nachgeladen) bzw. Kommentar (GitHub) und Beschreibung aus den
//   Commit-Betreffen (Versionsverwaltung im Hintergrund). „Buchen“ und
//   „Verwerfen“ ziehen die angezeigte Zeit ab, „Später“ behält sie.
// - „Offene Zeitbuchungen …“: Liste aus time.json, buchen oder verwerfen.
// Gebucht wird nur nach Klick, im Hintergrund über TAtlasIdeTrackerSync.
// Protokoll anonym: Anbieter und Entscheidung, nie Kennung, Adresse oder
// Beschreibung.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.TimeStore,
  Atlas.UI.Tracker.TimeDialog,
  Atlas.IDE.Tracker.Workflow;

type
  /// <summary>Anbieter zum Namen; nil ohne.</summary>
  TAtlasIdeTimeProvider = reference to function(const AName: string): IAtlasTrackerProvider;

  TAtlasIdeTimeBooking = class(TInterfacedObject)
  private
    FSync: TAtlasIdeTrackerSync;
    FProvider: TAtlasIdeTimeProvider;
    FReport: TProc<string>;
    FStore: TAtlasTimeStore;
    FSettled: TProc;
    FOffering: Boolean;
    FStopped: Boolean;
    /// <summary>Bucht im Hintergrund: Work Item bzw. (GitHub) Kommentar mit Aufwand und Beschreibung.</summary>
    function BookHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string; AMode: TAtlasTimeBookMode): TAtlasTimeBookEvent;
    /// <summary>Bindet den Dialog an die Sitzung und lädt Arbeitstypen und „Zeiterfassung aus“ nach.</summary>
    function PrepareHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const AKey: string; const ASession: IInterface): TProc<TAtlasTrackerTimeDialog>;
    procedure ShowBook(const AIssue: TAtlasTimeIssue; const AText: string);
    /// <summary>Gebucht oder verworfen: genau die gezeigte Zeit abziehen; was währenddessen dazukam, bleibt.
    /// </summary>
    procedure Settle(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
  public
    /// <summary>ASync: Buchen im Hintergrund; AProvider: Anbieter zum Namen; AReport: Zeile in die Meldungsansicht;
    /// AStore: Ablage (gehört dem Aufrufer); ASettled: nach jedem Abziehen (Statusfeld nachführen).</summary>
    constructor Create(ASync: TAtlasIdeTrackerSync; const AProvider: TAtlasIdeTimeProvider;
      const AReport: TProc<string>; AStore: TAtlasTimeStore; const ASettled: TProc);
    /// <summary>issues.timeTracking an?</summary>
    class function Active: Boolean; static;
    /// <summary>Buchen von AIssue anbieten; mit AFolder und ABranch die Commits gegen ABase als Beschreibung.
    /// </summary>
    procedure Offer(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
    /// <summary>Befehl „Offene Zeitbuchungen …“.</summary>
    procedure ShowOpen;
    /// <summary>Rückrufe lösen; danach wirkungslos (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Ein Buchungsdialog ist offen.</summary>
    property Offering: Boolean read FOffering;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.TimePlan,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Tracker.Time.Strings,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.TimeList,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

type
  /// <summary>Der offene Buchungsdialog für nachgeladene Werte; nil, sobald er geschlossen ist.</summary>
  IAtlasTimeBookSession = interface
    ['{2F6E4A81-9C3B-4D57-B0A2-6E1D8F4C3B97}']
    function Dialog: TAtlasTrackerTimeDialog;
    procedure SetDialog(ADialog: TAtlasTrackerTimeDialog);
  end;

  TAtlasTimeBookSession = class(TInterfacedObject, IAtlasTimeBookSession)
  private
    FDialog: TAtlasTrackerTimeDialog;
  public
    function Dialog: TAtlasTrackerTimeDialog;
    procedure SetDialog(ADialog: TAtlasTrackerTimeDialog);
  end;

{ TAtlasTimeBookSession }

function TAtlasTimeBookSession.Dialog: TAtlasTrackerTimeDialog;
begin
  Result := FDialog;
end;

procedure TAtlasTimeBookSession.SetDialog(ADialog: TAtlasTrackerTimeDialog);
begin
  FDialog := ADialog;
end;

const
  cDecisionNames: array[TAtlasTimeDecision] of string = ('später', 'gebucht', 'verworfen');

function TargetOf(const AIssue: TAtlasTimeIssue): TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(AIssue.Provider, AIssue.Url, AIssue.Project, '');
end;

/// <summary>Work Item, wenn der Anbieter Zeit buchen kann, sonst Kommentar (GitHub).</summary>
function ModeOf(const AProvider: IAtlasTrackerProvider): TAtlasTimeBookMode;
begin
  Result := TAtlasTimeBookMode.Comment;
  if TAtlasIdeTrackerSync.TimeWriterOf(AProvider) <> nil then
  begin
    Result := TAtlasTimeBookMode.WorkItem;
  end;
end;

{ TAtlasIdeTimeBooking }

constructor TAtlasIdeTimeBooking.Create(ASync: TAtlasIdeTrackerSync; const AProvider: TAtlasIdeTimeProvider;
  const AReport: TProc<string>; AStore: TAtlasTimeStore; const ASettled: TProc);
begin
  inherited Create;
  FSync := ASync;
  FProvider := AProvider;
  FReport := AReport;
  FStore := AStore;
  FSettled := ASettled;
end;

class function TAtlasIdeTimeBooking.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesTimeTracking;
end;

function TAtlasIdeTimeBooking.BookHandler(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
  const AKey: string; AMode: TAtlasTimeBookMode): TAtlasTimeBookEvent;
var
  mOwner: TAtlasIdeTimeBooking;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mMode: TAtlasTimeBookMode;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte, keinen Rahmen von ShowBook.
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mMode := AMode;
  Result :=
    procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
    var
      mComment: string;
    begin
      if mOwner.FStopped or (mOwner.FSync = nil) then
      begin
        ADone(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Cancelled, 0, ''));
        Exit;
      end;
      if mMode = TAtlasTimeBookMode.WorkItem then
      begin
        mOwner.FSync.BookTime(mProvider, mTarget, mKey, AItem, ADone);
        Exit;
      end;
      // GitHub: Aufwand als Kommentar, die Beschreibung darunter.
      mComment := TAtlasTimePlan.BookComment(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeBookComment,
        [TAtlasTrackerWorkflow.DurationText(AItem.Minutes)]), AItem.Text);
      mOwner.FSync.Apply(mProvider, mTarget, mKey, TAtlasTrackerWrite.CommentOnly(mComment), ADone);
    end;
end;

function TAtlasIdeTimeBooking.PrepareHandler(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string; const ASession: IInterface): TProc<TAtlasTrackerTimeDialog>;
var
  mOwner: TAtlasIdeTimeBooking;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mSession: IAtlasTimeBookSession;
begin
  mOwner := Self;
  mProvider := AProvider;
  mTarget := ATarget;
  mKey := AKey;
  mSession := ASession as IAtlasTimeBookSession;
  Result :=
    procedure(ADialog: TAtlasTrackerTimeDialog)
    var
      mWriter: IAtlasTrackerTimeWriter;
    begin
      mSession.SetDialog(ADialog);
      mWriter := TAtlasIdeTrackerSync.TimeWriterOf(mProvider);
      if (mWriter = nil) or (mOwner.FSync = nil) then
      begin
        Exit;
      end;
      ADialog.IsTrackingOff :=
        function(const AResult: TAtlasTrackerWriteResult): Boolean
        begin
          Result := mWriter.IsTrackingOff(AResult);
        end;
      // Ohne Leserecht bleibt die Klappliste frei beschreibbar und „Buchen“ frei.
      mOwner.FSync.TimeSettings(mProvider, mTarget, mKey,
        procedure(ASettings: TAtlasTrackerTimeSettings; AResult: TAtlasTrackerWriteResult)
        begin
          if mSession.Dialog = nil then
          begin
            Exit;
          end;
          mSession.Dialog.SetWorkTypes(ASettings.WorkTypes);
          if AResult.Succeeded and not ASettings.Enabled then
          begin
            mSession.Dialog.SetTrackingOff;
          end;
        end);
    end;
end;

procedure TAtlasIdeTimeBooking.Settle(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
begin
  FStore.Subtract(AIssue, ASeconds);
  if Assigned(FSettled) then
  begin
    FSettled();
  end;
end;

procedure TAtlasIdeTimeBooking.Offer(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeTimeBooking;
  mIssue: TAtlasTimeIssue;
  mFolder, mBranch, mBase, mCommits: string;
begin
  if FStopped or FOffering or not Active or AIssue.IsEmpty then
  begin
    Exit;
  end;
  if not TAtlasTimePlan.ReadsCommits(AFolder, ABranch) then
  begin
    ShowBook(AIssue, '');
    Exit;
  end;
  // Beschreibung aus den Commit-Betreffen: Versionsverwaltung im Hintergrund, Dialog danach.
  mKeep := Self;
  mOwner := Self;
  mIssue := AIssue;
  mFolder := AFolder;
  mBranch := ABranch;
  mBase := ABase;
  mCommits := '';
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mWork: IAtlasVcsLocalWork;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeTrackerSync.cVcsTimeoutMs);
      if Supports(mVcs, IAtlasVcsLocalWork, mWork) then
      begin
        mCommits := TAtlasTrackerWorkflow.CommitsFor(mWork, mBranch, mBase, mIssue.Key);
      end;
    end,
    procedure
    begin
      if (mKeep <> nil) and not mOwner.FStopped then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tracker,
          procedure
          begin
            mOwner.ShowBook(mIssue, TAtlasTrackerWorkflow.CommitSubjects(mCommits));
          end);
      end;
    end) then
  begin
    ShowBook(AIssue, '');
  end;
end;

procedure TAtlasIdeTimeBooking.ShowBook(const AIssue: TAtlasTimeIssue; const AText: string);
var
  mTotal: Int64;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mMode: TAtlasTimeBookMode;
  mSession: IAtlasTimeBookSession;
  mItem: TAtlasTrackerWorkItem;
  mDecision: TAtlasTimeDecision;
begin
  if FStopped or FOffering or not Active then
  begin
    Exit;
  end;
  FStore.Flush;
  mTotal := FStore.SavedTotal(AIssue);
  if not TAtlasTimePlan.Offers(mTotal) then
  begin
    Exit;
  end;
  mProvider := nil;
  if Assigned(FProvider) then
  begin
    mProvider := FProvider(AIssue.Provider);
  end;
  mTarget := TargetOf(AIssue);
  mMode := ModeOf(mProvider);
  FOffering := True;
  mSession := TAtlasTimeBookSession.Create;
  try
    mDecision := TAtlasTrackerTimeDialog.Execute(TAtlasTimeRequest.Create(AIssue.Key, mTotal,
      TAtlasIdeSettings.Current.IssuesTimeRounding, Date, AText, mMode),
      BookHandler(mProvider, mTarget, AIssue.Key, mMode),
      PrepareHandler(mProvider, mTarget, AIssue.Key, mSession), mItem);
  finally
    // Nachgeladene Werte kommen danach nicht mehr an den freigegebenen Dialog.
    mSession.SetDialog(nil);
    FOffering := False;
  end;
  if FStopped then
  begin
    Exit;
  end;
  // Anonym: Anbieter und Entscheidung, nie Kennung oder Beschreibung.
  TAtlasGuard.Log(Format('Zeiterfassung: Buchungsdialog %s, %s', [AIssue.Provider, cDecisionNames[mDecision]]));
  case mDecision of
    TAtlasTimeDecision.Booked:
      begin
        Settle(AIssue, mTotal);
        if Assigned(FReport) then
        begin
          FReport(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeBookDone,
            [TAtlasTrackerWorkflow.DurationText(mItem.Minutes), AIssue.Key]));
        end;
      end;
    TAtlasTimeDecision.Discarded:
      Settle(AIssue, mTotal);
  else
    // Später: Die Zeit bleibt für „Offene Zeitbuchungen …“.
  end;
end;

procedure TAtlasIdeTimeBooking.ShowOpen;
var
  mLog: TAtlasTimeLog;
  mItems: TArray<TAtlasTimeOpen>;
  mIndex: Integer;
  mAction: TAtlasTimeListAction;
begin
  if FStopped or FOffering then
  begin
    Exit;
  end;
  FStore.Flush;
  if not FStore.Read(mLog) then
  begin
    mLog := TAtlasTimeLog.Empty;
  end;
  mItems := mLog.Open;
  mAction := TAtlasTrackerTimeListDialog.Execute(mItems, mIndex);
  if (mIndex < 0) or (mIndex > High(mItems)) then
  begin
    Exit;
  end;
  case mAction of
    TAtlasTimeListAction.Book:
      Offer(mItems[mIndex].Issue, '', '', '');
    TAtlasTimeListAction.Discard:
      if MessageDlg(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeResetConfirm, [mItems[mIndex].Issue.Key,
        TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mItems[mIndex].Seconds, 1))]),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        Settle(mItems[mIndex].Issue, mItems[mIndex].Seconds);
      end;
  else
    // Schließen.
  end;
end;

procedure TAtlasIdeTimeBooking.Stop;
begin
  FStopped := True;
  FSync := nil;
  FProvider := nil;
  FReport := nil;
  FSettled := nil;
end;

end.
