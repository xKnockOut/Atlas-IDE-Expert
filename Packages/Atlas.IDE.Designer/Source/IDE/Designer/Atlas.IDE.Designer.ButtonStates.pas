unit Atlas.IDE.Designer.ButtonStates;

// Gemerkter Zustand der Umschaltknöpfe der Designer-Leiste in der IDE:
// Die Werkzeuge fragen beim Anlegen Pressed und melden jeden Klick über
// Remember. Gespeichert wird in der Zustandseinstellung designer.barButtons
// (TAtlasDesignerButtonStates); mit designer.rememberButtons aus gilt die
// Vorgabe des Werkzeugs, und nichts wird geschrieben.
// Nur im Hauptthread.

interface

type
  TAtlasIdeDesignerButtonStates = class
  public
    /// <summary>Zustand des Knopfs AId beim Anlegen des Werkzeugs; ADefault ohne gemerkten Zustand.</summary>
    class function Pressed(const AId: string; ADefault: Boolean): Boolean; static;
    /// <summary>Neuen Zustand des Knopfs AId nach einem Klick merken.</summary>
    class procedure Remember(const AId: string; APressed: Boolean); static;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.ButtonStates,
  Atlas.IDE.Foundation.Settings;

class function TAtlasIdeDesignerButtonStates.Pressed(const AId: string; ADefault: Boolean): Boolean;
begin
  Result := ADefault;
  if TAtlasIdeSettings.Current.DesignerRememberButtons then
  begin
    Result := TAtlasDesignerButtonStates.Pressed(TAtlasIdeSettings.Stored.DesignerBarButtons, AId, ADefault);
  end;
end;

class procedure TAtlasIdeDesignerButtonStates.Remember(const AId: string; APressed: Boolean);
var
  mNext: TAtlasPluginSettings;
  mText: string;
begin
  if not TAtlasIdeSettings.Current.DesignerRememberButtons then
  begin
    Exit;
  end;
  mNext := TAtlasIdeSettings.Stored;
  mText := TAtlasDesignerButtonStates.WithPressed(mNext.DesignerBarButtons, AId, APressed);
  if mText = mNext.DesignerBarButtons then
  begin
    Exit;
  end;
  mNext.DesignerBarButtons := mText;
  TAtlasIdeSettings.Update(mNext);
end;

end.
