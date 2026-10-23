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
  HauptFile = 'C:\P\Haupt.pas';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'function Trim(const S: string): string;'#10 +
    'implementation'#10 +
    'function Trim(const S: string): string;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSysUtils, 'C:\RTL\System.SysUtils.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspSemanticTokensTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspSemanticTokensTests.Collect: TArray<TSemanticToken>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspSemanticTokens.Collect(FResolver, FIndex, Tree, HauptFile, Default(TTextRange), False);
  finally
    Tree.Free;
  end;
end;

function TLspSemanticTokensTests.Describe(const ATokens: TArray<TSemanticToken>; ALine: Integer): string;
var
  Token: TSemanticToken;
  Modifier: TSemanticTokenModifier;
begin
  Result := '';
  for Token in ATokens do
    if Token.Position.Line = ALine then
    begin
      Result := Result + IntToStr(Token.Position.Character) + ' ' + TLspSemanticTokens.TypeName(Token.TokenType);
      for Modifier in Token.Modifiers do
        Result := Result + '+' + IntToStr(Ord(Modifier));
      Result := Result + '|';
    end;
end;

procedure TLspSemanticTokensTests.ClassifiesDeclarations;
var
  Tokens: TArray<TSemanticToken>;
begin
  Tokens := Collect;
  // +0 declaration, +1 readonly, +2 defaultLibrary
  Assert.AreEqual('2 enum+0|12 enumMember+0|17 enumMember+0|', Describe(Tokens, 4));
  Assert.AreEqual('4 field+0|', Describe(Tokens, 6));
  Assert.AreEqual('13 property+0|', Describe(Tokens, 8));
  Assert.AreEqual('13 event+0|', Describe(Tokens, 9));
  Assert.AreEqual('2 variable+0+1|', Describe(Tokens, 12));
end;

procedure TLspSemanticTokensTests.ClassifiesUses;
var
  Tokens: TArray<TSemanticToken>;
begin
  Tokens := Collect;
  // IntToStr ist unbekannt und bleibt ohne Einordnung.
  Assert.AreEqual('2 variable|10 function+2|15 variable|32 parameter|41 field|49 variable+1|', Describe(Tokens, 18));
  Assert.AreEqual('2 method|10 enumMember|17 variable+1|22 property|28 namespace+2|35 namespace+2|44 function+2|49 variable|',
    Describe(Tokens, 19));
end;

procedure TLspSemanticTokensTests.RangeLimitsTokens;
var
  Tree: TSyntaxTree;
  Tokens: TArray<TSemanticToken>;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Tokens := TLspSemanticTokens.Collect(FResolver, FIndex, Tree, HauptFile,
      TTextRange.Create(TTextPosition.Create(12, 0), TTextPosition.Create(13, 0)), True);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Tokens)));
  Assert.AreEqual(12, Tokens[0].Position.Line);
end;

procedure TLspSemanticTokensTests.EncodesRelativePositions;
var
  Tokens: TArray<TSemanticToken>;
  Data: TArray<Integer>;
begin
  SetLength(Tokens, 3);
  Tokens[0].Position := TTextPosition.Create(1, 4);
  Tokens[0].Length := 3;
  Tokens[0].TokenType := TSemanticTokenType.Class_;
  Tokens[0].Modifiers := [TSemanticTokenModifier.Declaration];
  Tokens[1].Position := TTextPosition.Create(1, 10);
  Tokens[1].Length := 2;
  Tokens[1].TokenType := TSemanticTokenType.Variable;
  Tokens[1].Modifiers := [TSemanticTokenModifier.Readonly, TSemanticTokenModifier.DefaultLibrary];
  Tokens[2].Position := TTextPosition.Create(3, 2);
  Tokens[2].Length := 5;
  Tokens[2].TokenType := TSemanticTokenType.Method;
  Tokens[2].Modifiers := [];
  Data := TLspSemanticTokens.Encode(Tokens);
  Assert.AreEqual('1,4,3,1,1,0,6,2,7,6,2,2,5,13,0', string.Join(',', TArray<string>.Create(
    IntToStr(Data[0]), IntToStr(Data[1]), IntToStr(Data[2]), IntToStr(Data[3]), IntToStr(Data[4]),
    IntToStr(Data[5]), IntToStr(Data[6]), IntToStr(Data[7]), IntToStr(Data[8]), IntToStr(Data[9]),
    IntToStr(Data[10]), IntToStr(Data[11]), IntToStr(Data[12]), IntToStr(Data[13]), IntToStr(Data[14]))));
end;

procedure TLspSemanticTokensTests.MarksReassignedNames;
const
  Source =
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
  Tree: TSyntaxTree;
  Tokens: TArray<TSemanticToken>;
  Capability: TJSONObject;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Tokens := TLspSemanticTokens.Collect(FResolver, FIndex, Tree, 'C:\P\R.pas', Default(TTextRange), False);
    TLspSemanticTokens.MarkReassigned(Tokens, TReassigned.Filter(TLspReassigned.Analyze(FResolver, Tree,
      'C:\P\R.pas', Source), TReassigned.DefaultTargets));
  finally
    Tree.Free;
  end;
  // +3 reassigned: Total an Deklaration und jeder Verwendung, Once nicht.
  Assert.AreEqual('2 variable+3|9 variable|', Describe(Tokens, 5));
  Assert.AreEqual('2 variable+3|11 parameter|', Describe(Tokens, 7));
  Assert.AreEqual('2 variable|10 variable+3|', Describe(Tokens, 8));
  Capability := TLspSemanticTokens.Capability;
  try
    Assert.IsTrue(Pos('"reassigned"', Capability.ToJSON) > 0);
  finally
    Capability.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSemanticTokensTests);

end.
