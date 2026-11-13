unit Atlas.IDE.Tracker.NewIssue;

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
// Base erreicht „Issue anlegen“ über IAtlasIssueCreation (TAtlasIdeIssueCreation,
// bereitgestellt von der Komposition des Moduls, #1455).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tracker.NewIssue,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Tracker.MyIssues;

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

  /// <summary>„Issue anlegen“ für Base (#1268, #1355): wandelt die Records des Vertrags und ruft
  /// TAtlasIdeNewIssue; ohne Start bzw. mit issues.create aus wirkungslos. Hauptthread.</summary>
  TAtlasIdeIssueCreation = class(TInterfacedObject, IAtlasIssueCreation)
  public
    function Enabled: Boolean;
    procedure FromFindings(const AFindings: TArray<TAtlasIssueFinding>);
    procedure FromCrash(const ATitle, ADescription: string; const AFiles: TArray<TAtlasIssueTextFile>);
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.NewIssue.Strings,
  Atlas.UI.Tracker.NewIssueDialog,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.NewIssuePlace,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files;

const
  cVcsTimeoutMs = 2000;
  cOutcomeKeys: array[TAtlasNewIssueOutcome] of string = ('created', 'noToken', 'notConfigured', 'rejected',
    'projectUnknown', 'invalid', 'unreadable', 'serverError', 'unreachable');
  cLogAborted = 'Issue anlegen: Anfrage mit %s abgebrochen';
  cLogClipboard = 'Issue anlegen: Zwischenablage belegt';
  cLogOutcome = 'Issue anlegen: %s, %s';

var
  Issues: TAtlasIdeIssues;
  IssuesRef: IInterface;
  Report: TProc<string>;
  Threads: TList<TThread>;
  /// <summary>Tracker der letzten Sendung (Send): Dorthin gehen danach die Dateien eines Absturzfalls.</summary>
  LastTarget: TAtlasTrackerTarget;

function Labels: TAtlasNewIssueLabels;
begin
  Result.Location := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelLocation);
  Result.Line := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelLine);
  Result.Method := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelMethod);
  Result.Branch := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelBranch);
  Result.Commit := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelCommit);
  Result.Findings := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueLabelFindings);
  Result.FindingsTitle := TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueFindingsTitle);
end;

procedure Say(const AText: string);
begin
  if Assigned(Report) then
  begin
    Report(AText);
  end;
end;

/// <summary>AWork im Hintergrund, danach ADone über TAtlasMainThread; beim Entladen verfällt ADone.</summary>
procedure RunInBackground(const AWork: TProc; const ADone: TProc);
var
  mThread: TThread;
begin
  if Threads = nil then
  begin
    Threads := TList<TThread>.Create;
  end;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AWork();
      except
        on E: Exception do
          TAtlasGuard.Log(Format(cLogAborted, [E.ClassName], TFormatSettings.Invariant));
      end;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Tracker,
        procedure
        begin
          if (Threads = nil) or not Threads.Contains(mThread) then
          begin
            Exit;
          end;
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
  if SameText(ATarget.Provider, TAtlasTrackerTarget.cGitHub) then
  begin
    mProvider := 'GitHub';
  end
  else
  begin
    mProvider := 'YouTrack';
  end;
  Result := mProvider + ' · ' + ATarget.Server;
  if AConnection <> '' then
  begin
    Result := AConnection + ' (' + Result + ')';
  end;
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
  mResolved := TAtlasIdeIssuesTargets.TrackerOf(AProject, mConnection);
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
    begin
      Continue;
    end;
    mTarget := TAtlasTrackerTarget.Create(mItem.Provider, mItem.Url, '', '');
    mTarget.Language := mItem.Language;
    Result := Result + [TAtlasNewIssueTracker.Create(CaptionOf(mItem.Name, mTarget), mTarget)];
  end;
  if (AIndex < 0) and (Length(Result) > 0) then
  begin
    AIndex := 0;
  end;
end;

procedure OpenPage(const APage: string);
begin
  if APage.StartsWith('https://', True) then
  begin
    TAtlasTrackerFiles.Shell.Open(APage);
  end;
end;

procedure Created(const AResult: TAtlasNewIssueResult; const ATitle: string; const APlace: TAtlasNewIssuePlace;
  AStartNow: Boolean);
var
  mPage, mText: string;
  mIssue: TAtlasTrackerIssue;
begin
  APlace.Mark(AResult.Key,
    procedure(AText: string)
    begin
      Say(AText);
    end);
  try
    Clipboard.AsText := AResult.Key;
  except
    // Zwischenablage gerade von einem anderen Programm belegt: die Meldung nennt die Kennung trotzdem.
    on E: Exception do
      TAtlasGuard.Log(cLogClipboard);
  end;
  mPage := AResult.Page;
  mText := TAtlasNewIssueStrings.Fmt(TAtlasNewIssueTextId.NewIssueCreated, [AResult.Key]);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cNewIssue, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Text(TAtlasTextId.NewIssueCreatedTitle), mText,
    [TAtlasNotificationCenter.Action(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueOpen),
    procedure
    begin
      OpenPage(mPage);
    end)]) = TAtlasNotificationMode.Show then
  begin
    Say(mText + ' ' + mPage);
  end;
  if AStartNow and (Issues <> nil) then
  begin
    mIssue := TAtlasTrackerIssue.Empty;
    mIssue.Key := AResult.Key;
    mIssue.Number := AResult.Number;
    mIssue.Title := ATitle;
    Issues.Commands.StartIssue(mIssue);
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
  begin
    Exit;
  end;
  mProvider := Issues.Context.ProviderOf(ATarget.Provider);
  mTarget := ATarget;
  mFields := TAtlasNewIssueFields.Empty;
  mLoaded := False;
  mDone := ADone;
  RunInBackground(
    procedure
    begin
      mLoaded := TAtlasNewIssues.LoadFields(mProvider, mTarget, Issues.Context.TransportOf(mProvider, mTarget),
        mFields);
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
  mProvider := Issues.Context.ProviderOf(ATarget.Provider);
  mTarget := ATarget;
  LastTarget := ATarget;
  mDraft := ADraft;
  mDone := ADone;
  mResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Unreachable);
  RunInBackground(
    procedure
    begin
      mResult := TAtlasNewIssues.CreateIssue(mProvider, mTarget, Issues.Context.TransportOf(mProvider, mTarget),
        mDraft);
    end,
    procedure
    begin
      // Anonym: Anbieter und Ergebnis, nie Adresse, Projekt, Titel oder Kennung.
      TAtlasGuard.Log(Format(cLogOutcome, [mTarget.Provider, cOutcomeKeys[mResult.Outcome]],
        TFormatSettings.Invariant));
      mDone(mResult);
    end);
end;

/// <summary>Dialog zeigen und nach dem Anlegen die Kennung verteilen (Hauptthread).</summary>
procedure ShowDialog(const ASetup: TAtlasNewIssueSetup; const APlace: TAtlasNewIssuePlace);
var
  mResult: TAtlasNewIssueResult;
  mStartNow: Boolean;
begin
  if TAtlasNewIssueDialog.Execute(ASetup, LoadFields, Send, mResult, mStartNow) then
  begin
    Created(mResult, ASetup.Title, APlace, mStartNow);
  end;
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
  begin
    mThen('', '');
  end;
end;

/// <summary>Wie ShowDialog, danach „An Issue anhängen“ mit AFiles für das neue Issue (#1355).</summary>
procedure ShowDialogWithFiles(const ASetup: TAtlasNewIssueSetup; const AFiles: TArray<TAtlasAttachFile>);
var
  mResult: TAtlasNewIssueResult;
  mStartNow: Boolean;
  mPlace: TAtlasNewIssuePlace;
begin
  // Aus einem Fall ändert Atlas den Code nicht.
  mPlace := TAtlasNewIssuePlace.None;
  if not TAtlasNewIssueDialog.Execute(ASetup, LoadFields, Send, mResult, mStartNow) then
  begin
    Exit;
  end;
  Created(mResult, ASetup.Title, mPlace, mStartNow);
  if (Length(AFiles) > 0) and (Issues <> nil) and (mResult.Key <> '') then
  begin
    Issues.Commands.AttachFiles(LastTarget, mResult.Key, AFiles);
  end;
end;

function NewSetup(const AProject: string): TAtlasNewIssueSetup;
begin
  Result := TAtlasNewIssueSetup.Empty;
  Result.Trackers := TrackersOf(AProject, Result.TrackerIndex);
  Result.IncludeCode := TAtlasIdeSettings.Current.IssuesCreateIncludeCode;
  Result.CanStart := (Issues <> nil) and Issues.Context.CanStart;
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
  mProject: string;
  mContext: TAtlasNewIssueContext;
  mPlace: TAtlasNewIssuePlace;
begin
  if not Enabled then
  begin
    Exit;
  end;
  if not TAtlasNewIssuePlace.Capture(mPlace, mContext) then
  begin
    Say(TAtlasNewIssueStrings.Text(TAtlasNewIssueTextId.NewIssueNoEditor));
    Exit;
  end;
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  WithHead(ExtractFileDir(mContext.FileName),
    procedure(ABranch, ACommit: string)
    var
      mSetup: TAtlasNewIssueSetup;
      mFull: TAtlasNewIssueContext;
    begin
      if not Enabled then
      begin
        Exit;
      end;
      mFull := mContext;
      mFull.Branch := ABranch;
      mFull.Commit := ACommit;
      mSetup := NewSetup(mProject);
      mSetup.Title := TAtlasNewIssues.TitleOf(mFull);
      mSetup.Description := TAtlasNewIssues.DescriptionOf(mFull, Labels);
      mSetup.Code := TAtlasNewIssues.CodeOf(mFull);
      TAtlasGuard.Run(TAtlasFeature.Tracker,
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
  begin
    Exit;
  end;
  mFindings := AFindings;
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  WithHead(ExtractFileDir(mProject),
    procedure(ABranch, ACommit: string)
    var
      mSetup: TAtlasNewIssueSetup;
      mContext: TAtlasNewIssueContext;
      mPlace: TAtlasNewIssuePlace;
    begin
      if not Enabled then
      begin
        Exit;
      end;
      mContext := TAtlasNewIssueContext.Empty;
      mContext.Branch := ABranch;
      mContext.Commit := ACommit;
      mSetup := NewSetup(mProject);
      mSetup.Title := TAtlasNewIssues.TitleOfFindings(mFindings, Labels);
      mSetup.Description := TAtlasNewIssues.DescriptionOfFindings(mFindings, mContext, Labels);
      mSetup.Code := TAtlasNewIssues.CodeOfFindings(mFindings);
      // Aus Befunden ändert Atlas den Code nicht.
      mPlace := TAtlasNewIssuePlace.None;
      TAtlasGuard.Run(TAtlasFeature.Tracker,
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
  begin
    Exit;
  end;
  mTitle := ATitle;
  mDescription := ADescription;
  mFiles := AFiles;
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  TAtlasGuard.Run(TAtlasFeature.Tracker,
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

{ TAtlasIdeIssueCreation }

function TAtlasIdeIssueCreation.Enabled: Boolean;
begin
  Result := TAtlasIdeNewIssue.Enabled;
end;

procedure TAtlasIdeIssueCreation.FromFindings(const AFindings: TArray<TAtlasIssueFinding>);
var
  mItems: TArray<TAtlasNewIssueFinding>;
  mIndex: Integer;
begin
  if not Enabled then
  begin
    Exit;
  end;
  SetLength(mItems, Length(AFindings));
  for mIndex := 0 to High(AFindings) do
  begin
    mItems[mIndex] := TAtlasNewIssueFinding.Create(AFindings[mIndex].Rule, AFindings[mIndex].Message,
      AFindings[mIndex].Location, AFindings[mIndex].LineText);
  end;
  TAtlasIdeNewIssue.FromFindings(mItems);
end;

procedure TAtlasIdeIssueCreation.FromCrash(const ATitle, ADescription: string;
  const AFiles: TArray<TAtlasIssueTextFile>);
var
  mFiles: TArray<TAtlasAttachFile>;
  mIndex: Integer;
begin
  if not Enabled then
  begin
    Exit;
  end;
  SetLength(mFiles, Length(AFiles));
  for mIndex := 0 to High(AFiles) do
  begin
    mFiles[mIndex] := TAtlasAttachFile.CreateText(TAtlasAttachKind.LogFile, AFiles[mIndex].Name, AFiles[mIndex].Text);
  end;
  TAtlasIdeNewIssue.FromCrash(ATitle, ADescription, mFiles);
end;

end.
