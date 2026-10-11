unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tests;

// Tests für die typbasierten Regeln zu RTL-Mustern aus #153, Stufe 2, und
// für die deklarierten Typen, auf denen sie aufbauen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRtlTypePatternRulesTests = class
  public
    [Test]
    procedure DeclaredTypesByScope;
    [Test]
    procedure Int32MulOverflow;
    [Test]
    procedure SizeOfPointer;
    [Test]
    procedure CharToPChar;
    [Test]
    procedure FloatEquality;
    [Test]
    procedure ConstructorOnInstance;
    [Test]
    procedure FormatWithoutSettings;
    [Test]
    procedure LocaleSpecifiers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.DeclaredTypes,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Tests.RuleAssert;

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

procedure TRtlTypePatternRulesTests.DeclaredTypesByScope;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FCount: Int64;'#10 +
    '    procedure Run(A: Integer; const S: string);'#10'  end;'#10'var'#10'  Global: Double;'#10 +
    'implementation'#10'procedure TFoo.Run(A: Integer; const S: string);'#10'var'#10'  L: TArray<Byte>;'#10 +
    'begin'#10'  var C: Char := ''x'';'#10'  FCount := A;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Types: TDeclaredTypes;
  At: TTextPosition;
begin
  Tree := TPascalParser.Parse(Source);
  Types := TDeclaredTypes.Create(Tree, Source);
  try
    At := TTextPosition.Create(16, 4);
    Assert.AreEqual('Integer', Types.DeclaredType('A', At));
    Assert.AreEqual('string', Types.DeclaredType('s', At));
    Assert.AreEqual('TArray<Byte>', Types.DeclaredType('L', At));
    Assert.AreEqual('Char', Types.DeclaredType('C', At));
    Assert.AreEqual('Int64', Types.DeclaredType('FCount', At));
    Assert.AreEqual('Double', Types.DeclaredType('Global', At));
    Assert.AreEqual('', Types.DeclaredType('Unbekannt', At));
    // Vor der Inline-Deklaration ist C nicht bekannt.
    Assert.AreEqual('', Types.DeclaredType('C', TTextPosition.Create(14, 0)));
  finally
    Types.Free;
    Tree.Free;
  end;
end;

procedure TRtlTypePatternRulesTests.Int32MulOverflow;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10 +
    '  Width, Height: Integer;', '  Total := Width * Height;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Int64(Width)', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Reports(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10'  N: Cardinal;',
    '  Total := N * 1000;'));
  TRuleAssert.Silent(TInt32MulOverflowRule.Create, InRoutine('  Total: Int64;'#10'  Width: Int64;'#10 +
    '  Height: Integer;'#10'  Area: Integer;', '  Total := Width * Height;'#10'  Area := Height * Height;'#10 +
    '  Total := Int64(Height) * Height;'));
end;

procedure TRtlTypePatternRulesTests.SizeOfPointer;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSizeOfPointerRule.Create, InRoutine('  Buffer: TBytes;'#10'  P: PByte;',
    '  FillChar(Buffer[0], SizeOf(Buffer), 0);'#10'  Move(P^, Buffer[0], SizeOf(P));'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  TRuleAssert.Silent(TSizeOfPointerRule.Create, InRoutine('  R: TPoint;'#10'  A: array[0..9] of Byte;',
    '  FillChar(R, SizeOf(R), 0);'#10'  FillChar(A, SizeOf(A), 0);'#10'  FillChar(R, SizeOf(TPoint), 0);'));
end;

procedure TRtlTypePatternRulesTests.CharToPChar;
begin
  TRuleAssert.Reports(TCharToPCharRule.Create, InRoutine('  C: Char;', '  ShowMessage(PChar(C));'));
  TRuleAssert.Silent(TCharToPCharRule.Create, InRoutine('  S: string;'#10'  C: Char;',
    '  ShowMessage(PChar(S));'#10'  ShowMessage(PChar(string(C)));'));
end;

procedure TRtlTypePatternRulesTests.FloatEquality;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFloatEqualityRule.Create, InRoutine('  A, B: Double;',
    '  if A = B then Save;'#10'  if A <> 1.5 then Save;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('SameValue(A, B)', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('not SameValue(A, 1.5)', Findings[1].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TFloatEqualityRule.Create, InRoutine('  A: Double;'#10'  N, M: Integer;',
    '  if A = 0 then Save;'#10'  if N = M then Save;'#10'  if A <> 0.0 then Save;'));
end;

procedure TRtlTypePatternRulesTests.ConstructorOnInstance;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TConstructorOnInstanceRule.Create, InRoutine('  List: TStringList;',
    '  List.Create;'#10'  try'#10'  finally'#10'    List.Free;'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TStringList', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TConstructorOnInstanceRule.Create, InRoutine('  List: TStringList;'#10 +
    '  Kind: TComponentClass;'#10'  C: TComponent;', '  List := TStringList.Create;'#10 +
    '  C := Kind.Create(nil);'#10'  inherited Create;'));
end;

procedure TRtlTypePatternRulesTests.FormatWithoutSettings;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFormatWithoutSettingsRule.Create, InRoutine('  X: Double;',
    '  S := Format(''%.2f'', [X]);'#10'  S := FloatToStr(X);'#10'  D := StrToDate(S);'));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual(', FormatSettings', Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TFormatWithoutSettingsRule.Create, InRoutine('  N: Integer;',
    '  S := Format(''%d'', [N]);'#10'  S := Format(''%.2f'', [X], FS);'#10'  S := FloatToStr(X, FS);'#10 +
    '  S := Writer.Format(''%f'', [X]);'));
end;

procedure TRtlTypePatternRulesTests.LocaleSpecifiers;
begin
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('%.2f'));
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('Summe: %0:-10.2n'));
  Assert.IsTrue(TFormatWithoutSettingsRule.HasLocaleSpecifier('%m'));
  Assert.IsFalse(TFormatWithoutSettingsRule.HasLocaleSpecifier('%d %s %x'));
  Assert.IsFalse(TFormatWithoutSettingsRule.HasLocaleSpecifier('100%% fertig'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlTypePatternRulesTests);

end.
