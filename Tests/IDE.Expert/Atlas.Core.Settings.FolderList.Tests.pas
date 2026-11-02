unit Atlas.Core.Settings.FolderList.Tests;

// Tests der Ordnerliste als Einstellungswert (#1455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFolderListTests = class
  public
    [Test]
    procedure ParseCleansList;
    [Test]
    procedure NormalKeepsRoot;
  end;

implementation

uses
  Atlas.Core.Settings.FolderList;

procedure TAtlasFolderListTests.ParseCleansList;
var
  mFolders: TArray<string>;
begin
  mFolders := TAtlasFolderList.Parse('C:\Komponenten\; ;c:\komponenten' + #13#10 + 'D:/Lib/ ;');
  Assert.AreEqual(2, Integer(Length(mFolders)));
  Assert.AreEqual('C:\Komponenten', mFolders[0]);
  Assert.AreEqual('D:\Lib', mFolders[1], 'Schrägstrich vereinheitlicht');
  Assert.AreEqual('C:\Komponenten;D:\Lib', TAtlasFolderList.Text('C:\Komponenten\;D:/Lib/;c:\KOMPONENTEN'));
  Assert.AreEqual(0, Integer(Length(TAtlasFolderList.Parse(''))));
end;

procedure TAtlasFolderListTests.NormalKeepsRoot;
begin
  Assert.AreEqual('\', TAtlasFolderList.Normal(' \\ '));
  Assert.AreEqual('', TAtlasFolderList.Normal('  '));
end;

end.
