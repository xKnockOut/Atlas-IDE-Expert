unit Atlas.UI.Designer.ScalePreview;

// Fenster „Skalierung und Texte“ (#607), reine VCL. Zeigt das Formular als
// Abbild in einer anderen Skalierung, auf einem kleineren Bildschirm und mit
// längeren Texten; die DFM bleibt unverändert.
//   Skalierung: [150 % ▾]  Bildschirm: [1366 × 768 ▾]  Texte: [Lange Texte ▾]
//   ┌──────────── Abbild 1:1 in Bildschirmpixeln ────────────┐
//   │ Texte der Komponenten, rot = Befund                    │
//   ┆ gestrichelt: nutzbare Fläche des Bildschirms           ┆
//   └────────────────────────────────────────────────────────┘
//   btnSave: Text 13 px breiter als die Komponente            ← Klick wählt
//   Formular: 119 px höher als der Bildschirm                 ← im Designer
// - Rechnung in TAtlasFormScale; Textbreiten misst das Fenster über GDI in
//   der Schrift der Komponente bei der gewählten Skalierung.
// - Grundlage ist TAtlasFormPreviewWindow (Abbild, Tooltip, Esc).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.Scale,
  Atlas.UI.Designer.FormPreview;

type
  TAtlasScalePreviewData = record
    Form: TAtlasFormPreviewData;
    /// <summary>Text je Knoten (gleiche Reihenfolge wie Form.Nodes).</summary>
    Texts: TArray<TAtlasScaleText>;
    DesignPpi: Integer;
    Scaled: Boolean;
    /// <summary>Rahmen und Titel in Pixeln der DFM.</summary>
    Frame: TSize;
    /// <summary>Angebotene Skalierungen in Prozent.</summary>
    Levels: TArray<Integer>;
    /// <summary>Angebotene Bildschirme in physischen Pixeln.</summary>
    Screens: TArray<TSize>;
    /// <summary>Verlängerung bei „Lange Texte“ in Prozent.</summary>
    LongFactor: Integer;
  end;

  TAtlasScalePreviewWindow = class(TAtlasFormPreviewWindow)
  private
    FScale: TAtlasScalePreviewData;
    FView: TAtlasScaleView;
    FMeasure: TBitmap;
    FLevelBox: TComboBox;
    FScreenBox: TComboBox;
    FTextBox: TComboBox;
    FList: TListBox;
    FListNodes: TArray<Integer>;
    FOnSelect: TProc<string>;
    function AddChoice(const ACaption: string; const AItems: TArray<string>; AIndex: Integer): TComboBox;
    function Setup: TAtlasScaleSetup;
    function TextWidth: TAtlasTextWidth;
    function NameOf(ANode: Integer): string;
    procedure ChoiceChanged(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure FillList;
  protected
    function Px(AValue: Integer): Integer; override;
    function NodeText(AIndex: Integer): string; override;
    function GripResizes: Boolean; override;
    procedure BuildBar; override;
    procedure Recalculate; override;
    procedure PaintOver; override;
  public
    constructor CreateScale(AOwner: TComponent; const AData: TAtlasScalePreviewData; const AColors: TAtlasColors);
    destructor Destroy; override;
    /// <summary>Skalierung in Prozent (100 = Designgröße).</summary>
    function Percent: Integer;
    property View: TAtlasScaleView read FView;
    /// <summary>Klick in der Liste der Befunde: Name der Komponente (Formular: sein Name).</summary>
    property OnSelect: TProc<string> read FOnSelect write FOnSelect;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Controls,
  Atlas.Core.Designer.Layout,
  Atlas.UI.Designer.ViewStrings;

const
  cPercent = 100;
  cListHeight = 96;
  cDashGap = 6;

{ TAtlasScalePreviewWindow }

constructor TAtlasScalePreviewWindow.CreateScale(AOwner: TComponent; const AData: TAtlasScalePreviewData;
  const AColors: TAtlasColors);
begin
  FScale := AData;
  if Length(FScale.Levels) = 0 then
  begin
    FScale.Levels := [cPercent];
  end;
  FMeasure := Vcl.Graphics.TBitmap.Create; // Winapi.Windows verdeckt TBitmap
  inherited CreatePreview(AOwner, AData.Form, AColors);
  Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleTitle, [AData.Form.FormName]);
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alBottom;
  FList.Height := S(cListHeight);
  FList.Top := FStatus.Top - 1;
  FList.AlignWithMargins := True;
  FList.OnClick := ListClick;
  Recalculate;
end;

destructor TAtlasScalePreviewWindow.Destroy;
begin
  FreeAndNil(FMeasure);
  inherited Destroy;
end;

function TAtlasScalePreviewWindow.AddChoice(const ACaption: string; const AItems: TArray<string>;
  AIndex: Integer): TComboBox;
var
  mLabel: TLabel;
  mItem: string;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := FBar;
  mLabel.Caption := ACaption;
  mLabel.AlignWithMargins := True;
  Result := TComboBox.Create(Self);
  Result.Parent := FBar;
  Result.Style := csDropDownList;
  Result.AlignWithMargins := True;
  for mItem in AItems do
  begin
    Result.Items.Add(mItem);
  end;
  Result.ItemIndex := AIndex;
  Result.OnChange := ChoiceChanged;
end;

procedure TAtlasScalePreviewWindow.BuildBar;
var
  mItems: TArray<string>;
  mIndex, mStart: Integer;
begin
  // Vorgabe: die erste Skalierung über 100 %, sonst die erste.
  mItems := nil;
  mStart := -1;
  for mIndex := 0 to High(FScale.Levels) do
  begin
    mItems := mItems + [Format('%d %%', [FScale.Levels[mIndex]])];
    if (mStart < 0) and (FScale.Levels[mIndex] > cPercent) then
    begin
      mStart := mIndex;
    end;
  end;
  FLevelBox := AddChoice(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleLevel), mItems,
    Max(mStart, 0));
  mItems := [TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleNoLimit)];
  for mIndex := 0 to High(FScale.Screens) do
  begin
    mItems := mItems + [Format('%d × %d', [FScale.Screens[mIndex].cx, FScale.Screens[mIndex].cy])];
  end;
  FScreenBox := AddChoice(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleScreen), mItems, 0);
  FTextBox := AddChoice(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleTexts),
    [TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleOriginal),
    TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleLong, [FScale.LongFactor])], 0);
end;

function TAtlasScalePreviewWindow.Percent: Integer;
begin
  Result := cPercent;
  if (FLevelBox <> nil) and (FLevelBox.ItemIndex >= 0) and (FLevelBox.ItemIndex <= High(FScale.Levels)) then
  begin
    Result := FScale.Levels[FLevelBox.ItemIndex];
  end;
end;

function TAtlasScalePreviewWindow.Setup: TAtlasScaleSetup;
begin
  Result := Default(TAtlasScaleSetup);
  Result.DesignPpi := FScale.DesignPpi;
  Result.Ppi := MulDiv(TAtlasFormScale.cBasePpi, Percent, cPercent);
  Result.Scaled := FScale.Scaled;
  Result.Client := FScale.Form.Design;
  Result.Frame := FScale.Frame;
  if (FScreenBox <> nil) and (FScreenBox.ItemIndex > 0) and (FScreenBox.ItemIndex <= Length(FScale.Screens)) then
  begin
    Result.Screen := FScale.Screens[FScreenBox.ItemIndex - 1];
  end;
  if (FTextBox <> nil) and (FTextBox.ItemIndex > 0) then
  begin
    Result.LongFactor := FScale.LongFactor;
  end;
end;

function TAtlasScalePreviewWindow.TextWidth: TAtlasTextWidth;
begin
  Result :=
    function(const AText: TAtlasScaleText; const ALine: string; APpi: Integer): Integer
    var
      mStyle: TFontStyles;
    begin
      mStyle := [];
      if AText.Bold then
      begin
        Include(mStyle, fsBold);
      end;
      if AText.Italic then
      begin
        Include(mStyle, fsItalic);
      end;
      if AText.FontName <> '' then
      begin
        FMeasure.Canvas.Font.Name := AText.FontName;
      end;
      FMeasure.Canvas.Font.Height := TAtlasFormScale.Value(AText.FontHeight, FScale.DesignPpi, APpi);
      FMeasure.Canvas.Font.Style := mStyle;
      Result := FMeasure.Canvas.TextWidth(ALine);
    end;
end;

function TAtlasScalePreviewWindow.Px(AValue: Integer): Integer;
begin
  // Das Abbild ist schon in Pixeln der gewählten Skalierung: 1:1.
  Result := AValue;
end;

function TAtlasScalePreviewWindow.NodeText(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex <= High(FView.Texts)) and (FView.Texts[AIndex] <> '') then
  begin
    Result := FView.Texts[AIndex].Split([#10])[0];
  end;
  if Result = '' then
  begin
    Result := inherited NodeText(AIndex);
  end;
end;

function TAtlasScalePreviewWindow.GripResizes: Boolean;
begin
  Result := False;
end;

function TAtlasScalePreviewWindow.NameOf(ANode: Integer): string;
begin
  Result := FScale.Form.FormName;
  if (ANode >= 0) and (ANode <= High(FData.Nodes)) then
  begin
    Result := FData.Nodes[ANode].Name;
  end;
end;

procedure TAtlasScalePreviewWindow.Recalculate;
var
  mWidth, mHeight: Integer;
begin
  if FMeasure = nil then
  begin
    Exit;
  end;
  FView := TAtlasFormScale.View(FScale.Form.Nodes, FScale.Texts, Setup, TextWidth());
  FData.Nodes := FView.Nodes;
  FBounds := FView.Bounds;
  FFindings := FView.Findings;
  FProbe := FView.Client;
  mWidth := Max(FProbe.cx, FView.Usable.cx);
  mHeight := Max(FProbe.cy, FView.Usable.cy);
  FPaint.SetBounds(0, 0, mWidth + 2 * Origin.X, mHeight + 2 * Origin.Y);
  if Length(FFindings) = 0 then
  begin
    FStatus.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleNone, [Percent]) + ' · ' +
      TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleKeys);
  end
  else
  begin
    FStatus.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleCount, [Length(FFindings),
      Percent]);
  end;
  if not FScale.Scaled then
  begin
    FStatus.Caption := FStatus.Caption + ' · ' +
      TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleNotScaled);
  end;
  FillList;
  FPaint.Invalidate;
end;

procedure TAtlasScalePreviewWindow.FillList;
var
  mFinding: TAtlasLayoutFinding;
  mNode: TAtlasLayoutNode;
begin
  if FList = nil then
  begin
    Exit;
  end;
  FListNodes := nil;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mFinding in FFindings do
    begin
      mNode := Default(TAtlasLayoutNode);
      if mFinding.Node >= 0 then
      begin
        mNode := FData.Nodes[mFinding.Node];
      end;
      FList.Items.Add(NameOf(mFinding.Node) + ': ' + FindingText(mFinding, mNode));
      FListNodes := FListNodes + [mFinding.Node];
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasScalePreviewWindow.ChoiceChanged(Sender: TObject);
begin
  Recalculate;
end;

procedure TAtlasScalePreviewWindow.ListClick(Sender: TObject);
begin
  if (FList.ItemIndex < 0) or (FList.ItemIndex > High(FListNodes)) or not Assigned(FOnSelect) then
  begin
    Exit;
  end;
  FOnSelect(NameOf(FListNodes[FList.ItemIndex]));
end;

procedure TAtlasScalePreviewWindow.PaintOver;
var
  mRect: TRect;
begin
  if (FView.Usable.cx <= 0) or (FView.Usable.cy <= 0) then
  begin
    Exit;
  end;
  // Nutzbare Fläche des Bildschirms gestrichelt (ohne Rahmen und Taskleiste).
  mRect := Bounds(Origin.X, Origin.Y, FView.Usable.cx, FView.Usable.cy);
  FPaint.Canvas.Brush.Style := bsClear;
  FPaint.Canvas.Pen.Color := TColor(FColors.Error);
  FPaint.Canvas.Pen.Style := psDash;
  FPaint.Canvas.Rectangle(mRect);
  FPaint.Canvas.Pen.Style := psSolid;
  FPaint.Canvas.Font.Color := TColor(FColors.Error);
  FPaint.Canvas.TextOut(mRect.Left + S(cDashGap), mRect.Bottom - FPaint.Canvas.TextHeight('0') - S(cDashGap),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ScaleUsable));
end;

end.
