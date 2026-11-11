unit Atlas.IDE.Contracts.MouseHistory;

// Vertrag zwischen Modulen (#1889, Modulregeln 4 und 6): Atlas-Fenster mit
// eigenem Verlauf (etwa die Issue-Vorschau) melden sich hier an, damit die
// Zurück-/Vor-Taste der Maus in ihnen deren Verlauf blättert statt im Code.
// Base fragt die Angemeldeten der Reihe nach mit dem Fenster unter der Maus;
// wer True antwortet, hat die Taste übernommen. Abmelden mit der Nummer aus
// Register beim Stoppen. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Atlas.Core.Editor.MouseButtons;

type
  /// <summary>AWindow liegt im eigenen Fenster: Verlauf in ADirection blättern und True; sonst False.</summary>
  TAtlasMouseHistoryHandler = reference to function(AWindow: HWND; ADirection: TAtlasNavDirection): Boolean;

  TAtlasMouseHistory = class
  private class var
    FHandlers: TArray<TAtlasMouseHistoryHandler>;
  public
    /// <summary>Fenster mit eigenem Verlauf anmelden; Ergebnis für Unregister.</summary>
    class function Register(const AHandler: TAtlasMouseHistoryHandler): Integer; static;
    class procedure Unregister(AId: Integer); static;
    /// <summary>Hat ein angemeldetes Fenster die Taste übernommen?</summary>
    class function Dispatch(AWindow: HWND; ADirection: TAtlasNavDirection): Boolean; static;
  end;

implementation

class function TAtlasMouseHistory.Register(const AHandler: TAtlasMouseHistoryHandler): Integer;
begin
  for Result := 0 to High(FHandlers) do
  begin
    if not Assigned(FHandlers[Result]) then
    begin
      FHandlers[Result] := AHandler;
      Exit;
    end;
  end;
  FHandlers := FHandlers + [AHandler];
  Result := High(FHandlers);
end;

class procedure TAtlasMouseHistory.Unregister(AId: Integer);
begin
  if (AId >= 0) and (AId <= High(FHandlers)) then
  begin
    FHandlers[AId] := nil;
  end;
end;

class function TAtlasMouseHistory.Dispatch(AWindow: HWND; ADirection: TAtlasNavDirection): Boolean;
var
  mHandler: TAtlasMouseHistoryHandler;
begin
  for mHandler in FHandlers do
  begin
    if Assigned(mHandler) and mHandler(AWindow, ADirection) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
