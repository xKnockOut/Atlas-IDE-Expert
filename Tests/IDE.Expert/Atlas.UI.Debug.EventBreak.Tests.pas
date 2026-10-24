unit Atlas.UI.Debug.EventBreak.Tests;

// Beim nächsten Ereignis anhalten (#856), Fensterteil: Wahl im Dialog und
// Leiste nach dem Halt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEventBreakWindowTests = class
  public
    [Test]
    procedure DialogShowsAndReturnsChoice;
    [Test]
    procedure DialogNeedsCategory;
    [Test]
    procedure BarButtons;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.EventBreak,
  Atlas.UI.Strings,
  Atlas.UI.Debug.EventBreak;

procedure TAtlasEventBreakWindowTests.DialogShowsAndReturnsChoice;
var
  Dialog: TAtlasEventBreakDialog;
  Start, Choice: TAtlasEventChoice;
  Asked: Integer;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Start := TAtlasEventChoice.Defaults;
  Start.Form := 'TfrmKunde';
  Asked := 0;
  Dialog := TAtlasEventBreakDialog.CreateDialog(nil, Start, TArray<string>.Create('TdmDaten', 'TfrmKunde'),
    TAtlasEventBreak.DefaultExcluded,
    function(const AChoice: TAtlasEventChoice): string
    begin
      Inc(Asked);
      Result := IntToStr(Asked);
    end);
  try
    Dialog.Prepare;
    Assert.IsTrue(Dialog.CategoryCheck(TAtlasEventCategory.Mouse).Checked);
    Assert.IsFalse(Dialog.CategoryCheck(TAtlasEventCategory.Timer).Checked);
    Assert.IsTrue(Dialog.AllRadio.Checked);
    Assert.AreEqual(1, Dialog.FormCombo.ItemIndex, 'gemerktes Formular');
    Assert.IsTrue(Asked > 0, 'Zahl zur Wahl');
    Dialog.CategoryCheck(TAtlasEventCategory.Database).Checked := True;
    Dialog.FrequentCheck.Checked := True;
    Dialog.OneRadio.Checked := True;
    Choice := Dialog.Choice;
    Assert.IsTrue(TAtlasEventCategory.Database in Choice.Categories);
    Assert.IsTrue(Choice.Frequent);
    Assert.AreEqual(Ord(TAtlasEventScope.OneForm), Ord(Choice.Scope));
    Assert.AreEqual('TfrmKunde', Choice.Form);
    Dialog.VisibleRadio.Checked := True;
    Assert.AreEqual(Ord(TAtlasEventScope.VisibleForms), Ord(Dialog.Choice.Scope));
    Assert.AreNotEqual('', Dialog.CountLabel.Caption);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasEventBreakWindowTests.DialogNeedsCategory;
var
  Dialog: TAtlasEventBreakDialog;
  Category: TAtlasEventCategory;
begin
  Dialog := TAtlasEventBreakDialog.CreateDialog(nil, TAtlasEventChoice.Defaults, nil, '', nil);
  try
    Dialog.Prepare;
    Assert.IsFalse(Dialog.OneRadio.Enabled, 'ohne Formulare');
    for Category := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
      Dialog.CategoryCheck(Category).Checked := False;
    Assert.IsFalse(Dialog.OkButton.Enabled);
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasEventBreakWindowTests.BarButtons;
var
  Bar: TAtlasEventBreakBar;
  Continued, Closed: Integer;
begin
  Continued := 0;
  Closed := 0;
  Bar := TAtlasEventBreakBar.Create(nil);
  try
    Bar.Colors := TAtlasColors.Light;
    Bar.SetScaling(96, 1, 'Segoe UI', 9);
    Bar.OnContinue :=
      procedure
      begin
        Inc(Continued);
      end;
    Bar.OnClose :=
      procedure
      begin
        Inc(Closed);
      end;
    Bar.ShowFor('btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick', Point(100, 100));
    Assert.IsTrue(Bar.IsShown);
    Assert.IsTrue(Bar.CloseRect.Left > Bar.ContinueRect.Right, 'nebeneinander');
    Bar.KeepWatching;
    Assert.AreEqual(1, Continued);
    Assert.IsFalse(Bar.IsShown);
    Bar.ShowFor('x', Point(100, 100));
    Bar.CloseBar;
    Assert.AreEqual(1, Closed);
    Assert.IsFalse(Bar.IsShown);
  finally
    Bar.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventBreakWindowTests);

end.
