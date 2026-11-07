unit Atlas.UI.Debug.StepInto.Tests;

// Gezielt hineinspringen (#836), Fensterteil: Beschriftung der Einträge mit
// Nummer und Art, Gründe für nicht wählbare, Wahl über Pfeile und Ziffern,
// Übernehmen und Abbrechen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
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
  begin
    Result.Location := 'Haupt.pas:12';
  end
  else
  begin
    Result.Unavailable := TAtlasStepUnavailable.NoSource;
  end;
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
  mRows: TArray<TAtlasStepRow>;
  mItem: TAtlasStepRow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mRows := Sample;
  Assert.AreEqual('1  TKunde.GetName  (Getter)', TAtlasStepIntoWindow.RowCaption(mRows, 0));
  Assert.AreEqual('2  Format', TAtlasStepIntoWindow.RowCaption(mRows, 1));
  Assert.AreEqual('ohne Quelltext', TAtlasStepIntoWindow.ReasonText(mRows[1]));
  Assert.AreEqual('', TAtlasStepIntoWindow.ReasonText(mRows[0]));
  mItem := Row('TStammkunde.Speichere', TAtlasStepKind.Call, True);
  mItem.Candidate := True;
  Assert.AreEqual('Überschreibung', TAtlasStepIntoWindow.KindText(mItem));
  mItem.Kind := TAtlasStepKind.Constructor_;
  Assert.AreEqual('Konstruktor, Überschreibung', TAtlasStepIntoWindow.KindText(mItem));
  mItem.Unavailable := TAtlasStepUnavailable.Library_;
  Assert.AreEqual('ohne Debug-DCUs', TAtlasStepIntoWindow.ReasonText(mItem));
  Assert.AreEqual('', TAtlasStepIntoWindow.RowCaption(mRows, 9));
end;

procedure TAtlasStepIntoWindowTests.KeysSkipUnavailable;
var
  mWindow: TAtlasStepIntoWindow;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowFor(Sample, Point(100, 100));
    try
      Assert.AreEqual(0, mWindow.Row);
      Assert.IsTrue(mWindow.MoveRow(1));
      Assert.AreEqual(2, mWindow.Row, 'Format ohne Quelltext wird übersprungen');
      Assert.IsTrue(mWindow.MoveRow(-1));
      Assert.AreEqual(0, mWindow.Row);
      Assert.IsFalse(mWindow.MoveRow(-1));
      mWindow.Select(1);
      Assert.AreEqual(0, mWindow.Row, 'nicht wählbar');
      Assert.IsTrue(mWindow.RowRect(3).Top > mWindow.RowRect(0).Top, 'untereinander');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasStepIntoWindowTests.DigitsAcceptAndCancel;
var
  mWindow: TAtlasStepIntoWindow;
  mAccepted, mCancelled: Integer;
begin
  mAccepted := -1;
  mCancelled := 0;
  mWindow := NewWindow;
  try
    mWindow.OnAccept :=
      procedure(AIndex: Integer)
      begin
        mAccepted := AIndex;
      end;
    mWindow.OnCancel :=
      procedure
      begin
        Inc(mCancelled);
      end;
    mWindow.ShowFor(Sample, Point(100, 100));
    Assert.IsFalse(mWindow.AcceptDigit(2), 'Format ist nicht wählbar');
    Assert.IsTrue(mWindow.IsShown);
    Assert.IsTrue(mWindow.AcceptDigit(4));
    Assert.AreEqual(3, mAccepted);
    Assert.IsFalse(mWindow.IsShown);
    mWindow.ShowFor(Sample, Point(100, 100));
    mWindow.Accept;
    Assert.AreEqual(0, mAccepted);
    mWindow.ShowFor(Sample, Point(100, 100));
    mWindow.Cancel;
    Assert.AreEqual(1, mCancelled);
    Assert.IsFalse(mWindow.IsShown);
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStepIntoWindowTests);

end.
