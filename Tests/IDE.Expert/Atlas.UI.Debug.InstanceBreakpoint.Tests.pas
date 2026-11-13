unit Atlas.UI.Debug.InstanceBreakpoint.Tests;

// Dialog „Haltepunkt nur für ein Objekt“ (#857): Satz, Knöpfe in der
// gegebenen Reihenfolge, Liste erst mit Fenster, Knopf drücken, Doppelklick
// bzw. Eingabe wählt den ersten Knopf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasInstanceBreakpointDialogTests = class
  public
    [Test]
    procedure ButtonsInOrder;
    [Test]
    procedure FillOnceAndPress;
    [Test]
    procedure EnterPressesFirstButton;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Debug.InstanceBreakpoint;

function Dialog: TAtlasInstanceBreakpointDialog;
begin
  Result := TAtlasInstanceBreakpointDialog.CreateQuestion(nil, 'Titel', 'Bedingung für Kunde.pas:42',
    TArray<string>.Create('FNr = 4711', 'FName = ''Meier'''), TArray<string>.Create('Übernehmen', 'Abbrechen'), 1);
end;

procedure TAtlasInstanceBreakpointDialogTests.ButtonsInOrder;
var
  mDialog: TAtlasInstanceBreakpointDialog;
begin
  mDialog := Dialog;
  try
    Assert.AreEqual(2, Integer(Length(mDialog.Buttons)));
    Assert.AreEqual('Übernehmen', mDialog.Buttons[0].Caption);
    Assert.IsTrue(mDialog.Buttons[0].Default);
    Assert.IsTrue(mDialog.Buttons[1].Cancel);
    Assert.AreEqual('Bedingung für Kunde.pas:42', mDialog.SummaryLabel.Caption);
    Assert.AreEqual(-1, mDialog.Pressed, 'noch nichts gedrückt');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasInstanceBreakpointDialogTests.FillOnceAndPress;
var
  mDialog: TAtlasInstanceBreakpointDialog;
begin
  mDialog := Dialog;
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    mDialog.Fill;
    Assert.AreEqual(2, mDialog.ItemList.Items.Count, 'einmal gefüllt');
    Assert.AreEqual(0, mDialog.ItemList.ItemIndex);
    Assert.AreEqual('FName = ''Meier''', mDialog.ItemList.Items[1]);
    mDialog.Buttons[1].Click;
    Assert.AreEqual(1, mDialog.Pressed);
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
    mDialog.Press(5);
    Assert.AreEqual(1, mDialog.Pressed, 'außerhalb der Knöpfe');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasInstanceBreakpointDialogTests.EnterPressesFirstButton;
var
  mDialog: TAtlasInstanceBreakpointDialog;
  mKey: Char;
begin
  mDialog := Dialog;
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    mKey := #13;
    mDialog.ItemList.OnKeyPress(mDialog.ItemList, mKey);
    Assert.AreEqual(0, mDialog.Pressed);
    Assert.AreEqual(#0, mKey);
  finally
    mDialog.Free;
  end;
end;

end.
