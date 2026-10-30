unit Atlas.Common.Architecture.Snapshot;

// Gespeicherter Stand der Architekturübersicht (#1121) für den Vergleich
// zweier Stände: AtlasServer --architecture <Datei.json>, „Stand speichern …“
// im Fenster und architecture.baseline.
//
// Der Stand nennt Units und Teilsysteme beim Namen statt bei der Nummer, damit
// ein Vergleich nicht an einer neuen Nummerierung hängt. Er ist stabil
// sortiert (Units, Kanten, Ausreißer und Querverbindungen nach Namen, Units
// eines Teilsystems nach Namen, Zyklen nach Art und Units; zentrale Units in
// ihrer Rangfolge) und enthält weder Zeit noch Rechendauer, Index-Generation
// oder absolute Pfade: Bei gleichem Stand ist die Datei byteweise gleich
// (UTF-8 ohne BOM, Zeilenende LF, eine Unit bzw. Kante je Zeile für den Diff
// der Versionsverwaltung).
//
// Format 2 (dieses):
//   {"format": 2, "kind": "atlas.architecture", "title": "Projekt",
//    "scope": "projectGroup", "includeLibrary": false, "excludes": ["Tests/**"],
//    "grouping": {"resolution": 1},
//    "summary": {"units": 3, "edges": 2, "subsystems": 1, "cycles": 0,
//                "interfaceCycles": 0, "crossLinks": 0, "outliers": 0},
//    "units": [{"name": "A", "file": "Source/A.pas", "subsystem": "Kern",
//               "direct": 1, "total": 2, "uses": 0, "role": "foundation",
//               "library": false}],
//    "edges": [["A", "B", "interface"]],
//    "central": ["A"],
//    "subsystems": [{"name": "Kern", "units": ["A", "B"], "central": "A",
//                    "inner": 2, "outer": 0, "cohesion": 1, "isolated": false,
//                    "foundation": true, "parent": "Common", "color": 0, "shade": 0}],
//                   ("foundation" nur am Teilsystem „Fundament“, #1365; "parent" nur bei
//                    nachgeteilten Teilsystemen, #1364; "color"/"shade" Farbe der Karte für
//                    die Angleichung, #1367, fehlen in älteren Ständen)
//    "outliers": [{"unit": "C", "suggested": "Kern", "reason": "namespace"}],
//    "cycles": [{"interfaceOnly": true, "units": ["A", "B"],
//                "edges": [["A", "B", "interface"], ["B", "A", "interface"]]}],
//    "crossLinks": [{"source": "A", "target": "C", "section": "implementation",
//                    "from": "Kern", "to": "UI", "reason": "rare",
//                    "forward": 1, "backward": 0}]}
// Format 1 (die Daten aus TArchitectureReport.Json mit Nummern statt Namen,
// z. B. aus atlas/architecture) liest Parse ebenfalls; jedes andere Format
// lehnt es mit einer Meldung ab. Ohne "grouping" (Stände vor #1366) gelten die
// Vorgaben der Gruppierung.

interface

uses
  Atlas.Common.Architecture.Overview;

type
  TSnapshotUnit = record
    Name: string;
    /// <summary>Pfad relativ zum Projekt mit /.</summary>
    FileName: string;
    /// <summary>Name des Teilsystems.</summary>
    Subsystem: string;
    Direct: Integer;
    Total: Integer;
    Uses_: Integer;
    /// <summary>"foundation", "hub" oder ''.</summary>
    Role: string;
    Library_: Boolean;
  end;

  TSnapshotEdge = record
    Source: string;
    Target: string;
    Interface_: Boolean;
    /// <summary>Quelle und Ziel ohne Groß-/Kleinschreibung; der Abschnitt zählt nicht.</summary>
    function Key: string;
  end;

  TSnapshotSubsystem = record
    Name: string;
    Units: TArray<string>;
    Central: string;
    Inner: Integer;
    Outer: Integer;
    Cohesion: Double;
    Isolated: Boolean;
    /// <summary>Ursprüngliches Teilsystem bei Nachteilung (#1364); '' sonst und in älteren Ständen.</summary>
    Parent: string;
    /// <summary>Teilsystem „Fundament“ (#1365); False in älteren Ständen.</summary>
    Foundation: Boolean;
    /// <summary>Farbe und Farbton der Karte (#1367, TOverviewSubsystem.ColorSlot/Shade); nur mit HasColor.</summary>
    ColorSlot: Integer;
    Shade: Integer;
    /// <summary>False in Ständen vor #1367 (ohne "color"): Die Angleichung vergibt dann neue Farben.</summary>
    HasColor: Boolean;
  end;

  TSnapshotOutlier = record
    Unit_: string;
    Suggested: string;
    /// <summary>"namespace" oder "edges".</summary>
    Reason: string;
  end;

  TSnapshotCycle = record
    InterfaceOnly: Boolean;
    /// <summary>Units in der Reihenfolge des Rundwegs.</summary>
    Units: TArray<string>;
    Edges: TArray<TSnapshotEdge>;
    /// <summary>Die Units sortiert und ohne Groß-/Kleinschreibung: derselbe Zyklus hat denselben Schlüssel, gleich
    /// wo der Rundweg beginnt.</summary>
    function Key: string;
  end;

  TSnapshotCrossLink = record
    Edge: TSnapshotEdge;
    FromSubsystem: string;
    ToSubsystem: string;
    /// <summary>"rare" oder "againstDirection".</summary>
    Reason: string;
    Forward: Integer;
    Backward: Integer;
  end;

  TArchitectureSnapshot = record
    /// <summary>Formatversion der gelesenen Datei (1 oder 2); FromOverview setzt 2.</summary>
    FormatVersion: Integer;
    Title: string;
    Scope: string;
    IncludeLibrary: Boolean;
    Excludes: TArray<string>;
    /// <summary>Einstellungen der Gruppierung, mit denen der Stand entstand (#1366).</summary>
    Grouping: TArchitectureGrouping;
    Units: TArray<TSnapshotUnit>;
    Edges: TArray<TSnapshotEdge>;
    /// <summary>Zentrale Units, die zentralste zuerst.</summary>
    Central: TArray<string>;
    Subsystems: TArray<TSnapshotSubsystem>;
    Outliers: TArray<TSnapshotOutlier>;
    Cycles: TArray<TSnapshotCycle>;
    CrossLinks: TArray<TSnapshotCrossLink>;
    /// <summary>Unit mit diesem Namen (ohne Groß-/Kleinschreibung), -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    function InterfaceCycleCount: Integer;
  end;

  TArchitectureSnapshots = class
  public const
    FormatVersion = 2;
    Kind = 'atlas.architecture';
  public
    /// <summary>Stand der Übersicht; Pfade relativ zu ihrem Root, sortiert wie im Kopf der Unit.</summary>
    class function FromOverview(const AOverview: TArchitectureOverview): TArchitectureSnapshot; static;
    /// <summary>Datei im Format 2 (siehe Kopf der Unit); bei gleichem Stand gleicher Text.</summary>
    class function Json(const ASnapshot: TArchitectureSnapshot): string; static;
    /// <summary>Stand aus Format 2 oder 1 lesen und sortieren. False mit AError bei kaputtem JSON, fremdem
    /// Inhalt oder anderem Format.</summary>
    class function Parse(const AText: string; out ASnapshot: TArchitectureSnapshot; out AError: string): Boolean;
      static;
    /// <summary>Wie Parse aus einer Datei (UTF-8, mit oder ohne BOM); AError nennt die Datei.</summary>
    class function Load(const AFileName: string; out ASnapshot: TArchitectureSnapshot; out AError: string): Boolean;
      static;
    /// <summary>Json nach AFileName (UTF-8 ohne BOM); legt den Ordner an.</summary>
    class procedure Save(const AFileName: string; const ASnapshot: TArchitectureSnapshot); static;
    /// <summary>Sortiert wie im Kopf der Unit (Parse und FromOverview rufen es).</summary>
    class procedure Normalize(var ASnapshot: TArchitectureSnapshot); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Metrics.Report;

const
  LineBreak = #10;

function CompareNames(const ALeft, ARight: string): Integer;
begin
  Result := CompareText(ALeft, ARight);
  if Result = 0 then
    Result := CompareStr(ALeft, ARight);
end;

function SectionText(AInterface: Boolean): string;
begin
  if AInterface then
    Result := 'interface'
  else
    Result := 'implementation';
end;

function RoleText(ARole: TOverviewUnitRole): string;
begin
  case ARole of
    TOverviewUnitRole.Foundation:
      Result := 'foundation';
    TOverviewUnitRole.Hub:
      Result := 'hub';
  else
    Result := '';
  end;
end;

{ TSnapshotEdge }

function TSnapshotEdge.Key: string;
begin
  Result := LowerCase(Source) + #1 + LowerCase(Target);
end;

{ TSnapshotCycle }

function TSnapshotCycle.Key: string;
var
  Names: TArray<string>;
  Index: Integer;
begin
  SetLength(Names, Length(Units));
  for Index := 0 to High(Units) do
    Names[Index] := LowerCase(Units[Index]);
  TArray.Sort<string>(Names);
  Result := string.Join(#1, Names);
end;

{ TArchitectureSnapshot }

function TArchitectureSnapshot.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Units) do
    if SameText(Units[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TArchitectureSnapshot.InterfaceCycleCount: Integer;
var
  Cycle: TSnapshotCycle;
begin
  Result := 0;
  for Cycle in Cycles do
    if Cycle.InterfaceOnly then
      Inc(Result);
end;

{ TArchitectureSnapshots }

function EdgeOf(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): TSnapshotEdge;
begin
  Result.Source := AOverview.Units[AEdge.Source].Name;
  Result.Target := AOverview.Units[AEdge.Target].Name;
  Result.Interface_ := AEdge.Section = TUsesSection.Interface_;
end;

function SubsystemOf(const AOverview: TArchitectureOverview; ASubsystem: Integer): string;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(AOverview.Subsystems)) then
    Result := AOverview.Subsystems[ASubsystem].Name
  else
    Result := '';
end;

class function TArchitectureSnapshots.FromOverview(const AOverview: TArchitectureOverview): TArchitectureSnapshot;
var
  Index, Member: Integer;
  Item: TOverviewUnit;
  Subsystem: TOverviewSubsystem;
  Cycle: TOverviewCycle;
  Edge: TOverviewEdge;
  Link: TOverviewCrossLink;
begin
  Result := Default(TArchitectureSnapshot);
  Result.FormatVersion := FormatVersion;
  Result.Title := AOverview.Title;
  Result.Scope := AOverview.Scope;
  Result.IncludeLibrary := AOverview.IncludeLibrary;
  Result.Excludes := Copy(AOverview.Excludes);
  Result.Grouping := AOverview.Grouping.Clamped;
  SetLength(Result.Units, Length(AOverview.Units));
  for Index := 0 to High(AOverview.Units) do
  begin
    Item := AOverview.Units[Index];
    Result.Units[Index].Name := Item.Name;
    Result.Units[Index].FileName := AOverview.RelativePath(Item.FileName);
    Result.Units[Index].Subsystem := SubsystemOf(AOverview, Item.Subsystem);
    Result.Units[Index].Direct := Item.Direct;
    Result.Units[Index].Total := Item.Total;
    Result.Units[Index].Uses_ := Item.Uses_;
    Result.Units[Index].Role := RoleText(Item.Role);
    Result.Units[Index].Library_ := Item.Library_;
  end;
  SetLength(Result.Edges, Length(AOverview.Edges));
  for Index := 0 to High(AOverview.Edges) do
    Result.Edges[Index] := EdgeOf(AOverview, AOverview.Edges[Index]);
  SetLength(Result.Central, Length(AOverview.Central));
  for Index := 0 to High(AOverview.Central) do
    Result.Central[Index] := AOverview.Units[AOverview.Central[Index]].Name;
  SetLength(Result.Subsystems, Length(AOverview.Subsystems));
  for Index := 0 to High(AOverview.Subsystems) do
  begin
    Subsystem := AOverview.Subsystems[Index];
    Result.Subsystems[Index].Name := Subsystem.Name;
    for Member in Subsystem.Units do
      Result.Subsystems[Index].Units := Result.Subsystems[Index].Units + [AOverview.Units[Member].Name];
    if Subsystem.Central >= 0 then
      Result.Subsystems[Index].Central := AOverview.Units[Subsystem.Central].Name;
    Result.Subsystems[Index].Inner := Subsystem.InnerEdges;
    Result.Subsystems[Index].Outer := Subsystem.OuterEdges;
    Result.Subsystems[Index].Cohesion := Subsystem.Cohesion;
    Result.Subsystems[Index].Isolated := Subsystem.Isolated;
    Result.Subsystems[Index].Parent := Subsystem.Parent;
    Result.Subsystems[Index].Foundation := Subsystem.Foundation;
    Result.Subsystems[Index].ColorSlot := Subsystem.ColorSlot;
    Result.Subsystems[Index].Shade := Subsystem.Shade;
    Result.Subsystems[Index].HasColor := True;
  end;
  SetLength(Result.Outliers, Length(AOverview.Outliers));
  for Index := 0 to High(AOverview.Outliers) do
  begin
    Result.Outliers[Index].Unit_ := AOverview.Units[AOverview.Outliers[Index].Unit_].Name;
    Result.Outliers[Index].Suggested := SubsystemOf(AOverview, AOverview.Outliers[Index].Suggested);
    if AOverview.Outliers[Index].Reason = TOverviewOutlierReason.Namespace then
      Result.Outliers[Index].Reason := 'namespace'
    else
      Result.Outliers[Index].Reason := 'edges';
  end;
  SetLength(Result.Cycles, Length(AOverview.Cycles));
  for Index := 0 to High(AOverview.Cycles) do
  begin
    Cycle := AOverview.Cycles[Index];
    Result.Cycles[Index].InterfaceOnly := Cycle.InterfaceOnly;
    for Member in Cycle.Units do
      Result.Cycles[Index].Units := Result.Cycles[Index].Units + [AOverview.Units[Member].Name];
    for Edge in Cycle.Edges do
      Result.Cycles[Index].Edges := Result.Cycles[Index].Edges + [EdgeOf(AOverview, Edge)];
  end;
  SetLength(Result.CrossLinks, Length(AOverview.CrossLinks));
  for Index := 0 to High(AOverview.CrossLinks) do
  begin
    Link := AOverview.CrossLinks[Index];
    Result.CrossLinks[Index].Edge := EdgeOf(AOverview, Link.Edge);
    Result.CrossLinks[Index].FromSubsystem := SubsystemOf(AOverview, Link.FromSubsystem);
    Result.CrossLinks[Index].ToSubsystem := SubsystemOf(AOverview, Link.ToSubsystem);
    if Link.Reason = TOverviewCrossReason.Rare then
      Result.CrossLinks[Index].Reason := 'rare'
    else
      Result.CrossLinks[Index].Reason := 'againstDirection';
    Result.CrossLinks[Index].Forward := Link.Forward;
    Result.CrossLinks[Index].Backward := Link.Backward;
  end;
  Normalize(Result);
end;

function CompareEdges(const ALeft, ARight: TSnapshotEdge): Integer;
begin
  Result := CompareNames(ALeft.Source, ARight.Source);
  if Result = 0 then
    Result := CompareNames(ALeft.Target, ARight.Target);
  // interface vor implementation.
  if Result = 0 then
    Result := Ord(ARight.Interface_) - Ord(ALeft.Interface_);
end;

function CompareCycles(const ALeft, ARight: TSnapshotCycle): Integer;
begin
  // Reine interface-Zyklen zuerst wie in der Übersicht.
  Result := Ord(ARight.InterfaceOnly) - Ord(ALeft.InterfaceOnly);
  if Result = 0 then
    Result := CompareStr(ALeft.Key, ARight.Key);
  if Result = 0 then
    Result := CompareStr(string.Join(#1, ALeft.Units), string.Join(#1, ARight.Units));
end;

class procedure TArchitectureSnapshots.Normalize(var ASnapshot: TArchitectureSnapshot);
var
  Index: Integer;
begin
  TArray.Sort<TSnapshotUnit>(ASnapshot.Units, TComparer<TSnapshotUnit>.Construct(
    function(const ALeft, ARight: TSnapshotUnit): Integer
    begin
      Result := CompareNames(ALeft.Name, ARight.Name);
    end));
  TArray.Sort<TSnapshotEdge>(ASnapshot.Edges, TComparer<TSnapshotEdge>.Construct(
    function(const ALeft, ARight: TSnapshotEdge): Integer
    begin
      Result := CompareEdges(ALeft, ARight);
    end));
  for Index := 0 to High(ASnapshot.Subsystems) do
    TArray.Sort<string>(ASnapshot.Subsystems[Index].Units, TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareNames(ALeft, ARight);
      end));
  TArray.Sort<TSnapshotOutlier>(ASnapshot.Outliers, TComparer<TSnapshotOutlier>.Construct(
    function(const ALeft, ARight: TSnapshotOutlier): Integer
    begin
      Result := CompareNames(ALeft.Unit_, ARight.Unit_);
    end));
  TArray.Sort<TSnapshotCycle>(ASnapshot.Cycles, TComparer<TSnapshotCycle>.Construct(
    function(const ALeft, ARight: TSnapshotCycle): Integer
    begin
      Result := CompareCycles(ALeft, ARight);
    end));
  TArray.Sort<TSnapshotCrossLink>(ASnapshot.CrossLinks, TComparer<TSnapshotCrossLink>.Construct(
    function(const ALeft, ARight: TSnapshotCrossLink): Integer
    begin
      Result := CompareEdges(ALeft.Edge, ARight.Edge);
    end));
end;

function Text(const AValue: string): string;
begin
  Result := TMetricsReport.JsonString(AValue);
end;

function Bool(AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

function Number(AValue: Double): string;
begin
  Result := FormatFloat('0.###', AValue, TFormatSettings.Invariant);
end;

function Names(const AValues: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(AValues) do
  begin
    if Index > 0 then
      Result := Result + ', ';
    Result := Result + Text(AValues[Index]);
  end;
  Result := Result + ']';
end;

function EdgeJson(const AEdge: TSnapshotEdge): string;
begin
  Result := '[' + Text(AEdge.Source) + ', ' + Text(AEdge.Target) + ', ' + Text(SectionText(AEdge.Interface_)) + ']';
end;

class function TArchitectureSnapshots.Json(const ASnapshot: TArchitectureSnapshot): string;
var
  Builder: TStringBuilder;
  Index, Inner: Integer;
  Item: TSnapshotUnit;
  Subsystem: TSnapshotSubsystem;
  Cycle: TSnapshotCycle;
  Link: TSnapshotCrossLink;

  procedure Separate(AIndex: Integer);
  begin
    if AIndex > 0 then
      Builder.Append(',');
    Builder.Append(LineBreak).Append('  ');
  end;

begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{').Append(LineBreak)
      .Append('"format": ').Append(FormatVersion).Append(',').Append(LineBreak)
      .Append('"kind": ').Append(Text(Kind)).Append(',').Append(LineBreak)
      .Append('"title": ').Append(Text(ASnapshot.Title)).Append(',').Append(LineBreak)
      .Append('"scope": ').Append(Text(ASnapshot.Scope)).Append(',').Append(LineBreak)
      .Append('"includeLibrary": ').Append(Bool(ASnapshot.IncludeLibrary)).Append(',').Append(LineBreak)
      .Append('"excludes": ').Append(Names(ASnapshot.Excludes)).Append(',').Append(LineBreak)
      .Append('"grouping": {"resolution": ').Append(Number(ASnapshot.Grouping.Clamped.Resolution)).Append('},')
      .Append(LineBreak)
      .Append('"summary": {"units": ').Append(Length(ASnapshot.Units))
      .Append(', "edges": ').Append(Length(ASnapshot.Edges))
      .Append(', "subsystems": ').Append(Length(ASnapshot.Subsystems))
      .Append(', "cycles": ').Append(Length(ASnapshot.Cycles))
      .Append(', "interfaceCycles": ').Append(ASnapshot.InterfaceCycleCount)
      .Append(', "crossLinks": ').Append(Length(ASnapshot.CrossLinks))
      .Append(', "outliers": ').Append(Length(ASnapshot.Outliers)).Append('},').Append(LineBreak);
    Builder.Append('"units": [');
    for Index := 0 to High(ASnapshot.Units) do
    begin
      Item := ASnapshot.Units[Index];
      Separate(Index);
      Builder.Append('{"name": ').Append(Text(Item.Name))
        .Append(', "file": ').Append(Text(Item.FileName))
        .Append(', "subsystem": ').Append(Text(Item.Subsystem))
        .Append(', "direct": ').Append(Item.Direct)
        .Append(', "total": ').Append(Item.Total)
        .Append(', "uses": ').Append(Item.Uses_)
        .Append(', "role": ').Append(Text(Item.Role))
        .Append(', "library": ').Append(Bool(Item.Library_)).Append('}');
    end;
    Builder.Append(LineBreak).Append('],').Append(LineBreak).Append('"edges": [');
    for Index := 0 to High(ASnapshot.Edges) do
    begin
      Separate(Index);
      Builder.Append(EdgeJson(ASnapshot.Edges[Index]));
    end;
    Builder.Append(LineBreak).Append('],').Append(LineBreak)
      .Append('"central": ').Append(Names(ASnapshot.Central)).Append(',').Append(LineBreak)
      .Append('"subsystems": [');
    for Index := 0 to High(ASnapshot.Subsystems) do
    begin
      Subsystem := ASnapshot.Subsystems[Index];
      Separate(Index);
      Builder.Append('{"name": ').Append(Text(Subsystem.Name))
        .Append(', "units": ').Append(Names(Subsystem.Units))
        .Append(', "central": ').Append(Text(Subsystem.Central))
        .Append(', "inner": ').Append(Subsystem.Inner)
        .Append(', "outer": ').Append(Subsystem.Outer)
        .Append(', "cohesion": ').Append(Number(Subsystem.Cohesion))
        .Append(', "isolated": ').Append(Bool(Subsystem.Isolated));
      // Nur bei nachgeteilten Teilsystemen: Stände ohne Nachteilung bleiben wie vor #1364.
      if Subsystem.Foundation then
        Builder.Append(', "foundation": true');
      if Subsystem.Parent <> '' then
        Builder.Append(', "parent": ').Append(Text(Subsystem.Parent));
      // Farbe für die Angleichung (#1367); ältere Stände ohne sie liest Parse weiter.
      if Subsystem.HasColor then
        Builder.Append(', "color": ').Append(Subsystem.ColorSlot).Append(', "shade": ').Append(Subsystem.Shade);
      Builder.Append('}');
    end;
    Builder.Append(LineBreak).Append('],').Append(LineBreak).Append('"outliers": [');
    for Index := 0 to High(ASnapshot.Outliers) do
    begin
      Separate(Index);
      Builder.Append('{"unit": ').Append(Text(ASnapshot.Outliers[Index].Unit_))
        .Append(', "suggested": ').Append(Text(ASnapshot.Outliers[Index].Suggested))
        .Append(', "reason": ').Append(Text(ASnapshot.Outliers[Index].Reason)).Append('}');
    end;
    Builder.Append(LineBreak).Append('],').Append(LineBreak).Append('"cycles": [');
    for Index := 0 to High(ASnapshot.Cycles) do
    begin
      Cycle := ASnapshot.Cycles[Index];
      Separate(Index);
      Builder.Append('{"interfaceOnly": ').Append(Bool(Cycle.InterfaceOnly))
        .Append(', "units": ').Append(Names(Cycle.Units))
        .Append(', "edges": [');
      for Inner := 0 to High(Cycle.Edges) do
      begin
        if Inner > 0 then
          Builder.Append(', ');
        Builder.Append(EdgeJson(Cycle.Edges[Inner]));
      end;
      Builder.Append(']}');
    end;
    Builder.Append(LineBreak).Append('],').Append(LineBreak).Append('"crossLinks": [');
    for Index := 0 to High(ASnapshot.CrossLinks) do
    begin
      Link := ASnapshot.CrossLinks[Index];
      Separate(Index);
      Builder.Append('{"source": ').Append(Text(Link.Edge.Source))
        .Append(', "target": ').Append(Text(Link.Edge.Target))
        .Append(', "section": ').Append(Text(SectionText(Link.Edge.Interface_)))
        .Append(', "from": ').Append(Text(Link.FromSubsystem))
        .Append(', "to": ').Append(Text(Link.ToSubsystem))
        .Append(', "reason": ').Append(Text(Link.Reason))
        .Append(', "forward": ').Append(Link.Forward)
        .Append(', "backward": ').Append(Link.Backward).Append('}');
    end;
    Builder.Append(LineBreak).Append(']').Append(LineBreak).Append('}').Append(LineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

type
  /// <summary>Lesen eines Stands; Fehler als EArchitectureSnapshot mit verständlicher Meldung.</summary>
  EArchitectureSnapshot = class(Exception);

  TSnapshotReader = class
  private
    FData: TJSONObject;
    FFormat: Integer;
    FUnitNames: TArray<string>;
    FSubsystemNames: TArray<string>;
    procedure Fail(const AText: string);
    function Field(AObject: TJSONObject; const AName: string): TJSONValue;
    function TextOf(AObject: TJSONObject; const AName: string): string;
    function IntOf(AObject: TJSONObject; const AName: string): Integer;
    function FloatOf(AObject: TJSONObject; const AName: string): Double;
    function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
    function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
    function ObjectAt(AItems: TJSONArray; AIndex: Integer; const AWhat: string): TJSONObject;
    /// <summary>Name einer Unit: Format 2 der Text, Format 1 die Nummer in "units".</summary>
    function UnitName(AValue: TJSONValue; const AWhat: string): string;
    function SubsystemName(AValue: TJSONValue; const AWhat: string): string;
    function UnitNames(AItems: TJSONArray; const AWhat: string): TArray<string>;
    /// <summary>Kante als Array [Quelle, Ziel, Abschnitt] (Format 1: Abschnitt "i"/"m") oder als Objekt mit
    /// "source", "target", "section".</summary>
    function EdgeOf(AValue: TJSONValue; const AWhat: string): TSnapshotEdge;
  public
    constructor Create(AData: TJSONObject; AFormat: Integer);
    function Read: TArchitectureSnapshot;
  end;

constructor TSnapshotReader.Create(AData: TJSONObject; AFormat: Integer);
begin
  inherited Create;
  FData := AData;
  FFormat := AFormat;
end;

procedure TSnapshotReader.Fail(const AText: string);
begin
  raise EArchitectureSnapshot.Create('Architekturstand ist beschädigt: ' + AText);
end;

function TSnapshotReader.Field(AObject: TJSONObject; const AName: string): TJSONValue;
begin
  Result := nil;
  if AObject <> nil then
    Result := AObject.GetValue(AName);
end;

function TSnapshotReader.TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := Field(AObject, AName);
  if (Value is TJSONString) and not (Value is TJSONNumber) then
    Result := Value.Value
  else
    Result := '';
end;

function TSnapshotReader.IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Value := Field(AObject, AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else
    Result := 0;
end;

function TSnapshotReader.FloatOf(AObject: TJSONObject; const AName: string): Double;
var
  Value: TJSONValue;
begin
  Value := Field(AObject, AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsDouble
  else
    Result := 0;
end;

function TSnapshotReader.FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Field(AObject, AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function TSnapshotReader.ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Value := Field(AObject, AName);
  if Value = nil then
    Exit(nil);
  if not (Value is TJSONArray) then
    Fail('"' + AName + '" ist keine Liste');
  Result := TJSONArray(Value);
end;

function TSnapshotReader.ObjectAt(AItems: TJSONArray; AIndex: Integer; const AWhat: string): TJSONObject;
begin
  if not (AItems.Items[AIndex] is TJSONObject) then
    Fail(AWhat + ' ' + IntToStr(AIndex + 1) + ' ist kein Objekt');
  Result := TJSONObject(AItems.Items[AIndex]);
end;

function TSnapshotReader.UnitName(AValue: TJSONValue; const AWhat: string): string;
var
  Number: Integer;
begin
  if FFormat = 1 then
  begin
    if not (AValue is TJSONNumber) then
      Fail(AWhat + ': Nummer einer Unit erwartet');
    Number := TJSONNumber(AValue).AsInt;
    if (Number < 0) or (Number > High(FUnitNames)) then
      Fail(AWhat + ': Unit ' + IntToStr(Number) + ' fehlt');
    Exit(FUnitNames[Number]);
  end;
  if not (AValue is TJSONString) or (AValue is TJSONNumber) or (AValue.Value = '') then
    Fail(AWhat + ': Name einer Unit erwartet');
  Result := AValue.Value;
end;

function TSnapshotReader.SubsystemName(AValue: TJSONValue; const AWhat: string): string;
var
  Number: Integer;
begin
  if FFormat = 1 then
  begin
    if not (AValue is TJSONNumber) then
      Fail(AWhat + ': Nummer eines Teilsystems erwartet');
    Number := TJSONNumber(AValue).AsInt;
    // -1: ohne Teilsystem (z. B. Ausreißer ohne Vorschlag).
    if Number < 0 then
      Exit('');
    if Number > High(FSubsystemNames) then
      Fail(AWhat + ': Teilsystem ' + IntToStr(Number) + ' fehlt');
    Exit(FSubsystemNames[Number]);
  end;
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
    Result := AValue.Value
  else
    Result := '';
end;

function TSnapshotReader.UnitNames(AItems: TJSONArray; const AWhat: string): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if AItems = nil then
    Exit;
  SetLength(Result, AItems.Count);
  for Index := 0 to AItems.Count - 1 do
    Result[Index] := UnitName(AItems.Items[Index], AWhat);
end;

function TSnapshotReader.EdgeOf(AValue: TJSONValue; const AWhat: string): TSnapshotEdge;
var
  Items: TJSONArray;
  Section: string;
begin
  Result := Default(TSnapshotEdge);
  if AValue is TJSONArray then
  begin
    Items := TJSONArray(AValue);
    if Items.Count < 3 then
      Fail(AWhat + ': [Quelle, Ziel, Abschnitt] erwartet');
    Result.Source := UnitName(Items.Items[0], AWhat);
    Result.Target := UnitName(Items.Items[1], AWhat);
    Section := Items.Items[2].Value;
  end
  else if AValue is TJSONObject then
  begin
    Result.Source := UnitName(Field(TJSONObject(AValue), 'source'), AWhat);
    Result.Target := UnitName(Field(TJSONObject(AValue), 'target'), AWhat);
    Section := TextOf(TJSONObject(AValue), 'section');
  end
  else
    Fail(AWhat + ': Kante erwartet');
  Result.Interface_ := (Section = 'interface') or (Section = 'i');
end;

function TSnapshotReader.Read: TArchitectureSnapshot;
var
  Items, Inner: TJSONArray;
  Item: TJSONObject;
  Index, Member: Integer;
  Value: TJSONValue;
  Units: TArray<TSnapshotUnit>;
  Edge: TJSONValue;
begin
  Result := Default(TArchitectureSnapshot);
  Result.FormatVersion := FFormat;
  Result.Title := TextOf(FData, 'title');
  Result.Scope := TextOf(FData, 'scope');
  Result.IncludeLibrary := FlagOf(FData, 'includeLibrary');
  Result.Grouping := TArchitectureGrouping.Default;
  if Field(FData, 'grouping') is TJSONObject then
  begin
    Item := TJSONObject(Field(FData, 'grouping'));
    if Field(Item, 'resolution') is TJSONNumber then
      Result.Grouping.Resolution := FloatOf(Item, 'resolution');
    Result.Grouping := Result.Grouping.Clamped;
  end;
  Items := ArrayOf(FData, 'excludes');
  if Items <> nil then
    for Value in Items do
      Result.Excludes := Result.Excludes + [Value.Value];
  // Format 1 nennt Units und Teilsysteme bei der Nummer: erst die Namen lesen.
  Items := ArrayOf(FData, 'units');
  if Items = nil then
    Fail('"units" fehlt');
  SetLength(FUnitNames, Items.Count);
  SetLength(Units, Items.Count);
  for Index := 0 to Items.Count - 1 do
  begin
    Item := ObjectAt(Items, Index, 'Unit');
    FUnitNames[Index] := TextOf(Item, 'name');
    if FUnitNames[Index] = '' then
      Fail('Unit ' + IntToStr(Index + 1) + ' ohne Namen');
  end;
  Inner := ArrayOf(FData, 'subsystems');
  if Inner <> nil then
  begin
    SetLength(FSubsystemNames, Inner.Count);
    for Index := 0 to Inner.Count - 1 do
      FSubsystemNames[Index] := TextOf(ObjectAt(Inner, Index, 'Teilsystem'), 'name');
  end;
  for Index := 0 to Items.Count - 1 do
  begin
    Item := TJSONObject(Items.Items[Index]);
    Units[Index].Name := FUnitNames[Index];
    Units[Index].FileName := TextOf(Item, 'file');
    Units[Index].Subsystem := SubsystemName(Field(Item, 'subsystem'), 'Unit ' + FUnitNames[Index]);
    Units[Index].Direct := IntOf(Item, 'direct');
    Units[Index].Total := IntOf(Item, 'total');
    Units[Index].Uses_ := IntOf(Item, 'uses');
    Units[Index].Role := TextOf(Item, 'role');
    Units[Index].Library_ := FlagOf(Item, 'library');
  end;
  Result.Units := Units;
  Items := ArrayOf(FData, 'edges');
  if Items <> nil then
  begin
    SetLength(Result.Edges, Items.Count);
    for Index := 0 to Items.Count - 1 do
      Result.Edges[Index] := EdgeOf(Items.Items[Index], 'Kante ' + IntToStr(Index + 1));
  end;
  Result.Central := UnitNames(ArrayOf(FData, 'central'), 'zentrale Units');
  if Inner <> nil then
  begin
    SetLength(Result.Subsystems, Inner.Count);
    for Index := 0 to Inner.Count - 1 do
    begin
      Item := TJSONObject(Inner.Items[Index]);
      Result.Subsystems[Index].Name := FSubsystemNames[Index];
      Result.Subsystems[Index].Units := UnitNames(ArrayOf(Item, 'units'), 'Teilsystem ' + FSubsystemNames[Index]);
      Value := Field(Item, 'central');
      if (Value <> nil) and not ((FFormat = 1) and (Value is TJSONNumber) and (TJSONNumber(Value).AsInt < 0)) and
        not ((FFormat <> 1) and (Value.Value = '')) then
        Result.Subsystems[Index].Central := UnitName(Value, 'Teilsystem ' + FSubsystemNames[Index]);
      Result.Subsystems[Index].Inner := IntOf(Item, 'inner');
      Result.Subsystems[Index].Outer := IntOf(Item, 'outer');
      Result.Subsystems[Index].Cohesion := FloatOf(Item, 'cohesion');
      Result.Subsystems[Index].Isolated := FlagOf(Item, 'isolated');
      Result.Subsystems[Index].Parent := TextOf(Item, 'parent');
      Result.Subsystems[Index].Foundation := FlagOf(Item, 'foundation');
      Result.Subsystems[Index].HasColor := Field(Item, 'color') is TJSONNumber;
      Result.Subsystems[Index].ColorSlot := IntOf(Item, 'color');
      Result.Subsystems[Index].Shade := IntOf(Item, 'shade');
    end;
  end;
  Items := ArrayOf(FData, 'outliers');
  if Items <> nil then
  begin
    SetLength(Result.Outliers, Items.Count);
    for Index := 0 to Items.Count - 1 do
    begin
      Item := ObjectAt(Items, Index, 'Ausreißer');
      Result.Outliers[Index].Unit_ := UnitName(Field(Item, 'unit'), 'Ausreißer');
      Result.Outliers[Index].Suggested := SubsystemName(Field(Item, 'suggested'), 'Ausreißer');
      Result.Outliers[Index].Reason := TextOf(Item, 'reason');
    end;
  end;
  Items := ArrayOf(FData, 'cycles');
  if Items <> nil then
  begin
    SetLength(Result.Cycles, Items.Count);
    for Index := 0 to Items.Count - 1 do
    begin
      Item := ObjectAt(Items, Index, 'Zyklus');
      Result.Cycles[Index].InterfaceOnly := FlagOf(Item, 'interfaceOnly');
      Result.Cycles[Index].Units := UnitNames(ArrayOf(Item, 'units'), 'Zyklus');
      Inner := ArrayOf(Item, 'edges');
      if Inner <> nil then
        for Member := 0 to Inner.Count - 1 do
        begin
          Edge := Inner.Items[Member];
          Result.Cycles[Index].Edges := Result.Cycles[Index].Edges + [EdgeOf(Edge, 'Zyklus')];
        end;
    end;
  end;
  Items := ArrayOf(FData, 'crossLinks');
  if Items <> nil then
  begin
    SetLength(Result.CrossLinks, Items.Count);
    for Index := 0 to Items.Count - 1 do
    begin
      Item := ObjectAt(Items, Index, 'Querverbindung');
      Result.CrossLinks[Index].Edge := EdgeOf(Item, 'Querverbindung');
      Result.CrossLinks[Index].FromSubsystem := SubsystemName(Field(Item, 'from'), 'Querverbindung');
      Result.CrossLinks[Index].ToSubsystem := SubsystemName(Field(Item, 'to'), 'Querverbindung');
      Result.CrossLinks[Index].Reason := TextOf(Item, 'reason');
      Result.CrossLinks[Index].Forward := IntOf(Item, 'forward');
      Result.CrossLinks[Index].Backward := IntOf(Item, 'backward');
    end;
  end;
end;

class function TArchitectureSnapshots.Parse(const AText: string; out ASnapshot: TArchitectureSnapshot;
  out AError: string): Boolean;
var
  Root: TJSONValue;
  Data: TJSONObject;
  Version: TJSONValue;
  Format_: Integer;
  Reader: TSnapshotReader;
begin
  ASnapshot := Default(TArchitectureSnapshot);
  AError := '';
  Result := False;
  try
    Root := TJSONObject.ParseJSONValue(AText);
  except
    Root := nil;
  end;
  try
    if not (Root is TJSONObject) then
    begin
      AError := 'Architekturstand ist kein JSON-Objekt';
      Exit;
    end;
    Data := TJSONObject(Root);
    // Antwort von atlas/architecture ("format": "json"): Die Daten stehen unter "data".
    if not (Data.GetValue('format') is TJSONNumber) and (Data.GetValue('data') is TJSONObject) then
      Data := TJSONObject(Data.GetValue('data'));
    Version := Data.GetValue('format');
    if not (Version is TJSONNumber) then
    begin
      AError := 'Architekturstand ohne Formatversion ("format"); erwartet wird eine Datei aus ' +
        'AtlasServer --architecture <Datei.json> oder „Stand speichern …“';
      Exit;
    end;
    Format_ := TJSONNumber(Version).AsInt;
    if (Format_ < 1) or (Format_ > FormatVersion) then
    begin
      AError := Format('Architekturstand im Format %d wird nicht unterstützt (gelesen werden ' +
        'die Formate 1 bis %d); bitte mit dieser Atlas-Version neu speichern', [Format_, FormatVersion]);
      Exit;
    end;
    if (Format_ = 2) and (Data.GetValue('kind') is TJSONString) and (Data.GetValue('kind').Value <> Kind) then
    begin
      AError := 'Datei ist kein Architekturstand ("kind": "' + Data.GetValue('kind').Value + '")';
      Exit;
    end;
    Reader := TSnapshotReader.Create(Data, Format_);
    try
      try
        ASnapshot := Reader.Read;
      except
        on E: EArchitectureSnapshot do
        begin
          ASnapshot := Default(TArchitectureSnapshot);
          AError := E.Message;
          Exit;
        end;
      end;
    finally
      Reader.Free;
    end;
    Normalize(ASnapshot);
    Result := True;
  finally
    Root.Free;
  end;
end;

class function TArchitectureSnapshots.Load(const AFileName: string; out ASnapshot: TArchitectureSnapshot;
  out AError: string): Boolean;
var
  Bytes: TBytes;
  Text: string;
begin
  ASnapshot := Default(TArchitectureSnapshot);
  if not TFile.Exists(AFileName) then
  begin
    AError := 'Architekturstand "' + AFileName + '" nicht gefunden';
    Exit(False);
  end;
  try
    Bytes := TFile.ReadAllBytes(AFileName);
    // UTF-8, ein BOM fällt weg.
    if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
      Text := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
    else
      Text := TEncoding.UTF8.GetString(Bytes);
  except
    on E: Exception do
    begin
      AError := 'Architekturstand "' + AFileName + '" nicht lesbar: ' + E.Message;
      Exit(False);
    end;
  end;
  Result := Parse(Text, ASnapshot, AError);
  if not Result then
    AError := AFileName + ': ' + AError;
end;

class procedure TArchitectureSnapshots.Save(const AFileName: string; const ASnapshot: TArchitectureSnapshot);
var
  Folder: string;
begin
  Folder := ExtractFileDir(TPath.GetFullPath(AFileName));
  if Folder <> '' then
    ForceDirectories(Folder);
  TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(Json(ASnapshot)));
end;

end.
