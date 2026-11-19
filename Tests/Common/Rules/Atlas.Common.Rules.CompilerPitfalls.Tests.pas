unit Atlas.Common.Rules.CompilerPitfalls.Tests;

// Tests für den Fallenkatalog der Compilermeldungen (#2621): Jede Falle mit Merkmal hat ein Beispiel, an dem sie
// als erste passt; ohne Merkmal bleibt sie eine weitere Ursache.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerPitfallsTests = class
  public
    [Test]
    procedure EachPitfallComesFirstAtItsExample;
    [Test]
    procedure WithoutMarkOnlyOtherCauses;
    [Test]
    procedure WithoutSourceNothingIsMarked;
    [Test]
    procedure EveryPitfallIsComplete;
    [Test]
    procedure RulesExistInTheCatalog;
    [Test]
    procedure KnowsOnlyCodesWithPitfalls;
    [Test]
    procedure MarksFollowUpErrors;
    [Test]
    procedure NamesIgnoreNamespaces;
    [Test]
    procedure PatternsRespectWordBoundaries;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.MessageCatalog,
  Atlas.Common.Rules.CompilerPitfalls;

type
  TPitfallExample = record
    Code: string;
    Text: string;
    Source: string;
    Line: Integer;
  end;

const
  cLongLine = '<long>';
  cNoExample = '';

  cExamples: array[TCompilerPitfall] of TPitfallExample = (
    (Code: 'E2010'; Text: 'Inkompatible Typen: ''TAtlasNameFilter'' und ''TAtlasNamePredicate''';
     Source: 'type'#10'  TAtlasNameFilter = reference to function(const AName: string): Boolean;'#10 +
       '  TAtlasNamePredicate = reference to function(const AName: string): Boolean;'#10'begin'#10 +
       '  FFilter := FPredicate;'; Line: 4),
    (Code: 'E2010'; Text: 'Incompatible types: ''TProc<System.string>'' and ''procedure, untyped pointer or ' +
       'untyped parameter'''; Source: '  Run(Show);'; Line: 0),
    (Code: 'E2010'; Text: cNoExample),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''reference'''; Source: '  FFilter: reference to function: Boolean;';
     Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''Enter'''; Source: '  TMonitor.Enter(FLock);'; Line: 0),
    (Code: 'E2015'; Text: 'Operator not applicable to this operand type'; Source: '  if FRange <> nil then';
     Line: 0),
    (Code: 'E2014'; Text: 'Statement expected, but expression of type ''TStep'' found'; Source: '      Continue;';
     Line: 0),
    (Code: 'E2010'; Text: 'Incompatible types: ''TArray<System.string>'' and ''Set''';
     Source: '    Exit([''a'', ''b'']);'; Line: 0),
    (Code: 'E2035'; Text: 'Not enough actual parameters'; Source: '  Exit(AFilter);'; Line: 0),
    (Code: 'E2250'; Text: 'There is no overloaded version of ''Add'' that can be called with these arguments';
     Source: '  mList.Add(procedure(AItem: string) begin end);'; Line: 0),
    (Code: 'E2532'; Text: 'Could not infer generic type argument from different argument types for method ' +
       '''AreEqual'''; Source: '  Assert.AreEqual(2, Length(mItems));'; Line: 0),
    (Code: 'E2250'; Text: 'There is no overloaded version of ''Rect'' that can be called with these arguments';
     Source: '  mBounds := Rect(mTopLeft, mBottomRight);'; Line: 0),
    (Code: 'E2035'; Text: 'Not enough actual parameters'; Source: '  mWidth := Scaled(10);'; Line: 0),
    (Code: 'E2362'; Text: 'Cannot access protected symbol ''TControl.Font'''; Source: '  AControl.Font.Size := 9;';
     Line: 0),
    (Code: 'E2169'; Text: 'Field definition not allowed after methods or properties'; Source: '    FName: string;';
     Line: 0),
    (Code: 'F2069'; Text: 'Line too long (more than 1023 characters)'; Source: cLongLine; Line: 0),
    (Code: 'H2443'; Text: 'Inline function ''TJSONArray.Count'' has not been expanded because unit ' +
       '''System.Generics.Collections'' is not specified in USES list'; Source: '  mCount := mItems.Count;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''OpenThread'''; Source: '  mThread := OpenThread(0, False, 1);';
     Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''GetTickCount64'''; Source: '  mStart := GetTickCount64;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''TContainedAction'''; Source: '  mAction: TContainedAction;';
     Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''IOTAPaletteServices''';
     Source: '  mPalette: IOTAPaletteServices;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''GetComponentEditor''';
     Source: '  mEditor := GetComponentEditor(AComponent, nil);'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''TScrollBox'''; Source: '  mBox: TScrollBox;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''TProc'''; Source: '  mDone: TProc;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''Create'''; Source: '  mBitmap := TBitmap.Create;'; Line: 0),
    (Code: 'E2018'; Text: 'Record, object or class type required'; Source: '  if Caption.StartsWith(''a'') then';
     Line: 0),
    (Code: 'E2211'; Text: 'Declaration of ''GetGlyph'' differs from declaration in interface ''INTAWizard''';
     Source: '    function GetGlyph: Cardinal;'; Line: 0),
    (Code: 'W1000'; Text: 'Symbol ''TScrollStyle'' is deprecated'; Source: '  mStyle: TScrollStyle;'; Line: 0),
    (Code: 'W1010'; Text: 'Method ''DoClose'' hides virtual method of base type ''TCustomForm''';
     Source: '    procedure DoClose;'; Line: 0),
    (Code: 'E2003'; Text: 'Undeclared identifier: ''cGap''';
     Source: 'type'#10'  TBasis = class'#10'  public const'#10'    cGap = 4;'#10'  end;'#10 +
       '  TAbleitung = class(TBasis)'#10'  public const'#10'    cRows = 2 * cGap;'#10'  end;'; Line: 7));

function SourceOf(const AExample: TPitfallExample): string;
begin
  Result := AExample.Source;
  if Result = cLongLine then
  begin
    Result := '  cText = ''' + StringOfChar('a', 1100) + ''';';
  end;
end;

function MatchOf(const AExample: TPitfallExample): TArray<TPitfallMatch>;
begin
  Result := TCompilerPitfalls.Match(TPitfallMessage.Create(AExample.Code, AExample.Text, AExample.Line),
    SourceOf(AExample));
end;

function Id(APitfall: TCompilerPitfall): string;
begin
  Result := TCompilerPitfalls.Info(APitfall, TTextLanguage.English).Id;
end;

{ TCompilerPitfallsTests }

procedure TCompilerPitfallsTests.EachPitfallComesFirstAtItsExample;
var
  mPitfall: TCompilerPitfall;
  mMatches: TArray<TPitfallMatch>;
begin
  for mPitfall := Low(TCompilerPitfall) to High(TCompilerPitfall) do
  begin
    if cExamples[mPitfall].Text = cNoExample then
    begin
      Continue;
    end;
    mMatches := MatchOf(cExamples[mPitfall]);
    Assert.IsTrue(Length(mMatches) > 0, Id(mPitfall));
    Assert.AreEqual(Id(mPitfall), Id(mMatches[0].Pitfall), Id(mPitfall));
    Assert.IsTrue(mMatches[0].Marked, Id(mPitfall));
    Assert.AreNotEqual('', mMatches[0].Evidence, Id(mPitfall));
  end;
end;

procedure TCompilerPitfallsTests.WithoutMarkOnlyOtherCauses;
var
  mMatch: TPitfallMatch;
  mMatches: TArray<TPitfallMatch>;
begin
  // E2010 ohne Merkmal in der Zeile: alle Fallen der Nummer, keine markiert.
  mMatches := TCompilerPitfalls.Match(TPitfallMessage.Create('E2010', 'Incompatible types: ''Integer'' and ''string''',
    0), '  mCount := mText;');
  Assert.IsTrue(Length(mMatches) >= 3);
  for mMatch in mMatches do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
    Assert.AreEqual('', mMatch.Evidence);
  end;
  // Ohne Falle zur Nummer: nichts.
  Assert.AreEqual(0, Integer(Length(TCompilerPitfalls.Match(TPitfallMessage.Create('E2029', ''';'' expected', 0),
    '  A := 1'))));
end;

procedure TCompilerPitfallsTests.WithoutSourceNothingIsMarked;
var
  mMatch: TPitfallMatch;
begin
  for mMatch in TCompilerPitfalls.Match(TPitfallMessage.Create('E2003', 'Undeclared identifier: ''Enter''', -1),
    '  TMonitor.Enter(FLock);') do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
  end;
  for mMatch in TCompilerPitfalls.Match(TPitfallMessage.Create('E2169', '', 0), '') do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
  end;
end;

procedure TCompilerPitfallsTests.EveryPitfallIsComplete;
var
  mPitfall: TCompilerPitfall;
  mLanguage: TTextLanguage;
  mInfo: TCompilerPitfallInfo;
  mCode: string;
  mIds: string;
begin
  mIds := ' ';
  for mPitfall := Low(TCompilerPitfall) to High(TCompilerPitfall) do
  begin
    for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
    begin
      mInfo := TCompilerPitfalls.Info(mPitfall, mLanguage);
      Assert.AreNotEqual('', mInfo.Title, mInfo.Id);
      Assert.AreNotEqual('', mInfo.Reason, mInfo.Id);
      Assert.AreNotEqual('', mInfo.Fix, mInfo.Id);
      Assert.AreEqual(mInfo.FixKind = TPitfallFix.AddUses, mInfo.UsesUnit <> '', mInfo.Id);
    end;
    Assert.AreEqual(0, Pos(' ' + mInfo.Id + ' ', mIds), 'doppelt: ' + mInfo.Id);
    mIds := mIds + mInfo.Id + ' ';
    Assert.IsTrue(Length(TCompilerPitfalls.Codes(mPitfall)) > 0, mInfo.Id);
    for mCode in TCompilerPitfalls.Codes(mPitfall) do
    begin
      Assert.AreEqual(mCode, TCompilerMessageCatalog.CodeOf(mCode), mInfo.Id);
    end;
  end;
end;

procedure TCompilerPitfallsTests.RulesExistInTheCatalog;
var
  mPitfall: TCompilerPitfall;
  mInfo: TCompilerPitfallInfo;
  mEntry: TRuleCatalogEntry;
begin
  for mPitfall := Low(TCompilerPitfall) to High(TCompilerPitfall) do
  begin
    mInfo := TCompilerPitfalls.Info(mPitfall, TTextLanguage.German);
    if mInfo.Rule <> '' then
    begin
      Assert.IsTrue(TRuleCatalog.Shared.TryFind(mInfo.Rule, mEntry), mInfo.Id + ': ' + mInfo.Rule);
    end;
  end;
end;

procedure TCompilerPitfallsTests.KnowsOnlyCodesWithPitfalls;
begin
  Assert.IsTrue(TCompilerPitfalls.Knows('E2010'));
  Assert.IsTrue(TCompilerPitfalls.Knows(' w1010 '));
  Assert.IsFalse(TCompilerPitfalls.Knows('E2029'));
  Assert.IsFalse(TCompilerPitfalls.Knows(''));
end;

procedure TCompilerPitfallsTests.MarksFollowUpErrors;
var
  mCause: string;
begin
  Assert.IsTrue(TCompilerPitfalls.IsFollowUp('E2250', ['W1036', 'e2010'], mCause));
  Assert.AreEqual('E2010', mCause);
  Assert.IsTrue(TCompilerPitfalls.IsFollowUp('F2063', ['E2029'], mCause));
  Assert.AreEqual('E2029', mCause);
  Assert.IsFalse(TCompilerPitfalls.IsFollowUp('E2250', ['E2029'], mCause));
  Assert.AreEqual('', mCause);
  Assert.IsFalse(TCompilerPitfalls.IsFollowUp('F2063', ['W1036', 'H2443'], mCause));
  Assert.IsFalse(TCompilerPitfalls.IsFollowUp('E2003', ['E2003'], mCause));
end;

procedure TCompilerPitfallsTests.NamesIgnoreNamespaces;
var
  mMatches: TArray<TPitfallMatch>;
begin
  mMatches := TCompilerPitfalls.Match(TPitfallMessage.Create('E2010',
    'Inkompatible Typen: ''System.SysUtils.TProc<System.string>'' und ''Prozedur''', 0), '  Run(Show);');
  Assert.AreEqual('const-parameter-to-generic', Id(mMatches[0].Pitfall));
  Assert.AreEqual('System.SysUtils.TProc<System.string>', mMatches[0].Evidence);
end;

procedure TCompilerPitfallsTests.PatternsRespectWordBoundaries;
var
  mMatch: TPitfallMatch;
begin
  // BoundsRect( ist kein Rect(, ExitCode kein Exit, TMonitor mit Unit-Namen ist schon richtig.
  for mMatch in TCompilerPitfalls.Match(TPitfallMessage.Create('E2250', '', 0), '  mValue := BoundsRect(mA);') do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
  end;
  for mMatch in TCompilerPitfalls.Match(TPitfallMessage.Create('E2014', '', 0), '  ExitCode;') do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
  end;
  for mMatch in TCompilerPitfalls.Match(TPitfallMessage.Create('E2003', 'Undeclared identifier: ''Enter''', 0),
    '  System' + '.TMonitor.Enter(FLock);') do
  begin
    Assert.IsFalse(mMatch.Marked, Id(mMatch.Pitfall));
  end;
end;

end.
