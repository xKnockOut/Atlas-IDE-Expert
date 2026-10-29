unit Atlas.UI.Editor.Bar.Tests;

// Gemeinsamer Vorfahr der Editorleisten (#1248) an einer Probeleiste mit zwei
// Teilen (linke und rechte Hälfte): feste Höhe nach DPI, Klick beim
// Loslassen trotz Mausverlassen, Abbruch bei anderem Teil, kein zweiter Klick
// nach Doppelklick, Hervorhebung und Tooltip, Kontextmenü bleibt in der
// Leiste, OnDisabled über VCL und EnableWindow je einmal.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Editor.Bar;

type
  [TestFixture]
  TAtlasEditorBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasEditorBar;
  public
    /// <summary>Erste Benutzung (Formular, Leiste) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HeightFollowsDpiOnly;
    [Test]
    procedure ClickOnReleaseSurvivesMouseLeave;
    [Test]
    procedure HoverSetsHotAndHint;
    [Test]
    procedure ContextMenuStaysInBar;
    [Test]
    procedure ReportsDisablingOnce;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls;

type
  /// <summary>Zwei Teile: linke Hälfte 0, rechte Hälfte 1; zählt Klicks und Menüs.</summary>
  TProbeBar = class(TAtlasEditorBar)
  protected
    class function BaseHeight: Integer; override;
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    procedure ContextMenu(const APoint: TPoint; APart: Integer); override;
    function KeyboardMenuPoint: TPoint; override;
  public
    Clicks: TArray<Integer>;
    MenuPart: Integer;
    MenuCount: Integer;
    function HotPart: Integer;
    procedure SetFixed(AValue: Boolean);
  end;

class function TProbeBar.BaseHeight: Integer;
begin
  Result := 20;
end;

function TProbeBar.PartAt(X, Y: Integer): Integer;
begin
  if (X < 0) or (Y < 0) or (X >= ClientWidth) or (Y >= ClientHeight) then
    Exit(PartNone);
  if X < ClientWidth div 2 then
    Result := 0
  else
    Result := 1;
end;

function TProbeBar.PartHint(APart: Integer): string;
begin
  if APart = PartNone then
    Result := ''
  else
    Result := 'Teil ' + IntToStr(APart);
end;

procedure TProbeBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
begin
  Clicks := Clicks + [APart];
end;

procedure TProbeBar.ContextMenu(const APoint: TPoint; APart: Integer);
begin
  Inc(MenuCount);
  MenuPart := APart;
end;

function TProbeBar.KeyboardMenuPoint: TPoint;
begin
  Result := Point(ClientWidth - 1, 1);
end;

function TProbeBar.HotPart: Integer;
begin
  Result := Hot;
end;

procedure TProbeBar.SetFixed(AValue: Boolean);
begin
  FixedHeight := AValue;
end;

/// <summary>Punkt als lParam einer Mausnachricht.</summary>
function MousePoint(X, Y: Integer): LPARAM;
begin
  Result := MakeLParam(Word(X), Word(Y));
end;

function Probe(ABar: TAtlasEditorBar): TProbeBar;
begin
  Result := ABar as TProbeBar;
end;

procedure TAtlasEditorBarTests.WarmUpFirstUse;
begin
  SetUp;
  try
    HeightFollowsDpiOnly;
  finally
    TearDown;
  end;
end;

procedure TAtlasEditorBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 400;
  FForm.Height := 200;
  FBar := TProbeBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
end;

procedure TAtlasEditorBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasEditorBarTests.HeightFollowsDpiOnly;
var
  mHeight: Integer;
begin
  mHeight := FBar.Height;
  Assert.AreEqual(TProbeBar.BarHeight(FBar.CurrentPPI), mHeight);
  Assert.AreEqual(40, TProbeBar.BarHeight(192), 'doppelte DPI, doppelte Höhe');
  Assert.AreEqual(20, TProbeBar.BarHeight(72), 'nie kleiner als bei 96 DPI');
  FBar.Height := mHeight * 2;
  Assert.AreEqual(mHeight, FBar.Height, 'eine Zeile, nie höher');
  Probe(FBar).SetFixed(False);
  FBar.Align := alNone;
  FBar.Height := mHeight * 2;
  Assert.AreEqual(mHeight * 2, FBar.Height, 'ohne feste Höhe bestimmt das Elternteil');
  Probe(FBar).SetFixed(True);
  Assert.AreEqual(mHeight, FBar.Height, 'wieder fest');
end;

procedure TAtlasEditorBarTests.ClickOnReleaseSurvivesMouseLeave;
var
  mLeft, mRight: LPARAM;
begin
  mLeft := MousePoint(10, 5);
  mRight := MousePoint(FBar.ClientWidth - 10, 5);
  // Drücken, Mausverlassen (Mausfang, Fokus in den Editor), Loslassen auf demselben Teil.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mLeft);
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  Assert.AreEqual(0, Integer(Length(Probe(FBar).Clicks)), 'erst beim Loslassen');
  FBar.Perform(WM_LBUTTONUP, 0, mLeft);
  Assert.AreEqual(1, Integer(Length(Probe(FBar).Clicks)), 'Klick trotz Mausverlassen');
  Assert.AreEqual(0, Probe(FBar).Clicks[0]);
  // Ohne gesehenes Drücken zählt das Loslassen.
  FBar.Perform(WM_LBUTTONUP, 0, mRight);
  Assert.AreEqual(2, Integer(Length(Probe(FBar).Clicks)), 'Loslassen ohne Drücken');
  Assert.AreEqual(1, Probe(FBar).Clicks[1]);
  // Auf einem Teil gedrückt, auf dem anderen losgelassen: kein Klick; danach gilt der nächste wieder.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mLeft);
  FBar.Perform(WM_LBUTTONUP, 0, mRight);
  Assert.AreEqual(2, Integer(Length(Probe(FBar).Clicks)), 'auf anderem Teil losgelassen');
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mRight);
  FBar.Perform(WM_LBUTTONUP, 0, mRight);
  Assert.AreEqual(3, Integer(Length(Probe(FBar).Clicks)), 'nächster Klick');
  // Doppelklick: Das zweite Loslassen ist kein weiterer Klick.
  FBar.Perform(WM_LBUTTONDBLCLK, MK_LBUTTON, mRight);
  FBar.Perform(WM_LBUTTONUP, 0, mRight);
  Assert.AreEqual(3, Integer(Length(Probe(FBar).Clicks)), 'Doppelklick');
  // Rechte Taste klickt nicht.
  FBar.Perform(WM_RBUTTONDOWN, MK_RBUTTON, mLeft);
  FBar.Perform(WM_RBUTTONUP, 0, mLeft);
  Assert.AreEqual(3, Integer(Length(Probe(FBar).Clicks)), 'rechte Taste');
  Probe(FBar).Clicks := nil;
end;

procedure TAtlasEditorBarTests.HoverSetsHotAndHint;
begin
  Assert.AreEqual(TAtlasEditorBar.PartNone, Probe(FBar).HotPart);
  FBar.Perform(WM_MOUSEMOVE, 0, MousePoint(FBar.ClientWidth - 5, 5));
  Assert.AreEqual(1, Probe(FBar).HotPart);
  Assert.AreEqual('Teil 1', FBar.Hint);
  Assert.AreEqual(Integer(crHandPoint), Integer(FBar.Cursor));
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  Assert.AreEqual(TAtlasEditorBar.PartNone, Probe(FBar).HotPart, 'Verlassen löscht die Hervorhebung');
end;

procedure TAtlasEditorBarTests.ContextMenuStaysInBar;
var
  mScreen: TPoint;
  mResult: LRESULT;
begin
  mScreen := FBar.ClientToScreen(Point(10, 5));
  mResult := FBar.Perform(WM_CONTEXTMENU, WPARAM(FBar.Handle), MakeLParam(Word(mScreen.X), Word(mScreen.Y)));
  Assert.AreEqual(1, Integer(mResult), 'behandelt, nicht an das Elternfenster');
  Assert.AreEqual(1, Probe(FBar).MenuCount);
  Assert.AreEqual(0, Probe(FBar).MenuPart);
  // Von der Tastatur: am Ort der Leiste (hier rechts).
  FBar.Perform(WM_CONTEXTMENU, WPARAM(FBar.Handle), LPARAM(-1));
  Assert.AreEqual(2, Probe(FBar).MenuCount);
  Assert.AreEqual(1, Probe(FBar).MenuPart);
end;

procedure TAtlasEditorBarTests.ReportsDisablingOnce;
var
  mCalls: Integer;
  mEnabledAtCall: Boolean;
begin
  mCalls := 0;
  mEnabledAtCall := False;
  FBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      Inc(mCalls);
      mEnabledAtCall := TControl(ASender).Enabled;
    end;
  // Über die VCL: vor dem Sperren gemeldet, WM_ENABLE danach meldet nicht noch einmal.
  FBar.Enabled := False;
  Assert.AreEqual(1, mCalls);
  Assert.IsTrue(mEnabledAtCall, 'gemeldet, bevor gesperrt');
  FBar.Enabled := True;
  Assert.AreEqual(1, mCalls, 'Freigeben meldet nichts');
  // An der VCL vorbei.
  EnableWindow(FBar.Handle, False);
  Assert.AreEqual(2, mCalls, 'EnableWindow');
  EnableWindow(FBar.Handle, True);
  Assert.AreEqual(2, mCalls);
  FBar.OnDisabled := nil;
end;

end.
