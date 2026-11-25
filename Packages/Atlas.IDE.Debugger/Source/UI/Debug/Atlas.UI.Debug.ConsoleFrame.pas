unit Atlas.UI.Debug.ConsoleFrame;

// Inhalt des Seitenfensters „Konsolenausgabe“ (#581), reine VCL: oben der
// Zustand (läuft, Debugger hängt sich an, beendet mit Exit-Code) mit
// „Beenden“ und „Leeren“, darunter die virtuelle Liste der Zeilen aus dem
// TAtlasConsoleBuffer der IDE-Schicht in fester Schrift (stderr rot,
// Eingaben blau, Hinweise grau; Farben aus TAtlasConsoleColors), unten das
// Eingabefeld mit „Senden“ (Enter) und „Eingabe beenden“ (Ende der Datei für
// Readln). Fundstellen wie „Datei.pas(12)“ sind unterstrichen; ein Klick darauf
// meldet OnOpen. Neue Zeilen rollen die Liste mit, solange die letzte Zeile zu
// sehen ist. Strg+C kopiert die gewählte Zeile, das Kontextmenü auch alles.
// Die Liste ist ein eigenes Steuerelement (TAtlasConsoleList). Virtuell wird
// sie erst in CreateWnd des Frames: SetStyle leert die Einträge per
// LB_RESETCONTENT und legt dafür ein Fenster an, das im Konstruktor ohne
// Parent fehlt (die IDE hängt den Frame erst nach dem Anlegen ein).
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Vcl.Controls.ListBox,
  Atlas.Core.Debug.ConsoleCapture;

type
  /// <summary>Virtuelle Liste der Zeilen in fester Schrift: Farben je Strom, Fundstellen unterstrichen, Klick auf
  /// eine Fundstelle meldet OnOpen, Strg+C kopiert die Zeile, Enter öffnet die Fundstelle.</summary>
  TAtlasConsoleList = class(TAtlasListBox)
  private
    FBuffer: TAtlasConsoleBuffer;
    FOnOpen: TProc<TAtlasConsoleLocation>;
    function RowCount: Integer;
    function TextLeft: Integer;
    function LocationAt(AX, AY: Integer; out ALocation: TAtlasConsoleLocation): Boolean;
    procedure UpdateItemHeight;
    function IsVirtual: Boolean;
    procedure Open(const ALocation: TAtlasConsoleLocation);
  protected
    procedure CreateWnd; override;
    procedure CMFontChanged(var AMessage: TMessage); message CM_FONTCHANGED;
    procedure DrawItem(AIndex: Integer; ARect: TRect; AState: TOwnerDrawState); override;
    procedure MouseMove(AShift: TShiftState; AX, AY: Integer); override;
    procedure MouseUp(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer); override;
    procedure KeyDown(var AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Gespeicherte und noch offene Zeile AIndex; False außerhalb.</summary>
    function RowAt(AIndex: Integer; out ALine: TAtlasConsoleLine): Boolean;
    /// <summary>Fundstelle der gewählten Zeile.</summary>
    function SelectedLocation(out ALocation: TAtlasConsoleLocation): Boolean;
    procedure SetBuffer(ABuffer: TAtlasConsoleBuffer);
    /// <summary>Zeilenzahl neu lesen und neu zeichnen; rollt mit, wenn die letzte Zeile zu sehen war.</summary>
    procedure Refill;
    procedure CopyLine;
    procedure CopyAll;
    procedure OpenSelected;
    property OnOpen: TProc<TAtlasConsoleLocation> read FOnOpen write FOnOpen;
  end;

  TAtlasDebugConsoleFrame = class(TFrame)
  private type
    /// <summary>Ereignisse an die IDE-Schicht.</summary>
    TEvents = record
      Send: TProc<string>;
      CloseInput: TProc;
      Stop: TProc;
      Clear: TProc;
    end;
  private
    FState: TLabel;
    FStop: TButton;
    FClear: TButton;
    FList: TAtlasConsoleList;
    FInput: TEdit;
    FSend: TButton;
    FEndInput: TButton;
    FMenu: TPopupMenu;
    FOpenItem: TMenuItem;
    FRunning: Boolean;
    FEvents: TEvents;
    procedure CreateStateBar;
    procedure CreateInputBar;
    procedure CreateList;
    procedure CreateMenu;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure UpdateButtons;
    function GetOnOpen: TProc<TAtlasConsoleLocation>;
    procedure SetOnOpen(const AValue: TProc<TAtlasConsoleLocation>);
    procedure InputKeyPress(Sender: TObject; var Key: Char);
    procedure SendClick(Sender: TObject);
    procedure EndInputClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure CopyLineClick(Sender: TObject);
    procedure CopyAllClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeilen der IDE-Schicht (sie gehört ihr; nil = leer).</summary>
    procedure SetBuffer(ABuffer: TAtlasConsoleBuffer);
    /// <summary>Zeilenzahl neu lesen und neu zeichnen; rollt mit, wenn die letzte Zeile zu sehen war.</summary>
    procedure Refill;
    /// <summary>Zustandszeile; ARunning gibt Eingabe und „Beenden“ frei.</summary>
    procedure SetState(const AText: string; ARunning: Boolean);
    /// <summary>Eingabefeld fokussieren, wenn das Fenster zu sehen ist.</summary>
    procedure FocusInput;
    property List: TAtlasConsoleList read FList;
    property OnSend: TProc<string> read FEvents.Send write FEvents.Send;
    property OnCloseInput: TProc read FEvents.CloseInput write FEvents.CloseInput;
    property OnStop: TProc read FEvents.Stop write FEvents.Stop;
    property OnClear: TProc read FEvents.Clear write FEvents.Clear;
    property OnOpen: TProc<TAtlasConsoleLocation> read GetOnOpen write SetOnOpen;
  end;

implementation

uses
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Plugin.Style.Color,
  Atlas.Vcl.Controls.Menus,
  Atlas.UI.Debug.Console.Strings;

{$R *.dfm}

const
  // Maße in logischen Pixeln (96 dpi).
  cBarHeight = 30;
  cButtonWidth = 90;
  cTextIndent = 4;
  cFontName = 'Consolas';
  cFontSize = 10;

{ TAtlasConsoleList }

constructor TAtlasConsoleList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Style erst in CreateWnd des Frames: SetStyle bräuchte hier schon ein Fenster.
  MultiSelect := False;
  Font.Name := cFontName;
  Font.Size := cFontSize;
end;

function TAtlasConsoleList.IsVirtual: Boolean;
begin
  Result := Style = lbVirtualOwnerDraw;
end;

procedure TAtlasConsoleList.CreateWnd;
begin
  inherited CreateWnd;
  // Count der virtuellen Liste braucht ein Fenster.
  Refill;
end;

procedure TAtlasConsoleList.CMFontChanged(var AMessage: TMessage);
begin
  inherited;
  UpdateItemHeight;
end;

procedure TAtlasConsoleList.UpdateItemHeight;
var
  mDC: HDC;
  mCanvas: TCanvas;
begin
  // Am Bildschirm messen, nicht am eigenen Fenster: Ohne Fenster fehlt es, und ItemHeight legt ein vorhandenes neu
  // an (in CreateWnd mitten im Anlegen).
  mDC := GetDC(0);
  mCanvas := TCanvas.Create;
  try
    mCanvas.Handle := mDC;
    mCanvas.Font := Font;
    ItemHeight := mCanvas.TextHeight('Wg') + 2;
  finally
    mCanvas.Handle := 0;
    mCanvas.Free;
    ReleaseDC(0, mDC);
  end;
end;

function TAtlasConsoleList.RowCount: Integer;
begin
  Result := 0;
  if FBuffer <> nil then
  begin
    Result := FBuffer.Count + Length(FBuffer.PendingLines);
  end;
end;

function TAtlasConsoleList.RowAt(AIndex: Integer; out ALine: TAtlasConsoleLine): Boolean;
var
  mPending: TArray<TAtlasConsoleLine>;
begin
  ALine := Default(TAtlasConsoleLine);
  Result := (FBuffer <> nil) and (AIndex >= 0);
  if not Result then
  begin
    Exit;
  end;
  if AIndex < FBuffer.Count then
  begin
    ALine := FBuffer.Line(AIndex);
    Exit;
  end;
  mPending := FBuffer.PendingLines;
  Result := AIndex - FBuffer.Count <= High(mPending);
  if Result then
  begin
    ALine := mPending[AIndex - FBuffer.Count];
  end;
end;

function TAtlasConsoleList.TextLeft: Integer;
begin
  Result := MulDiv(cTextIndent, CurrentPPI, 96);
end;

procedure TAtlasConsoleList.DrawItem(AIndex: Integer; ARect: TRect; AState: TOwnerDrawState);
var
  mLine: TAtlasConsoleLine;
  mStyle: TCustomStyleServices;
  mSelected: Boolean;
  mBackground, mDefault: TAtlasColor;
  mLocation: TAtlasConsoleLocation;
  mX, mY: Integer;
  mPrompt: string;

  function ColorOf(AStream: TAtlasConsoleStream): TColor;
  begin
    Result := TColor(mDefault);
    if not mSelected then
    begin
      Result := TColor(TAtlasConsoleColors.ForStream(AStream, mBackground, mDefault));
    end;
  end;

begin
  Canvas.Font := Font;
  // Farben des IDE-Themas (VCL-Stil), nicht die des Systems.
  mStyle := StyleServices(Self);
  mSelected := odSelected in AState;
  if mSelected then
  begin
    mBackground := TAtlasColor(ColorToRGB(mStyle.GetSystemColor(clHighlight)));
    mDefault := TAtlasColor(ColorToRGB(mStyle.GetSystemColor(clHighlightText)));
  end
  else
  begin
    mBackground := TAtlasColor(ColorToRGB(mStyle.GetSystemColor(Color)));
    mDefault := TAtlasColor(ColorToRGB(mStyle.GetSystemColor(Font.Color)));
  end;
  Canvas.Brush.Color := TColor(mBackground);
  Canvas.FillRect(ARect);
  if not RowAt(AIndex, mLine) then
  begin
    Exit;
  end;
  mX := ARect.Left + TextLeft;
  mY := ARect.Top + 1;
  Canvas.Brush.Style := bsClear;
  // Bei einer Eingabe steht die Frage des Programms in der Farbe der Ausgabe davor.
  mPrompt := Copy(mLine.Text, 1, mLine.PromptLength);
  if mPrompt <> '' then
  begin
    Canvas.Font.Color := ColorOf(TAtlasConsoleStream.Output);
    Canvas.TextOut(mX, mY, mPrompt);
    Inc(mX, Canvas.TextWidth(mPrompt));
  end;
  Canvas.Font.Color := ColorOf(mLine.Stream);
  Canvas.TextOut(mX, mY, Copy(mLine.Text, mLine.PromptLength + 1, MaxInt));
  if (mLine.Stream in [TAtlasConsoleStream.Output, TAtlasConsoleStream.Error]) and
    TAtlasConsoleLocations.Find(mLine.Text, mLocation) then
  begin
    // Fundstelle unterstreichen: Linie unter dem Text der Fundstelle.
    mX := ARect.Left + TextLeft + Canvas.TextWidth(Copy(mLine.Text, 1, mLocation.Start - 1));
    Canvas.Pen.Color := Canvas.Font.Color;
    Canvas.MoveTo(mX, ARect.Bottom - 2);
    Canvas.LineTo(mX + Canvas.TextWidth(Copy(mLine.Text, mLocation.Start, mLocation.Length)), ARect.Bottom - 2);
  end;
  Canvas.Brush.Style := bsSolid;
end;

function TAtlasConsoleList.LocationAt(AX, AY: Integer; out ALocation: TAtlasConsoleLocation): Boolean;
var
  mIndex, mLeft, mRight: Integer;
  mLine: TAtlasConsoleLine;
begin
  ALocation := Default(TAtlasConsoleLocation);
  mIndex := ItemAtPos(TPoint.Create(AX, AY), True);
  Result := RowAt(mIndex, mLine) and (mLine.Stream in [TAtlasConsoleStream.Output, TAtlasConsoleStream.Error]) and
    TAtlasConsoleLocations.Find(mLine.Text, ALocation);
  if not Result then
  begin
    Exit;
  end;
  Canvas.Font := Font;
  mLeft := TextLeft + Canvas.TextWidth(Copy(mLine.Text, 1, ALocation.Start - 1));
  mRight := mLeft + Canvas.TextWidth(Copy(mLine.Text, ALocation.Start, ALocation.Length));
  Result := (AX >= mLeft) and (AX < mRight);
end;

procedure TAtlasConsoleList.MouseMove(AShift: TShiftState; AX, AY: Integer);
var
  mLocation: TAtlasConsoleLocation;
begin
  inherited MouseMove(AShift, AX, AY);
  if LocationAt(AX, AY, mLocation) then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

procedure TAtlasConsoleList.MouseUp(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
var
  mLocation: TAtlasConsoleLocation;
begin
  inherited MouseUp(AButton, AShift, AX, AY);
  if (AButton = mbLeft) and (AShift * [ssShift, ssCtrl] = []) and LocationAt(AX, AY, mLocation) then
  begin
    Open(mLocation);
  end;
end;

procedure TAtlasConsoleList.KeyDown(var AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    CopyLine;
    AKey := 0;
  end
  else if AKey = VK_RETURN then
  begin
    OpenSelected;
    AKey := 0;
  end;
  inherited KeyDown(AKey, AShift);
end;

procedure TAtlasConsoleList.Open(const ALocation: TAtlasConsoleLocation);
begin
  if Assigned(FOnOpen) then
  begin
    FOnOpen(ALocation);
  end;
end;

function TAtlasConsoleList.SelectedLocation(out ALocation: TAtlasConsoleLocation): Boolean;
var
  mLine: TAtlasConsoleLine;
begin
  ALocation := Default(TAtlasConsoleLocation);
  Result := RowAt(ItemIndex, mLine) and TAtlasConsoleLocations.Find(mLine.Text, ALocation);
end;

procedure TAtlasConsoleList.OpenSelected;
var
  mLocation: TAtlasConsoleLocation;
begin
  if SelectedLocation(mLocation) then
  begin
    Open(mLocation);
  end;
end;

procedure TAtlasConsoleList.CopyLine;
var
  mLine: TAtlasConsoleLine;
begin
  if RowAt(ItemIndex, mLine) then
  begin
    Clipboard.AsText := mLine.Text;
  end;
end;

procedure TAtlasConsoleList.CopyAll;
begin
  if FBuffer <> nil then
  begin
    Clipboard.AsText := FBuffer.Text;
  end;
end;

procedure TAtlasConsoleList.SetBuffer(ABuffer: TAtlasConsoleBuffer);
begin
  FBuffer := ABuffer;
  Refill;
end;

procedure TAtlasConsoleList.Refill;
var
  mCount: Integer;
  mFollow: Boolean;
begin
  // Count der virtuellen Liste braucht ein Fenster (CreateWnd ruft erneut) und geht nur virtuell.
  if not HandleAllocated or not IsVirtual then
  begin
    Exit;
  end;
  mCount := RowCount;
  // Mitrollen, solange die letzte Zeile zu sehen ist (oder die Liste leer war).
  mFollow := (Count = 0) or (TopIndex + ClientHeight div ItemHeight >= Count - 1);
  if Count <> mCount then
  begin
    Count := mCount;
  end;
  if mFollow and (mCount > 0) then
  begin
    TopIndex := mCount - 1;
  end;
  Invalidate;
end;

{ TAtlasDebugConsoleFrame }

constructor TAtlasDebugConsoleFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  CreateStateBar;
  CreateInputBar;
  CreateMenu;
  CreateList;
  SetState(TAtlasConsoleStrings.Text(TAtlasConsoleTextId.StateIdle), False);
end;

procedure TAtlasDebugConsoleFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Erst jetzt hat der Parent der Liste ein Fenster (SetStyle leert per LB_RESETCONTENT).
  FList.Style := lbVirtualOwnerDraw;
end;

function TAtlasDebugConsoleFrame.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  Result.Width := MulDiv(cButtonWidth, CurrentPPI, 96);
  Result.OnClick := AClick;
end;

procedure TAtlasDebugConsoleFrame.CreateStateBar;
var
  mTop: TPanel;
begin
  mTop := TPanel.Create(Self);
  mTop.Top := 0;
  mTop.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mTop.Align := alTop;
  mTop.Parent := Self;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.ParentBackground := True;
  FClear := AddButton(mTop, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Clear), ClearClick);
  FStop := AddButton(mTop, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Stop), StopClick);
  FState := TLabel.Create(Self);
  FState.Parent := mTop;
  FState.Align := alClient;
  FState.AlignWithMargins := True;
  FState.Layout := tlCenter;
  FState.ShowAccelChar := False;
  FState.EllipsisPosition := epEndEllipsis;
end;

procedure TAtlasDebugConsoleFrame.CreateInputBar;
var
  mBottom: TPanel;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Top := MulDiv(cBarHeight * 10, CurrentPPI, 96);
  mBottom.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mBottom.Align := alBottom;
  mBottom.Parent := Self;
  mBottom.BevelOuter := bvNone;
  mBottom.ShowCaption := False;
  mBottom.ParentBackground := True;
  FEndInput := AddButton(mBottom, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.CloseInput), EndInputClick);
  FSend := AddButton(mBottom, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Send), SendClick);
  FInput := TEdit.Create(Self);
  FInput.Parent := mBottom;
  FInput.Align := alClient;
  FInput.AlignWithMargins := True;
  FInput.TextHint := TAtlasConsoleStrings.Text(TAtlasConsoleTextId.InputHint);
  FInput.OnKeyPress := InputKeyPress;
end;

procedure TAtlasDebugConsoleFrame.CreateMenu;
begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := TAtlasMenus.Add(FMenu, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.OpenLocation), OpenClick);
  FOpenItem.Default := True;
  TAtlasMenus.Add(FMenu, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Copy), CopyLineClick);
  TAtlasMenus.Add(FMenu, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.CopyAll), CopyAllClick);
  TAtlasMenus.Add(FMenu, TAtlasConsoleStrings.Text(TAtlasConsoleTextId.Clear), ClearClick);
end;

procedure TAtlasDebugConsoleFrame.InputKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    SendClick(Sender);
  end;
end;

procedure TAtlasDebugConsoleFrame.SendClick(Sender: TObject);
var
  mText: string;
begin
  if not FRunning or not Assigned(FEvents.Send) then
  begin
    Exit;
  end;
  mText := FInput.Text;
  FInput.Text := '';
  FEvents.Send(mText);
end;

procedure TAtlasDebugConsoleFrame.EndInputClick(Sender: TObject);
begin
  if FRunning and Assigned(FEvents.CloseInput) then
  begin
    FEvents.CloseInput();
  end;
end;

procedure TAtlasDebugConsoleFrame.StopClick(Sender: TObject);
begin
  if Assigned(FEvents.Stop) then
  begin
    FEvents.Stop();
  end;
end;

procedure TAtlasDebugConsoleFrame.ClearClick(Sender: TObject);
begin
  if Assigned(FEvents.Clear) then
  begin
    FEvents.Clear();
  end;
end;

procedure TAtlasDebugConsoleFrame.UpdateButtons;
begin
  FStop.Enabled := FRunning;
  FSend.Enabled := FRunning;
  FEndInput.Enabled := FRunning;
  FInput.Enabled := FRunning;
end;

procedure TAtlasDebugConsoleFrame.SetState(const AText: string; ARunning: Boolean);
begin
  FState.Caption := AText;
  FRunning := ARunning;
  UpdateButtons;
end;

procedure TAtlasDebugConsoleFrame.FocusInput;
begin
  if FRunning and FInput.CanFocus and Showing then
  begin
    FInput.SetFocus;
  end;
end;

procedure TAtlasDebugConsoleFrame.CreateList;
begin
  FList := TAtlasConsoleList.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.PopupMenu := FMenu;
end;

function TAtlasDebugConsoleFrame.GetOnOpen: TProc<TAtlasConsoleLocation>;
begin
  Result := FList.OnOpen;
end;

procedure TAtlasDebugConsoleFrame.SetOnOpen(const AValue: TProc<TAtlasConsoleLocation>);
begin
  FList.OnOpen := AValue;
end;

procedure TAtlasDebugConsoleFrame.CopyLineClick(Sender: TObject);
begin
  FList.CopyLine;
end;

procedure TAtlasDebugConsoleFrame.CopyAllClick(Sender: TObject);
begin
  FList.CopyAll;
end;

procedure TAtlasDebugConsoleFrame.OpenClick(Sender: TObject);
begin
  FList.OpenSelected;
end;

procedure TAtlasDebugConsoleFrame.MenuPopup(Sender: TObject);
var
  mLocation: TAtlasConsoleLocation;
begin
  FOpenItem.Enabled := FList.SelectedLocation(mLocation);
end;

procedure TAtlasDebugConsoleFrame.SetBuffer(ABuffer: TAtlasConsoleBuffer);
begin
  FList.SetBuffer(ABuffer);
end;

procedure TAtlasDebugConsoleFrame.Refill;
begin
  FList.Refill;
end;

end.
