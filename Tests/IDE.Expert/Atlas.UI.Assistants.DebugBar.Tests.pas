unit Atlas.UI.Assistants.DebugBar.Tests;

// Leiste „KI-Assistent debuggt“ (#1874): Knöpfe rechts in fester Reihenfolge, „Übernehmen“ nur mit eigener Sitzung
// des Assistenten, Klicks, feste Höhe.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Assistants.DebugBar;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantDebugBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasAssistantDebugBar;
    FClicked: string;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ButtonsStandRightInOrder;
    /// <summary>Akzeptanzkriterium: ohne Sitzung des Assistenten (nur „Pause für KI“) kein „Übernehmen“.</summary>
    [Test]
    procedure TakeOverOnlyWithOwnSession;
    [Test]
    procedure ClicksReachTheirButtons;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls;

function Sample(ACanTakeOver: Boolean): TAtlasAssistantDebugView;
begin
  Result := Default(TAtlasAssistantDebugView);
  Result.Text := 'Agent debuggt · 3 Aufträge · zuletzt debug_step';
  Result.PauseCaption := 'Pause für KI';
  Result.PauseHint := 'Pause-Hinweis';
  Result.TakeOverCaption := 'Übernehmen';
  Result.TakeOverHint := 'Übernehmen-Hinweis';
  Result.CanTakeOver := ACanTakeOver;
end;

function Middle(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

{ TAtlasAssistantDebugBarTests }

procedure TAtlasAssistantDebugBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 200;
  FBar := TAtlasAssistantDebugBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
  FClicked := '';
end;

procedure TAtlasAssistantDebugBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
  FClicked := '';
end;

procedure TAtlasAssistantDebugBarTests.ButtonsStandRightInOrder;
var
  mHeight: Integer;
begin
  mHeight := FBar.Height;
  FBar.SetView(Sample(True));
  Assert.AreEqual(mHeight, FBar.Height, 'eine Zeile');
  Assert.IsFalse(FBar.ButtonRect(TAtlasAssistantDebugButton.Pause).IsEmpty);
  Assert.IsTrue(FBar.ButtonRect(TAtlasAssistantDebugButton.Pause).Right <=
    FBar.ButtonRect(TAtlasAssistantDebugButton.TakeOver).Left, 'Pause vor Übernehmen');
  Assert.IsTrue(FBar.ButtonRect(TAtlasAssistantDebugButton.TakeOver).Right <= FBar.ClientWidth, 'in der Leiste');
end;

procedure TAtlasAssistantDebugBarTests.TakeOverOnlyWithOwnSession;
begin
  FBar.SetView(Sample(False));
  Assert.IsTrue(FBar.ButtonRect(TAtlasAssistantDebugButton.TakeOver).IsEmpty);
  Assert.IsFalse(FBar.ButtonRect(TAtlasAssistantDebugButton.Pause).IsEmpty);
end;

procedure TAtlasAssistantDebugBarTests.ClicksReachTheirButtons;
var
  mPoint: TPoint;
begin
  FBar.SetView(Sample(True));
  FBar.OnButton :=
    procedure(AButton: TAtlasAssistantDebugButton)
    begin
      FClicked := FClicked + IntToStr(Ord(AButton));
    end;
  mPoint := Middle(FBar.ButtonRect(TAtlasAssistantDebugButton.Pause));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  mPoint := Middle(FBar.ButtonRect(TAtlasAssistantDebugButton.TakeOver));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  FBar.ClickAt(2, 2);
  Assert.AreEqual('01', FClicked, 'Text links ist kein Knopf');
  FBar.OnButton := nil;
end;

end.
