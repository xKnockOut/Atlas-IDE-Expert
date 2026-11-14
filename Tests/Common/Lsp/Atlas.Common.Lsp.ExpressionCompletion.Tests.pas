unit Atlas.Common.Lsp.ExpressionCompletion.Tests;

// Vervollständigung in den Debug-Dialogen (#538), Server: Ausdruck vor oder
// hinter der Bezugszeile, Bezeichner vor der Schreibmarke, lokale Namen am
// Haltepunkt, Elemente nach dem Punkt, keine Schlüsselwörter und Vorlagen,
// Anfrage über den Dispatcher; der Dokumentspeicher bleibt unverändert.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.ExpressionCompletion;

type
  [TestFixture]
  TLspExpressionCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FExpressions: TLspExpressionCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FId: Integer;
    /// <summary>Antwort für AExpression mit der Schreibmarke am Ende; gehört dem Aufrufer.</summary>
    function Ask(ALine: Integer; const AExpression: string): TJSONObject;
    /// <summary>Beschriftungen der Einträge, durch Komma getrennt und mit Komma eingefasst.</summary>
    class function Labels(AAnswer: TJSONObject): string; static;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PlacesBeforeStatementAndAfterBegin;
    [Test]
    procedure PrefixBeforeCaret;
    [Test]
    procedure OffersLocalsAndParameters;
    [Test]
    procedure OffersMembersAfterDot;
    [Test]
    procedure DropsKeywordsAndSnippets;
    [Test]
    procedure HandlerKeepsStoreUnchanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex;

const
  cFileName = 'C:\P\Kunden.pas';
  cUnitText =
    'unit Kunden;'#13#10 +                                  // 0
    'interface'#13#10 +                                     // 1
    'type'#13#10 +                                          // 2
    '  TKunde = class'#13#10 +                              // 3
    '    Name: string;'#13#10 +                             // 4
    '    Umsatz: Integer;'#13#10 +                          // 5
    '  end;'#13#10 +                                        // 6
    'procedure Rechne(Anzahl: Integer);'#13#10 +            // 7
    'implementation'#13#10 +                                // 8
    'procedure Rechne(Anzahl: Integer);'#13#10 +            // 9
    'var'#13#10 +                                           // 10
    '  Kunde: TKunde;'#13#10 +                              // 11
    '  Summe: Integer;'#13#10 +                             // 12
    'begin'#13#10 +                                         // 13
    '  Summe := Anzahl;'#13#10 +                            // 14
    '  Kunde := nil;'#13#10 +                               // 15
    'end;'#13#10 +                                          // 16
    'end.';

{ TLspExpressionCompletionTests }

procedure TLspExpressionCompletionTests.WarmUpFirstUse;
begin
  Setup;
  try
    OffersLocalsAndParameters;
  finally
    TearDown;
  end;
end;

procedure TLspExpressionCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FStore.Open(TDocumentUris.FromPath(cFileName), 'delphi', 1, cUnitText);
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FExpressions := TLspExpressionCompletion.Create(FStore, FCompletion);
  FId := 0;
  FDispatcher := TJsonRpcDispatcher.Create;
  FExpressions.Attach(FDispatcher);
end;

procedure TLspExpressionCompletionTests.TearDown;
begin
  FDispatcher.Free;
  FExpressions.Free;
  FCompletion.Free;
  FStore := nil;
  FIndex := nil;
end;

function TLspExpressionCompletionTests.Ask(ALine: Integer; const AExpression: string): TJSONObject;
var
  mRequest, mResponse: TJSONObject;
begin
  // Über den Dispatcher: Er liefert das Abbruchsignal, das Complete braucht.
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) + ',"method":"' +
    TLspExpressionCompletion.cMethod + '","params":{"textDocument":{"uri":"' +
    TDocumentUris.FromPath(cFileName).Replace('\', '\\') + '"},"position":{"line":' + IntToStr(ALine) +
    ',"character":0},"expression":"' + AExpression + '","character":' + IntToStr(Length(AExpression)) +
    '}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    Assert.IsNotNull(mResponse);
    Result := mResponse.GetValue('result').Clone as TJSONObject;
  finally
    mResponse.Free;
  end;
end;

class function TLspExpressionCompletionTests.Labels(AAnswer: TJSONObject): string;
var
  mValue: TJSONValue;
begin
  Result := ',';
  for mValue in AAnswer.GetValue('items') as TJSONArray do
  begin
    Result := Result + (mValue as TJSONObject).GetValue('label').Value + ',';
  end;
end;

procedure TLspExpressionCompletionTests.PlacesBeforeStatementAndAfterBegin;
var
  mDocument: ITextDocument;
  mPlacement: TExpressionPlacement;
begin
  Assert.IsTrue(FStore.TryGet(TDocumentUris.FromPath(cFileName), mDocument));
  mPlacement := TLspExpressionCompletion.Place(mDocument, 15, 'Kunde.Name');
  Assert.AreEqual(15, mPlacement.Line, 'vor der Anweisung');
  Assert.AreEqual(2, mPlacement.Column);
  Assert.AreEqual('  Kunde.Name;'#13#10, mPlacement.Text);
  mPlacement := TLspExpressionCompletion.Place(mDocument, 13, 'Kunde');
  Assert.AreEqual(14, mPlacement.Line, 'hinter begin, sonst stünde der Ausdruck im var-Abschnitt');
  mPlacement := TLspExpressionCompletion.Place(mDocument, 99, 'Kunde');
  Assert.AreEqual(mDocument.LineCount - 1, mPlacement.Line, 'hinter dem Dokument begrenzt');
  mPlacement := TLspExpressionCompletion.Place(mDocument, 15, 'A'#13#10'+ B');
  Assert.AreEqual('  A  + B;'#13#10, mPlacement.Text, 'eine Zeile');
end;

procedure TLspExpressionCompletionTests.PrefixBeforeCaret;
begin
  Assert.AreEqual('Na', TLspExpressionCompletion.PrefixAt('Kunde.Name', 8));
  Assert.AreEqual('', TLspExpressionCompletion.PrefixAt('Kunde.', 6));
  Assert.AreEqual('Kun', TLspExpressionCompletion.PrefixAt('Kun', 3));
  Assert.AreEqual('Sum', TLspExpressionCompletion.PrefixAt('Sum + 1', 3));
  Assert.AreEqual('', TLspExpressionCompletion.PrefixAt('', 5));
end;

procedure TLspExpressionCompletionTests.OffersLocalsAndParameters;
var
  mAnswer: TJSONObject;
  mFound: string;
begin
  mAnswer := Ask(15, 'Ku');
  try
    Assert.AreEqual('Ku', mAnswer.GetValue('prefix').Value);
    mFound := Labels(mAnswer);
    Assert.IsTrue(Pos(',Kunde,', mFound) > 0, mFound);
  finally
    mAnswer.Free;
  end;
  mAnswer := Ask(14, 'An');
  try
    mFound := Labels(mAnswer);
    Assert.IsTrue(Pos(',Anzahl,', mFound) > 0, 'Parameter: ' + mFound);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.OffersMembersAfterDot;
var
  mAnswer: TJSONObject;
  mFound: string;
begin
  mAnswer := Ask(15, 'Kunde.');
  try
    mFound := Labels(mAnswer);
    Assert.IsTrue(Pos(',Name,', mFound) > 0, mFound);
    Assert.IsTrue(Pos(',Umsatz,', mFound) > 0, mFound);
    Assert.AreEqual(0, Pos(',Summe,', mFound), 'nach dem Punkt keine lokalen Namen: ' + mFound);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.DropsKeywordsAndSnippets;
var
  mAnswer: TJSONObject;
  mValue: TJSONValue;
  mKind: Integer;
begin
  mAnswer := Ask(15, 'b');
  try
    for mValue in mAnswer.GetValue('items') as TJSONArray do
    begin
      mKind := (mValue as TJSONObject).GetValue<Integer>('kind');
      Assert.IsTrue((mKind <> 14) and (mKind <> 15), mValue.ToJSON);
    end;
    Assert.AreEqual(0, Pos(',begin,', LowerCase(Labels(mAnswer))));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.HandlerKeepsStoreUnchanged;
var
  mRequest, mResponse: TJSONObject;
  mDocument: ITextDocument;
  mUri: string;
begin
  mUri := TDocumentUris.FromPath(cFileName);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspExpressionCompletion.cMethod +
    '","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') +
    '"},"position":{"line":15,"character":0},"expression":"Kunde.Na","character":8}}') as TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    Assert.IsNotNull(mResponse);
    Assert.AreEqual('Na', mResponse.GetValue<string>('result.prefix'));
    Assert.IsTrue(Pos(',Name,', Labels(mResponse.GetValue('result') as TJSONObject)) > 0, mResponse.ToJSON);
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(FStore.TryGet(mUri, mDocument));
  Assert.AreEqual(cUnitText, mDocument.Text, 'Dokumentspeicher unverändert');
end;

end.
