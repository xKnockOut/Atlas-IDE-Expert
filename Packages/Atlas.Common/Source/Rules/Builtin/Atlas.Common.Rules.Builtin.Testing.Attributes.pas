unit Atlas.Common.Rules.Builtin.Testing.Attributes;

// Regeln aus Atlas.Common.Rules.Builtin.Testing (#154); angemeldet werden sie dort. Nur in Testunits, Attribute
// über ihren Namen erkannt (mit oder ohne Unit und Endung Attribute), damit sie auch ohne DUnitX im Suchpfad gehen:
//   dunitx-ignore-without-reason  [Ignore] ohne Begründung (auch [Ignore('')]): Im Testbericht steht nicht, warum
//                                 der Test nicht läuft, und niemand weiß später, ob er wieder an darf.
//   dunitx-category-empty         [Category] ohne Namen ([Category('')], [Category(' , ')]): Der Test landet in
//                                 keiner Kategorie, ein Filter --include findet ihn nie.
//   dunitx-fixture-without-test   [TestFixture]-Klasse ohne [Test]-, [TestCase]- oder published-Methode (DUnitX
//                                 nimmt published-Methoden als Tests): Sie läuft leer. Still bei einem Vorfahren
//                                 außer TObject, der nicht in der Datei steht oder selbst Tests hat (geerbte Tests).
//   dunitx-duplicate-attribute    Dasselbe Attribut zweimal am selben Element: [Test] [Test], [Ignore] zweimal …;
//                                 TestCase, NamedTestCase und Category nur bei gleichen Argumenten. Korrektur
//                                 (sicher): das zweite entfernen.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXIgnoreWithoutReasonRuleId = 'dunitx-ignore-without-reason';
  cDUnitXCategoryEmptyRuleId = 'dunitx-category-empty';
  cDUnitXFixtureWithoutTestRuleId = 'dunitx-fixture-without-test';
  cDUnitXDuplicateAttributeRuleId = 'dunitx-duplicate-attribute';

type
  TDUnitXIgnoreWithoutReasonRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDUnitXCategoryEmptyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDUnitXFixtureWithoutTestRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDUnitXDuplicateAttributeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Rules.Builtin.Testing.TestCases,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TAttributesText = (TitleIgnore, TitleCategory, TitleFixture, TitleDuplicate, Ignore, Category, Fixture, Duplicate,
    RemoveDuplicate);

  /// <summary>Welche der vier Regeln prüft.</summary>
  TAttributeRule = (IgnoreReason, CategoryName, FixtureTest, Duplicate);

const
  cTexts: array[TAttributesText] of TAtlasText = (
    (De: '[Ignore] ohne Begründung'; En: '[Ignore] without a reason'),
    (De: '[Category] ohne Namen'; En: '[Category] without a name'),
    (De: '[TestFixture] ohne Test'; En: '[TestFixture] without a test'),
    (De: 'Attribut doppelt'; En: 'Duplicate attribute'),
    (De: '[Ignore] ohne Begründung: Der Testbericht sagt nicht, warum %s nicht läuft und wann der Test wieder an ' +
      'darf.';
     En: '[Ignore] without a reason: the test report does not say why %s does not run and when it may run again.'),
    (De: '[Category] ohne Namen: %s landet in keiner Kategorie, ein Filter findet den Test nie.';
     En: '[Category] without a name: %s ends up in no category, a filter never finds the test.'),
    (De: '%s hat [TestFixture], aber keine [Test]-, [TestCase]- oder published-Methode: Die Klasse läuft leer.';
     En: '%s has [TestFixture] but no [Test], [TestCase] or published method: the class runs empty.'),
    (De: '[%s] steht zweimal an %s.'; En: '[%s] appears twice on %s.'),
    (De: 'Zweites [%s] entfernen'; En: 'Remove the second [%s]'));

{$SCOPEDENUMS OFF}

const
  cTestAttributes: array[0..3] of string = ('Test', 'TestCase', 'NamedTestCase', 'RepeatTest');
  // Attribute, die DUnitX mehrfach auswertet: doppelt nur mit gleichen Argumenten.
  cRepeatable: array[0..2] of string = ('TestCase', 'NamedTestCase', 'Category');
  cKnownAttributes: array[0..16] of string = ('Test', 'TestCase', 'NamedTestCase', 'RepeatTest', 'TestFixture',
    'Setup', 'TearDown', 'SetupFixture', 'TearDownFixture', 'Ignore', 'Category', 'WillRaise', 'WillRaiseDescendant',
    'MaxTime', 'IgnoreMemoryLeaks', 'IgnoreFixture', 'TestInOwnThread');

type
  /// <summary>Eine Prüfung einer Datei für eine der Regeln.</summary>
  TAttributesCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRule: TAttributeRule;
    FClasses: TArray<TDUnitXClass>;
    function Source(ANode: TSyntaxNode): string;
    function Range(ANode: TSyntaxNode): TTextRange;
    function ElementName(const AClass: TDUnitXClass; ANode: TSyntaxNode): string;
    function TextArgument(AItem: TSyntaxNode; out AValue: string): Boolean;
    function ArgumentsText(AItem: TSyntaxNode): string;
    procedure CheckIgnore(const AItems: TArray<TSyntaxNode>; const AElement: string);
    procedure CheckCategory(const AItems: TArray<TSyntaxNode>; const AElement: string);
    function RemoveEdit(AItem: TSyntaxNode): TTextEdit;
    procedure CheckDuplicates(const AItems: TArray<TSyntaxNode>; const AElement: string);
    function ClassIndex(const AName: string): Integer;
    function HasTests(AIndex, ADepth: Integer): Boolean;
    procedure CheckFixture(AIndex: Integer);
    procedure CheckItems(const AItems: TArray<TSyntaxNode>; const AElement: string);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; ARule: TAttributeRule);
    procedure Run;
  end;

procedure RunCheck(const AContext: TRuleContext; const AReport: IRuleReport; ARule: TAttributeRule);
var
  mCheck: TAttributesCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, '[') or
    not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mCheck := TAttributesCheck.Create(AContext, AReport, ARule);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TAttributesCheck }

constructor TAttributesCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport; ARule: TAttributeRule);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FRule := ARule;
  FClasses := TDUnitXClasses.Collect(AContext.Tree.Root);
end;

function TAttributesCheck.Source(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TAttributesCheck.Range(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TAttributesCheck.ElementName(const AClass: TDUnitXClass; ANode: TSyntaxNode): string;
begin
  Result := AClass.Name;
  if ANode <> AClass.Decl then
  begin
    Result := AClass.Name + '.' + ANode.Name;
  end;
end;

function TAttributesCheck.TextArgument(AItem: TSyntaxNode; out AValue: string): Boolean;
var
  mArguments: TArray<TSyntaxNode>;
begin
  // True, wenn das erste Argument ein String-Literal ist (AValue dessen Wert) oder es keins gibt (AValue '').
  AValue := '';
  mArguments := TDUnitXClasses.Arguments(AItem);
  if mArguments = nil then
  begin
    Exit(True);
  end;
  Result := (mArguments[0].Kind = TSyntaxKind.Literal) and TDUnitXTestCases.Decode(mArguments[0].Name, AValue);
end;

function TAttributesCheck.ArgumentsText(AItem: TSyntaxNode): string;
var
  mArgument: TSyntaxNode;
begin
  Result := '';
  for mArgument in TDUnitXClasses.Arguments(AItem) do
  begin
    Result := Result + '|' + StringReplace(Source(mArgument), ' ', '', [rfReplaceAll]);
  end;
end;

procedure TAttributesCheck.CheckIgnore(const AItems: TArray<TSyntaxNode>; const AElement: string);
var
  mItem: TSyntaxNode;
  mReason: string;
begin
  for mItem in AItems do
  begin
    if SameText(TDUnitXClasses.ItemName(mItem), 'Ignore') and TextArgument(mItem, mReason) and
      (Trim(mReason) = '') then
    begin
      FReport.Add(Range(mItem), cTexts[TAttributesText.Ignore].Fmt([AElement]), TRuleConfidence.High);
    end;
  end;
end;

procedure TAttributesCheck.CheckCategory(const AItems: TArray<TSyntaxNode>; const AElement: string);
var
  mItem: TSyntaxNode;
  mNames: string;
begin
  for mItem in AItems do
  begin
    if SameText(TDUnitXClasses.ItemName(mItem), 'Category') and TextArgument(mItem, mNames) and
      (Trim(StringReplace(mNames, ',', '', [rfReplaceAll])) = '') then
    begin
      FReport.Add(Range(mItem), cTexts[TAttributesText.Category].Fmt([AElement]), TRuleConfidence.High);
    end;
  end;
end;

function TAttributesCheck.RemoveEdit(AItem: TSyntaxNode): TTextEdit;
var
  mAttribute: TSyntaxNode;
  mIndex: Integer;
  mStart, mEnd: TTextPosition;
begin
  mAttribute := AItem.Parent;
  if mAttribute.ChildCount = 1 then
  begin
    // [Test] allein: die Klammer samt folgendem Leerraum bis zum nächsten Zeichen derselben Zeile.
    mStart := mAttribute.StartPos;
    mEnd := mAttribute.EndPos;
    mIndex := mAttribute.EndOffset + 1;
    while (mIndex <= Length(FContext.Text)) and (FContext.Text[mIndex] = ' ') do
    begin
      Inc(mIndex);
      mEnd := TTextPosition.Create(mEnd.Line, mEnd.Character + 1);
    end;
    if (mIndex > Length(FContext.Text)) or CharInSet(FContext.Text[mIndex], [#13, #10]) then
    begin
      // Allein auf der Zeile: die ganze Zeile.
      mStart := TTextPosition.Create(mStart.Line, 0);
      mEnd := TTextPosition.Create(mEnd.Line + 1, 0);
    end;
    Exit(TTextEdit.Create(TTextRange.Create(mStart, mEnd), ''));
  end;
  // In [A, B]: das Komma davor mitnehmen (das zweite Vorkommen ist nie das erste Element).
  mIndex := 0;
  while mAttribute[mIndex] <> AItem do
  begin
    Inc(mIndex);
  end;
  Result := TTextEdit.Create(TTextRange.Create(mAttribute[mIndex - 1].EndPos, AItem.EndPos), '');
end;

procedure TAttributesCheck.CheckDuplicates(const AItems: TArray<TSyntaxNode>; const AElement: string);
var
  mFirst, mSecond: Integer;
  mName: string;
begin
  for mSecond := 1 to High(AItems) do
  begin
    mName := TDUnitXClasses.ItemName(AItems[mSecond]);
    if not MatchText(mName, cKnownAttributes) then
    begin
      Continue;
    end;
    for mFirst := 0 to mSecond - 1 do
    begin
      if SameText(TDUnitXClasses.ItemName(AItems[mFirst]), mName) and (not MatchText(mName, cRepeatable) or
        (ArgumentsText(AItems[mFirst]) = ArgumentsText(AItems[mSecond]))) then
      begin
        FReport.Add(Range(AItems[mSecond]), cTexts[TAttributesText.Duplicate].Fmt([mName, AElement]),
          TRuleConfidence.High, [TRuleFix.Create(cTexts[TAttributesText.RemoveDuplicate].Fmt([mName]),
          [RemoveEdit(AItems[mSecond])], True)]);
        Break;
      end;
    end;
  end;
end;

function TAttributesCheck.ClassIndex(const AName: string): Integer;
begin
  for Result := 0 to High(FClasses) do
  begin
    if SameText(FClasses[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAttributesCheck.HasTests(AIndex, ADepth: Integer): Boolean;
var
  mBody: TSyntaxNode;
  mIndex, mAncestor: Integer;
  mPublished: Boolean;
begin
  if FClasses[AIndex].HasMemberWith(cTestAttributes) then
  begin
    Exit(True);
  end;
  // DUnitX nimmt published-Methoden ohne Attribut als Tests.
  mBody := FClasses[AIndex].Body;
  mPublished := False;
  for mIndex := 0 to mBody.ChildCount - 1 do
  begin
    if mBody[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      mPublished := SameText(mBody[mIndex].Name, 'published');
    end
    else if mPublished and (mBody[mIndex].Kind = TSyntaxKind.RoutineHeader) then
    begin
      Exit(True);
    end;
  end;
  // Vorfahr: TObject erbt nichts; außerhalb der Datei unbekannt (zählt als mit Tests).
  if (FClasses[AIndex].Ancestor = '') or SameText(FClasses[AIndex].Ancestor, 'TObject') then
  begin
    Exit(False);
  end;
  mAncestor := ClassIndex(FClasses[AIndex].Ancestor);
  Result := (mAncestor < 0) or (ADepth > 20) or HasTests(mAncestor, ADepth + 1);
end;

procedure TAttributesCheck.CheckFixture(AIndex: Integer);
begin
  if FClasses[AIndex].HasAttribute('TestFixture') and not HasTests(AIndex, 0) then
  begin
    FReport.Add(TTextRange.Create(FClasses[AIndex].Decl.StartPos, TTextPosition.Create(
      FClasses[AIndex].Decl.StartPos.Line, FClasses[AIndex].Decl.StartPos.Character + Length(FClasses[AIndex].Name))),
      cTexts[TAttributesText.Fixture].Fmt([FClasses[AIndex].Name]), TRuleConfidence.Medium);
  end;
end;

procedure TAttributesCheck.CheckItems(const AItems: TArray<TSyntaxNode>; const AElement: string);
begin
  case FRule of
    TAttributeRule.IgnoreReason:
      CheckIgnore(AItems, AElement);
    TAttributeRule.CategoryName:
      CheckCategory(AItems, AElement);
    TAttributeRule.Duplicate:
      CheckDuplicates(AItems, AElement);
    TAttributeRule.FixtureTest:
      // Klassenweit in CheckFixture, nicht je Element.
      ;
  end;
end;

procedure TAttributesCheck.Run;
var
  mIndex: Integer;
  mMember: TDUnitXMember;
begin
  for mIndex := 0 to High(FClasses) do
  begin
    if FRule = TAttributeRule.FixtureTest then
    begin
      CheckFixture(mIndex);
      Continue;
    end;
    CheckItems(FClasses[mIndex].Attributes, FClasses[mIndex].Name);
    for mMember in FClasses[mIndex].Members do
    begin
      CheckItems(mMember.Attributes, ElementName(FClasses[mIndex], mMember.Node));
    end;
  end;
end;

{ TDUnitXIgnoreWithoutReasonRule }

function TDUnitXIgnoreWithoutReasonRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXIgnoreWithoutReasonRuleId, TRuleSeverity.Hint,
    cTexts[TAttributesText.TitleIgnore].Text);
end;

procedure TDUnitXIgnoreWithoutReasonRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, TAttributeRule.IgnoreReason);
end;

{ TDUnitXCategoryEmptyRule }

function TDUnitXCategoryEmptyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXCategoryEmptyRuleId, TRuleSeverity.Warning,
    cTexts[TAttributesText.TitleCategory].Text);
end;

procedure TDUnitXCategoryEmptyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, TAttributeRule.CategoryName);
end;

{ TDUnitXFixtureWithoutTestRule }

function TDUnitXFixtureWithoutTestRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXFixtureWithoutTestRuleId, TRuleSeverity.Warning,
    cTexts[TAttributesText.TitleFixture].Text);
end;

procedure TDUnitXFixtureWithoutTestRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, TAttributeRule.FixtureTest);
end;

{ TDUnitXDuplicateAttributeRule }

function TDUnitXDuplicateAttributeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXDuplicateAttributeRuleId, TRuleSeverity.Hint,
    cTexts[TAttributesText.TitleDuplicate].Text);
end;

procedure TDUnitXDuplicateAttributeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  RunCheck(AContext, AReport, TAttributeRule.Duplicate);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.Attributes', cTexts);

end.
