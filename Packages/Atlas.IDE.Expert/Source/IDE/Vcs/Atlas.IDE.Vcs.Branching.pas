unit Atlas.IDE.Vcs.Branching;

// „Branch anlegen“ in der IDE (#1288).
// - Ask: Dialog „Branch anlegen“ (TAtlasBranchDialog, modal, Thema der IDE).
//   Braucht der Plan Werte vom Server (SVN: HEAD-Revision des Hauptbranchs),
//   holt sie TAtlasIdeVcs.Run im Hintergrund mit dem Zeitlimit aus #1285;
//   bis dahin „wird ermittelt …“. Ein spätes Ergebnis nach dem Schließen
//   verfällt.
// - Befehl „Branch anlegen …“ (Atlas.CreateBranch, Befehlspalette und
//   Kontextmenü von „Projekte“): ohne Issue, Name leer, Dialog immer
//   (ausdrücklicher Aufruf, unabhängig von vcs.branch.confirm). Gibt es den
//   Branch schon, legt Atlas nichts an und meldet das.
// - Ausführen im Hintergrund, je Schritt eine Zeile in der Meldungsansicht;
//   scheitert ein Schritt, nennt die Meldung Schritt, Grund und die schon auf
//   dem Server ausgeführten Schritte (nichts wird zurückgerollt).
// - „Nicht mehr fragen, Vorgaben verwenden“ setzt vcs.branch.confirm aus
//   (StopAsking).
// - Git-Optionen (#1289, vcs.branch.git.*, GitOptions) belegen den Dialog vor.
//   Scheitert der Abruf vor dem Anlegen (Basis vom Server), fragt Atlas nach
//   dem Dialog „Vom lokalen Stand abzweigen?“ mit dem Zustand des Servers
//   (#1287) und legt nach Zustimmung ohne Abruf an (AskLocal). Scheitert nur
//   der Push, bleibt der Branch und die Meldung nennt den Grund. Mit worktree
//   bietet Atlas danach an, dieselbe .groupproj bzw. .dproj aus dem neuen
//   Ordner zu öffnen (OfferWorktree); gibt es den Ordner schon, legt Atlas
//   nichts an.
// Protokoll anonym: nur Art und Ergebnis, nie Name, Basis oder Pfad.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan;

type
  TAtlasIdeBranching = class
  private
    /// <summary>Anfrage im Hintergrund ausführen und melden (#1288); AOfferLocal: nach gescheitertem Abruf
    /// „Vom lokalen Stand abzweigen?“ (#1289).</summary>
    class procedure RunCreate(const AProject: string; const AFacts: TAtlasVcsBranchFacts;
      const ARequest: TAtlasVcsBranchRequest; AOfferLocal: Boolean; const ADone: TProc); static;
  public const
    /// <summary>Zeitlimit je Aufruf beim Anlegen (wie „Beginnen“, #765); vcs.timeoutSeconds, wenn größer.</summary>
    TimeoutMs = 30000;
  public
    /// <summary>Dialog zeigen (Hauptthread). True mit ARequest bei „Anlegen“; ANeverAsk, wenn „Nicht mehr fragen“
    /// gesetzt war (nur mit AOfferNeverAsk).</summary>
    class function Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean; overload;
      static;
    /// <summary>Wie oben mit der Kennung des Issues für {kennung} im worktree-Ordner (#1289); die Git-Vorgaben
    /// kommen aus GitOptions.</summary>
    class function Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
      AKey: string; AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
      overload; static;
    /// <summary>Git-Vorgaben aus vcs.branch.git.* (#1289).</summary>
    class function GitOptions: TAtlasVcsGitBranchOptions; static;
    /// <summary>Zustand des Servers in Worten wie auf der Seite Versionsverwaltung (#1287).</summary>
    class function ServerState(AOutcome: TAtlasVcsOutcome): string; static;
    /// <summary>Nach gescheitertem Abruf (FetchFailed, Hauptthread): „Vom lokalen Stand abzweigen?“; True mit
    /// AFallback (ohne Abruf, Basis wie bei base = local) bei „Ja“.</summary>
    class function AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
      out AFallback: TAtlasVcsBranchRequest): Boolean; static;
    /// <summary>vcs.branch.git.uncommitted = ask ohne Dialog (Hauptthread): mitnehmen (AStash False),
    /// beiseitelegen (True) oder abbrechen (Result False).</summary>
    class function AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean; static;
    /// <summary>Projekt im neuen worktree: die .groupproj von AProject, wenn sie unter ARoot liegt, sonst
    /// AProject; '' wenn nichts unter ARoot liegt.</summary>
    class function WorktreeProject(const AProject, ARoot, AFolder: string): string; static;
    /// <summary>Nach dem Anlegen im worktree (Hauptthread): fragen, ob ATarget geöffnet werden soll.</summary>
    class function OfferWorktree(const AName, AFolder, ATarget: string): Boolean; static;
    /// <summary>Projekt bzw. Gruppe in der IDE öffnen.</summary>
    class procedure OpenProject(const AFile: string); static;
    /// <summary>vcs.branch.confirm aus: „Beginnen“ legt danach ohne Dialog mit den Vorgaben an.</summary>
    class procedure StopAsking; static;
    /// <summary>Befehl „Branch anlegen …“ für AProject (.dproj bzw. .groupproj); ADone im Hauptthread nach
    /// erfolgreichem Anlegen (z. B. „Projekte“ neu abfragen).</summary>
    class procedure CreateFor(const AProject: string; const ADone: TProc); static;
    /// <summary>Kandidaten für den Hauptbranch wie bei „Beginnen“: issues.branchBase, sonst Hauptbranch des
    /// Projekts (#1286), sonst geraten.</summary>
    class function Candidates(AKind: TAtlasVcsKind; const AProject: string): TArray<string>; static;
    /// <summary>Zeile für die Meldungsansicht vor Schritt AIndex.</summary>
    class function ProgressText(AKind: TAtlasVcsKind; AIndex, ACount: Integer;
      const AStep: TAtlasVcsBranchStep): string; static;
    /// <summary>Fortschritt für TAtlasVcsBranchPlan.Execute: je Schritt ProgressText in die Meldungsansicht.
    /// </summary>
    class function Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress; static;
    /// <summary>Meldung nach einem Fehler: Schritt, Grund und schon auf dem Server Ausgeführtes.</summary>
    class function FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): string; static;
  end;

implementation

uses
  System.UITypes,
  System.Classes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.StdCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Welcome.Issues,
  Atlas.UI.Strings,
  Atlas.UI.Vcs.BranchDialog,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

class function TAtlasIdeBranching.Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage: string; AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
begin
  Result := Ask(AFolder, AFacts, AName, AMessage, '', AOfferNeverAsk, ARequest, ANeverAsk);
end;

class function TAtlasIdeBranching.Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage, AKey: string; AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest;
  out ANeverAsk: Boolean): Boolean;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mFolder: string;
  mOpen: Boolean;
begin
  ARequest := Default(TAtlasVcsBranchRequest);
  ANeverAsk := False;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, AFacts, AName, AMessage, AKey, GitOptions, AOfferNeverAsk);
  try
    TAtlasIdeDockWindow.ApplyIdeTheme(mDialog);
    mOpen := True;
    if AFacts.NeedsServer then
    begin
      mFacts := AFacts;
      mFolder := AFolder;
      // Arbeit und Ergebnis teilen sich mFacts; das Ergebnis kommt erst nach der Arbeit, nach dem Schließen nie
      // an den Dialog.
      if not TAtlasIdeVcs.Run(
        procedure
        begin
          TAtlasVcsBranchPlan.InspectServer(TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(TimeoutMs)), mFacts);
        end,
        procedure
        begin
          if mOpen then
            mDialog.Loaded(mFacts);
        end) then
      begin
        mFacts.ServerChecked := True;
        mFacts.ServerOutcome := TAtlasVcsOutcome.Failed;
        mDialog.Loaded(mFacts);
      end;
    end;
    Result := mDialog.ShowModal = mrOk;
    mOpen := False;
    if Result then
    begin
      ARequest := mDialog.Request;
      ANeverAsk := mDialog.NeverAsk.Visible and mDialog.NeverAsk.Checked;
    end;
  finally
    mOpen := False;
    mDialog.Free;
  end;
end;

class procedure TAtlasIdeBranching.StopAsking;
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  if not mNext.VcsBranchConfirm then
    Exit;
  mNext.VcsBranchConfirm := False;
  TAtlasIdeSettings.Update(mNext);
  TAtlasGuard.Log('Branch anlegen: Dialog abgeschaltet (vcs.branch.confirm)');
end;

class function TAtlasIdeBranching.GitOptions: TAtlasVcsGitBranchOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasVcsGitBranchOptions.FromSettings(mSettings.VcsBranchGitBase, mSettings.VcsBranchGitPush,
    mSettings.VcsBranchGitUncommitted, mSettings.VcsBranchGitWorktree, mSettings.VcsBranchGitWorktreeFolder);
end;

class function TAtlasIdeBranching.ServerState(AOutcome: TAtlasVcsOutcome): string;
begin
  case AOutcome of
    TAtlasVcsOutcome.LoginNeeded:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerToolMissing);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnreachable);
  end;
end;

class function TAtlasIdeBranching.AskLocal(const AFacts: TAtlasVcsBranchFacts;
  const ARequest: TAtlasVcsBranchRequest; const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
  out AFallback: TAtlasVcsBranchRequest): Boolean;
begin
  AFallback := ARequest;
  if not TAtlasVcsBranchPlan.FetchFailed(ASteps, ARun) then
    Exit(False);
  AFallback := TAtlasVcsBranchPlan.LocalFallback(AFacts, ARequest);
  Result := MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFetchFailedAsk, [ARequest.Base.RemoteName,
    ServerState(ARun.Outcome), sLineBreak + sLineBreak, TAtlasVcsBranchPlan.BaseName(AFallback.Kind,
    AFallback.Base)]), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  TAtlasGuard.Log(Format('Branch anlegen: Abruf gescheitert (%s), lokal weiter: %s',
    [AtlasVcsOutcomeName(ARun.Outcome), BoolToStr(Result, True)]));
end;

class function TAtlasIdeBranching.AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
var
  mDialog: TForm;
  mButton: TComponent;
  mAnswer: Integer;
begin
  AStash := False;
  mAnswer := mrCancel;
  mDialog := CreateMessageDialog(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchUncommittedAsk, [AChanges, AName, AName]),
    mtConfirmation, [mbYes, mbNo, mbCancel], mbYes);
  try
    // Eigene Beschriftungen statt Ja/Nein: mitnehmen, beiseitelegen, abbrechen.
    mButton := mDialog.FindComponent('Yes');
    if mButton is TButton then
      TButton(mButton).Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchCarry);
    mButton := mDialog.FindComponent('No');
    if mButton is TButton then
      TButton(mButton).Caption := TAtlasStrings.Text(TAtlasTextId.VcsBranchStashShort);
    mButton := mDialog.FindComponent('Cancel');
    if mButton is TButton then
      TButton(mButton).Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
    TAtlasIdeDockWindow.ApplyIdeTheme(mDialog);
    mAnswer := mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
  Result := (mAnswer = mrYes) or (mAnswer = mrNo);
  AStash := mAnswer = mrNo;
end;

class function TAtlasIdeBranching.WorktreeProject(const AProject, ARoot, AFolder: string): string;
var
  mGroup: string;
begin
  // Dieselbe Gruppe, wenn sie im Repository liegt; sonst das Projekt selbst.
  mGroup := TAtlasIdeFiles.GroupOfProject(AProject);
  Result := '';
  if mGroup <> '' then
    Result := TAtlasVcsBranchPlan.ProjectInFolder(mGroup, ARoot, AFolder);
  if Result = '' then
    Result := TAtlasVcsBranchPlan.ProjectInFolder(AProject, ARoot, AFolder);
end;

class function TAtlasIdeBranching.OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
begin
  Result := (ATarget <> '') and FileExists(ATarget) and (MessageDlg(TAtlasStrings.Fmt(
    TAtlasTextId.VcsBranchWorktreeOpen, [AName, AFolder, sLineBreak + sLineBreak, ExtractFileName(ATarget)]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

class function TAtlasIdeBranching.Candidates(AKind: TAtlasVcsKind; const AProject: string): TArray<string>;
begin
  Result := TAtlasTrackerNaming.Bases(AKind = TAtlasVcsKind.Svn, TAtlasIdeSettings.Current.IssuesBranchBase,
    TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject)));
end;

class function TAtlasIdeBranching.ProgressText(AKind: TAtlasVcsKind; AIndex, ACount: Integer;
  const AStep: TAtlasVcsBranchStep): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchProgress, [AIndex + 1, ACount,
    TAtlasVcsBranchPlan.StepText(AKind, AStep)]);
end;

class function TAtlasIdeBranching.Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
begin
  // Eigene Routine: Die Methodenreferenz fängt nur AKind ein.
  Result :=
    procedure(AIndex, ACount: Integer; const AStep: TAtlasVcsBranchStep)
    begin
      TAtlasIdeVcs.Report(ProgressText(AKind, AIndex, ACount, AStep));
    end;
end;

class function TAtlasIdeBranching.FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): string;
var
  mDone: TArray<TAtlasVcsBranchStep>;
  mStep: TAtlasVcsBranchStep;
  mList: string;
begin
  if (ARun.Failed >= 0) and (ARun.Failed <= High(ASteps)) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchStepFailed, [ARun.Failed + 1,
      TAtlasVcsBranchPlan.StepText(AKind, ASteps[ARun.Failed]), AtlasVcsOutcomeName(ARun.Outcome)])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFailed, [AtlasVcsOutcomeName(ARun.Outcome)]);
  mDone := TAtlasVcsBranchPlan.ServerStepsDone(ASteps, ARun.Done);
  if Length(mDone) = 0 then
    Exit;
  mList := '';
  for mStep in mDone do
  begin
    if mList <> '' then
      mList := mList + '; ';
    mList := mList + TAtlasVcsBranchPlan.StepText(AKind, mStep);
  end;
  Result := Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.VcsBranchServerDone, [mList]);
end;

class procedure TAtlasIdeBranching.CreateFor(const AProject: string; const ADone: TProc);
var
  mProject, mFolder: string;
  mFacts: TAtlasVcsBranchFacts;
  mBaseText: string;
  mDone: TProc;
begin
  mProject := AProject;
  mFolder := ExtractFileDir(AProject);
  mDone := ADone;
  if mFolder = '' then
    Exit;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mBaseText := TAtlasIdeSettings.Current.IssuesBranchBase;
  // Stand der Arbeitskopie im Hintergrund, dann der Dialog im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mKind: TAtlasVcsKind;
      mItems: TArray<TAtlasVcsChange>;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(TimeoutMs));
      mKind := TAtlasVcsKind.None;
      if mVcs <> nil then
        mKind := mVcs.Kind;
      mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TAtlasTrackerNaming.Bases(mKind = TAtlasVcsKind.Svn, mBaseText,
        TAtlasIdeVcs.MainBranchOf(mProject, TAtlasIdeFiles.GroupOfProject(mProject))));
      // Geänderte Dateien für die Zeile „Offene Änderungen“ im Dialog (#1289).
      if (mFacts.Outcome = TAtlasVcsOutcome.Ok) and (mVcs.Changes(mItems) = TAtlasVcsOutcome.Ok) then
        mFacts.LocalChanges := TAtlasWelcomeIssues.LocalChanges(mItems);
    end,
    procedure
    var
      mRequest: TAtlasVcsBranchRequest;
      mNever: Boolean;
    begin
      if (mFacts.Kind <> TAtlasVcsKind.Git) and (mFacts.Kind <> TAtlasVcsKind.Svn) then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
        Exit;
      end;
      if Ask(mFolder, mFacts, '', '', '', False, mRequest, mNever) then
        RunCreate(mProject, mFacts, mRequest, True, mDone);
    end) then
    TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
end;

class procedure TAtlasIdeBranching.RunCreate(const AProject: string; const AFacts: TAtlasVcsBranchFacts;
  const ARequest: TAtlasVcsBranchRequest; AOfferLocal: Boolean; const ADone: TProc);
var
  mProject, mFolder: string;
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
  mExists, mTaken, mOfferLocal: Boolean;
  mDone: TProc;
begin
  mProject := AProject;
  mFolder := ExtractFileDir(AProject);
  mFacts := AFacts;
  mRequest := ARequest;
  mOfferLocal := AOfferLocal;
  mDone := ADone;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  mExists := False;
  mTaken := False;
  mRun := Default(TAtlasVcsBranchRun);
  mRun.Failed := -1;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mBranching: IAtlasVcsBranching;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(TimeoutMs));
      if (mVcs = nil) or not Supports(mVcs, IAtlasVcsBranching, mBranching) then
      begin
        mRun.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
        mRun.Failed := 0;
        Exit;
      end;
      mRun.Outcome := mBranching.BranchExists(mRequest.Name, mExists);
      if (mRun.Outcome <> TAtlasVcsOutcome.Ok) or mExists then
        Exit;
      // Eigener Ordner (#1289): gibt es ihn schon, nichts anlegen.
      mTaken := (mRequest.WorktreeFolder <> '') and DirectoryExists(mRequest.WorktreeFolder);
      if mTaken then
        Exit;
      mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps, Progress(mRequest.Kind));
    end,
    procedure
    var
      mFallback: TAtlasVcsBranchRequest;
      mTarget: string;
    begin
      TAtlasGuard.Log(Format('Branch anlegen (Befehl): %s, %s', [AtlasVcsKindName(mRequest.Kind),
        AtlasVcsOutcomeName(mRun.Outcome)]));
      if mExists then
        TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchExists, [mRequest.Name]))
      else if mTaken then
        TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [mRequest.WorktreeFolder]))
      else if mRun.Succeeded or TAtlasVcsBranchPlan.OnlyPushFailed(mSteps, mRun) then
      begin
        if mRequest.WorktreeFolder <> '' then
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [mRequest.Name,
            TAtlasVcsBranchPlan.BaseName(mRequest.Kind, mRequest.Base), mRequest.WorktreeFolder]))
        else
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchCreated, [mRequest.Name,
            TAtlasVcsBranchPlan.BaseName(mRequest.Kind, mRequest.Base)]));
        // Nur der Push scheiterte: der lokale Branch bleibt.
        if not mRun.Succeeded then
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [mRequest.Name,
            ServerState(mRun.Outcome)]));
        if Assigned(mDone) then
          mDone();
        if mRequest.WorktreeFolder <> '' then
        begin
          mTarget := WorktreeProject(mProject, mFacts.Root, mRequest.WorktreeFolder);
          if OfferWorktree(mRequest.Name, mRequest.WorktreeFolder, mTarget) then
            OpenProject(mTarget);
        end;
      end
      // Abruf gescheitert, noch nichts geändert: nach Rückfrage vom lokalen Stand, ohne erneute Rückfrage.
      else if mOfferLocal and AskLocal(mFacts, mRequest, mSteps, mRun, mFallback) then
        RunCreate(mProject, mFacts, mFallback, False, mDone)
      else
        TAtlasIdeVcs.Report(FailureText(mRequest.Kind, mSteps, mRun));
    end) then
    TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFailed,
      [AtlasVcsOutcomeName(TAtlasVcsOutcome.Failed)]));
end;

class procedure TAtlasIdeBranching.OpenProject(const AFile: string);
var
  mActions: IOTAActionServices;
begin
  if FileExists(AFile) and Supports(BorlandIDEServices, IOTAActionServices, mActions) then
    mActions.OpenProject(AFile, True);
end;

end.
