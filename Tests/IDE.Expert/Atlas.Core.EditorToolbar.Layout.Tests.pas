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
  Button = 24;
  Line = 9;
  More = 24;

function B(APinned: Boolean): TAtlasToolbarSlot; overload;
begin
  Result := TAtlasToolbarSlot.Create(Button, False, APinned);
end;

function B: TAtlasToolbarSlot; overload;
begin
  Result := B(False);
end;

function S: TAtlasToolbarSlot;
begin
  Result := TAtlasToolbarSlot.Create(Line, True, False);
end;

function Shown(const AFit: TAtlasToolbarFit): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AFit.Visible) do
    if AFit.Visible[Index] then
      Result := Result + IntToStr(Index);
end;

function Menu(const AFit: TAtlasToolbarFit): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AFit.Overflow do
    Result := Result + IntToStr(Index);
end;

procedure TAtlasToolbarLayoutTests.EverythingFits;
var
  Fit: TAtlasToolbarFit;
begin
  // 0 1 | 3 4
  Fit := TAtlasToolbarLayout.Fit([B(True), B(True), S, B, B], 4 * Button + Line, More);
  Assert.IsFalse(Fit.More);
  Assert.AreEqual('01234', Shown(Fit));
  Assert.AreEqual(0, Integer(Length(Fit.Overflow)));
  Assert.AreEqual(4 * Button + Line, Fit.Used);
  Assert.AreEqual(4 * Button + Line, TAtlasToolbarLayout.FullWidth([B(True), B(True), S, B, B]));
end;

procedure TAtlasToolbarLayoutTests.TailGoesToOverflow;
var
  Fit: TAtlasToolbarFit;
begin
  // Platz für vier Knöpfe: zwei angeheftete, ein weiterer, dann ».
  Fit := TAtlasToolbarLayout.Fit([B(True), B(True), B, B, B, B], 4 * Button, More);
  Assert.IsTrue(Fit.More);
  Assert.AreEqual('012', Shown(Fit));
  Assert.AreEqual('345', Menu(Fit));
  Assert.AreEqual(3 * Button, Fit.Used);
end;

procedure TAtlasToolbarLayoutTests.PinnedStayEvenWhenNarrow;
var
  Fit: TAtlasToolbarFit;
begin
  Fit := TAtlasToolbarLayout.Fit([B(True), B(True), B(True), B, B], Button, More);
  Assert.AreEqual('012', Shown(Fit), 'Abschnittssymbole und Rücksprung bleiben vorn');
  Assert.AreEqual('34', Menu(Fit));
  Assert.IsTrue(Fit.More);
end;

procedure TAtlasToolbarLayoutTests.KeepsOrderInOverflow;
var
  Fit: TAtlasToolbarFit;
  Slots: TArray<TAtlasToolbarSlot>;
begin
  // Ein breiter Knopf (mit Text) passt nicht mehr; der schmale dahinter rückt nicht nach.
  Slots := [B, TAtlasToolbarSlot.Create(80, False, False), B];
  Fit := TAtlasToolbarLayout.Fit(Slots, Button + 60 + More, More);
  Assert.AreEqual('0', Shown(Fit));
  Assert.AreEqual('12', Menu(Fit));
end;

procedure TAtlasToolbarLayoutTests.SeparatorsOnlyBetweenButtons;
var
  Fit: TAtlasToolbarFit;
begin
  // | 1 | | 4 |  →  in der Leiste nur der mittlere Trennstrich.
  Fit := TAtlasToolbarLayout.Fit([S, B, S, S, B, S], 1000, More);
  Assert.AreEqual('124', Shown(Fit));
  Assert.AreEqual(2 * Button + Line, TAtlasToolbarLayout.FullWidth([S, B, S, S, B, S]));
  // 0 | 2 | 4 | 6 mit Platz für zwei Knöpfe und »: Der Trennstrich vor dem Überlauf entfällt, im Menü stehen
  // die Trennstriche nur zwischen Einträgen.
  Fit := TAtlasToolbarLayout.Fit([B, S, B, S, B, S, B], 2 * Button + Line + More, More);
  Assert.AreEqual('012', Shown(Fit));
  Assert.AreEqual('456', Menu(Fit));
end;

procedure TAtlasToolbarLayoutTests.EmptyToolbar;
var
  Fit: TAtlasToolbarFit;
begin
  Fit := TAtlasToolbarLayout.Fit(nil, 100, More);
  Assert.IsFalse(Fit.More);
  Assert.AreEqual(0, Fit.Used);
  // Nur Trennstriche: nichts zu zeigen, kein ».
  Fit := TAtlasToolbarLayout.Fit([S, S], 0, More);
  Assert.IsFalse(Fit.More);
  Assert.AreEqual('', Shown(Fit));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarLayoutTests);

end.
