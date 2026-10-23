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
// je ein altes zu höchstens einem neuen; übrige mit gleichem Namen danach.
// Eine Unit wechselt, wenn ihr neues Teilsystem einem anderen alten zugeordnet
// ist als dem, in dem sie stand, oder keinem.
// AddedEdges/DroppedEdges enthalten alle geänderten uses-Kanten für die Karte
// (neu grün, entfernt rot gestrichelt).
//
// JSON (Json, in der Antwort von atlas.architecture unter "comparison" und in
// den Daten des HTML-Berichts):
//   {"baseline": {"title": "Projekt", "units": 12, "edges": 30},
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

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Snapshot;

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

  /// <summary>Neues Teilsystem und das alte, dem es zugeordnet ist ('' = keinem).</summary>
  TComparisonMatch = record
    NewName: string;
    OldName: string;
  end;

  TArchitectureComparison = record
    BaselineTitle: string;
    BaselineUnits: Integer;
    BaselineEdges: Integer;
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
  Atlas.Common.Metrics.Report;

const
  LineBreak = #13#10;
  KindNameList: array[TArchitectureFailKind] of string = ('newCycle', 'newCrossLink', 'subsystemChange',
    'centralGrowth');

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

{ TArchitectureComparison }

function TArchitectureComparison.Kinds: TArchitectureFailKinds;
begin
  Result := [];
  if Length(NewCycles) > 0 then
    Include(Result, TArchitectureFailKind.NewCycle);
  if Length(NewCrossLinks) > 0 then
    Include(Result, TArchitectureFailKind.NewCrossLink);
  if Length(Moves) > 0 then
    Include(Result, TArchitectureFailKind.SubsystemChange);
  if Length(Growth) > 0 then
    Include(Result, TArchitectureFailKind.CentralGrowth);
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
    if SameText(Match.NewName, ANewName) then
      Exit(Match.OldName);
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
    if Kind in AKinds then
      Result := Result + [KindName(Kind)];
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
      if SameText(Trim(Name), KindName(Kind)) then
      begin
        Include(AKinds, Kind);
        Found := True;
      end;
    if not Found then
    begin
      AError := 'Unbekannte Abweichung "' + Name + '" (erlaubt: ' + string.Join(', ', KindNameList) + ')';
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

type
  TMatchCandidate = record
    NewIndex: Integer;
    OldIndex: Integer;
    Overlap: Integer;
    SameName: Boolean;
  end;

/// <summary>Teilsystemnamen eines Stands mit ihren Units (klein geschrieben); Units ohne Eintrag in Subsystems
/// zählen über ihr Feld Subsystem mit.</summary>
function GroupsOf(const ASnapshot: TArchitectureSnapshot;
  out ANames: TArray<string>): TArray<TDictionary<string, Boolean>>;
var
  Index, Group: Integer;
  Item: TSnapshotUnit;
  Lookup: TDictionary<string, Integer>;
  Key: string;
begin
  ANames := nil;
  Result := nil;
  Lookup := TDictionary<string, Integer>.Create;
  try
    for Index := 0 to High(ASnapshot.Subsystems) do
    begin
      Key := LowerCase(ASnapshot.Subsystems[Index].Name);
      if Lookup.ContainsKey(Key) then
        Continue;
      Lookup.Add(Key, Length(ANames));
      ANames := ANames + [ASnapshot.Subsystems[Index].Name];
      Result := Result + [TDictionary<string, Boolean>.Create];
    end;
    for Item in ASnapshot.Units do
    begin
      Key := LowerCase(Item.Subsystem);
      if not Lookup.TryGetValue(Key, Group) then
      begin
        Group := Length(ANames);
        Lookup.Add(Key, Group);
        ANames := ANames + [Item.Subsystem];
        Result := Result + [TDictionary<string, Boolean>.Create];
      end;
      Result[Group].AddOrSetValue(LowerCase(Item.Name), True);
    end;
  finally
    Lookup.Free;
  end;
end;

procedure FreeGroups(const AGroups: TArray<TDictionary<string, Boolean>>);
var
  Group: TDictionary<string, Boolean>;
begin
  for Group in AGroups do
    Group.Free;
end;

class function TArchitectureComparer.MatchSubsystems(const AOld, ANew: TArchitectureSnapshot)
  : TArray<TComparisonMatch>;
var
  OldNames, NewNames: TArray<string>;
  OldGroups, NewGroups: TArray<TDictionary<string, Boolean>>;
  Candidates: TList<TMatchCandidate>;
  Candidate: TMatchCandidate;
  NewIndex, OldIndex, Overlap: Integer;
  Key: string;
  OldTaken: TArray<Boolean>;
  Assigned_: TArray<Integer>;
begin
  OldGroups := GroupsOf(AOld, OldNames);
  NewGroups := nil;
  Candidates := nil;
  try
    NewGroups := GroupsOf(ANew, NewNames);
    Candidates := TList<TMatchCandidate>.Create;
    for NewIndex := 0 to High(NewGroups) do
      for OldIndex := 0 to High(OldGroups) do
      begin
        Overlap := 0;
        for Key in NewGroups[NewIndex].Keys do
          if OldGroups[OldIndex].ContainsKey(Key) then
            Inc(Overlap);
        if Overlap = 0 then
          Continue;
        Candidate.NewIndex := NewIndex;
        Candidate.OldIndex := OldIndex;
        Candidate.Overlap := Overlap;
        Candidate.SameName := SameText(NewNames[NewIndex], OldNames[OldIndex]);
        Candidates.Add(Candidate);
      end;
    // Größte Überschneidung zuerst, bei Gleichstand derselbe Name, dann nach Namen (eindeutig).
    Candidates.Sort(TComparer<TMatchCandidate>.Construct(
      function(const ALeft, ARight: TMatchCandidate): Integer
      begin
        Result := ARight.Overlap - ALeft.Overlap;
        if Result = 0 then
          Result := Ord(ARight.SameName) - Ord(ALeft.SameName);
        if Result = 0 then
          Result := CompareNames(NewNames[ALeft.NewIndex], NewNames[ARight.NewIndex]);
        if Result = 0 then
          Result := CompareNames(OldNames[ALeft.OldIndex], OldNames[ARight.OldIndex]);
      end));
    SetLength(OldTaken, Length(OldGroups));
    SetLength(Assigned_, Length(NewGroups));
    for NewIndex := 0 to High(Assigned_) do
      Assigned_[NewIndex] := -1;
    for Candidate in Candidates do
      if (Assigned_[Candidate.NewIndex] < 0) and not OldTaken[Candidate.OldIndex] then
      begin
        Assigned_[Candidate.NewIndex] := Candidate.OldIndex;
        OldTaken[Candidate.OldIndex] := True;
      end;
    // Ohne gemeinsame Units: derselbe Name, wenn das alte Teilsystem noch frei ist.
    for NewIndex := 0 to High(Assigned_) do
      if Assigned_[NewIndex] < 0 then
        for OldIndex := 0 to High(OldNames) do
          if not OldTaken[OldIndex] and SameText(OldNames[OldIndex], NewNames[NewIndex]) then
          begin
            Assigned_[NewIndex] := OldIndex;
            OldTaken[OldIndex] := True;
            Break;
          end;
    SetLength(Result, Length(NewNames));
    for NewIndex := 0 to High(NewNames) do
    begin
      Result[NewIndex].NewName := NewNames[NewIndex];
      if Assigned_[NewIndex] >= 0 then
        Result[NewIndex].OldName := OldNames[Assigned_[NewIndex]]
      else
        Result[NewIndex].OldName := '';
    end;
    TArray.Sort<TComparisonMatch>(Result, TComparer<TComparisonMatch>.Construct(
      function(const ALeft, ARight: TComparisonMatch): Integer
      begin
        Result := CompareNames(ALeft.NewName, ARight.NewName);
      end));
  finally
    Candidates.Free;
    FreeGroups(OldGroups);
    FreeGroups(NewGroups);
  end;
end;

function UnitMap(const ASnapshot: TArchitectureSnapshot): TDictionary<string, Integer>;
var
  Index: Integer;
begin
  Result := TDictionary<string, Integer>.Create;
  for Index := 0 to High(ASnapshot.Units) do
    Result.AddOrSetValue(LowerCase(ASnapshot.Units[Index].Name), Index);
end;

function EdgeKeys(const AEdges: TArray<TSnapshotEdge>): TDictionary<string, Boolean>;
var
  Edge: TSnapshotEdge;
begin
  Result := TDictionary<string, Boolean>.Create;
  for Edge in AEdges do
    Result.AddOrSetValue(Edge.Key, True);
end;

function SubsystemOfUnit(const ASnapshot: TArchitectureSnapshot; AUnits: TDictionary<string, Integer>;
  const AName: string): string;
var
  Index: Integer;
begin
  if AUnits.TryGetValue(LowerCase(AName), Index) then
    Result := ASnapshot.Units[Index].Subsystem
  else
    Result := '';
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
    if SameText(Item, AName) then
      Exit(True);
  Result := False;
end;

class function TArchitectureComparer.Compare(const AOld, ANew: TArchitectureSnapshot): TArchitectureComparison;
var
  OldUnits, NewUnits: TDictionary<string, Integer>;
  OldEdges, NewEdges, Keys: TDictionary<string, Boolean>;
  Edge: TSnapshotEdge;
  Change: TComparisonEdge;
  Cycle: TSnapshotCycle;
  Link: TSnapshotCrossLink;
  Item: TSnapshotUnit;
  Index, Grow: Integer;
  OldSubsystem: string;
  Moved: TComparisonMove;
  Growth: TComparisonGrowth;
begin
  Result := Default(TArchitectureComparison);
  Result.BaselineTitle := AOld.Title;
  Result.BaselineUnits := Length(AOld.Units);
  Result.BaselineEdges := Length(AOld.Edges);
  Result.Matches := MatchSubsystems(AOld, ANew);
  OldUnits := UnitMap(AOld);
  NewUnits := UnitMap(ANew);
  OldEdges := EdgeKeys(AOld.Edges);
  NewEdges := EdgeKeys(ANew.Edges);
  Keys := TDictionary<string, Boolean>.Create;
  try
    // uses-Kanten (die Snapshots sind sortiert, die Listen damit auch).
    for Edge in ANew.Edges do
      if not OldEdges.ContainsKey(Edge.Key) then
      begin
        Change := ChangeOf(Edge, ANew, NewUnits);
        Result.AddedEdges := Result.AddedEdges + [Change];
        if not SameText(Change.FromSubsystem, Change.ToSubsystem) then
          Result.NewEdges := Result.NewEdges + [Change];
      end;
    for Edge in AOld.Edges do
      if not NewEdges.ContainsKey(Edge.Key) then
      begin
        Change := ChangeOf(Edge, AOld, OldUnits);
        Result.DroppedEdges := Result.DroppedEdges + [Change];
        if not SameText(Change.FromSubsystem, Change.ToSubsystem) then
          Result.RemovedEdges := Result.RemovedEdges + [Change];
      end;
    // Zyklen.
    Keys.Clear;
    for Cycle in AOld.Cycles do
      Keys.AddOrSetValue(Cycle.Key, True);
    for Cycle in ANew.Cycles do
      if not Keys.ContainsKey(Cycle.Key) then
        Result.NewCycles := Result.NewCycles + [CycleOf(Cycle)];
    Keys.Clear;
    for Cycle in ANew.Cycles do
      Keys.AddOrSetValue(Cycle.Key, True);
    for Cycle in AOld.Cycles do
      if not Keys.ContainsKey(Cycle.Key) then
        Result.RemovedCycles := Result.RemovedCycles + [CycleOf(Cycle)];
    // Querverbindungen.
    Keys.Clear;
    for Link in AOld.CrossLinks do
      Keys.AddOrSetValue(Link.Edge.Key, True);
    for Link in ANew.CrossLinks do
      if not Keys.ContainsKey(Link.Edge.Key) then
        Result.NewCrossLinks := Result.NewCrossLinks + [LinkOf(Link)];
    Keys.Clear;
    for Link in ANew.CrossLinks do
      Keys.AddOrSetValue(Link.Edge.Key, True);
    for Link in AOld.CrossLinks do
      if not Keys.ContainsKey(Link.Edge.Key) then
        Result.RemovedCrossLinks := Result.RemovedCrossLinks + [LinkOf(Link)];
    // Units: neu, Teilsystemwechsel, Wachstum.
    for Item in ANew.Units do
    begin
      if not OldUnits.TryGetValue(LowerCase(Item.Name), Index) then
      begin
        Result.NewUnits := Result.NewUnits + [Item.Name];
        Continue;
      end;
      OldSubsystem := AOld.Units[Index].Subsystem;
      if not SameText(Result.MatchOf(Item.Subsystem), OldSubsystem) then
      begin
        Moved.Unit_ := Item.Name;
        Moved.FromSubsystem := OldSubsystem;
        Moved.ToSubsystem := Item.Subsystem;
        Result.Moves := Result.Moves + [Moved];
      end;
      Grow := Item.Total - AOld.Units[Index].Total;
      if (InList(Item.Name, ANew.Central) or InList(Item.Name, AOld.Central)) and (Grow >= GrowthMinimum) and
        (Grow * 100 > AOld.Units[Index].Total * GrowthPercent) then
      begin
        Growth.Unit_ := Item.Name;
        Growth.Before := AOld.Units[Index].Total;
        Growth.After := Item.Total;
        Result.Growth := Result.Growth + [Growth];
      end;
    end;
    for Item in AOld.Units do
      if not NewUnits.ContainsKey(LowerCase(Item.Name)) then
        Result.RemovedUnits := Result.RemovedUnits + [Item.Name];
    // Stärkster Zuwachs zuerst, bei Gleichstand nach Name.
    TArray.Sort<TComparisonGrowth>(Result.Growth, TComparer<TComparisonGrowth>.Construct(
      function(const ALeft, ARight: TComparisonGrowth): Integer
      begin
        Result := (ARight.After - ARight.Before) - (ALeft.After - ALeft.Before);
        if Result = 0 then
          Result := CompareNames(ALeft.Unit_, ARight.Unit_);
      end));
  finally
    Keys.Free;
    OldEdges.Free;
    NewEdges.Free;
    OldUnits.Free;
    NewUnits.Free;
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
    AComparison := Compare(Baseline, TArchitectureSnapshots.FromOverview(AOverview));
end;

class function TArchitectureComparer.ResolvePath(const ARoot, APath: string): string;
var
  Path: string;
begin
  Path := Trim(APath);
  if (Path = '') or (ARoot = '') or TPath.IsPathRooted(Path) then
    Exit(Path);
  Result := TPath.GetFullPath(TPath.Combine(ARoot, Path));
end;

class function TArchitectureComparer.CyclePath(const ACycle: TComparisonCycle): string;
begin
  Result := string.Join(' → ', ACycle.Units);
  if Length(ACycle.Units) > 0 then
    Result := Result + ' → ' + ACycle.Units[0];
end;

class function TArchitectureComparer.EdgeText(const AEdge: TComparisonEdge): string;
begin
  Result := AEdge.Source + ' → ' + AEdge.Target + ' (' + SectionText(AEdge.Interface_) + ')';
end;

function CycleCaption(const ACycle: TComparisonCycle): string;
begin
  if ACycle.InterfaceOnly then
    Result := 'nur über interface'
  else
    Result := 'über implementation';
end;

function ReasonCaption(const AReason: string): string;
begin
  if AReason = 'rare' then
    Result := 'selten'
  else if AReason = 'againstDirection' then
    Result := 'gegen die Hauptrichtung'
  else
    Result := AReason;
end;

function GrowthText(const AGrowth: TComparisonGrowth): string;
var
  Percent: Integer;
begin
  if AGrowth.Before > 0 then
    Percent := Round((AGrowth.After - AGrowth.Before) * 100 / AGrowth.Before)
  else
    Percent := 100;
  Result := AGrowth.Unit_ + ': gesamt abhängig ' + IntToStr(AGrowth.Before) + ' → ' + IntToStr(AGrowth.After) +
    ' (+' + IntToStr(AGrowth.After - AGrowth.Before) + ', +' + IntToStr(Percent) + ' %)';
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
    Count := ALimit;
  for Index := 0 to Count - 1 do
    Result := Result + '  ' + ALines[Index] + LineBreak;
  if Count < Length(ALines) then
    Result := Result + '  … ' + IntToStr(Length(ALines) - Count) + ' weitere' + LineBreak;
end;

function CycleLines(const ACycles: TArray<TComparisonCycle>): TArray<string>;
var
  Cycle: TComparisonCycle;
begin
  Result := nil;
  for Cycle in ACycles do
    Result := Result + [TArchitectureComparer.CyclePath(Cycle) + ' (' + CycleCaption(Cycle) + ')'];
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
      Line := Line + ', ' + ReasonCaption(Link.Reason);
    Result := Result + [Line];
  end;
end;

function MoveLines(const AMoves: TArray<TComparisonMove>): TArray<string>;
var
  Moved: TComparisonMove;
begin
  Result := nil;
  for Moved in AMoves do
    Result := Result + [Moved.Unit_ + ': ' + Moved.FromSubsystem + ' → ' + Moved.ToSubsystem];
end;

function GrowthLines(const AGrowth: TArray<TComparisonGrowth>): TArray<string>;
var
  Growth: TComparisonGrowth;
begin
  Result := nil;
  for Growth in AGrowth do
    Result := Result + [GrowthText(Growth)];
end;

class function TArchitectureComparer.Text(const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds;
  ALimit: Integer): string;
var
  Failed: TArchitectureFailKinds;
begin
  Result := 'Architekturvergleich mit dem Stand „' + AComparison.BaselineTitle + '“ (' +
    IntToStr(AComparison.BaselineUnits) + ' Units, ' + IntToStr(AComparison.BaselineEdges) + ' uses-Kanten)' +
    LineBreak;
  Result := Result + Section('Neue Zyklen', CycleLines(AComparison.NewCycles), ALimit) +
    Section('Entfernte Zyklen', CycleLines(AComparison.RemovedCycles), ALimit) +
    Section('Neue Querverbindungen', LinkLines(AComparison.NewCrossLinks, True), ALimit) +
    Section('Entfernte Querverbindungen', LinkLines(AComparison.RemovedCrossLinks, True), ALimit) +
    Section('Neue uses-Kanten zwischen Teilsystemen', LinkLines(AComparison.NewEdges, False), ALimit) +
    Section('Entfernte uses-Kanten zwischen Teilsystemen', LinkLines(AComparison.RemovedEdges, False), ALimit) +
    Section('Teilsystemwechsel', MoveLines(AComparison.Moves), ALimit) +
    Section('Gewachsene zentrale Units', GrowthLines(AComparison.Growth), ALimit) +
    Section('Neue Units', AComparison.NewUnits, ALimit) +
    Section('Entfernte Units', AComparison.RemovedUnits, ALimit);
  Failed := AComparison.Kinds * AFailOn;
  if AFailOn = [] then
    Result := Result + 'Ergebnis: keine Abweichung gilt als Fehler (fail-on leer)'
  else if Failed = [] then
    Result := Result + 'Ergebnis: keine Abweichung der Arten ' + string.Join(', ', KindNames(AFailOn))
  else
    Result := Result + 'Ergebnis: Abweichung ' + string.Join(', ', KindNames(Failed)) + ' (fail-on ' +
      string.Join(', ', KindNames(AFailOn)) + ')';
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
    Exit(Result + 'Keine.' + LineBreak + LineBreak);
  for Line in ALines do
    Result := Result + '- ' + Cell(Line) + LineBreak;
  Result := Result + LineBreak;
end;

class function TArchitectureComparer.Markdown(const AComparison: TArchitectureComparison): string;
begin
  Result := '## Vergleich' + LineBreak + LineBreak + 'Mit dem gespeicherten Stand „' + AComparison.BaselineTitle +
    '“ (' + IntToStr(AComparison.BaselineUnits) + ' Units, ' + IntToStr(AComparison.BaselineEdges) +
    ' uses-Kanten).' + LineBreak + LineBreak;
  if AComparison.IsEmpty then
    Result := Result + 'Keine Abweichung.' + LineBreak + LineBreak;
  Result := Result + MarkdownList('Neue Zyklen', CycleLines(AComparison.NewCycles)) +
    MarkdownList('Entfernte Zyklen', CycleLines(AComparison.RemovedCycles)) +
    MarkdownList('Neue Querverbindungen', LinkLines(AComparison.NewCrossLinks, True)) +
    MarkdownList('Entfernte Querverbindungen', LinkLines(AComparison.RemovedCrossLinks, True)) +
    MarkdownList('Neue uses-Kanten zwischen Teilsystemen', LinkLines(AComparison.NewEdges, False)) +
    MarkdownList('Entfernte uses-Kanten zwischen Teilsystemen', LinkLines(AComparison.RemovedEdges, False)) +
    MarkdownList('Teilsystemwechsel', MoveLines(AComparison.Moves)) +
    MarkdownList('Gewachsene zentrale Units', GrowthLines(AComparison.Growth)) +
    MarkdownList('Neue Units', AComparison.NewUnits) +
    MarkdownList('Entfernte Units', AComparison.RemovedUnits);
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
      Result := Result + ',';
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
      Result := Result + ',';
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
      Result := Result + ',';
    Result := Result + '{"source":' + JsonText(Edge.Source) + ',"target":' + JsonText(Edge.Target) + ',"section":' +
      JsonText(SectionText(Edge.Interface_)) + ',"from":' + JsonText(Edge.FromSubsystem) + ',"to":' +
      JsonText(Edge.ToSubsystem);
    if AReason then
      Result := Result + ',"reason":' + JsonText(Edge.Reason);
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
        Builder.Append(',');
      // Höchstens 20 Kanten je Zeile: Zeilen über 1023 Zeichen machen erzeugte Dateien unhandlich.
      if (Index > 0) and (Index mod 20 = 0) then
        Builder.Append(LineBreak);
      Builder.Append('[').Append(JsonText(AEdges[Index].Source)).Append(',').Append(JsonText(AEdges[Index].Target));
      if AEdges[Index].Interface_ then
        Builder.Append(',"i"]')
      else
        Builder.Append(',"m"]');
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
      Moves := Moves + ',';
    Moves := Moves + '{"unit":' + JsonText(AComparison.Moves[Index].Unit_) + ',"from":' +
      JsonText(AComparison.Moves[Index].FromSubsystem) + ',"to":' + JsonText(AComparison.Moves[Index].ToSubsystem) +
      '}';
  end;
  Moves := Moves + ']';
  Growth := '[';
  for Index := 0 to High(AComparison.Growth) do
  begin
    if Index > 0 then
      Growth := Growth + ',';
    Growth := Growth + '{"unit":' + JsonText(AComparison.Growth[Index].Unit_) + ',"before":' +
      IntToStr(AComparison.Growth[Index].Before) + ',"after":' + IntToStr(AComparison.Growth[Index].After) + '}';
  end;
  Growth := Growth + ']';
  Result := '{"baseline":{"title":' + JsonText(AComparison.BaselineTitle) + ',"units":' +
    IntToStr(AComparison.BaselineUnits) + ',"edges":' + IntToStr(AComparison.BaselineEdges) + '}' + LineBreak +
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

end.
