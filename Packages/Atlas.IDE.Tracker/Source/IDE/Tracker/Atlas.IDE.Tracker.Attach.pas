unit Atlas.IDE.Tracker.Attach;

// „An Issue anhängen …“ (#1276) in der IDE: sammelt, was der Dialog anbieten
// kann, zeigt TAtlasAttachDialog und sendet nach „Senden“ im Hintergrund.
// - Quellen: Fenster des debuggten Prozesses (IOTAProcess.ProcessId), das
//   Formular des aktiven Moduls im Designer (Bild über GetFormImage bzw.
//   PaintTo), Logdateien aus issues.attach.logFiles ($(ProjectDir) aus dem
//   Projekt des Debuggers, sonst dem aktiven), die Debug-Notiz (#582: Ort,
//   Ausschnitt, Aufrufstapel, letzte Exception; nur bei angehaltenem
//   Programm) und der Exception-Verlauf (#517, höchstens MaxExceptions).
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
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Tracker.IssueContext;

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
    TimeoutMs = 60000;
    MaxExceptions = 20;
    /// <summary>Abstand der Bilder in der Zwischenablage (GitHub).</summary>
    ImageGap = 16;
  private
    FHooks: TAtlasIssueAttachHooks;
    FStarted: Boolean;
    FThread: TThread;
    FCancel: IAtlasCiCancel;
    FTemp: TAtlasAttachTemp;
    procedure Report(const AText: string);
    procedure ReleaseThread(AWait: Boolean);
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
    /// <summary>Debug-Notiz des aktuellen Halts mit Dateiname; False, wenn das Programm nicht angehalten ist oder
    /// kein Modul eine Debug-Sitzung kennt.</summary>
    class function DebugNote(out AMarkdown, AFileName: string): Boolean; static;
    /// <summary>Exception-Verlauf der Sitzung als Text, neueste zuerst; '' ohne Einträge.</summary>
    class function ExceptionsText(out ACount: Integer): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  System.IOUtils,
  ToolsAPI,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Vcl.Dialogs,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.Capture,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.AttachDialog,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Modules.Registry,
  Atlas.IDE.Contracts.DebugReport;

// Bild des Formulars im Designer des aktiven Moduls; nil ohne (Datenmodul, FMX, kein Designer).
/// <summary>Bild eines Formulars bzw. Frames im Designer; nil ohne Fenster.</summary>
function RootImage(ARoot: TComponent): TBitmap;
begin
  Result := nil;
  if ARoot is TCustomForm then
  begin
    Result := TCustomForm(ARoot).GetFormImage;
  end
  else if (ARoot is TWinControl) and TWinControl(ARoot).HandleAllocated then
  begin
    Result := TBitmap.Create;
    try
      Result.SetSize(TWinControl(ARoot).Width, TWinControl(ARoot).Height);
      TWinControl(ARoot).PaintTo(Result.Canvas.Handle, 0, 0);
    except
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

/// <summary>Wurzel des ersten Formular-Editors im Modul; nil ohne.</summary>
function DesignerRoot(const AModule: IOTAModule): TComponent;
var
  mEditor: IOTAFormEditor;
  mComponent: INTAComponent;
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTAFormEditor, mEditor) and
      Supports(mEditor.GetRootComponent, INTAComponent, mComponent) then
    begin
      Exit(mComponent.GetComponent);
    end;
  end;
end;

function DesignerImage(out AName: string): TBitmap;
var
  mServices: IOTAModuleServices;
  mRoot: TComponent;
begin
  Result := nil;
  AName := '';
  mRoot := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) and (mServices.CurrentModule <> nil) then
  begin
    mRoot := DesignerRoot(mServices.CurrentModule);
  end;
  if mRoot <> nil then
  begin
    Result := RootImage(mRoot);
  end;
  if Result <> nil then
  begin
    AName := mRoot.Name;
  end;
end;

/// <summary>Bericht des Debuggers (#1455); nil, solange kein Modul eine Debug-Sitzung kennt.</summary>
function DebugReport: IAtlasDebugReportSource;
var
  mItem: IInterface;
begin
  Result := nil;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  for mItem in AtlasModuleRegistry.FindAll(IAtlasDebugReportSource) do
  begin
    if Supports(mItem, IAtlasDebugReportSource, Result) then
    begin
      Exit;
    end;
  end;
end;

function DebugProcessId: DWORD;
var
  mReport: IAtlasDebugReportSource;
begin
  Result := 0;
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.DebuggedProcessId;
  end;
end;

{ TAtlasIdeIssueAttach }

constructor TAtlasIdeIssueAttach.Create(const AHooks: TAtlasIssueAttachHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

destructor TAtlasIdeIssueAttach.Destroy;
begin
  ReleaseThread(True);
  DropTemp;
  inherited;
end;

class function TAtlasIdeIssueAttach.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesAttach;
end;

procedure TAtlasIdeIssueAttach.Start;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  try
    TAtlasAttachTemp.PruneStale(TAtlasAttachTemp.DefaultRoot, Now, TAtlasAttachTemp.StaleHours);
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
  ReleaseThread(True);
  DropTemp;
  FHooks := Default(TAtlasIssueAttachHooks);
end;

function TAtlasIdeIssueAttach.Busy: Boolean;
begin
  Result := (FThread <> nil) and not FThread.Finished;
end;

procedure TAtlasIdeIssueAttach.ReleaseThread(AWait: Boolean);
begin
  if FThread = nil then
  begin
    Exit;
  end;
  if AWait and not FThread.Finished then
  begin
    TAtlasShutdown.WaitForThreads([FThread]);
  end;
  if FThread.Finished then
  begin
    FreeAndNil(FThread);
  end
  else if AWait then
  begin
    // Läuft noch (Zeitgrenze): räumt sich selbst auf.
    FThread.FreeOnTerminate := True;
    FThread := nil;
  end;
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

procedure TAtlasIdeIssueAttach.Report(const AText: string);
begin
  if Assigned(FHooks.Report) then
  begin
    FHooks.Report(AText);
  end;
end;

function TAtlasIdeIssueAttach.ProjectFile: string;
var
  mReport: IAtlasDebugReportSource;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := '';
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.LaunchProject;
  end;
  if (Result = '') and Assigned(FHooks.Project) then
  begin
    Result := FHooks.Project();
  end;
end;

class function TAtlasIdeIssueAttach.DebugNote(out AMarkdown, AFileName: string): Boolean;
var
  mReport: IAtlasDebugReportSource;
begin
  AMarkdown := '';
  AFileName := '';
  mReport := DebugReport;
  Result := (mReport <> nil) and mReport.DebugNote(AMarkdown, AFileName);
end;

class function TAtlasIdeIssueAttach.ExceptionsText(out ACount: Integer): string;
var
  mReport: IAtlasDebugReportSource;
begin
  Result := '';
  ACount := 0;
  mReport := DebugReport;
  if mReport <> nil then
  begin
    Result := mReport.ExceptionsText(MaxExceptions, ACount);
  end;
end;

procedure TAtlasIdeIssueAttach.Execute(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Execute(ATarget, AKey, nil);
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
  Result.ProcessId := DebugProcessId;
  Result.LogFiles := TAtlasAttachLog.Candidates(TAtlasIdeSettings.Current.IssuesAttachLogFiles, AOwner.ProjectFile);
  TAtlasIdeIssueAttach.DebugNote(Result.DebugNote, Result.DebugNoteName);
  Result.ExceptionsText := TAtlasIdeIssueAttach.ExceptionsText(Result.ExceptionCount);
  Result.MaxImageWidth := TAtlasIdeSettings.Current.IssuesAttachMaxImageWidth;
  Result.Extra := AExtra;
  try
    Result.FormImage := DesignerImage(Result.FormName);
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
        Report(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachBusy));
        Exit;
      end;
      mProvider := nil;
      if Assigned(FHooks.Provider) and (mTarget.Provider <> '') then
      begin
        mProvider := FHooks.Provider(mTarget.Provider);
      end;
      if (mProvider = nil) or (mTarget.Server = '') then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
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
        mResult := TAtlasAttachSender.Send(AProvider, mTransport, ARequest, TAtlasIdeIssueAttach.TimeoutMs);
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
  if (ARequest.Key = '') or ((Length(ARequest.Files) = 0) and (ARequest.Comment = '')) then
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
  Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachSending, [ARequest.Key]));
  FThread := TThread.CreateAnonymousThread(SendWorker(Self, Self, AProvider, mTransport, ARequest));
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeIssueAttach.Sent(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest;
  const AOutcome: TAtlasAttachOutcome);
var
  mState: string;
begin
  FCancel := nil;
  ReleaseThread(False);
  // Die Dateien sind gesendet bzw. gescheitert: der Ordner des Laufs geht in jedem Fall.
  DropTemp;
  if AOutcome.Succeeded then
  begin
    mState := 'gesendet';
  end
  else
  begin
    mState := 'nicht gesendet (' + TAtlasCiBuild.ErrorKey(AOutcome.Error) + ')';
  end;
  TAtlasGuard.Log(Format('Anhängen: %s, %d Dateien, %s', [AProvider.Name, Length(ARequest.Files), mState]));
  if AOutcome.Error = TAtlasCiFetchError.Cancelled then
  begin
    Exit;
  end;
  if not AOutcome.Succeeded then
  begin
    if AOutcome.Uploaded > 0 then
    begin
      Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachCommentFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]));
    end
    else
    begin
      Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]));
    end;
    Exit;
  end;
  if AOutcome.Fallback then
  begin
    Fallback(ARequest, AOutcome);
    Exit;
  end;
  if (AOutcome.Uploaded > 0) and AOutcome.Commented then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachDoneComment, [ARequest.Key, AOutcome.Uploaded]));
  end
  else if AOutcome.Uploaded > 0 then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachDone, [ARequest.Key, AOutcome.Uploaded]));
  end
  else if AOutcome.Commented then
  begin
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachCommented, [ARequest.Key]));
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
    Report(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachCommented, [ARequest.Key]));
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
      mStacked := TAtlasAttachImages.Stacked(mBitmaps, ImageGap);
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
    mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachPasteHint, [Length(mBitmaps), ARequest.Key]);
    Report(mText);
    MessageDlg(mText, mtInformation, [mbOK], 0);
  end;
  TAtlasIssuePreview.Browse(AOutcome.Page);
end;

end.
