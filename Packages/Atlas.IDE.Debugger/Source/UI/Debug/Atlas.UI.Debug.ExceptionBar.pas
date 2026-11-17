unit Atlas.UI.Debug.ExceptionBar;

// Exception-Leiste beim Debuggen (#783), Darstellung: drei Zeilen oben im
// Editor, im Atlas-Stil (#410, #411: Akzentrahmen, runde Ecken, Farben nach
// IDE-Thema über SetColors).
//   1. Klasse (fett, Fehlerfarbe) und Meldung; rechts „n× an dieser Stelle“.
//   2. Thread, „n Ebenen ausgeblendet“ und die erste eigene Zeile (Routine,
//      Unit:Zeile; Klick springt hin, OnAction Open).
//   3. Knöpfe Anhalten, Fortsetzen, Klasse ignorieren, Nur an dieser Stelle
//      ignorieren (nur mit TAtlasDebugBannerInfo.CanIgnoreLocation), Meldung
//      kopieren, Test daraus anlegen (#1873, nur mit CanCreateTest); rechts die
//      Tastenhinweise als Fußzeile.
// Erklärung einer Zugriffsverletzung (#865, SetExplanation): zwischen Zeile 2
// und den Knöpfen eine Zeile mit dem Ergebnis („Auftrag.Kunde ist nil“ und
// Feld bzw. Versatz), darunter die geprüften Glieder mit ✓/✗ (höchstens
// MaxExplanationLines, dann „… n weitere“) und eine Zeile mit den Knöpfen
// „Wo wird X zugewiesen?“, „Ausdruck auswerten“, „Erklärung kopieren“. Die
// Höhe wächst mit den Zeilen. Während Atlas prüft, steht nur die Ergebniszeile
// („Atlas prüft …“) da.
// Gezeichnet wird alles selbst (kein Fokus, keine Fenster für Knöpfe), damit
// der Editor die Tasten behält; die Tasten F8, F9 und Esc fängt die IDE-Schicht.
// Wo Zeilen und Knöpfe liegen, rechnet TAtlasDebugBarLayout (Kern), gezeichnet
// wird mit TAtlasDebugBarPainter; die Leiste selbst hält Maus und Zustand.
// Ausgelöst wird beim Loslassen auf demselben Knopf. Was ein Knopf tut,
// entscheidet der Aufrufer (Atlas.IDE.Debug.ExceptionBar).

interface

uses
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.Core.Debug.ExceptionBarLayout;

type
  TAtlasDebugBarActionEvent = reference to procedure(AAction: TAtlasDebugBarAction);

  TAtlasDebugExceptionBar = class(TCustomControl)
  private
    FLayout: TAtlasDebugBarLayout;
    FColors: TAtlasColors;
    FHot: TAtlasDebugBarAction;
    FDown: TAtlasDebugBarAction;
    FLaidOut: Boolean;
    FOnAction: TAtlasDebugBarActionEvent;
    function DetailText: string;
    function GetInfo: TAtlasDebugBannerInfo;
    function GetExplanation: TAtlasDebugBannerExplanation;
    procedure ApplyHeight;
    procedure Layout;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetInfo(const AInfo: TAtlasDebugBannerInfo);
    /// <summary>Erklärung zeigen bzw. mit Active = False entfernen; die Höhe passt sich an.</summary>
    procedure SetExplanation(const AExplanation: TAtlasDebugBannerExplanation);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Höhe der Leiste bei APPI (drei Zeilen, 78 px bei 96 DPI).</summary>
    class function BarHeight(APPI: Integer): Integer; overload; static;
    /// <summary>Höhe bei APPI mit ARows Zeilen.</summary>
    class function BarHeight(APPI, ARows: Integer): Integer; overload; static;
    /// <summary>Zeilen der Leiste: drei, mit Erklärung mehr.</summary>
    function Rows: Integer;
    /// <summary>Knopf bzw. Ortszeile unter dem Punkt (Client); None = nichts.</summary>
    function ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
    /// <summary>Fläche eines Knopfs (Client); leer, wenn er fehlt.</summary>
    function ActionRect(AAction: TAtlasDebugBarAction): TRect;
    /// <summary>Wie ein Klick (Tasten, Tests): meldet OnAction, wenn es den Knopf gibt.</summary>
    procedure Trigger(AAction: TAtlasDebugBarAction);
    /// <summary>Zeile 2 als Text (für Tests und Tooltip).</summary>
    property Detail: string read DetailText;
    property Info: TAtlasDebugBannerInfo read GetInfo;
    property Explanation: TAtlasDebugBannerExplanation read GetExplanation;
    property OnAction: TAtlasDebugBarActionEvent read FOnAction write FOnAction;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.UI.Debug.ExceptionBarPainter,
  Atlas.UI.Debug.Exceptions.Strings;

{ TAtlasDebugExceptionBar }

constructor TAtlasDebugExceptionBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  ShowHint := True;
  FLayout := TAtlasDebugBarLayout.Create;
  FColors := TAtlasColors.Light;
  FHot := TAtlasDebugBarAction.None;
  FDown := TAtlasDebugBarAction.None;
  Height := BarHeight(TAtlasDebugBarLayout.cBasePPI);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

destructor TAtlasDebugExceptionBar.Destroy;
begin
  FreeAndNil(FLayout);
  inherited Destroy;
end;

function TAtlasDebugExceptionBar.DetailText: string;
begin
  Result := TAtlasDebugBarPainter.DetailText(FLayout.Info);
end;

function TAtlasDebugExceptionBar.GetInfo: TAtlasDebugBannerInfo;
begin
  Result := FLayout.Info;
end;

function TAtlasDebugExceptionBar.GetExplanation: TAtlasDebugBannerExplanation;
begin
  Result := FLayout.Explanation;
end;

procedure TAtlasDebugExceptionBar.Resize;
begin
  inherited Resize;
  FLaidOut := False;
end;

procedure TAtlasDebugExceptionBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := ActionAt(X, Y);
  end;
end;

procedure TAtlasDebugExceptionBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mAction: TAtlasDebugBarAction;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mAction := ActionAt(X, Y);
  if mAction = FDown then
  begin
    Trigger(mAction);
  end;
  FDown := TAtlasDebugBarAction.None;
end;

procedure TAtlasDebugExceptionBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: TAtlasDebugBarAction;
begin
  inherited MouseMove(Shift, X, Y);
  mHot := ActionAt(X, Y);
  if mHot = FHot then
  begin
    Exit;
  end;
  FHot := mHot;
  if mHot <> TAtlasDebugBarAction.None then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  Application.CancelHint;
  if mHot = TAtlasDebugBarAction.Open then
  begin
    Hint := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugBannerOpenHint);
  end
  else
  begin
    Hint := FLayout.Info.Message;
  end;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  ApplyHeight;
  FLaidOut := False;
end;

procedure TAtlasDebugExceptionBar.ApplyHeight;
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  Height := BarHeight(CurrentPPI, Rows);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

procedure TAtlasDebugExceptionBar.Layout;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  FLayout.PPI := CurrentPPI;
  Canvas.Font := Font;
  FLayout.Arrange(ClientWidth, Canvas.TextWidth(DetailText),
    function(AAction: TAtlasDebugBarAction): Integer
    begin
      Result := Canvas.TextWidth(TAtlasDebugBarPainter.Caption(AAction, FLayout.Explanation.WhereName));
    end);
  FLaidOut := True;
end;

procedure TAtlasDebugExceptionBar.Paint;
var
  mPainter: TAtlasDebugBarPainter;
begin
  Layout;
  FLayout.PPI := CurrentPPI;
  mPainter := TAtlasDebugBarPainter.Create(Canvas, Font, FLayout, FColors, FHot);
  try
    mPainter.Paint(ClientRect);
  finally
    mPainter.Free;
  end;
end;

procedure TAtlasDebugExceptionBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FDown := TAtlasDebugBarAction.None;
  if FHot = TAtlasDebugBarAction.None then
  begin
    Exit;
  end;
  FHot := TAtlasDebugBarAction.None;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.SetInfo(const AInfo: TAtlasDebugBannerInfo);
begin
  FLayout.SetContent(AInfo, FLayout.Explanation);
  FLaidOut := False;
  Hint := AInfo.Message;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.SetExplanation(const AExplanation: TAtlasDebugBannerExplanation);
begin
  FLayout.SetContent(FLayout.Info, AExplanation);
  ApplyHeight;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasDebugExceptionBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

class function TAtlasDebugExceptionBar.BarHeight(APPI: Integer): Integer;
begin
  Result := TAtlasDebugBarLayout.BarHeight(APPI, TAtlasDebugBarLayout.cBaseRows);
end;

class function TAtlasDebugExceptionBar.BarHeight(APPI, ARows: Integer): Integer;
begin
  Result := TAtlasDebugBarLayout.BarHeight(APPI, ARows);
end;

function TAtlasDebugExceptionBar.Rows: Integer;
begin
  Result := FLayout.Rows;
end;

function TAtlasDebugExceptionBar.ActionAt(AX, AY: Integer): TAtlasDebugBarAction;
begin
  Layout;
  Result := FLayout.ActionAt(AX, AY);
end;

function TAtlasDebugExceptionBar.ActionRect(AAction: TAtlasDebugBarAction): TRect;
begin
  Layout;
  Result := FLayout.ActionRect(AAction);
end;

procedure TAtlasDebugExceptionBar.Trigger(AAction: TAtlasDebugBarAction);
begin
  if FLayout.CanTrigger(AAction) and Assigned(FOnAction) then
  begin
    FOnAction(AAction);
  end;
end;

end.
