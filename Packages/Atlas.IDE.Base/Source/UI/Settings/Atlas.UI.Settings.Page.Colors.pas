unit Atlas.UI.Settings.Page.Colors;

// Reiter „Farben“: eigene Paarfarben je Thema und ihre Reihenfolge.

interface

uses
  System.Classes,
  System.UITypes,
  Vcl.ExtCtrls,
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
    /// <summary>Zeile mit Beschriftung und fünf Farbflächen.</summary>
    procedure AddSwatches(const ACaption: string; var ASwatches: array of TShape);
    procedure SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ResetColorsClick(Sender: TObject);
    class procedure ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors); static;
    /// <summary>Farben der Flächen als Einstellung; gleich der Palette = leer.</summary>
    class function PairsSetting(const ASwatches: array of TShape; const ADefault: TAtlasPairColors): string; static;
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
  Atlas.Core.Style.Color,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings;

{ TAtlasSettingsColorsPart }

procedure TAtlasSettingsColorsPart.Build;
var
  Panel: TWinControl;
  Title: TLabel;
  Button: TButton;
begin
  // Eigene Paarfarben und deren Reihenfolge je Thema.
  AddSheet(TAtlasTextId.SettingsTabColors);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsLight), FLightSwatches);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsDark), FDarkSwatches);
  Panel := AddPanel(22);
  Title := TLabel.Create(FPage);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsHint);
  Title.Left := 0;
  Title.Top := 3;
  Title.Font.Color := clGrayText;
  Panel := AddPanel(32);
  Button := TButton.Create(FPage);
  Button.Parent := Panel;
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsReset);
  Button.Left := 0;
  Button.Top := 3;
  Button.Width := 150;
  Button.OnClick := ResetColorsClick;
  Attach(Panel, FLightSwatches[0]);
end;

procedure TAtlasSettingsColorsPart.BindMarks;
begin
  FPage.Marks.Bind(FLightSwatches[0], ['PairColorsLight']);
  FPage.Marks.Bind(FDarkSwatches[0], ['PairColorsDark']);
end;

procedure TAtlasSettingsColorsPart.AddSwatches(const ACaption: string; var ASwatches: array of TShape);
var
  Panel: TWinControl;
  mCaption: TLabel;
  Index: Integer;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := Panel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  for Index := 0 to High(ASwatches) do
  begin
    ASwatches[Index] := TShape.Create(FPage);
    ASwatches[Index].Parent := Panel;
    ASwatches[Index].SetBounds(FieldLeft + Index * 34, 1, 28, 22);
    ASwatches[Index].Pen.Color := clGray;
    ASwatches[Index].Cursor := crHandPoint;
    ASwatches[Index].Hint := IntToStr(Index + 1);
    ASwatches[Index].ShowHint := True;
    ASwatches[Index].OnMouseDown := SwatchMouseDown;
  end;
end;

procedure TAtlasSettingsColorsPart.SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Dialog: TColorDialog;
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  Dialog := TColorDialog.Create(nil);
  try
    Dialog.Color := TShape(Sender).Brush.Color;
    Dialog.Options := Dialog.Options + [cdFullOpen];
    if Dialog.Execute then
    begin
      TShape(Sender).Brush.Color := Dialog.Color;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsColorsPart.ResetColorsClick(Sender: TObject);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.Pairs);
end;

class procedure TAtlasSettingsColorsPart.ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors);
var
  Index: Integer;
begin
  for Index := 0 to High(ASwatches) do
  begin
    ASwatches[Index].Brush.Color := TColor(APairs[Index]);
  end;
end;

class function TAtlasSettingsColorsPart.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TAtlasPairColors): string;
var
  Pairs: TAtlasPairColors;
  Index: Integer;
begin
  for Index := 0 to High(Pairs) do
  begin
    Pairs[Index] := TAtlasColor(ColorToRGB(ASwatches[Index].Brush.Color));
  end;
  Result := TAtlasColors.PairsText(Pairs);
  if Result = TAtlasColors.PairsText(ADefault) then
  begin
    Result := '';
  end;
end;

procedure TAtlasSettingsColorsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
end;

procedure TAtlasSettingsColorsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TAtlasColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TAtlasColors.Dark.Pairs);
end;

end.
