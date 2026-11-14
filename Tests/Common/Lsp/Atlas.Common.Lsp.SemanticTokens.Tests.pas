unit Atlas.Common.Lsp.SemanticTokens.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.SemanticTokens;

type
  [TestFixture]
  TLspSemanticTokensTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const ATokens: TArray<TSemanticToken>; ALine: Integer): string;
    function Collect: TArray<TSemanticToken>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassifiesDeclarations;
    [Test]
    procedure ClassifiesUses;
    [Test]
    procedure RangeLimitsTokens;
    [Test]
    procedure EncodesRelativePositions;
    /// <summary>Modifier reassigned an jeder Stelle neu zugewiesener Namen und in der Legende (#712).</summary>
    [Test]
    procedure MarksReassignedNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  System.JSON,
  Atlas.Common.Semantics.Reassigned,
  Atlas.Common.Lsp.Reassigned;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'function Trim(const S: string): string;'#10 +
    'implementation'#10 +
    'function Trim(const S: string): string;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +                                              // 0
    'interface'#10 +                                                // 1
    'uses System.SysUtils;'#10 +                                    // 2
    'type'#10 +                                                     // 3
    '  TFarbe = (Rot, Gruen);'#10 +                                 // 4
    '  TFoo = class'#10 +                                           // 5
    '    FWert: Integer;'#10 +                                      // 6
    '    procedure Bar(Anzahl: Integer);'#10 +                      // 7
    '    property Wert: Integer read FWert;'#10 +                   // 8
    '    property OnKlick: TNotifyEvent read FKlick;'#10 +          // 9
    '  end;'#10 +                                                   // 10
    'const'#10 +                                                    // 11
    '  Grenze = 10;'#10 +                                           // 12
    'implementation'#10 +                                           // 13
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +                     // 14
    'var'#10 +                                                      // 15
    '  Text: string;'#10 +                                          // 16
    'begin'#10 +                                                    // 17
    '  Text := Trim(Text) + IntToStr(Anzahl + FWert + Grenze);'#10 + // 18
    '  Bar(Ord(Rot)); Self.Wert; System.SysUtils.Trim(Text);'#10 +  // 19
    'end;'#10 +                                                     // 20
    'end.';

{ TLspSemanticTokensTests }

procedure TLspSemanticTokensTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSysUtils, 'C:\RTL\System.SysUtils.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspSemanticTokensTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspSemanticTokensTests.Collect: TArray<TSemanticToken>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspSemanticTokens.Collect(FResolver, FIndex, mTree, cHauptFile, Default(TTextRange), False);
  finally
    mTree.Free;
  end;
end;

function TLspSemanticTokensTests.Describe(const ATokens: TArray<TSemanticToken>; ALine: Integer): string;
var
  mToken: TSemanticToken;
  mModifier: TSemanticTokenModifier;
begin
  Result := '';
  for mToken in ATokens do
  begin
    if mToken.Position.Line = ALine then
    begin
      Result := Result + IntToStr(mToken.Position.Character) + ' ' + TLspSemanticTokens.TypeName(mToken.TokenType);
      for mModifier in mToken.Modifiers do
      begin
        Result := Result + '+' + IntToStr(Ord(mModifier));
      end;
      Result := Result + '|';
    end;
  end;
end;

procedure TLspSemanticTokensTests.ClassifiesDeclarations;
var
  mTokens: TArray<TSemanticToken>;
begin
  mTokens := Collect;
  // +0 declaration, +1 readonly, +2 defaultLibrary
  Assert.AreEqual('2 enum+0|12 enumMember+0|17 enumMember+0|', Describe(mTokens, 4));
  Assert.AreEqual('4 field+0|', Describe(mTokens, 6));
  // read FWert löst seit #690 zum Feld auf.
  Assert.AreEqual('13 property+0|32 field|', Describe(mTokens, 8));
  Assert.AreEqual('13 event+0|', Describe(mTokens, 9));
  Assert.AreEqual('2 variable+0+1|', Describe(mTokens, 12));
end;

procedure TLspSemanticTokensTests.ClassifiesUses;
var
  mTokens: TArray<TSemanticToken>;
begin
  mTokens := Collect;
  // IntToStr ist unbekannt und bleibt ohne Einordnung.
  Assert.AreEqual('2 variable|10 function+2|15 variable|32 parameter|41 field|49 variable+1|', Describe(mTokens, 18));
  Assert.AreEqual('2 method|10 enumMember|17 variable+1|22 property|28 namespace+2|35 namespace+2|44 function+2|49 variable|',
    Describe(mTokens, 19));
end;

procedure TLspSemanticTokensTests.RangeLimitsTokens;
var
  mTree: TSyntaxTree;
  mTokens: TArray<TSemanticToken>;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mTokens := TLspSemanticTokens.Collect(FResolver, FIndex, mTree, cHauptFile,
      TTextRange.Create(TTextPosition.Create(12, 0), TTextPosition.Create(13, 0)), True);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mTokens)));
  Assert.AreEqual(12, mTokens[0].Position.Line);
end;

procedure TLspSemanticTokensTests.EncodesRelativePositions;
var
  mTokens: TArray<TSemanticToken>;
  mData: TArray<Integer>;
begin
  SetLength(mTokens, 3);
  mTokens[0].Position := TTextPosition.Create(1, 4);
  mTokens[0].Length := 3;
  mTokens[0].TokenType := TSemanticTokenType.Class_;
  mTokens[0].Modifiers := [TSemanticTokenModifier.Declaration];
  mTokens[1].Position := TTextPosition.Create(1, 10);
  mTokens[1].Length := 2;
  mTokens[1].TokenType := TSemanticTokenType.Variable;
  mTokens[1].Modifiers := [TSemanticTokenModifier.Readonly, TSemanticTokenModifier.DefaultLibrary];
  mTokens[2].Position := TTextPosition.Create(3, 2);
  mTokens[2].Length := 5;
  mTokens[2].TokenType := TSemanticTokenType.Method;
  mTokens[2].Modifiers := [];
  mData := TLspSemanticTokens.Encode(mTokens);
  Assert.AreEqual('1,4,3,1,1,0,6,2,7,6,2,2,5,13,0', string.Join(',', TArray<string>.Create(
    IntToStr(mData[0]), IntToStr(mData[1]), IntToStr(mData[2]), IntToStr(mData[3]), IntToStr(mData[4]),
    IntToStr(mData[5]), IntToStr(mData[6]), IntToStr(mData[7]), IntToStr(mData[8]), IntToStr(mData[9]),
    IntToStr(mData[10]), IntToStr(mData[11]), IntToStr(mData[12]), IntToStr(mData[13]), IntToStr(mData[14]))));
end;

procedure TLspSemanticTokensTests.MarksReassignedNames;
const
  cSource =
    'unit R;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(A: Integer);'#10 +
    'var'#10 +
    '  Total, Once: Integer;'#10 +   // 5
    'begin'#10 +
    '  Total := A;'#10 +             // 7
    '  Once := Total;'#10 +
    '  Total := Once;'#10 +          // 9
    'end;'#10 +
    'end.';
var
  mTree: TSyntaxTree;
  mTokens: TArray<TSemanticToken>;
  mCapability: TJSONObject;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mTokens := TLspSemanticTokens.Collect(FResolver, FIndex, mTree, 'C:\P\R.pas', Default(TTextRange), False);
    TLspSemanticTokens.MarkReassigned(mTokens, TReassigned.Filter(TLspReassigned.Analyze(FResolver, mTree,
      'C:\P\R.pas', cSource), TReassigned.cDefaultTargets));
  finally
    mTree.Free;
  end;
  // +3 reassigned: Total an Deklaration und jeder Verwendung, Once nicht.
  Assert.AreEqual('2 variable+3|9 variable|', Describe(mTokens, 5));
  Assert.AreEqual('2 variable+3|11 parameter|', Describe(mTokens, 7));
  Assert.AreEqual('2 variable|10 variable+3|', Describe(mTokens, 8));
  mCapability := TLspSemanticTokens.Capability;
  try
    Assert.IsTrue(Pos('"reassigned"', mCapability.ToJSON) > 0);
  finally
    mCapability.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSemanticTokensTests);

end.
