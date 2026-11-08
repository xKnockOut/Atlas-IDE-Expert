unit Atlas.UI.VersionControl.SettingsSection;

// Abschnitt des Moduls Versionsverwaltung im Optionsdialog (#1891, seit #1905 die ganze Seite): Modulschalter
// vcs.enabled, Art, Programme, Zeitlimit und aktuelles Projekt, Tabellen Projekte und Server, Links, Branches,
// Externals und Git. Die Teile (Atlas.UI.VersionControl.Settings*) entstehen mit dem Abschnitt, damit die IDE-Schicht
// ihre Haken vor Build setzen kann; ihre Steuerelemente gehören einem Besitzer, den Close freigibt (Regel 3).
// Show mit dem Schlüssel vcs.projects und einem Ordner zeigt und prüft dessen Zeile in der Tabelle Server
// („Anmeldung am Server nötig – prüfen …“, #1287). Die Werte liegen in settings.json und bleiben beim Abschalten
// erhalten.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Section,
  Atlas.UI.VersionControl.SettingsPart,
  Atlas.UI.VersionControl.SettingsKind,
  Atlas.UI.VersionControl.SettingsTools,
  Atlas.UI.VersionControl.SettingsProject,
  Atlas.UI.VersionControl.SettingsProjects,
  Atlas.UI.VersionControl.SettingsBranch;

type
  /// <summary>Offen, bis der Abschnitt schließt; Antworten im Hintergrund fragen es, ohne den Abschnitt zu halten.
  /// </summary>
  TAtlasVcsSectionAlive = class(TInterfacedObject)
  private
    FOpen: Boolean;
  public
    constructor Create;
    property Open: Boolean read FOpen write FOpen;
  end;

  TAtlasVcsSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.vcs';
    cAreaId = 'Versionsverwaltung';
  private
    FParts: TList<TAtlasVcsSettingsPart>;
    FOwner: TAtlasVcsSettingsOwner;
    FKind: TAtlasSettingsVcsPart;
    FTools: TAtlasSettingsVcsToolsPart;
    FProject: TAtlasSettingsVcsProjectPart;
    FProjects: TAtlasSettingsVcsProjectsPart;
    FProjectAdd: TAtlasSettingsVcsProjectAddPart;
    FServers: TAtlasSettingsVcsServersPart;
    FBranch: TAtlasSettingsVcsBranchPart;
    FAlive: TAtlasVcsSectionAlive;
    FAliveRef: IInterface;
    function Add(APart: TAtlasVcsSettingsPart): TAtlasVcsSettingsPart;
  protected
    procedure BuildRows; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure WindowReady; override;
    function Show(const AKey, AArgument: string): Boolean; override;
    procedure Close; override;
    /// <summary>Sagt, ob der Abschnitt noch offen ist; hält ihn nicht fest (kein Ring über die Haken).</summary>
    function Alive: TFunc<Boolean>;
    property Kind: TAtlasSettingsVcsPart read FKind;
    property Tools: TAtlasSettingsVcsToolsPart read FTools;
    property Project: TAtlasSettingsVcsProjectPart read FProject;
    property Projects: TAtlasSettingsVcsProjectsPart read FProjects;
    property ProjectAdd: TAtlasSettingsVcsProjectAddPart read FProjectAdd;
    property Servers: TAtlasSettingsVcsServersPart read FServers;
    property Branch: TAtlasSettingsVcsBranchPart read FBranch;
  end;

implementation

{ TAtlasVcsSectionAlive }

constructor TAtlasVcsSectionAlive.Create;
begin
  inherited Create;
  FOpen := True;
end;

{ TAtlasVcsSettingsSection }

constructor TAtlasVcsSettingsSection.Create;
begin
  inherited Create;
  FAlive := TAtlasVcsSectionAlive.Create;
  FAliveRef := FAlive;
  FParts := TList<TAtlasVcsSettingsPart>.Create;
  FKind := Add(TAtlasSettingsVcsPart.Create) as TAtlasSettingsVcsPart;
  FTools := Add(TAtlasSettingsVcsToolsPart.Create) as TAtlasSettingsVcsToolsPart;
  FProject := Add(TAtlasSettingsVcsProjectPart.Create) as TAtlasSettingsVcsProjectPart;
  FProjects := Add(TAtlasSettingsVcsProjectsPart.Create) as TAtlasSettingsVcsProjectsPart;
  FProjectAdd := Add(TAtlasSettingsVcsProjectAddPart.Create) as TAtlasSettingsVcsProjectAddPart;
  FServers := Add(TAtlasSettingsVcsServersPart.Create) as TAtlasSettingsVcsServersPart;
  FBranch := Add(TAtlasSettingsVcsBranchPart.Create) as TAtlasSettingsVcsBranchPart;
end;

destructor TAtlasVcsSettingsSection.Destroy;
var
  mPart: TAtlasVcsSettingsPart;
begin
  Close;
  if FParts <> nil then
  begin
    for mPart in FParts do
    begin
      mPart.Free;
    end;
  end;
  FreeAndNil(FParts);
  FAlive := nil;
  FAliveRef := nil;
  inherited Destroy;
end;

function TAtlasVcsSettingsSection.Add(APart: TAtlasVcsSettingsPart): TAtlasVcsSettingsPart;
begin
  FParts.Add(APart);
  Result := APart;
end;

function TAtlasVcsSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasVcsSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasVcsSettingsSection.BuildRows;
var
  mPart: TAtlasVcsSettingsPart;
begin
  ModuleSwitch('vcs.enabled');
  FOwner := TAtlasVcsSettingsOwner.CreateFor(Host, FParts);
  for mPart in FParts do
  begin
    mPart.Attached(FOwner);
  end;
  // Reihenfolge der Seite wie vor #1905: Art, Programme, Projekt, Tabellen, Links, Branches.
  FKind.Build;
  FTools.Build;
  FProject.Build;
  FProjects.Build;
  FServers.Build;
  FKind.Build2;
  FBranch.Build;
end;

procedure TAtlasVcsSettingsSection.Load(const AValues: IAtlasSettingsValues);
var
  mPart: TAtlasVcsSettingsPart;
begin
  if Closed or (FOwner = nil) then
  begin
    Exit;
  end;
  for mPart in FParts do
  begin
    mPart.Load(AValues);
  end;
end;

procedure TAtlasVcsSettingsSection.Save(const AValues: IAtlasSettingsValues);
var
  mPart: TAtlasVcsSettingsPart;
begin
  if Closed or (FOwner = nil) then
  begin
    Exit;
  end;
  for mPart in FParts do
  begin
    mPart.Save(AValues);
  end;
end;

procedure TAtlasVcsSettingsSection.WindowReady;
var
  mPart: TAtlasVcsSettingsPart;
begin
  if Closed or (FOwner = nil) then
  begin
    Exit;
  end;
  for mPart in FParts do
  begin
    mPart.WindowReady;
  end;
end;

function TAtlasVcsSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  // „Anmeldung am Server nötig – prüfen …“ (#1287): Zeile für den Ordner zeigen und prüfen.
  Result := not Closed and (FOwner <> nil) and SameText(AKey, TAtlasSettingsVcsProjectsPart.cProjectsKey) and
    (Trim(AArgument) <> '');
  if Result then
  begin
    FServers.RevealVcsServer(AArgument);
  end;
end;

function TAtlasVcsSettingsSection.Alive: TFunc<Boolean>;
var
  mRef: IInterface;
  mAlive: TAtlasVcsSectionAlive;
begin
  mRef := FAliveRef;
  mAlive := FAlive;
  Result :=
    function: Boolean
    begin
      Result := (mRef <> nil) and mAlive.Open;
    end;
end;

procedure TAtlasVcsSettingsSection.Close;
var
  mPart: TAtlasVcsSettingsPart;
begin
  if FAlive <> nil then
  begin
    FAlive.Open := False;
  end;
  if FParts <> nil then
  begin
    for mPart in FParts do
    begin
      mPart.Attached(nil);
    end;
  end;
  FreeAndNil(FOwner);
  inherited Close;
end;

end.
