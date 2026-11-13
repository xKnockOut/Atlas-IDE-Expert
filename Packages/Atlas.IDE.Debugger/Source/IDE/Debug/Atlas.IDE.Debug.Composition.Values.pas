unit Atlas.IDE.Debug.Composition.Values;

// Modul Debugger (#1455), Teil der Komposition: die Teile der
// Feature-Tabelle rund um Werte und Ausdrücke, in dieser Reihenfolge Werte im
// Editor, angeheftete Werte, „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
// Debugger-Dialogen, Fenster „Auswerten“, „Warum bin ich hier?“, Werte ändern und Debug-Hover aufklappen. Sie
// fragen
// den Server nur, wenn er ohnehin läuft. Dazu der Speicherverlauf (#858, Werte
// des Prozesses über die Sitzung; ohne Server), der nach dem Schrittfilter
// startet. Atlas.IDE.Debug.Composition stellt sie über den Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Debug.DialogCompletion;

/// <summary>Teile für Werte und Ausdrücke in ihrer Startreihenfolge; AProvider liefert die Vervollständigung in
/// Debugger-Dialogen (erzeugt in Atlas.IDE.Debug.Composition), AScope ist der Scope des Moduls für Serverbefehle.
/// </summary>
function DebugValueParts(const AProvider: TAtlasDialogProviderFactory;
  const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
/// <summary>Speicherverlauf (#858): Zuhörer der Debug-Sitzung und Zeitgeber; aus = keine Messung.</summary>
function DebugMemoryParts: TArray<IAtlasFeaturePart>;
/// <summary>Einstellungen an „kein Zugriff“, Vervollständigung in Dialogen, Fenster „Auswerten“ und Speicherverlauf.
/// </summary>
procedure ApplyValueSettings;
/// <summary>Thema der Fenster dieser Teile, die nicht Atlas.IDE.Debug.Composition selbst nachführt.</summary>
procedure ValueThemeChanged;
/// <summary>Befehl Atlas.DebugMemory: Fenster „Atlas: Speicher“.</summary>
procedure ShowDebugMemory;
function DebugMemoryVisible: Boolean;
/// <summary>Menütext des Befehls Atlas.DebugMemory.</summary>
function DebugMemoryCommandText: string;
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
  Atlas.IDE.Debug.HoverTree,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.IDE.Debug.WhyHere,
  Atlas.IDE.Debug.MemoryTimeline,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.Memory.Strings;

const
  /// <summary>F2 (VK_F2): nur im angehaltenen Zustand mit Bezeichner an der Schreibmarke, sonst geht sie an die IDE.
  /// </summary>
  cEditValueKey = $71;
  /// <summary>Wartezeit auf die Eigenschaften aus dem Index (#895); danach nur die Felder aus dem Debugger.</summary>
  cHoverTreeTimeoutMs = 3000;

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

/// <summary>Speicherverlauf (#858): misst ohne Server.</summary>
procedure StartDebugMemoryTimeline;
begin
  TAtlasIdeDebugMemoryTimeline.Start(MessageLine);
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

/// <summary>Aktionen im Debug-Hover: „Ändern …“ (#868), „Anheften“ (#526), Kopieren und Beobachten (#895) teilen sich
/// die Haken des Tooltips, der die Debug-Schicht nicht kennt. Angehängt, solange einer der Teile läuft.</summary>
procedure HookHoverActions;
begin
  if not TAtlasIdeDebugPins.Started and not TAtlasIdeDebugEditValue.Started and
    not TAtlasIdeDebugHoverTree.Started then
  begin
    TAtlasEditorHover.OnDebugActions := nil;
    TAtlasEditorHover.OnDebugAction := nil;
    Exit;
  end;
  TAtlasEditorHover.OnDebugActions :=
    function(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>
    begin
      Result := TAtlasIdeDebugHoverTree.Actions(AValue) + TAtlasIdeDebugPins.Actions(AValue) +
        TAtlasIdeDebugEditValue.Actions(AValue);
    end;
  TAtlasEditorHover.OnDebugAction :=
    procedure(const AValue: TAtlasDebugValue; const AFileName: string; ALine, AAction: Integer)
    begin
      if not TAtlasIdeDebugEditValue.Act(AValue, AFileName, ALine, AAction) and
        not TAtlasIdeDebugHoverTree.Act(AValue, AAction) then
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

/// <summary>Nach dem Ändern eines Werts (#868): Werte im Editor und angeheftete Werte im selben Halt neu auswerten.
/// </summary>
procedure ValuesChanged;
begin
  ReevaluateInlineValues;
  TAtlasIdeDebugPins.Reevaluate;
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

/// <summary>Start von „Debug-Hover aufklappen“ (#895): Zeilen und alter Wert über die Haken des Tooltips,
/// Eigenschaften über Base und den Scope AScope.</summary>
function HoverTreeStarter(const AScope: IAtlasModuleScope): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeDebugHoverTree.Start(
        function(const AMethod, AParamsJson: string; const ADone: TProc<string>): Boolean
        begin
          Result := TAtlasIdeHost.RunRequestAsync(AScope, TAtlasFeature.Debugger,
            TAtlasServerRequest.Create(AMethod, AParamsJson, cHoverTreeTimeoutMs,
            function: Boolean
            begin
              // Anfragen verfallen mit dem Teil.
              Result := not TAtlasIdeDebugHoverTree.Started;
            end), ADone);
        end);
      TAtlasEditorHover.OnDebugTree :=
        function(const AValue: TAtlasDebugValue; const AFileName: string; ALine: Integer;
          const ARefresh: TProc): TAtlasDebugValue
        begin
          Result := TAtlasIdeDebugHoverTree.Decorate(AValue, AFileName, ALine, ARefresh);
        end;
      TAtlasEditorHover.OnDebugRow :=
        procedure(const AValue: TAtlasDebugValue; ARow: Integer)
        begin
          TAtlasIdeDebugHoverTree.Row(ARow);
        end;
      HookHoverActions;
    end;
end;

procedure ReleaseDebugHoverTree;
begin
  TAtlasEditorHover.OnDebugTree := nil;
  TAtlasEditorHover.OnDebugRow := nil;
  TAtlasIdeDebugHoverTree.Release;
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

/// <summary>Debug-Hover aufklappen und Änderungen markieren (#895): Haken des Tooltips und Zuhörer der Sitzung;
/// beide Schalter aus = nichts angemeldet, der Hover zeigt den Wert wie bisher.</summary>
function HoverTreePart(const AScope: IAtlasModuleScope): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugHoverTree',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and (TAtlasIdeSettings.Current.DebugHoverExpand or
        TAtlasIdeSettings.Current.DebugHoverChanges);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugHoverTree.Started;
    end, HoverTreeStarter(AScope), ReleaseDebugHoverTree);
end;

function DebugValueParts(const AProvider: TAtlasDialogProviderFactory;
  const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
begin
  GProvider := AProvider;
  Result := EditorParts + DialogParts + [WhyHerePart(AScope), EditValuePart(AScope), HoverTreePart(AScope)];
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

function DebugMemoryParts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    TAtlasFeaturePart.When('DebugMemoryTimeline',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugMemoryTimeline;
      end,
      function: Boolean
      begin
        Result := TAtlasIdeDebugMemoryTimeline.Started;
      end, StartDebugMemoryTimeline, TAtlasIdeDebugMemoryTimeline.Release)];
end;

procedure ValueThemeChanged;
begin
  TAtlasIdeDebugMemoryTimeline.ThemeChanged;
end;

procedure ShowDebugMemory;
begin
  TAtlasIdeDebugMemoryTimeline.ShowWindow;
end;

function DebugMemoryCommandText: string;
begin
  Result := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryCommand);
end;

function DebugMemoryVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugMemoryTimeline;
end;

procedure ApplyValueSettings;
begin
  // debug.explainUnavailable (#840): Ergänzungen der Fehlertexte neu lesen.
  TAtlasIdeDebugUnavailable.ApplySettings;
  // debug.completionInDialogs (#538): Breiten des Popups.
  TAtlasIdeDebugDialogCompletion.ApplySettings;
  // debug.evaluateWindow.replaceCtrlF7 (#784): Strg+F7 an- bzw. abhängen.
  TAtlasIdeDebugEvaluate.ApplySettings;
  // debug.memoryTimeline.intervalMs (#858); aus: Fenster zu.
  TAtlasIdeDebugMemoryTimeline.ApplySettings;
end;

end.
