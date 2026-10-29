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
  FileName = 'C:\P\Kunden.pas';
  UnitText =
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

procedure TLspExpressionCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FStore.Open(TDocumentUris.FromPath(FileName), 'delphi', 1, UnitText);
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
  Request, Response: TJSONObject;
begin
  // Über den Dispatcher: Er liefert das Abbruchsignal, das Complete braucht.
  Inc(FId);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) + ',"method":"' +
    TLspExpressionCompletion.Method + '","params":{"textDocument":{"uri":"' +
    TDocumentUris.FromPath(FileName).Replace('\', '\\') + '"},"position":{"line":' + IntToStr(ALine) +
    ',"character":0},"expression":"' + AExpression + '","character":' + IntToStr(Length(AExpression)) +
    '}}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  try
    Assert.IsNotNull(Response);
    Result := Response.GetValue('result').Clone as TJSONObject;
  finally
    Response.Free;
  end;
end;

class function TLspExpressionCompletionTests.Labels(AAnswer: TJSONObject): string;
var
  Value: TJSONValue;
begin
  Result := ',';
  for Value in AAnswer.GetValue('items') as TJSONArray do
    Result := Result + (Value as TJSONObject).GetValue('label').Value + ',';
end;

procedure TLspExpressionCompletionTests.PlacesBeforeStatementAndAfterBegin;
var
  Document: ITextDocument;
  Placement: TExpressionPlacement;
begin
  Assert.IsTrue(FStore.TryGet(TDocumentUris.FromPath(FileName), Document));
  Placement := TLspExpressionCompletion.Place(Document, 15, 'Kunde.Name');
  Assert.AreEqual(15, Placement.Line, 'vor der Anweisung');
  Assert.AreEqual(2, Placement.Column);
  Assert.AreEqual('  Kunde.Name;'#13#10, Placement.Text);
  Placement := TLspExpressionCompletion.Place(Document, 13, 'Kunde');
  Assert.AreEqual(14, Placement.Line, 'hinter begin, sonst stünde der Ausdruck im var-Abschnitt');
  Placement := TLspExpressionCompletion.Place(Document, 99, 'Kunde');
  Assert.AreEqual(Document.LineCount - 1, Placement.Line, 'hinter dem Dokument begrenzt');
  Placement := TLspExpressionCompletion.Place(Document, 15, 'A'#13#10'+ B');
  Assert.AreEqual('  A  + B;'#13#10, Placement.Text, 'eine Zeile');
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
  Answer: TJSONObject;
  Found: string;
begin
  Answer := Ask(15, 'Ku');
  try
    Assert.AreEqual('Ku', Answer.GetValue('prefix').Value);
    Found := Labels(Answer);
    Assert.IsTrue(Pos(',Kunde,', Found) > 0, Found);
  finally
    Answer.Free;
  end;
  Answer := Ask(14, 'An');
  try
    Found := Labels(Answer);
    Assert.IsTrue(Pos(',Anzahl,', Found) > 0, 'Parameter: ' + Found);
  finally
    Answer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.OffersMembersAfterDot;
var
  Answer: TJSONObject;
  Found: string;
begin
  Answer := Ask(15, 'Kunde.');
  try
    Found := Labels(Answer);
    Assert.IsTrue(Pos(',Name,', Found) > 0, Found);
    Assert.IsTrue(Pos(',Umsatz,', Found) > 0, Found);
    Assert.IsTrue(Pos(',Summe,', Found) = 0, 'nach dem Punkt keine lokalen Namen: ' + Found);
  finally
    Answer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.DropsKeywordsAndSnippets;
var
  Answer: TJSONObject;
  Value: TJSONValue;
  Kind: Integer;
begin
  Answer := Ask(15, 'b');
  try
    for Value in Answer.GetValue('items') as TJSONArray do
    begin
      Kind := (Value as TJSONObject).GetValue<Integer>('kind');
      Assert.IsTrue((Kind <> 14) and (Kind <> 15), Value.ToJSON);
    end;
    Assert.IsTrue(Pos(',begin,', LowerCase(Labels(Answer))) = 0);
  finally
    Answer.Free;
  end;
end;

procedure TLspExpressionCompletionTests.HandlerKeepsStoreUnchanged;
var
  Request, Response: TJSONObject;
  Document: ITextDocument;
  Uri: string;
begin
  Uri := TDocumentUris.FromPath(FileName);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspExpressionCompletion.Method +
    '","params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') +
    '"},"position":{"line":15,"character":0},"expression":"Kunde.Na","character":8}}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  try
    Assert.IsNotNull(Response);
    Assert.AreEqual('Na', Response.GetValue<string>('result.prefix'));
    Assert.IsTrue(Pos(',Name,', Labels(Response.GetValue('result') as TJSONObject)) > 0, Response.ToJSON);
  finally
    Response.Free;
  end;
  Assert.IsTrue(FStore.TryGet(Uri, Document));
  Assert.AreEqual(UnitText, Document.Text, 'Dokumentspeicher unverändert');
end;

end.
