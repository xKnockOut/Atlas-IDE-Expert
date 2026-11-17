unit Atlas.IDE.Editor.CaretPopup;

// Gerüst für ein kleines Fenster an der Schreibmarke, das Tasten des Editors
// abnimmt und auf Wunsch eine Markierung in den Editor zeichnet (Umschließung
// entfernen #657, Typ des Ausdrucks #689, Sprungziele beim Hineinspringen):
// - Tasten: Über TApplicationEvents, solange das Fenster steht und die Taste
//   im Editorfenster gedrückt wird. Umschalt, Strg und Alt allein gehen nicht
//   weiter; jede andere Taste bekommt der Besitzer (OnKey), der sie annimmt
//   oder das Fenster schließt.
// - Ein Mausklick (auf Wunsch auch das Mausrad) außerhalb des Fensters ruft
//   OnClose.
// - Zeichnen: ein Notifier für plsEndPaint, der an OnPaint weiterreicht; ohne
//   OnPaint (nil) wird keiner angemeldet.
// - Beide Wege laufen nur, solange die Funktion AFeature nicht abgeschaltet
//   ist (#493); eine Exception geht an TAtlasGuard und nie an die IDE.
// Nur im Hauptthread.

interface

uses
  System.Types,
  Winapi.Windows,
  Vcl.AppEvnts,
  ToolsAPI.Editor,
  Atlas.UI.Popup.Window,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>Taste AKey im Editor bei stehendem Fenster; AHandled = True nimmt sie dem Editor ab.</summary>
  TAtlasCaretPopupKeyEvent = procedure(AKey: Word; var AHandled: Boolean) of object;
  /// <summary>Klick außerhalb des Fensters.</summary>
  TAtlasCaretPopupCloseEvent = procedure of object;
  /// <summary>Zeile des Editors am Ende des Zeichnens (plsEndPaint).</summary>
  TAtlasCaretPopupPaintEvent = procedure(const ARect: TRect; const AStage: TPaintLineStage; ABeforeEvent: Boolean;
    const AContext: INTACodeEditorPaintContext) of object;

  TAtlasIdeCaretPopupHooks = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FFeature: TAtlasFeature;
    FPopup: TAtlasPopupWindow;
    FCloseOnWheel: Boolean;
    FOnKey: TAtlasCaretPopupKeyEvent;
    FOnClose: TAtlasCaretPopupCloseEvent;
    FOnPaint: TAtlasCaretPopupPaintEvent;
    FMessages: TApplicationEvents;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    function Shown: Boolean;
    function ClosesOnClick(AMessage: Cardinal): Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    /// <summary>Meldet Tasten und, mit AOnPaint, das Zeichnen für die Funktion AFeature an.</summary>
    constructor Create(AFeature: TAtlasFeature; const AOnKey: TAtlasCaretPopupKeyEvent;
      const AOnClose: TAtlasCaretPopupCloseEvent; const AOnPaint: TAtlasCaretPopupPaintEvent);
    /// <summary>Meldet erst ab, dann gibt es frei (#493). Das Fenster gehört dem Besitzer.</summary>
    destructor Destroy; override;
    /// <summary>Fenster, dessen Sichtbarkeit die Tasten freigibt; nil = keins.</summary>
    property Popup: TAtlasPopupWindow read FPopup write FPopup;
    /// <summary>Schließt auch das Mausrad außerhalb des Fensters?</summary>
    property CloseOnWheel: Boolean read FCloseOnWheel write FCloseOnWheel;
    /// <summary>Editor neu zeichnen (Markierung gesetzt oder entfernt).</summary>
    class procedure Invalidate; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Messages,
  ToolsAPI,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh;

function IsModifierKey(AKey: Word): Boolean;
begin
  Result := (AKey = VK_SHIFT) or (AKey = VK_CONTROL) or (AKey = VK_MENU);
end;

{ TAtlasIdeCaretPopupHooks.TEvents }

function TAtlasIdeCaretPopupHooks.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeCaretPopupHooks.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeCaretPopupHooks }

constructor TAtlasIdeCaretPopupHooks.Create(AFeature: TAtlasFeature; const AOnKey: TAtlasCaretPopupKeyEvent;
  const AOnClose: TAtlasCaretPopupCloseEvent; const AOnPaint: TAtlasCaretPopupPaintEvent);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FFeature := AFeature;
  FOnKey := AOnKey;
  FOnClose := AOnClose;
  FOnPaint := AOnPaint;
  FIndex := -1;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  if not Assigned(AOnPaint) then
  begin
    Exit;
  end;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeCaretPopupHooks.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  FreeAndNil(FMessages);
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  FPopup := nil;
  inherited;
end;

function TAtlasIdeCaretPopupHooks.Shown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsShown;
end;

function TAtlasIdeCaretPopupHooks.ClosesOnClick(AMessage: Cardinal): Boolean;
begin
  case AMessage of
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN:
      Result := True;
    WM_MOUSEWHEEL:
      Result := FCloseOnWheel;
  else
    Result := False;
  end;
end;

procedure TAtlasIdeCaretPopupHooks.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(FFeature) or not Shown then
  begin
    Exit;
  end;
  try
    if (Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN) then
    begin
      if TAtlasEditorBuffer.IsEditorWindow(Msg.hwnd) and not IsModifierKey(Word(Msg.wParam)) then
      begin
        FOnKey(Word(Msg.wParam), Handled);
      end;
    end
    else if ClosesOnClick(Msg.message) and (not FPopup.HandleAllocated or (Msg.hwnd <> FPopup.Handle)) then
    begin
      FOnClose;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(FFeature, E);
    end;
  end;
end;

procedure TAtlasIdeCaretPopupHooks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
  if TAtlasGuard.Disabled(FFeature) then
  begin
    Exit;
  end;
  try
    FOnPaint(Rect, Stage, BeforeEvent, Context);
  except
    on E: Exception do
      TAtlasGuard.Report(FFeature, E);
  end;
end;

class procedure TAtlasIdeCaretPopupHooks.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

end.
