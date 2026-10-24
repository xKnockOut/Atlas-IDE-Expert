unit Atlas.Core.Lsp.AccessChains;

// Zugriffsketten am Ausführungspunkt (#865), Plugin-Seite: Parameter von atlas/accessChains und Lesen der
// Antwort (Ketten, Glieder mit Art, Typ, Aufruf, Index und Feldern samt geschätztem Versatz).

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasAvLinkKind = (Unknown, ClassRef, InterfaceRef, Pointer, DynArray);
  {$SCOPEDENUMS OFF}

  TAtlasAvField = record
    Name: string;
    /// <summary>Geschätzt vom Server; -1 = unbekannt.</summary>
    Offset: Integer;
  end;

  TAtlasAvLink = record
    Expression: string;
    Name: string;
    TypeName: string;
    Member: string;
    Kind: TAtlasAvLinkKind;
    Call: Boolean;
    ImplicitSelf: Boolean;
    IndexText: string;
    IndexPlain: Boolean;
    /// <summary>Bereich im Quelltext, 0-basiert (Zeichen in UTF-16).</summary>
    StartLine, StartCharacter, EndLine, EndCharacter: Integer;
    NameLine, NameCharacter: Integer;
    Fields: TArray<TAtlasAvField>;
  end;

  TAtlasAvChain = record
    Text: string;
    Links: TArray<TAtlasAvLink>;
  end;

  TAtlasAvChains = record
    Found: Boolean;
    Statements: Integer;
    Chains: TArray<TAtlasAvChain>;
  end;

  TAtlasAvJson = class
  public const
    Method = 'atlas/accessChains';
  public
    /// <summary>Parameter der Anfrage (ALine 0-basiert). Der Aufrufer übernimmt das Objekt.</summary>
    class function Params(const AFileName: string; ALine, APointerSize: Integer): TJSONObject; static;
    class function Parse(const AValue: TJSONValue): TAtlasAvChains; static;
    /// <summary>8 für Win64 (auch Win64x), sonst 4.</summary>
    class function PointerSize(const APlatform: string): Integer; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Uris;

{ TAtlasAvJson }

class function TAtlasAvJson.PointerSize(const APlatform: string): Integer;
begin
  if StartsText('win64', Trim(APlatform)) then
    Result := 8
  else
    Result := 4;
end;

class function TAtlasAvJson.Params(const AFileName: string; ALine, APointerSize: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TTextUris.FromPath(AFileName))));
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('pointerSize', TJSONNumber.Create(APointerSize));
end;

function KindOf(const AName: string): TAtlasAvLinkKind;
begin
  if AName = 'class' then
    Result := TAtlasAvLinkKind.ClassRef
  else if AName = 'interface' then
    Result := TAtlasAvLinkKind.InterfaceRef
  else if AName = 'pointer' then
    Result := TAtlasAvLinkKind.Pointer
  else if AName = 'dynArray' then
    Result := TAtlasAvLinkKind.DynArray
  else
    Result := TAtlasAvLinkKind.Unknown;
end;

procedure ReadPosition(AObject: TJSONObject; const AName: string; out ALine, ACharacter: Integer);
var
  Value: TJSONValue;
begin
  ALine := 0;
  ACharacter := 0;
  if AObject.TryGetValue<TJSONValue>(AName, Value) and (Value is TJSONObject) then
  begin
    ALine := TJSONObject(Value).GetValue<Integer>('line', 0);
    ACharacter := TJSONObject(Value).GetValue<Integer>('character', 0);
  end;
end;

function ReadLink(AItem: TJSONObject): TAtlasAvLink;
var
  Value, Entry: TJSONValue;
  Range: TJSONObject;
  Field: TAtlasAvField;
begin
  Result := Default(TAtlasAvLink);
  Result.Expression := AItem.GetValue<string>('expression', '');
  Result.Name := AItem.GetValue<string>('name', '');
  Result.TypeName := AItem.GetValue<string>('typeName', '');
  Result.Member := AItem.GetValue<string>('member', '');
  Result.Kind := KindOf(AItem.GetValue<string>('kind', ''));
  Result.Call := AItem.GetValue<Boolean>('call', False);
  Result.ImplicitSelf := AItem.GetValue<Boolean>('implicitSelf', False);
  Result.IndexText := AItem.GetValue<string>('index', '');
  Result.IndexPlain := AItem.GetValue<Boolean>('indexPlain', False);
  if AItem.TryGetValue<TJSONValue>('range', Value) and (Value is TJSONObject) then
  begin
    Range := TJSONObject(Value);
    ReadPosition(Range, 'start', Result.StartLine, Result.StartCharacter);
    ReadPosition(Range, 'end', Result.EndLine, Result.EndCharacter);
  end;
  ReadPosition(AItem, 'namePosition', Result.NameLine, Result.NameCharacter);
  if AItem.TryGetValue<TJSONValue>('fields', Value) and (Value is TJSONArray) then
    for Entry in TJSONArray(Value) do
      if Entry is TJSONObject then
      begin
        Field.Name := TJSONObject(Entry).GetValue<string>('name', '');
        Field.Offset := TJSONObject(Entry).GetValue<Integer>('offset', -1);
        Result.Fields := Result.Fields + [Field];
      end;
end;

class function TAtlasAvJson.Parse(const AValue: TJSONValue): TAtlasAvChains;
var
  Response: TJSONObject;
  Value, Entry, LinkValue: TJSONValue;
  Chain: TAtlasAvChain;
begin
  Result := Default(TAtlasAvChains);
  if not (AValue is TJSONObject) then
    Exit;
  Response := TJSONObject(AValue);
  Result.Found := True;
  Result.Statements := Response.GetValue<Integer>('statements', 0);
  if not (Response.TryGetValue<TJSONValue>('chains', Value) and (Value is TJSONArray)) then
    Exit;
  for Entry in TJSONArray(Value) do
  begin
    if not (Entry is TJSONObject) then
      Continue;
    Chain := Default(TAtlasAvChain);
    Chain.Text := TJSONObject(Entry).GetValue<string>('text', '');
    if TJSONObject(Entry).TryGetValue<TJSONValue>('links', LinkValue) and (LinkValue is TJSONArray) then
      for LinkValue in TJSONArray(LinkValue) do
        if LinkValue is TJSONObject then
          Chain.Links := Chain.Links + [ReadLink(TJSONObject(LinkValue))];
    if Chain.Links <> nil then
      Result.Chains := Result.Chains + [Chain];
  end;
end;

end.
