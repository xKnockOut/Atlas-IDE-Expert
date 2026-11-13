unit Atlas.IDE.Debug.Composition.Values;

// Modul Debugger (#1455), Teil der Komposition: die Teile der
// Feature-Tabelle rund um Werte und Ausdrücke, in dieser Reihenfolge Werte im
// Editor, angeheftete Werte, „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
// Debugger-Dialogen, Fenster „Auswerten“ und „Warum bin ich hier?“. Sie fragen
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
/// <summary>Einstellungen an „kein Zugriff“, Vervollständigung in Dialogen und Fenster „Auswerten“.</summary>
procedure ApplyValueSettings;

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
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.IDE.Debug.WhyHere;

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

/// <summary>Angeheftete Werte (#526): „Anheften“ im Debug-Hover; der Tooltip kennt die Debug-Schicht nicht.
/// </summary>
procedure StartDebugPins;
begin
  TAtlasIdeDebugPins.Start(MessageLine);
  TAtlasEditorHover.OnDebugActions :=
    function(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>
    begin
      Result := TAtlasIdeDebugPins.Actions(AValue);
    end;
  TAtlasEditorHover.OnDebugAction :=
    procedure(const AValue: TAtlasDebugValue; const AFileName: string; ALine, AAction: Integer)
    begin
      TAtlasIdeDebugPins.Act(AValue, AFileName, ALine, AAction);
    end;
end;

procedure ReleaseDebugPins;
begin
  TAtlasEditorHover.OnDebugActions := nil;
  TAtlasEditorHover.OnDebugAction := nil;
  TAtlasIdeDebugPins.Release;
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

/// <summary>„Warum bin ich hier?“ (#1878): Zuhörer der Debug-Sitzung, Zeichner und Mausklick; aus = nichts
/// angemeldet.</summary>
function WhyHerePart(const AScope: IAtlasModuleScope): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.When('DebugWhyHere',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := NotMinimal(ALevel) and TAtlasIdeSettings.Current.DebugWhyHere;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugWhyHere.Started;
    end, WhyHereStarter(AScope), TAtlasIdeDebugWhyHere.Release);
end;

function DebugValueParts(const AProvider: TAtlasDialogProviderFactory;
  const AScope: IAtlasModuleScope): TArray<IAtlasFeaturePart>;
begin
  GProvider := AProvider;
  Result := EditorParts + DialogParts + [WhyHerePart(AScope)];
end;

procedure ApplyValueSettings;
begin
  // debug.explainUnavailable (#840): Ergänzungen der Fehlertexte neu lesen.
  TAtlasIdeDebugUnavailable.ApplySettings;
  // debug.completionInDialogs (#538): Breiten des Popups.
  TAtlasIdeDebugDialogCompletion.ApplySettings;
  // debug.evaluateWindow.replaceCtrlF7 (#784): Strg+F7 an- bzw. abhängen.
  TAtlasIdeDebugEvaluate.ApplySettings;
end;

end.
