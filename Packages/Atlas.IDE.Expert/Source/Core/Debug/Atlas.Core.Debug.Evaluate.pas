unit Atlas.Core.Debug.Evaluate;

// Fenster „Auswerten“ (#784) ohne Fenster und ohne IDE:
//   - TAtlasEvalText zerlegt Ergebnis-Strings des Debuggers: strukturierte
//     Werte „(Name: 'Meier'; Anzahl: 3; Innen: (X: 1))“ bzw. Arrays
//     „(1, 2, 3)“ in Teile (Name und Wert, ohne Namen „[0]“, „[1]“ …),
//     Delphi-Stringliterale „'a'#13#10'b'“ in Text, dazu die Ansichten Text
//     (Steuerzeichen sichtbar), Zeilen (TStrings über „.Text“), JSON
//     (eingerückt) und Hex (Zahlen).
//   - TAtlasEvalNode/TAtlasEvalList: die Zeilen des Fensters als Baum. Jeder
//     Knoten hat einen Schlüssel (Pfad vom Ausdruck bis zum Feld), über den
//     TAtlasEvalList bei jedem Halt den Wert des vorigen Halts merkt und
//     geänderte Werte markiert. Kinder kommen aus den Feldern des Atlas-Index
//     (je Feld ein Ausdruck „Ausdruck.Feld“, einzeln ausgewertet) oder, ohne
//     Server, aus den Teilen des Ergebnis-Strings.
//   - FieldsOf liest die Felder aus atlas/expressionCompletion auf
//     „Ausdruck.“; ExpressionAt den Ausdruck unter dem Cursor (Strg+F7).
//   - Festgeheftete Ausdrücke (Strg+Enter) und der Verlauf (50 je Projekt)
//     liegen in TAtlasExpressionHistory (Atlas.Core.Debug.DialogCompletion).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

{$SCOPEDENUMS ON}

type
  TAtlasEvalPart = record
    Name: string;
    Value: string;
    /// <summary>Ohne Namen im Ergebnis (Array): Index ab 0.</summary>
    Indexed: Boolean;
  end;

  TAtlasEvalParts = TArray<TAtlasEvalPart>;

  TAtlasEvalView = (Text, Lines, Json, Hex);

  TAtlasEvalText = class
  public
    /// <summary>Wert in runden Klammern mit Teilen.</summary>
    class function IsStructured(const AValue: string): Boolean; static;
    /// <summary>Teile eines strukturierten Werts; leer, wenn AValue keiner ist.</summary>
    class function Parts(const AValue: string): TAtlasEvalParts; static;
    /// <summary>Delphi-Stringliteral (auch 'a'#13#10'b', #65) in Text; False, wenn AValue keins ist.</summary>
    class function TryDecodeString(const AValue: string; out AText: string): Boolean; static;
    /// <summary>Zahl, String, Boolean, nil oder Aufzählungswert: nichts aufzuklappen.</summary>
    class function IsSimple(const AValue: string): Boolean; static;
    /// <summary>Ausdruck für das Feld AField von AExpression; Klammern um zusammengesetzte Ausdrücke.</summary>
    class function FieldExpression(const AExpression, AField: string): string; static;
    /// <summary>AExpression mit der Formatangabe ",r": Der Debugger liefert Records dann mit Feldnamen
    /// ("(Id: 'a'; Order: 10)" statt "('a', 10)"). Unverändert, wenn der Ausdruck schon eine Formatangabe trägt
    /// (Komma auf oberster Ebene, etwa "X,h") oder leer ist.</summary>
    class function WithFieldNames(const AExpression: string): string; static;
    /// <summary>Ausdruck unter dem Cursor (Strg+F7): Bezeichner samt Punkten und ^ davor bis zum Wortende,
    /// „Kunde.Adresse.Ort“; ACharacter 0-basiert. '' ohne Bezeichner.</summary>
    class function ExpressionAt(const ALine: string; ACharacter: Integer): string; static;
    /// <summary>Feldnamen aus der Antwort von atlas/expressionCompletion auf „Ausdruck.“: Einträge der Art Feld
    /// (5), mit AWithProperties auch Eigenschaften (10, Getter können Code ausführen). Ohne Doppelte.</summary>
    class function FieldsOf(const AResponse: TJSONValue; AWithProperties: Boolean): TArray<string>; static;
    /// <summary>Text mit sichtbaren Steuerzeichen: ␍␊ samt Umbruch, → für Tab, Bildzeichen ␀…␟.</summary>
    class function VisibleText(const AText: string): string; static;
    /// <summary>Zeilen wie TStrings sie aus AText macht: ein Umbruch am Ende ergibt keine leere letzte Zeile.
    /// </summary>
    class function StringsLines(const AText: string): TArray<string>; static;
    /// <summary>JSON eingerückt (zwei Leerzeichen); False, wenn AText kein JSON ist.</summary>
    class function TryFormatJson(const AText: string; out AFormatted: string): Boolean; static;
    /// <summary>„$0000002A (42)“; False, wenn AValue keine ganze Zahl ist.</summary>
    class function TryHex(const AValue: string; out AHex: string): Boolean; static;
    /// <summary>Inhalt der Ansicht AView für AValue. Für Lines ist AValue der Wert von „.Text“. Passt die Ansicht
    /// nicht (kein JSON, keine Zahl), False und der Text.</summary>
    class function Render(const AValue: string; AView: TAtlasEvalView; out AText: string): Boolean; static;
  end;

  TAtlasEvalState = (Pending, Value, Error, Unavailable);

  TAtlasEvalNode = class
  private
    FParent: TAtlasEvalNode;
    FChildren: TObjectList<TAtlasEvalNode>;
    FName: string;
    FExpression: string;
    FKey: string;
    function GetChildCount: Integer;
    function GetChild(AIndex: Integer): TAtlasEvalNode;
  public
    Value: string;
    State: TAtlasEvalState;
    /// <summary>Seit dem letzten Halt geändert.</summary>
    Changed: Boolean;
    Expanded: Boolean;
    /// <summary>Kinder geholt (Felder bzw. Teile); bis dahin nur ein Platzhalter im Baum.</summary>
    ChildrenLoaded: Boolean;
    /// <summary>Kinder aus den Teilen des Ergebnis-Strings statt eigener Auswertung.</summary>
    FromParts: Boolean;
    /// <summary>Festgeheftet (Strg+Enter): bleibt über Halte und Sitzungen.</summary>
    Pinned: Boolean;
    constructor Create(AParent: TAtlasEvalNode; const AName, AExpression, AKey: string);
    destructor Destroy; override;
    procedure ClearChildren;
    function AddChild(const AName, AExpression: string): TAtlasEvalNode;
    /// <summary>Lässt sich aufklappen: Wert ausgewertet und nicht einfach.</summary>
    function CanExpand: Boolean;
    property Parent: TAtlasEvalNode read FParent;
    property Name: string read FName;
    /// <summary>'' bei Kindern aus Teilen: Wert steht schon fest.</summary>
    property Expression: string read FExpression;
    property Key: string read FKey;
    property ChildCount: Integer read GetChildCount;
    property Children[AIndex: Integer]: TAtlasEvalNode read GetChild;
  end;

  TAtlasEvalList = class
  private
    FRoots: TObjectList<TAtlasEvalNode>;
    FPrevious: TDictionary<string, string>;
    FCurrent: TDictionary<string, string>;
    procedure CollectPending(ANode: TAtlasEvalNode; AList: TList<TAtlasEvalNode>);
    procedure Restart(ANode: TAtlasEvalNode);
    function GetCount: Integer;
    function GetRoot(AIndex: Integer): TAtlasEvalNode;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Zeile mit AExpression (getrimmt) am Ende; nil bei leerem Ausdruck.</summary>
    function Add(const AExpression: string): TAtlasEvalNode;
    procedure Delete(AIndex: Integer);
    function IndexOf(ANode: TAtlasEvalNode): Integer;
    /// <summary>Neuer Halt: Werte dieses Halts werden die vorigen, alle Knoten mit Ausdruck sind wieder offen.
    /// Kinder aus Teilen fallen weg und entstehen mit dem neuen Wert des Elternknotens.</summary>
    procedure BeginStop;
    /// <summary>Kein angehaltener Prozess: alle Knoten Unavailable, die Werte bleiben für den Vergleich.</summary>
    procedure Unavailable;
    /// <summary>Ergebnis für ANode; markiert Changed gegenüber dem vorigen Halt. Ist der Knoten aufgeklappt
    /// und hat Teile statt Felder, entstehen die Kinder neu.</summary>
    procedure SetResult(ANode: TAtlasEvalNode; AOk: Boolean; const AText: string);
    /// <summary>Kinder aus Feldnamen (einzeln auszuwerten).</summary>
    procedure SetFields(ANode: TAtlasEvalNode; const AFields: TArray<string>);
    /// <summary>Kinder aus den Teilen des Werts (ohne Server); False, wenn der Wert keine hat.</summary>
    function SetParts(ANode: TAtlasEvalNode): Boolean;
    /// <summary>Offene Knoten in Anzeigereihenfolge: Wurzeln und Kinder aufgeklappter Knoten.</summary>
    function Pending: TArray<TAtlasEvalNode>;
    /// <summary>Knoten zum Schlüssel; nil, wenn es ihn nicht mehr gibt.</summary>
    function Find(const AKey: string): TAtlasEvalNode;
    /// <summary>Ausdrücke der festgehefteten Zeilen in Reihenfolge.</summary>
    function PinnedExpressions: TArray<string>;
    property Count: Integer read GetCount;
    property Roots[AIndex: Integer]: TAtlasEvalNode read GetRoot;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

const
  // Bildzeichen für Steuerzeichen: U+2400 + Code; Tab als Pfeil.
  ControlPictureBase = $2400;
  TabPicture = #$2192;

/// <summary>AText[AIndex] ist ein Anführungszeichen: Index (1-basiert) hinter dem schließenden ('' zählt als
/// Inhalt); 0, wenn der String nicht endet.</summary>
function SkipString(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '''' then
    begin
      if (Result < Length(AText)) and (AText[Result + 1] = '''') then
        Inc(Result, 2)
      else
        Exit(Result + 1);
    end
    else
      Inc(Result);
  end;
  Result := 0;
end;

/// <summary>Teile von AInner (ohne äußere Klammern) an ";" bzw. "," der obersten Ebene.</summary>
function SplitTop(const AInner: string): TArray<string>;
var
  Index, Depth, Start: Integer;
  C: Char;
begin
  Result := nil;
  Depth := 0;
  Start := 1;
  Index := 1;
  while Index <= Length(AInner) do
  begin
    C := AInner[Index];
    if C = '''' then
    begin
      Index := SkipString(AInner, Index);
      if Index = 0 then
        Break;
      Continue;
    end;
    if CharInSet(C, ['(', '[', '{']) then
      Inc(Depth)
    else if CharInSet(C, [')', ']', '}']) then
      Dec(Depth)
    else if (Depth = 0) and CharInSet(C, [';', ',']) then
    begin
      Result := Result + [Trim(Copy(AInner, Start, Index - Start))];
      Start := Index + 1;
    end;
    Inc(Index);
  end;
  if Trim(Copy(AInner, Start, MaxInt)) <> '' then
    Result := Result + [Trim(Copy(AInner, Start, MaxInt))];
end;

/// <summary>"Name: Wert" bzw. "Name = Wert" mit Bezeichner (auch qualifiziert) vorn.</summary>
function SplitNamed(const APart: string; out AName, AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  Index := 1;
  if (APart = '') or not TTextChars.IsIdentStart(APart[1]) then
    Exit;
  while (Index <= Length(APart)) and (TTextChars.IsIdentChar(APart[Index]) or (APart[Index] = '.')) do
    Inc(Index);
  AName := Copy(APart, 1, Index - 1);
  while (Index <= Length(APart)) and (APart[Index] = ' ') do
    Inc(Index);
  if (Index > Length(APart)) or not CharInSet(APart[Index], [':', '=']) then
    Exit;
  // ":=" ist keine Benennung.
  if (APart[Index] = ':') and (Index < Length(APart)) and (APart[Index + 1] = '=') then
    Exit;
  AValue := Trim(Copy(APart, Index + 1, MaxInt));
  Result := True;
end;

{ TAtlasEvalText }

class function TAtlasEvalText.IsStructured(const AValue: string): Boolean;
var
  Text: string;
  Index, Depth: Integer;
begin
  Text := Trim(AValue);
  Result := (Length(Text) >= 2) and (Text[1] = '(') and (Text[Length(Text)] = ')');
  if not Result then
    Exit;
  // Die erste Klammer muss die letzte schließen: "(1) + (2)" ist kein Wert.
  Depth := 0;
  Index := 1;
  while Index <= Length(Text) do
  begin
    if Text[Index] = '''' then
    begin
      Index := SkipString(Text, Index);
      if Index = 0 then
        Exit(False);
      Continue;
    end;
    if Text[Index] = '(' then
      Inc(Depth)
    else if Text[Index] = ')' then
    begin
      Dec(Depth);
      if (Depth = 0) and (Index < Length(Text)) then
        Exit(False);
    end;
    Inc(Index);
  end;
  Result := Depth = 0;
end;

class function TAtlasEvalText.Parts(const AValue: string): TAtlasEvalParts;
var
  Text, Name, Value: string;
  Items: TArray<string>;
  Index: Integer;
begin
  Result := nil;
  if not IsStructured(AValue) then
    Exit;
  Text := Trim(AValue);
  Items := SplitTop(Copy(Text, 2, Length(Text) - 2));
  SetLength(Result, Length(Items));
  for Index := 0 to High(Items) do
  begin
    Result[Index] := Default(TAtlasEvalPart);
    if SplitNamed(Items[Index], Name, Value) then
    begin
      Result[Index].Name := Name;
      Result[Index].Value := Value;
    end
    else
    begin
      Result[Index].Name := '[' + IntToStr(Index) + ']';
      Result[Index].Value := Items[Index];
      Result[Index].Indexed := True;
    end;
  end;
end;

class function TAtlasEvalText.TryDecodeString(const AValue: string; out AText: string): Boolean;
var
  Text: string;
  Index, Stop, Code: Integer;
  Digits: string;
begin
  AText := '';
  Text := Trim(AValue);
  Result := (Text <> '') and CharInSet(Text[1], ['''', '#']);
  if not Result then
    Exit;
  Index := 1;
  while Index <= Length(Text) do
  begin
    if Text[Index] = '''' then
    begin
      Stop := SkipString(Text, Index);
      if Stop = 0 then
        Exit(False);
      AText := AText + StringReplace(Copy(Text, Index + 1, Stop - Index - 2), '''''', '''', [rfReplaceAll]);
      Index := Stop;
    end
    else if Text[Index] = '#' then
    begin
      Inc(Index);
      Digits := '';
      if (Index <= Length(Text)) and (Text[Index] = '$') then
      begin
        Digits := '$';
        Inc(Index);
      end;
      while (Index <= Length(Text)) and (CharInSet(Text[Index], ['0'..'9']) or
        ((Digits <> '') and (Digits[1] = '$') and CharInSet(Text[Index], ['a'..'f', 'A'..'F']))) do
      begin
        Digits := Digits + Text[Index];
        Inc(Index);
      end;
      if not TryStrToInt(Digits, Code) or (Code < 0) or (Code > $FFFF) then
        Exit(False);
      AText := AText + Char(Code);
    end
    else
      Exit(False);
  end;
end;

class function TAtlasEvalText.IsSimple(const AValue: string): Boolean;
var
  Text, Decoded: string;
  Number: Double;
  Index: Integer;
begin
  Text := Trim(AValue);
  if (Text = '') or SameText(Text, 'nil') or SameText(Text, 'True') or SameText(Text, 'False') then
    Exit(True);
  if TryDecodeString(Text, Decoded) then
    Exit(True);
  if TryStrToFloat(Text, Number, TFormatSettings.Invariant) then
    Exit(True);
  // Aufzählungswert: ein Bezeichner.
  Result := TTextChars.IsIdentStart(Text[1]);
  for Index := 2 to Length(Text) do
    if not TTextChars.IsIdentChar(Text[Index]) then
      Exit(False);
end;

class function TAtlasEvalText.WithFieldNames(const AExpression: string): string;
begin
  Result := Trim(AExpression);
  if (Result = '') or (Length(SplitTop(Result)) > 1) then
    Exit(AExpression);
  Result := Result + ',r';
end;

class function TAtlasEvalText.FieldExpression(const AExpression, AField: string): string;
var
  Index: Integer;
  Simple: Boolean;
begin
  // Bezeichner, Punkte, Indizes und ^ bleiben ohne Klammern: Kunde.Adresse.Ort, Liste[0].Name, P^.X.
  Simple := AExpression <> '';
  for Index := 1 to Length(AExpression) do
    if not (TTextChars.IsIdentChar(AExpression[Index]) or CharInSet(AExpression[Index], ['.', '[', ']', '^'])) then
    begin
      Simple := False;
      Break;
    end;
  if Simple then
    Result := AExpression + '.' + AField
  else
    Result := '(' + AExpression + ').' + AField;
end;

class function TAtlasEvalText.ExpressionAt(const ALine: string; ACharacter: Integer): string;
var
  First, Last: Integer;
begin
  Result := '';
  // 1-basiert: Zeichen rechts vom Cursor; steht er hinter dem Wort, zählt das Wort davor.
  Last := ACharacter + 1;
  if (Last > Length(ALine)) or not TTextChars.IsIdentChar(ALine[Last]) then
    Dec(Last);
  if (Last < 1) or (Last > Length(ALine)) or not TTextChars.IsIdentChar(ALine[Last]) then
    Exit;
  while (Last < Length(ALine)) and TTextChars.IsIdentChar(ALine[Last + 1]) do
    Inc(Last);
  First := Last;
  while (First > 1) and (TTextChars.IsIdentChar(ALine[First - 1]) or CharInSet(ALine[First - 1], ['.', '^'])) do
    Dec(First);
  // Vorn nur ein Bezeichner: „.Name“ oder „^P“ gehören nicht dazu, Zahlen auch nicht.
  while (First <= Last) and not TTextChars.IsIdentStart(ALine[First]) do
    Inc(First);
  Result := Copy(ALine, First, Last - First + 1);
end;

class function TAtlasEvalText.FieldsOf(const AResponse: TJSONValue; AWithProperties: Boolean): TArray<string>;
const
  FieldKind = 5;
  PropertyKind = 10;
var
  Items: TJSONArray;
  Item: TJSONValue;
  Name: string;
  Kind: Integer;
begin
  Result := nil;
  if not (AResponse is TJSONObject) or not (TJSONObject(AResponse).GetValue('items') is TJSONArray) then
    Exit;
  Items := TJSONArray(TJSONObject(AResponse).GetValue('items'));
  for Item in Items do
  begin
    if not (Item is TJSONObject) or not (TJSONObject(Item).GetValue('kind') is TJSONNumber) then
      Continue;
    Kind := TJSONNumber(TJSONObject(Item).GetValue('kind')).AsInt;
    if (Kind <> FieldKind) and not (AWithProperties and (Kind = PropertyKind)) then
      Continue;
    if not TJSONObject(Item).TryGetValue<string>('label', Name) then
      Continue;
    Name := Trim(Name);
    if (Name <> '') and (IndexText(Name, Result) < 0) then
      Result := Result + [Name];
  end;
end;

class function TAtlasEvalText.VisibleText(const AText: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  C: Char;
begin
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      C := AText[Index];
      if (C = #13) and (Index < Length(AText)) and (AText[Index + 1] = #10) then
      begin
        Builder.Append(Char(ControlPictureBase + 13)).Append(Char(ControlPictureBase + 10)).Append(sLineBreak);
        Inc(Index, 2);
        Continue;
      end;
      if CharInSet(C, [#10, #13]) then
        Builder.Append(Char(ControlPictureBase + Ord(C))).Append(sLineBreak)
      else if C = #9 then
        Builder.Append(TabPicture)
      else if Ord(C) < 32 then
        Builder.Append(Char(ControlPictureBase + Ord(C)))
      else
        Builder.Append(C);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasEvalText.StringsLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
  // TStrings: Ein Umbruch am Ende ergibt keine leere letzte Zeile, leerer Text keine Zeile.
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
    SetLength(Result, Length(Result) - 1);
end;

class function TAtlasEvalText.TryFormatJson(const AText: string; out AFormatted: string): Boolean;
var
  Value: TJSONValue;
  Builder: TStringBuilder;
  Index, Depth: Integer;
  C: Char;
  InString: Boolean;
  Source: string;

  procedure NewLine;
  begin
    Builder.Append(sLineBreak).Append(StringOfChar(' ', Depth * 2));
  end;

begin
  AFormatted := '';
  Source := Trim(AText);
  Value := TJSONObject.ParseJSONValue(Source);
  try
    Result := (Value is TJSONObject) or (Value is TJSONArray);
  finally
    Value.Free;
  end;
  if not Result then
    Exit;
  Builder := TStringBuilder.Create;
  try
    Depth := 0;
    InString := False;
    Index := 1;
    while Index <= Length(Source) do
    begin
      C := Source[Index];
      if InString then
      begin
        Builder.Append(C);
        if C = '\' then
        begin
          Inc(Index);
          if Index <= Length(Source) then
            Builder.Append(Source[Index]);
        end
        else if C = '"' then
          InString := False;
      end
      else
        case C of
          '"':
            begin
              InString := True;
              Builder.Append(C);
            end;
          '{', '[':
            begin
              Builder.Append(C);
              Inc(Depth);
              NewLine;
            end;
          '}', ']':
            begin
              Dec(Depth);
              NewLine;
              Builder.Append(C);
            end;
          ',':
            begin
              Builder.Append(C);
              NewLine;
            end;
          ':':
            Builder.Append(': ');
          ' ', #9, #10, #13:
            ;
        else
          Builder.Append(C);
        end;
      Inc(Index);
    end;
    AFormatted := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasEvalText.TryHex(const AValue: string; out AHex: string): Boolean;
var
  Number: Int64;
begin
  AHex := '';
  Result := TryStrToInt64(Trim(AValue), Number);
  if not Result then
    Exit;
  if (Number >= Low(Integer)) and (Number <= High(Integer)) then
    AHex := '$' + IntToHex(Integer(Number), 8)
  else
    AHex := '$' + IntToHex(Number, 16);
  AHex := AHex + ' (' + IntToStr(Number) + ')';
end;

class function TAtlasEvalText.Render(const AValue: string; AView: TAtlasEvalView; out AText: string): Boolean;
var
  Decoded: string;
begin
  if not TryDecodeString(AValue, Decoded) then
    Decoded := AValue;
  Result := True;
  case AView of
    TAtlasEvalView.Lines:
      AText := string.Join(sLineBreak, StringsLines(Decoded));
    TAtlasEvalView.Json:
      Result := TryFormatJson(Decoded, AText);
    TAtlasEvalView.Hex:
      Result := TryHex(AValue, AText);
  else
    AText := VisibleText(Decoded);
  end;
  if not Result then
    AText := VisibleText(Decoded);
end;

{ TAtlasEvalNode }

constructor TAtlasEvalNode.Create(AParent: TAtlasEvalNode; const AName, AExpression, AKey: string);
begin
  inherited Create;
  FParent := AParent;
  FName := AName;
  FExpression := AExpression;
  FKey := AKey;
  FChildren := TObjectList<TAtlasEvalNode>.Create(True);
end;

destructor TAtlasEvalNode.Destroy;
begin
  FChildren.Free;
  inherited;
end;

function TAtlasEvalNode.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

function TAtlasEvalNode.GetChild(AIndex: Integer): TAtlasEvalNode;
begin
  Result := FChildren[AIndex];
end;

procedure TAtlasEvalNode.ClearChildren;
begin
  FChildren.Clear;
  ChildrenLoaded := False;
  FromParts := False;
end;

function TAtlasEvalNode.AddChild(const AName, AExpression: string): TAtlasEvalNode;
begin
  Result := TAtlasEvalNode.Create(Self, AName, AExpression, FKey + #1 + AName);
  FChildren.Add(Result);
end;

function TAtlasEvalNode.CanExpand: Boolean;
begin
  Result := (State = TAtlasEvalState.Value) and not TAtlasEvalText.IsSimple(Value);
end;

{ TAtlasEvalList }

constructor TAtlasEvalList.Create;
begin
  inherited Create;
  FRoots := TObjectList<TAtlasEvalNode>.Create(True);
  FPrevious := TDictionary<string, string>.Create;
  FCurrent := TDictionary<string, string>.Create;
end;

destructor TAtlasEvalList.Destroy;
begin
  FCurrent.Free;
  FPrevious.Free;
  FRoots.Free;
  inherited;
end;

function TAtlasEvalList.GetCount: Integer;
begin
  Result := FRoots.Count;
end;

function TAtlasEvalList.GetRoot(AIndex: Integer): TAtlasEvalNode;
begin
  Result := FRoots[AIndex];
end;

function TAtlasEvalList.Add(const AExpression: string): TAtlasEvalNode;
var
  Expression: string;
  Index, Number: Integer;
  Key: string;
begin
  Result := nil;
  Expression := Trim(AExpression);
  if Expression = '' then
    Exit;
  // Gleicher Ausdruck zweimal: eigener Schlüssel, damit die Markierung je Zeile gilt.
  Key := Expression;
  Number := 1;
  Index := 0;
  while Index < FRoots.Count do
  begin
    if FRoots[Index].Key = Key then
    begin
      Inc(Number);
      Key := Expression + #2 + IntToStr(Number);
      Index := 0;
      Continue;
    end;
    Inc(Index);
  end;
  Result := TAtlasEvalNode.Create(nil, Expression, Expression, Key);
  FRoots.Add(Result);
end;

procedure TAtlasEvalList.Delete(AIndex: Integer);
begin
  FRoots.Delete(AIndex);
end;

function TAtlasEvalList.IndexOf(ANode: TAtlasEvalNode): Integer;
begin
  Result := FRoots.IndexOf(ANode);
end;

procedure TAtlasEvalList.Restart(ANode: TAtlasEvalNode);
var
  Index: Integer;
begin
  if ANode.FromParts then
  begin
    // Teile entstehen aus dem neuen Wert des Elternknotens neu; aufgeklappt bleibt er.
    ANode.ClearChildren;
  end;
  if ANode.Expression <> '' then
  begin
    ANode.State := TAtlasEvalState.Pending;
    ANode.Changed := False;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    Restart(ANode.Children[Index]);
end;

procedure TAtlasEvalList.BeginStop;
var
  Pair: TPair<string, string>;
  Index: Integer;
begin
  // Was in diesem Halt nicht ausgewertet wurde, behält den Stand des Halts davor.
  for Pair in FCurrent do
    FPrevious.AddOrSetValue(Pair.Key, Pair.Value);
  FCurrent.Clear;
  for Index := 0 to FRoots.Count - 1 do
    Restart(FRoots[Index]);
end;

procedure TAtlasEvalList.Unavailable;

  procedure Mark(ANode: TAtlasEvalNode);
  var
    Index: Integer;
  begin
    ANode.State := TAtlasEvalState.Unavailable;
    ANode.Changed := False;
    for Index := 0 to ANode.ChildCount - 1 do
      Mark(ANode.Children[Index]);
  end;

var
  Index: Integer;
begin
  for Index := 0 to FRoots.Count - 1 do
    Mark(FRoots[Index]);
end;

procedure TAtlasEvalList.SetResult(ANode: TAtlasEvalNode; AOk: Boolean; const AText: string);
var
  Previous: string;
begin
  ANode.Value := AText;
  if AOk then
    ANode.State := TAtlasEvalState.Value
  else
    ANode.State := TAtlasEvalState.Error;
  ANode.Changed := AOk and FPrevious.TryGetValue(ANode.Key, Previous) and (Previous <> AText);
  if AOk then
    FCurrent.AddOrSetValue(ANode.Key, AText);
  // Aufgeklappt ohne Felder: Teile aus dem neuen Wert.
  if ANode.Expanded and not ANode.ChildrenLoaded and AOk then
    SetParts(ANode);
end;

procedure TAtlasEvalList.SetFields(ANode: TAtlasEvalNode; const AFields: TArray<string>);
var
  Field: string;
begin
  ANode.ClearChildren;
  for Field in AFields do
    ANode.AddChild(Field, TAtlasEvalText.FieldExpression(ANode.Expression, Field)).State :=
      TAtlasEvalState.Pending;
  ANode.ChildrenLoaded := True;
end;

function TAtlasEvalList.SetParts(ANode: TAtlasEvalNode): Boolean;
var
  Parts: TAtlasEvalParts;
  Part: TAtlasEvalPart;
  Child: TAtlasEvalNode;
begin
  Parts := TAtlasEvalText.Parts(ANode.Value);
  Result := Length(Parts) > 0;
  if not Result then
    Exit;
  ANode.ClearChildren;
  for Part in Parts do
  begin
    Child := ANode.AddChild(Part.Name, '');
    SetResult(Child, True, Part.Value);
  end;
  ANode.ChildrenLoaded := True;
  ANode.FromParts := True;
end;

procedure TAtlasEvalList.CollectPending(ANode: TAtlasEvalNode; AList: TList<TAtlasEvalNode>);
var
  Index: Integer;
begin
  if (ANode.Expression <> '') and (ANode.State = TAtlasEvalState.Pending) then
    AList.Add(ANode);
  if ANode.Expanded then
    for Index := 0 to ANode.ChildCount - 1 do
      CollectPending(ANode.Children[Index], AList);
end;

function TAtlasEvalList.Pending: TArray<TAtlasEvalNode>;
var
  List: TList<TAtlasEvalNode>;
  Index: Integer;
begin
  List := TList<TAtlasEvalNode>.Create;
  try
    for Index := 0 to FRoots.Count - 1 do
      CollectPending(FRoots[Index], List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TAtlasEvalList.Find(const AKey: string): TAtlasEvalNode;

  function Search(ANode: TAtlasEvalNode): TAtlasEvalNode;
  var
    Index: Integer;
  begin
    if ANode.Key = AKey then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Result := Search(ANode.Children[Index]);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
  end;

var
  Index: Integer;
begin
  for Index := 0 to FRoots.Count - 1 do
  begin
    Result := Search(FRoots[Index]);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function TAtlasEvalList.PinnedExpressions: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to FRoots.Count - 1 do
    if FRoots[Index].Pinned then
      Result := Result + [FRoots[Index].Expression];
end;

end.
