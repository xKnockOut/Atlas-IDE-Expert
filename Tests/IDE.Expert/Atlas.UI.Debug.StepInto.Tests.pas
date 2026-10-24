unit Atlas.UI.Debug.StepInto.Tests;

// Gezielt hineinspringen (#836), Fensterteil: Beschriftung der Einträge mit
// Nummer und Art, Gründe für nicht wählbare, Wahl über Pfeile und Ziffern,
// Übernehmen und Abbrechen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStepIntoWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure CaptionsKindsAndReasons;
    [Test]
    procedure KeysSkipUnavailable;
    [Test]
    procedure DigitsAcceptAndCancel;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.StepInto,
  Atlas.UI.Strings,
  Atlas.UI.Debug.StepInto;

function Row(const ACaption: string; AKind: TAtlasStepKind; AAvailable: Boolean): TAtlasStepRow;
begin
  Result := Default(TAtlasStepRow);
  Result.Caption := ACaption;
  Result.Kind := AKind;
  Result.HasTarget := AAvailable;
  if AAvailable then
    Result.Location := 'Haupt.pas:12'
  else
    Result.Unavailable := TAtlasStepUnavailable.NoSource;
end;

function Sample: TArray<TAtlasStepRow>;
begin
  Result := [Row('TKunde.GetName', TAtlasStepKind.Getter, True), Row('Format', TAtlasStepKind.Call, False),
    Row('Pruefe', TAtlasStepKind.Call, True), Row('Speichere', TAtlasStepKind.Call, True)];
end;

function NewWindow: TAtlasStepIntoWindow;
begin
  Result := TAtlasStepIntoWindow.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Segoe UI', 9);
end;

procedure TAtlasStepIntoWindowTests.WarmUpFirstUse;
begin
  CaptionsKindsAndReasons;
  KeysSkipUnavailable;
end;

procedure TAtlasStepIntoWindowTests.CaptionsKindsAndReasons;
var
  Rows: TArray<TAtlasStepRow>;
  Item: TAtlasStepRow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Rows := Sample;
  Assert.AreEqual('1  TKunde.GetName  (Getter)', TAtlasStepIntoWindow.RowCaption(Rows, 0));
  Assert.AreEqual('2  Format', TAtlasStepIntoWindow.RowCaption(Rows, 1));
  Assert.AreEqual('ohne Quelltext', TAtlasStepIntoWindow.ReasonText(Rows[1]));
  Assert.AreEqual('', TAtlasStepIntoWindow.ReasonText(Rows[0]));
  Item := Row('TStammkunde.Speichere', TAtlasStepKind.Call, True);
  Item.Candidate := True;
  Assert.AreEqual('Überschreibung', TAtlasStepIntoWindow.KindText(Item));
  Item.Kind := TAtlasStepKind.Constructor_;
  Assert.AreEqual('Konstruktor, Überschreibung', TAtlasStepIntoWindow.KindText(Item));
  Item.Unavailable := TAtlasStepUnavailable.Library_;
  Assert.AreEqual('ohne Debug-DCUs', TAtlasStepIntoWindow.ReasonText(Item));
  Assert.AreEqual('', TAtlasStepIntoWindow.RowCaption(Rows, 9));
end;

procedure TAtlasStepIntoWindowTests.KeysSkipUnavailable;
var
  Window: TAtlasStepIntoWindow;
begin
  Window := NewWindow;
  try
    Window.ShowFor(Sample, Point(100, 100));
    try
      Assert.AreEqual(0, Window.Row);
      Assert.IsTrue(Window.MoveRow(1));
      Assert.AreEqual(2, Window.Row, 'Format ohne Quelltext wird übersprungen');
      Assert.IsTrue(Window.MoveRow(-1));
      Assert.AreEqual(0, Window.Row);
      Assert.IsFalse(Window.MoveRow(-1));
      Window.Select(1);
      Assert.AreEqual(0, Window.Row, 'nicht wählbar');
      Assert.IsTrue(Window.RowRect(3).Top > Window.RowRect(0).Top, 'untereinander');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasStepIntoWindowTests.DigitsAcceptAndCancel;
var
  Window: TAtlasStepIntoWindow;
  Accepted, Cancelled: Integer;
begin
  Accepted := -1;
  Cancelled := 0;
  Window := NewWindow;
  try
    Window.OnAccept :=
      procedure(AIndex: Integer)
      begin
        Accepted := AIndex;
      end;
    Window.OnCancel :=
      procedure
      begin
        Inc(Cancelled);
      end;
    Window.ShowFor(Sample, Point(100, 100));
    Assert.IsFalse(Window.AcceptDigit(2), 'Format ist nicht wählbar');
    Assert.IsTrue(Window.IsShown);
    Assert.IsTrue(Window.AcceptDigit(4));
    Assert.AreEqual(3, Accepted);
    Assert.IsFalse(Window.IsShown);
    Window.ShowFor(Sample, Point(100, 100));
    Window.Accept;
    Assert.AreEqual(0, Accepted);
    Window.ShowFor(Sample, Point(100, 100));
    Window.Cancel;
    Assert.AreEqual(1, Cancelled);
    Assert.IsFalse(Window.IsShown);
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStepIntoWindowTests);

end.
