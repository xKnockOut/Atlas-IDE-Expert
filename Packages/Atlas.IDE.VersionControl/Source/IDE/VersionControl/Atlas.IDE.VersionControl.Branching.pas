unit Atlas.IDE.VersionControl.Branching;

// „Branch anlegen“ in der IDE (#1288).
// - Ask: Dialog „Branch anlegen“ (TAtlasBranchDialog, modal, Thema der IDE).
//   Braucht der Plan Werte vom Server (SVN: HEAD-Revision des Hauptbranchs),
//   holt sie TAtlasIdeVcsCore.Run im Hintergrund mit dem Zeitlimit aus #1285;
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
// - SVN (#1290): SvnOptions liest vcs.branch.svn.* (Ort, Quelle, Danach,
//   Ordner, Nachricht) als Vorgaben für Dialog und „Beginnen“; nach
//   „frisch auschecken“ bietet OfferOpen an, dieselbe Gruppe im neuen Ordner
//   zu öffnen.
// - Externals (#1291): SvnOptions liest dazu vcs.externals.* (Vorgabe ohne
//   Revision, Vorschlag „mitverzweigen“, Regeln). Hat der Branch Externals
//   festgeschrieben bzw. mitverzweigt und wurde umgeschaltet, holt svn die
//   Externals des Branchs; RebuildIndex schickt dann atlas.server.rebuildIndex
//   über den Befehlsweg, den die Komposition in ServerCommand setzt.
// Protokoll anonym: nur Art und Ergebnis, nie Name, Basis oder Pfad.

interface

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.ExternalRules,
  Atlas.UI.VersionControl.BranchDialog;

type
  TAtlasIdeBranching = class
  private
    /// <summary>Anfrage im Hintergrund ausführen und melden (#1288); AOfferLocal: nach gescheitertem Abruf
    /// „Vom lokalen Stand abzweigen?“ (#1289).</summary>
    class procedure RunCreate(const AProject: string; const AFacts: TAtlasVcsBranchFacts;
      const ARequest: TAtlasVcsBranchRequest; const ASvn: TAtlasVcsSvnBranchOptions; AOfferLocal: Boolean;
      const ADone: TProc); static;
  public const
    /// <summary>Zeitlimit je Aufruf beim Anlegen (wie „Beginnen“, #765); vcs.timeoutSeconds, wenn größer.</summary>
    cTimeoutMs = 30000;
  private
    class var FServerCommand: TFunc<string, Boolean>;
  public
    /// <summary>Befehl an den Atlas-Server abschicken (#1291, aus der Komposition; True, wenn angenommen). Beim
    /// Entladen nil.</summary>
    class property ServerCommand: TFunc<string, Boolean> read FServerCommand write FServerCommand;
    /// <summary>Nach einem Branch mit geänderten Externals (#1291, Hauptthread): Index neu aufbauen und das in
    /// der Meldungsansicht sagen; ohne Server nichts.</summary>
    class procedure RebuildIndex; static;
    /// <summary>Dialog zeigen (Hauptthread) mit den Vorgaben aus ASetup (Git meist aus GitOptions, SVN aus
    /// SvnOptions). True mit ARequest bei „Anlegen“; ANeverAsk, wenn „Nicht mehr fragen“ gesetzt war (nur mit
    /// ASetup.OfferNeverAsk).</summary>
    class function Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts;
      const ASetup: TAtlasBranchDialogSetup; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
      static;
    /// <summary>Vorgaben für Ask: Git aus GitOptions, SVN aus ASvn.</summary>
    class function Setup(const AName, AMessage, AKey: string; const ASvn: TAtlasVcsSvnBranchOptions;
      AOfferNeverAsk: Boolean): TAtlasBranchDialogSetup; static;
    /// <summary>SVN-Optionen aus den Einstellungen (vcs.branch.svn.*, #1290); Projekt = Name der Gruppe von
    /// AProject (sonst des Projekts), Kennung und Titel leer.</summary>
    class function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions; static;
    /// <summary>Nach „frisch auschecken“ (#1290, Hauptthread): fragen, ob dieselbe Gruppe (bzw. AProject) im
    /// neuen Ordner AFolder geöffnet werden soll; ARoot ist die Wurzel der bisherigen Arbeitskopie.</summary>
    class procedure OfferOpen(const AProject, ARoot, AFolder: string); static;
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
  Atlas.Core.Setup.Checklist,
  Atlas.Core.VersionControl.BranchNames,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.VersionControl.Service;

class function TAtlasIdeBranching.Setup(const AName, AMessage, AKey: string;
  const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean): TAtlasBranchDialogSetup;
begin
  Result := TAtlasBranchDialogSetup.Make(AName, AMessage, AKey, AOfferNeverAsk);
  Result.Git := GitOptions;
  Result.Svn := ASvn;
end;

class function TAtlasIdeBranching.SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
var
  mSettings: TAtlasPluginSettings;
  mGroup: string;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasVcsSvnBranchOptions.Default;
  Result.Location := mSettings.VcsBranchSvnLocation;
  Result.Source := AtlasVcsSvnSourceOf(mSettings.VcsBranchSvnSource);
  Result.After := AtlasVcsSvnAfterOf(mSettings.VcsBranchSvnAfter);
  Result.CheckoutFolder := mSettings.VcsBranchSvnCheckoutFolder;
  Result.Message := mSettings.VcsBranchSvnMessage;
  Result.ExternalsOnBranch := AtlasVcsExternalActionOf(mSettings.VcsExternalsOnBranch);
  Result.ExternalsSuggest := AtlasVcsExternalSuggestOf(mSettings.VcsExternalsSuggestBranch);
  Result.ExternalsRules := TAtlasVcsExternalRules.RulesOf(mSettings.VcsExternalsRules);
  mGroup := '';
  if AProject <> '' then
  begin
    mGroup := TAtlasIdeFiles.GroupOfProject(AProject);
  end;
  if mGroup = '' then
  begin
    mGroup := AProject;
  end;
  Result.Project := ChangeFileExt(ExtractFileName(mGroup), '');
end;

class procedure TAtlasIdeBranching.OfferOpen(const AProject, ARoot, AFolder: string);
var
  mFile, mTarget: string;
  mActions: IOTAActionServices;
begin
  if (AProject = '') or (AFolder = '') then
  begin
    Exit;
  end;
  mFile := TAtlasIdeFiles.GroupOfProject(AProject);
  if mFile = '' then
  begin
    mFile := AProject;
  end;
  mTarget := TAtlasVcsBranchPlan.CheckoutTarget(ARoot, AFolder, mFile);
  if (mTarget = '') or not FileExists(mTarget) then
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchCheckedOut, [AFolder]));
    Exit;
  end;
  if MessageDlg(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchOpenCheckout, [ExtractFileName(mTarget), AFolder,
    sLineBreak + sLineBreak]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(mTarget, True);
      end);
  end;
end;

class function TAtlasIdeBranching.Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts;
  const ASetup: TAtlasBranchDialogSetup; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mFolder: string;
  mOpen: Boolean;
begin
  ARequest := Default(TAtlasVcsBranchRequest);
  ANeverAsk := False;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, AFacts, ASetup);
  try
    TAtlasIdeDockWindow.ApplyIdeTheme(mDialog);
    mOpen := True;
    if AFacts.NeedsServer then
    begin
      mFacts := AFacts;
      mFolder := AFolder;
      // Arbeit und Ergebnis teilen sich mFacts; das Ergebnis kommt erst nach der Arbeit, nach dem Schließen nie
      // an den Dialog.
      if not TAtlasIdeVcsCore.Run(
        procedure
        begin
          TAtlasVcsBranchPlan.InspectServer(
            TAtlasIdeVcsCore.ForFolder(mFolder, TAtlasIdeVcsCore.AtLeast(cTimeoutMs)), mFacts);
        end,
        procedure
        begin
          if mOpen then
          begin
            mDialog.ServerLoaded(mFacts);
          end;
        end) then
      begin
        mFacts.ServerChecked := True;
        mFacts.ServerOutcome := TAtlasVcsOutcome.Failed;
        mDialog.ServerLoaded(mFacts);
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

class procedure TAtlasIdeBranching.RebuildIndex;
begin
  if not Assigned(FServerCommand) or not FServerCommand(TAtlasSetupChecklist.cRebuildCommand) then
  begin
    Exit;
  end;
  TAtlasGuard.Log('Branch anlegen: Externals geändert, Index wird neu aufgebaut');
  TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchIndexRebuild));
end;

class procedure TAtlasIdeBranching.StopAsking;
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  if not mNext.VcsBranchConfirm then
  begin
    Exit;
  end;
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
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerLoginNeeded);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerToolMissing);
  else
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsServerUnreachable);
  end;
end;

class function TAtlasIdeBranching.AskLocal(const AFacts: TAtlasVcsBranchFacts;
  const ARequest: TAtlasVcsBranchRequest; const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
  out AFallback: TAtlasVcsBranchRequest): Boolean;
begin
  AFallback := ARequest;
  if not TAtlasVcsBranchPlan.FetchFailed(ASteps, ARun) then
  begin
    Exit(False);
  end;
  AFallback := TAtlasVcsBranchPlan.LocalFallback(AFacts, ARequest);
  Result := MessageDlg(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchFetchFailedAsk, [ARequest.Base.RemoteName,
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
  mDialog := CreateMessageDialog(
    TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchUncommittedAsk, [AChanges, AName, AName]),
    mtConfirmation, [mbYes, mbNo, mbCancel], mbYes);
  try
    // Eigene Beschriftungen statt Ja/Nein: mitnehmen, beiseitelegen, abbrechen.
    mButton := mDialog.FindComponent('Yes');
    if mButton is TButton then
    begin
      TButton(mButton).Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchCarry);
    end;
    mButton := mDialog.FindComponent('No');
    if mButton is TButton then
    begin
      TButton(mButton).Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchStashShort);
    end;
    mButton := mDialog.FindComponent('Cancel');
    if mButton is TButton then
    begin
      TButton(mButton).Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
    end;
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
  begin
    Result := TAtlasVcsBranchPlan.ProjectInFolder(mGroup, ARoot, AFolder);
  end;
  if Result = '' then
  begin
    Result := TAtlasVcsBranchPlan.ProjectInFolder(AProject, ARoot, AFolder);
  end;
end;

class function TAtlasIdeBranching.OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
begin
  Result := (ATarget <> '') and FileExists(ATarget) and (MessageDlg(TAtlasVcsStrings.Fmt(
    TAtlasVcsTextId.VcsBranchWorktreeOpen, [AName, AFolder, sLineBreak + sLineBreak, ExtractFileName(ATarget)]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

class function TAtlasIdeBranching.Candidates(AKind: TAtlasVcsKind; const AProject: string): TArray<string>;
begin
  Result := TAtlasVcsBranchNames.Bases(AKind = TAtlasVcsKind.Svn, TAtlasIdeSettings.Current.IssuesBranchBase,
    TAtlasIdeVcsCore.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject)));
end;

class function TAtlasIdeBranching.ProgressText(AKind: TAtlasVcsKind; AIndex, ACount: Integer;
  const AStep: TAtlasVcsBranchStep): string;
begin
  Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchProgress, [AIndex + 1, ACount,
    TAtlasVcsBranchPlan.StepText(AKind, AStep)]);
end;

class function TAtlasIdeBranching.Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
begin
  // Eigene Routine: Die Methodenreferenz fängt nur AKind ein.
  Result :=
    procedure(AIndex, ACount: Integer; const AStep: TAtlasVcsBranchStep)
    begin
      TAtlasIdeVcsCore.Report(ProgressText(AKind, AIndex, ACount, AStep));
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
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchStepFailed, [ARun.Failed + 1,
      TAtlasVcsBranchPlan.StepText(AKind, ASteps[ARun.Failed]), AtlasVcsOutcomeName(ARun.Outcome)]);
  end
  else
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchFailed, [AtlasVcsOutcomeName(ARun.Outcome)]);
  end;
  mDone := TAtlasVcsBranchPlan.ServerStepsDone(ASteps, ARun.Done);
  if Length(mDone) = 0 then
  begin
    Exit;
  end;
  mList := '';
  for mStep in mDone do
  begin
    if mList <> '' then
    begin
      mList := mList + '; ';
    end;
    mList := mList + TAtlasVcsBranchPlan.StepText(AKind, mStep);
  end;
  Result := Result + ' ' + TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchServerDone, [mList]);
end;

class procedure TAtlasIdeBranching.CreateFor(const AProject: string; const ADone: TProc);
var
  mProject, mFolder: string;
  mFacts: TAtlasVcsBranchFacts;
  mBaseText: string;
  mDone: TProc;
  mSvn: TAtlasVcsSvnBranchOptions;
begin
  mProject := AProject;
  mFolder := ExtractFileDir(AProject);
  mDone := ADone;
  if mFolder = '' then
  begin
    Exit;
  end;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mBaseText := TAtlasIdeSettings.Current.IssuesBranchBase;
  mSvn := SvnOptions(AProject);
  // Stand der Arbeitskopie im Hintergrund, dann der Dialog im Hauptthread.
  if not TAtlasIdeVcsCore.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mKind: TAtlasVcsKind;
      mItems: TArray<TAtlasVcsChange>;
    begin
      mVcs := TAtlasIdeVcsCore.ForFolder(mFolder, TAtlasIdeVcsCore.AtLeast(cTimeoutMs));
      mKind := TAtlasVcsKind.None;
      if mVcs <> nil then
      begin
        mKind := mVcs.Kind;
      end;
      mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TAtlasVcsBranchNames.Bases(mKind = TAtlasVcsKind.Svn, mBaseText,
        TAtlasIdeVcsCore.MainBranchOf(mProject, TAtlasIdeFiles.GroupOfProject(mProject))));
      // Geänderte Dateien für die Zeile „Offene Änderungen“ im Dialog (#1289).
      if (mFacts.Outcome = TAtlasVcsOutcome.Ok) and (mVcs.Changes(mItems) = TAtlasVcsOutcome.Ok) then
      begin
        mFacts.LocalChanges := TAtlasVcsBranchPlan.LocalChanges(mItems);
      end;
    end,
    procedure
    var
      mRequest: TAtlasVcsBranchRequest;
      mNever: Boolean;
    begin
      if (mFacts.Kind <> TAtlasVcsKind.Git) and (mFacts.Kind <> TAtlasVcsKind.Svn) then
      begin
        TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNoVcs));
        Exit;
      end;
      if Ask(mFolder, mFacts, Setup('', '', '', mSvn, False), mRequest, mNever) then
      begin
        RunCreate(mProject, mFacts, mRequest, mSvn, True, mDone);
      end;
    end) then
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsBranchNoVcs));
  end;
end;

type
  /// <summary>Ein Lauf von RunCreate: Arbeit im Hintergrund, Meldung im Hauptthread. Beide teilen sich die Felder;
  /// die Meldung kommt erst nach der Arbeit.</summary>
  TBranchCreation = class(TInterfacedObject)
  private
    FProject: string;
    FFolder: string;
    FSvn: TAtlasVcsSvnBranchOptions;
    FFacts: TAtlasVcsBranchFacts;
    FRequest: TAtlasVcsBranchRequest;
    FSteps: TArray<TAtlasVcsBranchStep>;
    FRun: TAtlasVcsBranchRun;
    FExists: Boolean;
    FTaken: Boolean;
    FOfferLocal: Boolean;
    FDone: TProc;
    /// <summary>Am Ort aus dem Dialog suchen (#1290), an dem auch angelegt wird.</summary>
    function SearchOptions: TAtlasVcsSvnBranchOptions;
    procedure ReportCreated;
    procedure AfterCreated;
  public
    procedure Work;
    procedure Finish;
  end;

function TBranchCreation.SearchOptions: TAtlasVcsSvnBranchOptions;
begin
  Result := FSvn;
  if FRequest.Location <> '' then
  begin
    Result.Location := '^/' + FRequest.Location;
  end;
end;

procedure TBranchCreation.Work;
var
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
begin
  mVcs := TAtlasIdeVcsCore.ForFolder(FFolder, TAtlasIdeVcsCore.AtLeast(TAtlasIdeBranching.cTimeoutMs));
  if (mVcs = nil) or not Supports(mVcs, IAtlasVcsBranching, mBranching) then
  begin
    FRun.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
    FRun.Failed := 0;
    Exit;
  end;
  FRun.Outcome := mBranching.BranchExists(FRequest.Name, SearchOptions, FExists);
  if (FRun.Outcome <> TAtlasVcsOutcome.Ok) or FExists then
  begin
    Exit;
  end;
  // Eigener Ordner (#1289): gibt es ihn schon, nichts anlegen.
  FTaken := (FRequest.WorktreeFolder <> '') and DirectoryExists(FRequest.WorktreeFolder);
  if not FTaken then
  begin
    FRun := TAtlasVcsBranchPlan.Execute(mBranching, FRequest, FSteps, TAtlasIdeBranching.Progress(FRequest.Kind));
  end;
end;

procedure TBranchCreation.ReportCreated;
var
  mBase: string;
begin
  mBase := TAtlasVcsBranchPlan.BaseName(FRequest.Kind, FRequest.Base);
  if FRequest.WorktreeFolder <> '' then
  begin
    TAtlasIdeVcsCore.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [FRequest.Name, mBase,
      FRequest.WorktreeFolder]));
  end
  else
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchCreated, [FRequest.Name, mBase]));
  end;
  // Nur der Push scheiterte: der lokale Branch bleibt.
  if not FRun.Succeeded then
  begin
    TAtlasIdeVcsCore.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [FRequest.Name,
      TAtlasIdeBranching.ServerState(FRun.Outcome)]));
  end;
end;

procedure TBranchCreation.AfterCreated;
var
  mTarget: string;
begin
  if Assigned(FDone) then
  begin
    FDone();
  end;
  if TAtlasVcsBranchPlan.ChangesExternals(FRequest) then
  begin
    TAtlasIdeBranching.RebuildIndex;
  end;
  if (FRequest.Kind = TAtlasVcsKind.Svn) and (FRequest.After = TAtlasVcsSvnAfter.Checkout) then
  begin
    TAtlasIdeBranching.OfferOpen(FProject, FFacts.Root, FRequest.CheckoutFolder);
  end;
  if FRequest.WorktreeFolder <> '' then
  begin
    mTarget := TAtlasIdeBranching.WorktreeProject(FProject, FFacts.Root, FRequest.WorktreeFolder);
    if TAtlasIdeBranching.OfferWorktree(FRequest.Name, FRequest.WorktreeFolder, mTarget) then
    begin
      TAtlasIdeBranching.OpenProject(mTarget);
    end;
  end;
end;

procedure TBranchCreation.Finish;
var
  mFallback: TAtlasVcsBranchRequest;
begin
  TAtlasGuard.Log(Format('Branch anlegen (Befehl): %s, %s', [AtlasVcsKindName(FRequest.Kind),
    AtlasVcsOutcomeName(FRun.Outcome)]));
  if FExists then
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchExists, [FRequest.Name]));
  end
  else if FTaken then
  begin
    TAtlasIdeVcsCore.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [FRequest.WorktreeFolder]));
  end
  else if FRun.Succeeded or TAtlasVcsBranchPlan.OnlyPushFailed(FSteps, FRun) then
  begin
    ReportCreated;
    AfterCreated;
  end
  // Abruf gescheitert, noch nichts geändert: nach Rückfrage vom lokalen Stand, ohne erneute Rückfrage.
  else if FOfferLocal and TAtlasIdeBranching.AskLocal(FFacts, FRequest, FSteps, FRun, mFallback) then
  begin
    TAtlasIdeBranching.RunCreate(FProject, FFacts, mFallback, FSvn, False, FDone);
  end
  else
  begin
    TAtlasIdeVcsCore.Report(TAtlasIdeBranching.FailureText(FRequest.Kind, FSteps, FRun));
  end;
end;

class procedure TAtlasIdeBranching.RunCreate(const AProject: string; const AFacts: TAtlasVcsBranchFacts;
  const ARequest: TAtlasVcsBranchRequest; const ASvn: TAtlasVcsSvnBranchOptions; AOfferLocal: Boolean;
  const ADone: TProc);
var
  mCreation: TBranchCreation;
  mKeep: IInterface;
begin
  mCreation := TBranchCreation.Create;
  mKeep := mCreation;
  mCreation.FProject := AProject;
  mCreation.FFolder := ExtractFileDir(AProject);
  mCreation.FFacts := AFacts;
  mCreation.FRequest := ARequest;
  mCreation.FSvn := ASvn;
  mCreation.FOfferLocal := AOfferLocal;
  mCreation.FDone := ADone;
  mCreation.FSteps := TAtlasVcsBranchPlan.Steps(ARequest);
  mCreation.FRun := Default(TAtlasVcsBranchRun);
  mCreation.FRun.Failed := -1;
  if not TAtlasIdeVcsCore.Run(
    procedure
    begin
      mCreation.Work;
    end,
    procedure
    begin
      mCreation.Finish;
      // Bis hierher hält mKeep den Lauf.
      mKeep := nil;
    end) then
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsBranchFailed,
      [AtlasVcsOutcomeName(TAtlasVcsOutcome.Failed)]));
  end;
end;

class procedure TAtlasIdeBranching.OpenProject(const AFile: string);
var
  mActions: IOTAActionServices;
begin
  if FileExists(AFile) and Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AFile, True);
      end);
  end;
end;

end.
