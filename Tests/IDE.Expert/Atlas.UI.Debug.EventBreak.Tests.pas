unit Atlas.UI.Debug.EventBreak.Tests;

// Beim nächsten Ereignis anhalten (#856), Fensterteil: Wahl im Dialog und
// Leiste nach dem Halt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEventBreakWindowTests = class
  public
    /// <summary>Einmal-Belegungen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  Atlas.Core.Settings.EventBreakNames,
  Atlas.UI.Strings,
  Atlas.UI.Debug.EventBreak;

procedure TAtlasEventBreakWindowTests.WarmUpFirstUse;
begin
  DialogShowsAndReturnsChoice;
end;

procedure TAtlasEventBreakWindowTests.DialogShowsAndReturnsChoice;
var
  mDialog: TAtlasEventBreakDialog;
  mStart, mChoice: TAtlasEventChoice;
  mAsked: Integer;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mStart := TAtlasEventChoice.Defaults;
  mStart.Form := 'TfrmKunde';
  mAsked := 0;
  mDialog := TAtlasEventBreakDialog.CreateDialog(nil, mStart, TArray<string>.Create('TdmDaten', 'TfrmKunde'),
    TAtlasEventBreakSettings.cDefaultExcluded,
    function(const AChoice: TAtlasEventChoice): string
    begin
      Inc(mAsked);
      Result := IntToStr(mAsked);
    end);
  try
    mDialog.Prepare;
    Assert.IsTrue(mDialog.CategoryCheck(TAtlasEventCategory.Mouse).Checked);
    Assert.IsFalse(mDialog.CategoryCheck(TAtlasEventCategory.Timer).Checked);
    Assert.IsTrue(mDialog.AllRadio.Checked);
    Assert.AreEqual(1, mDialog.FormCombo.ItemIndex, 'gemerktes Formular');
    Assert.IsTrue(mAsked > 0, 'Zahl zur Wahl');
    mDialog.CategoryCheck(TAtlasEventCategory.Database).Checked := True;
    mDialog.FrequentCheck.Checked := True;
    mDialog.OneRadio.Checked := True;
    mChoice := mDialog.Choice;
    Assert.IsTrue(TAtlasEventCategory.Database in mChoice.Categories);
    Assert.IsTrue(mChoice.Frequent);
    Assert.AreEqual(Ord(TAtlasEventScope.OneForm), Ord(mChoice.Scope));
    Assert.AreEqual('TfrmKunde', mChoice.Form);
    mDialog.VisibleRadio.Checked := True;
    Assert.AreEqual(Ord(TAtlasEventScope.VisibleForms), Ord(mDialog.Choice.Scope));
    Assert.AreNotEqual('', mDialog.CountLabel.Caption);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasEventBreakWindowTests.DialogNeedsCategory;
var
  mDialog: TAtlasEventBreakDialog;
  mCategory: TAtlasEventCategory;
begin
  mDialog := TAtlasEventBreakDialog.CreateDialog(nil, TAtlasEventChoice.Defaults, nil, '', nil);
  try
    mDialog.Prepare;
    Assert.IsFalse(mDialog.OneRadio.Enabled, 'ohne Formulare');
    for mCategory := Low(TAtlasEventCategory) to High(TAtlasEventCategory) do
    begin
      mDialog.CategoryCheck(mCategory).Checked := False;
    end;
    Assert.IsFalse(mDialog.OkButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasEventBreakWindowTests.BarButtons;
var
  mBar: TAtlasEventBreakBar;
  mContinued, mClosed: Integer;
begin
  mContinued := 0;
  mClosed := 0;
  mBar := TAtlasEventBreakBar.Create(nil);
  try
    mBar.Colors := TAtlasColors.Light;
    mBar.SetScaling(96, 1, 'Segoe UI', 9);
    mBar.OnContinue :=
      procedure
      begin
        Inc(mContinued);
      end;
    mBar.OnClose :=
      procedure
      begin
        Inc(mClosed);
      end;
    mBar.ShowFor('btnSpeichern.OnClick → TfrmKunde.btnSpeichernClick', Point(100, 100));
    Assert.IsTrue(mBar.IsShown);
    Assert.IsTrue(mBar.CloseRect.Left > mBar.ContinueRect.Right, 'nebeneinander');
    mBar.KeepWatching;
    Assert.AreEqual(1, mContinued);
    Assert.IsFalse(mBar.IsShown);
    mBar.ShowFor('x', Point(100, 100));
    mBar.CloseBar;
    Assert.AreEqual(1, mClosed);
    Assert.IsFalse(mBar.IsShown);
  finally
    mBar.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventBreakWindowTests);

end.
