unit Atlas.IDE.Welcome.Adapters.SettingsSection;

// Abschnitt „Willkommensseite“ (#1456) für die Optionsseite von Base: hüllt
// TAtlasWelcomeSettingsSection in den Vertrag IAtlasSettingsSection und gibt
// ihn mit der letzten Referenz frei.

interface

uses
  Atlas.UI.Settings.Contract,
  Atlas.UI.Welcome.SettingsSection;

type
  TAtlasIdeWelcomeSettingsSection = class(TInterfacedObject, IAtlasSettingsSection)
  private
    FSection: TAtlasWelcomeSettingsSection;
  public
    /// <summary>ASection gehört danach dieser Hülle.</summary>
    constructor Create(ASection: TAtlasWelcomeSettingsSection);
    destructor Destroy; override;
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure WindowReady;
    function Show(const AKey, AArgument: string): Boolean;
    procedure Close;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasIdeWelcomeSettingsSection }

constructor TAtlasIdeWelcomeSettingsSection.Create(ASection: TAtlasWelcomeSettingsSection);
begin
  inherited Create;
  FSection := ASection;
end;

destructor TAtlasIdeWelcomeSettingsSection.Destroy;
begin
  FreeAndNil(FSection);
  inherited Destroy;
end;

function TAtlasIdeWelcomeSettingsSection.OwnerId: string;
begin
  Result := TAtlasWelcomeSettingsSection.cOwnerId;
end;

function TAtlasIdeWelcomeSettingsSection.AreaId: string;
begin
  Result := TAtlasWelcomeSettingsSection.cAreaId;
end;

procedure TAtlasIdeWelcomeSettingsSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  FSection.Build(AHost);
end;

procedure TAtlasIdeWelcomeSettingsSection.Load(const AValues: IAtlasSettingsValues);
begin
  FSection.Load(AValues);
end;

procedure TAtlasIdeWelcomeSettingsSection.Save(const AValues: IAtlasSettingsValues);
begin
  FSection.Save(AValues);
end;

procedure TAtlasIdeWelcomeSettingsSection.WindowReady;
begin
  FSection.WindowReady;
end;

function TAtlasIdeWelcomeSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  // „Einstellung zeigen“ findet die Seite über die gebundenen Schlüssel selbst; keine Vorgaben.
  Result := False;
end;

procedure TAtlasIdeWelcomeSettingsSection.Close;
begin
  FSection.Close;
end;

end.
