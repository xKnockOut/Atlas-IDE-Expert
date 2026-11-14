unit Atlas.Common.Lsp.CompletionRequest.Tests;

// Anfrage der Vervollständigung: Zeilenhelfer mit der Semantik der
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
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', 'C:\P\U.pas', TTextPosition.Create(1, 5));
  try
    Assert.AreEqual('  Foo', mRequest.LineBefore);
  finally
    mRequest.Free;
  end;
  // Hinter dem Zeilenende: bis zum Umbruch, ohne #13.
  mRequest := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', 'C:\P\U.pas', TTextPosition.Create(1, 99));
  try
    Assert.AreEqual('  Foo.Bar', mRequest.LineBefore);
  finally
    mRequest.Free;
  end;
  // Zeile hinter dem Text: leer.
  mRequest := TCompletionRequest.Create('ab'#10'cd', 'C:\P\U.pas', TTextPosition.Create(5, 1));
  try
    Assert.AreEqual('', mRequest.LineBefore);
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionRequestTests.LineTextWithoutLineBreak;
var
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create('ab'#13#10'  Foo.Bar'#13#10'x', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual('ab', mRequest.LineText(0));
    Assert.AreEqual('  Foo.Bar', mRequest.LineText(1));
    Assert.AreEqual('x', mRequest.LineText(2));
    Assert.AreEqual('', mRequest.LineText(3));
    Assert.AreEqual('', mRequest.LineText(-1));
    Assert.AreEqual(3, Integer(Length(mRequest.Lines)));
  finally
    mRequest.Free;
  end;
  mRequest := TCompletionRequest.Create('ab'#10'cd'#10, '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual('cd', mRequest.LineText(1));
    Assert.AreEqual('', mRequest.LineText(2));
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionRequestTests.LineBreakFollowsText;
var
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create('a'#10'b'#13#10'c', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual(#13#10, mRequest.LineBreak);
  finally
    mRequest.Free;
  end;
  mRequest := TCompletionRequest.Create('a'#10'b', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual(#10, mRequest.LineBreak);
  finally
    mRequest.Free;
  end;
end;

procedure TCompletionRequestTests.OffsetMatchesDocument;
const
  cText = 'unit U;'#13#10'interface'#13#10'  Wert := 1;'#13#10'end.';
var
  mStore: IDocumentStore;
  mDocument: ITextDocument;
  mFromText, mFromDocument: TCompletionRequest;
  mPosition: TTextPosition;
  mLine, mCharacter: Integer;
begin
  mStore := TDocumentStore.Create;
  mDocument := mStore.Open('file:///C:/P/U.pas', 'delphi', 1, cText);
  mFromText := TCompletionRequest.Create(cText, 'C:\P\U.pas', TTextPosition.Create(2, 4));
  mFromDocument := TCompletionRequest.Create(mDocument, 'C:\P\U.pas', TTextPosition.Create(2, 4));
  try
    Assert.AreEqual('file:///C:/P/U.pas', mFromDocument.Uri);
    Assert.AreEqual(cText, mFromDocument.Text);
    for mLine := 0 to 3 do
    begin
      for mCharacter := 0 to Length(mDocument.LineText(mLine)) do
      begin
        mPosition := TTextPosition.Create(mLine, mCharacter);
        Assert.AreEqual(mDocument.OffsetAt(mPosition), mFromText.OffsetAt(mPosition), Format('%d:%d', [mLine, mCharacter]));
        Assert.AreEqual(mFromText.OffsetAt(mPosition), mFromDocument.OffsetAt(mPosition));
      end;
    end;
    Assert.AreEqual(mFromText.LineBefore, mFromDocument.LineBefore);
  finally
    mFromDocument.Free;
    mFromText.Free;
  end;
end;

procedure TCompletionRequestTests.UnitIndexIsExtractedOnce;
const
  cText = 'unit Haupt;'#13#10'interface'#13#10'type'#13#10'  TFoo = class'#13#10'  end;'#13#10'implementation'#13#10'end.';
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree, mOther: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mIndex := TSymbolIndex.Create;
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cText);
  mOther := TPascalParser.Parse(StringReplace(cText, 'unit Haupt;', 'unit Neben;', []));
  mRequest := TCompletionRequest.Create(cText, 'C:\P\Haupt.pas', TTextPosition.Create(3, 2));
  try
    mRequest.Resolver := mResolver;
    mRequest.Tree := mTree;
    Assert.AreEqual('Haupt', mRequest.UnitIndex.UnitName);
    Assert.AreEqual('Haupt', mRequest.UnitIndex.UnitName);
    Assert.AreEqual(Integer(Length(mResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas').Symbols)),
      Integer(Length(mRequest.UnitIndex.Symbols)));
    // Neuer Baum: neu ausgewertet.
    mRequest.Tree := mOther;
    Assert.AreEqual('Neben', mRequest.UnitIndex.UnitName);
  finally
    mRequest.Free;
    mOther.Free;
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TCompletionRequestTests.DefaultsAreFuzzyAndStandardSettings;
var
  mRequest: TCompletionRequest;
begin
  mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
  try
    Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Fuzzy, mRequest.Matching);
    Assert.IsTrue(mRequest.Settings.Keywords);
    Assert.IsTrue(mRequest.Settings.OfferTryFinally);
    Assert.AreEqual('', mRequest.Trigger);
    Assert.IsNull(mRequest.Tree);
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionRequestTests);

end.
