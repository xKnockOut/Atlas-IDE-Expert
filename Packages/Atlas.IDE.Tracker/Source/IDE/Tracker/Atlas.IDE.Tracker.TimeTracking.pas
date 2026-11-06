unit Atlas.IDE.Tracker.TimeTracking;

// Zeit je Issue erfassen und buchen (#1267), nur mit issues.timeTracking
// (Vorgabe aus: weder Anzeige noch Datei noch Dialog).
// - Uhr (TAtlasTimeClock) für das aktuelle Issue aus „Meine Issues“
//   (SetIssue): Alle TickMs zählt eine Eingabe in der IDE (GetLastInputInfo,
//   solange die IDE vorn ist) und ein laufender Debugger-Prozess als aktiv;
//   Leerlauf über issues.idleMinutes hält die Uhr an.
// - Jede Minute, beim Wechsel und beim Beenden in die Datei
//   %LOCALAPPDATA%\Atlas\time.json (TAtlasTimeFile, Sperrdatei; mehrere
//   IDE-Instanzen zählen nicht doppelt). Scheitert das Schreiben, bleiben die
//   Spannen im Speicher und gehen beim nächsten Mal mit.
// - Zusatzfeld im Statusfeld „ATL-123 · 1:25“; Klick: Pause/Weiter,
//   Zurücksetzen, Zeit korrigieren, Jetzt buchen, Offene Zeitbuchungen.
// - Buchen: beim Beenden (Ended) und beim Wechsel auf ein anderes Issue
//   (beim nächsten Takt) der Dialog „… buchen?“ (TAtlasTrackerTimeDialog) mit
//   Dauer, Arbeitstyp (YouTrack, nachgeladen) bzw. Kommentar (GitHub) und
//   Beschreibung aus den Commit-Betreffen. „Buchen“ und „Verwerfen“ ziehen die
//   angezeigte Zeit ab, „Später“ behält sie für „Offene Zeitbuchungen …“.
// - {time} für den Beenden-Dialog (#1266) über TimeText.
// Gebucht wird nur nach Klick, im Hintergrund über TAtlasIdeTrackerSync.
// Protokoll anonym: nie Kennung, Adresse oder Beschreibung.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.TimeClock,
  Atlas.Core.Tracker.TimeLog,
  Atlas.UI.Tracker.TimeDialog,
  Atlas.IDE.Tracker.Workflow;

type
  /// <summary>Zusatzfeld im Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasIdeTimeStatus = reference to procedure(const AText, AHint: string; const AOnClick: TProc<TPoint>);
  /// <summary>Anbieter zum Namen; nil ohne.</summary>
  TAtlasIdeTimeProvider = reference to function(const AName: string): IAtlasTrackerProvider;

  TAtlasIdeTrackerTime = class(TInterfacedObject)
  public const
    TickMs = 5000;
    /// <summary>Alle so viele Takte in die Datei (eine Minute).</summary>
    SaveTicks = 12;
    /// <summary>Weniger Zeit bietet Atlas nicht zum Buchen an.</summary>
    MinOfferSeconds = 60;
  private
    FSync: TAtlasIdeTrackerSync;
    FProvider: TAtlasIdeTimeProvider;
    FReport: TProc<string>;
    FStatus: TAtlasIdeTimeStatus;
    FPath: string;
    FClock: TAtlasTimeClock;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FTicks: Integer;
    FLastInput: Cardinal;
    // Summe des aktuellen Issues in der Datei und Spannen, die noch nicht geschrieben sind.
    FSaved: Int64;
    FPending: TArray<TAtlasTimeSpan>;
    FFileFailed: Boolean;
    FOffering: Boolean;
    FOfferNext: TAtlasTimeIssue;
    FStatusShown: Boolean;
    FStopped: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Detect;
    procedure Flush;
    function Change(const AChange: TAtlasTimeLogChange): Boolean;
    function SavedTotal(const AIssue: TAtlasTimeIssue): Int64;
    function CurrentTotal: Int64;
    procedure UpdateStatus;
    procedure HideStatus;
    procedure ShowMenu(const APoint: TPoint);
    /// <summary>Eintrag des Menüs am Feld; Tag ist die Nummer des Eintrags (TTimeMenu).</summary>
    procedure MenuClick(Sender: TObject);
    procedure Offer(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
    procedure ShowBook(const AIssue: TAtlasTimeIssue; const AText: string);
    procedure Settle(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
  public
    /// <summary>ASync: Buchen im Hintergrund; AProvider: Anbieter zum Namen; AReport: Zeile in die Meldungsansicht;
    /// APath: time.json.</summary>
    constructor Create(ASync: TAtlasIdeTrackerSync; const AProvider: TAtlasIdeTimeProvider;
      const AReport: TProc<string>; const APath: string);
    destructor Destroy; override;
    /// <summary>Takt anmelden.</summary>
    procedure Start;
    /// <summary>Letzte Zeit schreiben, Takt und Feld abmelden; danach wirkungslos (beim Entladen).</summary>
    procedure Stop;
    /// <summary>issues.timeTracking an?</summary>
    class function Active: Boolean; static;
    /// <summary>Das aktuelle Issue (TAtlasTimeIssue.None = keins). Ein Wechsel auf ein anderes Issue bietet das
    /// Buchen des bisherigen an.</summary>
    procedure SetIssue(const AIssue: TAtlasTimeIssue);
    /// <summary>AIssue wurde beendet: Zeit schreiben und das Buchen anbieten (Beschreibung aus den Commits von
    /// ABranch gegen ABase im Ordner AFolder).</summary>
    procedure Ended(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
    /// <summary>{time} für AKey: erfasste Zeit des aktuellen Issues, gerundet; '' ohne Zeiterfassung.</summary>
    function TimeText(const AKey: string): string;
    /// <summary>Befehl „Offene Zeitbuchungen …“.</summary>
    procedure ShowOpen;
    property OnStatus: TAtlasIdeTimeStatus read FStatus write FStatus;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.TimeList,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

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

function TAtlasTimeBookSession.Dialog: TAtlasTrackerTimeDialog;
begin
  Result := FDialog;
end;

procedure TAtlasTimeBookSession.SetDialog(ADialog: TAtlasTrackerTimeDialog);
begin
  FDialog := ADialog;
end;

const
  DecisionNames: array[TAtlasTimeDecision] of string = ('später', 'gebucht', 'verworfen');

type
{$SCOPEDENUMS ON}
  /// <summary>Einträge des Menüs am Feld (Tag der Menüeinträge).</summary>
  TTimeMenu = (Pause, Reset, Correct, Book, Open);
{$SCOPEDENUMS OFF}

function DebuggerRunning: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

function TargetOf(const AIssue: TAtlasTimeIssue): TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(AIssue.Provider, AIssue.Url, AIssue.Project, '');
end;

/// <summary>Bucht im Hintergrund: Work Item bzw. (GitHub) Kommentar mit Aufwand und Beschreibung.</summary>
function BookHandler(AOwner: TAtlasIdeTrackerTime; const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string; AMode: TAtlasTimeBookMode): TAtlasTimeBookEvent;
var
  mOwner: TAtlasIdeTrackerTime;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mMode: TAtlasTimeBookMode;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte, keinen Rahmen von ShowBook.
  mOwner := AOwner;
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
      mComment := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeBookComment,
        [TAtlasTrackerWorkflow.DurationText(AItem.Minutes)]);
      if AItem.Text <> '' then
      begin
        mComment := mComment + #10#10 + AItem.Text;
      end;
      mOwner.FSync.Apply(mProvider, mTarget, mKey, TAtlasTrackerWrite.CommentOnly(mComment), ADone);
    end;
end;

/// <summary>Bindet den Dialog an die Sitzung und lädt Arbeitstypen und „Zeiterfassung aus“ nach.</summary>
function PrepareHandler(AOwner: TAtlasIdeTrackerTime; const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string; const ASession: IInterface): TProc<TAtlasTrackerTimeDialog>;
var
  mOwner: TAtlasIdeTrackerTime;
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mSession: IAtlasTimeBookSession;
begin
  mOwner := AOwner;
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

/// <summary>„Zurücksetzen“ nach Rückfrage: Zeit des aktuellen Issues verwerfen.</summary>
procedure ResetTime(AOwner: TAtlasIdeTrackerTime);
var
  mIssue: TAtlasTimeIssue;
  mTotal: Int64;
begin
  if AOwner.FStopped or AOwner.FClock.Issue.IsEmpty then
  begin
    Exit;
  end;
  mIssue := AOwner.FClock.Issue;
  AOwner.Flush;
  mTotal := AOwner.CurrentTotal;
  if MessageDlg(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeResetConfirm, [mIssue.Key,
    TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mTotal, 1))]), mtConfirmation, [mbYes, mbNo],
    0) <> mrYes then
  begin
    Exit;
  end;
  AOwner.FClock.Discard;
  AOwner.Settle(mIssue, mTotal);
end;

/// <summary>„Korrigieren“: Zeit des aktuellen Issues von Hand setzen.</summary>
procedure CorrectTime(AOwner: TAtlasIdeTrackerTime);
var
  mIssue: TAtlasTimeIssue;
  mText: string;
  mMinutes: Integer;
begin
  if AOwner.FStopped or AOwner.FClock.Issue.IsEmpty then
  begin
    Exit;
  end;
  mIssue := AOwner.FClock.Issue;
  AOwner.Flush;
  mText := TAtlasTimeRounding.ClockText(AOwner.CurrentTotal);
  if not InputQuery(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TimeCorrectCaption),
    TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeCorrectPrompt, [mIssue.Key]), mText) then
  begin
    Exit;
  end;
  // 0 ist erlaubt (wie Zurücksetzen ohne Rückfrage); sonst muss die Dauer lesbar sein.
  if (Trim(mText) = '0') or (Trim(mText) = '0:00') then
  begin
    mMinutes := 0;
  end
  else if not TAtlasTimeRounding.ParseDuration(mText, mMinutes) then
  begin
    MessageDlg(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeCorrectInvalid, [mText]), mtWarning, [mbOK], 0);
    Exit;
  end;
  AOwner.FClock.Discard;
  AOwner.Change(
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.SetTotal(mIssue, Int64(mMinutes) * 60, Now);
    end);
  AOwner.UpdateStatus;
end;

{ TAtlasIdeTrackerTime }

constructor TAtlasIdeTrackerTime.Create(ASync: TAtlasIdeTrackerSync; const AProvider: TAtlasIdeTimeProvider;
  const AReport: TProc<string>; const APath: string);
begin
  inherited Create;
  FSync := ASync;
  FProvider := AProvider;
  FReport := AReport;
  FPath := APath;
  FOfferNext := TAtlasTimeIssue.None;
  FClock := TAtlasTimeClock.Create(
    function: TDateTime
    begin
      Result := Now;
    end, TAtlasIdeSettings.Current.IssuesIdleMinutes);
end;

destructor TAtlasIdeTrackerTime.Destroy;
begin
  Stop;
  FClock.Free;
  inherited;
end;

class function TAtlasIdeTrackerTime.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesTimeTracking;
end;

procedure TAtlasIdeTrackerTime.Start;
begin
  if FStopped or (FTimer <> nil) then
  begin
    Exit;
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeTrackerTime.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  FreeAndNil(FTimer);
  // Zeit bis zur letzten Eingabe sichern; ohne Zeiterfassung gibt es nichts.
  if Active then
  begin
    FClock.SetIssue(TAtlasTimeIssue.None);
    Flush;
  end;
  HideStatus;
  FreeAndNil(FMenu);
  FSync := nil;
  FProvider := nil;
  FReport := nil;
  FStatus := nil;
end;

procedure TAtlasIdeTrackerTime.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mOffer: TAtlasTimeIssue;
    begin
      if FStopped then
      begin
        Exit;
      end;
      if not Active then
      begin
        // Abgeschaltet: Was schon gezählt ist, kommt noch in die Datei; danach nichts mehr.
        if not FClock.Issue.IsEmpty then
        begin
          FClock.SetIssue(TAtlasTimeIssue.None);
          Flush;
        end;
        FOfferNext := TAtlasTimeIssue.None;
        HideStatus;
        Exit;
      end;
      FClock.SetIdleMinutes(TAtlasIdeSettings.Current.IssuesIdleMinutes);
      Detect;
      FClock.Tick;
      Inc(FTicks);
      if FTicks mod SaveTicks = 0 then
      begin
        Flush;
      end;
      UpdateStatus;
      // Wechsel auf ein anderes Issue: das bisherige zum Buchen anbieten (nicht mitten im SetIssue des Aufrufers).
      if not FOfferNext.IsEmpty and not FOffering then
      begin
        mOffer := FOfferNext;
        FOfferNext := TAtlasTimeIssue.None;
        Offer(mOffer, '', '', '');
      end;
    end);
end;

procedure TAtlasIdeTrackerTime.Detect;
var
  mInfo: TLastInputInfo;
  mAge: Cardinal;
begin
  if FClock.Issue.IsEmpty then
  begin
    Exit;
  end;
  // Debugger-Lauf zählt als aktiv, auch wenn das Programm vorn ist.
  if DebuggerRunning then
  begin
    FClock.Activity;
  end;
  mInfo.cbSize := SizeOf(mInfo);
  mInfo.dwTime := 0;
  if not GetLastInputInfo(mInfo) or (mInfo.dwTime = FLastInput) then
  begin
    Exit;
  end;
  FLastInput := mInfo.dwTime;
  // Nur Eingaben in der IDE: Sie muss vorn sein.
  if not Application.Active then
  begin
    Exit;
  end;
  mAge := Cardinal(GetTickCount - mInfo.dwTime);
  FClock.Activity(Now - mAge / MSecsPerDay);
end;

function TAtlasIdeTrackerTime.Change(const AChange: TAtlasTimeLogChange): Boolean;
var
  mLog: TAtlasTimeLog;
  mSpans: TArray<TAtlasTimeSpan>;
  mIssue: TAtlasTimeIssue;
begin
  // Noch nicht geschriebene Spannen gehen mit jeder Änderung mit.
  mSpans := FPending + FClock.Take;
  mIssue := FClock.Issue;
  Result := TAtlasTimeFile.Update(FPath,
    procedure(var ALog: TAtlasTimeLog)
    var
      mSpan: TAtlasTimeSpan;
    begin
      for mSpan in mSpans do
      begin
        ALog.Add(mSpan);
      end;
      if Assigned(AChange) then
      begin
        AChange(ALog);
      end;
    end, mLog);
  if not Result then
  begin
    FPending := mSpans;
    if not FFileFailed then
    begin
      FFileFailed := True;
      TAtlasGuard.Log('Zeiterfassung: time.json nicht geschrieben (gesperrt oder unlesbar)');
      if Assigned(FReport) then
      begin
        FReport(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeFileFailed, [FPath]));
      end;
    end;
    Exit;
  end;
  FPending := nil;
  FFileFailed := False;
  FSaved := mLog.Total(mIssue);
end;

procedure TAtlasIdeTrackerTime.Flush;
begin
  Change(nil);
end;

function TAtlasIdeTrackerTime.SavedTotal(const AIssue: TAtlasTimeIssue): Int64;
var
  mLog: TAtlasTimeLog;
begin
  Result := 0;
  if TAtlasTimeFile.Read(FPath, mLog) then
  begin
    Result := mLog.Total(AIssue);
  end;
end;

function TAtlasIdeTrackerTime.CurrentTotal: Int64;
var
  mSpan: TAtlasTimeSpan;
begin
  Result := FSaved + FClock.Unsaved;
  for mSpan in FPending do
  begin
    if mSpan.Issue.Same(FClock.Issue) then
    begin
      Inc(Result, mSpan.Seconds);
    end;
  end;
end;

procedure TAtlasIdeTrackerTime.SetIssue(const AIssue: TAtlasTimeIssue);
var
  mOld: TAtlasTimeIssue;
begin
  if FStopped or not Active or FClock.Issue.Same(AIssue) then
  begin
    Exit;
  end;
  mOld := FClock.Issue;
  // Die offene Spanne gehört dem bisherigen Issue; danach die Summe des neuen.
  FClock.SetIssue(AIssue);
  Flush;
  if not AIssue.IsEmpty then
  begin
    FSaved := SavedTotal(AIssue);
  end;
  if not mOld.IsEmpty and not AIssue.IsEmpty then
  begin
    FOfferNext := mOld;
  end;
  UpdateStatus;
end;

procedure TAtlasIdeTrackerTime.Ended(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
begin
  if FStopped or not Active or AIssue.IsEmpty then
  begin
    Exit;
  end;
  if FClock.Issue.Same(AIssue) then
  begin
    FClock.SetIssue(TAtlasTimeIssue.None);
  end;
  Flush;
  UpdateStatus;
  Offer(AIssue, AFolder, ABranch, ABase);
end;

function TAtlasIdeTrackerTime.TimeText(const AKey: string): string;
begin
  Result := '';
  if FStopped or not Active or FClock.Issue.IsEmpty or not SameText(FClock.Issue.Key, AKey) then
  begin
    Exit;
  end;
  Result := TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(CurrentTotal,
    TAtlasIdeSettings.Current.IssuesTimeRounding));
end;

procedure TAtlasIdeTrackerTime.HideStatus;
begin
  if FStatusShown and Assigned(FStatus) then
  begin
    FStatus('', '', nil);
  end;
  FStatusShown := False;
end;

procedure TAtlasIdeTrackerTime.UpdateStatus;
var
  mTotal: Int64;
  mText: string;
  mOwner: TAtlasIdeTrackerTime;
begin
  if FStopped or not Active or FClock.Issue.IsEmpty or not Assigned(FStatus) then
  begin
    HideStatus;
    Exit;
  end;
  mTotal := CurrentTotal;
  if FClock.Paused then
  begin
    mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeStatusPaused, [FClock.Issue.Key,
      TAtlasTimeRounding.ClockText(mTotal)]);
  end
  else
  begin
    mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeStatusText,
      [FClock.Issue.Key, TAtlasTimeRounding.ClockText(mTotal)]);
  end;
  mOwner := Self;
  FStatus(mText, TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeStatusHint, [FClock.Issue.Key,
    TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mTotal, 1))]),
    procedure(APoint: TPoint)
    begin
      if not mOwner.FStopped then
      begin
        mOwner.ShowMenu(APoint);
      end;
    end);
  FStatusShown := True;
end;

procedure TAtlasIdeTrackerTime.ShowMenu(const APoint: TPoint);
var
  mItem: TMenuItem;

  procedure Add(AText: TAtlasTrackerTextId; AEntry: TTimeMenu);
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasTrackerStrings.Text(AText);
    mItem.Tag := Ord(AEntry);
    mItem.OnClick := MenuClick;
    FMenu.Items.Add(mItem);
  end;

begin
  // Ein Menü für die ganze Sitzung: Die Klicks kommen erst nach Popup an.
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
  end;
  FMenu.Items.Clear;
  if FClock.Paused then
  begin
    Add(TAtlasTrackerTextId.TimeMenuResume, TTimeMenu.Pause);
  end
  else
  begin
    Add(TAtlasTrackerTextId.TimeMenuPause, TTimeMenu.Pause);
  end;
  Add(TAtlasTrackerTextId.TimeMenuReset, TTimeMenu.Reset);
  Add(TAtlasTrackerTextId.TimeMenuCorrect, TTimeMenu.Correct);
  Add(TAtlasTrackerTextId.TimeMenuBook, TTimeMenu.Book);
  Add(TAtlasTrackerTextId.TimeMenuOpen, TTimeMenu.Open);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeTrackerTime.MenuClick(Sender: TObject);
begin
  if FStopped then
  begin
    Exit;
  end;
  case TTimeMenu((Sender as TMenuItem).Tag) of
    TTimeMenu.Pause:
      begin
        if FClock.Paused then
        begin
          FClock.Resume;
        end
        else
        begin
          FClock.Pause;
        end;
        UpdateStatus;
      end;
    TTimeMenu.Reset:
      ResetTime(Self);
    TTimeMenu.Correct:
      CorrectTime(Self);
    TTimeMenu.Book:
      if not FClock.Issue.IsEmpty then
      begin
        Offer(FClock.Issue, '', '', '');
      end;
    TTimeMenu.Open:
      ShowOpen;
  end;
end;

procedure TAtlasIdeTrackerTime.Settle(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
begin
  // Gebucht oder verworfen: genau die gezeigte Zeit abziehen; was währenddessen dazukam, bleibt.
  Change(
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Subtract(AIssue, ASeconds);
    end);
  UpdateStatus;
end;

procedure TAtlasIdeTrackerTime.Offer(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeTrackerTime;
  mIssue: TAtlasTimeIssue;
  mFolder, mBranch, mBase, mCommits: string;
begin
  if FStopped or FOffering or not Active or AIssue.IsEmpty then
  begin
    Exit;
  end;
  if (AFolder = '') or (ABranch = '') then
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
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeTrackerSync.VcsTimeoutMs);
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

/// <summary>Work Item, wenn der Anbieter Zeit buchen kann, sonst Kommentar (GitHub).</summary>
function ModeOf(const AProvider: IAtlasTrackerProvider): TAtlasTimeBookMode;
begin
  Result := TAtlasTimeBookMode.Comment;
  if TAtlasIdeTrackerSync.TimeWriterOf(AProvider) <> nil then
  begin
    Result := TAtlasTimeBookMode.WorkItem;
  end;
end;

procedure TAtlasIdeTrackerTime.ShowBook(const AIssue: TAtlasTimeIssue; const AText: string);
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
  Flush;
  mTotal := SavedTotal(AIssue);
  if mTotal < MinOfferSeconds then
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
      BookHandler(Self, mProvider, mTarget, AIssue.Key, mMode),
      PrepareHandler(Self, mProvider, mTarget, AIssue.Key, mSession), mItem);
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
  TAtlasGuard.Log(Format('Zeiterfassung: Buchungsdialog %s, %s', [AIssue.Provider, DecisionNames[mDecision]]));
  case mDecision of
    TAtlasTimeDecision.Booked:
      begin
        Settle(AIssue, mTotal);
        if Assigned(FReport) then
        begin
          FReport(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeBookDone,
            [TAtlasTrackerWorkflow.DurationText(mItem.Minutes), AIssue.Key]));
        end;
      end;
    TAtlasTimeDecision.Discarded:
      Settle(AIssue, mTotal);
  else
    // Später: Die Zeit bleibt für „Offene Zeitbuchungen …“.
  end;
end;

procedure TAtlasIdeTrackerTime.ShowOpen;
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
  Flush;
  if not TAtlasTimeFile.Read(FPath, mLog) then
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
      if MessageDlg(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TimeResetConfirm, [mItems[mIndex].Issue.Key,
        TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mItems[mIndex].Seconds, 1))]),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        Settle(mItems[mIndex].Issue, mItems[mIndex].Seconds);
      end;
  else
    // Schließen.
  end;
end;

end.
