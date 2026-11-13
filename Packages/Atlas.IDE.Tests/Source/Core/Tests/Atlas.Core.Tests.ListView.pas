unit Atlas.Core.Tests.ListView;

// Testlisten (#2167) im Baum des Fensters „Atlas-Tests“, ohne VCL und Open
// Tools API: verbindet das Baummodell (Atlas.Core.Tests.Explorer) mit den
// Listen (Atlas.Core.Tests.Lists).
// - Items: die Blätter des Baums als Einträge der Listen, mit dem Stand aus
//   den Läufen dieser Sitzung (fehlgeschlagen, nicht gelaufen, veraltet) und
//   dem Knoten.
// - Visible: Sichtbarkeit im Reiter einer Liste; ein Blatt ist sichtbar, wenn
//   es zur Liste gehört und zu Filter und Suche passt, ein innerer Knoten,
//   wenn ein Kind sichtbar ist.
// - Names: Namen gewählter Knoten für eine feste Liste (Unit, Unit.Fixture,
//   Test oder Fall); ein Knoten unter einem ebenfalls gewählten zählt nicht.
// - Categories: Kategorien des Testprojekts zur Auswahl im Dialog.

interface

uses
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.Lists;

type
  TAtlasTestListView = class
  public
    /// <summary>Gelesene Units der Eingabe von TAtlasTestExplorer.Build in derselben Reihenfolge.</summary>
    class function Units(const AInputs: TArray<TAtlasTestUnitInput>): TArray<TDUnitXUnit>; static;
    /// <summary>Blätter von AInputs mit Stand und Knoten aus ANodes (Build über dieselben AInputs).</summary>
    class function Items(const AInputs: TArray<TAtlasTestUnitInput>;
      const ANodes: TArray<TAtlasTestNode>): TAtlasTestListItems; static;
    /// <summary>Sichtbarkeit je Knoten im Reiter einer Liste: AVisible (Filter und Suche, aus
    /// TAtlasTestExplorer.Visible) und AMembers je Eintrag von AItems.</summary>
    class function Visible(const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>;
      const AItems: TAtlasTestListItems; const AMembers: TArray<Boolean>): TArray<Boolean>; static;
    /// <summary>Volle Namen der Knoten ASelected ohne die unter einem ebenfalls gewählten.</summary>
    class function Names(const ANodes: TArray<TAtlasTestNode>; const ASelected: TArray<Integer>): TArray<string>;
      static;
    /// <summary>Kategorien an Fixtures und Tests von AInputs, ohne doppelte (ohne Groß-/Kleinschreibung),
    /// sortiert.</summary>
    class function Categories(const AInputs: TArray<TAtlasTestUnitInput>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Core.Tests.Run;

function KeyOf(AUnit, AFixture, ATest, ACase: Integer): string;
begin
  Result := Format('%d|%d|%d|%d', [AUnit, AFixture, ATest, ACase]);
end;

class function TAtlasTestListView.Units(const AInputs: TArray<TAtlasTestUnitInput>): TArray<TDUnitXUnit>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AInputs));
  for mIndex := 0 to High(AInputs) do
  begin
    Result[mIndex] := AInputs[mIndex].Found;
  end;
end;

class function TAtlasTestListView.Items(const AInputs: TArray<TAtlasTestUnitInput>;
  const ANodes: TArray<TAtlasTestNode>): TAtlasTestListItems;
var
  mNodes: TDictionary<string, Integer>;
  mIndex, mNode: Integer;
  mTally: TAtlasTestTally;
begin
  Result := TAtlasTestListModel.Items(Units(AInputs));
  mNodes := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(ANodes) do
    begin
      if ANodes[mIndex].Kind in [TAtlasTestNodeKind.Test, TAtlasTestNodeKind.TestCase] then
      begin
        mNodes.AddOrSetValue(KeyOf(ANodes[mIndex].UnitIndex, ANodes[mIndex].FixtureIndex, ANodes[mIndex].TestIndex,
          ANodes[mIndex].CaseIndex), mIndex);
      end;
    end;
    for mIndex := 0 to High(Result) do
    begin
      if not mNodes.TryGetValue(KeyOf(Result[mIndex].UnitIndex, Result[mIndex].FixtureIndex,
        Result[mIndex].TestIndex, Result[mIndex].CaseIndex), mNode) then
      begin
        Continue;
      end;
      Result[mIndex].Node := mNode;
      mTally := ANodes[mNode].Tally;
      Result[mIndex].Failed := mTally.Failed > 0;
      Result[mIndex].NotRun := mTally.Ran < mTally.Total;
      Result[mIndex].Stale := mTally.IsStale;
    end;
  finally
    mNodes.Free;
  end;
end;

class function TAtlasTestListView.Visible(const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>;
  const AItems: TAtlasTestListItems; const AMembers: TArray<Boolean>): TArray<Boolean>;
var
  mIndex, mNode, mParent: Integer;
begin
  SetLength(Result, Length(ANodes));
  for mIndex := 0 to High(AItems) do
  begin
    mNode := AItems[mIndex].Node;
    // Nur Blätter mit Knoten, die zur Liste gehören und zu Filter und Suche passen.
    if (mNode < 0) or (mNode > High(ANodes)) or (mNode > High(AVisible)) or (mIndex > High(AMembers)) then
    begin
      Continue;
    end;
    Result[mNode] := AMembers[mIndex] and AVisible[mNode];
  end;
  // Kinder stehen hinter ihrem Elternknoten: rückwärts trägt jeder sichtbare Knoten die Sichtbarkeit nach oben.
  for mIndex := High(ANodes) downto 0 do
  begin
    mParent := ANodes[mIndex].Parent;
    if Result[mIndex] and (mParent >= 0) then
    begin
      Result[mParent] := True;
    end;
  end;
end;

/// <summary>Ist ein Vorfahr von AIndex unter ASelected?</summary>
function AncestorChosen(const ANodes: TArray<TAtlasTestNode>; const ASelected: TArray<Integer>;
  AIndex: Integer): Boolean;
var
  mParent, mChosen: Integer;
begin
  mParent := ANodes[AIndex].Parent;
  while mParent >= 0 do
  begin
    for mChosen in ASelected do
    begin
      if mChosen = mParent then
      begin
        Exit(True);
      end;
    end;
    mParent := ANodes[mParent].Parent;
  end;
  Result := False;
end;

class function TAtlasTestListView.Names(const ANodes: TArray<TAtlasTestNode>;
  const ASelected: TArray<Integer>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in ASelected do
  begin
    if (mIndex >= 0) and (mIndex <= High(ANodes)) and (ANodes[mIndex].FullName <> '') and
      not AncestorChosen(ANodes, ASelected, mIndex) then
    begin
      Result := Result + [ANodes[mIndex].FullName];
    end;
  end;
end;

class function TAtlasTestListView.Categories(const AInputs: TArray<TAtlasTestUnitInput>): TArray<string>;
var
  mFound: TList<string>;
  mInput: TAtlasTestUnitInput;
  mFixture: TDUnitXFixture;
  mTest: TDUnitXTest;

  procedure Take(const ANames: TArray<string>);
  var
    mName, mKnown: string;
    mSeen: Boolean;
  begin
    for mName in ANames do
    begin
      mSeen := False;
      for mKnown in mFound do
      begin
        mSeen := mSeen or SameText(mKnown, mName);
      end;
      if not mSeen then
      begin
        mFound.Add(mName);
      end;
    end;
  end;

begin
  mFound := TList<string>.Create;
  try
    for mInput in AInputs do
    begin
      for mFixture in mInput.Found.Fixtures do
      begin
        Take(mFixture.Categories);
        for mTest in mFixture.Tests do
        begin
          Take(mTest.Categories);
        end;
      end;
    end;
    // Gleichstand gibt es nicht (keine doppelten); nach Text ohne Groß-/Kleinschreibung.
    mFound.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
        if Result = 0 then
        begin
          Result := CompareStr(ALeft, ARight);
        end;
      end));
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

end.
