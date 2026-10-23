unit Atlas.Core.Settings.StatusBarItems.Tests;

// Atlas-Statusleiste (#1155): Belegung editor.statusBar.items lesen und
// schreiben, Vorgabe, Bereinigen, Ein- und Ausblenden im Menü
// „Leiste anpassen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusBarItemsTests = class
  public
    [Test]
    procedure DefaultIsAllInOrder;
    [Test]
    procedure ParseKeepsKnownOnce;
    [Test]
    procedure EmptyStaysEmpty;
    [Test]
    procedure ToggleRemovesAndRestoresPlace;
    [Test]
    procedure ToggleKeepsCustomOrder;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.StatusBarItems;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(' ', AItems);
end;

procedure TAtlasStatusBarItemsTests.DefaultIsAllInOrder;
begin
  Assert.AreEqual('status,findings,liveCheck,method', TAtlasStatusBarItems.DefaultText);
  Assert.AreEqual('status findings liveCheck method', Joined(TAtlasStatusBarItems.All));
end;

procedure TAtlasStatusBarItemsTests.ParseKeepsKnownOnce;
begin
  Assert.AreEqual('method status', Joined(TAtlasStatusBarItems.Parse(' METHOD , unbekannt,,status,Method ')));
  Assert.AreEqual('liveCheck,findings', TAtlasStatusBarItems.Normalize('livecheck, findings, findings'));
  Assert.AreEqual('liveCheck', TAtlasStatusBarItems.Canonical(' LIVECHECK '));
  Assert.AreEqual('', TAtlasStatusBarItems.Canonical('gear'));
  Assert.IsTrue(TAtlasStatusBarItems.Contains(TAtlasStatusBarItems.All, 'Findings'));
  Assert.IsFalse(TAtlasStatusBarItems.Contains(nil, 'status'));
end;

procedure TAtlasStatusBarItemsTests.EmptyStaysEmpty;
begin
  Assert.AreEqual('', TAtlasStatusBarItems.Normalize(''));
  Assert.AreEqual('', TAtlasStatusBarItems.Normalize(' , ,x'));
  Assert.AreEqual(0, Integer(Length(TAtlasStatusBarItems.Parse(''))));
end;

procedure TAtlasStatusBarItemsTests.ToggleRemovesAndRestoresPlace;
var
  Items: TArray<string>;
begin
  Items := TAtlasStatusBarItems.All;
  Items := TAtlasStatusBarItems.Toggle(Items, 'findings');
  Assert.AreEqual('status liveCheck method', Joined(Items));
  Items := TAtlasStatusBarItems.Toggle(Items, 'status');
  Assert.AreEqual('liveCheck method', Joined(Items));
  Items := TAtlasStatusBarItems.Toggle(Items, 'FINDINGS');
  Assert.AreEqual('findings liveCheck method', Joined(Items), 'vor dem ersten, das in der Vorgabe nach ihm kommt');
  Items := TAtlasStatusBarItems.Toggle(Items, 'status');
  Assert.AreEqual('status findings liveCheck method', Joined(Items));
  Items := TAtlasStatusBarItems.Toggle(Items, 'unbekannt');
  Assert.AreEqual('status findings liveCheck method', Joined(Items));
  Items := TAtlasStatusBarItems.Toggle(nil, 'method');
  Assert.AreEqual('method', Joined(Items));
end;

procedure TAtlasStatusBarItemsTests.ToggleKeepsCustomOrder;
var
  Items: TArray<string>;
begin
  Items := TAtlasStatusBarItems.Parse('method,status');
  Items := TAtlasStatusBarItems.Toggle(Items, 'liveCheck');
  Assert.AreEqual('liveCheck method status', Joined(Items));
  Items := TAtlasStatusBarItems.Parse('status,method');
  Items := TAtlasStatusBarItems.Toggle(Items, 'findings');
  Assert.AreEqual('status findings method', Joined(Items));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusBarItemsTests);

end.
