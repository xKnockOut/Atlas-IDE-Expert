unit Argus.Core.Hover.Contract;

// Inhalt des Hover-Tooltips (#442, #588) aus dem Objekt "argus" der Hover-
// Antwort: Deklaration, Unit, Doku, Wert, Veraltung, dazu Art und Herkunft für
// die Kopfzeile, Fundort, Typnamen in der Deklaration als Links und die
// Vererbungskette. Ohne "argus" (fremder Server, Direktiven, Schlüsselwörter)
// wird der Klartext wie bisher in Deklaration und Doku geteilt.

interface

uses
  System.JSON;

type
  /// <summary>Typ mit Fundort (0-basiert); FileName '' ohne Fundort.</summary>
  TArgusHoverTypeRef = record
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    /// <summary>Schlüssel für "derselbe Typ" (Datei und Position bzw. Name).</summary>
    function Key: string;
    class function FromJson(const AObject: TJSONObject): TArgusHoverTypeRef; static;
  end;

  /// <summary>Typname in der Deklaration: Start (0-basiert) und Länge im Text.</summary>
  TArgusHoverLink = record
    Start: Integer;
    Length: Integer;
    Target: TArgusHoverTypeRef;
  end;

  TArgusHoverData = record
  public const
    KindClassRef = 'classref';
    /// <summary>Bis zu so vielen Gliedern zeigt der Tooltip die ganze Kette.</summary>
    MaxChainShown = 5;
  public
    Declaration: string;
    UnitName: string;
    Documentation: string;
    Value: string;
    Deprecation: string;
    /// <summary>class, classref, record, interface, enum, type, method … ('' unbekannt).</summary>
    Kind: string;
    /// <summary>VCL, FMX, RTL oder '' (eigene Unit).</summary>
    Origin: string;
    DocWiki: string;
    /// <summary>Fundort der Deklaration; Name ist der deklarierte Name, wenn bekannt.</summary>
    Location: TArgusHoverTypeRef;
    Links: TArray<TArgusHoverLink>;
    /// <summary>Typ, dessen Kette Ancestors zeigt (bei "class of T" T).</summary>
    ChainOf: string;
    Ancestors: TArray<TArgusHoverTypeRef>;
    function Found: Boolean;
    /// <summary>Name des angezeigten Typs: erstes Kettenglied bzw. Name am Fundort bzw. Deklarationsanfang.</summary>
    function Title: string;
    /// <summary>Kürzel für das Badge wie in der Vervollständigung (ty, fn, pp, fd, va, co, un, kw).</summary>
    function Badge: string;
    /// <summary>"Datei.pas : 20" (1-basiert) bzw. die Unit; '' ohne beides.</summary>
    function LocationText: string;
    /// <summary>Indizes der anzuzeigenden Kettenglieder; -1 steht für "…" (mehr als MaxChainShown).</summary>
    function VisibleChain: TArray<Integer>;
    /// <summary>Index des Links an der Textstelle AIndex (0-basiert); -1 ohne.</summary>
    function LinkAt(AIndex: Integer): Integer;
    class function FromHover(const AHover: TJSONValue): TArgusHoverData; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TArgusHoverTypeRef }

function TArgusHoverTypeRef.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

function TArgusHoverTypeRef.Key: string;
begin
  if HasLocation then
    Result := Format('%s|%d|%d', [UpperCase(FileName), Line, Character])
  else
    Result := UpperCase(Name);
end;

class function TArgusHoverTypeRef.FromJson(const AObject: TJSONObject): TArgusHoverTypeRef;
begin
  Result := Default(TArgusHoverTypeRef);
  if AObject = nil then
    Exit;
  Result.Name := AObject.GetValue<string>('name', '');
  Result.UnitName := AObject.GetValue<string>('unit', '');
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Character := AObject.GetValue<Integer>('character', 0);
end;

{ TArgusHoverData }

function TArgusHoverData.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function TArgusHoverData.Title: string;
var
  Index: Integer;
begin
  if (Length(Ancestors) > 0) and (Kind <> KindClassRef) then
    Exit(Ancestors[0].Name);
  if Location.Name <> '' then
    Exit(Location.Name);
  // Erster Bezeichner der Deklaration (TFoo = class, Name: Typ, procedure Bar).
  Result := Trim(Declaration);
  for Index := 1 to Length(Result) do
    if not CharInSet(Result[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '&']) then
    begin
      Result := Copy(Result, 1, Index - 1);
      Break;
    end;
  if MatchText(Result, ['procedure', 'function', 'constructor', 'destructor', 'property', 'class', 'type',
    'var', 'const']) then
  begin
    Result := Trim(Copy(Trim(Declaration), Length(Result) + 1, MaxInt));
    for Index := 1 to Length(Result) do
      if not CharInSet(Result[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '&']) then
      begin
        Result := Copy(Result, 1, Index - 1);
        Break;
      end;
  end;
end;

function TArgusHoverData.Badge: string;
begin
  if MatchStr(Kind, ['class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type']) then
    Result := 'ty'
  else if MatchStr(Kind, ['method', 'constructor', 'routine']) then
    Result := 'fn'
  else if Kind = 'property' then
    Result := 'pp'
  else if Kind = 'field' then
    Result := 'fd'
  else if Kind = 'variable' then
    Result := 'va'
  else if MatchStr(Kind, ['constant', 'enumMember']) then
    Result := 'co'
  else if StartsText('unit ', Declaration) then
    Result := 'un'
  else
    Result := 'kw';
end;

function TArgusHoverData.LocationText: string;
begin
  if Location.HasLocation then
    Result := Format('%s : %d', [ExtractFileName(Location.FileName), Location.Line + 1])
  else
    Result := UnitName;
end;

function TArgusHoverData.VisibleChain: TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  if Length(Ancestors) <= MaxChainShown then
  begin
    for Index := 0 to High(Ancestors) do
      Result := Result + [Index];
    Exit;
  end;
  // Die ersten vier, dann "…", dann das letzte (meist TObject).
  for Index := 0 to MaxChainShown - 2 do
    Result := Result + [Index];
  Result := Result + [-1, High(Ancestors)];
end;

function TArgusHoverData.LinkAt(AIndex: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Links) do
    if (AIndex >= Links[Index].Start) and (AIndex < Links[Index].Start + Links[Index].Length) then
      Exit(Index);
  Result := -1;
end;

function PlainText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
    Exit;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
    Result := Contents.Value
  else if Contents is TJSONObject then
    Result := TJSONObject(Contents).GetValue<string>('value', '');
end;

class function TArgusHoverData.FromHover(const AHover: TJSONValue): TArgusHoverData;
var
  Argus, Item: TJSONObject;
  List: TJSONArray;
  Value: TJSONValue;
  Link: TArgusHoverLink;
  Text: string;
  Split: Integer;
begin
  Result := Default(TArgusHoverData);
  if not (AHover is TJSONObject) then
    Exit;
  Argus := TJSONObject(AHover).GetValue('argus') as TJSONObject;
  if Argus = nil then
  begin
    // Rückfall: erster Absatz Deklaration, der Rest Doku; Markdown-Zäune entfernen.
    Text := StringReplace(PlainText(AHover), '```pascal', '', [rfReplaceAll]);
    Text := Trim(StringReplace(Text, '```', '', [rfReplaceAll]));
    Split := Pos(#10#10, Text);
    if Split = 0 then
      Result.Declaration := Text
    else
    begin
      Result.Declaration := Trim(Copy(Text, 1, Split - 1));
      Result.Documentation := Trim(Copy(Text, Split + 2, MaxInt));
    end;
    Exit;
  end;
  Result.Declaration := Argus.GetValue<string>('declaration', '');
  Result.UnitName := Argus.GetValue<string>('unit', '');
  Result.Documentation := Argus.GetValue<string>('documentation', '');
  Result.Value := Argus.GetValue<string>('value', '');
  Result.Deprecation := Argus.GetValue<string>('deprecation', '');
  Result.Kind := Argus.GetValue<string>('kind', '');
  Result.Origin := Argus.GetValue<string>('origin', '');
  Result.DocWiki := Argus.GetValue<string>('docWiki', '');
  Result.Location := TArgusHoverTypeRef.FromJson(Argus);
  Result.Location.Name := '';
  Result.Location.UnitName := Result.UnitName;
  Result.ChainOf := Argus.GetValue<string>('chainOf', '');
  if Argus.TryGetValue<TJSONArray>('links', List) then
    for Value in List do
      if Value is TJSONObject then
      begin
        Item := TJSONObject(Value);
        Link.Start := Item.GetValue<Integer>('start', 0);
        Link.Length := Item.GetValue<Integer>('length', 0);
        Link.Target := TArgusHoverTypeRef.FromJson(Item);
        if Link.Length > 0 then
          Result.Links := Result.Links + [Link];
      end;
  if Argus.TryGetValue<TJSONArray>('ancestors', List) then
    for Value in List do
      if Value is TJSONObject then
        Result.Ancestors := Result.Ancestors + [TArgusHoverTypeRef.FromJson(TJSONObject(Value))];
  // Der angezeigte Typ selbst: erstes Kettenglied mit demselben Fundort.
  if (Length(Result.Ancestors) > 0) and (Result.Ancestors[0].Key = Result.Location.Key) then
    Result.Location.Name := Result.Ancestors[0].Name;
end;

end.
