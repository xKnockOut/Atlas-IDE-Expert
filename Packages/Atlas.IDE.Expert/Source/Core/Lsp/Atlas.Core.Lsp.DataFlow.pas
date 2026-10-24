unit Atlas.Core.Lsp.DataFlow;

// Datenfluss (#690) auf der Seite des Plugins: Anfrage und Antwort von atlas/dataFlow als Werttypen, ohne VCL
// und Open Tools API. Der Server (Atlas.Common.Lsp.DataFlow) liefert zum Symbol an einer Stelle die Stellen,
// aus denen sein Wert kommt (Sources) bzw. in die er geht (Targets), jede mit Fundorten und den Symbolen, die
// sich weiter aufklappen lassen. Positionen sind 0-basiert in UTF-16-Einheiten.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>„Woher kommt der Wert?“ bzw. „Wohin geht der Wert?“.</summary>
  TAtlasDataFlowDirection = (Sources, Targets);
  /// <summary>Warum sich eine Quelle nicht aufklappen lässt.</summary>
  TAtlasDataFlowLeaf = (None, Constant, Outside, Cycle);
  /// <summary>Art einer Stelle, wie der Server sie nennt.</summary>
  TAtlasDataFlowKind = (Assignment, VarArgument, OutArgument, Input, Initializer, Loop, CallerArgument, Return,
    PropertyWrite, PropertyRead, Modify, Argument, Output, Use, Constant, Outside, Address, Unknown);
{$SCOPEDENUMS OFF}

  TAtlasDataFlowPlace = record
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Zeile ohne Einrückung.</summary>
    LineText: string;
  end;

  TAtlasDataFlowSymbol = record
    Name: string;
    FileName: string;
    /// <summary>Name der Deklaration.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Kennung für Zyklen; gleich für alle Wege zum selben Symbol.</summary>
    Key: string;
    Leaf: TAtlasDataFlowLeaf;
  end;

  TAtlasDataFlowNode = record
    Kind: TAtlasDataFlowKind;
    Detail: string;
    /// <summary>Aufgerufener, Property oder Setter, über den der Wert läuft.</summary>
    Via: string;
    Literal: Boolean;
    Unsafe: Boolean;
    /// <summary>pointer, absolute, move, fillchar, address.</summary>
    UnsafeReason: string;
    /// <summary>Mehrere bei zusammengefassten Stellen.</summary>
    Places: TArray<TAtlasDataFlowPlace>;
    Sources: TArray<TAtlasDataFlowSymbol>;
  end;

  TAtlasDataFlowResult = record
    Found: Boolean;
    Symbol: TAtlasDataFlowSymbol;
    Nodes: TArray<TAtlasDataFlowNode>;
  end;

  TAtlasDataFlowRequest = record
    Direction: TAtlasDataFlowDirection;
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Schlüssel der Vorfahren im Baum.</summary>
    Path: TArray<string>;
    ExcludeTests: Boolean;
    OnlyProject: Boolean;
    class function Create(ADirection: TAtlasDataFlowDirection; const AFileName: string; ALine,
      ACharacter: Integer): TAtlasDataFlowRequest; static;
  end;

  TAtlasDataFlowJson = class
  public const
    Method = 'atlas/dataFlow';
  public
    /// <summary>Parameter der Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Params(const ARequest: TAtlasDataFlowRequest): TJSONObject; static;
    /// <summary>Antwort des Servers; null oder Unbekanntes ergibt Found = False.</summary>
    class function Parse(const AValue: TJSONValue): TAtlasDataFlowResult; static;
    class function KindOf(const AName: string): TAtlasDataFlowKind; static;
  end;

implementation

uses
  Atlas.Text.Uris;

function UriToPath(const AUri: string): string;
begin
  Result := StringReplace(TTextUris.ToPath(AUri), '/', '\', [rfReplaceAll]);
end;

function ReadSymbol(const AValue: TJSONValue): TAtlasDataFlowSymbol;
var
  Leaf: string;
begin
  Result := Default(TAtlasDataFlowSymbol);
  if not (AValue is TJSONObject) then
    Exit;
  Result.Name := TJSONObject(AValue).GetValue<string>('name', '');
  Result.FileName := UriToPath(TJSONObject(AValue).GetValue<string>('uri', ''));
  Result.Line := TJSONObject(AValue).GetValue<Integer>('line', 0);
  Result.Character := TJSONObject(AValue).GetValue<Integer>('character', 0);
  Result.Key := TJSONObject(AValue).GetValue<string>('key', '');
  Leaf := TJSONObject(AValue).GetValue<string>('leaf', '');
  if Leaf = 'constant' then
    Result.Leaf := TAtlasDataFlowLeaf.Constant
  else if Leaf = 'outside' then
    Result.Leaf := TAtlasDataFlowLeaf.Outside
  else if Leaf = 'cycle' then
    Result.Leaf := TAtlasDataFlowLeaf.Cycle;
end;

function ReadPlace(const AValue: TJSONValue): TAtlasDataFlowPlace;
begin
  Result := Default(TAtlasDataFlowPlace);
  if not (AValue is TJSONObject) then
    Exit;
  Result.FileName := UriToPath(TJSONObject(AValue).GetValue<string>('uri', ''));
  Result.Line := TJSONObject(AValue).GetValue<Integer>('line', 0);
  Result.Character := TJSONObject(AValue).GetValue<Integer>('character', 0);
  Result.LineText := TJSONObject(AValue).GetValue<string>('lineText', '');
end;

{ TAtlasDataFlowRequest }

class function TAtlasDataFlowRequest.Create(ADirection: TAtlasDataFlowDirection; const AFileName: string; ALine,
  ACharacter: Integer): TAtlasDataFlowRequest;
begin
  Result := Default(TAtlasDataFlowRequest);
  Result.Direction := ADirection;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TAtlasDataFlowJson }

class function TAtlasDataFlowJson.KindOf(const AName: string): TAtlasDataFlowKind;
const
  Names: array[TAtlasDataFlowKind] of string = ('assignment', 'varArgument', 'outArgument', 'input',
    'initialization', 'loop', 'callerArgument', 'return', 'propertyWrite', 'propertyRead', 'modify', 'argument',
    'output', 'use', 'constant', 'outside', 'address', '');
var
  Kind: TAtlasDataFlowKind;
begin
  for Kind := Low(TAtlasDataFlowKind) to Pred(TAtlasDataFlowKind.Unknown) do
    if SameText(Names[Kind], AName) then
      Exit(Kind);
  Result := TAtlasDataFlowKind.Unknown;
end;

class function TAtlasDataFlowJson.Params(const ARequest: TAtlasDataFlowRequest): TJSONObject;
var
  Position: TJSONObject;
  Path: TJSONArray;
  Key: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TTextUris.FromPath(ARequest.FileName))));
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ARequest.Line));
  Position.AddPair('character', TJSONNumber.Create(ARequest.Character));
  Result.AddPair('position', Position);
  if ARequest.Direction = TAtlasDataFlowDirection.Targets then
    Result.AddPair('direction', 'targets')
  else
    Result.AddPair('direction', 'sources');
  Result.AddPair('excludeTests', TJSONBool.Create(ARequest.ExcludeTests));
  Result.AddPair('onlyProject', TJSONBool.Create(ARequest.OnlyProject));
  Path := TJSONArray.Create;
  for Key in ARequest.Path do
    Path.Add(Key);
  Result.AddPair('path', Path);
end;

class function TAtlasDataFlowJson.Parse(const AValue: TJSONValue): TAtlasDataFlowResult;
var
  Response, Item: TJSONObject;
  Nodes, List: TJSONArray;
  Value, Entry: TJSONValue;
  Node: TAtlasDataFlowNode;
begin
  Result := Default(TAtlasDataFlowResult);
  if not (AValue is TJSONObject) then
    Exit;
  Response := TJSONObject(AValue);
  Result.Found := Response.GetValue<Boolean>('found', False);
  if not Result.Found then
    Exit;
  if Response.TryGetValue<TJSONValue>('symbol', Value) then
    Result.Symbol := ReadSymbol(Value);
  if not (Response.TryGetValue<TJSONValue>('nodes', Value) and (Value is TJSONArray)) then
    Exit;
  Nodes := TJSONArray(Value);
  for Value in Nodes do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    Node := Default(TAtlasDataFlowNode);
    Node.Kind := KindOf(Item.GetValue<string>('kind', ''));
    Node.Detail := Item.GetValue<string>('detail', '');
    Node.Via := Item.GetValue<string>('via', '');
    Node.Literal := Item.GetValue<Boolean>('literal', False);
    Node.Unsafe := Item.GetValue<Boolean>('unsafe', False);
    Node.UnsafeReason := Item.GetValue<string>('unsafeReason', '');
    if Item.TryGetValue<TJSONValue>('places', Entry) and (Entry is TJSONArray) then
    begin
      List := TJSONArray(Entry);
      for Entry in List do
        Node.Places := Node.Places + [ReadPlace(Entry)];
    end;
    if Item.TryGetValue<TJSONValue>('sources', Entry) and (Entry is TJSONArray) then
    begin
      List := TJSONArray(Entry);
      for Entry in List do
        Node.Sources := Node.Sources + [ReadSymbol(Entry)];
    end;
    // Eine Stelle ohne Fundort lässt sich weder zeigen noch anspringen.
    if Length(Node.Places) > 0 then
      Result.Nodes := Result.Nodes + [Node];
  end;
end;

end.
