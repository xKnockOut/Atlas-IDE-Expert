unit Atlas.UI.Debug.ExceptionBar.Tests;

// Exception-Leiste (#783), Darstellung: feste Höhe, Zeile 2 mit Thread,
// ausgeblendeten Ebenen und erster eigener Zeile, Knöpfe in Reihenfolge,
// „Nur an dieser Stelle ignorieren“ nur mit Ort, Klick meldet die Aktion erst
// beim Loslassen auf demselben Knopf. Erklärung einer Zugriffsverletzung
// (#865): mehr Zeilen, eigene Knöpfe nur mit Inhalt.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Debug.ExceptionBar;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugExceptionBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasDebugExceptionBar;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsHeightAndShowsDetail;
    [Test]
    procedure ButtonsInOrder;
    [Test]
    procedure IgnoreLocationOnlyWithLocation;
    [Test]
    procedure CreateTestOnlyWhenOffered;
    [Test]
    procedure ClickReportsActionOnRelease;
    [Test]
    procedure ExplanationGrowsAndAddsButtons;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Debug.ExceptionBanner;

type
  // Zugriff auf die geschützten Mausereignisse.
  TBarAccess = class(TAtlasDebugExceptionBar);

function SampleInfo(ACanIgnore: Boolean): TAtlasDebugBannerInfo;
begin
  Result := Default(TAtlasDebugBannerInfo);
  Result.ExceptionClass := 'EConvertError';
  Result.Message := '''x'' ist kein gültiger Gleitkommawert';
  Result.ThreadText := 'Hauptthread 4711';
  Result.Count := 2;
  Result.FrameIndex := 3;
  Result.Hidden := 3;
  Result.Routine := 'Unit1.TForm1.Button1Click';
  Result.FileName := 'C:\Projekte\Demo\Unit1.pas';
  Result.Line := 42;
  Result.CanIgnoreLocation := ACanIgnore;
end;

{ TAtlasDebugExceptionBarTests }

procedure TAtlasDebugExceptionBarTests.WarmUpFirstUse;
begin
  SetUp;
  try
    KeepsHeightAndShowsDetail;
  finally
    TearDown;
  end;
end;

procedure TAtlasDebugExceptionBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 300;
  FBar := TAtlasDebugExceptionBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
end;

procedure TAtlasDebugExceptionBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasDebugExceptionBarTests.KeepsHeightAndShowsDetail;
begin
  FBar.SetInfo(SampleInfo(True));
  Assert.AreEqual(TAtlasDebugExceptionBar.BarHeight(FBar.CurrentPPI), FBar.Height);
  Assert.IsTrue(FBar.Detail.Contains('Hauptthread 4711'), FBar.Detail);
  Assert.IsTrue(FBar.Detail.Contains('3 '), 'ausgeblendete Ebenen: ' + FBar.Detail);
  Assert.IsTrue(FBar.Detail.EndsWith('Unit1.TForm1.Button1Click (Unit1.pas:42)'), FBar.Detail);
  Assert.IsFalse(FBar.ActionRect(TAtlasDebugBarAction.Open).IsEmpty, 'Ortszeile anklickbar');
end;

procedure TAtlasDebugExceptionBarTests.ButtonsInOrder;
var
  mBreakRect, mContinueRect, mClassRect, mLocationRect, mCopyRect: TRect;
begin
  FBar.SetInfo(SampleInfo(True));
  mBreakRect := FBar.ActionRect(TAtlasDebugBarAction.BreakHere);
  mContinueRect := FBar.ActionRect(TAtlasDebugBarAction.Continue);
  mClassRect := FBar.ActionRect(TAtlasDebugBarAction.IgnoreClass);
  mLocationRect := FBar.ActionRect(TAtlasDebugBarAction.IgnoreLocation);
  mCopyRect := FBar.ActionRect(TAtlasDebugBarAction.Copy);
  Assert.IsFalse(mBreakRect.IsEmpty);
  Assert.IsTrue(mBreakRect.Right < mContinueRect.Left);
  Assert.IsTrue(mContinueRect.Right < mClassRect.Left);
  Assert.IsTrue(mClassRect.Right < mLocationRect.Left);
  Assert.IsTrue(mLocationRect.Right < mCopyRect.Left);
  Assert.IsTrue(mBreakRect.Bottom <= FBar.ClientHeight, 'Knöpfe in der Leiste');
  Assert.IsTrue(mBreakRect.Top > FBar.ActionRect(TAtlasDebugBarAction.Open).Bottom - 1, 'unter der Ortszeile');
end;

procedure TAtlasDebugExceptionBarTests.IgnoreLocationOnlyWithLocation;
var
  mInfo: TAtlasDebugBannerInfo;
  mReported: TAtlasDebugBarAction;
begin
  FBar.SetInfo(SampleInfo(False));
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.IgnoreLocation).IsEmpty);
  mReported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      mReported := AAction;
    end;
  FBar.Trigger(TAtlasDebugBarAction.IgnoreLocation);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(mReported), 'ohne Knopf keine Aktion');
  mInfo := SampleInfo(False);
  mInfo.FileName := '';
  mInfo.Line := 0;
  FBar.SetInfo(mInfo);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.Open).IsEmpty, 'ohne Datei kein Sprung');
  FBar.Trigger(TAtlasDebugBarAction.Open);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(mReported));
  FBar.OnAction := nil;
end;

procedure TAtlasDebugExceptionBarTests.CreateTestOnlyWhenOffered;
var
  mInfo: TAtlasDebugBannerInfo;
  mReported: TAtlasDebugBarAction;
begin
  mReported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      mReported := AAction;
    end;
  FBar.SetInfo(SampleInfo(True));
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.CreateTest).IsEmpty, 'ohne Modul Tests kein Knopf');
  FBar.Trigger(TAtlasDebugBarAction.CreateTest);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(mReported), 'ohne Knopf keine Aktion');
  mInfo := SampleInfo(True);
  mInfo.CanCreateTest := True;
  FBar.SetInfo(mInfo);
  Assert.IsFalse(FBar.ActionRect(TAtlasDebugBarAction.CreateTest).IsEmpty);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.CreateTest).Left >
    FBar.ActionRect(TAtlasDebugBarAction.Copy).Right, 'nach „Meldung kopieren“');
  FBar.Trigger(TAtlasDebugBarAction.CreateTest);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.CreateTest), Ord(mReported));
  FBar.OnAction := nil;
end;

procedure TAtlasDebugExceptionBarTests.ClickReportsActionOnRelease;
var
  mReported: TAtlasDebugBarAction;
  mArea, mOther: TRect;
begin
  FBar.SetInfo(SampleInfo(True));
  mReported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      mReported := AAction;
    end;
  mArea := FBar.ActionRect(TAtlasDebugBarAction.Continue);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.Continue), Ord(FBar.ActionAt(mArea.CenterPoint.X, mArea.CenterPoint.Y)));
  // Drücken auf „Fortsetzen“, Loslassen auf „Anhalten“: nichts.
  mOther := FBar.ActionRect(TAtlasDebugBarAction.BreakHere);
  TBarAccess(FBar).MouseDown(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  TBarAccess(FBar).MouseUp(mbLeft, [], mOther.CenterPoint.X, mOther.CenterPoint.Y);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(mReported));
  TBarAccess(FBar).MouseDown(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  TBarAccess(FBar).MouseUp(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.Continue), Ord(mReported));
  FBar.OnAction := nil;
end;

procedure TAtlasDebugExceptionBarTests.ExplanationGrowsAndAddsButtons;
var
  mExplanation: TAtlasDebugBannerExplanation;
  mReported: TAtlasDebugBarAction;
  mIndex: Integer;
begin
  FBar.SetInfo(SampleInfo(True));
  // Während der Prüfung: eine Zeile mehr, keine Knöpfe der Erklärung.
  mExplanation := Default(TAtlasDebugBannerExplanation);
  mExplanation.Active := True;
  mExplanation.Busy := True;
  mExplanation.Headline := 'Atlas prüft';
  mExplanation.WhereName := 'Kunde';
  FBar.SetExplanation(mExplanation);
  Assert.AreEqual(4, FBar.Rows);
  Assert.AreEqual(TAtlasDebugExceptionBar.BarHeight(FBar.CurrentPPI, 4), FBar.Height);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).IsEmpty);
  // Fertig: Ergebniszeile, 8 Glieder (6 gezeigt, „… 2 weitere“), Knopfzeile.
  mExplanation.Busy := False;
  mExplanation.Headline := 'Auftrag.Kunde ist nil';
  for mIndex := 1 to 8 do
  begin
    mExplanation.Lines := mExplanation.Lines + [TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok,
      'Glied ' + IntToStr(mIndex))];
  end;
  mExplanation.CopyText := 'Text';
  FBar.SetExplanation(mExplanation);
  Assert.AreEqual(3 + 1 + 6 + 1 + 1, FBar.Rows);
  Assert.IsFalse(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).IsEmpty);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.Evaluate).IsEmpty, 'ohne Ausdruck kein Knopf');
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).Right <
    FBar.ActionRect(TAtlasDebugBarAction.CopyExplanation).Left);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).Bottom <=
    FBar.ActionRect(TAtlasDebugBarAction.Continue).Top, 'über den Knöpfen der Leiste');
  mReported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      mReported := AAction;
    end;
  FBar.Trigger(TAtlasDebugBarAction.Evaluate);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(mReported));
  FBar.Trigger(TAtlasDebugBarAction.CopyExplanation);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.CopyExplanation), Ord(mReported));
  FBar.OnAction := nil;
  // Ohne Erklärung wieder drei Zeilen.
  FBar.SetExplanation(Default(TAtlasDebugBannerExplanation));
  Assert.AreEqual(3, FBar.Rows);
  Assert.AreEqual(TAtlasDebugExceptionBar.BarHeight(FBar.CurrentPPI), FBar.Height);
end;

end.
