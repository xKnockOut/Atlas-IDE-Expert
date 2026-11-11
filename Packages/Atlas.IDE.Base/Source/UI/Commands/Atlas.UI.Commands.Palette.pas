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
// Mit RowHints zeigt ein Befehl mit Description diese als Hinweis über
// seiner Zeile (volle Signatur gekürzter Überladungen, #1784).

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
  /// <summary>Zeichnen der Palette: Maße, Eingabefeld, Zeilen mit Hervorhebung, Abzeichen, Überschrift und Status
  /// der Zusatzgruppe.</summary>
  TAtlasPaletteDrawing = class(TForm)
  protected const
    cVisibleRows = 12;
  protected
    FColors: TAtlasColors;
    function RowHeight: Integer;
    function InputHeight: Integer;
    function RowRect(ARow: Integer): TRect;
    /// <summary>Eingabefeld mit Akzentrahmen: APattern mit Schreibmarke, leer APrompt.</summary>
    procedure DrawInput(const APattern, APrompt: string);
    procedure DrawCommand(const ACommand: TAtlasCommand; const ARow: TRect; ASelected: Boolean;
      const AHighlight: string);
    procedure DrawHighlighted(const AText, AHighlight: string; const ARect: TRect);
    /// <summary>Überschrift der Gruppe mit Trennlinie darüber.</summary>
    procedure DrawHeader(const ARow: TRect; const ATitle: string);
    /// <summary>Statuszeile der Gruppe, kursiv und gedimmt.</summary>
    procedure DrawStatus(const ARow: TRect; const AStatus: string);
    procedure CreateParams(var Params: TCreateParams); override;
  public
    /// <summary>Oben mittig über AArea (Editor bzw. Hauptfenster).</summary>
    procedure ShowOver(const AArea: TRect);
  end;

  /// <summary>Ereignisse und Schließen der Palette: einmal OnClosed, Ausführen erst nach dem Schließen.</summary>
  TAtlasPaletteEvents = class(TAtlasPaletteDrawing)
  protected
    FOnExecute: TProc<TAtlasCommand>;
    FExecuting: Boolean;
    FOnQuery: TFunc<string, TArray<TAtlasCommand>>;
    FQueryTimer: TTimer;
    FPrompt: string;
    FOnHighlight: TFunc<string, string>;
    FInitialId: string;
    FShiftExecuted: Boolean;
    FCtrlExecuted: Boolean;
    FOnExecuteShift: TProc<TAtlasCommand, Boolean>;
    FOnPattern: TProc<string>;
    FOnGroupExecute: TProc<TAtlasCommand, TAtlasPaletteAction>;
    FOnClosed: TProc;
    FClosedSent: Boolean;
    procedure NotifyClosed;
    procedure FormDeactivate(Sender: TObject);
    function GetQueryDelay: Integer;
    procedure SetQueryDelay(AValue: Integer);
    /// <summary>Hervorzuhebender Text zur Eingabe APattern (OnHighlight, sonst APattern).</summary>
    function HighlightOf(const APattern: string): string;
  public
    destructor Destroy; override;
    /// <summary>Nach dem Schließen; das Fenster gibt sich danach selbst frei.</summary>
    property OnExecute: TProc<TAtlasCommand> read FOnExecute write FOnExecute;
    /// <summary>Einträge zur Eingabe neu holen (z. B. beim Server); läuft im Hauptthread.</summary>
    property OnQuery: TFunc<string, TArray<TAtlasCommand>> read FOnQuery write FOnQuery;
    /// <summary>Zeichen im leeren Eingabefeld, Standard "&gt;".</summary>
    property Prompt: string read FPrompt write FPrompt;
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
  end;

  TAtlasPaletteWindow = class(TAtlasPaletteEvents)
  private
    FCommands: TArray<TAtlasCommand>;
    FHistory: TAtlasCommandHistory;
    FPattern: string;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FKeepOrder: Boolean;
    FPresorted: Boolean;
    FGroup: TAtlasPaletteGroup;
    FRowHints: Boolean;
    procedure PatternChanged;
    procedure QueryTick(Sender: TObject);
    procedure Refilter;
    procedure Select(AIndex: Integer);
    /// <summary>Um ADelta weiter; Überschrift und Status werden übersprungen.</summary>
    procedure Step(ADelta: Integer);
    function Rows: TAtlasPaletteRows;
    procedure SelectFirst;
    procedure Execute;
    procedure ExecuteItem(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure DrawRow(ARow: Integer);
    procedure SetKeepOrder(AValue: Boolean);
    procedure SetPresorted(AValue: Boolean);
    procedure SetRowHints(AValue: Boolean);
    procedure CMHintShow(var Message: TCMHintShow); message CM_HINTSHOW;
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>AHistory gehört weiter dem Aufrufer.</summary>
    constructor CreatePalette(AOwner: TComponent; const ACommands: TArray<TAtlasCommand>;
      AHistory: TAtlasCommandHistory; const AColors: TAtlasColors);
    /// <summary>Zusatzgruppe unter den Befehlen zeigen bzw. ersetzen (#1270); TAtlasPaletteGroup.None entfernt sie.
    /// Steht die Auswahl auf einem Befehl, bleibt sie dort; sonst der erste Eintrag.</summary>
    procedure SetGroup(const AGroup: TAtlasPaletteGroup);
    /// <summary>Zeilen insgesamt (Befehle und Gruppe).</summary>
    function RowCount: Integer;
    /// <summary>Art der Zeile ARow; AIndex: Befehl in der Liste der Treffer bzw. Eintrag der Gruppe.</summary>
    function RowKind(ARow: Integer; out AIndex: Integer): TAtlasPaletteRowKind;
    /// <summary>Linke obere Ecke bei APoint (Bildschirm), AWidth breit; bleibt im Arbeitsbereich.</summary>
    procedure ShowAt(const APoint: TPoint; AWidth: Integer);
    /// <summary>Einträge ersetzen (etwa die erste Liste, wenn OnQuery das Fenster braucht).</summary>
    procedure SetCommands(const ACommands: TArray<TAtlasCommand>);
    property Pattern: string read FPattern;
    /// <summary>Reihenfolge der Einträge beibehalten statt alphabetisch (Code-Aktionen, #399); vor ShowOver
    /// setzen.</summary>
    property KeepOrder: Boolean read FKeepOrder write SetKeepOrder;
    /// <summary>Einträge in der Reihenfolge von OnQuery bzw. ACommands zeigen, ohne zu filtern (#503).</summary>
    property Presorted: Boolean read FPresorted write SetPresorted;
    /// <summary>Description eines Befehls als Hinweis über seiner Zeile (#1784); Vorgabe aus.</summary>
    property RowHints: Boolean read FRowHints write SetRowHints;
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

destructor TAtlasPaletteEvents.Destroy;
begin
  NotifyClosed;
  inherited;
end;

procedure TAtlasPaletteEvents.NotifyClosed;
var
  mHandler: TProc;
begin
  if FClosedSent then
  begin
    Exit;
  end;
  FClosedSent := True;
  mHandler := FOnClosed;
  FOnClosed := nil;
  FOnPattern := nil;
  if Assigned(mHandler) then
  begin
    mHandler();
  end;
end;

procedure TAtlasPaletteWindow.PatternChanged;
begin
  Refilter;
  if Assigned(FOnPattern) and not FExecuting then
  begin
    FOnPattern(FPattern);
  end;
  if Assigned(FOnQuery) then
  begin
    FQueryTimer.Enabled := False;
    if FQueryTimer.Interval = 0 then
    begin
      QueryTick(FQueryTimer);
    end
    else
    begin
      // Neu starten: erst nach einer Tipppause fragen.
      FQueryTimer.Enabled := True;
    end;
  end;
end;

procedure TAtlasPaletteWindow.QueryTick(Sender: TObject);
begin
  FQueryTimer.Enabled := False;
  if not Assigned(FOnQuery) or FExecuting then
  begin
    Exit;
  end;
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

function TAtlasPaletteEvents.GetQueryDelay: Integer;
begin
  Result := Integer(FQueryTimer.Interval);
end;

procedure TAtlasPaletteEvents.SetQueryDelay(AValue: Integer);
begin
  FQueryTimer.Interval := Cardinal(Max(0, AValue));
end;

function TAtlasPaletteEvents.HighlightOf(const APattern: string): string;
begin
  Result := APattern;
  if Assigned(FOnHighlight) then
  begin
    Result := FOnHighlight(APattern);
  end;
end;

procedure TAtlasPaletteDrawing.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

function TAtlasPaletteDrawing.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(10);
end;

function TAtlasPaletteDrawing.InputHeight: Integer;
begin
  Result := RowHeight + ScaleValue(10);
end;

function TAtlasPaletteDrawing.RowRect(ARow: Integer): TRect;
begin
  Result := Rect(ScaleValue(6), InputHeight + ARow * RowHeight, ClientWidth - ScaleValue(6),
    InputHeight + (ARow + 1) * RowHeight);
end;

procedure TAtlasPaletteDrawing.ShowOver(const AArea: TRect);
var
  mWidth_: Integer;
begin
  mWidth_ := Min(ScaleValue(640), AArea.Width - ScaleValue(40));
  SetBounds(AArea.Left + (AArea.Width - mWidth_) div 2, AArea.Top + ScaleValue(60), mWidth_,
    InputHeight + cVisibleRows * RowHeight + ScaleValue(8));
  Show;
  SetFocus;
end;

procedure TAtlasPaletteWindow.ShowAt(const APoint: TPoint; AWidth: Integer);
var
  mArea: TRect;
  mHeight_, mLeft_, mTop_: Integer;
begin
  mArea := Screen.MonitorFromPoint(APoint).WorkareaRect;
  mHeight_ := InputHeight + cVisibleRows * RowHeight + ScaleValue(8);
  mLeft_ := Max(mArea.Left, Min(APoint.X, mArea.Right - AWidth));
  mTop_ := APoint.Y;
  if mTop_ + mHeight_ > mArea.Bottom then
  begin
    mTop_ := Max(mArea.Top, mArea.Bottom - mHeight_);
  end;
  SetBounds(mLeft_, mTop_, AWidth, mHeight_);
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

procedure TAtlasPaletteWindow.SetRowHints(AValue: Boolean);
begin
  FRowHints := AValue;
  ShowHint := AValue;
end;

procedure TAtlasPaletteWindow.CMHintShow(var Message: TCMHintShow);
var
  mRow: Integer;
  mText: string;
begin
  mText := '';
  mRow := -1;
  if FRowHints and (Message.HintInfo.CursorPos.Y >= InputHeight) then
  begin
    mRow := (Message.HintInfo.CursorPos.Y - InputHeight) div RowHeight;
    if (FTop + mRow >= 0) and (FTop + mRow < Length(FOrder)) then
    begin
      mText := FCommands[FOrder[FTop + mRow]].Description;
    end;
  end;
  // Ohne Beschreibung kein Hinweis; die Fläche der Zeile begrenzt ihn, damit die nächste Zeile ihren eigenen zeigt.
  if mText = '' then
  begin
    Message.Result := 1;
    Exit;
  end;
  Message.HintInfo.HintStr := mText;
  Message.HintInfo.CursorRect := RowRect(mRow);
  Message.Result := 0;
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
  mIndex: Integer;
begin
  if FPresorted then
  begin
    SetLength(FOrder, Length(FCommands));
    for mIndex := 0 to High(FCommands) do
    begin
      FOrder[mIndex] := mIndex;
    end;
  end
  else
  begin
    FOrder := TAtlasCommandPalette.Order(FCommands, FPattern, FHistory, FKeepOrder);
  end;
  FSelected := 0;
  FTop := 0;
  SelectFirst;
  if (FPattern = '') and (FInitialId <> '') then
  begin
    for mIndex := 0 to High(FOrder) do
    begin
      if FCommands[FOrder[mIndex]].Id = FInitialId then
      begin
        Select(mIndex);
        Break;
      end;
    end;
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
  begin
    Select(mRow);
  end
  else
  begin
    FSelected := 0;
  end;
end;

procedure TAtlasPaletteWindow.Select(AIndex: Integer);
begin
  if RowCount = 0 then
  begin
    Exit;
  end;
  FSelected := EnsureRange(AIndex, 0, RowCount - 1);
  if FSelected < FTop then
  begin
    FTop := FSelected;
  end
  else if FSelected >= FTop + cVisibleRows then
  begin
    FTop := FSelected - cVisibleRows + 1;
  end;
  Invalidate;
end;

procedure TAtlasPaletteWindow.Step(ADelta: Integer);
begin
  if RowCount > 0 then
  begin
    Select(Rows.Step(FSelected, ADelta));
  end;
end;

procedure TAtlasPaletteWindow.ExecuteItem(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mHandler: TProc<TAtlasCommand, TAtlasPaletteAction>;
begin
  mHandler := FOnGroupExecute;
  if not Assigned(mHandler) then
  begin
    Exit;
  end;
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
  mCommand: TAtlasCommand;
  mHandler: TProc<TAtlasCommand>;
  mShiftHandler: TProc<TAtlasCommand, Boolean>;
  mShifted: Boolean;
  mIndex: Integer;
begin
  if (RowCount = 0) or FExecuting then
  begin
    Exit;
  end;
  case RowKind(FSelected, mIndex) of
    TAtlasPaletteRowKind.Command:
      mCommand := FCommands[FOrder[mIndex]];
    TAtlasPaletteRowKind.Item:
      begin
        ExecuteItem(FGroup.Items[mIndex], TAtlasPaletteRows.ActionOf(FCtrlExecuted, FShiftExecuted));
        Exit;
      end;
  else
    Exit;
  end;
  FExecuting := True;
  mHandler := FOnExecute;
  mShiftHandler := FOnExecuteShift;
  mShifted := FShiftExecuted;
  NotifyClosed;
  Close;
  if Assigned(mShiftHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
      procedure
      begin
        mShiftHandler(mCommand, mShifted);
      end);
    Release;
    Exit;
  end;
  // Erst nach dem Schließen ausführen: Der Befehl öffnet evtl. selbst einen Dialog.
  if Assigned(mHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Palette,
      procedure
      begin
        mHandler(mCommand);
      end);
  end;
  Release;
end;

procedure TAtlasPaletteEvents.FormDeactivate(Sender: TObject);
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
      Step(-cVisibleRows);
    VK_NEXT:
      Step(cVisibleRows);
    Ord('C'):
      begin
        // Strg+C auf einem Eintrag der Gruppe: Kennung kopieren (#1270); sonst wie bisher nichts.
        if not (ssCtrl in Shift) or (RowCount = 0) or (RowKind(FSelected, mIndex) <> TAtlasPaletteRowKind.Item) then
        begin
          Exit;
        end;
        ExecuteItem(FGroup.Items[mIndex], TAtlasPaletteAction.Copy);
      end;
    VK_BACK:
      if FPattern <> '' then
      begin
        if ssCtrl in Shift then
        begin
          FPattern := '';
        end
        else
        begin
          Delete(FPattern, Length(FPattern), 1);
        end;
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
  mRow: Integer;
begin
  inherited;
  if Y < InputHeight then
  begin
    Exit;
  end;
  mRow := (Y - InputHeight) div RowHeight;
  if Rows.Selectable(FTop + mRow) then
  begin
    Select(FTop + mRow);
    FShiftExecuted := False;
    FCtrlExecuted := False;
    Execute;
  end;
end;

function TAtlasPaletteWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTop := EnsureRange(FTop - Sign(WheelDelta) * 3, 0, Max(0, RowCount - cVisibleRows));
  Invalidate;
  Result := True;
end;

procedure TAtlasPaletteDrawing.DrawHighlighted(const AText, AHighlight: string; const ARect: TRect);
var
  mMarks: TArray<Boolean>;
  mPosition, mIndex, mRun, X: Integer;
  mPart: TRect;
  mChunk: string;
begin
  SetLength(mMarks, Length(AText) + 1);
  for mPosition in TAtlasItemPresentation.Highlights(AHighlight, AText) do
  begin
    if (mPosition >= 1) and (mPosition <= Length(AText)) then
    begin
      mMarks[mPosition] := True;
    end;
  end;
  X := ARect.Left;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mRun := mIndex;
    while (mRun < Length(AText)) and (mMarks[mRun + 1] = mMarks[mIndex]) do
    begin
      Inc(mRun);
    end;
    mChunk := Copy(AText, mIndex, mRun - mIndex + 1);
    if mMarks[mIndex] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(FColors.Text);
    end;
    mPart := Rect(X, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(mChunk), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(mChunk));
    mIndex := mRun + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasPaletteDrawing.DrawCommand(const ACommand: TAtlasCommand; const ARow: TRect; ASelected: Boolean;
  const AHighlight: string);
var
  mRow, mPart: TRect;
  mShortCutWidth, mCaptionWidth, mBadgeWidth: Integer;
begin
  mRow := ARow;
  if ASelected then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(mRow);
  end;
  Canvas.Brush.Style := bsClear;
  InflateRect(mRow, -ScaleValue(8), 0);
  mShortCutWidth := 0;
  if ACommand.ShortCut <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    mShortCutWidth := Canvas.TextWidth(ACommand.ShortCut);
    mPart := Rect(mRow.Right - mShortCutWidth, mRow.Top, mRow.Right, mRow.Bottom);
    DrawText(Canvas.Handle, PChar(ACommand.ShortCut), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Inc(mShortCutWidth, ScaleValue(16));
  end;
  // Abzeichen (Zustand eines Issues, #1270) rechts, vor dem Tastenkürzel.
  if ACommand.Badge <> '' then
  begin
    Canvas.Font.Size := Font.Size - 1;
    mBadgeWidth := Canvas.TextWidth(ACommand.Badge) + ScaleValue(12);
    mPart := Rect(mRow.Right - mShortCutWidth - mBadgeWidth, mRow.Top + ScaleValue(4), mRow.Right - mShortCutWidth,
      mRow.Bottom - ScaleValue(4));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Pen.Color := ToColor(FColors.Muted);
    Canvas.RoundRect(mPart.Left, mPart.Top, mPart.Right, mPart.Bottom, ScaleValue(8), ScaleValue(8));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(ACommand.Badge), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_CENTER or
      DT_NOPREFIX);
    Canvas.Font.Size := Font.Size;
    Inc(mShortCutWidth, mBadgeWidth + ScaleValue(10));
  end;
  mCaptionWidth := Min(Canvas.TextWidth(ACommand.Caption) + ScaleValue(4), mRow.Width - mShortCutWidth);
  DrawHighlighted(ACommand.Caption, AHighlight, Rect(mRow.Left, mRow.Top, mRow.Left + mCaptionWidth, mRow.Bottom));
  if ACommand.Path <> '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    mPart := Rect(mRow.Left + mCaptionWidth + ScaleValue(10), mRow.Top, mRow.Right - mShortCutWidth, mRow.Bottom);
    DrawText(Canvas.Handle, PChar(ACommand.Path), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteWindow.DrawRow(ARow: Integer);
var
  mRow: TRect;
  mIndex: Integer;
begin
  mRow := RowRect(ARow);
  case RowKind(FTop + ARow, mIndex) of
    TAtlasPaletteRowKind.Command:
      DrawCommand(FCommands[FOrder[mIndex]], mRow, FTop + ARow = FSelected, HighlightOf(FPattern));
    TAtlasPaletteRowKind.Item:
      DrawCommand(FGroup.Items[mIndex], mRow, FTop + ARow = FSelected, FGroup.Highlight);
    TAtlasPaletteRowKind.Header:
      DrawHeader(mRow, FGroup.Title);
    TAtlasPaletteRowKind.Status:
      DrawStatus(mRow, FGroup.Status);
  end;
end;

procedure TAtlasPaletteDrawing.DrawHeader(const ARow: TRect; const ATitle: string);
var
  mRow: TRect;
begin
  mRow := ARow;
  Canvas.Pen.Color := ToColor(FColors.Gutter);
  Canvas.MoveTo(mRow.Left, mRow.Top);
  Canvas.LineTo(mRow.Right, mRow.Top);
  InflateRect(mRow, -ScaleValue(8), 0);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Muted);
  DrawText(Canvas.Handle, PChar(ATitle), -1, mRow, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteDrawing.DrawStatus(const ARow: TRect; const AStatus: string);
var
  mRow: TRect;
begin
  mRow := ARow;
  InflateRect(mRow, -ScaleValue(8), 0);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsItalic];
  Canvas.Font.Color := ToColor(FColors.Muted);
  DrawText(Canvas.Handle, PChar(AStatus), -1, mRow, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteDrawing.DrawInput(const APattern, APrompt: string);
var
  mInput: TRect;
  mText: string;
begin
  // Eingabefeld mit Akzentrahmen.
  mInput := Rect(ScaleValue(6), ScaleValue(6), ClientWidth - ScaleValue(6), InputHeight - ScaleValue(4));
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.Rectangle(mInput);
  InflateRect(mInput, -ScaleValue(8), 0);
  Canvas.Brush.Style := bsClear;
  if APattern = '' then
  begin
    Canvas.Font.Color := ToColor(FColors.Muted);
    mText := APrompt;
  end
  else
  begin
    Canvas.Font.Color := ToColor(FColors.Text);
    mText := APattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, mInput, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasPaletteWindow.Paint;
var
  mRow: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  DrawInput(FPattern, FPrompt);
  for mRow := 0 to cVisibleRows - 1 do
  begin
    if FTop + mRow < RowCount then
    begin
      DrawRow(mRow);
    end;
  end;
  // Rahmen des Fensters.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.