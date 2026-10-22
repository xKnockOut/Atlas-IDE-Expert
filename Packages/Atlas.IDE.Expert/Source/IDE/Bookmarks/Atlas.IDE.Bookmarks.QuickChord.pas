unit Atlas.IDE.Bookmarks.QuickChord;

// Strg+Umschalt+K für schnelle Lesezeichen (#1104) neben den Faltungsakkorden
// der IDE (Strg+Umschalt+K, dann U, E, A, T, O …):
// - Die Tastaturbindung von Atlas nimmt nur den ersten Teil (Pressed) und
//   wartet bookmarks.quick.chordWait ms. Solange hört ein Client des
//   gemeinsamen Tastatur-Hooks (TAtlasKeyHook) auf die nächste Taste.
// - Ein Faltungsbuchstabe in der Wartezeit (TAtlasQuickBookmarks.Chord =
//   PassOn): Der Buchstabe wird geschluckt, und Atlas schickt Strg+Umschalt+K
//   und den Buchstaben erneut in die Eingabe (SendInput). Den wiederholten
//   ersten Teil lässt die Bindung durch (krNextProc), so dass die IDE den
//   ganzen Akkord wie ohne Atlas sieht.
// - Zeitüberschreitung oder eine andere Taste: Lesezeichen setzen bzw.
//   entfernen (QuickToggle); die andere Taste läuft danach normal weiter.
// - Lässt sich die Folge nicht weitergeben, meldet Atlas das in der
//   Meldungsansicht.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasIdeQuickChord = class
  public
    /// <summary>Aus der Tastaturbindung beim ersten Teil: True = Atlas übernimmt (krHandled), False = an die
    /// nächste Bindung (die eigene Weitergabe des Akkords).</summary>
    class function Pressed: Boolean; static;
    /// <summary>Warten abbrechen und Hook-Client freigeben (Entladen, Einstellungen).</summary>
    class procedure Release; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.ExtCtrls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Bookmarks.Service;

const
  /// <summary>Nach dem Wartezeitende des Tastatur-Hooks: vor den Fenstern von Atlas gefragt.</summary>
  ChordPriority = -10;
  /// <summary>So lange gilt ein selbst gesendeter erster Teil als „durchlassen“.</summary>
  PassMs = 1000;

type
  TChordState = class(TAtlasKeyClient)
  private
    FTimer: TTimer;
    FWaiting: Boolean;
    FStarted: UInt64;
    FBaseKey: Word;
    FPassAt: UInt64;
    procedure Tick(Sender: TObject);
    procedure Finish;
    procedure Toggle;
    procedure PassOn(AKey: Word);
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
  end;

var
  State: TChordState = nil;

{ TChordState }

constructor TChordState.Create;
begin
  inherited Create(ChordPriority);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

destructor TChordState.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if TAtlasKeyHook.Contains(Self) then
    TAtlasKeyHook.Remove(Self);
  FTimer.Free;
  inherited Destroy;
end;

procedure TChordState.Start;
begin
  FBaseKey := Word(TAtlasIdeSettings.Current.QuickBookmarkKey) and $00FF;
  FStarted := TThread.GetTickCount64;
  FWaiting := True;
  if not TAtlasKeyHook.Contains(Self) then
    TAtlasKeyHook.Add(Self);
  FTimer.Enabled := True;
end;

procedure TChordState.Finish;
begin
  FWaiting := False;
  FTimer.Enabled := False;
  if TAtlasKeyHook.Contains(Self) then
    TAtlasKeyHook.Remove(Self);
end;

procedure TChordState.Toggle;
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.QuickToggle);
    end);
end;

procedure TChordState.Tick(Sender: TObject);
var
  Elapsed: Integer;
begin
  try
    if not FWaiting then
    begin
      FTimer.Enabled := False;
      Exit;
    end;
    Elapsed := Integer(TThread.GetTickCount64 - FStarted);
    if TAtlasQuickBookmarks.Chord(TAtlasIdeSettings.Current.QuickBookmarkChordWait, Elapsed, 0) =
      TAtlasChordAction.Toggle then
    begin
      Finish;
      Toggle;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

function TChordState.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  // Im Hook gefragt, auch beim Loslassen: Die Taste des ersten Teils (Loslassen, Wiederholung) ist noch kein
  // zweiter Teil.
  Result := False;
  if not FWaiting or (AKey = FBaseKey) then
    Exit;
  case TAtlasQuickBookmarks.Chord(TAtlasIdeSettings.Current.QuickBookmarkChordWait,
    Integer(TThread.GetTickCount64 - FStarted), AKey) of
    TAtlasChordAction.PassOn:
      begin
        // Schlucken; HandleKey gibt die ganze Folge an die IDE.
        FWaiting := False;
        Result := True;
      end;
    TAtlasChordAction.Toggle:
      begin
        // Andere Taste: Lesezeichen, die Taste selbst läuft weiter in den Editor. Einzige Wirkung im Hook ist das
        // Ende des Wartens; Lesezeichen und Abmelden laufen nach der Nachrichtenverarbeitung.
        FWaiting := False;
        TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
          procedure
          begin
            if State <> nil then
            begin
              State.Finish;
              State.Toggle;
            end;
          end);
      end;
  end;
end;

procedure TChordState.HandleKey(AKey: Word; AShift: TShiftState);
begin
  Finish;
  PassOn(AKey);
end;

procedure TChordState.PassOn(AKey: Word);
var
  Inputs: TArray<TInput>;
  Pressed: TArray<Word>;
  Modifier: Word;
  Base: Word;

  procedure Add(AVirtual: Word; AUp: Boolean);
  var
    Input: TInput;
  begin
    Input := Default(TInput);
    Input.Itype := INPUT_KEYBOARD;
    Input.ki.wVk := AVirtual;
    if AUp then
      Input.ki.dwFlags := KEYEVENTF_KEYUP;
    Inputs := Inputs + [Input];
  end;

begin
  Inputs := nil;
  Pressed := nil;
  Base := Word(TAtlasIdeSettings.Current.QuickBookmarkKey);
  // Umschalttasten des ersten Teils, die der Nutzer nicht mehr hält, kurz selbst drücken.
  if ((Base and scCtrl) <> 0) and (GetKeyState(VK_CONTROL) >= 0) then
    Pressed := Pressed + [VK_CONTROL];
  if ((Base and scShift) <> 0) and (GetKeyState(VK_SHIFT) >= 0) then
    Pressed := Pressed + [VK_SHIFT];
  if ((Base and scAlt) <> 0) and (GetKeyState(VK_MENU) >= 0) then
    Pressed := Pressed + [VK_MENU];
  for Modifier in Pressed do
    Add(Modifier, False);
  Add(FBaseKey, False);
  Add(FBaseKey, True);
  for Modifier in Pressed do
    Add(Modifier, True);
  // Der zweite Teil mit den Umschalttasten, die der Nutzer gerade hält, wie er ihn gedrückt hat.
  Add(AKey, False);
  Add(AKey, True);
  FPassAt := TThread.GetTickCount64;
  if SendInput(Length(Inputs), Inputs[0], SizeOf(TInput)) <> Cardinal(Length(Inputs)) then
  begin
    FPassAt := 0;
    TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkChordFailed, [Char(AKey)]));
  end;
end;

{ TAtlasIdeQuickChord }

class function TAtlasIdeQuickChord.Pressed: Boolean;
var
  Wait: Integer;
begin
  if State = nil then
    State := TChordState.Create;
  // Der selbst gesendete erste Teil geht an die Faltung der IDE.
  if (State.FPassAt <> 0) and (TThread.GetTickCount64 - State.FPassAt < PassMs) then
  begin
    State.FPassAt := 0;
    Exit(False);
  end;
  State.FPassAt := 0;
  Result := True;
  Wait := TAtlasIdeSettings.Current.QuickBookmarkChordWait;
  if Wait <= 0 then
  begin
    State.Toggle;
    Exit;
  end;
  // Wiederholung der gehaltenen Taste, während Atlas noch wartet: weiter warten.
  if State.FWaiting then
    Exit;
  State.Start;
end;

class procedure TAtlasIdeQuickChord.Release;
begin
  FreeAndNil(State);
end;

end.
