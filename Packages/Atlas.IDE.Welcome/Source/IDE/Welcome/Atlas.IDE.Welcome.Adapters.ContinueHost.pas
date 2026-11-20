unit Atlas.IDE.Welcome.Adapters.ContinueHost;

// Die IDE für den Ablauf von „Weiterarbeiten“ (#755, TAtlasContinueWork):
// Einstellungen, Uhr, Editor und Projekte (Atlas.IDE.Welcome.Continue.Editor),
// Projekt-Zusammenfassungen der IDE, Abfragen der Versionsverwaltung im
// Hintergrund (TAtlasIdeVcs), Texte und Meldungen. Eingehende Commits holt
// fetch mit eigenem Zeitlimit; Zugangsdaten fragt der Anbieter nie ab.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.Contract.Summary,
  Atlas.Core.Welcome.Contract,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasIdeContinueHost = class(TInterfacedObject, IAtlasContinueHost)
  private
    FMessage: TAtlasMessageSink;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    function Settings: TAtlasContinueSettings;
    function Ticks: UInt64;
    function NowUtc: TDateTime;
    function CurrentTarget: string;
    function TargetOf(const AFileName: string): string;
    function TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
    function RecentProjects: TArray<string>;
    function LoadSummary(const ATarget: string; out ASummary: TAtlasProjectSummary): Boolean;
    procedure UpdateSummary(const ATarget: string; const AChange: TAtlasContinueSummaryChange);
    function QueryHead(const AFolder: string; const ADone: TAtlasContinueHeadDone): Boolean;
    function QueryIncoming(const ARequest: TAtlasContinueIncomingRequest;
      const ADone: TAtlasContinueIncomingDone): Boolean;
    function MainBranchOf(const AProject: string): string;
    function FileExists(const AFileName: string): Boolean;
    procedure EnsureProject(const AProject: string);
    procedure OpenTab(const ATab: TAtlasWorkTab);
    function Text(AText: TAtlasContinueText; const AArgument: string): string;
    procedure Say(const AText: string);
    procedure Changed;
  end;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.Core.VersionControl.Contract,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Continue.Editor;

/// <summary>Im Hintergrund: eingehende Commits abfragen.</summary>
function ProbeIncoming(const ARequest: TAtlasContinueIncomingRequest; out AFound: TAtlasContinueIncoming): Boolean;
var
  mProbe: TAtlasContinueProbe;
  mDir: string;
  mFetch: IAtlasVersionControl;
begin
  mProbe := TAtlasContinueProbe.Create(ARequest.Project, ARequest.MainBranch, ARequest.State, ARequest.Stamp);
  mDir := ExtractFileDir(ARequest.Project);
  mFetch := nil;
  if ARequest.Fetch then
  begin
    mFetch := TAtlasIdeVcs.ForFolder(mDir, TAtlasWelcomeContinue.cFetchTimeoutMs);
  end;
  Result := TAtlasWelcomeContinue.ProbeIncoming(TAtlasIdeVcs.ForFolder(mDir, TAtlasWelcomeContinue.cCallTimeoutMs),
    mFetch, mProbe, AFound);
end;

{ TAtlasIdeContinueHost }

constructor TAtlasIdeContinueHost.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := TAtlasMessageSink.Create(AMessage);
end;

function TAtlasIdeContinueHost.Settings: TAtlasContinueSettings;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := Default(TAtlasContinueSettings);
  Result.WelcomePage := mSettings^.WelcomePage;
  Result.Continue := mSettings^.WelcomePageContinue;
  Result.Incoming := mSettings^.WelcomePageContinueIncoming;
  Result.Fetch := mSettings^.WelcomePageContinueFetch;
  Result.Count := mSettings^.WelcomePageContinueCount;
end;

function TAtlasIdeContinueHost.Ticks: UInt64;
begin
  Result := GetTickCount64;
end;

function TAtlasIdeContinueHost.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function TAtlasIdeContinueHost.CurrentTarget: string;
begin
  Result := TAtlasIdeContinueEditor.CurrentTarget;
end;

function TAtlasIdeContinueHost.TargetOf(const AFileName: string): string;
begin
  Result := TAtlasIdeContinueEditor.TargetOf(AFileName);
end;

function TAtlasIdeContinueHost.TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
begin
  Result := TAtlasIdeContinueEditor.TakeSnapshot(AChanges);
end;

function TAtlasIdeContinueHost.RecentProjects: TArray<string>;
begin
  Result := nil;
  try
    Result := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

function TAtlasIdeContinueHost.LoadSummary(const ATarget: string; out ASummary: TAtlasProjectSummary): Boolean;
begin
  Result := TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, ATarget, ASummary);
end;

procedure TAtlasIdeContinueHost.UpdateSummary(const ATarget: string; const AChange: TAtlasContinueSummaryChange);
var
  mChange: TAtlasContinueSummaryChange;
begin
  mChange := AChange;
  TAtlasProjectSummaries.Update(TAtlasIdeProjectSummaries.Folder, ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      mChange(ASummary);
    end);
end;

function TAtlasIdeContinueHost.QueryHead(const AFolder: string; const ADone: TAtlasContinueHeadDone): Boolean;
var
  mDir: string;
  mOk: Boolean;
  mHead: TAtlasWorkState;
  mDone: TAtlasContinueHeadDone;
begin
  mDir := AFolder;
  mDone := ADone;
  mOk := False;
  mHead := TAtlasWorkState.Empty;
  Result := TAtlasIdeVcs.Run(
    procedure
    begin
      mOk := TAtlasWelcomeContinue.ProbeHead(TAtlasIdeVcs.ForFolder(mDir, TAtlasWelcomeContinue.cCallTimeoutMs),
        mHead);
    end,
    procedure
    begin
      mDone(mOk, mHead);
    end);
end;

function TAtlasIdeContinueHost.QueryIncoming(const ARequest: TAtlasContinueIncomingRequest;
  const ADone: TAtlasContinueIncomingDone): Boolean;
var
  mRequest: TAtlasContinueIncomingRequest;
  mOk: Boolean;
  mFound: TAtlasContinueIncoming;
  mDone: TAtlasContinueIncomingDone;
begin
  mRequest := ARequest;
  mDone := ADone;
  mOk := False;
  mFound := Default(TAtlasContinueIncoming);
  Result := TAtlasIdeVcs.Run(
    procedure
    begin
      mOk := ProbeIncoming(mRequest, mFound);
    end,
    procedure
    begin
      mDone(mOk, mFound);
    end);
end;

function TAtlasIdeContinueHost.MainBranchOf(const AProject: string): string;
begin
  // .atlas und Gruppe im Hauptthread.
  if SameText(ExtractFileExt(AProject), '.groupproj') then
  begin
    Result := TAtlasIdeVcs.MainBranchOf(AProject, AProject);
  end
  else
  begin
    Result := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  end;
end;

function TAtlasIdeContinueHost.FileExists(const AFileName: string): Boolean;
begin
  Result := System.SysUtils.FileExists(AFileName);
end;

procedure TAtlasIdeContinueHost.EnsureProject(const AProject: string);
begin
  TAtlasIdeContinueEditor.EnsureProject(AProject);
end;

procedure TAtlasIdeContinueHost.OpenTab(const ATab: TAtlasWorkTab);
begin
  TAtlasIdeContinueEditor.OpenTab(ATab);
end;

function TAtlasIdeContinueHost.Text(AText: TAtlasContinueText; const AArgument: string): string;
begin
  case AText of
    TAtlasContinueText.Disabled:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueDisabled);
    TAtlasContinueText.Nothing:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueNothing);
    TAtlasContinueText.ProjectMissing:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AArgument]);
  else
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMissing, [AArgument]);
  end;
end;

procedure TAtlasIdeContinueHost.Say(const AText: string);
begin
  FMessage.Say(AText);
end;

procedure TAtlasIdeContinueHost.Changed;
begin
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cContinue);
end;

end.
