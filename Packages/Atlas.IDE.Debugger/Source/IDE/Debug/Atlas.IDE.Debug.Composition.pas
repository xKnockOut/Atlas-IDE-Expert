unit Atlas.IDE.Debug.Composition;

// Modul Debugger (#1455, ADR 0017): einzige Unit, die die Teile des
// Debuggers erzeugt. Sie meldet in ihrer Initialisierung das Modul
// „atlas.debugger“ (Modulschalter debug, #1454) bei der Registry von Base an
// und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (Visualisierer, eigene Darstellungen,
//   Exception-Verlauf und -Leiste, nur eigener Code, Werte im Editor,
//   „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
//   Debugger-Dialogen, Fenster „Auswerten“, Schrittfilter),
// - Befehle (Palette), Einträge im Atlas-Menü und im Kontextmenü des Editors,
//   die Taste von „Gezielt hineinspringen“,
// - Hörer für Einstellungen, Thema und Ansichtswechsel sowie die Werte im
//   Tooltip,
// - für andere Module den Bericht über die Debug-Sitzung
//   (IAtlasDebugReportSource, Atlas.IDE.Contracts).
// Das erste Teil („DebugCommands“, ab dem abgesicherten Start) installiert
// „Gezielt hineinspringen“, „Beim nächsten Ereignis anhalten“ und die Befehle
// des Schrittfilters; es stoppt als letztes, nimmt sie zurück und hängt F7 ab
// (Trace). Start und Stop des Moduls selbst tun nichts weiter. Abmelden in der Finalisierung, solange Base
// läuft (Regel 5); passt die Vertragsversion von Base nicht, meldet sich das
// Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasDebugModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource, IAtlasKeySource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasFollowsEditorView, IAtlasHoverValueSource)
  public const
    ModuleId = 'atlas.debugger';
    Switch = 'debug';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
    procedure EditorViewActivated;
    function HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Status.Registry,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Providers.Expression,
  Atlas.Core.Completion.Providers.Server,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.InlineValues,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.DialogCompletion,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.DisplayRules,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Debug.EventBreak,
  Atlas.IDE.Debug.Trace,
  Atlas.IDE.Debug.StepFilter,
  Atlas.IDE.Debug.Report,
  Atlas.IDE.Contracts.DebugReport,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

var
  GScope: IAtlasModuleScope;
  GCommandsInstalled: Boolean;

{ Dienste von Base }

function Session: TLspSession;
begin
  Result := TAtlasIdeHost.RunningSession;
end;

procedure MessageLine(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure LogLine(AText: string);
begin
  TAtlasIdeHost.Log(AText);
end;

{ Sichtbarkeit und Bedingungen }

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

function DebugExceptionBarVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory and TAtlasIdeSettings.Current.DebugExceptionBanner;
end;

function DebugExceptionsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory;
end;

function DebugEvaluateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugEvaluateWindow;
end;

function StepIntoTargetVisible: Boolean;
begin
  Result := TAtlasIdeStepInto.Enabled;
end;

function BreakOnNextEventVisible: Boolean;
begin
  Result := TAtlasIdeEventBreak.Enabled;
end;

function StepFilterRunning: Boolean;
begin
  Result := TAtlasIdeDebugStepFilter.Started;
end;

/// <summary>Taste von „Gezielt hineinspringen“ (#836); 0, solange debug.stepIntoTarget aus ist.</summary>
function StepIntoTargetKey: Integer;
begin
  Result := 0;
  if TAtlasIdeSettings.Current.DebugStepIntoTarget then
    Result := TAtlasIdeSettings.Current.DebugStepIntoTargetKey;
end;

/// <summary>Taste von „Gezielt hineinspringen“ unter der Sicherung des Debuggers (#493): nur im angehaltenen
/// Zustand; sonst (und nach einem Fehler) geht die Taste an die IDE.</summary>
function TryStepInto: Boolean;
var
  mDone: Boolean;
begin
  mDone := False;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      mDone := TAtlasIdeStepInto.TryRun;
    end);
  Result := mDone;
end;

{ Start der Teile (aus der Kompositionswurzel hierher gezogen, #1455) }

procedure StartDisplayRules;
begin
  // Nur eine laufende Sitzung; die Regeln warten sonst auf den nächsten Versuch.
  TAtlasIdeDisplayRules.Start(
    function: TLspSession
    begin
      Result := Session;
    end);
end;

procedure StartDebugExceptions;
begin
  TAtlasIdeDebugExceptions.Start(MessageLine);
end;

procedure StartDebugOwnCode;
begin
  TAtlasIdeDebugOwnCode.Start(MessageLine);
end;

procedure StartDebugExceptionBar;
begin
  TAtlasIdeDebugExceptionBar.Start(MessageLine, TAtlasStatusRegistry.Default);
end;

procedure StartDebugInlineValues;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugInlineValues.Start(
    function: TLspSession
    begin
      Result := Session;
    end);
end;

/// <summary>„kein Zugriff auf Wert“ erklären (#840): Erklärung und Korrekturen im Hover; der Tooltip kennt die
/// Debug-Schicht nicht (A-09).</summary>
procedure StartDebugUnavailable;
begin
  TAtlasIdeDebugUnavailable.Start(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  TAtlasEditorHover.OnExplain :=
    function(const AValue: TAtlasDebugValue; const ADone: TAtlasDebugValueEvent): TAtlasDebugValue
    begin
      Result := TAtlasIdeDebugUnavailable.Explain(AValue, ADone);
    end;
  TAtlasEditorHover.OnDebugFix :=
    procedure(const AValue: TAtlasDebugValue; AFix: Integer)
    begin
      TAtlasIdeDebugUnavailable.Fix(AValue, AFix);
    end;
end;

procedure ReleaseDebugUnavailable;
begin
  TAtlasEditorHover.OnExplain := nil;
  TAtlasEditorHover.OnDebugFix := nil;
  TAtlasIdeDebugUnavailable.Release;
end;

function ExpressionProvider(const AHistory: TFunc<TArray<string>>): IAtlasCompletionProvider;
var
  mProvider: TAtlasExpressionCompletionProvider;
begin
  mProvider := TAtlasExpressionCompletionProvider.Create(
    function: TLspSession
    begin
      Result := Session;
    end, AHistory,
    function(AResponse: TJSONValue): TAtlasCompletionItems
    begin
      Result := TAtlasServerCompletionProvider.ItemsFromLsp(AResponse);
    end, TAtlasExpressionCompletionProvider.DefaultTimeoutMs);
  mProvider.HistoryCaption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExpressionHistory);
  Result := mProvider;
end;

procedure StartDebugDialogCompletion;
begin
  TAtlasIdeDebugDialogCompletion.Start(
    function: TLspSession
    begin
      Result := Session;
    end, LogLine, ExpressionProvider);
  TAtlasIdeDebugDialogCompletion.ApplySettings;
end;

procedure StartDebugEvaluate;
begin
  TAtlasIdeDebugEvaluate.Start(
    function: TLspSession
    begin
      Result := Session;
    end);
end;

procedure ShowWhereAssigned(const AFileName: string; ALine, ACharacter: Integer; const AName: string);
begin
  TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Sources, AFileName, ALine, ACharacter, AName);
end;

procedure EvaluateExpression(const AExpression: string);
begin
  TAtlasIdeDebugEvaluate.ShowWindow(AExpression);
end;

/// <summary>Zugriffsverletzung erklären (#865): Knöpfe der Leiste über den Datenfluss (#690) und das Fenster
/// „Auswerten“ (#784).</summary>
procedure StartDebugAccessViolation;
begin
  TAtlasIdeDebugAccessViolation.Start(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  TAtlasIdeDebugAccessViolation.SetWhereAssigned(ShowWhereAssigned);
  TAtlasIdeDebugAccessViolation.SetEvaluate(EvaluateExpression);
end;

procedure ToggleDebugJustMyCode;
begin
  TAtlasIdeDebugOwnCode.ToggleSetting(MessageLine);
end;

/// <summary>Befehl abgesichert ausführen (#493): eine Ausnahme schaltet nur die Debugger-Funktionen ab.</summary>
function Guarded(const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, AProc);
    end;
end;

function Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := Guarded(ARun);
  Result.Visible := AVisible;
end;

/// <summary>Wie Command, mit Tastenkürzel zur Anzeige. Eigener Name statt Überladung: anonyme Methoden als
/// Argument vertragen keine Überladungen.</summary>
function CommandWithKey(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>; const AKey: TFunc<Integer>): TAtlasModuleCommand;
begin
  Result := Command(AId, ACaption, ARun, AVisible);
  Result.Key := AKey;
end;

{ TAtlasDebugModule }

function TAtlasDebugModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Debugger';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // „Gezielt hineinspringen“ und die Befehle des Schrittfilters gab es schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
end;

procedure InstallCommands;
begin
  // Gezielt hineinspringen (#836): Liste der Aufrufe am Ausführungspunkt.
  TAtlasIdeStepInto.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  // Beim nächsten Ereignis anhalten (#856): Eintrag im Menü Start.
  TAtlasIdeEventBreak.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  // Schrittfilter (#850): Fenster und Befehle; den Ablauf startet das Teil DebugStepFilter.
  TAtlasIdeDebugStepFilter.Install(
    function: TLspSession
    begin
      Result := Session;
    end, MessageLine);
  GCommandsInstalled := True;
end;

procedure UninstallCommands;
begin
  GCommandsInstalled := False;
  TAtlasIdeStepInto.Uninstall;
  TAtlasIdeEventBreak.Uninstall;
  TAtlasIdeDebugStepFilter.Uninstall;
  // Nach allen anderen Teilen: Was von F7 übrig ist, hängt der Debugger hier ab (#850).
  TAtlasIdeDebugTrace.Release;
end;

function CommandsInstalled: Boolean;
begin
  Result := GCommandsInstalled;
end;

procedure TAtlasDebugModule.Start;
begin
  FActive := True;
end;

procedure TAtlasDebugModule.Stop;
begin
  FActive := False;
end;

function TAtlasDebugModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasDebugModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Gezielt hineinspringen (#836); nur sichtbar, solange debug.stepIntoTarget an ist.
    CommandWithKey('Atlas.StepIntoTarget', TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand),
      TAtlasIdeStepInto.Run,
      StepIntoTargetVisible, StepIntoTargetKey),
    // Beim nächsten Ereignis anhalten (#856); nur sichtbar, solange debug.breakOnNextEvent an ist.
    Command('Atlas.BreakOnNextEvent', TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCommand),
      TAtlasIdeEventBreak.Run,
      BreakOnNextEventVisible),
    // Schrittfilter (#850): Das Fenster schaltet debug.stepFilters selbst, deshalb immer sichtbar.
    Command('Atlas.StepFilters', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterWindowCommand),
      TAtlasIdeDebugStepFilter.ShowWindow,
      nil),
    Command('Atlas.StepIntoAnyway', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterStepIntoAnywayCommand),
      TAtlasIdeDebugStepFilter.StepIntoAnyway, StepFilterRunning),
    // Routine an der Schreibmarke in debug.stepFilters.patterns aufnehmen bzw. entfernen (#850); der Aufruf meldet,
    // was danach noch filtert.
    Command('Atlas.StepFilterSkip', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterSkipCommand),
      TAtlasIdeDebugStepFilter.SkipAtCursor, nil),
    Command('Atlas.StepFilterUnskip', TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterUnskipCommand),
      TAtlasIdeDebugStepFilter.UnskipAtCursor,
      nil),
    // Exception-Verlauf (#517); nur sichtbar, solange debug.exceptionHistory an ist.
    Command('Atlas.DebugExceptions', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsCommand),
      TAtlasIdeDebugExceptions.ShowWindow,
      DebugExceptionsVisible),
    // Fenster „Auswerten“ (#784) und der Dialog der IDE daneben.
    Command('Atlas.DebugEvaluate', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateCommand),
      TAtlasIdeDebugEvaluate.ShowWindow,
      DebugEvaluateVisible),
    Command('Atlas.DebugEvaluateIdeDialog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateIdeDialogCommand),
      TAtlasIdeDebugEvaluate.OpenIdeDialog, DebugEvaluateVisible),
    // Nur eigener Code (#578): schaltet debug.justMyCode um, deshalb immer sichtbar.
    Command('Atlas.DebugJustMyCode', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugJustMyCodeCommand),
      ToggleDebugJustMyCode, nil),
    // Exception-Leiste (#783): Dialog der IDE für die laufende Debug-Sitzung.
    Command('Atlas.DebugExceptionIdeDialog', TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugBannerIdeDialogCommand),
      TAtlasIdeDebugExceptionBar.ToggleIdeDialog, DebugExceptionBarVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function TAtlasDebugModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.DebugExceptions', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.DebugEvaluate', TAtlasMenuPlace.AtlasMenu),
    // Kontextmenü des Editors: gezielt hineinspringen (#836) und Schrittfilter (#850).
    MenuEntry('Atlas.StepIntoTarget', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.StepFilterSkip', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.StepFilterUnskip', TAtlasMenuPlace.EditorContext)];
end;

function TAtlasDebugModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  // Gezielt hineinspringen (#836): nur im angehaltenen Zustand; sonst geht die Taste an die IDE weiter.
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.StepIntoTarget';
  mKey.Caption := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand);
  mKey.Key := StepIntoTargetKey;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := TryStepInto;
    end;
  Result := [mKey];
end;

procedure TAtlasDebugModule.EditorViewActivated;
begin
  // Gezielt hineinspringen (#836): Die Liste gehört zum Ausführungspunkt in der bisherigen Ansicht.
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeStepInto.Dismiss);
end;

procedure TAtlasDebugModule.ApplySettings;
begin
  // debug.breakOnNextEvent (#856).
  TAtlasIdeEventBreak.ApplySettings;
  // debug.exceptionHistory (#517).
  TAtlasIdeDebugExceptions.ApplySettings;
  // debug.exceptionBanner* (#783).
  TAtlasIdeDebugExceptionBar.ApplySettings;
  // debug.explainUnavailable (#840): Ergänzungen der Fehlertexte neu lesen.
  TAtlasIdeDebugUnavailable.ApplySettings;
  // debug.completionInDialogs (#538): Breiten des Popups.
  TAtlasIdeDebugDialogCompletion.ApplySettings;
  // debug.evaluateWindow.replaceCtrlF7 (#784): Strg+F7 an- bzw. abhängen.
  TAtlasIdeDebugEvaluate.ApplySettings;
  // debug.stepFilters* (#850): Fenster mit dem gespeicherten Stand, Treffer neuer Muster zählen.
  TAtlasIdeDebugStepFilter.ApplySettings;
  // debug.visualizers aus: abmelden; Arten geändert: neu anmelden (#835).
  TAtlasIdeVisualizers.ApplySettings;
  // debug.displayRules aus: abmelden; an: Regeln beim nächsten Takt neu lesen (#854).
  TAtlasIdeDisplayRules.ApplySettings;
end;

procedure TAtlasDebugModule.ThemeChanged;
begin
  TAtlasIdeDebugExceptions.ThemeChanged;
  TAtlasIdeDebugExceptionBar.ThemeChanged;
  TAtlasIdeDebugEvaluate.ThemeChanged;
  TAtlasIdeDebugStepFilter.ThemeChanged;
end;

function TAtlasDebugModule.HoverValue(const AExpression: string; const ATypeChain: TArray<string>;
  const AText: string): string;
begin
  // Eigene Regel des Typs vor den Visualisierern für Bibliothekstypen (#835, #854); beide liefern '', solange ihr
  // Teil nicht läuft.
  Result := TAtlasIdeDisplayRules.HoverText(AExpression, ATypeChain);
  if Result = '' then
    Result := TAtlasIdeVisualizers.HoverText(AExpression, ATypeChain, AText);
end;

class function TAtlasDebugModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Zuerst: Befehle des Debuggers, schon im abgesicherten Start; stoppt als letztes Teil.
    TAtlasFeaturePart.AtLevel('DebugCommands', TAtlasSafeLevel.Safe, CommandsInstalled, InstallCommands,
      UninstallCommands),
    // Visualisierer für häufige Typen (#835): nur im normalen Start und solange debug.visualizers an ist.
    TAtlasFeaturePart.When('Visualizers',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugVisualizers;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeVisualizers.Started;
      end, TAtlasIdeVisualizers.Start, TAtlasIdeVisualizers.Stop),
    // Eigene Wertdarstellungen (#854): nur im normalen Start und solange debug.displayRules an ist.
    TAtlasFeaturePart.When('DisplayRules',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugDisplayRules;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDisplayRules.Started;
      end, StartDisplayRules, TAtlasIdeDisplayRules.Stop),
    // Exception-Verlauf (#517): Zuhörer der Debug-Sitzung; aus = kein Notifier beim Debugger.
    TAtlasFeaturePart.When('DebugExceptions',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugExceptionHistory;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugExceptions.Started;
      end, StartDebugExceptions, TAtlasIdeDebugExceptions.Release),
    // Nur eigener Code (#578): Zuhörer der Debug-Sitzung und Haken an „Einzelne Anweisung“ (F7).
    TAtlasFeaturePart.When('DebugOwnCode',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugJustMyCode;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugOwnCode.Started;
      end, StartDebugOwnCode, TAtlasIdeDebugOwnCode.Release),
    // Exception-Leiste (#783): baut auf dem Exception-Verlauf auf; aus = Dialog der IDE unverändert.
    TAtlasFeaturePart.When('DebugExceptionBar',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and DebugExceptionBarVisible;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugExceptionBar.Started;
      end, StartDebugExceptionBar, TAtlasIdeDebugExceptionBar.Release),
    // Werte im Editor (#508): Zuhörer der Debug-Sitzung und Zeichner; aus = nichts angemeldet.
    TAtlasFeaturePart.When('DebugInlineValues',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugInlineValues;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugInlineValues.Started;
      end, StartDebugInlineValues, TAtlasIdeDebugInlineValues.Release),
    // „kein Zugriff auf Wert“ erklären (#840): Hover und Werte im Editor.
    TAtlasFeaturePart.When('DebugUnavailable',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugExplainUnavailable;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugUnavailable.Started;
      end, StartDebugUnavailable, ReleaseDebugUnavailable),
    // Zugriffsverletzung erklären (#865): Zuhörer des Exception-Verlaufs und Zeichner.
    TAtlasFeaturePart.When('DebugAccessViolation',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugExplainAccessViolation;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugAccessViolation.Started;
      end, StartDebugAccessViolation, TAtlasIdeDebugAccessViolation.Release),
    // Vervollständigung in Debugger-Dialogen (#538): aus = kein Zeitgeber, kein Tastatur-Hook.
    TAtlasFeaturePart.When('DebugDialogCompletion',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugCompletionInDialogs;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugDialogCompletion.Started;
      end, StartDebugDialogCompletion, TAtlasIdeDebugDialogCompletion.Release),
    // Fenster „Auswerten“ (#784): aus = kein Fenster, kein Zuhörer, Strg+F7 bleibt bei der IDE.
    TAtlasFeaturePart.When('DebugEvaluate',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugEvaluateWindow;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugEvaluate.Started;
      end, StartDebugEvaluate, TAtlasIdeDebugEvaluate.Release),
    // Schrittfilter (#850): Zuhörer der Debug-Sitzung und Empfänger von F7; aus = F7 wie bisher.
    TAtlasFeaturePart.When('DebugStepFilter',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugStepFilters;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugStepFilter.Started;
      end, TAtlasIdeDebugStepFilter.Start, TAtlasIdeDebugStepFilter.Release)];
end;

class function TAtlasDebugModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDebugModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasDebugModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
    GScope.Provide(IAtlasFeaturePart, mPart);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasFollowsEditorView, mRef);
  GScope.Provide(IAtlasHoverValueSource, mRef);
  // Vertrag zwischen Modulen: Debug-Notiz und Exception-Verlauf für „An Issue anhängen …“ (#1276).
  GScope.Provide(IAtlasDebugReportSource, TAtlasIdeDebugReport.Create as IAtlasDebugReportSource);
  Result := True;
end;

class procedure TAtlasDebugModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasDebugModule.RegisterModule;

finalization
  TAtlasDebugModule.UnregisterModule;

end.
