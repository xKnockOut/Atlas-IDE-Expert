unit Atlas.Core.Debug.Variables;

// Fenster „Variablen“ (#853) ohne Fenster und ohne IDE:
//   - TAtlasVariables: Antwort von atlas.server.debugVariables lesen (Autos
//     und lokale Variablen) und die Argumente bauen.
//   - TAtlasVariableSearch: Suche nach Name oder Wert in einer TAtlasEvalList
//     (eine Zeile je Ausdruck, Kinder sind Felder bzw. Teile). Ohne Tiefe
//     sucht sie nur in dem, was schon da ist. Mit Unterelementen öffnet sie
//     selbst Knoten bis zur Tiefe Depth (NextToOpen, Wurzeln haben Tiefe 0),
//     breit zuerst; jedes Feld, das dafür ausgewertet werden muss, zählt
//     gegen Limit. Ist die Grenze erreicht, hört sie auf (Truncated).
//     Apply bestimmt Treffer und sichtbare Knoten: Treffer, ihre Vorfahren
//     (aufgeklappt) und ihre Nachfahren; was die Suche ohne Treffer geöffnet
//     hat, klappt sie wieder zu. Werte zählen nur, wenn sie nicht
//     strukturiert sind: Der Treffer liegt beim Feld, nicht beim Objekt, das
//     es im Text seines Werts mitbringt.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Debug.Evaluate;

type
  {$SCOPEDENUMS ON}
  TAtlasVariablesTab = (Autos, Locals, Watch);
  TAtlasVariableSearchMode = (Name, Value);
  {$SCOPEDENUMS OFF}

  TAtlasVariablesAnswer = record
    Autos: TArray<string>;
    Locals: TArray<string>;
  end;

  TAtlasVariables = class
  public const
    cCommand = 'atlas.server.debugVariables';
  public
    /// <summary>Antwort lesen; False bei falscher Form.</summary>
    class function ReadAnswer(const AJson: TJSONValue; out AAnswer: TAtlasVariablesAnswer): Boolean; static;
    /// <summary>Wie ReadAnswer aus JSON-Text; False bei leerem oder kaputtem Text.</summary>
    class function ReadAnswerText(const AText: string; out AAnswer: TAtlasVariablesAnswer): Boolean; static;
    /// <summary>Argumente als JSON-Text: [uri, line, previousLine] (Zeilen ab 0, -1 ohne vorige).</summary>
    class function Arguments(const AUri: string; ALine, APreviousLine: Integer): string; static;
  end;

  TAtlasVariableSearch = class
  public const
    cDefaultDepth = 3;
    cDefaultLimit = 500;
  private
    FText: string;
    FMode: TAtlasVariableSearchMode;
    FDeep: Boolean;
    FDepth: Integer;
    FLimit: Integer;
    FEvaluations: Integer;
    FTruncated: Boolean;
    /// <summary>Von der Suche geöffnete Knoten.</summary>
    FTried: TDictionary<string, Boolean>;
    /// <summary>Darunter waren die Felder schon gezählt.</summary>
    FCounted: TDictionary<string, Boolean>;
    /// <summary>Waren vorher zu: ohne Treffer wieder zuklappen.</summary>
    FOpened: TDictionary<string, Boolean>;
    FHits: TDictionary<string, Boolean>;
    FShown: TDictionary<string, Boolean>;
    function Visit(ANode: TAtlasEvalNode; AUnderHit: Boolean): Boolean;
    function IsCandidate(ANode: TAtlasEvalNode; ADepth: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Suche: AText (leer = keine Suche), nach Name oder Wert, mit ADeep auch in Unterelementen bis
    /// ADepth, höchstens ALimit Auswertungen.</summary>
    procedure Start(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean; ADepth, ALimit: Integer);
    /// <summary>Suche beenden; geöffnete Knoten bleiben, wie sie sind.</summary>
    procedure Clear;
    function Active: Boolean;
    /// <summary>Passt ANode zur Suche (Name bzw. einfacher Wert enthält den Text, ohne Groß/klein)?</summary>
    function Matches(ANode: TAtlasEvalNode): Boolean;
    /// <summary>Nächster Knoten, den die Suche öffnen muss; nil, wenn sie fertig ist oder die Grenze erreicht hat.
    /// Erst fragen, wenn nichts mehr ausgewertet wird.</summary>
    function NextToOpen(AList: TAtlasEvalList): TAtlasEvalNode;
    /// <summary>Die Suche öffnet ANode (aufgeklappt); sind seine Kinder schon da, zählen sie gleich.</summary>
    procedure Opened(ANode: TAtlasEvalNode);
    /// <summary>Die Kinder eines geöffneten Knotens sind da: Felder mit Ausdruck zählen als Auswertungen.</summary>
    procedure Loaded(ANode: TAtlasEvalNode);
    /// <summary>Hat die Suche den Knoten mit AKey geöffnet?</summary>
    function Tried(const AKey: string): Boolean;
    /// <summary>Treffer und sichtbare Knoten bestimmen, Pfade zu Treffern aufklappen; Anzahl der Treffer.</summary>
    function Apply(AList: TAtlasEvalList): Integer;
    function IsHit(ANode: TAtlasEvalNode): Boolean;
    /// <summary>Ohne Suche immer True.</summary>
    function IsShown(ANode: TAtlasEvalNode): Boolean;
    function HitCount: Integer;
    property Text: string read FText;
    property Mode: TAtlasVariableSearchMode read FMode;
    property Deep: Boolean read FDeep;
    property Evaluations: Integer read FEvaluations;
    /// <summary>Die Suche hat bei Limit aufgehört; tiefer läge noch etwas.</summary>
    property Truncated: Boolean read FTruncated;
  end;

implementation

uses
  System.StrUtils;

function StringsOf(AJson: TJSONObject; const AName: string; out AItems: TArray<string>): Boolean;
var
  mValue: TJSONValue;
  mItem: TJSONValue;
  mIndex: Integer;
begin
  AItems := nil;
  mValue := AJson.GetValue(AName);
  Result := mValue is TJSONArray;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(mValue).Count - 1 do
  begin
    mItem := TJSONArray(mValue).Items[mIndex];
    if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
    begin
      AItems := AItems + [Trim(mItem.Value)];
    end;
  end;
end;

{ TAtlasVariables }

class function TAtlasVariables.ReadAnswer(const AJson: TJSONValue; out AAnswer: TAtlasVariablesAnswer): Boolean;
begin
  AAnswer := Default(TAtlasVariablesAnswer);
  Result := (AJson is TJSONObject) and StringsOf(TJSONObject(AJson), 'autos', AAnswer.Autos) and
    StringsOf(TJSONObject(AJson), 'locals', AAnswer.Locals);
  if not Result then
  begin
    AAnswer := Default(TAtlasVariablesAnswer);
  end;
end;

class function TAtlasVariables.ReadAnswerText(const AText: string; out AAnswer: TAtlasVariablesAnswer): Boolean;
var
  mJson: TJSONValue;
begin
  AAnswer := Default(TAtlasVariablesAnswer);
  if Trim(AText) = '' then
  begin
    Exit(False);
  end;
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    Result := ReadAnswer(mJson, AAnswer);
  finally
    mJson.Free;
  end;
end;

class function TAtlasVariables.Arguments(const AUri: string; ALine, APreviousLine: Integer): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mArguments.Add(ALine);
    mArguments.Add(APreviousLine);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

{ TAtlasVariableSearch }

constructor TAtlasVariableSearch.Create;
begin
  inherited Create;
  FTried := TDictionary<string, Boolean>.Create;
  FCounted := TDictionary<string, Boolean>.Create;
  FOpened := TDictionary<string, Boolean>.Create;
  FHits := TDictionary<string, Boolean>.Create;
  FShown := TDictionary<string, Boolean>.Create;
  FDepth := cDefaultDepth;
  FLimit := cDefaultLimit;
end;

destructor TAtlasVariableSearch.Destroy;
begin
  FreeAndNil(FShown);
  FreeAndNil(FHits);
  FreeAndNil(FOpened);
  FreeAndNil(FCounted);
  FreeAndNil(FTried);
  FText := '';
  inherited Destroy;
end;

procedure TAtlasVariableSearch.Start(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean;
  ADepth, ALimit: Integer);
begin
  Clear;
  FText := Trim(AText);
  FMode := AMode;
  FDeep := ADeep;
  FDepth := ADepth;
  FLimit := ALimit;
end;

procedure TAtlasVariableSearch.Clear;
begin
  FText := '';
  FEvaluations := 0;
  FTruncated := False;
  FTried.Clear;
  FCounted.Clear;
  FOpened.Clear;
  FHits.Clear;
  FShown.Clear;
end;

function TAtlasVariableSearch.Active: Boolean;
begin
  Result := FText <> '';
end;

function TAtlasVariableSearch.Matches(ANode: TAtlasEvalNode): Boolean;
begin
  if not Active then
  begin
    Exit(False);
  end;
  if FMode = TAtlasVariableSearchMode.Name then
  begin
    Result := ContainsText(ANode.Name, FText);
  end
  else
  begin
    Result := (ANode.State = TAtlasEvalState.Value) and not TAtlasEvalText.IsStructured(ANode.Value) and
      ContainsText(ANode.Value, FText);
  end;
end;

function TAtlasVariableSearch.IsCandidate(ANode: TAtlasEvalNode; ADepth: Integer): Boolean;
begin
  // Zu oder ohne Kinder: öffnen. Felder eines zugeklappten Knotens wertet niemand aus.
  Result := (ADepth < FDepth) and ANode.CanExpand and not FTried.ContainsKey(ANode.Key) and
    not (ANode.Expanded and ANode.ChildrenLoaded);
end;

function TAtlasVariableSearch.NextToOpen(AList: TAtlasEvalList): TAtlasEvalNode;
var
  mQueue: TQueue<TPair<TAtlasEvalNode, Integer>>;
  mEntry: TPair<TAtlasEvalNode, Integer>;
  mIndex: Integer;
begin
  Result := nil;
  if not Active or not FDeep or (AList = nil) or FTruncated then
  begin
    Exit;
  end;
  mQueue := TQueue<TPair<TAtlasEvalNode, Integer>>.Create;
  try
    for mIndex := 0 to AList.Count - 1 do
    begin
      mQueue.Enqueue(TPair<TAtlasEvalNode, Integer>.Create(AList.Roots[mIndex], 0));
    end;
    // Breit zuerst: Bei der Grenze sind die flachen Ebenen durchsucht.
    while mQueue.Count > 0 do
    begin
      mEntry := mQueue.Dequeue;
      if IsCandidate(mEntry.Key, mEntry.Value) then
      begin
        if FEvaluations >= FLimit then
        begin
          FTruncated := True;
          Exit(nil);
        end;
        Exit(mEntry.Key);
      end;
      if mEntry.Key.Expanded and mEntry.Key.ChildrenLoaded and (mEntry.Value < FDepth) then
      begin
        for mIndex := 0 to mEntry.Key.ChildCount - 1 do
        begin
          mQueue.Enqueue(TPair<TAtlasEvalNode, Integer>.Create(mEntry.Key.Children[mIndex], mEntry.Value + 1));
        end;
      end;
    end;
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasVariableSearch.Opened(ANode: TAtlasEvalNode);
begin
  FTried.AddOrSetValue(ANode.Key, True);
  if not ANode.Expanded then
  begin
    FOpened.AddOrSetValue(ANode.Key, True);
  end;
  ANode.Expanded := True;
  if ANode.ChildrenLoaded then
  begin
    Loaded(ANode);
  end;
end;

procedure TAtlasVariableSearch.Loaded(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
begin
  if not FTried.ContainsKey(ANode.Key) or FCounted.ContainsKey(ANode.Key) then
  begin
    Exit;
  end;
  FCounted.Add(ANode.Key, True);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    // Teile des Ergebnis-Strings kosten keine Auswertung.
    if ANode.Children[mIndex].Expression <> '' then
    begin
      Inc(FEvaluations);
    end;
  end;
end;

function TAtlasVariableSearch.Tried(const AKey: string): Boolean;
begin
  Result := FTried.ContainsKey(AKey);
end;

function TAtlasVariableSearch.Visit(ANode: TAtlasEvalNode; AUnderHit: Boolean): Boolean;
var
  mHit, mBelow: Boolean;
  mIndex: Integer;
begin
  mHit := Matches(ANode);
  if mHit then
  begin
    FHits.AddOrSetValue(ANode.Key, True);
  end;
  mBelow := False;
  if ANode.ChildrenLoaded then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if Visit(ANode.Children[mIndex], AUnderHit or mHit) then
      begin
        mBelow := True;
      end;
    end;
  end;
  if mBelow then
  begin
    // Pfad zum Treffer aufklappen.
    ANode.Expanded := True;
  end
  else if FOpened.ContainsKey(ANode.Key) then
  begin
    ANode.Expanded := False;
  end;
  Result := mHit or mBelow;
  if Result or AUnderHit then
  begin
    FShown.AddOrSetValue(ANode.Key, True);
  end;
end;

function TAtlasVariableSearch.Apply(AList: TAtlasEvalList): Integer;
var
  mIndex: Integer;
begin
  FHits.Clear;
  FShown.Clear;
  if Active and (AList <> nil) then
  begin
    for mIndex := 0 to AList.Count - 1 do
    begin
      Visit(AList.Roots[mIndex], False);
    end;
  end;
  Result := FHits.Count;
end;

function TAtlasVariableSearch.IsHit(ANode: TAtlasEvalNode): Boolean;
begin
  Result := Active and (ANode <> nil) and FHits.ContainsKey(ANode.Key);
end;

function TAtlasVariableSearch.IsShown(ANode: TAtlasEvalNode): Boolean;
begin
  Result := not Active or ((ANode <> nil) and FShown.ContainsKey(ANode.Key));
end;

function TAtlasVariableSearch.HitCount: Integer;
begin
  Result := FHits.Count;
end;

end.
