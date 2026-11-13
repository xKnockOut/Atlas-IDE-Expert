unit Atlas.Common.Configuration.Internals.TestListOptions;

// Abschnitt testLists von atlas.json (#2167): Testlisten des Fensters
// „Atlas-Tests“ im Plugin, für das Team unter Versionsverwaltung. Das Plugin
// liest den Abschnitt selbst (Atlas.Core.Tests.Lists); der Server prüft nur
// und meldet:
// - eine Liste ist ein Objekt mit "name" (Text, nicht leer, eindeutig ohne
//   Groß-/Kleinschreibung) und "rules" (dynamisch) oder "tests" (fest),
// - eine Regel ist ein Objekt mit genau einem von "category", "unit"
//   (Muster) oder "state" ("failed", "notRun", "stale") und optional
//   "exclude" (true/false),
// - "tests" ist eine Liste von Texten.

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function TestListSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTestListOptionsText = (ListsMustBeAList, AListIsAnObject, ListWithoutName, TheListAlreadyExists, RulesMustBeAList,
    ARuleIsAnObject, ARuleNeedsOneKind, AllowedAreFailedNotRunStale, TestsMustBeAList);

const
  cTexts: array[TTestListOptionsText] of TAtlasText = (
    (De: '"testLists" muss eine Liste von Testlisten sein'; En: '"testLists" must be a list of test lists'),
    (De: 'Eine Testliste ist ein Objekt mit "name" und "rules" oder "tests"';
     En: 'A test list is an object with "name" and "rules" or "tests"'),
    (De: 'Testliste ohne "name"'; En: 'Test list without "name"'),
    (De: 'Die Testliste "%s" gibt es schon'; En: 'The test list "%s" already exists'),
    (De: '"rules" muss eine Liste von Regeln sein'; En: '"rules" must be a list of rules'),
    (De: 'Eine Regel ist ein Objekt mit "category", "unit" oder "state"';
     En: 'A rule is an object with "category", "unit" or "state"'),
    (De: 'Eine Regel hat genau eines von "category", "unit" und "state"';
     En: 'A rule has exactly one of "category", "unit" and "state"'),
    (De: 'Erlaubt sind "failed", "notRun" und "stale"'; En: 'Allowed are "failed", "notRun" and "stale"'),
    (De: '"tests" muss eine Liste von Namen sein (Unit, Unit.Fixture, Unit.Fixture.Methode)';
     En: '"tests" must be a list of names (unit, unit.fixture, unit.fixture.method)'));

/// <summary>Eine Regel prüfen.</summary>
procedure CheckRule(AReader: TConfigurationReader; ARule: TJsonNode);
var
  mIndex, mKinds, mChoice: Integer;
  mKey, mText: string;
  mExclude: Boolean;
begin
  if ARule.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ARule, cTexts[TTestListOptionsText.ARuleIsAnObject].Text);
    Exit;
  end;
  mKinds := 0;
  for mIndex := 0 to ARule.Count - 1 do
  begin
    mKey := ARule.Keys[mIndex];
    if (mKey = 'category') or (mKey = 'unit') then
    begin
      Inc(mKinds);
      AReader.ExpectString(ARule[mIndex], mKey, mText);
    end
    else if mKey = 'state' then
    begin
      Inc(mKinds);
      AReader.ExpectChoice(ARule[mIndex], mKey, ['failed', 'notRun', 'stale'],
        cTexts[TTestListOptionsText.AllowedAreFailedNotRunStale].Text, mChoice);
    end
    else if mKey = 'exclude' then
    begin
      mExclude := False;
      AReader.ExpectBoolean(ARule[mIndex], mKey, mExclude);
    end
    else
    begin
      AReader.ReportUnknown(ARule, mIndex, 'testLists.rules');
    end;
  end;
  if mKinds <> 1 then
  begin
    AReader.ReportNode(ARule, cTexts[TTestListOptionsText.ARuleNeedsOneKind].Text);
  end;
end;

procedure CheckRules(AReader: TConfigurationReader; ARules: TJsonNode);
var
  mIndex: Integer;
begin
  if ARules.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ARules, cTexts[TTestListOptionsText.RulesMustBeAList].Text);
    Exit;
  end;
  for mIndex := 0 to ARules.Count - 1 do
  begin
    CheckRule(AReader, ARules[mIndex]);
  end;
end;

/// <summary>Name der Liste AList prüfen und an ANames anhängen; '' ohne gültigen Namen.</summary>
function CheckName(AReader: TConfigurationReader; AList: TJsonNode; var ANames: TArray<string>): string;
var
  mIndex: Integer;
  mKnown: string;
begin
  Result := '';
  for mIndex := 0 to AList.Count - 1 do
  begin
    if (AList.Keys[mIndex] = 'name') and AReader.ExpectString(AList[mIndex], 'name', Result) then
    begin
      Result := Trim(Result);
      for mKnown in ANames do
      begin
        if SameText(mKnown, Result) then
        begin
          AReader.ReportNode(AList[mIndex], cTexts[TTestListOptionsText.TheListAlreadyExists].Fmt([Result]));
        end;
      end;
    end;
  end;
  if Result = '' then
  begin
    AReader.ReportNode(AList, cTexts[TTestListOptionsText.ListWithoutName].Text);
    Exit;
  end;
  ANames := ANames + [Result];
end;

/// <summary>Eine Liste prüfen; ANames sammelt die Namen.</summary>
procedure CheckList(AReader: TConfigurationReader; AList: TJsonNode; var ANames: TArray<string>);
var
  mIndex: Integer;
  mKey: string;
  mTests: TArray<string>;
begin
  if AList.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(AList, cTexts[TTestListOptionsText.AListIsAnObject].Text);
    Exit;
  end;
  CheckName(AReader, AList, ANames);
  for mIndex := 0 to AList.Count - 1 do
  begin
    mKey := AList.Keys[mIndex];
    if mKey = 'rules' then
    begin
      CheckRules(AReader, AList[mIndex]);
    end
    else if mKey = 'tests' then
    begin
      AReader.ExpectStrings(AList[mIndex], mKey, cTexts[TTestListOptionsText.TestsMustBeAList].Text, mTests);
    end
    else if mKey <> 'name' then
    begin
      AReader.ReportUnknown(AList, mIndex, 'testLists');
    end;
  end;
end;

procedure ReadTestLists(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mNames: TArray<string>;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, cTexts[TTestListOptionsText.ListsMustBeAList].Text);
    Exit;
  end;
  mNames := nil;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    CheckList(AReader, ANode[mIndex], mNames);
  end;
end;

procedure TakeTestLists(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
begin
  // Nur das Plugin liest die Listen, aus der atlas.json des Testprojekts; der Server übernimmt nichts.
end;

const
  cSections: array[0..0] of TConfigurationSection = (
    (Section: 'testLists'; Read: ReadTestLists; Take: TakeTestLists)
  );

function TestListSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.TestListOptions', cTexts);

end.
