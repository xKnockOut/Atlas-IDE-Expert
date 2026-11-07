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
    cMethod = 'atlas/dataFlow';
  public
    /// <summary>Parameter der Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Params(const ARequest: TAtlasDataFlowRequest): TJSONObject; static;
    /// <summary>Antwort des Servers; null oder Unbekanntes ergibt Found = False.</summary>
    class function Parse(const AValue: TJSONValue): TAtlasDataFlowResult; static;
    class function KindOf(const AName: string): TAtlasDataFlowKind; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Uris;

function UriToPath(const AUri: string): string;
begin
  Result := StringReplace(TTextUris.ToPath(AUri), '/', '\', [rfReplaceAll]);
end;

function ReadSymbol(const AValue: TJSONValue): TAtlasDataFlowSymbol;
var
  mLeaf: string;
begin
  Result := Default(TAtlasDataFlowSymbol);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Result.Name := TJSONObject(AValue).GetValue<string>('name', '');
  Result.FileName := UriToPath(TJSONObject(AValue).GetValue<string>('uri', ''));
  Result.Line := TJSONObject(AValue).GetValue<Integer>('line', 0);
  Result.Character := TJSONObject(AValue).GetValue<Integer>('character', 0);
  Result.Key := TJSONObject(AValue).GetValue<string>('key', '');
  mLeaf := TJSONObject(AValue).GetValue<string>('leaf', '');
  if mLeaf = 'constant' then
  begin
    Result.Leaf := TAtlasDataFlowLeaf.Constant;
  end
  else if mLeaf = 'outside' then
  begin
    Result.Leaf := TAtlasDataFlowLeaf.Outside;
  end
  else if mLeaf = 'cycle' then
  begin
    Result.Leaf := TAtlasDataFlowLeaf.Cycle;
  end;
end;

function ReadPlace(const AValue: TJSONValue): TAtlasDataFlowPlace;
begin
  Result := Default(TAtlasDataFlowPlace);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
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

/// <summary>Array AName von AItem, nil ohne.</summary>
function ArrayOf(AItem: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AItem.TryGetValue<TJSONValue>(AName, mValue) and (mValue is TJSONArray) then
  begin
    Result := TJSONArray(mValue);
  end;
end;

/// <summary>Liest einen Knoten; False, wenn er keinen Fundort hat.</summary>
function ReadNode(AItem: TJSONObject; out ANode: TAtlasDataFlowNode): Boolean;
var
  mList: TJSONArray;
  mEntry: TJSONValue;
begin
  ANode := Default(TAtlasDataFlowNode);
  ANode.Kind := TAtlasDataFlowJson.KindOf(AItem.GetValue<string>('kind', ''));
  ANode.Detail := AItem.GetValue<string>('detail', '');
  ANode.Via := AItem.GetValue<string>('via', '');
  ANode.Literal := AItem.GetValue<Boolean>('literal', False);
  ANode.Unsafe := AItem.GetValue<Boolean>('unsafe', False);
  ANode.UnsafeReason := AItem.GetValue<string>('unsafeReason', '');
  mList := ArrayOf(AItem, 'places');
  if mList <> nil then
  begin
    for mEntry in mList do
    begin
      ANode.Places := ANode.Places + [ReadPlace(mEntry)];
    end;
  end;
  mList := ArrayOf(AItem, 'sources');
  if mList <> nil then
  begin
    for mEntry in mList do
    begin
      ANode.Sources := ANode.Sources + [ReadSymbol(mEntry)];
    end;
  end;
  Result := Length(ANode.Places) > 0;
end;

{ TAtlasDataFlowJson }

class function TAtlasDataFlowJson.KindOf(const AName: string): TAtlasDataFlowKind;
const
  cNames: array[TAtlasDataFlowKind] of string = ('assignment', 'varArgument', 'outArgument', 'input',
    'initialization', 'loop', 'callerArgument', 'return', 'propertyWrite', 'propertyRead', 'modify', 'argument',
    'output', 'use', 'constant', 'outside', 'address', '');
var
  mKind: TAtlasDataFlowKind;
begin
  for mKind := Low(TAtlasDataFlowKind) to Pred(TAtlasDataFlowKind.Unknown) do
  begin
    if SameText(cNames[mKind], AName) then
    begin
      Exit(mKind);
    end;
  end;
  Result := TAtlasDataFlowKind.Unknown;
end;

class function TAtlasDataFlowJson.Params(const ARequest: TAtlasDataFlowRequest): TJSONObject;
var
  mPosition: TJSONObject;
  mPath: TJSONArray;
  mKey: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TTextUris.FromPath(ARequest.FileName))));
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ARequest.Line));
  mPosition.AddPair('character', TJSONNumber.Create(ARequest.Character));
  Result.AddPair('position', mPosition);
  if ARequest.Direction = TAtlasDataFlowDirection.Targets then
  begin
    Result.AddPair('direction', 'targets');
  end
  else
  begin
    Result.AddPair('direction', 'sources');
  end;
  Result.AddPair('excludeTests', TJSONBool.Create(ARequest.ExcludeTests));
  Result.AddPair('onlyProject', TJSONBool.Create(ARequest.OnlyProject));
  mPath := TJSONArray.Create;
  for mKey in ARequest.Path do
  begin
    mPath.Add(mKey);
  end;
  Result.AddPair('path', mPath);
end;

class function TAtlasDataFlowJson.Parse(const AValue: TJSONValue): TAtlasDataFlowResult;
var
  mResponse: TJSONObject;
  mValue: TJSONValue;
  mNode: TAtlasDataFlowNode;
begin
  Result := Default(TAtlasDataFlowResult);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mResponse := TJSONObject(AValue);
  Result.Found := mResponse.GetValue<Boolean>('found', False);
  if not Result.Found then
  begin
    Exit;
  end;
  if mResponse.TryGetValue<TJSONValue>('symbol', mValue) then
  begin
    Result.Symbol := ReadSymbol(mValue);
  end;
  if not (mResponse.TryGetValue<TJSONValue>('nodes', mValue) and (mValue is TJSONArray)) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(mValue) do
  begin
    // Eine Stelle ohne Fundort lässt sich weder zeigen noch anspringen.
    if (mValue is TJSONObject) and ReadNode(TJSONObject(mValue), mNode) then
    begin
      Result.Nodes := Result.Nodes + [mNode];
    end;
  end;
end;

end.
