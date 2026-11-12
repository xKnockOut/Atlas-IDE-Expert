unit Atlas.IDE.Designer.FitText;

// Befehl „Breite nach Text“ (#730) im Menü „Anordnen“ in der IDE: misst die
// Texte der markierten Steuerelemente in ihrer Schrift (TCanvas.TextWidth),
// rechnet mit TAtlasFitText die gemeinsame Breite und die neue Lage und setzt
// sie im Designer.
// - Text: Caption, je nach designer.fitToText.sources auch Text und Items.
// - Anteil des Steuerelements: Kästchen bei Checkbox und RadioButton, Pfeil
//   bei ComboBox, Glyph bei BitBtn und SpeedButton; in Pixeln der
//   Designgröße (PixelsPerInch des Formulars).
// - Nur Geschwister der ersten Auswahl; AutoSize und Align ohne freie Breite
//   bleiben und stehen in der Meldung.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows, // vor Vcl.Graphics, sonst verdeckt es TBitmap
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls;

type
  TAtlasIdeFitText = class
  public
    /// <summary>Breite des längsten Texts von AControl in seiner Schrift; -1 ohne Text.</summary>
    class function TextWidth(AControl: TControl; const ASources: string): Integer; static;
    /// <summary>Anteil des Steuerelements neben dem Text (Kästchen, Pfeil, Glyph) bei 96 dpi; auch für die
    /// Vorschau in anderen Skalierungen (#607).</summary>
    class function ExtraWidth(AControl: TControl): Integer; static;
    /// <summary>Veröffentlichte Schrift von AControl; nil ohne Font.</summary>
    class function FontOfControl(AControl: TControl): TFont; static;
    /// <summary>Steuerelemente mit Text unter ASelected (Geschwister der ersten).</summary>
    class function Candidates(const ASelected: TArray<TComponent>): TArray<TControl>; static;
    /// <summary>Gemeinsame Breite der Steuerelemente nach Text, Innenabstand und Mindestbreite (in Pixeln der
    /// Designgröße von ARoot); auch für die Knopfleiste (#732).</summary>
    class function CommonWidth(const AControls: TArray<TControl>; ARoot: TComponent): Integer; static;
    /// <summary>Befehl ausführen; Meldungen über AOnMessage.</summary>
    class procedure Execute(const AOnMessage: TProc<string>); static;
  end;

implementation

uses
  System.Types,
  System.TypInfo,
  Vcl.StdCtrls,
  Vcl.Buttons,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.FitText,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  /// <summary>Kästchen samt Abstand bei 96 dpi.</summary>
  cCheckWidth = 20;
  /// <summary>Pfeil samt Rand einer ComboBox bei 96 dpi.</summary>
  cArrowWidth = 22;
  cDefaultPpi = 96;

function HasSource(const ASources, AName: string): Boolean;
var
  mPart: string;
begin
  for mPart in ASources.Split([',']) do
  begin
    if SameText(Trim(mPart), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Texte von AControl aus den gewählten Quellen.</summary>
function TextsOf(AControl: TControl; const ASources: string): TArray<string>;
var
  mText: string;
  mItems: TObject;
  mIndex: Integer;
begin
  Result := nil;
  if HasSource(ASources, TAtlasPluginSettings.cFitSourceCaption) and
    TAtlasDesignerAccess.PropText(AControl, 'Caption', mText) then
  begin
    Result := Result + [mText];
  end;
  if HasSource(ASources, TAtlasPluginSettings.cFitSourceText) and
    TAtlasDesignerAccess.PropText(AControl, 'Text', mText) then
  begin
    Result := Result + [mText];
  end;
  if HasSource(ASources, TAtlasPluginSettings.cFitSourceItems) and IsPublishedProp(AControl, 'Items') and
    (PropType(AControl, 'Items') = tkClass) then
  begin
    mItems := GetObjectProp(AControl, 'Items');
    if mItems is TStrings then
    begin
      for mIndex := 0 to TStrings(mItems).Count - 1 do
      begin
        Result := Result + [TStrings(mItems)[mIndex]];
      end;
    end;
  end;
end;

function FontOf(AControl: TControl): TFont;
var
  mFont: TObject;
begin
  Result := nil;
  if IsPublishedProp(AControl, 'Font') and (PropType(AControl, 'Font') = tkClass) then
  begin
    mFont := GetObjectProp(AControl, 'Font');
    if mFont is TFont then
    begin
      Result := TFont(mFont);
    end;
  end;
end;

class function TAtlasIdeFitText.TextWidth(AControl: TControl; const ASources: string): Integer;
var
  mFont: TFont;
  mTexts: TArray<string>;
  mText, mLine: string;
  mBitmap: Vcl.Graphics.TBitmap;
begin
  Result := -1;
  mFont := FontOf(AControl);
  mTexts := TextsOf(AControl, ASources);
  if (mFont = nil) or (Length(mTexts) = 0) then
  begin
    Exit;
  end;
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(mFont);
    for mText in mTexts do
    begin
      for mLine in TAtlasFitText.Lines(mText) do
      begin
        if mBitmap.Canvas.TextWidth(mLine) > Result then
        begin
          Result := mBitmap.Canvas.TextWidth(mLine);
        end;
      end;
    end;
  finally
    mBitmap.Free;
  end;
end;

/// <summary>Anteil des Steuerelements neben dem Text bei 96 dpi.</summary>
function ExtraOf(AControl: TControl): Integer;
var
  mGlyph: Vcl.Graphics.TBitmap;
  mCount, mSpacing: Integer;
begin
  Result := 0;
  mGlyph := nil;
  mCount := 1;
  mSpacing := 0;
  if (AControl is TCustomCheckBox) or (AControl is TRadioButton) then
  begin
    Exit(cCheckWidth);
  end;
  if AControl is TCustomComboBox then
  begin
    Exit(cArrowWidth);
  end;
  if AControl is TBitBtn then
  begin
    mGlyph := TBitBtn(AControl).Glyph;
    mCount := TBitBtn(AControl).NumGlyphs;
    mSpacing := TBitBtn(AControl).Spacing;
  end
  else if AControl is TSpeedButton then
  begin
    mGlyph := TSpeedButton(AControl).Glyph;
    mCount := TSpeedButton(AControl).NumGlyphs;
    mSpacing := TSpeedButton(AControl).Spacing;
  end;
  if (mGlyph <> nil) and not mGlyph.Empty and (mCount > 0) then
  begin
    Result := mGlyph.Width div mCount + Abs(mSpacing);
  end;
end;

class function TAtlasIdeFitText.ExtraWidth(AControl: TControl): Integer;
begin
  Result := ExtraOf(AControl);
end;

class function TAtlasIdeFitText.FontOfControl(AControl: TControl): TFont;
begin
  Result := FontOf(AControl);
end;

/// <summary>Breite bleibt: AutoSize an oder Align, das die Breite vorgibt.</summary>
function FixedWidth(AControl: TControl): Boolean;
begin
  Result := AControl.Align in [alTop, alBottom, alClient];
  if not Result and IsPublishedProp(AControl, 'AutoSize') and (PropType(AControl, 'AutoSize') = tkEnumeration) then
  begin
    Result := GetOrdProp(AControl, 'AutoSize') <> 0;
  end;
end;

class function TAtlasIdeFitText.Candidates(const ASelected: TArray<TComponent>): TArray<TControl>;
var
  mComponent: TComponent;
  mParent: TWinControl;
  mSources: string;
begin
  Result := nil;
  mParent := nil;
  mSources := TAtlasIdeSettings.Current.DesignerFitToTextSources;
  for mComponent in ASelected do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) or
      (TextWidth(TControl(mComponent), mSources) < 0) then
    begin
      Continue;
    end;
    if mParent = nil then
    begin
      mParent := TControl(mComponent).Parent;
    end;
    if TControl(mComponent).Parent = mParent then
    begin
      Result := Result + [TControl(mComponent)];
    end;
  end;
end;

function PpiOf(ARoot: TComponent): Integer;
begin
  Result := cDefaultPpi;
  if (ARoot is TCustomForm) and (TCustomForm(ARoot).PixelsPerInch > 0) then
  begin
    Result := TCustomForm(ARoot).PixelsPerInch;
  end;
end;

/// <summary>Eingaben für TAtlasFitText; AFixed sammelt die Namen der Steuerelemente, deren Breite bleibt.</summary>
function ItemsOf(const AControls: TArray<TControl>; APpi: Integer; out AFixed: TArray<string>): TArray<TAtlasFitItem>;
var
  mControl: TControl;
  mSources: string;
begin
  Result := nil;
  AFixed := nil;
  mSources := TAtlasIdeSettings.Current.DesignerFitToTextSources;
  for mControl in AControls do
  begin
    Result := Result + [TAtlasFitItem.Create(mControl.BoundsRect, TAtlasIdeFitText.TextWidth(mControl, mSources),
      MulDiv(ExtraOf(mControl), APpi, cDefaultPpi), FixedWidth(mControl), akRight in mControl.Anchors)];
    if FixedWidth(mControl) then
    begin
      AFixed := AFixed + [mControl.Name];
    end;
  end;
end;

class function TAtlasIdeFitText.CommonWidth(const AControls: TArray<TControl>; ARoot: TComponent): Integer;
var
  mFixed: TArray<string>;
  mPpi: Integer;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  mPpi := PpiOf(ARoot);
  Result := TAtlasFitText.Width(ItemsOf(AControls, mPpi, mFixed), MulDiv(mSettings.DesignerFitToTextPadding, mPpi,
    cDefaultPpi), MulDiv(mSettings.DesignerFitToTextMinWidth, mPpi, cDefaultPpi));
end;

class procedure TAtlasIdeFitText.Execute(const AOnMessage: TProc<string>);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mControls: TArray<TControl>;
  mItems: TArray<TAtlasFitItem>;
  mNew: TArray<TRect>;
  mFixed: TArray<string>;
  mWidth, mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerFitToText or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mControls := Candidates(TAtlasDesignerAccess.Selection(mEditor, mRoot));
  if (mDesigner = nil) or (Length(mControls) = 0) then
  begin
    AOnMessage(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitNoText));
    Exit;
  end;
  mItems := ItemsOf(mControls, PpiOf(mRoot), mFixed);
  mWidth := CommonWidth(mControls, mRoot);
  mNew := TAtlasFitText.Apply(mItems, mWidth, mControls[0].Parent.ClientWidth);
  for mIndex := 0 to High(mControls) do
  begin
    if mNew[mIndex] <> mControls[mIndex].BoundsRect then
    begin
      mControls[mIndex].BoundsRect := mNew[mIndex];
    end;
  end;
  mDesigner.Modified;
  AOnMessage(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFitDone, [mWidth, Length(mControls)]));
  if Length(mFixed) > 0 then
  begin
    AOnMessage(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFitSkipped, [string.Join(', ', mFixed)]));
  end;
end;

end.
