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
  mParams: TJSONObject;
begin
  Assert.IsFalse(TLspApplyEdit.ClientSupports(nil));
  mParams := Parse('{"capabilities":{"workspace":{"applyEdit":true}}}');
  try
    Assert.IsTrue(TLspApplyEdit.ClientSupports(mParams));
  finally
    mParams.Free;
  end;
  mParams := Parse('{"capabilities":{"workspace":{"applyEdit":false}}}');
  try
    Assert.IsFalse(TLspApplyEdit.ClientSupports(mParams));
  finally
    mParams.Free;
  end;
  mParams := Parse('{"capabilities":{}}');
  try
    Assert.IsFalse(TLspApplyEdit.ClientSupports(mParams));
  finally
    mParams.Free;
  end;
end;

procedure TLspApplyEditTests.ReplacesWholeFile;
var
  mRequest, mChanges, mEdit: TJSONObject;
begin
  mRequest := TLspApplyEdit.Request('atlas/applyEdit/1', '/define TEST',
    TLspApplyEdit.ReplaceAll('C:\P\Haupt.dproj', '<Project>'#13#10'  <A/>'#13#10'</Project>', '<Project/>'));
  try
    Assert.AreEqual('workspace/applyEdit', mRequest.GetValue<string>('method'));
    Assert.AreEqual('atlas/applyEdit/1', mRequest.GetValue<string>('id'));
    Assert.AreEqual('/define TEST', mRequest.GetValue<string>('params.label'));
    mChanges := mRequest.GetValue<TJSONObject>('params.edit.changes');
    Assert.AreEqual(1, Integer(mChanges.Count));
    Assert.Contains(mChanges.Pairs[0].JsonString.Value, 'Haupt.dproj');
    mEdit := (mChanges.Pairs[0].JsonValue as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('<Project/>', mEdit.GetValue<string>('newText'));
    // Vom Anfang bis zum Ende der letzten Zeile: Zeile 2, Länge von "</Project>".
    Assert.AreEqual(0, mEdit.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(0, mEdit.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(2, mEdit.GetValue<Integer>('range.end.line'));
    Assert.AreEqual(10, mEdit.GetValue<Integer>('range.end.character'));
  finally
    mRequest.Free;
  end;
end;

procedure TLspApplyEditTests.CreatesAndReplacesFiles;
var
  mEdit, mItem: TJSONObject;
  mChanges: TJSONArray;
begin
  mEdit := TLspApplyEdit.Files([TLspFileChange.Create('C:\P\Neu.pas', '', 'unit Neu;', True),
    TLspFileChange.Create('C:\P\App.dproj', '<A/>'#13#10'<B/>', '<C/>', False)]);
  try
    mChanges := mEdit.GetValue<TJSONArray>('documentChanges');
    // Anlegen, Füllen der neuen Datei, Ersetzen der vorhandenen.
    Assert.AreEqual(3, Integer(mChanges.Count));
    mItem := mChanges.Items[0] as TJSONObject;
    Assert.AreEqual('create', mItem.GetValue<string>('kind'));
    Assert.Contains(mItem.GetValue<string>('uri'), 'Neu.pas');
    mItem := mChanges.Items[1] as TJSONObject;
    Assert.Contains(mItem.GetValue<string>('textDocument.uri'), 'Neu.pas');
    Assert.AreEqual('unit Neu;', (mItem.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<string>('newText'));
    Assert.AreEqual(0, (mItem.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>('range.end.line'));
    mItem := mChanges.Items[2] as TJSONObject;
    Assert.Contains(mItem.GetValue<string>('textDocument.uri'), 'App.dproj');
    Assert.AreEqual(1, (mItem.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>('range.end.line'));
    Assert.AreEqual(4, (mItem.GetValue<TJSONArray>('edits').Items[0] as TJSONObject).GetValue<Integer>(
      'range.end.character'));
  finally
    mEdit.Free;
  end;
end;

procedure TLspApplyEditTests.ReadsClientAnswer;

  function Read(const AJson: string; out AReason: string): Boolean;
  var
    mResponse: TJSONObject;
  begin
    mResponse := Parse(AJson);
    try
      Result := TLspApplyEdit.ReadResult(mResponse, AReason);
    finally
      mResponse.Free;
    end;
  end;

var
  mReason: string;
begin
  Assert.IsTrue(Read('{"jsonrpc":"2.0","id":"a","result":{"applied":true}}', mReason));
  Assert.AreEqual('', mReason);
  Assert.IsFalse(Read('{"jsonrpc":"2.0","id":"a","result":{"applied":false,"failureReason":"schreibgeschützt"}}',
    mReason));
  Assert.AreEqual('schreibgeschützt', mReason);
  Assert.IsFalse(Read('{"jsonrpc":"2.0","id":"a","error":{"code":-32601,"message":"unbekannt"}}', mReason));
  Assert.AreEqual('unbekannt', mReason);
  Assert.IsFalse(TLspApplyEdit.ReadResult(nil, mReason));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspApplyEditTests);

end.
