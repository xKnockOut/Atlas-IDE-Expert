unit Atlas.IDE.Editor.KeyHook;

// Tastatur-Hook des Hauptthreads für die Fenster von Atlas (#410, #436). Er ist
// nur installiert, solange mindestens ein Fenster offen ist und Tasten braucht;
// sonst berührt Atlas keine Taste. Keine Tastaturbindung der IDE: Eine Bindung für
// Pfeile, Enter, Tab, Pos1, Ende oder Esc nimmt sie dem Editor auch bei
// geschlossenem Fenster weg, weil er sie ohne eigenen Handler verarbeitet.
// Die Clients werden nach Priorität gefragt (kleiner zuerst): Esc schließt zuerst
// die Vervollständigung, dann den Parameter-Hint. Gewollte Tasten erreichen den
// Editor nicht (Drücken und Loslassen) und werden per ForceQueue nach der
// Nachrichtenverarbeitung ausgeführt, nicht im Hook.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

type
  TAtlasKeyClient = class abstract
  private
    FPriority: Integer;
  protected
    /// <summary>Gehört die Taste gerade diesem Fenster? Im Hook gefragt: schnell, ohne Seiteneffekte.</summary>
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; virtual; abstract;
    /// <summary>Führt die Taste aus; im Hauptthread nach der Nachrichtenverarbeitung.</summary>
    procedure HandleKey(AKey: Word; AShift: TShiftState); virtual; abstract;
  public
    constructor Create(APriority: Integer);
    property Priority: Integer read FPriority;
  end;

  TAtlasKeyHook = class
  public
    /// <summary>Meldet AClient an; installiert den Hook beim ersten Client.</summary>
    class procedure Add(AClient: TAtlasKeyClient); static;
    /// <summary>Meldet AClient ab; entfernt den Hook beim letzten. Vor dem Freigeben aufrufen.</summary>
    class procedure Remove(AClient: TAtlasKeyClient); static;
    class function Contains(AClient: TAtlasKeyClient): Boolean; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Generics.Collections;

var
  Clients: TList<TAtlasKeyClient> = nil;
  Hook: HHOOK = 0;

{ TAtlasKeyClient }

constructor TAtlasKeyClient.Create(APriority: Integer);
begin
  inherited Create;
  FPriority := APriority;
end;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
    Include(Result, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then
    Include(Result, ssCtrl);
  if GetKeyState(VK_MENU) < 0 then
    Include(Result, ssAlt);
end;

function KeyboardProc(Code: Integer; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Snapshot: TArray<TAtlasKeyClient>;
  Client: TAtlasKeyClient;
  Key: Word;
  Shift: TShiftState;
begin
  try
    if (Code = HC_ACTION) and (Clients <> nil) and (Clients.Count > 0) then
    begin
      Key := Word(WParam);
      Shift := CurrentShift;
      Snapshot := Clients.ToArray;
      for Client in Snapshot do
        if Client.WantsKey(Key, Shift) then
        begin
          // Gedrückt (auch Wiederholung): ausführen, solange der Client noch angemeldet ist.
          if (LParam and $80000000) = 0 then
            TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
              procedure
              begin
                try
                  if TAtlasKeyHook.Contains(Client) then
                    Client.HandleKey(Key, Shift);
                except
                  // Die Clients melden ihre Fehler selbst; hier nur das letzte Netz (#493).
                  on E: Exception do
                    TAtlasGuard.Log('Tastatur: ' + E.ClassName + ': ' + E.Message);
                end;
              end);
          Exit(1);
        end;
    end;
  except
    // Keine Exception an die IDE (#493); die Taste geht dann an den Editor.
    on E: Exception do
      TAtlasGuard.Log('Tastatur-Hook: ' + E.ClassName + ': ' + TAtlasGuard.SafeMessage(E.Message));
  end;
  Result := CallNextHookEx(Hook, Code, WParam, LParam);
end;

{ TAtlasKeyHook }

class procedure TAtlasKeyHook.Add(AClient: TAtlasKeyClient);
var
  Index: Integer;
begin
  if Clients = nil then
    Clients := TList<TAtlasKeyClient>.Create;
  if Clients.Contains(AClient) then
    Exit;
  Index := 0;
  while (Index < Clients.Count) and (Clients[Index].Priority <= AClient.Priority) do
    Inc(Index);
  Clients.Insert(Index, AClient);
  if Hook = 0 then
    Hook := SetWindowsHookEx(WH_KEYBOARD, @KeyboardProc, 0, GetCurrentThreadId);
end;

class procedure TAtlasKeyHook.Remove(AClient: TAtlasKeyClient);
begin
  if Clients = nil then
    Exit;
  Clients.Remove(AClient);
  if (Clients.Count = 0) and (Hook <> 0) then
  begin
    UnhookWindowsHookEx(Hook);
    Hook := 0;
  end;
end;

class function TAtlasKeyHook.Contains(AClient: TAtlasKeyClient): Boolean;
begin
  Result := (Clients <> nil) and Clients.Contains(AClient);
end;

class function TAtlasKeyHook.Installed: Boolean;
begin
  Result := Hook <> 0;
end;

initialization

finalization
  if Hook <> 0 then
    UnhookWindowsHookEx(Hook);
  Hook := 0;
  FreeAndNil(Clients);

end.
