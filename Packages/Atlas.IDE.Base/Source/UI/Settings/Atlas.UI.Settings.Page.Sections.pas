unit Atlas.UI.Settings.Page.Sections;

// Abschnitte der Module auf der Optionsseite „Atlas“ (#1455, ADR 0017 Entscheidung 3): Jeder
// IAtlasSettingsSectionProvider der Registry liefert einen eigenen Abschnitt, den der Teil in den Reiter seines
// Bereichs baut (Bausteine über IAtlasSettingsSectionHost). Geht ein Modul, schließt er seinen Abschnitt; seine
// Werte bleiben erhalten.

interface

uses
  System.Generics.Collections,
  Vcl.Controls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Bindings,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Abschnitte der Module (#1455) mit ihrer Anmeldung und ihrem Host, gleicher Index; der letzte Teil der
  /// Seite: lädt und speichert nach den übrigen.</summary>
  TAtlasSettingsSectionsPart = class(TAtlasSettingsPagePart)
  private
    FSections: TArray<IAtlasSettingsSection>;
    FProviders: TArray<IAtlasSettingsSectionProvider>;
    FHosts: TArray<IAtlasSettingsSectionHost>;
    /// <summary>Felder der Abschnitte an Plugin-Einstellungen.</summary>
    FBindings: TAtlasSettingsBindings;
    /// <summary>Reiter, die erst für einen Abschnitt entstanden sind: Bereich und Index in den Reitern der Seite.
    /// </summary>
    FAreas: TArray<TPair<string, Integer>>;
    FWatch: IAtlasRegistryListener;
    FWatchRegistration: IAtlasRegistration;
    /// <summary>Reiter des Bereichs AArea (x-area); -1 ohne.</summary>
    function SheetOfArea(const AArea: string): Integer;
    procedure AddSection(const AProvider: IAtlasSettingsSectionProvider);
    procedure AddBuilt(const AProvider: IAtlasSettingsSectionProvider; const ASection: IAtlasSettingsSection);
    procedure AddBinding(const AName: string; AControl: TControl; const AValues: TArray<string>);
    function Values(const AStore: IAtlasMemorySettingsStore): IAtlasSettingsValues;
    /// <summary>Abschnitte abgemeldeter Module schließen (Regel 3).</summary>
    procedure DropMissing;
    procedure CloseAll;
  public
    constructor Create(APage: TAtlasSettingsPageHost);
    destructor Destroy; override;
    /// <summary>Abschnitte der Module aus der Registry bauen und auf Abmeldungen hören.</summary>
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    /// <summary>Die Seite hat ein Fenster: Abschnitte füllen ihre Listen.</summary>
    procedure WindowReady; override;
    /// <summary>Einstellung AName (Registry-Name) mit Vorgabe AArgument zeigen (z. B. „zuordnen …“ mit dem
    /// Projekt): Der Abschnitt des Moduls, dem sie gehört, legt an bzw. wählt. False ohne Abschnitt dazu.
    /// </summary>
    function ShowSettingArgument(const AName, AArgument: string): Boolean;
    /// <summary>Zum Testen: Zahl der gebauten Abschnitte.</summary>
    function Count: Integer;
  end;

implementation

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.StoreValues,
  Atlas.Core.Modules.Registry,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox;

const
  cSectionKeyMissing = 'Einstellung %s ist keine Plugin-Einstellung';
  cSectionChoiceMismatch = 'Auswahl %s: Anzeige und Werte verschieden lang';

type
  /// <summary>Host und Wächter der Abschnitte lösen sich von der Seite, wenn sie schließt (#1455).</summary>
  IAtlasSettingsDetachable = interface
    ['{816EC08A-0148-46B9-AD92-1374D8305711}']
    procedure Detach;
  end;

  /// <summary>Bausteine der Seite für einen Abschnitt eines Moduls (#1455). Hält die Seite nur, solange sie lebt;
  /// nach dem Schließen der Seite tut er nichts mehr.</summary>
  TAtlasSettingsSectionHost = class(TInterfacedObject, IAtlasSettingsSectionHost, IAtlasSettingsDetachable)
  private
    FPart: TAtlasSettingsSectionsPart;
    FPage: TAtlasSettingsPageHost;
    function NameOf(const AKey: string): string;
  public
    constructor Create(APart: TAtlasSettingsSectionsPart);
    procedure Detach;
    procedure AddTitle(const ACaption: string);
    function AddHint(const AText: string; AHeight: Integer): TControl;
    function AddSwitch(const AKey, ACaption: string): TControl;
    function AddNumber(const AKey, ACaption: string): TControl;
    function AddText(const AKey, ACaption: string): TControl;
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TControl;
    function AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
    procedure Attach(ARow, AAnchor: TControl);
    procedure Changed;
    procedure Allow(AControl: TControl; AEnabled: Boolean);
    function ListReady(AControl: TWinControl): Boolean;
    function Reveal(const AKey: string): Boolean;
  end;

  /// <summary>Hört für die Seite auf die Registry: Geht ein Modul, schließt die Seite seinen Abschnitt (Regel 2).
  /// </summary>
  TAtlasSettingsSectionWatch = class(TInterfacedObject, IAtlasRegistryListener, IAtlasSettingsDetachable)
  private
    FPart: TAtlasSettingsSectionsPart;
  public
    constructor Create(APart: TAtlasSettingsSectionsPart);
    procedure Detach;
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
  end;

{ TAtlasSettingsSectionHost }

constructor TAtlasSettingsSectionHost.Create(APart: TAtlasSettingsSectionsPart);
begin
  inherited Create;
  FPart := APart;
  FPage := APart.FPage;
end;

procedure TAtlasSettingsSectionHost.Detach;
begin
  FPart := nil;
  FPage := nil;
end;

function TAtlasSettingsSectionHost.NameOf(const AKey: string): string;
begin
  Result := TAtlasSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  if Result = '' then
  begin
    raise EAtlasSettingsKey.CreateFmt(cSectionKeyMissing, [AKey]);
  end;
end;

procedure TAtlasSettingsSectionHost.AddTitle(const ACaption: string);
begin
  if FPage <> nil then
  begin
    FPage.AddTitleText(ACaption);
  end;
end;

function TAtlasSettingsSectionHost.AddHint(const AText: string; AHeight: Integer): TControl;
begin
  Result := nil;
  if FPage <> nil then
  begin
    Result := FPage.AddWrappedLabel(AHeight, AText);
  end;
end;

function TAtlasSettingsSectionHost.AddSwitch(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddCheck(ACaption);
  FPart.AddBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddNumber(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddNumber(ACaption);
  FPart.AddBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddText(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddTextLine(ACaption);
  FPart.AddBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddChoice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  if Length(ACaptions) <> Length(AValues) then
  begin
    raise EAtlasSettingsKey.CreateFmt(cSectionChoiceMismatch, [AKey]);
  end;
  mName := NameOf(AKey);
  Result := FPage.AddChoice(ACaption, ACaptions);
  FPart.AddBinding(mName, Result, AValues);
end;

function TAtlasSettingsSectionHost.AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
var
  mNames: TArray<string>;
  mKey, mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mNames := nil;
  for mKey in AKeys do
  begin
    mNames := mNames + [NameOf(mKey)];
  end;
  Result := FPage.AddPanel(AHeight);
  if Length(mNames) > 0 then
  begin
    // Die Bindung hängt an der Zeile der Seite, nie an Elementen des Moduls: Die gibt das Modul in Close frei.
    FPage.Marks.Bind(Result, mNames);
    for mName in mNames do
    begin
      FPage.Bind(mName, Result);
    end;
  end;
end;

procedure TAtlasSettingsSectionHost.Attach(ARow, AAnchor: TControl);
begin
  if FPage <> nil then
  begin
    FPage.Attach(ARow, AAnchor);
  end;
end;

procedure TAtlasSettingsSectionHost.Changed;
begin
  if FPage <> nil then
  begin
    FPage.RefreshMarks;
  end;
end;

procedure TAtlasSettingsSectionHost.Allow(AControl: TControl; AEnabled: Boolean);
begin
  if (FPage <> nil) and (AControl <> nil) then
  begin
    FPage.Allow(AControl, AEnabled);
  end;
end;

function TAtlasSettingsSectionHost.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FPage <> nil) and (AControl <> nil) and FPage.ListReady(AControl);
end;

function TAtlasSettingsSectionHost.Reveal(const AKey: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := TAtlasSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  Result := (mName <> '') and FPage.Reveal(mName);
end;

{ TAtlasSettingsSectionWatch }

constructor TAtlasSettingsSectionWatch.Create(APart: TAtlasSettingsSectionsPart);
begin
  inherited Create;
  FPart := APart;
end;

procedure TAtlasSettingsSectionWatch.Detach;
begin
  FPart := nil;
end;

procedure TAtlasSettingsSectionWatch.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if (FPart <> nil) and IsEqualGUID(AChange.IID, IAtlasSettingsSectionProvider) then
  begin
    FPart.DropMissing;
  end;
end;

/// <summary>Zeigen AFirst und ASecond auf dasselbe Objekt (Vergleich über IInterface, nicht über die
/// Schnittstelle)?</summary>
function SameInstance(const AFirst, ASecond: IInterface): Boolean;
begin
  Result := (AFirst as IInterface) = (ASecond as IInterface);
end;

{ TAtlasSettingsSectionsPart }

constructor TAtlasSettingsSectionsPart.Create(APage: TAtlasSettingsPageHost);
begin
  inherited Create(APage);
  FBindings := TAtlasSettingsBindings.Create;
end;

destructor TAtlasSettingsSectionsPart.Destroy;
begin
  // Zuerst die Abschnitte schließen: Ihre Elemente liegen in Zeilen der Seite.
  CloseAll;
  FreeAndNil(FBindings);
  inherited Destroy;
end;

function TAtlasSettingsSectionsPart.SheetOfArea(const AArea: string): Integer;
var
  mSheet, mIndex: Integer;
  mName: string;
begin
  // Reiter eines Bereichs: der erste, auf dem eine Einstellung dieses Bereichs (x-area) steht.
  for mSheet := 0 to High(FPage.Boxes) do
  begin
    for mName in FPage.Marks.NamesIn(FPage.Boxes[mSheet]) do
    begin
      mIndex := FPage.Catalog.IndexOfName(mName);
      if (mIndex >= 0) and SameText(FPage.Catalog[mIndex].Area, AArea) then
      begin
        Exit(mSheet);
      end;
    end;
  end;
  for mSheet := 0 to High(FAreas) do
  begin
    if SameText(FAreas[mSheet].Key, AArea) then
    begin
      Exit(FAreas[mSheet].Value);
    end;
  end;
  Result := -1;
end;

procedure TAtlasSettingsSectionsPart.Build;
var
  mItem: IInterface;
  mProvider: IAtlasSettingsSectionProvider;
begin
  // Abschnitte der Module (#1455): in den Reiter ihres Bereichs, hinter die Einstellungen von Base.
  for mItem in AtlasModuleRegistry.FindAll(IAtlasSettingsSectionProvider) do
  begin
    if Supports(mItem, IAtlasSettingsSectionProvider, mProvider) then
    begin
      AddSection(mProvider);
    end;
  end;
  FWatch := TAtlasSettingsSectionWatch.Create(Self);
  FWatchRegistration := AtlasModuleRegistry.Subscribe(FWatch);
end;

procedure TAtlasSettingsSectionsPart.AddSection(const AProvider: IAtlasSettingsSectionProvider);
var
  mSection: IAtlasSettingsSection;
begin
  try
    mSection := AProvider.CreateSection;
  except
    on E: Exception do
    begin
      TAtlasGuard.ReportProvider('settings', E);
      Exit;
    end;
  end;
  if mSection = nil then
  begin
    Exit;
  end;
  AddBuilt(AProvider, mSection);
end;

procedure TAtlasSettingsSectionsPart.AddBuilt(const AProvider: IAtlasSettingsSectionProvider;
  const ASection: IAtlasSettingsSection);
var
  mSheet: Integer;
  mHost: TAtlasSettingsSectionHost;
  mHostRef: IAtlasSettingsSectionHost;
begin
  mSheet := SheetOfArea(ASection.AreaId);
  if mSheet < 0 then
  begin
    // Unbekannter Bereich: eigener Reiter mit der Beschriftung des Katalogs (sonst die Id).
    FPage.AddSheetCaption(FPage.Catalog.AreaCaption(ASection.AreaId, TAtlasStrings.Language = TAtlasLanguage.English));
    mSheet := High(FPage.Sheets);
    FAreas := FAreas + [TPair<string, Integer>.Create(ASection.AreaId, mSheet)];
  end;
  FPage.ContinueSheet(mSheet);
  mHost := TAtlasSettingsSectionHost.Create(Self);
  mHostRef := mHost;
  try
    ASection.Build(mHostRef);
  except
    on E: Exception do
    begin
      // Ein fehlerhafter Abschnitt darf den Optionsdialog nicht verhindern; er bleibt zu und wird gemeldet.
      mHost.Detach;
      TAtlasGuard.ReportProvider('settings:' + ASection.OwnerId, E);
      ASection.Close;
      Exit;
    end;
  end;
  FSections := FSections + [ASection];
  FProviders := FProviders + [AProvider];
  FHosts := FHosts + [mHostRef];
end;

procedure TAtlasSettingsSectionsPart.AddBinding(const AName: string; AControl: TControl;
  const AValues: TArray<string>);
var
  mKind: TAtlasSettingsBindingKind;
begin
  mKind := sbkText;
  if AControl is TCheckBox then
  begin
    mKind := sbkCheck;
  end
  else if AControl is TAtlasChoiceBox then
  begin
    mKind := sbkChoice;
  end;
  FPage.BindValues(FBindings, AName, AControl, mKind, AValues);
  FPage.Marks.Bind(AControl, [AName]);
end;

function TAtlasSettingsSectionsPart.Values(const AStore: IAtlasMemorySettingsStore): IAtlasSettingsValues;
begin
  Result := TAtlasSettingsStoreValues.Create(FPage.Catalog, AStore,
    TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults));
end;

procedure TAtlasSettingsSectionsPart.Load(const ASettings: TAtlasPluginSettings);
var
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
  mSection: IAtlasSettingsSection;
begin
  if (Length(FSections) = 0) and (FBindings.Count = 0) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  FBindings.Load(mStore);
  mValues := Values(mStore);
  for mSection in FSections do
  begin
    mSection.Load(mValues);
  end;
end;

procedure TAtlasSettingsSectionsPart.Save(var ASettings: TAtlasPluginSettings);
var
  mStore: IAtlasMemorySettingsStore;
  mSection: IAtlasSettingsSection;
  mValues: IAtlasSettingsValues;
begin
  if (Length(FSections) = 0) and (FBindings.Count = 0) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  FBindings.Save(mStore);
  mValues := Values(mStore);
  for mSection in FSections do
  begin
    mSection.Save(mValues);
  end;
  ASettings.Load(mStore);
end;

procedure TAtlasSettingsSectionsPart.DropMissing;
var
  mCurrent: TArray<IInterface>;
  mKeep: TArray<IAtlasSettingsSection>;
  mKeepProviders: TArray<IAtlasSettingsSectionProvider>;
  mKeepHosts: TArray<IAtlasSettingsSectionHost>;
  mIndex: Integer;
  mItem: IInterface;
  mFound: Boolean;
begin
  // Ein abgemeldetes Modul erreicht danach nichts mehr (Regel 3): Abschnitt schließen und vergessen. Seine
  // Werte bleiben, gebundene Felder gehören der Seite. Neue Abschnitte zeigt erst die nächste Seite.
  mCurrent := AtlasModuleRegistry.FindAll(IAtlasSettingsSectionProvider);
  mKeep := nil;
  mKeepProviders := nil;
  mKeepHosts := nil;
  for mIndex := 0 to High(FSections) do
  begin
    mFound := False;
    for mItem in mCurrent do
    begin
      if SameInstance(mItem, FProviders[mIndex]) then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      mKeep := mKeep + [FSections[mIndex]];
      mKeepProviders := mKeepProviders + [FProviders[mIndex]];
      mKeepHosts := mKeepHosts + [FHosts[mIndex]];
    end
    else
    begin
      (FHosts[mIndex] as IAtlasSettingsDetachable).Detach;
      FSections[mIndex].Close;
    end;
  end;
  FSections := mKeep;
  FProviders := mKeepProviders;
  FHosts := mKeepHosts;
end;

procedure TAtlasSettingsSectionsPart.CloseAll;
var
  mIndex: Integer;
begin
  if FWatch <> nil then
  begin
    (FWatch as IAtlasSettingsDetachable).Detach;
  end;
  if FWatchRegistration <> nil then
  begin
    FWatchRegistration.Revoke;
  end;
  FWatchRegistration := nil;
  FWatch := nil;
  for mIndex := 0 to High(FSections) do
  begin
    (FHosts[mIndex] as IAtlasSettingsDetachable).Detach;
    FSections[mIndex].Close;
  end;
  FSections := nil;
  FProviders := nil;
  FHosts := nil;
  if FBindings <> nil then
  begin
    FBindings.Clear;
  end;
end;

procedure TAtlasSettingsSectionsPart.WindowReady;
var
  mSection: IAtlasSettingsSection;
begin
  for mSection in FSections do
  begin
    mSection.WindowReady;
  end;
end;

function TAtlasSettingsSectionsPart.ShowSettingArgument(const AName, AArgument: string): Boolean;
var
  mIndex: Integer;
  mKey: string;
  mSection: IAtlasSettingsSection;
begin
  Result := False;
  mIndex := FPage.Catalog.IndexOfName(AName);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mKey := FPage.Catalog[mIndex].Key;
  for mSection in FSections do
  begin
    if mSection.Show(mKey, AArgument) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasSettingsSectionsPart.Count: Integer;
begin
  Result := Length(FSections);
end;

end.
