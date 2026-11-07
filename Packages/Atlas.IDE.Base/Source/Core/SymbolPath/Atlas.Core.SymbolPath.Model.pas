unit Atlas.Core.SymbolPath.Model;

// Weg zwischen Symbolen (#1117) im Plugin, Kern ohne VCL und OTA:
// - TAtlasSymbolPathAnswer.Parse liest die Antwort des Befehls
//   atlas.symbolPath ({"enabled", "status", "routes": [{"nodes", "steps"}],
//   "candidates", …} aus TSymbolPathSearch.ToJson). Zeilen und Spalten
//   bleiben 0-basiert wie im Server.
// - TAtlasSymbolPathRoute.UnitNames: die Units des Wegs in Reihenfolge, ohne
//   direkte Wiederholung, für „In Architekturkarte zeigen“ (#1118).
// - Rows legt die Zeilen der gezeichneten Kette fest: je Weg (bei mehreren)
//   eine Überschrift, abwechselnd Knoten und Schritt; bei Mehrdeutigkeit die
//   Treffer. Jede Zeile kennt ihre Fundstelle für den Doppelklick.
// - TAtlasSymbolPathCommands.Arguments baut [uri, {"from", "to", "maxSteps",
//   "all"}] für den Befehl.
// - QualifiedName macht aus Name und Container eines Symbols die Angabe, die
//   der Server wie find_symbol auflöst („TFoo.Bar“, „Unit.Routine“).

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TAtlasSymbolPathNode = record
    /// <summary>„TKundenForm.btnSpeichernClick“ bzw. Unit-Name.</summary>
    Caption: string;
    UnitName: string;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    IsUnit: Boolean;
    Library_: Boolean;
  end;

  TAtlasSymbolPathStep = record
    /// <summary>"uses", "inherits", "implements", "hasField", "parameter", "result", "calls", "contains".</summary>
    Kind: string;
    /// <summary>„ruft auf“, „verwendet (implementation)“ … vom Server.</summary>
    Caption: string;
    /// <summary>Nur erschlossen (mehrere Umsetzungen, #1119): gestrichelt.</summary>
    Inferred: Boolean;
    Reverse: Boolean;
    Implementation_: Boolean;
    /// <summary>Fundstelle der Kante, '' ohne; 0-basiert.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TAtlasSymbolPathRoute = record
    Nodes: TArray<TAtlasSymbolPathNode>;
    /// <summary>Steps[I] führt von Nodes[I] zu Nodes[I + 1].</summary>
    Steps: TArray<TAtlasSymbolPathStep>;
    /// <summary>Units der Knoten in Reihenfolge, direkte Wiederholungen zusammengefasst.</summary>
    function UnitNames: TArray<string>;
  end;

{$SCOPEDENUMS ON}
  TAtlasSymbolPathStatus = (Found, NoPath, Aborted, Ambiguous, NotFound);
{$SCOPEDENUMS OFF}

{$SCOPEDENUMS ON}
  TAtlasSymbolPathRowKind = (Header, Node, Step, Candidate);
{$SCOPEDENUMS OFF}

  TAtlasSymbolPathRow = record
    Kind: TAtlasSymbolPathRowKind;
    /// <summary>Nummer des Wegs in Routes (Candidate: 0).</summary>
    Route: Integer;
    /// <summary>Knoten, Schritt bzw. Treffer im Weg bzw. in Candidates; Header: -1.</summary>
    Index: Integer;
    /// <summary>Ziel des Doppelklicks, '' ohne; 0-basiert.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
    Inferred: Boolean;
  end;

  TAtlasSymbolPathAnswer = record
    Enabled: Boolean;
    Status: TAtlasSymbolPathStatus;
    From: string;
    To_: string;
    Routes: TArray<TAtlasSymbolPathRoute>;
    MoreRoutes: Boolean;
    MaxSteps: Integer;
    SearchedSteps: Integer;
    Visited: Integer;
    ElapsedMs: Integer;
    AbortReason: string;
    /// <summary>Mehrdeutige bzw. unbekannte Angabe ("from" oder "to") und die Treffer dazu.</summary>
    Subject: string;
    Candidates: TArray<TAtlasSymbolPathNode>;
    /// <summary>Aufrufkanten wurden nicht ganz durchsucht (Zeitlimit in Stufe 2).</summary>
    CallsIncomplete: Boolean;
    /// <summary>False bei unlesbarer Antwort; mit navigation.symbolPath = false True und Enabled = False.</summary>
    class function Parse(const AAnswer: string; out AModel: TAtlasSymbolPathAnswer): Boolean; static;
    /// <summary>Schritte des ersten Wegs, 0 ohne.</summary>
    function StepCount: Integer;
    /// <summary>Zeilen der Kette; ein Schritt ohne Fundstelle springt zum Knoten, zu dem er führt.</summary>
    function Rows: TArray<TAtlasSymbolPathRow>;
  end;

  TAtlasSymbolPathCommands = class
  public const
    Command = 'atlas.symbolPath';
    DefaultSteps = 8;
    MaxSteps = 16;
  public
    /// <summary>[uri, {"from", "to", "maxSteps", "all"}]; AMaxSteps außerhalb 1–16 entfällt (Vorgabe des Servers).
    /// </summary>
    class function Arguments(const AProjectUri, AFrom, ATo: string; AMaxSteps: Integer; AAll: Boolean): string;
      static;
    /// <summary>„Container.Name“ bzw. Name ohne Container.</summary>
    class function QualifiedName(const AName, AContainer: string): string; static;
  end;

implementation

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := mValue.Value;
  end;
end;

function IntegerOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end;
end;

function BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end;
end;

function NodeOf(AObject: TJSONObject): TAtlasSymbolPathNode;
begin
  Result := Default(TAtlasSymbolPathNode);
  Result.Caption := StringOf(AObject, 'caption');
  Result.UnitName := StringOf(AObject, 'unit');
  Result.FileName := StringOf(AObject, 'file');
  Result.Line := IntegerOf(AObject, 'line');
  Result.Character := IntegerOf(AObject, 'character');
  Result.IsUnit := BoolOf(AObject, 'isUnit');
  Result.Library_ := BoolOf(AObject, 'library');
end;

function StepOf(AObject: TJSONObject): TAtlasSymbolPathStep;
begin
  Result := Default(TAtlasSymbolPathStep);
  Result.Kind := StringOf(AObject, 'kind');
  Result.Caption := StringOf(AObject, 'caption');
  Result.Inferred := BoolOf(AObject, 'inferred');
  Result.Reverse := BoolOf(AObject, 'reverse');
  Result.Implementation_ := BoolOf(AObject, 'implementation');
  Result.FileName := StringOf(AObject, 'file');
  Result.Line := IntegerOf(AObject, 'line');
  Result.Character := IntegerOf(AObject, 'character');
end;

function NodesOf(AArray: TJSONArray): TArray<TAtlasSymbolPathNode>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mItem in AArray do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [NodeOf(TJSONObject(mItem))];
    end;
  end;
end;

function StatusOf(const AText: string; out AStatus: TAtlasSymbolPathStatus): Boolean;
const
  cNames: array[TAtlasSymbolPathStatus] of string = ('found', 'noPath', 'aborted', 'ambiguous', 'notFound');
var
  mStatus: TAtlasSymbolPathStatus;
begin
  for mStatus := Low(TAtlasSymbolPathStatus) to High(TAtlasSymbolPathStatus) do
  begin
    if cNames[mStatus] = AText then
    begin
      AStatus := mStatus;
      Exit(True);
    end;
  end;
  AStatus := TAtlasSymbolPathStatus.NotFound;
  Result := False;
end;

{ TAtlasSymbolPathRoute }

function TAtlasSymbolPathRoute.UnitNames: TArray<string>;
var
  mNode: TAtlasSymbolPathNode;
begin
  Result := nil;
  for mNode in Nodes do
  begin
    if mNode.UnitName = '' then
    begin
      Continue;
    end;
    if (Length(Result) > 0) and SameText(Result[High(Result)], mNode.UnitName) then
    begin
      Continue;
    end;
    Result := Result + [mNode.UnitName];
  end;
end;

{ TAtlasSymbolPathAnswer }

function StepsOf(ASteps: TJSONArray): TArray<TAtlasSymbolPathStep>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if ASteps <> nil then
  begin
    for mItem in ASteps do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [StepOf(TJSONObject(mItem))];
      end;
    end;
  end;
end;

/// <summary>Wege der Antwort; False, wenn einer beschädigt ist (ein Weg mit n Knoten hat n - 1 Schritte).
/// </summary>
function RoutesOf(ARoutes: TJSONArray; var AModel: TAtlasSymbolPathAnswer): Boolean;
var
  mItem: TJSONValue;
  mRoute: TAtlasSymbolPathRoute;
begin
  Result := True;
  if ARoutes = nil then
  begin
    Exit;
  end;
  for mItem in ARoutes do
  begin
    if mItem is TJSONObject then
    begin
      mRoute := Default(TAtlasSymbolPathRoute);
      mRoute.Nodes := NodesOf(ArrayOf(TJSONObject(mItem), 'nodes'));
      mRoute.Steps := StepsOf(ArrayOf(TJSONObject(mItem), 'steps'));
      Result := Length(mRoute.Nodes) = Length(mRoute.Steps) + 1;
      if not Result then
      begin
        Exit;
      end;
      AModel.Routes := AModel.Routes + [mRoute];
    end;
  end;
end;

/// <summary>Felder einer eingeschalteten Antwort; False bei unbekanntem Status oder beschädigtem Weg.</summary>
function ReadAnswer(AData: TJSONObject; var AModel: TAtlasSymbolPathAnswer): Boolean;
var
  mStatus: TAtlasSymbolPathStatus;
begin
  Result := StatusOf(StringOf(AData, 'status'), mStatus);
  if not Result then
  begin
    Exit;
  end;
  AModel.Status := mStatus;
  AModel.From := StringOf(AData, 'from');
  AModel.To_ := StringOf(AData, 'to');
  AModel.MoreRoutes := BoolOf(AData, 'moreRoutes');
  AModel.MaxSteps := IntegerOf(AData, 'maxSteps');
  AModel.SearchedSteps := IntegerOf(AData, 'searchedSteps');
  AModel.Visited := IntegerOf(AData, 'visited');
  AModel.ElapsedMs := IntegerOf(AData, 'elapsedMs');
  AModel.AbortReason := StringOf(AData, 'abortReason');
  AModel.Subject := StringOf(AData, 'subject');
  AModel.CallsIncomplete := BoolOf(AData, 'callsIncomplete');
  AModel.Candidates := NodesOf(ArrayOf(AData, 'candidates'));
  Result := RoutesOf(ArrayOf(AData, 'routes'), AModel);
end;

function ParsedObject(const AAnswer: string): TJSONObject;
var
  mRoot: TJSONValue;
begin
  Result := nil;
  if Trim(AAnswer) = '' then
  begin
    Exit;
  end;
  try
    mRoot := TJSONObject.ParseJSONValue(AAnswer);
  except
    on EJSONException do
      mRoot := nil;
  end;
  if mRoot is TJSONObject then
  begin
    Result := TJSONObject(mRoot);
  end
  else
  begin
    mRoot.Free;
  end;
end;

class function TAtlasSymbolPathAnswer.Parse(const AAnswer: string; out AModel: TAtlasSymbolPathAnswer): Boolean;
var
  mData: TJSONObject;
begin
  AModel := Default(TAtlasSymbolPathAnswer);
  Result := False;
  mData := ParsedObject(AAnswer);
  if mData = nil then
  begin
    Exit;
  end;
  try
    if mData.GetValue('enabled') is TJSONBool then
    begin
      AModel.Enabled := BoolOf(mData, 'enabled');
      Result := not AModel.Enabled or ReadAnswer(mData, AModel);
    end;
  finally
    mData.Free;
  end;
end;

function TAtlasSymbolPathAnswer.StepCount: Integer;
begin
  Result := 0;
  if Length(Routes) > 0 then
  begin
    Result := Length(Routes[0].Steps);
  end;
end;

function PlaceRow(AKind: TAtlasSymbolPathRowKind; ARoute, AIndex: Integer;
  const ANode: TAtlasSymbolPathNode): TAtlasSymbolPathRow;
begin
  Result := Default(TAtlasSymbolPathRow);
  Result.Kind := AKind;
  Result.Route := ARoute;
  Result.Index := AIndex;
  Result.FileName := ANode.FileName;
  Result.Line := ANode.Line;
  Result.Character := ANode.Character;
end;

/// <summary>Schritt AIndex des Wegs: an seiner Stelle, ohne eigene an der des nächsten Knotens.</summary>
function StepRow(const ARoute: TAtlasSymbolPathRoute; ARouteIndex, AIndex: Integer): TAtlasSymbolPathRow;
begin
  Result := PlaceRow(TAtlasSymbolPathRowKind.Step, ARouteIndex, AIndex, ARoute.Nodes[AIndex + 1]);
  Result.Inferred := ARoute.Steps[AIndex].Inferred;
  if ARoute.Steps[AIndex].FileName <> '' then
  begin
    Result.FileName := ARoute.Steps[AIndex].FileName;
    Result.Line := ARoute.Steps[AIndex].Line;
    Result.Character := ARoute.Steps[AIndex].Character;
  end;
end;

function RouteRows(const ARoute: TAtlasSymbolPathRoute; ARouteIndex: Integer;
  AWithHeader: Boolean): TArray<TAtlasSymbolPathRow>;
var
  mIndex: Integer;
  mHeader: TAtlasSymbolPathRow;
begin
  Result := nil;
  if AWithHeader then
  begin
    mHeader := Default(TAtlasSymbolPathRow);
    mHeader.Kind := TAtlasSymbolPathRowKind.Header;
    mHeader.Route := ARouteIndex;
    mHeader.Index := -1;
    Result := [mHeader];
  end;
  for mIndex := 0 to High(ARoute.Nodes) do
  begin
    Result := Result + [PlaceRow(TAtlasSymbolPathRowKind.Node, ARouteIndex, mIndex, ARoute.Nodes[mIndex])];
    if mIndex <= High(ARoute.Steps) then
    begin
      Result := Result + [StepRow(ARoute, ARouteIndex, mIndex)];
    end;
  end;
end;

function TAtlasSymbolPathAnswer.Rows: TArray<TAtlasSymbolPathRow>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Status = TAtlasSymbolPathStatus.Ambiguous then
  begin
    for mIndex := 0 to High(Candidates) do
    begin
      Result := Result + [PlaceRow(TAtlasSymbolPathRowKind.Candidate, 0, mIndex, Candidates[mIndex])];
    end;
  end
  else
  begin
    for mIndex := 0 to High(Routes) do
    begin
      Result := Result + RouteRows(Routes[mIndex], mIndex, Length(Routes) > 1);
    end;
  end;
end;

{ TAtlasSymbolPathCommands }

class function TAtlasSymbolPathCommands.Arguments(const AProjectUri, AFrom, ATo: string; AMaxSteps: Integer;
  AAll: Boolean): string;
var
  mValues: TJSONArray;
  mOptions: TJSONObject;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AProjectUri);
    mOptions := TJSONObject.Create;
    mValues.AddElement(mOptions);
    mOptions.AddPair('from', Trim(AFrom));
    mOptions.AddPair('to', Trim(ATo));
    if (AMaxSteps >= 1) and (AMaxSteps <= MaxSteps) then
    begin
      mOptions.AddPair('maxSteps', TJSONNumber.Create(AMaxSteps));
    end;
    mOptions.AddPair('all', TJSONBool.Create(AAll));
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

class function TAtlasSymbolPathCommands.QualifiedName(const AName, AContainer: string): string;
begin
  if AContainer = '' then
  begin
    Result := AName;
  end
  else
  begin
    Result := AContainer + '.' + AName;
  end;
end;

end.
