unit Atlas.IDE.Commands.ShortcutTips;

// Tastenkürzel-Tipps (#600) in der IDE. Wer eine Aktion, für die es ein
// Kürzel gibt, per Maus aufruft, sieht kurz unten rechts im Editorfenster einen
// Tipp mit dem Kürzel (TAtlasShortcutTipWindow).
// Erkennen, wie ein Befehl aufgerufen wurde (vorher geprüft, siehe
// docs/Architektur.md):
// - Aktionen der IDE und anderer Erweiterungen: Application.OnActionExecute
//   über TApplicationEvents (mehrere Abonnenten möglich, ändert keine Aktion).
//   Die VCL ruft es für jede TContainedAction, deren Aktionsliste sie nicht
//   selbst ausführt – gleich, ob Hauptmenü, Kontextmenü, Werkzeugleiste oder
//   Tastenkürzel sie auslöst. Per Tastatur heißt: Haupttaste und Umschalttasten
//   eines Kürzels der Aktion sind in diesem Augenblick gedrückt bzw. waren die
//   letzte Taste (TAtlasShortcutTips.ChordMs); sonst per Maus. Nur bei einer
//   Eingabe des Benutzers in den letzten UserInputMs (GetLastInputInfo), damit
//   Aufrufe der IDE aus dem Programm heraus nicht zählen. Kürzel und
//   Beschriftung kommen von der Aktion selbst (auch Aktionen des
//   Editor-Kontextmenüs, die nicht in INTAServices.ActionList stehen, z. B.
//   „Klasse beim Cursor vervollständigen“), sonst aus dem Text hinter dem Tab
//   im Hauptmenü bzw. in den Kontextmenüs des Editorfensters. Solche Kürzel
//   merkt sich die Tabelle für die Tastatur (FLearned).
// - Befehle von Atlas: Hauptmenü Atlas, Kontextmenü und Befehlspalette melden
//   sich selbst (Invoked); die Palette meldet auch Aktionen der IDE, die sie
//   ausführt, OnActionExecute zählt diese dann nicht doppelt.
// - Tastatur: Application.OnMessage sieht jedes WM_KEYDOWN, bevor die IDE es
//   verarbeitet, auch Kürzel, die eine Tastaturbelegung des Editors ausführt
//   und die nie eine Aktion auslösen (z. B. Strg+Umschalt+C). Kürzel mit Strg,
//   Alt oder F-Tasten werden über eine Tabelle Kürzel → Befehle (Aktionen der
//   IDE mit Haupt- und Zweittasten, Kürzel mit zwei Schritten aus den
//   Menübeschriftungen, Atlas-Tasten, die Atlas tatsächlich hält) gezählt; die
//   Tabelle wird nach KeysMaxAgeMs, nach Package-Änderungen und nach
//   geänderten Einstellungen neu gebaut. Jede Taste schließt einen offenen Tipp.
// Zählung je Befehl in %LOCALAPPDATA%\Atlas\usage.json und Merker der Tipps
// in %LOCALAPPDATA%\Atlas\shortcut-tips.json über die gemeinsame Zählung
// TAtlasIdeCommandUsage (#757, nur lokal), gespeichert dort SaveDelayMs nach
// der letzten Änderung und beim Entladen; die Tastenkürzel-Übersicht (#520)
// und „Atlas entdecken“ (#757) lesen dieselbe Zählung. Mit tips.usageTracking
// aus zählt sie nichts. Ohne shortcutTips.enabled beobachtet Atlas nichts
// (außer CountAlways ist gesetzt: Karte „Atlas entdecken“ mit Zählung an).
// Der Titel eines Tipps kommt aus tips.json, wenn es dort einen Tipp zum
// Befehl gibt (dieselbe Tippquelle wie #757), sonst von der Aktion.
// Kein Tipp während einer angehaltenen Debug-Sitzung, bei offenem modalem
// Dialog und häufiger als alle 30 s; die Regeln stehen im Core.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.AppEvnts,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Commands.ShortcutTip,
  Atlas.IDE.Commands.Usage;

type
  TAtlasIdeShortcutTips = class
  public const
    /// <summary>Tabelle Kürzel → Befehle spätestens nach dieser Zeit neu bauen.</summary>
    KeysMaxAgeMs = 30000;
    /// <summary>Eine Aktion zählt nur, wenn der Benutzer so kurz vorher etwas eingegeben hat.</summary>
    UserInputMs = 1500;
    /// <summary>Selbst gemeldeter Aufruf: OnActionExecute derselben Aktion so lange danach nicht noch einmal.
    /// </summary>
    ExplicitMs = 1000;
  private class var
    FInstance: TAtlasIdeShortcutTips;
  private
    /// <summary>Gemeinsame Zählung (#757); gehört der Komposition.</summary>
    FHolder: TAtlasIdeCommandUsage;
    FEvents: TApplicationEvents;
    FWindow: TAtlasShortcutTipWindow;
    FActive: Boolean;
    FCountAlways: Boolean;
    /// <summary>Befehl des gerade gezeigten Tipps.</summary>
    FTipId: string;
    FLastTipAt: TDateTime;
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
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure AppActionExecute(Action: TBasicAction; var Handled: Boolean);
    procedure NeverClick(Sender: TObject);
    procedure AllKeysClick(Sender: TObject);
    procedure Changed;
    procedure Save;
    procedure EnsureKeys;
    procedure AddKeys(const AKeyText, AId: string); overload;
    procedure AddKeys(AShortCut: Word; const AId: string); overload;
    /// <summary>Taste zählen; AChordOnly: nur als zweiter Schritt eines Kürzels mit zwei Schritten (Taste ohne
    /// Strg/Alt).</summary>
    procedure KeyStroke(AShortCut: Word; AChordOnly: Boolean);
    /// <summary>Aufruf per Maus zählen und den Tipp nach der Aktion prüfen; Kürzel und Beschriftung erst dann
    /// ermitteln.</summary>
    procedure MouseUse(const AId: string); overload;
    /// <summary>Wie oben mit schon bekanntem Kürzel und Beschriftung (Aktion der IDE).</summary>
    procedure MouseUse(const AId, AKeyText, ACaption: string); overload;
    procedure Queue(const AId, AKeyText, ACaption: string; AKnown: Boolean);
    procedure Consider(const AId: string); overload;
    procedure Consider(const AId, AKeyText, ACaption: string; AIsAtlas: Boolean); overload;
    procedure ShowTip(const AId, AKeyText, ACaption: string);
    procedure UpdateActive;
    procedure SetCountAlways(AValue: Boolean);
    function GetUsage: TAtlasCommandUsage;
    /// <summary>Titel des Tipps zum Befehl aus tips.json in der Sprache der IDE; '' ohne.</summary>
    function TipTitle(const AId: string): string;
  public
    /// <summary>AHolder: gemeinsame Zählung (#757), muss länger leben als die Tipps.</summary>
    constructor Create(AHolder: TAtlasIdeCommandUsage);
    destructor Destroy; override;
    /// <summary>Die laufenden Tipps oder nil.</summary>
    class function Instance: TAtlasIdeShortcutTips; static;
    /// <summary>Ein Befehl von Atlas oder eine Aktion wurde per Menü, Kontextmenü oder Befehlspalette aufgerufen
    /// (AId: Befehl der Palette bzw. Name der Aktion). Ohne laufende Tipps nichts.</summary>
    class procedure Invoked(const AId: string); static;
    /// <summary>Nutzung je Befehl für die Übersicht (#520); False ohne gemeinsame Zählung.</summary>
    class function UsageOf(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean; static;
    /// <summary>Taste einer Atlas-Funktion ohne Befehl der Befehlspalette (TAtlasShortcutTips.IsKeyOnly), für die
    /// Karte „Atlas entdecken“ (#757): die Taste, die Atlas gerade hält; bei Vervollständigung und Parameter-Hint
    /// ohne eigene Taste die der IDE (Code Insight). False, wenn AId keine solche Funktion ist.</summary>
    class function KeyOnlyText(const AId: string; out AKeyText: string): Boolean; static;
    /// <summary>Einstellungen geändert (shortcutTips.*, Tasten): Beobachtung an/aus, Tabelle neu.</summary>
    procedure ApplySettings;
    /// <summary>Packages geändert: Tabelle der Kürzel neu bauen.</summary>
    procedure KeysChanged;
    procedure ThemeChanged;
    property Usage: TAtlasCommandUsage read GetUsage;
    /// <summary>Zählen auch ohne shortcutTips.enabled (Karte „Atlas entdecken“, #757); Tipps nur mit.
    /// </summary>
    property CountAlways: Boolean read FCountAlways write SetCountAlways;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Messages,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ActnList,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.Tips,
  Atlas.UI.Popup.Window,
  Atlas.UI.Commands.KeyMap,
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Commands.Keys,
  Atlas.IDE.Commands.KeyMap;

function Ticks: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

/// <summary>Umschalttasten, die gerade gedrückt sind, als Bits wie in TShortCut.</summary>
function CurrentModifiers: Word;
begin
  Result := 0;
  if GetKeyState(VK_SHIFT) < 0 then
    Result := Result or TAtlasKeyConflicts.scShift;
  if GetKeyState(VK_CONTROL) < 0 then
    Result := Result or TAtlasKeyConflicts.scCtrl;
  if GetKeyState(VK_MENU) < 0 then
    Result := Result or TAtlasKeyConflicts.scAlt;
end;

/// <summary>Der Benutzer hat gerade etwas eingegeben (Maus oder Tastatur, auch im Menü).</summary>
function UserJustActed: Boolean;
var
  Info: TLastInputInfo;
begin
  Info.cbSize := SizeOf(Info);
  Info.dwTime := 0;
  if not GetLastInputInfo(Info) then
    Exit(True);
  Result := DWORD(GetTickCount - Info.dwTime) < DWORD(TAtlasIdeShortcutTips.UserInputMs);
end;

/// <summary>Angehaltene Debug-Sitzung (Haltepunkt, Ausnahme).</summary>
function DebugPaused: Boolean;
var
  Debugger: IOTADebuggerServices;
  Process: IOTAProcess;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Exit;
  Process := Debugger.CurrentProcess;
  Result := (Process <> nil) and (Process.ProcessState in [psStopped, psFault, psException]);
end;

/// <summary>Ein modaler Dialog ist offen (VCL-Formular oder ein Dialog, der das Hauptfenster sperrt).</summary>
function ModalOpen: Boolean;
var
  Index: Integer;
begin
  for Index := 0 to Screen.FormCount - 1 do
    if Screen.Forms[Index].Visible and (fsModal in Screen.Forms[Index].FormState) then
      Exit(True);
  Result := (Application.MainForm <> nil) and Application.MainForm.HandleAllocated and
    not IsWindowEnabled(Application.MainForm.Handle);
end;

/// <summary>Aktion der IDE mit diesem Namen; nil ohne.</summary>
function FindAction(const AName: string): TCustomAction;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := nil;
  if (AName = '') or not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
    if (Services.ActionList.Actions[Index] is TCustomAction) and
      SameText(Services.ActionList.Actions[Index].Name, AName) then
      Exit(TCustomAction(Services.ActionList.Actions[Index]));
end;

/// <summary>Aktion gehört Atlas (eigene Aktionslisten, Kategorie „Atlas“); die melden sich selbst.</summary>
function IsAtlasAction(AAction: TCustomAction): Boolean;
begin
  Result := SameText(AAction.Category, 'Atlas') or AAction.Category.StartsWith('Atlas.', True);
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
        Text := ShortCutToText(Child.ShortCut);
      if (Text <> '') and not AResult.ContainsKey(Child.Action) then
        AResult.Add(Child.Action, Text);
    end;
    if Child.Count > 0 then
      CollectMenuKeys(Child, AResult);
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
    CollectMenuKeys(Services.MainMenu.Items, Result);
  if not AEditorMenus or not Supports(BorlandIDEServices, INTAEditorServices, Editor) then
    Exit;
  Window := Editor.TopEditWindow;
  if (Window = nil) or (Window.Form = nil) then
    Exit;
  for Index := 0 to Window.Form.ComponentCount - 1 do
    if Window.Form.Components[Index] is TPopupMenu then
      CollectMenuKeys(TPopupMenu(Window.Form.Components[Index]).Items, Result);
end;

/// <summary>Kürzel einer Aktion als Text: Haupttaste, sonst die erste Zweittaste, sonst ein Kürzel aus einem Menü
/// (auch mit zwei Schritten); '' ohne.</summary>
function ActionKeyText(AAction: TCustomAction): string;
var
  Keys: TDictionary<TBasicAction, string>;
  Index: Integer;
begin
  if AAction.ShortCut <> 0 then
    Exit(ShortCutToText(AAction.ShortCut));
  for Index := 0 to AAction.SecondaryShortCuts.Count - 1 do
    if AAction.SecondaryShortCuts.ShortCuts[Index] <> 0 then
      Exit(ShortCutToText(AAction.SecondaryShortCuts.ShortCuts[Index]));
  Keys := MenuKeys(True);
  try
    if not Keys.TryGetValue(AAction, Result) then
      Result := '';
  finally
    Keys.Free;
  end;
end;

/// <summary>Beschriftung einer Aktion ohne Kürzelzeichen und Tab-Text; sonst ihr Name.</summary>
function ActionCaption(AAction: TCustomAction): string;
var
  Tab: Integer;
begin
  Result := AAction.Caption;
  Tab := Pos(#9, Result);
  if Tab > 0 then
    Result := Copy(Result, 1, Tab - 1);
  Result := TAtlasCommandPalette.CleanCaption(Result);
  if Result = '' then
    Result := AAction.Name;
end;

/// <summary>Taste der Atlas-Funktion als Text, wenn Atlas sie hält (frei oder mit Vorrang, #494); sonst '', auch
/// wenn die Funktion abgeschaltet ist (Suchfeld der Willkommensseite aus, #775 aus, „Units suchen“ aus).
/// Immer aus den aktuellen Einstellungen: nach einer Neubelegung sofort die neue.</summary>
function AtlasKeyText(AFunc: TAtlasKeyFunction): string;
var
  Entry: TAtlasKeyEntry;
begin
  Result := '';
  for Entry in TAtlasIdeKeyMap.AtlasEntries do
    if Entry.Func = AFunc then
    begin
      // Das Suchfeld der Willkommensseite hat immer Vorrang; dort gibt es keinen Aufruf per Maus.
      if (Entry.Key <> 0) and not Entry.Disabled and
        TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority) then
        Result := ShortCutToText(TShortCut(Entry.Key));
      Exit;
    end;
end;

/// <summary>Taste eines Atlas-Befehls: unter mehreren Tasten für denselben Befehl (#775 zwei Tasten, #777 eigene
/// Taste und Strg+F12) die erste, die Atlas hält; AFunc bekommt deren Funktion.</summary>
function AtlasCommandKeyText(const AId: string; var AFunc: TAtlasKeyFunction): string;
var
  Func: TAtlasKeyFunction;
begin
  Result := '';
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
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

/// <summary>Fläche für den Tipp: das Editorfenster (Editor-Steuerelement, sonst das Fenster), sonst das
/// Hauptfenster.</summary>
function TipArea: TRect;
var
  Services: INTAEditorServices;
  Window: INTAEditWindow;
  Editor: TComponent;
  Control: TWinControl;
begin
  Control := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, Services) then
  begin
    Window := Services.TopEditWindow;
    if (Window <> nil) and (Window.Form <> nil) and Window.Form.Visible then
    begin
      Editor := Window.Form.FindComponent('Editor');
      if (Editor is TWinControl) and TWinControl(Editor).Showing then
        Control := TWinControl(Editor)
      else
        Control := Window.Form;
    end;
  end;
  if (Control = nil) and (Application.MainForm <> nil) then
    Control := Application.MainForm;
  if (Control = nil) or not Control.HandleAllocated then
    Exit(Screen.WorkAreaRect);
  Result.TopLeft := Control.ClientToScreen(Point(0, 0));
  Result.BottomRight := Control.ClientToScreen(Point(Control.ClientWidth, Control.ClientHeight));
end;

{ TAtlasIdeShortcutTips }

constructor TAtlasIdeShortcutTips.Create(AHolder: TAtlasIdeCommandUsage);
begin
  inherited Create;
  FInstance := Self;
  FHolder := AHolder;
  FKeys := TDictionary<string, TArray<string>>.Create;
  FLearned := TDictionary<string, string>.Create;
  FEvents := TApplicationEvents.Create(nil);
  UpdateActive;
end;

destructor TAtlasIdeShortcutTips.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FEvents);
  FreeAndNil(FWindow);
  // Gespeichert wird von der gemeinsamen Zählung (#757), die länger lebt.
  FKeys.Free;
  FLearned.Free;
  inherited;
end;

class function TAtlasIdeShortcutTips.Instance: TAtlasIdeShortcutTips;
begin
  Result := FInstance;
end;

function TAtlasIdeShortcutTips.GetUsage: TAtlasCommandUsage;
begin
  Result := FHolder.Usage;
end;

function TAtlasIdeShortcutTips.TipTitle(const AId: string): string;
var
  Tip: TAtlasTip;
begin
  Result := '';
  if TAtlasTipCatalog.FindByCommand(FHolder.Tips, AId, Tip) then
    Result := Tip.TitleIn(TAtlasStrings.Language = TAtlasLanguage.English);
end;

class procedure TAtlasIdeShortcutTips.Invoked(const AId: string);
begin
  if (FInstance = nil) or not FInstance.FActive or (Trim(AId) = '') or
    TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) then
    Exit;
  try
    FInstance.FExplicitId := AId;
    FInstance.FExplicitAt := Ticks;
    FInstance.MouseUse(AId);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

class function TAtlasIdeShortcutTips.KeyOnlyText(const AId: string; out AKeyText: string): Boolean;
var
  Func: TAtlasKeyFunction;
  Entry: TAtlasKeyEntry;
begin
  AKeyText := '';
  Result := TAtlasShortcutTips.IsKeyOnly(AId, Func);
  if not Result then
    Exit;
  AKeyText := AtlasKeyText(Func);
  if AKeyText <> '' then
    Exit;
  // Vervollständigung und Parameter-Hint ohne eigene Taste laufen über Code Insight mit der Taste der IDE.
  for Entry in TAtlasKeyEntry.AllFromSettings(TAtlasIdeSettings.Current) do
    if (Entry.Func = Func) and (Entry.Key = 0) and (Entry.IdeKey <> 0) then
    begin
      AKeyText := ShortCutToText(TShortCut(Entry.IdeKey));
      Exit;
    end;
end;

class function TAtlasIdeShortcutTips.UsageOf(const AId: string; out AEntry: TAtlasCommandUsageEntry): Boolean;
begin
  AEntry := TAtlasCommandUsageEntry.Create(AId);
  Result := (TAtlasIdeCommandUsage.Instance <> nil) and TAtlasIdeCommandUsage.Instance.Usage.Find(AId, AEntry);
end;

procedure TAtlasIdeShortcutTips.UpdateActive;
var
  Active: Boolean;
begin
  Active := (TAtlasIdeSettings.Current.ShortcutTips or FCountAlways) and
    not TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips);
  if Active = FActive then
    Exit;
  FActive := Active;
  if FActive then
  begin
    FEvents.OnMessage := AppMessage;
    FEvents.OnActionExecute := AppActionExecute;
  end
  else
  begin
    FEvents.OnMessage := nil;
    FEvents.OnActionExecute := nil;
    if FWindow <> nil then
      FWindow.Dismiss;
  end;
  // Anonym: nur der Zustand.
  TAtlasGuard.Log(Format('Tastenkürzel-Tipps (#600): Beobachtung %s', [BoolToStr(FActive, True)]));
end;

procedure TAtlasIdeShortcutTips.SetCountAlways(AValue: Boolean);
begin
  FCountAlways := AValue;
  UpdateActive;
end;

procedure TAtlasIdeShortcutTips.ApplySettings;
begin
  FKeysBuiltAt := 0;
  UpdateActive;
  if (FWindow <> nil) and not TAtlasIdeSettings.Current.ShortcutTips then
    FWindow.Dismiss;
end;

procedure TAtlasIdeShortcutTips.KeysChanged;
begin
  FKeysBuiltAt := 0;
end;

procedure TAtlasIdeShortcutTips.ThemeChanged;
begin
  if (FWindow <> nil) and FWindow.IsShown then
  begin
    FWindow.Colors := TAtlasIdeStyle.Colors;
    FWindow.Invalidate;
  end;
end;

procedure TAtlasIdeShortcutTips.Changed;
begin
  // Gesammelt speichern: nicht bei jedem Klick auf die Platte.
  FHolder.Changed;
end;

procedure TAtlasIdeShortcutTips.Save;
begin
  FHolder.SaveNow;
end;

procedure TAtlasIdeShortcutTips.AddKeys(AShortCut: Word; const AId: string);
var
  Key: string;
  Ids: TArray<string>;
begin
  if (AShortCut = 0) or (AId = '') then
    Exit;
  Key := TAtlasShortcutTips.StepsKey([AShortCut]);
  if not FKeys.TryGetValue(Key, Ids) then
    Ids := nil;
  FKeys.AddOrSetValue(Key, Ids + [AId]);
end;

procedure TAtlasIdeShortcutTips.AddKeys(const AKeyText, AId: string);
var
  Steps: TArray<Word>;
  Key: string;
  Ids: TArray<string>;
begin
  Steps := TAtlasShortcutTips.ParseSteps(AKeyText);
  if (Length(Steps) = 0) or (AId = '') then
    Exit;
  Key := TAtlasShortcutTips.StepsKey(Steps);
  if not FKeys.TryGetValue(Key, Ids) then
    Ids := nil;
  FKeys.AddOrSetValue(Key, Ids + [AId]);
end;

procedure TAtlasIdeShortcutTips.EnsureKeys;
var
  Services: INTAServices;
  Index, Secondary: Integer;
  Action: TCustomAction;
  Func: TAtlasKeyFunction;
  Menu: TDictionary<TBasicAction, string>;
  Pair: TPair<TBasicAction, string>;
  Learned: TPair<string, string>;
  Key: Word;
begin
  if (FKeysBuiltAt <> 0) and (Ticks - FKeysBuiltAt < KeysMaxAgeMs) then
    Exit;
  FKeysBuiltAt := Ticks;
  FKeys.Clear;
  // Atlas-Tasten, die Atlas tatsächlich hält.
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
    AddKeys(AtlasKeyText(Func), TAtlasShortcutTips.AtlasCommandId(Func));
  // Beim Aufruf gelernte Kürzel (Aktionen des Editor-Kontextmenüs).
  for Learned in FLearned do
    AddKeys(Learned.Value, Learned.Key);
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    if not (Services.ActionList.Actions[Index] is TCustomAction) then
      Continue;
    Action := TCustomAction(Services.ActionList.Actions[Index]);
    if (Action.Name = '') or IsAtlasAction(Action) then
      Continue;
    AddKeys(Word(Action.ShortCut), Action.Name);
    for Secondary := 0 to Action.SecondaryShortCuts.Count - 1 do
    begin
      Key := Word(Action.SecondaryShortCuts.ShortCuts[Secondary]);
      if Key <> Word(Action.ShortCut) then
        AddKeys(Key, Action.Name);
    end;
  end;
  // Kürzel mit zwei Schritten stehen nur in den Menübeschriftungen.
  Menu := MenuKeys(False);
  try
    for Pair in Menu do
      if (Pair.Key is TCustomAction) and (TCustomAction(Pair.Key).Name <> '') and
        (TCustomAction(Pair.Key).ShortCut = 0) and not IsAtlasAction(TCustomAction(Pair.Key)) then
        AddKeys(Pair.Value, TCustomAction(Pair.Key).Name);
  finally
    Menu.Free;
  end;
end;

procedure TAtlasIdeShortcutTips.KeyStroke(AShortCut: Word; AChordOnly: Boolean);
var
  Ids: TArray<string>;
  Id: string;
  Now_: TDateTime;
begin
  EnsureKeys;
  Ids := nil;
  if AChordOnly or not FKeys.TryGetValue(TAtlasShortcutTips.StepsKey([AShortCut]), Ids) then
    Ids := nil;
  // Zweiter Schritt eines Kürzels mit zwei Schritten.
  if (FPrevKey <> 0) and (Ticks - FPrevAt < TAtlasShortcutTips.ChordMs) and
    FKeys.ContainsKey(TAtlasShortcutTips.StepsKey([FPrevKey, AShortCut])) then
    Ids := Ids + FKeys[TAtlasShortcutTips.StepsKey([FPrevKey, AShortCut])];
  FPrevKey := AShortCut;
  FPrevAt := Ticks;
  if Length(Ids) = 0 then
    Exit;
  Now_ := Now;
  for Id in Ids do
    Usage.Count(Id, TAtlasCommandInput.Keyboard, Now_);
  Changed;
end;

procedure TAtlasIdeShortcutTips.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
  ShortCut: Word;
begin
  if (Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN) then
    Exit;
  // Von der Sicherung abgeschaltet (#493): nichts mehr beobachten.
  if TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) then
    Exit;
  try
    // Jede Taste schließt den Tipp.
    if (FWindow <> nil) and FWindow.IsShown then
      FWindow.Dismiss;
    // Wiederholung beim Festhalten zählt nicht.
    if (Msg.lParam and $40000000) <> 0 then
      Exit;
    Key := Word(Msg.wParam);
    if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) or (Key = VK_LWIN) or (Key = VK_RWIN) or
      (Key = VK_CAPITAL) then
      Exit;
    ShortCut := (Key and $FF) or CurrentModifiers;
    if not TAtlasShortcutTips.IsShortCutStroke(ShortCut) then
    begin
      // Zweiter Schritt ohne Umschalttaste („Strg+K, D“).
      if (FPrevKey <> 0) and (Ticks - FPrevAt < TAtlasShortcutTips.ChordMs) then
        KeyStroke(ShortCut, True)
      else
        FPrevKey := 0;
      Exit;
    end;
    KeyStroke(ShortCut, False);
  except
    // Die Taste geht in jedem Fall an die IDE (Handled bleibt False).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

/// <summary>Wurde AAction gerade über eines ihrer Kürzel ausgelöst? Taste und Umschalttasten jetzt gedrückt bzw.
/// eben gedrückt (APrevKey vor weniger als ChordMs).</summary>
function ViaShortCut(AAction: TCustomAction; APrevKey: Word; APrevAge: UInt64): Boolean;

  function Matches(AShortCut: Word): Boolean;
  var
    Key: Word;
  begin
    Result := False;
    if AShortCut = 0 then
      Exit;
    Key := AShortCut and $FF;
    if (GetKeyState(Key) < 0) and ((AShortCut and TAtlasKeyMap.ModifierMask) = CurrentModifiers) then
      Exit(True);
    Result := (APrevKey = AShortCut) and (APrevAge < TAtlasShortcutTips.ChordMs);
  end;

var
  Index: Integer;
begin
  if Matches(Word(AAction.ShortCut)) then
    Exit(True);
  for Index := 0 to AAction.SecondaryShortCuts.Count - 1 do
    if Matches(Word(AAction.SecondaryShortCuts.ShortCuts[Index])) then
      Exit(True);
  Result := False;
end;

procedure TAtlasIdeShortcutTips.AppActionExecute(Action: TBasicAction; var Handled: Boolean);
var
  Item: TCustomAction;
begin
  // Handled bleibt False: Die Aktion läuft wie immer.
  if TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) then
    Exit;
  try
    if not (Action is TCustomAction) then
      Exit;
    Item := TCustomAction(Action);
    // Namenlose Aktionen und die von Atlas (Kontextmenü, #399) melden sich selbst bzw. zählen nicht.
    if (Item.Name = '') or IsAtlasAction(Item) then
      Exit;
    // Von der Befehlspalette schon gemeldet.
    if SameText(Item.Name, FExplicitId) and (Ticks - FExplicitAt < ExplicitMs) then
      Exit;
    // Über das Kürzel: zählt schon AppMessage.
    if ViaShortCut(Item, FPrevKey, Ticks - FPrevAt) then
      Exit;
    // Aufrufe der IDE aus dem Programm heraus, ohne Eingabe des Benutzers, zählen nicht.
    if not UserJustActed then
      Exit;
    // Kürzel und Beschriftung jetzt, von der Aktion selbst: Sie steht nicht immer in INTAServices.ActionList.
    MouseUse(Item.Name, ActionKeyText(Item), ActionCaption(Item));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

procedure TAtlasIdeShortcutTips.MouseUse(const AId: string);
begin
  Usage.Count(AId, TAtlasCommandInput.Mouse, Now);
  Changed;
  Queue(AId, '', '', False);
end;

procedure TAtlasIdeShortcutTips.MouseUse(const AId, AKeyText, ACaption: string);
begin
  Usage.Count(AId, TAtlasCommandInput.Mouse, Now);
  Changed;
  // Kürzel außerhalb der Aktionsliste der IDE für die Tastatur merken.
  if (AKeyText <> '') and (FindAction(AId) = nil) then
  begin
    FLearned.AddOrSetValue(AId, AKeyText);
    FKeysBuiltAt := 0;
  end;
  Queue(AId, AKeyText, ACaption, True);
end;

procedure TAtlasIdeShortcutTips.Queue(const AId, AKeyText, ACaption: string; AKnown: Boolean);
var
  Id, KeyText, Caption: string;
  Known: Boolean;
begin
  if not TAtlasIdeSettings.Current.ShortcutTips then
    Exit;
  // Erst nach der Aktion: Sie kann einen modalen Dialog öffnen (dann kein Tipp) oder das Editorfenster wechseln.
  Id := AId;
  KeyText := AKeyText;
  Caption := ACaption;
  Known := AKnown;
  TAtlasMainThread.ForceQueue(TAtlasFeature.ShortcutTips,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
        procedure
        begin
          if FInstance = nil then
            Exit;
          if Known then
            FInstance.Consider(Id, KeyText, Caption, False)
          else
            FInstance.Consider(Id);
        end);
    end);
end;

procedure TAtlasIdeShortcutTips.Consider(const AId: string);
var
  Func: TAtlasKeyFunction;
  Action: TCustomAction;
  KeyText: string;
begin
  if TAtlasShortcutTips.AtlasFunctionOf(AId, Func) then
  begin
    KeyText := AtlasCommandKeyText(AId, Func);
    Consider(AId, KeyText, TAtlasKeyMapWindow.FunctionCaption(Func), True);
  end
  else if AId.StartsWith('Atlas.', True) then
    // Befehl von Atlas ohne eigene Taste: kein Tipp, aber dieselbe Prüfung.
    Consider(AId, '', '', True)
  else
  begin
    // Aktion der IDE aus der Befehlspalette.
    Action := FindAction(AId);
    if Action <> nil then
      Consider(AId, ActionKeyText(Action), ActionCaption(Action), IsAtlasAction(Action))
    else
      Consider(AId, '', '', False);
  end;
end;

procedure TAtlasIdeShortcutTips.Consider(const AId, AKeyText, ACaption: string; AIsAtlas: Boolean);
var
  Settings: TAtlasPluginSettings;
  Situation: TAtlasTipSituation;
  KeyText, Caption: string;
  Verdict: TAtlasTipVerdict;
begin
  Settings := TAtlasIdeSettings.Current;
  KeyText := AKeyText;
  // Dieselbe Tippquelle wie „Atlas entdecken“ (#757): Titel aus tips.json, sonst der Aktion.
  Caption := TipTitle(AId);
  if Caption = '' then
    Caption := ACaption;
  if Caption = '' then
    Caption := AId;
  Situation := TAtlasTipSituation.Create(Settings.ShortcutTips, TAtlasShortcutTips.ScopeOf(Settings.ShortcutTipsScope),
    AIsAtlas, KeyText, Now);
  Situation.LastTipAt := FLastTipAt;
  // Nur, wo es darauf ankommt: Die Abfrage des Debuggers ist billig, aber nicht umsonst.
  if KeyText <> '' then
  begin
    Situation.DebugPaused := DebugPaused;
    Situation.ModalOpen := ModalOpen;
  end;
  Verdict := TAtlasShortcutTips.Decide(Usage.Entry(AId), Situation);
  if Verdict = TAtlasTipVerdict.Show then
    ShowTip(AId, KeyText, Caption);
end;

procedure TAtlasIdeShortcutTips.ShowTip(const AId, AKeyText, ACaption: string);
var
  Entry: TAtlasCommandUsageEntry;
  Area: TRect;
  Editor: IOTAEditorServices;
  FontName: string;
  FontSize: Integer;
begin
  if FWindow = nil then
  begin
    FWindow := TAtlasShortcutTipWindow.Create(nil);
    FWindow.OnNever := NeverClick;
    FWindow.OnAllKeys := AllKeysClick;
  end;
  Area := TipArea;
  FontName := FWindow.Font.Name;
  FontSize := 10;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) and (Editor.EditOptions <> nil) then
  begin
    FontName := Editor.EditOptions.FontName;
    FontSize := Editor.EditOptions.FontSize;
  end;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(Area.CenterPoint), 1, FontName, FontSize);
  FWindow.ShowTip(TAtlasShortcutTipView.Create(AKeyText, ACaption, TAtlasIdeSettings.Current.KeyOverview), Area);
  FTipId := AId;
  FLastTipAt := Now;
  Entry := Usage.Entry(AId);
  TAtlasShortcutTips.MarkShown(Entry, FLastTipAt);
  Usage.Put(Entry);
  Changed;
  // Anonym: kein Dateiname, kein Quelltext.
  TAtlasGuard.Log('Tastenkürzel-Tipp gezeigt (#600)');
end;

procedure TAtlasIdeShortcutTips.NeverClick(Sender: TObject);
var
  Entry: TAtlasCommandUsageEntry;
begin
  TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
    procedure
    begin
      if FTipId = '' then
        Exit;
      Entry := Usage.Entry(FTipId);
      Entry.Never := True;
      Usage.Put(Entry);
      // Gleich sichern: Die Wahl soll auch einen Absturz überstehen.
      Save;
    end);
end;

procedure TAtlasIdeShortcutTips.AllKeysClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
    procedure
    begin
      if TAtlasIdeKeyMap.Instance <> nil then
        TAtlasIdeKeyMap.Instance.ShowAll;
    end);
end;

end.
