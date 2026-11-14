unit Atlas.Common.Lsp.SelectionRanges.Tests;

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
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.SelectionRanges;

const
  cCode: array[0..11] of string = (
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
  mText: string;
  mOffset: Integer;
  mTree: TSyntaxTree;
  mRange: TTextRange;
begin
  mText := string.Join(#13#10, ALines);
  mOffset := mText.IndexOf('|');
  mText := mText.Remove(mOffset, 1);
  Result := '';
  mTree := TPascalParser.Parse(mText);
  try
    for mRange in TLspSelectionRanges.RangesAt(mTree, mOffset) do
    begin
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + Format('%d:%d-%d:%d',
        [mRange.StartPos.Line, mRange.StartPos.Character, mRange.EndPos.Line, mRange.EndPos.Character]);
    end;
  finally
    mTree.Free;
  end;
end;

function WithMarker(ALine: Integer; const ANewText: string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cCode));
  for mIndex := 0 to High(cCode) do
  begin
    Result[mIndex] := cCode[mIndex];
  end;
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
  mJson: TJSONObject;
begin
  mJson := TLspSelectionRanges.ToJson([TTextRange.Create(0, 1, 0, 2), TTextRange.Create(0, 0, 1, 0)]);
  try
    Assert.AreEqual(1, mJson.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(1, mJson.GetValue<Integer>('parent.range.end.line'));
    Assert.IsNull(mJson.GetValue<TJSONObject>('parent').GetValue('parent'));
  finally
    mJson.Free;
  end;
end;

procedure TLspSelectionRangesTests.HandlesRequestThroughDispatcher;
var
  mStore: IDocumentStore;
  mFeature: TLspSelectionRanges;
  mDispatcher: TJsonRpcDispatcher;
  mRequest: TJSONObject;
  mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mStore.Open('file:///u.pas', 'objectpascal', 1, string.Join(#13#10, cCode));
  mDispatcher := TJsonRpcDispatcher.Create;
  mFeature := TLspSelectionRanges.Create(mStore);
  try
    mFeature.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/selectionRange","params":{' +
      '"textDocument":{"uri":"file:///u.pas"},' +
      '"positions":[{"line":9,"character":7},{"line":20,"character":0}]}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        Assert.AreEqual(2, mResponse.GetValue<TJSONArray>('result').Count);
        Assert.AreEqual(8, mResponse.GetValue<Integer>('result[0].range.end.character'));
        Assert.AreEqual(12, mResponse.GetValue<Integer>('result[0].parent.range.end.character'));
        // Hinter dem Dokumentende zählt das letzte Token.
        Assert.AreEqual(11, mResponse.GetValue<Integer>('result[1].range.start.line'));
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  finally
    mFeature.Free;
    mDispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSelectionRangesTests);

end.
