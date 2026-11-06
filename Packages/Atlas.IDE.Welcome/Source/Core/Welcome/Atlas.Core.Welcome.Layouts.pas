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
  Value: TJSONValue;
begin
  Result := Defaults;
  if Trim(AText) <> '' then
  begin
    Value := TJSONObject.ParseJSONValue(AText);
    try
      if Value is TJSONArray then
      begin
        Result.Items := nil;
        AddLayouts(Result, TJSONArray(Value));
      end;
    finally
      Value.Free;
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
  Layout: TAtlasWelcomeLayout;
begin
  Result := '';
  if IsDefault then
  begin
    Exit;
  end;
  for Layout in Items do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + Layout.ToJson;
  end;
  Result := '[' + Result + ']';
end;

function TAtlasWelcomeLayouts.IsDefault: Boolean;
var
  Left, Right: TAtlasWelcomeLayout;
  Index: Integer;
begin
  Result := Length(Items) = 1;
  if not Result then
  begin
    Exit;
  end;
  Left := Items[0];
  Right := TAtlasWelcomeLayout.Atlas;
  // Sichtbarkeit steht in den Einstellungen der Bereiche; für den Vergleich gleich setzen.
  Left.Slots := Copy(Left.Slots);
  for Index := 0 to High(Left.Slots) do
  begin
    Left.Slots[Index].Visible := True;
  end;
  Result := TAtlasWelcomeLayout.Same(Left, Right);
end;

function TAtlasWelcomeLayouts.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Items) do
  begin
    if SameText(Items[Index].Name, Trim(AName)) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasWelcomeLayouts.Names: TArray<string>;
var
  Layout: TAtlasWelcomeLayout;
begin
  Result := nil;
  for Layout in Items do
  begin
    Result := Result + [Layout.Name];
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
  Index: Integer;
begin
  ALayouts := Self;
  Index := IndexOf(AName);
  Result := Index >= 0;
  if Result then
  begin
    ALayouts.Active := Index;
  end;
end;

function TAtlasWelcomeLayouts.Added(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
var
  Layout: TAtlasWelcomeLayout;
begin
  ALayouts := Self;
  Result := ValidName(AName) and (IndexOf(AName) < 0);
  if not Result then
  begin
    Exit;
  end;
  Layout := Current;
  Layout.Name := Trim(AName);
  Layout.Slots := Copy(Layout.Slots);
  ALayouts.Items := Copy(Items) + [Layout];
  ALayouts.Active := High(ALayouts.Items);
end;

function TAtlasWelcomeLayouts.Renamed(const AName: string; out ALayouts: TAtlasWelcomeLayouts): Boolean;
var
  Other: Integer;
begin
  ALayouts := Self;
  Other := IndexOf(AName);
  Result := ValidName(AName) and ((Other < 0) or (Other = Active)) and (Active >= 0) and (Active <= High(Items));
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
  Number: Integer;
begin
  Result := Trim(ABase);
  Number := 1;
  while IndexOf(Result) >= 0 do
  begin
    Inc(Number);
    Result := Trim(ABase) + ' ' + IntToStr(Number);
  end;
end;

{ TAtlasWelcomeCustomizing }

class function TAtlasWelcomeCustomizing.Catalog: TArray<TAtlasWelcomeCatalogItem>;
begin
  Result := [
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Continue, 'WelcomePageContinue'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Projects, 'WelcomePageProjectStatus'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.History, 'WelcomePageTrends'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Tests, 'WelcomePageTests'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.State, 'WelcomePageStatusTile'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Unsaved, 'WelcomePageUnsaved'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.News, 'WelcomePageWhatsNew'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Discover, 'WelcomePageDiscover'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Setup, 'WelcomePageProjectSetup'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Issues, 'WelcomePageIssues'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Sprint, 'WelcomePageSprint'),
    TAtlasWelcomeCatalogItem.Create(TAtlasWelcomeIds.Help, 'WelcomePageHelp')];
end;

class function TAtlasWelcomeCustomizing.SettingOf(const AId: string): string;
var
  Item: TAtlasWelcomeCatalogItem;
begin
  for Item in Catalog do
  begin
    if SameText(Item.Id, AId) then
    begin
      Exit(Item.Setting);
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
  Store: IAtlasMemorySettingsStore;
  Key: string;
begin
  Key := SettingOf(AId);
  if Key = '' then
  begin
    Exit(True);
  end;
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if Store.HasInteger(Key) then
  begin
    Result := Store.ReadInteger(Key, 0) <> 0;
  end
  else
  begin
    Result := (Store.Text(Key) <> '') and not SameText(Store.Text(Key), 'off');
  end;
end;

class function TAtlasWelcomeCustomizing.WithSection(const ASettings: TAtlasPluginSettings; const AId: string;
  AOn: Boolean): TAtlasPluginSettings;
var
  Store, Defaults: IAtlasMemorySettingsStore;
  Key, Value: string;
begin
  Result := ASettings;
  Key := SettingOf(AId);
  if (Key = '') or (IsOn(ASettings, AId) = AOn) then
  begin
    Exit;
  end;
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if Store.HasInteger(Key) then
  begin
    if AOn then
    begin
      Store.WriteInteger(Key, 1);
    end
    else
    begin
      Store.WriteInteger(Key, 0);
    end;
  end
  else
  begin
    Value := 'off';
    if AOn then
    begin
      Defaults := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
      Value := Defaults.Text(Key);
      // Ist schon die Vorgabe "off", gilt der erste Wert, der zeigt (welcomePage.whatsNew: afterUpdate).
      if SameText(Value, 'off') or (Value = '') then
      begin
        Value := 'afterUpdate';
      end;
    end;
    Store.WriteString(Key, Value);
  end;
  Result.Load(Store);
end;

/// <summary>Sichtbarkeit der Katalogbereiche in ALayout aus den Einstellungen.</summary>
function VisibleFromSettings(const ALayout: TAtlasWelcomeLayout;
  const ASettings: TAtlasPluginSettings): TAtlasWelcomeLayout;
var
  Index: Integer;
begin
  Result := ALayout;
  Result.Slots := Copy(ALayout.Slots);
  for Index := 0 to High(Result.Slots) do
  begin
    if TAtlasWelcomeCustomizing.InCatalog(Result.Slots[Index].Id) then
    begin
      Result.Slots[Index].Visible := TAtlasWelcomeCustomizing.IsOn(ASettings, Result.Slots[Index].Id);
    end;
  end;
end;

class function TAtlasWelcomeCustomizing.Load(const ASettings: TAtlasPluginSettings): TAtlasWelcomeLayouts;
var
  Layout: TAtlasWelcomeLayout;
begin
  Result := TAtlasWelcomeLayouts.FromJson(ASettings.WelcomePageLayouts, ASettings.WelcomePageActiveLayout);
  // Spalten und Sichtbarkeit des aktiven Layouts gelten aus den Einstellungen (Optionsseite, Schnellschalter).
  Layout := VisibleFromSettings(Result.Current, ASettings);
  if Layout.Columns <> ASettings.WelcomePageColumns then
  begin
    Layout := Layout.WithColumns(ASettings.WelcomePageColumns);
  end;
  Result := Result.WithCurrent(Layout);
end;

class function TAtlasWelcomeCustomizing.Stored(const ASettings: TAtlasPluginSettings;
  const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings;
var
  Layouts: TAtlasWelcomeLayouts;
begin
  Result := ASettings;
  Layouts := ALayouts.WithCurrent(VisibleFromSettings(ALayouts.Current, ASettings));
  Result.WelcomePageLayouts := Layouts.ToJson;
  Result.WelcomePageActiveLayout := Layouts.ActiveName;
  Result.WelcomePageColumns := Layouts.Current.Columns;
  Result.Normalize;
end;

class function TAtlasWelcomeCustomizing.Applied(const ASettings: TAtlasPluginSettings;
  const ALayouts: TAtlasWelcomeLayouts): TAtlasPluginSettings;
var
  Slot: TAtlasWelcomeSlot;
begin
  Result := ASettings;
  for Slot in ALayouts.Current.Slots do
  begin
    Result := WithSection(Result, Slot.Id, Slot.Visible);
  end;
  Result := Stored(Result, ALayouts);
end;

class function TAtlasWelcomeCustomizing.Switched(const ASettings: TAtlasPluginSettings;
  const AName: string): TAtlasPluginSettings;
var
  Layouts, Target: TAtlasWelcomeLayouts;
begin
  Result := ASettings;
  Layouts := Load(ASettings);
  if not Layouts.Activated(AName, Target) or (Target.Active = Layouts.Active) then
  begin
    Exit;
  end;
  // Das bisherige Layout behält Sichtbarkeit und Spalten aus den Einstellungen (Load).
  Result := Applied(ASettings, Target);
end;

class function TAtlasWelcomeCustomizing.Reset(const ASettings: TAtlasPluginSettings): TAtlasPluginSettings;
var
  Layouts: TAtlasWelcomeLayouts;
  Layout: TAtlasWelcomeLayout;
begin
  Layouts := Load(ASettings);
  Layout := TAtlasWelcomeLayout.Atlas;
  Layout.Name := Layouts.ActiveName;
  Result := ASettings;
  Result.WelcomePageColumns := Layout.Columns;
  Result := Stored(Result, Layouts.WithCurrent(Layout));
end;

class function TAtlasWelcomeCustomizing.Hidden(const ASettings: TAtlasPluginSettings;
  const ARegistered: TArray<string>): TArray<string>;
var
  Item: TAtlasWelcomeCatalogItem;
  Id: string;
begin
  Result := nil;
  for Item in Catalog do
  begin
    for Id in ARegistered do
    begin
      if SameText(Id, Item.Id) then
      begin
        if not IsOn(ASettings, Item.Id) then
        begin
          Result := Result + [Item.Id];
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
  Layouts: TAtlasWelcomeLayouts;
  Ids: TArray<string>;
  Id: string;
begin
  Result := ASettings;
  AAdded := nil;
  // Nur, wenn schon eigene Layouts gespeichert sind; die Vorgabe kennt alle Bereiche dieser Version.
  if Trim(ASettings.WelcomePageLayouts) = '' then
  begin
    Exit;
  end;
  Layouts := Load(ASettings);
  Ids := nil;
  for Id in ARegistered do
  begin
    if not SameText(Id, TAtlasWelcomeIds.Header) and not SameText(Id, TAtlasWelcomeIds.Board) and
      not SameText(Id, TAtlasWelcomeIds.Search) then
    begin
      Ids := Ids + [Id];
    end;
  end;
  Layouts := Layouts.WithCurrent(Layouts.Current.Adopted(Ids, AWeight, AAdded));
  if Length(AAdded) > 0 then
  begin
    Result := Stored(ASettings, Layouts);
  end;
end;

end.
