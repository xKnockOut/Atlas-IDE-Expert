unit Atlas.IDE.Welcome.NewIssue;

// „Issue anlegen …“ in der IDE (#1268): aus dem Editor (Kontextmenü, Befehl
// Atlas.CreateIssue, Taste keys.createIssue) und aus Befunden des Fensters
// „Atlas-Prüfung“. Abschaltbar mit issues.create.
// - Vorschlag: Datei, Zeile, Methode und Auswahl aus der aktiven
//   Editoransicht, Branch und Commit der Arbeitskopie über TAtlasIdeVcs.Run
//   (im Hintergrund), Text und Titel aus Atlas.Core.Tracker.NewIssue.
// - Tracker: der des aktiven Projekts (.atlas bzw. Zuordnung, #1261) zuerst,
//   dahinter die übrigen persönlichen Verbindungen (issues.connections).
// - Dialog TAtlasNewIssueDialog: nichts geht ohne „Anlegen“ hinaus. Listen
//   (Typ, Priorität, Zuständig) und das Anlegen laufen in eigenen Threads mit
//   höchstens 10 s, die Ergebnisse kommen über TAtlasMainThread.
// - Danach: TODO unter dem Cursor bekommt die Kennung (// TODO ATL-130: …),
//   sonst die Frage nach dem Kommentar // ATL-130; Kennung in die
//   Zwischenablage; Benachrichtigung mit „Im Browser öffnen“; auf Wunsch
//   „Beginnen“ wie in „Meine Issues“ (#765). Schlägt das Anlegen fehl, ändert
//   Atlas am Code nichts.
// - Protokoll anonym: Anbieter und Ergebnis, nie Adresse, Projekt, Titel,
//   Text oder Token.
// - Aus einem Absturzfall des Servers (#1355): Titel und Text (Stapel,
//   Version) vom Plugin-Kern; nach dem Anlegen öffnet „An Issue anhängen“
//   (#1276) mit den Dateien des Falls für das neue Issue.
// Anbieter, Transport und „Beginnen“ kommen von TAtlasIdeIssues (Start).

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.NewIssue,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Welcome.Issues;

type
  TAtlasIdeNewIssue = class
  public
    /// <summary>AIssues: Bereich „Meine Issues“ (Anbieter, Transport, Beginnen); AMessage: Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Start(AIssues: TAtlasIdeIssues; const AMessage: TProc<string>); static;
    /// <summary>Beim Entladen: auf laufende Anfragen warten (höchstens deren Zeitgrenze), danach wirkungslos.
    /// </summary>
    class procedure Stop; static;
    /// <summary>issues.create an und gestartet.</summary>
    class function Enabled: Boolean; static;
    /// <summary>Aus dem Editor: Auswahl bzw. TODO an der Schreibmarke.</summary>
    class procedure FromEditor; static;
    /// <summary>Aus Befunden; mehrere ergeben ein Issue mit Liste.</summary>
    class procedure FromFindings(const AFindings: TArray<TAtlasNewIssueFinding>); static;
    /// <summary>Aus einem Absturzfall (#1355): ATitle und ADescription vorgeschlagen, AFiles nach dem Anlegen
    /// zum Anhängen vorgewählt.</summary>
    class procedure FromCrash(const ATitle, ADescription: string; const AFiles: TArray<TAtlasAttachFile>); static;
  end;

implementation

uses
  System.Classes,
  System.UITypes,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.ShellAPI,
  Vcl.Clipbrd,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Continue,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.NewIssue,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Vcs.Service;

const
  cVcsTimeoutMs = 2000;
  cOutcomeKeys: array[TAtlasNewIssueOutcome] of string = ('created', 'noToken', 'notConfigured', 'rejected',
    'projectUnknown', 'invalid', 'unreadable', 'serverError', 'unreachable');

type
  /// <summary>Wohin die Kennung nach dem Anlegen kommt: Datei und Zeile wie beim Öffnen des Dialogs.</summary>
  TEditorPlace = record
    Valid: Boolean;
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Text der Zeile beim Öffnen; hat er sich geändert, schreibt Atlas nichts.</summary>
    LineText: string;
  end;

var
  Issues: TAtlasIdeIssues;
  IssuesRef: IInterface;
  Report: TProc<string>;
  Threads: TList<TThread>;
  /// <summary>Tracker der letzten Sendung (Send): Dorthin gehen danach die Dateien eines Absturzfalls.</summary>
  LastTarget: TAtlasTrackerTarget;

function Labels: TAtlasNewIssueLabels;
begin
  Result.Location := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelLocation);
  Result.Line := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelLine);
  Result.Method := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelMethod);
  Result.Branch := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelBranch);
  Result.Commit := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelCommit);
  Result.Findings := TAtlasStrings.Text(TAtlasTextId.NewIssueLabelFindings);
  Result.FindingsTitle := TAtlasStrings.Text(TAtlasTextId.NewIssueFindingsTitle);
end;

procedure Say(const AText: string);
begin
  if Assigned(Report) then
    Report(AText);
end;

/// <summary>AWork im Hintergrund, danach ADone über TAtlasMainThread; beim Entladen verfällt ADone.</summary>
procedure RunInBackground(const AWork: TProc; const ADone: TProc);
var
  mThread: TThread;
begin
  if Threads = nil then
    Threads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AWork();
      except
        on E: Exception do
          TAtlasGuard.Log('Issue anlegen: Anfrage mit ' + E.ClassName + ' abgebrochen');
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if (Threads = nil) or not Threads.Contains(mThread) then
            Exit;
          Threads.Remove(mThread);
          mThread.WaitFor;
          mThread.Free;
          ADone();
        end);
    end);
  mThread.FreeOnTerminate := False;
  Threads.Add(mThread);
  mThread.Start;
end;

function CaptionOf(const AConnection: string; const ATarget: TAtlasTrackerTarget): string;
var
  mProvider: string;
begin
  if SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) then
    mProvider := 'GitHub'
  else
    mProvider := 'YouTrack';
  Result := mProvider + ' · ' + ATarget.Server;
  if AConnection <> '' then
    Result := AConnection + ' (' + Result + ')';
end;

/// <summary>Tracker des aktiven Projekts zuerst, dahinter die übrigen Verbindungen.</summary>
function TrackersOf(const AProject: string; out AIndex: Integer): TArray<TAtlasNewIssueTracker>;
var
  mResolved, mTarget: TAtlasTrackerTarget;
  mConnection: string;
  mItem: TAtlasTrackerConnection;
begin
  Result := nil;
  AIndex := -1;
  mResolved := TAtlasIdeIssues.TrackerOf(AProject, mConnection);
  mResolved.Language := TAtlasTrackerConnections.LanguageOf(
    TAtlasTrackerConnections.Read(TAtlasIdeSettings.Current.IssuesConnections), mResolved);
  if mResolved.Provider <> '' then
  begin
    Result := [TAtlasNewIssueTracker.Create(CaptionOf(mConnection, mResolved), mResolved)];
    AIndex := 0;
  end;
  for mItem in TAtlasTrackerConnections.Read(TAtlasIdeSettings.Current.IssuesConnections) do
  begin
    if (mConnection <> '') and SameText(mItem.Name, mConnection) then
      Continue;
    mTarget := TAtlasTrackerTarget.Create(mItem.Provider, mItem.Url, '', '');
    mTarget.Language := mItem.Language;
    Result := Result + [TAtlasNewIssueTracker.Create(CaptionOf(mItem.Name, mTarget), mTarget)];
  end;
  if (AIndex < 0) and (Length(Result) > 0) then
    AIndex := 0;
end;

/// <summary>Ersetzt Zeile ALine (ab 1) der Ansicht durch ANew; ein Rückgängig-Schritt der IDE.</summary>
function WriteLine(const AView: IOTAEditView; ALine: Integer; const ANew: string): Boolean;
var
  mText: string;
  mFrom, mTill: Integer;
  mWriter: IOTAEditWriter;
begin
  Result := False;
  if (AView = nil) or AView.Buffer.IsReadOnly then
    Exit;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mFrom := TAtlasEditorBuffer.CharOffset(mText, ALine - 1, 0);
  mTill := TAtlasEditorBuffer.CharOffset(mText, ALine - 1, MaxInt div 2);
  mWriter := AView.Buffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(mText, 1, mFrom)));
  if mTill > mFrom then
    mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(mText, 1, mTill)));
  if ANew <> '' then
    mWriter.Insert(PAnsiChar(UTF8Encode(ANew)));
  mWriter := nil;
  // Eigener Schreibvorgang: Probleme und Inlay-Hints lesen den Puffer neu (P-04).
  TAtlasEditorSnapshots.Invalidate(AView.Buffer.FileName);
  AView.Paint;
  Result := True;
end;

/// <summary>Kennung in den Code: TODO ergänzen bzw. nach Rückfrage Kommentar anhängen. Nur, wenn Datei und
/// Zeile noch so dastehen wie beim Öffnen des Dialogs.</summary>
procedure MarkCode(const APlace: TEditorPlace; const AKey: string);
var
  mView: IOTAEditView;
  mLine, mNew: string;
  mTodo: TAtlasTodoComment;
begin
  if not APlace.Valid then
    Exit;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or not SameText(mView.Buffer.FileName, APlace.FileName) then
    Exit;
  mLine := TAtlasEditorBuffer.LineText(mView, APlace.Line);
  if mLine <> APlace.LineText then
    Exit;
  if TAtlasNewIssues.TodoAt(mLine, mTodo) then
  begin
    mNew := TAtlasNewIssues.WithKey(mLine, AKey);
    if (mNew <> mLine) and WriteLine(mView, APlace.Line, mNew) then
      Say(TAtlasStrings.Fmt(TAtlasTextId.NewIssueTodoChanged, [Trim(mNew)]));
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.NewIssueInsertComment, [TAtlasNewIssues.KeyComment(AKey)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  WriteLine(mView, APlace.Line, TAtlasNewIssues.WithKeyComment(mLine, AKey));
end;

procedure OpenPage(const APage: string);
begin
  if APage.StartsWith('https://', True) then
    ShellExecute(0, 'open', PChar(APage), nil, nil, SW_SHOWNORMAL);
end;

procedure Created(const AResult: TAtlasNewIssueResult; const ATitle: string; const APlace: TEditorPlace;
  AStartNow: Boolean);
var
  mPage, mText: string;
  mIssue: TAtlasTrackerIssue;
begin
  MarkCode(APlace, AResult.Key);
  try
    Clipboard.AsText := AResult.Key;
  except
    // Zwischenablage gerade von einem anderen Programm belegt: die Meldung nennt die Kennung trotzdem.
    on E: Exception do
      TAtlasGuard.Log('Issue anlegen: Zwischenablage belegt');
  end;
  mPage := AResult.Page;
  mText := TAtlasStrings.Fmt(TAtlasTextId.NewIssueCreated, [AResult.Key]);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.NewIssue, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.NewIssueCreatedTitle), mText,
    [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.NewIssueOpen),
    procedure
    begin
      OpenPage(mPage);
    end)]) = TAtlasNotificationMode.Show then
    Say(mText + ' ' + mPage);
  if AStartNow and (Issues <> nil) then
  begin
    mIssue := TAtlasTrackerIssue.Empty;
    mIssue.Key := AResult.Key;
    mIssue.Number := AResult.Number;
    mIssue.Title := ATitle;
    Issues.StartIssue(mIssue);
  end;
end;

procedure LoadFields(const ATarget: TAtlasTrackerTarget; const ADone: TAtlasNewIssueFieldsDone);
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mFields: TAtlasNewIssueFields;
  mLoaded: Boolean;
  mDone: TAtlasNewIssueFieldsDone;
begin
  if Issues = nil then
    Exit;
  mProvider := Issues.ProviderFor(ATarget.Provider);
  mTarget := ATarget;
  mFields := TAtlasNewIssueFields.Empty;
  mLoaded := False;
  mDone := ADone;
  RunInBackground(
    procedure
    begin
      mLoaded := TAtlasNewIssues.LoadFields(mProvider, mTarget, Issues.TransportFor(mProvider, mTarget), mFields);
    end,
    procedure
    begin
      mDone(mFields, mLoaded);
    end);
end;

procedure Send(const ATarget: TAtlasTrackerTarget; const ADraft: TAtlasNewIssueDraft;
  const ADone: TAtlasNewIssueSendDone);
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mDraft: TAtlasNewIssueDraft;
  mResult: TAtlasNewIssueResult;
  mDone: TAtlasNewIssueSendDone;
begin
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  if Issues = nil then
  begin
    ADone(mResult);
    Exit;
  end;
  mProvider := Issues.ProviderFor(ATarget.Provider);
  mTarget := ATarget;
  LastTarget := ATarget;
  mDraft := ADraft;
  mDone := ADone;
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Unreachable);
  RunInBackground(
    procedure
    begin
      mResult := TAtlasNewIssues.CreateIssue(mProvider, mTarget, Issues.TransportFor(mProvider, mTarget), mDraft);
    end,
    procedure
    begin
      // Anonym: Anbieter und Ergebnis, nie Adresse, Projekt, Titel oder Kennung.
      TAtlasGuard.Log('Issue anlegen: ' + mTarget.Provider + ', ' + cOutcomeKeys[mResult.Outcome]);
      mDone(mResult);
    end);
end;

/// <summary>Dialog zeigen und nach dem Anlegen die Kennung verteilen (Hauptthread).</summary>
procedure ShowDialog(const ASetup: TAtlasNewIssueSetup; const APlace: TEditorPlace);
var
  mResult: TAtlasNewIssueResult;
  mStartNow: Boolean;
begin
  if TAtlasNewIssueDialog.Execute(ASetup, LoadFields, Send, mResult, mStartNow) then
    Created(mResult, ASetup.Title, APlace, mStartNow);
end;

/// <summary>Branch und Commit des Ordners AFolder im Hintergrund, danach AThen im Hauptthread.</summary>
procedure WithHead(const AFolder: string; const AThen: TProc<string, string>);
var
  mBranch, mCommit: string;
  mThen: TProc<string, string>;
begin
  mBranch := '';
  mCommit := '';
  mThen := AThen;
  if (AFolder = '') or not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mHead: TAtlasVcsHead;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(AFolder, cVcsTimeoutMs);
      if (mVcs <> nil) and (mVcs.Head(mHead) = TAtlasVcsOutcome.Ok) then
      begin
        mBranch := mHead.Branch;
        mCommit := mHead.Revision;
      end;
    end,
    procedure
    begin
      mThen(mBranch, mCommit);
    end) then
    mThen('', '');
end;

/// <summary>Wie ShowDialog, danach „An Issue anhängen“ mit AFiles für das neue Issue (#1355).</summary>
procedure ShowDialogWithFiles(const ASetup: TAtlasNewIssueSetup; const AFiles: TArray<TAtlasAttachFile>);
var
  mResult: TAtlasNewIssueResult;
  mStartNow: Boolean;
  mPlace: TEditorPlace;
begin
  // Aus einem Fall ändert Atlas den Code nicht.
  mPlace := Default(TEditorPlace);
  if not TAtlasNewIssueDialog.Execute(ASetup, LoadFields, Send, mResult, mStartNow) then
    Exit;
  Created(mResult, ASetup.Title, mPlace, mStartNow);
  if (Length(AFiles) > 0) and (Issues <> nil) and (mResult.Key <> '') then
    Issues.AttachFiles(LastTarget, mResult.Key, AFiles);
end;

function NewSetup(const AProject: string): TAtlasNewIssueSetup;
begin
  Result := TAtlasNewIssueSetup.Empty;
  Result.Trackers := TrackersOf(AProject, Result.TrackerIndex);
  Result.IncludeCode := TAtlasIdeSettings.Current.IssuesCreateIncludeCode;
  Result.CanStart := (Issues <> nil) and Issues.CanStartIssue;
end;

{ TAtlasIdeNewIssue }

class procedure TAtlasIdeNewIssue.Start(AIssues: TAtlasIdeIssues; const AMessage: TProc<string>);
begin
  Issues := AIssues;
  IssuesRef := AIssues;
  Report := AMessage;
end;

class procedure TAtlasIdeNewIssue.Stop;
var
  mThread: TThread;
begin
  if Threads <> nil then
  begin
    // Höchstens die Zeitgrenze einer Anfrage (10 s); danach kommt kein Ergebnis mehr an.
    for mThread in Threads do
    begin
      mThread.WaitFor;
      mThread.Free;
    end;
    FreeAndNil(Threads);
  end;
  Issues := nil;
  IssuesRef := nil;
  Report := nil;
  LastTarget := Default(TAtlasTrackerTarget);
end;

class function TAtlasIdeNewIssue.Enabled: Boolean;
begin
  Result := (Issues <> nil) and TAtlasIdeSettings.Current.IssuesCreate;
end;

class procedure TAtlasIdeNewIssue.FromEditor;
var
  mView: IOTAEditView;
  mText, mProject: string;
  mContext: TAtlasNewIssueContext;
  mPlace: TEditorPlace;
  mBlock: IOTAEditBlock;
begin
  if not Enabled then
    Exit;
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.NewIssueNoEditor));
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mContext := TAtlasNewIssueContext.Empty;
  mContext.FileName := mView.Buffer.FileName;
  mContext.Line := mView.CursorPos.Line;
  mContext.Lines := TTextLines.SplitLines(mText);
  mContext.Method := TAtlasWelcomeContinue.MethodAt(mText, mContext.Line);
  mBlock := mView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) then
  begin
    mContext.Selection := mBlock.Text;
    mContext.SelectionLine := mBlock.StartingRow;
  end;
  mPlace := Default(TEditorPlace);
  mPlace.Valid := True;
  mPlace.FileName := mContext.FileName;
  mPlace.Line := mContext.Line;
  if (mContext.Line >= 1) and (mContext.Line <= Length(mContext.Lines)) then
    mPlace.LineText := mContext.Lines[mContext.Line - 1];
  mProject := TAtlasIdeTeamFile.ActiveProject;
  WithHead(ExtractFileDir(mContext.FileName),
    procedure(ABranch, ACommit: string)
    var
      mSetup: TAtlasNewIssueSetup;
      mFull: TAtlasNewIssueContext;
    begin
      if not Enabled then
        Exit;
      mFull := mContext;
      mFull.Branch := ABranch;
      mFull.Commit := ACommit;
      mSetup := NewSetup(mProject);
      mSetup.Title := TAtlasNewIssues.TitleOf(mFull);
      mSetup.Description := TAtlasNewIssues.DescriptionOf(mFull, Labels);
      mSetup.Code := TAtlasNewIssues.CodeOf(mFull);
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          ShowDialog(mSetup, mPlace);
        end);
    end);
end;

class procedure TAtlasIdeNewIssue.FromFindings(const AFindings: TArray<TAtlasNewIssueFinding>);
var
  mProject: string;
  mFindings: TArray<TAtlasNewIssueFinding>;
begin
  if not Enabled or (Length(AFindings) = 0) then
    Exit;
  mFindings := AFindings;
  mProject := TAtlasIdeTeamFile.ActiveProject;
  WithHead(ExtractFileDir(mProject),
    procedure(ABranch, ACommit: string)
    var
      mSetup: TAtlasNewIssueSetup;
      mContext: TAtlasNewIssueContext;
      mPlace: TEditorPlace;
    begin
      if not Enabled then
        Exit;
      mContext := TAtlasNewIssueContext.Empty;
      mContext.Branch := ABranch;
      mContext.Commit := ACommit;
      mSetup := NewSetup(mProject);
      mSetup.Title := TAtlasNewIssues.TitleOfFindings(mFindings, Labels);
      mSetup.Description := TAtlasNewIssues.DescriptionOfFindings(mFindings, mContext, Labels);
      mSetup.Code := TAtlasNewIssues.CodeOfFindings(mFindings);
      // Aus Befunden ändert Atlas den Code nicht.
      mPlace := Default(TEditorPlace);
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          ShowDialog(mSetup, mPlace);
        end);
    end);
end;

class procedure TAtlasIdeNewIssue.FromCrash(const ATitle, ADescription: string;
  const AFiles: TArray<TAtlasAttachFile>);
var
  mProject, mTitle, mDescription: string;
  mFiles: TArray<TAtlasAttachFile>;
begin
  if not Enabled then
    Exit;
  mTitle := ATitle;
  mDescription := ADescription;
  mFiles := AFiles;
  mProject := TAtlasIdeTeamFile.ActiveProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mSetup: TAtlasNewIssueSetup;
    begin
      mSetup := NewSetup(mProject);
      mSetup.Title := mTitle;
      mSetup.Description := mDescription;
      ShowDialogWithFiles(mSetup, mFiles);
    end);
end;

end.
