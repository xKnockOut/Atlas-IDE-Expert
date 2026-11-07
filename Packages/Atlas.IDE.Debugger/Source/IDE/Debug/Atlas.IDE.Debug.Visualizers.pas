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
// - Das Ansichtsfenster (TAtlasIdeViewerUpdater) holt seinen Inhalt über eine
//   Quelle (TAtlasViewSource); die eigenen Wertdarstellungen (#854) nutzen es
//   mit ihrer Tabelle. Jedes Fenster gehört einer Gruppe, damit Stop nur die
//   eigenen schließt.
// - Visualisierer der Open Tools API laufen laut Embarcadero nur mit dem
//   32-Bit-Debugger ohne LLDB. Für Win64 und Hover bereitet HoverText den Wert
//   im Atlas-Tooltip auf (Art aus Typ und Vorfahren laut Server).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.UI.Debug.Viewer;

type
  /// <summary>Inhalt des Ansichtsfensters für einen Wert.</summary>
  TAtlasViewSource = reference to function(const AExpression, ATypeName, AEvalResult: string): TAtlasVisualizerView;

  {$SCOPEDENUMS ON}
  /// <summary>Wem ein Ansichtsfenster gehört (Stop schließt nur die eigenen).</summary>
  TAtlasViewerGroup = (Visualizers, DisplayRules);
  {$SCOPEDENUMS OFF}

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
    FGroup: TAtlasViewerGroup;
    FSource: TAtlasViewSource;
    FForm: TAtlasDebugViewer;
    FClosed: TOTAVisualizerClosedProcedure;
    procedure FormClosed(Sender: TObject);
  public
    /// <summary>Fenster an APosition (links oben) öffnen und den Wert zeigen.</summary>
    constructor Create(AGroup: TAtlasViewerGroup; const ASource: TAtlasViewSource; const AExpression, ATypeName,
      AEvalResult: string; const APosition: TPoint);
    destructor Destroy; override;
    { IOTADebuggerVisualizerExternalViewerUpdater }
    procedure CloseVisualizer;
    procedure MarkUnavailable(Reason: TOTAVisualizerUnavailableReason);
    procedure RefreshVisualizer(const Expression, TypeName, EvalResult: string);
    procedure SetClosedCallback(ClosedProc: TOTAVisualizerClosedProcedure);
    /// <summary>Fenster sofort freigeben (Entladen: keine eingereihte Freigabe) und den Debugger benachrichtigen.
    /// </summary>
    procedure Shutdown;
    property Group: TAtlasViewerGroup read FGroup;
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
    /// <summary>Quelle für das Ansichtsfenster einer Art.</summary>
    class function KindSource(AKind: TAtlasVisualizerKind): TAtlasViewSource; static;
    /// <summary>Offene Ansichtsfenster der Gruppe sofort freigeben (Entladen, Abschalten).</summary>
    class procedure CloseViewers(AGroup: TAtlasViewerGroup); static;
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
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

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
  begin
    Exit;
  end;
  TypeName := FTypes[Index].TypeName;
  AllDescendants := FTypes[Index].AllDescendants;
end;

procedure TAtlasIdeVisualizer.GetSupportedType(Index: Integer; var TypeName: string; var AllDescendants: Boolean;
  var IsGeneric: Boolean);
begin
  if (Index < 0) or (Index > High(FTypes)) then
  begin
    Exit;
  end;
  TypeName := FTypes[Index].TypeName;
  AllDescendants := FTypes[Index].AllDescendants;
  IsGeneric := FTypes[Index].IsGeneric;
end;

function TAtlasIdeVisualizer.GetVisualizerIdentifier: string;
begin
  Result := IdentifierPrefix + TAtlasVisualizerSettings.cKindNames[FKind];
end;

function TAtlasIdeVisualizer.GetVisualizerName: string;
begin
  Result := Format(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugVisualizerName), [KindCaption(FKind)]);
end;

function TAtlasIdeVisualizer.GetVisualizerDescription: string;
begin
  Result := Format(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugVisualizerDescription), [KindCaption(FKind)]);
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
    begin
      Exit;
    end;
    Text := TAtlasVisualizers.Replacement(FKind, Expression, TypeName, EvalResult, Options,
      TAtlasIdeDebugEvaluator.Context(TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs));
    if Text <> '' then
    begin
      Result := Text;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeViewerVisualizer }

function TAtlasIdeViewerVisualizer.GetMenuText: string;
begin
  Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerMenu);
end;

function TAtlasIdeViewerVisualizer.Show(const Expression, TypeName, EvalResult: string; SuggestedLeft,
  SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
begin
  Result := nil;
  try
    Result := TAtlasIdeViewerUpdater.Create(TAtlasViewerGroup.Visualizers, TAtlasIdeVisualizers.KindSource(Kind),
      Expression, TypeName, EvalResult, Point(SuggestedLeft, SuggestedTop));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeViewerUpdater }

constructor TAtlasIdeViewerUpdater.Create(AGroup: TAtlasViewerGroup; const ASource: TAtlasViewSource;
  const AExpression, ATypeName, AEvalResult: string; const APosition: TPoint);
begin
  inherited Create;
  FGroup := AGroup;
  FSource := ASource;
  FForm := TAtlasDebugViewer.CreateViewer(Application);
  FForm.OnClosed := FormClosed;
  FForm.Left := APosition.X;
  FForm.Top := APosition.Y;
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
  begin
    Closed;
  end;
end;

procedure TAtlasIdeViewerUpdater.CloseVisualizer;
begin
  if FForm <> nil then
  begin
    FForm.Close;
  end;
end;

procedure TAtlasIdeViewerUpdater.MarkUnavailable(Reason: TOTAVisualizerUnavailableReason);
begin
  if FForm = nil then
  begin
    Exit;
  end;
  if Reason = ovurProcessRunning then
  begin
    FForm.MarkUnavailable(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerRunning));
  end
  else
  begin
    FForm.MarkUnavailable(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugViewerOutOfScope));
  end;
end;

procedure TAtlasIdeViewerUpdater.RefreshVisualizer(const Expression, TypeName, EvalResult: string);
begin
  if FForm = nil then
  begin
    Exit;
  end;
  try
    FForm.ShowView(Expression, FSource(Expression, TypeName, EvalResult));
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
  begin
    Closed;
  end;
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
  Result.Kinds := TAtlasVisualizerSettings.ParseKinds(Settings.DebugVisualizerTypes);
  Result.NameFields := TAtlasVisualizerSettings.ParseNameFields(Settings.DebugVisualizerNameFields);
  Result.MaxLength := Settings.DebugVisualizerMaxLength;
  Result.Evaluation := TAtlasVisualizerSettings.ParseEvaluation(Settings.DebugVisualizerEvaluation);
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
  begin
    Exit;
  end;
  FRegistered := TList<IOTADebuggerVisualizer>.Create;
  FSignature := SettingsSignature;
  Kinds := TAtlasVisualizerSettings.ParseKinds(TAtlasIdeSettings.Current.DebugVisualizerTypes);
  for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    if not (Kind in Kinds) then
    begin
      Continue;
    end;
    if Kind in ViewerKinds then
    begin
      Visualizer := TAtlasIdeViewerVisualizer.Create(Kind);
    end
    else
    begin
      Visualizer := TAtlasIdeVisualizer.Create(Kind);
    end;
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
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
  begin
    for Visualizer in FRegistered do
      try
        Debugger.UnregisterDebugVisualizer(Visualizer);
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Debugger, E);
      end;
  end;
  FreeAndNil(FRegistered);
end;

class procedure TAtlasIdeVisualizers.CloseViewers(AGroup: TAtlasViewerGroup);
var
  Viewers: TArray<TAtlasIdeViewerUpdater>;
  Viewer: TAtlasIdeViewerUpdater;
begin
  // Sofort freigeben: Ihr Code liegt im Package, das gleich entladen werden kann; Close gäbe sie erst über eine
  // eingereihte Nachricht frei.
  if FViewers = nil then
  begin
    Exit;
  end;
  Viewers := FViewers.ToArray;
  for Viewer in Viewers do
  begin
    if Viewer.Group = AGroup then
    begin
      Viewer.Shutdown;
    end;
  end;
  if FViewers.Count = 0 then
  begin
    FreeAndNil(FViewers);
  end;
end;

class function TAtlasIdeVisualizers.KindSource(AKind: TAtlasVisualizerKind): TAtlasViewSource;
begin
  Result :=
    function(const AExpression, ATypeName, AEvalResult: string): TAtlasVisualizerView
    begin
      Result := ViewOf(AKind, AExpression, ATypeName, AEvalResult);
    end;
end;

class procedure TAtlasIdeVisualizers.Stop;
begin
  CloseViewers(TAtlasViewerGroup.Visualizers);
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
  begin
    Exit;
  end;
  Wanted := Options;
  if not (Kind in Wanted.Kinds) then
  begin
    Exit;
  end;
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
  begin
    FViewers := TList<TAtlasIdeViewerUpdater>.Create;
  end;
  if not FViewers.Contains(AViewer) then
  begin
    FViewers.Add(AViewer);
  end;
end;

class procedure TAtlasIdeVisualizers.ViewerClosed(AViewer: TAtlasIdeViewerUpdater);
begin
  if FViewers <> nil then
  begin
    FViewers.Remove(AViewer);
  end;
end;

end.
