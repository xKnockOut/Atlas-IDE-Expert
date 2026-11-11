unit Atlas.UI.Designer.BindingBar;

// Brotkrumenleiste der Datenbindung (#610), Darstellung: eine Zeile am
// unteren Rand des Designers mit den Gliedern von TAtlasDataBindings.Trail.
// - Glied: Symbol der Palette (OnImage, Bildliste Images), Name, bei
//   Steuerelementen klein das Feld. Die Auswahl ist hervorgehoben, ein Glied
//   mit Befund rot. Sammelglied „10 Verbraucher“ bzw. „4 TDBEdit“.
// - Hat eine Stufe mehrere Glieder, trägt das Glied den Schalter „n ▾“; er
//   (und ein Klick auf ein Sammelglied) klappt die Liste der Stufe nach oben
//   auf. Klick auf ein Glied oder einen Eintrag meldet OnSelect mit der
//   Kennung „Modul.Name“.
// - Rechts: Hinweis zum Befund der Auswahl (rot) und die Zahl der Glieder.
//   Passt der Weg nicht in die Zeile, fallen vorne Glieder weg („…“).
// Höhe, Farben, Hervorhebung und Klick beim Loslassen kommen vom Vorfahr
// TAtlasEditorBar. Reine VCL; was ein Klick tut, entscheidet
// Atlas.IDE.Designer.DataBindings.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Menus,
  Vcl.ImgList,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.DataBindings,
  Atlas.UI.Editor.Bar;

type
  TAtlasBindingBar = class(TAtlasEditorBar)
  private
    FTrail: TAtlasBindingTrail;
    FHasSelection: Boolean;
    FSegs: TArray<TRect>;
    FDrops: TArray<TRect>;
    /// <summary>Erstes gezeigtes Glied; davor „…“.</summary>
    FFirst: Integer;
    FImages: TCustomImageList;
    FOnImage: TFunc<string, Integer>;
    FOnSelect: TProc<string>;
    FMenu: TPopupMenu;
    FMenuIds: TArray<string>;
    procedure SetImages(AValue: TCustomImageList);
    procedure Layout;
    function DropWidth(const ACrumb: TAtlasBindingCrumb): Integer;
    function CrumbWidth(const ACrumb: TAtlasBindingCrumb): Integer;
    function FreeWidth: Integer;
    function DrawBack(AIndex: Integer): TColor;
    function CrumbText(const ACrumb: TAtlasBindingCrumb): string;
    function RightText(out AHint: string): string;
    function ImageOf(const AClassName: string): Integer;
    procedure DrawCrumb(AIndex: Integer);
    procedure OpenList(AIndex: Integer);
    procedure MenuClick(Sender: TObject);
  protected
    class function BaseHeight: Integer; override;
    function PartAt(AX, AY: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; AX, AY: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Glieder zeigen; AHasSelection False = keine Komponente gewählt.</summary>
    procedure ShowTrail(const ATrail: TAtlasBindingTrail; AHasSelection: Boolean);
    /// <summary>Text des Befunds eines Glieds; leer ohne.</summary>
    class function FindingText(const ANode: TAtlasBindingNode): string; static;
    property Images: TCustomImageList read FImages write SetImages;
    /// <summary>Index des Symbols zur Klasse in Images; -1 = keins.</summary>
    property OnImage: TFunc<string, Integer> read FOnImage write FOnImage;
    /// <summary>Klick auf ein Glied oder einen Eintrag der Liste: Kennung „Modul.Name“.</summary>
    property OnSelect: TProc<string> read FOnSelect write FOnSelect;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Designer.ViewStrings;

const
  cBaseHeight = 24;
  cIcon = 16;
  cInset = 3;
  cRadius = 4;
  /// <summary>Abstand rechts vom Hinweis und von der Zahl der Glieder.</summary>
  cRightGap = 18;
  cPad = 6;
  cSep = 14;
  cDropFormat = '%d ▾';
  cHintFormat = '%s: %s';
  cMenuFormat = '%s'#9'%s';
  cSeparator = '›';
  cEllipsis = '…';

{ TAtlasBindingBar }

constructor TAtlasBindingBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenu := TPopupMenu.Create(Self);
  FFirst := 0;
end;

class function TAtlasBindingBar.BaseHeight: Integer;
begin
  Result := cBaseHeight;
end;

procedure TAtlasBindingBar.ApplyColors(const AColors: TAtlasColors);
begin
  SetColors(AColors);
end;

procedure TAtlasBindingBar.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then
  begin
    Exit;
  end;
  if FImages <> nil then
  begin
    FImages.RemoveFreeNotification(Self);
  end;
  FImages := AValue;
  FMenu.Images := AValue;
  if FImages <> nil then
  begin
    FImages.FreeNotification(Self);
  end;
  Invalidate;
end;

procedure TAtlasBindingBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
  begin
    FImages := nil;
    FMenu.Images := nil;
  end;
end;

procedure TAtlasBindingBar.ShowTrail(const ATrail: TAtlasBindingTrail; AHasSelection: Boolean);
begin
  FTrail := ATrail;
  FHasSelection := AHasSelection;
  SetHot(cPartNone);
  Layout;
  Invalidate;
end;

class function TAtlasBindingBar.FindingText(const ANode: TAtlasBindingNode): string;
begin
  case ANode.Finding of
    TAtlasBindingFinding.FieldMissing:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DbFieldMissing,
        [ANode.MissingField, ANode.DataSet]);
    TAtlasBindingFinding.NoDataSource:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DbNoDataSource, [ANode.MissingField]);
  else
    Result := '';
  end;
end;

function TAtlasBindingBar.CrumbText(const ACrumb: TAtlasBindingCrumb): string;
begin
  if not ACrumb.Many then
  begin
    Exit(ACrumb.Head.Caption);
  end;
  if ACrumb.CommonClass <> '' then
  begin
    Exit(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DbManyOf, [ACrumb.OnPath, ACrumb.CommonClass]));
  end;
  Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DbConsumers, [ACrumb.OnPath]);
end;

function TAtlasBindingBar.RightText(out AHint: string): string;
begin
  AHint := FindingText(FTrail.Selected);
  if not FHasSelection then
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.DbNoSelection);
  end
  else if FTrail.Size <= 1 then
  begin
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.DbNone);
  end
  else
  begin
    Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.DbSize, [FTrail.Size]);
  end;
end;

function TAtlasBindingBar.ImageOf(const AClassName: string): Integer;
begin
  Result := -1;
  if (FImages <> nil) and Assigned(FOnImage) then
  begin
    Result := FOnImage(AClassName);
  end;
end;

function TAtlasBindingBar.DropWidth(const ACrumb: TAtlasBindingCrumb): Integer;
begin
  Result := 0;
  if Length(ACrumb.Members) > 1 then
  begin
    Result := Canvas.TextWidth(Format(cDropFormat, [Length(ACrumb.Members)])) + Scale(2 * cPad);
  end;
end;

function TAtlasBindingBar.CrumbWidth(const ACrumb: TAtlasBindingCrumb): Integer;
begin
  Result := Scale(cIcon + cPad + cPad + cPad) + Canvas.TextWidth(CrumbText(ACrumb)) + DropWidth(ACrumb);
  if (ACrumb.Head.Field <> '') and not ACrumb.Many then
  begin
    Inc(Result, Canvas.TextWidth(ACrumb.Head.Field) + Scale(cPad));
  end;
end;

function TAtlasBindingBar.FreeWidth: Integer;
var
  mHint: string;
begin
  Result := ClientWidth - Canvas.TextWidth(RightText(mHint)) - Scale(cRightGap);
  if mHint <> '' then
  begin
    Dec(Result, Canvas.TextWidth(mHint) + Scale(cRightGap));
  end;
end;

procedure TAtlasBindingBar.Layout;
var
  mIndex, mX, mWidth: Integer;
  mWidths: TArray<Integer>;
begin
  SetLength(FSegs, Length(FTrail.Crumbs));
  SetLength(FDrops, Length(FTrail.Crumbs));
  SetLength(mWidths, Length(FTrail.Crumbs));
  for mIndex := 0 to High(FSegs) do
  begin
    FSegs[mIndex] := TRect.Empty;
    FDrops[mIndex] := TRect.Empty;
  end;
  if not HandleAllocated then
  begin
    // Ohne Fenster misst kein Canvas; Paint legt nach dem Einhängen neu an.
    Exit;
  end;
  Canvas.Font := Font;
  mWidth := 0;
  for mIndex := 0 to High(FTrail.Crumbs) do
  begin
    mWidths[mIndex] := CrumbWidth(FTrail.Crumbs[mIndex]);
    Inc(mWidth, mWidths[mIndex] + Scale(cSep));
  end;
  // Vorne weglassen, bis der Rest passt; die Auswahl steht meist hinten.
  FFirst := 0;
  while (FFirst < High(FTrail.Crumbs)) and (mWidth > FreeWidth) do
  begin
    Dec(mWidth, mWidths[FFirst] + Scale(cSep));
    Inc(FFirst);
  end;
  mX := Scale(cPad);
  if FFirst > 0 then
  begin
    Inc(mX, Canvas.TextWidth(cEllipsis) + Scale(cSep));
  end;
  for mIndex := FFirst to High(FTrail.Crumbs) do
  begin
    FSegs[mIndex] := Rect(mX, Scale(cInset), mX + mWidths[mIndex], ClientHeight - Scale(cInset));
    if Length(FTrail.Crumbs[mIndex].Members) > 1 then
    begin
      FSegs[mIndex].Right := FSegs[mIndex].Right - DropWidth(FTrail.Crumbs[mIndex]);
      FDrops[mIndex] := Rect(FSegs[mIndex].Right, FSegs[mIndex].Top, mX + mWidths[mIndex], FSegs[mIndex].Bottom);
    end;
    mX := mX + mWidths[mIndex] + Scale(cSep);
  end;
end;

function TAtlasBindingBar.PartAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := FFirst to High(FSegs) do
  begin
    if FSegs[mIndex].Contains(Point(AX, AY)) then
    begin
      Exit(2 * mIndex);
    end;
    if FDrops[mIndex].Contains(Point(AX, AY)) then
    begin
      Exit(2 * mIndex + 1);
    end;
  end;
  Result := cPartNone;
end;

function TAtlasBindingBar.PartHint(APart: Integer): string;
var
  mNode: TAtlasBindingNode;
begin
  Result := '';
  if (APart < 0) or (APart div 2 > High(FTrail.Crumbs)) or Odd(APart) then
  begin
    Exit;
  end;
  mNode := FTrail.Crumbs[APart div 2].Head;
  Result := Format(cHintFormat, [mNode.Caption, mNode.ClassName]);
  if FindingText(mNode) <> '' then
  begin
    Result := Result + sLineBreak + FindingText(mNode);
  end;
end;

procedure TAtlasBindingBar.PartClicked(APart: Integer; AShift: TShiftState; AX, AY: Integer);
var
  mIndex: Integer;
begin
  mIndex := APart div 2;
  if (APart < 0) or (mIndex > High(FTrail.Crumbs)) then
  begin
    Exit;
  end;
  if Odd(APart) or FTrail.Crumbs[mIndex].Many then
  begin
    OpenList(mIndex);
  end
  else if Assigned(FOnSelect) then
  begin
    FOnSelect(FTrail.Crumbs[mIndex].Head.Id);
  end;
end;

procedure TAtlasBindingBar.OpenList(AIndex: Integer);
var
  mNode: TAtlasBindingNode;
  mItem: TMenuItem;
  mPoint: TPoint;
begin
  FMenu.Items.Clear;
  FMenuIds := nil;
  for mNode in FTrail.Crumbs[AIndex].Members do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mNode.Caption;
    if mNode.Field <> '' then
    begin
      mItem.Caption := Format(cMenuFormat, [mNode.Caption, mNode.Field]);
    end;
    mItem.ImageIndex := ImageOf(mNode.ClassName);
    mItem.Checked := SameText(mNode.Id, FTrail.Selected.Id);
    mItem.Tag := Length(FMenuIds);
    mItem.OnClick := MenuClick;
    FMenuIds := FMenuIds + [mNode.Id];
    FMenu.Items.Add(mItem);
  end;
  // Nach oben aufklappen: Die Leiste steht am unteren Rand des Designers.
  mPoint := ClientToScreen(Point(FSegs[AIndex].Left, 0));
  TrackPopupMenu(FMenu.Handle, TPM_LEFTALIGN or TPM_BOTTOMALIGN or TPM_LEFTBUTTON, mPoint.X, mPoint.Y, 0,
    PopupList.Window, nil);
end;

procedure TAtlasBindingBar.MenuClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FMenuIds)) and Assigned(FOnSelect) then
  begin
    FOnSelect(FMenuIds[mIndex]);
  end;
end;

function TAtlasBindingBar.DrawBack(AIndex: Integer): TColor;
var
  mCrumb: TAtlasBindingCrumb;
  mArea: TRect;
  mError: Boolean;
begin
  mCrumb := FTrail.Crumbs[AIndex];
  mArea := FSegs[AIndex];
  if not FDrops[AIndex].IsEmpty then
  begin
    mArea.Right := FDrops[AIndex].Right;
  end;
  mError := not mCrumb.Many and (mCrumb.Head.Finding <> TAtlasBindingFinding.None);
  Result := TColor(Colors.Text);
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Color := TColor(Colors.Gutter);
  Canvas.Brush.Color := TColor(Colors.Gutter);
  if mError then
  begin
    Result := TColor(Colors.Error);
    Canvas.Brush.Color := TColor(Colors.ErrorSoft);
    Canvas.Pen.Color := Canvas.Brush.Color;
  end
  else if mCrumb.Selected then
  begin
    Canvas.Brush.Color := TColor(Colors.AccentSoft);
    Canvas.Pen.Color := TColor(Colors.Accent);
  end
  else if (Hot = 2 * AIndex) or (Hot = 2 * AIndex + 1) then
  begin
    Canvas.Brush.Color := TColor(Colors.Selection);
    Canvas.Pen.Color := TColor(Colors.Line);
  end;
  if mCrumb.Selected and mError then
  begin
    Canvas.Pen.Color := TColor(Colors.Error);
  end;
  Canvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, Scale(cRadius), Scale(cRadius));
end;

procedure TAtlasBindingBar.DrawCrumb(AIndex: Integer);
var
  mCrumb: TAtlasBindingCrumb;
  mX, mY, mImage: Integer;
  mFore: TColor;
begin
  mCrumb := FTrail.Crumbs[AIndex];
  mFore := DrawBack(AIndex);
  mX := FSegs[AIndex].Left + Scale(cPad);
  mImage := ImageOf(mCrumb.Head.ClassName);
  if mImage >= 0 then
  begin
    FImages.Draw(Canvas, mX, (ClientHeight - FImages.Height) div 2, mImage);
  end;
  Inc(mX, Scale(cIcon + cPad));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := mFore;
  Canvas.Font.Style := [];
  if mCrumb.Selected then
  begin
    Canvas.Font.Style := [fsBold];
  end;
  mY := (ClientHeight - Canvas.TextHeight(cEllipsis)) div 2;
  Canvas.TextOut(mX, mY, CrumbText(mCrumb));
  Inc(mX, Canvas.TextWidth(CrumbText(mCrumb)) + Scale(cPad));
  Canvas.Font.Style := [];
  if (mCrumb.Head.Field <> '') and not mCrumb.Many then
  begin
    if mFore = TColor(Colors.Text) then
    begin
      Canvas.Font.Color := TColor(Colors.Muted);
    end;
    Canvas.TextOut(mX, mY, mCrumb.Head.Field);
  end;
  if not FDrops[AIndex].IsEmpty then
  begin
    Canvas.Pen.Color := TColor(Colors.Line);
    Canvas.MoveTo(FDrops[AIndex].Left, FDrops[AIndex].Top + Scale(cInset));
    Canvas.LineTo(FDrops[AIndex].Left, FDrops[AIndex].Bottom - Scale(cInset));
    Canvas.Font.Color := TColor(Colors.Text);
    Canvas.TextOut(FDrops[AIndex].Left + Scale(cPad), mY, Format(cDropFormat, [Length(mCrumb.Members)]));
  end;
end;

procedure TAtlasBindingBar.Paint;
var
  mIndex, mY, mRight: Integer;
  mHint, mText: string;
begin
  Layout;
  PaintChrome(True);
  Canvas.Font := Font;
  mY := (ClientHeight - Canvas.TextHeight(cEllipsis)) div 2;
  Canvas.Brush.Style := bsClear;
  if FFirst > 0 then
  begin
    Canvas.Font.Color := TColor(Colors.Muted);
    Canvas.TextOut(Scale(cPad), mY, cEllipsis);
  end;
  for mIndex := FFirst to High(FTrail.Crumbs) do
  begin
    if mIndex > FFirst then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := TColor(Colors.Muted);
      Canvas.TextOut(FSegs[mIndex].Left - Scale(cSep) + (Scale(cSep) - Canvas.TextWidth(cSeparator)) div 2, mY,
        cSeparator);
    end;
    DrawCrumb(mIndex);
  end;
  // Rechts: Zahl der Glieder, davor der Hinweis zum Befund.
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [];
  mText := RightText(mHint);
  mRight := ClientWidth - Scale(cPad) - Canvas.TextWidth(mText);
  Canvas.Font.Color := TColor(Colors.Muted);
  Canvas.TextOut(mRight, mY, mText);
  if mHint <> '' then
  begin
    mRight := mRight - Scale(2 * cPad) - Canvas.TextWidth(mHint);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor(Colors.ErrorSoft);
    Canvas.Pen.Color := TColor(Colors.Error);
    Canvas.RoundRect(mRight - Scale(cPad), Scale(cInset), mRight + Canvas.TextWidth(mHint) + Scale(cPad),
      ClientHeight - Scale(cInset), Scale(cRadius), Scale(cRadius));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(Colors.Error);
    Canvas.TextOut(mRight, mY, mHint);
  end;
end;

procedure TAtlasBindingBar.Resize;
begin
  inherited Resize;
  Layout;
end;

end.
