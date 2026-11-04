unit Atlas.IDE.Commands.ShortcutKeys;

// Tabelle Kürzel → Befehle der Tastenkürzel-Tipps (#600) und was die Tipps über
// Aktionen und Tasten wissen müssen (Kürzel und Beschriftung einer Aktion, Taste
// einer Atlas-Funktion). Ausgelagert aus Atlas.IDE.Commands.ShortcutTips, das den
// Ablauf beschreibt: Die Tabelle entsteht aus den Atlas-Tasten, die Atlas
// tatsächlich hält, den beim Aufruf gelernten Kürzeln, den Aktionen der IDE mit
// Haupt- und Zweittasten und den Kürzeln mit zwei Schritten aus den
// Menübeschriftungen; sie wird nach KeysMaxAgeMs oder nach ResetKeys neu gebaut.

interface

uses
  Winapi.Windows,
  System.Generics.Collections,
  Vcl.ActnList,
  Atlas.Core.Commands.KeyConflicts;

type
  /// <summary>Kürzel und Beschriftungen von Aktionen der IDE und Tasten von Atlas.</summary>
  TAtlasIdeActionKeys = record
  public
    class function Ticks: UInt64; static;
    /// <summary>Umschalttasten, die gerade gedrückt sind, als Bits wie in TShortCut.</summary>
    class function CurrentModifiers: Word; static;
    /// <summary>Aktion der IDE mit diesem Namen; nil ohne.</summary>
    class function FindAction(const AName: string): TCustomAction; static;
    /// <summary>Aktion gehört Atlas (eigene Aktionslisten, Kategorie „Atlas“); die melden sich selbst.</summary>
    class function IsAtlasAction(AAction: TCustomAction): Boolean; static;
    /// <summary>Kürzel einer Aktion als Text: Haupttaste, sonst die erste Zweittaste, sonst ein Kürzel aus einem
    /// Menü (auch mit zwei Schritten); '' ohne.</summary>
    class function ActionKeyText(AAction: TCustomAction): string; static;
    /// <summary>Beschriftung einer Aktion ohne Kürzelzeichen und Tab-Text; sonst ihr Name.</summary>
    class function ActionCaption(AAction: TCustomAction): string; static;
    /// <summary>Taste der Atlas-Funktion als Text, wenn Atlas sie hält (frei oder mit Vorrang, #494); sonst '',
    /// auch wenn die Funktion abgeschaltet ist (Suchfeld der Willkommensseite aus, #775 aus, „Units suchen“ aus).
    /// Immer aus den aktuellen Einstellungen: nach einer Neubelegung sofort die neue.</summary>
    class function AtlasKeyText(AFunc: TAtlasKeyFunction): string; static;
    /// <summary>Taste eines Atlas-Befehls: unter mehreren Tasten für denselben Befehl (#775 zwei Tasten, #777
    /// eigene Taste und Strg+F12) die erste, die Atlas hält; AFunc bekommt deren Funktion.</summary>
    class function AtlasCommandKeyText(const AId: string; var AFunc: TAtlasKeyFunction): string; static;
    /// <summary>Wie TAtlasIdeShortcutTips.KeyOnlyText.</summary>
    class function KeyOnlyText(const AId: string; out AKeyText: string): Boolean; static;
    /// <summary>Kürzel, Beschriftung und ob er von Atlas ist für einen Befehl der Befehlspalette (Atlas-Befehl
    /// oder Aktion der IDE); Kürzel und Beschriftung '', wenn es keine gibt.</summary>
    class procedure Describe(const AId: string; out AKeyText, ACaption: string; out AIsAtlas: Boolean); static;
  end;

  /// <summary>Tabelle Kürzel → Befehle und die Merker, wie ein Befehl gerade aufgerufen wurde.</summary>
  TAtlasIdeShortcutKeys = class
  public const
    /// <summary>Tabelle Kürzel → Befehle spätestens nach dieser Zeit neu bauen.</summary>
    KeysMaxAgeMs = 30000;
    /// <summary>Eine Aktion zählt nur, wenn der Benutzer so kurz vorher etwas eingegeben hat.</summary>
    UserInputMs = 1500;
    /// <summary>Selbst gemeldeter Aufruf: OnActionExecute derselben Aktion so lange danach nicht noch einmal.
    /// </summary>
    ExplicitMs = 1000;
  private
    /// <summary>Schlüssel der Tastenfolge (StepsKey) → Befehle.</summary>
    FKeys: TDictionary<string, TArray<string>>;
    FKeysBuiltAt: UInt64;
    FPrevKey: Word;
    FPrevAt: UInt64;
    FExplicitId: string;
    FExplicitAt: UInt64;
    /// <summary>Kürzel von Aktionen außerhalb von INTAServices.ActionList, gelernt beim Aufruf: Befehl → Text.
    /// </summary>
    FLearned: TDictionary<string, string>;
    procedure AddKeys(const AKeyText, AId: string); overload;
    procedure AddKeys(AShortCut: Word; const AId: string); overload;
    /// <summary>Atlas-Tasten, die Atlas tatsächlich hält, und beim Aufruf gelernte Kürzel.</summary>
    procedure AddAtlasKeys;
    /// <summary>Haupt- und Zweittasten der Aktionen der IDE.</summary>
    procedure AddActionKeys;
    /// <summary>Kürzel mit zwei Schritten stehen nur in den Menübeschriftungen.</summary>
    procedure AddMenuKeys;
    procedure EnsureKeys;
    /// <summary>Die letzte Taste ist so kurz her, dass diese der zweite Schritt eines Kürzels sein kann.</summary>
    function ChordPending: Boolean;
    /// <summary>Befehle zur Taste; AChordOnly: nur als zweiter Schritt eines Kürzels mit zwei Schritten (Taste
    /// ohne Strg/Alt). Merkt die Taste für den nächsten Schritt.</summary>
    function StrokeIds(AShortCut: Word; AChordOnly: Boolean): TArray<string>;
  protected
    /// <summary>Tabelle beim nächsten Gebrauch neu bauen (Einstellungen oder Packages geändert).</summary>
    procedure ResetKeys;
    /// <summary>Kürzel einer Aktion außerhalb der Aktionsliste der IDE für die Tastatur merken.</summary>
    procedure Learn(const AId, AKeyText: string);
    /// <summary>Befehl hat sich selbst gemeldet; OnActionExecute zählt ihn ExplicitMs lang nicht noch einmal.
    /// </summary>
    procedure Explicit(const AId: string);
    /// <summary>Befehle, die ein WM_KEYDOWN auslöst; leer bei Wiederholung, Umschalttasten und Tasten ohne
    /// Befehl.</summary>
    function Stroke(const AMsg: TMsg): TArray<string>;
    /// <summary>Ein Aufruf der Aktion zählt als Aufruf per Maus: keine Aktion von Atlas, nicht schon selbst
    /// gemeldet, nicht über ihr Kürzel und mit einer Eingabe des Benutzers kurz zuvor.</summary>
    function CountsAsMouseUse(AAction: TCustomAction): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Commands.KeyMap,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.KeyMap;

/// <summary>Der Benutzer hat gerade etwas eingegeben (Maus oder Tastatur, auch im Menü).</summary>
function UserJustActed: Boolean;
var
  Info: TLastInputInfo;
begin
  Info.cbSize := SizeOf(Info);
  Info.dwTime := 0;
  if not GetLastInputInfo(Info) then
  begin
    Exit(True);
  end;
  Result := DWORD(GetTickCount - Info.dwTime) < DWORD(TAtlasIdeShortcutKeys.UserInputMs);
end;

/// <summary>Kürzel aus Menüeinträgen: Aktion → Text hinter dem Tab der Beschriftung (auch Kürzel mit zwei
/// Schritten) bzw. ShortCut des Eintrags.</summary>
procedure CollectMenuKeys(AItem: TMenuItem; AResult: TDictionary<TBasicAction, string>);
var
  Index: Integer;
  Child: TMenuItem;
  Text: string;
begin
  for Index := 0 to AItem.Count - 1 do
  begin
    Child := AItem.Items[Index];
    if Child.Action <> nil then
    begin
      Text := TAtlasShortcutTips.KeyTextOfCaption(Child.Caption);
      if (Text = '') and (Child.ShortCut <> 0) then
      begin
        Text := ShortCutToText(Child.ShortCut);
      end;
      if (Text <> '') and not AResult.ContainsKey(Child.Action) then
      begin
        AResult.Add(Child.Action, Text);
      end;
    end;
    if Child.Count > 0 then
    begin
      CollectMenuKeys(Child, AResult);
    end;
  end;
end;

/// <summary>Kürzel aus dem Hauptmenü; mit AEditorMenus auch aus den Kontextmenüs des obersten Editorfensters.
/// </summary>
function MenuKeys(AEditorMenus: Boolean): TDictionary<TBasicAction, string>;
var
  Services: INTAServices;
  Editor: INTAEditorServices;
  Window: INTAEditWindow;
  Index: Integer;
begin
  Result := TDictionary<TBasicAction, string>.Create;
  if Supports(BorlandIDEServices, INTAServices, Services) and (Services.MainMenu <> nil) then
  begin
    CollectMenuKeys(Services.MainMenu.Items, Result);
  end;
  if not AEditorMenus or not Supports(BorlandIDEServices, INTAEditorServices, Editor) then
  begin
    Exit;
  end;
  Window := Editor.TopEditWindow;
  if (Window = nil) or (Window.Form = nil) then
  begin
    Exit;
  end;
  for Index := 0 to Window.Form.ComponentCount - 1 do
  begin
    if Window.Form.Components[Index] is TPopupMenu then
    begin
      CollectMenuKeys(TPopupMenu(Window.Form.Components[Index]).Items, Result);
    end;
  end;
end;

/// <summary>Passt AShortCut zu den Tasten, die jetzt gedrückt sind bzw. eben gedrückt wurden (APrevKey vor weniger
/// als ChordMs)?</summary>
function MatchesShortCut(AShortCut, APrevKey: Word; APrevAge: UInt64): Boolean;
var
  Key, Modifiers: Word;
begin
  Result := False;
  if AShortCut = 0 then
  begin
    Exit;
  end;
  Key := AShortCut and $FF;
  Modifiers := AShortCut and TAtlasKeyMap.ModifierMask;
  if (GetKeyState(Key) < 0) and (Modifiers = TAtlasIdeActionKeys.CurrentModifiers) then
  begin
    Exit(True);
  end;
  Result := (APrevKey = AShortCut) and (APrevAge < TAtlasShortcutTips.ChordMs);
end;

/// <summary>Wurde AAction gerade über eines ihrer Kürzel ausgelöst? Taste und Umschalttasten jetzt gedrückt bzw.
/// eben gedrückt (APrevKey vor weniger als ChordMs).</summary>
function ViaShortCut(AAction: TCustomAction; APrevKey: Word; APrevAge: UInt64): Boolean;
var
  Index: Integer;
begin
  Result := MatchesShortCut(Word(AAction.ShortCut), APrevKey, APrevAge);
  Index := 0;
  while not Result and (Index < AAction.SecondaryShortCuts.Count) do
  begin
    Result := MatchesShortCut(Word(AAction.SecondaryShortCuts.ShortCuts[Index]), APrevKey, APrevAge);
    Inc(Index);
  end;
end;

/// <summary>Taste zählt nie für sich (Umschalttasten, Windows-Taste, Feststelltaste).</summary>
function IsModifierKey(AKey: Word): Boolean;
begin
  case AKey of
    VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN, VK_CAPITAL:
      Result := True;
  else
    Result := False;
  end;
end;

{ TAtlasIdeActionKeys }

class function TAtlasIdeActionKeys.Ticks: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

class function TAtlasIdeActionKeys.CurrentModifiers: Word;
begin
  Result := 0;
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Result := Result or TAtlasKeyConflicts.scShift;
  end;
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Result := Result or TAtlasKeyConflicts.scCtrl;
  end;
  if GetKeyState(VK_MENU) < 0 then
  begin
    Result := Result or TAtlasKeyConflicts.scAlt;
  end;
end;

class function TAtlasIdeActionKeys.FindAction(const AName: string): TCustomAction;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := nil;
  if (AName = '') or not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
  begin
    Exit;
  end;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    if (Services.ActionList.Actions[Index] is TCustomAction) and
      SameText(Services.ActionList.Actions[Index].Name, AName) then
    begin
      Exit(TCustomAction(Services.ActionList.Actions[Index]));
    end;
  end;
end;

class function TAtlasIdeActionKeys.IsAtlasAction(AAction: TCustomAction): Boolean;
begin
  Result := SameText(AAction.Category, 'Atlas') or AAction.Category.StartsWith('Atlas.', True);
end;

class function TAtlasIdeActionKeys.ActionKeyText(AAction: TCustomAction): string;
var
  Keys: TDictionary<TBasicAction, string>;
  Index: Integer;
begin
  if AAction.ShortCut <> 0 then
  begin
    Exit(ShortCutToText(AAction.ShortCut));
  end;
  for Index := 0 to AAction.SecondaryShortCuts.Count - 1 do
  begin
    if AAction.SecondaryShortCuts.ShortCuts[Index] <> 0 then
    begin
      Exit(ShortCutToText(AAction.SecondaryShortCuts.ShortCuts[Index]));
    end;
  end;
  Keys := MenuKeys(True);
  try
    if not Keys.TryGetValue(AAction, Result) then
    begin
      Result := '';
    end;
  finally
    Keys.Free;
  end;
end;

class function TAtlasIdeActionKeys.ActionCaption(AAction: TCustomAction): string;
var
  Tab: Integer;
begin
  Result := AAction.Caption;
  Tab := Pos(#9, Result);
  if Tab > 0 then
  begin
    Result := Copy(Result, 1, Tab - 1);
  end;
  Result := TAtlasCommandPalette.CleanCaption(Result);
  if Result = '' then
  begin
    Result := AAction.Name;
  end;
end;

class function TAtlasIdeActionKeys.AtlasKeyText(AFunc: TAtlasKeyFunction): string;
var
  Entry: TAtlasKeyEntry;
begin
  Result := '';
  for Entry in TAtlasIdeKeyMap.AtlasEntries do
  begin
    if Entry.Func = AFunc then
    begin
      // Das Suchfeld der Willkommensseite hat immer Vorrang; dort gibt es keinen Aufruf per Maus.
      if (Entry.Key <> 0) and not Entry.Disabled and
        TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority) then
      begin
        Result := ShortCutToText(TShortCut(Entry.Key));
      end;
      Exit;
    end;
  end;
end;

class function TAtlasIdeActionKeys.AtlasCommandKeyText(const AId: string; var AFunc: TAtlasKeyFunction): string;
var
  Func: TAtlasKeyFunction;
begin
  Result := '';
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    if SameText(TAtlasShortcutTips.AtlasCommandId(Func), Trim(AId)) then
    begin
      Result := AtlasKeyText(Func);
      if Result <> '' then
      begin
        AFunc := Func;
        Exit;
      end;
    end;
  end;
end;

class function TAtlasIdeActionKeys.KeyOnlyText(const AId: string; out AKeyText: string): Boolean;
var
  Func: TAtlasKeyFunction;
  Entry: TAtlasKeyEntry;
begin
  AKeyText := '';
  Result := TAtlasShortcutTips.IsKeyOnly(AId, Func);
  if not Result then
  begin
    Exit;
  end;
  AKeyText := AtlasKeyText(Func);
  if AKeyText <> '' then
  begin
    Exit;
  end;
  // Vervollständigung und Parameter-Hint ohne eigene Taste laufen über Code Insight mit der Taste der IDE.
  for Entry in TAtlasKeyEntry.AllFromSettings(TAtlasIdeSettings.Current) do
  begin
    if (Entry.Func = Func) and (Entry.Key = 0) and (Entry.IdeKey <> 0) then
    begin
      AKeyText := ShortCutToText(TShortCut(Entry.IdeKey));
      Exit;
    end;
  end;
end;

class procedure TAtlasIdeActionKeys.Describe(const AId: string; out AKeyText, ACaption: string;
  out AIsAtlas: Boolean);
var
  Func: TAtlasKeyFunction;
  Action: TCustomAction;
begin
  AKeyText := '';
  ACaption := '';
  AIsAtlas := True;
  if TAtlasShortcutTips.AtlasFunctionOf(AId, Func) then
  begin
    AKeyText := AtlasCommandKeyText(AId, Func);
    ACaption := TAtlasKeyMapWindow.FunctionCaption(Func);
  end
  else if not AId.StartsWith('Atlas.', True) then
  begin
    // Aktion der IDE aus der Befehlspalette; ein Befehl von Atlas ohne eigene Taste bekommt keinen Tipp, aber
    // dieselbe Prüfung.
    Action := FindAction(AId);
    AIsAtlas := False;
    if Action <> nil then
    begin
      AKeyText := ActionKeyText(Action);
      ACaption := ActionCaption(Action);
      AIsAtlas := IsAtlasAction(Action);
    end;
  end;
end;

{ TAtlasIdeShortcutKeys }

constructor TAtlasIdeShortcutKeys.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, TArray<string>>.Create;
  FLearned := TDictionary<string, string>.Create;
end;

destructor TAtlasIdeShortcutKeys.Destroy;
begin
  FKeys.Free;
  FLearned.Free;
  inherited;
end;

procedure TAtlasIdeShortcutKeys.AddKeys(AShortCut: Word; const AId: string);
var
  Key: string;
  Ids: TArray<string>;
begin
  if (AShortCut = 0) or (AId = '') then
  begin
    Exit;
  end;
  Key := TAtlasShortcutTips.StepsKey([AShortCut]);
  if not FKeys.TryGetValue(Key, Ids) then
  begin
    Ids := nil;
  end;
  FKeys.AddOrSetValue(Key, Ids + [AId]);
end;

procedure TAtlasIdeShortcutKeys.AddKeys(const AKeyText, AId: string);
var
  Steps: TArray<Word>;
  Key: string;
  Ids: TArray<string>;
begin
  Steps := TAtlasShortcutTips.ParseSteps(AKeyText);
  if (Length(Steps) = 0) or (AId = '') then
  begin
    Exit;
  end;
  Key := TAtlasShortcutTips.StepsKey(Steps);
  if not FKeys.TryGetValue(Key, Ids) then
  begin
    Ids := nil;
  end;
  FKeys.AddOrSetValue(Key, Ids + [AId]);
end;

procedure TAtlasIdeShortcutKeys.AddAtlasKeys;
var
  mFunc: TAtlasKeyFunction;
  mLearned: TPair<string, string>;
begin
  for mFunc := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    AddKeys(TAtlasIdeActionKeys.AtlasKeyText(mFunc), TAtlasShortcutTips.AtlasCommandId(mFunc));
  end;
  // Beim Aufruf gelernte Kürzel (Aktionen des Editor-Kontextmenüs).
  for mLearned in FLearned do
  begin
    AddKeys(mLearned.Value, mLearned.Key);
  end;
end;

procedure TAtlasIdeShortcutKeys.AddActionKeys;
var
  mServices: INTAServices;
  mIndex, mSecondary: Integer;
  mAction: TCustomAction;
  mKey: Word;
begin
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if not (mServices.ActionList.Actions[mIndex] is TCustomAction) then
    begin
      Continue;
    end;
    mAction := TCustomAction(mServices.ActionList.Actions[mIndex]);
    if (mAction.Name = '') or TAtlasIdeActionKeys.IsAtlasAction(mAction) then
    begin
      Continue;
    end;
    AddKeys(Word(mAction.ShortCut), mAction.Name);
    for mSecondary := 0 to mAction.SecondaryShortCuts.Count - 1 do
    begin
      mKey := Word(mAction.SecondaryShortCuts.ShortCuts[mSecondary]);
      if mKey <> Word(mAction.ShortCut) then
      begin
        AddKeys(mKey, mAction.Name);
      end;
    end;
  end;
end;

procedure TAtlasIdeShortcutKeys.AddMenuKeys;
var
  mMenu: TDictionary<TBasicAction, string>;
  mPair: TPair<TBasicAction, string>;
  mAction: TCustomAction;
begin
  mMenu := MenuKeys(False);
  try
    for mPair in mMenu do
    begin
      if not (mPair.Key is TCustomAction) then
      begin
        Continue;
      end;
      mAction := TCustomAction(mPair.Key);
      if (mAction.Name <> '') and (mAction.ShortCut = 0) and not TAtlasIdeActionKeys.IsAtlasAction(mAction) then
      begin
        AddKeys(mPair.Value, mAction.Name);
      end;
    end;
  finally
    mMenu.Free;
  end;
end;

procedure TAtlasIdeShortcutKeys.EnsureKeys;
var
  mServices: INTAServices;
begin
  if (FKeysBuiltAt <> 0) and (TAtlasIdeActionKeys.Ticks - FKeysBuiltAt < KeysMaxAgeMs) then
  begin
    Exit;
  end;
  FKeysBuiltAt := TAtlasIdeActionKeys.Ticks;
  FKeys.Clear;
  AddAtlasKeys;
  // Ohne Aktionsliste der IDE auch keine Menükürzel (wie bisher).
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  AddActionKeys;
  AddMenuKeys;
end;

procedure TAtlasIdeShortcutKeys.ResetKeys;
begin
  FKeysBuiltAt := 0;
end;

procedure TAtlasIdeShortcutKeys.Learn(const AId, AKeyText: string);
begin
  if (AKeyText <> '') and (TAtlasIdeActionKeys.FindAction(AId) = nil) then
  begin
    FLearned.AddOrSetValue(AId, AKeyText);
    ResetKeys;
  end;
end;

procedure TAtlasIdeShortcutKeys.Explicit(const AId: string);
begin
  FExplicitId := AId;
  FExplicitAt := TAtlasIdeActionKeys.Ticks;
end;

function TAtlasIdeShortcutKeys.ChordPending: Boolean;
begin
  Result := (FPrevKey <> 0) and (TAtlasIdeActionKeys.Ticks - FPrevAt < TAtlasShortcutTips.ChordMs);
end;

function TAtlasIdeShortcutKeys.StrokeIds(AShortCut: Word; AChordOnly: Boolean): TArray<string>;
var
  mIds: TArray<string>;
begin
  EnsureKeys;
  Result := nil;
  if not AChordOnly and FKeys.TryGetValue(TAtlasShortcutTips.StepsKey([AShortCut]), mIds) then
  begin
    Result := mIds;
  end;
  // Zweiter Schritt eines Kürzels mit zwei Schritten.
  if ChordPending and FKeys.TryGetValue(TAtlasShortcutTips.StepsKey([FPrevKey, AShortCut]), mIds) then
  begin
    Result := Result + mIds;
  end;
  FPrevKey := AShortCut;
  FPrevAt := TAtlasIdeActionKeys.Ticks;
end;

function TAtlasIdeShortcutKeys.Stroke(const AMsg: TMsg): TArray<string>;
var
  mKey, mShortCut: Word;
begin
  Result := nil;
  // Wiederholung beim Festhalten zählt nicht.
  if (AMsg.lParam and $40000000) <> 0 then
  begin
    Exit;
  end;
  mKey := Word(AMsg.wParam);
  if IsModifierKey(mKey) then
  begin
    Exit;
  end;
  mShortCut := (mKey and $FF) or TAtlasIdeActionKeys.CurrentModifiers;
  if TAtlasShortcutTips.IsShortCutStroke(mShortCut) then
  begin
    Result := StrokeIds(mShortCut, False);
  end
  // Zweiter Schritt ohne Umschalttaste („Strg+K, D“).
  else if ChordPending then
  begin
    Result := StrokeIds(mShortCut, True);
  end
  else
  begin
    FPrevKey := 0;
  end;
end;

function TAtlasIdeShortcutKeys.CountsAsMouseUse(AAction: TCustomAction): Boolean;
begin
  // Namenlose Aktionen und die von Atlas (Kontextmenü, #399) melden sich selbst bzw. zählen nicht.
  if (AAction.Name = '') or TAtlasIdeActionKeys.IsAtlasAction(AAction) then
  begin
    Result := False;
  end
  // Von der Befehlspalette schon gemeldet.
  else if SameText(AAction.Name, FExplicitId) and (TAtlasIdeActionKeys.Ticks - FExplicitAt < ExplicitMs) then
  begin
    Result := False;
  end
  // Über das Kürzel: zählt schon die Tastatur.
  else if ViaShortCut(AAction, FPrevKey, TAtlasIdeActionKeys.Ticks - FPrevAt) then
  begin
    Result := False;
  end
  else
  begin
    // Aufrufe der IDE aus dem Programm heraus, ohne Eingabe des Benutzers, zählen nicht.
    Result := UserJustActed;
  end;
end;

end.
