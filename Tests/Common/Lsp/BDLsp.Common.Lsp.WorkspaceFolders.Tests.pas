unit BDLsp.Common.Lsp.WorkspaceFolders.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspWorkspaceFoldersTests = class
  public
    [Test]
    procedure ReadsFoldersFromInitialize;
    [Test]
    procedure FallsBackToRootUri;
    [Test]
    procedure ParsesAddedAndRemoved;
    [Test]
    procedure FindsInnermostFolder;
    [Test]
    procedure WritesCapability;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Lsp.WorkspaceFolders;

function ParseObject(const AText: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AText) as TJSONObject;
end;

{ TLspWorkspaceFoldersTests }

procedure TLspWorkspaceFoldersTests.ReadsFoldersFromInitialize;
var
  Params: TJSONObject;
  Folders: TArray<TWorkspaceFolder>;
begin
  Params := ParseObject('{"rootUri": "file:///c%3A/Alt", "workspaceFolders": [' +
    '{"uri": "file:///c%3A/App", "name": "App"}, {"uri": "file:///d%3A/Lib"}]}');
  try
    Folders := TLspWorkspaceFolders.FromInitialize(Params);
  finally
    Params.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Folders)));
  Assert.IsTrue(SameText('C:\App', Folders[0].Path), Folders[0].Path);
  Assert.AreEqual('App', Folders[0].Name);
  Assert.AreEqual('Lib', Folders[1].Name);
end;

procedure TLspWorkspaceFoldersTests.FallsBackToRootUri;
var
  Params: TJSONObject;
  Folders: TArray<TWorkspaceFolder>;
begin
  Params := ParseObject('{"rootUri": "file:///c%3A/Projekt", "workspaceFolders": null}');
  try
    Folders := TLspWorkspaceFolders.FromInitialize(Params);
  finally
    Params.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Folders)));
  Assert.IsTrue(SameText('C:\Projekt', Folders[0].Path), Folders[0].Path);
  Assert.AreEqual(0, Integer(Length(TLspWorkspaceFolders.FromInitialize(nil))));
end;

procedure TLspWorkspaceFoldersTests.ParsesAddedAndRemoved;
var
  Params: TJSONObject;
  Added, Removed: TArray<TWorkspaceFolder>;
begin
  Params := ParseObject('{"event": {"added": [{"uri": "file:///c%3A/Neu", "name": "Neu"}], ' +
    '"removed": [{"uri": "file:///c%3A/Alt", "name": "Alt"}]}}');
  try
    TLspWorkspaceFolders.ParseChange(Params, Added, Removed);
  finally
    Params.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Added)));
  Assert.AreEqual('Neu', Added[0].Name);
  Assert.AreEqual(1, Integer(Length(Removed)));
  Assert.AreEqual('Alt', Removed[0].Name);
end;

procedure TLspWorkspaceFoldersTests.FindsInnermostFolder;
var
  Folders: TArray<TWorkspaceFolder>;
begin
  Folders := [TWorkspaceFolder.Create('C:\Repo', 'Repo'), TWorkspaceFolder.Create('C:\Repo\Lib\', 'Lib'),
    TWorkspaceFolder.Create('C:\Repo2', 'Repo2')];
  Assert.AreEqual(0, TLspWorkspaceFolders.FolderOf(Folders, 'c:\repo\App\Main.pas'));
  Assert.AreEqual(1, TLspWorkspaceFolders.FolderOf(Folders, 'C:\Repo\Lib\Werkzeug.pas'));
  Assert.AreEqual(2, TLspWorkspaceFolders.FolderOf(Folders, 'C:/Repo2/X.pas'));
  Assert.AreEqual(-1, TLspWorkspaceFolders.FolderOf(Folders, 'D:\Anders\Y.pas'));
end;

procedure TLspWorkspaceFoldersTests.WritesCapability;
var
  Capability: TJSONObject;
begin
  Capability := TLspWorkspaceFolders.Capability;
  try
    Assert.IsTrue(Capability.GetValue<Boolean>('workspaceFolders.supported'));
    Assert.IsTrue(Capability.GetValue<Boolean>('workspaceFolders.changeNotifications'));
  finally
    Capability.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkspaceFoldersTests);

end.
