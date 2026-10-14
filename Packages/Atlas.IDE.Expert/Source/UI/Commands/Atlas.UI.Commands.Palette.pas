unit Atlas.UI.Commands.Palette;

// Fenster der Befehlspalette (#502) im Stil der Atlas-Popups: oben das
// Eingabefeld, darunter die Treffer mit hervorgehobenen Zeichen, Menüpfad
// gedimmt und Tastenkürzel rechts. Anders als die Vervollständigung nimmt
// die Palette den Fokus (sie hat ein eigenes Eingabefeld). Enter führt aus,
// Escape oder ein Klick daneben schließt.
// Mit OnQuery (Symbolsuche, #400) holt das Fenster die Einträge 150 ms nach
// der letzten Eingabe neu und ordnet sie dann wie die Befehle.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Commands.Palette;

type
  TAtlasPaletteWindow = class(TForm)
  private const
    VisibleRows = 12;
  private
    FCommands: TArray<TAtlasCommand>;
    FHistory: TAtlasCommandHistory;
    FColors: TAtlasColors;
    FPattern: string;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FOnExecute: TProc<TAtlasCommand>;
    FExecuting: Boolean;
    FOnQuery: TFunc<string, TArray<TAtlasCommand>>;
    FQueryTimer: TTimer;
    FPrompt: string;
    procedure PatternChanged;
    procedure QueryTick(Sender: TObject);
    function RowHeight: Integer;
    function InputHeight: Integer;
    function RowRect(ARow: Integer): TRect;
    procedure Refilter;
    procedure Select(AIndex: Integer);
    procedure Execute;
    procedure DrawRow(ARow: Integer);
    procedure DrawHighlighted(const AText: string; const ARect: TRect);
    procedure FormDeactivate(Sender: TObject);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>AHistory gehört weiter dem Aufrufer.</summary>
    constructor CreatePalette(AOwner: TComponent; const ACommands: TArray<TAtlasCommand>;
      AHistory: TAtlasCommandHistory; const AColors: TAtlasColors);
    /// <summary>Oben mittig über AArea (Editor bzw. Hauptfenster).</summary>
    procedure ShowOver(const AArea: TRect);
    /// <summary>Nach dem Schließen; das Fenster gibt sich danach selbst frei.</summary>
    property OnExecute: TProc<TAtlasCommand> read FOnExecute write FOnExecute;
    property Pattern: string read FPattern;
    /// <summary>Einträge zur Eingabe neu holen (z. B. beim Server); läuft im Hauptthread.</summary>
    property OnQuery: TFunc<string, TArray<TAtlasCommand>> read FOnQuery write FOnQuery;
    /// <summary>Zeichen im leeren Eingabefeld, Standard "&gt;".</summary>
    property Prompt: string read FPrompt write FPrompt;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Completion.Presentation;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasPaletteWindow }

constructor TAtlasPaletteWindow.CreatePalette(AOwner: TComponent; const ACommands: TArray<TAtlasCommand>;
  AHistory: TAtlasCommandHistory; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FCommands := ACommands;
  FHistory := AHistory;
  FColors := AColors;
  BorderStyle := bsNone;
  KeyPreview := False;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  OnDeactivate := FormDeactivate;
  FPrompt := '>';
  FQueryTimer := TTimer.Create(Self);
  FQueryTimer.Enabled := False;
  FQueryTimer.Interval := 150;
  FQueryTimer.OnTimer := QueryTick;
  Refilter;
end;

procedure TAtlasPaletteWindow.PatternChanged;
begin
  Refilter;
  if Assigned(FOnQuery) then
  begin
    // Neu starten: erst nach einer Tipppause fragen.
    FQueryTimer.Enabled := False;
    FQueryTimer.Enabled := True;
  end;
end;

procedure TAtlasPaletteWindow.QueryTick(Sender: TObject);
begin
  FQueryTimer.Enabled := False;
  if not Assigned(FOnQuery) or FExecuting then
    Exit;
  FCommands := FOnQuery(FPattern);
  Refilter;
end;

procedure TAtlasPaletteWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

function TAtlasPaletteWindow.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(10);
end;

function TAtlasPaletteWindow.InputHeight: Integer;
begin
  Result := RowHeight + ScaleValue(10);
end;

function TAtlasPaletteWindow.RowRect(ARow: Integer): TRect;
begin
  Result := Rect(ScaleValue(6), InputHeight + ARow * RowHeight, ClientWidth - ScaleValue(6),
    InputHeight + (ARow + 1) * RowHeight);
end;

procedure TAtlasPaletteWindow.ShowOver(const AArea: TRect);
var
  Width_: Integer;
begin
  Width_ := Min(ScaleValue(640), AArea.Width - ScaleValue(40));
  SetBounds(AArea.Left + (AArea.Width - Width_) div 2, AArea.Top + ScaleValue(60), Width_,
    InputHeight + VisibleRows * RowHeight + ScaleValue(8));
  Show;
  SetFocus;
end;

procedure TAtlasPaletteWindow.Refilter;
begin
  FOrder := TAtlasCommandPalette.Order(FCommands, FPattern, FHistory);
  FSelected := 0;
  FTop := 0;
  Invalidate;
end;

procedure TAtlasPaletteWindow.Select(AIndex: Integer);
begin
  if Length(FOrder) = 0 then
    Exit;
  FSelected := EnsureRange(AIndex, 0, High(FOrder));
  if FSelected < FTop then
    FTop := FSelected
  else if FSelected >= FTop + VisibleRows then
    FTop := FSelected - VisibleRows + 1;
  Invalidate;
end;

procedure TAtlasPaletteWindow.Execute;
var
  Command: TAtlasCommand;
  Handler: TProc<TAtlasCommand>;
begin
  if (Length(FOrder) = 0) or FExecuting then
    Exit;
  FExecuting := True;
  Command := FCommands[FOrder[FSelected]];
  Handler := FOnExecute;
  Close;
  // Erst nach dem Schließen ausführen: Der Befehl öffnet evtl. selbst einen Dialog.
  if Assigned(Handler) then
    TThread.ForceQueue(nil,
      procedure
      begin
        Handler(Command);
      end);
  Release;
end;

procedure TAtlasPaletteWindow.FormDeactivate(Sender: TObject);
begin
  if not FExecuting then
  begin
    FExecuting := True;
    Close;
    Release;
  end;
end;

procedure TAtlasPaletteWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      FormDeactivate(Self);
    VK_RETURN:
      Execute;
    VK_UP:
      Select(FSelected - 1);
    VK_DOWN:
      Select(FSelected + 1);
    VK_PRIOR:
      Select(FSelected - VisibleRows);
    VK_NEXT:
      Select(FSelected + VisibleRows);
    VK_BACK:
      if FPattern <> '' then
      begin
        if ssCtrl in Shift then
          FPattern := ''
        else
          Delete(FPattern, Length(FPattern), 1);
        PatternChanged;
      end;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasPaletteWindow.KeyPress(var Key: Char);
begin
  if Key >= ' ' then
  begin
    FPattern := FPattern + Key;
    PatternChanged;
  end;
  Key := #0;
end;

procedure TAtlasPaletteWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited;
  if Y < InputHeight then
    Exit;
  Row := (Y - InputHeight) div RowHeight;
  if FTop + Row <= High(FOrder) then
  begin
    Select(FTop + Row);
    Execute;
  end;
end;

function TAtlasPaletteWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTop := EnsureRange(FTop - Sign(WheelDelta) * 3, 0, Max(0, Length(FOrder) - VisibleRows));
  Invalidate;
  Result := True;
end;

procedure TAtlasPaletteWindow.DrawHighlighted(const AText: string; const ARect: TRect);
var
  Marks: TArray<Boolean>;
  Position, Index, Run, X: Integer;
  Part: TRect;
  Chunk: string;
begin
  SetLength(Marks, Length(AText) + 1);
  for Position in TAtlasItemPresentation.Highlights(FPattern, AText) do
    if (Position >= 1) and (Position <= Length(AText)) then
      Marks[Position] := True;
  X := ARect.Left;
  Index := 1;
  while Index <= Length(AText) do
  begin
    Run := Index;
    while (Run < Length(AText)) and (Marks[Run + 1] = Marks[Index]) do
      Inc(Run);
    Chunk := Copy(AText, Index, Run - Index + 1);
    if Marks[Index] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(FColors.Text);
    end;
    Part := Rect(X, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(Chunk), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Chunk));
    Index := Run + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasPaletteWindow.DrawRow(ARow: Integer);
var
  Command: TAtlasCommand;
  Row, Part: TRect;
  ShortCutWidth, CaptionWidth: Integer;
begin
  Command := FCommands[FOrder[FTop + ARow]];
  Row := RowRect(ARow);
  if FTop + ARow = FSelected then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(Row);
  end;
  Canvas.Brush.Style := bsClear;
  InflateRect(Row, -ScaleValue(8), 0);
  ShortCutWidth := 0;
  if Command.ShortCut <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    ShortCutWidth := Canvas.TextWidth(Command.ShortCut);
    Part := Rect(Row.Right - ShortCutWidth, Row.Top, Row.Right, Row.Bottom);
    DrawText(Canvas.Handle, PChar(Command.ShortCut), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Inc(ShortCutWidth, ScaleValue(16));
  end;
  CaptionWidth := Min(Canvas.TextWidth(Command.Caption) + ScaleValue(4), Row.Width - ShortCutWidth);
  DrawHighlighted(Command.Caption, Rect(Row.Left, Row.Top, Row.Left + CaptionWidth, Row.Bottom));
  if Command.Path <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    Part := Rect(Row.Left + CaptionWidth + ScaleValue(10), Row.Top, Row.Right - ShortCutWidth, Row.Bottom);
    DrawText(Canvas.Handle, PChar(Command.Path), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteWindow.Paint;
var
  Input: TRect;
  Row: Integer;
  Text: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Eingabefeld mit Akzentrahmen.
  Input := Rect(ScaleValue(6), ScaleValue(6), ClientWidth - ScaleValue(6), InputHeight - ScaleValue(4));
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.Rectangle(Input);
  InflateRect(Input, -ScaleValue(8), 0);
  Canvas.Brush.Style := bsClear;
  if FPattern = '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    Text := FPrompt;
  end
  else
  begin
    Canvas.Font.Color := ToColor(FColors.Text);
    Text := FPattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(Text), -1, Input, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  for Row := 0 to VisibleRows - 1 do
    if FTop + Row <= High(FOrder) then
      DrawRow(Row);
  // Rahmen des Fensters.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.