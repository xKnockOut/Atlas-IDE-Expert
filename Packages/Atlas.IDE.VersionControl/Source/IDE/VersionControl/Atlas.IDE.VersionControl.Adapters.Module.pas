unit Atlas.IDE.VersionControl.Adapters.Module;

// Modulklasse der Versionsverwaltung (#1891): erfüllt IAtlasModule und, nach dem Speichern der Optionen (#1905),
// IAtlasAppliesSettings und IAtlasFollowsTheme: settings.json neu lesen, damit ein neuer Pfad und ein neues
// Zeitlimit sofort gelten, und die Änderungsmarken (#507) nachziehen, solange der Teil „Vcs“ der Feature-Tabelle
// läuft. Ob er läuft, fragt sie die Composition (Atlas.IDE.VersionControl.Composition) über AStarted.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasVcsModule = class(TInterfacedObject, IAtlasModule, IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    cModuleId = 'atlas.vcs';
    cSwitch = 'vcs';
  private
    FActive: Boolean;
    FStarted: TFunc<Boolean>;
  public
    constructor Create(const AStarted: TFunc<Boolean>);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.VersionControl.LineChanges;

{ TAtlasVcsModule }

constructor TAtlasVcsModule.Create(const AStarted: TFunc<Boolean>);
begin
  inherited Create;
  FStarted := AStarted;
end;

function TAtlasVcsModule.Info: TAtlasModuleInfo;
begin
  // Die Versionsverwaltung lief bisher auch im abgesicherten Start (Projektzustand, Änderungsmarken).
  Result := TAtlasModuleHost.Info(cModuleId, 'Versionsverwaltung', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;

procedure TAtlasVcsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasVcsModule.Stop;
begin
  FActive := False;
end;

function TAtlasVcsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TAtlasVcsModule.ApplySettings;
begin
  TAtlasIdeVcs.Reload;
  // Änderungsmarken (#507): nur, solange der Teil läuft.
  if FStarted() then
  begin
    TAtlasIdeLineChanges.ApplySettings;
  end;
end;

procedure TAtlasVcsModule.ThemeChanged;
begin
  if FStarted() then
  begin
    TAtlasIdeLineChanges.ThemeChanged;
  end;
end;

end.
