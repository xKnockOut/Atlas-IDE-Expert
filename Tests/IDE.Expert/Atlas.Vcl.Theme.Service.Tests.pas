unit Atlas.Vcl.Theme.Service.Tests;

// Themendienst der Atlas-Fenster (#2061): ohne Install helle Farben und kein
// Anwenden, mit Install Farben und Anwenden über die Haken der IDE-Schicht,
// Abonnenten bei jedem Wechsel bis zum Abmelden, Fehler ins Protokoll,
// Textfarben der Meldungen aus der Palette, Dialogschrift, Fensterfarben aus
// dem Stil des Steuerelements (nicht der festen Palette), Systemfarben über den
// Stil und Schriftfarben, die dem Thema folgen, bis das Steuerelement geht.

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
    [Test]
    procedure WindowColorsComeFromStyleOfControl;
    [Test]
    procedure SystemColorComesFromStyleOfControl;
    [Test]
    procedure FontColorFollowsThemeUntilDefault;
    [Test]
    procedure FontColorEndsWithControl;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Themes,
  Atlas.Plugin.Style.Palette,
  Atlas.Plugin.Style.Signal,
  Atlas.Vcl.Theme.Service;

{ TAtlasUiThemeTests }

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
    // Nicht Assert.Pass: Die Ausnahme dahinter zählt der Leckmonitor als Leck.
    Assert.AreEqual(Integer(TAtlasColors.Light.Surface), Integer(TAtlasUiTheme.Colors.Surface), 'unverändert');
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
    Assert.AreSame(mForm, mApplied);
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

procedure TAtlasUiThemeTests.WindowColorsComeFromStyleOfControl;
var
  mForm: TForm;
  mColors: TAtlasColors;
begin
  // Auch mit installierter Atlas-Quelle: Fläche und Schrift aus dem Stil, nicht aus der Palette.
  TAtlasUiTheme.Install(
    function: TAtlasColors
    begin
      Result := TAtlasColors.Dark;
    end, nil, nil);
  mForm := TForm.CreateNew(nil);
  try
    mColors := TAtlasUiTheme.WindowColors(mForm);
    Assert.AreEqual(Integer(ColorToRGB(StyleServices(mForm).GetSystemColor(clWindow))), Integer(mColors.Surface));
    Assert.AreEqual(Integer(ColorToRGB(StyleServices(mForm).GetSystemColor(clWindowText))), Integer(mColors.Text));
    mColors := TAtlasUiTheme.WindowColors(nil);
    Assert.AreEqual(Integer(ColorToRGB(StyleServices.GetSystemColor(clWindow))), Integer(mColors.Surface), 'ohne');
  finally
    mForm.Free;
  end;
end;

procedure TAtlasUiThemeTests.SystemColorComesFromStyleOfControl;
var
  mForm: TForm;
begin
  mForm := TForm.CreateNew(nil);
  try
    Assert.AreEqual(Integer(ColorToRGB(StyleServices(mForm).GetSystemColor(clGrayText))),
      Integer(TAtlasUiTheme.SystemColor(mForm, clGrayText)));
    Assert.AreEqual(Integer(ColorToRGB(StyleServices.GetSystemColor(clHighlight))),
      Integer(TAtlasUiTheme.SystemColor(nil, clHighlight)), 'ohne Steuerelement');
    // Keine Systemfarbe: unverändert.
    Assert.AreEqual(Integer(TColor($123456)), Integer(TAtlasUiTheme.SystemColor(mForm, TColor($123456))));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasUiThemeTests.FontColorFollowsThemeUntilDefault;
var
  mForm: TForm;
  mLabel: TLabel;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TLabel.Create(mForm);
    mLabel.Parent := mForm;
    TAtlasUiTheme.UseFontColor(mLabel, clGrayText);
    // Ohne seFont, sonst übergeht der Stil Font.Color.
    Assert.IsFalse(seFont in mLabel.StyleElements);
    Assert.AreEqual(Integer(TAtlasUiTheme.SystemColor(mLabel, clGrayText)), Integer(mLabel.Font.Color));
    mLabel.Font.Color := TColor($123456);
    TAtlasUiTheme.Changed;
    Assert.AreEqual(Integer(TAtlasUiTheme.SystemColor(mLabel, clGrayText)), Integer(mLabel.Font.Color), 'Wechsel');
    TAtlasUiTheme.UseFontColor(mLabel, clHotLight);
    Assert.AreEqual(Integer(TAtlasUiTheme.SystemColor(mLabel, clHotLight)), Integer(mLabel.Font.Color), 'ersetzt');
    Assert.AreEqual(1, mLabel.ComponentCount, 'ein Hüter');
    TAtlasUiTheme.UseFontColor(mLabel, clDefault);
    Assert.IsTrue(seFont in mLabel.StyleElements);
    Assert.AreEqual(Integer(clWindowText), Integer(mLabel.Font.Color));
    Assert.AreEqual(0, mLabel.ComponentCount, 'Hüter weg');
    mLabel.Font.Color := TColor($123456);
    TAtlasUiTheme.Changed;
    Assert.AreEqual(Integer(TColor($123456)), Integer(mLabel.Font.Color), 'folgt nicht mehr');
    TAtlasUiTheme.UseFontColor(nil, clGrayText);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasUiThemeTests.FontColorEndsWithControl;
var
  mForm: TForm;
  mLabel: TLabel;
  mKeeper: TComponent;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TLabel.Create(mForm);
    mLabel.Parent := mForm;
    TAtlasUiTheme.UseFontColor(mLabel, clGrayText);
    mKeeper := mLabel.Components[0];
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mKeeper));
    mLabel.Free;
    Assert.IsFalse(TAtlasUiTheme.Subscribed(mKeeper), 'abgemeldet');
    // Erreicht nichts Freigegebenes mehr.
    TAtlasUiTheme.Changed;
    Assert.AreEqual(0, mForm.ComponentCount);
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUiThemeTests);

end.
