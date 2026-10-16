unit Atlas.Core.Settings.QuickToggles;

// Schnellschalter für Atlas-Funktionen (#604), Teil ohne VCL und ohne Open
// Tools API. Die Liste der Schalter kommt aus dem Einstellungskatalog: jede
// boolesche Einstellung mit "x-quickToggle": true erscheint, gruppiert nach
// ihrer Seite (x-page). Zwei Kataloge im Format des JSON-Schemas:
// - PluginCatalog: Einstellungen des Plugins (Registry); Schlüssel = Name in
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
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History;

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

function BoolJson(AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

function CaptionOf(ASchema: TJSONObject; AEnglish: Boolean): string;
begin
  Result := '';
  if AEnglish then
    Result := ASchema.GetValue<string>('x-captionEn', '');
  if Result = '' then
    Result := ASchema.GetValue<string>('x-caption', '');
  if Result = '' then
    Result := ASchema.GetValue<string>('description', '');
end;

function IsTrue(ASchema: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := ASchema.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

type
  TVisit = reference to procedure(const APath, APage, AScope: string; ASchema: TJSONObject);

function IsBoolean(ASchema: TJSONObject): Boolean;
var
  Kind: TJSONValue;
begin
  Kind := ASchema.GetValue('type');
  Result := (Kind is TJSONString) and (TJSONString(Kind).Value = 'boolean');
end;

/// <summary>Ruft AVisit für jede boolesche Einstellung mit x-quickToggle auf, auch für Glieder von Objekten
/// (Pfad "objekt.glied", Seite des Objekts, x-scope des Glieds oder sonst des Objekts).</summary>
procedure Walk(const ASchemaJson: string; const AVisit: TVisit);
var
  Root, Properties, Children: TJSONValue;
  Pair, Sub: TJSONPair;
  Page, Scope: string;
begin
  Root := TJSONObject.ParseJSONValue(ASchemaJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Properties := TJSONObject(Root).GetValue('properties');
    if not (Properties is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Properties) do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      Page := TJSONObject(Pair.JsonValue).GetValue<string>('x-page', '');
      Scope := TJSONObject(Pair.JsonValue).GetValue<string>('x-scope', '');
      if IsBoolean(TJSONObject(Pair.JsonValue)) and IsTrue(TJSONObject(Pair.JsonValue), 'x-quickToggle') then
        AVisit(Pair.JsonString.Value, Page, Scope, TJSONObject(Pair.JsonValue));
      Children := TJSONObject(Pair.JsonValue).GetValue('properties');
      if Children is TJSONObject then
        for Sub in TJSONObject(Children) do
          if (Sub.JsonValue is TJSONObject) and IsBoolean(TJSONObject(Sub.JsonValue)) and
            IsTrue(TJSONObject(Sub.JsonValue), 'x-quickToggle') then
            AVisit(Pair.JsonString.Value + '.' + Sub.JsonString.Value, Page,
              TJSONObject(Sub.JsonValue).GetValue<string>('x-scope', Scope), TJSONObject(Sub.JsonValue));
    end;
  finally
    Root.Free;
  end;
end;

{ TAtlasToggleSession }

procedure TAtlasToggleSession.Put(const AKey: string; AValue: Boolean);
var
  Index: Integer;
begin
  for Index := 0 to High(Overrides) do
    if SameText(Overrides[Index].Key, AKey) then
    begin
      Overrides[Index] := TPair<string, Boolean>.Create(Overrides[Index].Key, AValue);
      Exit;
    end;
  Overrides := Overrides + [TPair<string, Boolean>.Create(AKey, AValue)];
end;

procedure TAtlasToggleSession.Drop(const AKey: string);
var
  Index: Integer;
begin
  for Index := High(Overrides) downto 0 do
    if SameText(Overrides[Index].Key, AKey) then
      Delete(Overrides, Index, 1);
end;

function TAtlasToggleSession.TryGet(const AKey: string; out AValue: Boolean): Boolean;
var
  Pair: TPair<string, Boolean>;
begin
  AValue := False;
  for Pair in Overrides do
    if SameText(Pair.Key, AKey) then
    begin
      AValue := Pair.Value;
      Exit(True);
    end;
  Result := False;
end;

function TAtlasToggleSession.Apply(const AStored: TAtlasPluginSettings;
  const AToggles: TArray<TAtlasQuickToggle>): TAtlasPluginSettings;
var
  Pair: TPair<string, Boolean>;
  Toggle: TAtlasQuickToggle;
begin
  Result := AStored;
  for Pair in Overrides do
    TAtlasQuickToggles.SetFlag(Result, Pair.Key, Pair.Value);
  if AllOff then
    for Toggle in AToggles do
      if Toggle.Drawing then
        TAtlasQuickToggles.SetFlag(Result, Toggle.Key, False);
end;

{ TAtlasQuickToggles }

class function TAtlasQuickToggles.PluginCatalog: string;
begin
  // Wie atlas.schema.json: "x-page" = Seite (Gruppe), "x-quickToggle" = erscheint als Schnellschalter,
  // "x-caption"/"x-captionEn" = Beschriftung, "x-drawing" = Zeichnung im Editor, "x-feature" = Feature der
  // Absturzsicherung (#493) für den Vorschlag nach einem Absturz (#722).
  Result :=
    '{"properties":{' +
    '"Enabled":{"type":"boolean","x-feature":"Completion",' +
      '"default":true,"x-page":"Allgemein","x-quickToggle":true,' +
      '"x-caption":"Atlas-Code-Insight","x-captionEn":"Atlas Code Insight","x-issue":"#407"},' +
    '"DiagnosticMode":{"type":"boolean",' +
      '"default":false,"x-page":"Allgemein","x-quickToggle":true,' +
      '"x-caption":"Diagnosemodus","x-captionEn":"Diagnostic mode","x-issue":"#479"},' +
    '"PairColors":{"type":"boolean","x-feature":"Pairs",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Klammerfarben","x-captionEn":"Bracket colors","x-issue":"#514"},' +
    '"PairGuides":{"type":"boolean","x-feature":"Pairs",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Blocklinien","x-captionEn":"Block guides","x-issue":"#514"},' +
    '"PairOwners":{"type":"boolean","x-feature":"Pairs",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Anweisungen mitfärben","x-captionEn":"Colour statements","x-issue":"#653"},' +
    '"InactiveDim":{"type":"boolean","x-feature":"Pairs",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Inaktive {$IFDEF}-Zweige ausgrauen","x-captionEn":"Dim inactive {$IFDEF} branches",' +
      '"x-issue":"#615"},' +
    '"Problems":{"type":"boolean","x-feature":"Problems",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Probleme unterstreichen","x-captionEn":"Underline problems","x-issue":"#398"},' +
    '"InlayHints":{"type":"boolean","x-feature":"InlayHints",' +
      '"default":false,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Inlay-Hints","x-captionEn":"Inlay hints","x-issue":"#401"},' +
    '"Notes":{"type":"boolean","x-feature":"Notes",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Notizen","x-captionEn":"Notes","x-issue":"#545"},' +
    '"BookmarksNamed":{"type":"boolean","x-feature":"Bookmarks",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Benannte Lesezeichen","x-captionEn":"Named bookmarks","x-issue":"#622"},' +
    '"CodeLensMetrics":{"type":"boolean","x-feature":"EditorCommands",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Code-Metriken","x-captionEn":"Code metrics","x-issue":"#66"},' +
    '"CodeLensTests":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,"x-drawing":true,' +
      '"x-caption":"Code Lens „Test ausführen“","x-captionEn":"Code lens “Run test”","x-issue":"#69"},' +
    '"GenerateMenu":{"type":"boolean","x-feature":"EditorCommands",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,' +
      '"x-caption":"Erzeugen-Menü","x-captionEn":"Generate menu","x-issue":"#719"},' +
    '"TodoList":{"type":"boolean","x-feature":"Palette",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,' +
      '"x-caption":"TODO-Liste","x-captionEn":"TODO list","x-issue":"#68"},' +
    '"BaselineUpdate":{"type":"boolean","x-feature":"Palette",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,' +
      '"x-caption":"Baseline aktualisieren","x-captionEn":"Update baseline","x-issue":"#97"},' +
    '"MetricsReport":{"type":"boolean","x-feature":"Palette",' +
      '"default":true,"x-page":"Editor","x-quickToggle":true,' +
      '"x-caption":"Metrikbericht","x-captionEn":"Metrics report","x-issue":"#66"},' +
    '"TeamFile":{"type":"boolean","x-feature":"Settings",' +
      '"default":true,"x-page":"Allgemein","x-quickToggle":true,' +
      '"x-caption":"Projektdatei .atlas","x-captionEn":"Project file .atlas","x-issue":"#486"},' +
    '"HoverTooltip":{"type":"boolean","x-feature":"Hover",' +
      '"default":true,"x-page":"Hints","x-quickToggle":true,' +
      '"x-caption":"Hover-Tooltip","x-captionEn":"Hover tooltip","x-issue":"#442"},' +
    '"FilterChips":{"type":"boolean","x-feature":"Completion",' +
      '"default":true,"x-page":"Vervollständigung","x-quickToggle":true,' +
      '"x-caption":"Filter-Chips","x-captionEn":"Filter chips","x-issue":"#422"},' +
    '"Preview":{"type":"boolean","x-feature":"Completion",' +
      '"default":false,"x-page":"Vervollständigung","x-quickToggle":true,' +
      '"x-caption":"Vorschau im Editor","x-captionEn":"Preview in the editor","x-issue":"#434"},' +
    '"GroupInherited":{"type":"boolean","x-feature":"Completion",' +
      '"default":true,"x-page":"Vervollständigung","x-quickToggle":true,' +
      '"x-caption":"Geerbte Member gruppieren","x-captionEn":"Group inherited members","x-issue":"#419"},' +
    '"Learning":{"type":"boolean","x-feature":"Completion",' +
      '"default":true,"x-page":"Vervollständigung","x-quickToggle":true,' +
      '"x-caption":"Lernende Gewichtung","x-captionEn":"Learned ranking","x-issue":"#418"},' +
    '"Favorites":{"type":"boolean","x-feature":"Completion",' +
      '"default":true,"x-page":"Vervollständigung","x-quickToggle":true,' +
      '"x-caption":"Favoriten anheften","x-captionEn":"Pin favorites","x-issue":"#458"},' +
    '"CheckOnSave":{"type":"boolean","x-feature":"CheckOnSave",' +
      '"default":false,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Syntaxprüfung nach dem Speichern","x-captionEn":"Syntax check after saving","x-issue":"#548"},' +
    '"McpBuild":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Builds für Claude Code","x-captionEn":"Builds for Claude Code","x-issue":"#261"},' +
    '"StartProfiles":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Startprofile","x-captionEn":"Start profiles","x-issue":"#575"},' +
    '"StartProfilesStatusField":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Startprofil in der Statusleiste","x-captionEn":"Start profile in the status bar",' +
      '"x-issue":"#575"},' +
    '"TestRun":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Tests ausführen","x-captionEn":"Run tests","x-issue":"#69"},' +
    '"TestsAfterBuild":{"type":"boolean","x-feature":"Build",' +
      '"default":false,"x-page":"Compiler","x-quickToggle":true,' +
      '"x-caption":"Tests nach dem Build","x-captionEn":"Tests after the build","x-issue":"#69"},' +
    '"TestDebug":{"type":"boolean","x-feature":"Build",' +
      '"default":true,"x-page":"Debuggen","x-quickToggle":true,' +
      '"x-caption":"Test debuggen","x-captionEn":"Debug test","x-issue":"#585"},' +
    '"TestBreakAtStart":{"type":"boolean","default":true,"x-page":"Debuggen",' +
      '"x-caption":"Beim Test-Debuggen am Anfang der Methode anhalten",' +
      '"x-captionEn":"Stop at the start of the method when debugging a test","x-issue":"#585"},' +
    '"TestsBuildFirst":{"type":"boolean","default":true,"x-page":"Compiler",' +
      '"x-caption":"Vor den Tests bauen","x-captionEn":"Build before the tests","x-issue":"#69"},' +
    '"BuildZeroHints":{"type":"boolean","default":false,"x-page":"Compiler",' +
      '"x-caption":"Build nur ohne Warnungen und Hinweise erfolgreich",' +
      '"x-captionEn":"Build succeeds only without warnings and hints","x-issue":"#530"},' +
    '"WelcomePage":{"type":"boolean","x-feature":"WelcomePage",' +
      '"default":true,"x-page":"Willkommensseite","x-quickToggle":true,' +
      '"x-caption":"Atlas auf der Willkommensseite","x-captionEn":"Atlas on the welcome page","x-issue":"#753"},' +
    '"WelcomePageProjectSetup":{"type":"boolean","x-feature":"WelcomePage",' +
      '"default":true,"x-page":"Willkommensseite","x-quickToggle":true,' +
      '"x-caption":"Projekt für Atlas einrichten","x-captionEn":"Set up project for Atlas","x-issue":"#759"},' +
    '"ShortcutTips":{"type":"boolean","x-feature":"ShortcutTips",' +
      '"default":true,"x-page":"Allgemein","x-quickToggle":true,' +
      '"x-caption":"Tastenkürzel-Tipps","x-captionEn":"Keyboard shortcut tips","x-issue":"#600"},' +
    '"StatusFieldSummary":{"type":"boolean","default":true,"x-page":"Allgemein",' +
      '"x-caption":"Kurztext im Statusfeld","x-captionEn":"Summary in the status field","x-issue":"#591"}' +
    '}}';
end;

class function TAtlasQuickToggles.Build(const APluginCatalog, AProjectSchema: string): TArray<TAtlasQuickToggle>;
begin
  Result := Build(APluginCatalog, AProjectSchema, False);
end;

class function TAtlasQuickToggles.Build(const APluginCatalog, AProjectSchema: string;
  AEnglish: Boolean): TArray<TAtlasQuickToggle>;
var
  List: TArray<TAtlasQuickToggle>;
  Ordered: TArray<TAtlasQuickToggle>;
  Group: TAtlasQuickToggleGroup;
begin
  List := nil;
  Walk(APluginCatalog,
    procedure(const APath, APage, AScope: string; ASchema: TJSONObject)
    var
      Toggle: TAtlasQuickToggle;
    begin
      Toggle := Default(TAtlasQuickToggle);
      Toggle.Key := APath;
      Toggle.Page := APage;
      Toggle.Caption := CaptionOf(ASchema, AEnglish);
      Toggle.ProjectPath := ASchema.GetValue<string>('x-project', '');
      Toggle.Drawing := IsTrue(ASchema, 'x-drawing');
      Toggle.Feature := ASchema.GetValue<string>('x-feature', '');
      List := List + [Toggle];
    end);
  Walk(AProjectSchema,
    procedure(const APath, APage, AScope: string; ASchema: TJSONObject)
    var
      Toggle: TAtlasQuickToggle;
      Index: Integer;
      Key, ProjectPath: string;
    begin
      Key := ASchema.GetValue<string>('x-plugin', '');
      // Ohne Plugin-Einstellung gibt es keinen globalen Wert, den der Schalter schreiben könnte.
      if Key = '' then
        Exit;
      // Globale Schlüssel gelten in atlas.json nicht (#227): kein Ziel „Projekt“.
      ProjectPath := APath;
      if AScope = 'global' then
        ProjectPath := '';
      for Index := 0 to High(List) do
        if SameText(List[Index].Key, Key) then
        begin
          List[Index].ProjectPath := ProjectPath;
          Exit;
        end;
      Toggle := Default(TAtlasQuickToggle);
      Toggle.Key := Key;
      Toggle.Page := APage;
      Toggle.Caption := CaptionOf(ASchema, AEnglish);
      Toggle.ProjectPath := ProjectPath;
      Toggle.Drawing := IsTrue(ASchema, 'x-drawing');
      Toggle.Feature := ASchema.GetValue<string>('x-feature', '');
      List := List + [Toggle];
    end);
  // Nach Seiten ordnen, Reihenfolge der Seiten wie ihr erstes Auftreten.
  Ordered := nil;
  for Group in Groups(List) do
    Ordered := Ordered + Group.Toggles;
  Result := Ordered;
end;

class function TAtlasQuickToggles.Groups(const AToggles: TArray<TAtlasQuickToggle>): TArray<TAtlasQuickToggleGroup>;
var
  Toggle: TAtlasQuickToggle;
  Index, Found: Integer;
  Group: TAtlasQuickToggleGroup;
begin
  Result := nil;
  for Toggle in AToggles do
  begin
    Found := -1;
    for Index := 0 to High(Result) do
      if SameText(Result[Index].Page, Toggle.Page) then
        Found := Index;
    if Found < 0 then
    begin
      Group.Page := Toggle.Page;
      Group.Toggles := nil;
      Result := Result + [Group];
      Found := High(Result);
    end;
    Result[Found].Toggles := Result[Found].Toggles + [Toggle];
  end;
end;

class function TAtlasQuickToggles.Find(const AToggles: TArray<TAtlasQuickToggle>; const AKey: string;
  out AToggle: TAtlasQuickToggle): Boolean;
var
  Toggle: TAtlasQuickToggle;
begin
  AToggle := Default(TAtlasQuickToggle);
  for Toggle in AToggles do
    if SameText(Toggle.Key, AKey) then
    begin
      AToggle := Toggle;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasQuickToggles.GetFlag(const ASettings: TAtlasPluginSettings; const AKey: string;
  out AValue: Boolean): Boolean;
var
  Store: IAtlasMemorySettingsStore;
begin
  // Über Save statt eines eigenen Falls je Feld: jede neue Einstellung ist ohne Änderung hier erreichbar.
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := Store.HasInteger(AKey);
  AValue := Result and (Store.ReadInteger(AKey, 0) <> 0);
end;

class function TAtlasQuickToggles.SetFlag(var ASettings: TAtlasPluginSettings; const AKey: string;
  AValue: Boolean): Boolean;
var
  Store: IAtlasMemorySettingsStore;
begin
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := Store.HasInteger(AKey);
  if not Result then
    Exit;
  if AValue then
    Store.WriteInteger(AKey, 1)
  else
    Store.WriteInteger(AKey, 0);
  ASettings.Load(Store);
end;

class function TAtlasQuickToggles.ProjectValue(AProject: TJSONObject; const APath: string;
  out AValue: Boolean): Boolean;
var
  Current: TJSONValue;
  Segment: string;
begin
  AValue := False;
  Result := False;
  if (AProject = nil) or (APath = '') then
    Exit;
  Current := AProject;
  for Segment in APath.Split(['.']) do
  begin
    if not (Current is TJSONObject) then
      Exit;
    Current := TJSONObject(Current).GetValue(Segment);
  end;
  if Current is TJSONBool then
  begin
    AValue := TJSONBool(Current).AsBoolean;
    Result := True;
  end;
end;

class function TAtlasQuickToggles.Items(const AToggles: TArray<TAtlasQuickToggle>;
  const AStored: TAtlasPluginSettings; const ASession: TAtlasToggleSession;
  AProject: TJSONObject): TArray<TAtlasQuickToggleItem>;
var
  Toggle: TAtlasQuickToggle;
  Item: TAtlasQuickToggleItem;
  Value: Boolean;
begin
  Result := nil;
  for Toggle in AToggles do
  begin
    Item := Default(TAtlasQuickToggleItem);
    Item.Toggle := Toggle;
    GetFlag(AStored, Toggle.Key, Item.Checked);
    Item.Project := ProjectValue(AProject, Toggle.ProjectPath, Value);
    if Item.Project then
      Item.Checked := Value;
    Item.Session := ASession.TryGet(Toggle.Key, Value);
    if Item.Session then
      Item.Checked := Value;
    Result := Result + [Item];
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
