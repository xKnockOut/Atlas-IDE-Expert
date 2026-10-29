unit Atlas.Core.Architecture.Model;

// Fenster „Atlas-Architektur“ (#1118), Kern ohne VCL und OTA:
// - Parse liest die Antwort des Befehls atlas.architecture ({"enabled",
//   "root", "format": "json", "data"} mit den Daten aus
//   TArchitectureReport.Json, Format 1) in Datensätze. Pfade bleiben relativ
//   zu Root; FullPath macht sie absolut, Zeilen und Spalten sind 1-basiert
//   (0 = keine Fundstelle).
// - Sorted sortiert die Tabellen stabil (bei Gleichstand nach Name), Matches
//   filtert nach Teilen des Unit-Namens, ShortestPath sucht den kürzesten Weg
//   über uses wie die HTML-Karte.
// - TAtlasArchitecturePalette: Farben der Teilsysteme wie in der HTML-Karte,
//   je für helle und dunkle Themen.
// - Comparison: Vergleich mit einem gespeicherten Stand (#1121) aus
//   "comparison" (Daten aus TArchitectureComparer.Json), "baseline" und
//   "comparisonError" der Antwort: Abschnitte mit Einträgen (Namen statt
//   Nummern, je mit der Unit des aktuellen Stands zum Springen), dazu die
//   geänderten Kanten für die Karte (neue als Nummern in Edges, entfernte
//   zwischen Units, die es noch gibt).
// - TAtlasArchitectureCommands baut die Argumente der Befehle
//   atlas.architecture (mit "compareWith" bzw. "compare": false) und
//   atlas.architecture.saveReport (.json: Stand speichern).
// - Feinheit der Teilsysteme (#1366): Resolution aus "grouping" der Daten,
//   TAtlasArchResolution rechnet zwischen Reglerstellung (logarithmisch über
//   0,2–5,0, Mitte = 1,0) und Wert, TAtlasArchitectureGroupingSettings liest
//   und schreibt architecture.grouping in settings.json. Die Befehle nehmen
//   "resolution" über TAtlasArchitectureOptions mit.
// - TAtlasArchitectureView rechnet die Karte zwischen Lage (Koordinaten des
//   Servers) und Bildpunkten um: Einpassen, Zoomen um einen Punkt,
//   Verschieben, Treffer einer Unit.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasArchUnit = record
    Name: string;
    /// <summary>Pfad relativ zu Root mit /.</summary>
    FileName: string;
    Subsystem: Integer;
    /// <summary>Units, die die Unit direkt bzw. über eine Kette im interface-Teil brauchen.</summary>
    Direct: Integer;
    Total: Integer;
    /// <summary>Units, die die Unit selbst einbindet.</summary>
    Uses_: Integer;
    /// <summary>"foundation", "hub" oder ''.</summary>
    Role: string;
    Library_: Boolean;
    X: Double;
    Y: Double;
    /// <summary>Steht in "outliers".</summary>
    Outlier: Boolean;
    /// <summary>Gehört zu einem Zyklus.</summary>
    OnCycle: Boolean;
  end;

  TAtlasArchSubsystem = record
    Name: string;
    Units: TArray<Integer>;
    /// <summary>Zentralste Unit, -1 ohne.</summary>
    Central: Integer;
    Inner: Integer;
    Outer: Integer;
    /// <summary>0..1.</summary>
    Cohesion: Double;
    /// <summary>Sammelgruppe der Units ohne uses-Beziehung.</summary>
    Isolated: Boolean;
    X: Double;
    Y: Double;
    R: Double;
  end;

  TAtlasArchEdge = record
    Source: Integer;
    Target: Integer;
    Interface_: Boolean;
  end;

  /// <summary>uses-Eintrag mit Fundstelle (Zyklen, Querverbindungen).</summary>
  TAtlasArchLink = record
    Source: Integer;
    Target: Integer;
    Interface_: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Nur Querverbindungen: Teilsysteme, Grund ("rare", "againstDirection"), Kanten hin und zurück.
    /// </summary>
    FromSubsystem: Integer;
    ToSubsystem: Integer;
    Reason: string;
    Forward: Integer;
    Backward: Integer;
  end;

  TAtlasArchCycle = record
    /// <summary>Nur über interface: Compilerfehler F2047.</summary>
    InterfaceOnly: Boolean;
    Units: TArray<Integer>;
    Edges: TArray<TAtlasArchLink>;
  end;

  TAtlasArchOutlier = record
    Unit_: Integer;
    Suggested: Integer;
    /// <summary>"namespace" oder "edges".</summary>
    Reason: string;
    Inside: Integer;
    Toward: Integer;
  end;

{$SCOPEDENUMS ON}
  TAtlasArchColumn = (Name, Subsystem, Direct, Total, Uses_, Role);
  /// <summary>Abschnitte des Vergleichs (#1121) in der Reihenfolge der Anzeige.</summary>
  TAtlasArchChangeKind = (NewCycles, RemovedCycles, NewCrossLinks, RemovedCrossLinks, NewEdges, RemovedEdges, Moves,
    Growth, NewUnits, RemovedUnits);
{$SCOPEDENUMS OFF}

  /// <summary>Eintrag eines Abschnitts im Vergleich (#1121).</summary>
  TAtlasArchChange = record
    /// <summary>Unit, „A → B“ (Kanten) oder der Weg eines Zyklus.</summary>
    Text: string;
    /// <summary>Kanten und Wechsel: Teilsystem vorher bzw. nachher; Wachstum: „gesamt abhängig“ vorher und
    /// nachher; sonst ''.</summary>
    From: string;
    To_: string;
    /// <summary>Kanten: "interface" oder "implementation"; Zyklen: "interface" bei Zyklen nur über interface.
    /// </summary>
    Section: string;
    /// <summary>Querverbindungen: "rare" oder "againstDirection".</summary>
    Reason: string;
    /// <summary>Unit des aktuellen Stands zum Springen (Quelle bzw. erste Unit), -1 ohne (entfernte Unit).
    /// </summary>
    Unit_: Integer;
  end;

  TAtlasArchChangeSection = record
    Kind: TAtlasArchChangeKind;
    Items: TArray<TAtlasArchChange>;
  end;

  TAtlasArchComparison = record
    /// <summary>Pfad des gespeicherten Stands; '' ohne Vergleich.</summary>
    Baseline: string;
    /// <summary>Meldung, wenn der Stand nicht lesbar war (dann ohne Abschnitte).</summary>
    Error: string;
    BaselineTitle: string;
    BaselineUnits: Integer;
    BaselineEdges: Integer;
    /// <summary>Feinheit γ des gespeicherten bzw. des aktuellen Stands (#1366).</summary>
    BaselineResolution: Double;
    Resolution: Double;
    /// <summary>Arten aus architecture.failOn, die vorkommen ("newCycle", "newCrossLink", …).</summary>
    Failed: TArray<string>;
    /// <summary>Alle Abschnitte in der Reihenfolge von TAtlasArchChangeKind, auch leere.</summary>
    Sections: TArray<TAtlasArchChangeSection>;
    /// <summary>Neue uses-Kanten (Nummern in Edges).</summary>
    AddedEdges: TArray<Integer>;
    /// <summary>Entfernte uses-Kanten zwischen Units, die es noch gibt.</summary>
    DroppedEdges: TArray<TAtlasArchEdge>;
    /// <summary>Ein Stand wurde gelesen und verglichen.</summary>
    function Present: Boolean;
    /// <summary>Einträge aller Abschnitte.</summary>
    function Count: Integer;
    function Section(AKind: TAtlasArchChangeKind): TArray<TAtlasArchChange>;
    /// <summary>Beide Stände mit verschiedener Feinheit gerechnet (#1366).</summary>
    function ResolutionDiffers: Boolean;
  end;

  TAtlasArchitectureModel = record
  public const
    Format = 1;
  public
    Root: string;
    Title: string;
    /// <summary>"project" oder "projectGroup".</summary>
    Scope: string;
    Created: string;
    IncludeLibrary: Boolean;
    DurationMs: Integer;
    Generation: Int64;
    EdgeCount: Integer;
    InterfaceCycles: Integer;
    /// <summary>Muster aus architecture.exclude (für die Statuszeile).</summary>
    Excludes: TArray<string>;
    /// <summary>Feinheit γ, mit der der Server gruppiert hat (#1366); 1 ohne Angabe.</summary>
    Resolution: Double;
    Units: TArray<TAtlasArchUnit>;
    Edges: TArray<TAtlasArchEdge>;
    /// <summary>Zentrale Units, die zentralste zuerst.</summary>
    Central: TArray<Integer>;
    Subsystems: TArray<TAtlasArchSubsystem>;
    Outliers: TArray<TAtlasArchOutlier>;
    Cycles: TArray<TAtlasArchCycle>;
    CrossLinks: TArray<TAtlasArchLink>;
    /// <summary>Vergleich mit einem gespeicherten Stand (#1121), leer ohne.</summary>
    Comparison: TAtlasArchComparison;
    /// <summary>Antwort von atlas.architecture lesen. AEnabled: false bei architecture.enabled = false (dann
    /// True ohne Daten). False bei unlesbarer Antwort oder fremdem Format.</summary>
    class function Parse(const AAnswer: string; out AModel: TAtlasArchitectureModel;
      out AEnabled: Boolean): Boolean; static;
    /// <summary>Absoluter Pfad zu einem Pfad relativ zu Root; absolute Pfade bleiben.</summary>
    function FullPath(const AFileName: string): string;
    /// <summary>Nummer der Unit (ohne Groß-/Kleinschreibung), -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Eintrag in Outliers zur Unit, -1 ohne.</summary>
    function OutlierOf(AUnit: Integer): Integer;
    /// <summary>Jedes Wort aus AFilter kommt im Namen vor (ohne Groß-/Kleinschreibung); leer passt immer.</summary>
    function Matches(AUnit: Integer; const AFilter: string): Boolean;
    /// <summary>AUnits nach ASpalte, stabil: bei Gleichstand nach Name, dann Nummer.</summary>
    function Sorted(const AUnits: TArray<Integer>; AColumn: TAtlasArchColumn; ADescending: Boolean): TArray<Integer>;
    /// <summary>Name des Teilsystems, '' bei ungültiger Nummer.</summary>
    function SubsystemName(ASubsystem: Integer): string;
    /// <summary>"A → B → A" eines Zyklus.</summary>
    function CyclePath(const ACycle: TAtlasArchCycle): string;
    /// <summary>Radius einer Unit auf der Karte (wie die HTML-Karte: wächst mit gesamt abhängig).</summary>
    function NodeRadius(AUnit: Integer): Double;
    /// <summary>Kürzester Weg über uses von AFrom nach ATo (Breitensuche in der Reihenfolge von Edges, wie
    /// die HTML-Karte und find_path mit via ["uses"]). AEdges: Nummern in Edges. Ohne AImplementation nur
    /// interface-Kanten; AHidden (je Teilsystem, nil = keins) sperrt Units ausgeblendeter Teilsysteme.
    /// False ohne Weg und bei AFrom = ATo.</summary>
    function ShortestPath(AFrom, ATo: Integer; AImplementation: Boolean; const AHidden: TArray<Boolean>;
      out AEdges: TArray<Integer>): Boolean;
    /// <summary>„A → B → C“ für einen Weg aus ShortestPath.</summary>
    function PathText(AFrom: Integer; const AEdges: TArray<Integer>): string;
    /// <summary>Weg aus „Weg zwischen Symbolen“ (#1117) auf der Karte: AUnits sind die Units der Kette nach
    /// Namen. Units außerhalb des Umfangs fallen weg, direkte Wiederholungen ebenso. Zwischen zwei Units gilt
    /// die uses-Kante in einer der beiden Richtungen; ohne direkte Kante überbrückt der kürzeste Weg über uses
    /// (mit implementation). AEdges: Nummern in Edges. False, wenn keine Unit im Umfang liegt.</summary>
    function RouteOf(const ANames: TArray<string>; out AUnits, AEdges: TArray<Integer>): Boolean;
    /// <summary>„A → B → C“ zu Units aus RouteOf.</summary>
    function RouteText(const AUnits: TArray<Integer>): string;
    /// <summary>Die Unit gehört zu einem Teilsystem, das AHidden ausblendet.</summary>
    function IsHidden(AUnit: Integer; const AHidden: TArray<Boolean>): Boolean;
    /// <summary>Teilsysteme ohne die Sammelgruppe der Units ohne uses-Beziehung (Regler „Feinheit“).</summary>
    function SubsystemCount: Integer;
  end;

  /// <summary>Optionen der Befehle atlas.architecture und atlas.architecture.saveReport.</summary>
  TAtlasArchitectureOptions = record
    /// <summary>"projectGroup" oder "project".</summary>
    Scope: string;
    IncludeLibrary: Boolean;
    /// <summary>Pfad eines gespeicherten Stands (#1121); '' = architecture.baseline bzw. keiner.</summary>
    CompareWith: string;
    /// <summary>False: auch nicht mit architecture.baseline vergleichen.</summary>
    Compare: Boolean;
    /// <summary>Feinheit γ für diesen Aufruf (#1366); 0 = architecture.grouping.resolution des Servers.</summary>
    Resolution: Double;
    /// <summary>Umfang und Bibliotheks-Units, Vergleich mit architecture.baseline, Feinheit des Servers.</summary>
    class function Create(const AScope: string; AIncludeLibrary: Boolean): TAtlasArchitectureOptions; static;
  end;

  /// <summary>Regler „Feinheit“ (#1366): Stellung 0..Steps, logarithmisch über 0,2–5,0, Mitte = 1,0.</summary>
  TAtlasArchResolution = class
  public const
    MinValue = 0.2;
    MaxValue = 5.0;
    Steps = 100;
  public
    /// <summary>Wert zur Stellung, auf zwei Nachkommastellen gerundet.</summary>
    class function ValueAt(APosition: Integer): Double; static;
    /// <summary>Nächste Stellung zum Wert (Werte außerhalb werden begrenzt).</summary>
    class function PositionOf(AValue: Double): Integer; static;
    /// <summary>Wert in den Grenzen; ungültig (≤ 0, NaN) = 1.</summary>
    class function Clamp(AValue: Double): Double; static;
    /// <summary>"1,0" bzw. "1.0" nach AFormat, höchstens zwei Nachkommastellen.</summary>
    class function Text(AValue: Double; const AFormat: TFormatSettings): string; static;
    /// <summary>Gleich auf zwei Nachkommastellen.</summary>
    class function Same(ALeft, ARight: Double): Boolean; static;
  end;

  /// <summary>architecture.grouping in settings.json (#1366): der Server liest denselben Wert.</summary>
  TAtlasArchitectureGroupingSettings = class
  public const
    ResolutionPath = 'architecture.grouping.resolution';
    SliderPath = 'architecture.grouping.showResolutionSlider';
  public
    /// <summary>Werte aus dem Text von settings.json; fehlende oder ungültige: 1 bzw. True.</summary>
    class procedure Read(const AGlobalText: string; out AResolution: Double; out AShowSlider: Boolean); static;
    /// <summary>Text von settings.json mit neuer Feinheit; übriger Text bleibt.</summary>
    class function WithResolution(const AGlobalText: string; AValue: Double): string; static;
  end;

  TAtlasArchitectureCommands = class
  public const
    Command = 'atlas.architecture';
    SaveCommand = 'atlas.architecture.saveReport';
  public
    /// <summary>[uri, {"scope", "includeLibraryUnits", "format": "json"}] für atlas.architecture.</summary>
    class function Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean): string; overload; static;
    /// <summary>Wie oben mit Vergleich (#1121): ACompareWith (Pfad eines gespeicherten Stands) als "compareWith";
    /// leer und ohne ACompare "compare": false (auch nicht mit architecture.baseline vergleichen).</summary>
    class function Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean; const ACompareWith: string;
      ACompare: Boolean): string; overload; static;
    /// <summary>[uri, {"scope", "includeLibraryUnits", "format": "json", Vergleich, "resolution"}] (#1366).
    /// </summary>
    class function Arguments(const AProjectUri: string; const AOptions: TAtlasArchitectureOptions): string;
      overload; static;
    /// <summary>[uri, Datei, Optionen wie Arguments ohne "format"] für atlas.architecture.saveReport.</summary>
    class function SaveArguments(const AProjectUri, AFileName: string;
      const AOptions: TAtlasArchitectureOptions): string; overload; static;
    /// <summary>[uri, Datei, {"scope", "includeLibraryUnits"}] für atlas.architecture.saveReport; Datei .json
    /// speichert den Stand für den Vergleich.</summary>
    class function SaveArguments(const AProjectUri, AFileName, AScope: string;
      AIncludeLibrary: Boolean): string; overload; static;
    /// <summary>Wie oben mit Vergleich wie Arguments (Berichte bekommen den Abschnitt „Vergleich“).</summary>
    class function SaveArguments(const AProjectUri, AFileName, AScope: string; AIncludeLibrary: Boolean;
      const ACompareWith: string; ACompare: Boolean): string; overload; static;
    /// <summary>Gespeicherte Datei aus der Antwort von saveReport ({"file", "units"}); '' bei Fehler.</summary>
    class function SavedFile(const AAnswer: string): string; static;
  end;

  TAtlasArchitecturePalette = class
  public const
    Count = 10;
  public
    /// <summary>Farbe des Teilsystems ASubsystem als $00BBGGRR (wie TColor).</summary>
    class function Color(ASubsystem: Integer; ADark: Boolean): Cardinal; static;
    /// <summary>Hintergrund ($00BBGGRR) ist dunkel: Helligkeit unter der Hälfte.</summary>
    class function IsDark(ABackground: Cardinal): Boolean; static;
  end;

  TAtlasArchitectureView = record
  public const
    MinScale = 0.05;
    MaxScale = 8.0;
    /// <summary>Rand beim Einpassen in Bildpunkten.</summary>
    Margin = 20;
  public
    Scale: Double;
    OffsetX: Double;
    OffsetY: Double;
    /// <summary>Alle Teilsysteme in AWidth × AHeight einpassen, höchstens doppelt vergrößert.</summary>
    procedure Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
    function ScreenX(AX: Double): Double;
    function ScreenY(AY: Double): Double;
    function WorldX(AX: Double): Double;
    function WorldY(AY: Double): Double;
    /// <summary>Um AFactor zoomen; der Punkt unter (AX, AY) bleibt stehen.</summary>
    procedure ZoomAt(AFactor: Double; AX, AY: Double);
    procedure Pan(ADX, ADY: Double);
    /// <summary>Unit unter dem Bildpunkt (AX, AY), bei Überlappung die zuletzt gezeichnete; -1 ohne.</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer; overload;
    /// <summary>Wie oben, ohne Units ausgeblendeter Teilsysteme (AHidden je Teilsystem).</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
      const AHidden: TArray<Boolean>): Integer; overload;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Core.Settings.JsonText;

const
  // Wie --c0 … --c9 der HTML-Karte (#RRGGBB), hell bzw. dunkel.
  LightColors: array[0..TAtlasArchitecturePalette.Count - 1] of Cardinal = ($2F6FB3, $7A4FB0, $2E7D4F, $B07A1D,
    $A33C5A, $1B8A8F, $6B6F1D, $C2571A, $4A5AB8, $8A4F3A);
  DarkColors: array[0..TAtlasArchitecturePalette.Count - 1] of Cardinal = ($6AA6E6, $B28BE0, $6CC293, $E0B257,
    $E07A98, $5CC6C9, $C3C75A, $F0945A, $94A0F0, $D09A83);

function IntOf(const AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
end;

function Int64Of(const AObject: TJSONObject; const AName: string): Int64;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  // Über den Text: Generationen liegen über 2^32 (Kennung des Index im oberen Teil).
  if Value is TJSONNumber then
    Result := StrToInt64Def(Value.Value, 0);
end;

function FloatOf(const AObject: TJSONObject; const AName: string): Double;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsDouble;
end;

function TextOf(const AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Value.Value;
end;

function FlagOf(const AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := TJSONBool(Value).AsBoolean;
end;

function ArrayOf(const AObject: TJSONObject; const AName: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONArray then
    Result := TJSONArray(Value);
end;

function IntsOf(const AObject: TJSONObject; const AName: string): TArray<Integer>;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := nil;
  Items := ArrayOf(AObject, AName);
  if Items = nil then
    Exit;
  SetLength(Result, Items.Count);
  for Index := 0 to Items.Count - 1 do
    if Items.Items[Index] is TJSONNumber then
      Result[Index] := TJSONNumber(Items.Items[Index]).AsInt
    else
      Result[Index] := -1;
end;

function LinkOf(const AObject: TJSONObject): TAtlasArchLink;
begin
  Result := Default(TAtlasArchLink);
  Result.Source := IntOf(AObject, 'source', -1);
  Result.Target := IntOf(AObject, 'target', -1);
  Result.Interface_ := TextOf(AObject, 'section') = 'interface';
  Result.FileName := TextOf(AObject, 'file');
  Result.Line := IntOf(AObject, 'line', 0);
  Result.Character := IntOf(AObject, 'character', 0);
  Result.FromSubsystem := IntOf(AObject, 'from', -1);
  Result.ToSubsystem := IntOf(AObject, 'to', -1);
  Result.Reason := TextOf(AObject, 'reason');
  Result.Forward := IntOf(AObject, 'forward', 0);
  Result.Backward := IntOf(AObject, 'backward', 0);
end;

function ValidUnit(const AModel: TAtlasArchitectureModel; AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(AModel.Units));
end;

/// <summary>Verweise auf Units und Teilsysteme prüfen: Ein Fenster soll an fremden Daten nicht scheitern.</summary>
function Consistent(const AModel: TAtlasArchitectureModel): Boolean;
var
  Item: TAtlasArchUnit;
  Edge: TAtlasArchEdge;
  Subsystem: TAtlasArchSubsystem;
  Member: Integer;
  Cycle: TAtlasArchCycle;
  Link: TAtlasArchLink;
  Outlier: TAtlasArchOutlier;
begin
  Result := False;
  for Item in AModel.Units do
    if (Item.Subsystem < 0) or (Item.Subsystem >= Length(AModel.Subsystems)) then
      Exit;
  for Edge in AModel.Edges do
    if not ValidUnit(AModel, Edge.Source) or not ValidUnit(AModel, Edge.Target) then
      Exit;
  for Member in AModel.Central do
    if not ValidUnit(AModel, Member) then
      Exit;
  for Subsystem in AModel.Subsystems do
    for Member in Subsystem.Units do
      if not ValidUnit(AModel, Member) then
        Exit;
  for Cycle in AModel.Cycles do
  begin
    for Member in Cycle.Units do
      if not ValidUnit(AModel, Member) then
        Exit;
    for Link in Cycle.Edges do
      if not ValidUnit(AModel, Link.Source) or not ValidUnit(AModel, Link.Target) then
        Exit;
  end;
  for Link in AModel.CrossLinks do
    if not ValidUnit(AModel, Link.Source) or not ValidUnit(AModel, Link.Target) then
      Exit;
  for Outlier in AModel.Outliers do
    if not ValidUnit(AModel, Outlier.Unit_) then
      Exit;
  Result := True;
end;

function NamesOf(const AItems: TJSONArray): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if AItems = nil then
    Exit;
  for Index := 0 to AItems.Count - 1 do
    if AItems.Items[Index] is TJSONString then
      Result := Result + [AItems.Items[Index].Value];
end;

function ChangeOf(const AModel: TAtlasArchitectureModel; const AText, AUnit: string): TAtlasArchChange;
begin
  Result := Default(TAtlasArchChange);
  Result.Text := AText;
  Result.Unit_ := AModel.IndexOf(AUnit);
end;

/// <summary>Einträge eines Abschnitts aus "comparison"; fremde Einträge fallen weg.</summary>
function ChangesOf(const AModel: TAtlasArchitectureModel; const AData: TJSONObject;
  AKind: TAtlasArchChangeKind): TArray<TAtlasArchChange>;
const
  Names: array[TAtlasArchChangeKind] of string = ('newCycles', 'removedCycles', 'newCrossLinks', 'removedCrossLinks',
    'newEdges', 'removedEdges', 'moves', 'growth', 'newUnits', 'removedUnits');
var
  Items: TJSONArray;
  Index: Integer;
  Item: TJSONObject;
  Change: TAtlasArchChange;
  Members: TArray<string>;
  Name: string;
begin
  Result := nil;
  Items := ArrayOf(AData, Names[AKind]);
  if Items = nil then
    Exit;
  if AKind in [TAtlasArchChangeKind.NewUnits, TAtlasArchChangeKind.RemovedUnits] then
  begin
    for Name in NamesOf(Items) do
      Result := Result + [ChangeOf(AModel, Name, Name)];
    Exit;
  end;
  for Index := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[Index] is TJSONObject) then
      Continue;
    Item := TJSONObject(Items.Items[Index]);
    case AKind of
      TAtlasArchChangeKind.NewCycles, TAtlasArchChangeKind.RemovedCycles:
        begin
          Members := NamesOf(ArrayOf(Item, 'units'));
          if Length(Members) = 0 then
            Continue;
          Change := ChangeOf(AModel, string.Join(' → ', Members) + ' → ' + Members[0], Members[0]);
          if FlagOf(Item, 'interfaceOnly') then
            Change.Section := 'interface';
        end;
      TAtlasArchChangeKind.Moves:
        begin
          Change := ChangeOf(AModel, TextOf(Item, 'unit'), TextOf(Item, 'unit'));
          Change.From := TextOf(Item, 'from');
          Change.To_ := TextOf(Item, 'to');
        end;
      TAtlasArchChangeKind.Growth:
        begin
          Change := ChangeOf(AModel, TextOf(Item, 'unit'), TextOf(Item, 'unit'));
          Change.From := IntToStr(IntOf(Item, 'before', 0));
          Change.To_ := IntToStr(IntOf(Item, 'after', 0));
        end;
    else
      Change := ChangeOf(AModel, TextOf(Item, 'source') + ' → ' + TextOf(Item, 'target'), TextOf(Item, 'source'));
      Change.From := TextOf(Item, 'from');
      Change.To_ := TextOf(Item, 'to');
      Change.Section := TextOf(Item, 'section');
      Change.Reason := TextOf(Item, 'reason');
    end;
    Result := Result + [Change];
  end;
end;

/// <summary>Kanten ([Quelle, Ziel, "i"/"m"]) unter AName, deren Units es im aktuellen Stand gibt.</summary>
function MapEdgesOf(const AModel: TAtlasArchitectureModel; const AData: TJSONObject;
  const AName: string): TArray<TAtlasArchEdge>;
var
  Items, Pair: TJSONArray;
  Index: Integer;
  Edge: TAtlasArchEdge;
begin
  Result := nil;
  Items := ArrayOf(AData, AName);
  if Items = nil then
    Exit;
  for Index := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[Index] is TJSONArray) then
      Continue;
    Pair := TJSONArray(Items.Items[Index]);
    if Pair.Count < 3 then
      Continue;
    Edge.Source := AModel.IndexOf(Pair.Items[0].Value);
    Edge.Target := AModel.IndexOf(Pair.Items[1].Value);
    Edge.Interface_ := Pair.Items[2].Value = 'i';
    if (Edge.Source >= 0) and (Edge.Target >= 0) then
      Result := Result + [Edge];
  end;
end;

/// <summary>"resolution" einer Angabe; 1 ohne oder bei ungültigem Wert (Server vor #1366).</summary>
function ResolutionOf(const AObject: TJSONObject): Double;
begin
  Result := 1;
  if (AObject <> nil) and (AObject.GetValue('resolution') is TJSONNumber) then
    Result := TAtlasArchResolution.Clamp(FloatOf(AObject, 'resolution'));
end;

function ComparisonOf(const AModel: TAtlasArchitectureModel; const AAnswer: TJSONObject): TAtlasArchComparison;
var
  Data, Baseline: TJSONObject;
  Kind: TAtlasArchChangeKind;
  Section: TAtlasArchChangeSection;
  Edge: TAtlasArchEdge;
  Index: Integer;
begin
  Result := Default(TAtlasArchComparison);
  Result.Error := TextOf(AAnswer, 'comparisonError');
  if not (AAnswer.GetValue('comparison') is TJSONObject) then
    Exit;
  Result.Baseline := TextOf(AAnswer, 'baseline');
  Data := TJSONObject(AAnswer.GetValue('comparison'));
  if Data.GetValue('baseline') is TJSONObject then
  begin
    Baseline := TJSONObject(Data.GetValue('baseline'));
    Result.BaselineTitle := TextOf(Baseline, 'title');
    Result.BaselineUnits := IntOf(Baseline, 'units', 0);
    Result.BaselineEdges := IntOf(Baseline, 'edges', 0);
    Result.BaselineResolution := ResolutionOf(Baseline);
  end
  else
    Result.BaselineResolution := 1;
  Result.Resolution := ResolutionOf(Data);
  Result.Failed := NamesOf(ArrayOf(Data, 'failed'));
  for Kind := Low(TAtlasArchChangeKind) to High(TAtlasArchChangeKind) do
  begin
    Section.Kind := Kind;
    Section.Items := ChangesOf(AModel, Data, Kind);
    Result.Sections := Result.Sections + [Section];
  end;
  // Neue Kanten stehen im aktuellen Stand: als Nummern in Edges, damit die Karte sie wie die übrigen zeichnet.
  for Edge in MapEdgesOf(AModel, Data, 'addedEdges') do
    for Index := 0 to High(AModel.Edges) do
      if (AModel.Edges[Index].Source = Edge.Source) and (AModel.Edges[Index].Target = Edge.Target) then
      begin
        Result.AddedEdges := Result.AddedEdges + [Index];
        Break;
      end;
  Result.DroppedEdges := MapEdgesOf(AModel, Data, 'droppedEdges');
end;

{ TAtlasArchComparison }

function TAtlasArchComparison.Present: Boolean;
begin
  Result := (Baseline <> '') and (Error = '') and (Length(Sections) > 0);
end;

function TAtlasArchComparison.Count: Integer;
var
  Item: TAtlasArchChangeSection;
begin
  Result := 0;
  for Item in Sections do
    Inc(Result, Length(Item.Items));
end;

function TAtlasArchComparison.Section(AKind: TAtlasArchChangeKind): TArray<TAtlasArchChange>;
var
  Item: TAtlasArchChangeSection;
begin
  Result := nil;
  for Item in Sections do
    if Item.Kind = AKind then
      Exit(Item.Items);
end;

{ TAtlasArchitectureModel }

class function TAtlasArchitectureModel.Parse(const AAnswer: string; out AModel: TAtlasArchitectureModel;
  out AEnabled: Boolean): Boolean;
var
  Root: TJSONValue;
  Answer, Data, Item, Summary: TJSONObject;
  Items, Pair: TJSONArray;
  Index, Inner: Integer;
begin
  AModel := Default(TAtlasArchitectureModel);
  AEnabled := False;
  Result := False;
  Root := TJSONObject.ParseJSONValue(AAnswer);
  try
    if not (Root is TJSONObject) then
      Exit;
    Answer := TJSONObject(Root);
    AEnabled := FlagOf(Answer, 'enabled');
    if not AEnabled then
      Exit(Answer.GetValue('enabled') is TJSONBool);
    if not (Answer.GetValue('data') is TJSONObject) then
      Exit;
    Data := TJSONObject(Answer.GetValue('data'));
    if IntOf(Data, 'format', 0) <> Format then
      Exit;
    AModel.Root := TextOf(Answer, 'root');
    AModel.Title := TextOf(Data, 'title');
    AModel.Scope := TextOf(Data, 'scope');
    AModel.Created := TextOf(Data, 'created');
    AModel.IncludeLibrary := FlagOf(Data, 'includeLibrary');
    AModel.DurationMs := IntOf(Data, 'durationMs', 0);
    AModel.Generation := Int64Of(Data, 'generation');
    AModel.Resolution := 1;
    if Data.GetValue('grouping') is TJSONObject then
      AModel.Resolution := ResolutionOf(TJSONObject(Data.GetValue('grouping')));
    if Data.GetValue('summary') is TJSONObject then
    begin
      Summary := TJSONObject(Data.GetValue('summary'));
      AModel.EdgeCount := IntOf(Summary, 'edges', 0);
      AModel.InterfaceCycles := IntOf(Summary, 'interfaceCycles', 0);
    end;
    Items := ArrayOf(Data, 'units');
    if Items <> nil then
    begin
      SetLength(AModel.Units, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Units[Index].Name := TextOf(Item, 'name');
        AModel.Units[Index].FileName := TextOf(Item, 'file');
        AModel.Units[Index].Subsystem := IntOf(Item, 'subsystem', -1);
        AModel.Units[Index].Direct := IntOf(Item, 'direct', 0);
        AModel.Units[Index].Total := IntOf(Item, 'total', 0);
        AModel.Units[Index].Uses_ := IntOf(Item, 'uses', 0);
        AModel.Units[Index].Role := TextOf(Item, 'role');
        AModel.Units[Index].Library_ := FlagOf(Item, 'library');
        AModel.Units[Index].X := FloatOf(Item, 'x');
        AModel.Units[Index].Y := FloatOf(Item, 'y');
      end;
    end;
    Items := ArrayOf(Data, 'edges');
    if Items <> nil then
    begin
      SetLength(AModel.Edges, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONArray) then
          Exit;
        Pair := TJSONArray(Items.Items[Index]);
        if (Pair.Count < 3) or not (Pair.Items[0] is TJSONNumber) or not (Pair.Items[1] is TJSONNumber) then
          Exit;
        AModel.Edges[Index].Source := TJSONNumber(Pair.Items[0]).AsInt;
        AModel.Edges[Index].Target := TJSONNumber(Pair.Items[1]).AsInt;
        AModel.Edges[Index].Interface_ := Pair.Items[2].Value = 'i';
      end;
    end;
    AModel.Central := IntsOf(Data, 'central');
    Items := ArrayOf(Data, 'excludes');
    if Items <> nil then
    begin
      SetLength(AModel.Excludes, Items.Count);
      for Index := 0 to Items.Count - 1 do
        AModel.Excludes[Index] := Items.Items[Index].Value;
    end;
    Items := ArrayOf(Data, 'subsystems');
    if Items <> nil then
    begin
      SetLength(AModel.Subsystems, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Subsystems[Index].Name := TextOf(Item, 'name');
        AModel.Subsystems[Index].Units := IntsOf(Item, 'units');
        AModel.Subsystems[Index].Central := IntOf(Item, 'central', -1);
        AModel.Subsystems[Index].Inner := IntOf(Item, 'inner', 0);
        AModel.Subsystems[Index].Outer := IntOf(Item, 'outer', 0);
        AModel.Subsystems[Index].Cohesion := FloatOf(Item, 'cohesion');
        AModel.Subsystems[Index].Isolated := FlagOf(Item, 'isolated');
        AModel.Subsystems[Index].X := FloatOf(Item, 'x');
        AModel.Subsystems[Index].Y := FloatOf(Item, 'y');
        AModel.Subsystems[Index].R := FloatOf(Item, 'r');
      end;
    end;
    Items := ArrayOf(Data, 'outliers');
    if Items <> nil then
    begin
      SetLength(AModel.Outliers, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Outliers[Index].Unit_ := IntOf(Item, 'unit', -1);
        AModel.Outliers[Index].Suggested := IntOf(Item, 'suggested', -1);
        AModel.Outliers[Index].Reason := TextOf(Item, 'reason');
        AModel.Outliers[Index].Inside := IntOf(Item, 'inside', 0);
        AModel.Outliers[Index].Toward := IntOf(Item, 'toward', 0);
      end;
    end;
    Items := ArrayOf(Data, 'cycles');
    if Items <> nil then
    begin
      SetLength(AModel.Cycles, Items.Count);
      for Index := 0 to Items.Count - 1 do
      begin
        if not (Items.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Items.Items[Index]);
        AModel.Cycles[Index].InterfaceOnly := FlagOf(Item, 'interfaceOnly');
        AModel.Cycles[Index].Units := IntsOf(Item, 'units');
        Pair := ArrayOf(Item, 'edges');
        if Pair <> nil then
        begin
          SetLength(AModel.Cycles[Index].Edges, Pair.Count);
          for Inner := 0 to Pair.Count - 1 do
            if Pair.Items[Inner] is TJSONObject then
              AModel.Cycles[Index].Edges[Inner] := LinkOf(TJSONObject(Pair.Items[Inner]))
            else
              Exit;
        end;
      end;
    end;
    Items := ArrayOf(Data, 'crossLinks');
    if Items <> nil then
    begin
      SetLength(AModel.CrossLinks, Items.Count);
      for Index := 0 to Items.Count - 1 do
        if Items.Items[Index] is TJSONObject then
          AModel.CrossLinks[Index] := LinkOf(TJSONObject(Items.Items[Index]))
        else
          Exit;
    end;
    if not Consistent(AModel) then
      Exit;
    for Index := 0 to High(AModel.Outliers) do
      AModel.Units[AModel.Outliers[Index].Unit_].Outlier := True;
    for Index := 0 to High(AModel.Cycles) do
      for Inner in AModel.Cycles[Index].Units do
        AModel.Units[Inner].OnCycle := True;
    AModel.Comparison := ComparisonOf(AModel, Answer);
    Result := True;
  finally
    Root.Free;
    if not Result then
      AModel := Default(TAtlasArchitectureModel);
  end;
end;

function TAtlasArchitectureModel.FullPath(const AFileName: string): string;
var
  Name: string;
begin
  Name := StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]);
  Name := StringReplace(Name, '\', PathDelim, [rfReplaceAll]);
  if (Name = '') or (Root = '') or (Name[1] = PathDelim) or ((Length(Name) > 1) and (Name[2] = ':')) then
    Exit(Name);
  Result := IncludeTrailingPathDelimiter(Root) + Name;
end;

function TAtlasArchitectureModel.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Units) do
    if SameText(Units[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TAtlasArchitectureModel.OutlierOf(AUnit: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Outliers) do
    if Outliers[Index].Unit_ = AUnit then
      Exit(Index);
  Result := -1;
end;

function TAtlasArchitectureModel.Matches(AUnit: Integer; const AFilter: string): Boolean;
var
  Word, Name: string;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit(False);
  Name := LowerCase(Units[AUnit].Name);
  for Word in LowerCase(AFilter).Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if Pos(Word, Name) = 0 then
      Exit(False);
  Result := True;
end;

function TAtlasArchitectureModel.Sorted(const AUnits: TArray<Integer>; AColumn: TAtlasArchColumn;
  ADescending: Boolean): TArray<Integer>;
var
  Model: TAtlasArchitectureModel;
begin
  Result := Copy(AUnits);
  Model := Self;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    var
      Left, Right: TAtlasArchUnit;
    begin
      Left := Model.Units[ALeft];
      Right := Model.Units[ARight];
      case AColumn of
        TAtlasArchColumn.Subsystem:
          Result := CompareText(Model.SubsystemName(Left.Subsystem), Model.SubsystemName(Right.Subsystem));
        TAtlasArchColumn.Direct:
          Result := CompareValue(Left.Direct, Right.Direct);
        TAtlasArchColumn.Total:
          Result := CompareValue(Left.Total, Right.Total);
        TAtlasArchColumn.Uses_:
          Result := CompareValue(Left.Uses_, Right.Uses_);
        TAtlasArchColumn.Role:
          Result := CompareText(Left.Role, Right.Role);
      else
        Result := 0;
      end;
      if ADescending then
        Result := -Result;
      // Gleichstand eindeutig: TArray.Sort ist nicht stabil.
      if Result = 0 then
        Result := CompareText(Left.Name, Right.Name);
      if (Result <> 0) and ADescending and (AColumn = TAtlasArchColumn.Name) then
        Result := -Result;
      if Result = 0 then
        Result := CompareValue(ALeft, ARight);
    end));
end;

function TAtlasArchitectureModel.SubsystemName(ASubsystem: Integer): string;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(Subsystems)) then
    Result := Subsystems[ASubsystem].Name
  else
    Result := '';
end;

function TAtlasArchitectureModel.CyclePath(const ACycle: TAtlasArchCycle): string;
var
  Member: Integer;
begin
  Result := '';
  for Member in ACycle.Units do
    if (Member >= 0) and (Member < Length(Units)) then
    begin
      if Result <> '' then
        Result := Result + ' → ';
      Result := Result + Units[Member].Name;
    end;
  if (Length(ACycle.Units) > 0) and (ACycle.Units[0] >= 0) and (ACycle.Units[0] < Length(Units)) then
    Result := Result + ' → ' + Units[ACycle.Units[0]].Name;
end;

function TAtlasArchitectureModel.NodeRadius(AUnit: Integer): Double;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit(5);
  Result := 5 + Sqrt(Max(0, Units[AUnit].Total)) * 1.8;
end;

function TAtlasArchitectureModel.IsHidden(AUnit: Integer; const AHidden: TArray<Boolean>): Boolean;
var
  Subsystem: Integer;
begin
  Result := False;
  if (AUnit < 0) or (AUnit > High(Units)) then
    Exit;
  Subsystem := Units[AUnit].Subsystem;
  Result := (Subsystem >= 0) and (Subsystem < Length(AHidden)) and AHidden[Subsystem];
end;

function TAtlasArchitectureModel.ShortestPath(AFrom, ATo: Integer; AImplementation: Boolean;
  const AHidden: TArray<Boolean>; out AEdges: TArray<Integer>): Boolean;
var
  Outgoing: TArray<TArray<Integer>>;
  Previous, Queue: TArray<Integer>;
  Head, Tail, Current, Edge, Index: Integer;
  Reached: TArray<Boolean>;
begin
  AEdges := nil;
  Result := False;
  if (AFrom < 0) or (AFrom > High(Units)) or (ATo < 0) or (ATo > High(Units)) or (AFrom = ATo) then
    Exit;
  SetLength(Outgoing, Length(Units));
  for Index := 0 to High(Edges) do
    Outgoing[Edges[Index].Source] := Outgoing[Edges[Index].Source] + [Index];
  SetLength(Previous, Length(Units));
  SetLength(Reached, Length(Units));
  SetLength(Queue, Length(Units));
  Reached[AFrom] := True;
  Previous[AFrom] := -1;
  Queue[0] := AFrom;
  Head := 0;
  Tail := 1;
  while (Head < Tail) and not Reached[ATo] do
  begin
    Current := Queue[Head];
    Inc(Head);
    for Edge in Outgoing[Current] do
    begin
      Index := Edges[Edge].Target;
      if Reached[Index] or (not AImplementation and not Edges[Edge].Interface_) or IsHidden(Index, AHidden) then
        Continue;
      Reached[Index] := True;
      Previous[Index] := Edge;
      Queue[Tail] := Index;
      Inc(Tail);
    end;
  end;
  if not Reached[ATo] then
    Exit;
  Current := ATo;
  while Current <> AFrom do
  begin
    AEdges := TArray<Integer>.Create(Previous[Current]) + AEdges;
    Current := Edges[Previous[Current]].Source;
  end;
  Result := True;
end;

function TAtlasArchitectureModel.PathText(AFrom: Integer; const AEdges: TArray<Integer>): string;
var
  Edge: Integer;
begin
  Result := '';
  if (AFrom < 0) or (AFrom > High(Units)) then
    Exit;
  Result := Units[AFrom].Name;
  for Edge in AEdges do
    if (Edge >= 0) and (Edge <= High(Edges)) then
      Result := Result + ' → ' + Units[Edges[Edge].Target].Name;
end;

function TAtlasArchitectureModel.RouteOf(const ANames: TArray<string>; out AUnits, AEdges: TArray<Integer>): Boolean;
var
  Name: string;
  Unit_, Index, Edge, Previous: Integer;
  Direct: Integer;
  Bridge: TArray<Integer>;
begin
  AUnits := nil;
  AEdges := nil;
  for Name in ANames do
  begin
    Unit_ := IndexOf(Name);
    if (Unit_ < 0) or ((Length(AUnits) > 0) and (AUnits[High(AUnits)] = Unit_)) then
      Continue;
    if Length(AUnits) > 0 then
    begin
      Previous := AUnits[High(AUnits)];
      // Vorwärts zuerst; ein Weg über Vererbung oder Umsetzung kann auch gegen die uses-Richtung laufen.
      Direct := -1;
      for Index := 0 to High(Edges) do
        if (Edges[Index].Source = Previous) and (Edges[Index].Target = Unit_) then
        begin
          Direct := Index;
          Break;
        end;
      if Direct < 0 then
        for Index := 0 to High(Edges) do
          if (Edges[Index].Source = Unit_) and (Edges[Index].Target = Previous) then
          begin
            Direct := Index;
            Break;
          end;
      if Direct >= 0 then
        AEdges := AEdges + [Direct]
      else if ShortestPath(Previous, Unit_, True, nil, Bridge) then
        for Edge in Bridge do
        begin
          AEdges := AEdges + [Edge];
          // Zwischen-Units der Brücke gehören zum Weg (Ziel der letzten Kante ist Unit_ selbst).
          if Edges[Edge].Target <> Unit_ then
            AUnits := AUnits + [Edges[Edge].Target];
        end;
    end;
    AUnits := AUnits + [Unit_];
  end;
  Result := Length(AUnits) > 0;
end;

function TAtlasArchitectureModel.RouteText(const AUnits: TArray<Integer>): string;
var
  Unit_: Integer;
begin
  Result := '';
  for Unit_ in AUnits do
    if (Unit_ >= 0) and (Unit_ <= High(Units)) then
    begin
      if Result <> '' then
        Result := Result + ' → ';
      Result := Result + Units[Unit_].Name;
    end;
end;

function TAtlasArchitectureModel.SubsystemCount: Integer;
var
  mSubsystem: TAtlasArchSubsystem;
begin
  Result := 0;
  for mSubsystem in Subsystems do
    if not mSubsystem.Isolated then
      Inc(Result);
end;

function TAtlasArchComparison.ResolutionDiffers: Boolean;
begin
  Result := Present and not TAtlasArchResolution.Same(BaselineResolution, Resolution);
end;

{ TAtlasArchitectureOptions }

class function TAtlasArchitectureOptions.Create(const AScope: string;
  AIncludeLibrary: Boolean): TAtlasArchitectureOptions;
begin
  Result.Scope := AScope;
  Result.IncludeLibrary := AIncludeLibrary;
  Result.CompareWith := '';
  Result.Compare := True;
  Result.Resolution := 0;
end;

{ TAtlasArchResolution }

class function TAtlasArchResolution.Clamp(AValue: Double): Double;
begin
  if IsNan(AValue) or (AValue <= 0) then
    Exit(1);
  Result := EnsureRange(AValue, MinValue, MaxValue);
end;

class function TAtlasArchResolution.ValueAt(APosition: Integer): Double;
begin
  // 0,2 · 25^(p/Steps): Mitte 0,2 · 5 = 1,0.
  Result := MinValue * Power(MaxValue / MinValue, EnsureRange(APosition, 0, Steps) / Steps);
  Result := Round(Result * 100) / 100;
end;

class function TAtlasArchResolution.PositionOf(AValue: Double): Integer;
begin
  Result := Round(Ln(Clamp(AValue) / MinValue) / Ln(MaxValue / MinValue) * Steps);
  Result := EnsureRange(Result, 0, Steps);
end;

class function TAtlasArchResolution.Text(AValue: Double; const AFormat: TFormatSettings): string;
begin
  Result := FormatFloat('0.0#', AValue, AFormat);
end;

class function TAtlasArchResolution.Same(ALeft, ARight: Double): Boolean;
begin
  Result := Abs(ALeft - ARight) < 0.005;
end;

{ TAtlasArchitectureGroupingSettings }

class procedure TAtlasArchitectureGroupingSettings.Read(const AGlobalText: string; out AResolution: Double;
  out AShowSlider: Boolean);
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
begin
  AResolution := 1;
  AShowSlider := True;
  mRoot := TAtlasJsonText.Parse(AGlobalText);
  try
    if mRoot = nil then
      Exit;
    mValue := TJSONObject.ParseJSONValue(TAtlasJsonText.ValueAt(mRoot, ResolutionPath));
    try
      if mValue is TJSONNumber then
        AResolution := TAtlasArchResolution.Clamp(TJSONNumber(mValue).AsDouble);
    finally
      mValue.Free;
    end;
    AShowSlider := TAtlasJsonText.ValueAt(mRoot, SliderPath) <> 'false';
  finally
    mRoot.Free;
  end;
end;

class function TAtlasArchitectureGroupingSettings.WithResolution(const AGlobalText: string; AValue: Double): string;
begin
  Result := TAtlasJsonText.SetValue(AGlobalText, ResolutionPath,
    TAtlasArchResolution.Text(TAtlasArchResolution.Clamp(AValue), TFormatSettings.Invariant));
end;

{ TAtlasArchitectureCommands }

function Options(const AOptions: TAtlasArchitectureOptions): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('scope', AOptions.Scope);
  Result.AddPair('includeLibraryUnits', TJSONBool.Create(AOptions.IncludeLibrary));
  if AOptions.CompareWith <> '' then
    Result.AddPair('compareWith', AOptions.CompareWith)
  else if not AOptions.Compare then
    Result.AddPair('compare', TJSONBool.Create(False));
  if AOptions.Resolution > 0 then
    Result.AddPair('resolution', TJSONNumber.Create(TAtlasArchResolution.Clamp(AOptions.Resolution)));
end;

function ComparedOptions(const AScope: string; AIncludeLibrary: Boolean; const ACompareWith: string;
  ACompare: Boolean): TAtlasArchitectureOptions;
begin
  Result := TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary);
  Result.CompareWith := ACompareWith;
  Result.Compare := ACompare;
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri, AScope: string;
  AIncludeLibrary: Boolean): string;
begin
  Result := Arguments(AProjectUri, TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary));
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri, AScope: string; AIncludeLibrary: Boolean;
  const ACompareWith: string; ACompare: Boolean): string;
begin
  Result := Arguments(AProjectUri, ComparedOptions(AScope, AIncludeLibrary, ACompareWith, ACompare));
end;

class function TAtlasArchitectureCommands.Arguments(const AProjectUri: string;
  const AOptions: TAtlasArchitectureOptions): string;
var
  Items: TJSONArray;
  Option: TJSONObject;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Option := Options(AOptions);
    Option.AddPair('format', 'json');
    Items.AddElement(Option);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName, AScope: string;
  AIncludeLibrary: Boolean): string;
begin
  Result := SaveArguments(AProjectUri, AFileName, TAtlasArchitectureOptions.Create(AScope, AIncludeLibrary));
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName, AScope: string;
  AIncludeLibrary: Boolean; const ACompareWith: string; ACompare: Boolean): string;
begin
  Result := SaveArguments(AProjectUri, AFileName, ComparedOptions(AScope, AIncludeLibrary, ACompareWith, ACompare));
end;

class function TAtlasArchitectureCommands.SaveArguments(const AProjectUri, AFileName: string;
  const AOptions: TAtlasArchitectureOptions): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Items.Add(AFileName);
    Items.AddElement(Options(AOptions));
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasArchitectureCommands.SavedFile(const AAnswer: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AAnswer);
  try
    if Root is TJSONObject then
      Result := TextOf(TJSONObject(Root), 'file');
  finally
    Root.Free;
  end;
end;

{ TAtlasArchitecturePalette }

class function TAtlasArchitecturePalette.Color(ASubsystem: Integer; ADark: Boolean): Cardinal;
var
  Rgb: Cardinal;
  Slot: Integer;
begin
  Slot := Abs(ASubsystem) mod Count;
  if ADark then
    Rgb := DarkColors[Slot]
  else
    Rgb := LightColors[Slot];
  // #RRGGBB → $00BBGGRR.
  Result := ((Rgb and $FF) shl 16) or (Rgb and $FF00) or ((Rgb shr 16) and $FF);
end;

class function TAtlasArchitecturePalette.IsDark(ABackground: Cardinal): Boolean;
var
  Red, Green, Blue: Integer;
begin
  Red := ABackground and $FF;
  Green := (ABackground shr 8) and $FF;
  Blue := (ABackground shr 16) and $FF;
  Result := (Red * 299 + Green * 587 + Blue * 114) div 1000 < 128;
end;

{ TAtlasArchitectureView }

procedure TAtlasArchitectureView.Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
var
  Subsystem: TAtlasArchSubsystem;
  Left, Top, Right, Bottom: Double;
begin
  Scale := 1;
  OffsetX := AWidth / 2;
  OffsetY := AHeight / 2;
  if Length(AModel.Subsystems) = 0 then
    Exit;
  Left := MaxDouble;
  Top := MaxDouble;
  Right := -MaxDouble;
  Bottom := -MaxDouble;
  for Subsystem in AModel.Subsystems do
  begin
    Left := Min(Left, Subsystem.X - Subsystem.R);
    Top := Min(Top, Subsystem.Y - Subsystem.R);
    Right := Max(Right, Subsystem.X + Subsystem.R);
    Bottom := Max(Bottom, Subsystem.Y + Subsystem.R);
  end;
  Scale := Min(Min((AWidth - 2 * Margin) / Max(1, Right - Left), (AHeight - 2 * Margin) / Max(1, Bottom - Top)), 2);
  Scale := EnsureRange(Scale, MinScale, MaxScale);
  OffsetX := AWidth / 2 - (Left + Right) / 2 * Scale;
  OffsetY := AHeight / 2 - (Top + Bottom) / 2 * Scale;
end;

function TAtlasArchitectureView.ScreenX(AX: Double): Double;
begin
  Result := AX * Scale + OffsetX;
end;

function TAtlasArchitectureView.ScreenY(AY: Double): Double;
begin
  Result := AY * Scale + OffsetY;
end;

function TAtlasArchitectureView.WorldX(AX: Double): Double;
begin
  Result := (AX - OffsetX) / Scale;
end;

function TAtlasArchitectureView.WorldY(AY: Double): Double;
begin
  Result := (AY - OffsetY) / Scale;
end;

procedure TAtlasArchitectureView.ZoomAt(AFactor: Double; AX, AY: Double);
var
  Next: Double;
begin
  Next := EnsureRange(Scale * AFactor, MinScale, MaxScale);
  OffsetX := AX - (AX - OffsetX) * Next / Scale;
  OffsetY := AY - (AY - OffsetY) * Next / Scale;
  Scale := Next;
end;

procedure TAtlasArchitectureView.Pan(ADX, ADY: Double);
begin
  OffsetX := OffsetX + ADX;
  OffsetY := OffsetY + ADY;
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer;
begin
  Result := UnitAt(AModel, AX, AY, nil);
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
  const AHidden: TArray<Boolean>): Integer;
var
  Index: Integer;
  X, Y, Radius: Double;
begin
  X := WorldX(AX);
  Y := WorldY(AY);
  // Rückwärts: Später gezeichnete Units liegen oben.
  for Index := High(AModel.Units) downto 0 do
  begin
    if AModel.IsHidden(Index, AHidden) then
      Continue;
    // Mindestens 4 Bildpunkte, damit kleine Units weit herausgezoomt treffbar bleiben.
    Radius := Max(AModel.NodeRadius(Index), 4 / Scale);
    if Sqr(AModel.Units[Index].X - X) + Sqr(AModel.Units[Index].Y - Y) <= Sqr(Radius) then
      Exit(Index);
  end;
  Result := -1;
end;

end.
