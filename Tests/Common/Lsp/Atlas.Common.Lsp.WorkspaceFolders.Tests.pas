unit Atlas.Common.Lsp.WorkspaceFolders.Tests;

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
    [Test]
    procedure IgnoresDriveRoots;
    [Test]
    procedure FindsNearestProjectFolder;
    [Test]
    procedure ReadsProjectFileEntries;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.WorkspaceFolders;

function ParseObject(const AText: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AText) as TJSONObject;
end;

{ TLspWorkspaceFoldersTests }

procedure TLspWorkspaceFoldersTests.ReadsFoldersFromInitialize;
var
  mParams: TJSONObject;
  mFolders: TArray<TWorkspaceFolder>;
begin
  mParams := ParseObject('{"rootUri": "file:///c%3A/Alt", "workspaceFolders": [' +
    '{"uri": "file:///c%3A/App", "name": "App"}, {"uri": "file:///d%3A/Lib"}]}');
  try
    mFolders := TLspWorkspaceFolders.FromInitialize(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mFolders)));
  Assert.IsTrue(SameText('C:\App', mFolders[0].Path), mFolders[0].Path);
  Assert.AreEqual('App', mFolders[0].Name);
  Assert.AreEqual('Lib', mFolders[1].Name);
end;

procedure TLspWorkspaceFoldersTests.FallsBackToRootUri;
var
  mParams: TJSONObject;
  mFolders: TArray<TWorkspaceFolder>;
begin
  mParams := ParseObject('{"rootUri": "file:///c%3A/Projekt", "workspaceFolders": null}');
  try
    mFolders := TLspWorkspaceFolders.FromInitialize(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFolders)));
  Assert.IsTrue(SameText('C:\Projekt', mFolders[0].Path), mFolders[0].Path);
  Assert.AreEqual(0, Integer(Length(TLspWorkspaceFolders.FromInitialize(nil))));
end;

procedure TLspWorkspaceFoldersTests.ParsesAddedAndRemoved;
var
  mParams: TJSONObject;
  mAdded, mRemoved: TArray<TWorkspaceFolder>;
begin
  mParams := ParseObject('{"event": {"added": [{"uri": "file:///c%3A/Neu", "name": "Neu"}], ' +
    '"removed": [{"uri": "file:///c%3A/Alt", "name": "Alt"}]}}');
  try
    TLspWorkspaceFolders.ParseChange(mParams, mAdded, mRemoved);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mAdded)));
  Assert.AreEqual('Neu', mAdded[0].Name);
  Assert.AreEqual(1, Integer(Length(mRemoved)));
  Assert.AreEqual('Alt', mRemoved[0].Name);
end;

procedure TLspWorkspaceFoldersTests.FindsInnermostFolder;
var
  mFolders: TArray<TWorkspaceFolder>;
begin
  mFolders := [TWorkspaceFolder.Create('C:\Repo', 'Repo'), TWorkspaceFolder.Create('C:\Repo\Lib\', 'Lib'),
    TWorkspaceFolder.Create('C:\Repo2', 'Repo2')];
  Assert.AreEqual(0, TLspWorkspaceFolders.FolderOf(mFolders, 'c:\repo\App\Main.pas'));
  Assert.AreEqual(1, TLspWorkspaceFolders.FolderOf(mFolders, 'C:\Repo\Lib\Werkzeug.pas'));
  Assert.AreEqual(2, TLspWorkspaceFolders.FolderOf(mFolders, 'C:/Repo2/X.pas'));
  Assert.AreEqual(-1, TLspWorkspaceFolders.FolderOf(mFolders, 'D:\Anders\Y.pas'));
end;

procedure TLspWorkspaceFoldersTests.WritesCapability;
var
  mCapability: TJSONObject;
begin
  mCapability := TLspWorkspaceFolders.Capability;
  try
    Assert.IsTrue(mCapability.GetValue<Boolean>('workspaceFolders.supported'));
    Assert.IsTrue(mCapability.GetValue<Boolean>('workspaceFolders.changeNotifications'));
  finally
    mCapability.Free;
  end;
end;

procedure TLspWorkspaceFoldersTests.IgnoresDriveRoots;
var
  mParams: TJSONObject;
begin
  // So meldet sich RAD Studio: rootUri ohne Pfad, keine workspaceFolders.
  mParams := ParseObject('{"rootUri": "file:///", "workspaceFolders": [{"uri": "file:///c%3A/"}]}');
  try
    Assert.AreEqual(0, Integer(Length(TLspWorkspaceFolders.FromInitialize(mParams))));
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TLspWorkspaceFolders.IsUsableRoot(''));
  Assert.IsFalse(TLspWorkspaceFolders.IsUsableRoot('/'));
  Assert.IsFalse(TLspWorkspaceFolders.IsUsableRoot('C:'));
  Assert.IsFalse(TLspWorkspaceFolders.IsUsableRoot('C:\'));
  Assert.IsTrue(TLspWorkspaceFolders.IsUsableRoot('C:\Projekte'));
end;

procedure TLspWorkspaceFoldersTests.FindsNearestProjectFolder;
var
  mAsked: string;
begin
  mAsked := '';
  Assert.AreEqual('C:\Projekte\App', TLspWorkspaceFolders.ProjectFolderFor('C:\Projekte\App\Source\Main.pas',
    function(const AFolder: string): Boolean
    begin
      mAsked := mAsked + AFolder + ';';
      Result := SameText(AFolder, 'C:\Projekte\App') or SameText(AFolder, 'C:\Projekte');
    end));
  Assert.AreEqual('C:\Projekte\App\Source;C:\Projekte\App;', mAsked);
  // Ohne Projektdatei: aufwärts bis vor die Laufwerkswurzel, dann ''.
  mAsked := '';
  Assert.AreEqual('', TLspWorkspaceFolders.ProjectFolderFor('C:\Lose\Datei.pas',
    function(const AFolder: string): Boolean
    begin
      mAsked := mAsked + AFolder + ';';
      Result := False;
    end));
  Assert.AreEqual('C:\Lose;', mAsked);
end;

procedure TLspWorkspaceFoldersTests.ReadsProjectFileEntries;
var
  mParams: TJSONObject;
  mFolders: TArray<TWorkspaceFolder>;
begin
  // Das IDE-Plugin meldet die Projekte der Gruppe als Projektdateien (#648).
  mParams := ParseObject('{"workspaceFolders": [' +
    '{"uri": "file:///c%3A/Gruppe/App/App.dproj", "name": "App"}, ' +
    '{"uri": "file:///c%3A/Gruppe/App/Tool.dproj"}, ' +
    '{"uri": "file:///c%3A/Gruppe/Gruppe.groupproj"}, ' +
    '{"uri": "file:///c%3A/Gruppe/Lib"}]}');
  try
    mFolders := TLspWorkspaceFolders.FromInitialize(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(4, Integer(Length(mFolders)));
  Assert.IsTrue(SameText('C:\Gruppe\App', mFolders[0].Path), mFolders[0].Path);
  Assert.IsTrue(SameText('C:\Gruppe\App\App.dproj', mFolders[0].ProjectFile), mFolders[0].ProjectFile);
  Assert.AreEqual('App', mFolders[0].Name);
  // Zwei Projekte im selben Ordner bleiben getrennt: Der Schlüssel ist die Projektdatei.
  Assert.AreEqual('Tool', mFolders[1].Name);
  Assert.AreNotEqual(mFolders[0].Key, mFolders[1].Key);
  Assert.IsTrue(SameText('C:\Gruppe\Gruppe.groupproj', mFolders[2].ProjectFile), mFolders[2].ProjectFile);
  Assert.AreEqual('', mFolders[3].ProjectFile);
  Assert.AreEqual(TWorkspaceFolder.Create('C:\Gruppe\Lib\', '').Key, mFolders[3].Key);
  Assert.IsTrue(TLspWorkspaceFolders.IsProjectFile('C:\X\A.DPROJ'));
  Assert.IsFalse(TLspWorkspaceFolders.IsProjectFile('C:\X\A.dpr'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkspaceFoldersTests);

end.
