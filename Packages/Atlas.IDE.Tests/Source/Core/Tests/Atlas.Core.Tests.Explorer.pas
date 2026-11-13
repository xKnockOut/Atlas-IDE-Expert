unit Atlas.Core.Tests.Explorer;

// Baummodell des Fensters „Atlas-Tests“ (#1776), ohne VCL und Open Tools API,
// auch unter FPC prüfbar:
// - Build: Testunits eines Testprojekts (Atlas.Text.DUnitX) und die
//   Ergebnisse der Läufe dieser Sitzung werden zu Knoten Testunit → Fixture →
//   Test → Fall, je Knoten der Stand über alle Tests darunter
//   (TAtlasTestTally aus Atlas.Core.Tests.Run, mit veralteten Ergebnissen
//   #1770 und Dauer #1772). Tests mit [Ignore] stehen im Baum, zählen aber
//   nicht.
// - Visible: Filter (fehlgeschlagen, nicht gelaufen, veraltet, langsam;
//   mehrere gelten mit „oder“) und Suche im vollen Namen; ein Knoten ist
//   sichtbar, wenn er selbst passt oder ein Kind darunter, damit der Weg zu
//   jedem Treffer bleibt.
// - RunNames: Namen für --run einer Mehrfachauswahl; ein Knoten, dessen
//   Vorfahr mit ausgewählt ist, kommt nicht doppelt.
// - StackLines: Zeilen eines Stacktraces mit Datei und Zeile, wenn sie eine
//   Unit des Testprojekts nennen (Formate wie Atlas.Core.Tests.AssertLine).
// Zeilen sind 0-basiert.

interface

uses
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run;

type
{$SCOPEDENUMS ON}
  /// <summary>Ebene eines Knotens.</summary>
  TAtlasTestNodeKind = (TestUnit, Fixture, Test, TestCase);
  /// <summary>Farbe des Punkts: grün, rot, gelb (Teilstand), grau (nicht gelaufen bzw. veraltet).</summary>
  TAtlasTestNodeState = (NotRun, Passed, Failed, Partial, Stale);
  /// <summary>Filter des Fensters.</summary>
  TAtlasTestFilter = (Failed, NotRun, Stale, Slow);
{$SCOPEDENUMS OFF}
  TAtlasTestFilters = set of TAtlasTestFilter;

  /// <summary>Eine Testunit des Testprojekts: Datei, erkannte Fixtures und die Schlüssel ihrer Tests mit
  /// veraltetem Ergebnis (TAtlasTestStamps.KeyOf, #1770).</summary>
  TAtlasTestUnitInput = record
    FileName: string;
    Found: TDUnitXUnit;
    StaleKeys: TArray<string>;
  end;

  /// <summary>Eine Unit des Testprojekts für anklickbare Zeilen im Stacktrace.</summary>
  TAtlasTestUnitRef = record
    UnitName: string;
    FileName: string;
  end;

  /// <summary>Eine Zeile des Stacktraces; FileName '' ohne Fundstelle.</summary>
  TAtlasTestStackLine = record
    Text: string;
    FileName: string;
    Line: Integer;
  end;

  TAtlasTestNode = record
    Kind: TAtlasTestNodeKind;
    /// <summary>Index des Elternknotens; -1 für eine Testunit.</summary>
    Parent: Integer;
    /// <summary>Unitname, Klassenname, Methode bzw. Fall.</summary>
    Caption: string;
    /// <summary>Voller Name wie in DUnitX (Unit[.Fixture[.Methode[.Fall]]]).</summary>
    FullName: string;
    /// <summary>Index in die Eingabe von Build und in Fixtures, Tests bzw. Cases; -1, wo es nicht gilt.</summary>
    UnitIndex: Integer;
    FixtureIndex: Integer;
    TestIndex: Integer;
    CaseIndex: Integer;
    FileName: string;
    /// <summary>Sprungziel: Methodenkopf im implementation-Teil, sonst die Deklaration; -1 ohne.</summary>
    Line: Integer;
    /// <summary>Test mit [Ignore] (bzw. eine Fixture, deren Tests alle ignoriert sind).</summary>
    Ignored: Boolean;
    Tally: TAtlasTestTally;
  end;

  /// <summary>Texte einer Zeile: Ignored (%s Name) und das Dezimaltrennzeichen der Dauer.</summary>
  TAtlasTestRowTexts = record
    Ignored: string;
    DecimalSeparator: Char;
  end;

  /// <summary>Sichtbare Zeile des Baums.</summary>
  TAtlasTestRow = record
    /// <summary>Index des Knotens.</summary>
    Node: Integer;
    /// <summary>Zeile des Elternknotens; -1 oben.</summary>
    Parent: Integer;
    /// <summary>„Name · 3/4 · 12 ms“.</summary>
    Text: string;
    State: TAtlasTestNodeState;
  end;

  /// <summary>Texte der Einzelheiten: Passed (%s Dauer), NotRun, Skipped/Message/Expected/Actual (je %s) und
  /// die Überschrift des Stacktraces.</summary>
  TAtlasTestDetailTexts = record
    Passed: string;
    NotRun: string;
    Skipped: string;
    Message: string;
    Expected: string;
    Actual: string;
    Stack: string;
    DecimalSeparator: Char;
  end;

  TAtlasTestExplorer = class
  public
    /// <summary>Text einer Zeile: Name, Zähler und Dauer (ohne Lauf nur Name und Zähler).</summary>
    class function RowText(const ANode: TAtlasTestNode; const ATexts: TAtlasTestRowTexts): string; static;
    /// <summary>Sichtbare Zeilen (AVisible aus Visible) in Baumreihenfolge.</summary>
    class function Rows(const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>;
      const ATexts: TAtlasTestRowTexts): TArray<TAtlasTestRow>; static;
    /// <summary>Summe über alle Testunits: Tests, frisch bestanden, fehlgeschlagen, nicht gelaufen.</summary>
    class procedure Totals(const ANodes: TArray<TAtlasTestNode>; out ATotal, APassed, AFailed, ANotRun: Integer);
      static;
    /// <summary>Knoten aller Testunits AUnits (nach Unitname sortiert) mit dem Stand aus ACases.</summary>
    class function Build(const AUnits: TArray<TAtlasTestUnitInput>;
      const ACases: TArray<TTestCaseResult>): TArray<TAtlasTestNode>; static;
    /// <summary>Farbe des Punkts eines Knotens.</summary>
    class function StateOf(const ANode: TAtlasTestNode): TAtlasTestNodeState; static;
    /// <summary>Zähler „bestanden/alle“ (veraltete zählen nicht als bestanden); '' ohne Tests.</summary>
    class function Counter(const ANode: TAtlasTestNode): string; static;
    /// <summary>Passt der Knoten selbst zu den Filtern AFilters (leer = alle) und zur Suche ASearch (Teil des
    /// vollen Namens, ohne Groß-/Kleinschreibung; '' = alle)? ASlowMs: Grenze für „langsam“.</summary>
    class function Matches(const ANode: TAtlasTestNode; AFilters: TAtlasTestFilters; const ASearch: string;
      ASlowMs: Integer): Boolean; static;
    /// <summary>Sichtbarkeit je Knoten: passt er selbst (Test bzw. Fall) oder ein Knoten darunter.</summary>
    class function Visible(const ANodes: TArray<TAtlasTestNode>; AFilters: TAtlasTestFilters; const ASearch: string;
      ASlowMs: Integer): TArray<Boolean>; static;
    /// <summary>Namen für --run der Knoten ASelected (Indizes in ANodes) ohne doppelte; ein Knoten unter einem
    /// ebenfalls gewählten zählt nicht.</summary>
    class function RunNames(const AUnits: TArray<TAtlasTestUnitInput>; const ANodes: TArray<TAtlasTestNode>;
      const ASelected: TArray<Integer>): TArray<string>; static;
    /// <summary>Ergebnisse des Knotens, Fehlschläge zuerst; leer ohne Lauf.</summary>
    class function ResultsOf(const ANode: TAtlasTestNode; const AUnits: TArray<TAtlasTestUnitInput>;
      const ACases: TArray<TTestCaseResult>): TArray<TTestCaseResult>; static;
    /// <summary>Zeilen von AStackTrace; nennt eine die Unit bzw. Datei eines Eintrags von AUnits mit Zeile, stehen
    /// Datei und Zeile (0-basiert) daran.</summary>
    class function StackLines(const AStackTrace: string;
      const AUnits: TArray<TAtlasTestUnitRef>): TArray<TAtlasTestStackLine>; static;
    /// <summary>Einzelheiten zum ersten Ergebnis von AResults (ResultsOf, Fehlschläge zuerst): Stand bzw. Meldung,
    /// erwartet und erhalten, Stacktrace mit Fundstellen in AUnits; ohne Ergebnis „noch nicht gelaufen“.</summary>
    class function DetailLines(const AResults: TArray<TTestCaseResult>; const AUnits: TArray<TAtlasTestUnitRef>;
      const ATexts: TAtlasTestDetailTexts): TArray<TAtlasTestStackLine>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Core.Tests.Durations,
  Atlas.Core.Tests.AssertLine;

/// <summary>Reihenfolge der Testunits: nach Unitname, bei Gleichstand nach Datei (TArray.Sort ist nicht stabil).
/// </summary>
function SortedUnits(const AUnits: TArray<TAtlasTestUnitInput>): TArray<Integer>;
var
  mIndex: Integer;
  mUnits: TArray<TAtlasTestUnitInput>;
begin
  SetLength(Result, Length(AUnits));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIndex;
  end;
  mUnits := AUnits;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareText(mUnits[ALeft].Found.UnitName, mUnits[ARight].Found.UnitName);
      if Result = 0 then
      begin
        Result := CompareText(mUnits[ALeft].FileName, mUnits[ARight].FileName);
      end;
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
end;

/// <summary>Summe zweier Stände (Knoten über mehreren Fixtures).</summary>
function Added(const ALeft, ARight: TAtlasTestTally): TAtlasTestTally;
begin
  Result := ALeft;
  Inc(Result.Total, ARight.Total);
  Inc(Result.Ran, ARight.Ran);
  Inc(Result.Passed, ARight.Passed);
  Inc(Result.Failed, ARight.Failed);
  Inc(Result.Stale, ARight.Stale);
  Inc(Result.StalePassed, ARight.StalePassed);
  Inc(Result.DurationMs, ARight.DurationMs);
  Result.SlowestMs := Max(Result.SlowestMs, ARight.SlowestMs);
  Inc(Result.Leaked, ARight.Leaked);
  Inc(Result.LeakBytes, ARight.LeakBytes);
end;

/// <summary>Neuer Knoten mit Index und Elternteil.</summary>
function NewNode(AKind: TAtlasTestNodeKind; AParent, AUnitIndex: Integer; const AFileName: string): TAtlasTestNode;
begin
  Result := Default(TAtlasTestNode);
  Result.Kind := AKind;
  Result.Parent := AParent;
  Result.UnitIndex := AUnitIndex;
  Result.FixtureIndex := -1;
  Result.TestIndex := -1;
  Result.CaseIndex := -1;
  Result.FileName := AFileName;
  Result.Line := -1;
end;

/// <summary>Ergebnisse einer Fixture aus ACases (Vorauswahl, damit TallyOf nicht alle Ergebnisse je Test
/// durchsucht).</summary>
function FixtureCases(const ACases: TArray<TTestCaseResult>; const AUnitName,
  AFixture: string): TArray<TTestCaseResult>;
begin
  Result := TAtlasTestRun.ResultsOf(ACases, AUnitName, AFixture, '', '');
end;

/// <summary>Knoten der Tests und Fälle von Fixture AFixtureIndex anhängen.</summary>
procedure AddTests(var ANodes: TArray<TAtlasTestNode>; const AInput: TAtlasTestUnitInput; AUnitIndex,
  AFixtureIndex, AFixtureNode: Integer; const ACases: TArray<TTestCaseResult>);
var
  mFound: TDUnitXUnit;
  mFixture: TDUnitXFixture;
  mTest: TDUnitXTest;
  mStale: TAtlasTestStaleFunc;
  mNode: TAtlasTestNode;
  mTestIndex, mCaseIndex, mTestNode: Integer;
begin
  mFound := AInput.Found;
  mFixture := mFound.Fixtures[AFixtureIndex];
  mStale := TAtlasTestRun.StaleOf(AInput.StaleKeys, mFound.UnitName, mFixture.Name);
  for mTestIndex := 0 to High(mFixture.Tests) do
  begin
    mTest := mFixture.Tests[mTestIndex];
    mNode := NewNode(TAtlasTestNodeKind.Test, AFixtureNode, AUnitIndex, AInput.FileName);
    mNode.Caption := mTest.Method;
    mNode.FullName := TDUnitXCommandLine.TestName(mFound.UnitName, mFixture.Name, mTest.Method);
    mNode.FixtureIndex := AFixtureIndex;
    mNode.TestIndex := mTestIndex;
    mNode.Line := mFound.LineOf(mFixture.Name, mTest.Method);
    mNode.Ignored := mTest.Ignored;
    mNode.Tally := TAtlasTestRun.TallyOf(ACases, mFound.UnitName, mFixture.Name,
      TAtlasTestRun.Expected(mFound, AFixtureIndex, mTestIndex, -1), mStale);
    mTestNode := Length(ANodes);
    ANodes := ANodes + [mNode];
    if mTest.Ignored then
    begin
      // Mit [Ignore] führt DUnitX den Test als einen ohne Fälle.
      Continue;
    end;
    for mCaseIndex := 0 to High(mTest.Cases) do
    begin
      mNode := NewNode(TAtlasTestNodeKind.TestCase, mTestNode, AUnitIndex, AInput.FileName);
      mNode.Caption := mTest.Cases[mCaseIndex];
      mNode.FullName := TDUnitXCommandLine.CaseName(mFound.UnitName, mFixture.Name, mTest.Method,
        mTest.Cases[mCaseIndex]);
      mNode.FixtureIndex := AFixtureIndex;
      mNode.TestIndex := mTestIndex;
      mNode.CaseIndex := mCaseIndex;
      mNode.Line := -1;
      if mCaseIndex <= High(mTest.CaseLines) then
      begin
        mNode.Line := mTest.CaseLines[mCaseIndex];
      end;
      mNode.Tally := TAtlasTestRun.TallyOf(ACases, mFound.UnitName, mFixture.Name,
        TAtlasTestRun.Expected(mFound, AFixtureIndex, mTestIndex, mCaseIndex), mStale);
      ANodes := ANodes + [mNode];
    end;
  end;
end;

/// <summary>Knoten einer Testunit mit Fixtures, Tests und Fällen anhängen.</summary>
procedure AddUnit(var ANodes: TArray<TAtlasTestNode>; const AInput: TAtlasTestUnitInput; AUnitIndex: Integer;
  const ACases: TArray<TTestCaseResult>);
var
  mFound: TDUnitXUnit;
  mNode: TAtlasTestNode;
  mUnitNode, mFixtureNode, mFixtureIndex: Integer;
  mCases: TArray<TTestCaseResult>;
begin
  mFound := AInput.Found;
  mNode := NewNode(TAtlasTestNodeKind.TestUnit, -1, AUnitIndex, AInput.FileName);
  mNode.Caption := mFound.UnitName;
  if mNode.Caption = '' then
  begin
    mNode.Caption := ChangeFileExt(ExtractFileName(AInput.FileName), '');
  end;
  mNode.FullName := mFound.UnitName;
  mNode.Line := 0;
  mUnitNode := Length(ANodes);
  ANodes := ANodes + [mNode];
  for mFixtureIndex := 0 to High(mFound.Fixtures) do
  begin
    mCases := FixtureCases(ACases, mFound.UnitName, mFound.Fixtures[mFixtureIndex].Name);
    mNode := NewNode(TAtlasTestNodeKind.Fixture, mUnitNode, AUnitIndex, AInput.FileName);
    mNode.Caption := mFound.Fixtures[mFixtureIndex].Name;
    mNode.FullName := TDUnitXCommandLine.TestName(mFound.UnitName, mNode.Caption, '');
    mNode.FixtureIndex := mFixtureIndex;
    mNode.Line := mFound.Fixtures[mFixtureIndex].Line;
    mNode.Tally := TAtlasTestRun.TallyOf(mCases, mFound.UnitName, mNode.Caption,
      TAtlasTestRun.Expected(mFound, mFixtureIndex, -1, -1),
      TAtlasTestRun.StaleOf(AInput.StaleKeys, mFound.UnitName, mNode.Caption));
    mNode.Ignored := (Length(mFound.Fixtures[mFixtureIndex].Tests) > 0) and (mNode.Tally.Total = 0);
    ANodes[mUnitNode].Tally := Added(ANodes[mUnitNode].Tally, mNode.Tally);
    mFixtureNode := Length(ANodes);
    ANodes := ANodes + [mNode];
    AddTests(ANodes, AInput, AUnitIndex, mFixtureIndex, mFixtureNode, mCases);
  end;
end;

{ TAtlasTestExplorer }

class function TAtlasTestExplorer.Build(const AUnits: TArray<TAtlasTestUnitInput>;
  const ACases: TArray<TTestCaseResult>): TArray<TAtlasTestNode>;
var
  mUnitIndex: Integer;
begin
  Result := nil;
  for mUnitIndex in SortedUnits(AUnits) do
  begin
    if Length(AUnits[mUnitIndex].Found.Fixtures) > 0 then
    begin
      AddUnit(Result, AUnits[mUnitIndex], mUnitIndex, ACases);
    end;
  end;
end;

class function TAtlasTestExplorer.StateOf(const ANode: TAtlasTestNode): TAtlasTestNodeState;
begin
  case ANode.Tally.Shown of
    TAtlasTestStatus.Failed:
      Result := TAtlasTestNodeState.Failed;
    TAtlasTestStatus.Passed:
      begin
        Result := TAtlasTestNodeState.Passed;
        if ANode.Tally.IsStale then
        begin
          Result := TAtlasTestNodeState.Stale;
        end;
      end;
    TAtlasTestStatus.Partial:
      Result := TAtlasTestNodeState.Partial;
  else
    Result := TAtlasTestNodeState.NotRun;
  end;
end;

class function TAtlasTestExplorer.RowText(const ANode: TAtlasTestNode; const ATexts: TAtlasTestRowTexts): string;
var
  mCounter: string;
begin
  Result := ANode.Caption;
  if ANode.Ignored then
  begin
    Exit(Format(ATexts.Ignored, [Result]));
  end;
  mCounter := Counter(ANode);
  // Ein Test ohne Fälle bzw. ein Fall zählt nur sich selbst: „1/1“ sagt nichts, der Punkt zeigt den Stand.
  if (mCounter <> '') and ((ANode.Kind in [TAtlasTestNodeKind.TestUnit, TAtlasTestNodeKind.Fixture]) or
    (ANode.Tally.Total > 1)) then
  begin
    Result := Result + ' · ' + mCounter;
  end;
  if ANode.Tally.DurationMs > 0 then
  begin
    Result := Result + ' · ' + TTestResults.DurationText(ANode.Tally.DurationMs, ATexts.DecimalSeparator);
  end;
end;

class function TAtlasTestExplorer.Rows(const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>;
  const ATexts: TAtlasTestRowTexts): TArray<TAtlasTestRow>;
var
  mRowOf: TArray<Integer>;
  mIndex, mCount: Integer;
begin
  Result := nil;
  SetLength(mRowOf, Length(ANodes));
  SetLength(Result, Length(ANodes));
  mCount := 0;
  for mIndex := 0 to High(ANodes) do
  begin
    mRowOf[mIndex] := -1;
    if (mIndex > High(AVisible)) or not AVisible[mIndex] then
    begin
      Continue;
    end;
    mRowOf[mIndex] := mCount;
    Result[mCount].Node := mIndex;
    Result[mCount].Parent := -1;
    if ANodes[mIndex].Parent >= 0 then
    begin
      Result[mCount].Parent := mRowOf[ANodes[mIndex].Parent];
    end;
    Result[mCount].Text := RowText(ANodes[mIndex], ATexts);
    Result[mCount].State := StateOf(ANodes[mIndex]);
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

class procedure TAtlasTestExplorer.Totals(const ANodes: TArray<TAtlasTestNode>; out ATotal, APassed, AFailed,
  ANotRun: Integer);
var
  mNode: TAtlasTestNode;
begin
  ATotal := 0;
  APassed := 0;
  AFailed := 0;
  ANotRun := 0;
  for mNode in ANodes do
  begin
    if mNode.Kind = TAtlasTestNodeKind.TestUnit then
    begin
      Inc(ATotal, mNode.Tally.Total);
      Inc(APassed, mNode.Tally.FreshPassed);
      Inc(AFailed, mNode.Tally.Failed);
      Inc(ANotRun, mNode.Tally.Total - mNode.Tally.Ran);
    end;
  end;
end;

class function TAtlasTestExplorer.Counter(const ANode: TAtlasTestNode): string;
begin
  Result := '';
  if ANode.Tally.Total > 0 then
  begin
    Result := Format('%d/%d', [ANode.Tally.FreshPassed, ANode.Tally.Total]);
  end;
end;

class function TAtlasTestExplorer.Matches(const ANode: TAtlasTestNode; AFilters: TAtlasTestFilters;
  const ASearch: string; ASlowMs: Integer): Boolean;
var
  mTally: TAtlasTestTally;
begin
  if (ASearch <> '') and (Pos(AnsiLowerCase(ASearch), AnsiLowerCase(ANode.FullName)) = 0) then
  begin
    Exit(False);
  end;
  if AFilters = [] then
  begin
    Exit(True);
  end;
  mTally := ANode.Tally;
  Result := ((TAtlasTestFilter.Failed in AFilters) and (mTally.Failed > 0)) or
    ((TAtlasTestFilter.NotRun in AFilters) and (mTally.Ran < mTally.Total)) or
    ((TAtlasTestFilter.Stale in AFilters) and mTally.IsStale) or
    ((TAtlasTestFilter.Slow in AFilters) and TAtlasTestDurations.IsSlow(mTally.SlowestMs, ASlowMs));
end;

/// <summary>Ein Blatt: Test ohne Fälle (bzw. ignoriert) oder ein Fall. Nur Blätter entscheiden über Filter;
/// innere Knoten folgen ihren Kindern.</summary>
function IsLeaf(const ANodes: TArray<TAtlasTestNode>; AIndex: Integer): Boolean;
begin
  Result := (AIndex = High(ANodes)) or (ANodes[AIndex + 1].Parent <> AIndex);
end;

class function TAtlasTestExplorer.Visible(const ANodes: TArray<TAtlasTestNode>; AFilters: TAtlasTestFilters;
  const ASearch: string; ASlowMs: Integer): TArray<Boolean>;
var
  mIndex, mParent: Integer;
begin
  SetLength(Result, Length(ANodes));
  // Kinder stehen hinter ihrem Elternknoten: rückwärts trägt jeder sichtbare Knoten die Sichtbarkeit nach oben.
  for mIndex := High(ANodes) downto 0 do
  begin
    if IsLeaf(ANodes, mIndex) and Matches(ANodes[mIndex], AFilters, ASearch, ASlowMs) then
    begin
      Result[mIndex] := True;
    end;
    if Result[mIndex] then
    begin
      mParent := ANodes[mIndex].Parent;
      if mParent >= 0 then
      begin
        Result[mParent] := True;
      end;
    end;
  end;
end;

/// <summary>Ist ein Vorfahr von AIndex unter den gewählten?</summary>
function AncestorSelected(const ANodes: TArray<TAtlasTestNode>; const ASelected: TArray<Integer>;
  AIndex: Integer): Boolean;
var
  mParent, mChosen: Integer;
begin
  Result := False;
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
end;

/// <summary>ANames um AMore ergänzen, ohne doppelte (ohne Groß-/Kleinschreibung).</summary>
procedure AddNames(var ANames: TArray<string>; const AMore: TArray<string>);
var
  mName, mKnown: string;
  mFound: Boolean;
begin
  for mName in AMore do
  begin
    mFound := False;
    for mKnown in ANames do
    begin
      mFound := mFound or SameText(mKnown, mName);
    end;
    if not mFound then
    begin
      ANames := ANames + [mName];
    end;
  end;
end;

class function TAtlasTestExplorer.RunNames(const AUnits: TArray<TAtlasTestUnitInput>;
  const ANodes: TArray<TAtlasTestNode>; const ASelected: TArray<Integer>): TArray<string>;
var
  mIndex, mFixture: Integer;
  mNode: TAtlasTestNode;
  mFound: TDUnitXUnit;
begin
  Result := nil;
  for mIndex in ASelected do
  begin
    if (mIndex < 0) or (mIndex > High(ANodes)) or AncestorSelected(ANodes, ASelected, mIndex) then
    begin
      Continue;
    end;
    mNode := ANodes[mIndex];
    if (mNode.UnitIndex < 0) or (mNode.UnitIndex > High(AUnits)) then
    begin
      Continue;
    end;
    mFound := AUnits[mNode.UnitIndex].Found;
    if mNode.Kind = TAtlasTestNodeKind.TestUnit then
    begin
      for mFixture := 0 to High(mFound.Fixtures) do
      begin
        AddNames(Result, TDUnitXCommandLine.RunNames(mFound, mFixture, -1, -1));
      end;
    end
    else
    begin
      AddNames(Result, TDUnitXCommandLine.RunNames(mFound, mNode.FixtureIndex, mNode.TestIndex, mNode.CaseIndex));
    end;
  end;
end;

class function TAtlasTestExplorer.ResultsOf(const ANode: TAtlasTestNode; const AUnits: TArray<TAtlasTestUnitInput>;
  const ACases: TArray<TTestCaseResult>): TArray<TTestCaseResult>;
var
  mFound: TDUnitXUnit;
  mFixture, mMethod, mCase: string;
  mAll: TArray<TTestCaseResult>;
  mItem: TTestCaseResult;
  mRest: TArray<TTestCaseResult>;
begin
  Result := nil;
  if (ANode.Kind = TAtlasTestNodeKind.TestUnit) or (ANode.UnitIndex < 0) or (ANode.UnitIndex > High(AUnits)) then
  begin
    Exit;
  end;
  mFound := AUnits[ANode.UnitIndex].Found;
  mFixture := mFound.Fixtures[ANode.FixtureIndex].Name;
  mMethod := '';
  mCase := '';
  if ANode.TestIndex >= 0 then
  begin
    mMethod := mFound.Fixtures[ANode.FixtureIndex].Tests[ANode.TestIndex].Method;
  end;
  if ANode.CaseIndex >= 0 then
  begin
    mCase := mFound.Fixtures[ANode.FixtureIndex].Tests[ANode.TestIndex].Cases[ANode.CaseIndex];
  end;
  mAll := TAtlasTestRun.ResultsOf(ACases, mFound.UnitName, mFixture, mMethod, mCase);
  mRest := nil;
  for mItem in mAll do
  begin
    if mItem.IsFailure then
    begin
      Result := Result + [mItem];
    end
    else
    begin
      mRest := mRest + [mItem];
    end;
  end;
  Result := Result + mRest;
end;

class function TAtlasTestExplorer.StackLines(const AStackTrace: string;
  const AUnits: TArray<TAtlasTestUnitRef>): TArray<TAtlasTestStackLine>;
var
  mEntry: string;
  mLine: TAtlasTestStackLine;
  mUnit: TAtlasTestUnitRef;
  mFound, mLongest: Integer;
begin
  Result := nil;
  for mEntry in AStackTrace.Split([#10]) do
  begin
    mLine := Default(TAtlasTestStackLine);
    mLine.Text := TrimRight(mEntry);
    mLine.Line := -1;
    if Trim(mLine.Text) = '' then
    begin
      Continue;
    end;
    mLongest := -1;
    for mUnit in AUnits do
    begin
      // „Rechner“ steht auch in „Rechner.Tests 42“: der längste passende Unitname gilt.
      mFound := TAtlasAssertLine.FromStackTrace(mLine.Text, mUnit.UnitName, mUnit.FileName, MaxInt);
      if (mFound >= 0) and (Length(mUnit.UnitName) > mLongest) then
      begin
        mLongest := Length(mUnit.UnitName);
        mLine.FileName := mUnit.FileName;
        mLine.Line := mFound;
      end;
    end;
    Result := Result + [mLine];
  end;
end;

/// <summary>Zeile ohne Fundstelle.</summary>
function TextLine(const AText: string): TAtlasTestStackLine;
begin
  Result := Default(TAtlasTestStackLine);
  Result.Text := AText;
  Result.Line := -1;
end;

class function TAtlasTestExplorer.DetailLines(const AResults: TArray<TTestCaseResult>;
  const AUnits: TArray<TAtlasTestUnitRef>; const ATexts: TAtlasTestDetailTexts): TArray<TAtlasTestStackLine>;
var
  mFirst: TTestCaseResult;
  mMessage: string;
begin
  if Length(AResults) = 0 then
  begin
    Result := [TextLine(ATexts.NotRun)];
    Exit;
  end;
  mFirst := AResults[0];
  if mFirst.Outcome = TTestOutcome.Passed then
  begin
    Result := [TextLine(Format(ATexts.Passed, [TTestResults.DurationText(mFirst.DurationMs,
      ATexts.DecimalSeparator)]))];
    Exit;
  end;
  // Mehrzeilige Meldungen: nur die erste Zeile, der Rest steht im Stacktrace bzw. im Bericht.
  mMessage := Trim(mFirst.Message);
  if Pos(#10, mMessage) > 0 then
  begin
    mMessage := TrimRight(Copy(mMessage, 1, Pos(#10, mMessage) - 1));
  end;
  if mFirst.Outcome = TTestOutcome.Skipped then
  begin
    Result := [TextLine(Format(ATexts.Skipped, [mMessage]))];
    Exit;
  end;
  Result := [TextLine(Format(ATexts.Message, [mMessage]))];
  if mFirst.HasValues then
  begin
    Result := Result + [TextLine(Format(ATexts.Expected, [mFirst.Expected])),
      TextLine(Format(ATexts.Actual, [mFirst.Actual]))];
  end;
  if Trim(mFirst.StackTrace) <> '' then
  begin
    Result := Result + [TextLine(ATexts.Stack)] + StackLines(mFirst.StackTrace, AUnits);
  end;
end;

end.
