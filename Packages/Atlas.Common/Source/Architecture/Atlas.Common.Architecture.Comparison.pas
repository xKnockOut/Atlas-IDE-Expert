unit Atlas.Common.Architecture.Comparison;

// Vergleich zweier Architekturstände (#1121) für Fenster, Bericht,
// get_architecture (compareWith) und AtlasServer --compare.
//
// Abschnitte (alt = gespeicherter Stand, neu = aktueller):
// - neue und entfernte Zyklen (derselbe Zyklus: dieselben Units, gleich wo der
//   Rundweg beginnt),
// - neue und entfernte Querverbindungen (Quelle und Ziel),
// - neue und entfernte uses-Kanten zwischen Teilsystemen (neu: im neuen Stand
//   über eine Teilsystemgrenze, im alten nicht vorhanden; entfernt umgekehrt),
// - Units mit Teilsystemwechsel,
// - zentrale Units (in einer der beiden Listen), deren „gesamt abhängig“ um
//   mehr als 10 % und um mindestens 5 gestiegen ist,
// - neue und entfernte Units.
// Teilsysteme werden nicht über die Nummer zugeordnet, sondern über die
// größte Überschneidung ihrer Units (bei Gleichstand gewinnt derselbe Name),
// je ein altes zu höchstens einem neuen; übrige mit gleichem Namen danach
// (TSubsystemMatcher im Modus Überschneidung, #1367).
// Eine Unit wechselt, wenn ihr neues Teilsystem einem anderen alten zugeordnet
// ist als dem, in dem sie stand, oder keinem.
// AddedEdges/DroppedEdges enthalten alle geänderten uses-Kanten für die Karte
// (neu grün, entfernt rot gestrichelt).
//
// JSON (Json, in der Antwort von atlas.architecture unter "comparison" und in
// den Daten des HTML-Berichts):
//   {"baseline": {"title": "Projekt", "units": 12, "edges": 30, "resolution": 1}, "resolution": 1,
//    "kinds": ["newCycle"], "failOn": ["newCycle"], "failed": ["newCycle"],
//    "newCycles": [{"interfaceOnly": false, "units": ["A", "B"]}], "removedCycles": [],
//    "newCrossLinks": [{"source": "A", "target": "C", "section": "implementation",
//                       "from": "Kern", "to": "UI", "reason": "rare"}], "removedCrossLinks": [],
//    "newEdges": [{"source": …, "target": …, "section": …, "from": …, "to": …}], "removedEdges": [],
//    "moves": [{"unit": "D", "from": "Kern", "to": "UI"}],
//    "growth": [{"unit": "E", "before": 20, "after": 30}],
//    "newUnits": ["F"], "removedUnits": [],
//    "addedEdges": [["A", "B", "i"]], "droppedEdges": [["B", "C", "m"]]}
// "from"/"to": Teilsystem im neuen Stand (neue Kanten) bzw. im alten (entfernte).
// Gruppierung (#1366): "baseline" nennt die Feinheit γ des gespeicherten Stands ("resolution"), "resolution"
// die des aktuellen. Weichen sie ab, nennen Text, Markdown und HTML-Bericht das als Hinweis: Teilsystemwechsel
// können dann allein daher kommen.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Matching;

type
  TArchitectureFailKind = (NewCycle, NewCrossLink, SubsystemChange, CentralGrowth);
  TArchitectureFailKinds = set of TArchitectureFailKind;

  TComparisonEdge = record
    Source: string;
    Target: string;
    Interface_: Boolean;
    FromSubsystem: string;
    ToSubsystem: string;
    /// <summary>Nur Querverbindungen: "rare" oder "againstDirection".</summary>
    Reason: string;
  end;

  TComparisonCycle = record
    InterfaceOnly: Boolean;
    Units: TArray<string>;
  end;

  TComparisonMove = record
    Unit_: string;
    FromSubsystem: string;
    ToSubsystem: string;
  end;

  TComparisonGrowth = record
    Unit_: string;
    Before: Integer;
    After: Integer;
  end;

  /// <summary>Neues Teilsystem und das alte, dem es zugeordnet ist ('' = keinem; #1367: dieselbe Zuordnung wie
  /// die Angleichung, Atlas.Common.Architecture.Matching).</summary>
  TComparisonMatch = TSubsystemMatch;

  TArchitectureComparison = record
    BaselineTitle: string;
    BaselineUnits: Integer;
    BaselineEdges: Integer;
    /// <summary>Gruppierung des gespeicherten bzw. des aktuellen Stands (#1366).</summary>
    BaselineGrouping: TArchitectureGrouping;
    Grouping: TArchitectureGrouping;
    NewCycles: TArray<TComparisonCycle>;
    RemovedCycles: TArray<TComparisonCycle>;
    NewCrossLinks: TArray<TComparisonEdge>;
    RemovedCrossLinks: TArray<TComparisonEdge>;
    /// <summary>uses-Kanten zwischen Teilsystemen.</summary>
    NewEdges: TArray<TComparisonEdge>;
    RemovedEdges: TArray<TComparisonEdge>;
    Moves: TArray<TComparisonMove>;
    Growth: TArray<TComparisonGrowth>;
    NewUnits: TArray<string>;
    RemovedUnits: TArray<string>;
    /// <summary>Alle neuen bzw. entfernten uses-Kanten (Karte).</summary>
    AddedEdges: TArray<TComparisonEdge>;
    DroppedEdges: TArray<TComparisonEdge>;
    Matches: TArray<TComparisonMatch>;
    /// <summary>Arten, die vorkommen (für --fail-on).</summary>
    function Kinds: TArchitectureFailKinds;
    /// <summary>Kein Abschnitt hat einen Eintrag.</summary>
    function IsEmpty: Boolean;
    /// <summary>Altes Teilsystem zum neuen ANewName; '' ohne Zuordnung.</summary>
    function MatchOf(const ANewName: string): string;
    /// <summary>Die beiden Stände wurden mit verschiedener Feinheit γ gerechnet (#1366).</summary>
    function ResolutionDiffers: Boolean;
    /// <summary>Hinweis auf verschiedene Feinheit; '' bei gleicher.</summary>
    function GroupingNote: string;
  end;

  TArchitectureComparer = class
  public const
    /// <summary>„gesamt abhängig“ muss um mehr als so viel Prozent und mindestens GrowthMinimum steigen.</summary>
    GrowthPercent = 10;
    GrowthMinimum = 5;
  public
    /// <summary>Vorgabe von architecture.failOn: [NewCycle].</summary>
    class function DefaultFailOn: TArchitectureFailKinds; static;
    class function Compare(const AOld, ANew: TArchitectureSnapshot): TArchitectureComparison; static;
    /// <summary>Gespeicherten Stand AFileName lesen und mit AOverview vergleichen; False mit AError, wenn die Datei
    /// fehlt oder nicht lesbar ist (TArchitectureSnapshots.Load).</summary>
    class function CompareWithFile(const AFileName: string; const AOverview: TArchitectureOverview;
      out AComparison: TArchitectureComparison; out AError: string): Boolean; static;
    /// <summary>Pfad eines Stands: absolut unverändert, sonst relativ zu ARoot.</summary>
    class function ResolvePath(const ARoot, APath: string): string; static;
    /// <summary>Zuordnung der Teilsysteme von ANew zu denen von AOld (siehe Kopf der Unit), nach neuem Namen.
    /// </summary>
    class function MatchSubsystems(const AOld, ANew: TArchitectureSnapshot): TArray<TComparisonMatch>; static;
    /// <summary>newCycle, newCrossLink, subsystemChange, centralGrowth.</summary>
    class function KindName(AKind: TArchitectureFailKind): string; static;
    /// <summary>Namen ohne Groß-/Kleinschreibung; False mit AError beim ersten unbekannten Namen.</summary>
    class function ParseKinds(const ANames: TArray<string>; out AKinds: TArchitectureFailKinds;
      out AError: string): Boolean; static;
    /// <summary>Wie ParseKinds für "newCycle,newCrossLink" (Komma oder Leerzeichen).</summary>
    class function ParseKindList(const AText: string; out AKinds: TArchitectureFailKinds;
      out AError: string): Boolean; static;
    class function KindNames(AKinds: TArchitectureFailKinds): TArray<string>; static;
    /// <summary>Text des Vergleichs für AtlasServer --compare und get_architecture; Listen auf ALimit gekürzt
    /// (0 = alles). Letzte Zeile: Ergebnis zu AFailOn.</summary>
    class function Text(const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds;
      ALimit: Integer): string; static;
    /// <summary>Abschnitt „## Vergleich“ des Markdown-Berichts.</summary>
    class function Markdown(const AComparison: TArchitectureComparison): string; static;
    /// <summary>Daten des Vergleichs (siehe Kopf der Unit).</summary>
    class function Json(const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string;
      static;
    /// <summary>"A → B → A".</summary>
    class function CyclePath(const ACycle: TComparisonCycle): string; static;
    /// <summary>"A → B (implementation)".</summary>
    class function EdgeText(const AEdge: TComparisonEdge): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TComparisonText = (NoteTheSavedStateWas, ThroughInterfaceOnly, ThroughImplementation, AgainstTheMainDirection,
    ArchitectureComparisonWithTheState, ResultNoChangeCountsAs, ResultNoChangeOfThe, ComparisonSWithTheSavedState,
    NoChanges, NewCycles, RemovedCycles, NewCrossLinks, RemovedCrossLinks, NewUsesEdgesBetweenSubsystems,
    RemovedUsesEdgesBetweenSubsystems, GrownCentralUnits, NewUnits, RemovedUnits, ResultChangeFailOn,
    UnknownDeviationAllowed, Rare, More, SubsystemChanges, GrowthLine);

const
  cTexts: array[TComparisonText] of TAtlasText = (
    (De: 'Hinweis: Der gespeicherte Stand wurde mit Feinheit γ = %s gerechnet, der aktuelle mit γ = %s; ' +
      'Teilsystemwechsel können daher kommen.';
     En: 'Note: the saved state was calculated with granularity γ = %s, the current one with γ = %s; subsystem moves ' +
      'may come from that.'),
    (De: 'nur über interface'; En: 'through interface only'),
    (De: 'über implementation'; En: 'through implementation'),
    (De: 'gegen die Hauptrichtung'; En: 'against the main direction'),
    (De: 'Architekturvergleich mit dem Stand „%s“ (%s Units, %s uses-Kanten)';
     En: 'Architecture comparison with the state “%s” (%s units, %s uses edges)'),
    (De: 'Ergebnis: keine Abweichung gilt als Fehler (fail-on leer)';
     En: 'Result: no change counts as an error (fail-on empty)'),
    (De: 'Ergebnis: keine Abweichung der Arten '; En: 'Result: no change of the kinds '),
    (De: '## Vergleich%s%sMit dem gespeicherten Stand „%s“ (%s Units, %s uses-Kanten).';
     En: '## Comparison%s%sWith the saved state “%s” (%s units, %s uses edges).'),
    (De: 'Keine Abweichung.'; En: 'No changes.'),
    (De: 'Neue Zyklen'; En: 'New cycles'),
    (De: 'Entfernte Zyklen'; En: 'Removed cycles'),
    (De: 'Neue Querverbindungen'; En: 'New cross links'),
    (De: 'Entfernte Querverbindungen'; En: 'Removed cross links'),
    (De: 'Neue uses-Kanten zwischen Teilsystemen'; En: 'New uses edges between subsystems'),
    (De: 'Entfernte uses-Kanten zwischen Teilsystemen'; En: 'Removed uses edges between subsystems'),
    (De: 'Gewachsene zentrale Units'; En: 'Grown central units'),
    (De: 'Neue Units'; En: 'New units'),
    (De: 'Entfernte Units'; En: 'Removed units'),
    (De: 'Ergebnis: Abweichung %s (fail-on %s)'; En: 'Result: change %s (fail-on %s)'),
    (De: 'Unbekannte Abweichung "%s" (erlaubt: %s)'; En: 'Unknown deviation "%s" (allowed: %s)'),
    (De: 'selten'; En: 'rare'),
    (De: '  … %s weitere'; En: '  … %s more'),
    (De: 'Teilsystemwechsel'; En: 'Subsystem changes'),
    (De: '%s: gesamt abhängig %s → %s (+%s, +%s %%)'; En: '%s: total dependents %s → %s (+%s, +%s %%)'));

const
  LineBreak = #13#10;
  KindNameList: array[TArchitectureFailKind] of string = ('newCycle', 'newCrossLink', 'subsystemChange',
    'centralGrowth');

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

{ TArchitectureComparison }

function TArchitectureComparison.ResolutionDiffers: Boolean;
begin
  Result := not TArchitectureGrouping.SameResolution(BaselineGrouping.Clamped.Resolution, Grouping.Clamped.Resolution);
end;

function TArchitectureComparison.GroupingNote: string;
begin
  Result := '';
  if ResolutionDiffers then
  begin
    Result := cTexts[TComparisonText.NoteTheSavedStateWas].Fmt([
      TArchitectureGrouping.ResolutionText(BaselineGrouping.Clamped.Resolution),
      TArchitectureGrouping.ResolutionText(Grouping.Clamped.Resolution)]);
  end;
end;

function TArchitectureComparison.Kinds: TArchitectureFailKinds;
begin
  Result := [];
  if Length(NewCycles) > 0 then
  begin
    Include(Result, TArchitectureFailKind.NewCycle);
  end;
  if Length(NewCrossLinks) > 0 then
  begin
    Include(Result, TArchitectureFailKind.NewCrossLink);
  end;
  if Length(Moves) > 0 then
  begin
    Include(Result, TArchitectureFailKind.SubsystemChange);
  end;
  if Length(Growth) > 0 then
  begin
    Include(Result, TArchitectureFailKind.CentralGrowth);
  end;
end;

function TArchitectureComparison.IsEmpty: Boolean;
begin
  Result := (Length(NewCycles) = 0) and (Length(RemovedCycles) = 0) and (Length(NewCrossLinks) = 0) and
    (Length(RemovedCrossLinks) = 0) and (Length(NewEdges) = 0) and (Length(RemovedEdges) = 0) and
    (Length(Moves) = 0) and (Length(Growth) = 0) and (Length(NewUnits) = 0) and (Length(RemovedUnits) = 0);
end;

function TArchitectureComparison.MatchOf(const ANewName: string): string;
var
  Match: TComparisonMatch;
begin
  for Match in Matches do
  begin
    if SameText(Match.NewName, ANewName) then
    begin
      Exit(Match.OldName);
    end;
  end;
  Result := '';
end;

{ TArchitectureComparer }

class function TArchitectureComparer.DefaultFailOn: TArchitectureFailKinds;
begin
  Result := [TArchitectureFailKind.NewCycle];
end;

class function TArchitectureComparer.KindName(AKind: TArchitectureFailKind): string;
begin
  Result := KindNameList[AKind];
end;

class function TArchitectureComparer.KindNames(AKinds: TArchitectureFailKinds): TArray<string>;
var
  Kind: TArchitectureFailKind;
begin
  Result := nil;
  for Kind := Low(TArchitectureFailKind) to High(TArchitectureFailKind) do
  begin
    if Kind in AKinds then
    begin
      Result := Result + [KindName(Kind)];
    end;
  end;
end;

class function TArchitectureComparer.ParseKinds(const ANames: TArray<string>; out AKinds: TArchitectureFailKinds;
  out AError: string): Boolean;
var
  Name: string;
  Kind: TArchitectureFailKind;
  Found: Boolean;
begin
  AKinds := [];
  AError := '';
  for Name in ANames do
  begin
    Found := False;
    for Kind := Low(TArchitectureFailKind) to High(TArchitectureFailKind) do
    begin
      if SameText(Trim(Name), KindName(Kind)) then
      begin
        Include(AKinds, Kind);
        Found := True;
      end;
    end;
    if not Found then
    begin
      AError := cTexts[TComparisonText.UnknownDeviationAllowed].Fmt([Name, string.Join(', ', KindNameList)]);
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TArchitectureComparer.ParseKindList(const AText: string; out AKinds: TArchitectureFailKinds;
  out AError: string): Boolean;
begin
  Result := ParseKinds(AText.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty), AKinds, AError);
end;

class function TArchitectureComparer.MatchSubsystems(const AOld, ANew: TArchitectureSnapshot)
  : TArray<TComparisonMatch>;
begin
  Result := TSubsystemMatcher.Match(AOld, ANew, TSubsystemMatchMode.Overlap);
end;

function UnitMap(const ASnapshot: TArchitectureSnapshot): TDictionary<string, Integer>;
var
  Index: Integer;
begin
  Result := TDictionary<string, Integer>.Create;
  for Index := 0 to High(ASnapshot.Units) do
  begin
    Result.AddOrSetValue(LowerCase(ASnapshot.Units[Index].Name), Index);
  end;
end;

function EdgeKeys(const AEdges: TArray<TSnapshotEdge>): TDictionary<string, Boolean>;
var
  Edge: TSnapshotEdge;
begin
  Result := TDictionary<string, Boolean>.Create;
  for Edge in AEdges do
  begin
    Result.AddOrSetValue(Edge.Key, True);
  end;
end;

function SubsystemOfUnit(const ASnapshot: TArchitectureSnapshot; AUnits: TDictionary<string, Integer>;
  const AName: string): string;
var
  Index: Integer;
begin
  if AUnits.TryGetValue(LowerCase(AName), Index) then
  begin
    Result := ASnapshot.Units[Index].Subsystem;
  end
  else
  begin
    Result := '';
  end;
end;

function ChangeOf(const AEdge: TSnapshotEdge; const ASnapshot: TArchitectureSnapshot;
  AUnits: TDictionary<string, Integer>): TComparisonEdge;
begin
  Result := Default(TComparisonEdge);
  Result.Source := AEdge.Source;
  Result.Target := AEdge.Target;
  Result.Interface_ := AEdge.Interface_;
  Result.FromSubsystem := SubsystemOfUnit(ASnapshot, AUnits, AEdge.Source);
  Result.ToSubsystem := SubsystemOfUnit(ASnapshot, AUnits, AEdge.Target);
end;

function CycleOf(const ACycle: TSnapshotCycle): TComparisonCycle;
begin
  Result.InterfaceOnly := ACycle.InterfaceOnly;
  Result.Units := Copy(ACycle.Units);
end;

function LinkOf(const ALink: TSnapshotCrossLink): TComparisonEdge;
begin
  Result := Default(TComparisonEdge);
  Result.Source := ALink.Edge.Source;
  Result.Target := ALink.Edge.Target;
  Result.Interface_ := ALink.Edge.Interface_;
  Result.FromSubsystem := ALink.FromSubsystem;
  Result.ToSubsystem := ALink.ToSubsystem;
  Result.Reason := ALink.Reason;
end;

function InList(const AName: string; const AList: TArray<string>): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kanten aus ASnapshot, die in AOtherKeys fehlen: alle in AAll, die zwischen Teilsystemen auch in
/// ACross.</summary>
procedure EdgesOnlyIn(const ASnapshot: TArchitectureSnapshot; AUnits: TDictionary<string, Integer>;
  const AOtherEdges: TArray<TSnapshotEdge>; var AAll, ACross: TArray<TComparisonEdge>);
var
  mOtherKeys: TDictionary<string, Boolean>;
  mEdge: TSnapshotEdge;
  mChange: TComparisonEdge;
begin
  mOtherKeys := EdgeKeys(AOtherEdges);
  try
    for mEdge in ASnapshot.Edges do
    begin
      if mOtherKeys.ContainsKey(mEdge.Key) then
      begin
        Continue;
      end;
      mChange := ChangeOf(mEdge, ASnapshot, AUnits);
      AAll := AAll + [mChange];
      if not SameText(mChange.FromSubsystem, mChange.ToSubsystem) then
      begin
        ACross := ACross + [mChange];
      end;
    end;
  finally
    mOtherKeys.Free;
  end;
end;

/// <summary>Zyklen aus ACycles, die in AOther fehlen.</summary>
function CyclesOnlyIn(const ACycles, AOther: TArray<TSnapshotCycle>): TArray<TComparisonCycle>;
var
  mKeys: TDictionary<string, Boolean>;
  mCycle: TSnapshotCycle;
begin
  Result := nil;
  mKeys := TDictionary<string, Boolean>.Create;
  try
    for mCycle in AOther do
    begin
      mKeys.AddOrSetValue(mCycle.Key, True);
    end;
    for mCycle in ACycles do
    begin
      if not mKeys.ContainsKey(mCycle.Key) then
      begin
        Result := Result + [CycleOf(mCycle)];
      end;
    end;
  finally
    mKeys.Free;
  end;
end;

/// <summary>Querverbindungen aus ALinks, die in AOther fehlen.</summary>
function CrossLinksOnlyIn(const ALinks, AOther: TArray<TSnapshotCrossLink>): TArray<TComparisonEdge>;
var
  mKeys: TDictionary<string, Boolean>;
  mLink: TSnapshotCrossLink;
begin
  Result := nil;
  mKeys := TDictionary<string, Boolean>.Create;
  try
    for mLink in AOther do
    begin
      mKeys.AddOrSetValue(mLink.Edge.Key, True);
    end;
    for mLink in ALinks do
    begin
      if not mKeys.ContainsKey(mLink.Edge.Key) then
      begin
        Result := Result + [LinkOf(mLink)];
      end;
    end;
  finally
    mKeys.Free;
  end;
end;

/// <summary>Zentrale Unit (alt oder neu), die um mindestens GrowthMinimum und GrowthPercent gewachsen ist.</summary>
function HasGrown(const AOld, ANew: TArchitectureSnapshot; const ANewUnit, AOldUnit: TSnapshotUnit): Boolean;
var
  mGrow: Integer;
begin
  mGrow := ANewUnit.Total - AOldUnit.Total;
  Result := (InList(ANewUnit.Name, ANew.Central) or InList(ANewUnit.Name, AOld.Central)) and
    (mGrow >= TArchitectureComparer.GrowthMinimum) and
    (mGrow * 100 > AOldUnit.Total * TArchitectureComparer.GrowthPercent);
end;

/// <summary>Eine Unit, die es in beiden Ständen gibt: Teilsystemwechsel und Wachstum.</summary>
procedure CompareUnit(var AResult: TArchitectureComparison; const AOld, ANew: TArchitectureSnapshot;
  const ANewUnit, AOldUnit: TSnapshotUnit);
var
  mMoved: TComparisonMove;
  mGrowth: TComparisonGrowth;
begin
  if not SameText(AResult.MatchOf(ANewUnit.Subsystem), AOldUnit.Subsystem) then
  begin
    mMoved.Unit_ := ANewUnit.Name;
    mMoved.FromSubsystem := AOldUnit.Subsystem;
    mMoved.ToSubsystem := ANewUnit.Subsystem;
    AResult.Moves := AResult.Moves + [mMoved];
  end;
  if HasGrown(AOld, ANew, ANewUnit, AOldUnit) then
  begin
    mGrowth.Unit_ := ANewUnit.Name;
    mGrowth.Before := AOldUnit.Total;
    mGrowth.After := ANewUnit.Total;
    AResult.Growth := AResult.Growth + [mGrowth];
  end;
end;

/// <summary>Units: neu, Teilsystemwechsel, Wachstum, entfallen.</summary>
procedure CompareUnits(var AResult: TArchitectureComparison; const AOld, ANew: TArchitectureSnapshot;
  AOldUnits, ANewUnits: TDictionary<string, Integer>);
var
  mItem: TSnapshotUnit;
  mIndex: Integer;
begin
  for mItem in ANew.Units do
  begin
    if AOldUnits.TryGetValue(LowerCase(mItem.Name), mIndex) then
    begin
      CompareUnit(AResult, AOld, ANew, mItem, AOld.Units[mIndex]);
    end
    else
    begin
      AResult.NewUnits := AResult.NewUnits + [mItem.Name];
    end;
  end;
  for mItem in AOld.Units do
  begin
    if not ANewUnits.ContainsKey(LowerCase(mItem.Name)) then
    begin
      AResult.RemovedUnits := AResult.RemovedUnits + [mItem.Name];
    end;
  end;
  // Stärkster Zuwachs zuerst, bei Gleichstand nach Name.
  TArray.Sort<TComparisonGrowth>(AResult.Growth, TComparer<TComparisonGrowth>.Construct(
    function(const ALeft, ARight: TComparisonGrowth): Integer
    begin
      Result := (ARight.After - ARight.Before) - (ALeft.After - ALeft.Before);
      if Result = 0 then
      begin
        Result := CompareNames(ALeft.Unit_, ARight.Unit_);
      end;
    end));
end;

class function TArchitectureComparer.Compare(const AOld, ANew: TArchitectureSnapshot): TArchitectureComparison;
var
  mOldUnits, mNewUnits: TDictionary<string, Integer>;
begin
  Result := Default(TArchitectureComparison);
  Result.BaselineTitle := AOld.Title;
  Result.BaselineUnits := Length(AOld.Units);
  Result.BaselineEdges := Length(AOld.Edges);
  Result.BaselineGrouping := AOld.Grouping.Clamped;
  Result.Grouping := ANew.Grouping.Clamped;
  Result.Matches := MatchSubsystems(AOld, ANew);
  mOldUnits := UnitMap(AOld);
  mNewUnits := UnitMap(ANew);
  try
    // uses-Kanten (die Snapshots sind sortiert, die Listen damit auch).
    EdgesOnlyIn(ANew, mNewUnits, AOld.Edges, Result.AddedEdges, Result.NewEdges);
    EdgesOnlyIn(AOld, mOldUnits, ANew.Edges, Result.DroppedEdges, Result.RemovedEdges);
    Result.NewCycles := CyclesOnlyIn(ANew.Cycles, AOld.Cycles);
    Result.RemovedCycles := CyclesOnlyIn(AOld.Cycles, ANew.Cycles);
    Result.NewCrossLinks := CrossLinksOnlyIn(ANew.CrossLinks, AOld.CrossLinks);
    Result.RemovedCrossLinks := CrossLinksOnlyIn(AOld.CrossLinks, ANew.CrossLinks);
    CompareUnits(Result, AOld, ANew, mOldUnits, mNewUnits);
  finally
    mOldUnits.Free;
    mNewUnits.Free;
  end;
end;

class function TArchitectureComparer.CompareWithFile(const AFileName: string; const AOverview: TArchitectureOverview;
  out AComparison: TArchitectureComparison; out AError: string): Boolean;
var
  Baseline: TArchitectureSnapshot;
begin
  AComparison := Default(TArchitectureComparison);
  Result := TArchitectureSnapshots.Load(AFileName, Baseline, AError);
  if Result then
  begin
    AComparison := Compare(Baseline, TArchitectureSnapshots.FromOverview(AOverview));
  end;
end;

class function TArchitectureComparer.ResolvePath(const ARoot, APath: string): string;
var
  Path: string;
begin
  Path := Trim(APath);
  if (Path = '') or (ARoot = '') or TPath.IsPathRooted(Path) then
  begin
    Exit(Path);
  end;
  Result := TPath.GetFullPath(TPath.Combine(ARoot, Path));
end;

class function TArchitectureComparer.CyclePath(const ACycle: TComparisonCycle): string;
begin
  Result := string.Join(' → ', ACycle.Units);
  if Length(ACycle.Units) > 0 then
  begin
    Result := Result + ' → ' + ACycle.Units[0];
  end;
end;

class function TArchitectureComparer.EdgeText(const AEdge: TComparisonEdge): string;
begin
  Result := AEdge.Source + ' → ' + AEdge.Target + ' (' + SectionText(AEdge.Interface_) + ')';
end;

function CycleCaption(const ACycle: TComparisonCycle): string;
begin
  if ACycle.InterfaceOnly then
  begin
    Result := cTexts[TComparisonText.ThroughInterfaceOnly].Text;
  end
  else
  begin
    Result := cTexts[TComparisonText.ThroughImplementation].Text;
  end;
end;

function ReasonCaption(const AReason: string): string;
begin
  if AReason = 'rare' then
  begin
    Result := cTexts[TComparisonText.Rare].Text;
  end
  else if AReason = 'againstDirection' then
  begin
    Result := cTexts[TComparisonText.AgainstTheMainDirection].Text;
  end
  else
  begin
    Result := AReason;
  end;
end;

function GrowthText(const AGrowth: TComparisonGrowth): string;
var
  Percent: Integer;
begin
  if AGrowth.Before > 0 then
  begin
    Percent := Round((AGrowth.After - AGrowth.Before) * 100 / AGrowth.Before);
  end
  else
  begin
    Percent := 100;
  end;
  Result := cTexts[TComparisonText.GrowthLine].Fmt([AGrowth.Unit_, IntToStr(AGrowth.Before),
    IntToStr(AGrowth.After), IntToStr(AGrowth.After - AGrowth.Before), IntToStr(Percent)]);
end;

function SubsystemPair(const AEdge: TComparisonEdge): string;
begin
  Result := AEdge.FromSubsystem + ' → ' + AEdge.ToSubsystem;
end;

/// <summary>Zeilen eines Abschnitts: Überschrift mit Zahl, je Eintrag eine eingerückte Zeile, gekürzt auf ALimit.
/// </summary>
function Section(const ATitle: string; const ALines: TArray<string>; ALimit: Integer): string;
var
  Index, Count: Integer;
begin
  Result := ATitle + ': ' + IntToStr(Length(ALines)) + LineBreak;
  Count := Length(ALines);
  if (ALimit > 0) and (Count > ALimit) then
  begin
    Count := ALimit;
  end;
  for Index := 0 to Count - 1 do
  begin
    Result := Result + '  ' + ALines[Index] + LineBreak;
  end;
  if Count < Length(ALines) then
  begin
    Result := Result + cTexts[TComparisonText.More].Fmt([IntToStr(Length(ALines) - Count)]) + LineBreak;
  end;
end;

function CycleLines(const ACycles: TArray<TComparisonCycle>): TArray<string>;
var
  Cycle: TComparisonCycle;
begin
  Result := nil;
  for Cycle in ACycles do
  begin
    Result := Result + [TArchitectureComparer.CyclePath(Cycle) + ' (' + CycleCaption(Cycle) + ')'];
  end;
end;

function LinkLines(const ALinks: TArray<TComparisonEdge>; AReason: Boolean): TArray<string>;
var
  Link: TComparisonEdge;
  Line: string;
begin
  Result := nil;
  for Link in ALinks do
  begin
    Line := TArchitectureComparer.EdgeText(Link) + ' ' + SubsystemPair(Link);
    if AReason and (Link.Reason <> '') then
    begin
      Line := Line + ', ' + ReasonCaption(Link.Reason);
    end;
    Result := Result + [Line];
  end;
end;

function MoveLines(const AMoves: TArray<TComparisonMove>): TArray<string>;
var
  Moved: TComparisonMove;
begin
  Result := nil;
  for Moved in AMoves do
  begin
    Result := Result + [Moved.Unit_ + ': ' + Moved.FromSubsystem + ' → ' + Moved.ToSubsystem];
  end;
end;

function GrowthLines(const AGrowth: TArray<TComparisonGrowth>): TArray<string>;
var
  Growth: TComparisonGrowth;
begin
  Result := nil;
  for Growth in AGrowth do
  begin
    Result := Result + [GrowthText(Growth)];
  end;
end;

class function TArchitectureComparer.Text(const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds;
  ALimit: Integer): string;
var
  Failed: TArchitectureFailKinds;
begin
  Result := cTexts[TComparisonText.ArchitectureComparisonWithTheState].Fmt([AComparison.BaselineTitle,
    IntToStr(AComparison.BaselineUnits), IntToStr(AComparison.BaselineEdges)]) +
    LineBreak;
  if AComparison.GroupingNote <> '' then
  begin
    Result := Result + AComparison.GroupingNote + LineBreak;
  end;
  Result := Result + Section(cTexts[TComparisonText.NewCycles].Text, CycleLines(AComparison.NewCycles), ALimit) +
    Section(cTexts[TComparisonText.RemovedCycles].Text, CycleLines(AComparison.RemovedCycles), ALimit) +
    Section(cTexts[TComparisonText.NewCrossLinks].Text, LinkLines(AComparison.NewCrossLinks, True), ALimit) +
    Section(cTexts[TComparisonText.RemovedCrossLinks].Text, LinkLines(AComparison.RemovedCrossLinks, True), ALimit) +
    Section(cTexts[TComparisonText.NewUsesEdgesBetweenSubsystems].Text, LinkLines(AComparison.NewEdges, False),
      ALimit) +
    Section(cTexts[TComparisonText.RemovedUsesEdgesBetweenSubsystems].Text, LinkLines(AComparison.RemovedEdges, False),
      ALimit) +
    Section(cTexts[TComparisonText.SubsystemChanges].Text, MoveLines(AComparison.Moves), ALimit) +
    Section(cTexts[TComparisonText.GrownCentralUnits].Text, GrowthLines(AComparison.Growth), ALimit) +
    Section(cTexts[TComparisonText.NewUnits].Text, AComparison.NewUnits, ALimit) +
    Section(cTexts[TComparisonText.RemovedUnits].Text, AComparison.RemovedUnits, ALimit);
  Failed := AComparison.Kinds * AFailOn;
  if AFailOn = [] then
  begin
    Result := Result + cTexts[TComparisonText.ResultNoChangeCountsAs].Text;
  end
  else if Failed = [] then
  begin
    Result := Result + cTexts[TComparisonText.ResultNoChangeOfThe].Text + string.Join(', ', KindNames(AFailOn));
  end
  else
  begin
    Result := Result + cTexts[TComparisonText.ResultChangeFailOn].Fmt([string.Join(', ', KindNames(Failed)),
      string.Join(', ', KindNames(AFailOn))]);
  end;
end;

function ResolutionJson(const AGrouping: TArchitectureGrouping): string;
begin
  Result := FormatFloat('0.###', AGrouping.Clamped.Resolution, TFormatSettings.Invariant);
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

function MarkdownList(const ATitle: string; const ALines: TArray<string>): string;
var
  Line: string;
begin
  Result := '### ' + ATitle + ' (' + IntToStr(Length(ALines)) + ')' + LineBreak + LineBreak;
  if Length(ALines) = 0 then
  begin
    Exit(Result + 'Keine.' + LineBreak + LineBreak);
  end;
  for Line in ALines do
  begin
    Result := Result + '- ' + Cell(Line) + LineBreak;
  end;
  Result := Result + LineBreak;
end;

class function TArchitectureComparer.Markdown(const AComparison: TArchitectureComparison): string;
begin
  Result := cTexts[TComparisonText.ComparisonSWithTheSavedState].Fmt([LineBreak, LineBreak, AComparison.BaselineTitle,
    IntToStr(AComparison.BaselineUnits), IntToStr(AComparison.BaselineEdges)]) + LineBreak + LineBreak;
  if AComparison.GroupingNote <> '' then
  begin
    Result := Result + AComparison.GroupingNote + LineBreak + LineBreak;
  end;
  if AComparison.IsEmpty then
  begin
    Result := Result + cTexts[TComparisonText.NoChanges].Text + LineBreak + LineBreak;
  end;
  Result := Result + MarkdownList(cTexts[TComparisonText.NewCycles].Text, CycleLines(AComparison.NewCycles)) +
    MarkdownList(cTexts[TComparisonText.RemovedCycles].Text, CycleLines(AComparison.RemovedCycles)) +
    MarkdownList(cTexts[TComparisonText.NewCrossLinks].Text, LinkLines(AComparison.NewCrossLinks, True)) +
    MarkdownList(cTexts[TComparisonText.RemovedCrossLinks].Text, LinkLines(AComparison.RemovedCrossLinks, True)) +
    MarkdownList(cTexts[TComparisonText.NewUsesEdgesBetweenSubsystems].Text, LinkLines(AComparison.NewEdges, False)) +
    MarkdownList(cTexts[TComparisonText.RemovedUsesEdgesBetweenSubsystems].Text, LinkLines(AComparison.RemovedEdges,
      False)) +
    MarkdownList(cTexts[TComparisonText.SubsystemChanges].Text, MoveLines(AComparison.Moves)) +
    MarkdownList(cTexts[TComparisonText.GrownCentralUnits].Text, GrowthLines(AComparison.Growth)) +
    MarkdownList(cTexts[TComparisonText.NewUnits].Text, AComparison.NewUnits) +
    MarkdownList(cTexts[TComparisonText.RemovedUnits].Text, AComparison.RemovedUnits);
end;

function JsonText(const AText: string): string;
begin
  Result := TMetricsReport.JsonString(AText);
end;

function JsonNames(const ANames: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(ANames) do
  begin
    if Index > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + JsonText(ANames[Index]);
  end;
  Result := Result + ']';
end;

function CyclesJson(const ACycles: TArray<TComparisonCycle>): string;
var
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(ACycles) do
  begin
    if Index > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + '{"interfaceOnly":' + LowerCase(BoolToStr(ACycles[Index].InterfaceOnly, True)) +
      ',"units":' + JsonNames(ACycles[Index].Units) + '}';
  end;
  Result := Result + ']';
end;

function EdgesJson(const AEdges: TArray<TComparisonEdge>; AReason: Boolean): string;
var
  Index: Integer;
  Edge: TComparisonEdge;
begin
  Result := '[';
  for Index := 0 to High(AEdges) do
  begin
    Edge := AEdges[Index];
    if Index > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + '{"source":' + JsonText(Edge.Source) + ',"target":' + JsonText(Edge.Target) + ',"section":' +
      JsonText(SectionText(Edge.Interface_)) + ',"from":' + JsonText(Edge.FromSubsystem) + ',"to":' +
      JsonText(Edge.ToSubsystem);
    if AReason then
    begin
      Result := Result + ',"reason":' + JsonText(Edge.Reason);
    end;
    Result := Result + '}';
  end;
  Result := Result + ']';
end;

function MapEdgesJson(const AEdges: TArray<TComparisonEdge>): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('[');
    for Index := 0 to High(AEdges) do
    begin
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      // Höchstens 20 Kanten je Zeile: Zeilen über 1023 Zeichen machen erzeugte Dateien unhandlich.
      if (Index > 0) and (Index mod 20 = 0) then
      begin
        Builder.Append(LineBreak);
      end;
      Builder.Append('[').Append(JsonText(AEdges[Index].Source)).Append(',').Append(JsonText(AEdges[Index].Target));
      if AEdges[Index].Interface_ then
      begin
        Builder.Append(',"i"]');
      end
      else
      begin
        Builder.Append(',"m"]');
      end;
    end;
    Builder.Append(']');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TArchitectureComparer.Json(const AComparison: TArchitectureComparison;
  AFailOn: TArchitectureFailKinds): string;
var
  Moves, Growth: string;
  Index: Integer;
begin
  Moves := '[';
  for Index := 0 to High(AComparison.Moves) do
  begin
    if Index > 0 then
    begin
      Moves := Moves + ',';
    end;
    Moves := Moves + '{"unit":' + JsonText(AComparison.Moves[Index].Unit_) + ',"from":' +
      JsonText(AComparison.Moves[Index].FromSubsystem) + ',"to":' + JsonText(AComparison.Moves[Index].ToSubsystem) +
      '}';
  end;
  Moves := Moves + ']';
  Growth := '[';
  for Index := 0 to High(AComparison.Growth) do
  begin
    if Index > 0 then
    begin
      Growth := Growth + ',';
    end;
    Growth := Growth + '{"unit":' + JsonText(AComparison.Growth[Index].Unit_) + ',"before":' +
      IntToStr(AComparison.Growth[Index].Before) + ',"after":' + IntToStr(AComparison.Growth[Index].After) + '}';
  end;
  Growth := Growth + ']';
  Result := '{"baseline":{"title":' + JsonText(AComparison.BaselineTitle) + ',"units":' +
    IntToStr(AComparison.BaselineUnits) + ',"edges":' + IntToStr(AComparison.BaselineEdges) + ',"resolution":' +
    ResolutionJson(AComparison.BaselineGrouping) + '}' + LineBreak + ',"resolution":' +
    ResolutionJson(AComparison.Grouping) + LineBreak +
    ',"kinds":' + JsonNames(KindNames(AComparison.Kinds)) + ',"failOn":' + JsonNames(KindNames(AFailOn)) +
    ',"failed":' + JsonNames(KindNames(AComparison.Kinds * AFailOn)) + LineBreak +
    ',"newCycles":' + CyclesJson(AComparison.NewCycles) + LineBreak +
    ',"removedCycles":' + CyclesJson(AComparison.RemovedCycles) + LineBreak +
    ',"newCrossLinks":' + EdgesJson(AComparison.NewCrossLinks, True) + LineBreak +
    ',"removedCrossLinks":' + EdgesJson(AComparison.RemovedCrossLinks, True) + LineBreak +
    ',"newEdges":' + EdgesJson(AComparison.NewEdges, False) + LineBreak +
    ',"removedEdges":' + EdgesJson(AComparison.RemovedEdges, False) + LineBreak +
    ',"moves":' + Moves + LineBreak + ',"growth":' + Growth + LineBreak +
    ',"newUnits":' + JsonNames(AComparison.NewUnits) + LineBreak +
    ',"removedUnits":' + JsonNames(AComparison.RemovedUnits) + LineBreak +
    ',"addedEdges":' + MapEdgesJson(AComparison.AddedEdges) + LineBreak +
    ',"droppedEdges":' + MapEdgesJson(AComparison.DroppedEdges) + '}';
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Architecture.Comparison', cTexts);

end.
