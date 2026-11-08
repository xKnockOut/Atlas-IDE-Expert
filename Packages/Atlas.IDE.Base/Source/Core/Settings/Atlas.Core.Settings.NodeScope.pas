unit Atlas.Core.Settings.NodeScope;

// Optionen je Package (#1903): Unter Tools › Optionen › Atlas › Module hat jedes
// Package einen eigenen Knoten. Jeder Knoten zeigt dieselbe Seite, gefiltert auf
// seinen Besitzer:
// - TAtlasSettingsNodeScope: Wem gehört ein Element? Einstellungen über ihren
//   Modulschalter (x-module, '' = Base), Abschnitte der Module über deren Id.
//   Elemente ohne beides gehören Base.
// - TAtlasSettingsMerge: Jeder Knoten hat seinen eigenen Stand. Beim Speichern
//   gehen nur die Werte, die der Knoten geändert hat, in den gespeicherten Stand;
//   so überschreibt ein zweiter Knoten die Änderungen des ersten nicht.
// Ohne VCL und ohne Registry.

interface

uses
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups;

type
  TAtlasSettingsNodeScope = record
    /// <summary>Id des Moduls (z. B. „atlas.tests“); '' = Base.</summary>
    ModuleId: string;
    /// <summary>Modulschalter (x-module) des Moduls, z. B. „tests“; '' ohne.</summary>
    Switch: string;
    class function Base: TAtlasSettingsNodeScope; static;
    class function Module(const AModuleId, ASwitch: string): TAtlasSettingsNodeScope; static;
    function IsBase: Boolean;
    /// <summary>Gehört ein Element in diesen Knoten? AOwners: Knoten der Abschnitte, aus denen es stammt (Modul-Id
    /// des Besitzers bzw. Gastgebers); sie entscheiden allein. Sonst ASwitches, die Modulschalter seiner
    /// Einstellungen ('' = Base). Ohne beides: nur in Base.</summary>
    function Includes(const AOwners, ASwitches: TArray<string>): Boolean;
    /// <summary>Modulschalter (x-module) der Einstellung AName: der eigene oder der des nächsten Hauptschalters
    /// darüber, der einen hat; '' = Base.</summary>
    class function ModuleOf(ACatalog: TAtlasSettingsCatalog; AGroups: TAtlasSettingsGroups;
      const AName: string): string; static;
  end;

  /// <summary>Treffer der Suche auf der Übersicht „Atlas“: Einstellung mit Beschriftung, Modulschalter ('' =
  /// Base) und Bereich.</summary>
  TAtlasSettingHit = record
    Name: string;
    Caption: string;
    Module: string;
    AreaCaption: string;
  end;

  TAtlasSettingsSearch = class
  public
    /// <summary>Plugin-Einstellungen (ohne Zustände), deren Beschriftung oder Schlüssel AText enthält, in
    /// Katalogreihenfolge; höchstens AMax. Leerer Text: keine Treffer.</summary>
    class function Find(ACatalog: TAtlasSettingsCatalog; AGroups: TAtlasSettingsGroups; const AText: string;
      AEnglish: Boolean; AMax: Integer): TArray<TAtlasSettingHit>; static;
  end;

  TAtlasSettingsMerge = class
  public
    /// <summary>Schreibt jeden Wert, der in AAfter anders ist als in ABefore, nach ATarget; liefert die Namen.
    /// </summary>
    class function Changes(const ABefore, AAfter, ATarget: IAtlasMemorySettingsStore): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils;

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasSettingsNodeScope }

class function TAtlasSettingsNodeScope.Base: TAtlasSettingsNodeScope;
begin
  Result := Default(TAtlasSettingsNodeScope);
end;

class function TAtlasSettingsNodeScope.Module(const AModuleId, ASwitch: string): TAtlasSettingsNodeScope;
begin
  Result.ModuleId := AModuleId;
  Result.Switch := ASwitch;
end;

function TAtlasSettingsNodeScope.IsBase: Boolean;
begin
  Result := ModuleId = '';
end;

function TAtlasSettingsNodeScope.Includes(const AOwners, ASwitches: TArray<string>): Boolean;
begin
  if (Length(AOwners) = 0) and (Length(ASwitches) = 0) then
  begin
    Exit(IsBase);
  end;
  // Zeilen aus Abschnitten: Es zählt, in welchem Knoten der Abschnitt steht (Besitzer oder Gastgeber eines
  // Beitrags), nicht das Modul der Einstellungen darin.
  if Length(AOwners) > 0 then
  begin
    Exit(Contains(AOwners, ModuleId));
  end;
  if IsBase then
  begin
    Exit(Contains(ASwitches, ''));
  end;
  Result := (Switch <> '') and Contains(ASwitches, Switch);
end;

class function TAtlasSettingsNodeScope.ModuleOf(ACatalog: TAtlasSettingsCatalog; AGroups: TAtlasSettingsGroups;
  const AName: string): string;
var
  mNames: TArray<string>;
  mName: string;
  mIndex: Integer;
begin
  mNames := AGroups.AncestorsOf(AName);
  Insert(AName, mNames, 0);
  for mName in mNames do
  begin
    mIndex := ACatalog.IndexOfName(mName);
    if (mIndex >= 0) and (ACatalog[mIndex].Module <> '') then
    begin
      Exit(ACatalog[mIndex].Module);
    end;
  end;
  Result := '';
end;

{ TAtlasSettingsSearch }

class function TAtlasSettingsSearch.Find(ACatalog: TAtlasSettingsCatalog; AGroups: TAtlasSettingsGroups;
  const AText: string; AEnglish: Boolean; AMax: Integer): TArray<TAtlasSettingHit>;
var
  mIndex: Integer;
  mEntry: TAtlasCatalogEntry;
  mHit: TAtlasSettingHit;
  mText: string;
begin
  Result := nil;
  mText := Trim(AText).ToLower;
  if mText = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    if Length(Result) >= AMax then
    begin
      Break;
    end;
    mEntry := ACatalog[mIndex];
    if (mEntry.Source <> asPlugin) or mEntry.State then
    begin
      Continue;
    end;
    mHit.Caption := mEntry.Caption;
    if AEnglish and (mEntry.CaptionEn <> '') then
    begin
      mHit.Caption := mEntry.CaptionEn;
    end;
    if (Pos(mText, mHit.Caption.ToLower) = 0) and (Pos(mText, mEntry.Key.ToLower) = 0) then
    begin
      Continue;
    end;
    mHit.Name := mEntry.Name;
    mHit.Module := TAtlasSettingsNodeScope.ModuleOf(ACatalog, AGroups, mEntry.Name);
    mHit.AreaCaption := ACatalog.AreaCaption(mEntry.Area, AEnglish);
    Result := Result + [mHit];
  end;
end;

{ TAtlasSettingsMerge }

class function TAtlasSettingsMerge.Changes(const ABefore, AAfter, ATarget: IAtlasMemorySettingsStore): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in AAfter.Names do
  begin
    if AAfter.Text(mName) = ABefore.Text(mName) then
    begin
      Continue;
    end;
    if AAfter.HasInteger(mName) then
    begin
      ATarget.WriteInteger(mName, AAfter.ReadInteger(mName, 0));
    end
    else
    begin
      ATarget.WriteString(mName, AAfter.ReadString(mName, ''));
    end;
    Result := Result + [mName];
  end;
end;

end.
