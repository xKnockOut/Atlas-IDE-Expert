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
//   je für helle und dunkle Themen; die Teile eines nachgeteilten
//   Teilsystems (#1364, "parent") teilen eine Farbe ("color") in helleren und
//   dunkleren Tönen ("shade"); das Teilsystem „Fundament“ (#1365,
//   "foundation") in neutraler Farbe wie --muted der HTML-Karte.
// - Comparison: Vergleich mit einem gespeicherten Stand (#1121) aus
//   "comparison" (Daten aus TArchitectureComparer.Json), "baseline" und
//   "comparisonError" der Antwort: Abschnitte mit Einträgen (Namen statt
//   Nummern, je mit der Unit des aktuellen Stands zum Springen), dazu die
//   geänderten Kanten für die Karte (neue als Nummern in Edges, entfernte
//   zwischen Units, die es noch gibt).
// - Feinheit der Teilsysteme (#1366): Resolution aus "grouping" der Daten,
//   TAtlasArchResolution rechnet zwischen Reglerstellung (logarithmisch über
//   0,2–5,0, Mitte = 1,0) und Wert, TAtlasArchitectureGroupingSettings liest
//   und schreibt architecture.grouping in settings.json. Die Befehle
//   (Atlas.Core.Architecture.Commands) nehmen "resolution" mit.
// - Zuordnung (#1368): je Unit "assignment" (Kanten je Teilsystem) und
//   "close" (knapp, fehlende Kanten), dazu "explanation"; fehlen mit
//   architecture.explainAssignment = false, dann HasAssignment False.
// - Angleichung (#1367): "aligned" (Herkunft, Zeitpunkt, behaltene
//   Teilsysteme) für die Statuszeile; RenameSubsystems in den Optionen
//   schickt "renameSubsystems" (einmal ohne Angleichung rechnen).

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Kanten einer Unit zu einem Teilsystem (#1368).</summary>
  TAtlasArchAssignmentRow = record
    Subsystem: Integer;
    Interfaces: Integer;
    Implementations: Integer;
    /// <summary>False bei Kanten zum Teilsystem „Fundament“: zählen bei der Zuordnung nicht.</summary>
    Counts: Boolean;
    /// <summary>Gewichtete Summe wie TArchitectureAnalyzer: interface 2, implementation 1.</summary>
    function Sum: Integer;
  end;

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
    /// <summary>Kanten je Teilsystem, nach Summe absteigend (#1368); leer ohne explainAssignment.</summary>
    Assignment: TArray<TAtlasArchAssignmentRow>;
    /// <summary>Knapp zugeordnet; Missing: gewichtete Kanten, die zum Wechsel fehlen (0 = schon gleich viele).
    /// </summary>
    Close: Boolean;
    Missing: Integer;
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
    /// <summary>Ursprüngliches Teilsystem, wenn dieses nachgeteilt wurde (#1364); '' sonst.</summary>
    Parent: string;
    /// <summary>Farbe in der Palette (ältere Daten: Nummer des Teilsystems) und Ton (0, heller +, dunkler −).</summary>
    ColorSlot: Integer;
    Shade: Integer;
    /// <summary>Teilsystem „Fundament“ der übergreifenden Fundament-Units (#1365): ohne Zusammenhalt.</summary>
    Foundation: Boolean;
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
    /// <summary>Wie die Teilsysteme gebildet werden, mit den aktiven Einstellungen (#1368, Text des Berichts);
    /// '' ohne explainAssignment.</summary>
    Explanation: string;
    /// <summary>Übrige Einstellungen der Gruppierung aus "grouping" (#1364, #1365) für die Erklärung im Fenster;
    /// Vorgaben ohne Angabe.</summary>
    MaxShare: Double;
    MinCohesion: Double;
    /// <summary>"group", "attach" oder "separate".</summary>
    Foundations: string;
    /// <summary>Angleichung an einen vorigen Stand (#1367, "aligned"): "baseline", "last" oder '' ohne; Zeitpunkt
    /// des Stands wie "created" und Zahl der Teilsysteme, die Farbe und Namen behielten.</summary>
    AlignedSource: string;
    AlignedAt: string;
    AlignedKept: Integer;
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
    /// <summary>Farbe des Teilsystems in Karte und Legende (Farbfamilie bei Nachteilung, #1364).</summary>
    function SubsystemColor(ASubsystem: Integer; ADark: Boolean): Cardinal;
    /// <summary>Die Kante führt ins oder aus dem Teilsystem „Fundament“ (#1365).</summary>
    function TouchesFoundation(const AEdge: TAtlasArchEdge): Boolean;
    /// <summary>Es gibt ein Teilsystem „Fundament“.</summary>
    function HasFoundation: Boolean;
    /// <summary>Der Server hat die Zuordnung mitgeschickt (architecture.explainAssignment, #1368).</summary>
    function HasAssignment: Boolean;
    /// <summary>Zeitpunkt der Angleichung (#1367) als „2026-10-29 14:23“; '' ohne.</summary>
    function AlignedText: string;
    /// <summary>Zeile des eigenen bzw. des stärksten anderen zählenden Teilsystems in Units[AUnit].Assignment;
    /// -1 ohne.</summary>
    function OwnRow(AUnit: Integer): Integer;
    function RivalRow(AUnit: Integer): Integer;
    /// <summary>Reihenfolge der Legende: wie Subsystems, die Teile eines nachgeteilten Teilsystems (gleicher
    /// Parent) zusammen an der Stelle des ersten Teils.</summary>
    function LegendOrder: TArray<Integer>;
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

  TAtlasArchitecturePalette = class
  public const
    Count = 10;
    /// <summary>Höchstens so weit wird ein Ton zu Weiß bzw. Schwarz gemischt.</summary>
    MaxShadeMix = 0.6;
    /// <summary>Mischanteil je Tonstufe.</summary>
    ShadeStep = 0.22;
  public
    /// <summary>Farbe des Teilsystems ASubsystem als $00BBGGRR (wie TColor).</summary>
    class function Color(ASubsystem: Integer; ADark: Boolean): Cardinal; overload; static;
    /// <summary>Farbe ASlot im Ton AShade (#1364): positiv heller, negativ dunkler, wie color-mix der HTML-Karte.
    /// </summary>
    class function Color(ASlot, AShade: Integer; ADark: Boolean): Cardinal; overload; static;
    /// <summary>Neutrale Farbe des Teilsystems „Fundament“ (#1365), wie --muted der HTML-Karte.</summary>
    class function FoundationColor(ADark: Boolean): Cardinal; static;
    /// <summary>Hintergrund ($00BBGGRR) ist dunkel: Helligkeit unter der Hälfte.</summary>
    class function IsDark(ABackground: Cardinal): Boolean; static;
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
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end;
end;

function Int64Of(const AObject: TJSONObject; const AName: string): Int64;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  // Über den Text: Generationen liegen über 2^32 (Kennung des Index im oberen Teil).
  if Value is TJSONNumber then
  begin
    Result := StrToInt64Def(Value.Value, 0);
  end;
end;

function FloatOf(const AObject: TJSONObject; const AName: string): Double;
var
  Value: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsDouble;
  end;
end;

function TextOf(const AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := Value.Value;
  end;
end;

function FlagOf(const AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
  begin
    Result := TJSONBool(Value).AsBoolean;
  end;
end;

function ArrayOf(const AObject: TJSONObject; const AName: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  Value := AObject.GetValue(AName);
  if Value is TJSONArray then
  begin
    Result := TJSONArray(Value);
  end;
end;

function IntsOf(const AObject: TJSONObject; const AName: string): TArray<Integer>;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := nil;
  Items := ArrayOf(AObject, AName);
  if Items = nil then
  begin
    Exit;
  end;
  SetLength(Result, Items.Count);
  for Index := 0 to Items.Count - 1 do
  begin
    if Items.Items[Index] is TJSONNumber then
    begin
      Result[Index] := TJSONNumber(Items.Items[Index]).AsInt;
    end
    else
    begin
      Result[Index] := -1;
    end;
  end;
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

function ValidLink(const AModel: TAtlasArchitectureModel; const ALink: TAtlasArchLink): Boolean;
begin
  Result := ValidUnit(AModel, ALink.Source) and ValidUnit(AModel, ALink.Target);
end;

function ValidSubsystem(const AModel: TAtlasArchitectureModel; ASubsystem: Integer): Boolean;
begin
  Result := (ASubsystem >= 0) and (ASubsystem < Length(AModel.Subsystems));
end;

function ValidMembers(const AModel: TAtlasArchitectureModel; const AMembers: TArray<Integer>): Boolean;
var
  mMember: Integer;
begin
  Result := False;
  for mMember in AMembers do
  begin
    if not ValidUnit(AModel, mMember) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

function ValidLinks(const AModel: TAtlasArchitectureModel; const ALinks: TArray<TAtlasArchLink>): Boolean;
var
  mLink: TAtlasArchLink;
begin
  Result := False;
  for mLink in ALinks do
  begin
    if not ValidLink(AModel, mLink) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Teilsystem und Zuordnungszeilen einer Unit verweisen auf vorhandene Teilsysteme.</summary>
function ValidUnitData(const AModel: TAtlasArchitectureModel; const AItem: TAtlasArchUnit): Boolean;
var
  mRow: TAtlasArchAssignmentRow;
begin
  Result := False;
  if not ValidSubsystem(AModel, AItem.Subsystem) then
  begin
    Exit;
  end;
  for mRow in AItem.Assignment do
  begin
    if not ValidSubsystem(AModel, mRow.Subsystem) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

function ValidEdges(const AModel: TAtlasArchitectureModel): Boolean;
var
  mEdge: TAtlasArchEdge;
begin
  Result := False;
  for mEdge in AModel.Edges do
  begin
    if not ValidUnit(AModel, mEdge.Source) or not ValidUnit(AModel, mEdge.Target) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Units der Teilsysteme, Zyklen und Ausreißer verweisen auf vorhandene Units.</summary>
function ValidGroups(const AModel: TAtlasArchitectureModel): Boolean;
var
  mSubsystem: TAtlasArchSubsystem;
  mCycle: TAtlasArchCycle;
  mOutlier: TAtlasArchOutlier;
begin
  Result := False;
  for mSubsystem in AModel.Subsystems do
  begin
    if not ValidMembers(AModel, mSubsystem.Units) then
    begin
      Exit;
    end;
  end;
  for mCycle in AModel.Cycles do
  begin
    if not ValidMembers(AModel, mCycle.Units) or not ValidLinks(AModel, mCycle.Edges) then
    begin
      Exit;
    end;
  end;
  for mOutlier in AModel.Outliers do
  begin
    if not ValidUnit(AModel, mOutlier.Unit_) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Verweise auf Units und Teilsysteme prüfen: Ein Fenster soll an fremden Daten nicht scheitern.</summary>
function Consistent(const AModel: TAtlasArchitectureModel): Boolean;
var
  mItem: TAtlasArchUnit;
begin
  Result := False;
  for mItem in AModel.Units do
  begin
    if not ValidUnitData(AModel, mItem) then
    begin
      Exit;
    end;
  end;
  Result := ValidEdges(AModel) and ValidMembers(AModel, AModel.Central) and ValidGroups(AModel)
    and ValidLinks(AModel, AModel.CrossLinks);
end;

/// <summary>"assignment" und "close" einer Unit (#1368): [Teilsystem, interface, implementation(, 0)]. False bei
/// ungültigem Aufbau.</summary>
function AssignmentOf(AItem: TJSONObject; var AUnit: TAtlasArchUnit): Boolean;
var
  mRows, mRow: TJSONArray;
  mIndex, mPart: Integer;
  mValues: array[0..3] of Integer;
begin
  Result := True;
  if AItem.GetValue('close') is TJSONNumber then
  begin
    AUnit.Close := True;
    AUnit.Missing := TJSONNumber(AItem.GetValue('close')).AsInt;
  end;
  mRows := ArrayOf(AItem, 'assignment');
  if mRows = nil then
  begin
    Exit;
  end;
  SetLength(AUnit.Assignment, mRows.Count);
  for mIndex := 0 to mRows.Count - 1 do
  begin
    if not (mRows.Items[mIndex] is TJSONArray) then
    begin
      Exit(False);
    end;
    mRow := TJSONArray(mRows.Items[mIndex]);
    if (mRow.Count < 3) or (mRow.Count > 4) then
    begin
      Exit(False);
    end;
    mValues[3] := 1;
    for mPart := 0 to mRow.Count - 1 do
    begin
      if mRow.Items[mPart] is TJSONNumber then
      begin
        mValues[mPart] := TJSONNumber(mRow.Items[mPart]).AsInt;
      end
      else
      begin
        Exit(False);
      end;
    end;
    AUnit.Assignment[mIndex].Subsystem := mValues[0];
    AUnit.Assignment[mIndex].Interfaces := mValues[1];
    AUnit.Assignment[mIndex].Implementations := mValues[2];
    AUnit.Assignment[mIndex].Counts := mValues[3] <> 0;
  end;
end;

function NamesOf(const AItems: TJSONArray): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for Index := 0 to AItems.Count - 1 do
  begin
    if AItems.Items[Index] is TJSONString then
    begin
      Result := Result + [AItems.Items[Index].Value];
    end;
  end;
end;

function ChangeOf(const AModel: TAtlasArchitectureModel; const AText, AUnit: string): TAtlasArchChange;
begin
  Result := Default(TAtlasArchChange);
  Result.Text := AText;
  Result.Unit_ := AModel.IndexOf(AUnit);
end;

/// <summary>Eintrag eines Zyklus-Abschnitts; False ohne Units.</summary>
function CycleChange(const AModel: TAtlasArchitectureModel; const AItem: TJSONObject;
  out AChange: TAtlasArchChange): Boolean;
var
  mMembers: TArray<string>;
begin
  mMembers := NamesOf(ArrayOf(AItem, 'units'));
  Result := Length(mMembers) > 0;
  if not Result then
  begin
    AChange := Default(TAtlasArchChange);
    Exit;
  end;
  AChange := ChangeOf(AModel, string.Join(' → ', mMembers) + ' → ' + mMembers[0], mMembers[0]);
  if FlagOf(AItem, 'interfaceOnly') then
  begin
    AChange.Section := 'interface';
  end;
end;

function UnitChange(const AModel: TAtlasArchitectureModel; const AItem: TJSONObject;
  AKind: TAtlasArchChangeKind): TAtlasArchChange;
begin
  Result := ChangeOf(AModel, TextOf(AItem, 'unit'), TextOf(AItem, 'unit'));
  if AKind = TAtlasArchChangeKind.Growth then
  begin
    Result.From := IntToStr(IntOf(AItem, 'before', 0));
    Result.To_ := IntToStr(IntOf(AItem, 'after', 0));
  end
  else
  begin
    Result.From := TextOf(AItem, 'from');
    Result.To_ := TextOf(AItem, 'to');
  end;
end;

function LinkChange(const AModel: TAtlasArchitectureModel; const AItem: TJSONObject): TAtlasArchChange;
begin
  Result := ChangeOf(AModel, TextOf(AItem, 'source') + ' → ' + TextOf(AItem, 'target'), TextOf(AItem, 'source'));
  Result.From := TextOf(AItem, 'from');
  Result.To_ := TextOf(AItem, 'to');
  Result.Section := TextOf(AItem, 'section');
  Result.Reason := TextOf(AItem, 'reason');
end;

/// <summary>Ein Eintrag des Abschnitts AKind (ohne neue und entfernte Units); False, wenn er wegfällt.</summary>
function ItemChange(const AModel: TAtlasArchitectureModel; const AItem: TJSONObject; AKind: TAtlasArchChangeKind;
  out AChange: TAtlasArchChange): Boolean;
begin
  Result := True;
  case AKind of
    TAtlasArchChangeKind.NewCycles, TAtlasArchChangeKind.RemovedCycles:
      begin
        Result := CycleChange(AModel, AItem, AChange);
      end;
    TAtlasArchChangeKind.Moves, TAtlasArchChangeKind.Growth:
      begin
        AChange := UnitChange(AModel, AItem, AKind);
      end;
  else
    AChange := LinkChange(AModel, AItem);
  end;
end;

/// <summary>Einträge eines Abschnitts aus "comparison"; fremde Einträge fallen weg.</summary>
function ChangesOf(const AModel: TAtlasArchitectureModel; const AData: TJSONObject;
  AKind: TAtlasArchChangeKind): TArray<TAtlasArchChange>;
const
  cNames: array[TAtlasArchChangeKind] of string = ('newCycles', 'removedCycles', 'newCrossLinks', 'removedCrossLinks',
    'newEdges', 'removedEdges', 'moves', 'growth', 'newUnits', 'removedUnits');
var
  mItems: TJSONArray;
  mIndex: Integer;
  mChange: TAtlasArchChange;
  mName: string;
begin
  Result := nil;
  mItems := ArrayOf(AData, cNames[AKind]);
  if mItems = nil then
  begin
    Exit;
  end;
  if AKind in [TAtlasArchChangeKind.NewUnits, TAtlasArchChangeKind.RemovedUnits] then
  begin
    for mName in NamesOf(mItems) do
    begin
      Result := Result + [ChangeOf(AModel, mName, mName)];
    end;
    Exit;
  end;
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if (mItems.Items[mIndex] is TJSONObject)
      and ItemChange(AModel, TJSONObject(mItems.Items[mIndex]), AKind, mChange) then
    begin
      Result := Result + [mChange];
    end;
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
  begin
    Exit;
  end;
  for Index := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[Index] is TJSONArray) then
    begin
      Continue;
    end;
    Pair := TJSONArray(Items.Items[Index]);
    if Pair.Count < 3 then
    begin
      Continue;
    end;
    Edge.Source := AModel.IndexOf(Pair.Items[0].Value);
    Edge.Target := AModel.IndexOf(Pair.Items[1].Value);
    Edge.Interface_ := Pair.Items[2].Value = 'i';
    if (Edge.Source >= 0) and (Edge.Target >= 0) then
    begin
      Result := Result + [Edge];
    end;
  end;
end;

/// <summary>"resolution" einer Angabe; 1 ohne oder bei ungültigem Wert (Server vor #1366).</summary>
function ResolutionOf(const AObject: TJSONObject): Double;
begin
  Result := 1;
  if (AObject <> nil) and (AObject.GetValue('resolution') is TJSONNumber) then
  begin
    Result := TAtlasArchResolution.Clamp(FloatOf(AObject, 'resolution'));
  end;
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
  begin
    Exit;
  end;
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
  begin
    Result.BaselineResolution := 1;
  end;
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
  begin
    for Index := 0 to High(AModel.Edges) do
    begin
      if (AModel.Edges[Index].Source = Edge.Source) and (AModel.Edges[Index].Target = Edge.Target) then
      begin
        Result.AddedEdges := Result.AddedEdges + [Index];
        Break;
      end;
    end;
  end;
  Result.DroppedEdges := MapEdgesOf(AModel, Data, 'droppedEdges');
end;

{ TAtlasArchAssignmentRow }

function TAtlasArchAssignmentRow.Sum: Integer;
begin
  Result := Interfaces * 2 + Implementations;
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
  begin
    Inc(Result, Length(Item.Items));
  end;
end;

function TAtlasArchComparison.Section(AKind: TAtlasArchChangeKind): TArray<TAtlasArchChange>;
var
  Item: TAtlasArchChangeSection;
begin
  Result := nil;
  for Item in Sections do
  begin
    if Item.Kind = AKind then
    begin
      Exit(Item.Items);
    end;
  end;
end;

{ TAtlasArchitectureModel }

/// <summary>"grouping" der Daten (#1366); fehlt es, bleiben die Vorgaben.</summary>
procedure ReadGrouping(const AData: TJSONObject; var AModel: TAtlasArchitectureModel);
var
  mItem: TJSONObject;
begin
  AModel.Resolution := 1;
  AModel.MaxShare := 0.25;
  AModel.MinCohesion := 0.3;
  AModel.Foundations := 'separate';
  if not (AData.GetValue('grouping') is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AData.GetValue('grouping'));
  AModel.Resolution := ResolutionOf(mItem);
  if mItem.GetValue('maxShare') is TJSONNumber then
  begin
    AModel.MaxShare := TJSONNumber(mItem.GetValue('maxShare')).AsDouble;
  end;
  if mItem.GetValue('minCohesion') is TJSONNumber then
  begin
    AModel.MinCohesion := TJSONNumber(mItem.GetValue('minCohesion')).AsDouble;
  end;
  if TextOf(mItem, 'foundations') <> '' then
  begin
    AModel.Foundations := TextOf(mItem, 'foundations');
  end;
end;

/// <summary>Kopfdaten, "aligned" und "summary".</summary>
procedure ReadHeader(const AAnswer, AData: TJSONObject; var AModel: TAtlasArchitectureModel);
var
  mItem: TJSONObject;
begin
  AModel.Root := TextOf(AAnswer, 'root');
  AModel.Title := TextOf(AData, 'title');
  AModel.Scope := TextOf(AData, 'scope');
  AModel.Created := TextOf(AData, 'created');
  AModel.IncludeLibrary := FlagOf(AData, 'includeLibrary');
  AModel.DurationMs := IntOf(AData, 'durationMs', 0);
  AModel.Generation := Int64Of(AData, 'generation');
  AModel.Explanation := TextOf(AData, 'explanation');
  ReadGrouping(AData, AModel);
  if AData.GetValue('aligned') is TJSONObject then
  begin
    mItem := TJSONObject(AData.GetValue('aligned'));
    AModel.AlignedSource := TextOf(mItem, 'source');
    AModel.AlignedAt := TextOf(mItem, 'at');
    AModel.AlignedKept := IntOf(mItem, 'kept', 0);
  end;
  if AData.GetValue('summary') is TJSONObject then
  begin
    mItem := TJSONObject(AData.GetValue('summary'));
    AModel.EdgeCount := IntOf(mItem, 'edges', 0);
    AModel.InterfaceCycles := IntOf(mItem, 'interfaceCycles', 0);
  end;
end;

/// <summary>Eintrag AIndex von AItems als Objekt; False, wenn er keins ist.</summary>
function ObjectAt(const AItems: TJSONArray; AIndex: Integer; out AItem: TJSONObject): Boolean;
begin
  Result := AItems.Items[AIndex] is TJSONObject;
  AItem := nil;
  if Result then
  begin
    AItem := TJSONObject(AItems.Items[AIndex]);
  end;
end;

function ReadUnit(const AItem: TJSONObject; var AUnit: TAtlasArchUnit): Boolean;
begin
  AUnit.Name := TextOf(AItem, 'name');
  AUnit.FileName := TextOf(AItem, 'file');
  AUnit.Subsystem := IntOf(AItem, 'subsystem', -1);
  AUnit.Direct := IntOf(AItem, 'direct', 0);
  AUnit.Total := IntOf(AItem, 'total', 0);
  AUnit.Uses_ := IntOf(AItem, 'uses', 0);
  AUnit.Role := TextOf(AItem, 'role');
  AUnit.Library_ := FlagOf(AItem, 'library');
  AUnit.X := FloatOf(AItem, 'x');
  AUnit.Y := FloatOf(AItem, 'y');
  Result := AssignmentOf(AItem, AUnit);
end;

function ReadUnits(const AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := True;
  mItems := ArrayOf(AData, 'units');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Units, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not ObjectAt(mItems, mIndex, mItem) or not ReadUnit(mItem, AModel.Units[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Kante [Quelle, Ziel, "i"/"m"]; False bei ungültigem Aufbau.</summary>
function ReadEdge(const AValue: TJSONValue; out AEdge: TAtlasArchEdge): Boolean;
var
  mPair: TJSONArray;
begin
  AEdge := Default(TAtlasArchEdge);
  Result := False;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  mPair := TJSONArray(AValue);
  if (mPair.Count < 3) or not (mPair.Items[0] is TJSONNumber) or not (mPair.Items[1] is TJSONNumber) then
  begin
    Exit;
  end;
  AEdge.Source := TJSONNumber(mPair.Items[0]).AsInt;
  AEdge.Target := TJSONNumber(mPair.Items[1]).AsInt;
  AEdge.Interface_ := mPair.Items[2].Value = 'i';
  Result := True;
end;

function ReadEdges(const AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  Result := True;
  mItems := ArrayOf(AData, 'edges');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Edges, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not ReadEdge(mItems.Items[mIndex], AModel.Edges[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

procedure ReadExcludes(const AData: TJSONObject; var AModel: TAtlasArchitectureModel);
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  mItems := ArrayOf(AData, 'excludes');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Excludes, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    AModel.Excludes[mIndex] := mItems.Items[mIndex].Value;
  end;
end;

function SubsystemOf(const AItem: TJSONObject; AIndex: Integer): TAtlasArchSubsystem;
begin
  Result := Default(TAtlasArchSubsystem);
  Result.Name := TextOf(AItem, 'name');
  Result.Units := IntsOf(AItem, 'units');
  Result.Central := IntOf(AItem, 'central', -1);
  Result.Inner := IntOf(AItem, 'inner', 0);
  Result.Outer := IntOf(AItem, 'outer', 0);
  Result.Cohesion := FloatOf(AItem, 'cohesion');
  Result.Isolated := FlagOf(AItem, 'isolated');
  Result.Parent := TextOf(AItem, 'parent');
  Result.ColorSlot := IntOf(AItem, 'color', AIndex);
  Result.Shade := IntOf(AItem, 'shade', 0);
  Result.Foundation := FlagOf(AItem, 'foundation');
  Result.X := FloatOf(AItem, 'x');
  Result.Y := FloatOf(AItem, 'y');
  Result.R := FloatOf(AItem, 'r');
end;

function ReadSubsystems(const AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := True;
  mItems := ArrayOf(AData, 'subsystems');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Subsystems, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not ObjectAt(mItems, mIndex, mItem) then
    begin
      Exit(False);
    end;
    AModel.Subsystems[mIndex] := SubsystemOf(mItem, mIndex);
  end;
end;

function ReadOutlier(const AItem: TJSONObject): TAtlasArchOutlier;
begin
  Result := Default(TAtlasArchOutlier);
  Result.Unit_ := IntOf(AItem, 'unit', -1);
  Result.Suggested := IntOf(AItem, 'suggested', -1);
  Result.Reason := TextOf(AItem, 'reason');
  Result.Inside := IntOf(AItem, 'inside', 0);
  Result.Toward := IntOf(AItem, 'toward', 0);
end;

function ReadOutliers(const AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := True;
  mItems := ArrayOf(AData, 'outliers');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Outliers, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not ObjectAt(mItems, mIndex, mItem) then
    begin
      Exit(False);
    end;
    AModel.Outliers[mIndex] := ReadOutlier(mItem);
  end;
end;

/// <summary>Verweise AItems (Objekte {"source", "target", …}) als Links; False bei einem anderen Eintrag.</summary>
function ReadLinks(const AItems: TJSONArray; out ALinks: TArray<TAtlasArchLink>): Boolean;
var
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := True;
  ALinks := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  SetLength(ALinks, AItems.Count);
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if not ObjectAt(AItems, mIndex, mItem) then
    begin
      Exit(False);
    end;
    ALinks[mIndex] := LinkOf(mItem);
  end;
end;

function ReadCycles(const AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := True;
  mItems := ArrayOf(AData, 'cycles');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(AModel.Cycles, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not ObjectAt(mItems, mIndex, mItem) then
    begin
      Exit(False);
    end;
    AModel.Cycles[mIndex].InterfaceOnly := FlagOf(mItem, 'interfaceOnly');
    AModel.Cycles[mIndex].Units := IntsOf(mItem, 'units');
    if not ReadLinks(ArrayOf(mItem, 'edges'), AModel.Cycles[mIndex].Edges) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Ausreißer und Units auf Zyklen markieren (nach Consistent).</summary>
procedure MarkUnits(var AModel: TAtlasArchitectureModel);
var
  mIndex, mMember: Integer;
begin
  for mIndex := 0 to High(AModel.Outliers) do
  begin
    AModel.Units[AModel.Outliers[mIndex].Unit_].Outlier := True;
  end;
  for mIndex := 0 to High(AModel.Cycles) do
  begin
    for mMember in AModel.Cycles[mIndex].Units do
    begin
      AModel.Units[mMember].OnCycle := True;
    end;
  end;
end;

/// <summary>Teile von "data" nacheinander; False beim ersten ungültigen.</summary>
function ReadData(const AAnswer, AData: TJSONObject; var AModel: TAtlasArchitectureModel): Boolean;
begin
  ReadHeader(AAnswer, AData, AModel);
  Result := ReadUnits(AData, AModel) and ReadEdges(AData, AModel);
  if not Result then
  begin
    Exit;
  end;
  AModel.Central := IntsOf(AData, 'central');
  ReadExcludes(AData, AModel);
  Result := ReadSubsystems(AData, AModel) and ReadOutliers(AData, AModel) and ReadCycles(AData, AModel)
    and ReadLinks(ArrayOf(AData, 'crossLinks'), AModel.CrossLinks) and Consistent(AModel);
  if Result then
  begin
    MarkUnits(AModel);
    AModel.Comparison := ComparisonOf(AModel, AAnswer);
  end;
end;

class function TAtlasArchitectureModel.Parse(const AAnswer: string; out AModel: TAtlasArchitectureModel;
  out AEnabled: Boolean): Boolean;
var
  mRoot: TJSONValue;
  mAnswer: TJSONObject;
begin
  AModel := Default(TAtlasArchitectureModel);
  AEnabled := False;
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AAnswer);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mAnswer := TJSONObject(mRoot);
    AEnabled := FlagOf(mAnswer, 'enabled');
    if not AEnabled then
    begin
      Exit(mAnswer.GetValue('enabled') is TJSONBool);
    end;
    Result := (mAnswer.GetValue('data') is TJSONObject)
      and (IntOf(TJSONObject(mAnswer.GetValue('data')), 'format', 0) = Format)
      and ReadData(mAnswer, TJSONObject(mAnswer.GetValue('data')), AModel);
  finally
    mRoot.Free;
    if not Result then
    begin
      AModel := Default(TAtlasArchitectureModel);
    end;
  end;
end;

function TAtlasArchitectureModel.FullPath(const AFileName: string): string;
var
  Name: string;
begin
  Name := StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]);
  Name := StringReplace(Name, '\', PathDelim, [rfReplaceAll]);
  if (Name = '') or (Root = '') or (Name[1] = PathDelim) or ((Length(Name) > 1) and (Name[2] = ':')) then
  begin
    Exit(Name);
  end;
  Result := IncludeTrailingPathDelimiter(Root) + Name;
end;

function TAtlasArchitectureModel.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Units) do
  begin
    if SameText(Units[Index].Name, AName) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasArchitectureModel.OutlierOf(AUnit: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Outliers) do
  begin
    if Outliers[Index].Unit_ = AUnit then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasArchitectureModel.Matches(AUnit: Integer; const AFilter: string): Boolean;
var
  Word, Name: string;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
  begin
    Exit(False);
  end;
  Name := LowerCase(Units[AUnit].Name);
  for Word in LowerCase(AFilter).Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if Pos(Word, Name) = 0 then
    begin
      Exit(False);
    end;
  end;
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
      begin
        Result := -Result;
      end;
      // Gleichstand eindeutig: TArray.Sort ist nicht stabil.
      if Result = 0 then
      begin
        Result := CompareText(Left.Name, Right.Name);
      end;
      if (Result <> 0) and ADescending and (AColumn = TAtlasArchColumn.Name) then
      begin
        Result := -Result;
      end;
      if Result = 0 then
      begin
        Result := CompareValue(ALeft, ARight);
      end;
    end));
end;

function TAtlasArchitectureModel.SubsystemName(ASubsystem: Integer): string;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(Subsystems)) then
  begin
    Result := Subsystems[ASubsystem].Name;
  end
  else
  begin
    Result := '';
  end;
end;

function TAtlasArchitectureModel.CyclePath(const ACycle: TAtlasArchCycle): string;
var
  Member: Integer;
begin
  Result := '';
  for Member in ACycle.Units do
  begin
    if (Member >= 0) and (Member < Length(Units)) then
    begin
      if Result <> '' then
      begin
        Result := Result + ' → ';
      end;
      Result := Result + Units[Member].Name;
    end;
  end;
  if (Length(ACycle.Units) > 0) and (ACycle.Units[0] >= 0) and (ACycle.Units[0] < Length(Units)) then
  begin
    Result := Result + ' → ' + Units[ACycle.Units[0]].Name;
  end;
end;

function TAtlasArchitectureModel.NodeRadius(AUnit: Integer): Double;
begin
  if (AUnit < 0) or (AUnit > High(Units)) then
  begin
    Exit(5);
  end;
  Result := 5 + Sqrt(Max(0, Units[AUnit].Total)) * 1.8;
end;

function TAtlasArchitectureModel.IsHidden(AUnit: Integer; const AHidden: TArray<Boolean>): Boolean;
var
  Subsystem: Integer;
begin
  Result := False;
  if (AUnit < 0) or (AUnit > High(Units)) then
  begin
    Exit;
  end;
  Subsystem := Units[AUnit].Subsystem;
  Result := (Subsystem >= 0) and (Subsystem < Length(AHidden)) and AHidden[Subsystem];
end;

/// <summary>Je Unit die Nummern der Kanten, die von ihr ausgehen.</summary>
function OutgoingOf(const AModel: TAtlasArchitectureModel): TArray<TArray<Integer>>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AModel.Units));
  for mIndex := 0 to High(AModel.Edges) do
  begin
    Result[AModel.Edges[mIndex].Source] := Result[AModel.Edges[mIndex].Source] + [mIndex];
  end;
end;

/// <summary>Kanten von AFrom nach ATo rückwärts aus APrevious (Kante, über die eine Unit erreicht wurde).</summary>
function PathBack(const AModel: TAtlasArchitectureModel; AFrom, ATo: Integer;
  const APrevious: TArray<Integer>): TArray<Integer>;
var
  mCurrent: Integer;
begin
  Result := nil;
  mCurrent := ATo;
  while mCurrent <> AFrom do
  begin
    Result := TArray<Integer>.Create(APrevious[mCurrent]) + Result;
    mCurrent := AModel.Edges[APrevious[mCurrent]].Source;
  end;
end;

function TAtlasArchitectureModel.ShortestPath(AFrom, ATo: Integer; AImplementation: Boolean;
  const AHidden: TArray<Boolean>; out AEdges: TArray<Integer>): Boolean;
var
  mOutgoing: TArray<TArray<Integer>>;
  mPrevious, mQueue: TArray<Integer>;
  mHead, mTail, mEdge, mTarget: Integer;
  mReached: TArray<Boolean>;
begin
  AEdges := nil;
  Result := False;
  if not ValidUnit(Self, AFrom) or not ValidUnit(Self, ATo) or (AFrom = ATo) then
  begin
    Exit;
  end;
  mOutgoing := OutgoingOf(Self);
  SetLength(mPrevious, Length(Units));
  SetLength(mReached, Length(Units));
  SetLength(mQueue, Length(Units));
  mReached[AFrom] := True;
  mPrevious[AFrom] := -1;
  mQueue[0] := AFrom;
  mHead := 0;
  mTail := 1;
  while (mHead < mTail) and not mReached[ATo] do
  begin
    for mEdge in mOutgoing[mQueue[mHead]] do
    begin
      mTarget := Edges[mEdge].Target;
      if not mReached[mTarget] and (AImplementation or Edges[mEdge].Interface_) and not IsHidden(mTarget, AHidden) then
      begin
        mReached[mTarget] := True;
        mPrevious[mTarget] := mEdge;
        mQueue[mTail] := mTarget;
        Inc(mTail);
      end;
    end;
    Inc(mHead);
  end;
  Result := mReached[ATo];
  if Result then
  begin
    AEdges := PathBack(Self, AFrom, ATo, mPrevious);
  end;
end;

function TAtlasArchitectureModel.PathText(AFrom: Integer; const AEdges: TArray<Integer>): string;
var
  Edge: Integer;
begin
  Result := '';
  if (AFrom < 0) or (AFrom > High(Units)) then
  begin
    Exit;
  end;
  Result := Units[AFrom].Name;
  for Edge in AEdges do
  begin
    if (Edge >= 0) and (Edge <= High(Edges)) then
    begin
      Result := Result + ' → ' + Units[Edges[Edge].Target].Name;
    end;
  end;
end;

/// <summary>Nummer der Kante ASource → ATarget, -1 ohne.</summary>
function EdgeFromTo(const AModel: TAtlasArchitectureModel; ASource, ATarget: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AModel.Edges) do
  begin
    if (AModel.Edges[mIndex].Source = ASource) and (AModel.Edges[mIndex].Target = ATarget) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Schritt von APrevious zu AUnit an den Weg hängen: direkte Kante (vorwärts zuerst; ein Weg über
/// Vererbung oder Umsetzung kann auch gegen die uses-Richtung laufen), sonst die kürzeste Brücke.</summary>
procedure AppendStep(const AModel: TAtlasArchitectureModel; APrevious, AUnit: Integer;
  var AUnits, AEdges: TArray<Integer>);
var
  mDirect, mEdge: Integer;
  mBridge: TArray<Integer>;
begin
  mDirect := EdgeFromTo(AModel, APrevious, AUnit);
  if mDirect < 0 then
  begin
    mDirect := EdgeFromTo(AModel, AUnit, APrevious);
  end;
  if mDirect >= 0 then
  begin
    AEdges := AEdges + [mDirect];
    Exit;
  end;
  if not AModel.ShortestPath(APrevious, AUnit, True, nil, mBridge) then
  begin
    Exit;
  end;
  for mEdge in mBridge do
  begin
    AEdges := AEdges + [mEdge];
    // Zwischen-Units der Brücke gehören zum Weg (Ziel der letzten Kante ist AUnit selbst).
    if AModel.Edges[mEdge].Target <> AUnit then
    begin
      AUnits := AUnits + [AModel.Edges[mEdge].Target];
    end;
  end;
end;

function TAtlasArchitectureModel.RouteOf(const ANames: TArray<string>; out AUnits, AEdges: TArray<Integer>): Boolean;
var
  mName: string;
  mUnit: Integer;
begin
  AUnits := nil;
  AEdges := nil;
  for mName in ANames do
  begin
    mUnit := IndexOf(mName);
    if (mUnit < 0) or ((Length(AUnits) > 0) and (AUnits[High(AUnits)] = mUnit)) then
    begin
      Continue;
    end;
    if Length(AUnits) > 0 then
    begin
      AppendStep(Self, AUnits[High(AUnits)], mUnit, AUnits, AEdges);
    end;
    AUnits := AUnits + [mUnit];
  end;
  Result := Length(AUnits) > 0;
end;

function TAtlasArchitectureModel.RouteText(const AUnits: TArray<Integer>): string;
var
  Unit_: Integer;
begin
  Result := '';
  for Unit_ in AUnits do
  begin
    if (Unit_ >= 0) and (Unit_ <= High(Units)) then
    begin
      if Result <> '' then
      begin
        Result := Result + ' → ';
      end;
      Result := Result + Units[Unit_].Name;
    end;
  end;
end;

function TAtlasArchitectureModel.SubsystemCount: Integer;
var
  mSubsystem: TAtlasArchSubsystem;
begin
  Result := 0;
  for mSubsystem in Subsystems do
  begin
    if not mSubsystem.Isolated then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasArchitectureModel.SubsystemColor(ASubsystem: Integer; ADark: Boolean): Cardinal;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(Subsystems)) and Subsystems[ASubsystem].Foundation then
  begin
    Result := TAtlasArchitecturePalette.FoundationColor(ADark);
  end
  else if (ASubsystem >= 0) and (ASubsystem < Length(Subsystems)) then
  begin
    Result := TAtlasArchitecturePalette.Color(Subsystems[ASubsystem].ColorSlot, Subsystems[ASubsystem].Shade, ADark);
  end
  else
  begin
    Result := TAtlasArchitecturePalette.Color(ASubsystem, ADark);
  end;
end;

function TAtlasArchitectureModel.TouchesFoundation(const AEdge: TAtlasArchEdge): Boolean;

  function InFoundation(AUnit: Integer): Boolean;
  begin
    Result := (AUnit >= 0) and (AUnit < Length(Units)) and (Units[AUnit].Subsystem >= 0) and
      (Units[AUnit].Subsystem < Length(Subsystems)) and Subsystems[Units[AUnit].Subsystem].Foundation;
  end;

begin
  Result := InFoundation(AEdge.Source) or InFoundation(AEdge.Target);
end;

function TAtlasArchitectureModel.HasFoundation: Boolean;
var
  mSubsystem: TAtlasArchSubsystem;
begin
  Result := False;
  for mSubsystem in Subsystems do
  begin
    if mSubsystem.Foundation then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasArchitectureModel.AlignedText: string;
begin
  Result := '';
  if AlignedSource <> '' then
  begin
    Result := Copy(StringReplace(AlignedAt, 'T', ' ', []), 1, 16);
  end;
end;

function TAtlasArchitectureModel.HasAssignment: Boolean;
var
  mUnit: TAtlasArchUnit;
begin
  Result := False;
  for mUnit in Units do
  begin
    if Length(mUnit.Assignment) > 0 then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasArchitectureModel.OwnRow(AUnit: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if (AUnit < 0) or (AUnit >= Length(Units)) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Units[AUnit].Assignment) do
  begin
    if Units[AUnit].Assignment[mIndex].Subsystem = Units[AUnit].Subsystem then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasArchitectureModel.RivalRow(AUnit: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if (AUnit < 0) or (AUnit >= Length(Units)) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Units[AUnit].Assignment) do
  begin
    if (Units[AUnit].Assignment[mIndex].Subsystem <> Units[AUnit].Subsystem) and
      Units[AUnit].Assignment[mIndex].Counts then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasArchitectureModel.LegendOrder: TArray<Integer>;
var
  mIndex, mOther: Integer;
  mDone: TArray<Boolean>;
begin
  Result := nil;
  SetLength(mDone, Length(Subsystems));
  for mIndex := 0 to High(Subsystems) do
  begin
    if mDone[mIndex] then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
    mDone[mIndex] := True;
    if Subsystems[mIndex].Parent = '' then
    begin
      Continue;
    end;
    for mOther := mIndex + 1 to High(Subsystems) do
    begin
      if not mDone[mOther] and SameText(Subsystems[mOther].Parent, Subsystems[mIndex].Parent) then
      begin
        Result := Result + [mOther];
        mDone[mOther] := True;
      end;
    end;
  end;
end;

function TAtlasArchComparison.ResolutionDiffers: Boolean;
begin
  Result := Present and not TAtlasArchResolution.Same(BaselineResolution, Resolution);
end;

{ TAtlasArchResolution }

class function TAtlasArchResolution.Clamp(AValue: Double): Double;
begin
  if IsNan(AValue) or (AValue <= 0) then
  begin
    Exit(1);
  end;
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
    begin
      Exit;
    end;
    mValue := TJSONObject.ParseJSONValue(TAtlasJsonText.ValueAt(mRoot, ResolutionPath));
    try
      if mValue is TJSONNumber then
      begin
        AResolution := TAtlasArchResolution.Clamp(TJSONNumber(mValue).AsDouble);
      end;
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

{ TAtlasArchitecturePalette }

class function TAtlasArchitecturePalette.Color(ASubsystem: Integer; ADark: Boolean): Cardinal;
var
  Rgb: Cardinal;
  Slot: Integer;
begin
  Slot := Abs(ASubsystem) mod Count;
  if ADark then
  begin
    Rgb := DarkColors[Slot];
  end
  else
  begin
    Rgb := LightColors[Slot];
  end;
  // #RRGGBB → $00BBGGRR.
  Result := ((Rgb and $FF) shl 16) or (Rgb and $FF00) or ((Rgb shr 16) and $FF);
end;

class function TAtlasArchitecturePalette.Color(ASlot, AShade: Integer; ADark: Boolean): Cardinal;
var
  mBase: Cardinal;
  mMix: Double;
  mShift, mChannel: Integer;
begin
  mBase := Color(ASlot, ADark);
  if AShade = 0 then
  begin
    Exit(mBase);
  end;
  mMix := Min(MaxShadeMix, ShadeStep * Abs(AShade));
  Result := 0;
  mShift := 0;
  while mShift <= 16 do
  begin
    mChannel := (mBase shr mShift) and $FF;
    if AShade > 0 then
    begin
      mChannel := Round(mChannel + (255 - mChannel) * mMix);
    end
    else
    begin
      mChannel := Round(mChannel * (1 - mMix));
    end;
    Result := Result or (Cardinal(EnsureRange(mChannel, 0, 255)) shl mShift);
    Inc(mShift, 8);
  end;
end;

class function TAtlasArchitecturePalette.FoundationColor(ADark: Boolean): Cardinal;
begin
  // #5D6576 bzw. #9AA2B2 als $00BBGGRR.
  if ADark then
  begin
    Result := $B2A29A;
  end
  else
  begin
    Result := $76655D;
  end;
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

end.
