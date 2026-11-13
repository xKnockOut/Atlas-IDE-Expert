unit Atlas.Core.Debug.HoverTree;

// Aufklappbarer Wert im Debug-Hover (#895) ohne IDE:
//   - TAtlasValueChanges merkt sich je Ausdruck den Wert früherer Halte, getrennt nach Kontext (Thread und
//     Methode). Observe meldet den alten Wert, wenn er sich seitdem geändert hat. Das Variablenfenster (#853)
//     kann denselben Kern nutzen.
//   - TAtlasHoverTree ist der Baum zum Ausdruck im Hover. Die Wurzel wird beim Aufklappen mit Feldnamen
//     ausgewertet („Ausdruck,r“); ihre Kinder sind die Teile des Ergebnisses (Felder bzw. Elemente „[0]“).
//     Ein Kind mit zusammengesetztem Wert klappt aus seinen Teilen auf, ein Zeiger oder Objekt („$1A2B“) über
//     eine eigene Auswertung. Ist der Wert zu lang für den Debugger (gekürzt, etwa ein Array mit 1000 Elementen),
//     fragt der Baum „Length(Ausdruck)“ und wertet die sichtbaren Elemente einzeln aus. Eigenschaften kommen aus
//     dem Atlas-Index und sind Getter: erst „auswerten“, dann mit erlaubten Nebenwirkungen ausgewertet.
//     Höchstens MaxChildren Kinder je Ebene, dann „weitere N …“.
//   - Auswertungen holt die IDE-Schicht der Reihe nach über NextRequest und gibt das Ergebnis mit SetResult bzw.
//     SetProperties zurück; Rows liefert die sichtbaren Zeilen für den Tooltip.
//   - Aufgeklappte Ausdrücke bleiben über Halte aufgeklappt, bis Clear (Ende der Sitzung) sie vergisst.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Hover.DebugValue;

{$SCOPEDENUMS ON}

type
  /// <summary>Werte früherer Halte je Kontext und Ausdruck (#895).</summary>
  TAtlasValueChanges = class
  private
    FContext: string;
    /// <summary>Zuletzt gesehener Wert vor diesem Halt, Schlüssel Kontext #0 Ausdruck.</summary>
    FLast: TDictionary<string, string>;
    /// <summary>Werte dieses Halts.</summary>
    FCurrent: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Halt im Kontext AContext (Thread und Methode): Werte des vorigen Halts werden die alten.
    /// </summary>
    procedure BeginStop(const AContext: string);
    /// <summary>AText ist der Wert von AExpression in diesem Halt. Ergebnis: Wert eines früheren Halts im selben
    /// Kontext, wenn er anders war; sonst ''.</summary>
    function Observe(const AExpression, AText: string): string;
    /// <summary>Alles vergessen (Ende der Debug-Sitzung).</summary>
    procedure Clear;
  end;

  /// <summary>Value: Wert steht fest; Pending: Getter wird ausgewertet; Lazy: Getter, noch nicht ausgewertet;
  /// Queued: Element, wird ohne Nebenwirkungen ausgewertet, sobald es sichtbar ist; Failed: Auswertung
  /// gescheitert (Text ist die Meldung).</summary>
  TAtlasHoverTreeState = (Value, Pending, Lazy, Queued, Failed);

  TAtlasHoverTreeNode = class
  private
    FParent: TAtlasHoverTreeNode;
    FChildren: TObjectList<TAtlasHoverTreeNode>;
    FName: string;
    FExpression: string;
    FDepth: Integer;
    FText: string;
    FOldText: string;
    FState: TAtlasHoverTreeState;
    FExpanded: Boolean;
    FLoaded: Boolean;
    FWantsValue: Boolean;
    FWantsProperties: Boolean;
    FWantsLength: Boolean;
    FLimit: Integer;
    function GetChild(AIndex: Integer): TAtlasHoverTreeNode;
    function GetChildCount: Integer;
  public
    constructor Create(AParent: TAtlasHoverTreeNode; const AName, AExpression: string);
    destructor Destroy; override;
    function AddChild(const AName, AExpression: string): TAtlasHoverTreeNode;
    procedure ClearChildren;
    /// <summary>Lässt sich aufklappen: Wert steht fest und ist weder Zahl, String, nil noch Aufzählungswert;
    /// geladen mit mindestens einem Kind.</summary>
    function CanExpand: Boolean;
    /// <summary>Hat ein Kind mit Namen AName.</summary>
    function HasChild(const AName: string): Boolean;
    property Parent: TAtlasHoverTreeNode read FParent;
    property Name: string read FName;
    property Expression: string read FExpression;
    property Depth: Integer read FDepth;
    property ChildCount: Integer read GetChildCount;
    property Children[AIndex: Integer]: TAtlasHoverTreeNode read GetChild;
    property Text: string read FText write FText;
    property OldText: string read FOldText write FOldText;
    property State: TAtlasHoverTreeState read FState write FState;
    property Expanded: Boolean read FExpanded write FExpanded;
    /// <summary>Kinder geholt; ohne Kinder ist der Knoten danach ein Blatt.</summary>
    property Loaded: Boolean read FLoaded write FLoaded;
    /// <summary>Auswertung für die Kinder läuft bzw. steht an (Wert mit Feldnamen, dann Eigenschaften).</summary>
    property WantsValue: Boolean read FWantsValue write FWantsValue;
    property WantsProperties: Boolean read FWantsProperties write FWantsProperties;
    /// <summary>Wert zu lang (gekürzt): Anzahl der Elemente erfragen, dann einzeln auswerten.</summary>
    property WantsLength: Boolean read FWantsLength write FWantsLength;
    /// <summary>So viele Kinder sind sichtbar; der Rest steht hinter „weitere …“.</summary>
    property Limit: Integer read FLimit write FLimit;
  end;

  /// <summary>Auswertung, die der Baum braucht. Properties: Eigenschaften aus dem Index für „Expression.“ statt
  /// einer Auswertung im Debugger; SideEffects: Getter, Funktionsaufrufe erlaubt. Key nennt den Knoten.</summary>
  TAtlasHoverTreeRequest = record
    Key: string;
    Expression: string;
    Properties: Boolean;
    SideEffects: Boolean;
  end;

  /// <summary>Texte der Zeilen, die nicht vom Debugger kommen.</summary>
  TAtlasHoverTreeTexts = record
    /// <summary>Getter, noch nicht ausgewertet.</summary>
    Evaluate: string;
    /// <summary>Auswertung läuft.</summary>
    Pending: string;
    /// <summary>„weitere %d …“.</summary>
    More: string;
  end;

  TAtlasHoverTree = class
  public const
    cDefaultMaxChildren = 100;
  private
    FRoot: TAtlasHoverTreeNode;
    FChanges: TAtlasValueChanges;
    FMaxChildren: Integer;
    FTexts: TAtlasHoverTreeTexts;
    FShowChanges: Boolean;
    /// <summary>Aufgeklappte Ausdrücke; gelten über Halte hinweg.</summary>
    FExpanded: TDictionary<string, Boolean>;
    /// <summary>Knoten je Zeile aus Rows; More: Zeile „weitere …“ dieses Knotens.</summary>
    FRowNodes: TArray<TAtlasHoverTreeNode>;
    FRowMore: TArray<Boolean>;
    procedure SetValue(ANode: TAtlasHoverTreeNode; const AText: string);
    procedure SetExpanded(ANode: TAtlasHoverTreeNode; AExpanded: Boolean);
    /// <summary>Kinder aus den Teilen von AText; False, wenn AText keine hat.</summary>
    function LoadParts(ANode: TAtlasHoverTreeNode; const AText: string): Boolean;
    /// <summary>Beim Aufklappen: Kinder aus Teilen oder eine Auswertung anfordern.</summary>
    procedure Load(ANode: TAtlasHoverTreeNode);
    function FindNode(ANode: TAtlasHoverTreeNode; const AKey: string): TAtlasHoverTreeNode;
    function FindRequest(ANode: TAtlasHoverTreeNode; out ARequest: TAtlasHoverTreeRequest): Boolean;
    /// <summary>Anfrage für die Kinder von ANode selbst (Wert, Anzahl, Eigenschaften); False ohne.</summary>
    class function OwnRequest(ANode: TAtlasHoverTreeNode; var ARequest: TAtlasHoverTreeRequest): Boolean; static;
    /// <summary>Antwort auf „Length(…)“: ACount Elemente, je einzeln auszuwerten.</summary>
    procedure SetCount(ANode: TAtlasHoverTreeNode; AOk: Boolean; const AText: string);
    /// <summary>Antwort für ein Kind selbst (Getter, Element).</summary>
    procedure SetOwnValue(ANode: TAtlasHoverTreeNode; AOk: Boolean; const AText: string);
    procedure AddRows(ANode: TAtlasHoverTreeNode; var ARows: TArray<TAtlasDebugValueRow>);
    /// <summary>Zeile ARow für ANode anhängen; AMore: „weitere …“ von ANode.</summary>
    procedure AddRow(var ARows: TArray<TAtlasDebugValueRow>; const ARow: TAtlasDebugValueRow;
      ANode: TAtlasHoverTreeNode; AMore: Boolean);
    /// <summary>Zeile ohne Knoten („…“, „weitere …“) unter ANode.</summary>
    function PlainRow(ANode: TAtlasHoverTreeNode; const AText: string): TAtlasDebugValueRow;
    function RowOf(ANode: TAtlasHoverTreeNode): TAtlasDebugValueRow;
  public
    /// <summary>AChanges vergleicht mit früheren Halten (nicht übernommen, nil = ohne).</summary>
    constructor Create(AChanges: TAtlasValueChanges);
    destructor Destroy; override;
    /// <summary>Wert im Hover: anderer Ausdruck oder Wert = neuer Baum (aufgeklappt, was es vorher war);
    /// sonst bleibt er.</summary>
    procedure Bind(const AExpression, AText: string);
    /// <summary>AValue mit Zeilen, altem Wert und Aufklappzustand der Wurzel; unverändert ohne passenden Baum.
    /// </summary>
    function Decorate(const AValue: TAtlasDebugValue): TAtlasDebugValue;
    /// <summary>Sichtbare Zeilen unter der Wurzel (leer, solange sie zugeklappt ist).</summary>
    function Rows: TArray<TAtlasDebugValueRow>;
    /// <summary>Klick auf Zeile ARow aus Rows (-1 die Wurzel): auf- bzw. zuklappen, Getter auswerten, weitere
    /// zeigen. False, wenn sich nichts ändert.</summary>
    function Click(ARow: Integer): Boolean;
    /// <summary>Nächste ausstehende Auswertung in Anzeigereihenfolge; False ohne.</summary>
    function NextRequest(out ARequest: TAtlasHoverTreeRequest): Boolean;
    /// <summary>Ergebnis der Auswertung zu AKey (Wert bzw. Fehlermeldung).</summary>
    procedure SetResult(const AKey: string; AOk: Boolean; const AText: string);
    /// <summary>Eigenschaften zu AKey aus dem Index; die nicht schon Felder sind, werden Getter.</summary>
    procedure SetProperties(const AKey: string; const ANames: TArray<string>);
    /// <summary>Baum verwerfen (neuer Halt); aufgeklappte Ausdrücke bleiben.</summary>
    procedure Reset;
    /// <summary>Baum und aufgeklappte Ausdrücke verwerfen (Ende der Sitzung).</summary>
    procedure Clear;
    property Root: TAtlasHoverTreeNode read FRoot;
    property MaxChildren: Integer read FMaxChildren write FMaxChildren;
    property Texts: TAtlasHoverTreeTexts read FTexts write FTexts;
    /// <summary>Parameter für atlas/expressionCompletion auf AExpression („Kunde.“) in AUri, Zeile ALine
    /// (0-basiert).</summary>
    class function CompletionParams(const AUri: string; ALine: Integer; const AExpression: string): string; static;
    /// <summary>Namen der Eigenschaften (ohne Felder) aus der Antwort von atlas/expressionCompletion; nil, wenn sie
    /// fehlt oder kein JSON ist.</summary>
    class function PropertiesOf(const AAnswer: string): TArray<string>; static;
    /// <summary>Alte Werte zeigen (debug.hoverChanges).</summary>
    property ShowChanges: Boolean read FShowChanges write FShowChanges;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.StrUtils,
  Atlas.Core.Debug.Evaluate;

{ TAtlasValueChanges }

constructor TAtlasValueChanges.Create;
begin
  inherited Create;
  FLast := TDictionary<string, string>.Create;
  FCurrent := TDictionary<string, string>.Create;
end;

destructor TAtlasValueChanges.Destroy;
begin
  FCurrent.Free;
  FLast.Free;
  inherited Destroy;
end;

procedure TAtlasValueChanges.BeginStop(const AContext: string);
var
  mPair: TPair<string, string>;
begin
  for mPair in FCurrent do
  begin
    FLast.AddOrSetValue(mPair.Key, mPair.Value);
  end;
  FCurrent.Clear;
  FContext := AContext;
end;

function TAtlasValueChanges.Observe(const AExpression, AText: string): string;
var
  mKey, mOld: string;
begin
  Result := '';
  mKey := FContext + #0 + AExpression;
  FCurrent.AddOrSetValue(mKey, AText);
  if FLast.TryGetValue(mKey, mOld) and (mOld <> AText) then
  begin
    Result := mOld;
  end;
end;

procedure TAtlasValueChanges.Clear;
begin
  FLast.Clear;
  FCurrent.Clear;
  FContext := '';
end;

{ TAtlasHoverTreeNode }

constructor TAtlasHoverTreeNode.Create(AParent: TAtlasHoverTreeNode; const AName, AExpression: string);
begin
  inherited Create;
  FParent := AParent;
  FName := AName;
  FExpression := AExpression;
  FChildren := TObjectList<TAtlasHoverTreeNode>.Create(True);
  if AParent <> nil then
  begin
    FDepth := AParent.Depth + 1;
  end;
end;

destructor TAtlasHoverTreeNode.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

function TAtlasHoverTreeNode.GetChild(AIndex: Integer): TAtlasHoverTreeNode;
begin
  Result := FChildren[AIndex];
end;

function TAtlasHoverTreeNode.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

function TAtlasHoverTreeNode.AddChild(const AName, AExpression: string): TAtlasHoverTreeNode;
begin
  Result := TAtlasHoverTreeNode.Create(Self, AName, AExpression);
  FChildren.Add(Result);
end;

procedure TAtlasHoverTreeNode.ClearChildren;
begin
  FChildren.Clear;
end;

function TAtlasHoverTreeNode.CanExpand: Boolean;
begin
  if Loaded then
  begin
    Exit(FChildren.Count > 0);
  end;
  Result := (State = TAtlasHoverTreeState.Value) and not TAtlasEvalText.IsSimple(Text);
end;

function TAtlasHoverTreeNode.HasChild(const AName: string): Boolean;
var
  mChild: TAtlasHoverTreeNode;
begin
  for mChild in FChildren do
  begin
    if SameText(mChild.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasHoverTree }

constructor TAtlasHoverTree.Create(AChanges: TAtlasValueChanges);
begin
  inherited Create;
  FChanges := AChanges;
  FMaxChildren := cDefaultMaxChildren;
  FShowChanges := True;
  FExpanded := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasHoverTree.Destroy;
begin
  FRoot.Free;
  FExpanded.Free;
  inherited Destroy;
end;

procedure TAtlasHoverTree.SetValue(ANode: TAtlasHoverTreeNode; const AText: string);
begin
  ANode.Text := AText;
  ANode.State := TAtlasHoverTreeState.Value;
  ANode.OldText := '';
  if FChanges <> nil then
  begin
    ANode.OldText := FChanges.Observe(ANode.Expression, AText);
  end;
end;

procedure TAtlasHoverTree.SetExpanded(ANode: TAtlasHoverTreeNode; AExpanded: Boolean);
begin
  ANode.Expanded := AExpanded;
  if AExpanded then
  begin
    FExpanded.AddOrSetValue(ANode.Expression, True);
    Load(ANode);
  end
  else
  begin
    FExpanded.Remove(ANode.Expression);
  end;
end;

function TAtlasHoverTree.LoadParts(ANode: TAtlasHoverTreeNode; const AText: string): Boolean;
var
  mParts: TAtlasEvalParts;
  mPart: TAtlasEvalPart;
  mChild: TAtlasHoverTreeNode;
  mExpression: string;
begin
  mParts := TAtlasEvalText.Parts(AText);
  Result := Length(mParts) > 0;
  if not Result then
  begin
    Exit;
  end;
  ANode.ClearChildren;
  ANode.Limit := FMaxChildren;
  for mPart in mParts do
  begin
    if mPart.Indexed then
    begin
      mExpression := ANode.Expression + mPart.Name;
    end
    else
    begin
      mExpression := TAtlasEvalText.FieldExpression(ANode.Expression, mPart.Name);
    end;
    mChild := ANode.AddChild(mPart.Name, mExpression);
    SetValue(mChild, mPart.Value);
    // Über Halte aufgeklappt: Kinder gleich wieder laden.
    if FExpanded.ContainsKey(mExpression) and mChild.CanExpand then
    begin
      SetExpanded(mChild, True);
    end;
  end;
  ANode.Loaded := True;
  // Elemente eines Arrays haben keine Eigenschaften; Felder eines Objekts oder Records vielleicht.
  ANode.WantsProperties := not mParts[0].Indexed;
end;

procedure TAtlasHoverTree.Load(ANode: TAtlasHoverTreeNode);
begin
  if ANode.Loaded or ANode.WantsValue or (ANode.State <> TAtlasHoverTreeState.Value) then
  begin
    Exit;
  end;
  // Die Wurzel zeigt den Wert ohne Feldnamen; ein Kind ohne Teile ist ein Zeiger oder Objekt: neu auswerten.
  if (ANode = FRoot) or not LoadParts(ANode, ANode.Text) then
  begin
    ANode.WantsValue := True;
  end;
end;

procedure TAtlasHoverTree.Bind(const AExpression, AText: string);
begin
  if (FRoot <> nil) and (FRoot.Expression = AExpression) and (FRoot.Text = AText) then
  begin
    Exit;
  end;
  FreeAndNil(FRoot);
  FRoot := TAtlasHoverTreeNode.Create(nil, '', AExpression);
  SetValue(FRoot, AText);
  if FExpanded.ContainsKey(AExpression) and FRoot.CanExpand then
  begin
    SetExpanded(FRoot, True);
  end;
end;

function TAtlasHoverTree.Decorate(const AValue: TAtlasDebugValue): TAtlasDebugValue;
begin
  Result := AValue;
  if (FRoot = nil) or (FRoot.Expression <> AValue.Expression) then
  begin
    Exit;
  end;
  Result.Expandable := FRoot.CanExpand;
  Result.Expanded := FRoot.Expanded and Result.Expandable;
  if FShowChanges then
  begin
    Result.OldText := FRoot.OldText;
  end;
  Result.Rows := Rows;
end;

function TAtlasHoverTree.RowOf(ANode: TAtlasHoverTreeNode): TAtlasDebugValueRow;
begin
  Result := Default(TAtlasDebugValueRow);
  Result.Expression := ANode.Expression;
  Result.Name := ANode.Name;
  Result.Text := ANode.Text;
  Result.Depth := ANode.Depth - 1;
  Result.Expandable := ANode.CanExpand;
  Result.Expanded := ANode.Expanded and Result.Expandable;
  if FShowChanges then
  begin
    Result.OldText := ANode.OldText;
  end;
  // Wert bzw. Meldung stehen in Text; ausstehende Werte und Getter tragen einen eigenen Text.
  if ANode.State in [TAtlasHoverTreeState.Pending, TAtlasHoverTreeState.Queued] then
  begin
    Result.Pending := True;
    Result.Text := FTexts.Pending;
  end
  else if ANode.State = TAtlasHoverTreeState.Lazy then
  begin
    Result.Lazy := True;
    Result.Text := FTexts.Evaluate;
  end;
end;

procedure TAtlasHoverTree.AddRow(var ARows: TArray<TAtlasDebugValueRow>; const ARow: TAtlasDebugValueRow;
  ANode: TAtlasHoverTreeNode; AMore: Boolean);
begin
  SetLength(ARows, Length(ARows) + 1);
  ARows[High(ARows)] := ARow;
  SetLength(FRowNodes, Length(FRowNodes) + 1);
  FRowNodes[High(FRowNodes)] := ANode;
  SetLength(FRowMore, Length(FRowMore) + 1);
  FRowMore[High(FRowMore)] := AMore;
end;

function TAtlasHoverTree.PlainRow(ANode: TAtlasHoverTreeNode; const AText: string): TAtlasDebugValueRow;
begin
  Result := Default(TAtlasDebugValueRow);
  Result.Text := AText;
  Result.Depth := ANode.Depth;
end;

procedure TAtlasHoverTree.AddRows(ANode: TAtlasHoverTreeNode; var ARows: TArray<TAtlasDebugValueRow>);
var
  mIndex, mShown: Integer;
  mRow: TAtlasDebugValueRow;
begin
  if not ANode.Expanded then
  begin
    Exit;
  end;
  if (ANode.WantsValue or ANode.WantsLength) and (ANode.ChildCount = 0) then
  begin
    // Kinder kommen noch: eine Zeile „…“.
    mRow := PlainRow(ANode, FTexts.Pending);
    mRow.Pending := True;
    AddRow(ARows, mRow, ANode, False);
    Exit;
  end;
  mShown := ANode.ChildCount;
  if (ANode.Limit > 0) and (mShown > ANode.Limit) then
  begin
    mShown := ANode.Limit;
  end;
  for mIndex := 0 to mShown - 1 do
  begin
    AddRow(ARows, RowOf(ANode.Children[mIndex]), ANode.Children[mIndex], False);
    AddRows(ANode.Children[mIndex], ARows);
  end;
  if mShown < ANode.ChildCount then
  begin
    mRow := PlainRow(ANode, Format(FTexts.More, [Min(FMaxChildren, ANode.ChildCount - mShown)]));
    mRow.More := True;
    AddRow(ARows, mRow, ANode, True);
  end;
end;

function TAtlasHoverTree.Rows: TArray<TAtlasDebugValueRow>;
begin
  Result := nil;
  FRowNodes := nil;
  FRowMore := nil;
  if FRoot <> nil then
  begin
    AddRows(FRoot, Result);
  end;
end;

function TAtlasHoverTree.Click(ARow: Integer): Boolean;
var
  mNode: TAtlasHoverTreeNode;
begin
  Result := False;
  if (ARow < -1) or (ARow > High(FRowNodes)) or (FRoot = nil) then
  begin
    Exit;
  end;
  if ARow = -1 then
  begin
    mNode := FRoot;
  end
  else
  begin
    mNode := FRowNodes[ARow];
  end;
  if (ARow >= 0) and FRowMore[ARow] then
  begin
    mNode.Limit := mNode.Limit + FMaxChildren;
    Exit(True);
  end;
  if mNode.State = TAtlasHoverTreeState.Lazy then
  begin
    // Getter erst auf Klick: Nebenwirkungen sind möglich.
    mNode.State := TAtlasHoverTreeState.Pending;
    Exit(True);
  end;
  Result := mNode.CanExpand;
  if Result then
  begin
    SetExpanded(mNode, not mNode.Expanded);
  end;
end;

class function TAtlasHoverTree.OwnRequest(ANode: TAtlasHoverTreeNode; var ARequest: TAtlasHoverTreeRequest): Boolean;
begin
  Result := True;
  if ANode.State in [TAtlasHoverTreeState.Pending, TAtlasHoverTreeState.Queued] then
  begin
    ARequest.Expression := ANode.Expression;
    ARequest.SideEffects := ANode.State = TAtlasHoverTreeState.Pending;
  end
  else if ANode.Expanded and ANode.WantsValue then
  begin
    ARequest.Expression := TAtlasEvalText.WithFieldNames(ANode.Expression);
  end
  else if ANode.Expanded and ANode.WantsLength then
  begin
    ARequest.Expression := 'Length(' + ANode.Expression + ')';
  end
  else if ANode.Expanded and ANode.WantsProperties then
  begin
    ARequest.Expression := ANode.Expression + '.';
    ARequest.Properties := True;
  end
  else
  begin
    Result := False;
  end;
end;

function TAtlasHoverTree.FindRequest(ANode: TAtlasHoverTreeNode; out ARequest: TAtlasHoverTreeRequest): Boolean;
var
  mIndex, mShown: Integer;
begin
  ARequest := Default(TAtlasHoverTreeRequest);
  ARequest.Key := ANode.Expression;
  if OwnRequest(ANode, ARequest) then
  begin
    Exit(True);
  end;
  if not ANode.Expanded then
  begin
    Exit(False);
  end;
  // Nur sichtbare Kinder: Elemente hinter „weitere …“ warten.
  mShown := ANode.ChildCount;
  if (ANode.Limit > 0) and (mShown > ANode.Limit) then
  begin
    mShown := ANode.Limit;
  end;
  for mIndex := 0 to mShown - 1 do
  begin
    if FindRequest(ANode.Children[mIndex], ARequest) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasHoverTree.NextRequest(out ARequest: TAtlasHoverTreeRequest): Boolean;
begin
  ARequest := Default(TAtlasHoverTreeRequest);
  Result := (FRoot <> nil) and FindRequest(FRoot, ARequest);
end;

function TAtlasHoverTree.FindNode(ANode: TAtlasHoverTreeNode; const AKey: string): TAtlasHoverTreeNode;
var
  mIndex: Integer;
begin
  if ANode.Expression = AKey then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindNode(ANode.Children[mIndex], AKey);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TAtlasHoverTree.SetOwnValue(ANode: TAtlasHoverTreeNode; AOk: Boolean; const AText: string);
begin
  // Getter bzw. Element ausgewertet: Wert oder Meldung, aufklappbar wie jedes andere Kind.
  if AOk then
  begin
    SetValue(ANode, AText);
    if FExpanded.ContainsKey(ANode.Expression) and ANode.CanExpand then
    begin
      SetExpanded(ANode, True);
    end;
  end
  else
  begin
    ANode.Text := AText;
    ANode.State := TAtlasHoverTreeState.Failed;
  end;
end;

procedure TAtlasHoverTree.SetCount(ANode: TAtlasHoverTreeNode; AOk: Boolean; const AText: string);
var
  mCount, mIndex: Integer;
  mChild: TAtlasHoverTreeNode;
begin
  ANode.WantsLength := False;
  ANode.Loaded := True;
  ANode.ClearChildren;
  if not AOk or not TryStrToInt(Trim(AText), mCount) then
  begin
    Exit;
  end;
  ANode.Limit := FMaxChildren;
  for mIndex := 0 to mCount - 1 do
  begin
    mChild := ANode.AddChild('[' + IntToStr(mIndex) + ']', ANode.Expression + '[' + IntToStr(mIndex) + ']');
    mChild.State := TAtlasHoverTreeState.Queued;
  end;
end;

procedure TAtlasHoverTree.SetResult(const AKey: string; AOk: Boolean; const AText: string);
var
  mNode: TAtlasHoverTreeNode;
begin
  if FRoot = nil then
  begin
    Exit;
  end;
  mNode := FindNode(FRoot, AKey);
  if mNode = nil then
  begin
    Exit;
  end;
  if mNode.State in [TAtlasHoverTreeState.Pending, TAtlasHoverTreeState.Queued] then
  begin
    SetOwnValue(mNode, AOk, AText);
  end
  else if mNode.WantsValue then
  begin
    mNode.WantsValue := False;
    if AOk and LoadParts(mNode, AText) then
    begin
      Exit;
    end;
    // Gekürzt (zu lang für den Debugger): Elemente einzeln. Sonst (Fehler, nil) ein Blatt.
    mNode.WantsLength := AOk and AText.StartsWith('(') and not TAtlasEvalText.IsStructured(AText);
    mNode.Loaded := not mNode.WantsLength;
    mNode.ClearChildren;
    mNode.WantsProperties := False;
  end
  else if mNode.WantsLength then
  begin
    SetCount(mNode, AOk, AText);
  end;
end;

procedure TAtlasHoverTree.SetProperties(const AKey: string; const ANames: TArray<string>);
var
  mNode, mChild: TAtlasHoverTreeNode;
  mName: string;
begin
  if FRoot = nil then
  begin
    Exit;
  end;
  mNode := FindNode(FRoot, AKey);
  if (mNode = nil) or not mNode.WantsProperties then
  begin
    Exit;
  end;
  mNode.WantsProperties := False;
  for mName in ANames do
  begin
    if not mNode.HasChild(mName) then
    begin
      mChild := mNode.AddChild(mName, TAtlasEvalText.FieldExpression(mNode.Expression, mName));
      mChild.State := TAtlasHoverTreeState.Lazy;
    end;
  end;
end;

class function TAtlasHoverTree.CompletionParams(const AUri: string; ALine: Integer;
  const AExpression: string): string;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
    mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
      .AddPair('character', TJSONNumber.Create(0)));
    mParams.AddPair('expression', AExpression);
    mParams.AddPair('character', TJSONNumber.Create(Length(AExpression)));
    Result := mParams.ToJSON([]);
  finally
    mParams.Free;
  end;
end;

class function TAtlasHoverTree.PropertiesOf(const AAnswer: string): TArray<string>;
var
  mAnswer: TJSONValue;
  mFields: TArray<string>;
  mName: string;
begin
  Result := nil;
  mAnswer := TJSONObject.ParseJSONValue(AAnswer);
  try
    mFields := TAtlasEvalText.FieldsOf(mAnswer, False);
    for mName in TAtlasEvalText.FieldsOf(mAnswer, True) do
    begin
      if IndexText(mName, mFields) < 0 then
      begin
        Result := Result + [mName];
      end;
    end;
  finally
    mAnswer.Free;
  end;
end;

procedure TAtlasHoverTree.Reset;
begin
  FreeAndNil(FRoot);
  FRowNodes := nil;
  FRowMore := nil;
end;

procedure TAtlasHoverTree.Clear;
begin
  Reset;
  FExpanded.Clear;
end;

end.
