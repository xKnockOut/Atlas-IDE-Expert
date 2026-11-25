unit Atlas.Common.Architecture.FeatureCycles;

// Zyklen zwischen Features gleichen Präfixes und Richtungen zwischen Features
// (Regel architecture-feature-cycle, Tools/Check-PackageDependencies.ps1).
//
// - Feature einer Unit: das erste Segment nach dem längsten passenden Präfix
//   (Atlas.Core.Lsp.Session → Präfix Atlas.Core, Feature Lsp). Units ohne
//   Präfix zählen nicht.
// - Gezählt wird jeder uses-Eintrag zwischen zwei Features desselben Präfixes,
//   interface und implementation, auch auf Contract-Units. Einträge, deren
//   Quelle oder Ziel unter "exclude" fällt (Globs auf den Pfad relativ zur
//   Konfiguration wie "Tests/**" oder auf den Unit-Namen), zählen nicht.
// - Zyklus: starke Zusammenhangskomponente des Feature-Graphen mit mehr als
//   einem Feature. "known" führt bestehende Zyklen als schrumpfende Liste
//   ("Atlas.Core: Lsp, Problems"): Eine Komponente innerhalb eines Eintrags
//   ist bekannt; ein Eintrag, dem keine Komponente genau entspricht, ist
//   veraltet und muss auf den neuen Stand gekürzt werden.
// - Richtungen: "Präfix: A < B < C" – B und C dürfen A verwenden, aber nicht
//   umgekehrt (A verwendet weder B noch C, B nicht C). "Präfix: A | B" – keine
//   Kante zwischen A und B. Einzelne Einträge dagegen stehen als schrumpfende
//   Liste in "knownEdges" ("Quelle -> Ziel" mit Unit-Namen); ein Eintrag ohne
//   Kante ist veraltet.
// - Findings nennt jeden Befund als Schlüssel, nach Text sortiert: "cycle
//   Präfix: A, B", "stale Präfix: A, B", "direction Quelle -> Ziel",
//   "staleEdge Quelle -> Ziel", "invalid Eintrag". Dieselben Schlüssel bildet
//   das Skript; beide prüfen Tests/Data/Architecture/feature-cycles.json.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Ein uses-Eintrag: Unit-Namen und Pfade relativ zur Konfiguration (Pfad '' = unbekannt).</summary>
  TFeatureEdge = record
    SourceUnit: string;
    SourcePath: string;
    TargetUnit: string;
    TargetPath: string;
    class function Create(const ASourceUnit, ASourcePath, ATargetUnit, ATargetPath: string): TFeatureEdge; static;
  end;

  /// <summary>Optionen der Regel architecture-feature-cycle (siehe Kopfkommentar).</summary>
  TFeatureCycleOptions = record
    Prefixes: TArray<string>;
    Exclude: TArray<string>;
    Known: TArray<string>;
    Directions: TArray<string>;
    KnownEdges: TArray<string>;
    /// <summary>Optionen aus dem JSON-Text der Regel; ungültiger Text ergibt leere Optionen.</summary>
    class function Parse(const AJson: string): TFeatureCycleOptions; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Befund zu einem uses-Eintrag: keiner, Teil eines unbekannten Zyklus, gegen eine Richtung.</summary>
  TFeatureVerdict = (None, Cycle, Direction);
{$SCOPEDENUMS OFF}

  IFeatureCycles = interface
    ['{17478D00-F9B1-4781-B444-EF82C14FC280}']
    /// <summary>Befund zum uses-Eintrag ASourceUnit → ATargetUnit. ADetail nennt beim Zyklus die Komponente
    /// ("Atlas.Core: Lsp, Problems"), bei der Richtung den Eintrag aus "directions".</summary>
    function Verdict(const ASourceUnit, ATargetUnit: string; out ADetail: string): TFeatureVerdict;
    /// <summary>Alle Befunde als Schlüssel (siehe Kopfkommentar), sortiert.</summary>
    function Findings: TArray<string>;
  end;

  TFeatureCycles = class(TInterfacedObject, IFeatureCycles)
  private type
    TEdgeVerdict = record
      Verdict: TFeatureVerdict;
      Detail: string;
    end;
  private
    FVerdicts: TDictionary<string, TEdgeVerdict>;
    FFindings: TArray<string>;
    constructor CreateFrom(const AOptions: TFeatureCycleOptions; const AEdges: TArray<TFeatureEdge>);
    procedure Mark(const AKey: string; AVerdict: TFeatureVerdict; const ADetail: string);
  public
    destructor Destroy; override;
    /// <summary>Wertet AEdges nach AOptions aus.</summary>
    class function Analyze(const AOptions: TFeatureCycleOptions; const AEdges: TArray<TFeatureEdge>):
      IFeatureCycles; static;
    /// <summary>Präfix und Feature von AUnitName nach dem längsten passenden Präfix; False ohne Präfix.</summary>
    class function FeatureOf(const AUnitName: string; const APrefixes: TArray<string>; out APrefix,
      AFeature: string): Boolean; static;
    function Verdict(const ASourceUnit, ATargetUnit: string; out ADetail: string): TFeatureVerdict;
    function Findings: TArray<string>;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  Atlas.Common.Configuration.Contract,
  Atlas.Text.Json;

const
  cEdgeArrow = ' -> ';

function EdgeKey(const ASourceUnit, ATargetUnit: string): string;
begin
  Result := LowerCase(ASourceUnit) + '>' + LowerCase(ATargetUnit);
end;

function Excluded(const APatterns: TArray<string>; const APath: string): Boolean;
var
  mPattern: string;
begin
  if APath = '' then
  begin
    Exit(False);
  end;
  for mPattern in APatterns do
  begin
    if MatchesGlob(mPattern, APath) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure SortTexts(var AItems: TArray<string>);
begin
  TArray.Sort<string>(AItems, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(ALeft, ARight);
      if Result = 0 then
      begin
        Result := CompareStr(ALeft, ARight);
      end;
    end));
end;

/// <summary>Teilt "Präfix: A, B" bzw. "Präfix: A &lt; B" am Doppelpunkt; False ohne Präfix oder Teile.</summary>
function SplitEntry(const AEntry: string; const ASeparator: Char; out APrefix: string;
  out AParts: TArray<string>): Boolean;
var
  mColon: Integer;
  mPart: string;
begin
  APrefix := '';
  AParts := nil;
  mColon := Pos(':', AEntry);
  if mColon = 0 then
  begin
    Exit(False);
  end;
  APrefix := Trim(Copy(AEntry, 1, mColon - 1));
  for mPart in Copy(AEntry, mColon + 1, MaxInt).Split([ASeparator]) do
  begin
    if Trim(mPart) <> '' then
    begin
      AParts := AParts + [Trim(mPart)];
    end;
  end;
  Result := (APrefix <> '') and (Length(AParts) >= 2);
end;

function ComponentText(const APrefix: string; const AFeatures: TArray<string>): string;
var
  mFeatures: TArray<string>;
begin
  mFeatures := Copy(AFeatures);
  SortTexts(mFeatures);
  Result := APrefix + ': ' + string.Join(', ', mFeatures);
end;

{ TFeatureEdge }

class function TFeatureEdge.Create(const ASourceUnit, ASourcePath, ATargetUnit,
  ATargetPath: string): TFeatureEdge;
begin
  Result.SourceUnit := ASourceUnit;
  Result.SourcePath := ASourcePath;
  Result.TargetUnit := ATargetUnit;
  Result.TargetPath := ATargetPath;
end;

{ TFeatureCycleOptions }

class function TFeatureCycleOptions.Parse(const AJson: string): TFeatureCycleOptions;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
begin
  Result := Default(TFeatureCycleOptions);
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    Result.Prefixes := TJsonRead.TrimmedStrings(mObject.GetValue('prefixes'));
    Result.Exclude := TJsonRead.TrimmedStrings(mObject.GetValue('exclude'));
    Result.Known := TJsonRead.TrimmedStrings(mObject.GetValue('known'));
    Result.Directions := TJsonRead.TrimmedStrings(mObject.GetValue('directions'));
    Result.KnownEdges := TJsonRead.TrimmedStrings(mObject.GetValue('knownEdges'));
  finally
    mValue.Free;
  end;
end;

{ TFeatureCycles }

class function TFeatureCycles.FeatureOf(const AUnitName: string; const APrefixes: TArray<string>; out APrefix,
  AFeature: string): Boolean;
var
  mPrefix, mRest: string;
  mDot: Integer;
begin
  APrefix := '';
  AFeature := '';
  for mPrefix in APrefixes do
  begin
    if (Length(mPrefix) > Length(APrefix)) and (Length(AUnitName) > Length(mPrefix) + 1) and
      SameText(Copy(AUnitName, 1, Length(mPrefix) + 1), mPrefix + '.') then
    begin
      APrefix := mPrefix;
    end;
  end;
  if APrefix = '' then
  begin
    Exit(False);
  end;
  mRest := Copy(AUnitName, Length(APrefix) + 2, MaxInt);
  mDot := Pos('.', mRest);
  if mDot > 0 then
  begin
    mRest := Copy(mRest, 1, mDot - 1);
  end;
  AFeature := mRest;
  Result := AFeature <> '';
end;

class function TFeatureCycles.Analyze(const AOptions: TFeatureCycleOptions;
  const AEdges: TArray<TFeatureEdge>): IFeatureCycles;
begin
  Result := TFeatureCycles.CreateFrom(AOptions, AEdges);
end;

type
  /// <summary>Feature-Graph eines Laufs mit Tarjan über die Knotennummern.</summary>
  TFeatureGraph = class
  private
    FIds: TDictionary<string, Integer>;
    FPrefixes: TList<string>;
    FFeatures: TList<string>;
    FNext: TObjectList<TList<Integer>>;
    FNumber, FLow, FComponent: TArray<Integer>;
    FOnStack: TArray<Boolean>;
    FStack: TStack<Integer>;
    FCounter: Integer;
    FComponents: TList<TArray<Integer>>;
    procedure Visit(ANode: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function Node(const APrefix, AFeature: string): Integer;
    procedure Link(AFrom, ATo: Integer);
    /// <summary>Starke Zusammenhangskomponenten mit mehr als einem Knoten; ComponentOf danach gültig.</summary>
    procedure Solve;
    function ComponentOf(ANode: Integer): Integer;
    function Prefix(ANode: Integer): string;
    function Feature(ANode: Integer): string;
    property Components: TList<TArray<Integer>> read FComponents;
  end;

constructor TFeatureGraph.Create;
begin
  inherited Create;
  FIds := TDictionary<string, Integer>.Create;
  FPrefixes := TList<string>.Create;
  FFeatures := TList<string>.Create;
  FNext := TObjectList<TList<Integer>>.Create(True);
  FStack := TStack<Integer>.Create;
  FComponents := TList<TArray<Integer>>.Create;
end;

destructor TFeatureGraph.Destroy;
begin
  FComponents.Free;
  FStack.Free;
  FNext.Free;
  FFeatures.Free;
  FPrefixes.Free;
  FIds.Free;
  inherited;
end;

function TFeatureGraph.Node(const APrefix, AFeature: string): Integer;
var
  mKey: string;
begin
  mKey := LowerCase(APrefix + '.' + AFeature);
  if FIds.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := FPrefixes.Count;
  FIds.Add(mKey, Result);
  FPrefixes.Add(APrefix);
  FFeatures.Add(AFeature);
  FNext.Add(TList<Integer>.Create);
end;

procedure TFeatureGraph.Link(AFrom, ATo: Integer);
begin
  if not FNext[AFrom].Contains(ATo) then
  begin
    FNext[AFrom].Add(ATo);
  end;
end;

procedure TFeatureGraph.Visit(ANode: Integer);
var
  mNext, mMember: Integer;
  mMembers: TArray<Integer>;
begin
  FNumber[ANode] := FCounter;
  FLow[ANode] := FCounter;
  Inc(FCounter);
  FStack.Push(ANode);
  FOnStack[ANode] := True;
  for mNext in FNext[ANode] do
  begin
    if FNumber[mNext] < 0 then
    begin
      Visit(mNext);
      if FLow[mNext] < FLow[ANode] then
      begin
        FLow[ANode] := FLow[mNext];
      end;
    end
    else if FOnStack[mNext] and (FNumber[mNext] < FLow[ANode]) then
    begin
      FLow[ANode] := FNumber[mNext];
    end;
  end;
  if FLow[ANode] <> FNumber[ANode] then
  begin
    Exit;
  end;
  mMembers := nil;
  repeat
    mMember := FStack.Pop;
    FOnStack[mMember] := False;
    mMembers := mMembers + [mMember];
  until mMember = ANode;
  if Length(mMembers) > 1 then
  begin
    for mMember in mMembers do
    begin
      FComponent[mMember] := FComponents.Count;
    end;
    FComponents.Add(mMembers);
  end;
end;

procedure TFeatureGraph.Solve;
var
  mNode: Integer;
begin
  SetLength(FNumber, FPrefixes.Count);
  SetLength(FLow, FPrefixes.Count);
  SetLength(FComponent, FPrefixes.Count);
  SetLength(FOnStack, FPrefixes.Count);
  for mNode := 0 to FPrefixes.Count - 1 do
  begin
    FNumber[mNode] := -1;
    FComponent[mNode] := -1;
    FOnStack[mNode] := False;
  end;
  FCounter := 0;
  for mNode := 0 to FPrefixes.Count - 1 do
  begin
    if FNumber[mNode] < 0 then
    begin
      Visit(mNode);
    end;
  end;
end;

function TFeatureGraph.ComponentOf(ANode: Integer): Integer;
begin
  Result := FComponent[ANode];
end;

function TFeatureGraph.Prefix(ANode: Integer): string;
begin
  Result := FPrefixes[ANode];
end;

function TFeatureGraph.Feature(ANode: Integer): string;
begin
  Result := FFeatures[ANode];
end;

type
  /// <summary>Ein Eintrag aus "known": Präfix und Features (kleingeschrieben), normalisierter Text.</summary>
  TKnownCycle = record
    Prefix: string;
    Features: TArray<string>;
    Text: string;
    function Contains(const AFeature: string): Boolean;
  end;

function TKnownCycle.Contains(const AFeature: string): Boolean;
var
  mFeature: string;
begin
  for mFeature in Features do
  begin
    if SameText(mFeature, AFeature) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function PairKey(const APrefix, AFrom, ATo: string): string;
begin
  Result := LowerCase(APrefix + ':' + AFrom + '>' + ATo);
end;

/// <summary>Verbotene Paare aus "directions"; ungültige Einträge landen in AInvalid.</summary>
function ForbiddenPairs(const ADirections: TArray<string>; var AInvalid: TArray<string>):
  TDictionary<string, string>;
var
  mEntry, mPrefix: string;
  mParts: TArray<string>;
  mFrom, mTo: Integer;
  mOrdered: Boolean;
begin
  Result := TDictionary<string, string>.Create;
  for mEntry in ADirections do
  begin
    mOrdered := Pos('<', mEntry) > 0;
    if mOrdered then
    begin
      SplitEntry(mEntry, '<', mPrefix, mParts);
    end
    else
    begin
      SplitEntry(mEntry, '|', mPrefix, mParts);
    end;
    if (mPrefix = '') or (Length(mParts) < 2) or (mOrdered and (Pos('|', mEntry) > 0)) then
    begin
      AInvalid := AInvalid + ['invalid ' + mEntry];
      Continue;
    end;
    for mFrom := 0 to High(mParts) do
    begin
      for mTo := 0 to High(mParts) do
      begin
        // A < B: A verwendet B nicht. A | B: keine Richtung.
        if (mFrom < mTo) or ((mFrom > mTo) and not mOrdered) then
        begin
          Result.AddOrSetValue(PairKey(mPrefix, mParts[mFrom], mParts[mTo]), mEntry);
        end;
      end;
    end;
  end;
end;

function KnownCycles(const AKnown: TArray<string>; var AInvalid: TArray<string>): TArray<TKnownCycle>;
var
  mEntry: string;
  mItem: TKnownCycle;
begin
  Result := nil;
  for mEntry in AKnown do
  begin
    if not SplitEntry(mEntry, ',', mItem.Prefix, mItem.Features) then
    begin
      AInvalid := AInvalid + ['invalid ' + mEntry];
      Continue;
    end;
    mItem.Text := ComponentText(mItem.Prefix, mItem.Features);
    Result := Result + [mItem];
  end;
end;

/// <summary>"Quelle -> Ziel" als Kantenschlüssel; '' bei ungültigem Eintrag.</summary>
function KnownEdgeKey(const AEntry: string): string;
var
  mArrow: Integer;
begin
  mArrow := Pos('->', AEntry);
  if (mArrow <= 1) or (Trim(Copy(AEntry, mArrow + 2, MaxInt)) = '') then
  begin
    Exit('');
  end;
  Result := EdgeKey(Trim(Copy(AEntry, 1, mArrow - 1)), Trim(Copy(AEntry, mArrow + 2, MaxInt)));
end;

type
  /// <summary>Eine Auswertung: Graph der Features, Richtungen, bekannte Zyklen und Kanten. Schreibt Befunde und
  /// Urteile in FOwner.</summary>
  TFeatureAnalysis = class
  private
    FOwner: TFeatureCycles;
    FOptions: TFeatureCycleOptions;
    FGraph: TFeatureGraph;
    FForbidden: TDictionary<string, string>;
    FKnownEdges: TDictionary<string, string>;
    FUsedEdges: TDictionary<string, Boolean>;
    FEdges: TList<TFeatureEdge>;
    FFromNodes, FToNodes: TList<Integer>;
    FKnown: TArray<TKnownCycle>;
    FCovered: TArray<Boolean>;
    procedure Finding(const AText: string);
    function Considered(const AEdge: TFeatureEdge; out APrefix, ASourceFeature, ATargetFeature: string): Boolean;
    function FeaturesOf(AComponent: Integer): TArray<string>;
    procedure ReadKnownEdges;
    procedure AddEdge(const AEdge: TFeatureEdge);
    procedure MatchComponents;
    procedure MarkCycleEdges;
    procedure ReportStaleEdges;
  public
    constructor Create(AOwner: TFeatureCycles; const AOptions: TFeatureCycleOptions);
    destructor Destroy; override;
    procedure Run(const AEdges: TArray<TFeatureEdge>);
  end;

constructor TFeatureAnalysis.Create(AOwner: TFeatureCycles; const AOptions: TFeatureCycleOptions);
begin
  inherited Create;
  FOwner := AOwner;
  FOptions := AOptions;
  FForbidden := ForbiddenPairs(AOptions.Directions, FOwner.FFindings);
  FKnownEdges := TDictionary<string, string>.Create;
  FUsedEdges := TDictionary<string, Boolean>.Create;
  FEdges := TList<TFeatureEdge>.Create;
  FFromNodes := TList<Integer>.Create;
  FToNodes := TList<Integer>.Create;
  FGraph := TFeatureGraph.Create;
end;

destructor TFeatureAnalysis.Destroy;
begin
  FGraph.Free;
  FToNodes.Free;
  FFromNodes.Free;
  FEdges.Free;
  FUsedEdges.Free;
  FKnownEdges.Free;
  FForbidden.Free;
  FKnown := nil;
  FCovered := nil;
  inherited Destroy;
end;

procedure TFeatureAnalysis.Finding(const AText: string);
begin
  FOwner.FFindings := FOwner.FFindings + [AText];
end;

procedure TFeatureAnalysis.ReadKnownEdges;
var
  mEntry, mKey: string;
begin
  for mEntry in FOptions.KnownEdges do
  begin
    mKey := KnownEdgeKey(mEntry);
    if mKey = '' then
    begin
      Finding('invalid ' + mEntry);
      Continue;
    end;
    FKnownEdges.AddOrSetValue(mKey, mEntry);
  end;
end;

/// <summary>Kante zwischen zwei Features desselben Präfixes, die kein Ausschluss trifft?</summary>
function TFeatureAnalysis.Considered(const AEdge: TFeatureEdge; out APrefix, ASourceFeature,
  ATargetFeature: string): Boolean;
var
  mTargetPrefix: string;
begin
  Result := TFeatureCycles.FeatureOf(AEdge.SourceUnit, FOptions.Prefixes, APrefix, ASourceFeature) and
    TFeatureCycles.FeatureOf(AEdge.TargetUnit, FOptions.Prefixes, mTargetPrefix, ATargetFeature) and
    SameText(APrefix, mTargetPrefix) and not SameText(ASourceFeature, ATargetFeature) and
    not Excluded(FOptions.Exclude, AEdge.SourcePath) and not Excluded(FOptions.Exclude, AEdge.TargetPath) and
    not Excluded(FOptions.Exclude, AEdge.SourceUnit) and not Excluded(FOptions.Exclude, AEdge.TargetUnit);
end;

/// <summary>Nimmt die Kante in den Graphen, je Unit-Paar einmal, und prüft die Richtung.</summary>
procedure TFeatureAnalysis.AddEdge(const AEdge: TFeatureEdge);
var
  mPrefix, mSourceFeature, mTargetFeature, mKey, mEntry: string;
begin
  if not Considered(AEdge, mPrefix, mSourceFeature, mTargetFeature) then
  begin
    Exit;
  end;
  mKey := EdgeKey(AEdge.SourceUnit, AEdge.TargetUnit);
  if FUsedEdges.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FUsedEdges.Add(mKey, False);
  FEdges.Add(AEdge);
  FFromNodes.Add(FGraph.Node(mPrefix, mSourceFeature));
  FToNodes.Add(FGraph.Node(mPrefix, mTargetFeature));
  FGraph.Link(FFromNodes.Last, FToNodes.Last);
  if not FForbidden.TryGetValue(PairKey(mPrefix, mSourceFeature, mTargetFeature), mEntry) then
  begin
    Exit;
  end;
  if FKnownEdges.ContainsKey(mKey) then
  begin
    FUsedEdges[mKey] := True;
  end
  else
  begin
    FOwner.Mark(mKey, TFeatureVerdict.Direction, mEntry);
    Finding('direction ' + AEdge.SourceUnit + cEdgeArrow + AEdge.TargetUnit);
  end;
end;

function TFeatureAnalysis.FeaturesOf(AComponent: Integer): TArray<string>;
var
  mMember: Integer;
begin
  Result := nil;
  for mMember in FGraph.Components[AComponent] do
  begin
    Result := Result + [FGraph.Feature(mMember)];
  end;
end;

/// <summary>Komponenten gegen die bekannten Zyklen: unbekannte melden, Einträge ohne gleiche Komponente veraltet.
/// </summary>
procedure TFeatureAnalysis.MatchComponents;
var
  mExact: TArray<Boolean>;
  mFeatures: TArray<string>;
  mPrefix, mFeature: string;
  mIndex, mKnownIndex: Integer;
  mInside: Boolean;
begin
  SetLength(mExact, Length(FKnown));
  SetLength(FCovered, FGraph.Components.Count);
  for mIndex := 0 to FGraph.Components.Count - 1 do
  begin
    mFeatures := FeaturesOf(mIndex);
    mPrefix := FGraph.Prefix(FGraph.Components[mIndex][0]);
    FCovered[mIndex] := False;
    for mKnownIndex := 0 to High(FKnown) do
    begin
      mInside := SameText(FKnown[mKnownIndex].Prefix, mPrefix);
      for mFeature in mFeatures do
      begin
        mInside := mInside and FKnown[mKnownIndex].Contains(mFeature);
      end;
      if mInside then
      begin
        FCovered[mIndex] := True;
        mExact[mKnownIndex] := mExact[mKnownIndex] or (Length(mFeatures) = Length(FKnown[mKnownIndex].Features));
      end;
    end;
    if not FCovered[mIndex] then
    begin
      Finding('cycle ' + ComponentText(mPrefix, mFeatures));
    end;
  end;
  for mKnownIndex := 0 to High(FKnown) do
  begin
    if not mExact[mKnownIndex] then
    begin
      Finding('stale ' + FKnown[mKnownIndex].Text);
    end;
  end;
end;

/// <summary>Urteil "Zyklus" für jede Kante innerhalb eines unbekannten Zyklus.</summary>
procedure TFeatureAnalysis.MarkCycleEdges;
var
  mIndex, mComponent: Integer;
begin
  for mIndex := 0 to FEdges.Count - 1 do
  begin
    mComponent := FGraph.ComponentOf(FFromNodes[mIndex]);
    if (mComponent < 0) or FCovered[mComponent] or (mComponent <> FGraph.ComponentOf(FToNodes[mIndex])) then
    begin
      Continue;
    end;
    FOwner.Mark(EdgeKey(FEdges[mIndex].SourceUnit, FEdges[mIndex].TargetUnit), TFeatureVerdict.Cycle,
      ComponentText(FGraph.Prefix(FFromNodes[mIndex]), FeaturesOf(mComponent)));
  end;
end;

procedure TFeatureAnalysis.ReportStaleEdges;
var
  mKey, mEntry: string;
  mUsed: Boolean;
begin
  for mKey in FKnownEdges.Keys do
  begin
    if not FUsedEdges.TryGetValue(mKey, mUsed) or not mUsed then
    begin
      mEntry := FKnownEdges[mKey];
      Finding('staleEdge ' + Trim(Copy(mEntry, 1, Pos('->', mEntry) - 1)) + cEdgeArrow +
        Trim(Copy(mEntry, Pos('->', mEntry) + 2, MaxInt)));
    end;
  end;
end;

procedure TFeatureAnalysis.Run(const AEdges: TArray<TFeatureEdge>);
var
  mEdge: TFeatureEdge;
begin
  FKnown := KnownCycles(FOptions.Known, FOwner.FFindings);
  ReadKnownEdges;
  for mEdge in AEdges do
  begin
    AddEdge(mEdge);
  end;
  FGraph.Solve;
  MatchComponents;
  MarkCycleEdges;
  ReportStaleEdges;
end;

constructor TFeatureCycles.CreateFrom(const AOptions: TFeatureCycleOptions; const AEdges: TArray<TFeatureEdge>);
var
  mAnalysis: TFeatureAnalysis;
begin
  inherited Create;
  FVerdicts := TDictionary<string, TEdgeVerdict>.Create;
  FFindings := nil;
  mAnalysis := TFeatureAnalysis.Create(Self, AOptions);
  try
    mAnalysis.Run(AEdges);
  finally
    mAnalysis.Free;
  end;
  SortTexts(FFindings);
end;

destructor TFeatureCycles.Destroy;
begin
  FVerdicts.Free;
  inherited;
end;

procedure TFeatureCycles.Mark(const AKey: string; AVerdict: TFeatureVerdict; const ADetail: string);
var
  mVerdict: TEdgeVerdict;
begin
  // Eine Richtung ist der genauere Befund: Sie bleibt, wenn die Kante auch einen Zyklus schließt.
  if FVerdicts.TryGetValue(AKey, mVerdict) and (mVerdict.Verdict = TFeatureVerdict.Direction) then
  begin
    Exit;
  end;
  mVerdict.Verdict := AVerdict;
  mVerdict.Detail := ADetail;
  FVerdicts.AddOrSetValue(AKey, mVerdict);
end;

function TFeatureCycles.Verdict(const ASourceUnit, ATargetUnit: string; out ADetail: string): TFeatureVerdict;
var
  mVerdict: TEdgeVerdict;
begin
  ADetail := '';
  if not FVerdicts.TryGetValue(EdgeKey(ASourceUnit, ATargetUnit), mVerdict) then
  begin
    Exit(TFeatureVerdict.None);
  end;
  ADetail := mVerdict.Detail;
  Result := mVerdict.Verdict;
end;

function TFeatureCycles.Findings: TArray<string>;
begin
  Result := Copy(FFindings);
end;

end.
