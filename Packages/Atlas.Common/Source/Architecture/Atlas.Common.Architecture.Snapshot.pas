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
    cFormatVersion = 2;
    cKind = 'atlas.architecture';
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
  Atlas.Common.Metrics.Report,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSnapshotText = (ArchitectureStateIsDamaged, IsNotAList, IsNotAnObject, NumberOfAUnitExpected, UnitMissing,
    NameOfAUnitExpected, SubsystemMissing, Outliers, UnitsMissing, ArchitectureStateWithoutFormatVersion,
    ArchitectureStateInFormatIs, FileIsNotAnArchitecture, ArchitectureStateIsNotA, ArchitectureStateNotFound,
    ArchitectureStateNotReadable, NumberOfASubsystemExpected, SourceTargetSectionExpected, UnitWithoutName,
    CentralUnits, EdgeExpected, Subsystem, Edge, Subsystem2, Cycle, CrossLink);

const
  cTexts: array[TSnapshotText] of TAtlasText = (
    (De: 'Architekturstand ist beschädigt: '; En: 'Architecture state is damaged: '),
    (De: '"%s" ist keine Liste'; En: '"%s" is not a list'),
    (De: ' %s ist kein Objekt'; En: ' %s is not an object'),
    (De: ': Nummer einer Unit erwartet'; En: ': number of a unit expected'),
    (De: ': Unit %s fehlt'; En: ': unit %s missing'),
    (De: ': Name einer Unit erwartet'; En: ': name of a unit expected'),
    (De: ': Teilsystem %s fehlt'; En: ': subsystem %s missing'),
    (De: 'Ausreißer'; En: 'Outliers'),
    (De: '"units" fehlt'; En: '"units" missing'),
    (De: 'Architekturstand ohne Formatversion ("format"); erwartet wird eine Datei aus AtlasServer --architecture ' +
      '<Datei.json> oder „Stand speichern …“';
     En: 'Architecture state without format version ("format"); expected is a file from AtlasServer --architecture ' +
      '<file.json> or “Save state …”'),
    (De: 'Architekturstand im Format %d wird nicht unterstützt (gelesen werden die Formate 1 bis %d); bitte mit ' +
      'dieser Atlas-Version neu speichern';
     En: 'Architecture state in format %d is not supported (formats 1 to %d are read); please save it again with ' +
      'this Atlas version'),
    (De: 'Datei ist kein Architekturstand ("kind": "%s")'; En: 'File is not an architecture state ("kind": "%s")'),
    (De: 'Architekturstand ist kein JSON-Objekt'; En: 'Architecture state is not a JSON object'),
    (De: 'Architekturstand "%s" nicht gefunden'; En: 'Architecture state "%s" not found'),
    (De: 'Architekturstand "%s" nicht lesbar: '; En: 'Architecture state "%s" not readable: '),
    (De: ': Nummer eines Teilsystems erwartet'; En: ': number of a subsystem expected'),
    (De: ': [Quelle, Ziel, Abschnitt] erwartet'; En: ': [source, target, section] expected'),
    (De: 'Unit %s ohne Namen'; En: 'Unit %s without name'),
    (De: 'zentrale Units'; En: 'central units'),
    (De: ': Kante erwartet'; En: ': edge expected'),
    (De: 'Teilsystem'; En: 'Subsystem'),
    (De: 'Kante '; En: 'Edge '),
    (De: 'Teilsystem '; En: 'Subsystem '),
    (De: 'Zyklus'; En: 'Cycle'),
    (De: 'Querverbindung'; En: 'Cross link'));

{$SCOPEDENUMS OFF}

const
  cLineBreak = #10;

function CompareNames(const ALeft, ARight: string): Integer;
begin
  Result := CompareText(ALeft, ARight);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft, ARight);
  end;
end;

function SectionText(AInterface: Boolean): string;
begin
  if AInterface then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
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
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mNames, Length(Units));
  for mIndex := 0 to High(Units) do
  begin
    mNames[mIndex] := LowerCase(Units[mIndex]);
  end;
  TArray.Sort<string>(mNames);
  Result := string.Join(#1, mNames);
end;

{ TArchitectureSnapshot }

function TArchitectureSnapshot.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Units) do
  begin
    if SameText(Units[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TArchitectureSnapshot.InterfaceCycleCount: Integer;
var
  mCycle: TSnapshotCycle;
begin
  Result := 0;
  for mCycle in Cycles do
  begin
    if mCycle.InterfaceOnly then
    begin
      Inc(Result);
    end;
  end;
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
  begin
    Result := AOverview.Subsystems[ASubsystem].Name;
  end
  else
  begin
    Result := '';
  end;
end;

function SnapshotUnitOf(const AOverview: TArchitectureOverview; const AItem: TOverviewUnit): TSnapshotUnit;
begin
  Result := Default(TSnapshotUnit);
  Result.Name := AItem.Name;
  Result.FileName := AOverview.RelativePath(AItem.FileName);
  Result.Subsystem := SubsystemOf(AOverview, AItem.Subsystem);
  Result.Direct := AItem.Direct;
  Result.Total := AItem.Total;
  Result.Uses_ := AItem.Uses_;
  Result.Role := RoleText(AItem.Role);
  Result.Library_ := AItem.Library_;
end;

/// <summary>Namen der Units mit den Nummern AMembers.</summary>
function UnitNamesOf(const AOverview: TArchitectureOverview; const AMembers: TArray<Integer>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AMembers));
  for mIndex := 0 to High(AMembers) do
  begin
    Result[mIndex] := AOverview.Units[AMembers[mIndex]].Name;
  end;
end;

function SnapshotSubsystemOf(const AOverview: TArchitectureOverview; const ASubsystem: TOverviewSubsystem)
  : TSnapshotSubsystem;
begin
  Result := Default(TSnapshotSubsystem);
  Result.Name := ASubsystem.Name;
  Result.Units := UnitNamesOf(AOverview, ASubsystem.Units);
  if ASubsystem.Central >= 0 then
  begin
    Result.Central := AOverview.Units[ASubsystem.Central].Name;
  end;
  Result.Inner := ASubsystem.InnerEdges;
  Result.Outer := ASubsystem.OuterEdges;
  Result.Cohesion := ASubsystem.Cohesion;
  Result.Isolated := ASubsystem.Isolated;
  Result.Parent := ASubsystem.Parent;
  Result.Foundation := ASubsystem.Foundation;
  Result.ColorSlot := ASubsystem.ColorSlot;
  Result.Shade := ASubsystem.Shade;
  Result.HasColor := True;
end;

function SnapshotOutlierOf(const AOverview: TArchitectureOverview; const AOutlier: TOverviewOutlier)
  : TSnapshotOutlier;
begin
  Result := Default(TSnapshotOutlier);
  Result.Unit_ := AOverview.Units[AOutlier.Unit_].Name;
  Result.Suggested := SubsystemOf(AOverview, AOutlier.Suggested);
  if AOutlier.Reason = TOverviewOutlierReason.Namespace then
  begin
    Result.Reason := 'namespace';
  end
  else
  begin
    Result.Reason := 'edges';
  end;
end;

function SnapshotCycleOf(const AOverview: TArchitectureOverview; const ACycle: TOverviewCycle): TSnapshotCycle;
var
  mIndex: Integer;
begin
  Result := Default(TSnapshotCycle);
  Result.InterfaceOnly := ACycle.InterfaceOnly;
  Result.Units := UnitNamesOf(AOverview, ACycle.Units);
  SetLength(Result.Edges, Length(ACycle.Edges));
  for mIndex := 0 to High(ACycle.Edges) do
  begin
    Result.Edges[mIndex] := EdgeOf(AOverview, ACycle.Edges[mIndex]);
  end;
end;

function SnapshotCrossLinkOf(const AOverview: TArchitectureOverview; const ALink: TOverviewCrossLink)
  : TSnapshotCrossLink;
begin
  Result := Default(TSnapshotCrossLink);
  Result.Edge := EdgeOf(AOverview, ALink.Edge);
  Result.FromSubsystem := SubsystemOf(AOverview, ALink.FromSubsystem);
  Result.ToSubsystem := SubsystemOf(AOverview, ALink.ToSubsystem);
  if ALink.Reason = TOverviewCrossReason.Rare then
  begin
    Result.Reason := 'rare';
  end
  else
  begin
    Result.Reason := 'againstDirection';
  end;
  Result.Forward := ALink.Forward;
  Result.Backward := ALink.Backward;
end;

class function TArchitectureSnapshots.FromOverview(const AOverview: TArchitectureOverview): TArchitectureSnapshot;
var
  mIndex: Integer;
begin
  Result := Default(TArchitectureSnapshot);
  Result.FormatVersion := cFormatVersion;
  Result.Title := AOverview.Title;
  Result.Scope := AOverview.Scope;
  Result.IncludeLibrary := AOverview.IncludeLibrary;
  Result.Excludes := Copy(AOverview.Excludes);
  Result.Grouping := AOverview.Grouping.Clamped;
  SetLength(Result.Units, Length(AOverview.Units));
  for mIndex := 0 to High(AOverview.Units) do
  begin
    Result.Units[mIndex] := SnapshotUnitOf(AOverview, AOverview.Units[mIndex]);
  end;
  SetLength(Result.Edges, Length(AOverview.Edges));
  for mIndex := 0 to High(AOverview.Edges) do
  begin
    Result.Edges[mIndex] := EdgeOf(AOverview, AOverview.Edges[mIndex]);
  end;
  Result.Central := UnitNamesOf(AOverview, AOverview.Central);
  SetLength(Result.Subsystems, Length(AOverview.Subsystems));
  for mIndex := 0 to High(AOverview.Subsystems) do
  begin
    Result.Subsystems[mIndex] := SnapshotSubsystemOf(AOverview, AOverview.Subsystems[mIndex]);
  end;
  SetLength(Result.Outliers, Length(AOverview.Outliers));
  for mIndex := 0 to High(AOverview.Outliers) do
  begin
    Result.Outliers[mIndex] := SnapshotOutlierOf(AOverview, AOverview.Outliers[mIndex]);
  end;
  SetLength(Result.Cycles, Length(AOverview.Cycles));
  for mIndex := 0 to High(AOverview.Cycles) do
  begin
    Result.Cycles[mIndex] := SnapshotCycleOf(AOverview, AOverview.Cycles[mIndex]);
  end;
  SetLength(Result.CrossLinks, Length(AOverview.CrossLinks));
  for mIndex := 0 to High(AOverview.CrossLinks) do
  begin
    Result.CrossLinks[mIndex] := SnapshotCrossLinkOf(AOverview, AOverview.CrossLinks[mIndex]);
  end;
  Normalize(Result);
end;

function CompareEdges(const ALeft, ARight: TSnapshotEdge): Integer;
begin
  Result := CompareNames(ALeft.Source, ARight.Source);
  if Result = 0 then
  begin
    Result := CompareNames(ALeft.Target, ARight.Target);
  end;
  // interface vor implementation.
  if Result = 0 then
  begin
    Result := Ord(ARight.Interface_) - Ord(ALeft.Interface_);
  end;
end;

function CompareCycles(const ALeft, ARight: TSnapshotCycle): Integer;
begin
  // Reine interface-Zyklen zuerst wie in der Übersicht.
  Result := Ord(ARight.InterfaceOnly) - Ord(ALeft.InterfaceOnly);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Key, ARight.Key);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(string.Join(#1, ALeft.Units), string.Join(#1, ARight.Units));
  end;
end;

class procedure TArchitectureSnapshots.Normalize(var ASnapshot: TArchitectureSnapshot);
var
  mIndex: Integer;
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
  for mIndex := 0 to High(ASnapshot.Subsystems) do
  begin
    TArray.Sort<string>(ASnapshot.Subsystems[mIndex].Units, TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareNames(ALeft, ARight);
      end));
  end;
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
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

function Number(AValue: Double): string;
begin
  Result := FormatFloat('0.###', AValue, TFormatSettings.Invariant);
end;

function Names(const AValues: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '[';
  for mIndex := 0 to High(AValues) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Text(AValues[mIndex]);
  end;
  Result := Result + ']';
end;

function EdgeJson(const AEdge: TSnapshotEdge): string;
begin
  Result := '[' + Text(AEdge.Source) + ', ' + Text(AEdge.Target) + ', ' + Text(SectionText(AEdge.Interface_)) + ']';
end;

/// <summary>Trenner vor dem Eintrag AIndex einer Liste: Komma ab dem zweiten, dann neue eingerückte Zeile.
/// </summary>
procedure Separate(ABuilder: TStringBuilder; AIndex: Integer);
begin
  if AIndex > 0 then
  begin
    ABuilder.Append(',');
  end;
  ABuilder.Append(cLineBreak).Append('  ');
end;

procedure AppendHeader(ABuilder: TStringBuilder; const ASnapshot: TArchitectureSnapshot);
begin
  ABuilder.Append('{').Append(cLineBreak)
    .Append('"format": ').Append(TArchitectureSnapshots.cFormatVersion).Append(',').Append(cLineBreak)
    .Append('"kind": ').Append(Text(TArchitectureSnapshots.cKind)).Append(',').Append(cLineBreak)
    .Append('"title": ').Append(Text(ASnapshot.Title)).Append(',').Append(cLineBreak)
    .Append('"scope": ').Append(Text(ASnapshot.Scope)).Append(',').Append(cLineBreak)
    .Append('"includeLibrary": ').Append(Bool(ASnapshot.IncludeLibrary)).Append(',').Append(cLineBreak)
    .Append('"excludes": ').Append(Names(ASnapshot.Excludes)).Append(',').Append(cLineBreak)
    .Append('"grouping": {"resolution": ').Append(Number(ASnapshot.Grouping.Clamped.Resolution)).Append('},')
    .Append(cLineBreak)
    .Append('"summary": {"units": ').Append(Length(ASnapshot.Units))
    .Append(', "edges": ').Append(Length(ASnapshot.Edges))
    .Append(', "subsystems": ').Append(Length(ASnapshot.Subsystems))
    .Append(', "cycles": ').Append(Length(ASnapshot.Cycles))
    .Append(', "interfaceCycles": ').Append(ASnapshot.InterfaceCycleCount)
    .Append(', "crossLinks": ').Append(Length(ASnapshot.CrossLinks))
    .Append(', "outliers": ').Append(Length(ASnapshot.Outliers)).Append('},').Append(cLineBreak);
end;

procedure AppendUnits(ABuilder: TStringBuilder; const ASnapshot: TArchitectureSnapshot);
var
  mIndex: Integer;
  mItem: TSnapshotUnit;
begin
  ABuilder.Append('"units": [');
  for mIndex := 0 to High(ASnapshot.Units) do
  begin
    mItem := ASnapshot.Units[mIndex];
    Separate(ABuilder, mIndex);
    ABuilder.Append('{"name": ').Append(Text(mItem.Name))
      .Append(', "file": ').Append(Text(mItem.FileName))
      .Append(', "subsystem": ').Append(Text(mItem.Subsystem))
      .Append(', "direct": ').Append(mItem.Direct)
      .Append(', "total": ').Append(mItem.Total)
      .Append(', "uses": ').Append(mItem.Uses_)
      .Append(', "role": ').Append(Text(mItem.Role))
      .Append(', "library": ').Append(Bool(mItem.Library_)).Append('}');
  end;
  ABuilder.Append(cLineBreak).Append('],').Append(cLineBreak).Append('"edges": [');
  for mIndex := 0 to High(ASnapshot.Edges) do
  begin
    Separate(ABuilder, mIndex);
    ABuilder.Append(EdgeJson(ASnapshot.Edges[mIndex]));
  end;
  ABuilder.Append(cLineBreak).Append('],').Append(cLineBreak)
    .Append('"central": ').Append(Names(ASnapshot.Central)).Append(',').Append(cLineBreak);
end;

procedure AppendSubsystem(ABuilder: TStringBuilder; const ASubsystem: TSnapshotSubsystem);
begin
  ABuilder.Append('{"name": ').Append(Text(ASubsystem.Name))
    .Append(', "units": ').Append(Names(ASubsystem.Units))
    .Append(', "central": ').Append(Text(ASubsystem.Central))
    .Append(', "inner": ').Append(ASubsystem.Inner)
    .Append(', "outer": ').Append(ASubsystem.Outer)
    .Append(', "cohesion": ').Append(Number(ASubsystem.Cohesion))
    .Append(', "isolated": ').Append(Bool(ASubsystem.Isolated));
  // Nur bei nachgeteilten Teilsystemen: Stände ohne Nachteilung bleiben wie vor #1364.
  if ASubsystem.Foundation then
  begin
    ABuilder.Append(', "foundation": true');
  end;
  if ASubsystem.Parent <> '' then
  begin
    ABuilder.Append(', "parent": ').Append(Text(ASubsystem.Parent));
  end;
  // Farbe für die Angleichung (#1367); ältere Stände ohne sie liest Parse weiter.
  if ASubsystem.HasColor then
  begin
    ABuilder.Append(', "color": ').Append(ASubsystem.ColorSlot).Append(', "shade": ').Append(ASubsystem.Shade);
  end;
  ABuilder.Append('}');
end;

procedure AppendSubsystemsAndOutliers(ABuilder: TStringBuilder; const ASnapshot: TArchitectureSnapshot);
var
  mIndex: Integer;
begin
  ABuilder.Append('"subsystems": [');
  for mIndex := 0 to High(ASnapshot.Subsystems) do
  begin
    Separate(ABuilder, mIndex);
    AppendSubsystem(ABuilder, ASnapshot.Subsystems[mIndex]);
  end;
  ABuilder.Append(cLineBreak).Append('],').Append(cLineBreak).Append('"outliers": [');
  for mIndex := 0 to High(ASnapshot.Outliers) do
  begin
    Separate(ABuilder, mIndex);
    ABuilder.Append('{"unit": ').Append(Text(ASnapshot.Outliers[mIndex].Unit_))
      .Append(', "suggested": ').Append(Text(ASnapshot.Outliers[mIndex].Suggested))
      .Append(', "reason": ').Append(Text(ASnapshot.Outliers[mIndex].Reason)).Append('}');
  end;
  ABuilder.Append(cLineBreak).Append('],').Append(cLineBreak);
end;

procedure AppendCycles(ABuilder: TStringBuilder; const ASnapshot: TArchitectureSnapshot);
var
  mIndex, mInner: Integer;
  mCycle: TSnapshotCycle;
begin
  ABuilder.Append('"cycles": [');
  for mIndex := 0 to High(ASnapshot.Cycles) do
  begin
    mCycle := ASnapshot.Cycles[mIndex];
    Separate(ABuilder, mIndex);
    ABuilder.Append('{"interfaceOnly": ').Append(Bool(mCycle.InterfaceOnly))
      .Append(', "units": ').Append(Names(mCycle.Units))
      .Append(', "edges": [');
    for mInner := 0 to High(mCycle.Edges) do
    begin
      if mInner > 0 then
      begin
        ABuilder.Append(', ');
      end;
      ABuilder.Append(EdgeJson(mCycle.Edges[mInner]));
    end;
    ABuilder.Append(']}');
  end;
  ABuilder.Append(cLineBreak).Append('],').Append(cLineBreak);
end;

procedure AppendCrossLinks(ABuilder: TStringBuilder; const ASnapshot: TArchitectureSnapshot);
var
  mIndex: Integer;
  mLink: TSnapshotCrossLink;
begin
  ABuilder.Append('"crossLinks": [');
  for mIndex := 0 to High(ASnapshot.CrossLinks) do
  begin
    mLink := ASnapshot.CrossLinks[mIndex];
    Separate(ABuilder, mIndex);
    ABuilder.Append('{"source": ').Append(Text(mLink.Edge.Source))
      .Append(', "target": ').Append(Text(mLink.Edge.Target))
      .Append(', "section": ').Append(Text(SectionText(mLink.Edge.Interface_)))
      .Append(', "from": ').Append(Text(mLink.FromSubsystem))
      .Append(', "to": ').Append(Text(mLink.ToSubsystem))
      .Append(', "reason": ').Append(Text(mLink.Reason))
      .Append(', "forward": ').Append(mLink.Forward)
      .Append(', "backward": ').Append(mLink.Backward).Append('}');
  end;
  ABuilder.Append(cLineBreak).Append(']').Append(cLineBreak);
end;

class function TArchitectureSnapshots.Json(const ASnapshot: TArchitectureSnapshot): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    AppendHeader(mBuilder, ASnapshot);
    AppendUnits(mBuilder, ASnapshot);
    AppendSubsystemsAndOutliers(mBuilder, ASnapshot);
    AppendCycles(mBuilder, ASnapshot);
    AppendCrossLinks(mBuilder, ASnapshot);
    mBuilder.Append('}').Append(cLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
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
    procedure ReadHeader(var ASnapshot: TArchitectureSnapshot);
    /// <summary>Format 1 nennt Units und Teilsysteme bei der Nummer: erst die Namen lesen.</summary>
    procedure ReadNames(AUnits, ASubsystems: TJSONArray);
    function ReadUnits(AItems: TJSONArray): TArray<TSnapshotUnit>;
    function ReadEdges: TArray<TSnapshotEdge>;
    /// <summary>"central" eines Teilsystems ist gesetzt (Format 1: Nummer ab 0, Format 2: nicht leer).</summary>
    function HasCentral(AValue: TJSONValue): Boolean;
    function ReadSubsystem(AItem: TJSONObject; const AName: string): TSnapshotSubsystem;
    function ReadSubsystems(AItems: TJSONArray): TArray<TSnapshotSubsystem>;
    function ReadOutliers: TArray<TSnapshotOutlier>;
    function ReadCycle(AItem: TJSONObject): TSnapshotCycle;
    function ReadCycles: TArray<TSnapshotCycle>;
    function ReadCrossLinks: TArray<TSnapshotCrossLink>;
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
  raise EArchitectureSnapshot.Create(cTexts[TSnapshotText.ArchitectureStateIsDamaged].Text + AText);
end;

function TSnapshotReader.Field(AObject: TJSONObject; const AName: string): TJSONValue;
begin
  Result := nil;
  if AObject <> nil then
  begin
    Result := AObject.GetValue(AName);
  end;
end;

function TSnapshotReader.TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  mValue := Field(AObject, AName);
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
  begin
    Result := mValue.Value;
  end
  else
  begin
    Result := '';
  end;
end;

function TSnapshotReader.IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  mValue := Field(AObject, AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end
  else
  begin
    Result := 0;
  end;
end;

function TSnapshotReader.FloatOf(AObject: TJSONObject; const AName: string): Double;
var
  mValue: TJSONValue;
begin
  mValue := Field(AObject, AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsDouble;
  end
  else
  begin
    Result := 0;
  end;
end;

function TSnapshotReader.FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := Field(AObject, AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function TSnapshotReader.ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  mValue := Field(AObject, AName);
  if mValue = nil then
  begin
    Exit(nil);
  end;
  if not (mValue is TJSONArray) then
  begin
    Fail(cTexts[TSnapshotText.IsNotAList].Fmt([AName]));
  end;
  Result := TJSONArray(mValue);
end;

function TSnapshotReader.ObjectAt(AItems: TJSONArray; AIndex: Integer; const AWhat: string): TJSONObject;
begin
  if not (AItems.Items[AIndex] is TJSONObject) then
  begin
    Fail(AWhat + cTexts[TSnapshotText.IsNotAnObject].Fmt([IntToStr(AIndex + 1)]));
  end;
  Result := TJSONObject(AItems.Items[AIndex]);
end;

function TSnapshotReader.UnitName(AValue: TJSONValue; const AWhat: string): string;
var
  mNumber: Integer;
begin
  if FFormat = 1 then
  begin
    if not (AValue is TJSONNumber) then
    begin
      Fail(AWhat + cTexts[TSnapshotText.NumberOfAUnitExpected].Text);
    end;
    mNumber := TJSONNumber(AValue).AsInt;
    if (mNumber < 0) or (mNumber > High(FUnitNames)) then
    begin
      Fail(AWhat + cTexts[TSnapshotText.UnitMissing].Fmt([IntToStr(mNumber)]));
    end;
    Exit(FUnitNames[mNumber]);
  end;
  if not (AValue is TJSONString) or (AValue is TJSONNumber) or (AValue.Value = '') then
  begin
    Fail(AWhat + cTexts[TSnapshotText.NameOfAUnitExpected].Text);
  end;
  Result := AValue.Value;
end;

function TSnapshotReader.SubsystemName(AValue: TJSONValue; const AWhat: string): string;
var
  mNumber: Integer;
begin
  if FFormat = 1 then
  begin
    if not (AValue is TJSONNumber) then
    begin
      Fail(AWhat + cTexts[TSnapshotText.NumberOfASubsystemExpected].Text);
    end;
    mNumber := TJSONNumber(AValue).AsInt;
    // -1: ohne Teilsystem (z. B. Ausreißer ohne Vorschlag).
    if mNumber < 0 then
    begin
      Exit('');
    end;
    if mNumber > High(FSubsystemNames) then
    begin
      Fail(AWhat + cTexts[TSnapshotText.SubsystemMissing].Fmt([IntToStr(mNumber)]));
    end;
    Exit(FSubsystemNames[mNumber]);
  end;
  if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    Result := AValue.Value;
  end
  else
  begin
    Result := '';
  end;
end;

function TSnapshotReader.UnitNames(AItems: TJSONArray; const AWhat: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, AItems.Count);
  for mIndex := 0 to AItems.Count - 1 do
  begin
    Result[mIndex] := UnitName(AItems.Items[mIndex], AWhat);
  end;
end;

function TSnapshotReader.EdgeOf(AValue: TJSONValue; const AWhat: string): TSnapshotEdge;
var
  mItems: TJSONArray;
  mSection: string;
begin
  Result := Default(TSnapshotEdge);
  if AValue is TJSONArray then
  begin
    mItems := TJSONArray(AValue);
    if mItems.Count < 3 then
    begin
      Fail(AWhat + cTexts[TSnapshotText.SourceTargetSectionExpected].Text);
    end;
    Result.Source := UnitName(mItems.Items[0], AWhat);
    Result.Target := UnitName(mItems.Items[1], AWhat);
    mSection := mItems.Items[2].Value;
  end
  else if AValue is TJSONObject then
  begin
    Result.Source := UnitName(Field(TJSONObject(AValue), 'source'), AWhat);
    Result.Target := UnitName(Field(TJSONObject(AValue), 'target'), AWhat);
    mSection := TextOf(TJSONObject(AValue), 'section');
  end
  else
  begin
    Fail(AWhat + cTexts[TSnapshotText.EdgeExpected].Text);
  end;
  Result.Interface_ := (mSection = 'interface') or (mSection = 'i');
end;

procedure TSnapshotReader.ReadHeader(var ASnapshot: TArchitectureSnapshot);
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mValue: TJSONValue;
begin
  ASnapshot.FormatVersion := FFormat;
  ASnapshot.Title := TextOf(FData, 'title');
  ASnapshot.Scope := TextOf(FData, 'scope');
  ASnapshot.IncludeLibrary := FlagOf(FData, 'includeLibrary');
  ASnapshot.Grouping := TArchitectureGrouping.Default;
  if Field(FData, 'grouping') is TJSONObject then
  begin
    mItem := TJSONObject(Field(FData, 'grouping'));
    if Field(mItem, 'resolution') is TJSONNumber then
    begin
      ASnapshot.Grouping.Resolution := FloatOf(mItem, 'resolution');
    end;
    ASnapshot.Grouping := ASnapshot.Grouping.Clamped;
  end;
  mItems := ArrayOf(FData, 'excludes');
  if mItems <> nil then
  begin
    for mValue in mItems do
    begin
      ASnapshot.Excludes := ASnapshot.Excludes + [mValue.Value];
    end;
  end;
end;

procedure TSnapshotReader.ReadNames(AUnits, ASubsystems: TJSONArray);
var
  mIndex: Integer;
begin
  SetLength(FUnitNames, AUnits.Count);
  for mIndex := 0 to AUnits.Count - 1 do
  begin
    FUnitNames[mIndex] := TextOf(ObjectAt(AUnits, mIndex, 'Unit'), 'name');
    if FUnitNames[mIndex] = '' then
    begin
      Fail(cTexts[TSnapshotText.UnitWithoutName].Fmt([IntToStr(mIndex + 1)]));
    end;
  end;
  if ASubsystems <> nil then
  begin
    SetLength(FSubsystemNames, ASubsystems.Count);
    for mIndex := 0 to ASubsystems.Count - 1 do
    begin
      FSubsystemNames[mIndex] := TextOf(ObjectAt(ASubsystems, mIndex, cTexts[TSnapshotText.Subsystem].Text), 'name');
    end;
  end;
end;

function TSnapshotReader.ReadUnits(AItems: TJSONArray): TArray<TSnapshotUnit>;
var
  mItem: TJSONObject;
  mIndex: Integer;
begin
  SetLength(Result, AItems.Count);
  for mIndex := 0 to AItems.Count - 1 do
  begin
    mItem := TJSONObject(AItems.Items[mIndex]);
    Result[mIndex] := Default(TSnapshotUnit);
    Result[mIndex].Name := FUnitNames[mIndex];
    Result[mIndex].FileName := TextOf(mItem, 'file');
    Result[mIndex].Subsystem := SubsystemName(Field(mItem, 'subsystem'), 'Unit ' + FUnitNames[mIndex]);
    Result[mIndex].Direct := IntOf(mItem, 'direct');
    Result[mIndex].Total := IntOf(mItem, 'total');
    Result[mIndex].Uses_ := IntOf(mItem, 'uses');
    Result[mIndex].Role := TextOf(mItem, 'role');
    Result[mIndex].Library_ := FlagOf(mItem, 'library');
  end;
end;

function TSnapshotReader.ReadEdges: TArray<TSnapshotEdge>;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  mItems := ArrayOf(FData, 'edges');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    Result[mIndex] := EdgeOf(mItems.Items[mIndex], cTexts[TSnapshotText.Edge].Text + IntToStr(mIndex + 1));
  end;
end;

function TSnapshotReader.HasCentral(AValue: TJSONValue): Boolean;
begin
  if AValue = nil then
  begin
    Result := False;
  end
  else if FFormat = 1 then
  begin
    Result := not ((AValue is TJSONNumber) and (TJSONNumber(AValue).AsInt < 0));
  end
  else
  begin
    Result := AValue.Value <> '';
  end;
end;

function TSnapshotReader.ReadSubsystem(AItem: TJSONObject; const AName: string): TSnapshotSubsystem;
begin
  Result := Default(TSnapshotSubsystem);
  Result.Name := AName;
  Result.Units := UnitNames(ArrayOf(AItem, 'units'), cTexts[TSnapshotText.Subsystem2].Text + AName);
  if HasCentral(Field(AItem, 'central')) then
  begin
    Result.Central := UnitName(Field(AItem, 'central'), cTexts[TSnapshotText.Subsystem2].Text + AName);
  end;
  Result.Inner := IntOf(AItem, 'inner');
  Result.Outer := IntOf(AItem, 'outer');
  Result.Cohesion := FloatOf(AItem, 'cohesion');
  Result.Isolated := FlagOf(AItem, 'isolated');
  Result.Parent := TextOf(AItem, 'parent');
  Result.Foundation := FlagOf(AItem, 'foundation');
  Result.HasColor := Field(AItem, 'color') is TJSONNumber;
  Result.ColorSlot := IntOf(AItem, 'color');
  Result.Shade := IntOf(AItem, 'shade');
end;

function TSnapshotReader.ReadSubsystems(AItems: TJSONArray): TArray<TSnapshotSubsystem>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, AItems.Count);
  for mIndex := 0 to AItems.Count - 1 do
  begin
    Result[mIndex] := ReadSubsystem(TJSONObject(AItems.Items[mIndex]), FSubsystemNames[mIndex]);
  end;
end;

function TSnapshotReader.ReadOutliers: TArray<TSnapshotOutlier>;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := nil;
  mItems := ArrayOf(FData, 'outliers');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    mItem := ObjectAt(mItems, mIndex, cTexts[TSnapshotText.Outliers].Text);
    Result[mIndex] := Default(TSnapshotOutlier);
    Result[mIndex].Unit_ := UnitName(Field(mItem, 'unit'), cTexts[TSnapshotText.Outliers].Text);
    Result[mIndex].Suggested := SubsystemName(Field(mItem, 'suggested'), cTexts[TSnapshotText.Outliers].Text);
    Result[mIndex].Reason := TextOf(mItem, 'reason');
  end;
end;

function TSnapshotReader.ReadCycle(AItem: TJSONObject): TSnapshotCycle;
var
  mEdges: TJSONArray;
  mMember: Integer;
begin
  Result := Default(TSnapshotCycle);
  Result.InterfaceOnly := FlagOf(AItem, 'interfaceOnly');
  Result.Units := UnitNames(ArrayOf(AItem, 'units'), cTexts[TSnapshotText.Cycle].Text);
  mEdges := ArrayOf(AItem, 'edges');
  if mEdges = nil then
  begin
    Exit;
  end;
  SetLength(Result.Edges, mEdges.Count);
  for mMember := 0 to mEdges.Count - 1 do
  begin
    Result.Edges[mMember] := EdgeOf(mEdges.Items[mMember], cTexts[TSnapshotText.Cycle].Text);
  end;
end;

function TSnapshotReader.ReadCycles: TArray<TSnapshotCycle>;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  mItems := ArrayOf(FData, 'cycles');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    Result[mIndex] := ReadCycle(ObjectAt(mItems, mIndex, cTexts[TSnapshotText.Cycle].Text));
  end;
end;

function TSnapshotReader.ReadCrossLinks: TArray<TSnapshotCrossLink>;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Result := nil;
  mItems := ArrayOf(FData, 'crossLinks');
  if mItems = nil then
  begin
    Exit;
  end;
  SetLength(Result, mItems.Count);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    mItem := ObjectAt(mItems, mIndex, cTexts[TSnapshotText.CrossLink].Text);
    Result[mIndex] := Default(TSnapshotCrossLink);
    Result[mIndex].Edge := EdgeOf(mItem, cTexts[TSnapshotText.CrossLink].Text);
    Result[mIndex].FromSubsystem := SubsystemName(Field(mItem, 'from'), cTexts[TSnapshotText.CrossLink].Text);
    Result[mIndex].ToSubsystem := SubsystemName(Field(mItem, 'to'), cTexts[TSnapshotText.CrossLink].Text);
    Result[mIndex].Reason := TextOf(mItem, 'reason');
    Result[mIndex].Forward := IntOf(mItem, 'forward');
    Result[mIndex].Backward := IntOf(mItem, 'backward');
  end;
end;

function TSnapshotReader.Read: TArchitectureSnapshot;
var
  mUnits, mSubsystems: TJSONArray;
begin
  Result := Default(TArchitectureSnapshot);
  ReadHeader(Result);
  mUnits := ArrayOf(FData, 'units');
  if mUnits = nil then
  begin
    Fail(cTexts[TSnapshotText.UnitsMissing].Text);
  end;
  mSubsystems := ArrayOf(FData, 'subsystems');
  ReadNames(mUnits, mSubsystems);
  Result.Units := ReadUnits(mUnits);
  Result.Edges := ReadEdges;
  Result.Central := UnitNames(ArrayOf(FData, 'central'), cTexts[TSnapshotText.CentralUnits].Text);
  Result.Subsystems := ReadSubsystems(mSubsystems);
  Result.Outliers := ReadOutliers;
  Result.Cycles := ReadCycles;
  Result.CrossLinks := ReadCrossLinks;
end;

/// <summary>Daten eines Stands: die Antwort von atlas/architecture ("format": "json") hat sie unter "data".
/// </summary>
function SnapshotData(ARoot: TJSONObject): TJSONObject;
begin
  Result := ARoot;
  if not (Result.GetValue('format') is TJSONNumber) and (Result.GetValue('data') is TJSONObject) then
  begin
    Result := TJSONObject(Result.GetValue('data'));
  end;
end;

/// <summary>Formatversion und Art prüfen; False mit AError, wenn der Stand nicht lesbar ist.</summary>
function CheckFormat(AData: TJSONObject; out AFormat: Integer; out AError: string): Boolean;
var
  mVersion: TJSONValue;
begin
  AFormat := 0;
  AError := '';
  mVersion := AData.GetValue('format');
  if not (mVersion is TJSONNumber) then
  begin
    AError := cTexts[TSnapshotText.ArchitectureStateWithoutFormatVersion].Text;
  end
  else
  begin
    AFormat := TJSONNumber(mVersion).AsInt;
    if (AFormat < 1) or (AFormat > TArchitectureSnapshots.cFormatVersion) then
    begin
      AError := cTexts[TSnapshotText.ArchitectureStateInFormatIs].Fmt([AFormat, TArchitectureSnapshots.cFormatVersion]);
    end
    else if (AFormat = 2) and (AData.GetValue('kind') is TJSONString) and
      (AData.GetValue('kind').Value <> TArchitectureSnapshots.cKind) then
    begin
      AError := cTexts[TSnapshotText.FileIsNotAnArchitecture].Fmt([AData.GetValue('kind').Value]);
    end;
  end;
  Result := AError = '';
end;

/// <summary>Stand mit TSnapshotReader lesen; False mit AError bei beschädigtem Inhalt.</summary>
function ReadSnapshot(AData: TJSONObject; AFormat: Integer; out ASnapshot: TArchitectureSnapshot;
  out AError: string): Boolean;
var
  mReader: TSnapshotReader;
begin
  AError := '';
  mReader := TSnapshotReader.Create(AData, AFormat);
  try
    try
      ASnapshot := mReader.Read;
    except
      on E: EArchitectureSnapshot do
      begin
        ASnapshot := Default(TArchitectureSnapshot);
        AError := E.Message;
      end;
    end;
  finally
    mReader.Free;
  end;
  Result := AError = '';
end;

class function TArchitectureSnapshots.Parse(const AText: string; out ASnapshot: TArchitectureSnapshot;
  out AError: string): Boolean;
var
  mRoot: TJSONValue;
  mData: TJSONObject;
  mFormat: Integer;
begin
  ASnapshot := Default(TArchitectureSnapshot);
  AError := '';
  try
    mRoot := TJSONObject.ParseJSONValue(AText);
  except
    mRoot := nil;
  end;
  try
    if not (mRoot is TJSONObject) then
    begin
      AError := cTexts[TSnapshotText.ArchitectureStateIsNotA].Text;
      Exit(False);
    end;
    mData := SnapshotData(TJSONObject(mRoot));
    Result := CheckFormat(mData, mFormat, AError) and ReadSnapshot(mData, mFormat, ASnapshot, AError);
    if Result then
    begin
      Normalize(ASnapshot);
    end;
  finally
    mRoot.Free;
  end;
end;

class function TArchitectureSnapshots.Load(const AFileName: string; out ASnapshot: TArchitectureSnapshot;
  out AError: string): Boolean;
var
  mBytes: TBytes;
  mText: string;
begin
  ASnapshot := Default(TArchitectureSnapshot);
  if not TFile.Exists(AFileName) then
  begin
    AError := cTexts[TSnapshotText.ArchitectureStateNotFound].Fmt([AFileName]);
    Exit(False);
  end;
  try
    mBytes := TFile.ReadAllBytes(AFileName);
    // UTF-8, ein BOM fällt weg.
    if (Length(mBytes) >= 3) and (mBytes[0] = $EF) and (mBytes[1] = $BB) and (mBytes[2] = $BF) then
    begin
      mText := TEncoding.UTF8.GetString(mBytes, 3, Length(mBytes) - 3);
    end
    else
    begin
      mText := TEncoding.UTF8.GetString(mBytes);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Fehler geht als AError an den Aufrufer
    on E: Exception do
    begin
      AError := cTexts[TSnapshotText.ArchitectureStateNotReadable].Fmt([AFileName]) + E.Message;
      Exit(False);
    end;
  end;
  Result := Parse(mText, ASnapshot, AError);
  if not Result then
  begin
    AError := AFileName + ': ' + AError;
  end;
end;

class procedure TArchitectureSnapshots.Save(const AFileName: string; const ASnapshot: TArchitectureSnapshot);
var
  mFolder: string;
begin
  mFolder := ExtractFileDir(TPath.GetFullPath(AFileName));
  if mFolder <> '' then
  begin
    ForceDirectories(mFolder);
  end;
  TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(Json(ASnapshot)));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Architecture.Snapshot', cTexts);

end.
