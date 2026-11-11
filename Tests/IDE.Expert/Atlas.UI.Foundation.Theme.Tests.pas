unit Atlas.UI.Foundation.Theme.Tests;

// Themendienst der Atlas-Fenster (#2061): ohne Install helle Farben und kein
// Anwenden, mit Install Farben und Anwenden über die Haken der IDE-Schicht,
// Abonnenten bei jedem Wechsel bis zum Abmelden, Fehler ins Protokoll,
// Textfarben der Meldungen aus der Palette, Dialogschrift.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUiThemeTests = class
  private
    FLog: string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutInstallUsesLightColorsAndAppliesNothing;
    [Test]
    procedure InstalledSourceAndApplierAreUsed;
    [Test]
    procedure SubscribersFollowChangesUntilUnsubscribed;
    [Test]
    procedure FailuresGoToLog;
    [Test]
    procedure TextColorsComeFromPalette;
    [Test]
    procedure DialogFontIsSegoeNine;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

procedure TAtlasUiThemeTests.TearDown;
begin
  TAtlasUiTheme.Uninstall;
  FLog := '';
end;

procedure TAtlasUiThemeTests.WithoutInstallUsesLightColorsAndAppliesNothing;
var
  mForm: TForm;
begin
  TAtlasUiTheme.Uninstall;
  Assert.IsFalse(TAtlasUiTheme.Colors.IsDark);
  Assert.AreEqual(Integer(TAtlasColors.Light.Surface), Integer(TAtlasUiTheme.Colors.Surface));
  mForm := TForm.CreateNew(nil);
  try
    TAtlasUiTheme.Apply(mForm);
    TAtlasUiTheme.Apply(nil);
    Assert.Pass;
  finally
    mForm.Free;
  end;
end;

procedure TAtlasUiThemeTests.InstalledSourceAndApplierAreUsed;
var
  mForm: TForm;
  mApplied: TWinControl;
begin
  mApplied := nil;
  TAtlasUiTheme.Install(
    function: TAtlasColors
    begin
      Result := TAtlasColors.Dark;
    end,
    procedure(AControl: TWinControl)
    begin
      mApplied := AControl;
    end, nil);
  Assert.IsTrue(TAtlasUiTheme.Colors.IsDark);
  mForm := TForm.CreateNew(nil);
  try
    TAtlasUiTheme.Apply(mForm);
    Assert.IsTrue(mApplied = mForm);
  finally
    mForm.Free;
  end;
  TAtlasUiTheme.Uninstall;
  Assert.IsFalse(TAtlasUiTheme.Colors.IsDark);
end;

procedure TAtlasUiThemeTests.SubscribersFollowChangesUntilUnsubscribed;
var
  mOwner: TObject;
  mCount: Integer;
begin
  mCount := 0;
  mOwner := TObject.Create;
  try
    TAtlasUiTheme.Subscribe(mOwner,
      procedure
      begin
        Inc(mCount);
      end);
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mOwner));
    TAtlasUiTheme.Changed;
    TAtlasUiTheme.Changed;
    Assert.AreEqual(2, mCount);
    TAtlasUiTheme.Unsubscribe(mOwner);
    TAtlasUiTheme.Changed;
    Assert.AreEqual(2, mCount);
    Assert.IsFalse(TAtlasUiTheme.Subscribed(mOwner));
  finally
    TAtlasUiTheme.Unsubscribe(mOwner);
    mOwner.Free;
  end;
end;

procedure TAtlasUiThemeTests.FailuresGoToLog;
var
  mOwner: TObject;
begin
  mOwner := TObject.Create;
  try
    TAtlasUiTheme.Install(nil, nil,
      procedure(AFailure: string)
      begin
        FLog := FLog + AFailure;
      end);
    TAtlasUiTheme.Subscribe(mOwner,
      procedure
      begin
        raise EArgumentException.Create('kaputt');
      end);
    TAtlasUiTheme.Changed;
    Assert.AreEqual('EArgumentException: kaputt', FLog);
  finally
    TAtlasUiTheme.Unsubscribe(mOwner);
    mOwner.Free;
  end;
end;

procedure TAtlasUiThemeTests.TextColorsComeFromPalette;
var
  mDark: TAtlasColors;
begin
  mDark := TAtlasColors.Dark;
  TAtlasUiTheme.Install(
    function: TAtlasColors
    begin
      Result := TAtlasColors.Dark;
    end, nil, nil);
  Assert.AreEqual(Integer(TColor(mDark.Error)), Integer(TAtlasUiTheme.TextColor(TAtlasSignalKind.Error)));
  Assert.AreEqual(Integer(TColor(mDark.Warn)), Integer(TAtlasUiTheme.TextColor(TAtlasSignalKind.Warn)));
  Assert.AreEqual(Integer(TColor(mDark.Add)), Integer(TAtlasUiTheme.TextColor(TAtlasSignalKind.Ok)));
  // Hinweise ohne Aussage zeichnet der Stil.
  Assert.AreEqual(Integer(clWindowText), Integer(TAtlasUiTheme.TextColor(TAtlasSignalKind.Info)));
  Assert.IsTrue(TAtlasUiTheme.UsesStyleText(TAtlasSignalKind.Idle));
  Assert.IsFalse(TAtlasUiTheme.UsesStyleText(TAtlasSignalKind.Error));
end;

procedure TAtlasUiThemeTests.DialogFontIsSegoeNine;
var
  mFont: TFont;
begin
  mFont := TFont.Create;
  try
    mFont.Style := [fsBold];
    TAtlasUiTheme.AssignDialogFont(mFont);
    Assert.AreEqual(string(TAtlasUiTheme.cFontName), string(mFont.Name));
    Assert.AreEqual(TAtlasUiTheme.cFontSize, mFont.Size);
    Assert.IsTrue(fsBold in mFont.Style);
    TAtlasUiTheme.AssignDialogFont(nil);
  finally
    mFont.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUiThemeTests);

end.
