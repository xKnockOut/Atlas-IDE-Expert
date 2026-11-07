unit Atlas.IDE.Debug.DisplayRules;

// Eigene Wertdarstellung je Typ beim Debugger der IDE (#854):
// - Regeln: Sobald ein Prozess läuft, fragt ein Zeitgeber einmal je Projekt
//   und Stand der Projektdatei atlas.server.debugDisplayRules (nur, wenn der
//   Server ohnehin läuft) und nimmt die Regeln aus .atlas (debugDisplayRules)
//   dazu. Antwortet der Server nicht, gelten die Regeln der Projektdatei, und
//   der nächste Versuch folgt nach RetryMs.
// - Anmeldung: Ein Visualisierer (IOTADebuggerVisualizer250,
//   IOTADebuggerVisualizerValueReplacer, IOTADebuggerVisualizerExternalViewer)
//   für alle Typen mit Regel und ihre Erben, jeweils mit AllDescendants. Bei
//   neuen Regeln wird er ab- und neu angemeldet.
// - Ersatztext und Hover: TAtlasDisplayRender mit den Rückrufen von
//   TAtlasIdeDebugEvaluator; Zeitbudget debug.visualizers.timeoutMs für alle
//   Platzhalter zusammen, Höchstlänge debug.visualizers.maxLength.
// - Ansichtsfenster (Lupe): Unterelemente aus atlas-debug-children, „Alle
//   Felder“ schaltet auf die ganze Feldliste. Die Fenster der IDE (Überwachte
//   Ausdrücke, Lokale Variablen) klappen weiter alle Felder auf: Die Open
//   Tools API kennt keine Auswahl der Unterelemente.
// - debug.displayRules aus: abmelden, Fenster schließen; die IDE zeigt ihre
//   eigenen Werte. Visualisierer der Open Tools API laufen laut Embarcadero
//   nur mit dem 32-Bit-Debugger ohne LLDB; Win64 erreicht die Regel über den
//   Atlas-Tooltip (HoverText).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Debug.DisplayRules;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasDisplayRulesSessionFunc = reference to function: TLspSession;

  TAtlasIdeDisplayVisualizer = class(TInterfacedObject, IOTADebuggerVisualizer, IOTADebuggerVisualizer250,
    IOTADebuggerVisualizerValueReplacer, IOTADebuggerVisualizerExternalViewer)
  private
    FTypes: TArray<string>;
  public
    constructor Create(const ATypes: TArray<string>);
    { IOTADebuggerVisualizer }
    function GetSupportedTypeCount: Integer;
    procedure GetSupportedType(Index: Integer; var TypeName: string; var AllDescendants: Boolean); overload;
    function GetVisualizerIdentifier: string;
    function GetVisualizerName: string;
    function GetVisualizerDescription: string;
    { IOTADebuggerVisualizer250 }
    procedure GetSupportedType(Index: Integer; var TypeName: string; var AllDescendants: Boolean;
      var IsGeneric: Boolean); overload;
    { IOTADebuggerVisualizerValueReplacer }
    function GetReplacementValue(const Expression, TypeName, EvalResult: string): string;
    { IOTADebuggerVisualizerExternalViewer }
    function GetMenuText: string;
    function Show(const Expression, TypeName, EvalResult: string; SuggestedLeft,
      SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
  end;

  TAtlasIdeDisplayRules = class
  public const
    cCommand = 'atlas.server.debugDisplayRules';
    cTickMs = 1000;
    cTimeoutMs = 3000;
    cRetryMs = 15000;
  private class var
    FRules: TAtlasDisplayRules;
    FSession: TAtlasDisplayRulesSessionFunc;
    FTimer: TTimer;
    FTicker: TObject;
    FVisualizer: IOTADebuggerVisualizer;
    FFetchedKey: string;
    FServerKey: string;
    FRetryAt: UInt64;
    class function Debugging: Boolean; static;
    class function StateKey: string; static;
    class procedure Fetch(const AKey: string); static;
    class procedure Register; static;
    class procedure Unregister; static;
  public
    class function Started: Boolean; static;
    class procedure Start(const ASession: TAtlasDisplayRulesSessionFunc); static;
    class procedure Stop; static;
    /// <summary>Nach einer Einstellungsänderung: aus = Stop; an = beim nächsten Takt neu lesen.</summary>
    class procedure ApplySettings; static;
    /// <summary>Zeitgeber: Regeln holen, wenn ein Prozess läuft und Projekt oder .atlas sich geändert haben.
    /// </summary>
    class procedure Tick; static;
    class function Options: TAtlasDisplayRuleOptions; static;
    /// <summary>Regel zum Typ des Werts (Debugger) bzw. zur Kette aus dem Hover.</summary>
    class function FindRule(const ATypeName: string; out ARule: TAtlasDisplayRule): Boolean; static;
    /// <summary>Ersatztext für den Atlas-Tooltip: erstes Glied von ATypeChain mit Regel; '' ohne.</summary>
    class function HoverText(const AExpression: string; const ATypeChain: array of string): string; static;
    /// <summary>Ersatztext für den Debugger; '' = Text der IDE lassen.</summary>
    class function ReplacementText(const AExpression, ATypeName: string): string; static;
    class function ViewOf(const AExpression, ATypeName, AEvalResult: string): TAtlasVisualizerView; static;
  end;

implementation

uses
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Lsp.Client,
  Atlas.Text.DebugDisplay,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Visualizers,
  Atlas.UI.Debug.Strings;

const
  cVisualizerIdentifier = 'Atlas.Visualizer.DisplayRules';

type
  /// <summary>Hält den Zeitgeber; OnTimer braucht eine Methode.</summary>
  TTicker = class
  public
    procedure Timer(Sender: TObject);
  end;

procedure TTicker.Timer(Sender: TObject);
begin
  TAtlasIdeDisplayRules.Tick;
end;

{ TAtlasIdeDisplayVisualizer }

constructor TAtlasIdeDisplayVisualizer.Create(const ATypes: TArray<string>);
begin
  inherited Create;
  FTypes := ATypes;
end;

function TAtlasIdeDisplayVisualizer.GetSupportedTypeCount: Integer;
begin
  Result := Length(FTypes);
end;

procedure TAtlasIdeDisplayVisualizer.GetSupportedType(Index: Integer; var TypeName: string;
  var AllDescendants: Boolean);
begin
  if (Index < 0) or (Index > High(FTypes)) then
  begin
    Exit;
  end;
  TypeName := FTypes[Index];
  AllDescendants := True;
end;

procedure TAtlasIdeDisplayVisualizer.GetSupportedType(Index: Integer; var TypeName: string;
  var AllDescendants: Boolean; var IsGeneric: Boolean);
begin
  if (Index < 0) or (Index > High(FTypes)) then
  begin
    Exit;
  end;
  TypeName := FTypes[Index];
  AllDescendants := True;
  IsGeneric := False;
end;

function TAtlasIdeDisplayVisualizer.GetVisualizerIdentifier: string;
begin
  Result := cVisualizerIdentifier;
end;

function TAtlasIdeDisplayVisualizer.GetVisualizerName: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugDisplayName);
end;

function TAtlasIdeDisplayVisualizer.GetVisualizerDescription: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugDisplayDescription);
end;

function TAtlasIdeDisplayVisualizer.GetReplacementValue(const Expression, TypeName, EvalResult: string): string;
var
  mText: string;
begin
  // '' wäre ein leerer Wert in der Liste der IDE: ohne eigenen Text bleibt der der IDE.
  Result := EvalResult;
  try
    mText := TAtlasIdeDisplayRules.ReplacementText(Expression, TypeName);
    if mText <> '' then
    begin
      Result := mText;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

function TAtlasIdeDisplayVisualizer.GetMenuText: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerMenu);
end;

/// <summary>Quelle des Ansichtsfensters; eigene Routine, damit der Rahmen keine anderen Methodenreferenzen hält.
/// </summary>
function DisplaySource: TAtlasViewSource;
begin
  Result :=
    function(const AExpression, ATypeName, AEvalResult: string): TAtlasVisualizerView
    begin
      Result := TAtlasIdeDisplayRules.ViewOf(AExpression, ATypeName, AEvalResult);
    end;
end;

function TAtlasIdeDisplayVisualizer.Show(const Expression, TypeName, EvalResult: string; SuggestedLeft,
  SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
begin
  Result := nil;
  try
    Result := TAtlasIdeViewerUpdater.Create(TAtlasViewerGroup.DisplayRules, DisplaySource(), Expression, TypeName,
      EvalResult, Point(SuggestedLeft, SuggestedTop));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeDisplayRules }

class function TAtlasIdeDisplayRules.Started: Boolean;
begin
  Result := FTimer <> nil;
end;

class procedure TAtlasIdeDisplayRules.Start(const ASession: TAtlasDisplayRulesSessionFunc);
begin
  if Started then
  begin
    Exit;
  end;
  FSession := ASession;
  FRules := TAtlasDisplayRules.Create;
  FTicker := TTicker.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TTicker(FTicker).Timer;
  FTimer.Enabled := True;
  FFetchedKey := '';
  FServerKey := '';
  FRetryAt := 0;
end;

class procedure TAtlasIdeDisplayRules.Stop;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  TAtlasIdeVisualizers.CloseViewers(TAtlasViewerGroup.DisplayRules);
  Unregister;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FRules);
  FSession := nil;
  FFetchedKey := '';
  FServerKey := '';
end;

class procedure TAtlasIdeDisplayRules.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugDisplayRules then
  begin
    Stop;
  end
  else
  begin
    FFetchedKey := '';
  end;
end;

class function TAtlasIdeDisplayRules.Options: TAtlasDisplayRuleOptions;
begin
  Result := Default(TAtlasDisplayRuleOptions);
  Result.AllowCalls := TAtlasIdeSettings.Current.DebugDisplayRulesAllowCalls;
  Result.MaxLength := TAtlasIdeSettings.Current.DebugVisualizerMaxLength;
end;

class function TAtlasIdeDisplayRules.Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

class function TAtlasIdeDisplayRules.StateKey: string;
begin
  Result := TAtlasIdeTeamFile.ActiveProject + '|' + IntToStr(TAtlasIdeTeamFile.Version);
end;

class procedure TAtlasIdeDisplayRules.Tick;
var
  mKey: string;
begin
  try
    if not Started or not TAtlasIdeSettings.Current.DebugDisplayRules or not Debugging then
    begin
      Exit;
    end;
    mKey := StateKey;
    // Gleicher Stand mit Antwort des Servers: nichts zu tun; ohne Antwort erst nach RetryMs wieder fragen.
    if (mKey = FFetchedKey) and ((FServerKey = mKey) or (GetTickCount64 < FRetryAt)) then
    begin
      Exit;
    end;
    Fetch(mKey);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

/// <summary>Argumente für den Server: Projekt und Namen der Regeln aus der Projektdatei.</summary>
function ServerArguments(const AProject: string; const ANames: TArray<string>): string;
var
  mValues, mNames: TJSONArray;
  mName: string;
begin
  mValues := TJSONArray.Create;
  try
    if AProject = '' then
    begin
      mValues.AddElement(TJSONNull.Create);
    end
    else
    begin
      mValues.Add(TLspSession.PathToUri(AProject));
    end;
    mNames := TJSONArray.Create;
    for mName in ANames do
    begin
      mNames.Add(mName);
    end;
    mValues.AddElement(mNames);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

class procedure TAtlasIdeDisplayRules.Fetch(const AKey: string);
var
  mTeam: TAtlasTeamSettings;
  mTeamRule: TAtlasTeamDisplayRule;
  mRule: TAtlasDisplayRule;
  mSession: TLspSession;
  mAnswer: TJSONValue;
begin
  FFetchedKey := AKey;
  FRetryAt := GetTickCount64 + cRetryMs;
  FRules.Clear;
  // Projektdatei zuerst: Regeln im Quelltext schlagen sie (TAtlasDisplayRules.Add).
  mTeam := TAtlasIdeTeamFile.Current;
  for mTeamRule in mTeam.DisplayRules do
  begin
    mRule := Default(TAtlasDisplayRule);
    mRule.TypeName := mTeamRule.TypeName;
    mRule.Template := mTeamRule.Template;
    mRule.Children := mTeamRule.Children;
    mRule.Origin := TDebugDisplayOrigin.Project;
    mRule.FileName := mTeam.FileName;
    mRule.Line := -1;
    FRules.Add(mRule);
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession <> nil then
    try
      mAnswer := mSession.RunCommand(cCommand, ServerArguments(TAtlasIdeTeamFile.ActiveProject, FRules.ProjectNames),
        cTimeoutMs);
      try
        if (mAnswer <> nil) and FRules.LoadJson(mAnswer.ToJSON) then
        begin
          FServerKey := AKey;
        end;
      finally
        mAnswer.Free;
      end;
    except
      on ELspClientError do
        // Server beschäftigt, weg oder zu alt: Regeln der Projektdatei gelten, später noch einmal.
        FServerKey := '';
    end;
  Register;
end;

class procedure TAtlasIdeDisplayRules.Register;
var
  mDebugger: IOTADebuggerServices;
  mTypes: TArray<string>;
begin
  Unregister;
  mTypes := FRules.TypeNames;
  if (Length(mTypes) = 0) or not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  FVisualizer := TAtlasIdeDisplayVisualizer.Create(mTypes);
  try
    mDebugger.RegisterDebugVisualizer(FVisualizer);
  except
    on E: Exception do
    begin
      FVisualizer := nil;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

class procedure TAtlasIdeDisplayRules.Unregister;
var
  mDebugger: IOTADebuggerServices;
begin
  if FVisualizer = nil then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
    try
      mDebugger.UnregisterDebugVisualizer(FVisualizer);
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  FVisualizer := nil;
end;

class function TAtlasIdeDisplayRules.FindRule(const ATypeName: string; out ARule: TAtlasDisplayRule): Boolean;
begin
  Result := (FRules <> nil) and TAtlasIdeSettings.Current.DebugDisplayRules and FRules.Find(ATypeName, ARule);
end;

class function TAtlasIdeDisplayRules.ReplacementText(const AExpression, ATypeName: string): string;
var
  mRule: TAtlasDisplayRule;
begin
  Result := '';
  if not FindRule(ATypeName, mRule) then
  begin
    Exit;
  end;
  Result := TAtlasDisplayRender.Render(mRule, AExpression, Options,
    TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs).Eval);
end;

class function TAtlasIdeDisplayRules.HoverText(const AExpression: string; const ATypeChain: array of string): string;
var
  mRule: TAtlasDisplayRule;
begin
  Result := '';
  if (FRules = nil) or not TAtlasIdeSettings.Current.DebugDisplayRules or not FRules.FindChain(ATypeChain, mRule) then
  begin
    Exit;
  end;
  try
    Result := TAtlasDisplayRender.Render(mRule, AExpression, Options,
      TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs).Eval);
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
      Result := '';
    end;
  end;
end;

class function TAtlasIdeDisplayRules.ViewOf(const AExpression, ATypeName, AEvalResult: string): TAtlasVisualizerView;
var
  mRule: TAtlasDisplayRule;
begin
  Result := Default(TAtlasVisualizerView);
  if not FindRule(ATypeName, mRule) then
  begin
    Result.Mode := TAtlasVisualizerViewMode.Text;
    Result.Summary := AEvalResult;
    Result.Text := AEvalResult;
    Exit;
  end;
  Result := TAtlasDisplayRender.View(mRule, AExpression, AEvalResult, Options,
    TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs *
    TAtlasIdeVisualizers.cViewBudgetFactor).Eval);
end;

end.
