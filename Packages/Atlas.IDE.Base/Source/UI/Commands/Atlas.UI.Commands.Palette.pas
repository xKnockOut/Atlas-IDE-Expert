unit Atlas.UI.Commands.Palette;

// Fenster der Befehlspalette (#502) im Stil der Atlas-Popups: oben das
// Eingabefeld, darunter die Treffer mit hervorgehobenen Zeichen, Menüpfad
// gedimmt und Tastenkürzel rechts. Anders als die Vervollständigung nimmt
// die Palette den Fokus (sie hat ein eigenes Eingabefeld). Enter führt aus,
// Escape oder ein Klick daneben schließt.
// Mit OnQuery (Symbolsuche, #400) holt das Fenster die Einträge 150 ms nach
// der letzten Eingabe neu und ordnet sie dann wie die Befehle.
// Schnell öffnen (#503): Mit Presorted bleibt die Reihenfolge von OnQuery
// (der Aufrufer filtert und ordnet selbst), QueryDelay 0 fragt bei jedem
// Tastendruck sofort, und OnHighlight bestimmt den hervorgehobenen Text
// (Suchtext ohne Präfix wie "@").
// Sprungmenü der Brotkrumenleiste (#590): ShowAt öffnet unter einem Punkt,
// InitialId wählt bei leerer Eingabe den aktuellen Eintrag, OnExecuteShift
// erfährt zusätzlich, ob mit Umschalt+Enter ausgeführt wurde.
// Zusatzgruppe (#1270, Issues): SetGroup zeigt unter den Befehlen eine
// Überschrift, eine Statuszeile und eigene Einträge; Überschrift und Status
// lassen sich nicht wählen. OnPattern erfährt jede Eingabe sofort (die Quelle
// entprellt selbst), OnGroupExecute bekommt Enter, Strg+Enter,
// Umschalt+Enter und Strg+C auf einem Eintrag der Gruppe, OnClosed das
// Schließen (einmal, auch beim Freigeben).

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
    FKeepOrder: Boolean;
    FPresorted: Boolean;
    FOnHighlight: TFunc<string, string>;
    FInitialId: string;
    FShiftExecuted: Boolean;
    FCtrlExecuted: Boolean;
    FOnExecuteShift: TProc<TAtlasCommand, Boolean>;
    FGroup: TAtlasPaletteGroup;
    FOnPattern: TProc<string>;
    FOnGroupExecute: TProc<TAtlasCommand, TAtlasPaletteAction>;
    FOnClosed: TProc;
    FClosedSent: Boolean;
    procedure PatternChanged;
    procedure QueryTick(Sender: TObject);
    function RowHeight: Integer;
    function InputHeight: Integer;
    function RowRect(ARow: Integer): TRect;
    procedure Refilter;
    procedure Select(AIndex: Integer);
    /// <summary>Um ADelta weiter; Überschrift und Status werden übersprungen.</summary>
    procedure Step(ADelta: Integer);
    function Rows: TAtlasPaletteRows;
    procedure SelectFirst;
    procedure Execute;
    procedure ExecuteItem(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure NotifyClosed;
    procedure DrawRow(ARow: Integer);
    procedure DrawCommand(const ACommand: TAtlasCommand; const ARow: TRect; ASelected: Boolean;
      const AHighlight: string);
    procedure DrawHighlighted(const AText, AHighlight: string; const ARect: TRect);
    procedure FormDeactivate(Sender: TObject);
    procedure SetKeepOrder(AValue: Boolean);
    procedure SetPresorted(AValue: Boolean);
    function GetQueryDelay: Integer;
    procedure SetQueryDelay(AValue: Integer);
    function HighlightPattern: string;
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
    destructor Destroy; override;
    /// <summary>Zusatzgruppe unter den Befehlen zeigen bzw. ersetzen (#1270); TAtlasPaletteGroup.None entfernt sie.
    /// Steht die Auswahl auf einem Befehl, bleibt sie dort; sonst der erste Eintrag.</summary>
    procedure SetGroup(const AGroup: TAtlasPaletteGroup);
    /// <summary>Zeilen insgesamt (Befehle und Gruppe).</summary>
    function RowCount: Integer;
    /// <summary>Art der Zeile ARow; AIndex: Befehl in der Liste der Treffer bzw. Eintrag der Gruppe.</summary>
    function RowKind(ARow: Integer; out AIndex: Integer): TAtlasPaletteRowKind;
    /// <summary>Oben mittig über AArea (Editor bzw. Hauptfenster).</summary>
    procedure ShowOver(const AArea: TRect);
    /// <summary>Linke obere Ecke bei APoint (Bildschirm), AWidth breit; bleibt im Arbeitsbereich.</summary>
    procedure ShowAt(const APoint: TPoint; AWidth: Integer);
    /// <summary>Einträge ersetzen (etwa die erste Liste, wenn OnQuery das Fenster braucht).</summary>
    procedure SetCommands(const ACommands: TArray<TAtlasCommand>);
    /// <summary>Nach dem Schließen; das Fenster gibt sich danach selbst frei.</summary>
    property OnExecute: TProc<TAtlasCommand> read FOnExecute write FOnExecute;
    property Pattern: string read FPattern;
    /// <summary>Einträge zur Eingabe neu holen (z. B. beim Server); läuft im Hauptthread.</summary>
    property OnQuery: TFunc<string, TArray<TAtlasCommand>> read FOnQuery write FOnQuery;
    /// <summary>Zeichen im leeren Eingabefeld, Standard "&gt;".</summary>
    property Prompt: string read FPrompt write FPrompt;
    /// <summary>Reihenfolge der Einträge beibehalten statt alphabetisch (Code-Aktionen, #399); vor ShowOver setzen.</summary>
    property KeepOrder: Boolean read FKeepOrder write SetKeepOrder;
    /// <summary>Einträge in der Reihenfolge von OnQuery bzw. ACommands zeigen, ohne zu filtern (#503).</summary>
    property Presorted: Boolean read FPresorted write SetPresorted;
    /// <summary>Wartezeit vor OnQuery in ms, Standard 150; 0 = sofort bei jeder Eingabe.</summary>
    property QueryDelay: Integer read GetQueryDelay write SetQueryDelay;
    /// <summary>Text, dessen Zeichen in den Einträgen hervorgehoben werden; ohne die Eingabe selbst.</summary>
    property OnHighlight: TFunc<string, string> read FOnHighlight write FOnHighlight;
    /// <summary>Eintrag, der bei leerer Eingabe gewählt ist (Kennung); vor ShowAt setzen.</summary>
    property InitialId: string read FInitialId write FInitialId;
    /// <summary>Wie OnExecute, mit True nach Umschalt+Enter; ersetzt OnExecute, wenn gesetzt.</summary>
    property OnExecuteShift: TProc<TAtlasCommand, Boolean> read FOnExecuteShift write FOnExecuteShift;
    /// <summary>Jede Eingabe sofort, nach dem Filtern der Befehle (#1270).</summary>
    property OnPattern: TProc<string> read FOnPattern write FOnPattern;
    /// <summary>Eintrag der Zusatzgruppe ausgeführt; außer bei Copy erst nach dem Schließen (#1270).</summary>
    property OnGroupExecute: TProc<TAtlasCommand, TAtlasPaletteAction> read FOnGroupExecute write FOnGroupExecute;
    /// <summary>Palette geschlossen (Ausführen, Escape, Klick daneben, Freigeben); einmal.</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
    property Group: TAtlasPaletteGroup read FGroup;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
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
  FGroup := TAtlasPaletteGroup.None;
  Refilter;
end;

destructor TAtlasPaletteWindow.Destroy;
begin
  NotifyClosed;
  inherited;
end;

procedure TAtlasPaletteWindow.NotifyClosed;
var
  mHandler: TProc;
begin
  if FClosedSent then
    Exit;
  FClosedSent := True;
  mHandler := FOnClosed;
  FOnClosed := nil;
  FOnPattern := nil;
  if Assigned(mHandler) then
    mHandler();
end;

procedure TAtlasPaletteWindow.PatternChanged;
begin
  Refilter;
  if Assigned(FOnPattern) and not FExecuting then
    FOnPattern(FPattern);
  if Assigned(FOnQuery) then
  begin
    FQueryTimer.Enabled := False;
    if FQueryTimer.Interval = 0 then
      QueryTick(FQueryTimer)
    else
      // Neu starten: erst nach einer Tipppause fragen.
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

procedure TAtlasPaletteWindow.SetKeepOrder(AValue: Boolean);
begin
  FKeepOrder := AValue;
  Refilter;
end;

procedure TAtlasPaletteWindow.SetPresorted(AValue: Boolean);
begin
  FPresorted := AValue;
  Refilter;
end;

function TAtlasPaletteWindow.GetQueryDelay: Integer;
begin
  Result := Integer(FQueryTimer.Interval);
end;

procedure TAtlasPaletteWindow.SetQueryDelay(AValue: Integer);
begin
  FQueryTimer.Interval := Cardinal(Max(0, AValue));
end;

function TAtlasPaletteWindow.HighlightPattern: string;
begin
  Result := FPattern;
  if Assigned(FOnHighlight) then
    Result := FOnHighlight(FPattern);
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

procedure TAtlasPaletteWindow.ShowAt(const APoint: TPoint; AWidth: Integer);
var
  Area: TRect;
  Height_, Left_, Top_: Integer;
begin
  Area := Screen.MonitorFromPoint(APoint).WorkareaRect;
  Height_ := InputHeight + VisibleRows * RowHeight + ScaleValue(8);
  Left_ := Max(Area.Left, Min(APoint.X, Area.Right - AWidth));
  Top_ := APoint.Y;
  if Top_ + Height_ > Area.Bottom then
    Top_ := Max(Area.Top, Area.Bottom - Height_);
  SetBounds(Left_, Top_, AWidth, Height_);
  // Leere Eingabe: der aktuelle Eintrag ist gewählt.
  Refilter;
  Show;
  SetFocus;
end;

procedure TAtlasPaletteWindow.SetCommands(const ACommands: TArray<TAtlasCommand>);
begin
  FCommands := ACommands;
  Refilter;
end;

function TAtlasPaletteWindow.Rows: TAtlasPaletteRows;
begin
  Result := TAtlasPaletteRows.Create(Length(FOrder), FGroup);
end;

function TAtlasPaletteWindow.RowCount: Integer;
begin
  Result := Rows.Count;
end;

function TAtlasPaletteWindow.RowKind(ARow: Integer; out AIndex: Integer): TAtlasPaletteRowKind;
begin
  Result := Rows.Kind(ARow, AIndex);
end;

procedure TAtlasPaletteWindow.Refilter;
var
  Index: Integer;
begin
  if FPresorted then
  begin
    SetLength(FOrder, Length(FCommands));
    for Index := 0 to High(FCommands) do
      FOrder[Index] := Index;
  end
  else
    FOrder := TAtlasCommandPalette.Order(FCommands, FPattern, FHistory, FKeepOrder);
  FSelected := 0;
  FTop := 0;
  SelectFirst;
  if (FPattern = '') and (FInitialId <> '') then
    for Index := 0 to High(FOrder) do
      if FCommands[FOrder[Index]].Id = FInitialId then
      begin
        Select(Index);
        Break;
      end;
  Invalidate;
end;

procedure TAtlasPaletteWindow.SetGroup(const AGroup: TAtlasPaletteGroup);
var
  mOnCommand: Boolean;
begin
  // Die Befehle stehen vor der Gruppe: Eine Auswahl auf einem Befehl bleibt gültig.
  mOnCommand := FSelected < Length(FOrder);
  FGroup := AGroup;
  if not mOnCommand then
  begin
    FTop := 0;
    SelectFirst;
  end;
  Invalidate;
end;

procedure TAtlasPaletteWindow.SelectFirst;
var
  mRow: Integer;
begin
  mRow := Rows.First;
  if mRow >= 0 then
    Select(mRow)
  else
    FSelected := 0;
end;

procedure TAtlasPaletteWindow.Select(AIndex: Integer);
begin
  if RowCount = 0 then
    Exit;
  FSelected := EnsureRange(AIndex, 0, RowCount - 1);
  if FSelected < FTop then
    FTop := FSelected
  else if FSelected >= FTop + VisibleRows then
    FTop := FSelected - VisibleRows + 1;
  Invalidate;
end;

procedure TAtlasPaletteWindow.Step(ADelta: Integer);
begin
  if RowCount > 0 then
    Select(Rows.Step(FSelected, ADelta));
end;

procedure TAtlasPaletteWindow.ExecuteItem(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mHandler: TProc<TAtlasCommand, TAtlasPaletteAction>;
begin
  mHandler := FOnGroupExecute;
  if not Assigned(mHandler) then
    Exit;
  // Kennung kopieren: Die Palette bleibt offen.
  if AAction = TAtlasPaletteAction.Copy then
  begin
    mHandler(AItem, AAction);
    Exit;
  end;
  FExecuting := True;
  NotifyClosed;
  Close;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
    procedure
    begin
      mHandler(AItem, AAction);
    end);
  Release;
end;

procedure TAtlasPaletteWindow.Execute;
var
  Command: TAtlasCommand;
  Handler: TProc<TAtlasCommand>;
  ShiftHandler: TProc<TAtlasCommand, Boolean>;
  Shifted: Boolean;
  mIndex: Integer;
begin
  if (RowCount = 0) or FExecuting then
    Exit;
  case RowKind(FSelected, mIndex) of
    TAtlasPaletteRowKind.Command:
      Command := FCommands[FOrder[mIndex]];
    TAtlasPaletteRowKind.Item:
      begin
        ExecuteItem(FGroup.Items[mIndex], TAtlasPaletteRows.ActionOf(FCtrlExecuted, FShiftExecuted));
        Exit;
      end;
  else
    Exit;
  end;
  FExecuting := True;
  Handler := FOnExecute;
  ShiftHandler := FOnExecuteShift;
  Shifted := FShiftExecuted;
  NotifyClosed;
  Close;
  if Assigned(ShiftHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
      procedure
      begin
        ShiftHandler(Command, Shifted);
      end);
    Release;
    Exit;
  end;
  // Erst nach dem Schließen ausführen: Der Befehl öffnet evtl. selbst einen Dialog.
  if Assigned(Handler) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
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
    NotifyClosed;
    Close;
    Release;
  end;
end;

procedure TAtlasPaletteWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  mIndex: Integer;
begin
  case Key of
    VK_ESCAPE:
      FormDeactivate(Self);
    VK_RETURN:
      begin
        FShiftExecuted := ssShift in Shift;
        FCtrlExecuted := ssCtrl in Shift;
        Execute;
      end;
    VK_UP:
      Step(-1);
    VK_DOWN:
      Step(1);
    VK_PRIOR:
      Step(-VisibleRows);
    VK_NEXT:
      Step(VisibleRows);
    Ord('C'):
      begin
        // Strg+C auf einem Eintrag der Gruppe: Kennung kopieren (#1270); sonst wie bisher nichts.
        if not (ssCtrl in Shift) or (RowCount = 0) or (RowKind(FSelected, mIndex) <> TAtlasPaletteRowKind.Item) then
          Exit;
        ExecuteItem(FGroup.Items[mIndex], TAtlasPaletteAction.Copy);
      end;
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
  if Rows.Selectable(FTop + Row) then
  begin
    Select(FTop + Row);
    FShiftExecuted := False;
    FCtrlExecuted := False;
    Execute;
  end;
end;

function TAtlasPaletteWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTop := EnsureRange(FTop - Sign(WheelDelta) * 3, 0, Max(0, RowCount - VisibleRows));
  Invalidate;
  Result := True;
end;

procedure TAtlasPaletteWindow.DrawHighlighted(const AText, AHighlight: string; const ARect: TRect);
var
  Marks: TArray<Boolean>;
  Position, Index, Run, X: Integer;
  Part: TRect;
  Chunk: string;
begin
  SetLength(Marks, Length(AText) + 1);
  for Position in TAtlasItemPresentation.Highlights(AHighlight, AText) do
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

procedure TAtlasPaletteWindow.DrawCommand(const ACommand: TAtlasCommand; const ARow: TRect; ASelected: Boolean;
  const AHighlight: string);
var
  Row, Part: TRect;
  ShortCutWidth, CaptionWidth, mBadgeWidth: Integer;
begin
  Row := ARow;
  if ASelected then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(Row);
  end;
  Canvas.Brush.Style := bsClear;
  InflateRect(Row, -ScaleValue(8), 0);
  ShortCutWidth := 0;
  if ACommand.ShortCut <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    ShortCutWidth := Canvas.TextWidth(ACommand.ShortCut);
    Part := Rect(Row.Right - ShortCutWidth, Row.Top, Row.Right, Row.Bottom);
    DrawText(Canvas.Handle, PChar(ACommand.ShortCut), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Inc(ShortCutWidth, ScaleValue(16));
  end;
  // Abzeichen (Zustand eines Issues, #1270) rechts, vor dem Tastenkürzel.
  if ACommand.Badge <> '' then
  begin
    Canvas.Font.Size := Font.Size - 1;
    mBadgeWidth := Canvas.TextWidth(ACommand.Badge) + ScaleValue(12);
    Part := Rect(Row.Right - ShortCutWidth - mBadgeWidth, Row.Top + ScaleValue(4), Row.Right - ShortCutWidth,
      Row.Bottom - ScaleValue(4));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Pen.Color := ToColor(FColors.Muted);
    Canvas.RoundRect(Part.Left, Part.Top, Part.Right, Part.Bottom, ScaleValue(8), ScaleValue(8));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(ACommand.Badge), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_CENTER or
      DT_NOPREFIX);
    Canvas.Font.Size := Font.Size;
    Inc(ShortCutWidth, mBadgeWidth + ScaleValue(10));
  end;
  CaptionWidth := Min(Canvas.TextWidth(ACommand.Caption) + ScaleValue(4), Row.Width - ShortCutWidth);
  DrawHighlighted(ACommand.Caption, AHighlight, Rect(Row.Left, Row.Top, Row.Left + CaptionWidth, Row.Bottom));
  if ACommand.Path <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    Part := Rect(Row.Left + CaptionWidth + ScaleValue(10), Row.Top, Row.Right - ShortCutWidth, Row.Bottom);
    DrawText(Canvas.Handle, PChar(ACommand.Path), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteWindow.DrawRow(ARow: Integer);
var
  Row: TRect;
  mIndex: Integer;
begin
  Row := RowRect(ARow);
  case RowKind(FTop + ARow, mIndex) of
    TAtlasPaletteRowKind.Command:
      DrawCommand(FCommands[FOrder[mIndex]], Row, FTop + ARow = FSelected, HighlightPattern);
    TAtlasPaletteRowKind.Item:
      DrawCommand(FGroup.Items[mIndex], Row, FTop + ARow = FSelected, FGroup.Highlight);
    TAtlasPaletteRowKind.Header:
      begin
        // Überschrift der Gruppe mit Trennlinie darüber.
        Canvas.Pen.Color := ToColor(FColors.Gutter);
        Canvas.MoveTo(Row.Left, Row.Top);
        Canvas.LineTo(Row.Right, Row.Top);
        InflateRect(Row, -ScaleValue(8), 0);
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Style := [fsBold];
        Canvas.Font.Color := ToColor(FColors.Muted);
        DrawText(Canvas.Handle, PChar(FGroup.Title), -1, Row, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
        Canvas.Font.Style := [];
        Canvas.Brush.Style := bsSolid;
      end;
    TAtlasPaletteRowKind.Status:
      begin
        InflateRect(Row, -ScaleValue(8), 0);
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Style := [fsItalic];
        Canvas.Font.Color := ToColor(FColors.Muted);
        DrawText(Canvas.Handle, PChar(FGroup.Status), -1, Row, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
          DT_END_ELLIPSIS);
        Canvas.Font.Style := [];
        Canvas.Brush.Style := bsSolid;
      end;
  end;
end;

procedure TAtlasPaletteWindow.Paint;
var
  Input: TRect;
  Row: Integer;
  mText: string;
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
    mText := FPrompt;
  end
  else
  begin
    Canvas.Font.Color := ToColor(FColors.Text);
    mText := FPattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, Input, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  for Row := 0 to VisibleRows - 1 do
    if FTop + Row < RowCount then
      DrawRow(Row);
  // Rahmen des Fensters.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.