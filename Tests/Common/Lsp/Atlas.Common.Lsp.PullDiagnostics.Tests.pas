unit Atlas.Common.Lsp.PullDiagnostics.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspPullDiagnosticsTests = class
  public
    [Test]
    procedure DetectsClientSupport;
    [Test]
    procedure OffersWorkspaceDiagnostics;
    [Test]
    procedure ReportsOpenDocumentThenUnchanged;
    [Test]
    procedure ChangeStartsNewGeneration;
    [Test]
    procedure ReportsClosedFilesInWorkspace;
    [Test]
    procedure WorkspaceSkipsKnownAndOpenFiles;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.PullDiagnostics;

const
  OpenFile = 'C:\P\Offen.pas';
  ClosedFile = 'C:\P\Zu.pas';
  // Syntaxfehler: fehlendes "then".
  Broken = 'unit Zu;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10'  if True'#10'  X;'#10'end;'#10'end.';
  Valid = 'unit Offen;'#10'interface'#10'implementation'#10'end.';

type
  TFixture = record
    Store: IDocumentStore;
    Diagnostics: TLspSyntaxDiagnostics;
    Pull: TLspPullDiagnostics;
    procedure Init;
    procedure Done;
  end;

procedure TFixture.Init;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(OpenFile), 'objectpascal', 1, Valid);
  Diagnostics := TLspSyntaxDiagnostics.Create(Store, nil, 0);
  Diagnostics.PullMode := True;
  Pull := TLspPullDiagnostics.Create(Store, Diagnostics, nil,
    function: TArray<string>
    begin
      Result := [OpenFile, ClosedFile];
    end,
    function(const AFileName: string; out AStamp: Int64): Boolean
    begin
      AStamp := 42;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := Broken;
      Result := SameText(AFileName, ClosedFile);
    end);
  Pull.WaitMs := 0;
end;

procedure TFixture.Done;
begin
  Pull.Free;
  Diagnostics.Free;
end;

function Token: IJsonRpcCancellationToken;
begin
  Result := TJsonRpcCancellation.Create;
end;

procedure TLspPullDiagnosticsTests.DetectsClientSupport;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"capabilities":{"textDocument":{"diagnostic":{}},"workspace":{"diagnostics":{"refreshSupport":true}}}}')
    as TJSONObject;
  try
    Assert.IsTrue(TLspPullDiagnostics.ClientSupportsPull(Params));
    Assert.IsTrue(TLspPullDiagnostics.ClientSupportsRefresh(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{}}}') as TJSONObject;
  try
    Assert.IsFalse(TLspPullDiagnostics.ClientSupportsPull(Params));
    Assert.IsFalse(TLspPullDiagnostics.ClientSupportsRefresh(Params));
  finally
    Params.Free;
  end;
  Assert.IsFalse(TLspPullDiagnostics.ClientSupportsPull(nil));
end;

procedure TLspPullDiagnosticsTests.OffersWorkspaceDiagnostics;
var
  Capability: TJSONObject;
begin
  Capability := TLspPullDiagnostics.Capability;
  try
    Assert.IsTrue(Capability.GetValue<Boolean>('workspaceDiagnostics'));
    Assert.IsTrue(Capability.GetValue<Boolean>('interFileDependencies'));
  finally
    Capability.Free;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsOpenDocumentThenUnchanged;
var
  Fixture: TFixture;
  Report: TJSONObject;
  ResultId: string;
begin
  Fixture.Init;
  try
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), '');
    try
      Assert.AreEqual('full', Report.GetValue<string>('kind'));
      Assert.AreEqual(0, Report.GetValue<TJSONArray>('items').Count);
      ResultId := Report.GetValue<string>('resultId');
    finally
      Report.Free;
    end;
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(OpenFile), ResultId);
    try
      Assert.AreEqual('unchanged', Report.GetValue<string>('kind'));
      Assert.IsNull(Report.GetValue('items'));
    finally
      Report.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ChangeStartsNewGeneration;
var
  Fixture: TFixture;
  Report: TJSONObject;
  ResultId: string;
begin
  Fixture.Init;
  try
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), '');
    try
      Assert.IsTrue(Report.GetValue<TJSONArray>('items').Count > 0, 'Syntaxfehler der geschlossenen Datei');
      ResultId := Report.GetValue<string>('resultId');
    finally
      Report.Free;
    end;
    Fixture.Pull.Changed;
    Report := Fixture.Pull.DocumentReport(TDocumentUris.FromPath(ClosedFile), ResultId);
    try
      Assert.AreEqual('full', Report.GetValue<string>('kind'));
    finally
      Report.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.ReportsClosedFilesInWorkspace;
var
  Fixture: TFixture;
  Result_: TJSONValue;
  Items: TJSONArray;
begin
  Fixture.Init;
  try
    Result_ := Fixture.Pull.WorkspaceReport(nil, Token);
    try
      Items := (Result_ as TJSONObject).GetValue<TJSONArray>('items');
      Assert.AreEqual(1, Items.Count, 'nur die geschlossene Datei');
      Assert.AreEqual(TDocumentUris.FromPath(ClosedFile), Items.Items[0].GetValue<string>('uri'));
      Assert.AreEqual('full', Items.Items[0].GetValue<string>('kind'));
      Assert.IsTrue(Items.Items[0].GetValue<TJSONArray>('items').Count > 0);
    finally
      Result_.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

procedure TLspPullDiagnosticsTests.WorkspaceSkipsKnownAndOpenFiles;
var
  Fixture: TFixture;
  Params, Entry: TJSONObject;
  Result_: TJSONValue;
begin
  Fixture.Init;
  try
    Entry := TJSONObject.Create;
    Entry.AddPair('uri', TDocumentUris.FromPath(ClosedFile));
    Entry.AddPair('value', Format('%d:t42', [Fixture.Pull.Generation]));
    Params := TJSONObject.Create;
    Params.AddPair('previousResultIds', TJSONArray.Create(Entry));
    try
      Result_ := Fixture.Pull.WorkspaceReport(Params, Token);
      try
        Assert.AreEqual(0, (Result_ as TJSONObject).GetValue<TJSONArray>('items').Count);
      finally
        Result_.Free;
      end;
    finally
      Params.Free;
    end;
  finally
    Fixture.Done;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspPullDiagnosticsTests);

end.
