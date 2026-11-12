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
//   letzte Taste (TAtlasShortcutTips.cChordMs); sonst per Maus. Nur bei einer
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
// Benachrichtigungszentrale (#601, Quelle shortcutTips): Jeder Tipp ist auch
// ein Eintrag mit „Alle Kürzel“ und „Nicht mehr zeigen“; „nur sammeln“ zeigt
// kein Fenster (der Tipp gilt trotzdem als gezeigt), „aus“ unterdrückt ihn.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.AppEvnts,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Notifications.Contract,
  Atlas.UI.Commands.ShortcutTip,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutKeys;

type
  /// <summary>Tipps und Zählung; Tabelle der Kürzel und Merker zum Aufrufweg in TAtlasIdeShortcutKeys.</summary>
  TAtlasIdeShortcutTips = class(TAtlasIdeShortcutKeys)
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
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure AppActionExecute(Action: TBasicAction; var Handled: Boolean);
    procedure NeverClick(Sender: TObject);
    procedure AllKeysClick(Sender: TObject);
    /// <summary>„Nicht mehr zeigen“ für den Tipp zu AId (Fenster und Benachrichtigung).</summary>
    procedure SetNever(const AId: string);
    /// <summary>Aktionen des Eintrags in der Benachrichtigungszentrale (#601).</summary>
    class function TipActions(const AId: string): TArray<TAtlasNotificationAction>; static;
    procedure Changed;
    procedure Save;
    /// <summary>Aufrufe über die Tastatur zählen.</summary>
    procedure CountKeys(const AIds: TArray<string>);
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
  Atlas.Core.Commands.ShortcutTips,
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Messages,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ActnList,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.Tips,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Popup.Window,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Commands.KeyMap;

/// <summary>Angehaltene Debug-Sitzung (Haltepunkt, Ausnahme).</summary>
function DebugPaused: Boolean;
var
  mDebugger: IOTADebuggerServices;
  mProcess: IOTAProcess;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  mProcess := mDebugger.CurrentProcess;
  Result := (mProcess <> nil) and (mProcess.ProcessState in [psStopped, psFault, psException]);
end;

/// <summary>Ein modaler Dialog ist offen (VCL-Formular oder ein Dialog, der das Hauptfenster sperrt).</summary>
function ModalOpen: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Screen.FormCount - 1 do
  begin
    if Screen.Forms[mIndex].Visible and (fsModal in Screen.Forms[mIndex].FormState) then
    begin
      Exit(True);
    end;
  end;
  Result := (Application.MainForm <> nil) and Application.MainForm.HandleAllocated and
    not IsWindowEnabled(Application.MainForm.Handle);
end;

/// <summary>Fläche für den Tipp: das Editorfenster (Editor-Steuerelement, sonst das Fenster), sonst das
/// Hauptfenster.</summary>
function TipArea: TRect;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
  mEditor: TWinControl;
  mControl: TWinControl;
begin
  mControl := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    mWindow := mServices.TopEditWindow;
    if (mWindow <> nil) and (mWindow.Form <> nil) and mWindow.Form.Visible then
    begin
      mEditor := TAtlasEditorBarHost.EditorOf(mWindow);
      if (mEditor <> nil) and mEditor.Showing then
      begin
        mControl := mEditor;
      end
      else
      begin
        mControl := mWindow.Form;
      end;
    end;
  end;
  if (mControl = nil) and (Application.MainForm <> nil) then
  begin
    mControl := Application.MainForm;
  end;
  if (mControl = nil) or not mControl.HandleAllocated then
  begin
    Exit(Screen.WorkAreaRect);
  end;
  Result.TopLeft := mControl.ClientToScreen(Point(0, 0));
  Result.BottomRight := mControl.ClientToScreen(Point(mControl.ClientWidth, mControl.ClientHeight));
end;

{ TAtlasIdeShortcutTips }

constructor TAtlasIdeShortcutTips.Create(AHolder: TAtlasIdeCommandUsage);
begin
  inherited Create;
  FInstance := Self;
  FHolder := AHolder;
  FEvents := TApplicationEvents.Create(nil);
  UpdateActive;
end;

destructor TAtlasIdeShortcutTips.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FEvents);
  FreeAndNil(FWindow);
  // Gespeichert wird von der gemeinsamen Zählung (#757), die länger lebt.
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
  mTip: TAtlasTip;
begin
  Result := '';
  if TAtlasTipCatalog.FindByCommand(FHolder.Tips, AId, mTip) then
  begin
    Result := mTip.TitleIn(TAtlasStrings.Language = TAtlasLanguage.English);
  end;
end;

class procedure TAtlasIdeShortcutTips.Invoked(const AId: string);
begin
  if (FInstance = nil) or not FInstance.FActive or (Trim(AId) = '') or
    TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) then
  begin
    Exit;
  end;
  try
    FInstance.Explicit(AId);
    FInstance.MouseUse(AId);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

class function TAtlasIdeShortcutTips.KeyOnlyText(const AId: string; out AKeyText: string): Boolean;
begin
  Result := TAtlasIdeActionKeys.KeyOnlyText(AId, AKeyText);
end;

procedure TAtlasIdeShortcutTips.UpdateActive;
var
  mActive: Boolean;
begin
  mActive := (TAtlasIdeSettings.Current.ShortcutTips or FCountAlways) and
    not TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips);
  if mActive = FActive then
  begin
    Exit;
  end;
  FActive := mActive;
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
    begin
      FWindow.Dismiss;
    end;
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
  ResetKeys;
  UpdateActive;
  if (FWindow <> nil) and not TAtlasIdeSettings.Current.ShortcutTips then
  begin
    FWindow.Dismiss;
  end;
end;

procedure TAtlasIdeShortcutTips.KeysChanged;
begin
  ResetKeys;
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

procedure TAtlasIdeShortcutTips.CountKeys(const AIds: TArray<string>);
var
  mId: string;
  mNow: TDateTime;
begin
  if Length(AIds) = 0 then
  begin
    Exit;
  end;
  mNow := Now;
  for mId in AIds do
  begin
    Usage.Count(mId, TAtlasCommandInput.Keyboard, mNow);
  end;
  Changed;
end;

procedure TAtlasIdeShortcutTips.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  // Von der Sicherung abgeschaltet (#493): nichts mehr beobachten.
  if ((Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN)) or
    TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) then
  begin
    Exit;
  end;
  try
    // Jede Taste schließt den Tipp.
    if (FWindow <> nil) and FWindow.IsShown then
    begin
      FWindow.Dismiss;
    end;
    CountKeys(Stroke(Msg));
  except
    // Die Taste geht in jedem Fall an die IDE (Handled bleibt False).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

procedure TAtlasIdeShortcutTips.AppActionExecute(Action: TBasicAction; var Handled: Boolean);
var
  mItem: TCustomAction;
begin
  // Handled bleibt False: Die Aktion läuft wie immer.
  if TAtlasGuard.Disabled(TAtlasFeature.ShortcutTips) or not (Action is TCustomAction) then
  begin
    Exit;
  end;
  try
    mItem := TCustomAction(Action);
    // Kürzel und Beschriftung jetzt, von der Aktion selbst: Sie steht nicht immer in INTAServices.ActionList.
    if CountsAsMouseUse(mItem) then
    begin
      MouseUse(mItem.Name, TAtlasIdeActionKeys.ActionKeyText(mItem), TAtlasIdeActionKeys.ActionCaption(mItem));
    end;
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
  Learn(AId, AKeyText);
  Queue(AId, AKeyText, ACaption, True);
end;

procedure TAtlasIdeShortcutTips.Queue(const AId, AKeyText, ACaption: string; AKnown: Boolean);
var
  mId, mKeyText, mCaption: string;
  mKnown: Boolean;
begin
  if not TAtlasIdeSettings.Current.ShortcutTips then
  begin
    Exit;
  end;
  // Erst nach der Aktion: Sie kann einen modalen Dialog öffnen (dann kein Tipp) oder das Editorfenster wechseln.
  mId := AId;
  mKeyText := AKeyText;
  mCaption := ACaption;
  mKnown := AKnown;
  TAtlasMainThread.ForceQueue(TAtlasFeature.ShortcutTips,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
        procedure
        begin
          if FInstance = nil then
          begin
            Exit;
          end;
          if mKnown then
          begin
            FInstance.Consider(mId, mKeyText, mCaption, False);
          end
          else
          begin
            FInstance.Consider(mId);
          end;
        end);
    end);
end;

procedure TAtlasIdeShortcutTips.Consider(const AId: string);
var
  mKeyText, mCaption: string;
  mIsAtlas: Boolean;
begin
  TAtlasIdeActionKeys.Describe(AId, mKeyText, mCaption, mIsAtlas);
  Consider(AId, mKeyText, mCaption, mIsAtlas);
end;

procedure TAtlasIdeShortcutTips.Consider(const AId, AKeyText, ACaption: string; AIsAtlas: Boolean);
var
  mSettings: TAtlasPluginSettings;
  mSituation: TAtlasTipSituation;
  mKeyText, mCaption: string;
  mVerdict: TAtlasTipVerdict;
begin
  mSettings := TAtlasIdeSettings.Current;
  mKeyText := AKeyText;
  // Dieselbe Tippquelle wie „Atlas entdecken“ (#757): Titel aus tips.json, sonst der Aktion.
  mCaption := TipTitle(AId);
  if mCaption = '' then
  begin
    mCaption := ACaption;
  end;
  if mCaption = '' then
  begin
    mCaption := AId;
  end;
  mSituation := TAtlasTipSituation.Create(mSettings.ShortcutTips,
    TAtlasShortcutTips.ScopeOf(mSettings.ShortcutTipsScope),
    AIsAtlas, mKeyText, Now);
  mSituation.LastTipAt := FLastTipAt;
  // Nur, wo es darauf ankommt: Die Abfrage des Debuggers ist billig, aber nicht umsonst.
  if mKeyText <> '' then
  begin
    mSituation.DebugPaused := DebugPaused;
    mSituation.ModalOpen := ModalOpen;
  end;
  mVerdict := TAtlasShortcutTips.Decide(Usage.Entry(AId), mSituation);
  if mVerdict = TAtlasTipVerdict.Show then
  begin
    ShowTip(AId, mKeyText, mCaption);
  end;
end;

class function TAtlasIdeShortcutTips.TipActions(const AId: string): TArray<TAtlasNotificationAction>;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.KeyOverview then
  begin
    Result := [TAtlasNotificationCenter.Action(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.ShortcutTipAllKeys),
      procedure
      begin
        if TAtlasIdeKeyMap.Instance <> nil then
        begin
          TAtlasIdeKeyMap.Instance.ShowAll;
        end;
      end)];
  end;
  Result := Result + [TAtlasNotificationCenter.Action(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.ShortcutTipNever),
    procedure
    begin
      // Die Tipps können inzwischen beendet sein: nur über die laufende Instanz.
      if FInstance <> nil then
      begin
        FInstance.SetNever(AId);
      end;
    end)];
end;

procedure TAtlasIdeShortcutTips.ShowTip(const AId, AKeyText, ACaption: string);
var
  mEntry: TAtlasCommandUsageEntry;
  mArea: TRect;
  mEditor: IOTAEditorServices;
  mFontName: string;
  mFontSize: Integer;
  mMode: TAtlasNotificationMode;
begin
  // Benachrichtigungszentrale (#601): „nur sammeln“ zeigt kein Fenster, „aus“ unterdrückt den Tipp ganz.
  mMode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cShortcutTips,
    TAtlasNotificationSeverity.Info, TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.NotificationsTipTitle, [AKeyText]),
    TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.NotificationsTipText, [ACaption, AKeyText]), TipActions(AId));
  if mMode = TAtlasNotificationMode.Off then
  begin
    Exit;
  end;
  if mMode = TAtlasNotificationMode.Show then
  begin
    if FWindow = nil then
    begin
      FWindow := TAtlasShortcutTipWindow.Create(nil);
      FWindow.OnNever := NeverClick;
      FWindow.OnAllKeys := AllKeysClick;
    end;
    mArea := TipArea;
    mFontName := FWindow.Font.Name;
    mFontSize := 10;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
    begin
      mFontName := mEditor.EditOptions.FontName;
      mFontSize := mEditor.EditOptions.FontSize;
    end;
    FWindow.Colors := TAtlasIdeStyle.Colors;
    FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.CenterPoint), 1, mFontName, mFontSize);
    FWindow.ShowTip(TAtlasShortcutTipView.Create(AKeyText, ACaption, TAtlasIdeSettings.Current.KeyOverview), mArea);
  end;
  FTipId := AId;
  FLastTipAt := Now;
  mEntry := Usage.Entry(AId);
  TAtlasShortcutTips.MarkShown(mEntry, FLastTipAt);
  Usage.Put(mEntry);
  Changed;
  // Anonym: kein Dateiname, kein Quelltext.
  TAtlasGuard.Log('Tastenkürzel-Tipp gezeigt (#600)');
end;

procedure TAtlasIdeShortcutTips.NeverClick(Sender: TObject);
begin
  SetNever(FTipId);
end;

procedure TAtlasIdeShortcutTips.SetNever(const AId: string);
var
  mEntry: TAtlasCommandUsageEntry;
  mId: string;
begin
  mId := AId;
  TAtlasGuard.Run(TAtlasFeature.ShortcutTips,
    procedure
    begin
      if mId = '' then
      begin
        Exit;
      end;
      mEntry := Usage.Entry(mId);
      mEntry.Never := True;
      Usage.Put(mEntry);
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
      begin
        TAtlasIdeKeyMap.Instance.ShowAll;
      end;
    end);
end;

end.
