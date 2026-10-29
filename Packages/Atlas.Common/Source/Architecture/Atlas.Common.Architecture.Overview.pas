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
// - Zyklen aus dem Uses-Graphen (reine interface-Zyklen zuerst), je Kante mit
//   Fundstelle.
// - Querverbindungen: Kanten zwischen zwei Teilsystemen, die selten sind
//   (höchstens zwei Kanten zwischen dem Paar) oder gegen die überwiegende
//   Richtung laufen; mit Fundstelle.
// - Gruppierung einstellbar (architecture.grouping, TArchitectureGrouping):
//   Auflösung γ des Louvain-Verfahrens (#1366), 1 = klassisch.
// - Alles deterministisch: Units nach Name, Teilsysteme nach Größe und Name.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator;

type
  TOverviewUnitRole = (None, Foundation, Hub);

  /// <summary>Einstellungen der Gruppierung in Teilsysteme (architecture.grouping).</summary>
  TArchitectureGrouping = record
  public const
    MinResolution = 0.2;
    MaxResolution = 5.0;
  public
    /// <summary>Auflösung γ des Louvain-Verfahrens (#1366): größer = mehr und kleinere Teilsysteme.</summary>
    Resolution: Double;
    /// <summary>Vorgaben: Auflösung 1 (Verhalten wie vor #1366).</summary>
    class function Default: TArchitectureGrouping; static;
    /// <summary>Werte in ihren Grenzen (Resolution 0,2–5,0).</summary>
    function Clamped: TArchitectureGrouping;
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
    /// <summary>Unit mit diesem Namen (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    function Profile(AUnit: Integer): TOverviewProfile;
    /// <summary>Pfad relativ zu Root mit /, sonst unverändert.</summary>
    function RelativePath(const AFileName: string): string;
    /// <summary>Zahl der uses-Kanten.</summary>
    function EdgeCount: Integer;
  end;

  TArchitectureAnalyzer = class
  public const
    InterfaceWeight = 2;
    ImplementationWeight = 1;
    /// <summary>Höchstens so viele Kanten zwischen zwei Teilsystemen gelten als selten.</summary>
    RareLimit = 2;
    IsolatedName = 'Ohne uses-Beziehung';
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
    if Value = AValue then
      Exit(True);
  Result := False;
end;

{ TArchitectureGrouping }

class function TArchitectureGrouping.Default: TArchitectureGrouping;
begin
  Result.Resolution := 1;
end;

function TArchitectureGrouping.Clamped: TArchitectureGrouping;
begin
  Result := Self;
  if IsNan(Result.Resolution) or (Result.Resolution <= 0) then
    Result.Resolution := 1;
  Result.Resolution := EnsureRange(Result.Resolution, MinResolution, MaxResolution);
end;

function TArchitectureGrouping.Key: string;
begin
  Result := 'r' + FormatFloat('0.####', Clamped.Resolution, TFormatSettings.Invariant);
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
    if SameText(Units[Index].Name, AName) then
      Exit(Index);
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
    RootPath := RootPath + '/';
  if (RootPath <> '') and StartsText(RootPath, FileName) then
    Result := Copy(FileName, Length(RootPath) + 1, MaxInt)
  else
    Result := FileName;
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
      Result.DependsOn := Result.DependsOn + [Edge.Target];
    if (Edge.Target = AUnit) and not ContainsInt(Edge.Source, Result.UsedBy) then
      Result.UsedBy := Result.UsedBy + [Edge.Source];
  end;
  for Index := 0 to High(Cycles) do
    for Member in Cycles[Index].Component do
      if Member = AUnit then
        Result.Cycles := Result.Cycles + [Index];
  for Index := 0 to High(CrossLinks) do
    if (CrossLinks[Index].Edge.Source = AUnit) or (CrossLinks[Index].Edge.Target = AUnit) then
      Result.CrossLinks := Result.CrossLinks + [Index];
  for Index := 0 to High(Outliers) do
    if Outliers[Index].Unit_ = AUnit then
      Result.Outlier := Index;
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
    Exit(nil);
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
    procedure CollectUnits;
    procedure CollectEdges;
    procedure Measure;
    procedure Group;
    procedure NameSubsystems;
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
end;

function TAnalysis.Weight(const AEdge: TOverviewEdge): Integer;
begin
  if AEdge.Section = TUsesSection.Interface_ then
    Result := TArchitectureAnalyzer.InterfaceWeight
  else
    Result := TArchitectureAnalyzer.ImplementationWeight;
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
    FUnitOf[Index] := -1;
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
      for GraphEdge in FGraph.Node(FResult.Units[Index].Node).Outgoing do
      begin
        if FUnitOf[GraphEdge.Target] < 0 then
          Continue;
        Edge := Default(TOverviewEdge);
        Edge.Source := Index;
        Edge.Target := FUnitOf[GraphEdge.Target];
        Edge.Section := GraphEdge.Section;
        Edges.Add(Edge);
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
        Item.Role := TOverviewUnitRole.Foundation
      else if Item.Uses_ >= 3 then
        Item.Role := TOverviewUnitRole.Hub;
    end;
    FResult.Units[Index] := Item;
  end;
  Order := TList<Integer>.Create;
  try
    for Index := 0 to High(FResult.Units) do
      Order.Add(Index);
    Order.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := FResult.Units[ARight].Total - FResult.Units[ALeft].Total;
        if Result = 0 then
          Result := FResult.Units[ARight].Direct - FResult.Units[ALeft].Direct;
        if Result = 0 then
          Result := ALeft - ARight;
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
  // Units ohne Kante bilden bei Louvain je eine eigene Gruppe; sie kommen in eine Sammelgruppe.
  SetLength(Degree, Length(FResult.Units));
  for Edge in FResult.Edges do
  begin
    Inc(Degree[Edge.Source]);
    Inc(Degree[Edge.Target]);
  end;
  Isolated := -1;
  for Index := 0 to High(Communities) do
    if Degree[Index] = 0 then
    begin
      if Isolated < 0 then
        Isolated := Communities[Index];
      Communities[Index] := Isolated;
    end;
  Renumber(Communities);
  if Isolated >= 0 then
    for Index := 0 to High(Communities) do
      if Degree[Index] = 0 then
      begin
        Isolated := Communities[Index];
        Break;
      end;
  Count := 0;
  for Member in Communities do
    Count := Max(Count, Member + 1);
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
    if FResult.Units[Edge.Source].Subsystem = FResult.Units[Edge.Target].Subsystem then
      Inc(FResult.Subsystems[FResult.Units[Edge.Source].Subsystem].InnerEdges)
    else
    begin
      Inc(FResult.Subsystems[FResult.Units[Edge.Source].Subsystem].OuterEdges);
      Inc(FResult.Subsystems[FResult.Units[Edge.Target].Subsystem].OuterEdges);
    end;
  for Index := 0 to High(FResult.Subsystems) do
  begin
    Subsystem := FResult.Subsystems[Index];
    Subsystem.Isolated := Index = Isolated;
    if Subsystem.InnerEdges + Subsystem.OuterEdges > 0 then
      Subsystem.Cohesion := Subsystem.InnerEdges / (Subsystem.InnerEdges + Subsystem.OuterEdges)
    else
      Subsystem.Cohesion := 1;
    // Units nach gesamt abhängig absteigend; die erste ist die zentrale.
    TArray.Sort<Integer>(Subsystem.Units, TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := FResult.Units[ARight].Total - FResult.Units[ALeft].Total;
        if Result = 0 then
          Result := FResult.Units[ARight].Direct - FResult.Units[ALeft].Direct;
        if Result = 0 then
          Result := ALeft - ARight;
      end));
    if Subsystem.Units <> nil then
      Subsystem.Central := Subsystem.Units[0];
    FResult.Subsystems[Index] := Subsystem;
  end;
end;

/// <summary>Bester Namensraum-Abschnitt einer Gruppe: Häufigkeit in der Gruppe mal log(Units / Häufigkeit im
/// Projekt); '' ohne Abschnitt mit Gewinn.</summary>
function BestPart(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>; const AGlobal:
  TDictionary<string, Integer>; ATotal: Integer; out AScore: Double): string;
var
  Local: TDictionary<string, Integer>;
  Member, Count, Global_: Integer;
  Part, Key: string;
  Seen: TArray<string>;
  Keys: TArray<string>;
  Score: Double;
begin
  Result := '';
  AScore := 0;
  Local := TDictionary<string, Integer>.Create;
  try
    for Member in AMembers do
    begin
      // Jeder Abschnitt zählt je Unit einmal.
      Seen := nil;
      for Part in AParts[Member] do
      begin
        Key := LowerCase(Part);
        if IndexStr(Key, Seen) >= 0 then
          Continue;
        Seen := Seen + [Key];
        if not Local.TryGetValue(Key, Count) then
          Count := 0;
        Local.AddOrSetValue(Key, Count + 1);
      end;
    end;
    Keys := Local.Keys.ToArray;
    TArray.Sort<string>(Keys);
    for Key in Keys do
    begin
      if not AGlobal.TryGetValue(Key, Global_) or (Global_ <= 0) then
        Continue;
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
    for Part in AParts[Member] do
      if SameText(Part, AKey) then
        Exit(Part);
  Result := AKey;
end;

procedure TAnalysis.NameSubsystems;
var
  Parts: TArray<TArray<string>>;
  Global_: TDictionary<string, Integer>;
  Index, Count, Suffix, Other: Integer;
  Part, Key, Name: string;
  Seen: TArray<string>;
  Score: Double;
  Taken: Boolean;
begin
  SetLength(FNamedByPart, Length(FResult.Subsystems));
  SetLength(FPartKey, Length(FResult.Subsystems));
  SetLength(Parts, Length(FResult.Units));
  Global_ := TDictionary<string, Integer>.Create;
  try
    for Index := 0 to High(FResult.Units) do
    begin
      Parts[Index] := TArchitectureAnalyzer.NamespaceParts(FResult.Units[Index].Name);
      Seen := nil;
      for Part in Parts[Index] do
      begin
        Key := LowerCase(Part);
        if IndexStr(Key, Seen) >= 0 then
          Continue;
        Seen := Seen + [Key];
        if not Global_.TryGetValue(Key, Count) then
          Count := 0;
        Global_.AddOrSetValue(Key, Count + 1);
      end;
    end;
    for Index := 0 to High(FResult.Subsystems) do
    begin
      if FResult.Subsystems[Index].Isolated then
        Key := ''
      else
        Key := BestPart(Parts, FResult.Subsystems[Index].Units, Global_, Length(FResult.Units), Score);
      FNamedByPart[Index] := Key <> '';
      FPartKey[Index] := Key;
      if FResult.Subsystems[Index].Isolated then
        Name := TArchitectureAnalyzer.IsolatedName
      else if Key <> '' then
        Name := PartCaption(Parts, FResult.Subsystems[Index].Units, Key)
      else if FResult.Subsystems[Index].Central >= 0 then
        Name := FResult.Units[FResult.Subsystems[Index].Central].Name
      else
        Name := '';
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
        if SameText(FResult.Subsystems[Other].Name, Name) then
          Taken := True;
      if Taken then
      begin
        Inc(Suffix);
        Name := FResult.Subsystems[Index].Name + ' ' + IntToStr(Suffix);
      end;
    until not Taken;
    FResult.Subsystems[Index].Name := Name;
  end;
end;

procedure TAnalysis.FindOutliers;
var
  Links: TArray<TArray<Integer>>;
  Edge: TOverviewEdge;
  Index, Own, Best, Subsystem: Integer;
  Outlier: TOverviewOutlier;
  Parts: TArray<string>;
  Part: string;
  NameOwn: Boolean;
begin
  // Kantengewichte je Unit und Teilsystem (ungerichtet).
  SetLength(Links, Length(FResult.Units));
  for Index := 0 to High(Links) do
    SetLength(Links[Index], Length(FResult.Subsystems));
  for Edge in FResult.Edges do
  begin
    Inc(Links[Edge.Source][FResult.Units[Edge.Target].Subsystem]);
    Inc(Links[Edge.Target][FResult.Units[Edge.Source].Subsystem]);
  end;
  for Index := 0 to High(FResult.Units) do
  begin
    Own := FResult.Units[Index].Subsystem;
    Outlier := Default(TOverviewOutlier);
    Outlier.Unit_ := Index;
    Outlier.Suggested := -1;
    // Nach Kanten: ein anderes Teilsystem mit mehr Kanten als das eigene.
    Best := Own;
    for Subsystem := 0 to High(FResult.Subsystems) do
      if (Subsystem <> Own) and (Links[Index][Subsystem] > Links[Index][Best]) then
        Best := Subsystem;
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
        if SameText(Part, FPartKey[Own]) then
          NameOwn := True;
      if not NameOwn and FNamedByPart[Own] then
        for Subsystem := 0 to High(FResult.Subsystems) do
        begin
          if (Subsystem = Own) or not FNamedByPart[Subsystem] or (Length(FResult.Subsystems[Subsystem].Units) < 2) then
            Continue;
          for Part in Parts do
            if SameText(Part, FPartKey[Subsystem]) and (Outlier.Suggested < 0) then
            begin
              Outlier.Suggested := Subsystem;
              Outlier.Reason := TOverviewOutlierReason.Namespace;
            end;
        end;
    end;
    if Outlier.Suggested < 0 then
      Continue;
    Outlier.Inside := Links[Index][Own];
    Outlier.Toward := Links[Index][Outlier.Suggested];
    FResult.Outliers := FResult.Outliers + [Outlier];
  end;
end;

function TAnalysis.Locate(var AEdge: TOverviewEdge; const AGraphEdge: TUsesEdge): Boolean;
begin
  Result := False;
  if FLocator = nil then
    Exit;
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
      Item.Units := Item.Units + [FUnitOf[Node]];
    for Node in Cycle.Component do
      Item.Component := Item.Component + [FUnitOf[Node]];
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
    SetLength(Pairs[Index], Count);
  for Edge in FResult.Edges do
  begin
    From_ := FResult.Units[Edge.Source].Subsystem;
    To_ := FResult.Units[Edge.Target].Subsystem;
    if From_ <> To_ then
      Inc(Pairs[From_][To_]);
  end;
  // In Quelltextreihenfolge je Unit (Units nach Name), damit die Liste stabil bleibt.
  for Index := 0 to High(FResult.Units) do
    for GraphEdge in FGraph.Node(FResult.Units[Index].Node).Outgoing do
    begin
      if FUnitOf[GraphEdge.Target] < 0 then
        Continue;
      From_ := FResult.Units[Index].Subsystem;
      To_ := FResult.Units[FUnitOf[GraphEdge.Target]].Subsystem;
      if From_ = To_ then
        Continue;
      Link := Default(TOverviewCrossLink);
      Link.FromSubsystem := From_;
      Link.ToSubsystem := To_;
      Link.Forward := Pairs[From_][To_];
      Link.Backward := Pairs[To_][From_];
      if Link.Forward + Link.Backward <= TArchitectureAnalyzer.RareLimit then
        Link.Reason := TOverviewCrossReason.Rare
      else if Link.Forward < Link.Backward then
        Link.Reason := TOverviewCrossReason.AgainstDirection
      else
        Continue;
      Edge := Default(TOverviewEdge);
      Edge.Source := Index;
      Edge.Target := FUnitOf[GraphEdge.Target];
      Edge.Section := GraphEdge.Section;
      Locate(Edge, GraphEdge);
      Link.Edge := Edge;
      FResult.CrossLinks := FResult.CrossLinks + [Link];
    end;
end;

procedure TAnalysis.SortSubsystems;
var
  Order, Map: TArray<Integer>;
  Sorted: TArray<TOverviewSubsystem>;
  Index: Integer;
begin
  // Größte zuerst, bei Gleichstand nach dem Namen der zentralen Unit (Namen entstehen erst danach); die
  // Sammelgruppe ohne uses-Beziehung zuletzt.
  SetLength(Order, Length(FResult.Subsystems));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := Ord(FResult.Subsystems[ALeft].Isolated) - Ord(FResult.Subsystems[ARight].Isolated);
      if Result = 0 then
        Result := Length(FResult.Subsystems[ARight].Units) - Length(FResult.Subsystems[ALeft].Units);
      if Result = 0 then
        Result := CompareText(FResult.Units[FResult.Subsystems[ALeft].Central].Name,
          FResult.Units[FResult.Subsystems[ARight].Central].Name);
      if Result = 0 then
        Result := ALeft - ARight;
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
    FResult.Units[Index].Subsystem := Map[FResult.Units[Index].Subsystem];
end;

function TAnalysis.Run(ACentralCount: Integer): TArchitectureOverview;
begin
  FResult := Default(TArchitectureOverview);
  FResult.Grouping := FGrouping;
  CollectUnits;
  CollectEdges;
  Measure;
  Group;
  SortSubsystems;
  NameSubsystems;
  FindOutliers;
  CollectCycles;
  CollectCrossLinks;
  if Length(FResult.Central) > ACentralCount then
    SetLength(FResult.Central, ACentralCount);
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
