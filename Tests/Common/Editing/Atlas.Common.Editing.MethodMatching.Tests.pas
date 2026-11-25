unit Atlas.Common.Editing.MethodMatching.Tests;

interface

// Zuordnung von Deklarationen und Rümpfen je Datei (#1477): Token an einer
// Lage, Typen und Methoden über Tabellen, Überladungen, Aufrufkonvention,
// gleichnamige generische Typen und Lesen erst beim ersten Zugriff.

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodMatchingTests = class
  public
    [Test]
    procedure FindsTokensByPosition;
    [Test]
    procedure ReadsConventionOfRest;
    [Test]
    procedure MatchesBodiesPerType;
    [Test]
    procedure MatchesOverloadsAndConventions;
    [Test]
    procedure SkipsGenericAndForeignBodies;
    [Test]
    procedure FindsTypesAndMethodsByName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Text.Lines,
  Atlas.Common.Editing.MethodMatching;

/// <summary>Zuordnung für AText; der Aufrufer gibt sie frei.</summary>
function MatchingOf(const AText: string): TMethodMatching;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TMethodMatching.Create(TTextLines.SplitLines(AText), TIndexExtractor.Extract(mTree, ''));
  finally
    mTree.Free;
  end;
end;

/// <summary>Zuordnung des Typs ATypeName; Exception ohne.</summary>
function MatchOf(AMatching: TMethodMatching; const ATypeName: string): TTypeMethodMatch;
var
  mMatch: TTypeMethodMatch;
begin
  for mMatch in AMatching.Matches do
  begin
    if SameText(mMatch.TypeName, ATypeName) then
    begin
      Exit(mMatch);
    end;
  end;
  raise Exception.Create('Typ fehlt: ' + ATypeName);
end;

{ TMethodMatchingTests }

procedure TMethodMatchingTests.FindsTokensByPosition;
var
  mTokens: TArray<TPascalToken>;
begin
  // 'unit' 0:0-0:4, 'U' 0:5-0:6, ';' 0:6-0:7, Kommentar 1:0-1:7, 'end' 2:0-2:3, '.' 2:3-2:4
  mTokens := TPascalLexer.Tokenize('unit U;'#10'{ x y }'#10'end.');
  Assert.AreEqual(1, TMethodText.TokenEndingAt(mTokens, TTextPosition.Create(0, 6)));
  Assert.AreEqual(2, TMethodText.TokenEndingAt(mTokens, TTextPosition.Create(0, 7)));
  Assert.AreEqual(3, TMethodText.TokenEndingAt(mTokens, TTextPosition.Create(1, 7)));
  Assert.AreEqual(-1, TMethodText.TokenEndingAt(mTokens, TTextPosition.Create(0, 5)));
  Assert.AreEqual(-1, TMethodText.TokenEndingAt(mTokens, TTextPosition.Create(9, 0)));
  Assert.AreEqual(0, TMethodText.TokenStartingAt(mTokens, TTextPosition.Create(0, 0)));
  Assert.AreEqual(4, TMethodText.TokenStartingAt(mTokens, TTextPosition.Create(2, 0)));
  Assert.AreEqual(5, TMethodText.TokenStartingAt(mTokens, TTextPosition.Create(2, 3)));
  Assert.AreEqual(-1, TMethodText.TokenStartingAt(mTokens, TTextPosition.Create(0, 1)));
  Assert.AreEqual(-1, TMethodText.TokenEndingAt(nil, TTextPosition.Create(0, 0)));
  mTokens := nil;
end;

procedure TMethodMatchingTests.ReadsConventionOfRest;
begin
  Assert.AreEqual('stdcall', TMethodText.ConventionOfRest('overload; stdcall;'));
  Assert.AreEqual('cdecl', TMethodText.ConventionOfRest(' virtual; CDECL'));
  Assert.AreEqual('', TMethodText.ConventionOfRest('overload; virtual;'));
  // Hinter einer fremden Direktive ist Schluss.
  Assert.AreEqual('', TMethodText.ConventionOfRest('unbekannt; stdcall;'));
  Assert.IsFalse(TMethodText.ConventionDiffers('', 'stdcall'));
  Assert.IsFalse(TMethodText.ConventionDiffers('register', ''));
  Assert.IsTrue(TMethodText.ConventionDiffers('stdcall', ''));
end;

procedure TMethodMatchingTests.MatchesBodiesPerType;
var
  mMatching: TMethodMatching;
  mMatch: TTypeMethodMatch;
begin
  mMatching := MatchingOf('unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B; virtual; abstract;'#10 +
    '    procedure C;'#10 +
    '  end;'#10 +
    '  TBar = class'#10 +
    '    procedure A;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.A;'#10'begin'#10'end;'#10 +
    'procedure TFoo.D;'#10'begin'#10'end;'#10 +
    'procedure TBar.A;'#10'begin'#10'end;'#10 +
    'end.');
  try
    Assert.AreEqual(2, Integer(Length(mMatching.Matches)));
    mMatch := MatchOf(mMatching, 'TFoo');
    Assert.AreEqual(3, Integer(Length(mMatch.Declarations)));
    Assert.AreEqual(2, Integer(Length(mMatch.Bodies)));
    // A hat Rumpf 0, B ist abstrakt, C hat keinen; D ist ein Rumpf ohne Deklaration.
    Assert.AreEqual(0, mMatch.BodyOf[0]);
    Assert.AreEqual(-2, mMatch.BodyOf[1]);
    Assert.AreEqual(-1, mMatch.BodyOf[2]);
    Assert.IsTrue(mMatch.BodyUsed[0]);
    Assert.IsFalse(mMatch.BodyUsed[1]);
    Assert.AreEqual('D', mMatch.Bodies[1].Name);
    mMatch := MatchOf(mMatching, 'TBar');
    Assert.AreEqual(0, mMatch.BodyOf[0]);
  finally
    mMatching.Free;
  end;
end;

procedure TMethodMatchingTests.MatchesOverloadsAndConventions;
var
  mMatching: TMethodMatching;
  mMatch: TTypeMethodMatch;
begin
  mMatching := MatchingOf('unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Lauf(A: Integer); overload;'#10 +
    '    procedure Lauf(const A: string); overload;'#10 +
    '    procedure Ruf; stdcall;'#10 +
    '    procedure Kurz(A: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Lauf(const A: string);'#10'begin'#10'end;'#10 +
    'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure TFoo.Ruf; cdecl;'#10'begin'#10'end;'#10 +
    'procedure TFoo.Kurz;'#10'begin'#10'end;'#10 +
    'end.');
  try
    mMatch := MatchOf(mMatching, 'TFoo');
    // Überladungen nach Parametern, nicht nach Reihenfolge.
    Assert.AreEqual(1, mMatch.BodyOf[0]);
    Assert.AreEqual(0, mMatch.BodyOf[1]);
    // Eine andere ausdrückliche Aufrufkonvention passt nicht (E2037).
    Assert.AreEqual(-1, mMatch.BodyOf[2]);
    Assert.IsFalse(mMatch.BodyUsed[2]);
    // Rumpf ohne Parameterliste passt zur ersten Deklaration gleichen Namens.
    Assert.AreEqual(3, mMatch.BodyOf[3]);
  finally
    mMatching.Free;
  end;
end;

procedure TMethodMatchingTests.SkipsGenericAndForeignBodies;
var
  mMatching: TMethodMatching;
  mMatch: TTypeMethodMatch;
begin
  mMatching := MatchingOf('unit U;'#10'interface'#10'type'#10 +
    '  THash = class'#10 +
    '    procedure Put;'#10 +
    '  end;'#10 +
    '  THash<T> = class'#10 +
    '    procedure Put;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure THash<T>.Put;'#10'begin'#10'end;'#10 +
    'procedure THash.Put;'#10'begin'#10'end;'#10 +
    'procedure TFremd.Put;'#10'begin'#10'end;'#10 +
    'end.');
  try
    // Der generische Typ fehlt; sein Rumpf gehört nicht zu THash, Rümpfe fremder Typen fehlen ganz.
    Assert.AreEqual(1, Integer(Length(mMatching.Matches)));
    mMatch := MatchOf(mMatching, 'THash');
    Assert.AreEqual(1, Integer(Length(mMatch.Declarations)));
    Assert.AreEqual(1, Integer(Length(mMatch.Bodies)));
    Assert.AreEqual(0, mMatch.BodyOf[0]);
  finally
    mMatching.Free;
  end;
end;

procedure TMethodMatchingTests.FindsTypesAndMethodsByName;
var
  mMatching: TMethodMatching;
  mType: TIndexSymbol;
  mMethods: TArray<Integer>;
begin
  mMatching := MatchingOf('unit U;'#10'interface'#10'type'#10 +
    '  TAussen = class'#10 +
    '  type'#10 +
    '    TInnen = class'#10 +
    '      procedure Tief;'#10 +
    '    end;'#10 +
    '  public'#10 +
    '    procedure Flach;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAussen.TInnen.Tief;'#10'begin'#10'end;'#10 +
    'procedure TAussen.Flach;'#10'begin'#10'end;'#10 +
    'end.');
  try
    Assert.IsTrue(mMatching.FindType('taussen.tinnen', mType));
    Assert.AreEqual('TInnen', mType.Name);
    Assert.IsFalse(mMatching.FindType('TInnen', mType));
    mMethods := mMatching.MethodsOf('TAUSSEN.TINNEN');
    // Deklaration und Rumpf von Tief.
    Assert.AreEqual(2, Integer(Length(mMethods)));
    Assert.AreEqual('Tief', mMatching.UnitIndex.Symbols[mMethods[0]].Name);
    Assert.AreEqual(0, Integer(Length(mMatching.MethodsOf('TFremd'))));
    Assert.AreEqual(2, Integer(Length(mMatching.TypeIndexes)));
    Assert.AreEqual(0, MatchOf(mMatching, 'TAussen.TInnen').BodyOf[0]);
  finally
    mMatching.Free;
  end;
  mMethods := nil;
end;

end.
