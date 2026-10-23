unit Atlas.IDE.Debug.Visualizers;

// Visualisierer für häufige Typen (#835) beim Debugger der IDE:
// - Je Art aus debug.visualizers.types ein Visualisierer
//   (IOTADebuggerVisualizer250, IOTADebuggerVisualizerValueReplacer), Arten mit
//   Ansicht zusätzlich als IOTADebuggerVisualizerExternalViewer (Lupe in
//   Überwachten Ausdrücken, Lokalen Variablen und Debug-Inspektor). Eigene
//   Objekte je Art, weil GetReplacementValue nicht sagt, welche Anmeldung
//   gegriffen hat.
// - Ersatztext und Ansicht rechnet der Kern (TAtlasVisualizers) mit den
//   Rückrufen von TAtlasIdeDebugEvaluator; der Ersatztext hat
//   debug.visualizers.timeoutMs für alle Auswertungen zusammen, das
//   Ansichtsfenster ViewBudgetFactor-mal so viel. Gelingt nichts, bleibt der
//   Text der IDE.
// - ApplySettings meldet neu an, wenn sich Schalter, Arten oder Grenzen
//   ändern; Stop meldet alles ab und schließt offene Ansichtsfenster.
// - Visualisierer der Open Tools API laufen laut Embarcadero nur mit dem
//   32-Bit-Debugger ohne LLDB. Für Win64 und Hover bereitet HoverText den Wert
//   im Atlas-Tooltip auf (Art aus Typ und Vorfahren laut Server).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.Visualizers,
  Atlas.UI.Debug.Viewer;

type
  TAtlasIdeVisualizer = class(TInterfacedObject, IOTADebuggerVisualizer, IOTADebuggerVisualizer250,
    IOTADebuggerVisualizerValueReplacer)
  private
    FKind: TAtlasVisualizerKind;
    FTypes: TArray<TAtlasVisualizerType>;
  public
    constructor Create(AKind: TAtlasVisualizerKind);
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
    property Kind: TAtlasVisualizerKind read FKind;
  end;

  /// <summary>Visualisierer mit Ansichtsfenster.</summary>
  TAtlasIdeViewerVisualizer = class(TAtlasIdeVisualizer, IOTADebuggerVisualizerExternalViewer)
  public
    { IOTADebuggerVisualizerExternalViewer }
    function GetMenuText: string;
    function Show(const Expression, TypeName, EvalResult: string; SuggestedLeft,
      SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
  end;

  /// <summary>Verbindung zwischen dem Debugger und einem offenen Ansichtsfenster.</summary>
  TAtlasIdeViewerUpdater = class(TInterfacedObject, IOTADebuggerVisualizerExternalViewerUpdater)
  private
    FKind: TAtlasVisualizerKind;
    FForm: TAtlasDebugViewer;
    FClosed: TOTAVisualizerClosedProcedure;
    procedure FormClosed(Sender: TObject);
  public
    constructor Create(AKind: TAtlasVisualizerKind; const AExpression, ATypeName, AEvalResult: string;
      ALeft, ATop: Integer);
    destructor Destroy; override;
    { IOTADebuggerVisualizerExternalViewerUpdater }
    procedure CloseVisualizer;
    procedure MarkUnavailable(Reason: TOTAVisualizerUnavailableReason);
    procedure RefreshVisualizer(const Expression, TypeName, EvalResult: string);
    procedure SetClosedCallback(ClosedProc: TOTAVisualizerClosedProcedure);
    /// <summary>Fenster sofort freigeben (Entladen: keine eingereihte Freigabe) und den Debugger benachrichtigen.
    /// </summary>
    procedure Shutdown;
  end;

  TAtlasIdeVisualizers = class
  public const
    /// <summary>Das Ansichtsfenster darf so viel länger auswerten als der Ersatztext (bis 1000 Zeilen).</summary>
    ViewBudgetFactor = 25;
  private class var
    FRegistered: TList<IOTADebuggerVisualizer>;
    FSignature: string;
    FViewers: TList<TAtlasIdeViewerUpdater>;
    class function SettingsSignature: string; static;
    class procedure Unregister; static;
  public
    /// <summary>Optionen aus den Einstellungen (debug.visualizers.*).</summary>
    class function Options: TAtlasVisualizerOptions; static;
    class function Started: Boolean; static;
    /// <summary>Meldet die Visualisierer der eingeschalteten Arten beim Debugger an.</summary>
    class procedure Start; static;
    class procedure Stop; static;
    /// <summary>Nach einer Einstellungsänderung: aus = Stop, sonst neu anmelden, wenn sich etwas geändert hat.
    /// </summary>
    class procedure ApplySettings; static;
    /// <summary>Ersatztext für den Atlas-Tooltip: Art aus ATypeChain (Typ zuerst, dann Vorfahren); '' = den Wert
    /// der IDE zeigen (aus, keine Art, nichts auswertbar).</summary>
    class function HoverText(const AExpression: string; const ATypeChain: array of string;
      const AEvalResult: string): string; static;
    /// <summary>Ansicht für den Wert; Budget wie das Ansichtsfenster.</summary>
    class function ViewOf(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
      AEvalResult: string): TAtlasVisualizerView; static;
    class procedure ViewerOpened(AViewer: TAtlasIdeViewerUpdater); static;
    class procedure ViewerClosed(AViewer: TAtlasIdeViewerUpdater); static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Debug.Evaluator,
  Atlas.UI.Strings;

const
  IdentifierPrefix = 'Atlas.Visualizer.';
  /// <summary>Arten mit Ansichtsfenster; TGUID und Geometrie haben nur den Ersatztext.</summary>
  ViewerKinds = [TAtlasVisualizerKind.Lists, TAtlasVisualizerKind.Dictionaries, TAtlasVisualizerKind.DataSets,
    TAtlasVisualizerKind.Bytes, TAtlasVisualizerKind.Json, TAtlasVisualizerKind.Colors,
    TAtlasVisualizerKind.Graphics];

function KindCaption(AKind: TAtlasVisualizerKind): string;
const
  Ids: array[TAtlasVisualizerKind] of TAtlasTextId = (TAtlasTextId.DebugVisualizerKindLists,
    TAtlasTextId.DebugVisualizerKindDictionaries, TAtlasTextId.DebugVisualizerKindDataSets,
    TAtlasTextId.DebugVisualizerKindBytes, TAtlasTextId.DebugVisualizerKindJson,
    TAtlasTextId.DebugVisualizerKindColors, TAtlasTextId.DebugVisualizerKindGuid,
    TAtlasTextId.DebugVisualizerKindGeometry, TAtlasTextId.DebugVisualizerKindGraphics);
begin
  Result := TAtlasStrings.Text(Ids[AKind]);
end;

{ TAtlasIdeVisualizer }

constructor TAtlasIdeVisualizer.Create(AKind: TAtlasVisualizerKind);
begin
  inherited Create;
  FKind := AKind;
  FTypes := TAtlasVisualizers.SupportedTypes(AKind);
end;

function TAtlasIdeVisualizer.GetSupportedTypeCount: Integer;
begin
  Result := Length(FTypes);
end;

procedure TAtlasIdeVisualizer.GetSupportedType(Index: Integer; var TypeName: string; var AllDescendants: Boolean);
begin
  if (Index < 0) or (Index > High(FTypes)) then
    Exit;
  TypeName := FTypes[Index].TypeName;
  AllDescendants := FTypes[Index].AllDescendants;
end;

procedure TAtlasIdeVisualizer.GetSupportedType(Index: Integer; var TypeName: string; var AllDescendants: Boolean;
  var IsGeneric: Boolean);
begin
  if (Index < 0) or (Index > High(FTypes)) then
    Exit;
  TypeName := FTypes[Index].TypeName;
  AllDescendants := FTypes[Index].AllDescendants;
  IsGeneric := FTypes[Index].IsGeneric;
end;

function TAtlasIdeVisualizer.GetVisualizerIdentifier: string;
begin
  Result := IdentifierPrefix + TAtlasVisualizers.KindNames[FKind];
end;

function TAtlasIdeVisualizer.GetVisualizerName: string;
begin
  Result := Format(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerName), [KindCaption(FKind)]);
end;

function TAtlasIdeVisualizer.GetVisualizerDescription: string;
begin
  Result := Format(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerDescription), [KindCaption(FKind)]);
end;

function TAtlasIdeVisualizer.GetReplacementValue(const Expression, TypeName, EvalResult: string): string;
var
  Options: TAtlasVisualizerOptions;
  Text: string;
begin
  // '' wäre ein leerer Wert in der Liste der IDE: ohne eigenen Text bleibt der der IDE.
  Result := EvalResult;
  try
    Options := TAtlasIdeVisualizers.Options;
    if not TAtlasIdeSettings.Current.DebugVisualizers or not (FKind in Options.Kinds) then
      Exit;
    Text := TAtlasVisualizers.Replacement(FKind, Expression, TypeName, EvalResult, Options,
      TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs));
    if Text <> '' then
      Result := Text;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeViewerVisualizer }

function TAtlasIdeViewerVisualizer.GetMenuText: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.DebugViewerMenu);
end;

function TAtlasIdeViewerVisualizer.Show(const Expression, TypeName, EvalResult: string; SuggestedLeft,
  SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
begin
  Result := nil;
  try
    Result := TAtlasIdeViewerUpdater.Create(Kind, Expression, TypeName, EvalResult, SuggestedLeft, SuggestedTop);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeViewerUpdater }

constructor TAtlasIdeViewerUpdater.Create(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string; ALeft, ATop: Integer);
begin
  inherited Create;
  FKind := AKind;
  FForm := TAtlasDebugViewer.CreateViewer(Application);
  FForm.OnClosed := FormClosed;
  FForm.Left := ALeft;
  FForm.Top := ATop;
  FForm.MakeFullyVisible;
  TAtlasIdeDockWindow.ApplyIdeTheme(FForm);
  FForm.Show;
  TAtlasIdeVisualizers.ViewerOpened(Self);
  RefreshVisualizer(AExpression, ATypeName, AEvalResult);
end;

destructor TAtlasIdeViewerUpdater.Destroy;
begin
  TAtlasIdeVisualizers.ViewerClosed(Self);
  if FForm <> nil then
  begin
    FForm.OnClosed := nil;
    FForm.Release;
    FForm := nil;
  end;
  inherited;
end;

procedure TAtlasIdeViewerUpdater.FormClosed(Sender: TObject);
var
  Closed: TOTAVisualizerClosedProcedure;
begin
  // Das Fenster gibt sich selbst frei (caFree).
  FForm := nil;
  TAtlasIdeVisualizers.ViewerClosed(Self);
  Closed := FClosed;
  FClosed := nil;
  if Assigned(Closed) then
    Closed;
end;

procedure TAtlasIdeViewerUpdater.CloseVisualizer;
begin
  if FForm <> nil then
    FForm.Close;
end;

procedure TAtlasIdeViewerUpdater.MarkUnavailable(Reason: TOTAVisualizerUnavailableReason);
begin
  if FForm = nil then
    Exit;
  if Reason = ovurProcessRunning then
    FForm.MarkUnavailable(TAtlasStrings.Text(TAtlasTextId.DebugViewerRunning))
  else
    FForm.MarkUnavailable(TAtlasStrings.Text(TAtlasTextId.DebugViewerOutOfScope));
end;

procedure TAtlasIdeViewerUpdater.RefreshVisualizer(const Expression, TypeName, EvalResult: string);
begin
  if FForm = nil then
    Exit;
  try
    FForm.ShowView(Expression, TAtlasIdeVisualizers.ViewOf(FKind, Expression, TypeName, EvalResult));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeViewerUpdater.Shutdown;
var
  Form: TAtlasDebugViewer;
  Closed: TOTAVisualizerClosedProcedure;
begin
  Form := FForm;
  Closed := FClosed;
  FForm := nil;
  FClosed := nil;
  TAtlasIdeVisualizers.ViewerClosed(Self);
  if Form <> nil then
  begin
    Form.OnClosed := nil;
    Form.Free;
  end;
  if Assigned(Closed) then
    Closed;
end;

procedure TAtlasIdeViewerUpdater.SetClosedCallback(ClosedProc: TOTAVisualizerClosedProcedure);
begin
  FClosed := ClosedProc;
end;

{ TAtlasIdeVisualizers }

class function TAtlasIdeVisualizers.Options: TAtlasVisualizerOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasVisualizerOptions.Defaults;
  Result.Kinds := TAtlasVisualizers.ParseKinds(Settings.DebugVisualizerTypes);
  Result.NameFields := TAtlasVisualizers.ParseNameFields(Settings.DebugVisualizerNameFields);
  Result.MaxLength := Settings.DebugVisualizerMaxLength;
  Result.Evaluation := TAtlasVisualizers.ParseEvaluation(Settings.DebugVisualizerEvaluation);
  Result.MaxImagePixels := Settings.DebugVisualizerMaxImagePixels;
end;

class function TAtlasIdeVisualizers.SettingsSignature: string;
begin
  // Angemeldet wird je Art; nur Schalter und Arten verlangen eine neue Anmeldung, der Rest wird je Wert gelesen.
  Result := BoolToStr(TAtlasIdeSettings.Current.DebugVisualizers, True) + '|' +
    TAtlasIdeSettings.Current.DebugVisualizerTypes;
end;

class function TAtlasIdeVisualizers.Started: Boolean;
begin
  Result := FRegistered <> nil;
end;

class procedure TAtlasIdeVisualizers.Start;
var
  Debugger: IOTADebuggerServices;
  Kind: TAtlasVisualizerKind;
  Kinds: TAtlasVisualizerKinds;
  Visualizer: IOTADebuggerVisualizer;
begin
  if Started or not Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Exit;
  FRegistered := TList<IOTADebuggerVisualizer>.Create;
  FSignature := SettingsSignature;
  Kinds := TAtlasVisualizers.ParseKinds(TAtlasIdeSettings.Current.DebugVisualizerTypes);
  for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    if not (Kind in Kinds) then
      Continue;
    if Kind in ViewerKinds then
      Visualizer := TAtlasIdeViewerVisualizer.Create(Kind)
    else
      Visualizer := TAtlasIdeVisualizer.Create(Kind);
    try
      Debugger.RegisterDebugVisualizer(Visualizer);
      FRegistered.Add(Visualizer);
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

class procedure TAtlasIdeVisualizers.Unregister;
var
  Debugger: IOTADebuggerServices;
  Visualizer: IOTADebuggerVisualizer;
begin
  if FRegistered = nil then
    Exit;
  if Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    for Visualizer in FRegistered do
      try
        Debugger.UnregisterDebugVisualizer(Visualizer);
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Debugger, E);
      end;
  FreeAndNil(FRegistered);
end;

class procedure TAtlasIdeVisualizers.Stop;
var
  Viewers: TArray<TAtlasIdeViewerUpdater>;
  Viewer: TAtlasIdeViewerUpdater;
begin
  // Offene Fenster zuerst und sofort: Ihr Code liegt im Package, das gleich entladen werden kann; Close gäbe
  // sie erst über eine eingereihte Nachricht frei.
  if FViewers <> nil then
  begin
    Viewers := FViewers.ToArray;
    for Viewer in Viewers do
      Viewer.Shutdown;
    FreeAndNil(FViewers);
  end;
  Unregister;
  FSignature := '';
end;

class procedure TAtlasIdeVisualizers.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugVisualizers then
  begin
    Stop;
    Exit;
  end;
  // Arten geändert: neu anmelden. Nicht gestartet: Das übernimmt RegisterFeatures.
  if Started and (FSignature <> SettingsSignature) then
  begin
    Unregister;
    Start;
  end;
end;

class function TAtlasIdeVisualizers.HoverText(const AExpression: string; const ATypeChain: array of string;
  const AEvalResult: string): string;
var
  Wanted: TAtlasVisualizerOptions;
  Kind: TAtlasVisualizerKind;
  TypeName: string;
begin
  Result := '';
  if not TAtlasIdeSettings.Current.DebugVisualizers or (Length(ATypeChain) = 0) or
    not TAtlasVisualizers.KindOfChain(ATypeChain, Kind) then
    Exit;
  Wanted := Options;
  if not (Kind in Wanted.Kinds) then
    Exit;
  TypeName := ATypeChain[0];
  try
    Result := TAtlasVisualizers.Replacement(Kind, AExpression, TypeName, AEvalResult, Wanted,
      TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs));
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
      Result := '';
    end;
  end;
end;

class function TAtlasIdeVisualizers.ViewOf(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string): TAtlasVisualizerView;
begin
  Result := TAtlasVisualizers.View(AKind, AExpression, ATypeName, AEvalResult, Options,
    TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs * ViewBudgetFactor));
end;

class procedure TAtlasIdeVisualizers.ViewerOpened(AViewer: TAtlasIdeViewerUpdater);
begin
  if FViewers = nil then
    FViewers := TList<TAtlasIdeViewerUpdater>.Create;
  if not FViewers.Contains(AViewer) then
    FViewers.Add(AViewer);
end;

class procedure TAtlasIdeVisualizers.ViewerClosed(AViewer: TAtlasIdeViewerUpdater);
begin
  if FViewers <> nil then
    FViewers.Remove(AViewer);
end;

end.
