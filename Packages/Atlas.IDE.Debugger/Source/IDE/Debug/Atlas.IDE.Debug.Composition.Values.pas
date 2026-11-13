unit Atlas.IDE.Debug.Composition.Values;

// Modul Debugger (#1455), Teil der Komposition: die Teile der
// Feature-Tabelle rund um Werte und Ausdrücke, in dieser Reihenfolge Werte im
// Editor, „kein Zugriff“ erklären, Zugriffsverletzung, Vervollständigung in
// Debugger-Dialogen und Fenster „Auswerten“. Sie fragen den Server nur, wenn
// er ohnehin läuft. Dazu der Speicherverlauf (#858, Werte des Prozesses über
// die Sitzung; ohne Server), der nach dem Schrittfilter startet.
// Atlas.IDE.Debug.Composition stellt sie über den Scope des Moduls bereit.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Debug.DialogCompletion;

/// <summary>Teile für Werte und Ausdrücke in ihrer Startreihenfolge; AProvider liefert die Vervollständigung in
/// Debugger-Dialogen (erzeugt in Atlas.IDE.Debug.Composition).</summary>
function DebugValueParts(const AProvider: TAtlasDialogProviderFactory): TArray<IAtlasFeaturePart>;
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

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Debug.InlineValues,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.IDE.Debug.MemoryTimeline;

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

function DebugValueParts(const AProvider: TAtlasDialogProviderFactory): TArray<IAtlasFeaturePart>;
begin
  GProvider := AProvider;
  Result := EditorParts + DialogParts;
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
