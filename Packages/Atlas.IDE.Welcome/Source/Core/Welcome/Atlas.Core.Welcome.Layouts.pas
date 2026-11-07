unit Atlas.Core.Welcome.Layouts;

// Benannte Layouts der Willkommensseite (#767) und ihr Abgleich mit den
// Plugin-Einstellungen, ohne VCL und Open Tools API.
// - TAtlasWelcomeLayouts: Liste der Layouts („Standard“, „Arbeit“,
//   „Präsentation“ …) mit dem aktiven; JSON für welcomePage.layouts. Die
//   Vorgabe ist ein Layout „Standard“ mit den Plätzen von Atlas (#753); sie
//   wird als '' gespeichert, damit Export und Zurücksetzen (#723) nur echte
//   Änderungen sehen.
// - TAtlasWelcomeCustomizing: Katalog der Atlas-Bereiche mit dem Schlüssel
//   ihrer Einstellung. Sichtbar ist ein Bereich, wenn seine Einstellung an
//   ist (Auge, Schnellschalter #604 und Optionsseite #227 sind dasselbe).
//   Das aktive Layout liest seine Sichtbarkeit und Spaltenzahl aus den
//   Einstellungen; beim Wechsel des Layouts merkt sich das alte seine
//   Sichtbarkeit, das neue schreibt seine in die Einstellungen. Neue Bereiche
//   späterer Versionen kommen ans Ende der Spalte mit dem meisten Platz.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout;

type
  /// <summary>Ein Atlas-Bereich, der sich anordnen und ausblenden lässt.</summary>
  TAtlasWelcomeCatalogItem = record
    Id: string;
    /// <summary>Registry-Name der Einstellung, die den Bereich zeigt (z. B. WelcomePageStatusTile).</summary>
    Setting: string;
    class function Create(const AId, ASetting: string): TAtlasWelcomeCatalogItem; static;
  end;

  TAtlasWelcomeLayouts = record
  public
    Items: TArray<TAtlasWelcomeLayout>;
    /// <summary>Index des aktiven Layouts in Items.</summary>
    Active: Integer;
    /// <summary>Ein Layout „Standard“ mit den Plätzen von Atlas.</summary>
    class function Defaults: TAtlasWelcomeLayouts; static;
    /// <summary>Liste aus welcomePage.layouts und welcomePage.activeLayout; '' oder ungültig = Defaults,
    /// unbekannter Name = erstes Layout.</summary>
    class function FromJson(const AText, AActive: string): TAtlasWelcomeLayouts; static;
    /// <summary>JSON-Liste; '' für die Vorgabe (IsDefault).</summary>
    function ToJson: string;
    /// <summary>Nur ein Layout „Standard“ mit der Anordnung von Atlas (Sichtbarkeit zählt nicht: sie steht in
    /// den Einstellungen der Bereiche).</summary>
    function IsDefault: Boolean;
    function IndexOf(const AName: string): Integer;
    function Names: TArray<string>;
    function Current: TAtlasWelcomeLayout;
    function ActiveName: string;
    /// <summary>Das aktive Layout ersetzt (Name bleibt).</summary>
    function WithCurrent(const ALayout: TAtlasWelcomeLayout): TAtlasWelcomeLayouts;
    /// <summary>AName aktivieren; False, wenn es das Layout nicht gibt.</summary>
    function Activated(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
    /// <summary>Kopie des aktiven Layouts unter AName, danach aktiv; False bei leerem oder vergebenem Namen.
    /// </summary>
    function Added(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
    /// <summary>Aktives Layout umbenennen; False bei leerem oder vergebenem Namen.</summary>
    function Renamed(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
    /// <summary>Aktives Layout löschen, danach ist das vorige aktiv; False beim letzten Layout.</summary>
    function Deleted(out ALayouts: TAtlasWelcomeLayouts): Boolean;
    /// <summary>ABase, sonst „ABase 2“, „ABase 3“ …, der noch frei ist.</summary>
    function UniqueName(const ABase: string): string;
    class function ValidName(const AName: string): Boolean; static;
  end;

  TAtlasWelcomeCustomizing = class
  public
    /// <summary>Alle Atlas-Bereiche in der Reihenfolge des Atlas-Layouts (ohne Kopf, Suchfeld und „Atlas“).
    /// </summary>
    class function Catalog: TArray<TAtlasWelcomeCatalogItem>; static;
    /// <summary>Registry-Name der Einstellung von AId; '' für Bereiche außerhalb des Katalogs.</summary>
    class function SettingOf(const AId: string): string; static;
    class function InCatalog(const AId: string): Boolean; static;
    /// <summary>Ist die Einstellung des Bereichs an? Bereiche außerhalb des Katalogs gelten als an.</summary>
    class function IsOn(const ASettings: TAtlasPluginSettings; const AId: string): Boolean; static;
    /// <summary>Einstellung des Bereichs an- oder ausschalten. Text-Schalter (welcomePage.whatsNew) bekommen
    /// beim Einschalten ihren Vorgabewert, beim Ausschalten "off".</summary>
    class function WithSection(const ASettings: TAtlasPluginSettings; const AId: string;
      AOn: Boolean): TAtlasPluginSettings; static;
    /// <summary>Layouts aus den Einstellungen; das aktive mit Spalten und Sichtbarkeit aus den Einstellungen.
    /// </summary>
    class function Load(const ASettings: TAtlasPluginSettings): TAtlasWelcomeLayouts; static;
    /// <summary>ALayouts in die Einstellungen (Liste, aktives Layout, Spalten); die Sichtbarkeit des aktiven
    /// Layouts kommt aus den Einstellungen.</summary>
    class function Stored(const ASettings: TAtlasPluginSettings;
      const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings; static;
    /// <summary>Wie Stored, dazu die Sichtbarkeit des aktiven Layouts in die Einstellungen der Bereiche.
    /// </summary>
    class function Applied(const ASettings: TAtlasPluginSettings;
      const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings; static;
    /// <summary>Layout AName aktivieren: das bisherige merkt sich seine Sichtbarkeit, das neue setzt seine.
    /// Unverändert, wenn es AName nicht gibt.</summary>
    class function Switched(const ASettings: TAtlasPluginSettings; const AName: string): TAtlasPluginSettings;
      static;
    /// <summary>„Zurücksetzen“: aktives Layout mit Plätzen, Breiten und Spalten von Atlas (#753); Name und
    /// Sichtbarkeit bleiben.</summary>
    class function Reset(const ASettings: TAtlasPluginSettings): TAtlasPluginSettings; static;
    /// <summary>Katalogbereiche aus ARegistered, deren Einstellung aus ist (Leiste „Ausgeblendet“).</summary>
    class function Hidden(const ASettings: TAtlasPluginSettings; const ARegistered: TArray<string>): TArray<string>;
      static;
    /// <summary>Bereiche aus ARegistered, die das aktive Layout nicht kennt, ans Ende der Spalte mit dem
    /// meisten Platz. AAdded nennt sie; gespeichert wird nur, wenn schon eigene Layouts gespeichert sind
    /// (sonst gilt weiter die Vorgabe).</summary>
    class function Adopted(const ASettings: TAtlasPluginSettings; const ARegistered: TArray<string>;
      const AWeight: TAtlasWelcomeWeight; out AAdded: TArray<string>): TAtlasPluginSettings; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.History;

{ TAtlasWelcomeCatalogItem }

class function TAtlasWelcomeCatalogItem.Create(const AId, ASetting: string): TAtlasWelcomeCatalogItem;
begin
  Result.Id := AId;
  Result.Setting := ASetting;
end;

{ TAtlasWelcomeLayouts }

class function TAtlasWelcomeLayouts.Defaults: TAtlasWelcomeLayouts;
begin
  Result.Items := [TAtlasWelcomeLayout.Atlas];
  Result.Active := 0;
end;

class function TAtlasWelcomeLayouts.ValidName(const AName: string): Boolean;
begin
  Result := Trim(AName) <> '';
end;

/// <summary>Layout aus AValue mit getrimmtem Namen; False bei ungültigem Eintrag oder leerem Namen.</summary>
function TryLayoutFrom(AValue: TJSONValue; out ALayout: TAtlasWelcomeLayout): Boolean;
begin
  Result := (AValue is TJSONObject) and TAtlasWelcomeLayout.FromJson(AValue.ToJSON, ALayout);
  if Result then
  begin
    ALayout.Name := Trim(ALayout.Name);
    Result := TAtlasWelcomeLayouts.ValidName(ALayout.Name);
  end;
end;

/// <summary>Gültige Layouts aus AList an ALayouts; ein ungültiger Eintrag fällt weg, doppelte Namen ebenso.
/// </summary>
procedure AddLayouts(var ALayouts: TAtlasWelcomeLayouts; AList: TJSONArray);
var
  mIndex: Integer;
  mLayout: TAtlasWelcomeLayout;
begin
  for mIndex := 0 to AList.Count - 1 do
  begin
    if TryLayoutFrom(AList.Items[mIndex], mLayout) and (ALayouts.IndexOf(mLayout.Name) < 0) then
    begin
      ALayouts.Items := ALayouts.Items + [mLayout];
    end;
  end;
end;

class function TAtlasWelcomeLayouts.FromJson(const AText, AActive: string): TAtlasWelcomeLayouts;
var
  mValue: TJSONValue;
begin
  Result := Defaults;
  if Trim(AText) <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(AText);
    try
      if mValue is TJSONArray then
      begin
        Result.Items := nil;
        AddLayouts(Result, TJSONArray(mValue));
      end;
    finally
      mValue.Free;
    end;
  end;
  if Length(Result.Items) = 0 then
  begin
    Result := Defaults;
  end;
  Result.Active := Result.IndexOf(Trim(AActive));
  if Result.Active < 0 then
  begin
    Result.Active := 0;
  end;
end;

function TAtlasWelcomeLayouts.ToJson: string;
var
  mLayout: TAtlasWelcomeLayout;
begin
  Result := '';
  if IsDefault then
  begin
    Exit;
  end;
  for mLayout in Items do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mLayout.ToJson;
  end;
  Result := '[' + Result + ']';
end;

function TAtlasWelcomeLayouts.IsDefault: Boolean;
var
  mLeft, mRight: TAtlasWelcomeLayout;
  mIndex: Integer;
begin
  Result := Length(Items) = 1;
  if not Result then
  begin
    Exit;
  end;
  mLeft := Items[0];
  mRight := TAtlasWelcomeLayout.Atlas;
  // Sichtbarkeit steht in den Einstellungen der Bereiche; für den Vergleich gleich setzen.
  mLeft.Slots := Copy(mLeft.Slots);
  for mIndex := 0 to High(mLeft.Slots) do
  begin
    mLeft.Slots[mIndex].Visible := True;
  end;
  Result := TAtlasWelcomeLayout.Same(mLeft, mRight);
end;

function TAtlasWelcomeLayouts.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Items) do
  begin
    if SameText(Items[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasWelcomeLayouts.Names: TArray<string>;
var
  mLayout: TAtlasWelcomeLayout;
begin
  Result := nil;
  for mLayout in Items do
  begin
    Result := Result + [mLayout.Name];
  end;
end;

function TAtlasWelcomeLayouts.Current: TAtlasWelcomeLayout;
begin
  if (Active >= 0) and (Active <= High(Items)) then
  begin
    Result := Items[Active];
  end
  else if Length(Items) > 0 then
  begin
    Result := Items[0];
  end
  else
  begin
    Result := TAtlasWelcomeLayout.Atlas;
  end;
end;

function TAtlasWelcomeLayouts.ActiveName: string;
begin
  Result := Current.Name;
end;

function TAtlasWelcomeLayouts.WithCurrent(const ALayout: TAtlasWelcomeLayout): TAtlasWelcomeLayouts;
begin
  Result := Self;
  Result.Items := Copy(Items);
  if Length(Result.Items) = 0 then
  begin
    Result.Items := [ALayout];
    Result.Active := 0;
    Exit;
  end;
  if (Result.Active < 0) or (Result.Active > High(Result.Items)) then
  begin
    Result.Active := 0;
  end;
  Result.Items[Result.Active] := ALayout;
  Result.Items[Result.Active].Name := Items[Result.Active].Name;
end;

function TAtlasWelcomeLayouts.Activated(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
var
  mIndex: Integer;
begin
  ALayouts := Self;
  mIndex := IndexOf(AName);
  Result := mIndex >= 0;
  if Result then
  begin
    ALayouts.Active := mIndex;
  end;
end;

function TAtlasWelcomeLayouts.Added(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
var
  mLayout: TAtlasWelcomeLayout;
begin
  ALayouts := Self;
  Result := ValidName(AName) and (IndexOf(AName) < 0);
  if not Result then
  begin
    Exit;
  end;
  mLayout := Current;
  mLayout.Name := Trim(AName);
  mLayout.Slots := Copy(mLayout.Slots);
  ALayouts.Items := Copy(Items) + [mLayout];
  ALayouts.Active := High(ALayouts.Items);
end;

function TAtlasWelcomeLayouts.Renamed(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
var
  mOther: Integer;
begin
  ALayouts := Self;
  mOther := IndexOf(AName);
  Result := ValidName(AName) and ((mOther < 0) or (mOther = Active)) and (Active >= 0) and (Active <= High(Items));
  if not Result then
  begin
    Exit;
  end;
  ALayouts.Items := Copy(Items);
  ALayouts.Items[Active].Name := Trim(AName);
end;

function TAtlasWelcomeLayouts.Deleted(out ALayouts: TAtlasWelcomeLayouts): Boolean;
begin
  ALayouts := Self;
  Result := (Length(Items) > 1) and (Active >= 0) and (Active <= High(Items));
  if not Result then
  begin
    Exit;
  end;
  ALayouts.Items := Copy(Items);
  Delete(ALayouts.Items, Active, 1);
  ALayouts.Active := Active - 1;
  if ALayouts.Active < 0 then
  begin
    ALayouts.Active := 0;
  end;
end;

function TAtlasWelcomeLayouts.UniqueName(const ABase: string): string;
var
  mNumber: Integer;
begin
  Result := Trim(ABase);
  mNumber := 1;
  while IndexOf(Result) >= 0 do
  begin
    Inc(mNumber);
    Result := Trim(ABase) + ' ' + IntToStr(mNumber);
  end;
end;

{ TAtlasWelcomeCustomizing }

class function TAtlasWelcomeCustomizing.Catalog: TArray<TAtlasWelcomeCatalogItem>;
begin
  Result := [
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cContinue, 'WelcomePageContinue'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cProjects, 'WelcomePageProjectStatus'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cHistory, 'WelcomePageTrends'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cTests, 'WelcomePageTests'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cState, 'WelcomePageStatusTile'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cUnsaved, 'WelcomePageUnsaved'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cNews, 'WelcomePageWhatsNew'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cDiscover, 'WelcomePageDiscover'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cSetup, 'WelcomePageProjectSetup'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cIssues, 'WelcomePageIssues'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cSprint, 'WelcomePageSprint'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.cHelp, 'WelcomePageHelp')];
end;

class function TAtlasWelcomeCustomizing.SettingOf(const AId: string): string;
var
  mItem: TAtlasWelcomeCatalogItem;
begin
  for mItem in Catalog do
  begin
    if SameText(mItem.Id, AId) then
    begin
      Exit(mItem.Setting);
    end;
  end;
  Result := '';
end;

class function TAtlasWelcomeCustomizing.InCatalog(const AId: string): Boolean;
begin
  Result := SettingOf(AId) <> '';
end;

class function TAtlasWelcomeCustomizing.IsOn(const ASettings: TAtlasPluginSettings; const AId: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
  mKey: string;
begin
  mKey := SettingOf(AId);
  if mKey = '' then
  begin
    Exit(True);
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if mStore.HasInteger(mKey) then
  begin
    Result := mStore.ReadInteger(mKey, 0) <> 0;
  end
  else
  begin
    Result := (mStore.Text(mKey) <> '') and not SameText(mStore.Text(mKey), 'off');
  end;
end;

class function TAtlasWelcomeCustomizing.WithSection(const ASettings: TAtlasPluginSettings; const AId: string;
  AOn: Boolean): TAtlasPluginSettings;
var
  mStore, mDefaults: IAtlasMemorySettingsStore;
  mKey, mValue: string;
begin
  Result := ASettings;
  mKey := SettingOf(AId);
  if (mKey = '') or (IsOn(ASettings, AId) = AOn) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if mStore.HasInteger(mKey) then
  begin
    if AOn then
    begin
      mStore.WriteInteger(mKey, 1);
    end
    else
    begin
      mStore.WriteInteger(mKey, 0);
    end;
  end
  else
  begin
    mValue := 'off';
    if AOn then
    begin
      mDefaults := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
      mValue := mDefaults.Text(mKey);
      // Ist schon die Vorgabe "off", gilt der erste Wert, der zeigt (welcomePage.whatsNew: afterUpdate).
      if SameText(mValue, 'off') or (mValue = '') then
      begin
        mValue := 'afterUpdate';
      end;
    end;
    mStore.WriteString(mKey, mValue);
  end;
  Result.Load(mStore);
end;

/// <summary>Sichtbarkeit der Katalogbereiche in ALayout aus den Einstellungen.</summary>
function VisibleFromSettings(const ALayout: TAtlasWelcomeLayout;
  const ASettings: TAtlasPluginSettings): TAtlasWelcomeLayout;
var
  mIndex: Integer;
begin
  Result := ALayout;
  Result.Slots := Copy(ALayout.Slots);
  for mIndex := 0 to High(Result.Slots) do
  begin
    if TAtlasWelcomeCustomizing.InCatalog(Result.Slots[mIndex].Id) then
    begin
      Result.Slots[mIndex].Visible := TAtlasWelcomeCustomizing.IsOn(ASettings, Result.Slots[mIndex].Id);
    end;
  end;
end;

class function TAtlasWelcomeCustomizing.Load(const ASettings: TAtlasPluginSettings): TAtlasWelcomeLayouts;
var
  mLayout: TAtlasWelcomeLayout;
begin
  Result := TAtlasWelcomeLayouts.FromJson(ASettings.WelcomePageLayouts, ASettings.WelcomePageActiveLayout);
  // Spalten und Sichtbarkeit des aktiven Layouts gelten aus den Einstellungen (Optionsseite, Schnellschalter).
  mLayout := VisibleFromSettings(Result.Current, ASettings);
  if mLayout.Columns <> ASettings.WelcomePageColumns then
  begin
    mLayout := mLayout.WithColumns(ASettings.WelcomePageColumns);
  end;
  Result := Result.WithCurrent(mLayout);
end;

class function TAtlasWelcomeCustomizing.Stored(const ASettings: TAtlasPluginSettings;
  const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings;
var
  mLayouts: TAtlasWelcomeLayouts;
begin
  Result := ASettings;
  mLayouts := ALayouts.WithCurrent(VisibleFromSettings(ALayouts.Current, ASettings));
  Result.WelcomePageLayouts := mLayouts.ToJson;
  Result.WelcomePageActiveLayout := mLayouts.ActiveName;
  Result.WelcomePageColumns := mLayouts.Current.Columns;
  Result.Normalize;
end;

class function TAtlasWelcomeCustomizing.Applied(const ASettings: TAtlasPluginSettings;
  const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings;
var
  mSlot: TAtlasWelcomeSlot;
begin
  Result := ASettings;
  for mSlot in ALayouts.Current.Slots do
  begin
    Result := WithSection(Result, mSlot.Id, mSlot.Visible);
  end;
  Result := Stored(Result, ALayouts);
end;

class function TAtlasWelcomeCustomizing.Switched(const ASettings: TAtlasPluginSettings;
  const AName: string): TAtlasPluginSettings;
var
  mLayouts, mTarget: TAtlasWelcomeLayouts;
begin
  Result := ASettings;
  mLayouts := Load(ASettings);
  if not mLayouts.Activated(AName, mTarget) or (mTarget.Active = mLayouts.Active) then
  begin
    Exit;
  end;
  // Das bisherige Layout behält Sichtbarkeit und Spalten aus den Einstellungen (Load).
  Result := Applied(ASettings, mTarget);
end;

class function TAtlasWelcomeCustomizing.Reset(const ASettings: TAtlasPluginSettings): TAtlasPluginSettings;
var
  mLayouts: TAtlasWelcomeLayouts;
  mLayout: TAtlasWelcomeLayout;
begin
  mLayouts := Load(ASettings);
  mLayout := TAtlasWelcomeLayout.Atlas;
  mLayout.Name := mLayouts.ActiveName;
  Result := ASettings;
  Result.WelcomePageColumns := mLayout.Columns;
  Result := Stored(Result, mLayouts.WithCurrent(mLayout));
end;

class function TAtlasWelcomeCustomizing.Hidden(const ASettings: TAtlasPluginSettings;
  const ARegistered: TArray<string>): TArray<string>;
var
  mItem: TAtlasWelcomeCatalogItem;
  mId: string;
begin
  Result := nil;
  for mItem in Catalog do
  begin
    for mId in ARegistered do
    begin
      if SameText(mId, mItem.Id) then
      begin
        if not IsOn(ASettings, mItem.Id) then
        begin
          Result := Result + [mItem.Id];
        end;
        Break;
      end;
    end;
  end;
end;

class function TAtlasWelcomeCustomizing.Adopted(const ASettings: TAtlasPluginSettings;
  const ARegistered: TArray<string>; const AWeight: TAtlasWelcomeWeight;
  out AAdded: TArray<string>): TAtlasPluginSettings;
var
  mLayouts: TAtlasWelcomeLayouts;
  mIds: TArray<string>;
  mId: string;
begin
  Result := ASettings;
  AAdded := nil;
  // Nur, wenn schon eigene Layouts gespeichert sind; die Vorgabe kennt alle Bereiche dieser Version.
  if Trim(ASettings.WelcomePageLayouts) = '' then
  begin
    Exit;
  end;
  mLayouts := Load(ASettings);
  mIds := nil;
  for mId in ARegistered do
  begin
    if not SameText(mId, TAtlasWelcomeIds.cHeader) and not SameText(mId, TAtlasWelcomeIds.cBoard) and
      not SameText(mId, TAtlasWelcomeIds.cSearch) then
    begin
      mIds := mIds + [mId];
    end;
  end;
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.Adopted(mIds, AWeight, AAdded));
  if Length(AAdded) > 0 then
  begin
    Result := Stored(ASettings, mLayouts);
  end;
end;

end.
