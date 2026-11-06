unit Atlas.Common.Architecture.Overview;

// Architekturübersicht aus dem Uses-Graphen (#1118): dieselben Zahlen für
// das IDE-Fenster, den Bericht (Markdown, HTML) und get_architecture.
//
// - Zentrale Units: direkt abhängig (Fan-in), gesamt abhängig (neu zu
//   übersetzen bei Änderung im interface, wie #554/#593), verwendet
//   (Fan-out); Rolle Fundament (viele Abhängige, wenige Abhängigkeiten) oder
//   Drehscheibe (viele in beide Richtungen).
// - Teilsysteme: Louvain auf dem ungerichteten Graphen (interface-Kanten
//   Gewicht 2, implementation 1). Name ohne KI aus dem Namensraum-Abschnitt,
//   der die Units des Teilsystems am besten von den übrigen unterscheidet
//   (Häufigkeit innen mal Seltenheit im ganzen Projekt), sonst der Name der
//   zentralsten Unit. Zusammenhalt = Anteil der Kanten, die im Teilsystem
//   bleiben. Ausreißer: Unit, deren Namensraum zu einem anderen Teilsystem
//   passt, oder die mehr Kanten in ein anderes Teilsystem hat als ins eigene;
//   mit Vorschlag.
// - Zuordnung (#1368): je Unit ihre Kanten je Teilsystem (interface,
//   implementation, gewichtete Summe), absteigend nach Summe. Knapp, wenn das
//   stärkste andere Teilsystem mindestens 75 % der Summe des eigenen hat;
//   Kanten zum Fundament zählen nicht. Die Ausreißer nach Kanten lesen
//   dieselbe Liste.
// - Zyklen aus dem Uses-Graphen (reine interface-Zyklen zuerst), je Kante mit
//   Fundstelle.
// - Querverbindungen: Kanten zwischen zwei Teilsystemen, die selten sind
//   (höchstens zwei Kanten zwischen dem Paar) oder gegen die überwiegende
//   Richtung laufen; mit Fundstelle.
// - Gruppierung einstellbar (architecture.grouping, TArchitectureGrouping):
//   Auflösung γ des Louvain-Verfahrens (#1366), 1 = klassisch.
// - Nachteilung (#1364): Ein Teilsystem mit mehr als MaxShare aller Units
//   (ab 10 Units) oder mit Zusammenhalt unter MinCohesion (ab 30 Units)
//   wird mit einem zweiten Louvain-Lauf nur auf seinen Units und Kanten
//   geteilt, höchstens zwei Stufen tief. Units ohne Kante im Teilgraphen
//   bleiben beim größten Teil. Die Teile heißen nach dem Abschnitt, der sie
//   innerhalb des ursprünglichen Teilsystems unterscheidet, tragen dessen
//   Namen in Parent und eine gemeinsame Farbfamilie (ColorSlot, Shade).
// - Fundamente (#1365): Units mit Rolle Fundament, deren direkt Abhängige
//   nach dem ersten Lauf in mindestens drei Teilsystemen liegen oder höchstens
//   zu 60 % im eigenen, ziehen fremde Teilsysteme zusammen. Mit Foundations
//   Attach bzw. Separate rechnet ein zweiter Lauf ohne sie und ihre Kanten;
//   danach kommen sie in das Teilsystem mit den meisten Abhängigen (Attach)
//   oder alle in das Teilsystem „Fundament“ (Separate, zuerst sortiert,
//   ohne Zusammenhalt, keine Querverbindungen und Ausreißer dorthin). Units,
//   deren einzige Kanten zu Fundamenten führen, folgen ihrem Fundament.
// - Alles deterministisch: Units nach Name, Teilsysteme nach Größe und Name.
//   Farben und Namen kann danach Atlas.Common.Architecture.Alignment an einen
//   vorigen Stand angleichen (#1367); die Reihenfolge bleibt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator;

type
  TOverviewUnitRole = (None, Foundation, Hub);

  /// <summary>Behandlung übergreifender Fundament-Units beim Gruppieren (#1365).</summary>
  TArchitectureFoundations = (Group, Attach, Separate);

  /// <summary>Einstellungen der Gruppierung in Teilsysteme (architecture.grouping).</summary>
  TArchitectureGrouping = record
  public const
    MinResolution = 0.2;
    MaxResolution = 5.0;
    DefaultMaxShare = 0.25;
    MaxMaxShare = 0.9;
    DefaultMinCohesion = 0.3;
    /// <summary>Nachteilen nach Größe erst ab so vielen Units (#1364).</summary>
    SplitMinUnits = 10;
    /// <summary>Nachteilen nach Zusammenhalt erst ab so vielen Units.</summary>
    LooseMinUnits = 30;
    /// <summary>Höchstens so viele Stufen Nachteilung.</summary>
    SplitDepth = 2;
    /// <summary>Übergreifendes Fundament (#1365): Abhängige in mindestens so vielen Teilsystemen …</summary>
    FoundationMinSpread = 3;
    /// <summary>… oder höchstens dieser Anteil der Abhängigen (in Prozent, ganzzahlig verglichen) im eigenen
    /// Teilsystem.</summary>
    FoundationMaxOwnPercent = 60;
  public
    /// <summary>Auflösung γ des Louvain-Verfahrens (#1366): größer = mehr und kleinere Teilsysteme.</summary>
    Resolution: Double;
    /// <summary>Ab diesem Anteil aller Units wird ein Teilsystem nachgeteilt (#1364); 0 = nie nach Größe.</summary>
    MaxShare: Double;
    /// <summary>Teilsysteme ab LooseMinUnits mit geringerem Zusammenhalt werden nachgeteilt; 0 = nie.</summary>
    MinCohesion: Double;
    /// <summary>Übergreifende Fundamente mitgruppieren, anhängen oder getrennt zeigen (#1365).</summary>
    Foundations: TArchitectureFoundations;
    /// <summary>Vorgaben: Auflösung 1 (Verhalten wie vor #1366), MaxShare 0,25, MinCohesion 0,3, Fundamente
    /// getrennt.</summary>
    class function Default: TArchitectureGrouping; static;
    /// <summary>Werte in ihren Grenzen (Resolution 0,2–5,0, MaxShare 0–0,9, MinCohesion 0–1).</summary>
    function Clamped: TArchitectureGrouping;
    /// <summary>Ein Teilsystem mit ASize von ATotal Units und Zusammenhalt ACohesion wird nachgeteilt (#1364).
    /// </summary>
    function NeedsSplit(ASize, ATotal: Integer; ACohesion: Double): Boolean;
    /// <summary>Text, der die Einstellungen eindeutig beschreibt (Schlüssel des Zwischenspeichers).</summary>
    function Key: string;
    /// <summary>Auflösung weicht von 1 ab (Kopf des Berichts, Hinweis im Vergleich).</summary>
    function ResolutionChanged: Boolean;
    /// <summary>"1,5" (deutsch, höchstens zwei Nachkommastellen).</summary>
    class function ResolutionText(AValue: Double): string; static;
    /// <summary>AValue liegt in 0,2–5,0 (Anfrage und get_architecture).</summary>
    class function ValidResolution(AValue: Double): Boolean; static;
    /// <summary>Zwei Auflösungen gelten als gleich (auf zwei Nachkommastellen).</summary>
    class function SameResolution(ALeft, ARight: Double): Boolean; static;
    /// <summary>"group", "attach" oder "separate" (architecture.grouping.foundations).</summary>
    class function FoundationsText(AValue: TArchitectureFoundations): string; static;
    class function TryFoundations(const AText: string; out AValue: TArchitectureFoundations): Boolean; static;
  end;

  TOverviewUnit = record
    Name: string;
    FileName: string;
    Library_: Boolean;
    /// <summary>Knotennummer im Uses-Graphen.</summary>
    Node: Integer;
    Subsystem: Integer;
    /// <summary>Units, die diese direkt verwenden.</summary>
    Direct: Integer;
    /// <summary>Units, die neu übersetzt werden, wenn sich ihr interface ändert.</summary>
    Total: Integer;
    /// <summary>Units, die diese direkt verwendet.</summary>
    Uses_: Integer;
    Role: TOverviewUnitRole;
  end;

  /// <summary>Kante zwischen zwei Units der Übersicht (Nummern in TArchitectureOverview.Units).</summary>
  TOverviewEdge = record
    Source: Integer;
    Target: Integer;
    Section: TUsesSection;
    /// <summary>Fundstelle des uses-Eintrags; nur bei Zyklen und Querverbindungen gesucht.</summary>
    Located: Boolean;
    Location: TUsesLocation;
  end;

  TOverviewSubsystem = record
    Name: string;
    /// <summary>Units nach gesamt abhängig absteigend, dann nach Name.</summary>
    Units: TArray<Integer>;
    /// <summary>Unit mit den meisten Abhängigen.</summary>
    Central: Integer;
    InnerEdges: Integer;
    OuterEdges: Integer;
    /// <summary>Anteil der Kanten der Units, die im Teilsystem bleiben (0..1).</summary>
    Cohesion: Double;
    /// <summary>Sammelgruppe der Units ohne uses-Beziehung im Umfang (Name TArchitectureAnalyzer.IsolatedName).</summary>
    Isolated: Boolean;
    /// <summary>Name des ursprünglichen Teilsystems, wenn dieses nachgeteilt wurde (#1364); '' sonst.</summary>
    Parent: string;
    /// <summary>Farbe der Karte (Nummer in der Palette); die Teile eines Teilsystems teilen sie.</summary>
    ColorSlot: Integer;
    /// <summary>Farbton innerhalb der Farbfamilie: 0 = Grundfarbe, positiv heller, negativ dunkler.</summary>
    Shade: Integer;
    /// <summary>Teilsystem „Fundament“ der übergreifenden Fundament-Units (#1365, Foundations = Separate); ohne
    /// Zusammenhalt (Cohesion 0), ColorSlot -1 (neutrale Farbe).</summary>
    Foundation: Boolean;
  end;

  TOverviewOutlierReason = (Namespace, Edges);

  TOverviewOutlier = record
    Unit_: Integer;
    /// <summary>Teilsystem, wohin die Unit nach ihren Kanten bzw. ihrem Namensraum gehört.</summary>
    Suggested: Integer;
    Reason: TOverviewOutlierReason;
    /// <summary>Kanten ins eigene bzw. ins vorgeschlagene Teilsystem.</summary>
    Inside: Integer;
    Toward: Integer;
  end;

  /// <summary>Kanten einer Unit zu einem Teilsystem (#1368), ein- und ausgehend zusammen wie bei der Gruppierung.
  /// </summary>
  TOverviewAssignmentRow = record
    Subsystem: Integer;
    Interfaces: Integer;
    Implementations: Integer;
    /// <summary>Gewichtete Summe (interface 2, implementation 1).</summary>
    Sum: Integer;
    /// <summary>False bei Kanten zum Teilsystem „Fundament“: Sie zählen bei der Zuordnung nicht (#1365).</summary>
    Counts: Boolean;
    /// <summary>Zahl der Kanten (ungewichtet).</summary>
    function Edges: Integer;
  end;

  /// <summary>Warum eine Unit in ihrem Teilsystem liegt (#1368).</summary>
  TOverviewAssignment = record
    /// <summary>Teilsysteme mit Kanten der Unit, nach Summe absteigend, bei Gleichstand nach Name; das eigene
    /// steht immer darin (auch ohne Kanten).</summary>
    Rows: TArray<TOverviewAssignmentRow>;
    /// <summary>Stelle des eigenen Teilsystems in Rows; -1 ohne Daten.</summary>
    Own: Integer;
    /// <summary>Stelle des stärksten anderen Teilsystems, das zählt; -1 ohne.</summary>
    Rival: Integer;
    /// <summary>Knapp zugeordnet: Rival erreicht mindestens 75 % der Summe des eigenen Teilsystems.</summary>
    Close: Boolean;
    /// <summary>Gewichtete Kanten, die Rival zum Wechsel fehlen (0, wenn es schon gleich viele oder mehr hat).
    /// </summary>
    Missing: Integer;
    function OwnSum: Integer;
    function RivalSum: Integer;
  end;

  TOverviewCycle = record
    Units: TArray<Integer>;
    Edges: TArray<TOverviewEdge>;
    /// <summary>Alle Units der Komponente.</summary>
    Component: TArray<Integer>;
    InterfaceOnly: Boolean;
  end;

  TOverviewCrossReason = (Rare, AgainstDirection);

  TOverviewCrossLink = record
    Edge: TOverviewEdge;
    FromSubsystem: Integer;
    ToSubsystem: Integer;
    Reason: TOverviewCrossReason;
    /// <summary>Kanten von FromSubsystem nach ToSubsystem bzw. zurück.</summary>
    Forward: Integer;
    Backward: Integer;
  end;

  /// <summary>Steckbrief einer Unit (MCP unit, Klick in der Karte).</summary>
  TOverviewProfile = record
    Unit_: Integer;
    DependsOn: TArray<Integer>;
    UsedBy: TArray<Integer>;
    Cycles: TArray<Integer>;
    CrossLinks: TArray<Integer>;
    /// <summary>Nummer in Outliers; -1, wenn die Unit kein Ausreißer ist.</summary>
    Outlier: Integer;
  end;

  TArchitectureOverview = record
    Title: string;
    /// <summary>Ordner, gegen den Pfade relativ angezeigt werden.</summary>
    Root: string;
    Scope: string;
    IncludeLibrary: Boolean;
    Excludes: TArray<string>;
    Generation: Int64;
    DurationMs: Int64;
    /// <summary>Zeitpunkt der Berechnung (für den Kopf des Berichts).</summary>
    Created: TDateTime;
    /// <summary>Verwendete Einstellungen der Gruppierung.</summary>
    Grouping: TArchitectureGrouping;
    Units: TArray<TOverviewUnit>;
    Edges: TArray<TOverviewEdge>;
    /// <summary>Die zentralsten Units (höchstens CentralCount), nach gesamt abhängig absteigend.</summary>
    Central: TArray<Integer>;
    Subsystems: TArray<TOverviewSubsystem>;
    Outliers: TArray<TOverviewOutlier>;
    Cycles: TArray<TOverviewCycle>;
    CrossLinks: TArray<TOverviewCrossLink>;
    /// <summary>Je Unit ihre Kanten je Teilsystem (#1368); daraus ergeben sich auch die Ausreißer.</summary>
    Assignments: TArray<TOverviewAssignment>;
    /// <summary>Zuordnung in Bericht, Fenster und get_architecture zeigen (architecture.explainAssignment).
    /// </summary>
    ExplainAssignment: Boolean;
    /// <summary>Angleichung an einen vorigen Stand (#1367): Herkunft ('' = keine, AlignedBaseline oder
    /// AlignedLast), Zeitpunkt des Stands und Zahl der Teilsysteme, die Name oder Farbe behielten.</summary>
    AlignedSource: string;
    AlignedAt: TDateTime;
    AlignedKept: Integer;
    /// <summary>Teilsysteme an einen vorigen Stand angeglichen (AlignedSource gesetzt).</summary>
    function IsAligned: Boolean;
    /// <summary>Unit mit diesem Namen (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Zuordnung der Unit; Own = -1, wenn die Übersicht keine hat (gespeicherter Stand).</summary>
    function Assignment(AUnit: Integer): TOverviewAssignment;
    /// <summary>ExplainAssignment und Zuordnungen für alle Units vorhanden.</summary>
    function ShowsAssignment: Boolean;
    /// <summary>Zahl der knapp zugeordneten Units.</summary>
    function CloseCount: Integer;
    function Profile(AUnit: Integer): TOverviewProfile;
    /// <summary>Pfad relativ zu Root mit /, sonst unverändert.</summary>
    function RelativePath(const AFileName: string): string;
    /// <summary>Zahl der uses-Kanten.</summary>
    function EdgeCount: Integer;
  end;

  /// <summary>Teilt die Gruppe AMembers in AParts (mindestens zwei); False = bleibt, wie sie ist.</summary>
  TArchitectureSplitFunc = reference to function(const AMembers: TArray<Integer>;
    out AParts: TArray<TArray<Integer>>): Boolean;

  TArchitectureAnalyzer = class
  public const
    InterfaceWeight = 2;
    ImplementationWeight = 1;
    /// <summary>Höchstens so viele Kanten zwischen zwei Teilsystemen gelten als selten.</summary>
    RareLimit = 2;
    IsolatedName = 'Ohne uses-Beziehung';
    FoundationName = 'Fundament';
    /// <summary>Knapp zugeordnet (#1368), wenn das stärkste andere Teilsystem mindestens so viel Prozent der Summe
    /// des eigenen erreicht.</summary>
    ClosePercent = 75;
    /// <summary>Herkunft der Angleichung (#1367): architecture.baseline bzw. der zuletzt berechnete Stand.</summary>
    AlignedBaseline = 'baseline';
    AlignedLast = 'last';
  public
    /// <summary>Regel, nach der Units ins Teilsystem „Fundament“ kommen (Bericht, Fenster, get_architecture).
    /// </summary>
    class function FoundationRule: string; static;
    /// <summary>Übersicht über alle aktiven Units von AGraph. ALocator darf nil sein (dann ohne Fundstellen).
    /// ACentralCount: Länge der Liste zentraler Units (5..100).</summary>
    class function Analyze(AGraph: TUsesGraph; ALocator: TUsesLocator; ACentralCount: Integer): TArchitectureOverview;
      overload; static;
    /// <summary>Wie oben mit den Einstellungen AGrouping (Werte außerhalb der Grenzen werden begrenzt).</summary>
    class function Analyze(AGraph: TUsesGraph; ALocator: TUsesLocator; ACentralCount: Integer;
      const AGrouping: TArchitectureGrouping): TArchitectureOverview; overload; static;
    /// <summary>Namensraum-Abschnitte eines Unit-Namens ohne den letzten (Atlas.Common.Index.Builder →
    /// Atlas, Common, Index).</summary>
    class function NamespaceParts(const AUnitName: string): TArray<string>; static;
    /// <summary>Text der Rolle: "Fundament", "Drehscheibe" oder ''.</summary>
    class function RoleCaption(ARole: TOverviewUnitRole): string; static;
    /// <summary>Nachteilung (#1364): teilt jede Gruppe außer ASkip mit ASplit, ein Teil höchstens ADepth Stufen
    /// tief. Das erste Teil nimmt den Platz der Gruppe ein, die übrigen kommen hinten dazu. AFamilies: je
    /// Ergebnis die Nummer der Ausgangsgruppe.</summary>
    class function SplitGroups(const AGroups: TArray<TArray<Integer>>; ASkip, ADepth: Integer;
      const ASplit: TArchitectureSplitFunc; out AFamilies: TArray<Integer>): TArray<TArray<Integer>>; static;
    /// <summary>Zuordnung aus den Zeilen ARows (#1368): sortiert sie, sucht das eigene Teilsystem AOwn und das
    /// stärkste andere, das zählt, und bestimmt Knapp und fehlende Kanten. ANames: Namen der Teilsysteme für den
    /// Gleichstand.</summary>
    class function AssignmentOf(const ARows: TArray<TOverviewAssignmentRow>; AOwn: Integer;
      const ANames: TArray<string>): TOverviewAssignment; static;
    /// <summary>Je Unit von AOverview ihre Kanten je Teilsystem (ungerichtet, wie bei der Gruppierung; #1368).
    /// </summary>
    class function Assignments(const AOverview: TArchitectureOverview): TArray<TOverviewAssignment>; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Architecture.Louvain,
  Atlas.Common.Architecture.Overview.Foundations,
  Atlas.Common.Architecture.Overview.Naming,
  Atlas.Common.Architecture.Overview.Splitting,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TOverviewText = (Hub, UnitsWithTheFoundationRole, Foundation);

const
  cTexts: array[TOverviewText] of TAtlasText = (
    (De: 'Drehscheibe'; En: 'hub'),
    (De: 'Units mit Rolle Fundament, deren direkt Abhängige in mindestens drei Teilsystemen liegen oder höchstens zu ' +
      '60 % im eigenen, und Units, die nur sie verwenden';
     En: 'Units with the foundation role whose direct dependents lie in at least three subsystems or at most 60 % in ' +
      'their own, and units that only they use'),
    (De: 'Fundament'; En: 'foundation'));

class function TArchitectureAnalyzer.FoundationRule: string;
begin
  Result := cTexts[TOverviewText.UnitsWithTheFoundationRole].Text;
end;

function ContainsInt(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  Value: Integer;
begin
  for Value in AValues do
  begin
    if Value = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>AUnit (Nummer AIndex) ist zentraler als AOther (Nummer AOtherIndex): mehr Verbindungen insgesamt,
/// dann mehr direkte, dann die kleinere Nummer.</summary>
function MoreCentral(const AUnit, AOther: TOverviewUnit; AIndex, AOtherIndex: Integer): Boolean;
begin
  if AUnit.Total <> AOther.Total then
  begin
    Exit(AUnit.Total > AOther.Total);
  end;
  if AUnit.Direct <> AOther.Direct then
  begin
    Exit(AUnit.Direct > AOther.Direct);
  end;
  Result := AIndex < AOtherIndex;
end;

/// <summary>Die Nummern 0..ACount-1.</summary>
function AllIndices(ACount: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := mIndex;
  end;
end;

/// <summary>AMembers nach Zentralität sortieren: die zentralste Unit zuerst.</summary>
procedure SortByCentrality(const AUnits: TArray<TOverviewUnit>; var AMembers: TArray<Integer>);
var
  mUnits: TArray<TOverviewUnit>;
begin
  mUnits := AUnits;
  TArray.Sort<Integer>(AMembers, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      if ALeft = ARight then
      begin
        Result := 0;
      end
      else if MoreCentral(mUnits[ALeft], mUnits[ARight], ALeft, ARight) then
      begin
        Result := -1;
      end
      else
      begin
        Result := 1;
      end;
    end));
end;

/// <summary>Gewicht einer Kante für Louvain: interface schwerer als implementation.</summary>
function EdgeWeight(const AEdge: TOverviewEdge): Integer;
begin
  if AEdge.Section = TUsesSection.Interface_ then
  begin
    Result := TArchitectureAnalyzer.InterfaceWeight;
  end
  else
  begin
    Result := TArchitectureAnalyzer.ImplementationWeight;
  end;
end;

/// <summary>Die Kanten als Louvain-Kanten (A = Quelle, B = Ziel), in derselben Reihenfolge.</summary>
function LouvainEdges(const AEdges: TArray<TOverviewEdge>): TArray<TLouvainEdge>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEdges));
  for mIndex := 0 to High(AEdges) do
  begin
    Result[mIndex].A := AEdges[mIndex].Source;
    Result[mIndex].B := AEdges[mIndex].Target;
    Result[mIndex].Weight := EdgeWeight(AEdges[mIndex]);
  end;
end;

/// <summary>Zahl der Gruppen: größte Nummer + 1.</summary>
function CommunityCount(const ACommunities: TArray<Integer>): Integer;
var
  mMember: Integer;
begin
  Result := 0;
  for mMember in ACommunities do
  begin
    Result := Max(Result, mMember + 1);
  end;
end;

/// <summary>Units ohne Kante bilden bei Louvain je eine eigene Gruppe; sie kommen in eine Sammelgruppe. Danach
/// fortlaufend nummeriert. Ergebnis: Nummer der Sammelgruppe; -1 ohne.</summary>
function MergeIsolated(const AEdges: TArray<TOverviewEdge>; var ACommunities: TArray<Integer>): Integer;
var
  mDegree: TArray<Integer>;
  mEdge: TOverviewEdge;
  mIndex, mFirst: Integer;
begin
  SetLength(mDegree, Length(ACommunities));
  for mEdge in AEdges do
  begin
    Inc(mDegree[mEdge.Source]);
    Inc(mDegree[mEdge.Target]);
  end;
  mFirst := -1;
  for mIndex := 0 to High(ACommunities) do
  begin
    if mDegree[mIndex] <> 0 then
    begin
      Continue;
    end;
    if mFirst < 0 then
    begin
      mFirst := mIndex;
    end;
    ACommunities[mIndex] := ACommunities[mFirst];
  end;
  TFoundationSeparation.Renumber(ACommunities);
  Result := -1;
  if mFirst >= 0 then
  begin
    Result := ACommunities[mFirst];
  end;
end;

/// <summary>Gruppe der ersten Fundament-Unit (#1365); -1 ohne.</summary>
function FoundationGroup(const AInFoundation: TArray<Boolean>; const ACommunities: TArray<Integer>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(AInFoundation), High(ACommunities)) do
  begin
    if AInFoundation[mIndex] then
    begin
      Exit(ACommunities[mIndex]);
    end;
  end;
  Result := -1;
end;

/// <summary>Units je Gruppe, nach Nummer (= nach Name).</summary>
function GroupsOf(const ACommunities: TArray<Integer>): TArray<TArray<Integer>>;
var
  mSizes: TArray<Integer>;
  mIndex, mMember: Integer;
begin
  SetLength(mSizes, CommunityCount(ACommunities));
  for mMember in ACommunities do
  begin
    Inc(mSizes[mMember]);
  end;
  SetLength(Result, Length(mSizes));
  for mIndex := 0 to High(mSizes) do
  begin
    SetLength(Result[mIndex], mSizes[mIndex]);
    mSizes[mIndex] := 0;
  end;
  for mIndex := 0 to High(ACommunities) do
  begin
    Result[ACommunities[mIndex]][mSizes[ACommunities[mIndex]]] := mIndex;
    Inc(mSizes[ACommunities[mIndex]]);
  end;
end;

/// <summary>Zusammenhalt: Kanten innen / (innen + nach außen); 1 ohne Kanten.</summary>
function SubsystemCohesion(const ASubsystem: TOverviewSubsystem): Double;
begin
  Result := 1;
  if ASubsystem.InnerEdges + ASubsystem.OuterEdges > 0 then
  begin
    Result := ASubsystem.InnerEdges / (ASubsystem.InnerEdges + ASubsystem.OuterEdges);
  end;
end;

{ TArchitectureGrouping }

class function TArchitectureGrouping.Default: TArchitectureGrouping;
begin
  Result.Resolution := 1;
  Result.MaxShare := DefaultMaxShare;
  Result.MinCohesion := DefaultMinCohesion;
  Result.Foundations := TArchitectureFoundations.Separate;
end;

function TArchitectureGrouping.Clamped: TArchitectureGrouping;
begin
  Result := Self;
  if IsNan(Result.Resolution) or (Result.Resolution <= 0) then
  begin
    Result.Resolution := 1;
  end;
  Result.Resolution := EnsureRange(Result.Resolution, MinResolution, MaxResolution);
  if IsNan(Result.MaxShare) then
  begin
    Result.MaxShare := DefaultMaxShare;
  end;
  Result.MaxShare := EnsureRange(Result.MaxShare, 0, MaxMaxShare);
  if IsNan(Result.MinCohesion) then
  begin
    Result.MinCohesion := DefaultMinCohesion;
  end;
  Result.MinCohesion := EnsureRange(Result.MinCohesion, 0, 1);
end;

function TArchitectureGrouping.NeedsSplit(ASize, ATotal: Integer; ACohesion: Double): Boolean;
begin
  Result := ((MaxShare > 0) and (ASize >= SplitMinUnits) and (ASize > MaxShare * ATotal)) or
    ((MinCohesion > 0) and (ASize >= LooseMinUnits) and (ACohesion < MinCohesion));
end;

function TArchitectureGrouping.Key: string;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := Clamped;
  Result := 'r' + FormatFloat('0.####', mGrouping.Resolution, TFormatSettings.Invariant) + ';s' +
    FormatFloat('0.####', mGrouping.MaxShare, TFormatSettings.Invariant) + ';c' +
    FormatFloat('0.####', mGrouping.MinCohesion, TFormatSettings.Invariant) + ';f' + FoundationsText(Foundations);
end;

class function TArchitectureGrouping.FoundationsText(AValue: TArchitectureFoundations): string;
begin
  case AValue of
    TArchitectureFoundations.Attach:
      Result := 'attach';
    TArchitectureFoundations.Separate:
      Result := 'separate';
  else
    Result := 'group';
  end;
end;

class function TArchitectureGrouping.TryFoundations(const AText: string; out AValue: TArchitectureFoundations): Boolean;
begin
  Result := True;
  if AText = 'group' then
  begin
    AValue := TArchitectureFoundations.Group;
  end
  else if AText = 'attach' then
  begin
    AValue := TArchitectureFoundations.Attach;
  end
  else if AText = 'separate' then
  begin
    AValue := TArchitectureFoundations.Separate;
  end
  else
  begin
    AValue := TArchitectureFoundations.Group;
    Result := False;
  end;
end;

function TArchitectureGrouping.ResolutionChanged: Boolean;
begin
  Result := not SameResolution(Clamped.Resolution, 1);
end;

class function TArchitectureGrouping.ResolutionText(AValue: Double): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  mSettings.DecimalSeparator := ',';
  Result := FormatFloat('0.0#', AValue, mSettings);
end;

class function TArchitectureGrouping.ValidResolution(AValue: Double): Boolean;
begin
  Result := not IsNan(AValue) and (AValue >= MinResolution - 1E-9) and (AValue <= MaxResolution + 1E-9);
end;

class function TArchitectureGrouping.SameResolution(ALeft, ARight: Double): Boolean;
begin
  Result := Abs(ALeft - ARight) < 0.005;
end;

{ TArchitectureOverview }

function TArchitectureOverview.IndexOf(const AName: string): Integer;
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

function TArchitectureOverview.EdgeCount: Integer;
begin
  Result := Length(Edges);
end;

function TArchitectureOverview.RelativePath(const AFileName: string): string;
var
  RootPath, FileName: string;
begin
  FileName := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  RootPath := StringReplace(Root, '\', '/', [rfReplaceAll]);
  if (RootPath <> '') and (RootPath[Length(RootPath)] <> '/') then
  begin
    RootPath := RootPath + '/';
  end;
  if (RootPath <> '') and StartsText(RootPath, FileName) then
  begin
    Result := Copy(FileName, Length(RootPath) + 1, MaxInt);
  end
  else
  begin
    Result := FileName;
  end;
end;

/// <summary>Nummern der Zyklen, zu deren Komponente AUnit gehört.</summary>
function CyclesWith(const ACycles: TArray<TOverviewCycle>; AUnit: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ACycles) do
  begin
    if ContainsInt(AUnit, ACycles[mIndex].Component) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Nummern der Querverbindungen, die bei AUnit beginnen oder enden.</summary>
function CrossLinksWith(const ALinks: TArray<TOverviewCrossLink>; AUnit: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ALinks) do
  begin
    if (ALinks[mIndex].Edge.Source = AUnit) or (ALinks[mIndex].Edge.Target = AUnit) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Nummer des (letzten) Ausreißers zu AUnit; -1 ohne.</summary>
function OutlierOf(const AOutliers: TArray<TOverviewOutlier>; AUnit: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AOutliers) do
  begin
    if AOutliers[mIndex].Unit_ = AUnit then
    begin
      Result := mIndex;
    end;
  end;
end;

function TArchitectureOverview.Profile(AUnit: Integer): TOverviewProfile;
var
  mEdge: TOverviewEdge;
begin
  Result := Default(TOverviewProfile);
  Result.Unit_ := AUnit;
  for mEdge in Edges do
  begin
    if (mEdge.Source = AUnit) and not ContainsInt(mEdge.Target, Result.DependsOn) then
    begin
      Result.DependsOn := Result.DependsOn + [mEdge.Target];
    end;
    if (mEdge.Target = AUnit) and not ContainsInt(mEdge.Source, Result.UsedBy) then
    begin
      Result.UsedBy := Result.UsedBy + [mEdge.Source];
    end;
  end;
  Result.Cycles := CyclesWith(Cycles, AUnit);
  Result.CrossLinks := CrossLinksWith(CrossLinks, AUnit);
  Result.Outlier := OutlierOf(Outliers, AUnit);
end;

function TArchitectureOverview.Assignment(AUnit: Integer): TOverviewAssignment;
begin
  if (AUnit >= 0) and (AUnit < Length(Assignments)) then
  begin
    Exit(Assignments[AUnit]);
  end;
  Result := Default(TOverviewAssignment);
  Result.Own := -1;
  Result.Rival := -1;
end;

function TArchitectureOverview.IsAligned: Boolean;
begin
  Result := AlignedSource <> '';
end;

function TArchitectureOverview.ShowsAssignment: Boolean;
begin
  Result := ExplainAssignment and (Length(Units) > 0) and (Length(Assignments) = Length(Units));
end;

function TArchitectureOverview.CloseCount: Integer;
var
  mAssignment: TOverviewAssignment;
begin
  Result := 0;
  for mAssignment in Assignments do
  begin
    if mAssignment.Close then
    begin
      Inc(Result);
    end;
  end;
end;

{ TOverviewAssignmentRow }

function TOverviewAssignmentRow.Edges: Integer;
begin
  Result := Interfaces + Implementations;
end;

{ TOverviewAssignment }

function TOverviewAssignment.OwnSum: Integer;
begin
  Result := 0;
  if Own >= 0 then
  begin
    Result := Rows[Own].Sum;
  end;
end;

function TOverviewAssignment.RivalSum: Integer;
begin
  Result := 0;
  if Rival >= 0 then
  begin
    Result := Rows[Rival].Sum;
  end;
end;

{ TArchitectureAnalyzer }

class function TArchitectureAnalyzer.RoleCaption(ARole: TOverviewUnitRole): string;
begin
  case ARole of
    TOverviewUnitRole.Foundation:
      Result := cTexts[TOverviewText.Foundation].Text;
    TOverviewUnitRole.Hub:
      Result := cTexts[TOverviewText.Hub].Text;
  else
    Result := '';
  end;
end;

class function TArchitectureAnalyzer.NamespaceParts(const AUnitName: string): TArray<string>;
var
  Parts: TArray<string>;
begin
  Parts := AUnitName.Split(['.']);
  if Length(Parts) <= 1 then
  begin
    Exit(nil);
  end;
  Result := Copy(Parts, 0, Length(Parts) - 1);
end;

type
  TAnalysis = class
  private
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FResult: TArchitectureOverview;
    FGrouping: TArchitectureGrouping;
    /// <summary>Knotennummer → Unit-Nummer (-1 außerhalb).</summary>
    FUnitOf: TArray<Integer>;
    /// <summary>Je Teilsystem: Name stammt aus einem Namensraum-Abschnitt (nicht aus der zentralen Unit).</summary>
    FNamedByPart: TArray<Boolean>;
    /// <summary>Je Teilsystem der Namensraum-Abschnitt seines Namens (klein, ohne Zähler " 2"); '' ohne.</summary>
    FPartKey: TArray<string>;
    /// <summary>Je Teilsystem seine Familie: Nummer des ersten Teils des ursprünglichen Teilsystems (#1364).</summary>
    FFamily: TArray<Integer>;
    /// <summary>Je Unit: gehört ins Teilsystem „Fundament“ (#1365, nur Foundations = Separate).</summary>
    FInFoundation: TArray<Boolean>;
    /// <summary>Nummer des Teilsystems „Fundament“; -1 ohne.</summary>
    FFoundation: Integer;
    procedure CollectUnits;
    procedure CollectEdges;
    procedure Measure;
    procedure Group;
    procedure SeparateFoundations(const AEdges: TArray<TLouvainEdge>; var ACommunities: TArray<Integer>);
    function IsFoundation(ASubsystem: Integer): Boolean;
    procedure Split(const AEdges: TArray<TLouvainEdge>; var ACommunities: TArray<Integer>; AIsolated: Integer);
    procedure BuildSubsystems(const ACommunities: TArray<Integer>);
    procedure CountSubsystemEdges;
    procedure FinishSubsystems(AIsolated: Integer);
    procedure NameSubsystems;
    procedure NameSubsystem(AIndex: Integer; const AParts: TArray<TArray<string>>;
      const AFamilies: TArray<TArray<Integer>>; const AGlobal: TDictionary<string, Integer>);
    function NameOf(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
      const ACounts: TDictionary<string, Integer>; ATotal: Integer; out AKey: string): string;
    procedure AssignColors;
    procedure CollectAssignments;
    procedure FindOutliers;
    procedure CollectCycles;
    procedure CollectCrossLinks;
    function CrossLinkOf(AUnit: Integer; const AGraphEdge: TUsesEdge; const APairs: TArray<TArray<Integer>>;
      out ALink: TOverviewCrossLink): Boolean;
    function EdgeRival(const AAssignment: TOverviewAssignment; AOwn: Integer): Integer;
    function NamespaceRival(AUnit, AOwn: Integer): Integer;
    procedure SortSubsystems;
    function Locate(var AEdge: TOverviewEdge; const AGraphEdge: TUsesEdge): Boolean;
  public
    constructor Create(AGraph: TUsesGraph; ALocator: TUsesLocator; const AGrouping: TArchitectureGrouping);
    function Run(ACentralCount: Integer): TArchitectureOverview;
  end;

constructor TAnalysis.Create(AGraph: TUsesGraph; ALocator: TUsesLocator; const AGrouping: TArchitectureGrouping);
begin
  inherited Create;
  FGraph := AGraph;
  FLocator := ALocator;
  FGrouping := AGrouping.Clamped;
  FFoundation := -1;
end;

function TAnalysis.IsFoundation(ASubsystem: Integer): Boolean;
begin
  Result := (FFoundation >= 0) and (ASubsystem = FFoundation);
end;

procedure TAnalysis.CollectUnits;
var
  Sorted: TArray<Integer>;
  Index: Integer;
  Node: TUsesNode;
  Item: TOverviewUnit;
begin
  Sorted := FGraph.SortedNodes;
  SetLength(FUnitOf, FGraph.NodeCount);
  for Index := 0 to High(FUnitOf) do
  begin
    FUnitOf[Index] := -1;
  end;
  SetLength(FResult.Units, Length(Sorted));
  for Index := 0 to High(Sorted) do
  begin
    Node := FGraph.Node(Sorted[Index]);
    Item := Default(TOverviewUnit);
    Item.Name := Node.UnitName;
    Item.FileName := Node.FileName;
    Item.Library_ := Node.Library_;
    Item.Node := Sorted[Index];
    Item.Subsystem := -1;
    FResult.Units[Index] := Item;
    FUnitOf[Sorted[Index]] := Index;
  end;
end;

procedure TAnalysis.CollectEdges;
var
  Edges: TList<TOverviewEdge>;
  Index: Integer;
  GraphEdge: TUsesEdge;
  Edge: TOverviewEdge;
begin
  Edges := TList<TOverviewEdge>.Create;
  try
    for Index := 0 to High(FResult.Units) do
    begin
      for GraphEdge in FGraph.Node(FResult.Units[Index].Node).Outgoing do
      begin
        if FUnitOf[GraphEdge.Target] < 0 then
        begin
          Continue;
        end;
        Edge := Default(TOverviewEdge);
        Edge.Source := Index;
        Edge.Target := FUnitOf[GraphEdge.Target];
        Edge.Section := GraphEdge.Section;
        Edges.Add(Edge);
      end;
    end;
    FResult.Edges := Edges.ToArray;
  finally
    Edges.Free;
  end;
end;

procedure TAnalysis.Measure;
var
  Index, Count: Integer;
  Item: TOverviewUnit;
  Ratio: Double;
begin
  for Index := 0 to High(FResult.Units) do
  begin
    Item := FResult.Units[Index];
    Item.Direct := Length(FGraph.DirectDependents(Item.Node, AllUsesSections));
    Item.Uses_ := Length(FGraph.DirectDependencies(Item.Node, AllUsesSections));
    Item.Total := FGraph.RecompileCount(Item.Node);
    // Fundament: wird viel verwendet, verwendet selbst wenig. Drehscheibe: viel in beide Richtungen.
    Item.Role := TOverviewUnitRole.None;
    Count := Item.Direct + Item.Uses_;
    if (Item.Direct >= 3) and (Count > 0) then
    begin
      Ratio := Item.Uses_ / Count;
      if Ratio <= 0.25 then
      begin
        Item.Role := TOverviewUnitRole.Foundation;
      end
      else if Item.Uses_ >= 3 then
      begin
        Item.Role := TOverviewUnitRole.Hub;
      end;
    end;
    FResult.Units[Index] := Item;
  end;
  FResult.Central := AllIndices(Length(FResult.Units));
  SortByCentrality(FResult.Units, FResult.Central);
end;

procedure TAnalysis.Group;
var
  mEdges: TArray<TLouvainEdge>;
  mCommunities: TArray<Integer>;
  mIsolated: Integer;
begin
  mEdges := LouvainEdges(FResult.Edges);
  mCommunities := TLouvain.Communities(Length(FResult.Units), mEdges, FGrouping.Resolution);
  if FGrouping.Foundations <> TArchitectureFoundations.Group then
  begin
    SeparateFoundations(mEdges, mCommunities);
  end;
  mIsolated := MergeIsolated(FResult.Edges, mCommunities);
  FFoundation := FoundationGroup(FInFoundation, mCommunities);
  // Die Nachteilung lässt die Nummer ungeteilter Gruppen (also auch des Fundaments) stehen.
  Split(mEdges, mCommunities, mIsolated);
  BuildSubsystems(mCommunities);
  CountSubsystemEdges;
  FinishSubsystems(mIsolated);
end;

procedure TAnalysis.BuildSubsystems(const ACommunities: TArray<Integer>);
var
  mIndex: Integer;
begin
  SetLength(FResult.Subsystems, CommunityCount(ACommunities));
  for mIndex := 0 to High(FResult.Subsystems) do
  begin
    FResult.Subsystems[mIndex] := Default(TOverviewSubsystem);
    FResult.Subsystems[mIndex].Central := -1;
  end;
  for mIndex := 0 to High(FResult.Units) do
  begin
    FResult.Units[mIndex].Subsystem := ACommunities[mIndex];
    FResult.Subsystems[ACommunities[mIndex]].Units := FResult.Subsystems[ACommunities[mIndex]].Units + [mIndex];
  end;
end;

procedure TAnalysis.CountSubsystemEdges;
var
  mEdge: TOverviewEdge;
  mSource, mTarget: Integer;
begin
  for mEdge in FResult.Edges do
  begin
    mSource := FResult.Units[mEdge.Source].Subsystem;
    mTarget := FResult.Units[mEdge.Target].Subsystem;
    if mSource = mTarget then
    begin
      Inc(FResult.Subsystems[mSource].InnerEdges);
    end
    else if not IsFoundation(mSource) and not IsFoundation(mTarget) then
    begin
      // Kanten ins Fundament (#1365) gehen nicht in den Zusammenhalt ein.
      Inc(FResult.Subsystems[mSource].OuterEdges);
      Inc(FResult.Subsystems[mTarget].OuterEdges);
    end;
  end;
end;

procedure TAnalysis.FinishSubsystems(AIsolated: Integer);
var
  mIndex: Integer;
  mSubsystem: TOverviewSubsystem;
begin
  for mIndex := 0 to High(FResult.Subsystems) do
  begin
    mSubsystem := FResult.Subsystems[mIndex];
    mSubsystem.Isolated := mIndex = AIsolated;
    mSubsystem.Foundation := IsFoundation(mIndex);
    mSubsystem.Cohesion := 0;
    if not mSubsystem.Foundation then
    begin
      mSubsystem.Cohesion := SubsystemCohesion(mSubsystem);
    end;
    // Units nach gesamt abhängig absteigend; die erste ist die zentrale.
    SortByCentrality(FResult.Units, mSubsystem.Units);
    if mSubsystem.Units <> nil then
    begin
      mSubsystem.Central := mSubsystem.Units[0];
    end;
    FResult.Subsystems[mIndex] := mSubsystem;
  end;
end;

class function TArchitectureAnalyzer.SplitGroups(const AGroups: TArray<TArray<Integer>>; ASkip, ADepth: Integer;
  const ASplit: TArchitectureSplitFunc; out AFamilies: TArray<Integer>): TArray<TArray<Integer>>;
var
  Groups: TList<TArray<Integer>>;
  Levels, Families: TList<Integer>;
  Index, Part: Integer;
  Parts: TArray<TArray<Integer>>;
begin
  Groups := TList<TArray<Integer>>.Create;
  Levels := TList<Integer>.Create;
  Families := TList<Integer>.Create;
  try
    for Index := 0 to High(AGroups) do
    begin
      Groups.Add(AGroups[Index]);
      Levels.Add(0);
      Families.Add(Index);
    end;
    Index := 0;
    while Index < Groups.Count do
    begin
      if (Index <> ASkip) and (Levels[Index] < ADepth) and ASplit(Groups[Index], Parts) and (Length(Parts) > 1) then
      begin
        Groups[Index] := Parts[0];
        Levels[Index] := Levels[Index] + 1;
        for Part := 1 to High(Parts) do
        begin
          Groups.Add(Parts[Part]);
          Levels.Add(Levels[Index]);
          Families.Add(Families[Index]);
        end;
        // Das erste Teil gleich noch einmal prüfen (nächste Stufe); die übrigen kommen der Reihe nach.
        Continue;
      end;
      Inc(Index);
    end;
    Result := Groups.ToArray;
    AFamilies := Families.ToArray;
  finally
    Families.Free;
    Levels.Free;
    Groups.Free;
  end;
end;

procedure TAnalysis.SeparateFoundations(const AEdges: TArray<TLouvainEdge>; var ACommunities: TArray<Integer>);
var
  mSeparation: TFoundationSeparation;
  mSettings: TFoundationSettings;
  mRoles: TArray<Boolean>;
  mUnit: Integer;
begin
  SetLength(mRoles, Length(FResult.Units));
  for mUnit := 0 to High(mRoles) do
  begin
    mRoles[mUnit] := FResult.Units[mUnit].Role = TOverviewUnitRole.Foundation;
  end;
  mSettings.Resolution := FGrouping.Resolution;
  mSettings.Separate := FGrouping.Foundations = TArchitectureFoundations.Separate;
  mSettings.MinSpread := TArchitectureGrouping.FoundationMinSpread;
  mSettings.MaxOwnPercent := TArchitectureGrouping.FoundationMaxOwnPercent;
  mSeparation := TFoundationSeparation.Create(Length(FResult.Units), AEdges, mSettings);
  try
    mSeparation.Run(mRoles, ACommunities, FInFoundation);
  finally
    mSeparation.Free;
  end;
end;

/// <summary>Entscheidung der Nachteilung nach AGrouping bei ATotal Units im Projekt.</summary>
function SplitDecision(const AGrouping: TArchitectureGrouping; ATotal: Integer): TSplitDecision;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := AGrouping;
  Result :=
    function(ASize: Integer; ACohesion: Double): Boolean
    begin
      Result := mGrouping.NeedsSplit(ASize, ATotal, ACohesion);
    end;
end;

/// <summary>Teilfunktion für SplitGroups über ASplitter.</summary>
function SplitFuncOf(ASplitter: TSubsystemSplitter): TArchitectureSplitFunc;
begin
  Result :=
    function(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean
    begin
      Result := ASplitter.SplitGroup(AMembers, AParts);
    end;
end;

procedure TAnalysis.Split(const AEdges: TArray<TLouvainEdge>; var ACommunities: TArray<Integer>; AIsolated: Integer);
var
  mSettings: TSplitSettings;
  mSplitter: TSubsystemSplitter;
  mGroups: TArray<TArray<Integer>>;
  mIndex, mMember: Integer;
begin
  mSettings.Resolution := FGrouping.Resolution;
  // Zusammenhalt erst rechnen, wenn er zählt.
  mSettings.CohesionMinUnits := MaxInt;
  if FGrouping.MinCohesion > 0 then
  begin
    mSettings.CohesionMinUnits := TArchitectureGrouping.LooseMinUnits;
  end;
  mSettings.Decision := SplitDecision(FGrouping, Length(FResult.Units));
  // Units nach Nummer (= nach Name): dieselbe Startreihenfolge wie im ersten Lauf.
  mSplitter := TSubsystemSplitter.Create(Length(FResult.Units), AEdges, FInFoundation, mSettings);
  try
    mGroups := TArchitectureAnalyzer.SplitGroups(GroupsOf(ACommunities), AIsolated, TArchitectureGrouping.SplitDepth,
      SplitFuncOf(mSplitter), FFamily);
  finally
    mSplitter.Free;
  end;
  for mIndex := 0 to High(mGroups) do
  begin
    for mMember in mGroups[mIndex] do
    begin
      ACommunities[mMember] := mIndex;
    end;
  end;
end;

/// <summary>Name der zentralsten Unit aus AMembers; '' ohne Units.</summary>
function CentralName(const AUnits: TArray<TOverviewUnit>; const AMembers: TArray<Integer>): string;
var
  mMember, mCentral: Integer;
begin
  mCentral := -1;
  for mMember in AMembers do
  begin
    if (mCentral < 0) or MoreCentral(AUnits[mMember], AUnits[mCentral], mMember, mCentral) then
    begin
      mCentral := mMember;
    end;
  end;
  Result := '';
  if mCentral >= 0 then
  begin
    Result := AUnits[mCentral].Name;
  end;
end;

/// <summary>Namensraum-Abschnitte je Unit.</summary>
function UnitParts(const AUnits: TArray<TOverviewUnit>): TArray<TArray<string>>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AUnits));
  for mIndex := 0 to High(AUnits) do
  begin
    Result[mIndex] := TArchitectureAnalyzer.NamespaceParts(AUnits[mIndex].Name);
  end;
end;

/// <summary>Units je Familie (ursprüngliches Teilsystem vor der Nachteilung, #1364), nach Familiennummer.
/// </summary>
function FamilyUnits(const ASubsystems: TArray<TOverviewSubsystem>; const AFamily: TArray<Integer>)
  : TArray<TArray<Integer>>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASubsystems));
  for mIndex := 0 to High(ASubsystems) do
  begin
    Result[AFamily[mIndex]] := Result[AFamily[mIndex]] + ASubsystems[mIndex].Units;
  end;
end;

/// <summary>Teilsystem AIndex teilt seine Familie mit einem anderen (Teil eines nachgeteilten Teilsystems).
/// </summary>
function IsSplitPart(const AFamily: TArray<Integer>; AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  for mOther := 0 to High(AFamily) do
  begin
    if (mOther <> AIndex) and (AFamily[mOther] = AFamily[AIndex]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAnalysis.NameOf(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
  const ACounts: TDictionary<string, Integer>; ATotal: Integer; out AKey: string): string;
var
  mScore: Double;
begin
  AKey := TSubsystemNaming.BestPart(AParts, AMembers, ACounts, ATotal, mScore);
  if AKey <> '' then
  begin
    Result := TSubsystemNaming.PartCaption(AParts, AMembers, AKey);
  end
  else
  begin
    Result := CentralName(FResult.Units, AMembers);
  end;
end;

procedure TAnalysis.NameSubsystem(AIndex: Integer; const AParts: TArray<TArray<string>>;
  const AFamilies: TArray<TArray<Integer>>; const AGlobal: TDictionary<string, Integer>);
var
  mKey, mParentKey: string;
  mCounts: TDictionary<string, Integer>;
  mFamily: TArray<Integer>;
begin
  mKey := '';
  if FResult.Subsystems[AIndex].Isolated then
  begin
    FResult.Subsystems[AIndex].Name := TArchitectureAnalyzer.IsolatedName;
  end
  else if FResult.Subsystems[AIndex].Foundation then
  begin
    FResult.Subsystems[AIndex].Name := TArchitectureAnalyzer.FoundationName;
  end
  else if IsSplitPart(FFamily, AIndex) then
  begin
    // Teil eines nachgeteilten Teilsystems: Abschnitt, der es innerhalb des ursprünglichen unterscheidet.
    mFamily := AFamilies[FFamily[AIndex]];
    mCounts := TSubsystemNaming.PartCounts(AParts, mFamily);
    try
      FResult.Subsystems[AIndex].Name := NameOf(AParts, FResult.Subsystems[AIndex].Units, mCounts, Length(mFamily),
        mKey);
    finally
      mCounts.Free;
    end;
    FResult.Subsystems[AIndex].Parent := NameOf(AParts, mFamily, AGlobal, Length(FResult.Units), mParentKey);
  end
  else
  begin
    FResult.Subsystems[AIndex].Name := NameOf(AParts, FResult.Subsystems[AIndex].Units, AGlobal,
      Length(FResult.Units), mKey);
  end;
  FNamedByPart[AIndex] := mKey <> '';
  FPartKey[AIndex] := mKey;
end;

procedure TAnalysis.NameSubsystems;
var
  mParts: TArray<TArray<string>>;
  mFamilies: TArray<TArray<Integer>>;
  mGlobal: TDictionary<string, Integer>;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(FNamedByPart, Length(FResult.Subsystems));
  SetLength(FPartKey, Length(FResult.Subsystems));
  mParts := UnitParts(FResult.Units);
  mFamilies := FamilyUnits(FResult.Subsystems, FFamily);
  mGlobal := TSubsystemNaming.PartCounts(mParts, AllIndices(Length(FResult.Units)));
  try
    for mIndex := 0 to High(FResult.Subsystems) do
    begin
      NameSubsystem(mIndex, mParts, mFamilies, mGlobal);
    end;
  finally
    mGlobal.Free;
  end;
  // Doppelte Namen eindeutig machen: "Index", "Index 2" (in der Reihenfolge der Teilsysteme).
  SetLength(mNames, Length(FResult.Subsystems));
  for mIndex := 0 to High(FResult.Subsystems) do
  begin
    mNames[mIndex] := FResult.Subsystems[mIndex].Name;
  end;
  TSubsystemNaming.MakeUnique(mNames);
  for mIndex := 0 to High(FResult.Subsystems) do
  begin
    FResult.Subsystems[mIndex].Name := mNames[mIndex];
  end;
end;

class function TArchitectureAnalyzer.AssignmentOf(const ARows: TArray<TOverviewAssignmentRow>; AOwn: Integer;
  const ANames: TArray<string>): TOverviewAssignment;
var
  mIndex: Integer;
  mOwnSum, mRivalSum: Integer;
begin
  Result := Default(TOverviewAssignment);
  Result.Rows := Copy(ARows);
  // TArray.Sort ist nicht stabil: bei gleichem Namen weiter nach Nummer.
  TArray.Sort<TOverviewAssignmentRow>(Result.Rows, TComparer<TOverviewAssignmentRow>.Construct(
    function(const ALeft, ARight: TOverviewAssignmentRow): Integer
    begin
      Result := ARight.Sum - ALeft.Sum;
      if (Result = 0) and (ALeft.Subsystem < Length(ANames)) and (ARight.Subsystem < Length(ANames)) then
      begin
        Result := CompareText(ANames[ALeft.Subsystem], ANames[ARight.Subsystem]);
      end;
      if Result = 0 then
      begin
        Result := ALeft.Subsystem - ARight.Subsystem;
      end;
    end));
  Result.Own := -1;
  Result.Rival := -1;
  for mIndex := 0 to High(Result.Rows) do
  begin
    if Result.Rows[mIndex].Subsystem = AOwn then
    begin
      Result.Own := mIndex;
    end
    else if Result.Rows[mIndex].Counts and (Result.Rival < 0) then
    begin
      Result.Rival := mIndex;
    end;
  end;
  mOwnSum := Result.OwnSum;
  mRivalSum := Result.RivalSum;
  // Ganzzahlig verglichen: 6 von 8 sind genau 75 %.
  Result.Close := (Result.Own >= 0) and Result.Rows[Result.Own].Counts and (Result.Rival >= 0) and (mOwnSum > 0) and
    (mRivalSum * 100 >= mOwnSum * ClosePercent);
  if Result.Close then
  begin
    Result.Missing := Max(0, mOwnSum - mRivalSum + 1);
  end;
end;

/// <summary>Je Unit und Teilsystem der Gegenseite die Kanten im interface (AInterfaces) bzw. in der
/// implementation (AImplementations), beide Richtungen.</summary>
procedure CountEdgesBySubsystem(const AOverview: TArchitectureOverview;
  out AInterfaces, AImplementations: TArray<TArray<Integer>>);
var
  mEdge: TOverviewEdge;
  mIndex, mSource, mTarget: Integer;
begin
  SetLength(AInterfaces, Length(AOverview.Units));
  SetLength(AImplementations, Length(AOverview.Units));
  for mIndex := 0 to High(AOverview.Units) do
  begin
    SetLength(AInterfaces[mIndex], Length(AOverview.Subsystems));
    SetLength(AImplementations[mIndex], Length(AOverview.Subsystems));
  end;
  for mEdge in AOverview.Edges do
  begin
    mSource := AOverview.Units[mEdge.Source].Subsystem;
    mTarget := AOverview.Units[mEdge.Target].Subsystem;
    if mEdge.Section = TUsesSection.Interface_ then
    begin
      Inc(AInterfaces[mEdge.Source][mTarget]);
      Inc(AInterfaces[mEdge.Target][mSource]);
    end
    else
    begin
      Inc(AImplementations[mEdge.Source][mTarget]);
      Inc(AImplementations[mEdge.Target][mSource]);
    end;
  end;
end;

/// <summary>Zeilen der Zuordnung einer Unit im Teilsystem AOwn: das eigene und jedes mit Kanten.</summary>
function AssignmentRows(const AOverview: TArchitectureOverview; AOwn: Integer;
  const AInterfaces, AImplementations: TArray<Integer>): TArray<TOverviewAssignmentRow>;
var
  mRow: TOverviewAssignmentRow;
  mSubsystem: Integer;
begin
  Result := nil;
  for mSubsystem := 0 to High(AOverview.Subsystems) do
  begin
    if (mSubsystem <> AOwn) and (AInterfaces[mSubsystem] = 0) and (AImplementations[mSubsystem] = 0) then
    begin
      Continue;
    end;
    mRow := Default(TOverviewAssignmentRow);
    mRow.Subsystem := mSubsystem;
    mRow.Interfaces := AInterfaces[mSubsystem];
    mRow.Implementations := AImplementations[mSubsystem];
    mRow.Sum := mRow.Interfaces * TArchitectureAnalyzer.InterfaceWeight +
      mRow.Implementations * TArchitectureAnalyzer.ImplementationWeight;
    // Kanten zum Fundament zählen bei der Zuordnung nicht (#1365); im Fundament selbst zählen sie.
    mRow.Counts := not AOverview.Subsystems[mSubsystem].Foundation or AOverview.Subsystems[AOwn].Foundation;
    Result := Result + [mRow];
  end;
end;

class function TArchitectureAnalyzer.Assignments(const AOverview: TArchitectureOverview):
  TArray<TOverviewAssignment>;
var
  mInterfaces, mImplementations: TArray<TArray<Integer>>;
  mNames: TArray<string>;
  mIndex, mOwn: Integer;
begin
  CountEdgesBySubsystem(AOverview, mInterfaces, mImplementations);
  SetLength(mNames, Length(AOverview.Subsystems));
  for mIndex := 0 to High(AOverview.Subsystems) do
  begin
    mNames[mIndex] := AOverview.Subsystems[mIndex].Name;
  end;
  SetLength(Result, Length(AOverview.Units));
  for mIndex := 0 to High(AOverview.Units) do
  begin
    mOwn := AOverview.Units[mIndex].Subsystem;
    if (mOwn < 0) or (mOwn > High(AOverview.Subsystems)) then
    begin
      Result[mIndex] := AssignmentOf(nil, -1, mNames);
      Continue;
    end;
    Result[mIndex] := AssignmentOf(AssignmentRows(AOverview, mOwn, mInterfaces[mIndex], mImplementations[mIndex]),
      mOwn, mNames);
    // Ins Fundament kommt eine Unit nach der Regel FoundationRule, nicht nach ihren Kanten: nie knapp.
    if AOverview.Subsystems[mOwn].Foundation then
    begin
      Result[mIndex].Close := False;
      Result[mIndex].Missing := 0;
    end;
  end;
end;

procedure TAnalysis.CollectAssignments;
begin
  // Einmal gerechnet für Ausreißer und Erklärung (#1368).
  FResult.Assignments := TArchitectureAnalyzer.Assignments(FResult);
end;

/// <summary>Kanten (ungerichtet, ungewichtet) der Zuordnung zum Teilsystem ASubsystem; 0 ohne Zeile.</summary>
function EdgesTo(const AAssignment: TOverviewAssignment; ASubsystem: Integer): Integer;
var
  mRow: TOverviewAssignmentRow;
begin
  Result := 0;
  for mRow in AAssignment.Rows do
  begin
    if mRow.Subsystem = ASubsystem then
    begin
      Exit(mRow.Edges);
    end;
  end;
end;

/// <summary>ARow schlägt das bisher beste Teilsystem ABest (ABestEdges Kanten): mehr Kanten, bei Gleichstand
/// gegen ein fremdes Teilsystem die kleinere Nummer.</summary>
function BeatsBest(const ARow: TOverviewAssignmentRow; ABest, ABestEdges, AOwn: Integer): Boolean;
begin
  if ARow.Edges <> ABestEdges then
  begin
    Exit(ARow.Edges > ABestEdges);
  end;
  Result := (ABest <> AOwn) and (ARow.Subsystem < ABest);
end;

/// <summary>Einer der Abschnitte AParts ist AKey (ohne Groß-/Kleinschreibung).</summary>
function HasPart(const AParts: TArray<string>; const AKey: string): Boolean;
var
  mPart: string;
begin
  for mPart in AParts do
  begin
    if SameText(mPart, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAnalysis.EdgeRival(const AAssignment: TOverviewAssignment; AOwn: Integer): Integer;
var
  mRow: TOverviewAssignmentRow;
  mBestEdges: Integer;
begin
  Result := AOwn;
  mBestEdges := EdgesTo(AAssignment, AOwn);
  for mRow in AAssignment.Rows do
  begin
    if (mRow.Subsystem <> AOwn) and not IsFoundation(mRow.Subsystem) and
      BeatsBest(mRow, Result, mBestEdges, AOwn) then
    begin
      Result := mRow.Subsystem;
      mBestEdges := mRow.Edges;
    end;
  end;
  if Result = AOwn then
  begin
    Result := -1;
  end;
end;

function TAnalysis.NamespaceRival(AUnit, AOwn: Integer): Integer;
var
  mParts: TArray<string>;
  mSubsystem: Integer;
begin
  mParts := TArchitectureAnalyzer.NamespaceParts(FResult.Units[AUnit].Name);
  if not FNamedByPart[AOwn] or HasPart(mParts, FPartKey[AOwn]) then
  begin
    Exit(-1);
  end;
  for mSubsystem := 0 to High(FResult.Subsystems) do
  begin
    if (mSubsystem = AOwn) or not FNamedByPart[mSubsystem] or (Length(FResult.Subsystems[mSubsystem].Units) < 2) or
      IsFoundation(mSubsystem) then
    begin
      Continue;
    end;
    if HasPart(mParts, FPartKey[mSubsystem]) then
    begin
      Exit(mSubsystem);
    end;
  end;
  Result := -1;
end;

procedure TAnalysis.FindOutliers;
var
  mAssignment: TOverviewAssignment;
  mIndex, mOwn: Integer;
  mOutlier: TOverviewOutlier;
begin
  for mIndex := 0 to High(FResult.Units) do
  begin
    mOwn := FResult.Units[mIndex].Subsystem;
    // Ausreißer nur unter den übrigen Teilsystemen (#1365): weder aus dem Fundament noch dorthin.
    if IsFoundation(mOwn) then
    begin
      Continue;
    end;
    mAssignment := FResult.Assignments[mIndex];
    mOutlier := Default(TOverviewOutlier);
    mOutlier.Unit_ := mIndex;
    // Nach Kanten (ungewichtet): ein anderes Teilsystem mit mehr Kanten als das eigene, bei Gleichstand das mit
    // der kleineren Nummer.
    mOutlier.Suggested := EdgeRival(mAssignment, mOwn);
    mOutlier.Reason := TOverviewOutlierReason.Edges;
    if mOutlier.Suggested < 0 then
    begin
      // Nach Namensraum: Die Unit trägt nicht den Namen ihres Teilsystems, aber den eines anderen. Nur wenn
      // beide Namen aus Namensraum-Abschnitten stammen.
      mOutlier.Suggested := NamespaceRival(mIndex, mOwn);
      mOutlier.Reason := TOverviewOutlierReason.Namespace;
    end;
    if mOutlier.Suggested < 0 then
    begin
      Continue;
    end;
    mOutlier.Inside := EdgesTo(mAssignment, mOwn);
    mOutlier.Toward := EdgesTo(mAssignment, mOutlier.Suggested);
    FResult.Outliers := FResult.Outliers + [mOutlier];
  end;
end;

function TAnalysis.Locate(var AEdge: TOverviewEdge; const AGraphEdge: TUsesEdge): Boolean;
begin
  Result := False;
  if FLocator = nil then
  begin
    Exit;
  end;
  Result := FLocator.Locate(FGraph, AGraphEdge, AEdge.Location);
  AEdge.Located := Result;
end;

procedure TAnalysis.CollectCycles;
var
  Cycle: TUsesCycle;
  Item: TOverviewCycle;
  GraphEdge: TUsesEdge;
  Edge: TOverviewEdge;
  Node: Integer;
begin
  for Cycle in FGraph.AllCycles do
  begin
    Item := Default(TOverviewCycle);
    Item.InterfaceOnly := Cycle.InterfaceOnly;
    for Node in Cycle.Units do
    begin
      Item.Units := Item.Units + [FUnitOf[Node]];
    end;
    for Node in Cycle.Component do
    begin
      Item.Component := Item.Component + [FUnitOf[Node]];
    end;
    for GraphEdge in Cycle.Edges do
    begin
      Edge := Default(TOverviewEdge);
      Edge.Source := FUnitOf[GraphEdge.Source];
      Edge.Target := FUnitOf[GraphEdge.Target];
      Edge.Section := GraphEdge.Section;
      Locate(Edge, GraphEdge);
      Item.Edges := Item.Edges + [Edge];
    end;
    FResult.Cycles := FResult.Cycles + [Item];
  end;
end;

/// <summary>Je Paar von Teilsystemen (Quelle, Ziel) die Zahl der Kanten zwischen ihnen.</summary>
function SubsystemPairs(const AOverview: TArchitectureOverview): TArray<TArray<Integer>>;
var
  mIndex, mFrom, mTo: Integer;
  mEdge: TOverviewEdge;
begin
  SetLength(Result, Length(AOverview.Subsystems));
  for mIndex := 0 to High(Result) do
  begin
    SetLength(Result[mIndex], Length(AOverview.Subsystems));
  end;
  for mEdge in AOverview.Edges do
  begin
    mFrom := AOverview.Units[mEdge.Source].Subsystem;
    mTo := AOverview.Units[mEdge.Target].Subsystem;
    if mFrom <> mTo then
    begin
      Inc(Result[mFrom][mTo]);
    end;
  end;
end;

/// <summary>Grund der Querverbindung mit AForward Kanten hin und ABackward zurück; False = keine.</summary>
function CrossReason(AForward, ABackward: Integer; out AReason: TOverviewCrossReason): Boolean;
begin
  Result := True;
  if AForward + ABackward <= TArchitectureAnalyzer.RareLimit then
  begin
    AReason := TOverviewCrossReason.Rare;
  end
  else if AForward < ABackward then
  begin
    AReason := TOverviewCrossReason.AgainstDirection;
  end
  else
  begin
    AReason := TOverviewCrossReason.Rare;
    Result := False;
  end;
end;

function TAnalysis.CrossLinkOf(AUnit: Integer; const AGraphEdge: TUsesEdge; const APairs: TArray<TArray<Integer>>;
  out ALink: TOverviewCrossLink): Boolean;
var
  mFrom, mTo: Integer;
  mEdge: TOverviewEdge;
begin
  ALink := Default(TOverviewCrossLink);
  mFrom := FResult.Units[AUnit].Subsystem;
  mTo := FResult.Units[FUnitOf[AGraphEdge.Target]].Subsystem;
  // Kanten ins Fundament (#1365) sind gewollt, keine Querverbindung.
  if (mFrom = mTo) or IsFoundation(mFrom) or IsFoundation(mTo) then
  begin
    Exit(False);
  end;
  ALink.FromSubsystem := mFrom;
  ALink.ToSubsystem := mTo;
  ALink.Forward := APairs[mFrom][mTo];
  ALink.Backward := APairs[mTo][mFrom];
  Result := CrossReason(ALink.Forward, ALink.Backward, ALink.Reason);
  if Result then
  begin
    mEdge := Default(TOverviewEdge);
    mEdge.Source := AUnit;
    mEdge.Target := FUnitOf[AGraphEdge.Target];
    mEdge.Section := AGraphEdge.Section;
    Locate(mEdge, AGraphEdge);
    ALink.Edge := mEdge;
  end;
end;

procedure TAnalysis.CollectCrossLinks;
var
  mPairs: TArray<TArray<Integer>>;
  mIndex: Integer;
  mGraphEdge: TUsesEdge;
  mLink: TOverviewCrossLink;
begin
  mPairs := SubsystemPairs(FResult);
  // In Quelltextreihenfolge je Unit (Units nach Name), damit die Liste stabil bleibt.
  for mIndex := 0 to High(FResult.Units) do
  begin
    for mGraphEdge in FGraph.Node(FResult.Units[mIndex].Node).Outgoing do
    begin
      if (FUnitOf[mGraphEdge.Target] >= 0) and CrossLinkOf(mIndex, mGraphEdge, mPairs, mLink) then
      begin
        FResult.CrossLinks := FResult.CrossLinks + [mLink];
      end;
    end;
  end;
end;

procedure TAnalysis.SortSubsystems;
var
  Order, Map, Family: TArray<Integer>;
  Sorted: TArray<TOverviewSubsystem>;
  Index: Integer;
begin
  // Das Fundament (#1365) zuerst (Mitte der Karte), dann die größten, bei Gleichstand nach dem Namen der zentralen
  // Unit (Namen entstehen erst danach); die Sammelgruppe ohne uses-Beziehung zuletzt.
  SetLength(Order, Length(FResult.Subsystems));
  for Index := 0 to High(Order) do
  begin
    Order[Index] := Index;
  end;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := Ord(FResult.Subsystems[ARight].Foundation) - Ord(FResult.Subsystems[ALeft].Foundation);
      if Result = 0 then
      begin
        Result := Ord(FResult.Subsystems[ALeft].Isolated) - Ord(FResult.Subsystems[ARight].Isolated);
      end;
      if Result = 0 then
      begin
        Result := Length(FResult.Subsystems[ARight].Units) - Length(FResult.Subsystems[ALeft].Units);
      end;
      if Result = 0 then
      begin
        Result := CompareText(FResult.Units[FResult.Subsystems[ALeft].Central].Name,
          FResult.Units[FResult.Subsystems[ARight].Central].Name);
      end;
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
  SetLength(Sorted, Length(Order));
  SetLength(Map, Length(Order));
  for Index := 0 to High(Order) do
  begin
    Sorted[Index] := FResult.Subsystems[Order[Index]];
    Map[Order[Index]] := Index;
  end;
  FResult.Subsystems := Sorted;
  for Index := 0 to High(FResult.Units) do
  begin
    FResult.Units[Index].Subsystem := Map[FResult.Units[Index].Subsystem];
  end;
  SetLength(Family, Length(FFamily));
  for Index := 0 to High(FFamily) do
  begin
    Family[Map[Index]] := Map[FFamily[Index]];
  end;
  FFamily := Family;
  if FFoundation >= 0 then
  begin
    FFoundation := Map[FFoundation];
  end;
end;

procedure TAnalysis.AssignColors;
var
  Slots, Ranks: TDictionary<Integer, Integer>;
  Index, Slot, Rank: Integer;
begin
  // Eine Farbe je Familie in der Reihenfolge der Teilsysteme (ohne Nachteilung: Farbe = Nummer wie vor #1364);
  // die Teile abwechselnd heller und dunkler: 0, +1, -1, +2, …
  Slots := TDictionary<Integer, Integer>.Create;
  Ranks := TDictionary<Integer, Integer>.Create;
  try
    for Index := 0 to High(FResult.Subsystems) do
    begin
      // Das Fundament (#1365) bekommt die neutrale Farbe und verbraucht keine.
      if FResult.Subsystems[Index].Foundation then
      begin
        FResult.Subsystems[Index].ColorSlot := -1;
        FResult.Subsystems[Index].Shade := 0;
        Continue;
      end;
      if not Slots.TryGetValue(FFamily[Index], Slot) then
      begin
        Slot := Slots.Count;
        Slots.Add(FFamily[Index], Slot);
      end;
      if not Ranks.TryGetValue(FFamily[Index], Rank) then
      begin
        Rank := 0;
      end;
      Ranks.AddOrSetValue(FFamily[Index], Rank + 1);
      FResult.Subsystems[Index].ColorSlot := Slot;
      if Rank = 0 then
      begin
        FResult.Subsystems[Index].Shade := 0;
      end
      else if Odd(Rank) then
      begin
        FResult.Subsystems[Index].Shade := (Rank + 1) div 2;
      end
      else
      begin
        FResult.Subsystems[Index].Shade := -(Rank div 2);
      end;
    end;
  finally
    Ranks.Free;
    Slots.Free;
  end;
end;

function TAnalysis.Run(ACentralCount: Integer): TArchitectureOverview;
begin
  FResult := Default(TArchitectureOverview);
  FResult.Grouping := FGrouping;
  FResult.ExplainAssignment := True;
  CollectUnits;
  CollectEdges;
  Measure;
  Group;
  SortSubsystems;
  NameSubsystems;
  AssignColors;
  CollectAssignments;
  FindOutliers;
  CollectCycles;
  CollectCrossLinks;
  if Length(FResult.Central) > ACentralCount then
  begin
    SetLength(FResult.Central, ACentralCount);
  end;
  Result := FResult;
end;

class function TArchitectureAnalyzer.Analyze(AGraph: TUsesGraph; ALocator: TUsesLocator;
  ACentralCount: Integer): TArchitectureOverview;
begin
  Result := Analyze(AGraph, ALocator, ACentralCount, TArchitectureGrouping.Default);
end;

class function TArchitectureAnalyzer.Analyze(AGraph: TUsesGraph; ALocator: TUsesLocator; ACentralCount: Integer;
  const AGrouping: TArchitectureGrouping): TArchitectureOverview;
var
  Analysis: TAnalysis;
  Started: TDateTime;
begin
  Started := Now;
  Analysis := TAnalysis.Create(AGraph, ALocator, AGrouping);
  try
    Result := Analysis.Run(EnsureRange(ACentralCount, 1, MaxInt));
  finally
    Analysis.Free;
  end;
  Result.Root := AGraph.Options.Root;
  Result.IncludeLibrary := AGraph.Options.IncludeLibrary;
  Result.Excludes := AGraph.Options.Exclude;
  Result.Created := Now;
  Result.DurationMs := MilliSecondsBetween(Result.Created, Started);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Architecture.Overview', cTexts);

end.
