unit Atlas.Core.Editor.MouseButtons;

// Zurück- und Vor-Taste der Maus (#1889), Kern ohne VCL und OTA: welche
// Nachricht für welche Richtung im Navigationsverlauf steht.
// - WM_XBUTTONUP: XBUTTON1 (Daumen hinten) = Zurück, XBUTTON2 = Vor. Atlas
//   wertet erst das Loslassen aus wie Browser und Visual Studio; verbraucht
//   es die Nachricht, erzeugt Windows daraus kein WM_APPCOMMAND mehr.
// - WM_APPCOMMAND mit APPCOMMAND_BROWSER_BACKWARD/FORWARD: Maustreiber, die
//   statt der Tasten Befehle schicken.
// Alles andere ist None. Die Werte stehen hier, damit der Kern ohne
// Winapi.Windows auskommt.

interface

type
{$SCOPEDENUMS ON}
  TAtlasNavDirection = (None, Back, Forward);
{$SCOPEDENUMS OFF}

  TAtlasMouseButtons = class
  public const
    cWmXButtonUp = $020C;
    cWmAppCommand = $0319;
    cXButton1 = 1;
    cXButton2 = 2;
    cAppCommandBrowserBackward = 1;
    cAppCommandBrowserForward = 2;
    /// <summary>Gerätebits im oberen Wort von lParam (FAPPCOMMAND_MASK).</summary>
    cAppCommandDeviceMask = $F000;
  public
    /// <summary>Richtung zur Nachricht AMessage mit AWParam/ALParam; None, wenn sie keine Verlaufstaste ist.</summary>
    class function DirectionOf(AMessage: Cardinal; AWParam, ALParam: NativeInt): TAtlasNavDirection; static;
  end;

implementation

class function TAtlasMouseButtons.DirectionOf(AMessage: Cardinal; AWParam, ALParam: NativeInt): TAtlasNavDirection;
var
  mCode: Integer;
begin
  Result := TAtlasNavDirection.None;
  if AMessage = cWmXButtonUp then
  begin
    mCode := (AWParam shr 16) and $FFFF;
    if mCode = cXButton1 then
    begin
      Result := TAtlasNavDirection.Back;
    end
    else if mCode = cXButton2 then
    begin
      Result := TAtlasNavDirection.Forward;
    end;
  end
  else if AMessage = cWmAppCommand then
  begin
    mCode := ((ALParam shr 16) and $FFFF) and not cAppCommandDeviceMask;
    if mCode = cAppCommandBrowserBackward then
    begin
      Result := TAtlasNavDirection.Back;
    end
    else if mCode = cAppCommandBrowserForward then
    begin
      Result := TAtlasNavDirection.Forward;
    end;
  end;
end;

end.
