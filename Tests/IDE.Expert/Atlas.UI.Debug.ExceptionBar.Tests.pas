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
  TAtlasDebugExceptionBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasDebugExceptionBar;
  public
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
  BreakRect, ContinueRect, ClassRect, LocationRect, CopyRect: TRect;
begin
  FBar.SetInfo(SampleInfo(True));
  BreakRect := FBar.ActionRect(TAtlasDebugBarAction.BreakHere);
  ContinueRect := FBar.ActionRect(TAtlasDebugBarAction.Continue);
  ClassRect := FBar.ActionRect(TAtlasDebugBarAction.IgnoreClass);
  LocationRect := FBar.ActionRect(TAtlasDebugBarAction.IgnoreLocation);
  CopyRect := FBar.ActionRect(TAtlasDebugBarAction.Copy);
  Assert.IsFalse(BreakRect.IsEmpty);
  Assert.IsTrue(BreakRect.Right < ContinueRect.Left);
  Assert.IsTrue(ContinueRect.Right < ClassRect.Left);
  Assert.IsTrue(ClassRect.Right < LocationRect.Left);
  Assert.IsTrue(LocationRect.Right < CopyRect.Left);
  Assert.IsTrue(BreakRect.Bottom <= FBar.ClientHeight, 'Knöpfe in der Leiste');
  Assert.IsTrue(BreakRect.Top > FBar.ActionRect(TAtlasDebugBarAction.Open).Bottom - 1, 'unter der Ortszeile');
end;

procedure TAtlasDebugExceptionBarTests.IgnoreLocationOnlyWithLocation;
var
  Info: TAtlasDebugBannerInfo;
  Reported: TAtlasDebugBarAction;
begin
  FBar.SetInfo(SampleInfo(False));
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.IgnoreLocation).IsEmpty);
  Reported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      Reported := AAction;
    end;
  FBar.Trigger(TAtlasDebugBarAction.IgnoreLocation);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(Reported), 'ohne Knopf keine Aktion');
  Info := SampleInfo(False);
  Info.FileName := '';
  Info.Line := 0;
  FBar.SetInfo(Info);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.Open).IsEmpty, 'ohne Datei kein Sprung');
  FBar.Trigger(TAtlasDebugBarAction.Open);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(Reported));
  FBar.OnAction := nil;
end;

procedure TAtlasDebugExceptionBarTests.ClickReportsActionOnRelease;
var
  Reported: TAtlasDebugBarAction;
  Area, Other: TRect;
begin
  FBar.SetInfo(SampleInfo(True));
  Reported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      Reported := AAction;
    end;
  Area := FBar.ActionRect(TAtlasDebugBarAction.Continue);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.Continue), Ord(FBar.ActionAt(Area.CenterPoint.X, Area.CenterPoint.Y)));
  // Drücken auf „Fortsetzen“, Loslassen auf „Anhalten“: nichts.
  Other := FBar.ActionRect(TAtlasDebugBarAction.BreakHere);
  TBarAccess(FBar).MouseDown(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  TBarAccess(FBar).MouseUp(mbLeft, [], Other.CenterPoint.X, Other.CenterPoint.Y);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(Reported));
  TBarAccess(FBar).MouseDown(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  TBarAccess(FBar).MouseUp(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.Continue), Ord(Reported));
  FBar.OnAction := nil;
end;

procedure TAtlasDebugExceptionBarTests.ExplanationGrowsAndAddsButtons;
var
  Explanation: TAtlasDebugBannerExplanation;
  Reported: TAtlasDebugBarAction;
  Index: Integer;
begin
  FBar.SetInfo(SampleInfo(True));
  // Während der Prüfung: eine Zeile mehr, keine Knöpfe der Erklärung.
  Explanation := Default(TAtlasDebugBannerExplanation);
  Explanation.Active := True;
  Explanation.Busy := True;
  Explanation.Headline := 'Atlas prüft';
  Explanation.WhereName := 'Kunde';
  FBar.SetExplanation(Explanation);
  Assert.AreEqual(4, FBar.Rows);
  Assert.AreEqual(TAtlasDebugExceptionBar.BarHeight(FBar.CurrentPPI, 4), FBar.Height);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).IsEmpty);
  // Fertig: Ergebniszeile, 8 Glieder (6 gezeigt, „… 2 weitere“), Knopfzeile.
  Explanation.Busy := False;
  Explanation.Headline := 'Auftrag.Kunde ist nil';
  for Index := 1 to 8 do
    Explanation.Lines := Explanation.Lines + [TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok,
      'Glied ' + IntToStr(Index))];
  Explanation.CopyText := 'Text';
  FBar.SetExplanation(Explanation);
  Assert.AreEqual(3 + 1 + 6 + 1 + 1, FBar.Rows);
  Assert.IsFalse(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).IsEmpty);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.Evaluate).IsEmpty, 'ohne Ausdruck kein Knopf');
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).Right <
    FBar.ActionRect(TAtlasDebugBarAction.CopyExplanation).Left);
  Assert.IsTrue(FBar.ActionRect(TAtlasDebugBarAction.WhereAssigned).Bottom <=
    FBar.ActionRect(TAtlasDebugBarAction.Continue).Top, 'über den Knöpfen der Leiste');
  Reported := TAtlasDebugBarAction.None;
  FBar.OnAction :=
    procedure(AAction: TAtlasDebugBarAction)
    begin
      Reported := AAction;
    end;
  FBar.Trigger(TAtlasDebugBarAction.Evaluate);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.None), Ord(Reported));
  FBar.Trigger(TAtlasDebugBarAction.CopyExplanation);
  Assert.AreEqual(Ord(TAtlasDebugBarAction.CopyExplanation), Ord(Reported));
  FBar.OnAction := nil;
  // Ohne Erklärung wieder drei Zeilen.
  FBar.SetExplanation(Default(TAtlasDebugBannerExplanation));
  Assert.AreEqual(3, FBar.Rows);
  Assert.AreEqual(TAtlasDebugExceptionBar.BarHeight(FBar.CurrentPPI), FBar.Height);
end;

end.
