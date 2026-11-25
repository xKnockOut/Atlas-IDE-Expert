unit Atlas.Common.Pascal.MethodText.Tests;

// Textbausteine für Methodenköpfe (#1477): Token an einer Lage, Aufrufkonvention hinter dem Kopf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodTextTests = class
  public
    [Test]
    procedure FindsTokensByPosition;
    [Test]
    procedure ReadsConventionOfRest;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.MethodText;

{ TMethodTextTests }

procedure TMethodTextTests.FindsTokensByPosition;
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

procedure TMethodTextTests.ReadsConventionOfRest;
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

initialization
  TDUnitX.RegisterTestFixture(TMethodTextTests);

end.
