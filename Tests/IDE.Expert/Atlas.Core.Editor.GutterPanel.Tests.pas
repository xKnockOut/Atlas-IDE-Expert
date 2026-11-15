unit Atlas.Core.Editor.GutterPanel.Tests;

// Tafel und Klick der Atlas-Spalte (#768): Klick je Symbol, Zeilen der Problemtafel, Korrekturen, Pfeile, Farben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGutterPanelTests = class
  public
    [Test]
    procedure ClickOpensActionsOrJumpsOrShowsThePanel;
    [Test]
    procedure PanelBelongsToTheSymbol;
    [Test]
    procedure SeveralProblemsShowTheirCode;
    [Test]
    procedure OnlyAvailableQuickFixes;
    [Test]
    procedure ArrowsOnlyForBothDirections;
    [Test]
    procedure CodeStartSkipsBlanks;
    [Test]
    procedure SymbolColorFollowsTheKind;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Editor.GutterPanel;

function Problem(const ACode, AMessage: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Code := ACode;
  Result.Message := AMessage;
end;

function ClickOf(ASymbol: TAtlasGutterSymbol; ATargets: Integer): Integer;
begin
  Result := Ord(TAtlasGutterPanel.ClickOf(ASymbol, ATargets));
end;

{ TAtlasGutterPanelTests }

procedure TAtlasGutterPanelTests.ClickOpensActionsOrJumpsOrShowsThePanel;
begin
  Assert.AreEqual(Ord(TAtlasGutterClick.OpenActions), ClickOf(TAtlasGutterSymbol.Action, 0));
  Assert.AreEqual(Ord(TAtlasGutterClick.GoToTarget), ClickOf(TAtlasGutterSymbol.Overrides, 1));
  Assert.AreEqual(Ord(TAtlasGutterClick.ShowPanel), ClickOf(TAtlasGutterSymbol.Overridden, 3));
  Assert.AreEqual(Ord(TAtlasGutterClick.ShowPanel), ClickOf(TAtlasGutterSymbol.Overrides, 0));
  Assert.AreEqual(Ord(TAtlasGutterClick.ShowPanelWithFixes), ClickOf(TAtlasGutterSymbol.Warning, 0));
  Assert.AreEqual(Ord(TAtlasGutterClick.None), ClickOf(TAtlasGutterSymbol.None, 0));
end;

procedure TAtlasGutterPanelTests.PanelBelongsToTheSymbol;
begin
  Assert.AreEqual(Ord(TAtlasGutterPanelKind.Problem), Ord(TAtlasGutterPanel.PanelOf(TAtlasGutterSymbol.Hint)));
  Assert.AreEqual(Ord(TAtlasGutterPanelKind.Action), Ord(TAtlasGutterPanel.PanelOf(TAtlasGutterSymbol.Action)));
  Assert.AreEqual(Ord(TAtlasGutterPanelKind.Overrides),
    Ord(TAtlasGutterPanel.PanelOf(TAtlasGutterSymbol.Overridden)));
  Assert.AreEqual(Ord(TAtlasGutterPanelKind.None), Ord(TAtlasGutterPanel.PanelOf(TAtlasGutterSymbol.None)));
end;

procedure TAtlasGutterPanelTests.SeveralProblemsShowTheirCode;
var
  mProblems: TArray<TAtlasProblem>;
  mLines: TArray<string>;
begin
  mProblems := TArray<TAtlasProblem>.Create(Problem('W1000', 'Veraltet'));
  mLines := TAtlasGutterPanel.ProblemLines(mProblems);
  Assert.AreEqual(Integer(1), Integer(Length(mLines)));
  Assert.AreEqual('Veraltet', mLines[0], 'eine Meldung ohne Code');
  mProblems := TArray<TAtlasProblem>.Create(Problem('W1000', 'Veraltet'), Problem('', 'Ohne Code'));
  mLines := TAtlasGutterPanel.ProblemLines(mProblems);
  Assert.AreEqual('W1000: Veraltet', mLines[0]);
  Assert.AreEqual('Ohne Code', mLines[1]);
end;

procedure TAtlasGutterPanelTests.OnlyAvailableQuickFixes;
begin
  Assert.IsTrue(TAtlasGutterPanel.IsQuickFix('quickfix', ''));
  Assert.IsTrue(TAtlasGutterPanel.IsQuickFix('quickfix.atlas', ''));
  Assert.IsFalse(TAtlasGutterPanel.IsQuickFix('refactor.extract', ''));
  Assert.IsFalse(TAtlasGutterPanel.IsQuickFix('quickfix', 'geht gerade nicht'));
end;

procedure TAtlasGutterPanelTests.ArrowsOnlyForBothDirections;
var
  mEntry: TAtlasGutterOverrides;
  mUp, mDown: string;
begin
  mEntry := Default(TAtlasGutterOverrides);
  SetLength(mEntry.Overrides, 1);
  Assert.IsFalse(TAtlasGutterPanel.Arrows(mEntry, mUp, mDown));
  Assert.AreEqual('', mUp);
  SetLength(mEntry.Overridden, 2);
  Assert.IsTrue(TAtlasGutterPanel.Arrows(mEntry, mUp, mDown));
  Assert.AreEqual('↑ ', mUp);
  Assert.AreEqual('↓ ', mDown);
end;

procedure TAtlasGutterPanelTests.CodeStartSkipsBlanks;
begin
  Assert.AreEqual(1, TAtlasGutterPanel.CodeStart('begin'));
  Assert.AreEqual(4, TAtlasGutterPanel.CodeStart(' '#9' x := 1;'));
  Assert.AreEqual(3, TAtlasGutterPanel.CodeStart('  '));
  Assert.AreEqual(1, TAtlasGutterPanel.CodeStart(''));
end;

procedure TAtlasGutterPanelTests.SymbolColorFollowsTheKind;
var
  mColors: TAtlasColors;
begin
  mColors := Default(TAtlasColors);
  mColors.Error := $0000C0;
  mColors.Warn := $0080C0;
  mColors.Muted := $808080;
  mColors.Accent := $C00000;
  mColors.Add := $00A000;
  // Über dem eigenen Ton bleibt die Farbe gleich: so zeigt sich, welcher Ton zur Art gehört.
  Assert.AreEqual(Cardinal(mColors.Error), Cardinal(TAtlasGutterPanel.SymbolColor(TAtlasGutterSymbol.Error,
    mColors, mColors.Error)));
  Assert.AreEqual(Cardinal(mColors.Muted), Cardinal(TAtlasGutterPanel.SymbolColor(TAtlasGutterSymbol.Hint,
    mColors, mColors.Muted)));
  Assert.AreEqual(Cardinal(mColors.Add), Cardinal(TAtlasGutterPanel.SymbolColor(TAtlasGutterSymbol.Overridden,
    mColors, mColors.Add)));
  // Hinweise blasser als Fehler.
  Assert.AreEqual(Cardinal(TAtlasColorMath.Mix(mColors.Muted, $FFFFFF, 0.9)),
    Cardinal(TAtlasGutterPanel.SymbolColor(TAtlasGutterSymbol.Hint, mColors, $FFFFFF)));
  Assert.AreEqual(Cardinal(TAtlasColorMath.Mix(mColors.Accent, $FFFFFF, 0.95)),
    Cardinal(TAtlasGutterPanel.SymbolColor(TAtlasGutterSymbol.Action, mColors, $FFFFFF)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGutterPanelTests);

end.
