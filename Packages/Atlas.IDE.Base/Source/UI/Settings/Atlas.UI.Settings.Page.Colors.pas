unit Atlas.UI.Settings.Page.Colors;

// Reiter „Farben“: eigene Paarfarben je Thema und ihre Reihenfolge.

interface

uses
  System.Classes,
  System.UITypes,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Farben“: eigene Paarfarben je Thema und ihre Reihenfolge.</summary>
  TAtlasSettingsColorsPart = class(TAtlasSettingsPagePart)
  private
    // Eigene Paarfarben je Thema, eine Fläche je Tiefe.
    FLightSwatches: array[0..4] of TShape;
    FDarkSwatches: array[0..4] of TShape;
    // Eigene Farbe lokaler Routinen je Thema (#1788).
    FNestedLight: array[0..0] of TShape;
    FNestedDark: array[0..0] of TShape;
    /// <summary>Zeile mit Beschriftung und fünf Farbflächen.</summary>
    procedure AddSwatches(const ACaption: string; var ASwatches: array of TShape);
    procedure SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ResetColorsClick(Sender: TObject);
    class procedure ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors); static;
    /// <summary>Farben der Flächen als Einstellung; gleich der Palette = leer.</summary>
    class function PairsSetting(const ASwatches: array of TShape; const ADefault: TAtlasPairColors): string; static;
    /// <summary>Farbe der Fläche als Einstellung; gleich ADefault = leer (#1788).</summary>
    class function ColorSetting(ASwatch: TShape; ADefault: TAtlasColor): string; static;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

{ TAtlasSettingsColorsPart }

procedure TAtlasSettingsColorsPart.Build;
var
  mPanel: TWinControl;
  mTitle: TLabel;
  mButton: TButton;
begin
  // Eigene Paarfarben und deren Reihenfolge je Thema.
  AddSheet(TAtlasTextId.SettingsTabColors);
  AddSwatches(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairColorsLight), FLightSwatches);
  AddSwatches(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairColorsDark), FDarkSwatches);
  AddSwatches(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutineColorLight), FNestedLight);
  AddSwatches(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutineColorDark), FNestedDark);
  mPanel := AddPanel(22);
  mTitle := TLabel.Create(FPage);
  mTitle.Parent := mPanel;
  mTitle.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairColorsHint);
  mTitle.Left := 0;
  mTitle.Top := mTitle.ScaleValue(3);
  mTitle.Font.Color := clGrayText;
  mPanel := AddPanel(32);
  mButton := TButton.Create(FPage);
  mButton.Parent := mPanel;
  mButton.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairColorsReset);
  mButton.Left := 0;
  mButton.Top := mButton.ScaleValue(3);
  mButton.Width := mButton.ScaleValue(150);
  mButton.OnClick := ResetColorsClick;
  Attach(mPanel, FLightSwatches[0]);
end;

procedure TAtlasSettingsColorsPart.BindMarks;
begin
  FPage.Marks.Bind(FLightSwatches[0], ['PairColorsLight']);
  FPage.Marks.Bind(FDarkSwatches[0], ['PairColorsDark']);
  FPage.Marks.Bind(FNestedLight[0], ['NestedRoutineColorLight']);
  FPage.Marks.Bind(FNestedDark[0], ['NestedRoutineColorDark']);
end;

procedure TAtlasSettingsColorsPart.AddSwatches(const ACaption: string; var ASwatches: array of TShape);
var
  mPanel: TWinControl;
  mCaption: TLabel;
  mIndex: Integer;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  for mIndex := 0 to High(ASwatches) do
  begin
    ASwatches[mIndex] := TShape.Create(FPage);
    ASwatches[mIndex].Parent := mPanel;
    ASwatches[mIndex].SetBounds(cFieldLeft + mIndex * 34, 1, 28, 22);
    ASwatches[mIndex].Pen.Color := clGray;
    ASwatches[mIndex].Cursor := crHandPoint;
    ASwatches[mIndex].Hint := IntToStr(mIndex + 1);
    ASwatches[mIndex].ShowHint := True;
    ASwatches[mIndex].OnMouseDown := SwatchMouseDown;
  end;
end;

procedure TAtlasSettingsColorsPart.SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mDialog: TColorDialog;
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mDialog := TColorDialog.Create(nil);
  try
    mDialog.Color := TShape(Sender).Brush.Color;
    mDialog.Options := mDialog.Options + [cdFullOpen];
    if mDialog.Execute then
    begin
      TShape(Sender).Brush.Color := mDialog.Color;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSettingsColorsPart.ResetColorsClick(Sender: TObject);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.Pairs);
  FNestedLight[0].Brush.Color := TColor(TAtlasColors.Light.NestedRoutine);
  FNestedDark[0].Brush.Color := TColor(TAtlasColors.Dark.NestedRoutine);
end;

class procedure TAtlasSettingsColorsPart.ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASwatches) do
  begin
    ASwatches[mIndex].Brush.Color := TColor(APairs[mIndex]);
  end;
end;

class function TAtlasSettingsColorsPart.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TAtlasPairColors): string;
var
  mPairs: TAtlasPairColors;
  mIndex: Integer;
begin
  for mIndex := 0 to High(mPairs) do
  begin
    mPairs[mIndex] := TAtlasColor(ColorToRGB(ASwatches[mIndex].Brush.Color));
  end;
  Result := TAtlasColors.PairsText(mPairs);
  if Result = TAtlasColors.PairsText(ADefault) then
  begin
    Result := '';
  end;
end;

class function TAtlasSettingsColorsPart.ColorSetting(ASwatch: TShape; ADefault: TAtlasColor): string;
var
  mColor: TAtlasColor;
begin
  mColor := TAtlasColor(ColorToRGB(ASwatch.Brush.Color));
  Result := '';
  if mColor <> ADefault then
  begin
    Result := TAtlasColorMath.ToHex(mColor);
  end;
end;

procedure TAtlasSettingsColorsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
  FNestedLight[0].Brush.Color := TColor(TAtlasColors.Light.WithNestedRoutine(ASettings.NestedRoutineColorLight)
    .NestedRoutine);
  FNestedDark[0].Brush.Color := TColor(TAtlasColors.Dark.WithNestedRoutine(ASettings.NestedRoutineColorDark)
    .NestedRoutine);
end;

procedure TAtlasSettingsColorsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TAtlasColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TAtlasColors.Dark.Pairs);
  ASettings.NestedRoutineColorLight := ColorSetting(FNestedLight[0], TAtlasColors.Light.NestedRoutine);
  ASettings.NestedRoutineColorDark := ColorSetting(FNestedDark[0], TAtlasColors.Dark.NestedRoutine);
end;

end.
