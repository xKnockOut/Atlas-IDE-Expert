unit Atlas.Common.Lsp.WatchedFiles.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspWatchedFilesTests = class
  public
    [Test]
    procedure ParsesChanges;
    [Test]
    procedure IgnoresInvalidEntries;
    [Test]
    procedure DetectsDynamicRegistration;
    [Test]
    procedure BuildsRegistration;
    [Test]
    procedure RecognizesProjectFiles;
    [Test]
    procedure BuildsNotificationForOwnWatcher;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WatchedFiles;

{ TLspWatchedFilesTests }

procedure TLspWatchedFilesTests.ParsesChanges;
var
  Params: TJSONValue;
  Changes: TArray<TFileChange>;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"changes":[{"uri":"file:///c%3A/P/A.pas","type":1},{"uri":"file:///c%3A/P/B.pas","type":2},' +
    '{"uri":"file:///c%3A/P/C.pas","type":3}]}');
  try
    Changes := TLspWatchedFiles.ParseChanges(Params);
  finally
    Params.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Changes)));
  Assert.IsTrue(SameText('C:\P\A.pas', Changes[0].FileName), Changes[0].FileName);
  Assert.IsTrue(Changes[0].Kind = TFileChangeKind.Created);
  Assert.IsTrue(Changes[1].Kind = TFileChangeKind.Changed);
  Assert.IsTrue(Changes[2].Kind = TFileChangeKind.Deleted);
end;

procedure TLspWatchedFilesTests.IgnoresInvalidEntries;
var
  Params: TJSONValue;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"changes":[{"uri":"file:///c%3A/P/A.pas","type":9},{"type":1},{"uri":"untitled:1","type":1}]}');
  try
    Assert.AreEqual(0, Integer(Length(TLspWatchedFiles.ParseChanges(Params))));
  finally
    Params.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TLspWatchedFiles.ParseChanges(nil))));
end;

procedure TLspWatchedFilesTests.DetectsDynamicRegistration;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"capabilities":{"workspace":{"didChangeWatchedFiles":{"dynamicRegistration":true}}}}') as TJSONObject;
  try
    Assert.IsTrue(TLspWatchedFiles.SupportsDynamicRegistration(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"capabilities":{}}') as TJSONObject;
  try
    Assert.IsFalse(TLspWatchedFiles.SupportsDynamicRegistration(Params));
  finally
    Params.Free;
  end;
end;

procedure TLspWatchedFilesTests.BuildsRegistration;
var
  Request: TJSONObject;
begin
  Request := TLspWatchedFiles.BuildRegistration;
  try
    Assert.AreEqual('client/registerCapability', Request.GetValue<string>('method'));
    Assert.AreEqual('workspace/didChangeWatchedFiles', Request.GetValue<string>('params.registrations[0].method'));
    Assert.AreEqual(TLspWatchedFiles.GlobPattern,
      Request.GetValue<string>('params.registrations[0].registerOptions.watchers[0].globPattern'));
  finally
    Request.Free;
  end;
end;

procedure TLspWatchedFilesTests.RecognizesProjectFiles;
begin
  Assert.IsTrue(TLspWatchedFiles.IsProjectFile('C:\P\Projekt.DPROJ'));
  Assert.IsTrue(TLspWatchedFiles.IsProjectFile('C:\P\Paket.dpk'));
  Assert.IsTrue(TLspWatchedFiles.IsProjectFile('C:\P\Gruppe.groupproj'));
  Assert.IsFalse(TLspWatchedFiles.IsProjectFile('C:\P\Unit1.pas'));
end;

procedure TLspWatchedFilesTests.BuildsNotificationForOwnWatcher;
var
  Message: TJSONObject;
  Changes: TArray<TFileChange>;
begin
  // Eigener Beobachter des Servers (#227): dieselbe Notification wie vom Client.
  Message := TLspWatchedFiles.Notification(['c:\Projekt\atlas.json', 'c:\Benutzer\settings.json']);
  try
    Assert.AreEqual(TLspWatchedFiles.Method, Message.GetValue<string>('method'));
    Assert.IsNull(Message.GetValue('id'));
    Changes := TLspWatchedFiles.ParseChanges(Message.GetValue('params'));
  finally
    Message.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Changes)));
  Assert.IsTrue(SameText('c:\Projekt\atlas.json', Changes[0].FileName), Changes[0].FileName);
  Assert.IsTrue(Changes[1].Kind = TFileChangeKind.Changed);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWatchedFilesTests);

end.
