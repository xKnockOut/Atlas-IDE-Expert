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
  Winapi.Windows,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Style.Palette,
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
    Result := Format('%s:%d', [ExtractFileName(AFileName), ALine + 1]);
end;

class function TAtlasSymbolPathChain.StepCaption(const AStep: TAtlasSymbolPathStep): string;
begin
  if AStep.Kind = 'uses' then
  begin
    if AStep.Implementation_ then
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUsesImpl)
    else
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeUses);
  end
  else if AStep.Kind = 'inherits' then
    Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeInherits)
  else if AStep.Kind = 'implements' then
  begin
    if AStep.Reverse then
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplementedBy)
    else
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeImplements);
  end
  else if AStep.Kind = 'hasField' then
  begin
    // Der Server unterscheidet „hat Feld“ (Typ → Typ) und „vom Typ“ (Feld, Variable → Typ).
    if AStep.Caption = 'vom Typ' then
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeOfType)
    else
      Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeHasField);
  end
  else if AStep.Kind = 'parameter' then
    Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeParameter)
  else if AStep.Kind = 'result' then
    Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeResult)
  else if AStep.Kind = 'calls' then
    Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeCalls)
  else if AStep.Kind = 'contains' then
    Result := TAtlasStrings.Text(TAtlasTextId.SymbolPathEdgeContains)
  else
    Result := AStep.Caption;
end;

function NodeDetail(const ANode: TAtlasSymbolPathNode): string;
var
  Location: string;
begin
  Result := '';
  if not ANode.IsUnit then
    Result := ANode.UnitName;
  Location := TAtlasSymbolPathChain.LocationText(ANode.FileName, ANode.Line);
  if Location <> '' then
  begin
    if Result <> '' then
      Result := Result + ' · ';
    Result := Result + Location;
  end;
  if ANode.Library_ then
  begin
    if Result <> '' then
      Result := Result + ' · ';
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
          AMain := AMain + ' [' + TAtlasStrings.Text(TAtlasTextId.SymbolPathInferred) + ']';
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
          Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFoundMany, [AAnswer.StepCount, Length(AAnswer.Routes),
            AAnswer.Visited, AAnswer.ElapsedMs])
        else
          Result := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathFound, [AAnswer.StepCount, AAnswer.Visited,
            AAnswer.ElapsedMs]);
        if AAnswer.MoreRoutes then
          Result := Result + TAtlasStrings.Text(TAtlasTextId.SymbolPathMoreRoutes);
        if AAnswer.CallsIncomplete then
          Result := Result + TAtlasStrings.Text(TAtlasTextId.SymbolPathCallsIncomplete);
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
      FSelected := Min(1, High(FRows));
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
      Inc(Top, Px(4));
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
    if (Y >= FTops[Index]) and (Y < FTops[Index] + FHeights[Index]) then
      Exit(Index);
  Result := -1;
end;

function TAtlasSymbolPathChain.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
    Result := TRect.Create(Px(Margin), FTops[AIndex], ClientWidth - Px(Margin), FTops[AIndex] + FHeights[AIndex]);
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
      Main := Main + ' · ' + Detail;
    Result := Result + [Main];
  end;
end;

procedure TAtlasSymbolPathChain.SetSelected(AValue: Integer);
var
  Bounds: TRect;
begin
  if (AValue < -1) or (AValue > High(FRows)) then
    AValue := -1;
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
  // In der Scrollbox sichtbar halten.
  if (FSelected >= 0) and (Parent is TScrollingWinControl) then
  begin
    Bounds := RowRect(FSelected);
    if Top + Bounds.Top < 0 then
      TScrollingWinControl(Parent).VertScrollBar.Position := TScrollingWinControl(Parent).VertScrollBar.Position +
        Top + Bounds.Top
    else if Top + Bounds.Bottom > Parent.ClientHeight then
      TScrollingWinControl(Parent).VertScrollBar.Position := TScrollingWinControl(Parent).VertScrollBar.Position +
        Top + Bounds.Bottom - Parent.ClientHeight;
  end;
end;

procedure TAtlasSymbolPathChain.OpenSelected;
var
  Row: TAtlasSymbolPathRow;
begin
  if (FSelected < 0) or (FSelected > High(FRows)) then
    Exit;
  Row := FRows[FSelected];
  if (Row.FileName = '') or not Assigned(FOnOpen) then
    Exit;
  FOnOpen(Row.FileName, Row.Line, Row.Character);
end;

procedure TAtlasSymbolPathChain.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited;
  if Showing and CanFocus then
    SetFocus;
  Hit := RowAt(Y);
  if (Hit >= 0) and (FRows[Hit].Kind <> TAtlasSymbolPathRowKind.Header) then
    SetSelected(Hit);
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
            Inc(Next)
          else
            Dec(Next);
        until (Next < 0) or (Next > High(FRows)) or (FRows[Next].Kind <> TAtlasSymbolPathRowKind.Header);
        if (Next >= 0) and (Next <= High(FRows)) then
          SetSelected(Next);
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathChain.Paint;
var
  Colors: TAtlasColors;
  Index, X, Y, Bottom, Tip, TextTop: Integer;
  Box: TRect;
  Main, Detail: string;
  Row: TAtlasSymbolPathRow;
begin
  Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  for Index := 0 to High(FRows) do
  begin
    Row := FRows[Index];
    RowTexts(FAnswer, Row, Main, Detail);
    Box := RowRect(Index);
    case Row.Kind of
      TAtlasSymbolPathRowKind.Header:
        begin
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := ToColor(Colors.Text);
          Canvas.Font.Style := [fsBold];
          Canvas.TextOut(Box.Left, Box.Top + (Box.Height - Canvas.TextHeight(Main)) div 2, Main);
          Canvas.Font.Style := [];
        end;
      TAtlasSymbolPathRowKind.Node, TAtlasSymbolPathRowKind.Candidate:
        begin
          // Kasten: gewählt mit Auswahlfläche und Akzentrand.
          Canvas.Pen.Style := psSolid;
          Canvas.Pen.Width := 1;
          if Index = FSelected then
          begin
            Canvas.Brush.Color := ToColor(Colors.Selection);
            Canvas.Pen.Color := ToColor(Colors.Accent);
          end
          else
          begin
            Canvas.Brush.Color := ToColor(Colors.Gutter);
            Canvas.Pen.Color := ToColor(Colors.Line);
          end;
          Canvas.Brush.Style := bsSolid;
          Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, Px(6), Px(6));
          Canvas.Brush.Style := bsClear;
          TextTop := Box.Top + Px(3);
          Canvas.Font.Color := ToColor(Colors.Text);
          Canvas.Font.Style := [fsBold];
          Canvas.TextRect(Box, Box.Left + Px(8), TextTop, Main);
          Canvas.Font.Style := [];
          Canvas.Font.Color := ToColor(Colors.Muted);
          Canvas.TextRect(Box, Box.Left + Px(8), TextTop + Canvas.TextHeight('Ag') + Px(1), Detail);
        end;
      TAtlasSymbolPathRowKind.Step:
        begin
          // Pfeil nach unten links, erschlossene Kanten gestrichelt (Breite 1, sonst zeichnet GDI durchgehend).
          X := Box.Left + Px(ArrowIndent);
          Y := Box.Top + Px(2);
          Bottom := Box.Bottom - Px(2);
          if Row.Inferred then
          begin
            Canvas.Pen.Style := psDash;
            Canvas.Pen.Width := 1;
          end
          else
          begin
            Canvas.Pen.Style := psSolid;
            Canvas.Pen.Width := Max(1, Px(2));
          end;
          if Index = FSelected then
            Canvas.Pen.Color := ToColor(Colors.Accent)
          else
            Canvas.Pen.Color := ToColor(Colors.Muted);
          Canvas.MoveTo(X, Y);
          Canvas.LineTo(X, Bottom);
          Canvas.Pen.Style := psSolid;
          Canvas.Pen.Width := 1;
          Tip := Px(5);
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := Canvas.Pen.Color;
          Canvas.Polygon([Point(X - Tip, Bottom - Tip), Point(X + Tip, Bottom - Tip), Point(X, Bottom)]);
          Canvas.Brush.Style := bsClear;
          if Index = FSelected then
            Canvas.Font.Color := ToColor(Colors.Accent)
          else
            Canvas.Font.Color := ToColor(Colors.Text);
          TextTop := Box.Top + (Box.Height - Canvas.TextHeight(Main)) div 2;
          Canvas.TextOut(X + Px(14), TextTop, Main);
          if Detail <> '' then
          begin
            Canvas.Font.Color := ToColor(Colors.Muted);
            Canvas.TextOut(X + Px(14) + Canvas.TextWidth(Main) + Px(12), TextTop, Detail);
          end;
        end;
    end;
  end;
  if Focused and (FSelected >= 0) then
  begin
    Box := RowRect(FSelected);
    Canvas.DrawFocusRect(Box);
  end;
end;

end.
