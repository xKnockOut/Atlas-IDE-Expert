unit Atlas.IDE.Tracker.TimeTracking;

// Zeit je Issue erfassen (#1267), nur mit issues.timeTracking (Vorgabe aus:
// weder Anzeige noch Datei noch Dialog).
// - Uhr (TAtlasTimeClock) für das aktuelle Issue aus „Meine Issues“
//   (SetIssue): Alle TickMs zählt eine Eingabe in der IDE (GetLastInputInfo,
//   solange die IDE vorn ist) und ein laufender Debugger-Prozess als aktiv;
//   Leerlauf über issues.idleMinutes hält die Uhr an.
// - Jede Minute, beim Wechsel und beim Beenden in die Datei
//   %LOCALAPPDATA%\Atlas\time.json (TAtlasTimeStore, Sperrdatei; mehrere
//   IDE-Instanzen zählen nicht doppelt). Scheitert das Schreiben, bleiben die
//   Spannen im Speicher und gehen beim nächsten Mal mit.
// - Zeit für das Statusfeld (OnStatus): Kennung, „1:25“ bzw. „1:25 (Pause)“,
//   Hinweis und die Einträge des Menüs (Pause/Weiter, Zurücksetzen, Zeit
//   korrigieren, Jetzt buchen, Offene Zeitbuchungen); das Feld zeigt
//   Atlas.IDE.Tracker.IssueState zusammen mit dem Zustand (#2124).
// - Buchen anbieten: beim Beenden (Ended) und beim Wechsel auf ein anderes
//   Issue (beim nächsten Takt); den Dialog zeigt Atlas.IDE.Tracker.TimeBooking.
// - {time} für den Beenden-Dialog (#1266) über TimeText, die Zeit im Dialog
//   selbst (#2123) über Seconds und Booked.
// Protokoll anonym: nie Kennung, Adresse oder Beschreibung.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Tracker.TimeClock,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Core.Tracker.TimeStore,
  Atlas.IDE.Tracker.TimeBooking,
  Atlas.IDE.Tracker.Workflow;

type
  /// <summary>Zusatzfeld im Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasIdeTimeStatus = reference to procedure(const AText, AHint: string; const AOnClick: TProc<TPoint>);

  /// <summary>Erfasste Zeit des aktuellen Issues fürs Statusfeld (#2124); Key '' = keine Anzeige.</summary>
  TAtlasIdeTimeField = record
    Key: string;
    /// <summary>„1:25“ bzw. „1:25 (Pause)“.</summary>
    Clock: string;
    Hint: string;
    /// <summary>Hängt die Einträge der Uhr an den Menüeintrag an (Pause, Zurücksetzen, Korrigieren, Buchen,
    /// Offene Zeitbuchungen).</summary>
    Menu: TProc<TMenuItem>;
    class function None: TAtlasIdeTimeField; static;
  end;

  /// <summary>Zeit fürs Statusfeld geändert.</summary>
  TAtlasIdeTimeChanged = reference to procedure(const AField: TAtlasIdeTimeField);
  /// <summary>Anbieter zum Namen; nil ohne.</summary>
  TAtlasIdeTimeProvider = Atlas.IDE.Tracker.TimeBooking.TAtlasIdeTimeProvider;

  TAtlasIdeTrackerTime = class(TInterfacedObject)
  public const
    cTickMs = 5000;
  private
    FReport: TProc<string>;
    FStatus: TAtlasIdeTimeChanged;
    FClock: TAtlasTimeClock;
    FStore: TAtlasTimeStore;
    FBooking: TAtlasIdeTimeBooking;
    FBookingRef: IInterface;
    FTimer: TTimer;
    FTicks: Integer;
    FLastInput: Cardinal;
    FOfferNext: TAtlasTimeIssue;
    // Kennung, deren Zeit der Beenden-Dialog gebucht hat (#2123): Ended bietet dann nichts mehr an.
    FBookedOnEnd: string;
    FStatusShown: Boolean;
    FStopped: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Detect;
    procedure UpdateStatus;
    procedure HideStatus;
    /// <summary>Einträge der Uhr an AParent anhängen (das Menü gehört dem Statusfeld).</summary>
    procedure FillMenu(AParent: TMenuItem);
    /// <summary>Eintrag des Menüs am Feld; Tag ist die Nummer des Eintrags (TTimeMenu).</summary>
    procedure MenuClick(Sender: TObject);
    /// <summary>„Zurücksetzen“ nach Rückfrage: Zeit des aktuellen Issues verwerfen.</summary>
    procedure ResetTime;
    /// <summary>„Korrigieren“: Zeit des aktuellen Issues von Hand setzen.</summary>
    procedure CorrectTime;
    /// <summary>time.json ließ sich nicht schreiben (erstes Mal nach einem Erfolg).</summary>
    procedure FileFailed;
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
    /// <summary>AIssue wurde beendet: Zeit schreiben und mit AOffer das Buchen anbieten (Beschreibung aus den
    /// Commits von ABranch gegen ABase im Ordner AFolder); ohne AOffer (#2135, „nicht geplant“, „Duplikat“) nur die
    /// Uhr anhalten.</summary>
    procedure Ended(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string; AOffer: Boolean);
    /// <summary>Befehl „Offene Zeitbuchungen …“.</summary>
    procedure ShowOpen;
    /// <summary>Erfasste Zeit des aktuellen Issues AKey in Sekunden (#2123); 0 ohne Zeiterfassung oder wenn AKey
    /// nicht das aktuelle ist.</summary>
    function Seconds(const AKey: string): Int64;
    /// <summary>{time} für AKey (#1266): erfasste Zeit des aktuellen Issues, gerundet; '' ohne Zeiterfassung.
    /// </summary>
    function TimeText(const AKey: string): string;
    /// <summary>Der Beenden-Dialog hat ASeconds der Zeit von AKey gebucht (#2123): genau diese Zeit abziehen; das
    /// folgende Ended bietet nichts mehr an.</summary>
    procedure Booked(const AKey: string; ASeconds: Int64);
    property OnStatus: TAtlasIdeTimeChanged read FStatus write FStatus;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.TimePlan,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.Time.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Diagnostics.UserIdle;

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

{ TAtlasIdeTrackerTime }

constructor TAtlasIdeTrackerTime.Create(ASync: TAtlasIdeTrackerSync; const AProvider: TAtlasIdeTimeProvider;
  const AReport: TProc<string>; const APath: string);
var
  mOwner: TAtlasIdeTrackerTime;
begin
  inherited Create;
  FReport := AReport;
  FOfferNext := TAtlasTimeIssue.None;
  FClock := TAtlasTimeClock.Create(
    function: TDateTime
    begin
      Result := Now;
    end, TAtlasIdeSettings.Current.IssuesIdleMinutes);
  // Eigene Variable: Die anonymen Methoden halten nur das Objekt; Stop löst sie.
  mOwner := Self;
  FStore := TAtlasTimeStore.Create(APath, FClock,
    procedure
    begin
      mOwner.FileFailed;
    end);
  FBooking := TAtlasIdeTimeBooking.Create(ASync, AProvider, AReport, FStore,
    procedure
    begin
      mOwner.UpdateStatus;
    end);
  FBookingRef := FBooking;
end;

destructor TAtlasIdeTrackerTime.Destroy;
begin
  Stop;
  FBooking := nil;
  FBookingRef := nil;
  FStore.Free;
  FClock.Free;
  inherited;
end;

procedure TAtlasIdeTrackerTime.FileFailed;
begin
  TAtlasGuard.Log('Zeiterfassung: time.json nicht geschrieben (gesperrt oder unlesbar)');
  if Assigned(FReport) then
  begin
    FReport(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeFileFailed, [FStore.Path]));
  end;
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
          FStore.Flush;
        end;
        FOfferNext := TAtlasTimeIssue.None;
        HideStatus;
        Exit;
      end;
      FClock.SetIdleMinutes(TAtlasIdeSettings.Current.IssuesIdleMinutes);
      Detect;
      FClock.Tick;
      Inc(FTicks);
      if TAtlasTimePlan.SavesOnTick(FTicks) then
      begin
        FStore.Flush;
      end;
      UpdateStatus;
      // Wechsel auf ein anderes Issue: das bisherige zum Buchen anbieten (nicht mitten im SetIssue des Aufrufers).
      if not FOfferNext.IsEmpty and not FBooking.Offering then
      begin
        mOffer := FOfferNext;
        FOfferNext := TAtlasTimeIssue.None;
        FBooking.Offer(mOffer, '', '', '');
      end;
    end);
end;

procedure TAtlasIdeTrackerTime.Detect;
var
  mInput: Cardinal;
  mAge: Cardinal;
  mKnown: Boolean;
  mStep: TAtlasTimeInput;
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
  // Nur Eingaben in der IDE: Sie muss vorn sein.
  mKnown := TAtlasUserIdle.LastInput(mInput);
  mStep := TAtlasTimePlan.InputOf(mKnown, mInput, FLastInput, Application.Active);
  if mStep = TAtlasTimeInput.Same then
  begin
    Exit;
  end;
  FLastInput := mInput;
  if mStep = TAtlasTimeInput.Ide then
  begin
    mAge := TAtlasUserIdle.Since(mInput);
    FClock.Activity(TAtlasTimePlan.InputAt(Now, mAge));
  end;
end;

procedure TAtlasIdeTrackerTime.UpdateStatus;
var
  mTotal: Int64;
  mField: TAtlasIdeTimeField;
  mOwner: TAtlasIdeTrackerTime;
begin
  if FStopped or not Active or FClock.Issue.IsEmpty or not Assigned(FStatus) then
  begin
    HideStatus;
    Exit;
  end;
  mTotal := FStore.CurrentTotal;
  mField := TAtlasIdeTimeField.None;
  mField.Key := FClock.Issue.Key;
  mField.Clock := TAtlasTimeRounding.ClockText(mTotal);
  if FClock.Paused then
  begin
    mField.Clock := TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeStatusPaused, [mField.Clock]);
  end;
  mField.Hint := TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeStatusHint, [FClock.Issue.Key,
    TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mTotal, 1))]);
  mOwner := Self;
  mField.Menu :=
    procedure(AParent: TMenuItem)
    begin
      if not mOwner.FStopped then
      begin
        mOwner.FillMenu(AParent);
      end;
    end;
  FStatus(mField);
  FStatusShown := True;
end;

procedure TAtlasIdeTrackerTime.HideStatus;
begin
  if FStatusShown and Assigned(FStatus) then
  begin
    FStatus(TAtlasIdeTimeField.None);
  end;
  FStatusShown := False;
end;

procedure TAtlasIdeTrackerTime.FillMenu(AParent: TMenuItem);
var
  mItem: TMenuItem;

  procedure Add(AText: TAtlasTimeTextId; AEntry: TTimeMenu);
  begin
    mItem := TMenuItem.Create(AParent);
    mItem.Caption := TAtlasTimeStrings.Text(AText);
    mItem.Tag := Ord(AEntry);
    mItem.OnClick := MenuClick;
    AParent.Add(mItem);
  end;

begin
  if FClock.Paused then
  begin
    Add(TAtlasTimeTextId.TimeMenuResume, TTimeMenu.Pause);
  end
  else
  begin
    Add(TAtlasTimeTextId.TimeMenuPause, TTimeMenu.Pause);
  end;
  Add(TAtlasTimeTextId.TimeMenuReset, TTimeMenu.Reset);
  Add(TAtlasTimeTextId.TimeMenuCorrect, TTimeMenu.Correct);
  Add(TAtlasTimeTextId.TimeMenuBook, TTimeMenu.Book);
  Add(TAtlasTimeTextId.TimeMenuOpen, TTimeMenu.Open);
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
      ResetTime;
    TTimeMenu.Correct:
      CorrectTime;
    TTimeMenu.Book:
      if not FClock.Issue.IsEmpty then
      begin
        FBooking.Offer(FClock.Issue, '', '', '');
      end;
    TTimeMenu.Open:
      ShowOpen;
  end;
end;

procedure TAtlasIdeTrackerTime.ResetTime;
var
  mIssue: TAtlasTimeIssue;
  mTotal: Int64;
begin
  if FStopped or FClock.Issue.IsEmpty then
  begin
    Exit;
  end;
  mIssue := FClock.Issue;
  FStore.Flush;
  mTotal := FStore.CurrentTotal;
  if MessageDlg(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeResetConfirm, [mIssue.Key,
    TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(mTotal, 1))]), mtConfirmation, [mbYes, mbNo],
    0) <> mrYes then
  begin
    Exit;
  end;
  FClock.Discard;
  // Genau die gezeigte Zeit abziehen; was währenddessen dazukam, bleibt.
  FStore.Subtract(mIssue, mTotal);
  UpdateStatus;
end;

procedure TAtlasIdeTrackerTime.CorrectTime;
var
  mIssue: TAtlasTimeIssue;
  mText: string;
  mMinutes: Integer;
begin
  if FStopped or FClock.Issue.IsEmpty then
  begin
    Exit;
  end;
  mIssue := FClock.Issue;
  FStore.Flush;
  mText := TAtlasTimeRounding.ClockText(FStore.CurrentTotal);
  if not InputQuery(TAtlasTimeStrings.Text(TAtlasTimeTextId.TimeCorrectCaption),
    TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeCorrectPrompt, [mIssue.Key]), mText) then
  begin
    Exit;
  end;
  // 0 ist erlaubt (wie Zurücksetzen ohne Rückfrage); sonst muss die Dauer lesbar sein.
  if not TAtlasTimePlan.CorrectedMinutes(mText, mMinutes) then
  begin
    MessageDlg(TAtlasTimeStrings.Fmt(TAtlasTimeTextId.TimeCorrectInvalid, [mText]), mtWarning, [mbOK], 0);
    Exit;
  end;
  FClock.Discard;
  FStore.SetTotal(mIssue, Int64(mMinutes) * 60, Now);
  UpdateStatus;
end;

{ TAtlasIdeTimeField }

class function TAtlasIdeTimeField.None: TAtlasIdeTimeField;
begin
  Result := Default(TAtlasIdeTimeField);
end;

procedure TAtlasIdeTrackerTime.Start;
begin
  if FStopped or (FTimer <> nil) then
  begin
    Exit;
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
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
    FStore.Flush;
  end;
  HideStatus;
  FBooking.Stop;
  FStore.Detach;
  FReport := nil;
  FStatus := nil;
end;

class function TAtlasIdeTrackerTime.Active: Boolean;
begin
  Result := TAtlasIdeTimeBooking.Active;
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
  FStore.Flush;
  FStore.Select(AIssue);
  if TAtlasTimePlan.OffersOnSwitch(mOld, AIssue) then
  begin
    FOfferNext := mOld;
  end;
  UpdateStatus;
end;

procedure TAtlasIdeTrackerTime.Ended(const AIssue: TAtlasTimeIssue; const AFolder, ABranch, ABase: string;
  AOffer: Boolean);
begin
  if FStopped or not Active or AIssue.IsEmpty then
  begin
    Exit;
  end;
  if FClock.Issue.Same(AIssue) then
  begin
    FClock.SetIssue(TAtlasTimeIssue.None);
  end;
  FStore.Flush;
  UpdateStatus;
  // Schon im Beenden-Dialog gebucht: Was seitdem dazukam, bleibt für „Offene Zeitbuchungen …“.
  case TAtlasTimePlan.EndStep(AIssue.Key, FBookedOnEnd, AOffer) of
    TAtlasTimeEndStep.BookedOnEnd:
      FBookedOnEnd := '';
    TAtlasTimeEndStep.Offer:
      FBooking.Offer(AIssue, AFolder, ABranch, ABase);
  end;
end;

procedure TAtlasIdeTrackerTime.ShowOpen;
begin
  if not FStopped then
  begin
    FBooking.ShowOpen;
  end;
end;

function TAtlasIdeTrackerTime.Seconds(const AKey: string): Int64;
begin
  Result := 0;
  if FStopped or not Active or not TAtlasTimePlan.IsCurrent(FClock.Issue, AKey) then
  begin
    Exit;
  end;
  Result := FStore.CurrentTotal;
end;

function TAtlasIdeTrackerTime.TimeText(const AKey: string): string;
begin
  Result := TAtlasTrackerWorkflow.DurationText(TAtlasTimeRounding.Minutes(Seconds(AKey),
    TAtlasIdeSettings.Current.IssuesTimeRounding));
end;

procedure TAtlasIdeTrackerTime.Booked(const AKey: string; ASeconds: Int64);
begin
  if FStopped or not TAtlasTimePlan.IsCurrent(FClock.Issue, AKey) then
  begin
    Exit;
  end;
  // Erst die offene Spanne schreiben, dann genau die gezeigte Zeit abziehen.
  FStore.Flush;
  FStore.Subtract(FClock.Issue, ASeconds);
  UpdateStatus;
  FBookedOnEnd := AKey;
end;

end.
