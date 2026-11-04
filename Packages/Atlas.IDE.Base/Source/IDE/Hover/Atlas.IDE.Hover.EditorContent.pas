unit Atlas.IDE.Hover.EditorContent;

// Inhalt des Hover-Tooltips im Editor (#442), ohne Editor-Ereignisse, Zeitgeber und Tastatur (die stehen in
// Atlas.IDE.Hover.Editor):
//   - TAtlasEditorHoverContent: Tooltip, Verlauf der angeklickten Typen (#588), Sitzung, Probleme an der
//     Mausposition (#398) und das Wort unter der Maus.
//   - TAtlasEditorHoverDebug: Wert im angehaltenen Debugger (#891), Erklärung „kein Zugriff“ (#840) und
//     Ersatztext der Visualisierer (#835).
//   - TAtlasEditorHoverActions: Klicks im Tooltip (Typen, Pfad, Zurück, Aktionsleiste, Aktionen unter
//     Problemen #621/#909, Links der XMLDoc #654).
// Die Stufen bauen aufeinander auf; TAtlasEditorHover ist die oberste.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Hover.DebugValue,
  Atlas.UI.Hover.Tip;

type
  TAtlasHoverSessionFunc = reference to function: TLspSession;
  TAtlasHoverLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Probleme an der Stelle (0-basiert, #398).</summary>
  TAtlasHoverProblemsFunc = reference to function(const AFileName: string; ALine, ACharacter: Integer):
    TArray<TAtlasProblem>;
  /// <summary>Bedient Atlas die Datei? Sonst zeigt die IDE ihren eigenen Tooltip.</summary>
  TAtlasHoverHandlesFunc = reference to function(const AFileName: string): Boolean;
  /// <summary>Code-Aktion mit Kennung ATag für den Bereich des Problems ausführen (#621).</summary>
  TAtlasHoverProblemActionProc = reference to procedure(const AProblem: TAtlasProblem; const ATag: string);
  /// <summary>„kein Zugriff“ erklären (#840): AValue mit vorläufiger Erklärung oder unverändert (kein bekannter
  /// Text, abgeschaltet); die fertige Erklärung kommt später im Hauptthread an ADone.</summary>
  TAtlasHoverExplainFunc = reference to function(const AValue: TAtlasDebugValue;
    const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
  /// <summary>Korrektur AFix (Index in AValue.Note.Fixes) ausführen (#840).</summary>
  TAtlasHoverDebugFixProc = reference to procedure(const AValue: TAtlasDebugValue; AFix: Integer);
  /// <summary>Ersatztext für den Wert AExpression (eigene Regel #854, sonst Visualisierer #835); ATypeChain ist der
  /// Typ, dann seine Vorfahren, AText der Text der IDE. '' = den Text der IDE lassen.</summary>
  TAtlasHoverVisualizeFunc = reference to function(const AExpression: string; const ATypeChain: TArray<string>;
    const AText: string): string;

  /// <summary>Lebt der Tooltip noch? Hintergrund-Anfragen prüfen das, bevor sie ihr Ergebnis zeigen.</summary>
  TAtlasHoverAlive = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  /// <summary>Tooltip, Verlauf, Sitzung, Probleme und das Wort unter der Maus.</summary>
  TAtlasEditorHoverContent = class
  protected
    FTip: TAtlasHoverTip;
    FHistory: TAtlasHoverHistory;
    FUsagesCount: Integer;
    FSession: TAtlasHoverSessionFunc;
    FLog: TAtlasHoverLogFunc;
    FProblemsAt: TAtlasHoverProblemsFunc;
    FHandles: TAtlasHoverHandlesFunc;
    // Probleme an der Mausposition; nur Probleme, wenn dort kein Bezeichner steht.
    FProblems: TArray<TAtlasProblem>;
    // FAlive endet mit dem Objekt; Hintergrund-Anfragen und späte Rückrufe prüfen es.
    FAlive: TAtlasHoverAlive;
    FAliveRef: IInterface;
    // Bezeichner unter der Maus bzw. im offenen Tooltip.
    FEditor: TWinControl;
    FView: IOTAEditView;
    FLine: Integer;
    FStart: Integer;
    FMouseCharacter: Integer;
    FProblemsOnly: Boolean;
    FWordRect: TRect;
    FKey: string;
    FShownKey: string;
    procedure Log(const AMessage: string);
    function Handles(const AFileName: string): Boolean;
    function CurrentSession: TLspSession;
    function Fetch(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;
    /// <summary>Inhalt für den Tooltip aus Verlauf, Einstellungen und Problemen.</summary>
    function CurrentView: TAtlasHoverView; virtual;
    procedure Refresh;
    function MouseOverTip: Boolean;
    /// <summary>Liegt der Editor unter der Maus (kein anderes Fenster davor)?</summary>
    function MouseOverEditor: Boolean;
    function CurrentEditView: IOTAEditView;
  public
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
    destructor Destroy; override;
    procedure Hide; virtual;
  end;

  /// <summary>Wert im angehaltenen Debugger (#891) samt Erklärung (#840) und Visualisierern (#835).</summary>
  TAtlasEditorHoverDebug = class(TAtlasEditorHoverContent)
  private class var
    FOnExplain: TAtlasHoverExplainFunc;
    FOnDebugFix: TAtlasHoverDebugFixProc;
    FOnVisualize: TAtlasHoverVisualizeFunc;
  private
    FDebug: TAtlasIdeDebugValues;
    /// <summary>Ersatztext der Visualisierer (#835) zu FDebugValue und Deklaration; Schlüssel des letzten Aufrufs.
    /// </summary>
    FVisualizedKey: string;
    FVisualized: string;
    procedure DebugValueDone(const AKey: string; const AValue: TAtlasDebugValue);
    /// <summary>AValue mit Erklärung „kein Zugriff“ (#840), wenn OnExplain sie gibt; die fertige an
    /// DebugValueDone.</summary>
    function Explain(const AKey: string; const AValue: TAtlasDebugValue): TAtlasDebugValue;
    /// <summary>FDebugValue, aufbereitet von den Visualisierern (#835), sobald Wert und Typ bekannt sind.</summary>
    function VisualizedDebugValue: TAtlasDebugValue;
    procedure TipDebugFix(Sender: TObject; AIndex: Integer);
  protected
    // Ausdruck unter der Maus ('' ohne angehaltenen Prozess) und sein Wert.
    FDebugExpression: string;
    FDebugValue: TAtlasDebugValue;
    /// <summary>Wert des Ausdrucks unter der Maus anfordern (#891); verzögerte Werte ergänzt DebugValueDone.</summary>
    procedure EvaluateDebugValue;
    function CurrentView: TAtlasHoverView; override;
  public
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
    destructor Destroy; override;
    procedure Hide; override;
    /// <summary>Erklärung und Korrekturen bei „kein Zugriff“ (#840); setzt die Kompositionswurzel.</summary>
    class property OnExplain: TAtlasHoverExplainFunc read FOnExplain write FOnExplain;
    class property OnDebugFix: TAtlasHoverDebugFixProc read FOnDebugFix write FOnDebugFix;
    class property OnVisualize: TAtlasHoverVisualizeFunc read FOnVisualize write FOnVisualize;
  end;

  /// <summary>Klicks und Aktionen im Tooltip.</summary>
  TAtlasEditorHoverActions = class(TAtlasEditorHoverDebug)
  private class var
    FOnProblemAction: TAtlasHoverProblemActionProc;
  private
    procedure TipLink(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean);
    procedure TipPath(Sender: TObject; AIndex: Integer);
    procedure TipAction(Sender: TObject; AAction: TAtlasHoverAction);
    /// <summary>Link (href) in der XMLDoc (#654): im Browser öffnen.</summary>
    procedure TipUrl(Sender: TObject; const AUrl: string);
    procedure TipProblemAction(Sender: TObject; AProblem: Integer; AAction: TAtlasHoverProblemAction;
      AItem: Integer);
    procedure ShowUsages;
    /// <summary>Strg+C: markierter Doku-Text, Liste der published-Mitglieder oder Deklaration.</summary>
    procedure CopyToClipboard(const AData: TAtlasHoverData);
  protected
    procedure TipBack(Sender: TObject);
    procedure Execute(AAction: TAtlasHoverAction);
  public
    constructor Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
      const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
    /// <summary>Aktion unter einem uses-Hinweis (#621); setzt die Kompositionswurzel (der Tooltip kennt die
    /// Editorbefehle nicht, A-09), ohne Zuweisung keine.</summary>
    class property OnProblemAction: TAtlasHoverProblemActionProc read FOnProblemAction write FOnProblemAction;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.StrUtils,
  Vcl.Forms,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.Declaration,
  Atlas.Core.Settings.Reassigned,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Results.Commands,
  Atlas.UI.Strings;

{ TAtlasEditorHoverContent }

constructor TAtlasEditorHoverContent.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FProblemsAt := AProblemsAt;
  FHandles := AHandles;
  FUsagesCount := -1;
  FTip := TAtlasHoverTip.Create(nil);
  FHistory := TAtlasHoverHistory.Create(Fetch);
  FAlive := TAtlasHoverAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
end;

destructor TAtlasEditorHoverContent.Destroy;
begin
  if FAlive <> nil then
  begin
    FAlive.Alive := False;
  end;
  FTip.Free;
  FHistory.Free;
  inherited Destroy;
end;

procedure TAtlasEditorHoverContent.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

function TAtlasEditorHoverContent.Handles(const AFileName: string): Boolean;
begin
  Result := not Assigned(FHandles) or FHandles(AFileName);
end;

function TAtlasEditorHoverContent.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
  begin
    Result := FSession();
  end;
end;

function TAtlasEditorHoverContent.Fetch(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;
var
  mSession: TLspSession;
begin
  AData := Default(TAtlasHoverData);
  mSession := CurrentSession;
  Result := (mSession <> nil) and ARef.HasLocation;
  if Result then
  begin
    AData := mSession.HoverDataAt(ARef.FileName, ARef.Line, ARef.Character);
    Result := AData.Found;
  end;
end;

/// <summary>Neu zugewiesen (#712): nur mit der Einstellung und für die gewählten Arten; der Server kennt sie
/// nicht.</summary>
function ShowsReassigned(const AData: TAtlasHoverData): Boolean;
var
  mTargets, mStyle, mColor: string;
  mTarget: TAtlasReassignedTarget;
begin
  Result := TAtlasIdeSettings.ReassignedOn(mTargets, mStyle, mColor) and
    not TAtlasGuard.Disabled(TAtlasFeature.Reassigned) and
    TAtlasReassignedNames.TryTarget(AData.ReassignedTarget, mTarget);
  Result := Result and (mTarget in TAtlasReassignedNames.ParseTargets(mTargets));
end;

function TAtlasEditorHoverContent.CurrentView: TAtlasHoverView;
begin
  Result := TAtlasHoverView.Create(FHistory.Current);
  Result.Path := FHistory.Path;
  Result.Pinned := FHistory.Pinned;
  Result.CanGoBack := FHistory.CanGoBack;
  Result.UsagesCount := FUsagesCount;
  // Anzeige der XMLDoc (#654): hints aus settings.json meldet der Server, sonst die Optionen des Plugins
  // (dieselben Werte, #227).
  if Result.Data.Display.Known then
  begin
    Result.Display := Result.Data.Display;
  end
  else
  begin
    Result.Display := TAtlasDocDisplay.Create(TAtlasDocDisplay.ExpandOf(TAtlasIdeSettings.Current.XmlDocExpand),
      TAtlasIdeSettings.Current.XmlDocMaxLines);
  end;
  if not ShowsReassigned(Result.Data) then
  begin
    Result.Data.ClearReassigned;
  end;
  // Probleme gehören zur Stelle im Editor, nicht zu angeklickten Typen.
  if FHistory.Count <= 1 then
  begin
    Result.Problems := FProblems;
  end;
end;

procedure TAtlasEditorHoverContent.Refresh;
begin
  FTip.ProblemActions := TAtlasIdeSettings.Current.HoverProblemActions;
  FTip.HideCompilerCode := not TAtlasIdeSettings.Current.ProblemsShowCompilerCode;
  FTip.UpdateContent(CurrentView);
end;

procedure TAtlasEditorHoverContent.Hide;
begin
  FTip.HidePopup;
  FHistory.Clear;
  FProblems := nil;
  FUsagesCount := -1;
  FShownKey := '';
  FKey := '';
  FView := nil;
end;

function TAtlasEditorHoverContent.CurrentEditView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

function TAtlasEditorHoverContent.MouseOverEditor: Boolean;
var
  mUnder: HWND;
begin
  // Liegt ein anderes Fenster über dem Editor (z. B. „Units suchen“), kein Tooltip darüber.
  mUnder := WindowFromPoint(Mouse.CursorPos);
  Result := (FEditor <> nil) and FEditor.HandleAllocated and
    ((mUnder = FEditor.Handle) or IsChild(FEditor.Handle, mUnder));
end;

function TAtlasEditorHoverContent.MouseOverTip: Boolean;
begin
  Result := FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos);
end;

{ TAtlasEditorHoverDebug }

constructor TAtlasEditorHoverDebug.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
begin
  inherited Create(ASession, ALog, AProblemsAt, AHandles);
  FDebug := TAtlasIdeDebugValues.Create;
  FTip.OnDebugFix := TipDebugFix;
end;

destructor TAtlasEditorHoverDebug.Destroy;
begin
  FDebug.Free;
  inherited Destroy;
end;

function TAtlasEditorHoverDebug.CurrentView: TAtlasHoverView;
begin
  Result := inherited CurrentView;
  // Der Wert im Debugger gehört zur Stelle im Editor, nicht zu angeklickten Typen.
  if FHistory.Count <= 1 then
  begin
    Result.DebugValue := VisualizedDebugValue;
  end;
end;

/// <summary>Typ der Deklaration, dann seine Vorfahren (für die Visualisierer, #835).</summary>
function TypeChain(const AData: TAtlasHoverData): TArray<string>;
var
  mAncestor: TAtlasHoverTypeRef;
begin
  Result := TArray<string>.Create(TAtlasHoverDeclaration.DeclaredType(AData.Declaration));
  for mAncestor in AData.Ancestors do
  begin
    Result := Result + [mAncestor.Name];
  end;
end;

function TAtlasEditorHoverDebug.VisualizedDebugValue: TAtlasDebugValue;
var
  mData: TAtlasHoverData;
  mKey: string;
begin
  Result := FDebugValue;
  if (FDebugValue.State <> TAtlasDebugValueState.Value) or not Assigned(FOnVisualize) then
  begin
    Exit;
  end;
  mData := FHistory.Current;
  if not mData.Found then
  begin
    Exit;
  end;
  // Einmal je Wert und Typ: Die Visualisierer werten im Debugger aus, Refresh kommt öfter.
  mKey := FDebugValue.Expression + #0 + FDebugValue.Text + #0 + mData.Declaration;
  if mKey <> FVisualizedKey then
  begin
    FVisualizedKey := mKey;
    FVisualized := FOnVisualize(FDebugValue.Expression, TypeChain(mData), FDebugValue.Text);
  end;
  if FVisualized <> '' then
  begin
    Result := TAtlasDebugValue.Evaluated(FDebugValue.Expression, FVisualized);
  end;
end;

procedure TAtlasEditorHoverDebug.Hide;
begin
  FDebug.Cancel;
  FDebugValue := Default(TAtlasDebugValue);
  FVisualizedKey := '';
  FVisualized := '';
  inherited Hide;
end;

procedure TAtlasEditorHoverDebug.EvaluateDebugValue;
var
  mOwner: TAtlasEditorHoverDebug;
  mKey: string;
begin
  FDebug.Cancel;
  FDebugValue := Default(TAtlasDebugValue);
  if (FDebugExpression = '') or FProblemsOnly or not TAtlasIdeSettings.Current.DebugHoverValues then
  begin
    Exit;
  end;
  mOwner := Self;
  mKey := FKey;
  // Im Hauptthread: Der Debugger der IDE ist nicht threadsicher. Sofortige Werte stehen gleich im Tooltip.
  FDebugValue := Explain(mKey, FDebug.Evaluate(FDebugExpression, FView.Buffer.FileName, FLine,
    procedure(const AValue: TAtlasDebugValue)
    begin
      mOwner.DebugValueDone(mKey, mOwner.Explain(mKey, AValue));
    end));
end;

function TAtlasEditorHoverDebug.Explain(const AKey: string; const AValue: TAtlasDebugValue): TAtlasDebugValue;
var
  mOwner: TAtlasEditorHoverDebug;
  mAlive: TAtlasHoverAlive;
  mAliveRef: IInterface;
begin
  Result := AValue;
  if (AValue.State <> TAtlasDebugValueState.Failed) or (AValue.Note.Caption <> '') or (AKey <> FKey) or
    not Assigned(FOnExplain) then
  begin
    Exit;
  end;
  mOwner := Self;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  Result := FOnExplain(AValue,
    procedure(const ADone: TAtlasDebugValue)
    begin
      // mAliveRef hält die Markierung, bis die Erklärung kommt; das Objekt selbst kann schon weg sein.
      if mAlive.Alive and (mAliveRef <> nil) then
      begin
        mOwner.DebugValueDone(AKey, ADone);
      end;
    end);
end;

procedure TAtlasEditorHoverDebug.DebugValueDone(const AKey: string; const AValue: TAtlasDebugValue);
begin
  // Nur für das Wort, auf dem die Maus noch steht; FDebug verwirft ältere Auswertungen ohnehin.
  if AKey <> FKey then
  begin
    Exit;
  end;
  FDebugValue := AValue;
  if not FTip.IsShown or (FShownKey <> AKey) then
  begin
    Exit;
  end;
  // Kein Wert (Fehler, weitergelaufen) und sonst nichts zu zeigen: schließen.
  if not FDebugValue.Visible and not FHistory.Current.Found and (Length(FProblems) = 0) then
  begin
    Hide;
  end
  else
  begin
    Refresh;
  end;
end;

procedure TAtlasEditorHoverDebug.TipDebugFix(Sender: TObject; AIndex: Integer);
var
  mValue: TAtlasDebugValue;
begin
  try
    mValue := FTip.View.DebugValue;
    if not Assigned(FOnDebugFix) or (AIndex < 0) or (AIndex > High(mValue.Note.Fixes)) then
    begin
      Exit;
    end;
    Hide;
    FOnDebugFix(mValue, AIndex);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

{ TAtlasEditorHoverActions }

constructor TAtlasEditorHoverActions.Create(const ASession: TAtlasHoverSessionFunc; const ALog: TAtlasHoverLogFunc;
  const AProblemsAt: TAtlasHoverProblemsFunc; const AHandles: TAtlasHoverHandlesFunc);
begin
  inherited Create(ASession, ALog, AProblemsAt, AHandles);
  FTip.OnLink := TipLink;
  FTip.OnPath := TipPath;
  FTip.OnBack := TipBack;
  FTip.OnAction := TipAction;
  FTip.OnUrl := TipUrl;
  FTip.OnProblemAction := TipProblemAction;
end;

procedure TAtlasEditorHoverActions.TipLink(Sender: TObject; const ARef: TAtlasHoverTypeRef; AControl: Boolean);
begin
  try
    // Strg+Klick: wie bisher zur Deklaration im Quelltext.
    if AControl then
    begin
      if ARef.HasLocation then
      begin
        Hide;
        TAtlasIdeNavigation.GoToLocation(ARef.FileName, ARef.Line, ARef.Character);
      end;
      Exit;
    end;
    if FHistory.Open(ARef) then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

procedure TAtlasEditorHoverActions.TipPath(Sender: TObject; AIndex: Integer);
begin
  try
    if FHistory.JumpTo(AIndex) then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverActions.TipBack(Sender: TObject);
begin
  try
    if FHistory.Back then
    begin
      FUsagesCount := -1;
      Refresh;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverActions.TipAction(Sender: TObject; AAction: TAtlasHoverAction);
begin
  try
    Execute(AAction);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverActions.TipProblemAction(Sender: TObject; AProblem: Integer;
  AAction: TAtlasHoverProblemAction; AItem: Integer);
const
  // Related und ShowGraph (#896) sind Client-Aktionen: „related:<Stelle>“ springt an Problem.Related[Stelle].
  Tags: array[TAtlasHoverProblemAction] of string = ('uses.remove', 'uses.removeAll', 'uses.move', 'rule.fix',
    'rule.suppressLine', 'rule.configure', 'related:', 'cycle.showGraph');
var
  mProblem: TAtlasProblem;
  mTag: string;
begin
  try
    if not Assigned(FOnProblemAction) or (AProblem < 0) or (AProblem > High(FTip.View.Problems)) then
    begin
      Exit;
    end;
    mProblem := FTip.View.Problems[AProblem];
    mTag := Tags[AAction];
    if AAction = TAtlasHoverProblemAction.Related then
    begin
      mTag := mTag + IntToStr(AItem);
    end;
    Hide;
    FOnProblemAction(mProblem, mTag);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverActions.TipUrl(Sender: TObject; const AUrl: string);
begin
  try
    // Nur Web- und Mail-Adressen; andere Schemata (file:, Programme) öffnet der Tooltip nicht.
    if StartsText('http://', AUrl) or StartsText('https://', AUrl) or StartsText('mailto:', AUrl) then
    begin
      ShellExecute(0, 'open', PChar(AUrl), nil, nil, SW_SHOWNORMAL);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverActions.ShowUsages;
var
  mData: TAtlasHoverData;
begin
  mData := FHistory.Current;
  if (CurrentSession = nil) or not mData.Location.HasLocation then
  begin
    Exit;
  end;
  // Im Ergebnisfenster (#400), nach Unit gruppiert, samt Fundstellen in Formularen.
  FUsagesCount := TAtlasIdeResults.ShowReferences(mData.Location.FileName, mData.Location.Line,
    mData.Location.Character, mData.Title);
  Refresh;
end;

procedure TAtlasEditorHoverActions.CopyToClipboard(const AData: TAtlasHoverData);
begin
  // Markierter Doku-Text (#654) hat Vorrang, bei Komponentenklassen die gezeigte Liste (#110), sonst die
  // Deklaration.
  if FTip.HasSelection then
  begin
    Clipboard.AsText := FTip.SelectedText;
  end
  else if Length(AData.Members) > 0 then
  begin
    Clipboard.AsText := AData.MembersText(not FTip.View.HideInherited, FTip.View.OnlyDefaults,
      TAtlasStrings.Text(TAtlasTextId.PublishedImplicit));
  end
  else
  begin
    Clipboard.AsText := AData.Declaration;
  end;
end;

procedure TAtlasEditorHoverActions.Execute(AAction: TAtlasHoverAction);
var
  mData: TAtlasHoverData;
begin
  try
    mData := FHistory.Current;
    case AAction of
      TAtlasHoverAction.Navigate:
        if mData.Location.HasLocation then
        begin
          Hide;
          TAtlasIdeNavigation.GoToLocation(mData.Location.FileName, mData.Location.Line, mData.Location.Character);
        end;
      TAtlasHoverAction.Usages:
        ShowUsages;
      TAtlasHoverAction.Copy:
        CopyToClipboard(mData);
      TAtlasHoverAction.Help:
        if mData.DocWiki <> '' then
        begin
          ShellExecute(0, 'open', PChar(mData.DocWiki), nil, nil, SW_SHOWNORMAL);
        end;
    end;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
    end;
  end;
end;

end.
