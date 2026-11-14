unit Atlas.Core.EditorToolbar.Layout.Tests;

// Atlas-Editorleiste (#1101): Überlauf-Layout. Alles passt ohne »; sonst
// Platz für », vordere Knöpfe bleiben, ab dem ersten zu breiten alles ins
// Menü, angeheftete Abschnittssymbole bleiben immer; Trennstriche nie am Rand
// oder doppelt, weder in der Leiste noch im Menü.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasToolbarLayoutTests = class
  public
    [Test]
    procedure EverythingFits;
    [Test]
    procedure TailGoesToOverflow;
    [Test]
    procedure PinnedStayEvenWhenNarrow;
    [Test]
    procedure KeepsOrderInOverflow;
    [Test]
    procedure SeparatorsOnlyBetweenButtons;
    [Test]
    procedure EmptyToolbar;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.EditorToolbar.Layout;

const
  cButton = 24;
  cLine = 9;
  cMore = 24;

function B(APinned: Boolean): TAtlasToolbarSlot; overload;
begin
  Result := TAtlasToolbarSlot.Create(cButton, False, APinned);
end;

function B: TAtlasToolbarSlot; overload;
begin
  Result := B(False);
end;

function S: TAtlasToolbarSlot;
begin
  Result := TAtlasToolbarSlot.Create(cLine, True, False);
end;

function Shown(const AFit: TAtlasToolbarFit): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AFit.Visible) do
  begin
    if AFit.Visible[mIndex] then
    begin
      Result := Result + IntToStr(mIndex);
    end;
  end;
end;

function Menu(const AFit: TAtlasToolbarFit): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AFit.Overflow do
  begin
    Result := Result + IntToStr(mIndex);
  end;
end;

procedure TAtlasToolbarLayoutTests.EverythingFits;
var
  mFit: TAtlasToolbarFit;
begin
  // 0 1 | 3 4
  mFit := TAtlasToolbarLayout.Fit([B(True), B(True), S, B, B], 4 * cButton + cLine, cMore);
  Assert.IsFalse(mFit.More);
  Assert.AreEqual('01234', Shown(mFit));
  Assert.AreEqual(0, Integer(Length(mFit.Overflow)));
  Assert.AreEqual(4 * cButton + cLine, mFit.Used);
  Assert.AreEqual(4 * cButton + cLine, TAtlasToolbarLayout.FullWidth([B(True), B(True), S, B, B]));
end;

procedure TAtlasToolbarLayoutTests.TailGoesToOverflow;
var
  mFit: TAtlasToolbarFit;
begin
  // Platz für vier Knöpfe: zwei angeheftete, ein weiterer, dann ».
  mFit := TAtlasToolbarLayout.Fit([B(True), B(True), B, B, B, B], 4 * cButton, cMore);
  Assert.IsTrue(mFit.More);
  Assert.AreEqual('012', Shown(mFit));
  Assert.AreEqual('345', Menu(mFit));
  Assert.AreEqual(3 * cButton, mFit.Used);
end;

procedure TAtlasToolbarLayoutTests.PinnedStayEvenWhenNarrow;
var
  mFit: TAtlasToolbarFit;
begin
  mFit := TAtlasToolbarLayout.Fit([B(True), B(True), B(True), B, B], cButton, cMore);
  Assert.AreEqual('012', Shown(mFit), 'Abschnittssymbole und Rücksprung bleiben vorn');
  Assert.AreEqual('34', Menu(mFit));
  Assert.IsTrue(mFit.More);
end;

procedure TAtlasToolbarLayoutTests.KeepsOrderInOverflow;
var
  mFit: TAtlasToolbarFit;
  mSlots: TArray<TAtlasToolbarSlot>;
begin
  // Ein breiter Knopf (mit Text) passt nicht mehr; der schmale dahinter rückt nicht nach.
  mSlots := [B, TAtlasToolbarSlot.Create(80, False, False), B];
  mFit := TAtlasToolbarLayout.Fit(mSlots, cButton + 60 + cMore, cMore);
  Assert.AreEqual('0', Shown(mFit));
  Assert.AreEqual('12', Menu(mFit));
end;

procedure TAtlasToolbarLayoutTests.SeparatorsOnlyBetweenButtons;
var
  mFit: TAtlasToolbarFit;
begin
  // | 1 | | 4 |  →  in der Leiste nur der mittlere Trennstrich.
  mFit := TAtlasToolbarLayout.Fit([S, B, S, S, B, S], 1000, cMore);
  Assert.AreEqual('124', Shown(mFit));
  Assert.AreEqual(2 * cButton + cLine, TAtlasToolbarLayout.FullWidth([S, B, S, S, B, S]));
  // 0 | 2 | 4 | 6 mit Platz für zwei Knöpfe und »: Der Trennstrich vor dem Überlauf entfällt, im Menü stehen
  // die Trennstriche nur zwischen Einträgen.
  mFit := TAtlasToolbarLayout.Fit([B, S, B, S, B, S, B], 2 * cButton + cLine + cMore, cMore);
  Assert.AreEqual('012', Shown(mFit));
  Assert.AreEqual('456', Menu(mFit));
end;

procedure TAtlasToolbarLayoutTests.EmptyToolbar;
var
  mFit: TAtlasToolbarFit;
begin
  mFit := TAtlasToolbarLayout.Fit(nil, 100, cMore);
  Assert.IsFalse(mFit.More);
  Assert.AreEqual(0, mFit.Used);
  // Nur Trennstriche: nichts zu zeigen, kein ».
  mFit := TAtlasToolbarLayout.Fit([S, S], 0, cMore);
  Assert.IsFalse(mFit.More);
  Assert.AreEqual('', Shown(mFit));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarLayoutTests);

end.
