unit Atlas.Core.Assistants.LinkLock.Tests;

// Assistenten-Kopplung (#2377): Ort und Inhalt der Lock-Datei, Token und Port.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasLinkLockTests = class
  public
    [Test]
    procedure FolderFollowsConfigVariable;
    [Test]
    procedure ContentHasAllFields;
    [Test]
    procedure TokenIsLowerHex;
    [Test]
    procedure PortStaysInRange;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Assistants.LinkLock;

procedure TAtlasLinkLockTests.FolderFollowsConfigVariable;
begin
  Assert.AreEqual('Home' + PathDelim + '.claude' + PathDelim + 'ide', TAtlasLinkLock.Folder('Home', ''));
  Assert.AreEqual('Konfig' + PathDelim + 'ide', TAtlasLinkLock.Folder('Home', 'Konfig'));
  Assert.AreEqual('Ordner' + PathDelim + '12345.lock', TAtlasLinkLock.FileName('Ordner', 12345));
end;

procedure TAtlasLinkLockTests.ContentHasAllFields;
var
  mRoot: TJSONObject;
begin
  mRoot := TJsonRead.ParseObject(TAtlasLinkLock.Content(4711, ['C:\Projekte\Kunde', 'C:\Projekte\Lib'],
    TAtlasLinkLock.IdeName('13'), 'abc'));
  try
    Assert.IsNotNull(mRoot);
    Assert.AreEqual(4711, TJsonRead.Int(mRoot, 'pid'));
    Assert.AreEqual(2, Integer(Length(TJsonRead.Strings(mRoot, 'workspaceFolders'))));
    Assert.AreEqual('C:\Projekte\Kunde', TJsonRead.Strings(mRoot, 'workspaceFolders')[0]);
    Assert.AreEqual('RAD Studio 13 (Atlas)', TJsonRead.Text(mRoot, 'ideName'));
    Assert.AreEqual('ws', TJsonRead.Text(mRoot, 'transport'));
    Assert.AreEqual('abc', TJsonRead.Text(mRoot, 'authToken'));
  finally
    mRoot.Free;
  end;
  Assert.AreEqual('RAD Studio (Atlas)', TAtlasLinkLock.IdeName(''));
end;

procedure TAtlasLinkLockTests.TokenIsLowerHex;
var
  mBytes: TBytes;
begin
  mBytes := TBytes.Create($00, $AB, $FF, $10);
  Assert.AreEqual('00abff10', TAtlasLinkLock.TokenOf(mBytes));
  SetLength(mBytes, TAtlasLinkLock.cTokenBytes);
  Assert.AreEqual(32, Length(TAtlasLinkLock.TokenOf(mBytes)));
end;

procedure TAtlasLinkLockTests.PortStaysInRange;
begin
  Assert.AreEqual(TAtlasLinkLock.cMinPort, TAtlasLinkLock.PortOf(0));
  Assert.AreEqual(TAtlasLinkLock.cMaxPort, TAtlasLinkLock.PortOf(TAtlasLinkLock.cMaxPort - TAtlasLinkLock.cMinPort));
  Assert.AreEqual(TAtlasLinkLock.cMinPort, TAtlasLinkLock.PortOf(TAtlasLinkLock.cMaxPort - TAtlasLinkLock.cMinPort +
    1));
  Assert.IsTrue(TAtlasLinkLock.PortOf(High(Cardinal)) <= TAtlasLinkLock.cMaxPort);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkLockTests);

end.
