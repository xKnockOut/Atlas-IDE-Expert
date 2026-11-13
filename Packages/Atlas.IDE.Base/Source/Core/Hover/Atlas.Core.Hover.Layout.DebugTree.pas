unit Atlas.Core.Hover.Layout.DebugTree;

// Aufgeklappter Wert im Debug-Hover (#895) ohne VCL: je sichtbarer Zeile (TAtlasDebugValueRow) eingerückt
// „▸ Name = Wert“, aufklappbare mit ▸ bzw. ▾, Getter („auswerten“) und „weitere …“ in der Akzentfarbe, geänderte
// Zeilen hinterlegt mit dem alten Wert gedimmt dahinter („← 980,00“), die gewählte Zeile in der Auswahlfarbe.
// Jede Zeile ist eine Klickfläche DebugRow mit ihrem Index. Sind es mehr als Input.DebugRows.MaxLines Zeilen,
// scrollen sie in einem eigenen Rollbereich mit Daumen (TAtlasHoverScroll wie die published-Mitglieder).

interface

uses
  System.Types,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.Layout.Members;

type
  TAtlasHoverDebugPainter = class(TAtlasHoverMembersPainter)
  private
    procedure DebugRow(const ARow: TAtlasDebugValueRow; AIndex: Integer);
    /// <summary>Fläche hinter einer Zeile ab ATop bis FY: gewählt bzw. geändert.</summary>
    procedure RowBack(ATop, AFirstItem: Integer; ASelected, AChanged: Boolean);
  protected
    /// <summary>Rollbereich der Zeilen des aufgeklappten Werts.</summary>
    FDebugRows: TAtlasHoverScroll;
    /// <summary>Zeichen vor dem Ausdruck: ▸ bzw. ▾ bei aufklappbarem Wert, sonst ''.</summary>
    class function ToggleGlyph(AExpandable, AExpanded: Boolean): string; static;
    /// <summary>Alter Wert hinter einem geänderten Wert: „← 980,00“ gedimmt, eine Zeile.</summary>
    procedure OldValue(const AOldText: string);
    /// <summary>Zeilen von AValue (nur aufgeklappt) samt Rollbereich.</summary>
    procedure DebugRows(const AValue: TAtlasDebugValue);
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color;

const
  /// <summary>Einzug je Ebene und Abstand der Zeilen bei 96 dpi.</summary>
  cIndent = 12;
  cRowGap = 3;
  cGlyphClosed = '▸ ';
  cGlyphOpen = '▾ ';
  cOldArrow = '← ';

constructor TAtlasHoverDebugPainter.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create(AInput, AMeasure);
  FDebugRows := TAtlasHoverScroll.None;
end;

class function TAtlasHoverDebugPainter.ToggleGlyph(AExpandable, AExpanded: Boolean): string;
begin
  Result := '';
  if AExpandable and AExpanded then
  begin
    Result := cGlyphOpen;
  end
  else if AExpandable then
  begin
    Result := cGlyphClosed;
  end;
end;

procedure TAtlasHoverDebugPainter.OldValue(const AOldText: string);
var
  mFace: TAtlasHoverFace;
begin
  if AOldText = '' then
  begin
    Exit;
  end;
  mFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallMono, False, False);
  AddText(FLeft, FY, Clipped(mFace, cOldArrow + AOldText, FRight - FLeft), mFace, FColors.Muted);
  Inc(FY, Height(mFace) + Scale(cRowGap));
end;

procedure TAtlasHoverDebugPainter.RowBack(ATop, AFirstItem: Integer; ASelected, AChanged: Boolean);
var
  mItem: TAtlasHoverItem;
begin
  if not ASelected and not AChanged then
  begin
    Exit;
  end;
  // Vor die Texte der Zeile: Bausteine zeichnet das Fenster in Reihenfolge.
  if ASelected then
  begin
    mItem := NewItem(TAtlasHoverItemKind.Fill, Rect(FLeft - Scale(2), ATop, FRight, FY), FColors.Selection);
  end
  else
  begin
    mItem := NewItem(TAtlasHoverItemKind.Fill, Rect(FLeft - Scale(2), ATop, FRight, FY), FColors.WarnSoft);
  end;
  Insert(AFirstItem, mItem);
end;

procedure TAtlasHoverDebugPainter.DebugRow(const ARow: TAtlasDebugValueRow; AIndex: Integer);
var
  mFace, mOldFace: TAtlasHoverFace;
  mTop, mFirst, mX: Integer;
  mText: string;
  mColor: TAtlasColor;
begin
  mFace := TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False);
  mOldFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallMono, False, False);
  mTop := FY;
  mFirst := FItemCount;
  mX := FLeft + Scale(cIndent) * ARow.Depth;
  // „weitere …“ und Getter („auswerten“) sind Verweise; ausstehende Werte gedämpft.
  mColor := FColors.Text;
  if ARow.More or ARow.Lazy then
  begin
    mColor := FColors.Accent;
  end
  else if ARow.Pending then
  begin
    mColor := FColors.Muted;
  end;
  if ARow.More then
  begin
    mText := ARow.Text;
  end
  else
  begin
    mText := ToggleGlyph(ARow.Expandable, ARow.Expanded) + ARow.Name + ' = ' + ARow.Text;
  end;
  mText := Clipped(mFace, mText, FRight - mX);
  AddText(mX, FY, mText, mFace, mColor);
  if ARow.OldText <> '' then
  begin
    Inc(mX, Width(mFace, mText + ' '));
    AddText(mX, FY + Scale(1), Clipped(mOldFace, cOldArrow + ARow.OldText, FRight - mX), mOldFace, FColors.Muted);
  end;
  Inc(FY, Height(mFace) + Scale(cRowGap));
  RowBack(mTop, mFirst, AIndex + 1 = FInput.DebugSelectedRow, ARow.OldText <> '');
  AddHit(TAtlasHoverHitKind.DebugRow, AIndex, Rect(FLeft, mTop, FRight, FY));
end;

procedure TAtlasHoverDebugPainter.DebugRows(const AValue: TAtlasDebugValue);
var
  mIndex, mTop, mFirstItem, mFirstHit: Integer;
begin
  if not AValue.Expanded or (Length(AValue.Rows) = 0) then
  begin
    Exit;
  end;
  mTop := FY;
  mFirstItem := FItemCount;
  mFirstHit := FHitCount;
  for mIndex := 0 to High(AValue.Rows) do
  begin
    DebugRow(AValue.Rows[mIndex], mIndex);
  end;
  ClipScroll(FDebugRows, FInput.DebugRows, mTop, mFirstItem, mFirstHit);
end;

end.
