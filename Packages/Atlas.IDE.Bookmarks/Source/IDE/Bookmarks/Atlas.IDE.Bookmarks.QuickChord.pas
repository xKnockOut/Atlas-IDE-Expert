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
  Atlas.UI.Bookmarks.Strings,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Bookmarks.QuickService,
  Atlas.IDE.Foundation.Host;

const
  /// <summary>Nach dem Wartezeitende des Tastatur-Hooks: vor den Fenstern von Atlas gefragt.</summary>
  cChordPriority = -10;
  /// <summary>So lange gilt ein selbst gesendeter erster Teil als „durchlassen“.</summary>
  cPassMs = 1000;

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
  inherited Create(cChordPriority);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := Tick;
end;

destructor TChordState.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if TAtlasKeyHook.Contains(Self) then
  begin
    TAtlasKeyHook.Remove(Self);
  end;
  FTimer.Free;
  inherited Destroy;
end;

procedure TChordState.Start;
begin
  FBaseKey := Word(TAtlasIdeSettings.Current.QuickBookmarkKey) and $00FF;
  FStarted := TThread.GetTickCount64;
  FWaiting := True;
  if not TAtlasKeyHook.Contains(Self) then
  begin
    TAtlasKeyHook.Add(Self);
  end;
  FTimer.Enabled := True;
end;

procedure TChordState.Finish;
begin
  FWaiting := False;
  FTimer.Enabled := False;
  if TAtlasKeyHook.Contains(Self) then
  begin
    TAtlasKeyHook.Remove(Self);
  end;
end;

procedure TChordState.Toggle;
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks, TAtlasIdeQuickBookmarks.QuickToggle);
    end);
end;

procedure TChordState.Tick(Sender: TObject);
var
  mElapsed: Integer;
begin
  try
    if not FWaiting then
    begin
      FTimer.Enabled := False;
      Exit;
    end;
    mElapsed := Integer(TThread.GetTickCount64 - FStarted);
    if TAtlasQuickBookmarks.Chord(TAtlasIdeSettings.Current.QuickBookmarkChordWait, mElapsed, 0) =
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
  begin
    Exit;
  end;
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
  mInputs: TArray<TInput>;
  mPressed: TArray<Word>;
  mModifier: Word;
  mBase: Word;

  procedure Add(AVirtual: Word; AUp: Boolean);
  var
    mInput: TInput;
  begin
    mInput := Default(TInput);
    mInput.Itype := INPUT_KEYBOARD;
    mInput.ki.wVk := AVirtual;
    if AUp then
    begin
      mInput.ki.dwFlags := KEYEVENTF_KEYUP;
    end;
    mInputs := mInputs + [mInput];
  end;

begin
  mInputs := nil;
  mPressed := nil;
  mBase := Word(TAtlasIdeSettings.Current.QuickBookmarkKey);
  // Umschalttasten des ersten Teils, die der Nutzer nicht mehr hält, kurz selbst drücken.
  if ((mBase and scCtrl) <> 0) and (GetKeyState(VK_CONTROL) >= 0) then
  begin
    mPressed := mPressed + [VK_CONTROL];
  end;
  if ((mBase and scShift) <> 0) and (GetKeyState(VK_SHIFT) >= 0) then
  begin
    mPressed := mPressed + [VK_SHIFT];
  end;
  if ((mBase and scAlt) <> 0) and (GetKeyState(VK_MENU) >= 0) then
  begin
    mPressed := mPressed + [VK_MENU];
  end;
  for mModifier in mPressed do
  begin
    Add(mModifier, False);
  end;
  Add(FBaseKey, False);
  Add(FBaseKey, True);
  for mModifier in mPressed do
  begin
    Add(mModifier, True);
  end;
  // Der zweite Teil mit den Umschalttasten, die der Nutzer gerade hält, wie er ihn gedrückt hat.
  Add(AKey, False);
  Add(AKey, True);
  FPassAt := TThread.GetTickCount64;
  if SendInput(Length(mInputs), mInputs[0], SizeOf(TInput)) <> Cardinal(Length(mInputs)) then
  begin
    FPassAt := 0;
    TAtlasIdeHost.Message(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkChordFailed, [Char(AKey)]));
  end;
end;

{ TAtlasIdeQuickChord }

class function TAtlasIdeQuickChord.Pressed: Boolean;
var
  mWait: Integer;
begin
  if State = nil then
  begin
    State := TChordState.Create;
  end;
  // Der selbst gesendete erste Teil geht an die Faltung der IDE.
  if (State.FPassAt <> 0) and (TThread.GetTickCount64 - State.FPassAt < cPassMs) then
  begin
    State.FPassAt := 0;
    Exit(False);
  end;
  State.FPassAt := 0;
  Result := True;
  mWait := TAtlasIdeSettings.Current.QuickBookmarkChordWait;
  if mWait <= 0 then
  begin
    State.Toggle;
    Exit;
  end;
  // Wiederholung der gehaltenen Taste, während Atlas noch wartet: weiter warten.
  if State.FWaiting then
  begin
    Exit;
  end;
  State.Start;
end;

class procedure TAtlasIdeQuickChord.Release;
begin
  FreeAndNil(State);
end;

end.
