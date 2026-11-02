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
    /// <summary>Regel, nach der Units ins Teilsystem „Fundament“ kommen (Bericht, Fenster, get_architecture).
    /// </summary>
    FoundationRule = 'Units mit Rolle Fundament, deren direkt Abhängige in mindestens drei Teilsystemen liegen ' +
      'oder höchstens zu 60 % im eigenen, und Units, die nur sie verwenden';
    /// <summary>Knapp zugeordnet (#1368), wenn das stärkste andere Teilsystem mindestens so viel Prozent der Summe
    /// des eigenen erreicht.</summary>
    ClosePercent = 75;
    /// <summary>Herkunft der Angleichung (#1367): architecture.baseline bzw. der zuletzt berechnete Stand.</summary>
    AlignedBaseline = 'baseline';
    AlignedLast = 'last';
  public
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
  Atlas.Common.Architecture.Louvain;

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

function TArchitectureOverview.Profile(AUnit: Integer): TOverviewProfile;
var
  Edge: TOverviewEdge;
  Index, Member: Integer;
begin
  Result := Default(TOverviewProfile);
  Result.Unit_ := AUnit;
  Result.Outlier := -1;
  for Edge in Edges do
  begin
    if (Edge.Source = AUnit) and not ContainsInt(Edge.Target, Result.DependsOn) then
    begin
      Result.DependsOn := Result.DependsOn + [Edge.Target];
    end;
    if (Edge.Target = AUnit) and not ContainsInt(Edge.Source, Result.UsedBy) then
    begin
      Result.UsedBy := Result.UsedBy + [Edge.Source];
    end;
  end;
  for Index := 0 to High(Cycles) do
  begin
    for Member in Cycles[Index].Component do
    begin
      if Member = AUnit then
      begin
        Result.Cycles := Result.Cycles + [Index];
      end;
    end;
  end;
  for Index := 0 to High(CrossLinks) do
  begin
    if (CrossLinks[Index].Edge.Source = AUnit) or (CrossLinks[Index].Edge.Target = AUnit) then
    begin
      Result.CrossLinks := Result.CrossLinks + [Index];
    end;
  end;
  for Index := 0 to High(Outliers) do
  begin
    if Outliers[Index].Unit_ = AUnit then
    begin
      Result.Outlier := Index;
    end;
  end;
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
      Result := 'Fundament';
    TOverviewUnitRole.Hub:
      Result := 'Drehscheibe';
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

/// <summary>Gruppennummern fortlaufend ab 0 in der Reihenfolge des ersten Auftretens.</summary>
procedure Renumber(var AValues: TArray<Integer>);
var
  Map: TDictionary<Integer, Integer>;
  Index, Number: Integer;
begin
  Map := TDictionary<Integer, Integer>.Create;
  try
    for Index := 0 to High(AValues) do
    begin
      if not Map.TryGetValue(AValues[Index], Number) then
      begin
        Number := Map.Count;
        Map.Add(AValues[Index], Number);
      end;
      AValues[Index] := Number;
    end;
  finally
    Map.Free;
  end;
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
    /// <summary>Je Unit die Nummern ihrer Kanten in FResult.Edges (beide Richtungen, ohne Schleifen).</summary>
    FIncident: TArray<TArray<Integer>>;
    /// <summary>Je Unit die Stelle im gerade untersuchten Teilsystem; -1 außerhalb.</summary>
    FLocal: TArray<Integer>;
    /// <summary>Je Unit: gehört ins Teilsystem „Fundament“ (#1365, nur Foundations = Separate).</summary>
    FInFoundation: TArray<Boolean>;
    /// <summary>Nummer des Teilsystems „Fundament“; -1 ohne.</summary>
    FFoundation: Integer;
    procedure CollectUnits;
    procedure CollectEdges;
    procedure Measure;
    procedure Group;
    procedure SeparateFoundations(const AEdges: TArray<TLouvainEdge>; var ACommunities: TArray<Integer>);
    function InFoundation(AUnit: Integer): Boolean;
    function IsFoundation(ASubsystem: Integer): Boolean;
    procedure Split(var ACommunities: TArray<Integer>; AIsolated: Integer);
    function NeedsSplit(const AMembers: TArray<Integer>): Boolean;
    function SplitMembers(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
    function SplitGroup(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
    procedure NameSubsystems;
    procedure AssignColors;
    procedure CollectAssignments;
    procedure FindOutliers;
    procedure CollectCycles;
    procedure CollectCrossLinks;
    procedure SortSubsystems;
    function Locate(var AEdge: TOverviewEdge; const AGraphEdge: TUsesEdge): Boolean;
    function Weight(const AEdge: TOverviewEdge): Integer;
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

function TAnalysis.InFoundation(AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(FInFoundation)) and FInFoundation[AUnit];
end;

function TAnalysis.IsFoundation(ASubsystem: Integer): Boolean;
begin
  Result := (FFoundation >= 0) and (ASubsystem = FFoundation);
end;

function TAnalysis.Weight(const AEdge: TOverviewEdge): Integer;
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
  Order: TList<Integer>;
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
  Order := TList<Integer>.Create;
  try
    for Index := 0 to High(FResult.Units) do
    begin
      Order.Add(Index);
    end;
    Order.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := FResult.Units[ARight].Total - FResult.Units[ALeft].Total;
        if Result = 0 then
        begin
          Result := FResult.Units[ARight].Direct - FResult.Units[ALeft].Direct;
        end;
        if Result = 0 then
        begin
          Result := ALeft - ARight;
        end;
      end));
    FResult.Central := Order.ToArray;
  finally
    Order.Free;
  end;
end;

procedure TAnalysis.Group;
var
  Edges: TArray<TLouvainEdge>;
  Edge: TOverviewEdge;
  Item: TLouvainEdge;
  Communities: TArray<Integer>;
  Index, Count, Member, Isolated: Integer;
  Degree: TArray<Integer>;
  Subsystem: TOverviewSubsystem;
begin
  SetLength(Edges, Length(FResult.Edges));
  Count := 0;
  for Edge in FResult.Edges do
  begin
    Item.A := Edge.Source;
    Item.B := Edge.Target;
    Item.Weight := Weight(Edge);
    Edges[Count] := Item;
    Inc(Count);
  end;
  Communities := TLouvain.Communities(Length(FResult.Units), Edges, FGrouping.Resolution);
  if FGrouping.Foundations <> TArchitectureFoundations.Group then
  begin
    SeparateFoundations(Edges, Communities);
  end;
  // Units ohne Kante bilden bei Louvain je eine eigene Gruppe; sie kommen in eine Sammelgruppe.
  SetLength(Degree, Length(FResult.Units));
  for Edge in FResult.Edges do
  begin
    Inc(Degree[Edge.Source]);
    Inc(Degree[Edge.Target]);
  end;
  Isolated := -1;
  for Index := 0 to High(Communities) do
  begin
    if Degree[Index] = 0 then
    begin
      if Isolated < 0 then
      begin
        Isolated := Communities[Index];
      end;
      Communities[Index] := Isolated;
    end;
  end;
  Renumber(Communities);
  if Isolated >= 0 then
  begin
    for Index := 0 to High(Communities) do
    begin
      if Degree[Index] = 0 then
      begin
        Isolated := Communities[Index];
        Break;
      end;
    end;
  end;
  for Index := 0 to High(Communities) do
  begin
    if InFoundation(Index) then
    begin
      FFoundation := Communities[Index];
      Break;
    end;
  end;
  // Die Nachteilung lässt die Nummer ungeteilter Gruppen (also auch des Fundaments) stehen.
  Split(Communities, Isolated);
  Count := 0;
  for Member in Communities do
  begin
    Count := Max(Count, Member + 1);
  end;
  SetLength(FResult.Subsystems, Count);
  for Index := 0 to Count - 1 do
  begin
    Subsystem := Default(TOverviewSubsystem);
    Subsystem.Central := -1;
    FResult.Subsystems[Index] := Subsystem;
  end;
  for Index := 0 to High(FResult.Units) do
  begin
    FResult.Units[Index].Subsystem := Communities[Index];
    FResult.Subsystems[Communities[Index]].Units := FResult.Subsystems[Communities[Index]].Units + [Index];
  end;
  for Edge in FResult.Edges do
  begin
    if FResult.Units[Edge.Source].Subsystem = FResult.Units[Edge.Target].Subsystem then
    begin
      Inc(FResult.Subsystems[FResult.Units[Edge.Source].Subsystem].InnerEdges);
    end
    else if IsFoundation(FResult.Units[Edge.Source].Subsystem) or IsFoundation(FResult.Units[Edge.Target].Subsystem) then
    begin
      // Kanten ins Fundament (#1365) gehen nicht in den Zusammenhalt ein.
      Continue;
    end
    else
    begin
      Inc(FResult.Subsystems[FResult.Units[Edge.Source].Subsystem].OuterEdges);
      Inc(FResult.Subsystems[FResult.Units[Edge.Target].Subsystem].OuterEdges);
    end;
  end;
  for Index := 0 to High(FResult.Subsystems) do
  begin
    Subsystem := FResult.Subsystems[Index];
    Subsystem.Isolated := Index = Isolated;
    Subsystem.Foundation := IsFoundation(Index);
    if Subsystem.Foundation then
    begin
      Subsystem.Cohesion := 0;
    end
    else if Subsystem.InnerEdges + Subsystem.OuterEdges > 0 then
    begin
      Subsystem.Cohesion := Subsystem.InnerEdges / (Subsystem.InnerEdges + Subsystem.OuterEdges);
    end
    else
    begin
      Subsystem.Cohesion := 1;
    end;
    // Units nach gesamt abhängig absteigend; die erste ist die zentrale.
    TArray.Sort<Integer>(Subsystem.Units, TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := FResult.Units[ARight].Total - FResult.Units[ALeft].Total;
        if Result = 0 then
        begin
          Result := FResult.Units[ARight].Direct - FResult.Units[ALeft].Direct;
        end;
        if Result = 0 then
        begin
          Result := ALeft - ARight;
        end;
      end));
    if Subsystem.Units <> nil then
    begin
      Subsystem.Central := Subsystem.Units[0];
    end;
    FResult.Subsystems[Index] := Subsystem;
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
  Count, Index, Unit_, Other, Best, Next, Total, Largest, Number: Integer;
  Candidate, Foundation, Follower, Assigned_: TArray<Boolean>;
  Degree, ReducedDegree, Follow, Probe, Second: TArray<Integer>;
  Weights: TArray<Double>;
  Incoming: TArray<TArray<Integer>>;
  Edge: TLouvainEdge;
  Spread: TDictionary<Integer, Integer>;
  Pass: Integer;
  Changed, Any, Same: Boolean;

  /// <summary>Gemeinschaft mit dem größten Gewicht in Weights (Gleichstand: kleinere Nummer); -1 ohne.</summary>
  function Heaviest: Integer;
  var
    mCommunity: Integer;
  begin
    Result := -1;
    for mCommunity := 0 to High(Weights) do
    begin
      if (Weights[mCommunity] > 0) and ((Result < 0) or (Weights[mCommunity] > Weights[Result])) then
      begin
        Result := mCommunity;
      end;
    end;
  end;

  /// <summary>Louvain ohne die Units AExcluded und ihre Kanten, fortlaufend nummeriert; ADegree: Kanten je Unit
  /// im verbleibenden Graphen.</summary>
  function Without(const AExcluded: TArray<Boolean>; out ADegree: TArray<Integer>): TArray<Integer>;
  var
    mReduced: TList<TLouvainEdge>;
    mEdge: TLouvainEdge;
  begin
    SetLength(ADegree, Count);
    mReduced := TList<TLouvainEdge>.Create;
    try
      for mEdge in AEdges do
      begin
        if not AExcluded[mEdge.A] and not AExcluded[mEdge.B] then
        begin
          mReduced.Add(mEdge);
          Inc(ADegree[mEdge.A]);
          Inc(ADegree[mEdge.B]);
        end;
      end;
      Result := TLouvain.Communities(Count, mReduced.ToArray, FGrouping.Resolution);
    finally
      mReduced.Free;
    end;
    Renumber(Result);
  end;

begin
  Count := Length(FResult.Units);
  SetLength(Candidate, Count);
  SetLength(Foundation, Count);
  SetLength(Incoming, Count);
  SetLength(Degree, Count);
  for Index := 0 to High(AEdges) do
  begin
    Incoming[AEdges[Index].B] := Incoming[AEdges[Index].B] + [Index];
    Inc(Degree[AEdges[Index].A]);
    Inc(Degree[AEdges[Index].B]);
  end;
  // Kandidaten: Rolle Fundament. Ihre Verteilung zählt in einem Lauf ohne sie, denn im ersten Lauf ziehen sie ihre
  // Abhängigen ja gerade zusammen.
  Any := False;
  for Unit_ := 0 to Count - 1 do
  begin
    Candidate[Unit_] := (FResult.Units[Unit_].Role = TOverviewUnitRole.Foundation) and (Length(Incoming[Unit_]) > 0);
    Any := Any or Candidate[Unit_];
  end;
  if not Any then
  begin
    Exit;
  end;
  Probe := Without(Candidate, ReducedDegree);
  // Übergreifend: Abhängige (ohne Kandidaten und ohne Units, die nur an Kandidaten hängen) in mindestens drei
  // Teilsystemen oder höchstens 60 % im größten.
  Any := False;
  Spread := TDictionary<Integer, Integer>.Create;
  try
    for Unit_ := 0 to Count - 1 do
    begin
      if not Candidate[Unit_] then
      begin
        Continue;
      end;
      Spread.Clear;
      Total := 0;
      for Index in Incoming[Unit_] do
      begin
        Other := AEdges[Index].A;
        if Candidate[Other] or (ReducedDegree[Other] = 0) then
        begin
          Continue;
        end;
        Inc(Total);
        if not Spread.TryGetValue(Probe[Other], Number) then
        begin
          Number := 0;
        end;
        Spread.AddOrSetValue(Probe[Other], Number + 1);
      end;
      if Total = 0 then
      begin
        Continue;
      end;
      Largest := 0;
      for Number in Spread.Values do
      begin
        Largest := Max(Largest, Number);
      end;
      Foundation[Unit_] := (Spread.Count >= TArchitectureGrouping.FoundationMinSpread) or
        (Largest * 100 <= TArchitectureGrouping.FoundationMaxOwnPercent * Total);
      Any := Any or Foundation[Unit_];
    end;
  finally
    Spread.Free;
  end;
  if not Any then
  begin
    Exit;
  end;
  // Zweiter Lauf ohne die übergreifenden Fundamente und ohne ihre Kanten (sind es alle Kandidaten, ist es der Lauf
  // von eben).
  Same := True;
  for Unit_ := 0 to Count - 1 do
  begin
    Same := Same and (Candidate[Unit_] = Foundation[Unit_]);
  end;
  if Same then
  begin
    Second := Probe;
  end
  else
  begin
    Second := Without(Foundation, ReducedDegree);
  end;
  Next := 0;
  for Index in Second do
  begin
    Next := Max(Next, Index + 1);
  end;
  // Units, deren einzige Kanten zu Fundamenten führen, folgen dem Fundament mit dem größten Gewicht.
  SetLength(Follower, Count);
  SetLength(Follow, Count);
  SetLength(Weights, Count);
  for Unit_ := 0 to Count - 1 do
  begin
    Follow[Unit_] := -1;
    if Foundation[Unit_] or (Degree[Unit_] = 0) or (ReducedDegree[Unit_] > 0) then
    begin
      Continue;
    end;
    for Index := 0 to Count - 1 do
    begin
      Weights[Index] := 0;
    end;
    for Edge in AEdges do
    begin
      if Edge.A = Unit_ then
      begin
        Weights[Edge.B] := Weights[Edge.B] + Edge.Weight;
      end
      else if Edge.B = Unit_ then
      begin
        Weights[Edge.A] := Weights[Edge.A] + Edge.Weight;
      end;
    end;
    for Other := 0 to Count - 1 do
    begin
      if Foundation[Other] and (Weights[Other] > 0) and
        ((Follow[Unit_] < 0) or (Weights[Other] > Weights[Follow[Unit_]])) then
      begin
        Follow[Unit_] := Other;
      end;
    end;
    Follower[Unit_] := Follow[Unit_] >= 0;
  end;
  if FGrouping.Foundations = TArchitectureFoundations.Separate then
  begin
    SetLength(FInFoundation, Count);
    for Unit_ := 0 to Count - 1 do
    begin
      if Foundation[Unit_] or Follower[Unit_] then
      begin
        Second[Unit_] := Next;
        FInFoundation[Unit_] := True;
      end;
    end;
  end
  else
  begin
    // Anhängen: in das Teilsystem, aus dem die meisten Abhängigen stammen (gewichtet, Gleichstand: kleinere
    // Nummer). Fundamente, die nur Fundamente verwenden, folgen ihren Abhängigen, sobald diese zugeordnet sind;
    // solche ohne zugeordnete Abhängige zuletzt den Units, die sie verwenden.
    SetLength(Assigned_, Count);
    for Unit_ := 0 to Count - 1 do
    begin
      Assigned_[Unit_] := not Foundation[Unit_] and not Follower[Unit_];
    end;
    SetLength(Weights, Next);
    for Pass := 0 to 1 do
      repeat
        Changed := False;
        for Unit_ := 0 to Count - 1 do
        begin
          if not Foundation[Unit_] or Assigned_[Unit_] then
          begin
            Continue;
          end;
          for Index := 0 to High(Weights) do
          begin
            Weights[Index] := 0;
          end;
          for Index in Incoming[Unit_] do
          begin
            if Assigned_[AEdges[Index].A] then
            begin
              Weights[Second[AEdges[Index].A]] := Weights[Second[AEdges[Index].A]] + AEdges[Index].Weight;
            end;
          end;
          if Pass = 1 then
          begin
            for Edge in AEdges do
            begin
              if (Edge.A = Unit_) and Assigned_[Edge.B] then
              begin
                Weights[Second[Edge.B]] := Weights[Second[Edge.B]] + Edge.Weight;
              end;
            end;
          end;
          Best := Heaviest;
          if Best < 0 then
          begin
            Continue;
          end;
          Second[Unit_] := Best;
          Assigned_[Unit_] := True;
          Changed := True;
        end;
      until not Changed;
    // Ohne jede Zuordnung (nur Kanten unter solchen Fundamenten): je ein eigenes Teilsystem.
    for Unit_ := 0 to Count - 1 do
    begin
      if Foundation[Unit_] and not Assigned_[Unit_] then
      begin
        Second[Unit_] := Next;
        Inc(Next);
      end;
    end;
    for Unit_ := 0 to Count - 1 do
    begin
      if Follower[Unit_] then
      begin
        Second[Unit_] := Second[Follow[Unit_]];
      end;
    end;
  end;
  ACommunities := Second;
end;

procedure TAnalysis.Split(var ACommunities: TArray<Integer>; AIsolated: Integer);
var
  Groups: TArray<TArray<Integer>>;
  Sizes: TArray<Integer>;
  Count, Index, Member: Integer;
  Edge: TOverviewEdge;
begin
  Count := 0;
  for Member in ACommunities do
  begin
    Count := Max(Count, Member + 1);
  end;
  // Kanten je Unit für Zusammenhalt und Teilgraphen.
  SetLength(Sizes, Length(FResult.Units));
  for Edge in FResult.Edges do
  begin
    if Edge.Source <> Edge.Target then
    begin
      Inc(Sizes[Edge.Source]);
      Inc(Sizes[Edge.Target]);
    end;
  end;
  SetLength(FIncident, Length(FResult.Units));
  for Index := 0 to High(FIncident) do
  begin
    SetLength(FIncident[Index], Sizes[Index]);
    Sizes[Index] := 0;
  end;
  for Index := 0 to High(FResult.Edges) do
  begin
    Edge := FResult.Edges[Index];
    if Edge.Source = Edge.Target then
    begin
      Continue;
    end;
    FIncident[Edge.Source][Sizes[Edge.Source]] := Index;
    Inc(Sizes[Edge.Source]);
    FIncident[Edge.Target][Sizes[Edge.Target]] := Index;
    Inc(Sizes[Edge.Target]);
  end;
  SetLength(FLocal, Length(FResult.Units));
  for Index := 0 to High(FLocal) do
  begin
    FLocal[Index] := -1;
  end;
  // Units nach Nummer (= nach Name): dieselbe Startreihenfolge wie im ersten Lauf.
  SetLength(Sizes, Count);
  for Index := 0 to Count - 1 do
  begin
    Sizes[Index] := 0;
  end;
  for Member in ACommunities do
  begin
    Inc(Sizes[Member]);
  end;
  SetLength(Groups, Count);
  for Index := 0 to Count - 1 do
  begin
    SetLength(Groups[Index], Sizes[Index]);
    Sizes[Index] := 0;
  end;
  for Index := 0 to High(ACommunities) do
  begin
    Groups[ACommunities[Index]][Sizes[ACommunities[Index]]] := Index;
    Inc(Sizes[ACommunities[Index]]);
  end;
  Groups := TArchitectureAnalyzer.SplitGroups(Groups, AIsolated, TArchitectureGrouping.SplitDepth, SplitGroup,
    FFamily);
  for Index := 0 to High(Groups) do
  begin
    for Member in Groups[Index] do
    begin
      ACommunities[Member] := Index;
    end;
  end;
end;

function TAnalysis.SplitGroup(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
begin
  AParts := nil;
  // Das Fundament (#1365) bleibt ganz.
  Result := (Length(AMembers) > 0) and not InFoundation(AMembers[0]) and NeedsSplit(AMembers) and
    SplitMembers(AMembers, AParts);
end;

function TAnalysis.NeedsSplit(const AMembers: TArray<Integer>): Boolean;
var
  Inner, Outer, Member, EdgeIndex, Other: Integer;
  Edge: TOverviewEdge;
  Cohesion: Double;
begin
  // Zusammenhalt wie in Group: Kanten innen / (innen + nach außen); erst rechnen, wenn er zählt.
  Cohesion := 1;
  if (FGrouping.MinCohesion > 0) and (Length(AMembers) >= TArchitectureGrouping.LooseMinUnits) then
  begin
    for Member in AMembers do
    begin
      FLocal[Member] := 0;
    end;
    Inner := 0;
    Outer := 0;
    for Member in AMembers do
    begin
      for EdgeIndex in FIncident[Member] do
      begin
        Edge := FResult.Edges[EdgeIndex];
        if Edge.Source = Member then
        begin
          Other := Edge.Target;
        end
        else
        begin
          Other := Edge.Source;
        end;
        // Kanten ins Fundament zählen wie in Group nicht mit.
        if InFoundation(Other) then
        begin
          Continue;
        end;
        if FLocal[Other] >= 0 then
        begin
          Inc(Inner);
        end
        else
        begin
          Inc(Outer);
        end;
      end;
    end;
    for Member in AMembers do
    begin
      FLocal[Member] := -1;
    end;
    // Innere Kanten stehen bei beiden Enden.
    Inner := Inner div 2;
    if Inner + Outer > 0 then
    begin
      Cohesion := Inner / (Inner + Outer);
    end;
  end;
  Result := FGrouping.NeedsSplit(Length(AMembers), Length(FResult.Units), Cohesion);
end;

function TAnalysis.SplitMembers(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
var
  Edges: TList<TLouvainEdge>;
  Item: TLouvainEdge;
  Degree, Local, Sizes: TArray<Integer>;
  Numbers: TDictionary<Integer, Integer>;
  Position, EdgeIndex, Number, Largest: Integer;
  Edge: TOverviewEdge;
begin
  AParts := nil;
  SetLength(Degree, Length(AMembers));
  for Position := 0 to High(AMembers) do
  begin
    FLocal[AMembers[Position]] := Position;
  end;
  Edges := TList<TLouvainEdge>.Create;
  try
    for Position := 0 to High(AMembers) do
    begin
      for EdgeIndex in FIncident[AMembers[Position]] do
      begin
        Edge := FResult.Edges[EdgeIndex];
        // Jede Kante einmal, bei ihrer Quelle; nur Kanten innerhalb des Teilsystems.
        if (Edge.Source <> AMembers[Position]) or (FLocal[Edge.Target] < 0) then
        begin
          Continue;
        end;
        Item.A := Position;
        Item.B := FLocal[Edge.Target];
        Item.Weight := Weight(Edge);
        Edges.Add(Item);
        Inc(Degree[Item.A]);
        Inc(Degree[Item.B]);
      end;
    end;
    Local := TLouvain.Communities(Length(AMembers), Edges.ToArray, FGrouping.Resolution);
  finally
    Edges.Free;
    for Position := 0 to High(AMembers) do
    begin
      FLocal[AMembers[Position]] := -1;
    end;
  end;
  // Teile fortlaufend in der Reihenfolge der Units; Units ohne Kante im Teilgraphen zählen nicht mit.
  Numbers := TDictionary<Integer, Integer>.Create;
  try
    for Position := 0 to High(Local) do
    begin
      if Degree[Position] = 0 then
      begin
        Local[Position] := -1;
        Continue;
      end;
      if not Numbers.TryGetValue(Local[Position], Number) then
      begin
        Number := Numbers.Count;
        Numbers.Add(Local[Position], Number);
      end;
      Local[Position] := Number;
    end;
    Result := Numbers.Count > 1;
    if not Result then
    begin
      Exit;
    end;
    SetLength(Sizes, Numbers.Count);
  finally
    Numbers.Free;
  end;
  for Number in Local do
  begin
    if Number >= 0 then
    begin
      Inc(Sizes[Number]);
    end;
  end;
  // Units ohne Kante im Teilgraphen bleiben beim größten Teil (keine Teile aus einer einzelnen Unit).
  Largest := 0;
  for Number := 1 to High(Sizes) do
  begin
    if Sizes[Number] > Sizes[Largest] then
    begin
      Largest := Number;
    end;
  end;
  SetLength(AParts, Length(Sizes));
  for Position := 0 to High(Local) do
  begin
    if Local[Position] < 0 then
    begin
      Local[Position] := Largest;
    end;
    AParts[Local[Position]] := AParts[Local[Position]] + [AMembers[Position]];
  end;
end;

/// <summary>Je Namensraum-Abschnitt (klein) die Zahl der Units aus AMembers, die ihn tragen (je Unit einmal).
/// </summary>
function PartCounts(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>): TDictionary<string, Integer>;
var
  Member, Count: Integer;
  Part, Key: string;
  Seen: TArray<string>;
begin
  Result := TDictionary<string, Integer>.Create;
  for Member in AMembers do
  begin
    Seen := nil;
    for Part in AParts[Member] do
    begin
      Key := LowerCase(Part);
      if IndexStr(Key, Seen) >= 0 then
      begin
        Continue;
      end;
      Seen := Seen + [Key];
      if not Result.TryGetValue(Key, Count) then
      begin
        Count := 0;
      end;
      Result.AddOrSetValue(Key, Count + 1);
    end;
  end;
end;

/// <summary>Bester Namensraum-Abschnitt einer Gruppe: Häufigkeit in der Gruppe mal log(ATotal / Häufigkeit in
/// AGlobal); '' ohne Abschnitt mit Gewinn. AGlobal zählt über das ganze Projekt bzw. bei Teilen eines
/// nachgeteilten Teilsystems über dessen Units (#1364).</summary>
function BestPart(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>; const AGlobal:
  TDictionary<string, Integer>; ATotal: Integer; out AScore: Double): string;
var
  Local: TDictionary<string, Integer>;
  Global_: Integer;
  Key: string;
  Keys: TArray<string>;
  Score: Double;
begin
  Result := '';
  AScore := 0;
  Local := PartCounts(AParts, AMembers);
  try
    Keys := Local.Keys.ToArray;
    TArray.Sort<string>(Keys);
    for Key in Keys do
    begin
      if not AGlobal.TryGetValue(Key, Global_) or (Global_ <= 0) then
      begin
        Continue;
      end;
      Score := Local[Key] * Ln(ATotal / Global_);
      if Score > AScore + 1E-9 then
      begin
        AScore := Score;
        Result := Key;
      end;
    end;
  finally
    Local.Free;
  end;
end;

/// <summary>Schreibweise eines Abschnitts, wie er in den Units der Gruppe steht.</summary>
function PartCaption(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>; const AKey: string): string;
var
  Member: Integer;
  Part: string;
begin
  for Member in AMembers do
  begin
    for Part in AParts[Member] do
    begin
      if SameText(Part, AKey) then
      begin
        Exit(Part);
      end;
    end;
  end;
  Result := AKey;
end;

procedure TAnalysis.NameSubsystems;
var
  Parts: TArray<TArray<string>>;
  Global_, Family: TDictionary<string, Integer>;
  Index, Suffix, Other: Integer;
  Key, ParentKey, Name: string;
  All: TArray<Integer>;
  FamilyUnits: TArray<TArray<Integer>>;
  FamilySize: TArray<Integer>;
  Score: Double;
  Taken: Boolean;

  /// <summary>Name aus dem besten Abschnitt von AMembers gegen ACounts, sonst die zentralste Unit.</summary>
  function NameOf(const AMembers: TArray<Integer>; const ACounts: TDictionary<string, Integer>; ATotal: Integer;
    out AKey: string): string;
  var
    mMember, mCentral: Integer;
  begin
    AKey := BestPart(Parts, AMembers, ACounts, ATotal, Score);
    if AKey <> '' then
    begin
      Exit(PartCaption(Parts, AMembers, AKey));
    end;
    mCentral := -1;
    for mMember in AMembers do
    begin
      if (mCentral < 0) or (FResult.Units[mMember].Total > FResult.Units[mCentral].Total) or
        ((FResult.Units[mMember].Total = FResult.Units[mCentral].Total) and
        ((FResult.Units[mMember].Direct > FResult.Units[mCentral].Direct) or
        ((FResult.Units[mMember].Direct = FResult.Units[mCentral].Direct) and (mMember < mCentral)))) then
      begin
        mCentral := mMember;
      end;
    end;
    if mCentral >= 0 then
    begin
      Result := FResult.Units[mCentral].Name;
    end
    else
    begin
      Result := '';
    end;
  end;

begin
  SetLength(FNamedByPart, Length(FResult.Subsystems));
  SetLength(FPartKey, Length(FResult.Subsystems));
  SetLength(Parts, Length(FResult.Units));
  SetLength(All, Length(FResult.Units));
  for Index := 0 to High(FResult.Units) do
  begin
    Parts[Index] := TArchitectureAnalyzer.NamespaceParts(FResult.Units[Index].Name);
    All[Index] := Index;
  end;
  // Units je Familie (ursprüngliches Teilsystem vor der Nachteilung, #1364).
  SetLength(FamilyUnits, Length(FResult.Subsystems));
  SetLength(FamilySize, Length(FResult.Subsystems));
  for Index := 0 to High(FResult.Subsystems) do
  begin
    FamilyUnits[FFamily[Index]] := FamilyUnits[FFamily[Index]] + FResult.Subsystems[Index].Units;
    Inc(FamilySize[FFamily[Index]]);
  end;
  Global_ := PartCounts(Parts, All);
  try
    for Index := 0 to High(FResult.Subsystems) do
    begin
      Key := '';
      if FResult.Subsystems[Index].Isolated then
      begin
        Name := TArchitectureAnalyzer.IsolatedName;
      end
      else if FResult.Subsystems[Index].Foundation then
      begin
        Name := TArchitectureAnalyzer.FoundationName;
      end
      else if FamilySize[FFamily[Index]] > 1 then
      begin
        // Teil eines nachgeteilten Teilsystems: Abschnitt, der es innerhalb des ursprünglichen unterscheidet.
        Family := PartCounts(Parts, FamilyUnits[FFamily[Index]]);
        try
          Name := NameOf(FResult.Subsystems[Index].Units, Family, Length(FamilyUnits[FFamily[Index]]), Key);
        finally
          Family.Free;
        end;
        FResult.Subsystems[Index].Parent := NameOf(FamilyUnits[FFamily[Index]], Global_, Length(FResult.Units),
          ParentKey);
      end
      else
      begin
        Name := NameOf(FResult.Subsystems[Index].Units, Global_, Length(FResult.Units), Key);
      end;
      FNamedByPart[Index] := Key <> '';
      FPartKey[Index] := Key;
      FResult.Subsystems[Index].Name := Name;
    end;
  finally
    Global_.Free;
  end;
  // Doppelte Namen eindeutig machen: "Index", "Index 2" (in der Reihenfolge der Teilsysteme).
  for Index := 1 to High(FResult.Subsystems) do
  begin
    Name := FResult.Subsystems[Index].Name;
    Suffix := 1;
    repeat
      Taken := False;
      for Other := 0 to Index - 1 do
      begin
        if SameText(FResult.Subsystems[Other].Name, Name) then
        begin
          Taken := True;
        end;
      end;
      if Taken then
      begin
        Inc(Suffix);
        Name := FResult.Subsystems[Index].Name + ' ' + IntToStr(Suffix);
      end;
    until not Taken;
    FResult.Subsystems[Index].Name := Name;
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

class function TArchitectureAnalyzer.Assignments(const AOverview: TArchitectureOverview):
  TArray<TOverviewAssignment>;
var
  mInterfaces, mImplementations: TArray<TArray<Integer>>;
  mNames: TArray<string>;
  mRows: TArray<TOverviewAssignmentRow>;
  mEdge: TOverviewEdge;
  mIndex, mSubsystem, mCount, mOwn: Integer;

  procedure Count(AUnit, ASubsystem: Integer; AInterface: Boolean);
  begin
    if AInterface then
    begin
      Inc(mInterfaces[AUnit][ASubsystem]);
    end
    else
    begin
      Inc(mImplementations[AUnit][ASubsystem]);
    end;
  end;

begin
  SetLength(mInterfaces, Length(AOverview.Units));
  SetLength(mImplementations, Length(AOverview.Units));
  for mIndex := 0 to High(AOverview.Units) do
  begin
    SetLength(mInterfaces[mIndex], Length(AOverview.Subsystems));
    SetLength(mImplementations[mIndex], Length(AOverview.Subsystems));
  end;
  for mEdge in AOverview.Edges do
  begin
    Count(mEdge.Source, AOverview.Units[mEdge.Target].Subsystem, mEdge.Section = TUsesSection.Interface_);
    Count(mEdge.Target, AOverview.Units[mEdge.Source].Subsystem, mEdge.Section = TUsesSection.Interface_);
  end;
  SetLength(mNames, Length(AOverview.Subsystems));
  for mSubsystem := 0 to High(AOverview.Subsystems) do
  begin
    mNames[mSubsystem] := AOverview.Subsystems[mSubsystem].Name;
  end;
  SetLength(Result, Length(AOverview.Units));
  SetLength(mRows, Length(AOverview.Subsystems));
  for mIndex := 0 to High(AOverview.Units) do
  begin
    mOwn := AOverview.Units[mIndex].Subsystem;
    mCount := 0;
    if (mOwn < 0) or (mOwn > High(AOverview.Subsystems)) then
    begin
      Result[mIndex] := AssignmentOf(nil, -1, mNames);
      Continue;
    end;
    for mSubsystem := 0 to High(AOverview.Subsystems) do
    begin
      if (mSubsystem <> mOwn) and (mInterfaces[mIndex][mSubsystem] = 0) and
        (mImplementations[mIndex][mSubsystem] = 0) then
      begin
        Continue;
      end;
      mRows[mCount].Subsystem := mSubsystem;
      mRows[mCount].Interfaces := mInterfaces[mIndex][mSubsystem];
      mRows[mCount].Implementations := mImplementations[mIndex][mSubsystem];
      mRows[mCount].Sum := mRows[mCount].Interfaces * InterfaceWeight +
        mRows[mCount].Implementations * ImplementationWeight;
      // Kanten zum Fundament zählen bei der Zuordnung nicht (#1365); im Fundament selbst zählen sie.
      mRows[mCount].Counts := not AOverview.Subsystems[mSubsystem].Foundation or
        AOverview.Subsystems[mOwn].Foundation;
      Inc(mCount);
    end;
    Result[mIndex] := AssignmentOf(Copy(mRows, 0, mCount), mOwn, mNames);
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

procedure TAnalysis.FindOutliers;
var
  mAssignment: TOverviewAssignment;
  mRow: TOverviewAssignmentRow;
  Index, Own, Best, Subsystem: Integer;
  Outlier: TOverviewOutlier;
  Parts: TArray<string>;
  Part: string;
  NameOwn: Boolean;
  mBestEdges: Integer;
begin
  for Index := 0 to High(FResult.Units) do
  begin
    Own := FResult.Units[Index].Subsystem;
    // Ausreißer nur unter den übrigen Teilsystemen (#1365): weder aus dem Fundament noch dorthin.
    if IsFoundation(Own) then
    begin
      Continue;
    end;
    mAssignment := FResult.Assignments[Index];
    Outlier := Default(TOverviewOutlier);
    Outlier.Unit_ := Index;
    Outlier.Suggested := -1;
    // Nach Kanten (ungewichtet): ein anderes Teilsystem mit mehr Kanten als das eigene, bei Gleichstand das mit
    // der kleineren Nummer.
    Best := Own;
    mBestEdges := EdgesTo(mAssignment, Own);
    for mRow in mAssignment.Rows do
    begin
      if (mRow.Subsystem <> Own) and not IsFoundation(mRow.Subsystem) and ((mRow.Edges > mBestEdges) or
        ((mRow.Edges = mBestEdges) and (Best <> Own) and (mRow.Subsystem < Best))) then
      begin
        Best := mRow.Subsystem;
        mBestEdges := mRow.Edges;
      end;
    end;
    if Best <> Own then
    begin
      Outlier.Suggested := Best;
      Outlier.Reason := TOverviewOutlierReason.Edges;
    end
    else
    begin
      // Nach Namensraum: Die Unit trägt nicht den Namen ihres Teilsystems, aber den eines anderen. Nur wenn
      // beide Namen aus Namensraum-Abschnitten stammen.
      Parts := TArchitectureAnalyzer.NamespaceParts(FResult.Units[Index].Name);
      NameOwn := False;
      for Part in Parts do
      begin
        if SameText(Part, FPartKey[Own]) then
        begin
          NameOwn := True;
        end;
      end;
      if not NameOwn and FNamedByPart[Own] then
      begin
        for Subsystem := 0 to High(FResult.Subsystems) do
        begin
          if (Subsystem = Own) or not FNamedByPart[Subsystem] or (Length(FResult.Subsystems[Subsystem].Units) < 2) or
            IsFoundation(Subsystem) then
          begin
            Continue;
          end;
          for Part in Parts do
          begin
            if SameText(Part, FPartKey[Subsystem]) and (Outlier.Suggested < 0) then
            begin
              Outlier.Suggested := Subsystem;
              Outlier.Reason := TOverviewOutlierReason.Namespace;
            end;
          end;
        end;
      end;
    end;
    if Outlier.Suggested < 0 then
    begin
      Continue;
    end;
    Outlier.Inside := EdgesTo(mAssignment, Own);
    Outlier.Toward := EdgesTo(mAssignment, Outlier.Suggested);
    FResult.Outliers := FResult.Outliers + [Outlier];
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

procedure TAnalysis.CollectCrossLinks;
var
  Count: Integer;
  Pairs: TArray<TArray<Integer>>;
  Index, From_, To_: Integer;
  GraphEdge: TUsesEdge;
  Edge: TOverviewEdge;
  Link: TOverviewCrossLink;
begin
  Count := Length(FResult.Subsystems);
  SetLength(Pairs, Count);
  for Index := 0 to Count - 1 do
  begin
    SetLength(Pairs[Index], Count);
  end;
  for Edge in FResult.Edges do
  begin
    From_ := FResult.Units[Edge.Source].Subsystem;
    To_ := FResult.Units[Edge.Target].Subsystem;
    if From_ <> To_ then
    begin
      Inc(Pairs[From_][To_]);
    end;
  end;
  // In Quelltextreihenfolge je Unit (Units nach Name), damit die Liste stabil bleibt.
  for Index := 0 to High(FResult.Units) do
  begin
    for GraphEdge in FGraph.Node(FResult.Units[Index].Node).Outgoing do
    begin
      if FUnitOf[GraphEdge.Target] < 0 then
      begin
        Continue;
      end;
      From_ := FResult.Units[Index].Subsystem;
      To_ := FResult.Units[FUnitOf[GraphEdge.Target]].Subsystem;
      // Kanten ins Fundament (#1365) sind gewollt, keine Querverbindung.
      if (From_ = To_) or IsFoundation(From_) or IsFoundation(To_) then
      begin
        Continue;
      end;
      Link := Default(TOverviewCrossLink);
      Link.FromSubsystem := From_;
      Link.ToSubsystem := To_;
      Link.Forward := Pairs[From_][To_];
      Link.Backward := Pairs[To_][From_];
      if Link.Forward + Link.Backward <= TArchitectureAnalyzer.RareLimit then
      begin
        Link.Reason := TOverviewCrossReason.Rare;
      end
      else if Link.Forward < Link.Backward then
      begin
        Link.Reason := TOverviewCrossReason.AgainstDirection;
      end
      else
      begin
        Continue;
      end;
      Edge := Default(TOverviewEdge);
      Edge.Source := Index;
      Edge.Target := FUnitOf[GraphEdge.Target];
      Edge.Section := GraphEdge.Section;
      Locate(Edge, GraphEdge);
      Link.Edge := Edge;
      FResult.CrossLinks := FResult.CrossLinks + [Link];
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

end.
