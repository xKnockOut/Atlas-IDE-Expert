unit Atlas.IDE.Editor.MouseButtons;

// Zurück- und Vor-Taste der Maus (#1889) im Code-Editor, im Formular-Designer
// und in den übrigen Fenstern der IDE:
// - Ein TApplicationEvents liest die Nachrichtenschleife der IDE; nur
//   Nachrichten an Fenster des eigenen Prozesses kommen dort an.
// - Zuerst die Atlas-Fenster mit eigenem Verlauf (TAtlasMouseHistory, etwa die
//   Issue-Vorschau), sonst der Navigationsverlauf (#504) wie Alt+←/Alt+→.
// - Verbraucht wird die Nachricht nur, wenn Atlas sie übernommen hat; am
//   Anfang bzw. Ende des Verlaufs geht sie unverändert weiter (kein Ton).
// - Mit navigation.mouseButtons oder navHistory.enabled aus: keine Wirkung.
// Nur im Hauptthread.

interface

type
  TAtlasIdeMouseButtons = class
  private class var
    FEvents: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.AppEvnts,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.MouseButtons,
  Atlas.IDE.Contracts.MouseHistory,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.NavHistory;

type
  TMouseEvents = class(TComponent)
  private
    FEvents: TApplicationEvents;
    procedure Message(var AMsg: TMsg; var AHandled: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TMouseEvents.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEvents := TApplicationEvents.Create(Self);
  FEvents.OnMessage := Message;
end;

procedure TMouseEvents.Message(var AMsg: TMsg; var AHandled: Boolean);
var
  mDirection: TAtlasNavDirection;
  mWindow: HWND;
  mTaken: Boolean;
begin
  if AHandled or not TAtlasIdeSettings.Current.MouseNavButtons then
  begin
    Exit;
  end;
  mDirection := TAtlasMouseButtons.DirectionOf(AMsg.message, AMsg.wParam, AMsg.lParam);
  if mDirection = TAtlasNavDirection.None then
  begin
    Exit;
  end;
  mWindow := AMsg.hwnd;
  mTaken := False;
  TAtlasGuard.Run(TAtlasFeature.NavHistory,
    procedure
    begin
      mTaken := TAtlasMouseHistory.Dispatch(mWindow, mDirection) or
        TAtlasIdeNavHistory.Step(mDirection = TAtlasNavDirection.Forward);
    end);
  AHandled := mTaken;
end;

class procedure TAtlasIdeMouseButtons.Install;
begin
  FreeAndNil(FEvents);
  FEvents := TMouseEvents.Create(nil);
end;

class procedure TAtlasIdeMouseButtons.Uninstall;
begin
  FreeAndNil(FEvents);
end;

end.
