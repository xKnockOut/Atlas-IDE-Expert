unit Atlas.UI.Editor.Bar;

// Gemeinsamer Vorfahr der gezeichneten Editorleisten (#1248): Editorleiste,
// Statusleiste, Brotkrumen. Was jede von ihnen gleich braucht, steht hier
// einmal; früher hatte jede ihre Kopie, und Fehler wurden je Kopie behoben.
// - Höhe nur nach DPI (BaseHeight bei 96 DPI), nie nach dem Inhalt;
//   FixedHeight := False gibt die Höhe frei (Editorleiste in der
//   Brotkrumenzeile).
// - Farben (SetColors), Fläche und Trennlinie zum Editor (PaintChrome).
// - Hervorhebung beim Überfahren: Die Leiste fragt PartAt; ändert sich das
//   Element, setzt sie Hot, Mauszeiger (PartEnabled), Tooltip (PartHint) und
//   zeichnet neu. Das Verlassen löscht Hot.
// - Klick erst beim Loslassen über dem Element (#1101): Nur wer auf einem
//   anderen Element gedrückt hat, bricht ab. Das Verlassen der Leiste
//   zwischen Drücken und Loslassen bricht nicht ab: In der IDE kommt es bei
//   jedem Klick (Mausfang, die IDE holt den Fokus in den Editor). Das
//   Loslassen nach einem Doppelklick ist kein zweiter Klick. PartClicked
//   meldet den Klick.
// - Kontextmenü (Rechtsklick, Menütaste): WM_CONTEXTMENU behandelt die
//   Leiste selbst (ContextMenu); es geht nie an das Editorfenster der IDE
//   weiter, sonst öffnete sich dessen Menü über der Leiste.
// - Gesperrt wird eine Leiste nur von außen (die IDE beim Schließen aller
//   Editoren). OnDisabled meldet das im Moment des Sperrens, über die VCL
//   (Enabled := False, der Aufrufer steht noch auf dem Stapel) wie an ihr
//   vorbei (EnableWindow, WM_ENABLE).
// Teile sind Ganzzahlen; PartNone heißt keins. Jede Leiste legt fest, was
// eine Zahl bedeutet.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

type
  TAtlasEditorBar = class(TCustomControl)
  public const
    PartNone = -1;
  private
    FColors: TAtlasColors;
    FHot: Integer;
    FDown: Integer;
    FSkipUp: Boolean;
    FFixedHeight: Boolean;
    FOnDisabled: TProc<TObject>;
    procedure SetFixedHeight(AValue: Boolean);
    procedure FixHeight(APPI: Integer);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMContextMenu(var Message: TWMContextMenu); message WM_CONTEXTMENU;
    procedure WMEnable(var Message: TWMEnable); message WM_ENABLE;
  protected
    /// <summary>Höhe bei 96 DPI.</summary>
    class function BaseHeight: Integer; virtual;
    function Scale(AValue: Integer): Integer;
    /// <summary>Element unter dem Punkt (Client); PartNone = keins.</summary>
    function PartAt(X, Y: Integer): Integer; virtual;
    /// <summary>Tooltip des Elements; '' = keiner.</summary>
    function PartHint(APart: Integer): string; virtual;
    /// <summary>Handzeiger über dem Element?</summary>
    function PartEnabled(APart: Integer): Boolean; virtual;
    /// <summary>Klick auf das Element (beim Loslassen, linke Taste).</summary>
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); virtual;
    /// <summary>Kontextmenü an APoint (Client); APart ist das Element dort.</summary>
    procedure ContextMenu(const APoint: TPoint; APart: Integer); virtual;
    /// <summary>Ort des Kontextmenüs von der Tastatur (Client).</summary>
    function KeyboardMenuPoint: TPoint; virtual;
    /// <summary>Hot hat sich geändert; zeichnet neu.</summary>
    procedure HotChanged; virtual;
    /// <summary>Fläche in Gutter, Trennlinie in Line oben (ALineAtTop) bzw. unten.</summary>
    procedure PaintChrome(ALineAtTop: Boolean);
    /// <summary>Hervorhebung von außen setzen (Inhalt geändert); zeichnet neu, wenn sie sich ändert.</summary>
    procedure SetHot(APart: Integer);
    procedure SetEnabled(Value: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    property Hot: Integer read FHot;
    /// <summary>Höhe nach DPI fest (Vorgabe); False: Höhe vom Elternteil (Align).</summary>
    property FixedHeight: Boolean read FFixedHeight write SetFixedHeight;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Höhe der Leiste bei APPI (eine Zeile).</summary>
    class function BarHeight(APPI: Integer): Integer;
    property Colors: TAtlasColors read FColors;
    /// <summary>Jemand sperrt die Leiste; gerufen, bevor sie gesperrt ist (VCL) bzw. sobald ihr Fenster gesperrt
    /// ist (EnableWindow).</summary>
    property OnDisabled: TProc<TObject> read FOnDisabled write FOnDisabled;
  end;

implementation

uses
  System.Math,
  Vcl.Forms;

{ TAtlasEditorBar }

constructor TAtlasEditorBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  ShowHint := True;
  FColors := TAtlasColors.Light;
  FHot := PartNone;
  FDown := PartNone;
  FFixedHeight := True;
  // Bei 96 DPI anlegen; das Elternteil skaliert beim Einhängen auf seine DPI (ChangeScale).
  FixHeight(96);
end;

class function TAtlasEditorBar.BaseHeight: Integer;
begin
  Result := 22;
end;

class function TAtlasEditorBar.BarHeight(APPI: Integer): Integer;
begin
  Result := MulDiv(BaseHeight, Max(APPI, 96), 96);
end;

function TAtlasEditorBar.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

procedure TAtlasEditorBar.FixHeight(APPI: Integer);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  if not FFixedHeight then
    Exit;
  Height := BarHeight(APPI);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

procedure TAtlasEditorBar.SetFixedHeight(AValue: Boolean);
begin
  if AValue = FFixedHeight then
    Exit;
  FFixedHeight := AValue;
  FixHeight(CurrentPPI);
end;

procedure TAtlasEditorBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  FixHeight(CurrentPPI);
end;

procedure TAtlasEditorBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasEditorBar.PaintChrome(ALineAtTop: Boolean);
var
  mLine: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := TColor(FColors.Line);
  mLine := ClientHeight - 1;
  if ALineAtTop then
    mLine := 0;
  Canvas.MoveTo(0, mLine);
  Canvas.LineTo(ClientWidth, mLine);
end;

function TAtlasEditorBar.PartAt(X, Y: Integer): Integer;
begin
  Result := PartNone;
end;

function TAtlasEditorBar.PartHint(APart: Integer): string;
begin
  Result := '';
end;

function TAtlasEditorBar.PartEnabled(APart: Integer): Boolean;
begin
  Result := APart <> PartNone;
end;

procedure TAtlasEditorBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
begin
  // Ohne Elemente nichts zu tun.
end;

procedure TAtlasEditorBar.ContextMenu(const APoint: TPoint; APart: Integer);
begin
  // Vorgabe: kein Menü; das des Editors darf trotzdem nicht kommen (siehe WMContextMenu).
end;

function TAtlasEditorBar.KeyboardMenuPoint: TPoint;
begin
  Result := Point(0, ClientHeight);
end;

procedure TAtlasEditorBar.HotChanged;
begin
  Invalidate;
end;

procedure TAtlasEditorBar.SetHot(APart: Integer);
begin
  if APart = FHot then
    Exit;
  FHot := APart;
  HotChanged;
end;

procedure TAtlasEditorBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  mHot := PartAt(X, Y);
  if mHot = FHot then
    Exit;
  FHot := mHot;
  if (mHot <> PartNone) and PartEnabled(mHot) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Application.CancelHint;
  Hint := PartHint(mHot);
  HotChanged;
end;

procedure TAtlasEditorBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  // FDown bleibt: Das Verlassen kommt in der IDE zwischen Drücken und Loslassen jedes Klicks (siehe oben).
  if FHot = PartNone then
    Exit;
  FHot := PartNone;
  HotChanged;
end;

procedure TAtlasEditorBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  FSkipUp := ssDouble in Shift;
  FDown := PartAt(X, Y);
end;

procedure TAtlasEditorBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mReleased: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if FSkipUp then
  begin
    FSkipUp := False;
    FDown := PartNone;
    Exit;
  end;
  // Erst beim Loslassen: Die IDE holt beim Drücken den Fokus in den Editor. Ein Drücken muss die Leiste dafür nicht
  // gesehen haben; nur ein Drücken auf einem anderen Element bricht ab.
  mReleased := PartAt(X, Y);
  if (mReleased <> PartNone) and ((FDown = PartNone) or (FDown = mReleased)) then
  begin
    FDown := PartNone;
    PartClicked(mReleased, Shift, X, Y);
    Exit;
  end;
  FDown := PartNone;
end;

procedure TAtlasEditorBar.WMContextMenu(var Message: TWMContextMenu);
var
  mPosition: TPoint;
begin
  // Nicht inherited: Sonst ginge das Kontextmenü an das Editorfenster der IDE weiter.
  Message.Result := 1;
  if (Message.XPos = -1) and (Message.YPos = -1) then
    mPosition := KeyboardMenuPoint
  else
    mPosition := ScreenToClient(SmallPointToPoint(Message.Pos));
  ContextMenu(mPosition, PartAt(mPosition.X, mPosition.Y));
end;

procedure TAtlasEditorBar.SetEnabled(Value: Boolean);
begin
  // Vor dem Sperren melden: Der Aufrufer steht dann noch auf dem Stapel.
  if not Value and Enabled and Assigned(FOnDisabled) then
    FOnDisabled(Self);
  inherited SetEnabled(Value);
end;

procedure TAtlasEditorBar.WMEnable(var Message: TWMEnable);
begin
  inherited;
  // An der VCL vorbei gesperrt (EnableWindow): Die VCL hält die Leiste noch für frei. Über SetEnabled kam die
  // Meldung schon; dann ist Enabled hier bereits False.
  if not Message.Enabled and Enabled and Assigned(FOnDisabled) then
    FOnDisabled(Self);
end;

end.
