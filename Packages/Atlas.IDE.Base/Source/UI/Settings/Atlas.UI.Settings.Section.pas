unit Atlas.UI.Settings.Section;

// Grundlage für Abschnitte der Module im Optionsdialog (#1455): TAtlasSettingsSection
// setzt IAtlasSettingsSection mit leeren Vorgaben um und reicht die Bausteine der Seite typisiert weiter
// (Schalter, Zahl, Text, Tastenkürzel, Auswahl, eigene Elemente). Ein Modul leitet je Reiter eine Klasse ab,
// überschreibt OwnerId, AreaId und BuildRows und, wenn es eigene Elemente hat, Load und Save.
// TAtlasSettingsSectionFactory ist der Anbieter dazu: Er legt für jede Optionsseite einen neuen Abschnitt der
// Klasse an. Die Elemente gehören der Seite; nach Close greift der Abschnitt nicht mehr auf sie zu.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox;

type
  TAtlasSettingsSection = class(TInterfacedObject, IAtlasSettingsSection)
  private
    FHost: IAtlasSettingsSectionHost;
    FClosed: Boolean;
  protected
    /// <summary>Elemente des Abschnitts über die Bausteine unten anlegen; Host ist gesetzt.</summary>
    procedure BuildRows; virtual; abstract;
    procedure Title(const ACaption: string);
    function Switch(const AKey, ACaption: string): TCheckBox;
    /// <summary>Schalter des Moduls mit der Beschriftung aus dem Katalog.</summary>
    function ModuleSwitch(const AKey: string): TCheckBox;
    function Number(const AKey, ACaption: string): TEdit;
    function Line(const AKey, ACaption: string): TEdit;
    function Key(const AKey, ACaption: string): TEdit;
    function Choice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
    function OwnCheck(const ACaption: string; const AKeys: TArray<string>): TCheckBox;
    function OwnNumber(const ACaption: string; const AKeys: TArray<string>): TEdit;
    function OwnText(const ACaption: string; const AKeys: TArray<string>): TEdit;
    function OwnChoice(const ACaption: string; const ACaptions, AKeys: TArray<string>): TAtlasChoiceBox;
    property Host: IAtlasSettingsSectionHost read FHost;
  public
    constructor Create; virtual;
    /// <summary>Meldet in der Composition eines Moduls über AScope eine Fabrik dieser Klasse an: je Optionsseite
    /// ein neuer Abschnitt, bis zum Abmelden des Moduls.</summary>
    class procedure ProvideIn(const AScope: IAtlasModuleScope);
    { IAtlasSettingsSection }
    function OwnerId: string; virtual; abstract;
    function AreaId: string; virtual; abstract;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues); virtual;
    procedure Save(const AValues: IAtlasSettingsValues); virtual;
    procedure WindowReady; virtual;
    function Show(const AKey, AArgument: string): Boolean; virtual;
    procedure Close; virtual;
    property Closed: Boolean read FClosed;
  end;

  TAtlasSettingsSectionClass = class of TAtlasSettingsSection;

  /// <summary>Anbieter für GScope.Provide(IAtlasSettingsSectionProvider, …): je Optionsseite ein neuer Abschnitt
  /// der Klasse.</summary>
  TAtlasSettingsSectionFactory = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  private
    FSectionClass: TAtlasSettingsSectionClass;
  public
    constructor Create(ASectionClass: TAtlasSettingsSectionClass);
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

{ TAtlasSettingsSection }

constructor TAtlasSettingsSection.Create;
begin
  inherited Create;
end;

class procedure TAtlasSettingsSection.ProvideIn(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasSettingsSectionProvider,
    TAtlasSettingsSectionFactory.Create(Self) as IAtlasSettingsSectionProvider);
end;

procedure TAtlasSettingsSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  if FClosed or (FHost <> nil) then
  begin
    Exit;
  end;
  FHost := AHost;
  BuildRows;
end;

procedure TAtlasSettingsSection.Title(const ACaption: string);
begin
  FHost.AddTitle(ACaption);
end;

function TAtlasSettingsSection.Switch(const AKey, ACaption: string): TCheckBox;
begin
  Result := FHost.AddSwitch(AKey, ACaption) as TCheckBox;
end;

function TAtlasSettingsSection.ModuleSwitch(const AKey: string): TCheckBox;
begin
  Result := FHost.AddModuleSwitch(AKey) as TCheckBox;
end;

function TAtlasSettingsSection.Number(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddNumber(AKey, ACaption) as TEdit;
end;

function TAtlasSettingsSection.Line(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddText(AKey, ACaption) as TEdit;
end;

function TAtlasSettingsSection.Key(const AKey, ACaption: string): TEdit;
begin
  Result := FHost.AddKey(AKey, ACaption) as TEdit;
end;

function TAtlasSettingsSection.Choice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TAtlasChoiceBox;
begin
  Result := FHost.AddChoice(AKey, ACaption, ACaptions, AValues) as TAtlasChoiceBox;
end;

function TAtlasSettingsSection.OwnCheck(const ACaption: string; const AKeys: TArray<string>): TCheckBox;
begin
  Result := FHost.AddOwnCheck(ACaption, AKeys) as TCheckBox;
end;

function TAtlasSettingsSection.OwnNumber(const ACaption: string; const AKeys: TArray<string>): TEdit;
begin
  Result := FHost.AddOwnNumber(ACaption, AKeys) as TEdit;
end;

function TAtlasSettingsSection.OwnText(const ACaption: string; const AKeys: TArray<string>): TEdit;
begin
  Result := FHost.AddOwnText(ACaption, AKeys) as TEdit;
end;

function TAtlasSettingsSection.OwnChoice(const ACaption: string;
  const ACaptions, AKeys: TArray<string>): TAtlasChoiceBox;
begin
  Result := FHost.AddOwnChoice(ACaption, ACaptions, AKeys) as TAtlasChoiceBox;
end;

procedure TAtlasSettingsSection.Load(const AValues: IAtlasSettingsValues);
begin
  // Ohne eigene Elemente: Die Seite lädt die gebundenen selbst.
end;

procedure TAtlasSettingsSection.Save(const AValues: IAtlasSettingsValues);
begin
  // Ohne eigene Elemente: Die Seite speichert die gebundenen selbst.
end;

procedure TAtlasSettingsSection.WindowReady;
begin
  // Ohne Listen, die ein Fenster brauchen.
end;

function TAtlasSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  // Keine Einstellung mit Vorgabe.
  Result := False;
end;

procedure TAtlasSettingsSection.Close;
begin
  FClosed := True;
  FHost := nil;
end;

{ TAtlasSettingsSectionFactory }

constructor TAtlasSettingsSectionFactory.Create(ASectionClass: TAtlasSettingsSectionClass);
begin
  inherited Create;
  FSectionClass := ASectionClass;
end;

function TAtlasSettingsSectionFactory.CreateSection: IAtlasSettingsSection;
begin
  Result := FSectionClass.Create;
end;

end.
