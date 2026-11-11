unit Atlas.IDE.Designer.ScalePreview;

// Knopf „Skalierung und Texte“ der Designer-Leiste (#607) in der IDE: zeigt
// das Formular des aktiven Designers im Fenster TAtlasScalePreviewWindow in
// einer anderen Skalierung, auf einem kleineren Bildschirm und mit langen
// Texten (Grundlage TAtlasIdePreviewTool). Ein Klick in der Liste der Befunde
// wählt die Komponente im Designer.
// - Texte: Caption von Labels, Knöpfen, Checkboxen und RadioButtons, Items von
//   ComboBoxen und ListBoxen; Schrift der Komponente (ParentFont schon
//   aufgelöst), Höhe in Pixeln der DFM.
// - Anteil neben dem Text wie bei „Breite nach Text“ (Kästchen, Pfeil, Glyph),
//   dazu der Innenabstand eines Knopfs bzw. einer Liste.
// - Scaled des Formulars, PixelsPerInch, Rahmen und Titel; Skalierungen,
//   Bildschirme und Verlängerung aus den Einstellungen designer.*.
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.FormPreview,
  Atlas.IDE.Designer.Preview;

type
  TAtlasIdeScalePreview = class(TAtlasIdePreviewTool)
  public const
    cId = 'scalePreview';
  private
    FFormName: string;
    procedure SelectComponent(const AName: string);
  protected
    function Id: string; override;
    function Icon: TAtlasToolbarIcon; override;
    function HintText: string; override;
    function Enabled(const ASettings: TAtlasPluginSettings): Boolean; override;
    function CreateWindow(ARoot: TWinControl): TAtlasFormPreviewWindow; override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Buttons,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.Layout,
  Atlas.Core.Designer.Scale,
  Atlas.UI.Designer.ScalePreview,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cBasePpi = 96;
  /// <summary>Innenabstand eines Knopfs links und rechts zusammen bei 96 dpi.</summary>
  cButtonPadding = 12;
  /// <summary>Rand einer ComboBox oder ListBox links und rechts zusammen bei 96 dpi.</summary>
  cListPadding = 4;
  cLineBreak = #10;

function Flag(AControl: TControl; const AName: string): Boolean;
begin
  Result := IsPublishedProp(AControl, AName) and (PropType(AControl, AName) = tkEnumeration) and
    (GetOrdProp(AControl, AName) <> 0);
end;

function ItemsText(AControl: TControl): string;
var
  mItems: TObject;
  mIndex: Integer;
begin
  Result := '';
  if not IsPublishedProp(AControl, 'Items') or (PropType(AControl, 'Items') <> tkClass) then
  begin
    Exit;
  end;
  mItems := GetObjectProp(AControl, 'Items');
  if mItems is TStrings then
  begin
    for mIndex := 0 to TStrings(mItems).Count - 1 do
    begin
      if Result <> '' then
      begin
        Result := Result + cLineBreak;
      end;
      Result := Result + TStrings(mItems)[mIndex];
    end;
  end;
end;

/// <summary>Text, Schrift und Anteil neben dem Text; Text leer bei Steuerelementen ohne Prüfung.</summary>
function TextOf(AControl: TControl; const AScale: TAtlasDesignScale): TAtlasScaleText;
var
  mPadding: Integer;
  mText: string;
  mFont: TFont;
begin
  Result := Default(TAtlasScaleText);
  mText := '';
  if (AControl is TCustomLabel) or (AControl is TCustomStaticText) then
  begin
    mPadding := 0;
    Result.AutoSize := Flag(AControl, 'AutoSize');
  end
  else if (AControl is TCustomButton) or (AControl is TSpeedButton) then
  begin
    mPadding := cButtonPadding;
  end
  else if (AControl is TCustomCheckBox) or (AControl is TRadioButton) then
  begin
    mPadding := 0;
  end
  else if (AControl is TCustomComboBox) or (AControl is TCustomListBox) then
  begin
    mPadding := cListPadding;
    mText := ItemsText(AControl);
  end
  else
  begin
    Exit;
  end;
  if (mText = '') and not TAtlasDesignerAccess.PropText(AControl, 'Caption', mText) then
  begin
    Exit;
  end;
  mFont := TAtlasIdeFitText.FontOfControl(AControl);
  if mFont = nil then
  begin
    Exit;
  end;
  Result.Text := mText;
  Result.FontName := mFont.Name;
  Result.FontHeight := AScale.ToDesign(mFont.Height);
  Result.Bold := fsBold in mFont.Style;
  Result.Italic := fsItalic in mFont.Style;
  Result.WordWrap := Flag(AControl, 'WordWrap');
  Result.Extra := MulDiv(TAtlasIdeFitText.ExtraWidth(AControl) + mPadding, AScale.Design, cBasePpi);
end;

function ScaledOf(ARoot: TWinControl): Boolean;
begin
  Result := True;
  if IsPublishedProp(ARoot, 'Scaled') and (PropType(ARoot, 'Scaled') = tkEnumeration) then
  begin
    Result := GetOrdProp(ARoot, 'Scaled') <> 0;
  end;
end;

function ScaleData(ARoot: TWinControl): TAtlasScalePreviewData;
var
  mControls: TArray<TControl>;
  mControl: TControl;
  mScale: TAtlasDesignScale;
begin
  Result := Default(TAtlasScalePreviewData);
  Result.Form := TAtlasIdePreviewTool.FormData(ARoot);
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  // Gleiche Reihenfolge wie die Knoten in FormData.
  TAtlasDesignerModel.LayoutNodes(ARoot, mControls);
  for mControl in mControls do
  begin
    Result.Texts := Result.Texts + [TextOf(mControl, mScale)];
  end;
  Result.DesignPpi := mScale.Design;
  Result.Scaled := ScaledOf(ARoot);
  Result.Frame := TAtlasIdePreviewTool.FrameOf(ARoot);
  Result.Levels := TAtlasFormScale.ParseLevels(TAtlasIdeSettings.Current.DesignerScalePreviewLevels);
  Result.Screens := TAtlasFormLayout.ParseSizes(TAtlasIdeSettings.Current.DesignerScalePreviewScreens);
  Result.LongFactor := TAtlasIdeSettings.Current.DesignerLongTextFactor;
end;

{ TAtlasIdeScalePreview }

function TAtlasIdeScalePreview.Id: string;
begin
  Result := cId;
end;

function TAtlasIdeScalePreview.Icon: TAtlasToolbarIcon;
begin
  Result := TAtlasToolbarIcon.ScalePreview;
end;

function TAtlasIdeScalePreview.HintText: string;
begin
  Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleHint);
end;

function TAtlasIdeScalePreview.Enabled(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerScalePreview;
end;

function TAtlasIdeScalePreview.CreateWindow(ARoot: TWinControl): TAtlasFormPreviewWindow;
var
  mWindow: TAtlasScalePreviewWindow;
begin
  FFormName := ARoot.Name;
  mWindow := TAtlasScalePreviewWindow.CreateScale(nil, ScaleData(ARoot), TAtlasIdeStyle.Colors);
  mWindow.OnSelect :=
    procedure(AName: string)
    begin
      SelectComponent(AName);
    end;
  Result := mWindow;
end;

procedure TAtlasIdeScalePreview.SelectComponent(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  // Nur im selben Formular; ein anderer Designer kann inzwischen vorn sein.
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SameText(mRoot.Name, FFormName) then
  begin
    Exit;
  end;
  if SameText(AName, mRoot.Name) then
  begin
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, nil);
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  if mComponent <> nil then
  begin
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
  end;
end;

end.
