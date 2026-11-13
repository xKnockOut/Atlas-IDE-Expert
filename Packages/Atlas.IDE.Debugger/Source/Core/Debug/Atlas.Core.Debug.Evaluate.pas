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
    /// <summary>Wurzeln auf AExpressions bringen, in deren Reihenfolge und ohne Doppelte: gleiche Ausdrücke behalten
    /// ihren Knoten samt Wert und Aufklappzustand, übrige fallen weg, neue kommen offen dazu. Für Listen, die Atlas
    /// selbst füllt (Fenster „Variablen“, #853).</summary>
    procedure Replace(const AExpressions: TArray<string>);
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

  /// <summary>Was die Ansicht unten zeigt: gewählter Knoten, sein Zustand und Wert, Ansicht und Wert von „.Text“.
  /// Gleich wie beim letzten Mal: nichts neu berechnen. Der Frame gleicht nach jeder Zeitscheibe der Auswertung
  /// ab; JSON formatieren und den Text des Memos lesen kostet bei langen Werten sonst jedes Mal.</summary>
  TAtlasEvalDetailInput = record
    Valid: Boolean;
    Key: string;
    State: TAtlasEvalState;
    Value: string;
    View: TAtlasEvalView;
    LinesOk: Boolean;
    Lines: string;
    /// <summary>Eingabe für ANode (nil: keine Auswahl).</summary>
    class function ForNode(ANode: TAtlasEvalNode; AView: TAtlasEvalView; ALinesOk: Boolean;
      const ALines: string): TAtlasEvalDetailInput; static;
    function Same(const AOther: TAtlasEvalDetailInput): Boolean;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

const
  // Bildzeichen für Steuerzeichen: U+2400 + Code; Tab als Pfeil.
  cControlPictureBase = $2400;
  cTabPicture = #$2192;

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
      begin
        Inc(Result, 2);
      end
      else
      begin
        Exit(Result + 1);
      end;
    end
    else
    begin
      Inc(Result);
    end;
  end;
  Result := 0;
end;

/// <summary>Teile von AInner (ohne äußere Klammern) an ";" bzw. "," der obersten Ebene.</summary>
function SplitTop(const AInner: string): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  C: Char;
begin
  Result := nil;
  mDepth := 0;
  mStart := 1;
  mIndex := 1;
  while mIndex <= Length(AInner) do
  begin
    C := AInner[mIndex];
    if C = '''' then
    begin
      mIndex := SkipString(AInner, mIndex);
      if mIndex = 0 then
      begin
        Break;
      end;
      Continue;
    end;
    if CharInSet(C, ['(', '[', '{']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(C, [')', ']', '}']) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and CharInSet(C, [';', ',']) then
    begin
      Result := Result + [Trim(Copy(AInner, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end;
    Inc(mIndex);
  end;
  if Trim(Copy(AInner, mStart, MaxInt)) <> '' then
  begin
    Result := Result + [Trim(Copy(AInner, mStart, MaxInt))];
  end;
end;

/// <summary>"Name: Wert" bzw. "Name = Wert" mit Bezeichner (auch qualifiziert) vorn.</summary>
function SplitNamed(const APart: string; out AName, AValue: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := 1;
  if (APart = '') or not TTextChars.IsIdentStart(APart[1]) then
  begin
    Exit;
  end;
  while (mIndex <= Length(APart)) and (TTextChars.IsIdentChar(APart[mIndex]) or (APart[mIndex] = '.')) do
  begin
    Inc(mIndex);
  end;
  AName := Copy(APart, 1, mIndex - 1);
  while (mIndex <= Length(APart)) and (APart[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  if (mIndex > Length(APart)) or not CharInSet(APart[mIndex], [':', '=']) then
  begin
    Exit;
  end;
  // ":=" ist keine Benennung.
  if (APart[mIndex] = ':') and (mIndex < Length(APart)) and (APart[mIndex + 1] = '=') then
  begin
    Exit;
  end;
  AValue := Trim(Copy(APart, mIndex + 1, MaxInt));
  Result := True;
end;

{ TAtlasEvalText }

class function TAtlasEvalText.IsStructured(const AValue: string): Boolean;
var
  mText: string;
  mIndex, mDepth: Integer;
begin
  mText := Trim(AValue);
  Result := (Length(mText) >= 2) and (mText[1] = '(') and (mText[Length(mText)] = ')');
  if not Result then
  begin
    Exit;
  end;
  // Die erste Klammer muss die letzte schließen: "(1) + (2)" ist kein Wert.
  mDepth := 0;
  mIndex := 1;
  while mIndex <= Length(mText) do
  begin
    if mText[mIndex] = '''' then
    begin
      mIndex := SkipString(mText, mIndex);
      if mIndex = 0 then
      begin
        Exit(False);
      end;
      Continue;
    end;
    if mText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if mText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if (mDepth = 0) and (mIndex < Length(mText)) then
      begin
        Exit(False);
      end;
    end;
    Inc(mIndex);
  end;
  Result := mDepth = 0;
end;

class function TAtlasEvalText.Parts(const AValue: string): TAtlasEvalParts;
var
  mText, mName, mValue: string;
  mItems: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  if not IsStructured(AValue) then
  begin
    Exit;
  end;
  mText := Trim(AValue);
  mItems := SplitTop(Copy(mText, 2, Length(mText) - 2));
  SetLength(Result, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    Result[mIndex] := Default(TAtlasEvalPart);
    if SplitNamed(mItems[mIndex], mName, mValue) then
    begin
      Result[mIndex].Name := mName;
      Result[mIndex].Value := mValue;
    end
    else
    begin
      Result[mIndex].Name := '[' + IntToStr(mIndex) + ']';
      Result[mIndex].Value := mItems[mIndex];
      Result[mIndex].Indexed := True;
    end;
  end;
end;

/// <summary>Zeichen „#65“ bzw. „#$41“ ab AIndex (auf „#“); AIndex steht danach hinter den
/// Ziffern.</summary>
function DecodeCharCode(const AText: string; var AIndex: Integer; out AChar: Char): Boolean;
var
  mDigits: string;
  mCode: Integer;
begin
  AChar := #0;
  Inc(AIndex);
  mDigits := '';
  if (AIndex <= Length(AText)) and (AText[AIndex] = '$') then
  begin
    mDigits := '$';
    Inc(AIndex);
  end;
  while (AIndex <= Length(AText)) and (CharInSet(AText[AIndex], ['0'..'9']) or
    ((mDigits <> '') and (mDigits[1] = '$') and CharInSet(AText[AIndex], ['a'..'f', 'A'..'F']))) do
  begin
    mDigits := mDigits + AText[AIndex];
    Inc(AIndex);
  end;
  Result := TryStrToInt(mDigits, mCode) and (mCode >= 0) and (mCode <= $FFFF);
  if Result then
  begin
    AChar := Char(mCode);
  end;
end;

class function TAtlasEvalText.TryDecodeString(const AValue: string; out AText: string): Boolean;
var
  mText: string;
  mIndex, mStop: Integer;
  mCode: Char;
begin
  AText := '';
  mText := Trim(AValue);
  Result := (mText <> '') and CharInSet(mText[1], ['''', '#']);
  mIndex := 1;
  while Result and (mIndex <= Length(mText)) do
  begin
    if mText[mIndex] = '''' then
    begin
      mStop := SkipString(mText, mIndex);
      Result := mStop <> 0;
      if Result then
      begin
        AText := AText + StringReplace(Copy(mText, mIndex + 1, mStop - mIndex - 2), '''''', '''', [rfReplaceAll]);
        mIndex := mStop;
      end;
    end
    else if mText[mIndex] = '#' then
    begin
      Result := DecodeCharCode(mText, mIndex, mCode);
      if Result then
      begin
        AText := AText + mCode;
      end;
    end
    else
    begin
      Result := False;
    end;
  end;
end;

class function TAtlasEvalText.IsSimple(const AValue: string): Boolean;
var
  mText, mDecoded: string;
  mNumber: Double;
  mIndex: Integer;
begin
  mText := Trim(AValue);
  if (mText = '') or SameText(mText, 'nil') or SameText(mText, 'True') or SameText(mText, 'False') then
  begin
    Exit(True);
  end;
  if TryDecodeString(mText, mDecoded) then
  begin
    Exit(True);
  end;
  if TryStrToFloat(mText, mNumber, TFormatSettings.Invariant) then
  begin
    Exit(True);
  end;
  // Aufzählungswert: ein Bezeichner.
  Result := TTextChars.IsIdentStart(mText[1]);
  for mIndex := 2 to Length(mText) do
  begin
    if not TTextChars.IsIdentChar(mText[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasEvalText.WithFieldNames(const AExpression: string): string;
begin
  Result := Trim(AExpression);
  if (Result = '') or (Length(SplitTop(Result)) > 1) then
  begin
    Exit(AExpression);
  end;
  Result := Result + ',r';
end;

class function TAtlasEvalText.FieldExpression(const AExpression, AField: string): string;
var
  mIndex: Integer;
  mSimple: Boolean;
begin
  // Bezeichner, Punkte, Indizes und ^ bleiben ohne Klammern: Kunde.Adresse.Ort, Liste[0].Name, P^.X.
  mSimple := AExpression <> '';
  for mIndex := 1 to Length(AExpression) do
  begin
    if not (TTextChars.IsIdentChar(AExpression[mIndex]) or CharInSet(AExpression[mIndex], ['.', '[', ']', '^'])) then
    begin
      mSimple := False;
      Break;
    end;
  end;
  if mSimple then
  begin
    Result := AExpression + '.' + AField;
  end
  else
  begin
    Result := '(' + AExpression + ').' + AField;
  end;
end;

class function TAtlasEvalText.ExpressionAt(const ALine: string; ACharacter: Integer): string;
var
  mFirst, mLast: Integer;
begin
  Result := '';
  // 1-basiert: Zeichen rechts vom Cursor; steht er hinter dem Wort, zählt das Wort davor.
  mLast := ACharacter + 1;
  if (mLast > Length(ALine)) or not TTextChars.IsIdentChar(ALine[mLast]) then
  begin
    Dec(mLast);
  end;
  if (mLast < 1) or (mLast > Length(ALine)) or not TTextChars.IsIdentChar(ALine[mLast]) then
  begin
    Exit;
  end;
  while (mLast < Length(ALine)) and TTextChars.IsIdentChar(ALine[mLast + 1]) do
  begin
    Inc(mLast);
  end;
  mFirst := mLast;
  while (mFirst > 1) and (TTextChars.IsIdentChar(ALine[mFirst - 1]) or CharInSet(ALine[mFirst - 1], ['.', '^'])) do
  begin
    Dec(mFirst);
  end;
  // Vorn nur ein Bezeichner: „.Name“ oder „^P“ gehören nicht dazu, Zahlen auch nicht.
  while (mFirst <= mLast) and not TTextChars.IsIdentStart(ALine[mFirst]) do
  begin
    Inc(mFirst);
  end;
  Result := Copy(ALine, mFirst, mLast - mFirst + 1);
end;

class function TAtlasEvalText.FieldsOf(const AResponse: TJSONValue; AWithProperties: Boolean): TArray<string>;
const
  cFieldKind = 5;
  cPropertyKind = 10;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mName: string;
  mKind: Integer;
begin
  Result := nil;
  if not (AResponse is TJSONObject) or not (TJSONObject(AResponse).GetValue('items') is TJSONArray) then
  begin
    Exit;
  end;
  mItems := TJSONArray(TJSONObject(AResponse).GetValue('items'));
  for mItem in mItems do
  begin
    if not (mItem is TJSONObject) or not (TJSONObject(mItem).GetValue('kind') is TJSONNumber) then
    begin
      Continue;
    end;
    mKind := TJSONNumber(TJSONObject(mItem).GetValue('kind')).AsInt;
    if (mKind <> cFieldKind) and not (AWithProperties and (mKind = cPropertyKind)) then
    begin
      Continue;
    end;
    if not TJSONObject(mItem).TryGetValue<string>('label', mName) then
    begin
      Continue;
    end;
    mName := Trim(mName);
    if (mName <> '') and (IndexText(mName, Result) < 0) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TAtlasEvalText.VisibleText(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  C: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      C := AText[mIndex];
      if (C = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
      begin
        mBuilder.Append(Char(cControlPictureBase + 13)).Append(Char(cControlPictureBase + 10)).Append(sLineBreak);
        Inc(mIndex, 2);
        Continue;
      end;
      if CharInSet(C, [#10, #13]) then
      begin
        mBuilder.Append(Char(cControlPictureBase + Ord(C))).Append(sLineBreak);
      end
      else if C = #9 then
      begin
        mBuilder.Append(cTabPicture);
      end
      else if Ord(C) < 32 then
      begin
        mBuilder.Append(Char(cControlPictureBase + Ord(C)));
      end
      else
      begin
        mBuilder.Append(C);
      end;
      Inc(mIndex);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasEvalText.StringsLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
  // TStrings: Ein Umbruch am Ende ergibt keine leere letzte Zeile, leerer Text keine Zeile.
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

procedure AppendJsonLine(ABuilder: TStringBuilder; ADepth: Integer);
begin
  ABuilder.Append(sLineBreak).Append(StringOfChar(' ', ADepth * 2));
end;

/// <summary>Zeichenkette ab AIndex (auf dem öffnenden „"“) bis zum schließenden übernehmen; AIndex steht danach
/// auf dem schließenden.</summary>
procedure AppendJsonString(ABuilder: TStringBuilder; const ASource: string; var AIndex: Integer);
begin
  ABuilder.Append(ASource[AIndex]);
  Inc(AIndex);
  while AIndex <= Length(ASource) do
  begin
    ABuilder.Append(ASource[AIndex]);
    if ASource[AIndex] = '"' then
    begin
      Exit;
    end;
    if (ASource[AIndex] = '\') and (AIndex < Length(ASource)) then
    begin
      Inc(AIndex);
      ABuilder.Append(ASource[AIndex]);
    end;
    Inc(AIndex);
  end;
end;

function IsJsonContainer(const ASource: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(ASource);
  try
    Result := (mValue is TJSONObject) or (mValue is TJSONArray);
  finally
    mValue.Free;
  end;
end;

class function TAtlasEvalText.TryFormatJson(const AText: string; out AFormatted: string): Boolean;
var
  mBuilder: TStringBuilder;
  mIndex, mDepth: Integer;
  mSource: string;
begin
  AFormatted := '';
  mSource := Trim(AText);
  Result := IsJsonContainer(mSource);
  if not Result then
  begin
    Exit;
  end;
  mBuilder := TStringBuilder.Create;
  try
    mDepth := 0;
    mIndex := 1;
    while mIndex <= Length(mSource) do
    begin
      case mSource[mIndex] of
        '"':
          AppendJsonString(mBuilder, mSource, mIndex);
        '{', '[':
          begin
            mBuilder.Append(mSource[mIndex]);
            Inc(mDepth);
            AppendJsonLine(mBuilder, mDepth);
          end;
        '}', ']':
          begin
            Dec(mDepth);
            AppendJsonLine(mBuilder, mDepth);
            mBuilder.Append(mSource[mIndex]);
          end;
        ',':
          begin
            mBuilder.Append(',');
            AppendJsonLine(mBuilder, mDepth);
          end;
        ':':
          mBuilder.Append(': ');
        ' ', #9, #10, #13:
          ;
      else
        mBuilder.Append(mSource[mIndex]);
      end;
      Inc(mIndex);
    end;
    AFormatted := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasEvalText.TryHex(const AValue: string; out AHex: string): Boolean;
var
  mNumber: Int64;
begin
  AHex := '';
  Result := TryStrToInt64(Trim(AValue), mNumber);
  if not Result then
  begin
    Exit;
  end;
  if (mNumber >= Low(Integer)) and (mNumber <= High(Integer)) then
  begin
    AHex := '$' + IntToHex(Integer(mNumber), 8);
  end
  else
  begin
    AHex := '$' + IntToHex(mNumber, 16);
  end;
  AHex := AHex + ' (' + IntToStr(mNumber) + ')';
end;

class function TAtlasEvalText.Render(const AValue: string; AView: TAtlasEvalView; out AText: string): Boolean;
var
  mDecoded: string;
begin
  if not TryDecodeString(AValue, mDecoded) then
  begin
    mDecoded := AValue;
  end;
  Result := True;
  case AView of
    TAtlasEvalView.Lines:
      AText := string.Join(sLineBreak, StringsLines(mDecoded));
    TAtlasEvalView.Json:
      Result := TryFormatJson(mDecoded, AText);
    TAtlasEvalView.Hex:
      Result := TryHex(AValue, AText);
  else
    AText := VisibleText(mDecoded);
  end;
  if not Result then
  begin
    AText := VisibleText(mDecoded);
  end;
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
  mExpression: string;
  mIndex, mNumber: Integer;
  mKey: string;
begin
  Result := nil;
  mExpression := Trim(AExpression);
  if mExpression = '' then
  begin
    Exit;
  end;
  // Gleicher Ausdruck zweimal: eigener Schlüssel, damit die Markierung je Zeile gilt.
  mKey := mExpression;
  mNumber := 1;
  mIndex := 0;
  while mIndex < FRoots.Count do
  begin
    if FRoots[mIndex].Key = mKey then
    begin
      Inc(mNumber);
      mKey := mExpression + #2 + IntToStr(mNumber);
      mIndex := 0;
      Continue;
    end;
    Inc(mIndex);
  end;
  Result := TAtlasEvalNode.Create(nil, mExpression, mExpression, mKey);
  FRoots.Add(Result);
end;

procedure TAtlasEvalList.Delete(AIndex: Integer);
begin
  FRoots.Delete(AIndex);
end;

procedure TAtlasEvalList.Replace(const AExpressions: TArray<string>);
var
  mOld: TDictionary<string, TAtlasEvalNode>;
  mPrevious: TArray<TAtlasEvalNode>;
  mNode: TAtlasEvalNode;
  mExpression: string;
begin
  mOld := TDictionary<string, TAtlasEvalNode>.Create;
  try
    // Bisherige Wurzeln lösen, ohne sie freizugeben; Schlüssel ist der Ausdruck.
    mPrevious := FRoots.ToArray;
    FRoots.OwnsObjects := False;
    try
      FRoots.Clear;
    finally
      FRoots.OwnsObjects := True;
    end;
    for mNode in mPrevious do
    begin
      if mOld.ContainsKey(mNode.Key) then
      begin
        mNode.Free;
      end
      else
      begin
        mOld.Add(mNode.Key, mNode);
      end;
    end;
    for mExpression in AExpressions do
    begin
      if (Trim(mExpression) = '') or (Find(Trim(mExpression)) <> nil) then
      begin
        Continue;
      end;
      if mOld.TryGetValue(Trim(mExpression), mNode) then
      begin
        mOld.Remove(mNode.Key);
        FRoots.Add(mNode);
      end
      else
      begin
        Add(mExpression);
      end;
    end;
  finally
    for mNode in mOld.Values do
    begin
      mNode.Free;
    end;
    mOld.Free;
  end;
end;

function TAtlasEvalList.IndexOf(ANode: TAtlasEvalNode): Integer;
begin
  Result := FRoots.IndexOf(ANode);
end;

procedure TAtlasEvalList.Restart(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
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
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Restart(ANode.Children[mIndex]);
  end;
end;

procedure TAtlasEvalList.BeginStop;
var
  mPair: TPair<string, string>;
  mIndex: Integer;
begin
  // Was in diesem Halt nicht ausgewertet wurde, behält den Stand des Halts davor.
  for mPair in FCurrent do
  begin
    FPrevious.AddOrSetValue(mPair.Key, mPair.Value);
  end;
  FCurrent.Clear;
  for mIndex := 0 to FRoots.Count - 1 do
  begin
    Restart(FRoots[mIndex]);
  end;
end;

procedure TAtlasEvalList.Unavailable;

  procedure Mark(ANode: TAtlasEvalNode);
  var
    mIndex: Integer;
  begin
    ANode.State := TAtlasEvalState.Unavailable;
    ANode.Changed := False;
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      Mark(ANode.Children[mIndex]);
    end;
  end;

var
  mIndex: Integer;
begin
  for mIndex := 0 to FRoots.Count - 1 do
  begin
    Mark(FRoots[mIndex]);
  end;
end;

procedure TAtlasEvalList.SetResult(ANode: TAtlasEvalNode; AOk: Boolean; const AText: string);
var
  mPrevious: string;
begin
  ANode.Value := AText;
  if AOk then
  begin
    ANode.State := TAtlasEvalState.Value;
  end
  else
  begin
    ANode.State := TAtlasEvalState.Error;
  end;
  ANode.Changed := AOk and FPrevious.TryGetValue(ANode.Key, mPrevious) and (mPrevious <> AText);
  if AOk then
  begin
    FCurrent.AddOrSetValue(ANode.Key, AText);
  end;
  // Aufgeklappt ohne Felder: Teile aus dem neuen Wert.
  if ANode.Expanded and not ANode.ChildrenLoaded and AOk then
  begin
    SetParts(ANode);
  end;
end;

procedure TAtlasEvalList.SetFields(ANode: TAtlasEvalNode; const AFields: TArray<string>);
var
  mField: string;
begin
  ANode.ClearChildren;
  for mField in AFields do
  begin
    ANode.AddChild(mField, TAtlasEvalText.FieldExpression(ANode.Expression, mField)).State :=
      TAtlasEvalState.Pending;
  end;
  ANode.ChildrenLoaded := True;
end;

function TAtlasEvalList.SetParts(ANode: TAtlasEvalNode): Boolean;
var
  mParts: TAtlasEvalParts;
  mPart: TAtlasEvalPart;
  mChild: TAtlasEvalNode;
begin
  mParts := TAtlasEvalText.Parts(ANode.Value);
  Result := Length(mParts) > 0;
  if not Result then
  begin
    Exit;
  end;
  ANode.ClearChildren;
  for mPart in mParts do
  begin
    mChild := ANode.AddChild(mPart.Name, '');
    SetResult(mChild, True, mPart.Value);
  end;
  ANode.ChildrenLoaded := True;
  ANode.FromParts := True;
end;

procedure TAtlasEvalList.CollectPending(ANode: TAtlasEvalNode; AList: TList<TAtlasEvalNode>);
var
  mIndex: Integer;
begin
  if (ANode.Expression <> '') and (ANode.State = TAtlasEvalState.Pending) then
  begin
    AList.Add(ANode);
  end;
  if ANode.Expanded then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      CollectPending(ANode.Children[mIndex], AList);
    end;
  end;
end;

function TAtlasEvalList.Pending: TArray<TAtlasEvalNode>;
var
  mList: TList<TAtlasEvalNode>;
  mIndex: Integer;
begin
  mList := TList<TAtlasEvalNode>.Create;
  try
    for mIndex := 0 to FRoots.Count - 1 do
    begin
      CollectPending(FRoots[mIndex], mList);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>AKey gehört zu einem Knoten unter dem mit AParentKey (AParentKey + #1 + …).</summary>
function IsUnder(const AKey, AParentKey: string): Boolean;
var
  mLength: Integer;
begin
  mLength := Length(AParentKey);
  Result := (Length(AKey) > mLength) and (AKey[mLength + 1] = #1) and AKey.StartsWith(AParentKey);
end;

function TAtlasEvalList.Find(const AKey: string): TAtlasEvalNode;

  function Search(ANode: TAtlasEvalNode): TAtlasEvalNode;
  var
    mIndex: Integer;
  begin
    if ANode.Key = AKey then
    begin
      Exit(ANode);
    end;
    // Kinder tragen den Schlüssel des Elternknotens vorn (Key + #1 + Name): andere Teilbäume nicht absuchen. Der
    // Frame fragt bei jedem Abgleich und jeder Auswahl; ohne das ging jede Suche durch alle Knoten.
    if not IsUnder(AKey, ANode.Key) then
    begin
      Exit(nil);
    end;
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      Result := Search(ANode.Children[mIndex]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
    Result := nil;
  end;

var
  mIndex: Integer;
begin
  for mIndex := 0 to FRoots.Count - 1 do
  begin
    Result := Search(FRoots[mIndex]);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function TAtlasEvalList.PinnedExpressions: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to FRoots.Count - 1 do
  begin
    if FRoots[mIndex].Pinned then
    begin
      Result := Result + [FRoots[mIndex].Expression];
    end;
  end;
end;

{ TAtlasEvalDetailInput }

class function TAtlasEvalDetailInput.ForNode(ANode: TAtlasEvalNode; AView: TAtlasEvalView; ALinesOk: Boolean;
  const ALines: string): TAtlasEvalDetailInput;
begin
  Result := Default(TAtlasEvalDetailInput);
  Result.Valid := True;
  Result.View := AView;
  Result.LinesOk := ALinesOk;
  Result.Lines := ALines;
  if ANode <> nil then
  begin
    Result.Key := ANode.Key;
    Result.State := ANode.State;
    Result.Value := ANode.Value;
  end;
end;

function TAtlasEvalDetailInput.Same(const AOther: TAtlasEvalDetailInput): Boolean;
begin
  // Strings derselben Instanz vergleicht Delphi über den Zeiger: ein unveränderter langer Wert kostet nichts.
  Result := Valid and AOther.Valid and (Key = AOther.Key) and (State = AOther.State) and (View = AOther.View) and
    (LinesOk = AOther.LinesOk) and (Value = AOther.Value) and (Lines = AOther.Lines);
end;

end.
