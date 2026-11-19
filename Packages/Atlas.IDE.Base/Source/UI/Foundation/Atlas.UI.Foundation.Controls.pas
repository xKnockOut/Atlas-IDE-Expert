unit Atlas.UI.Foundation.Controls;

// Kleine Bausteine selbst gebauter Steuerelemente, gemeinsam für Base und Module (Willkommensseite, Tracker,
// Statusfeld, Gliederung):
// - WindowOrPending: Kacheln und Bereiche füllen sich erst mit Fenster (Text messen); ohne merken sie sich, dass
//   die Aktualisierung nachzuholen ist.
// - ClearHot: Hervorhebung beim Verlassen mit der Maus löschen und nur dann neu zeichnen.
// - SuppressBeep: Enter und Esc in einem Eingabefeld ohne Signalton von Windows.
// - Remeasure: Inhaltshöhe nach einer neuen Breite neu rechnen und eine Änderung melden.

interface

uses
  System.SysUtils,
  Vcl.Controls;

type
  TAtlasControls = record
  public const
    /// <summary>Keine Zeile oder kein Teil hervorgehoben.</summary>
    cNoHot = -1;
  public
    /// <summary>True, wenn AControl oder ein Vorfahr ein Fenster hat, an einem fremden Fenster hängt oder ein
    /// Formular ist; sonst APending := True (nachholen, sobald das Fenster da ist).</summary>
    class function WindowOrPending(AControl: TWinControl; var APending: Boolean): Boolean; static;
    /// <summary>AHot auf cNoHot setzen; war vorher etwas hervorgehoben, AControl neu zeichnen.</summary>
    class procedure ClearHot(AControl: TControl; var AHot: Integer); static;
    /// <summary>Enter (#13) und Esc (#27) in AKey verschlucken, damit Windows nicht piept.</summary>
    class procedure SuppressBeep(var AKey: Char); static;
    /// <summary>AHeight := ANewHeight; bei einer Änderung AChanged rufen.</summary>
    class procedure Remeasure(var AHeight: Integer; ANewHeight: Integer; const AChanged: TProc); static;
  end;

implementation

uses
  Vcl.Forms;

{ TAtlasControls }

class function TAtlasControls.WindowOrPending(AControl: TWinControl; var APending: Boolean): Boolean;
var
  mControl: TWinControl;
begin
  mControl := AControl;
  while mControl <> nil do
  begin
    if mControl.HandleAllocated or (mControl.ParentWindow <> 0) or (mControl is TCustomForm) then
    begin
      Exit(True);
    end;
    mControl := mControl.Parent;
  end;
  APending := True;
  Result := False;
end;

class procedure TAtlasControls.ClearHot(AControl: TControl; var AHot: Integer);
begin
  if AHot >= 0 then
  begin
    AHot := cNoHot;
    AControl.Invalidate;
  end;
end;

class procedure TAtlasControls.SuppressBeep(var AKey: Char);
begin
  if (AKey = #13) or (AKey = #27) then
  begin
    AKey := #0;
  end;
end;

class procedure TAtlasControls.Remeasure(var AHeight: Integer; ANewHeight: Integer; const AChanged: TProc);
var
  mOldHeight: Integer;
begin
  mOldHeight := AHeight;
  AHeight := ANewHeight;
  if (mOldHeight <> ANewHeight) and Assigned(AChanged) then
  begin
    AChanged();
  end;
end;

end.
