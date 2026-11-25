unit Atlas.Core.Welcome.QuickActionRows.Tests;

// Tests der Zeilen der Knopfleiste mit Schnellaktionen (#764): Auswahl nach neuen Zeilen in den Grenzen, aktive
// Zeile aus Tastatur und Maus, Knopf an einer Stelle samt Teil ▾, laufende Aktionen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Welcome.QuickActionRows;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasQuickActionRowsTests = class
  private
    FRows: TAtlasQuickActionRows;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadClampsSelection;
    [Test]
    procedure ActiveRowPrefersKeyOnlyWithFocus;
    [Test]
    procedure ActiveRowNeedsButtons;
    [Test]
    procedure HitButtonFindsMenuPart;
    [Test]
    procedure RefreshUpdatesRunning;
  end;

implementation

uses
  System.Types;

function Button(AAction: TAtlasQuickAction): TAtlasQuickActionButton;
begin
  Result := Default(TAtlasQuickActionButton);
  Result.Action := AAction;
  Result.Enabled := True;
end;

function TwoButtons: TAtlasQuickActionButtons;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := Button(TAtlasQuickAction.Build);
  Result[1] := Button(TAtlasQuickAction.Pull);
end;

procedure TAtlasQuickActionRowsTests.Setup;
begin
  FRows := TAtlasQuickActionRows.Create;
end;

procedure TAtlasQuickActionRowsTests.TearDown;
begin
  FRows.Free;
  FRows := nil;
end;

procedure TAtlasQuickActionRowsTests.LoadClampsSelection;
begin
  Assert.AreEqual(-1, FRows.Selection.KeyRow, 'ohne Auswahl');
  FRows.Load(TArray<string>.Create('A', 'B', 'C'), TArray<TAtlasQuickActionButtons>.Create(TwoButtons, TwoButtons,
    TwoButtons), nil, 10);
  FRows.Selection.KeyRow := 2;
  FRows.Selection.KeyButton := 1;
  FRows.Selection.HoverRow := 2;
  FRows.Selection.HoverButton := 0;
  FRows.Load(TArray<string>.Create('A', 'B'), TArray<TAtlasQuickActionButtons>.Create(TwoButtons, nil), nil, 20);
  Assert.AreEqual(1, FRows.Selection.KeyRow, 'letzte Zeile');
  Assert.AreEqual(-1, FRows.Selection.KeyButton, 'Zeile ohne Knöpfe');
  Assert.AreEqual(-1, FRows.Selection.HoverRow, 'Maus außerhalb');
  Assert.AreEqual(-1, FRows.Selection.HoverButton);
  Assert.AreEqual(2, FRows.Count);
  Assert.AreEqual('B', FRows.Project(1));
  Assert.AreEqual('', FRows.Project(2), 'außerhalb leer');
  Assert.IsFalse(FRows.State(0).Running, 'ohne Stand Idle');
  Assert.AreEqual(UInt64(20), FRows.NowMs);
end;

procedure TAtlasQuickActionRowsTests.ActiveRowPrefersKeyOnlyWithFocus;
begin
  FRows.Load(TArray<string>.Create('A', 'B'), TArray<TAtlasQuickActionButtons>.Create(TwoButtons, TwoButtons), nil,
    0);
  FRows.Selection.KeyRow := 0;
  FRows.Selection.HoverRow := 1;
  Assert.AreEqual(1, FRows.ActiveRow(True), 'Maus zuletzt');
  FRows.Selection.UseKey := True;
  Assert.AreEqual(0, FRows.ActiveRow(True), 'Tastatur zuletzt');
  Assert.AreEqual(1, FRows.ActiveRow(False), 'ohne Fokus die Maus');
  FRows.Selection.HoverRow := -1;
  Assert.AreEqual(-1, FRows.ActiveRow(False), 'ohne Fokus und Maus keine');
end;

procedure TAtlasQuickActionRowsTests.ActiveRowNeedsButtons;
begin
  FRows.Load(TArray<string>.Create('A'), nil, nil, 0);
  FRows.Selection.HoverRow := 0;
  Assert.AreEqual(-1, FRows.ActiveRow(False));
end;

procedure TAtlasQuickActionRowsTests.HitButtonFindsMenuPart;
var
  mIndex: Integer;
  mMenu: Boolean;
begin
  FRows.Load(TArray<string>.Create('A'), TArray<TAtlasQuickActionButtons>.Create(TwoButtons), nil, 0);
  Assert.IsFalse(FRows.HitButton(0, 15, 5, 4, mIndex, mMenu), 'vor dem Zeichnen keine Rechtecke');
  FRows.SetRects(0, TArray<TRect>.Create(Rect(0, 0, 20, 10), Rect(30, 0, 50, 10)));
  Assert.IsTrue(FRows.HitButton(0, 5, 5, 4, mIndex, mMenu));
  Assert.AreEqual(0, mIndex);
  Assert.IsFalse(mMenu, 'links im Knopf');
  Assert.IsTrue(FRows.HitButton(0, 18, 5, 4, mIndex, mMenu));
  Assert.IsTrue(mMenu, 'Teil ▾ von „Öffnen und bauen“');
  Assert.IsTrue(FRows.HitButton(0, 48, 5, 4, mIndex, mMenu));
  Assert.AreEqual(1, mIndex);
  Assert.IsFalse(mMenu, 'Pull hat keinen Teil ▾');
  Assert.IsFalse(FRows.HitButton(0, 25, 5, 4, mIndex, mMenu), 'zwischen den Knöpfen');
  Assert.AreEqual(-1, mIndex);
end;

procedure TAtlasQuickActionRowsTests.RefreshUpdatesRunning;
begin
  FRows.Load(TArray<string>.Create('A', 'B'), nil, nil, 0);
  Assert.IsFalse(FRows.Running);
  FRows.Refresh(TArray<TAtlasQuickActionState>.Create(TAtlasQuickActionState.Idle,
    TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 100)), 200);
  Assert.IsTrue(FRows.Running, 'Zeile B baut');
  Assert.AreEqual(UInt64(200), FRows.NowMs);
end;

end.
