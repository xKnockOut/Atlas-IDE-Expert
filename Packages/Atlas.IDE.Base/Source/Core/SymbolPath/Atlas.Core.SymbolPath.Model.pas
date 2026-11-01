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
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Value.Value;
end;

function IntegerOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
end;

function BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AName);
  if Value is TJSONArray then
    Result := TJSONArray(Value);
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
  Item: TJSONValue;
begin
  Result := nil;
  if AArray = nil then
    Exit;
  for Item in AArray do
    if Item is TJSONObject then
      Result := Result + [NodeOf(TJSONObject(Item))];
end;

function StatusOf(const AText: string; out AStatus: TAtlasSymbolPathStatus): Boolean;
const
  Names: array[TAtlasSymbolPathStatus] of string = ('found', 'noPath', 'aborted', 'ambiguous', 'notFound');
var
  Status: TAtlasSymbolPathStatus;
begin
  for Status := Low(TAtlasSymbolPathStatus) to High(TAtlasSymbolPathStatus) do
    if Names[Status] = AText then
    begin
      AStatus := Status;
      Exit(True);
    end;
  AStatus := TAtlasSymbolPathStatus.NotFound;
  Result := False;
end;

{ TAtlasSymbolPathRoute }

function TAtlasSymbolPathRoute.UnitNames: TArray<string>;
var
  Node: TAtlasSymbolPathNode;
begin
  Result := nil;
  for Node in Nodes do
  begin
    if Node.UnitName = '' then
      Continue;
    if (Length(Result) > 0) and SameText(Result[High(Result)], Node.UnitName) then
      Continue;
    Result := Result + [Node.UnitName];
  end;
end;

{ TAtlasSymbolPathAnswer }

class function TAtlasSymbolPathAnswer.Parse(const AAnswer: string; out AModel: TAtlasSymbolPathAnswer): Boolean;
var
  Root: TJSONValue;
  Data, RouteObject: TJSONObject;
  Routes, Steps: TJSONArray;
  Item, StepItem: TJSONValue;
  Route: TAtlasSymbolPathRoute;
  Status: TAtlasSymbolPathStatus;
begin
  AModel := Default(TAtlasSymbolPathAnswer);
  Result := False;
  if Trim(AAnswer) = '' then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(AAnswer);
  except
    on EJSONException do
      Root := nil;
  end;
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Exit;
  end;
  try
    Data := TJSONObject(Root);
    if not (Data.GetValue('enabled') is TJSONBool) then
      Exit;
    AModel.Enabled := BoolOf(Data, 'enabled');
    if not AModel.Enabled then
      Exit(True);
    if not StatusOf(StringOf(Data, 'status'), Status) then
      Exit;
    AModel.Status := Status;
    AModel.From := StringOf(Data, 'from');
    AModel.To_ := StringOf(Data, 'to');
    AModel.MoreRoutes := BoolOf(Data, 'moreRoutes');
    AModel.MaxSteps := IntegerOf(Data, 'maxSteps');
    AModel.SearchedSteps := IntegerOf(Data, 'searchedSteps');
    AModel.Visited := IntegerOf(Data, 'visited');
    AModel.ElapsedMs := IntegerOf(Data, 'elapsedMs');
    AModel.AbortReason := StringOf(Data, 'abortReason');
    AModel.Subject := StringOf(Data, 'subject');
    AModel.CallsIncomplete := BoolOf(Data, 'callsIncomplete');
    AModel.Candidates := NodesOf(ArrayOf(Data, 'candidates'));
    Routes := ArrayOf(Data, 'routes');
    if Routes <> nil then
      for Item in Routes do
      begin
        if not (Item is TJSONObject) then
          Continue;
        RouteObject := TJSONObject(Item);
        Route := Default(TAtlasSymbolPathRoute);
        Route.Nodes := NodesOf(ArrayOf(RouteObject, 'nodes'));
        Steps := ArrayOf(RouteObject, 'steps');
        if Steps <> nil then
          for StepItem in Steps do
            if StepItem is TJSONObject then
              Route.Steps := Route.Steps + [StepOf(TJSONObject(StepItem))];
        // Ein Weg mit n Knoten hat n - 1 Schritte; sonst ist die Antwort beschädigt.
        if Length(Route.Nodes) <> Length(Route.Steps) + 1 then
          Exit;
        AModel.Routes := AModel.Routes + [Route];
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function TAtlasSymbolPathAnswer.StepCount: Integer;
begin
  Result := 0;
  if Length(Routes) > 0 then
    Result := Length(Routes[0].Steps);
end;

function TAtlasSymbolPathAnswer.Rows: TArray<TAtlasSymbolPathRow>;
var
  RouteIndex, Index: Integer;
  Row: TAtlasSymbolPathRow;
  Route: TAtlasSymbolPathRoute;
begin
  Result := nil;
  if Status = TAtlasSymbolPathStatus.Ambiguous then
  begin
    for Index := 0 to High(Candidates) do
    begin
      Row := Default(TAtlasSymbolPathRow);
      Row.Kind := TAtlasSymbolPathRowKind.Candidate;
      Row.Index := Index;
      Row.FileName := Candidates[Index].FileName;
      Row.Line := Candidates[Index].Line;
      Row.Character := Candidates[Index].Character;
      Result := Result + [Row];
    end;
    Exit;
  end;
  for RouteIndex := 0 to High(Routes) do
  begin
    Route := Routes[RouteIndex];
    if Length(Routes) > 1 then
    begin
      Row := Default(TAtlasSymbolPathRow);
      Row.Kind := TAtlasSymbolPathRowKind.Header;
      Row.Route := RouteIndex;
      Row.Index := -1;
      Result := Result + [Row];
    end;
    for Index := 0 to High(Route.Nodes) do
    begin
      Row := Default(TAtlasSymbolPathRow);
      Row.Kind := TAtlasSymbolPathRowKind.Node;
      Row.Route := RouteIndex;
      Row.Index := Index;
      Row.FileName := Route.Nodes[Index].FileName;
      Row.Line := Route.Nodes[Index].Line;
      Row.Character := Route.Nodes[Index].Character;
      Result := Result + [Row];
      if Index > High(Route.Steps) then
        Continue;
      Row := Default(TAtlasSymbolPathRow);
      Row.Kind := TAtlasSymbolPathRowKind.Step;
      Row.Route := RouteIndex;
      Row.Index := Index;
      Row.Inferred := Route.Steps[Index].Inferred;
      if Route.Steps[Index].FileName <> '' then
      begin
        Row.FileName := Route.Steps[Index].FileName;
        Row.Line := Route.Steps[Index].Line;
        Row.Character := Route.Steps[Index].Character;
      end
      else
      begin
        Row.FileName := Route.Nodes[Index + 1].FileName;
        Row.Line := Route.Nodes[Index + 1].Line;
        Row.Character := Route.Nodes[Index + 1].Character;
      end;
      Result := Result + [Row];
    end;
  end;
end;

{ TAtlasSymbolPathCommands }

class function TAtlasSymbolPathCommands.Arguments(const AProjectUri, AFrom, ATo: string; AMaxSteps: Integer;
  AAll: Boolean): string;
var
  Values: TJSONArray;
  Options: TJSONObject;
begin
  Values := TJSONArray.Create;
  try
    Values.Add(AProjectUri);
    Options := TJSONObject.Create;
    Values.AddElement(Options);
    Options.AddPair('from', Trim(AFrom));
    Options.AddPair('to', Trim(ATo));
    if (AMaxSteps >= 1) and (AMaxSteps <= MaxSteps) then
      Options.AddPair('maxSteps', TJSONNumber.Create(AMaxSteps));
    Options.AddPair('all', TJSONBool.Create(AAll));
    Result := Values.ToJSON;
  finally
    Values.Free;
  end;
end;

class function TAtlasSymbolPathCommands.QualifiedName(const AName, AContainer: string): string;
begin
  if AContainer = '' then
    Result := AName
  else
    Result := AContainer + '.' + AName;
end;

end.
