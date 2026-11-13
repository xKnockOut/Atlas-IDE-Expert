unit Atlas.IDE.Hover.EditorContent;

// Inhalt des Hover-Tooltips im Editor (#442), ohne Editor-Ereignisse, Zeitgeber und Tastatur (die stehen in
// Atlas.IDE.Hover.Editor):
//   - TAtlasEditorHoverContent: Tooltip, Verlauf der angeklickten Typen (#588), Sitzung, Probleme an der
//     Mausposition (#398) und das Wort unter der Maus.
//   - TAtlasEditorHoverDebug: Wert im angehaltenen Debugger (#891), Erklärung „kein Zugriff“ (#840) und
//     Ersatztext der Visualisierer (#835); Zeilen und Änderungen des aufgeklappten Werts (#895) kommen über
//     OnDebugTree, die Aktionen wirken auf die gewählte Zeile.
//   - TAtlasEditorHoverActions: Klicks im Tooltip (Typen, Pfad, Zurück, Aktionsleiste, Aktionen unter
//     Problemen #621/#909, Links der XMLDoc #654). „Beispiel zeigen“ (#145) holt den Katalogtext über
//     OnRuleExample, klappt ihn im Tooltip auf und heftet ihn an; ein neuer Hover beginnt zugeklappt.
// Die Stufen bauen aufeinander auf; TAtlasEditorHover ist die oberste.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Hover.View,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Explanation,
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
  /// <summary>Katalogtext der Regel ARule (#145) an ADone im Hauptthread, sofort oder nach der Antwort des Servers.
  /// </summary>
  TAtlasHoverRuleExampleProc = reference to procedure(const ARule: string; const ADone: TAtlasRuleExplanationEvent);
  /// <summary>„kein Zugriff“ erklären (#840): AValue mit vorläufiger Erklärung oder unverändert (kein bekannter
  /// Text, abgeschaltet); die fertige Erklärung kommt später im Hauptthread an ADone.</summary>
  TAtlasHoverExplainFunc = reference to function(const AValue: TAtlasDebugValue;
    const ADone: TAtlasDebugValueEvent): TAtlasDebugValue;
  /// <summary>Korrektur AFix (Index in AValue.Note.Fixes) ausführen (#840).</summary>
  TAtlasHoverDebugFixProc = reference to procedure(const AValue: TAtlasDebugValue; AFix: Integer);
  /// <summary>Aktionen unter dem Wert AValue (Anheften #526); leer ohne.</summary>
  TAtlasHoverDebugActionsFunc = reference to function(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>;
  /// <summary>Aktion mit Id AAction für AValue an der Stelle AFileName, ALine (1-basiert) ausführen (#526).</summary>
  TAtlasHoverDebugActionProc = reference to procedure(const AValue: TAtlasDebugValue; const AFileName: string;
    ALine, AAction: Integer);
  /// <summary>Aufklappen und Änderungen (#895): AValue an AFileName, ALine (1-basiert) mit Zeilen, altem Wert und
  /// Aufklappzustand; unverändert, wenn abgeschaltet. ARefresh im Hauptthread, sobald ausstehende Kinder da sind.
  /// </summary>
  TAtlasHoverDebugTreeFunc = reference to function(const AValue: TAtlasDebugValue; const AFileName: string;
    ALine: Integer; const ARefresh: TProc): TAtlasDebugValue;
  /// <summary>Zeile ARow (Index in AValue.Rows, -1 der Wert selbst) auf- bzw. zuklappen, „weitere …“ laden
  /// oder den Getter auswerten (#895).</summary>
  TAtlasHoverDebugRowProc = reference to procedure(const AValue: TAtlasDebugValue; ARow: Integer);
  /// <summary>Ersatztext für den Wert AExpression (eigene Regel #854, sonst Visualisierer #835); ATypeChain ist der
  /// Typ, dann seine Vorfahren, AText der Text der IDE. '' = den Text der IDE lassen.</summary>
  TAtlasHoverVisualizeFunc = reference to function(const AExpression: string; const ATypeChain: TArray<string>;
    const AText: string): string;
  /// <summary>Erklärung eines Problems aus dem Katalog (#54); Known False ohne Eintrag.</summary>
  TAtlasHoverExplanationFunc = reference to function(const AProblem: TAtlasProblem): TAtlasHoverExplanation;
  /// <summary>Lässt sich unter AProblem erwartet und erhalten eines fehlgeschlagenen Tests vergleichen (#1779)?
  /// </summary>
  TAtlasHoverComparableFunc = reference to function(const AProblem: TAtlasProblem): Boolean;

  /// <summary>Lebt der Tooltip noch? Hintergrund-Anfragen prüfen das, bevor sie ihr Ergebnis zeigen.</summary>
  TAtlasHoverAlive = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  /// <summary>Tooltip, Verlauf, Sitzung, Probleme und das Wort unter der Maus.</summary>
  TAtlasEditorHoverContent = class
  private class var
    FOnExplanation: TAtlasHoverExplanationFunc;
    FOnComparable: TAtlasHoverComparableFunc;
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
    // Aufgeklappte Beispiele je Problem (#145), gleicher Index wie FProblems; neu je Hover.
    FExamples: TArray<TAtlasRuleExplanation>;
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
    /// <summary>Erklärungen zu AProblems (#54); nil, wenn abgeschaltet.</summary>
    class function Explanations(const AProblems: TArray<TAtlasProblem>): TArray<TAtlasHoverExplanation>; static;
    /// <summary>„Vergleichen“ je Problem (#1779); nil ohne Zuweisung.</summary>
    class function Comparisons(const AProblems: TArray<TAtlasProblem>): TArray<Boolean>; static;
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
    /// <summary>Erklärungen zu Compilermeldungen und Regeln (#54, hover.explainMessages); setzt die
    /// Kompositionswurzel, ohne Zuweisung keine.</summary>
    class property OnExplanation: TAtlasHoverExplanationFunc read FOnExplanation write FOnExplanation;
    /// <summary>Fehlgeschlagene Tests mit erwartetem und erhaltenem Wert (#1779); setzt die Kompositionswurzel.
    /// </summary>
    class property OnComparable: TAtlasHoverComparableFunc read FOnComparable write FOnComparable;
  end;

  /// <summary>Wert im angehaltenen Debugger (#891) samt Erklärung (#840) und Visualisierern (#835).</summary>
  TAtlasEditorHoverDebug = class(TAtlasEditorHoverContent)
  private class var
    FOnExplain: TAtlasHoverExplainFunc;
    FOnDebugFix: TAtlasHoverDebugFixProc;
    FOnVisualize: TAtlasHoverVisualizeFunc;
    FOnDebugActions: TAtlasHoverDebugActionsFunc;
    FOnDebugAction: TAtlasHoverDebugActionProc;
    FOnDebugTree: TAtlasHoverDebugTreeFunc;
    FOnDebugRow: TAtlasHoverDebugRowProc;
  private
    FDebug: TAtlasIdeDebugValues;
    /// <summary>Kontextmenü einer Zeile des aufgeklappten Werts (#895), beim ersten Rechtsklick angelegt.</summary>
    FMenu: TPopupMenu;
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
    procedure TipDebugAction(Sender: TObject; AIndex: Integer);
    procedure TipDebugRow(Sender: TObject; AIndex: Integer; AMenu: Boolean);
    /// <summary>Aktionen der gewählten Zeile als Kontextmenü (#895).</summary>
    procedure DebugRowMenu;
    procedure DebugMenuClick(Sender: TObject);
    /// <summary>Refresh, solange derselbe Bezeichner im Tooltip steht (nachgereichte Kinder, #895).</summary>
    function DebugTreeRefresh: TProc;
    /// <summary>Wert, auf den die Aktionen wirken: die gewählte Zeile des aufgeklappten Werts (#895), sonst AValue.
    /// </summary>
    class function Subject(const AValue: TAtlasDebugValue; ARow: Integer): TAtlasDebugValue; static;
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
    /// <summary>Aktionen unter dem Wert und ihre Ausführung (#526); setzt die Kompositionswurzel.</summary>
    class property OnDebugActions: TAtlasHoverDebugActionsFunc read FOnDebugActions write FOnDebugActions;
    class property OnDebugAction: TAtlasHoverDebugActionProc read FOnDebugAction write FOnDebugAction;
    /// <summary>Aufklappen und Änderungen (#895); setzt die Kompositionswurzel.</summary>
    class property OnDebugTree: TAtlasHoverDebugTreeFunc read FOnDebugTree write FOnDebugTree;
    class property OnDebugRow: TAtlasHoverDebugRowProc read FOnDebugRow write FOnDebugRow;
  end;

  /// <summary>Klicks und Aktionen im Tooltip.</summary>
  TAtlasEditorHoverActions = class(TAtlasEditorHoverDebug)
  private class var
    FOnProblemAction: TAtlasHoverProblemActionProc;
    FOnRuleExample: TAtlasHoverRuleExampleProc;
  private
    /// <summary>„Beispiel zeigen“ bzw. „ausblenden“ unter Problem AProblem (#145).</summary>
    procedure ToggleExample(AProblem: Integer);
    /// <summary>Katalogtext ist da: aufklappen, wenn derselbe Tooltip (AKey) noch dasselbe Problem zeigt.</summary>
    procedure ExampleDone(const AKey: string; AProblem: Integer; const ARule: string;
      const AExplanation: TAtlasRuleExplanation);
    procedure SetExample(AProblem: Integer; const AExample: TAtlasRuleExplanation);
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
    /// Editorbefehle nicht), ohne Zuweisung keine.</summary>
    class property OnProblemAction: TAtlasHoverProblemActionProc read FOnProblemAction write FOnProblemAction;
    /// <summary>Katalogtext für „Beispiel zeigen“ (#145); setzt die Kompositionswurzel, ohne Zuweisung bleibt das
    /// Beispiel zu.</summary>
    class property OnRuleExample: TAtlasHoverRuleExampleProc read FOnRuleExample write FOnRuleExample;
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
  Atlas.UI.Hover.Strings;

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
    // Sprung im Tooltip: Der Hauptthread wartet, deshalb kurzes Zeitlimit.
    AData := mSession.HoverDataAt(ARef.FileName, ARef.Line, ARef.Character, TLspSession.cMainThreadTimeoutMs);
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
    Result.Explanations := Explanations(FProblems);
    Result.Comparisons := Comparisons(FProblems);
    Result.Examples := FExamples;
  end;
end;

class function TAtlasEditorHoverContent.Explanations(const AProblems: TArray<TAtlasProblem>):
  TArray<TAtlasHoverExplanation>;
var
  mIndex: Integer;
begin
  Result := nil;
  if not Assigned(FOnExplanation) or not TAtlasIdeSettings.Current.HoverExplainMessages then
  begin
    Exit;
  end;
  SetLength(Result, Length(AProblems));
  for mIndex := 0 to High(AProblems) do
  begin
    Result[mIndex] := FOnExplanation(AProblems[mIndex]);
  end;
end;

class function TAtlasEditorHoverContent.Comparisons(const AProblems: TArray<TAtlasProblem>): TArray<Boolean>;
var
  mIndex: Integer;
begin
  Result := nil;
  if not Assigned(FOnComparable) then
  begin
    Exit;
  end;
  SetLength(Result, Length(AProblems));
  for mIndex := 0 to High(AProblems) do
  begin
    Result[mIndex] := FOnComparable(AProblems[mIndex]);
  end;
end;

procedure TAtlasEditorHoverContent.Refresh;
begin
  FTip.ProblemActions := TAtlasIdeSettings.Current.HoverProblemActions;
  FTip.RuleExamples := TAtlasIdeSettings.Current.HoverRuleExamples;
  FTip.HideCompilerCode := not TAtlasIdeSettings.Current.ProblemsShowCompilerCode;
  FTip.MembersMaxLines := TAtlasIdeSettings.Current.HoverMembersMaxLines;
  FTip.SignatureParams := TAtlasIdeSettings.Current.HoverSignatureParams;
  FTip.UpdateContent(CurrentView);
end;

procedure TAtlasEditorHoverContent.Hide;
begin
  FTip.HidePopup;
  FHistory.Clear;
  FProblems := nil;
  FExamples := nil;
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
  FTip.OnDebugAction := TipDebugAction;
  FTip.OnDebugRow := TipDebugRow;
end;

destructor TAtlasEditorHoverDebug.Destroy;
begin
  FMenu.Free;
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
    if Result.DebugValue.State <> TAtlasDebugValueState.Value then
    begin
      Exit;
    end;
    if Assigned(FOnDebugTree) and (FView <> nil) then
    begin
      Result.DebugValue := FOnDebugTree(Result.DebugValue, FView.Buffer.FileName, FLine, DebugTreeRefresh);
    end;
    // Aktionen wirken auf die gewählte Zeile (#895).
    if Assigned(FOnDebugActions) then
    begin
      Result.DebugValue.Actions := FOnDebugActions(Subject(Result.DebugValue, FTip.DebugSelectedIndex));
    end;
  end;
end;

class function TAtlasEditorHoverDebug.Subject(const AValue: TAtlasDebugValue; ARow: Integer): TAtlasDebugValue;
begin
  Result := AValue;
  if (ARow < 0) or (ARow > High(AValue.Rows)) or AValue.Rows[ARow].More then
  begin
    Exit;
  end;
  Result.Expression := AValue.Rows[ARow].Expression;
  Result.Text := AValue.Rows[ARow].Text;
  Result.OldText := AValue.Rows[ARow].OldText;
  Result.Expandable := AValue.Rows[ARow].Expandable;
  Result.Expanded := AValue.Rows[ARow].Expanded;
  Result.Rows := nil;
  // Ausstehender Wert oder nicht ausgewerteter Getter: noch nichts zum Kopieren, Anheften oder Ändern.
  if AValue.Rows[ARow].Pending or AValue.Rows[ARow].Lazy then
  begin
    Result.State := TAtlasDebugValueState.Pending;
  end;
end;

function TAtlasEditorHoverDebug.DebugTreeRefresh: TProc;
var
  mOwner: TAtlasEditorHoverDebug;
  mAlive: TAtlasHoverAlive;
  mAliveRef: IInterface;
  mKey: string;
begin
  mOwner := Self;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  mKey := FKey;
  Result :=
    procedure
    begin
      if mAlive.Alive and (mAliveRef <> nil) and (mOwner.FShownKey = mKey) and mOwner.FTip.IsShown then
      begin
        mOwner.Refresh;
      end;
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

procedure TAtlasEditorHoverDebug.TipDebugAction(Sender: TObject; AIndex: Integer);
var
  mValue: TAtlasDebugValue;
  mFileName: string;
  mLine: Integer;
begin
  try
    mValue := Subject(FTip.View.DebugValue, FTip.DebugSelectedIndex);
    if not Assigned(FOnDebugAction) or (FView = nil) or (AIndex < 0) or (AIndex > High(mValue.Actions)) then
    begin
      Exit;
    end;
    // Stelle vor Hide sichern: Hide vergisst den Bezeichner unter der Maus.
    mFileName := FView.Buffer.FileName;
    mLine := FLine;
    Hide;
    FOnDebugAction(mValue, mFileName, mLine, mValue.Actions[AIndex].Id);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverDebug.TipDebugRow(Sender: TObject; AIndex: Integer; AMenu: Boolean);
begin
  try
    if AMenu then
    begin
      DebugRowMenu;
      Exit;
    end;
    // Klick wählt die Zeile; aufklappbare klappen, Getter und „weitere …“ werten aus. Refresh holt die neuen
    // Zeilen und die Aktionen der gewählten.
    if Assigned(FOnDebugRow) then
    begin
      FOnDebugRow(FTip.View.DebugValue, AIndex);
    end;
    Refresh;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

procedure TAtlasEditorHoverDebug.DebugRowMenu;
var
  mActions: TArray<TAtlasDebugValueFix>;
  mItem: TMenuItem;
  mIndex: Integer;
begin
  // Aktionen der eben gewählten Zeile (Refresh rechnet sie neu) als Kontextmenü.
  Refresh;
  mActions := FTip.View.DebugValue.Actions;
  if Length(mActions) = 0 then
  begin
    Exit;
  end;
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(nil);
  end;
  FMenu.Items.Clear;
  for mIndex := 0 to High(mActions) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mActions[mIndex].Caption;
    mItem.Tag := mIndex;
    mItem.OnClick := DebugMenuClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

procedure TAtlasEditorHoverDebug.DebugMenuClick(Sender: TObject);
begin
  TipDebugAction(Sender, TMenuItem(Sender).Tag);
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
  // Explain (#54) öffnet den Dialog „Erklären“; DocWiki öffnet der Tooltip selbst; Example (#145) bleibt im
  // Tooltip und hat keine Kennung; Compare (#1779) zeigt erwartet und erhalten des Tests.
  cTags: array[TAtlasHoverProblemAction] of string = ('uses.remove', 'uses.removeAll', 'uses.move', 'rule.fix',
    'rule.suppressLine', 'rule.configure', 'related:', 'cycle.showGraph', 'problem.explain', '', '', 'test.compare');
var
  mProblem: TAtlasProblem;
  mTag: string;
begin
  try
    if AAction = TAtlasHoverProblemAction.Example then
    begin
      ToggleExample(AProblem);
      Exit;
    end;
    if not Assigned(FOnProblemAction) or (AProblem < 0) or (AProblem > High(FTip.View.Problems)) then
    begin
      Exit;
    end;
    mProblem := FTip.View.Problems[AProblem];
    if AAction = TAtlasHoverProblemAction.DocWiki then
    begin
      if AProblem <= High(FTip.View.Explanations) then
      begin
        mTag := FTip.View.Explanations[AProblem].DocWiki;
        Hide;
        TipUrl(Self, mTag);
      end;
      Exit;
    end;
    mTag := cTags[AAction];
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

procedure TAtlasEditorHoverActions.SetExample(AProblem: Integer; const AExample: TAtlasRuleExplanation);
begin
  if Length(FExamples) <> Length(FProblems) then
  begin
    SetLength(FExamples, Length(FProblems));
  end;
  if (AProblem >= 0) and (AProblem <= High(FExamples)) then
  begin
    FExamples[AProblem] := AExample;
  end;
  FTip.SetExample(AProblem, AExample, FHistory.Pinned);
end;

procedure TAtlasEditorHoverActions.ToggleExample(AProblem: Integer);
var
  mOwner: TAtlasEditorHoverActions;
  mAlive: TAtlasHoverAlive;
  mAliveRef: IInterface;
  mKey, mRule: string;
begin
  if (AProblem < 0) or (AProblem > High(FTip.View.Problems)) then
  begin
    Exit;
  end;
  if FTip.View.ExampleShown(AProblem) then
  begin
    SetExample(AProblem, Default(TAtlasRuleExplanation));
    Exit;
  end;
  if not Assigned(FOnRuleExample) then
  begin
    Exit;
  end;
  // Angeheftet wie nach einem Klick auf einen Typ: Der Tooltip bleibt, während man das Beispiel liest.
  FHistory.Pinned := True;
  mRule := FTip.View.Problems[AProblem].Code;
  mKey := FShownKey;
  mOwner := Self;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  FOnRuleExample(mRule,
    procedure(const AExplanation: TAtlasRuleExplanation)
    begin
      // mAliveRef hält die Markierung, bis der Katalog kommt; das Objekt selbst kann schon weg sein.
      if mAlive.Alive and (mAliveRef <> nil) then
      begin
        mOwner.ExampleDone(mKey, AProblem, mRule, AExplanation);
      end;
    end);
end;

procedure TAtlasEditorHoverActions.ExampleDone(const AKey: string; AProblem: Integer; const ARule: string;
  const AExplanation: TAtlasRuleExplanation);
var
  mExample: TAtlasRuleExplanation;
begin
  try
    if not FTip.IsShown or (AKey <> FShownKey) or (AProblem > High(FTip.View.Problems)) or
      (FTip.View.Problems[AProblem].Code <> ARule) then
    begin
      Exit;
    end;
    // Ohne Katalogeintrag trotzdem aufklappen: Der Tooltip sagt dann, dass der Katalog nichts zur Regel hat.
    mExample := AExplanation;
    if mExample.Id = '' then
    begin
      mExample.Id := ARule;
    end;
    SetExample(AProblem, mExample);
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
      TAtlasHoverStrings.Text(TAtlasHoverTextId.PublishedImplicit));
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
