unit Atlas.Tests.DialogSmoke;

// Rauchtest der Dialoge: Ein Dialog bekommt ein Fenster für sich und jedes eingehängte Steuerelement und
// durchläuft einmal den Weg vor dem Zeigen (DoShow), ohne sichtbar zu werden. Was sonst erst beim Öffnen in der
// IDE scheitert (Ereignis vor dem Aufbau, Liste ohne Fenster, Füllen vor dem Zeigen), macht so den Testlauf rot.
// Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog in einem Test gebaut wird.

interface

uses
  Vcl.Forms;

type
  TAtlasDialogSmoke = class
  public
    /// <summary>Fenster von ADialog und allen Steuerelementen mit Parent anlegen, DoShow wie beim Zeigen ausführen
    /// und danach neu entstandenen Steuerelementen ebenfalls ein Fenster geben. Ergebnis: Zahl der Fenster
    /// (der Dialog zählt mit).</summary>
    class function Realize(ADialog: TCustomForm): Integer; static;
  end;

implementation

uses
  Vcl.Controls;

type
  /// <summary>Zugriff auf das geschützte DoShow.</summary>
  TFormAccess = class(TCustomForm);

/// <summary>Jedem Steuerelement von ADialog mit Parent ein Fenster geben; Ergebnis: Zahl dieser Steuerelemente.
/// Ohne Parent hätte HandleNeeded kein übergeordnetes Fenster.</summary>
function RealizeControls(ADialog: TCustomForm): Integer;
var
  mIndex: Integer;
  mControl: TWinControl;
begin
  Result := 0;
  for mIndex := 0 to ADialog.ComponentCount - 1 do
  begin
    if ADialog.Components[mIndex] is TWinControl then
    begin
      mControl := TWinControl(ADialog.Components[mIndex]);
      if mControl.Parent <> nil then
      begin
        mControl.HandleNeeded;
        Inc(Result);
      end;
    end;
  end;
end;

{ TAtlasDialogSmoke }

class function TAtlasDialogSmoke.Realize(ADialog: TCustomForm): Integer;
begin
  ADialog.HandleNeeded;
  RealizeControls(ADialog);
  TFormAccess(ADialog).DoShow;
  Result := RealizeControls(ADialog) + 1;
end;

end.
