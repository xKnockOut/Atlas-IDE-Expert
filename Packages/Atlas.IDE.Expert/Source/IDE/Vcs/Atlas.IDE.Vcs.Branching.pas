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
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan;

type
  TAtlasIdeBranching = class
  public const
    /// <summary>Zeitlimit je Aufruf beim Anlegen (wie „Beginnen“, #765); vcs.timeoutSeconds, wenn größer.</summary>
    TimeoutMs = 30000;
  private
    class var FServerCommand: TFunc<string, Boolean>;
  public
    /// <summary>Befehl an den Atlas-Server abschicken (#1291, aus der Komposition; True, wenn angenommen). Beim
    /// Entladen nil.</summary>
    class property ServerCommand: TFunc<string, Boolean> read FServerCommand write FServerCommand;
    /// <summary>Nach einem Branch mit geänderten Externals (#1291, Hauptthread): Index neu aufbauen und das in
    /// der Meldungsansicht sagen; ohne Server nichts.</summary>
    class procedure RebuildIndex; static;
    /// <summary>Dialog zeigen (Hauptthread). True mit ARequest bei „Anlegen“; ANeverAsk, wenn „Nicht mehr fragen“
    /// gesetzt war (nur mit AOfferNeverAsk).</summary>
    class function Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean; overload;
      static;
    /// <summary>Wie oben mit den SVN-Optionen als Vorgaben im Dialog (#1290).</summary>
    class function Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest;
      out ANeverAsk: Boolean): Boolean; overload; static;
    /// <summary>SVN-Optionen aus den Einstellungen (vcs.branch.svn.*, #1290); Projekt = Name der Gruppe von
    /// AProject (sonst des Projekts), Kennung und Titel leer.</summary>
    class function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions; static;
    /// <summary>Nach „frisch auschecken“ (#1290, Hauptthread): fragen, ob dieselbe Gruppe (bzw. AProject) im
    /// neuen Ordner AFolder geöffnet werden soll; ARoot ist die Wurzel der bisherigen Arbeitskopie.</summary>
    class procedure OfferOpen(const AProject, ARoot, AFolder: string); static;
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
  Vcl.Controls,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Tracker.Naming,
  Atlas.UI.Strings,
  Atlas.UI.Vcs.BranchDialog,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

class function TAtlasIdeBranching.Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage: string; AOfferNeverAsk: Boolean; out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
begin
  Result := Ask(AFolder, AFacts, AName, AMessage, TAtlasVcsSvnBranchOptions.Legacy, AOfferNeverAsk, ARequest,
    ANeverAsk);
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
  Result.ExternalsRules := TAtlasVcsBranchPlan.RulesOf(mSettings.VcsExternalsRules);
  mGroup := '';
  if AProject <> '' then
    mGroup := TAtlasIdeFiles.GroupOfProject(AProject);
  if mGroup = '' then
    mGroup := AProject;
  Result.Project := ChangeFileExt(ExtractFileName(mGroup), '');
end;

class procedure TAtlasIdeBranching.OfferOpen(const AProject, ARoot, AFolder: string);
var
  mFile, mTarget: string;
  mActions: IOTAActionServices;
begin
  if (AProject = '') or (AFolder = '') then
    Exit;
  mFile := TAtlasIdeFiles.GroupOfProject(AProject);
  if mFile = '' then
    mFile := AProject;
  mTarget := TAtlasVcsBranchPlan.CheckoutTarget(ARoot, AFolder, mFile);
  if (mTarget = '') or not FileExists(mTarget) then
  begin
    TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchCheckedOut, [AFolder]));
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchOpenCheckout, [ExtractFileName(mTarget), AFolder,
    sLineBreak + sLineBreak]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
    mActions.OpenProject(mTarget, True);
end;

class function TAtlasIdeBranching.Ask(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage: string; const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean;
  out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
var
  mDialog: TAtlasBranchDialog;
  mFacts: TAtlasVcsBranchFacts;
  mFolder: string;
  mOpen: Boolean;
begin
  ARequest := Default(TAtlasVcsBranchRequest);
  ANeverAsk := False;
  mDialog := TAtlasBranchDialog.CreateDialog(nil, AFacts, AName, AMessage, ASvn, AOfferNeverAsk);
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

class procedure TAtlasIdeBranching.RebuildIndex;
begin
  if not Assigned(FServerCommand) or not FServerCommand(TAtlasSetupChecklist.RebuildCommand) then
    Exit;
  TAtlasGuard.Log('Branch anlegen: Externals geändert, Index wird neu aufgebaut');
  TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchIndexRebuild));
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
  mSvn: TAtlasVcsSvnBranchOptions;
begin
  mProject := AProject;
  mFolder := ExtractFileDir(AProject);
  mDone := ADone;
  if mFolder = '' then
    Exit;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mBaseText := TAtlasIdeSettings.Current.IssuesBranchBase;
  mSvn := SvnOptions(AProject);
  // Stand der Arbeitskopie im Hintergrund, dann der Dialog im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mKind: TAtlasVcsKind;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(TimeoutMs));
      mKind := TAtlasVcsKind.None;
      if mVcs <> nil then
        mKind := mVcs.Kind;
      mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TAtlasTrackerNaming.Bases(mKind = TAtlasVcsKind.Svn, mBaseText,
        TAtlasIdeVcs.MainBranchOf(mProject, TAtlasIdeFiles.GroupOfProject(mProject))));
    end,
    procedure
    var
      mRequest: TAtlasVcsBranchRequest;
      mNever: Boolean;
      mSteps: TArray<TAtlasVcsBranchStep>;
      mRun: TAtlasVcsBranchRun;
      mExists: Boolean;
    begin
      if (mFacts.Kind <> TAtlasVcsKind.Git) and (mFacts.Kind <> TAtlasVcsKind.Svn) then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
        Exit;
      end;
      if not Ask(mFolder, mFacts, '', '', mSvn, False, mRequest, mNever) then
        Exit;
      mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
      mExists := False;
      mRun := Default(TAtlasVcsBranchRun);
      mRun.Failed := -1;
      if not TAtlasIdeVcs.Run(
        procedure
        var
          mVcs: IAtlasVersionControl;
          mBranching: IAtlasVcsBranching;
          mFound: TAtlasVcsSvnBranchOptions;
        begin
          mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(TimeoutMs));
          if (mVcs = nil) or not Supports(mVcs, IAtlasVcsBranching, mBranching) then
          begin
            mRun.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
            mRun.Failed := 0;
            Exit;
          end;
          // Am Ort aus dem Dialog suchen (#1290), an dem auch angelegt wird.
          mFound := mSvn;
          if mRequest.Location <> '' then
            mFound.Location := '^/' + mRequest.Location;
          mRun.Outcome := mBranching.BranchExists(mRequest.Name, mFound, mExists);
          if (mRun.Outcome <> TAtlasVcsOutcome.Ok) or mExists then
            Exit;
          mRun := TAtlasVcsBranchPlan.Execute(mBranching, mRequest, mSteps, Progress(mRequest.Kind));
        end,
        procedure
        begin
          TAtlasGuard.Log(Format('Branch anlegen (Befehl): %s, %s', [AtlasVcsKindName(mRequest.Kind),
            AtlasVcsOutcomeName(mRun.Outcome)]));
          if mExists then
            TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchExists, [mRequest.Name]))
          else if mRun.Succeeded then
          begin
            TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchCreated, [mRequest.Name,
              TAtlasVcsBranchPlan.BaseName(mRequest.Kind, mRequest.Base)]));
            if Assigned(mDone) then
              mDone();
            if TAtlasVcsBranchPlan.ChangesExternals(mRequest) then
              RebuildIndex;
            if (mRequest.Kind = TAtlasVcsKind.Svn) and (mRequest.After = TAtlasVcsSvnAfter.Checkout) then
              OfferOpen(mProject, mFacts.Root, mRequest.CheckoutFolder);
          end
          else
            TAtlasIdeVcs.Report(FailureText(mRequest.Kind, mSteps, mRun));
        end) then
        TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFailed,
          [AtlasVcsOutcomeName(TAtlasVcsOutcome.Failed)]));
    end) then
    TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
end;

end.
