unit Atlas.Core.Lsp.AccessChains.Tests;

// Zugriffsketten (#865), Plugin-Seite: Parameter von atlas/accessChains, Lesen der Antwort und Zeigergröße.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLspAccessChainsTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure ParamsCarryUriLineAndPointerSize;
    [Test]
    procedure PointerSizeFromPlatform;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.AccessChains;

{ TAtlasLspAccessChainsTests }

procedure TAtlasLspAccessChainsTests.ParsesServerAnswer;
const
  cAnswer =
    '{"statements":2,"chains":[{"text":"Auftrag.Kunde.Adresse","links":[' +
    '{"expression":"Auftrag","name":"Auftrag","kind":"class","typeName":"TAuftrag","member":"Kunde",' +
    '"range":{"start":{"line":40,"character":2},"end":{"line":40,"character":9}},' +
    '"namePosition":{"line":40,"character":2}},' +
    '{"expression":"Auftrag.Kunde","name":"Kunde","kind":"class","typeName":"TKunde","call":true,' +
    '"member":"Adresse","fields":[{"name":"FName","offset":4},{"name":"FAdresse","offset":-1}]}]},' +
    '{"text":"Liste[I].Name","links":[{"expression":"Liste","name":"Liste","kind":"dynArray",' +
    '"implicitSelf":true,"index":"I","indexPlain":true,"member":"[]"}]},' +
    '{"text":"leer","links":[]}]}';
var
  mValue: TJSONValue;
  mParsed: TAtlasAvChains;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    mParsed := TAtlasAvJson.Parse(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mParsed.Found);
  Assert.AreEqual(2, mParsed.Statements);
  Assert.AreEqual(2, Integer(Length(mParsed.Chains)));
  Assert.AreEqual('Auftrag.Kunde.Adresse', mParsed.Chains[0].Text);
  Assert.AreEqual(2, Integer(Length(mParsed.Chains[0].Links)));
  Assert.AreEqual<TAtlasAvLinkKind>(TAtlasAvLinkKind.ClassRef, mParsed.Chains[0].Links[0].Kind);
  Assert.AreEqual(40, mParsed.Chains[0].Links[0].StartLine);
  Assert.AreEqual(9, mParsed.Chains[0].Links[0].EndCharacter);
  Assert.AreEqual(2, mParsed.Chains[0].Links[0].NameCharacter);
  Assert.IsTrue(mParsed.Chains[0].Links[1].Call);
  Assert.AreEqual('TKunde', mParsed.Chains[0].Links[1].TypeName);
  Assert.AreEqual(2, Integer(Length(mParsed.Chains[0].Links[1].Fields)));
  Assert.AreEqual(-1, mParsed.Chains[0].Links[1].Fields[1].Offset);
  Assert.AreEqual<TAtlasAvLinkKind>(TAtlasAvLinkKind.DynArray, mParsed.Chains[1].Links[0].Kind);
  Assert.IsTrue(mParsed.Chains[1].Links[0].ImplicitSelf);
  Assert.AreEqual('I', mParsed.Chains[1].Links[0].IndexText);
  Assert.IsTrue(mParsed.Chains[1].Links[0].IndexPlain);
  Assert.IsFalse(TAtlasAvJson.Parse(nil).Found);
end;

procedure TAtlasLspAccessChainsTests.ParamsCarryUriLineAndPointerSize;
var
  mParams: TJSONObject;
begin
  mParams := TAtlasAvJson.Params('C:\P\Haupt.pas', 40, 8);
  try
    Assert.AreEqual('file:///c%3A/P/Haupt.pas', mParams.GetValue<string>('textDocument.uri'));
    Assert.AreEqual(40, mParams.GetValue<Integer>('line'));
    Assert.AreEqual(8, mParams.GetValue<Integer>('pointerSize'));
  finally
    mParams.Free;
  end;
end;

procedure TAtlasLspAccessChainsTests.PointerSizeFromPlatform;
begin
  Assert.AreEqual(8, TAtlasAvJson.PointerSize('Win64'));
  Assert.AreEqual(8, TAtlasAvJson.PointerSize('Win64x'));
  Assert.AreEqual(4, TAtlasAvJson.PointerSize('Win32'));
  Assert.AreEqual(4, TAtlasAvJson.PointerSize(''));
end;

end.
