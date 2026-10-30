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
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.Core.Debug.Note,
  Atlas.IDE.Tracker.IssuePreview;

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
    class function NoteTexts: TAtlasDebugNoteTexts; static;
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
    /// <summary>Debug-Notiz des aktuellen Halts; False, wenn das Programm nicht angehalten ist.</summary>
    class function DebugNote(out AMarkdown: string): Boolean; static;
    /// <summary>Exception-Verlauf der Sitzung als Text, neueste zuerst; '' ohne Einträge.</summary>
    class function ExceptionsText(out ACount: Integer): string; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.UITypes,
  System.IOUtils,
  System.StrUtils,
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
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Capture,
  Atlas.UI.Tracker.IssueTip,
  Atlas.UI.Tracker.AttachDialog,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Exceptions;

// Bild des Formulars im Designer des aktiven Moduls; nil ohne (Datenmodul, FMX, kein Designer).
function DesignerImage(out AName: string): TBitmap;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mEditor: IOTAFormEditor;
  mComponent: INTAComponent;
  mRoot: TComponent;
  mIndex: Integer;
begin
  Result := nil;
  AName := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
    Exit;
  mModule := mServices.CurrentModule;
  if mModule = nil then
    Exit;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
    if Supports(mModule.ModuleFileEditors[mIndex], IOTAFormEditor, mEditor) and
      Supports(mEditor.GetRootComponent, INTAComponent, mComponent) then
    begin
      mRoot := mComponent.GetComponent;
      if mRoot is TCustomForm then
        Result := TCustomForm(mRoot).GetFormImage
      else if (mRoot is TWinControl) and TWinControl(mRoot).HandleAllocated then
      begin
        Result := TBitmap.Create;
        try
          Result.SetSize(TWinControl(mRoot).Width, TWinControl(mRoot).Height);
          TWinControl(mRoot).PaintTo(Result.Canvas.Handle, 0, 0);
        except
          FreeAndNil(Result);
          raise;
        end;
      end;
      if Result <> nil then
        AName := mRoot.Name;
      Exit;
    end;
end;

function DebugProcessId: DWORD;
var
  mProcess: IOTAProcess;
begin
  Result := 0;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
    Result := mProcess.ProcessId;
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
    Exit;
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
    Exit;
  FStarted := False;
  if FCancel <> nil then
    FCancel.Cancel;
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
    Exit;
  if AWait and not FThread.Finished then
    TAtlasShutdown.WaitForThreads([FThread]);
  if FThread.Finished then
    FreeAndNil(FThread)
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
    Exit;
  FTemp.Cleanup;
  FreeAndNil(FTemp);
end;

procedure TAtlasIdeIssueAttach.Report(const AText: string);
begin
  if Assigned(FHooks.Report) then
    FHooks.Report(AText);
end;

function TAtlasIdeIssueAttach.ProjectFile: string;
begin
  // Beim Debuggen das gestartete Projekt, sonst das aktive.
  Result := TAtlasIdeDebugSession.LaunchProject;
  if (Result = '') and Assigned(FHooks.Project) then
    Result := FHooks.Project();
end;

class function TAtlasIdeIssueAttach.NoteTexts: TAtlasDebugNoteTexts;
begin
  Result.Title := TAtlasStrings.Text(TAtlasTextId.DebugNoteTitle);
  Result.Project := TAtlasStrings.Text(TAtlasTextId.DebugNoteProject);
  Result.Configuration := TAtlasStrings.Text(TAtlasTextId.DebugNoteConfiguration);
  Result.TargetPlatform := TAtlasStrings.Text(TAtlasTextId.DebugNotePlatform);
  Result.Time := TAtlasStrings.Text(TAtlasTextId.DebugNoteTime);
  Result.Thread := TAtlasStrings.Text(TAtlasTextId.DebugNoteThread);
  Result.Location := TAtlasStrings.Text(TAtlasTextId.DebugNoteLocation);
  Result.CallStack := TAtlasStrings.Text(TAtlasTextId.DebugNoteCallStack);
  Result.LastException := TAtlasStrings.Text(TAtlasTextId.DebugNoteLastException);
  Result.Count := TAtlasStrings.Text(TAtlasTextId.DebugNoteCount);
  Result.NoLocation := TAtlasStrings.Text(TAtlasTextId.DebugNoteNoLocation);
end;

class function TAtlasIdeIssueAttach.DebugNote(out AMarkdown: string): Boolean;
var
  mThread: IOTAThread;
  mData: TAtlasDebugNoteData;
  mFrames: TAtlasDebugFrames;
  mHistory: TAtlasDebugExceptionHistory;
  mNewest: TArray<Integer>;
  mFile: string;
begin
  AMarkdown := '';
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if mThread = nil then
    Exit(False);
  mData := TAtlasDebugNoteData.Empty;
  mData.Project := TAtlasIdeDebugSession.LaunchProject;
  mData.Configuration := TAtlasIdeDebugSession.LaunchConfiguration;
  mData.TargetPlatform := TAtlasIdeDebugSession.LaunchPlatform;
  mData.Time := Now;
  mData.Thread := TAtlasDebugException.Create(0, '', '', mThread.GetOSThreadID,
    TAtlasIdeDebugSession.ThreadName(mThread), '', 0, '').ThreadText(
    TAtlasStrings.Text(TAtlasTextId.DebugExceptionsThread));
  mData.FileName := mThread.CurrentFile;
  mData.Line := Integer(mThread.CurrentLine);
  if TAtlasIdeDebugSession.ReadStack(mThread, TAtlasDebugNote.MaxFrames, mFrames) = TAtlasDebugStackRead.Ready then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    mData.Frames := mFrames;
    if Length(mFrames) > 0 then
      mData.Routine := TAtlasDebugCallStack.RoutineOf(mFrames[0].Header);
  end;
  // Ausschnitt von der Platte; ohne Datei bleibt der Ort ohne Code.
  if mData.FileName <> '' then
  begin
    mFile := TAtlasIdeDebugSources.Resolve(mData.FileName);
    if mFile <> '' then
      try
        mData.Source := TTextLines.SplitLines(TAtlasAttachLog.Decode(TFile.ReadAllBytes(mFile)));
        mData.SourceFirstLine := 1;
      except
        on E: EInOutError do
          mData.Source := nil;
        on E: EFileStreamError do
          mData.Source := nil;
      end;
  end;
  mHistory := TAtlasIdeDebugExceptions.History;
  if mHistory <> nil then
  begin
    mNewest := mHistory.Filter('', '');
    if Length(mNewest) > 0 then
    begin
      mData.HasException := True;
      mData.Exception := mHistory[mNewest[0]];
    end;
  end;
  AMarkdown := TAtlasDebugNote.Markdown(mData, NoteTexts);
  Result := True;
end;

class function TAtlasIdeIssueAttach.ExceptionsText(out ACount: Integer): string;
var
  mHistory: TAtlasDebugExceptionHistory;
  mIndexes: TArray<Integer>;
  mItems: TAtlasDebugExceptions;
  mIndex: Integer;
begin
  Result := '';
  ACount := 0;
  mHistory := TAtlasIdeDebugExceptions.History;
  if mHistory = nil then
    Exit;
  mIndexes := mHistory.Filter('', '');
  ACount := Length(mIndexes);
  mItems := nil;
  for mIndex in mIndexes do
  begin
    if Length(mItems) >= MaxExceptions then
      Break;
    mItems := mItems + [mHistory[mIndex]];
  end;
  Result := TAtlasDebugNote.HistoryText(mItems, MaxExceptions);
end;

procedure TAtlasIdeIssueAttach.Execute(const ATarget: TAtlasTrackerTarget; const AKey: string);
begin
  Execute(ATarget, AKey, nil);
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
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mProvider: IAtlasTrackerProvider;
      mAttach: IAtlasTrackerAttach;
      mInput: TAtlasAttachDialogInput;
      mDialog: TAtlasAttachDialog;
      mRequest: TAtlasAttachRequest;
      mName: string;
    begin
      if not FStarted or not Active then
        Exit;
      if Busy then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.AttachBusy));
        Exit;
      end;
      mProvider := nil;
      if Assigned(FHooks.Provider) and (mTarget.Provider <> '') then
        mProvider := FHooks.Provider(mTarget.Provider);
      if (mProvider = nil) or (mTarget.Server = '') then
      begin
        Report(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoTracker));
        Exit;
      end;
      mName := mTarget.Provider;
      mInput := TAtlasAttachDialogInput.Empty;
      mInput.Tracker := mProvider.Caption;
      mInput.CanUpload := Supports(mProvider, IAtlasTrackerAttach, mAttach) and mAttach.CanUpload;
      if Assigned(FHooks.Issues) then
        mInput.Issues := FHooks.Issues();
      mInput.Key := mKey;
      mInput.KeyOf :=
        function(AInput: string): string
        begin
          Result := TAtlasIssuePreview.KeyOf(mName, AInput);
        end;
      mInput.ProcessId := DebugProcessId;
      mInput.LogFiles := TAtlasAttachLog.Candidates(TAtlasIdeSettings.Current.IssuesAttachLogFiles, ProjectFile);
      DebugNote(mInput.DebugNote);
      mInput.DebugNoteName := TAtlasDebugNote.FileName(Now);
      mInput.ExceptionsText := ExceptionsText(mInput.ExceptionCount);
      mInput.MaxImageWidth := TAtlasIdeSettings.Current.IssuesAttachMaxImageWidth;
      mInput.Extra := mExtra;
      DropTemp;
      FTemp := TAtlasAttachTemp.Create(TAtlasAttachTemp.DefaultRoot);
      try
        mInput.FormImage := DesignerImage(mInput.FormName);
      except
        // Ohne Bild des Formulars weiter; der Rest des Dialogs bleibt nutzbar.
        on E: Exception do
        begin
          mInput.FormImage := nil;
          TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
        end;
      end;
      try
        mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, FTemp);
      finally
        // Der Dialog hat eine Kopie.
        mInput.FormImage.Free;
        mInput.FormImage := nil;
      end;
      try
        if mDialog.ShowModal <> mrOk then
        begin
          DropTemp;
          Exit;
        end;
        mRequest := Default(TAtlasAttachRequest);
        mRequest.Target := mTarget;
        mRequest.Key := mDialog.Key;
        mRequest.Files := mDialog.Files;
        mRequest.Comment := mDialog.CommentText;
        mRequest.WithComment := mDialog.WithComment;
      finally
        mDialog.Free;
      end;
      Send(mProvider, mRequest);
    end);
end;

procedure TAtlasIdeIssueAttach.Send(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest);
var
  mTransport: IAtlasCiTransport;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueAttach;
  mOutcome: TAtlasAttachOutcome;
begin
  if (ARequest.Key = '') or ((Length(ARequest.Files) = 0) and (ARequest.Comment = '')) then
  begin
    DropTemp;
    Exit;
  end;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(AProvider, ARequest.Target);
  if mTransport = nil then
  begin
    mOutcome := Default(TAtlasAttachOutcome);
    mOutcome.Error := TAtlasCiFetchError.Unauthorized;
    Sent(AProvider, ARequest, mOutcome);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    FCancel := nil;
  Report(TAtlasStrings.Fmt(TAtlasTextId.AttachSending, [ARequest.Key]));
  mKeep := Self;
  mOwner := Self;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasAttachOutcome;
    begin
      mResult := Default(TAtlasAttachOutcome);
      try
        mResult := TAtlasAttachSender.Send(AProvider, mTransport, ARequest, TimeoutMs);
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
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if (mKeep <> nil) and mOwner.FStarted then
            mOwner.Sent(AProvider, ARequest, mResult);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeIssueAttach.Sent(const AProvider: IAtlasTrackerProvider; const ARequest: TAtlasAttachRequest;
  const AOutcome: TAtlasAttachOutcome);
begin
  FCancel := nil;
  ReleaseThread(False);
  // Die Dateien sind gesendet bzw. gescheitert: der Ordner des Laufs geht in jedem Fall.
  DropTemp;
  TAtlasGuard.Log(Format('Anhängen: %s, %d Dateien, %s', [AProvider.Name, Length(ARequest.Files),
    IfThen(AOutcome.Succeeded, 'gesendet', 'nicht gesendet (' + TAtlasCiBuild.ErrorKey(AOutcome.Error) + ')')]));
  if AOutcome.Error = TAtlasCiFetchError.Cancelled then
    Exit;
  if not AOutcome.Succeeded then
  begin
    if AOutcome.Uploaded > 0 then
      Report(TAtlasStrings.Fmt(TAtlasTextId.AttachCommentFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]))
    else
      Report(TAtlasStrings.Fmt(TAtlasTextId.AttachFailed, [ARequest.Key,
        TAtlasIssueTip.ErrorText(AOutcome.Error, ARequest.Key)]));
    Exit;
  end;
  if AOutcome.Fallback then
  begin
    Fallback(ARequest, AOutcome);
    Exit;
  end;
  if (AOutcome.Uploaded > 0) and AOutcome.Commented then
    Report(TAtlasStrings.Fmt(TAtlasTextId.AttachDoneComment, [ARequest.Key, AOutcome.Uploaded]))
  else if AOutcome.Uploaded > 0 then
    Report(TAtlasStrings.Fmt(TAtlasTextId.AttachDone, [ARequest.Key, AOutcome.Uploaded]))
  else if AOutcome.Commented then
    Report(TAtlasStrings.Fmt(TAtlasTextId.AttachCommented, [ARequest.Key]));
end;

procedure TAtlasIdeIssueAttach.Fallback(const ARequest: TAtlasAttachRequest; const AOutcome: TAtlasAttachOutcome);
var
  mBitmaps: TArray<TBitmap>;
  mBitmap, mStacked: TBitmap;
  mImage: TAtlasAttachFile;
  mText: string;
begin
  if AOutcome.Commented then
    Report(TAtlasStrings.Fmt(TAtlasTextId.AttachCommented, [ARequest.Key]));
  if Length(AOutcome.Images) > 0 then
  begin
    mBitmaps := nil;
    try
      for mImage in AOutcome.Images do
      begin
        mBitmap := TAtlasAttachImages.FromPng(mImage.Data);
        if mBitmap <> nil then
          mBitmaps := mBitmaps + [mBitmap];
      end;
      mStacked := TAtlasAttachImages.Stacked(mBitmaps, ImageGap);
      try
        if mStacked <> nil then
          Clipboard.Assign(mStacked);
      finally
        mStacked.Free;
      end;
    finally
      for mBitmap in mBitmaps do
        mBitmap.Free;
    end;
    // Erst der Hinweis, dann der Browser: Der Nutzer weiß, was er dort tun soll.
    mText := TAtlasStrings.Fmt(TAtlasTextId.AttachPasteHint, [Length(mBitmaps), ARequest.Key]);
    Report(mText);
    MessageDlg(mText, mtInformation, [mbOK], 0);
  end;
  if TAtlasIssuePreview.MayBrowse(AOutcome.Page) then
    ShellExecute(0, 'open', PChar(AOutcome.Page), nil, nil, SW_SHOWNORMAL);
end;

end.
