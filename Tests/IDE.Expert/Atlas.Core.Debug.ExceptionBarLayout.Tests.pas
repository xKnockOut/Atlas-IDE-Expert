unit Atlas.Core.Debug.ExceptionBarLayout.Tests;

// Tests für die Aufteilung der Exception-Leiste (#783, #865) ohne VCL: Zeilen mit und ohne Erklärung, Knöpfe
// nebeneinander und nur, wenn die Info sie anbietet, anklickbare Ortszeile nur mit Datei, Auslösen nur vorhandener
// Knöpfe, Skalierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugBarLayoutTests = class
  public
    [Test]
    procedure RowsGrowWithExplanation;
    [Test]
    procedure ButtonsSideBySideInLastRow;
    [Test]
    procedure OptionalButtonsOnlyWhenOffered;
    [Test]
    procedure OpenOnlyWithLocation;
    [Test]
    procedure ExplanationButtonsAboveBarButtons;
    [Test]
    procedure ScalesWithPPI;
    [Test]
    procedure KnownErrorsBelowExplanation;
    [Test]
    procedure KnownButtonsFollowFirstHit;
  end;

implementation

uses
  System.Types,
  Atlas.Core.KnownErrors.Contract,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.Core.Debug.ExceptionBarLayout;

/// <summary>Jede Beschriftung 50 Pixel breit.</summary>
function FixedWidth: TAtlasDebugBarTextWidth;
begin
  Result :=
    function(AAction: TAtlasDebugBarAction): Integer
    begin
      Result := 50;
    end;
end;

function Known(AHits: Integer; AFirstResolved, ACanComment, ACanCreate: Boolean): TAtlasDebugBannerKnown;
var
  mIndex: Integer;
  mError: TAtlasKnownError;
begin
  Result := Default(TAtlasDebugBannerKnown);
  for mIndex := 1 to AHits do
  begin
    mError := Default(TAtlasKnownError);
    mError.Key := 'ATL-' + Char(Ord('0') + mIndex);
    mError.Resolved := AFirstResolved and (mIndex = 1);
    Result.Errors := Result.Errors + [mError];
  end;
  Result.CanComment := ACanComment;
  Result.CanCreate := ACanCreate;
end;

function Explanation(ALines: Integer; ABusy: Boolean): TAtlasDebugBannerExplanation;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  Result.Busy := ABusy;
  Result.Headline := 'Auftrag.Kunde ist nil';
  Result.WhereName := 'Kunde';
  for mIndex := 1 to ALines do
  begin
    Result.Lines := Result.Lines + [TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok, 'Glied')];
  end;
end;

procedure TAtlasDebugBarLayoutTests.RowsGrowWithExplanation;
var
  mLayout: TAtlasDebugBarLayout;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    Assert.AreEqual(3, mLayout.Rows, 'ohne Erklärung');
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), Explanation(2, True));
    Assert.AreEqual(4, mLayout.Rows, 'prüft noch: nur die Ergebniszeile');
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), Explanation(2, False));
    Assert.AreEqual(3 + 1 + 2 + 1, mLayout.Rows, 'Ergebnis, zwei Glieder, Knöpfe');
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), Explanation(9, False));
    Assert.AreEqual(TAtlasDebugBarLayout.cMaxExplanationLines, mLayout.ShownLines);
    Assert.AreEqual(3 + 1 + TAtlasDebugBarLayout.cMaxExplanationLines + 1 + 1, mLayout.Rows,
      'mit „… n weitere“');
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.ButtonsSideBySideInLastRow;
var
  mLayout: TAtlasDebugBarLayout;
  mBreak, mContinue: TRect;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.Arrange(800, 0, FixedWidth());
    mBreak := mLayout.ActionRect(TAtlasDebugBarAction.BreakHere);
    mContinue := mLayout.ActionRect(TAtlasDebugBarAction.Continue);
    Assert.AreEqual(50 + TAtlasDebugBarLayout.cButtonPadding, mBreak.Width);
    Assert.AreEqual(mBreak.Right + TAtlasDebugBarLayout.cGap, mContinue.Left);
    Assert.AreEqual(mLayout.RowTop(2) + 2, mBreak.Top, 'dritte Zeile');
    Assert.AreEqual<TAtlasDebugBarAction>(TAtlasDebugBarAction.Continue,
      mLayout.ActionAt(mContinue.Left + 1, mContinue.Top + 1));
    Assert.AreEqual<TAtlasDebugBarAction>(TAtlasDebugBarAction.None,
      mLayout.ActionAt(1, 1), 'Titelzeile ist kein Knopf');
    Assert.AreEqual(mLayout.ActionRect(TAtlasDebugBarAction.Copy).Right, mLayout.LastButtonRight);
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.OptionalButtonsOnlyWhenOffered;
var
  mLayout: TAtlasDebugBarLayout;
  mInfo: TAtlasDebugBannerInfo;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.Arrange(800, 0, FixedWidth());
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.IgnoreLocation).IsEmpty);
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.CreateTest).IsEmpty);
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.IgnoreLocation));
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.None));
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.Copy));
    mInfo := Default(TAtlasDebugBannerInfo);
    mInfo.CanIgnoreLocation := True;
    mInfo.CanCreateTest := True;
    mLayout.SetContent(mInfo, Default(TAtlasDebugBannerExplanation));
    mLayout.Arrange(800, 0, FixedWidth());
    Assert.IsFalse(mLayout.ActionRect(TAtlasDebugBarAction.IgnoreLocation).IsEmpty);
    Assert.AreEqual(mLayout.ActionRect(TAtlasDebugBarAction.CreateTest).Right, mLayout.LastButtonRight);
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.IgnoreLocation));
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.OpenOnlyWithLocation;
var
  mLayout: TAtlasDebugBarLayout;
  mInfo: TAtlasDebugBannerInfo;
  mOpen: TRect;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.Arrange(800, 300, FixedWidth());
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.Open).IsEmpty);
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.Open));
    mInfo := Default(TAtlasDebugBannerInfo);
    mInfo.FileName := 'Unit1.pas';
    mInfo.Line := 42;
    mLayout.SetContent(mInfo, Default(TAtlasDebugBannerExplanation));
    mLayout.Arrange(800, 300, FixedWidth());
    mOpen := mLayout.ActionRect(TAtlasDebugBarAction.Open);
    Assert.AreEqual(300, mOpen.Width, 'so breit wie der Text');
    Assert.AreEqual(mLayout.RowTop(1), mOpen.Top, 'zweite Zeile');
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.Open));
    mLayout.Arrange(200, 300, FixedWidth());
    Assert.AreEqual(200 - 2 * (TAtlasDebugBarLayout.cBarPadding + TAtlasDebugBarLayout.cGap),
      mLayout.ActionRect(TAtlasDebugBarAction.Open).Width, 'nicht breiter als die Leiste');
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.ExplanationButtonsAboveBarButtons;
var
  mLayout: TAtlasDebugBarLayout;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mExplanation := Explanation(1, False);
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), mExplanation);
    mLayout.Arrange(800, 0, FixedWidth());
    Assert.AreEqual(mLayout.RowTop(mLayout.Rows - 2) + 2, mLayout.ActionRect(TAtlasDebugBarAction.WhereAssigned).Top);
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.Evaluate).IsEmpty, 'ohne Ausdruck kein Knopf');
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.Evaluate));
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.WhereAssigned));
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), Explanation(1, True));
    mLayout.Arrange(800, 0, FixedWidth());
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.WhereAssigned).IsEmpty, 'prüft noch: keine Knöpfe');
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.WhereAssigned));
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.ScalesWithPPI;
var
  mLayout: TAtlasDebugBarLayout;
begin
  Assert.AreEqual(3 * TAtlasDebugBarLayout.cBaseRow + TAtlasDebugBarLayout.cBarPadding,
    TAtlasDebugBarLayout.BarHeight(96, 3));
  Assert.AreEqual(2 * (3 * TAtlasDebugBarLayout.cBaseRow + TAtlasDebugBarLayout.cBarPadding),
    TAtlasDebugBarLayout.BarHeight(192, 3));
  Assert.AreEqual(TAtlasDebugBarLayout.BarHeight(96, 3), TAtlasDebugBarLayout.BarHeight(72, 3),
    'nie kleiner als bei 96 dpi');
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.PPI := 192;
    Assert.AreEqual(48, mLayout.RowHeight);
    Assert.AreEqual(6 + 48, mLayout.RowTop(1));
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.KnownErrorsBelowExplanation;
var
  mLayout: TAtlasDebugBarLayout;
  mWhere, mOpen, mBreak: TRect;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.SetKnown(Known(0, False, True, False));
    Assert.AreEqual(3, mLayout.Rows, 'ohne Treffer wie bisher');
    // Erklärung: Ergebnis, ein Glied, Knöpfe (3 Zeilen); Treffer: sechs, gezeigt vier, dazu die Knöpfe.
    mLayout.SetContent(Default(TAtlasDebugBannerInfo), Explanation(1, False));
    mLayout.SetKnown(Known(6, False, True, False));
    Assert.AreEqual(4, mLayout.ShownKnown);
    Assert.AreEqual(3 + 3 + 5, mLayout.Rows);
    Assert.AreEqual(5, mLayout.KnownRow, 'unter Ort und Erklärung');
    mLayout.Arrange(800, 0, FixedWidth());
    mWhere := mLayout.ActionRect(TAtlasDebugBarAction.WhereAssigned);
    mOpen := mLayout.ActionRect(TAtlasDebugBarAction.KnownOpen);
    mBreak := mLayout.ActionRect(TAtlasDebugBarAction.BreakHere);
    Assert.AreEqual(mLayout.RowTop(4) + 2, mWhere.Top, 'Knöpfe der Erklärung bleiben über den Treffern');
    Assert.AreEqual(mLayout.RowTop(mLayout.Rows - 2) + 2, mOpen.Top, 'Knöpfe der Treffer unter den Treffern');
    Assert.AreEqual(mLayout.RowTop(mLayout.Rows - 1) + 2, mBreak.Top);
  finally
    mLayout.Free;
  end;
end;

procedure TAtlasDebugBarLayoutTests.KnownButtonsFollowFirstHit;
var
  mLayout: TAtlasDebugBarLayout;
begin
  mLayout := TAtlasDebugBarLayout.Create;
  try
    mLayout.SetKnown(Known(2, False, True, True));
    mLayout.Arrange(1200, 0, FixedWidth());
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.KnownOpen));
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.KnownComment));
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.KnownReopen), 'offen: nicht wieder öffnen');
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.KnownNew));
    Assert.AreEqual(mLayout.ActionRect(TAtlasDebugBarAction.KnownNew).Right, mLayout.LastButtonRight,
      'Neues Issue zuletzt in der letzten Zeile');
    mLayout.SetKnown(Known(1, True, True, False));
    mLayout.Arrange(1200, 0, FixedWidth());
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.KnownComment), 'erledigt: wieder öffnen statt Kommentar');
    Assert.IsTrue(mLayout.CanTrigger(TAtlasDebugBarAction.KnownReopen));
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.KnownNew));
    Assert.IsTrue(mLayout.ActionRect(TAtlasDebugBarAction.KnownNew).IsEmpty);
    mLayout.SetKnown(Known(1, False, False, False));
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.KnownComment), 'Tracker schreibt nicht');
    mLayout.SetKnown(Known(0, False, False, True));
    mLayout.Arrange(1200, 0, FixedWidth());
    Assert.AreEqual(3, mLayout.Rows, 'ohne Treffer nur Neues Issue');
    Assert.IsFalse(mLayout.CanTrigger(TAtlasDebugBarAction.KnownOpen));
    Assert.IsFalse(mLayout.ActionRect(TAtlasDebugBarAction.KnownNew).IsEmpty);
  finally
    mLayout.Free;
  end;
end;

end.
