unit Atlas.Common.Editing.DataFieldNames;

// Feld- und Parameternamen in FieldByName('…'), FindField('…') und
// ParamByName('…') (#461): den Aufruf am Cursor in einer Zeile erkennen, die
// Namen der Datenmenge aus der Formulardatei sammeln und die SELECT-Liste einer
// Anweisung in Spaltennamen zerlegen.
//
// Quellen in dieser Reihenfolge: persistente Felder (Kindobjekte mit
// FieldName), Spalten der SQL-Anweisung aus SQL.Strings bzw. CommandText
// (Aliasnamen gelten, bei * keine Spalten, solange es keinen Schema-Cache gibt,
// #462); für ParamByName die :Platzhalter der Anweisung und die Einträge der
// Params-, Parameters- bzw. ParamData-Sammlung. Ohne Formulardatei oder ohne
// Datenmenge darin gibt es keine Namen: Zur Laufzeit erzeugte Datenmengen
// bekommen keinen geratenen Vorschlag.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TDataNameKind = (Field, Param);
  {$SCOPEDENUMS OFF}

  /// <summary>Aufruf wie qryOrders.FieldByName('cu|') mit dem Cursor im String-Literal.</summary>
  TDataNameCall = record
    /// <summary>Name der Datenmenge ohne "Self." und ohne ".Params", ".Parameters", ".ParamData", ".Fields".</summary>
    DataSet: string;
    Kind: TDataNameKind;
    /// <summary>FieldByName, FindField oder ParamByName wie im Quelltext.</summary>
    Method: string;
    /// <summary>Spalte hinter dem öffnenden Anführungszeichen (0-basiert).</summary>
    ContentStart: Integer;
    /// <summary>Ende des Inhalts (exklusiv): vor dem schließenden Anführungszeichen, ohne eines das Zeilenende.</summary>
    ContentEnd: Integer;
    /// <summary>Inhalt des Literals, '' als ' gelesen.</summary>
    Content: string;
  end;

  TDataName = record
    /// <summary>Schreibweise wie in der Quelle.</summary>
    Name: string;
    /// <summary>Feld- oder Parametertyp ("Integer", "String"); '' wenn unbekannt.</summary>
    TypeName: string;
  end;

  TDataFieldNames = class
  public
    /// <summary>Steht der Cursor (ACharacter Zeichen vor ihm, 0-basiert) im ersten Argument von FieldByName,
    /// FindField oder ParamByName an einer Datenmenge dieser Unit? False bei Datenmengen anderer Units
    /// ("DM.qryOrders") und ohne Datenmenge vor dem Punkt.</summary>
    class function CallAt(const ALine: string; ACharacter: Integer; out ACall: TDataNameCall): Boolean; static;
    /// <summary>Spaltennamen der ersten SELECT-Liste in ASql: Aliasname, sonst der letzte Teil von
    /// "T.Spalte"; Ausdrücke ohne Alias entfallen. AStar: Die Liste enthält * oder T.*.</summary>
    class function SelectColumns(const ASql: string; out AStar: Boolean): TArray<string>; static;
    /// <summary>Namen für ADataSet aus der Formulardatei, ohne Doppelte. ASql ist die SQL-Anweisung der
    /// Datenmenge ('' ohne). AFound: Die Datenmenge steht in der Formulardatei.</summary>
    class function FromForm(const AFormText, ADataSet: string; AKind: TDataNameKind; out ASql: string;
      out AFound: Boolean): TArray<TDataName>; static;
    /// <summary>ASql in einer Zeile mit einfachen Leerzeichen, nach AMaxLength Zeichen mit "…" gekürzt.</summary>
    class function ShortSql(const ASql: string; AMaxLength: Integer = 60): string; static;
    /// <summary>Steht AName (ohne Groß-/Kleinschreibung) in ANames?</summary>
    class function Contains(const ANames: TArray<TDataName>; const AName: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser;

type
  {$SCOPEDENUMS ON}
  TSqlTokenKind = (Word, Quoted, Text, Number, Symbol);
  {$SCOPEDENUMS OFF}

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    function IsWord(const AText: string): Boolean;
    function IsSymbol(const AText: string): Boolean;
  end;

  TSqlTokens = TArray<TSqlToken>;

function TSqlToken.IsWord(const AText: string): Boolean;
begin
  Result := (Kind = TSqlTokenKind.Word) and SameText(Text, AText);
end;

function TSqlToken.IsSymbol(const AText: string): Boolean;
begin
  Result := (Kind = TSqlTokenKind.Symbol) and (Text = AText);
end;

function IsWordStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '@', '#']) or (Ord(C) > 127);
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := IsWordStart(C) or CharInSet(C, ['0'..'9', '$']);
end;

function MakeToken(AKind: TSqlTokenKind; const AText: string): TSqlToken;
begin
  Result.Kind := AKind;
  Result.Text := AText;
end;

/// <summary>Zerlegt SQL in Wörter, Bezeichner in "…", […] oder `…`, Strings, Zahlen und Zeichen;
/// Kommentare entfallen.</summary>
function Tokenize(const ASql: string): TSqlTokens;
var
  Index, Start: Integer;
  C, Close: Char;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(ASql) do
  begin
    C := ASql[Index];
    if C <= ' ' then
      Inc(Index)
    else if (C = '-') and (Index < Length(ASql)) and (ASql[Index + 1] = '-') then
    begin
      while (Index <= Length(ASql)) and not CharInSet(ASql[Index], [#10, #13]) do
        Inc(Index);
    end
    else if (C = '/') and (Index < Length(ASql)) and (ASql[Index + 1] = '*') then
    begin
      Start := PosEx('*/', ASql, Index + 2);
      if Start = 0 then
        Index := Length(ASql) + 1
      else
        Index := Start + 2;
    end
    else if C = '''' then
    begin
      Start := Index;
      Inc(Index);
      while Index <= Length(ASql) do
        if ASql[Index] = '''' then
        begin
          if (Index < Length(ASql)) and (ASql[Index + 1] = '''') then
            Inc(Index, 2)
          else
            Break;
        end
        else
          Inc(Index);
      Result := Result + [MakeToken(TSqlTokenKind.Text, Copy(ASql, Start, Index - Start + 1))];
      Inc(Index);
    end
    else if CharInSet(C, ['"', '[', '`']) then
    begin
      Close := C;
      if C = '[' then
        Close := ']';
      Start := Index + 1;
      Index := Start;
      while (Index <= Length(ASql)) and (ASql[Index] <> Close) do
        Inc(Index);
      Result := Result + [MakeToken(TSqlTokenKind.Quoted, Copy(ASql, Start, Index - Start))];
      Inc(Index);
    end
    else if IsWordStart(C) then
    begin
      Start := Index;
      while (Index <= Length(ASql)) and IsWordChar(ASql[Index]) do
        Inc(Index);
      Result := Result + [MakeToken(TSqlTokenKind.Word, Copy(ASql, Start, Index - Start))];
    end
    else if CharInSet(C, ['0'..'9']) then
    begin
      Start := Index;
      while (Index <= Length(ASql)) and CharInSet(ASql[Index], ['0'..'9', '.']) do
        Inc(Index);
      Result := Result + [MakeToken(TSqlTokenKind.Number, Copy(ASql, Start, Index - Start))];
    end
    else
    begin
      Result := Result + [MakeToken(TSqlTokenKind.Symbol, C)];
      Inc(Index);
    end;
  end;
end;

function IsName(const AToken: TSqlToken): Boolean;
begin
  Result := AToken.Kind in [TSqlTokenKind.Word, TSqlTokenKind.Quoted];
end;

/// <summary>Wörter, die am Ende eines Ausdrucks stehen können, aber kein Aliasname sind.</summary>
function IsKeyword(const AToken: TSqlToken): Boolean;
begin
  Result := (AToken.Kind = TSqlTokenKind.Word) and (IndexText(AToken.Text,
    ['end', 'null', 'true', 'false', 'and', 'or', 'not', 'as', 'is', 'distinct']) >= 0);
end;

/// <summary>Spaltenname eines Eintrags der SELECT-Liste; '' bei Ausdrücken ohne Alias.</summary>
function ColumnName(const ATokens: TSqlTokens; out AStar: Boolean): string;
var
  Count, Index: Integer;
  Chain: Boolean;
begin
  Result := '';
  AStar := False;
  Count := Length(ATokens);
  if Count = 0 then
    Exit;
  if ATokens[Count - 1].IsSymbol('*') then
  begin
    AStar := (Count = 1) or ATokens[Count - 2].IsSymbol('.');
    Exit;
  end;
  if not IsName(ATokens[Count - 1]) or IsKeyword(ATokens[Count - 1]) then
    Exit;
  // Spalte AS Alias
  if (Count >= 2) and ATokens[Count - 2].IsWord('as') then
    Exit(ATokens[Count - 1].Text);
  // T.Spalte, Spalte
  Chain := Odd(Count);
  for Index := 0 to Count - 1 do
    if Odd(Index) then
      Chain := Chain and ATokens[Index].IsSymbol('.')
    else
      Chain := Chain and IsName(ATokens[Index]);
  if Chain then
    Exit(ATokens[Count - 1].Text);
  // Ausdruck Alias: Alias direkt hinter einem Namen, String, einer Zahl oder ")".
  if (Count >= 2) and not IsKeyword(ATokens[Count - 2]) and ((ATokens[Count - 2].Kind <> TSqlTokenKind.Symbol) or
    ATokens[Count - 2].IsSymbol(')')) then
    Result := ATokens[Count - 1].Text;
end;

{ TDataFieldNames }

class function TDataFieldNames.CallAt(const ALine: string; ACharacter: Integer; out ACall: TDataNameCall): Boolean;
const
  Suffixes: array[0..3] of string = ('.Params', '.Parameters', '.ParamData', '.Fields');
var
  Index, Open, Close: Integer;
  Match: TMatch;
  Name, Suffix: string;
begin
  ACall := Default(TDataNameCall);
  Result := False;
  // String-Literal suchen, in dem der Cursor steht; Kommentare überspringen.
  Open := 0;
  Close := 0;
  Index := 1;
  while Index <= Length(ALine) do
  begin
    if ALine[Index] = '''' then
    begin
      Open := Index;
      Inc(Index);
      while Index <= Length(ALine) do
        if ALine[Index] = '''' then
        begin
          if (Index < Length(ALine)) and (ALine[Index + 1] = '''') then
            Inc(Index, 2)
          else
            Break;
        end
        else
          Inc(Index);
      Close := Index;
      if (Open <= ACharacter) and (ACharacter <= Close - 1) then
        Break;
      Open := 0;
      Inc(Index);
    end
    else if (ALine[Index] = '/') and (Index < Length(ALine)) and (ALine[Index + 1] = '/') then
      Break
    else if ALine[Index] = '{' then
    begin
      Index := PosEx('}', ALine, Index + 1);
      if Index = 0 then
        Break;
      Inc(Index);
    end
    else if (ALine[Index] = '(') and (Index < Length(ALine)) and (ALine[Index + 1] = '*') then
    begin
      Index := PosEx('*)', ALine, Index + 2);
      if Index = 0 then
        Break;
      Inc(Index, 2);
    end
    else
      Inc(Index);
  end;
  if Open = 0 then
    Exit;
  Match := TRegEx.Match(Copy(ALine, 1, Open - 1),
    '(?:^|[^\w.])((?:\w+\s*\.\s*)*\w+)\s*\.\s*(FieldByName|FindField|ParamByName)\s*\(\s*$', [roIgnoreCase]);
  if not Match.Success then
    Exit;
  Name := StringReplace(Match.Groups[1].Value, ' ', '', [rfReplaceAll]);
  if StartsText('Self.', Name) then
    Delete(Name, 1, 5);
  for Suffix in Suffixes do
    if EndsText(Suffix, Name) then
    begin
      SetLength(Name, Length(Name) - Length(Suffix));
      Break;
    end;
  if (Name = '') or (Pos('.', Name) > 0) or SameText(Name, 'Self') then
    Exit;
  ACall.DataSet := Name;
  ACall.Method := Match.Groups[2].Value;
  if SameText(ACall.Method, 'ParamByName') then
    ACall.Kind := TDataNameKind.Param
  else
    ACall.Kind := TDataNameKind.Field;
  ACall.ContentStart := Open;
  ACall.ContentEnd := Close - 1;
  ACall.Content := StringReplace(Copy(ALine, Open + 1, Close - Open - 1), '''''', '''', [rfReplaceAll]);
  Result := True;
end;

class function TDataFieldNames.SelectColumns(const ASql: string; out AStar: Boolean): TArray<string>;
var
  Tokens, Item: TSqlTokens;
  Index, Depth: Integer;
  Star: Boolean;
  Name: string;

  procedure Flush;
  begin
    Name := ColumnName(Item, Star);
    AStar := AStar or Star;
    if (Name <> '') and (IndexText(Name, Result) < 0) then
      Result := Result + [Name];
    Item := nil;
  end;

begin
  Result := nil;
  AStar := False;
  Tokens := Tokenize(ASql);
  Index := 0;
  while (Index <= High(Tokens)) and not Tokens[Index].IsWord('select') do
    Inc(Index);
  if Index > High(Tokens) then
    Exit;
  Inc(Index);
  // DISTINCT, ALL, TOP n, FIRST n, SKIP n
  while Index <= High(Tokens) do
    if Tokens[Index].IsWord('distinct') or Tokens[Index].IsWord('all') or Tokens[Index].IsWord('unique') then
      Inc(Index)
    else if (Tokens[Index].IsWord('top') or Tokens[Index].IsWord('first') or Tokens[Index].IsWord('skip')) and
      (Index < High(Tokens)) and (Tokens[Index + 1].Kind = TSqlTokenKind.Number) then
      Inc(Index, 2)
    else
      Break;
  Item := nil;
  Depth := 0;
  while Index <= High(Tokens) do
  begin
    if Depth = 0 then
      if Tokens[Index].IsWord('from') or Tokens[Index].IsWord('into') or Tokens[Index].IsSymbol(';') then
        Break
      else if Tokens[Index].IsSymbol(',') then
      begin
        Flush;
        Inc(Index);
        Continue;
      end;
    if Tokens[Index].IsSymbol('(') then
      Inc(Depth)
    else if Tokens[Index].IsSymbol(')') then
      Dec(Depth);
    Item := Item + [Tokens[Index]];
    Inc(Index);
  end;
  Flush;
end;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if (AObject.Kind <> TDfmObjectKind.Item) and SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := FindObject(Child, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function PropertyText(AObject: TDfmObject; const AName: string; out AText: string): Boolean;
var
  Prop: TDfmProperty;
begin
  AText := '';
  for Prop in AObject.Properties do
    if SameText(Prop.Name, AName) then
    begin
      if not TStringLiterals.PlainText(Prop.Value, AText) then
        AText := Trim(Prop.Value);
      Exit(True);
    end;
  Result := False;
end;

procedure Add(var ANames: TArray<TDataName>; const AName, ATypeName: string);
var
  Index: Integer;
  Item: TDataName;
begin
  if AName = '' then
    Exit;
  for Index := 0 to High(ANames) do
    if SameText(ANames[Index].Name, AName) then
    begin
      if ANames[Index].TypeName = '' then
        ANames[Index].TypeName := ATypeName;
      Exit;
    end;
  Item.Name := AName;
  Item.TypeName := ATypeName;
  ANames := ANames + [Item];
end;

/// <summary>TIntegerField → Integer, TWideStringField → WideString.</summary>
function FieldTypeName(const AClassName: string): string;
begin
  Result := AClassName;
  if StartsText('T', Result) then
    Delete(Result, 1, 1);
  if EndsText('Field', Result) then
    SetLength(Result, Length(Result) - 5);
end;

class function TDataFieldNames.FromForm(const AFormText, ADataSet: string; AKind: TDataNameKind; out ASql: string;
  out AFound: Boolean): TArray<TDataName>;
var
  Document: TDfmDocument;
  DataSet, Child: TDfmObject;
  Name, DataType, Dummy: string;
  Star: Boolean;
  Params: TArray<TDataName>;
  Param: TDataName;
begin
  Result := nil;
  ASql := '';
  AFound := False;
  Params := nil;
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root = nil then
      Exit;
    DataSet := FindObject(Document.Root, ADataSet);
    if DataSet = nil then
      Exit;
    AFound := True;
    ASql := TSqlText.FromForm(AFormText, ADataSet);
    for Child in DataSet.Children do
      if Child.Kind = TDfmObjectKind.Item then
      begin
        // Eintrag der Params-, Parameters- oder ParamData-Sammlung: Name und ParamType bzw. Direction.
        if PropertyText(Child, 'Name', Name) and (PropertyText(Child, 'ParamType', Dummy) or
          PropertyText(Child, 'Direction', Dummy)) then
        begin
          PropertyText(Child, 'DataType', DataType);
          if StartsText('ft', DataType) then
            Delete(DataType, 1, 2);
          if SameText(DataType, 'Unknown') then
            DataType := '';
          Add(Params, Name, DataType);
        end;
      end
      // Persistentes Feld: Kindobjekt mit FieldName.
      else if (AKind = TDataNameKind.Field) and PropertyText(Child, 'FieldName', Name) then
        Add(Result, Name, FieldTypeName(Child.TypeName));
  finally
    Document.Free;
  end;
  if AKind = TDataNameKind.Field then
  begin
    for Name in SelectColumns(ASql, Star) do
      Add(Result, Name, '');
  end
  else
  begin
    for Name in TSqlText.Params(ASql) do
      Add(Result, Name, '');
    for Param in Params do
      Add(Result, Param.Name, Param.TypeName);
  end;
end;

class function TDataFieldNames.ShortSql(const ASql: string; AMaxLength: Integer): string;
begin
  Result := Trim(TRegEx.Replace(ASql, '\s+', ' '));
  if Length(Result) > AMaxLength then
    Result := Copy(Result, 1, AMaxLength - 1) + '…';
end;

class function TDataFieldNames.Contains(const ANames: TArray<TDataName>; const AName: string): Boolean;
var
  Item: TDataName;
begin
  for Item in ANames do
    if SameText(Item.Name, AName) then
      Exit(True);
  Result := False;
end;

end.
