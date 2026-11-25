unit Atlas.Vcl.Controls.Helpers;

// Kleine Bausteine selbst gebauter Steuerelemente, gemeinsam für Base und Module (Willkommensseite, Tracker,
// Statusfeld, Gliederung):
// - WindowOrPending: Kacheln und Bereiche füllen sich erst mit Fenster (Text messen); ohne merken sie sich, dass
//   die Aktualisierung nachzuholen ist.
// - ClearHot: Hervorhebung beim Verlassen mit der Maus löschen und nur dann neu zeichnen.
// - SuppressBeep: Enter und Esc in einem Eingabefeld ohne Signalton von Windows.
// - Remeasure: Inhaltshöhe nach einer neuen Breite neu rechnen und eine Änderung melden.
// - KeyHandled: CN_KEYDOWN/CN_SYSKEYDOWN an eine eigene Tastenbehandlung geben, bevor die VCL sie verteilt.
// - NewHiddenSheet: Reiterseite ohne sichtbaren Reiter einhängen (ein sichtbarer braucht das Fenster).
// - CanFocusNow: Fokus jetzt möglich, auch am Formular. CanFocus prüft das Formular selbst nicht, SetFocus wirft
//   dann EInvalidOperation („kann nicht fokussiert werden“), etwa wenn die IDE ihr Hauptfenster beim Start eines
//   Programms sperrt.

interface

uses
  Winapi.Messages,
  System.Types,
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls;

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
    /// <summary>Taste aus AMessage (CN_KEYDOWN oder CN_SYSKEYDOWN) an AHandle(Taste, Umschalttasten) geben; True und
    /// AMessage.Result 1, wenn AHandle sie behandelt hat (dann kein inherited, die IDE sieht sie nicht).</summary>
    class function KeyHandled(var AMessage: TWMKeyDown; const AHandle: TFunc<Word, TShiftState, Boolean>): Boolean;
      static;
    /// <summary>Reiterseite ACaption in APages, Besitzer AOwner, noch ohne sichtbaren Reiter: Ein sichtbarer Reiter
    /// braucht das Fenster des PageControls; der Besitzer zeigt ihn, sobald es da ist (CreateWnd).</summary>
    class function NewHiddenSheet(AOwner: TComponent; APages: TPageControl; const ACaption: string): TTabSheet;
      static;
    /// <summary>Ist AKey Enter: AKey := 0 und AOpen rufen (Eintrag öffnen statt Signalton), Ergebnis True.</summary>
    class function ReturnKey(var AKey: Word; const AOpen: TProc): Boolean; static;
    /// <summary>Tasten einer Liste: Enter ruft AOpen (wie ReturnKey), Strg+C ACopy; die behandelte Taste wird 0.
    /// True, wenn eine der beiden gedrückt war.</summary>
    class function OpenOrCopyKey(var AKey: Word; AShift: TShiftState; const AOpen, ACopy: TProc): Boolean; static;
    /// <summary>Data des gewählten Knotens von ATree als Zahl (Index in die Zeilen des Besitzers); -1 ohne Auswahl.
    /// </summary>
    class function SelectedIndex(ATree: TTreeView): Integer; static;
    /// <summary>Bildschirmpunkt unter der linken unteren Ecke von AControl (dort klappt ein Menü auf).</summary>
    class function BelowLeft(AControl: TControl): TPoint; static;
    /// <summary>Caption von ALabel, wenn es sichtbar ist; sonst ''.</summary>
    class function ShownCaption(ALabel: TCustomLabel): string; static;
    /// <summary>True, wenn SetFocus auf AControl jetzt gelingt: CanFocus, gezeigt, und das Formular darüber
    /// sichtbar und freigegeben (CanFocus prüft das Formular selbst nicht).</summary>
    class function CanFocusNow(AControl: TWinControl): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
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

class function TAtlasControls.KeyHandled(var AMessage: TWMKeyDown;
  const AHandle: TFunc<Word, TShiftState, Boolean>): Boolean;
begin
  Result := AHandle(AMessage.CharCode, KeyDataToShiftState(AMessage.KeyData));
  if Result then
  begin
    AMessage.Result := 1;
  end;
end;

class function TAtlasControls.NewHiddenSheet(AOwner: TComponent; APages: TPageControl;
  const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(AOwner);
  Result.TabVisible := False;
  Result.PageControl := APages;
  Result.Caption := ACaption;
end;

class function TAtlasControls.ReturnKey(var AKey: Word; const AOpen: TProc): Boolean;
begin
  Result := AKey = VK_RETURN;
  if Result then
  begin
    AKey := 0;
    AOpen();
  end;
end;

class function TAtlasControls.OpenOrCopyKey(var AKey: Word; AShift: TShiftState; const AOpen, ACopy: TProc): Boolean;
begin
  Result := ReturnKey(AKey, AOpen);
  if not Result and (AKey = Ord('C')) and (ssCtrl in AShift) then
  begin
    AKey := 0;
    ACopy();
    Result := True;
  end;
end;

class function TAtlasControls.SelectedIndex(ATree: TTreeView): Integer;
begin
  Result := -1;
  if ATree.Selected <> nil then
  begin
    Result := Integer(NativeInt(ATree.Selected.Data));
  end;
end;

class function TAtlasControls.BelowLeft(AControl: TControl): TPoint;
begin
  Result := AControl.ClientToScreen(TPoint.Create(0, AControl.Height));
end;

class function TAtlasControls.ShownCaption(ALabel: TCustomLabel): string;
begin
  Result := '';
  if ALabel.Visible then
  begin
    Result := ALabel.Caption;
  end;
end;

class function TAtlasControls.CanFocusNow(AControl: TWinControl): Boolean;
var
  mForm: TCustomForm;
begin
  Result := False;
  if (AControl = nil) or not AControl.Showing or not AControl.CanFocus then
  begin
    Exit;
  end;
  // Wie TWinControl.SetFocus: das oberste Formular (FocusControl, dort SetFocus mit Visible und Enabled).
  mForm := GetParentForm(AControl);
  Result := (mForm <> nil) and mForm.Visible and mForm.Enabled;
end;

end.
