unit Atlas.Common.Lsp.ApplyEdit.Tests;

// Tests für workspace/applyEdit an den Client (#397) und Edits über mehrere Dateien (#297).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspApplyEditTests = class
  public
    [Test]
    procedure ChecksClientCapability;
    [Test]
    procedure ReplacesWholeFile;
    [Test]
    procedure ReadsClientAnswer;
    [Test]
    procedure CreatesAndReplacesFiles;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.ApplyEdit;

function Parse(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

procedure TLspApplyEditTests.ChecksClientCapability;
var
  Params: TJSONObject;
begin
  Assert.IsFalse(TLspApplyEdit.ClientSupports(nil));
  Params := Parse('{"capabilities":{"workspace":{"applyEdit":true}}}');
  try
    Assert.IsTrue(TLspApplyEdit.ClientSupports(Params));
  finally
    Params.Free;
  end;
  Params := Parse('{"capabilities":{"workspace":{"applyEdit":false}}}');
  try
    Assert.IsFalse(TLspApplyEdit.ClientSupports(Params));
  finally
    Params.Free;
  end;
  Params := Parse('{"capabilities":{}}');
  try
    Assert.IsFalse(TLspApplyEdit.ClientSupports(Params));
  finally
    Params.Free;
  end;
end;

procedure TLspApplyEditTests.ReplacesWholeFile;
var
  Request, Changes, Edit: TJSONObject;
begin
  Request := TLspApplyEdit.Request('atlas/applyEdit/1', '/define TEST',
    TLspApplyEdit.ReplaceAll('C:\P\Haupt.dproj', '<Project>'#13#10'  <A/>'#13#10'</Project>', '<Project/>'));
  try
    Assert.AreEqual('workspace/applyEdit', Request.GetValue<string>('method'));
    Assert.AreEqual('atlas/applyEdit/1', Request.GetValue<string>('id'));
    Assert.AreEqual('/define TEST', Request.GetValue<string>('params.label'));
    Changes := Request.GetValue<TJSONObject>('params.edit.changes');
    Assert.AreEqual(1, Changes.Count);
    Assert.Contains(Changes.Pairs[0].JsonString.Value, 'Haupt.dproj');
    Edit := (Changes.Pairs[0].JsonValue as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('<Project/>', Edit.GetValue<string>('newText'));
    // Vom Anfang bis zum Ende der letzten Zeile: Zeile 2, Länge von "</Project>".
    Assert.AreEqual(0, Edit.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(0, Edit.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(2, Edit.GetValue<Integer>('range.end.line'));
    Assert.AreEqual(10, Edit.GetValue<Integer>('range.end.character'));
  finally
    Request.Free;
  end;
end;

procedure TLspApplyEditTests.CreatesAndReplacesFiles;
var
  Edit, Item: TJSONObject;
  Changes: TJSONArray;
begin
  Edit := TLspApplyEdit.Files([TLspFileChange.Create('C:\P\Neu.pas', '', 'unit Neu;', True),
    TLspFileChange.Create('C:\P\App.dproj', '<A/>'#13#10'<B/>', '<C/>', False)]);
  try
    Changes := Edit.GetValue<TJSONArray>('documentChanges');
    // Anlegen, Füllen der neuen Datei, Ersetzen der vorhandenen.
    Assert.AreEqual(3, Changes.Count);
    Item := Changes.Items[0] as TJSONObject;
    Assert.AreEqual('create', Item.GetValue<string>('kind'));
    Assert.Contains(Item.GetValue<string>('uri'), 'Neu.pas');
    Item := Changes.Items[1] as TJSONObject;
    Assert.Contains(Item.GetValue<string>('textDocument.uri'), 'Neu.pas');
    Assert.AreEqual('unit Neu;', (Item.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<string>('newText'));
    Assert.AreEqual(0, (Item.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>('range.end.line'));
    Item := Changes.Items[2] as TJSONObject;
    Assert.Contains(Item.GetValue<string>('textDocument.uri'), 'App.dproj');
    Assert.AreEqual(1, (Item.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>('range.end.line'));
    Assert.AreEqual(4, (Item.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>(
      'range.end.character'));
  finally
    Edit.Free;
  end;
end;

procedure TLspApplyEditTests.ReadsClientAnswer;

  function Read(const AJson: string; out AReason: string): Boolean;
  var
    Response: TJSONObject;
  begin
    Response := Parse(AJson);
    try
      Result := TLspApplyEdit.ReadResult(Response, AReason);
    finally
      Response.Free;
    end;
  end;

var
  Reason: string;
begin
  Assert.IsTrue(Read('{"jsonrpc":"2.0","id":"a","result":{"applied":true}}', Reason));
  Assert.AreEqual('', Reason);
  Assert.IsFalse(Read('{"jsonrpc":"2.0","id":"a","result":{"applied":false,"failureReason":"schreibgeschützt"}}',
    Reason));
  Assert.AreEqual('schreibgeschützt', Reason);
  Assert.IsFalse(Read('{"jsonrpc":"2.0","id":"a","error":{"code":-32601,"message":"unbekannt"}}', Reason));
  Assert.AreEqual('unbekannt', Reason);
  Assert.IsFalse(TLspApplyEdit.ReadResult(nil, Reason));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspApplyEditTests);

end.
