unit Atlas.Core.Tests.Lists;

// Testlisten des Fensters „Atlas-Tests“ (#2167), ohne VCL und Open Tools API,
// auch unter FPC prüfbar:
// - Eine Liste ist fest (Namen von Testunits, Fixtures, Tests oder Fällen wie
//   in DUnitX: Unit[.Fixture[.Methode[.Fall]]]) oder dynamisch (Regeln, mit
//   „und“ verknüpft): Kategorie ist bzw. ist nicht (an Fixture oder Test),
//   Unit bzw. Fixture passt bzw. passt nicht auf ein Muster mit * und ?
//   (verglichen mit dem Unitnamen und mit Unit.Fixture), Stand fehlgeschlagen,
//   nicht gelaufen oder veraltet (#1770). Neue Tests, die passen, gehören ohne
//   Zutun dazu.
// - Ausgewertet wird je Blatt des Baums (Test ohne Fälle, ignorierter Test
//   oder Fall, TAtlasTestListItem). Ignorierte Tests zählen nicht mit.
// - RunArguments bildet die Argumente eines Laufs: Kategorie-Regeln, deren
//   Kategorie an keiner Fixture des Projekts steht, gehen als --include bzw.
//   --exclude an DUnitX (ältere DUnitX-Fassungen geben Kategorien einer
//   Fixture nicht an ihre Tests weiter, darum nur diese); alle übrigen Regeln
//   wertet Atlas aus und nennt die Tests über --run. Die Namen fasst es so weit
//   zusammen, wie es geht: eine Fixture, deren Tests alle dazugehören, über
//   ihren Namen, viele Fixtures über einen gemeinsamen Anfang ihres Namens
//   (Namensraum wie „Atlas.Core“), wenn jede Fixture mit diesem Anfang ganz
//   dazugehört. DUnitX vergleicht in älteren Fassungen nur den Textanfang, in
//   neueren den Anfang bis zu einem Punkt; die Bedingung gilt für beide.
// - Ablage: Listen „im Projekt“ stehen in atlas.json unter "testLists", Listen
//   „nur für mich“ in einer Datei des Plugins (Atlas.IDE.Tests.Lists). Parse
//   und ToJson lesen bzw. schreiben das Array der Listen einer Ablage:
//     [{"name": "Vor dem Commit",
//       "rules": [{"category": "Benchmark", "exclude": true},
//                 {"unit": "*.Slow.*", "exclude": true},
//                 {"state": "failed"}]},
//      {"name": "Parser", "tests": ["Atlas.Common.Pascal.Tests.TLexerTests"]}]
//   Ungültige Einträge (ohne Namen, doppelter Name, unbekannte Regel) fallen
//   weg; die genaue Prüfung von atlas.json macht der Server.

interface

uses
  Atlas.Text.DUnitX;

type
{$SCOPEDENUMS ON}
  TAtlasTestListRuleKind = (Category, Pattern, State);
  TAtlasTestListState = (Failed, NotRun, Stale);
  /// <summary>Ablage einer Liste: in atlas.json des Projekts (für das Team) oder nur für diesen Benutzer.</summary>
  TAtlasTestListStore = (Project, Personal);
  /// <summary>Ergebnis von RunArguments.</summary>
  TAtlasTestListRun = (
    /// <summary>Argumente bereit (leer = alle Tests).</summary>
    Ready,
    /// <summary>Kein Test gehört dazu.</summary>
    Empty,
    /// <summary>Die Namen passen nicht in eine Befehlszeile.</summary>
    TooLong);
{$SCOPEDENUMS OFF}

  TAtlasTestListRule = record
    Kind: TAtlasTestListRuleKind;
    /// <summary>Kategorie bzw. Muster; bei State leer.</summary>
    Value: string;
    State: TAtlasTestListState;
    /// <summary>„ist nicht“ bzw. „passt nicht“.</summary>
    Exclude: Boolean;
    class function Category(const AName: string; AExclude: Boolean): TAtlasTestListRule; static;
    class function Pattern(const APattern: string; AExclude: Boolean): TAtlasTestListRule; static;
    class function OfState(AState: TAtlasTestListState; AExclude: Boolean): TAtlasTestListRule; static;
  end;

  TAtlasTestList = record
    Name: string;
    Store: TAtlasTestListStore;
    /// <summary>Regeln einer dynamischen Liste; leer bei einer festen.</summary>
    Rules: TArray<TAtlasTestListRule>;
    /// <summary>Namen einer festen Liste: Unit, Unit.Fixture, Unit.Fixture.Methode oder voller Name eines Falls.
    /// </summary>
    Tests: TArray<string>;
    function IsDynamic: Boolean;
  end;

  TAtlasTestLists = TArray<TAtlasTestList>;

  /// <summary>Ein Blatt des Baums für die Auswertung: Test ohne Fälle (bzw. ignoriert) oder ein Fall.</summary>
  TAtlasTestListItem = record
    /// <summary>Index in die Units von Items bzw. RunArguments, Fixture, Test und Fall darin (-1 ohne Fall).
    /// </summary>
    UnitIndex: Integer;
    FixtureIndex: Integer;
    TestIndex: Integer;
    CaseIndex: Integer;
    UnitName: string;
    /// <summary>Unit.Fixture wie in DUnitX.</summary>
    FixtureName: string;
    /// <summary>Voller Name des Tests bzw. Falls wie in DUnitX.</summary>
    FullName: string;
    /// <summary>Kategorien der Fixture und des Tests.</summary>
    Categories: TArray<string>;
    Ignored: Boolean;
    Failed: Boolean;
    NotRun: Boolean;
    Stale: Boolean;
    /// <summary>Knoten im Baum des Fensters; -1, solange nicht zugeordnet.</summary>
    Node: Integer;
  end;

  TAtlasTestListItems = TArray<TAtlasTestListItem>;

  TAtlasTestListModel = class
  public const
    cKeyTestLists = 'testLists';
  public
    /// <summary>Blätter aller Fixtures von AUnits in deren Reihenfolge; Stand „nicht gelaufen“.</summary>
    class function Items(const AUnits: TArray<TDUnitXUnit>): TAtlasTestListItems; static;
    /// <summary>Passt AText auf APattern (* beliebig viele, ? ein Zeichen; ohne Groß-/Kleinschreibung)?</summary>
    class function PatternMatches(const APattern, AText: string): Boolean; static;
    /// <summary>Erfüllt AItem die Regel (Exclude schon eingerechnet)?</summary>
    class function RuleMatches(const ARule: TAtlasTestListRule; const AItem: TAtlasTestListItem): Boolean; static;
    /// <summary>Gehört AItem zur Liste: dynamisch alle Regeln, fest einer der Namen (er selbst oder ein Teil davor)?
    /// Eine dynamische Liste ohne Regeln enthält alles.</summary>
    class function Contains(const AList: TAtlasTestList; const AItem: TAtlasTestListItem): Boolean; static;
    /// <summary>Contains je Eintrag von AItems.</summary>
    class function Members(const AList: TAtlasTestList; const AItems: TAtlasTestListItems): TArray<Boolean>; static;
    /// <summary>Zählt die nicht ignorierten Blätter: alle (ATotal) und die mit AMembers (AInList).</summary>
    class procedure Count(const AItems: TAtlasTestListItems; const AMembers: TArray<Boolean>; out AInList,
      ATotal: Integer); static;
    /// <summary>Argumente für einen Lauf der Liste über AItems (aus Items mit dem Stand) und AUnits: zuerst
    /// --include/--exclude, dann die Namen für --run (TDUnitXCommandLine.Arguments). Leer bei Ready: alle Tests.
    /// </summary>
    class function RunArguments(const AList: TAtlasTestList; const AItems: TAtlasTestListItems;
      const AUnits: TArray<TDUnitXUnit>; out AArguments: TArray<string>): TAtlasTestListRun; static;
    /// <summary>Listen aus dem JSON-Array AJson ('' oder ungültig = keine), alle mit Ablage AStore.</summary>
    class function Parse(const AJson: string; AStore: TAtlasTestListStore): TAtlasTestLists; static;
    /// <summary>JSON-Array der Listen ALists (ohne Ablage); die Zeilen nach der ersten beginnen mit AIndent
    /// (Einrückung des Schlüssels, unter dem das Array steht).</summary>
    class function ToJson(const ALists: TAtlasTestLists; const AIndent: string): string; static;
    /// <summary>Listen von ALists mit Ablage AStore.</summary>
    class function OfStore(const ALists: TAtlasTestLists; AStore: TAtlasTestListStore): TAtlasTestLists; static;
    /// <summary>Index der Liste AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOf(const ALists: TAtlasTestLists; const AName: string): Integer; static;
    /// <summary>ABase, sonst „ABase (2)“, „ABase (3)“ … ohne Namen aus ALists.</summary>
    class function UniqueName(const ALists: TAtlasTestLists; const ABase: string): string; static;
    /// <summary>Namen ANames an die feste Liste AList anfügen, ohne doppelte und ohne solche, die ein Name der Liste
    /// schon ganz enthält. Anzahl der neuen.</summary>
    class function AddTests(var AList: TAtlasTestList; const ANames: TArray<string>): Integer; static;
    /// <summary>Namen ANames aus der festen Liste AList entfernen. Anzahl der entfernten.</summary>
    class function RemoveTests(var AList: TAtlasTestList; const ANames: TArray<string>): Integer; static;
    /// <summary>Kennwort eines Stands in JSON (failed, notRun, stale).</summary>
    class function StateName(AState: TAtlasTestListState): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

const
  cStateNames: array[TAtlasTestListState] of string = ('failed', 'notRun', 'stale');
  cIndent = '  ';
  cNewLine = #13#10;
  /// <summary>Zusatz einer Regel mit „ist nicht“ bzw. „passt nicht“.</summary>
  cExcludeJson = ', "exclude": true';

{ TAtlasTestListRule }

class function TAtlasTestListRule.Category(const AName: string; AExclude: Boolean): TAtlasTestListRule;
begin
  Result := Default(TAtlasTestListRule);
  Result.Kind := TAtlasTestListRuleKind.Category;
  Result.Value := AName;
  Result.Exclude := AExclude;
end;

class function TAtlasTestListRule.Pattern(const APattern: string; AExclude: Boolean): TAtlasTestListRule;
begin
  Result := Default(TAtlasTestListRule);
  Result.Kind := TAtlasTestListRuleKind.Pattern;
  Result.Value := APattern;
  Result.Exclude := AExclude;
end;

class function TAtlasTestListRule.OfState(AState: TAtlasTestListState; AExclude: Boolean): TAtlasTestListRule;
begin
  Result := Default(TAtlasTestListRule);
  Result.Kind := TAtlasTestListRuleKind.State;
  Result.State := AState;
  Result.Exclude := AExclude;
end;

{ TAtlasTestList }

function TAtlasTestList.IsDynamic: Boolean;
begin
  Result := Length(Rules) > 0;
end;

{ Blätter }

/// <summary>Kategorien von Fixture und Test ohne doppelte.</summary>
function JoinedCategories(const AFixture, ATest: TArray<string>): TArray<string>;
var
  mName, mKnown: string;
  mFound: Boolean;
begin
  Result := AFixture;
  for mName in ATest do
  begin
    mFound := False;
    for mKnown in Result do
    begin
      mFound := mFound or SameText(mKnown, mName);
    end;
    if not mFound then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Blatt zu Fixture AFixture, Test ATest, Fall ACase (-1 ohne) von AUnit.</summary>
function NewItem(const AUnit: TDUnitXUnit; AUnitIndex, AFixture, ATest, ACase: Integer): TAtlasTestListItem;
var
  mFixture: TDUnitXFixture;
  mTest: TDUnitXTest;
begin
  mFixture := AUnit.Fixtures[AFixture];
  mTest := mFixture.Tests[ATest];
  Result := Default(TAtlasTestListItem);
  Result.UnitIndex := AUnitIndex;
  Result.FixtureIndex := AFixture;
  Result.TestIndex := ATest;
  Result.CaseIndex := ACase;
  Result.UnitName := AUnit.UnitName;
  Result.FixtureName := TDUnitXCommandLine.TestName(AUnit.UnitName, mFixture.Name, '');
  if ACase >= 0 then
  begin
    Result.FullName := TDUnitXCommandLine.CaseName(AUnit.UnitName, mFixture.Name, mTest.Method, mTest.Cases[ACase]);
  end
  else
  begin
    Result.FullName := TDUnitXCommandLine.TestName(AUnit.UnitName, mFixture.Name, mTest.Method);
  end;
  Result.Categories := JoinedCategories(mFixture.Categories, mTest.Categories);
  Result.Ignored := mTest.Ignored;
  Result.NotRun := True;
  Result.Node := -1;
end;

class function TAtlasTestListModel.Items(const AUnits: TArray<TDUnitXUnit>): TAtlasTestListItems;
var
  mUnit, mFixture, mTest, mCase: Integer;
  mCases: TArray<string>;
begin
  Result := nil;
  for mUnit := 0 to High(AUnits) do
  begin
    for mFixture := 0 to High(AUnits[mUnit].Fixtures) do
    begin
      for mTest := 0 to High(AUnits[mUnit].Fixtures[mFixture].Tests) do
      begin
        mCases := AUnits[mUnit].Fixtures[mFixture].Tests[mTest].Cases;
        // Mit [Ignore] führt DUnitX einen [TestCase]-Test als einen ohne Fälle (wie der Baum).
        if (Length(mCases) = 0) or AUnits[mUnit].Fixtures[mFixture].Tests[mTest].Ignored then
        begin
          Result := Result + [NewItem(AUnits[mUnit], mUnit, mFixture, mTest, -1)];
          Continue;
        end;
        for mCase := 0 to High(mCases) do
        begin
          Result := Result + [NewItem(AUnits[mUnit], mUnit, mFixture, mTest, mCase)];
        end;
      end;
    end;
  end;
end;

{ Regeln }

function MatchFrom(const APattern, AText: string; APatternPos, ATextPos: Integer): Boolean; forward;

/// <summary>APattern hat an APatternPos ein *: mehrere * wirken wie eins; danach jede Stelle ab ATextPos versuchen.
/// </summary>
function MatchStar(const APattern, AText: string; APatternPos, ATextPos: Integer): Boolean;
var
  mRest: Integer;
begin
  while (APatternPos <= Length(APattern)) and (APattern[APatternPos] = '*') do
  begin
    Inc(APatternPos);
  end;
  Result := APatternPos > Length(APattern);
  mRest := ATextPos;
  while not Result and (mRest <= Length(AText)) do
  begin
    Result := MatchFrom(APattern, AText, APatternPos, mRest);
    Inc(mRest);
  end;
end;

/// <summary>Passt AText ab ATextPos auf APattern ab APatternPos (beide schon klein)?</summary>
function MatchFrom(const APattern, AText: string; APatternPos, ATextPos: Integer): Boolean;
begin
  while APatternPos <= Length(APattern) do
  begin
    if APattern[APatternPos] = '*' then
    begin
      Exit(MatchStar(APattern, AText, APatternPos, ATextPos));
    end;
    if (ATextPos > Length(AText)) or ((APattern[APatternPos] <> '?') and
      (APattern[APatternPos] <> AText[ATextPos])) then
    begin
      Exit(False);
    end;
    Inc(APatternPos);
    Inc(ATextPos);
  end;
  Result := ATextPos > Length(AText);
end;

class function TAtlasTestListModel.PatternMatches(const APattern, AText: string): Boolean;
begin
  Result := MatchFrom(AnsiLowerCase(Trim(APattern)), AnsiLowerCase(AText), 1, 1);
end;

function HasCategory(const AItem: TAtlasTestListItem; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AItem.Categories do
  begin
    if SameText(mName, Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
end;

function HasState(const AItem: TAtlasTestListItem; AState: TAtlasTestListState): Boolean;
begin
  case AState of
    TAtlasTestListState.Failed:
      Result := AItem.Failed;
    TAtlasTestListState.NotRun:
      Result := AItem.NotRun;
  else
    Result := AItem.Stale;
  end;
end;

class function TAtlasTestListModel.RuleMatches(const ARule: TAtlasTestListRule;
  const AItem: TAtlasTestListItem): Boolean;
begin
  case ARule.Kind of
    TAtlasTestListRuleKind.Category:
      Result := HasCategory(AItem, ARule.Value);
    TAtlasTestListRuleKind.Pattern:
      Result := PatternMatches(ARule.Value, AItem.UnitName) or PatternMatches(ARule.Value, AItem.FixtureName);
  else
    Result := HasState(AItem, ARule.State);
  end;
  Result := Result <> ARule.Exclude;
end;

/// <summary>Nennt AName den Test bzw. Fall AFullName oder einen Teil davor (Unit, Fixture, Methode)? Ein Fall in
/// Klammern folgt ohne Punkt.</summary>
function NameCovers(const AName, AFullName: string): Boolean;
begin
  Result := (AName <> '') and (SameText(AName, AFullName) or SameText(AName + '.', Copy(AFullName, 1,
    Length(AName) + 1)) or SameText(AName + '(', Copy(AFullName, 1, Length(AName) + 1)));
end;

class function TAtlasTestListModel.Contains(const AList: TAtlasTestList; const AItem: TAtlasTestListItem): Boolean;
var
  mRule: TAtlasTestListRule;
  mName: string;
begin
  if AList.IsDynamic then
  begin
    for mRule in AList.Rules do
    begin
      if not RuleMatches(mRule, AItem) then
      begin
        Exit(False);
      end;
    end;
    Exit(True);
  end;
  for mName in AList.Tests do
  begin
    if NameCovers(mName, AItem.FullName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTestListModel.Members(const AList: TAtlasTestList;
  const AItems: TAtlasTestListItems): TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := Contains(AList, AItems[mIndex]);
  end;
end;

class procedure TAtlasTestListModel.Count(const AItems: TAtlasTestListItems; const AMembers: TArray<Boolean>;
  out AInList, ATotal: Integer);
var
  mIndex: Integer;
begin
  AInList := 0;
  ATotal := 0;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Ignored then
    begin
      Continue;
    end;
    Inc(ATotal);
    if (mIndex <= High(AMembers)) and AMembers[mIndex] then
    begin
      Inc(AInList);
    end;
  end;
end;

{ Argumente }

type
{$SCOPEDENUMS ON}
  /// <summary>Stand einer Fixture für die Namen: keiner ihrer Tests, einige, alle nicht ignorierten.</summary>
  TFixtureCover = (None, Partial, Full);
{$SCOPEDENUMS OFF}

  /// <summary>Zustand von RunArguments: Blätter, Zugehörigkeit und Fixtures mit ihrem Stand.</summary>
  TRunNames = record
    Items: TAtlasTestListItems;
    Members: TArray<Boolean>;
    Units: TArray<TDUnitXUnit>;
    /// <summary>Unit.Fixture je Fixture (Schlüssel „Unit|Fixture“ über FixtureKeys).</summary>
    FixtureNames: TArray<string>;
    FixtureCovers: TArray<TFixtureCover>;
    /// <summary>Index in FixtureNames je Blatt.</summary>
    FixtureOf: TArray<Integer>;
    Names: TArray<string>;
    procedure Prepare;
    /// <summary>Nimmt jede Fixture, deren Name mit APrefix beginnt (Textanfang), ganz dazu?</summary>
    function AllFull(const APrefix: string): Boolean;
    /// <summary>Kürzester Name für die ganze Fixture AFixture (Namensraum oder sie selbst); '' ohne.</summary>
    function ShortestName(AFixture: Integer): string;
    /// <summary>Wird AFixture schon von einem Namen getroffen (gleich oder Anfang bis zu einem Punkt)?</summary>
    function Covered(AFixture: Integer): Boolean;
    procedure AddNames(const AMore: TArray<string>);
    /// <summary>Namen der Tests bzw. Fälle von AFixture, die dazugehören.</summary>
    procedure AddPartial(AFixture: Integer);
    procedure Build;
  end;

procedure TRunNames.Prepare;
var
  mKeys: TDictionary<string, Integer>;
  mIndex, mFixture: Integer;
  mKey: string;
  mAll, mAny: TArray<Boolean>;
begin
  FixtureNames := nil;
  SetLength(FixtureOf, Length(Items));
  mKeys := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(Items) do
    begin
      mKey := IntToStr(Items[mIndex].UnitIndex) + '|' + IntToStr(Items[mIndex].FixtureIndex);
      if not mKeys.TryGetValue(mKey, mFixture) then
      begin
        mFixture := Length(FixtureNames);
        mKeys.Add(mKey, mFixture);
        FixtureNames := FixtureNames + [Items[mIndex].FixtureName];
      end;
      FixtureOf[mIndex] := mFixture;
    end;
  finally
    mKeys.Free;
  end;
  SetLength(mAll, Length(FixtureNames));
  SetLength(mAny, Length(FixtureNames));
  for mFixture := 0 to High(mAll) do
  begin
    mAll[mFixture] := True;
  end;
  for mIndex := 0 to High(Items) do
  begin
    // Ignorierte Tests laufen ohnehin nicht: Sie stehen einer ganzen Fixture nicht im Weg.
    if Members[mIndex] then
    begin
      mAny[FixtureOf[mIndex]] := True;
    end
    else if not Items[mIndex].Ignored then
    begin
      mAll[FixtureOf[mIndex]] := False;
    end;
  end;
  SetLength(FixtureCovers, Length(FixtureNames));
  for mFixture := 0 to High(FixtureCovers) do
  begin
    FixtureCovers[mFixture] := TFixtureCover.None;
    if mAny[mFixture] and mAll[mFixture] then
    begin
      FixtureCovers[mFixture] := TFixtureCover.Full;
    end
    else if mAny[mFixture] then
    begin
      FixtureCovers[mFixture] := TFixtureCover.Partial;
    end;
  end;
end;

function TRunNames.AllFull(const APrefix: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FixtureNames) do
  begin
    if SameText(APrefix, Copy(FixtureNames[mIndex], 1, Length(APrefix))) and
      (FixtureCovers[mIndex] <> TFixtureCover.Full) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TRunNames.ShortestName(AFixture: Integer): string;
var
  mName: string;
  mIndex: Integer;
begin
  // Jeder Anfang bis vor einen Punkt, zuletzt der ganze Name.
  mName := FixtureNames[AFixture];
  for mIndex := 2 to Length(mName) + 1 do
  begin
    if ((mIndex > Length(mName)) or (mName[mIndex] = '.')) and AllFull(Copy(mName, 1, mIndex - 1)) then
    begin
      Exit(Copy(mName, 1, mIndex - 1));
    end;
  end;
  Result := '';
end;

function TRunNames.Covered(AFixture: Integer): Boolean;
var
  mName: string;
begin
  for mName in Names do
  begin
    if NameCovers(mName, FixtureNames[AFixture]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TRunNames.AddNames(const AMore: TArray<string>);
var
  mName, mKnown: string;
  mFound: Boolean;
begin
  for mName in AMore do
  begin
    mFound := False;
    for mKnown in Names do
    begin
      mFound := mFound or SameText(mKnown, mName);
    end;
    if not mFound then
    begin
      Names := Names + [mName];
    end;
  end;
end;

procedure TRunNames.AddPartial(AFixture: Integer);
var
  mIndex, mOther: Integer;
  mOwn: TArray<Integer>;
  mWhole: Boolean;
  mItem: TAtlasTestListItem;
begin
  mOwn := nil;
  for mIndex := 0 to High(Items) do
  begin
    if FixtureOf[mIndex] = AFixture then
    begin
      mOwn := mOwn + [mIndex];
    end;
  end;
  for mIndex in mOwn do
  begin
    if not Members[mIndex] then
    begin
      Continue;
    end;
    mItem := Items[mIndex];
    // Gehören alle Fälle des Tests dazu, genügt der Test (RunNames nennt dann jeden Fall, DUnitX verlangt das).
    mWhole := mItem.CaseIndex >= 0;
    for mOther in mOwn do
    begin
      if (Items[mOther].TestIndex = mItem.TestIndex) and not Members[mOther] then
      begin
        mWhole := False;
      end;
    end;
    if mWhole then
    begin
      AddNames(TDUnitXCommandLine.RunNames(Units[mItem.UnitIndex], mItem.FixtureIndex, mItem.TestIndex, -1));
    end
    else
    begin
      AddNames(TDUnitXCommandLine.RunNames(Units[mItem.UnitIndex], mItem.FixtureIndex, mItem.TestIndex,
        mItem.CaseIndex));
    end;
  end;
end;

procedure TRunNames.Build;
var
  mFixture: Integer;
  mName: string;
begin
  Names := nil;
  for mFixture := 0 to High(FixtureNames) do
  begin
    case FixtureCovers[mFixture] of
      TFixtureCover.Full:
        if not Covered(mFixture) then
        begin
          mName := ShortestName(mFixture);
          if mName <> '' then
          begin
            AddNames([mName]);
          end
          else
          begin
            // Eine andere Fixture beginnt mit demselben Namen und gehört nicht ganz dazu: über die Tests.
            AddPartial(mFixture);
          end;
        end;
      TFixtureCover.Partial:
        AddPartial(mFixture);
      TFixtureCover.None: ;
    end;
  end;
end;

/// <summary>Steht die Kategorie AName an einer Fixture von AUnits?</summary>
function OnFixture(const AUnits: TArray<TDUnitXUnit>; const AName: string): Boolean;
var
  mUnit: TDUnitXUnit;
  mFixture: TDUnitXFixture;
  mCategory: string;
begin
  for mUnit in AUnits do
  begin
    for mFixture in mUnit.Fixtures do
    begin
      for mCategory in mFixture.Categories do
      begin
        if SameText(mCategory, Trim(AName)) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Regeln von AList, die DUnitX selbst auswertet, als Optionen; die übrigen in ARest.</summary>
function CategoryOptions(const AList: TAtlasTestList; const AUnits: TArray<TDUnitXUnit>;
  out ARest: TAtlasTestList): TArray<string>;
var
  mRule: TAtlasTestListRule;
begin
  Result := nil;
  ARest := AList;
  ARest.Rules := nil;
  for mRule in AList.Rules do
  begin
    // Kommas trennen in DUnitX mehrere Kategorien: eine solche Regel wertet Atlas aus.
    if (mRule.Kind = TAtlasTestListRuleKind.Category) and (Trim(mRule.Value) <> '') and
      (Pos(',', mRule.Value) = 0) and (Pos(' ', Trim(mRule.Value)) = 0) and not OnFixture(AUnits, mRule.Value) then
    begin
      if mRule.Exclude then
      begin
        Result := Result + ['--exclude:' + Trim(mRule.Value)];
      end
      else
      begin
        Result := Result + ['--include:' + Trim(mRule.Value)];
      end;
    end
    else
    begin
      ARest.Rules := ARest.Rules + [mRule];
    end;
  end;
end;

/// <summary>Gehört jedes nicht ignorierte Blatt dazu?</summary>
function AllMembers(const AItems: TAtlasTestListItems; const AMembers: TArray<Boolean>): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if not AMembers[mIndex] and not AItems[mIndex].Ignored then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TAtlasTestListModel.RunArguments(const AList: TAtlasTestList; const AItems: TAtlasTestListItems;
  const AUnits: TArray<TDUnitXUnit>; out AArguments: TArray<string>): TAtlasTestListRun;
var
  mInList, mTotal, mLength: Integer;
  mRest: TAtlasTestList;
  mNames: TRunNames;
  mName: string;
begin
  AArguments := nil;
  Count(AItems, Members(AList, AItems), mInList, mTotal);
  if mInList = 0 then
  begin
    Exit(TAtlasTestListRun.Empty);
  end;
  mRest := AList;
  if AList.IsDynamic then
  begin
    AArguments := CategoryOptions(AList, AUnits, mRest);
  end;
  mNames := Default(TRunNames);
  mNames.Items := AItems;
  mNames.Units := AUnits;
  if AList.IsDynamic and not mRest.IsDynamic then
  begin
    // Alles ging als Option an DUnitX.
    Exit(TAtlasTestListRun.Ready);
  end;
  mNames.Members := Members(mRest, AItems);
  if AList.IsDynamic and AllMembers(AItems, mNames.Members) then
  begin
    Exit(TAtlasTestListRun.Ready);
  end;
  mNames.Prepare;
  mNames.Build;
  mLength := 0;
  for mName in mNames.Names do
  begin
    Inc(mLength, Length(mName) + 1);
  end;
  if mLength > TDUnitXCommandLine.cMaxRunLength then
  begin
    AArguments := nil;
    Exit(TAtlasTestListRun.TooLong);
  end;
  AArguments := AArguments + mNames.Names;
  Result := TAtlasTestListRun.Ready;
end;

{ Ablage }

class function TAtlasTestListModel.StateName(AState: TAtlasTestListState): string;
begin
  Result := cStateNames[AState];
end;

/// <summary>Text eines Werts von AObject; '' ohne oder bei anderem Typ.</summary>
function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  // TJSONNumber erbt unter FPC und Delphi 12 von TJSONString.
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function ExcludeOf(AObject: TJSONObject): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue('exclude');
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

/// <summary>Regel aus AObject; False bei unbekannter oder leerer.</summary>
function ReadRule(AObject: TJSONObject; out ARule: TAtlasTestListRule): Boolean;
var
  mState: TAtlasTestListState;
  mText: string;
begin
  Result := True;
  if Trim(TextOf(AObject, 'category')) <> '' then
  begin
    ARule := TAtlasTestListRule.Category(Trim(TextOf(AObject, 'category')), ExcludeOf(AObject));
    Exit;
  end;
  if Trim(TextOf(AObject, 'unit')) <> '' then
  begin
    ARule := TAtlasTestListRule.Pattern(Trim(TextOf(AObject, 'unit')), ExcludeOf(AObject));
    Exit;
  end;
  mText := TextOf(AObject, 'state');
  for mState := Low(TAtlasTestListState) to High(TAtlasTestListState) do
  begin
    if SameText(mText, cStateNames[mState]) then
    begin
      ARule := TAtlasTestListRule.OfState(mState, ExcludeOf(AObject));
      Exit;
    end;
  end;
  Result := False;
end;

/// <summary>Liste aus AObject; False ohne Namen.</summary>
function ReadList(AObject: TJSONObject; AStore: TAtlasTestListStore; out AList: TAtlasTestList): Boolean;
var
  mValue: TJSONValue;
  mIndex: Integer;
  mRule: TAtlasTestListRule;
  mArray: TJSONArray;
begin
  AList := Default(TAtlasTestList);
  AList.Name := Trim(TextOf(AObject, 'name'));
  AList.Store := AStore;
  Result := AList.Name <> '';
  mValue := AObject.GetValue('rules');
  if mValue is TJSONArray then
  begin
    mArray := TJSONArray(mValue);
    for mIndex := 0 to mArray.Count - 1 do
    begin
      if (mArray.Items[mIndex] is TJSONObject) and ReadRule(TJSONObject(mArray.Items[mIndex]), mRule) then
      begin
        AList.Rules := AList.Rules + [mRule];
      end;
    end;
  end;
  mValue := AObject.GetValue('tests');
  if mValue is TJSONArray then
  begin
    mArray := TJSONArray(mValue);
    for mIndex := 0 to mArray.Count - 1 do
    begin
      if (mArray.Items[mIndex] is TJSONString) and not (mArray.Items[mIndex] is TJSONNumber) and
        (Trim(TJSONString(mArray.Items[mIndex]).Value) <> '') then
      begin
        AList.Tests := AList.Tests + [Trim(TJSONString(mArray.Items[mIndex]).Value)];
      end;
    end;
  end;
end;

class function TAtlasTestListModel.Parse(const AJson: string; AStore: TAtlasTestListStore): TAtlasTestLists;
var
  mRoot: TJSONValue;
  mIndex: Integer;
  mList: TAtlasTestList;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      Exit;
    end;
    for mIndex := 0 to TJSONArray(mRoot).Count - 1 do
    begin
      if (TJSONArray(mRoot).Items[mIndex] is TJSONObject) and
        ReadList(TJSONObject(TJSONArray(mRoot).Items[mIndex]), AStore, mList) and (IndexOf(Result, mList.Name) < 0)
      then
      begin
        Result := Result + [mList];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>AText als JSON-Zeichenkette mit Anführungszeichen.</summary>
function Quoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    // Ohne Argument schreibt ToJSON Umlaute als \u-Folge; lesbar mit [].
    Result := mValue.ToJSON([]);
  finally
    mValue.Free;
  end;
end;

function RuleJson(const ARule: TAtlasTestListRule): string;
begin
  case ARule.Kind of
    TAtlasTestListRuleKind.Category:
      Result := '{"category": ' + Quoted(ARule.Value);
    TAtlasTestListRuleKind.Pattern:
      Result := '{"unit": ' + Quoted(ARule.Value);
  else
    Result := '{"state": ' + Quoted(cStateNames[ARule.State]);
  end;
  if ARule.Exclude then
  begin
    Result := Result + cExcludeJson;
  end;
  Result := Result + '}';
end;

/// <summary>Einträge AItems als JSON-Array, je Eintrag eine Zeile mit Einrückung AIndent.</summary>
function ArrayJson(const AItems: TArray<string>; const AIndent: string): string;
var
  mIndex: Integer;
begin
  if Length(AItems) = 0 then
  begin
    Exit('[]');
  end;
  Result := '[';
  for mIndex := 0 to High(AItems) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + cNewLine + AIndent + cIndent + AItems[mIndex];
  end;
  Result := Result + cNewLine + AIndent + ']';
end;

function ListJson(const AList: TAtlasTestList; const AIndent: string): string;
var
  mParts: TArray<string>;
  mRule: TAtlasTestListRule;
  mName: string;
begin
  Result := '{"name": ' + Quoted(AList.Name) + ', ';
  mParts := nil;
  if AList.IsDynamic then
  begin
    for mRule in AList.Rules do
    begin
      mParts := mParts + [RuleJson(mRule)];
    end;
    Result := Result + '"rules": ' + ArrayJson(mParts, AIndent + cIndent + cIndent) + '}';
    Exit;
  end;
  for mName in AList.Tests do
  begin
    mParts := mParts + [Quoted(mName)];
  end;
  Result := Result + '"tests": ' + ArrayJson(mParts, AIndent + cIndent + cIndent) + '}';
end;

class function TAtlasTestListModel.ToJson(const ALists: TAtlasTestLists; const AIndent: string): string;
var
  mParts: TArray<string>;
  mList: TAtlasTestList;
begin
  mParts := nil;
  for mList in ALists do
  begin
    mParts := mParts + [ListJson(mList, AIndent)];
  end;
  Result := ArrayJson(mParts, AIndent);
end;

class function TAtlasTestListModel.OfStore(const ALists: TAtlasTestLists;
  AStore: TAtlasTestListStore): TAtlasTestLists;
var
  mList: TAtlasTestList;
begin
  Result := nil;
  for mList in ALists do
  begin
    if mList.Store = AStore then
    begin
      Result := Result + [mList];
    end;
  end;
end;

class function TAtlasTestListModel.IndexOf(const ALists: TAtlasTestLists; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALists) do
  begin
    if SameText(ALists[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTestListModel.UniqueName(const ALists: TAtlasTestLists; const ABase: string): string;
var
  mNumber: Integer;
begin
  Result := Trim(ABase);
  mNumber := 1;
  while IndexOf(ALists, Result) >= 0 do
  begin
    Inc(mNumber);
    Result := Format('%s (%d)', [Trim(ABase), mNumber]);
  end;
end;

class function TAtlasTestListModel.AddTests(var AList: TAtlasTestList; const ANames: TArray<string>): Integer;
var
  mName, mKnown: string;
  mFound: Boolean;
begin
  Result := 0;
  for mName in ANames do
  begin
    mFound := Trim(mName) = '';
    for mKnown in AList.Tests do
    begin
      mFound := mFound or NameCovers(mKnown, Trim(mName));
    end;
    if not mFound then
    begin
      AList.Tests := AList.Tests + [Trim(mName)];
      Inc(Result);
    end;
  end;
end;

class function TAtlasTestListModel.RemoveTests(var AList: TAtlasTestList; const ANames: TArray<string>): Integer;
var
  mKept: TArray<string>;
  mKnown, mName: string;
  mDrop: Boolean;
begin
  mKept := nil;
  for mKnown in AList.Tests do
  begin
    mDrop := False;
    for mName in ANames do
    begin
      // Entfernt wird ein Name, der den gewählten Knoten oder etwas darunter nennt.
      mDrop := mDrop or NameCovers(Trim(mName), mKnown);
    end;
    if not mDrop then
    begin
      mKept := mKept + [mKnown];
    end;
  end;
  Result := Length(AList.Tests) - Length(mKept);
  AList.Tests := mKept;
end;

end.
