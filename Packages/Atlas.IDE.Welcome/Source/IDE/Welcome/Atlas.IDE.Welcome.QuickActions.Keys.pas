unit Atlas.IDE.Welcome.QuickActions.Keys;

// Tasten der Schnellaktionen (#764): Strg+B und Strg+T (einstellbar) nimmt
// TAtlasQuickActionKeys über TApplicationEvents vor den Tasten der IDE ab,
// solange die unsichtbare Tastatur-Steuerung einer Leiste
// (TAtlasQuickKeySink) den Fokus hat. Ob eine Taste gilt, entscheidet der
// Besitzer (OnAccept); er merkt sich dabei auch den Zeitpunkt (eine Taste
// zählt nicht als Mausklick, #600). Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Vcl.AppEvnts;

type
  /// <summary>Gilt das gedrückte Kürzel AShortCut (TShortCut) als Taste einer Schnellaktion?</summary>
  TAtlasQuickKeyAcceptEvent = function(AShortCut: Integer): Boolean of object;

  TAtlasQuickActionKeys = class
  private
    FEvents: TApplicationEvents;
    FOnAccept: TAtlasQuickKeyAcceptEvent;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
  public
    /// <summary>Meldet die Beobachtung an; AOnAccept prüft jedes Kürzel in einer Leiste mit Fokus.</summary>
    constructor Create(const AOnAccept: TAtlasQuickKeyAcceptEvent);
    /// <summary>Meldet ab; danach kommt keine Taste mehr an.</summary>
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Welcome.QuickActions;

{ TAtlasQuickActionKeys }

constructor TAtlasQuickActionKeys.Create(const AOnAccept: TAtlasQuickKeyAcceptEvent);
begin
  inherited Create;
  FOnAccept := AOnAccept;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
end;

destructor TAtlasQuickActionKeys.Destroy;
begin
  FreeAndNil(FEvents);
  FOnAccept := nil;
  inherited;
end;

procedure TAtlasQuickActionKeys.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mControl: TWinControl;
  mShift: TShiftState;
  mPressed: TShortCut;
begin
  if (Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN) then
  begin
    Exit;
  end;
  try
    mControl := FindControl(Msg.hwnd);
    if not (mControl is TAtlasQuickKeySink) then
    begin
      Exit;
    end;
    mShift := KeyDataToShiftState(Msg.lParam);
    mPressed := ShortCut(Word(Msg.wParam), mShift);
    // Vor den Tasten der IDE (Strg+B, Strg+T im Editor): nur in der Zeile mit dem Fokus.
    if (mPressed <> 0) and FOnAccept(Integer(mPressed)) then
    begin
      Handled := TAtlasQuickKeySink(mControl).HandleKey(Word(Msg.wParam), mShift);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
