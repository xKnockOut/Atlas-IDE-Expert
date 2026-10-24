unit Atlas.Core.Lsp.DataFlow.Tests;

// Datenfluss (#690), Plugin-Seite: Parameter von atlas/dataFlow und Lesen der Antwort.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLspDataFlowTests = class
  public
    [Test]
    procedure ParamsCarryDirectionFiltersAndPath;
    [Test]
    procedure ParsesNodesPlacesAndSources;
    [Test]
    procedure NotFoundAndNull;
    [Test]
    procedure UnknownKind;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.DataFlow;

const
  Answer =
    '{"found":true,"symbol":{"name":"Zaehler","uri":"file:///c%3A/P/Haupt.pas","line":6,"character":25,' +
    '"key":"C:\\P\\HAUPT.PAS|6:25","symbolKind":9},"nodes":[' +
    '{"kind":"assignment","detail":"Summe(Wert)","via":"Summe","places":[' +
    '{"uri":"file:///c%3A/P/Haupt.pas","line":11,"character":2,"lineText":"Zaehler := Summe(Wert);"},' +
    '{"uri":"file:///c%3A/P/Haupt.pas","line":13,"character":2,"lineText":"Zaehler := Summe(Wert);"}],' +
    '"sources":[{"name":"Summe","uri":"file:///c%3A/P/Daten.pas","line":10,"character":9,' +
    '"key":"C:\\P\\DATEN.PAS|10:9"}]},' +
    '{"kind":"assignment","detail":"Zaehler + 1","literal":true,"unsafe":true,"unsafeReason":"move",' +
    '"places":[{"uri":"file:///c%3A/P/Haupt.pas","line":18,"character":2,"lineText":"x"}],' +
    '"sources":[{"name":"Zaehler","uri":"file:///c%3A/P/Haupt.pas","line":6,"character":25,"key":"k",' +
    '"leaf":"cycle"},{"name":"cMax","uri":"file:///c%3A/P/Daten.pas","line":14,"character":2,"key":"c",' +
    '"leaf":"constant"}]},' +
    '{"kind":"input","detail":"ReadLn(X)","places":[]}]}';

{ TAtlasLspDataFlowTests }

procedure TAtlasLspDataFlowTests.ParamsCarryDirectionFiltersAndPath;
var
  Request: TAtlasDataFlowRequest;
  Params: TJSONObject;
begin
  Request := TAtlasDataFlowRequest.Create(TAtlasDataFlowDirection.Targets, 'C:\P\Haupt.pas', 4, 7);
  Request.ExcludeTests := True;
  Request.Path := TArray<string>.Create('a', 'b');
  Params := TAtlasDataFlowJson.Params(Request);
  try
    Assert.AreEqual('file:///c%3A/P/Haupt.pas', Params.GetValue<string>('textDocument.uri'));
    Assert.AreEqual(4, Params.GetValue<Integer>('position.line'));
    Assert.AreEqual(7, Params.GetValue<Integer>('position.character'));
    Assert.AreEqual('targets', Params.GetValue<string>('direction'));
    Assert.IsTrue(Params.GetValue<Boolean>('excludeTests'));
    Assert.IsFalse(Params.GetValue<Boolean>('onlyProject'));
    Assert.AreEqual(2, Params.GetValue<TJSONArray>('path').Count);
    Assert.AreEqual('b', Params.GetValue<TJSONArray>('path').Items[1].Value);
  finally
    Params.Free;
  end;
  Request.Direction := TAtlasDataFlowDirection.Sources;
  Params := TAtlasDataFlowJson.Params(Request);
  try
    Assert.AreEqual('sources', Params.GetValue<string>('direction'));
  finally
    Params.Free;
  end;
end;

procedure TAtlasLspDataFlowTests.ParsesNodesPlacesAndSources;
var
  Value: TJSONValue;
  Flow: TAtlasDataFlowResult;
begin
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Flow := TAtlasDataFlowJson.Parse(Value);
  finally
    Value.Free;
  end;
  Assert.IsTrue(Flow.Found);
  Assert.AreEqual('Zaehler', Flow.Symbol.Name);
  Assert.IsTrue(SameText('C:\P\Haupt.pas', Flow.Symbol.FileName), Flow.Symbol.FileName);
  Assert.AreEqual(6, Flow.Symbol.Line);
  // Die Stelle ohne Fundort fällt weg.
  Assert.AreEqual(2, Integer(Length(Flow.Nodes)));
  Assert.IsTrue(Flow.Nodes[0].Kind = TAtlasDataFlowKind.Assignment);
  Assert.AreEqual('Summe', Flow.Nodes[0].Via);
  Assert.AreEqual(2, Integer(Length(Flow.Nodes[0].Places)));
  Assert.AreEqual(13, Flow.Nodes[0].Places[1].Line);
  Assert.AreEqual('Zaehler := Summe(Wert);', Flow.Nodes[0].Places[0].LineText);
  Assert.IsTrue(SameText('C:\P\Daten.pas', Flow.Nodes[0].Sources[0].FileName));
  Assert.IsTrue(Flow.Nodes[0].Sources[0].Leaf = TAtlasDataFlowLeaf.None);
  Assert.IsTrue(Flow.Nodes[1].Literal);
  Assert.IsTrue(Flow.Nodes[1].Unsafe);
  Assert.AreEqual('move', Flow.Nodes[1].UnsafeReason);
  Assert.IsTrue(Flow.Nodes[1].Sources[0].Leaf = TAtlasDataFlowLeaf.Cycle);
  Assert.IsTrue(Flow.Nodes[1].Sources[1].Leaf = TAtlasDataFlowLeaf.Constant);
end;

procedure TAtlasLspDataFlowTests.NotFoundAndNull;
var
  Value: TJSONValue;
begin
  Assert.IsFalse(TAtlasDataFlowJson.Parse(nil).Found);
  Value := TJSONNull.Create;
  try
    Assert.IsFalse(TAtlasDataFlowJson.Parse(Value).Found);
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue('{"found":false}');
  try
    Assert.IsFalse(TAtlasDataFlowJson.Parse(Value).Found);
  finally
    Value.Free;
  end;
end;

procedure TAtlasLspDataFlowTests.UnknownKind;
begin
  Assert.IsTrue(TAtlasDataFlowJson.KindOf('callerArgument') = TAtlasDataFlowKind.CallerArgument);
  Assert.IsTrue(TAtlasDataFlowJson.KindOf('initialization') = TAtlasDataFlowKind.Initializer);
  Assert.IsTrue(TAtlasDataFlowJson.KindOf('neu') = TAtlasDataFlowKind.Unknown);
  Assert.IsTrue(TAtlasDataFlowJson.KindOf('') = TAtlasDataFlowKind.Unknown);
end;

end.
