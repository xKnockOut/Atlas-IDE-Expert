unit Atlas.IDE.Contracts.VersionControl;

// Vertrag zwischen Modulen (#1891, Modulregel 6): Das Modul Versionsverwaltung
// (Atlas.IDE.VersionControl) stellt über seinen Scope einen IAtlasVcsService (Arbeitskopie zu
// einem Ordner, Arbeit im Hintergrund, Fundort und Prüfung der Werkzeuge, Server)
// und einen IAtlasVcsDialogs (Branch anlegen, Arbeitskopien, Rückfragen beim
// Beginnen eines Issues) bereit. Base, Tracker, Welcome und Tests fragen beides
// nur über TAtlasIdeVcs (unten); das Modul setzt seine Dienste beim Start mit
// Bind ein und nimmt sie beim Stop mit Unbind zurück. Ohne Modul antwortet
// ein Null-Objekt: keine Arbeitskopie, kein Hintergrundlauf, keine Dialoge.
// Threadsicher, weil ForFolder auch in Hintergrundläufen gefragt wird.
// Die Daten (Records, Aufzählungen, IAtlasVersionControl) stehen in
// Atlas.Core.VersionControl.Contract und den reinen Units unter Source/Core/Vcs von Base;
// git und svn rufen nur die Umsetzungen im Modul auf.
// Liegt in Base (Source/Contracts).

interface

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.ToolCheck,
  Atlas.Core.VersionControl.ServerCheck,
  Atlas.Core.Projects.VersionControl;

type
  /// <summary>Frage „Branch anlegen“ beim Beginnen eines Issues (#765, #1288): Ordner des Projekts, Lage der
  /// Arbeitskopie, vorgeschlagener Name, Commit-Nachricht und Kennung des Issues, SVN-Vorgaben;
  /// OfferNeverAsk zeigt „Nicht mehr fragen“.</summary>
  TAtlasVcsBranchAsk = record
    Folder: string;
    Facts: TAtlasVcsBranchFacts;
    Name: string;
    Message: string;
    Key: string;
    Svn: TAtlasVcsSvnBranchOptions;
    OfferNeverAsk: Boolean;
  end;

  /// <summary>Versionsverwaltung der IDE. ForFolder und Run in jedem Thread, alles andere im Hauptthread.</summary>
  IAtlasVcsService = interface
    ['{8E0B6C4D-5A21-4F3E-9C7B-2D61A4E9B305}']
    /// <summary>Meldung an den Benutzer (Meldungsfenster bzw. Statuszeile).</summary>
    procedure Report(const AText: string);
    /// <summary>Gewählter Anbieter aus vcs.provider.</summary>
    function Provider: TAtlasVcsProvider;
    /// <summary>Zeitlimit eines Aufrufs (vcs.timeoutMs).</summary>
    function TimeoutMs: Cardinal;
    /// <summary>settings.json neu lesen (neuer Pfad, neues Zeitlimit).</summary>
    procedure Reload;
    /// <summary>Arbeitskopie zu AFolder; ATimeoutMs 0 = Zeitlimit der Einstellung.</summary>
    function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
    function MainBranchOf(const AProjectFile, AGroupFile: string): string;
    function Projects: TArray<TAtlasVcsProjectMapping>;
    /// <summary>AWork im Hintergrund, ADone danach im Hauptthread; False, wenn nichts gestartet wurde.</summary>
    function Run(const AWork, ADone: TProc): Boolean;
    function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
    function CheckTool(AKind: TAtlasVcsKind; const APath: string; const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
    function QueryProject(const AProjectFile, AGroupFile: string; const ADone: TProc<TAtlasVcsProjectState>): Boolean;
    function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
    function ServerState(const AFolder: string): TAtlasVcsServerCheck;
    function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
  end;

  /// <summary>Dialoge und Rückfragen der Versionsverwaltung (Hauptthread).</summary>
  IAtlasVcsDialogs = interface
    ['{3F7A92C1-0B4D-4E86-A5D3-9C1E7B2F6048}']
    /// <summary>Dialog „Branch anlegen“ für das Projekt AProject; ADone nach Erfolg.</summary>
    procedure CreateBranchFor(const AProject: string; const ADone: TProc);
    /// <summary>Dialog „Arbeitskopien“ für AProject; ADone nach Änderungen.</summary>
    procedure ShowWorkingCopies(const AProject: string; const ADone: TProc);
    /// <summary>Dialog „Branch anlegen“ beim Beginnen eines Issues (#765, #1288).</summary>
    function AskBranch(const AAsk: TAtlasVcsBranchAsk; out ARequest: TAtlasVcsBranchRequest;
      out ANeverAsk: Boolean): Boolean;
    function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
    function GitOptions: TAtlasVcsGitBranchOptions;
    procedure OfferOpen(const AProject, ARoot, AFolder: string);
    function ServerState(AOutcome: TAtlasVcsOutcome): string;
    function AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
      out AFallback: TAtlasVcsBranchRequest): Boolean;
    function AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
    function WorktreeProject(const AProject, ARoot, AFolder: string): string;
    function OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
    procedure StopAsking;
    procedure RebuildIndex;
    function Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
    function FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): string;
  end;

  TAtlasIdeVcs = class
  public const
    /// <summary>Zeitlimit ohne Modul.</summary>
    cDefaultTimeoutMs = 30000;
  public
    /// <summary>Dienste des Moduls einsetzen (Start des Moduls, Hauptthread).</summary>
    class procedure Bind(const AService: IAtlasVcsService; const ADialogs: IAtlasVcsDialogs); static;
    /// <summary>Dienste des Moduls zurücknehmen (Stop des Moduls); danach antwortet das Null-Objekt.</summary>
    class procedure Unbind; static;
    /// <summary>Ist das Modul da?</summary>
    class function Available: Boolean; static;
    /// <summary>Dienst des Moduls oder Null-Objekt.</summary>
    class function Service: IAtlasVcsService; static;
    /// <summary>Dialoge des Moduls oder Null-Objekt.</summary>
    class function Dialogs: IAtlasVcsDialogs; static;
    class procedure Report(const AText: string); static;
    class function Provider: TAtlasVcsProvider; static;
    class function TimeoutMs: Cardinal; static;
    /// <summary>Zeitlimit der Einstellung, mindestens AMinimumMs.</summary>
    class function AtLeast(AMinimumMs: Cardinal): Cardinal; static;
    class procedure Reload; static;
    class function ForFolder(const AFolder: string): IAtlasVersionControl; overload; static;
    class function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl; overload; static;
    class function MainBranchOf(const AProjectFile, AGroupFile: string): string; static;
    class function Projects: TArray<TAtlasVcsProjectMapping>; static;
    class function Run(const AWork, ADone: TProc): Boolean; static;
    class function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation; static;
    class function CheckTool(AKind: TAtlasVcsKind; const APath: string;
      const ADone: TProc<TAtlasVcsToolCheck>): Boolean; static;
    class function QueryProject(const AProjectFile, AGroupFile: string;
      const ADone: TProc<TAtlasVcsProjectState>): Boolean; static;
    class function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean; static;
    class function ServerState(const AFolder: string): TAtlasVcsServerCheck; static;
    class function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean; static;
  end;

  /// <summary>Antwort ohne Modul (#1891): keine Arbeitskopie, nichts im Hintergrund.</summary>
  TAtlasNullVcsService = class(TInterfacedObject, IAtlasVcsService)
  public
    procedure Report(const AText: string);
    function Provider: TAtlasVcsProvider;
    function TimeoutMs: Cardinal;
    procedure Reload;
    function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
    function MainBranchOf(const AProjectFile, AGroupFile: string): string;
    function Projects: TArray<TAtlasVcsProjectMapping>;
    function Run(const AWork, ADone: TProc): Boolean;
    function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
    function CheckTool(AKind: TAtlasVcsKind; const APath: string; const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
    function QueryProject(const AProjectFile, AGroupFile: string; const ADone: TProc<TAtlasVcsProjectState>): Boolean;
    function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
    function ServerState(const AFolder: string): TAtlasVcsServerCheck;
    function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
  end;

  /// <summary>Dialoge ohne Modul: fragt nichts, legt nichts an.</summary>
  TAtlasNullVcsDialogs = class(TInterfacedObject, IAtlasVcsDialogs)
  public
    procedure CreateBranchFor(const AProject: string; const ADone: TProc);
    procedure ShowWorkingCopies(const AProject: string; const ADone: TProc);
    function AskBranch(const AAsk: TAtlasVcsBranchAsk; out ARequest: TAtlasVcsBranchRequest;
      out ANeverAsk: Boolean): Boolean;
    function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
    function GitOptions: TAtlasVcsGitBranchOptions;
    procedure OfferOpen(const AProject, ARoot, AFolder: string);
    function ServerState(AOutcome: TAtlasVcsOutcome): string;
    function AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
      out AFallback: TAtlasVcsBranchRequest): Boolean;
    function AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
    function WorktreeProject(const AProject, ARoot, AFolder: string): string;
    function OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
    procedure StopAsking;
    procedure RebuildIndex;
    function Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
    function FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): string;
  end;

implementation

uses
  System.SyncObjs,
  Atlas.Core.VersionControl.Providers.Null;

var
  GLock: TCriticalSection;
  GService: IAtlasVcsService;
  GDialogs: IAtlasVcsDialogs;

{ TAtlasIdeVcs }

class procedure TAtlasIdeVcs.Bind(const AService: IAtlasVcsService; const ADialogs: IAtlasVcsDialogs);
begin
  GLock.Enter;
  try
    GService := AService;
    GDialogs := ADialogs;
  finally
    GLock.Leave;
  end;
end;

class procedure TAtlasIdeVcs.Unbind;
begin
  Bind(nil, nil);
end;

class function TAtlasIdeVcs.Available: Boolean;
begin
  GLock.Enter;
  try
    Result := GService <> nil;
  finally
    GLock.Leave;
  end;
end;

class function TAtlasIdeVcs.Service: IAtlasVcsService;
begin
  GLock.Enter;
  try
    Result := GService;
  finally
    GLock.Leave;
  end;
  if Result = nil then
  begin
    Result := TAtlasNullVcsService.Create;
  end;
end;

class function TAtlasIdeVcs.Dialogs: IAtlasVcsDialogs;
begin
  GLock.Enter;
  try
    Result := GDialogs;
  finally
    GLock.Leave;
  end;
  if Result = nil then
  begin
    Result := TAtlasNullVcsDialogs.Create;
  end;
end;

class procedure TAtlasIdeVcs.Report(const AText: string);
begin
  Service.Report(AText);
end;

class function TAtlasIdeVcs.Provider: TAtlasVcsProvider;
begin
  Result := Service.Provider;
end;

class function TAtlasIdeVcs.TimeoutMs: Cardinal;
begin
  Result := Service.TimeoutMs;
end;

class function TAtlasIdeVcs.AtLeast(AMinimumMs: Cardinal): Cardinal;
begin
  Result := TimeoutMs;
  if AMinimumMs > Result then
  begin
    Result := AMinimumMs;
  end;
end;

class procedure TAtlasIdeVcs.Reload;
begin
  Service.Reload;
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string): IAtlasVersionControl;
begin
  Result := Service.ForFolder(AFolder, 0);
end;

class function TAtlasIdeVcs.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  Result := Service.ForFolder(AFolder, ATimeoutMs);
end;

class function TAtlasIdeVcs.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := Service.MainBranchOf(AProjectFile, AGroupFile);
end;

class function TAtlasIdeVcs.Projects: TArray<TAtlasVcsProjectMapping>;
begin
  Result := Service.Projects;
end;

class function TAtlasIdeVcs.Run(const AWork, ADone: TProc): Boolean;
begin
  Result := Service.Run(AWork, ADone);
end;

class function TAtlasIdeVcs.Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
begin
  Result := Service.Locate(AKind, APath);
end;

class function TAtlasIdeVcs.CheckTool(AKind: TAtlasVcsKind; const APath: string;
  const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
begin
  Result := Service.CheckTool(AKind, APath, ADone);
end;

class function TAtlasIdeVcs.QueryProject(const AProjectFile, AGroupFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
begin
  Result := Service.QueryProject(AProjectFile, AGroupFile, ADone);
end;

class function TAtlasIdeVcs.CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
begin
  Result := Service.CheckServer(AFolder, ADone);
end;

class function TAtlasIdeVcs.ServerState(const AFolder: string): TAtlasVcsServerCheck;
begin
  Result := Service.ServerState(AFolder);
end;

class function TAtlasIdeVcs.OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
begin
  Result := Service.OpenServerLogin(ACheck, AClosed);
end;

{ TAtlasNullVcsService }

procedure TAtlasNullVcsService.Report(const AText: string);
begin
  // Ohne Modul gibt es nichts zu melden.
end;

function TAtlasNullVcsService.Provider: TAtlasVcsProvider;
begin
  Result := TAtlasVcsProvider.Off;
end;

function TAtlasNullVcsService.TimeoutMs: Cardinal;
begin
  Result := TAtlasIdeVcs.cDefaultTimeoutMs;
end;

procedure TAtlasNullVcsService.Reload;
begin
  // Nichts zu lesen.
end;

function TAtlasNullVcsService.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  Result := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
end;

function TAtlasNullVcsService.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := '';
end;

function TAtlasNullVcsService.Projects: TArray<TAtlasVcsProjectMapping>;
begin
  Result := nil;
end;

function TAtlasNullVcsService.Run(const AWork, ADone: TProc): Boolean;
begin
  Result := False;
end;

function TAtlasNullVcsService.Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasVcsTools.Probe(AKind, APath);
end;

function TAtlasNullVcsService.CheckTool(AKind: TAtlasVcsKind; const APath: string;
  const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
begin
  Result := False;
end;

function TAtlasNullVcsService.QueryProject(const AProjectFile, AGroupFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
begin
  Result := False;
end;

function TAtlasNullVcsService.CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
begin
  Result := False;
end;

function TAtlasNullVcsService.ServerState(const AFolder: string): TAtlasVcsServerCheck;
begin
  Result := Default(TAtlasVcsServerCheck);
end;

function TAtlasNullVcsService.OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
begin
  Result := False;
end;

{ TAtlasNullVcsDialogs }

procedure TAtlasNullVcsDialogs.CreateBranchFor(const AProject: string; const ADone: TProc);
begin
  // Ohne Modul kein Dialog.
end;

procedure TAtlasNullVcsDialogs.ShowWorkingCopies(const AProject: string; const ADone: TProc);
begin
  // Ohne Modul kein Dialog.
end;

function TAtlasNullVcsDialogs.AskBranch(const AAsk: TAtlasVcsBranchAsk; out ARequest: TAtlasVcsBranchRequest;
  out ANeverAsk: Boolean): Boolean;
begin
  ARequest := Default(TAtlasVcsBranchRequest);
  ANeverAsk := False;
  Result := False;
end;

function TAtlasNullVcsDialogs.SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
begin
  Result := TAtlasVcsSvnBranchOptions.Default;
end;

function TAtlasNullVcsDialogs.GitOptions: TAtlasVcsGitBranchOptions;
begin
  Result := Default(TAtlasVcsGitBranchOptions);
end;

procedure TAtlasNullVcsDialogs.OfferOpen(const AProject, ARoot, AFolder: string);
begin
  // Ohne Modul nichts anzubieten.
end;

function TAtlasNullVcsDialogs.ServerState(AOutcome: TAtlasVcsOutcome): string;
begin
  Result := '';
end;

function TAtlasNullVcsDialogs.AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
  const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
  out AFallback: TAtlasVcsBranchRequest): Boolean;
begin
  AFallback := Default(TAtlasVcsBranchRequest);
  Result := False;
end;

function TAtlasNullVcsDialogs.AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
begin
  AStash := False;
  Result := False;
end;

function TAtlasNullVcsDialogs.WorktreeProject(const AProject, ARoot, AFolder: string): string;
begin
  Result := '';
end;

function TAtlasNullVcsDialogs.OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
begin
  Result := False;
end;

procedure TAtlasNullVcsDialogs.StopAsking;
begin
  // Nichts zu merken.
end;

procedure TAtlasNullVcsDialogs.RebuildIndex;
begin
  // Ohne Modul kein Branch und nichts neu aufzubauen.
end;

function TAtlasNullVcsDialogs.Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
begin
  Result := nil;
end;

function TAtlasNullVcsDialogs.FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): string;
begin
  Result := '';
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  GService := nil;
  GDialogs := nil;
  FreeAndNil(GLock);

end.
