unit Atlas.IDE.Tracker.Attach;

// „An Issue anhängen …“ (#1276) in der IDE: sammelt, was der Dialog anbieten
// kann, zeigt TAtlasAttachDialog und sendet nach „Senden“ im Hintergrund.
// - Quellen: Fenster des debuggten Prozesses (IOTAProcess.ProcessId), das
//   Formular des aktiven Moduls im Designer (Bild über GetFormImage bzw.
//   PaintTo), Logdateien aus issues.attach.logFiles ($(ProjectDir) aus dem
//   Projekt des Debuggers, sonst dem aktiven), die Debug-Notiz (#582: Ort,
//   Ausschnitt, Aufrufstapel, letzte Exception; nur bei angehaltenem
//   Programm) und der Exception-Verlauf (#517, höchstens MaxExceptions);
//   gesammelt in Atlas.IDE.Tracker.Attach.Sources.
// - Senden: TAtlasAttachSender.Send im Hintergrund-Thread mit TimeoutMs,
//   Rückkehr über TAtlasMainThread; Stop bricht über IAtlasCiCancel ab.
//   Eine Sendung zur Zeit.
// - GitHub (kein Hochladen): Bilder untereinander in die Zwischenablage,
//   Hinweis „In GitHub mit Strg+V einfügen“, dann öffnet der Browser die Seite
//   des Issues (nur http/https ohne Benutzer).
// - Temporäre Dateien unter %TEMP%\Atlas\attach\<Lauf>: gelöscht nach Senden
//   oder Abbrechen; Reste abgestürzter Läufe räumt Start weg.
// - Meldungen in die Meldungsansicht; das Protokoll bleibt anonym (Anbieter,
//   Anzahl, Ergebnis, Fehlerart; nie Kennung, Adresse oder Inhalt).
// Anbieter, Transport, Vorschläge und Projekt kommen über Hooks („Meine
// Issues“ bzw. die Komposition).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasIssueAttachHooks = record
    Provider: TAtlasIssuePreviewProviderHook;
    /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token.</summary>
    Transport: TAtlasIssuePreviewTransportHook;
    /// <summary>Vorschläge „KEY Titel“ für den Dialog (etwa die Liste aus „Meine Issues“).</summary>
    Issues: TFunc<TArray<string>>;
    /// <summary>Aktives Projekt (.dproj) für $(ProjectDir); '' ohne.</summary>
    Project: TFunc<string>;
    /// <summary>Zeile in die Meldungsansicht.</summary>
    Report: TProc<string>;
  end;

  TAtlasIdeIssueAttach = class(TInterfacedObject)
  public const
    /// <summary>Zeitgrenze für Hochladen und Kommentar zusammen.</summary>
    cTimeoutMs = 60000;
    /// <summary>Abstand der Bilder in der Zwischenablage (GitHub).</summary>
    cImageGap = 16;
  private
    FHooks: TAtlasIssueAttachHooks;
    FMessage: TAtlasMessageSink;
    FStarted: Boolean;
    FWorker: TAtlasWorkerSlot;
    FCancel: IAtlasCiCancel;
    FTemp: TAtlasAttachTemp;
    procedure Send(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest);
    procedure Sent(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest;
      const AOutcome: TAtlasAttachOutcome);
    procedure Fallback(const ARequest: TAtlasAttachRequest; const AOutcome: TAtlasAttachOutcome);
    procedure DropTemp;
    function ProjectFile: string;
  public
    constructor Create(const AHooks: TAtlasIssueAttachHooks);
    destructor Destroy; override;
    /// <summary>Reste früherer Läufe aufräumen.</summary>
    procedure Start;
    /// <summary>Sendung abbrechen, kurz warten, Dateien löschen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Dialog für ATarget zeigen, AKey vorgewählt ('' = keins); nach „Senden“ im Hintergrund senden.
    /// </summary>
    procedure Execute(const ATarget: TAtlasTrackerTarget; const AKey: string); overload;
    /// <summary>Wie oben, mit weiteren Dateien, vorgewählt (etwa die eines Absturzfalls, #1355).</summary>
    procedure Execute(const ATarget: TAtlasTrackerTarget; const AKey: string;
      const AExtra: TArray<TAtlasAttachFile>); overload;
    /// <summary>Läuft eine Sendung?</summary>
    function Busy: Boolean;
    /// <summary>issues.attach an?</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  System.UITypes,
  System.IOUtils,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.AttachPlan,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Attach.Strings,
  Atlas.UI.Tracker.Capture,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.AttachDialog,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.Attach.Sources;

{ TAtlasIdeIssueAttach }

constructor TAtlasIdeIssueAttach.Create(const AHooks: TAtlasIssueAttachHooks);
begin
  inherited Create;
  FHooks := AHooks;
  FMessage := TAtlasMessageSink.Create(FHooks.Report);
  FWorker := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeIssueAttach.Destroy;
begin
  FWorker.Free;
  DropTemp;
  inherited;
end;

procedure TAtlasIdeIssueAttach.Sent(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest;
  const AOutcome: TAtlasAttachOutcome);
begin
  FCancel := nil;
  FWorker.Prune;
  // Die Dateien sind gesendet bzw. gescheitert: der Ordner des Laufs geht in jedem Fall.
  DropTemp;
  TAtlasGuard.Log(TAtlasAttachPlan.SentLog(AProvider.Name, Length(ARequest.Files), AOutcome.Succeeded,
    AOutcome.Error));
  case TAtlasAttachPlan.ReportOf(AOutcome.Succeeded, AOutcome.Error, AOutcome.Uploaded, AOutcome.Commented,
    AOutcome.Fallback) of
    TAtlasAttachReport.Silent:
      ; // Abgebrochen: keine Meldung.
    TAtlasAttachReport.CommentFailed:
      FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachCommentFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]));
    TAtlasAttachReport.Failed:
      FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]));
    TAtlasAttachReport.Fallback:
      Fallback(ARequest, AOutcome);
    TAtlasAttachReport.DoneComment:
      FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachDoneComment, [ARequest.Key, AOutcome.Uploaded]));
    TAtlasAttachReport.Done:
      FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachDone, [ARequest.Key, AOutcome.Uploaded]));
    TAtlasAttachReport.Commented:
      FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachCommented, [ARequest.Key]));
    TAtlasAttachReport.Nothing:
      ; // Weder Dateien noch Kommentar: nichts zu melden.
  end;
end;

procedure TAtlasIdeIssueAttach.Fallback(const ARequest: TAtlasAttachRequest; const AOutcome: TAtlasAttachOutcome);
var
  mBitmaps: TArray<TBitmap>;
  mBitmap, mStacked: TBitmap;
  mImage: TAtlasAttachFile;
  mText: string;
begin
  if AOutcome.Commented then
  begin
    FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachCommented, [ARequest.Key]));
  end;
  if Length(AOutcome.Images) > 0 then
  begin
    mBitmaps := nil;
    try
      for mImage in AOutcome.Images do
      begin
        mBitmap := TAtlasAttachImages.FromPng(mImage.Data);
        if mBitmap <> nil then
        begin
          mBitmaps := mBitmaps + [mBitmap];
        end;
      end;
      mStacked := TAtlasAttachImages.Stacked(mBitmaps, cImageGap);
      try
        if mStacked <> nil then
        begin
          Clipboard.Assign(mStacked);
        end;
      finally
        mStacked.Free;
      end;
    finally
      for mBitmap in mBitmaps do
      begin
        mBitmap.Free;
      end;
    end;
    // Erst der Hinweis, dann der Browser: Der Nutzer weiß, was er dort tun soll.
    mText := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachPasteHint, [Length(mBitmaps), ARequest.Key]);
    FMessage.Say(mText);
    MessageDlg(mText, mtInformation, [mbOK], 0);
  end;
  TAtlasIssuePreview.Browse(AOutcome.Page);
end;

procedure TAtlasIdeIssueAttach.DropTemp;
begin
  if FTemp = nil then
  begin
    Exit;
  end;
  FTemp.Cleanup;
  FreeAndNil(FTemp);
end;


function TAtlasIdeIssueAttach.ProjectFile: string;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := TAtlasIdeAttachSources.LaunchProject;
  if (Result = '') and Assigned(FHooks.Project) then
  begin
    Result := FHooks.Project();
  end;
end;

procedure TAtlasIdeIssueAttach.Start;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  try
    TAtlasAttachTemp.PruneStale(TAtlasAttachTemp.DefaultRoot, Now, TAtlasAttachTemp.cStaleHours);
  except
    on E: Exception do
      TAtlasGuard.Log('Anhängen: Aufräumen alter Läufe mit ' + E.ClassName + ' abgebrochen');
  end;
end;

procedure TAtlasIdeIssueAttach.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
  FWorker.Stop(TAtlasShutdown.cStopMs);
  DropTemp;
  FHooks := Default(TAtlasIssueAttachHooks);
  FMessage.Clear;
end;

procedure TAtlasIdeIssueAttach.Execute(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Execute(ATarget, AKey, nil);
end;

function TAtlasIdeIssueAttach.Busy: Boolean;
begin
  Result := FWorker.Busy;
end;

class function TAtlasIdeIssueAttach.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesAttach;
end;

/// <summary>Eingaben des Dialogs: Tracker, Vorschläge, Kennung, Prozess, Protokolle, Debug-Notiz, Exceptions,
/// Bild des Formulars (ohne es weiter; der Rest des Dialogs bleibt nutzbar) und weitere Dateien.</summary>
function DialogInput(AOwner: TAtlasIdeIssueAttach; const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const AKey: string; const AExtra: TArray<TAtlasAttachFile>):
  TAtlasAttachDialogInput;
var
  mAttach: IAtlasTrackerAttach;
  mName: string;
begin
  mName := ATarget.Provider;
  Result := TAtlasAttachDialogInput.Empty;
  Result.Tracker := AProvider.Caption;
  Result.CanUpload := Supports(AProvider, IAtlasTrackerAttach, mAttach) and mAttach.CanUpload;
  if Assigned(AOwner.FHooks.Issues) then
  begin
    Result.Issues := AOwner.FHooks.Issues();
  end;
  Result.Key := AKey;
  Result.KeyOf :=
    function(AInput: string): string
    begin
      Result := TAtlasIssuePreview.KeyOf(mName, AInput);
    end;
  Result.ProcessId := TAtlasIdeAttachSources.ProcessId;
  Result.LogFiles := TAtlasAttachLog.Candidates(TAtlasIdeSettings.Current.IssuesAttachLogFiles, AOwner.ProjectFile);
  TAtlasIdeAttachSources.DebugNote(Result.DebugNote, Result.DebugNoteName);
  Result.ExceptionsText := TAtlasIdeAttachSources.ExceptionsText(Result.ExceptionCount);
  Result.MaxImageWidth := TAtlasIdeSettings.Current.IssuesAttachMaxImageWidth;
  Result.RaiseProgram := TAtlasIdeSettings.Current.IssuesAttachRaiseProgram;
  Result.Extra := AExtra;
  try
    Result.FormImage := TAtlasIdeAttachSources.DesignerImage(Result.FormName);
  except
    on E: Exception do
    begin
      Result.FormImage := nil;
      TAtlasGuard.Report(TAtlasFeature.Tracker, E);
    end;
  end;
end;

/// <summary>Dialog zeigen; True nach „Senden“ mit der Anfrage. AInput.FormImage gibt er frei (der Dialog hat eine
/// Kopie).</summary>
function AskRequest(AOwner: TAtlasIdeIssueAttach; var AInput: TAtlasAttachDialogInput;
  const ATarget: TAtlasTrackerTarget; out ARequest: TAtlasAttachRequest): Boolean;
var
  mDialog: TAtlasAttachDialog;
begin
  ARequest := Default(TAtlasAttachRequest);
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, AInput, AOwner.FTemp);
  finally
    AInput.FormImage.Free;
    AInput.FormImage := nil;
  end;
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      ARequest.Target := ATarget;
      ARequest.Key := mDialog.Key;
      ARequest.Files := mDialog.Files;
      ARequest.Comment := mDialog.CommentText;
      ARequest.WithComment := mDialog.WithComment;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasIdeIssueAttach.Execute(const ATarget: TAtlasTrackerTarget; const AKey: string;
  const AExtra: TArray<TAtlasAttachFile>);
var
  mTarget: TAtlasTrackerTarget;
  mKey: string;
  mExtra: TArray<TAtlasAttachFile>;
begin
  mTarget := ATarget;
  mKey := AKey;
  mExtra := AExtra;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mProvider: IAtlasTrackerProvider;
      mInput: TAtlasAttachDialogInput;
      mRequest: TAtlasAttachRequest;
    begin
      if not FStarted or not Active then
      begin
        Exit;
      end;
      if Busy then
      begin
        FMessage.Say(TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachBusy));
        Exit;
      end;
      mProvider := nil;
      if Assigned(FHooks.Provider) and (mTarget.Provider <> '') then
      begin
        mProvider := FHooks.Provider(mTarget.Provider);
      end;
      if (mProvider = nil) or (mTarget.Server = '') then
      begin
        FMessage.Say(TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewNoTracker));
        Exit;
      end;
      DropTemp;
      FTemp := TAtlasAttachTemp.Create(TAtlasAttachTemp.DefaultRoot);
      mInput := DialogInput(Self, mProvider, mTarget, mKey, mExtra);
      if AskRequest(Self, mInput, mTarget, mRequest) then
      begin
        Send(mProvider, mRequest);
      end
      else
      begin
        DropTemp;
      end;
    end);
end;

/// <summary>Arbeit des Hintergrundthreads: hochladen und kommentieren; das Ergebnis geht über den Hauptthread an
/// AOwner, solange AKeep ihn hält. Eigene Routine: Die anonyme Methode hält nur ihre Parameter.</summary>
function SendWorker(AOwner: TAtlasIdeIssueAttach; const AKeep: IInterface; const AProvider: IAtlasTrackerProvider;
  const ATransport: IAtlasCiTransport; const ARequest: TAtlasAttachRequest): TProc;
var
  mKeep: IInterface;
  mTransport: IAtlasCiTransport;
begin
  mKeep := AKeep;
  mTransport := ATransport;
  Result :=
    procedure
    var
      mResult: TAtlasAttachOutcome;
    begin
      mResult := Default(TAtlasAttachOutcome);
      try
        mResult := TAtlasAttachSender.Send(AProvider, mTransport, ARequest, TAtlasIdeIssueAttach.cTimeoutMs);
      except
        // Kein Dialog aus dem Hintergrund: als Netzfehler werten.
        on E: Exception do
        begin
          mResult.Error := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Anhängen: Senden mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if (mKeep <> nil) and AOwner.FStarted then
          begin
            AOwner.Sent(AProvider, ARequest, mResult);
          end;
        end);
    end;
end;

procedure TAtlasIdeIssueAttach.Send(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest);
var
  mTransport: IAtlasCiTransport;
  mOutcome: TAtlasAttachOutcome;
begin
  if not TAtlasAttachPlan.HasWork(ARequest.Key, Length(ARequest.Files), ARequest.Comment) then
  begin
    DropTemp;
    Exit;
  end;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(AProvider, ARequest.Target);
  end;
  if mTransport = nil then
  begin
    mOutcome := Default(TAtlasAttachOutcome);
    mOutcome.Error := TAtlasCiFetchError.Unauthorized;
    Sent(AProvider, ARequest, mOutcome);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  FMessage.Say(TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachSending, [ARequest.Key]));
  FWorker.Start(TThread.CreateAnonymousThread(SendWorker(Self, Self, AProvider, mTransport, ARequest)));
end;

end.
