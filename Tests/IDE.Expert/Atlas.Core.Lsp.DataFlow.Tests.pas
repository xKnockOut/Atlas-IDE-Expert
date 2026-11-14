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
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.DataFlow;

const
  cAnswer =
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
  mRequest: TAtlasDataFlowRequest;
  mParams: TJSONObject;
begin
  mRequest := TAtlasDataFlowRequest.Create(TAtlasDataFlowDirection.Targets, 'C:\P\Haupt.pas', 4, 7);
  mRequest.ExcludeTests := True;
  mRequest.Path := TArray<string>.Create('a', 'b');
  mParams := TAtlasDataFlowJson.Params(mRequest);
  try
    Assert.AreEqual('file:///c%3A/P/Haupt.pas', mParams.GetValue<string>('textDocument.uri'));
    Assert.AreEqual(4, mParams.GetValue<Integer>('position.line'));
    Assert.AreEqual(7, mParams.GetValue<Integer>('position.character'));
    Assert.AreEqual('targets', mParams.GetValue<string>('direction'));
    Assert.IsTrue(mParams.GetValue<Boolean>('excludeTests'));
    Assert.IsFalse(mParams.GetValue<Boolean>('onlyProject'));
    Assert.AreEqual(2, mParams.GetValue<TJSONArray>('path').Count);
    Assert.AreEqual('b', mParams.GetValue<TJSONArray>('path').Items[1].Value);
  finally
    mParams.Free;
  end;
  mRequest.Direction := TAtlasDataFlowDirection.Sources;
  mParams := TAtlasDataFlowJson.Params(mRequest);
  try
    Assert.AreEqual('sources', mParams.GetValue<string>('direction'));
  finally
    mParams.Free;
  end;
end;

procedure TAtlasLspDataFlowTests.ParsesNodesPlacesAndSources;
var
  mValue: TJSONValue;
  mFlow: TAtlasDataFlowResult;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    mFlow := TAtlasDataFlowJson.Parse(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mFlow.Found);
  Assert.AreEqual('Zaehler', mFlow.Symbol.Name);
  Assert.IsTrue(SameText('C:\P\Haupt.pas', mFlow.Symbol.FileName), mFlow.Symbol.FileName);
  Assert.AreEqual(6, mFlow.Symbol.Line);
  // Die Stelle ohne Fundort fällt weg.
  Assert.AreEqual(2, Integer(Length(mFlow.Nodes)));
  Assert.AreEqual<TAtlasDataFlowKind>(TAtlasDataFlowKind.Assignment, mFlow.Nodes[0].Kind);
  Assert.AreEqual('Summe', mFlow.Nodes[0].Via);
  Assert.AreEqual(2, Integer(Length(mFlow.Nodes[0].Places)));
  Assert.AreEqual(13, mFlow.Nodes[0].Places[1].Line);
  Assert.AreEqual('Zaehler := Summe(Wert);', mFlow.Nodes[0].Places[0].LineText);
  Assert.IsTrue(SameText('C:\P\Daten.pas', mFlow.Nodes[0].Sources[0].FileName));
  Assert.AreEqual<TAtlasDataFlowLeaf>(TAtlasDataFlowLeaf.None, mFlow.Nodes[0].Sources[0].Leaf);
  Assert.IsTrue(mFlow.Nodes[1].Literal);
  Assert.IsTrue(mFlow.Nodes[1].Unsafe);
  Assert.AreEqual('move', mFlow.Nodes[1].UnsafeReason);
  Assert.AreEqual<TAtlasDataFlowLeaf>(TAtlasDataFlowLeaf.Cycle, mFlow.Nodes[1].Sources[0].Leaf);
  Assert.AreEqual<TAtlasDataFlowLeaf>(TAtlasDataFlowLeaf.Constant, mFlow.Nodes[1].Sources[1].Leaf);
end;

procedure TAtlasLspDataFlowTests.NotFoundAndNull;
var
  mValue: TJSONValue;
begin
  Assert.IsFalse(TAtlasDataFlowJson.Parse(nil).Found);
  mValue := TJSONNull.Create;
  try
    Assert.IsFalse(TAtlasDataFlowJson.Parse(mValue).Found);
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue('{"found":false}');
  try
    Assert.IsFalse(TAtlasDataFlowJson.Parse(mValue).Found);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasLspDataFlowTests.UnknownKind;
begin
  Assert.AreEqual<TAtlasDataFlowKind>(TAtlasDataFlowKind.CallerArgument, TAtlasDataFlowJson.KindOf('callerArgument'));
  Assert.AreEqual<TAtlasDataFlowKind>(TAtlasDataFlowKind.Initializer, TAtlasDataFlowJson.KindOf('initialization'));
  Assert.AreEqual<TAtlasDataFlowKind>(TAtlasDataFlowKind.Unknown, TAtlasDataFlowJson.KindOf('neu'));
  Assert.AreEqual<TAtlasDataFlowKind>(TAtlasDataFlowKind.Unknown, TAtlasDataFlowJson.KindOf(''));
end;

end.
