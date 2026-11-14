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
  mItems: TArray<string>;
begin
  mItems := TAtlasStatusBarItems.All;
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'findings');
  Assert.AreEqual('status liveCheck method', Joined(mItems));
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'status');
  Assert.AreEqual('liveCheck method', Joined(mItems));
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'FINDINGS');
  Assert.AreEqual('findings liveCheck method', Joined(mItems), 'vor dem ersten, das in der Vorgabe nach ihm kommt');
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'status');
  Assert.AreEqual('status findings liveCheck method', Joined(mItems));
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'unbekannt');
  Assert.AreEqual('status findings liveCheck method', Joined(mItems));
  mItems := TAtlasStatusBarItems.Toggle(nil, 'method');
  Assert.AreEqual('method', Joined(mItems));
end;

procedure TAtlasStatusBarItemsTests.ToggleKeepsCustomOrder;
var
  mItems: TArray<string>;
begin
  mItems := TAtlasStatusBarItems.Parse('method,status');
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'liveCheck');
  Assert.AreEqual('liveCheck method status', Joined(mItems));
  mItems := TAtlasStatusBarItems.Parse('status,method');
  mItems := TAtlasStatusBarItems.Toggle(mItems, 'findings');
  Assert.AreEqual('status findings method', Joined(mItems));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusBarItemsTests);

end.
