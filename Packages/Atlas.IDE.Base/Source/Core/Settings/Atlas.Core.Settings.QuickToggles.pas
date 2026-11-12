unit Atlas.Core.Settings.QuickToggles;

// Schnellschalter für Atlas-Funktionen (#604), Teil ohne VCL und ohne Open
// Tools API. Die Liste der Schalter kommt aus dem Einstellungskatalog: jede
// boolesche Einstellung mit "x-quickToggle": true erscheint, gruppiert nach
// ihrer Seite (x-page). Zwei Kataloge im Format des JSON-Schemas:
// - PluginCatalog: Einstellungen des Plugins (Registry), erzeugt aus
//   schemas/atlas-plugin.schema.json (#723); Schlüssel = Name in
//   TAtlasPluginSettings.Load/Save. "x-drawing" kennzeichnet, was „Alles aus
//   für diese Sitzung“ abschaltet (Zeichnungen im Editor).
// - atlas.schema.json: Einstellungen mit "x-plugin" (Name der Plugin-
//   Einstellung). Nur Projekt-Schlüssel (x-scope, #227) haben einen Wert in
//   atlas.json; der Schalter zeigt dann „Projekt“, wenn atlas.json ihn setzt.
//   Globale Schlüssel (z. B. hints.xmlDocFull) stehen nur in settings.json,
//   dorthin schreibt die Plugin-Einstellung selbst.
// Ein Schalter schreibt dieselbe globale Einstellung wie die Optionsseite.
// Sitzungswerte (nur für diese Sitzung oder „Alles aus“) liegen in
// TAtlasToggleSession und ändern die gespeicherten Werte nie.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin;

type
  TAtlasQuickToggle = record
    /// <summary>Name der Plugin-Einstellung, z. B. "PairColors".</summary>
    Key: string;
    Caption: string;
    Page: string;
    /// <summary>Pfad in atlas.json, der den Wert im Projekt setzt; '' ohne.</summary>
    ProjectPath: string;
    /// <summary>Zeichnung im Editor: „Alles aus für diese Sitzung“ schaltet sie ab.</summary>
    Drawing: Boolean;
    /// <summary>Feature der Absturzsicherung (#493, Name aus TAtlasFeature) für den Vorschlag nach einem
    /// Absturz (#722); '' ohne.</summary>
    Feature: string;
    /// <summary>Experimentelle Funktion (x-experimental, #834): Kennzeichen „Experimentell“ im Fenster.</summary>
    Experimental: Boolean;
  end;

  TAtlasQuickToggleGroup = record
    Page: string;
    Toggles: TArray<TAtlasQuickToggle>;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wohin ein Umschalten geht: globale Einstellung, nur diese Sitzung oder atlas.json.</summary>
  TAtlasToggleTarget = (Global, Session, Project);
{$SCOPEDENUMS OFF}

  /// <summary>Werte nur für diese Sitzung; ändern nie die gespeicherten Einstellungen.</summary>
  TAtlasToggleSession = record
    Overrides: TArray<TPair<string, Boolean>>;
    /// <summary>„Alles aus für diese Sitzung“: alle Zeichnungen aus.</summary>
    AllOff: Boolean;
    procedure Put(const AKey: string; AValue: Boolean);
    procedure Drop(const AKey: string);
    function TryGet(const AKey: string; out AValue: Boolean): Boolean;
    /// <summary>Wirksame Einstellungen: gespeicherte Werte, darüber Sitzungswerte, bei AllOff Zeichnungen
    /// aus.</summary>
    function Apply(const AStored: TAtlasPluginSettings;
      const AToggles: TArray<TAtlasQuickToggle>): TAtlasPluginSettings;
  end;

  /// <summary>Ein Schalter im Fenster mit seinem Zustand.</summary>
  TAtlasQuickToggleItem = record
    Toggle: TAtlasQuickToggle;
    /// <summary>An oder aus: Sitzungswert, sonst Wert im Projekt, sonst gespeicherter Wert.</summary>
    Checked: Boolean;
    /// <summary>atlas.json setzt den Wert („Projekt“).</summary>
    Project: Boolean;
    /// <summary>Gilt nur für diese Sitzung.</summary>
    Session: Boolean;
  end;

  TAtlasQuickToggles = class
  public
    /// <summary>Katalog der Plugin-Einstellungen im Format des JSON-Schemas.</summary>
    class function PluginCatalog: string; static;
    /// <summary>Schalter aus beiden Katalogen: Seiten in der Reihenfolge ihres ersten Schalters, darin wie
    /// im Katalog. Einstellungen aus AProjectSchema brauchen "x-plugin"; ist der Name schon im
    /// Plugin-Katalog, ergänzt der Eintrag nur den Pfad in atlas.json.</summary>
    class function Build(const APluginCatalog, AProjectSchema: string; AEnglish: Boolean): TArray<TAtlasQuickToggle>;
      overload; static;
    class function Build(const APluginCatalog, AProjectSchema: string): TArray<TAtlasQuickToggle>; overload; static;
    class function Groups(const AToggles: TArray<TAtlasQuickToggle>): TArray<TAtlasQuickToggleGroup>; static;
    class function Find(const AToggles: TArray<TAtlasQuickToggle>; const AKey: string;
      out AToggle: TAtlasQuickToggle): Boolean; static;
    /// <summary>Wahrheitswert AKey aus ASettings; False, wenn es den Namen nicht gibt.</summary>
    class function GetFlag(const ASettings: TAtlasPluginSettings; const AKey: string;
      out AValue: Boolean): Boolean; static;
    /// <summary>Setzt AKey; False, wenn es den Namen nicht gibt.</summary>
    class function SetFlag(var ASettings: TAtlasPluginSettings; const AKey: string; AValue: Boolean): Boolean; static;
    /// <summary>Wert an APath in atlas.json (AProject darf nil sein); False ohne booleschen Wert.</summary>
    class function ProjectValue(AProject: TJSONObject; const APath: string; out AValue: Boolean): Boolean; static;
    /// <summary>Schalter mit Zustand für das Fenster.</summary>
    class function Items(const AToggles: TArray<TAtlasQuickToggle>; const AStored: TAtlasPluginSettings;
      const ASession: TAtlasToggleSession; AProject: TJSONObject): TArray<TAtlasQuickToggleItem>; static;
    /// <summary>AItem umschalten. Global: gespeicherte Einstellung, Sitzungswert fällt weg; Session: nur
    /// Sitzungswert; Project: Ergebnis ist der neue JSON-Wert für atlas.json (sonst '').</summary>
    class function Toggle(const AItem: TAtlasQuickToggleItem; ATarget: TAtlasToggleTarget;
      var AStored: TAtlasPluginSettings; var ASession: TAtlasToggleSession): string; static;
  end;

implementation

uses
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.PluginSchemaData,
  Atlas.Text.Json;

function BoolJson(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

function CaptionOf(ASchema: TJSONObject; AEnglish: Boolean): string;
begin
  Result := '';
  if AEnglish then
  begin
    Result := ASchema.GetValue<string>('x-captionEn', '');
  end;
  if (Result = '') and AEnglish then
  begin
    Result := ASchema.GetValue<string>('x-description-en', '');
  end;
  if Result = '' then
  begin
    Result := ASchema.GetValue<string>('x-caption', '');
  end;
  if Result = '' then
  begin
    Result := ASchema.GetValue<string>('description', '');
  end;
end;

type
  TVisit = reference to procedure(const APath, APage, AScope: string; ASchema: TJSONObject);

function IsBoolean(ASchema: TJSONObject): Boolean;
var
  mKind: TJSONValue;
begin
  mKind := ASchema.GetValue('type');
  Result := (mKind is TJSONString) and (TJSONString(mKind).Value = 'boolean');
end;

function IsQuickToggle(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONObject) and IsBoolean(TJSONObject(AValue)) and
    TJsonRead.Flag(TJSONObject(AValue), 'x-quickToggle');
end;

/// <summary>Schnellschalter unter den Gliedern des Objekts AName: Pfad "objekt.glied", x-scope des Glieds oder
/// sonst AScope.</summary>
procedure VisitChildren(const AName, APage, AScope: string; AObject: TJSONObject; const AVisit: TVisit);
var
  mChildren: TJSONValue;
  mSub: TJSONPair;
begin
  mChildren := AObject.GetValue('properties');
  if not (mChildren is TJSONObject) then
  begin
    Exit;
  end;
  for mSub in TJSONObject(mChildren) do
  begin
    if IsQuickToggle(mSub.JsonValue) then
    begin
      AVisit(AName + '.' + mSub.JsonString.Value, APage,
        TJSONObject(mSub.JsonValue).GetValue<string>('x-scope', AScope), TJSONObject(mSub.JsonValue));
    end;
  end;
end;

/// <summary>Ruft AVisit für jede boolesche Einstellung mit x-quickToggle auf, auch für Glieder von Objekten
/// (Pfad "objekt.glied", Seite des Objekts, x-scope des Glieds oder sonst des Objekts).</summary>
procedure Walk(const ASchemaJson: string; const AVisit: TVisit);
var
  mRoot, mProperties: TJSONValue;
  mPair: TJSONPair;
  mObject: TJSONObject;
  mPage, mScope: string;
begin
  mRoot := TJSONObject.ParseJSONValue(ASchemaJson);
  try
    mProperties := nil;
    if mRoot is TJSONObject then
    begin
      mProperties := TJSONObject(mRoot).GetValue('properties');
    end;
    if not (mProperties is TJSONObject) then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mProperties) do
    begin
      if not (mPair.JsonValue is TJSONObject) then
      begin
        Continue;
      end;
      mObject := TJSONObject(mPair.JsonValue);
      mPage := mObject.GetValue<string>('x-page', '');
      mScope := mObject.GetValue<string>('x-scope', '');
      if IsQuickToggle(mObject) then
      begin
        AVisit(mPair.JsonString.Value, mPage, mScope, mObject);
      end;
      VisitChildren(mPair.JsonString.Value, mPage, mScope, mObject, AVisit);
    end;
  finally
    mRoot.Free;
  end;
end;

function ToggleOf(const AKey, APage: string; ASchema: TJSONObject; AEnglish: Boolean;
  const AProjectPath: string): TAtlasQuickToggle;
begin
  Result := Default(TAtlasQuickToggle);
  Result.Key := AKey;
  Result.Page := APage;
  Result.Caption := CaptionOf(ASchema, AEnglish);
  Result.ProjectPath := AProjectPath;
  Result.Drawing := TJsonRead.Flag(ASchema, 'x-drawing');
  Result.Feature := ASchema.GetValue<string>('x-feature', '');
  Result.Experimental := TJsonRead.Flag(ASchema, 'x-experimental');
end;

/// <summary>Projekteinstellung mit Plugin-Einstellung (x-plugin): Ziel „Projekt“ beim Schalter der
/// Plugin-Einstellung, sonst ein eigener Schalter.</summary>
procedure AddProjectToggle(var AList: TArray<TAtlasQuickToggle>; const APath, APage, AScope: string;
  ASchema: TJSONObject; AEnglish: Boolean);
var
  mIndex: Integer;
  mKey, mProjectPath: string;
begin
  mKey := ASchema.GetValue<string>('x-plugin', '');
  // Ohne Plugin-Einstellung gibt es keinen globalen Wert, den der Schalter schreiben könnte.
  if mKey = '' then
  begin
    Exit;
  end;
  // Globale Schlüssel gelten in atlas.json nicht (#227): kein Ziel „Projekt“.
  mProjectPath := APath;
  if AScope = 'global' then
  begin
    mProjectPath := '';
  end;
  for mIndex := 0 to High(AList) do
  begin
    if SameText(AList[mIndex].Key, mKey) then
    begin
      AList[mIndex].ProjectPath := mProjectPath;
      AList[mIndex].Experimental := AList[mIndex].Experimental or TJsonRead.Flag(ASchema, 'x-experimental');
      Exit;
    end;
  end;
  AList := AList + [ToggleOf(mKey, APage, ASchema, AEnglish, mProjectPath)];
end;
{ TAtlasToggleSession }

procedure TAtlasToggleSession.Put(const AKey: string; AValue: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Overrides) do
  begin
    if SameText(Overrides[mIndex].Key, AKey) then
    begin
      Overrides[mIndex] := TPair<string, Boolean>.Create(Overrides[mIndex].Key, AValue);
      Exit;
    end;
  end;
  Overrides := Overrides + [TPair<string, Boolean>.Create(AKey, AValue)];
end;

procedure TAtlasToggleSession.Drop(const AKey: string);
var
  mIndex: Integer;
begin
  for mIndex := High(Overrides) downto 0 do
  begin
    if SameText(Overrides[mIndex].Key, AKey) then
    begin
      Delete(Overrides, mIndex, 1);
    end;
  end;
end;

function TAtlasToggleSession.TryGet(const AKey: string; out AValue: Boolean): Boolean;
var
  mPair: TPair<string, Boolean>;
begin
  AValue := False;
  for mPair in Overrides do
  begin
    if SameText(mPair.Key, AKey) then
    begin
      AValue := mPair.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasToggleSession.Apply(const AStored: TAtlasPluginSettings;
  const AToggles: TArray<TAtlasQuickToggle>): TAtlasPluginSettings;
var
  mPair: TPair<string, Boolean>;
  mToggle: TAtlasQuickToggle;
begin
  Result := AStored;
  for mPair in Overrides do
  begin
    TAtlasQuickToggles.SetFlag(Result, mPair.Key, mPair.Value);
  end;
  if AllOff then
  begin
    for mToggle in AToggles do
    begin
      if mToggle.Drawing then
      begin
        TAtlasQuickToggles.SetFlag(Result, mToggle.Key, False);
      end;
    end;
  end;
end;

{ TAtlasQuickToggles }

class function TAtlasQuickToggles.PluginCatalog: string;
begin
  // Erzeugt aus schemas/atlas-plugin.schema.json (#723): "x-page" = Seite (Gruppe), "x-quickToggle" = erscheint
  // als Schnellschalter, "x-caption"/"x-captionEn" = Beschriftung, "x-drawing" = Zeichnung im Editor,
  // "x-feature" = Feature der Absturzsicherung (#493) für den Vorschlag nach einem Absturz (#722).
  Result := AtlasPluginSchemaJson;
end;

class function TAtlasQuickToggles.Build(const APluginCatalog, AProjectSchema: string): TArray<TAtlasQuickToggle>;
begin
  Result := Build(APluginCatalog, AProjectSchema, False);
end;

class function TAtlasQuickToggles.Build(const APluginCatalog, AProjectSchema: string;
  AEnglish: Boolean): TArray<TAtlasQuickToggle>;
var
  mList: TArray<TAtlasQuickToggle>;
  mGroup: TAtlasQuickToggleGroup;
begin
  mList := nil;
  Walk(APluginCatalog,
    procedure(const APath, APage, AScope: string; ASchema: TJSONObject)
    begin
      mList := mList + [ToggleOf(APath, APage, ASchema, AEnglish, ASchema.GetValue<string>('x-project', ''))];
    end);
  Walk(AProjectSchema,
    procedure(const APath, APage, AScope: string; ASchema: TJSONObject)
    begin
      AddProjectToggle(mList, APath, APage, AScope, ASchema, AEnglish);
    end);
  // Nach Seiten ordnen, Reihenfolge der Seiten wie ihr erstes Auftreten.
  Result := nil;
  for mGroup in Groups(mList) do
  begin
    Result := Result + mGroup.Toggles;
  end;
end;

class function TAtlasQuickToggles.Groups(const AToggles: TArray<TAtlasQuickToggle>): TArray<TAtlasQuickToggleGroup>;
var
  mToggle: TAtlasQuickToggle;
  mIndex, mFound: Integer;
  mGroup: TAtlasQuickToggleGroup;
begin
  Result := nil;
  for mToggle in AToggles do
  begin
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Page, mToggle.Page) then
      begin
        mFound := mIndex;
      end;
    end;
    if mFound < 0 then
    begin
      mGroup.Page := mToggle.Page;
      mGroup.Toggles := nil;
      Result := Result + [mGroup];
      mFound := High(Result);
    end;
    Result[mFound].Toggles := Result[mFound].Toggles + [mToggle];
  end;
end;

class function TAtlasQuickToggles.Find(const AToggles: TArray<TAtlasQuickToggle>; const AKey: string;
  out AToggle: TAtlasQuickToggle): Boolean;
var
  mToggle: TAtlasQuickToggle;
begin
  AToggle := Default(TAtlasQuickToggle);
  for mToggle in AToggles do
  begin
    if SameText(mToggle.Key, AKey) then
    begin
      AToggle := mToggle;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasQuickToggles.GetFlag(const ASettings: TAtlasPluginSettings; const AKey: string;
  out AValue: Boolean): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
begin
  // Über Save statt eines eigenen Falls je Feld: jede neue Einstellung ist ohne Änderung hier erreichbar.
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := mStore.HasInteger(AKey);
  AValue := Result and (mStore.ReadInteger(AKey, 0) <> 0);
end;

class function TAtlasQuickToggles.SetFlag(var ASettings: TAtlasPluginSettings; const AKey: string;
  AValue: Boolean): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := mStore.HasInteger(AKey);
  if not Result then
  begin
    Exit;
  end;
  if AValue then
  begin
    mStore.WriteInteger(AKey, 1);
  end
  else
  begin
    mStore.WriteInteger(AKey, 0);
  end;
  ASettings.Load(mStore);
end;

class function TAtlasQuickToggles.ProjectValue(AProject: TJSONObject; const APath: string;
  out AValue: Boolean): Boolean;
var
  mCurrent: TJSONValue;
  mSegment: string;
begin
  AValue := False;
  Result := False;
  if (AProject = nil) or (APath = '') then
  begin
    Exit;
  end;
  mCurrent := AProject;
  for mSegment in APath.Split(['.']) do
  begin
    if not (mCurrent is TJSONObject) then
    begin
      Exit;
    end;
    mCurrent := TJSONObject(mCurrent).GetValue(mSegment);
  end;
  if mCurrent is TJSONBool then
  begin
    AValue := TJSONBool(mCurrent).AsBoolean;
    Result := True;
  end;
end;

class function TAtlasQuickToggles.Items(const AToggles: TArray<TAtlasQuickToggle>;
  const AStored: TAtlasPluginSettings; const ASession: TAtlasToggleSession;
  AProject: TJSONObject): TArray<TAtlasQuickToggleItem>;
var
  mToggle: TAtlasQuickToggle;
  mItem: TAtlasQuickToggleItem;
  mValue: Boolean;
begin
  Result := nil;
  for mToggle in AToggles do
  begin
    mItem := Default(TAtlasQuickToggleItem);
    mItem.Toggle := mToggle;
    GetFlag(AStored, mToggle.Key, mItem.Checked);
    mItem.Project := ProjectValue(AProject, mToggle.ProjectPath, mValue);
    if mItem.Project then
    begin
      mItem.Checked := mValue;
    end;
    mItem.Session := ASession.TryGet(mToggle.Key, mValue);
    if mItem.Session then
    begin
      mItem.Checked := mValue;
    end;
    Result := Result + [mItem];
  end;
end;

class function TAtlasQuickToggles.Toggle(const AItem: TAtlasQuickToggleItem; ATarget: TAtlasToggleTarget;
  var AStored: TAtlasPluginSettings; var ASession: TAtlasToggleSession): string;
begin
  Result := '';
  case ATarget of
    TAtlasToggleTarget.Session:
      ASession.Put(AItem.Toggle.Key, not AItem.Checked);
    TAtlasToggleTarget.Project:
      begin
        ASession.Drop(AItem.Toggle.Key);
        Result := BoolJson(not AItem.Checked);
      end;
  else
    begin
      ASession.Drop(AItem.Toggle.Key);
      SetFlag(AStored, AItem.Toggle.Key, not AItem.Checked);
    end;
  end;
end;

end.
