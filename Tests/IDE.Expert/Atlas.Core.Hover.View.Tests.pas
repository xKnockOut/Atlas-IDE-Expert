unit Atlas.Core.Hover.View.Tests;

// Inhalt des Hover-Tooltips (Atlas.Core.Hover.View): Vorgaben und Schalter der published-Mitglieder (#110).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverViewTests = class
  public
    [Test]
    procedure CreateKeepsDataAndUnknownUsages;
    [Test]
    procedure ToggleFlipsOnlyItsSwitch;
  end;

implementation

uses
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.View;

procedure THoverViewTests.CreateKeepsDataAndUnknownUsages;
var
  mData: TAtlasHoverData;
  mView: TAtlasHoverView;
begin
  mData := Default(TAtlasHoverData);
  mData.UnitName := 'Vcl.Forms';
  mView := TAtlasHoverView.Create(mData);
  Assert.AreEqual('Vcl.Forms', mView.Data.UnitName);
  Assert.AreEqual(-1, mView.UsagesCount);
  Assert.AreEqual(0, Integer(Length(mView.Problems)));
  Assert.AreEqual(0, Integer(Length(mView.Explanations)));
end;

procedure THoverViewTests.ToggleFlipsOnlyItsSwitch;
var
  mView: TAtlasHoverView;
begin
  mView := TAtlasHoverView.Create(Default(TAtlasHoverData));
  mView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  Assert.IsTrue(mView.HideInherited);
  Assert.IsFalse(mView.OnlyDefaults);
  mView.Toggle(TAtlasHoverPublishedToggle.MoreEvents);
  Assert.IsTrue(mView.AllEvents);
  Assert.IsFalse(mView.AllProperties);
  mView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  Assert.IsFalse(mView.HideInherited);
end;

initialization
  TDUnitX.RegisterTestFixture(THoverViewTests);

end.
