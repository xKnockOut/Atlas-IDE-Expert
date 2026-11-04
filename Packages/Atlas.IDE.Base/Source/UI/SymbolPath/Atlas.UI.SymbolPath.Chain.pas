unit Atlas.UI.SymbolPath.Chain;

// Gezeichnete Kette eines Wegs zwischen Symbolen (#1117), reine VCL:
// Knoten als Kästen mit Symbol und „Unit · Datei:Zeile“, dazwischen ein Pfeil
// nach unten mit der Kantenart („ruft auf“, „setzt um“ …) und ihrer
// Fundstelle; nur erschlossene Kanten (#1119) gestrichelt mit
// „[erschlossen]“. Bei mehreren gleich langen Wegen je Weg eine Überschrift,
// bei mehrdeutiger Angabe die Treffer als Kästen. Klick wählt eine Zeile,
// Doppelklick oder Enter springt über OnOpen zur Fundstelle, ↑/↓ wählt.
// Die Zeilen legt TAtlasSymbolPathAnswer.Rows fest; Texte in der Sprache der
// Oberfläche (Kantenarten auch englisch). Das Steuerelement wächst mit
// seinem Inhalt und steht in einer TScrollBox.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.SymbolPath.Model;

type
  TAtlasSymbolPathOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);

  TAtlasSymbolPathChain = class(TCustomControl)
  private
    FAnswer: TAtlasSymbolPathAnswer;
    FRows: TArray<TAtlasSymbolPathRow>;
    FTops: TArray<Integer>;
    FHeights: TArray<Integer>;
    FSelected: Integer;
    FOnOpen: TAtlasSymbolPathOpen;
    function Px(AValue: Integer): Integer;
    procedure Layout;
    procedure SetSelected(AValue: Integer);
    procedure OpenSelected;
    procedure DrawHeader(const ABox: TRect; const AMain: string; const AColors: TAtlasColors);
    procedure DrawNode(const ABox: TRect; const AMain, ADetail: string; const AColors: TAtlasColors;
      ASelected: Boolean);
    procedure DrawStep(const ABox: TRect; const AMain, ADetail: string; const AColors: TAtlasColors;
      AInferred, ASelected: Boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetAnswer(const AAnswer: TAtlasSymbolPathAnswer);
    /// <summary>Zeile unter dem Punkt (Client-Koordinaten), -1 ohne.</summary>
    function RowAt(Y: Integer): Integer;
    /// <summary>Oberkante und Höhe einer Zeile (nach Layout).</summary>
    function RowRect(AIndex: Integer): TRect;
    /// <summary>Text je Zeile wie gezeichnet, Haupt- und Nebenzeile mit „ · “ (für Tests und Bildschirmleser).
    /// </summary>
    function Lines: TArray<string>;
    /// <summary>Kantenart in der Sprache der Oberfläche: „ruft auf“, „umgesetzt von“, „verwendet
    /// (implementation)“ …; unbekannte Art: Text des Servers.</summary>
    class function StepCaption(const AStep: TAtlasSymbolPathStep): string; static;
    /// <summary>„Kunden.pas:12“ (1-basiert), '' ohne Datei.</summary>
    class function LocationText(const AFileName: string; ALine: Integer): string; static;
    /// <summary>Hauptzeile und Nebenzeile einer Zeile.</summary>
    class procedure RowTexts(const AAnswer: TAtlasSymbolPathAnswer; const ARow: TAtlasSymbolPathRow;
      out AMain, ADetail: string); static;
    /// <summary>Statuszeile über der Kette: Schritte, Knoten und Dauer; kein Weg; Abbruch; Mehrdeutigkeit.
    /// </summary>
    class function StatusText(const AAnswer: TAtlasSymbolPathAnswer): string; static;
    property Answer: TAtlasSymbolPathAnswer read FAnswer;
    property Rows: TArray<TAtlasSymbolPathRow> read FRows;
    property Selected: Integer read FSelected write SetSelected;
    property OnOpen: TAtlasSymbolPathOpen read FOnOpen write FOnOpen;
    property Font;
    property TabStop default True;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.UI.Strings;

const
  /// <summary>Logische Bildpunkte bei 96 dpi.</summary>
  NodeHeight = 40;
  StepHeight = 30;
  HeaderHeight = 26;
  Margin = 8;
  ArrowIndent = 24;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>AOn für die gewählte Zeile, sonst AOff.</summary>
function PickColor(ASelected: Boolean; AOn, AOff: TAtlasColor): TColor;
begin
  if ASelected then
  begin
    Result := ToColor(AOn);
  end
  else
  begin
    Result := ToColor(AOff);
  end;
end;

{ TAtlasSymbolPathChain }

constructor TAtlasSymbolPathChain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  FSelected := -1;
  Height := Px(NodeHeight);
end;

function TAtlasSymbolPathChain.Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

class function TAtlasSymbolPathChain.LocationText(const AFileName: string; ALine: Integer): string;
begin
  Result := '';
  if AFileName <> '' then
  begin
    Result := Format('%s:%d', [ExtractFileName(AFileName), ALine + 1]);
  end;
end;

type
  /// <summary>Kantenart des Servers ohne Variante und ihr Text.</summary>
  TAtlasStepText = record
    Kind: string;
    Id: TAtlasTextId;
  end;

const
  cStepTexts: array[0..4] of TAtlasStepText = (
    (Kind: 'inherits'; Id: TAtlasTextId.SymbolPathEdgeInherits),
    (Kind: 'parameter'; Id: TAtlasTextId.SymbolPathEdgeParameter),
    (Kind: 'result'; Id: TAtlasTextId.SymbolPathEdgeResult),
    (Kind: 'calls'; Id: TAtlasTextId.SymbolPathEdgeCalls),
    (Kind: 'contains'; Id: TAtlasTextId.SymbolPathEdgeContains));
  cUsesTexts: array[Boolean] of TAtlasTextId = (TAtlasTextId.SymbolPathEdgeUses,
    TAtlasTextId.SymbolPathEdgeUsesImpl);
  cImplementsTexts: array[Boolean] of TAtlasTextId = (TAtlasTextId.SymbolPathEdgeImplements,
    TAtlasTextId.SymbolPathEdgeImplementedBy);
  cHasFieldTexts: array[Boolean] of TAtlasTextId = (TAtlasTextId.SymbolPathEdgeHasField,
    TAtlasTextId.SymbolPathEdgeOfType);

/// <summary>Text einer Kantenart ohne Variante; False bei unbekannter Art.</summary>
function SimpleStepText(const AKind: string; out AId: TAtlasTextId): Boolean;
var
  mEntry: TAtlasStepText;
begin
  for mEntry in cStepTexts do
  begin
    if mEntry.Kind = AKind then
    begin
      AId := mEntry.Id;
      Exit(True);
    end;
  end;
  AId := Default(TAtlasTextId);
  Result := False;
end;

class function TAtlasSymbolPathChain.StepCaption(const AStep: TAtlasSymbolPathStep): string;
var
  mId: TAtlasTextId;
begin
  if AStep.Kind = 'uses' then
  begin
    Result := TAtlasStrings.Text(cUsesTexts[AStep.Implementation_]);
  end
  else if AStep.Kind = 'implements' then
  begin
    Result := TAtlasStrings.Text(cImplementsTexts[AStep.Reverse]);
  end
  else if AStep.Kind = 'hasField' then
  begin
    // Der Server unterscheidet „hat Feld“ (Typ → Typ) und „vom Typ“ (Feld, Variable → Typ).
    Result := TAtlasStrings.Text(cHasFieldTexts[AStep.Caption = 'vom Typ']);
  end
  else if SimpleStepText(AStep.Kind, mId) then
  begin
    Result := TAtlasStrings.Text(mId);
  end
  else
  begin
    Result := AStep.Caption;
  end;
end;

function NodeDetail(const ANode: TAtlasSymbolPathNode): string;
var
  Location: string;
begin
  Result := '';
  if not ANode.IsUnit then
  begin
    Result := ANode.UnitName;
  end;
  Location := TAtlasSymbolPathChain.LocationText(ANode.FileName, ANode.Line);
  if Location <> '' then
  begin
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + Location;
  end;
  if ANode.Library_ then
  begin
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + TAtlasStrings.Text(TAtlasTextId.SymbolPathLibrary);
  end;
end;

class procedure TAtlasSymbolPathChain.RowTexts(const AAnswer: TAtlasSymbolPathAnswer;
  const ARow: TAtlasSymbolPathRow; out AMain, ADetail: string);
var
  Node: TAtlasSymbolPathNode;
  Step: TAtlasSymbolPathStep;
begin
  AMain := '';
  ADetail := '';
  case ARow.Kind of
    TAtlasSymbolPathRowKind.Header:
      AMain := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathRouteHeader, [ARow.Route + 1]);
    TAtlasSymbolPathRowKind.Node:
      begin
        Node := AAnswer.Routes[ARow.Route].Nodes[ARow.Index];
        AMain := Format('%d  %s', [ARow.Index + 1, Node.Caption]);
        ADetail := NodeDetail(Node);
      end;
    TAtlasSymbolPathRowKind.Step:
      begin
        Step := AAnswer.Routes[ARow.Route].Steps[ARow.Index];
        AMain := StepCaption(Step);
        if Step.Inferred then
        begin
          AMain := AMain + ' [' + TAtlasStrings.Text(TAtlasTextId.SymbolPathInferred) + ']';
        end;
        ADetail := LocationText(Step.FileName, Step.Line);
      end;
    TAtlasSymbolPathRowKind.Candidate:
      begin
        Node := AAnswer.Candidates[ARow.Index];
        AMain := Node.Caption;
        ADetail := NodeDetail(Node);
      end;
  end;
end;

class function TAtlasSymbolPathChain.StatusText(const AAnswer: TAtlasSymbolPathAnswer): string;
begin
  case AAnswer.Status of
    TAtlasSymbolPathStatus.Found:
      begin
        if Length(AAnswer.Routes) > 1 then
        begin
          Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFoundMany, [AAnswer.StepCount, Length(AAnswer.Routes),
            AAnswer.Visited, AAnswer.ElapsedMs]);
        end
        else
        begin
          Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFound, [AAnswer.StepCount, AAnswer.Visited,
            AAnswer.ElapsedMs]);
        end;
        if AAnswer.MoreRoutes then
        begin
          Result := Result + TAtlasStrings.Text(TAtlasTextId.SymbolPathMoreRoutes);
        end;
        if AAnswer.CallsIncomplete then
        begin
          Result := Result + TAtlasStrings.Text(TAtlasTextId.SymbolPathCallsIncomplete);
        end;
      end;
    TAtlasSymbolPathStatus.NoPath:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNoPath, [AAnswer.MaxSteps, AAnswer.Visited]);
    TAtlasSymbolPathStatus.Aborted:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAborted, [AAnswer.SearchedSteps, AAnswer.Visited,
        AAnswer.AbortReason]);
    TAtlasSymbolPathStatus.Ambiguous:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathAmbiguous, [AAnswer.Subject]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathNotFound, [AAnswer.Subject]);
  end;
end;

procedure TAtlasSymbolPathChain.SetAnswer(const AAnswer: TAtlasSymbolPathAnswer);
begin
  FAnswer := AAnswer;
  FRows := FAnswer.Rows;
  FSelected := -1;
  // Erste anspringbare Zeile wählen, damit Enter gleich etwas tut.
  if Length(FRows) > 0 then
  begin
    FSelected := 0;
    if FRows[0].Kind = TAtlasSymbolPathRowKind.Header then
    begin
      FSelected := Min(1, High(FRows));
    end;
  end;
  Layout;
  Invalidate;
end;

procedure TAtlasSymbolPathChain.Layout;
var
  Index, Top: Integer;
begin
  SetLength(FTops, Length(FRows));
  SetLength(FHeights, Length(FRows));
  Top := Px(Margin);
  for Index := 0 to High(FRows) do
  begin
    FTops[Index] := Top;
    case FRows[Index].Kind of
      TAtlasSymbolPathRowKind.Header:
        FHeights[Index] := Px(HeaderHeight);
      TAtlasSymbolPathRowKind.Step:
        FHeights[Index] := Px(StepHeight);
    else
      FHeights[Index] := Px(NodeHeight);
    end;
    Inc(Top, FHeights[Index]);
    // Treffer stehen ohne Pfeil untereinander, mit etwas Abstand.
    if FRows[Index].Kind = TAtlasSymbolPathRowKind.Candidate then
    begin
      Inc(Top, Px(4));
    end;
  end;
  Height := Top + Px(Margin);
end;

procedure TAtlasSymbolPathChain.Resize;
begin
  inherited;
  Invalidate;
end;

procedure TAtlasSymbolPathChain.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited;
  Layout;
end;

function TAtlasSymbolPathChain.RowAt(Y: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FRows) do
  begin
    if (Y >= FTops[Index]) and (Y < FTops[Index] + FHeights[Index]) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasSymbolPathChain.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
  begin
    Result := TRect.Create(Px(Margin), FTops[AIndex], ClientWidth - Px(Margin), FTops[AIndex] + FHeights[AIndex]);
  end;
end;

function TAtlasSymbolPathChain.Lines: TArray<string>;
var
  Row: TAtlasSymbolPathRow;
  Main, Detail: string;
begin
  Result := nil;
  for Row in FRows do
  begin
    RowTexts(FAnswer, Row, Main, Detail);
    if Detail <> '' then
    begin
      Main := Main + ' · ' + Detail;
    end;
    Result := Result + [Main];
  end;
end;

procedure TAtlasSymbolPathChain.SetSelected(AValue: Integer);
var
  Bounds: TRect;
begin
  if (AValue < -1) or (AValue > High(FRows)) then
  begin
    AValue := -1;
  end;
  if FSelected = AValue then
  begin
    Exit;
  end;
  FSelected := AValue;
  Invalidate;
  // In der Scrollbox sichtbar halten.
  if (FSelected >= 0) and (Parent is TScrollingWinControl) then
  begin
    Bounds := RowRect(FSelected);
    if Top + Bounds.Top < 0 then
    begin
      TScrollingWinControl(Parent).VertScrollBar.Position := TScrollingWinControl(Parent).VertScrollBar.Position +
        Top + Bounds.Top;
    end
    else if Top + Bounds.Bottom > Parent.ClientHeight then
    begin
      TScrollingWinControl(Parent).VertScrollBar.Position := TScrollingWinControl(Parent).VertScrollBar.Position +
        Top + Bounds.Bottom - Parent.ClientHeight;
    end;
  end;
end;

procedure TAtlasSymbolPathChain.OpenSelected;
var
  Row: TAtlasSymbolPathRow;
begin
  if (FSelected < 0) or (FSelected > High(FRows)) then
  begin
    Exit;
  end;
  Row := FRows[FSelected];
  if (Row.FileName = '') or not Assigned(FOnOpen) then
  begin
    Exit;
  end;
  FOnOpen(Row.FileName, Row.Line, Row.Character);
end;

procedure TAtlasSymbolPathChain.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited;
  if Showing and CanFocus then
  begin
    SetFocus;
  end;
  Hit := RowAt(Y);
  if (Hit >= 0) and (FRows[Hit].Kind <> TAtlasSymbolPathRowKind.Header) then
  begin
    SetSelected(Hit);
  end;
end;

procedure TAtlasSymbolPathChain.DblClick;
begin
  inherited;
  OpenSelected;
end;

procedure TAtlasSymbolPathChain.KeyDown(var Key: Word; Shift: TShiftState);
var
  Next: Integer;
begin
  inherited;
  case Key of
    VK_RETURN:
      begin
        OpenSelected;
        Key := 0;
      end;
    VK_DOWN, VK_UP:
      begin
        Next := FSelected;
        repeat
          if Key = VK_DOWN then
          begin
            Inc(Next);
          end
          else
          begin
            Dec(Next);
          end;
        until (Next < 0) or (Next > High(FRows)) or (FRows[Next].Kind <> TAtlasSymbolPathRowKind.Header);
        if (Next >= 0) and (Next <= High(FRows)) then
        begin
          SetSelected(Next);
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathChain.DrawHeader(const ABox: TRect; const AMain: string; const AColors: TAtlasColors);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(AColors.Text);
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(ABox.Left, ABox.Top + (ABox.Height - Canvas.TextHeight(AMain)) div 2, AMain);
  Canvas.Font.Style := [];
end;

procedure TAtlasSymbolPathChain.DrawNode(const ABox: TRect; const AMain, ADetail: string;
  const AColors: TAtlasColors; ASelected: Boolean);
var
  mTextTop: Integer;
begin
  // Kasten: gewählt mit Auswahlfläche und Akzentrand.
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  if ASelected then
  begin
    Canvas.Brush.Color := ToColor(AColors.Selection);
    Canvas.Pen.Color := ToColor(AColors.Accent);
  end
  else
  begin
    Canvas.Brush.Color := ToColor(AColors.Gutter);
    Canvas.Pen.Color := ToColor(AColors.Line);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.RoundRect(ABox.Left, ABox.Top, ABox.Right, ABox.Bottom, Px(6), Px(6));
  Canvas.Brush.Style := bsClear;
  mTextTop := ABox.Top + Px(3);
  Canvas.Font.Color := ToColor(AColors.Text);
  Canvas.Font.Style := [fsBold];
  Canvas.TextRect(ABox, ABox.Left + Px(8), mTextTop, AMain);
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(AColors.Muted);
  Canvas.TextRect(ABox, ABox.Left + Px(8), mTextTop + Canvas.TextHeight('Ag') + Px(1), ADetail);
end;

procedure TAtlasSymbolPathChain.DrawStep(const ABox: TRect; const AMain, ADetail: string;
  const AColors: TAtlasColors; AInferred, ASelected: Boolean);
var
  mX, mBottom, mTip, mTextTop: Integer;
begin
  // Pfeil nach unten links, erschlossene Kanten gestrichelt (Breite 1, sonst zeichnet GDI durchgehend).
  mX := ABox.Left + Px(ArrowIndent);
  mBottom := ABox.Bottom - Px(2);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(1, Px(2));
  if AInferred then
  begin
    Canvas.Pen.Style := psDash;
    Canvas.Pen.Width := 1;
  end;
  Canvas.Pen.Color := PickColor(ASelected, AColors.Accent, AColors.Muted);
  Canvas.MoveTo(mX, ABox.Top + Px(2));
  Canvas.LineTo(mX, mBottom);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  mTip := Px(5);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Canvas.Pen.Color;
  Canvas.Polygon([Point(mX - mTip, mBottom - mTip), Point(mX + mTip, mBottom - mTip), Point(mX, mBottom)]);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := PickColor(ASelected, AColors.Accent, AColors.Text);
  mTextTop := ABox.Top + (ABox.Height - Canvas.TextHeight(AMain)) div 2;
  Canvas.TextOut(mX + Px(14), mTextTop, AMain);
  if ADetail <> '' then
  begin
    Canvas.Font.Color := ToColor(AColors.Muted);
    Canvas.TextOut(mX + Px(14) + Canvas.TextWidth(AMain) + Px(12), mTextTop, ADetail);
  end;
end;

procedure TAtlasSymbolPathChain.Paint;
var
  mColors: TAtlasColors;
  mIndex: Integer;
  mBox: TRect;
  mMain, mDetail: string;
  mRow: TAtlasSymbolPathRow;
begin
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mColors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  for mIndex := 0 to High(FRows) do
  begin
    mRow := FRows[mIndex];
    RowTexts(FAnswer, mRow, mMain, mDetail);
    mBox := RowRect(mIndex);
    case mRow.Kind of
      TAtlasSymbolPathRowKind.Header:
        DrawHeader(mBox, mMain, mColors);
      TAtlasSymbolPathRowKind.Node, TAtlasSymbolPathRowKind.Candidate:
        DrawNode(mBox, mMain, mDetail, mColors, mIndex = FSelected);
      TAtlasSymbolPathRowKind.Step:
        DrawStep(mBox, mMain, mDetail, mColors, mRow.Inferred, mIndex = FSelected);
    end;
  end;
  if Focused and (FSelected >= 0) then
  begin
    Canvas.DrawFocusRect(RowRect(FSelected));
  end;
end;

end.
