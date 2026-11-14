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
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WatchedFiles;

{ TLspWatchedFilesTests }

procedure TLspWatchedFilesTests.ParsesChanges;
var
  mParams: TJSONValue;
  mChanges: TArray<TFileChange>;
begin
  mParams := TJSONObject.ParseJSONValue(
    '{"changes":[{"uri":"file:///c%3A/P/A.pas","type":1},{"uri":"file:///c%3A/P/B.pas","type":2},' +
    '{"uri":"file:///c%3A/P/C.pas","type":3}]}');
  try
    mChanges := TLspWatchedFiles.ParseChanges(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mChanges)));
  Assert.IsTrue(SameText('C:\P\A.pas', mChanges[0].FileName), mChanges[0].FileName);
  Assert.AreEqual<TFileChangeKind>(TFileChangeKind.Created, mChanges[0].Kind);
  Assert.AreEqual<TFileChangeKind>(TFileChangeKind.Changed, mChanges[1].Kind);
  Assert.AreEqual<TFileChangeKind>(TFileChangeKind.Deleted, mChanges[2].Kind);
end;

procedure TLspWatchedFilesTests.IgnoresInvalidEntries;
var
  mParams: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue(
    '{"changes":[{"uri":"file:///c%3A/P/A.pas","type":9},{"type":1},{"uri":"untitled:1","type":1}]}');
  try
    Assert.AreEqual(0, Integer(Length(TLspWatchedFiles.ParseChanges(mParams))));
  finally
    mParams.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TLspWatchedFiles.ParseChanges(nil))));
end;

procedure TLspWatchedFilesTests.DetectsDynamicRegistration;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue(
    '{"capabilities":{"workspace":{"didChangeWatchedFiles":{"dynamicRegistration":true}}}}') as TJSONObject;
  try
    Assert.IsTrue(TLspWatchedFiles.SupportsDynamicRegistration(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"capabilities":{}}') as TJSONObject;
  try
    Assert.IsFalse(TLspWatchedFiles.SupportsDynamicRegistration(mParams));
  finally
    mParams.Free;
  end;
end;

procedure TLspWatchedFilesTests.BuildsRegistration;
var
  mRequest: TJSONObject;
begin
  mRequest := TLspWatchedFiles.BuildRegistration;
  try
    Assert.AreEqual('client/registerCapability', mRequest.GetValue<string>('method'));
    Assert.AreEqual('workspace/didChangeWatchedFiles', mRequest.GetValue<string>('params.registrations[0].method'));
    Assert.AreEqual(TLspWatchedFiles.cGlobPattern,
      mRequest.GetValue<string>('params.registrations[0].registerOptions.watchers[0].globPattern'));
  finally
    mRequest.Free;
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
  mMessage: TJSONObject;
  mChanges: TArray<TFileChange>;
begin
  // Eigener Beobachter des Servers (#227): dieselbe Notification wie vom Client.
  mMessage := TLspWatchedFiles.Notification(['c:\Projekt\atlas.json', 'c:\Benutzer\settings.json']);
  try
    Assert.AreEqual(TLspWatchedFiles.cMethod, mMessage.GetValue<string>('method'));
    Assert.IsNull(mMessage.GetValue('id'));
    mChanges := TLspWatchedFiles.ParseChanges(mMessage.GetValue('params'));
  finally
    mMessage.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mChanges)));
  Assert.IsTrue(SameText('c:\Projekt\atlas.json', mChanges[0].FileName), mChanges[0].FileName);
  Assert.AreEqual<TFileChangeKind>(TFileChangeKind.Changed, mChanges[1].Kind);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWatchedFilesTests);

end.
