unit Atlas.IDE.Foundation.Caret;

// Schreibmarke des Editors in Bildschirmkoordinaten, für Fenster und Menüs an
// der Schreibmarke. Ihr Rechteck kommt aus GetGUIThreadInfo (rcCaret) und
// trägt die wirkliche Zeilenhöhe: Die ändert sich mit Skalierung des
// Monitors, Editorschrift und Zoom, ein fester Abstand in Pixeln passt nur
// bei 100 Prozent. Ohne Schreibmarke gilt die Maus, mit Höhe 0, damit ein
// Fenster dort beginnt und die Höhe nicht als Zoom gelesen wird.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.Types;

type
  TAtlasIdeCaret = class
  public
    /// <summary>Schreibmarke des Hauptthreads in Bildschirmkoordinaten und ihr Fenster; False ohne
    /// Schreibmarke.</summary>
    class function TryFind(out AWindow: HWND; out ARect: TRect): Boolean; static;
    /// <summary>Schreibmarke in Bildschirmkoordinaten; ohne Schreibmarke die Maus mit Höhe 0.</summary>
    class function Area: TRect; static;
    /// <summary>Bildschirmstelle direkt unter der Zeile mit der Schreibmarke (linke Unterkante); ohne
    /// Schreibmarke die Maus.</summary>
    class function BelowLine: TPoint; static;
  end;

implementation

uses
  Vcl.Controls;

class function TAtlasIdeCaret.TryFind(out AWindow: HWND; out ARect: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  AWindow := mInfo.hwndCaret;
  ARect := mInfo.rcCaret;
  if Result then
  begin
    MapWindowPoints(AWindow, 0, ARect, 2);
  end;
end;

class function TAtlasIdeCaret.Area: TRect;
var
  mWindow: HWND;
begin
  if not TryFind(mWindow, Result) then
  begin
    Result := TRect.Create(Mouse.CursorPos, 0, 0);
  end;
end;

class function TAtlasIdeCaret.BelowLine: TPoint;
var
  mArea: TRect;
begin
  mArea := Area;
  Result := TPoint.Create(mArea.Left, mArea.Bottom);
end;

end.
