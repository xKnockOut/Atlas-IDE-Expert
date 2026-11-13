unit Atlas.IDE.Debug.Composition.Values;

// Modul Debugger (#1455), Teil der Komposition: die Teile der
// Feature-Tabelle rund um Werte und Ausdrücke, in dieser Reihenfolge Werte im
// Editor, angeheftete Werte, „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
// Debugger-Dialogen, Fenster „Auswerten“, „Warum bin ich hier?“, Werte ändern und Fenster
// „Variablen“. Sie fragen
// den Server nur, wenn er ohnehin läuft. Atlas.IDE.Debug.Composition stellt sie
// über den Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Debug.DialogCompletion;

/// <summary>Teile für Werte und Ausdrücke in ihrer Startreihenfolge; AProvider liefert die Vervollständigung in
/// Debugger-Dialogen (erzeugt in Atlas.IDE.Debug.Composition), AScope ist der Scope des Moduls für Serverbefehle.
/// </summary>
function DebugValueParts(const AProvider: TAtlasDialogProviderFactory;
  const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
/// <summary>Einstellungen an „kein Zugriff“, Vervollständigung in Dialogen und die Fenster „Auswerten“ und
/// „Variablen“.</summary>
procedure ApplyValueSettings;
/// <summary>Thema der Fenster „Auswerten“ und „Variablen“.</summary>
procedure ValueThemeChanged;
/// <summary>Fenster „Variablen“ zeigen (#853).</summary>
procedure ShowVariablesWindow;
/// <summary>Befehl „Variablen“ sichtbar: debug.variablesWindow an.</summary>
function VariablesWindowVisible: Boolean;
/// <summary>Befehle „Wert ändern“ und „Geänderten Wert zurücksetzen“ (#868), noch ohne Sicherung.</summary>
function ValueCommands: TArray<TAtlasModuleCommand>;
/// <summary>Einträge im Kontextmenü des Editors für Werte ändern (#868).</summary>
function ValueMenuEntries: TArray<TAtlasMenuEntry>;
/// <summary>Taste F2 für „Wert ändern“ (#868), nur im angehaltenen Zustand.</summary>
function ValueKeys: TArray<TAtlasModuleKey>;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Debug.InlineValues,
  Atlas.IDE.Debug.Pins,
  Atlas.IDE.Debug.EditValue,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.IDE.Debug.WhyHere,
  Atlas.IDE.Debug.Variables,
  Atlas.UI.Debug.Strings;

const
  /// <summary>F2 (VK_F2): nur im angehaltenen Zustand mit Bezeichner an der Schreibmarke, sonst geht sie an die IDE.
  /// </summary>
  cEditValueKey = $71;

var
  GProvider: TAtlasDialogProviderFactory;

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

function NotMinimal(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

{ Start der Teile }

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
/// Debug-Schicht nicht.</summary>
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

procedure StartDebugDialogCompletion;
begin
  TAtlasIdeDebugDialogCompletion.Start(
    function: TLspSession
    begin
      Result := Session;
    end, LogLine, GProvider);
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

/// <summary>Start von „Warum bin ich hier?“ mit Serverbefehlen im Hintergrund über Base und den Scope AScope; die
/// Antwort kommt nur, solange das Modul angemeldet ist.</summary>
function WhyHereStarter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugWhyHere.Start(
        function: TLspSession
        begin
          Result := Session;
        end,
        function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
        begin
          Result := TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger, ACommand, AArgumentsJson,
            ATimeoutMs, ADone);
        end);
    end;
end;

/// <summary>Start des Fensters „Variablen“ (#853) mit Serverbefehlen im Hintergrund über Base und den Scope
/// AScope; die Antwort kommt nur, solange das Modul angemeldet ist.</summary>
function VariablesStarter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugVariables.Start(
        function: TLspSession
        begin
          Result := Session;
        end,
        function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
        begin
          Result := TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger, ACommand, AArgumentsJson,
            ATimeoutMs, ADone);
        end);
    end;
end;

/// <summary>Aktionen im Debug-Hover: „Ändern …“ (#868) und „Anheften“ (#526) teilen sich die Haken des Tooltips,
/// der die Debug-Schicht nicht kennt. Angehängt, solange einer der beiden Teile läuft.</summary>
procedure HookHoverActions;
begin
  if not TAtlasIdeDebugPins.Started and not TAtlasIdeDebugEditValue.Started then
  begin
    TAtlasEditorHover.OnDebugActions := nil;
    TAtlasEditorHover.OnDebugAction := nil;
    Exit;
  end;
  TAtlasEditorHover.OnDebugActions :=
    function(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>
    begin
      Result := TAtlasIdeDebugEditValue.Actions(AValue) + TAtlasIdeDebugPins.Actions(AValue);
    end;
  TAtlasEditorHover.OnDebugAction :=
    procedure(const AValue: TAtlasDebugValue; const AFileName: string; ALine, AAction: Integer)
    begin
      if not TAtlasIdeDebugEditValue.Act(AValue, AFileName, ALine, AAction) then
      begin
        TAtlasIdeDebugPins.Act(AValue, AFileName, ALine, AAction);
      end;
    end;
end;

/// <summary>Angeheftete Werte (#526): „Anheften“ im Debug-Hover.</summary>
procedure StartDebugPins;
begin
  TAtlasIdeDebugPins.Start(MessageLine);
  HookHoverActions;
end;

procedure ReleaseDebugPins;
begin
  TAtlasIdeDebugPins.Release;
  HookHoverActions;
end;

/// <summary>Nach dem Ändern eines Werts (#868): Werte im Editor, angeheftete Werte und das Fenster „Variablen“ im
/// selben Halt neu auswerten.</summary>
procedure ValuesChanged;
begin
  ReevaluateInlineValues;
  TAtlasIdeDebugPins.Reevaluate;
  // Fenster „Variablen“ (#853): F2 dort ändert über denselben Weg.
  TAtlasIdeDebugVariables.Reevaluate;
end;

/// <summary>Start von „Werte ändern“ (#868) mit Serverbefehlen über Base und den Scope AScope.</summary>
function EditValueStarter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugEditValue.Start(
        function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
        begin
          Result := TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Debugger, ACommand, AArgumentsJson,
            ATimeoutMs, ADone);
        end, MessageLine, ValuesChanged);
      HookHoverActions;
    end;
end;

procedure ReleaseDebugEditValue;
begin
  TAtlasIdeDebugEditValue.Release;
  HookHoverActions;
end;

{ Teile }

/// <summary>Werte im Editor, „kein Zugriff“ und Zugriffsverletzung.</summary>
function EditorParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
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
    // Angeheftete Werte (#526): Aktion im Hover, Zuhörer und Zeichner; aus = nichts angemeldet.
    TAtlasFeaturePart.When('DebugPinnedValues',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugPinnedValues;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugPins.Started;
      end, StartDebugPins, ReleaseDebugPins),
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
      end, StartDebugAccessViolation, TAtlasIdeDebugAccessViolation.Release)]
end;

/// <summary>Vervollständigung in Debugger-Dialogen und Fenster „Auswerten“.</summary>
function DialogParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
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
      end, StartDebugEvaluate, TAtlasIdeDebugEvaluate.Release)]
end;

/// <summary>„Warum bin ich hier?“ (#1878) und Bedingungen vorausschauen (#2169): Zuhörer der Debug-Sitzung,
/// Zeichner und Mausklick; beide aus = nichts angemeldet.</summary>
function WhyHerePart(const AScope: IAtlasModuleScope): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugWhyHere',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and (TAtlasIdeSettings.Current.DebugWhyHere or
        TAtlasIdeSettings.Current.DebugPredictConditions);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugWhyHere.Started;
    end, WhyHereStarter(AScope), TAtlasIdeDebugWhyHere.Release);
end;

/// <summary>Fenster „Variablen“ (#853): Zuhörer der Debug-Sitzung und Fenster; aus = nichts angemeldet, kein
/// Fenster.</summary>
function VariablesPart(const AScope: IAtlasModuleScope): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugVariablesWindow',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugVariablesWindow;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugVariables.Started;
    end, VariablesStarter(AScope), TAtlasIdeDebugVariables.Release);
end;

/// <summary>Werte ändern (#868): Aktionen im Hover, F2 und Markierung am Zeilenende; aus = nichts angemeldet,
/// Werte sind nur lesbar.</summary>
function EditValuePart(const AScope: IAtlasModuleScope): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugEditValues',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugEditValues;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugEditValue.Started;
    end, EditValueStarter(AScope), ReleaseDebugEditValue);
end;

function DebugValueParts(const AProvider: TAtlasDialogProviderFactory;
  const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
begin
  GProvider := AProvider;
  Result := EditorParts + DialogParts + [WhyHerePart(AScope), EditValuePart(AScope), VariablesPart(AScope)];
end;

function EditValueVisible: Boolean;
begin
  Result := TAtlasIdeDebugEditValue.Started;
end;

function EditValueKey: Integer;
begin
  Result := cEditValueKey;
end;

function ValueCommands: TArray<TAtlasModuleCommand>;
var
  mEdit, mUndo: TAtlasModuleCommand;
begin
  mEdit := Default(TAtlasModuleCommand);
  mEdit.Id := 'Atlas.DebugEditValue';
  mEdit.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueCommand);
  mEdit.Run := TAtlasIdeDebugEditValue.EditAtCursor;
  mEdit.Visible := EditValueVisible;
  mEdit.Key := EditValueKey;
  mUndo := Default(TAtlasModuleCommand);
  mUndo.Id := 'Atlas.DebugUndoValue';
  mUndo.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueUndoCommand);
  mUndo.Run := TAtlasIdeDebugEditValue.UndoAtCursor;
  mUndo.Visible := EditValueVisible;
  Result := [mEdit, mUndo];
end;

/// <summary>Ist das Programm angehalten?</summary>
function WhileStopped(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging and (TAtlasIdeDebugValues.StoppedThread <> nil);
end;

function ValueMenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
  mId: string;
begin
  Result := nil;
  for mId in TArray<string>.Create('Atlas.DebugEditValue', 'Atlas.DebugUndoValue') do
  begin
    mEntry := Default(TAtlasMenuEntry);
    mEntry.CommandId := mId;
    mEntry.Place := TAtlasMenuPlace.EditorContext;
    mEntry.Section := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEditorMenuGroup);
    mEntry.Group := 'debug';
    mEntry.When := WhileStopped;
    Result := Result + [mEntry];
  end;
end;

/// <summary>F2 unter der Sicherung des Debuggers (#493); nach einem Fehler geht die Taste an die IDE.</summary>
function TryEditValue: Boolean;
var
  mDone: Boolean;
begin
  mDone := False;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      mDone := TAtlasIdeDebugEditValue.TryEditAtCursor;
    end);
  Result := mDone;
end;

function ValueKeys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.DebugEditValues then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.DebugEditValue';
  mKey.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EditValueCommand);
  mKey.Key := cEditValueKey;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := TryEditValue;
    end;
  Result := [mKey];
end;

procedure ApplyValueSettings;
begin
  // debug.explainUnavailable (#840): Ergänzungen der Fehlertexte neu lesen.
  TAtlasIdeDebugUnavailable.ApplySettings;
  // debug.completionInDialogs (#538): Breiten des Popups.
  TAtlasIdeDebugDialogCompletion.ApplySettings;
  // debug.evaluateWindow.replaceCtrlF7 (#784): Strg+F7 an- bzw. abhängen.
  TAtlasIdeDebugEvaluate.ApplySettings;
  // debug.variablesWindow (#853): ausgeschaltet verschwindet das Fenster.
  TAtlasIdeDebugVariables.ApplySettings;
end;

procedure ValueThemeChanged;
begin
  TAtlasIdeDebugEvaluate.ThemeChanged;
  TAtlasIdeDebugVariables.ThemeChanged;
end;

procedure ShowVariablesWindow;
begin
  TAtlasIdeDebugVariables.ShowWindow;
end;

function VariablesWindowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugVariablesWindow;
end;

end.
