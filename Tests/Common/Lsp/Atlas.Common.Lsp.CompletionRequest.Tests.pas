unit Atlas.Common.Lsp.CompletionRequest.Tests;

// Anfrage der Vervollständigung (Code-Review S-01, Block H Schritt 2): Zeilenhelfer mit der Semantik der
// früheren freien Funktionen, Zeilenende, Offset wie das Dokument und Index der eigenen Unit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionRequestTests = class
  public
    [Test]
    procedure LineBeforeStopsAtCursor;
    [Test]
    procedure LineTextWithoutLineBreak;
    [Test]
    procedure LineBreakFollowsText;
    [Test]
    procedure OffsetMatchesDocument;
    [Test]
    procedure UnitIndexIsExtractedOnce;
    [Test]
    procedure DefaultsAreFuzzyAndStandardSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

procedure TCompletionRequestTests.LineBeforeStopsAtCursor;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', 'C:\P\U.pas', TTextPosition.Create(1, 5));
  try
    Assert.AreEqual('  Foo', Request.LineBefore);
  finally
    Request.Free;
  end;
  // Hinter dem Zeilenende: bis zum Umbruch, ohne #13.
  Request := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', 'C:\P\U.pas', TTextPosition.Create(1, 99));
  try
    Assert.AreEqual('  Foo.Bar', Request.LineBefore);
  finally
    Request.Free;
  end;
  // Zeile hinter dem Text: leer.
  Request := TCompletionRequest.Create('ab'#10'cd', 'C:\P\U.pas', TTextPosition.Create(5, 1));
  try
    Assert.AreEqual('', Request.LineBefore);
  finally
    Request.Free;
  end;
end;

procedure TCompletionRequestTests.LineTextWithoutLineBreak;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual('ab', Request.LineText(0));
    Assert.AreEqual('  Foo.Bar', Request.LineText(1));
    Assert.AreEqual('x', Request.LineText(2));
    Assert.AreEqual('', Request.LineText(3));
    Assert.AreEqual('', Request.LineText(-1));
    Assert.AreEqual(3, Integer(Length(Request.Lines)));
  finally
    Request.Free;
  end;
  Request := TCompletionRequest.Create('ab'#10'cd'#10, '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual('cd', Request.LineText(1));
    Assert.AreEqual('', Request.LineText(2));
  finally
    Request.Free;
  end;
end;

procedure TCompletionRequestTests.LineBreakFollowsText;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create('a'#10'b'#13#10'c', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual(#13#10, Request.LineBreak);
  finally
    Request.Free;
  end;
  Request := TCompletionRequest.Create('a'#10'b', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual(#10, Request.LineBreak);
  finally
    Request.Free;
  end;
end;

procedure TCompletionRequestTests.OffsetMatchesDocument;
const
  Text = 'unit U;'#13#10'interface'#13#10'  Wert := 1;'#13#10'end.';
var
  Store: IDocumentStore;
  Document: ITextDocument;
  FromText, FromDocument: TCompletionRequest;
  Position: TTextPosition;
  Line, Character: Integer;
begin
  Store := TDocumentStore.Create;
  Document := Store.Open('file:///C:/P/U.pas', 'delphi', 1, Text);
  FromText := TCompletionRequest.Create(Text, 'C:\P\U.pas', TTextPosition.Create(2, 4));
  FromDocument := TCompletionRequest.Create(Document, 'C:\P\U.pas', TTextPosition.Create(2, 4));
  try
    Assert.AreEqual('file:///C:/P/U.pas', FromDocument.Uri);
    Assert.AreEqual(Text, FromDocument.Text);
    for Line := 0 to 3 do
      for Character := 0 to Length(Document.LineText(Line)) do
      begin
        Position := TTextPosition.Create(Line, Character);
        Assert.AreEqual(Document.OffsetAt(Position), FromText.OffsetAt(Position), Format('%d:%d', [Line, Character]));
        Assert.AreEqual(FromText.OffsetAt(Position), FromDocument.OffsetAt(Position));
      end;
    Assert.AreEqual(FromText.LineBefore, FromDocument.LineBefore);
  finally
    FromDocument.Free;
    FromText.Free;
  end;
end;

procedure TCompletionRequestTests.UnitIndexIsExtractedOnce;
const
  Text = 'unit Haupt;'#13#10'interface'#13#10'type'#13#10'  TFoo = class'#13#10'  end;'#13#10'implementation'#13#10'end.';
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree, Other: TSyntaxTree;
  Request: TCompletionRequest;
begin
  Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(Text);
  Other := TPascalParser.Parse(StringReplace(Text, 'unit Haupt;', 'unit Neben;', []));
  Request := TCompletionRequest.Create(Text, 'C:\P\Haupt.pas', TTextPosition.Create(3, 2));
  try
    Request.Resolver := Resolver;
    Request.Tree := Tree;
    Assert.AreEqual('Haupt', Request.UnitIndex.UnitName);
    Assert.AreEqual('Haupt', Request.UnitIndex.UnitName);
    Assert.AreEqual(Integer(Length(Resolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas').Symbols)),
      Integer(Length(Request.UnitIndex.Symbols)));
    // Neuer Baum: neu ausgewertet.
    Request.Tree := Other;
    Assert.AreEqual('Neben', Request.UnitIndex.UnitName);
  finally
    Request.Free;
    Other.Free;
    Tree.Free;
    Resolver.Free;
  end;
end;

procedure TCompletionRequestTests.DefaultsAreFuzzyAndStandardSettings;
var
  Request: TCompletionRequest;
begin
  Request := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    Assert.IsTrue(Request.Matching = TCompletionMatching.Fuzzy);
    Assert.IsTrue(Request.Settings.Keywords);
    Assert.IsTrue(Request.Settings.OfferTryFinally);
    Assert.AreEqual('', Request.Trigger);
    Assert.IsNull(Request.Tree);
  finally
    Request.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionRequestTests);

end.
