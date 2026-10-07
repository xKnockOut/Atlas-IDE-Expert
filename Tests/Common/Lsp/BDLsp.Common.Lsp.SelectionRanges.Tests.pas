unit BDLsp.Common.Lsp.SelectionRanges.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSelectionRangesTests = class
  public
    [Test]
    procedure ExpandsFromIdentifierToFile;
    [Test]
    procedure PrefersIdentifierBeforeSemicolon;
    [Test]
    procedure ExpandsInsideClass;
    [Test]
    procedure ReturnsNothingOutsideCode;
    [Test]
    procedure WritesParentChain;
    [Test]
    procedure HandlesRequestThroughDispatcher;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Lsp.SelectionRanges;

const
  Code: array[0..11] of string = (
    'unit U;',
    'interface',
    'type',
    '  TFoo = class',
    '    procedure A;',
    '  end;',
    'implementation',
    'procedure TFoo.A;',
    'begin',
    '  X := Y + Z;',
    'end;',
    'end.');

// Bereiche an der Stelle von "|" im Text, z. B. "9:7-9:8 9:7-9:12".
function Describe(const ALines: array of string): string;
var
  Text: string;
  Offset: Integer;
  Tree: TSyntaxTree;
  Range: TTextRange;
begin
  Text := string.Join(#13#10, ALines);
  Offset := Text.IndexOf('|');
  Text := Text.Remove(Offset, 1);
  Result := '';
  Tree := TPascalParser.Parse(Text);
  try
    for Range in TLspSelectionRanges.RangesAt(Tree, Offset) do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%d-%d:%d',
        [Range.StartPos.Line, Range.StartPos.Character, Range.EndPos.Line, Range.EndPos.Character]);
    end;
  finally
    Tree.Free;
  end;
end;

function WithMarker(ALine: Integer; const ANewText: string): TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Code));
  for Index := 0 to High(Code) do
    Result[Index] := Code[Index];
  Result[ALine] := ANewText;
end;

{ TLspSelectionRangesTests }

procedure TLspSelectionRangesTests.ExpandsFromIdentifierToFile;
begin
  // Bezeichner → Ausdruck → Anweisung → begin/end → Methode → implementation → Datei.
  Assert.AreEqual('9:7-9:8 9:7-9:12 9:2-9:12 8:0-10:3 7:0-10:4 6:0-10:4 0:0-11:4',
    Describe(WithMarker(9, '  X := |Y + Z;')));
end;

procedure TLspSelectionRangesTests.PrefersIdentifierBeforeSemicolon;
begin
  Assert.AreEqual('9:11-9:12 9:7-9:12 9:2-9:12 8:0-10:3 7:0-10:4 6:0-10:4 0:0-11:4',
    Describe(WithMarker(9, '  X := Y + Z|;')));
end;

procedure TLspSelectionRangesTests.ExpandsInsideClass;
begin
  // Methodenname → Kopf → Klasse → Typdeklaration → type-Abschnitt → interface → Datei.
  Assert.AreEqual('4:14-4:15 4:4-4:16 3:9-5:5 3:2-5:6 2:0-5:6 1:0-5:6 0:0-11:4',
    Describe(WithMarker(4, '    procedure |A;')));
end;

procedure TLspSelectionRangesTests.ReturnsNothingOutsideCode;
begin
  Assert.AreEqual('', Describe(['|', 'unit U; interface implementation end.']));
end;

procedure TLspSelectionRangesTests.WritesParentChain;
var
  Json: TJSONObject;
begin
  Json := TLspSelectionRanges.ToJson([TTextRange.Create(0, 1, 0, 2), TTextRange.Create(0, 0, 1, 0)]);
  try
    Assert.AreEqual(1, Json.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(1, Json.GetValue<Integer>('parent.range.end.line'));
    Assert.IsNull(Json.GetValue<TJSONObject>('parent').GetValue('parent'));
  finally
    Json.Free;
  end;
end;

procedure TLspSelectionRangesTests.HandlesRequestThroughDispatcher;
var
  Store: IDocumentStore;
  Feature: TLspSelectionRanges;
  Dispatcher: TJsonRpcDispatcher;
  Request: TJSONObject;
  Response: TJSONObject;
begin
  Store := TDocumentStore.Create;
  Store.Open('file:///u.pas', 'objectpascal', 1, string.Join(#13#10, Code));
  Dispatcher := TJsonRpcDispatcher.Create;
  Feature := TLspSelectionRanges.Create(Store);
  try
    Feature.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/selectionRange","params":{' +
      '"textDocument":{"uri":"file:///u.pas"},' +
      '"positions":[{"line":9,"character":7},{"line":20,"character":0}]}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Assert.AreEqual(2, Response.GetValue<TJSONArray>('result').Count);
        Assert.AreEqual(8, Response.GetValue<Integer>('result[0].range.end.character'));
        Assert.AreEqual(12, Response.GetValue<Integer>('result[0].parent.range.end.character'));
        // Hinter dem Dokumentende zählt das letzte Token.
        Assert.AreEqual(11, Response.GetValue<Integer>('result[1].range.start.line'));
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  finally
    Feature.Free;
    Dispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSelectionRangesTests);

end.
