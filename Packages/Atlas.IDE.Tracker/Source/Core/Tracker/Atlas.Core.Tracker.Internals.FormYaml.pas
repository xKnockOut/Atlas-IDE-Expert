unit Atlas.Core.Tracker.Internals.FormYaml;

// YAML-Leser für die Issue-Formulare von GitHub (#2137), ohne VCL und Open
// Tools API: nur der Teil, den .github/ISSUE_TEMPLATE/*.yml, config.yml und
// der Kopf von Markdown-Vorlagen nutzen. Ergebnis ist ein JSON-Baum
// (System.JSON), damit die Leser mit TJsonRead arbeiten.
// - Blöcke nach Einrückung: Zuordnungen „schlüssel: wert“ und Listen
//   „- wert“, auch „- schlüssel: wert“ und Listen auf der Einrückung ihres
//   Schlüssels.
// - Werte: ohne Anführungszeichen (Kommentar ab „ #“, Folgezeilen werden mit
//   Leerzeichen verbunden), '…' ('' = '), "…" mit \n, \t, \", \\, \uXXXX,
//   Blöcke | und > mit - und +, Folgen [a, "b"] und Abbildungen {a: b}, auch
//   über mehrere Zeilen. true/false werden Wahrheitswerte, null und ~ null;
//   Zahlen bleiben Text.
// - Nicht unterstützt (Parse liefert nil): Anker (&), Verweise (*), Typen (!),
//   „? “-Schlüssel, mehrere Dokumente und Tabulatoren in der Einrückung. Der
//   Dialog bietet für solche Vorlagen nur „Im Browser fortsetzen“ an.

interface

uses
  System.JSON;

type
  TAtlasFormYaml = class
  public
    /// <summary>Baum zu AText; nil bei nicht unterstützten Konstrukten oder fehlerhaftem Text. Der Aufrufer gibt
    /// das Ergebnis frei.</summary>
    class function ToJson(const AText: string): TJSONValue; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

const
  /// <summary>Hexziffern nach \x und \u.</summary>
  cByteDigits = 2;
  cCharDigits = 4;

type
  /// <summary>Text, den der Leser nicht versteht; ToJson fängt ihn ab und liefert nil.</summary>
  EAtlasFormYaml = class(Exception);

  TYamlLine = record
    /// <summary>Leerzeichen vor dem Inhalt.</summary>
    Indent: Integer;
    /// <summary>Inhalt ohne Einrückung und ohne Leerraum am Ende.</summary>
    Text: string;
    /// <summary>Ganze Zeile (für Blockwerte).</summary>
    Raw: string;
  end;

  /// <summary>Liest Zeile für Zeile; Fehler als EAtlasFormYaml.</summary>
  TYamlReader = class
  private
    FLines: TArray<TYamlLine>;
    FIndex: Integer;
    procedure SplitLines(const AText: string);
    function AtEnd: Boolean;
    procedure SkipBlank;
    function ParseBlock(AIndent: Integer): TJSONValue;
    function ParseMap(AIndent: Integer): TJSONObject;
    function ParseList(AIndent: Integer): TJSONArray;
    function ParseListItem(AIndent: Integer): TJSONValue;
    function ParseValue(const ARest: string; AOwnerIndent: Integer): TJSONValue;
    function ParseNested(AOwnerIndent: Integer): TJSONValue;
    function ParseBlockScalar(const AHeader: string; AOwnerIndent: Integer): TJSONValue;
    function ParsePlain(const AText: string; AOwnerIndent: Integer): TJSONValue;
    /// <summary>Einrückung eines Blockwerts: AOwnerIndent + AExplicit, ohne Angabe die der ersten nicht leeren
    /// Zeile.</summary>
    function BlockIndent(AOwnerIndent, AExplicit: Integer): Integer;
    /// <summary>Folgezeilen ab FIndex mit mindestens AIndent Leerzeichen, ohne diese Einrückung.</summary>
    function BlockLines(AIndent: Integer): TArray<string>;
    /// <summary>AText und die Folgezeilen, bis Klammern bzw. Anführungszeichen geschlossen sind.</summary>
    function Continued(const AText: string; AOwnerIndent: Integer): string;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Document: TJSONValue;
  end;

  /// <summary>Werte in einer Zeile: Anführungszeichen, [ … ] und { … }.</summary>
  TYamlFlow = class
  private
    FText: string;
    FPos: Integer;
    procedure SkipSpaces;
    function Peek: Char;
    function ReadQuoted: string;
    function ReadPlain(const AStops: TSysCharSet): string;
    function ReadSequence: TJSONArray;
    function ReadMapping: TJSONObject;
  public
    constructor Create(const AText: string);
    function ReadValue: TJSONValue;
    /// <summary>Nach dem Wert nur noch Leerraum oder ein Kommentar.</summary>
    procedure ExpectEnd;
    property Pos: Integer read FPos;
  end;

procedure Fail;
begin
  raise EAtlasFormYaml.Create('yaml');
end;

function IsBlank(const ALine: TYamlLine): Boolean;
begin
  Result := (ALine.Text = '') or (ALine.Text[1] = '#');
end;

function IsListItem(const AText: string): Boolean;
begin
  Result := (AText = '-') or AText.StartsWith('- ');
end;

/// <summary>Skalar ohne Anführungszeichen: true/false, null/~, sonst Text.</summary>
function Scalar(const AText: string): TJSONValue;
const
  cTrue = 0;
  cFalse = 1;
  cEmpty = 2;
  cTilde = 3;
  cNull = 4;
begin
  case IndexText(AText, ['true', 'false', '', '~', 'null']) of
    cTrue:
      Result := TJSONBool.Create(True);
    cFalse:
      Result := TJSONBool.Create(False);
    cEmpty, cTilde, cNull:
      Result := TJSONNull.Create;
  else
    Result := TJSONString.Create(AText);
  end;
end;

/// <summary>Kommentar ab " #" abschneiden (nur für Text ohne Anführungszeichen).</summary>
function StripComment(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  for mIndex := 2 to Length(AText) do
  begin
    if (AText[mIndex] = '#') and CharInSet(AText[mIndex - 1], [' ', #9]) then
    begin
      Result := Copy(AText, 1, mIndex - 1);
      Break;
    end;
  end;
  Result := TrimRight(Result);
end;

/// <summary>Anfang, den der Leser ablehnt (Anker, Verweise, Typen, „? “-Schlüssel).</summary>
procedure RejectSpecial(const AText: string);
begin
  if (AText <> '') and (CharInSet(AText[1], ['&', '*', '!', '%', '@', '`']) or AText.StartsWith('? ') or
    (AText = '?')) then
  begin
    Fail;
  end;
end;

/// <summary>Stelle hinter dem schließenden Anführungszeichen ab AStart; 0 ohne.</summary>
function QuoteEnd(const AText: string; AStart: Integer): Integer;
var
  mQuote: Char;
begin
  mQuote := AText[AStart];
  Result := AStart + 1;
  while Result <= Length(AText) do
  begin
    if (mQuote = '"') and (AText[Result] = '\') then
    begin
      Inc(Result, 2);
      Continue;
    end;
    if AText[Result] = mQuote then
    begin
      if (mQuote = '''') and (Result < Length(AText)) and (AText[Result + 1] = '''') then
      begin
        Inc(Result, 2);
        Continue;
      end;
      Exit(Result + 1);
    end;
    Inc(Result);
  end;
  Result := 0;
end;

/// <summary>Zuordnung mit Schlüssel in Anführungszeichen ("a b": rest).</summary>
function SplitQuotedKey(const AText: string; out AKey, ARest: string): Boolean;
var
  mEnd: Integer;
  mFlow: TYamlFlow;
begin
  mEnd := QuoteEnd(AText, 1);
  Result := (mEnd > 0) and (mEnd <= Length(AText)) and (AText[mEnd] = ':') and
    ((mEnd = Length(AText)) or (AText[mEnd + 1] = ' '));
  if Result then
  begin
    mFlow := TYamlFlow.Create(Copy(AText, 1, mEnd - 1));
    try
      AKey := mFlow.ReadQuoted;
    finally
      mFlow.Free;
    end;
    ARest := Copy(AText, mEnd + 1, MaxInt);
  end;
end;

/// <summary>Zuordnung mit Schlüssel ohne Anführungszeichen (schlüssel: rest); ein Kommentar davor beendet die
/// Suche.</summary>
function SplitPlainKey(const AText: string; out AKey, ARest: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to Length(AText) do
  begin
    if (AText[mIndex] = '#') and (mIndex > 1) and (AText[mIndex - 1] = ' ') then
    begin
      Break;
    end;
    if (AText[mIndex] = ':') and ((mIndex = Length(AText)) or (AText[mIndex + 1] = ' ')) then
    begin
      AKey := TrimRight(Copy(AText, 1, mIndex - 1));
      ARest := Copy(AText, mIndex + 1, MaxInt);
      Result := AKey <> '';
      Break;
    end;
  end;
end;

/// <summary>"schlüssel: rest" in AKey und ARest; False, wenn AText keine Zuordnung ist.</summary>
function SplitKey(const AText: string; out AKey, ARest: string): Boolean;
begin
  Result := False;
  AKey := '';
  ARest := '';
  if AText = '' then
  begin
    Exit;
  end;
  if CharInSet(AText[1], ['"', '''']) then
  begin
    Result := SplitQuotedKey(AText, AKey, ARest);
  end
  else if not CharInSet(AText[1], ['[', '{', '#']) then
  begin
    Result := SplitPlainKey(AText, AKey, ARest);
  end;
end;

{ TYamlFlow }

constructor TYamlFlow.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

procedure TYamlFlow.SkipSpaces;
begin
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], [' ', #9, #10]) do
  begin
    Inc(FPos);
  end;
end;

function TYamlFlow.Peek: Char;
begin
  SkipSpaces;
  if FPos > Length(FText) then
  begin
    Result := #0;
  end
  else
  begin
    Result := FText[FPos];
  end;
end;

/// <summary>Escape nach "\" in doppelten Anführungszeichen ab APos; APos danach hinter dem Escape.</summary>
function Escaped(const AText: string; var APos: Integer): string;
var
  mDigits: Integer;
  mCode: Integer;
begin
  Result := '';
  if APos > Length(AText) then
  begin
    Fail;
  end;
  mDigits := 0;
  case AText[APos] of
    'n':
      Result := #10;
    't':
      Result := #9;
    'r':
      Result := #13;
    '0':
      Result := #0;
    ' ', '"', '\', '/':
      Result := AText[APos];
    'x':
      mDigits := cByteDigits;
    'u':
      mDigits := cCharDigits;
  else
    Fail;
  end;
  Inc(APos);
  if mDigits > 0 then
  begin
    if (APos + mDigits - 1 > Length(AText)) or not TryStrToInt('$' + Copy(AText, APos, mDigits), mCode) then
    begin
      Fail;
    end;
    Result := Char(mCode);
    Inc(APos, mDigits);
  end;
end;

function TYamlFlow.ReadQuoted: string;
var
  mQuote: Char;
  mBuilder: TStringBuilder;
begin
  mQuote := FText[FPos];
  Inc(FPos);
  mBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      if FPos > Length(FText) then
      begin
        Fail;
      end;
      if (mQuote = '"') and (FText[FPos] = '\') then
      begin
        Inc(FPos);
        mBuilder.Append(Escaped(FText, FPos));
        Continue;
      end;
      if FText[FPos] = mQuote then
      begin
        if (mQuote = '''') and (FPos < Length(FText)) and (FText[FPos + 1] = '''') then
        begin
          mBuilder.Append('''');
          Inc(FPos, 2);
          Continue;
        end;
        Inc(FPos);
        Break;
      end;
      // Zeilen in Anführungszeichen werden mit einem Leerzeichen verbunden (Continued liefert #10).
      if FText[FPos] = #10 then
      begin
        mBuilder.Append(' ');
      end
      else
      begin
        mBuilder.Append(FText[FPos]);
      end;
      Inc(FPos);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TYamlFlow.ReadPlain(const AStops: TSysCharSet): string;
var
  mStart: Integer;
begin
  mStart := FPos;
  while (FPos <= Length(FText)) and not CharInSet(FText[FPos], AStops) do
  begin
    // ": " beendet einen Schlüssel, ":" in einer Adresse nicht.
    if (FText[FPos] = ':') and ('}' in AStops) and ((FPos = Length(FText)) or
      CharInSet(FText[FPos + 1], [' ', #10, ',', '}'])) then
    begin
      Break;
    end;
    Inc(FPos);
  end;
  Result := Trim(StringReplace(Copy(FText, mStart, FPos - mStart), #10, ' ', [rfReplaceAll]));
  RejectSpecial(Result);
end;

function TYamlFlow.ReadSequence: TJSONArray;
begin
  Inc(FPos);
  Result := TJSONArray.Create;
  try
    while Peek <> ']' do
    begin
      if Peek = #0 then
      begin
        Fail;
      end;
      Result.AddElement(ReadValue);
      if Peek = ',' then
      begin
        Inc(FPos);
      end
      else if Peek <> ']' then
      begin
        Fail;
      end;
    end;
    Inc(FPos);
  except
    Result.Free;
    raise;
  end;
end;

function TYamlFlow.ReadMapping: TJSONObject;
var
  mKey: string;
begin
  Inc(FPos);
  Result := TJSONObject.Create;
  try
    while Peek <> '}' do
    begin
      if Peek = #0 then
      begin
        Fail;
      end;
      if CharInSet(Peek, ['"', '''']) then
      begin
        mKey := ReadQuoted;
      end
      else
      begin
        mKey := ReadPlain([',', '}', ']', '[', '{']);
      end;
      if Peek <> ':' then
      begin
        Fail;
      end;
      Inc(FPos);
      Result.AddPair(mKey, ReadValue);
      if Peek = ',' then
      begin
        Inc(FPos);
      end
      else if Peek <> '}' then
      begin
        Fail;
      end;
    end;
    Inc(FPos);
  except
    Result.Free;
    raise;
  end;
end;

function TYamlFlow.ReadValue: TJSONValue;
begin
  case Peek of
    '[':
      Result := ReadSequence;
    '{':
      Result := ReadMapping;
    '"', '''':
      Result := TJSONString.Create(ReadQuoted);
  else
    Result := Scalar(ReadPlain([',', ']', '}']));
  end;
end;

procedure TYamlFlow.ExpectEnd;
begin
  if (Peek <> #0) and (Peek <> '#') then
  begin
    Fail;
  end;
end;

{ TYamlReader }

constructor TYamlReader.Create(const AText: string);
begin
  inherited Create;
  SplitLines(AText);
end;

destructor TYamlReader.Destroy;
begin
  FLines := nil;
  inherited Destroy;
end;

procedure TYamlReader.SplitLines(const AText: string);
var
  mParts: TArray<string>;
  mPart: string;
  mLine: TYamlLine;
begin
  mParts := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
  FLines := nil;
  for mPart in mParts do
  begin
    mLine.Raw := mPart;
    mLine.Indent := 0;
    while (mLine.Indent < Length(mPart)) and (mPart[mLine.Indent + 1] = ' ') do
    begin
      Inc(mLine.Indent);
    end;
    mLine.Text := TrimRight(Copy(mPart, mLine.Indent + 1, MaxInt));
    // Tabulator in der Einrückung ist in YAML verboten.
    if (mLine.Text <> '') and (mLine.Text[1] = #9) and (Trim(mLine.Text) <> '') then
    begin
      Fail;
    end;
    FLines := FLines + [mLine];
  end;
  if (Length(FLines) > 0) and FLines[0].Raw.StartsWith(#$FEFF) then
  begin
    FLines[0].Raw := Copy(FLines[0].Raw, 2, MaxInt);
    FLines[0].Text := TrimLeft(Copy(FLines[0].Text, 2, MaxInt));
  end;
  FIndex := 0;
end;

function TYamlReader.AtEnd: Boolean;
begin
  Result := FIndex > High(FLines);
end;

procedure TYamlReader.SkipBlank;
begin
  while not AtEnd and IsBlank(FLines[FIndex]) do
  begin
    Inc(FIndex);
  end;
end;

function TYamlReader.Document: TJSONValue;
begin
  SkipBlank;
  if not AtEnd and (FLines[FIndex].Indent = 0) and (FLines[FIndex].Text = '---') then
  begin
    Inc(FIndex);
    SkipBlank;
  end;
  if AtEnd then
  begin
    Exit(TJSONNull.Create);
  end;
  Result := ParseBlock(FLines[FIndex].Indent);
  try
    SkipBlank;
    // Ein zweites Dokument (---) oder Reste mit kleinerer Einrückung versteht der Leser nicht; "..." beendet.
    if not AtEnd and (FLines[FIndex].Text <> '...') then
    begin
      Fail;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYamlReader.ParseBlock(AIndent: Integer): TJSONValue;
var
  mKey, mRest: string;
begin
  SkipBlank;
  if AtEnd then
  begin
    Exit(TJSONNull.Create);
  end;
  if IsListItem(FLines[FIndex].Text) then
  begin
    Result := ParseList(AIndent);
  end
  else if SplitKey(FLines[FIndex].Text, mKey, mRest) then
  begin
    Result := ParseMap(AIndent);
  end
  else
  begin
    // Ein Wert allein (etwa ein Dokument nur aus Text).
    Inc(FIndex);
    Result := ParseValue(' ' + FLines[FIndex - 1].Text, AIndent - 1);
  end;
end;

function TYamlReader.ParseMap(AIndent: Integer): TJSONObject;
var
  mKey, mRest: string;
begin
  Result := TJSONObject.Create;
  try
    while True do
    begin
      SkipBlank;
      if AtEnd or (FLines[FIndex].Indent < AIndent) then
      begin
        Break;
      end;
      if (FLines[FIndex].Indent > AIndent) or not SplitKey(FLines[FIndex].Text, mKey, mRest) then
      begin
        // Eine Liste auf dieser Einrückung gehört zum Schlüssel davor (ParseNested); hier ist sie ein Fehler.
        Fail;
      end;
      RejectSpecial(mKey);
      Inc(FIndex);
      Result.AddPair(mKey, ParseValue(mRest, AIndent));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYamlReader.ParseList(AIndent: Integer): TJSONArray;
begin
  Result := TJSONArray.Create;
  try
    while True do
    begin
      SkipBlank;
      if AtEnd or (FLines[FIndex].Indent < AIndent) then
      begin
        Break;
      end;
      if FLines[FIndex].Indent > AIndent then
      begin
        Fail;
      end;
      if not IsListItem(FLines[FIndex].Text) then
      begin
        Break;
      end;
      Result.AddElement(ParseListItem(AIndent));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYamlReader.ParseListItem(AIndent: Integer): TJSONValue;
var
  mContent, mKey, mRest: string;
  mOffset: Integer;
begin
  mContent := Copy(FLines[FIndex].Text, 2, MaxInt);
  mOffset := 1;
  while (mOffset <= Length(mContent)) and (mContent[mOffset] = ' ') do
  begin
    Inc(mOffset);
  end;
  mContent := Copy(mContent, mOffset, MaxInt);
  if (mContent = '') or (mContent[1] = '#') then
  begin
    Inc(FIndex);
    Exit(ParseNested(AIndent));
  end;
  if IsListItem(mContent) or (SplitKey(mContent, mKey, mRest) and not CharInSet(mContent[1], ['[', '{'])) then
  begin
    // "- name: x" bzw. "- - a": Der Rest der Zeile beginnt einen Block auf der Einrückung hinter dem Strich.
    FLines[FIndex].Indent := AIndent + mOffset;
    FLines[FIndex].Text := mContent;
    Exit(ParseBlock(AIndent + mOffset));
  end;
  Inc(FIndex);
  Result := ParseValue(' ' + mContent, AIndent);
end;

function TYamlReader.ParseNested(AOwnerIndent: Integer): TJSONValue;
begin
  SkipBlank;
  if AtEnd then
  begin
    Exit(TJSONNull.Create);
  end;
  if FLines[FIndex].Indent > AOwnerIndent then
  begin
    Result := ParseBlock(FLines[FIndex].Indent);
  end
  else if (FLines[FIndex].Indent = AOwnerIndent) and IsListItem(FLines[FIndex].Text) then
  begin
    // labels:
    // - bug   (Liste auf der Einrückung des Schlüssels)
    Result := ParseList(AOwnerIndent);
  end
  else
  begin
    Result := TJSONNull.Create;
  end;
end;

/// <summary>True, wenn in AText eine Klammer oder ein Anführungszeichen offen bleibt.</summary>
function FlowOpen(const AText: string): Boolean;
var
  mDepth, mIndex: Integer;
  mQuote: Char;
begin
  mDepth := 0;
  mQuote := #0;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if mQuote = #0 then
    begin
      case AText[mIndex] of
        '"', '''':
          mQuote := AText[mIndex];
        '[', '{':
          Inc(mDepth);
        ']', '}':
          Dec(mDepth);
      end;
    end
    else if (mQuote = '"') and (AText[mIndex] = '\') then
    begin
      Inc(mIndex);
    end
    else if AText[mIndex] = mQuote then
    begin
      mQuote := #0;
    end;
    Inc(mIndex);
  end;
  Result := (mDepth > 0) or (mQuote <> #0);
end;

function TYamlReader.Continued(const AText: string; AOwnerIndent: Integer): string;
begin
  Result := AText;
  while FlowOpen(Result) do
  begin
    // Noch offen: die nächste Zeile gehört dazu (eingerückt hinter dem Schlüssel).
    if AtEnd or ((FLines[FIndex].Text <> '') and (FLines[FIndex].Indent <= AOwnerIndent)) then
    begin
      Fail;
    end;
    Result := Result + #10 + FLines[FIndex].Text;
    Inc(FIndex);
  end;
end;

function TYamlReader.ParseValue(const ARest: string; AOwnerIndent: Integer): TJSONValue;
var
  mText: string;
  mFlow: TYamlFlow;
begin
  mText := Trim(ARest);
  if (mText = '') or (mText[1] = '#') then
  begin
    Exit(ParseNested(AOwnerIndent));
  end;
  RejectSpecial(mText);
  if CharInSet(mText[1], ['|', '>']) then
  begin
    Exit(ParseBlockScalar(mText, AOwnerIndent));
  end;
  if not CharInSet(mText[1], ['"', '''', '[', '{']) then
  begin
    Exit(ParsePlain(mText, AOwnerIndent));
  end;
  mFlow := TYamlFlow.Create(Continued(mText, AOwnerIndent));
  try
    Result := mFlow.ReadValue;
    try
      mFlow.ExpectEnd;
    except
      Result.Free;
      raise;
    end;
  finally
    mFlow.Free;
  end;
end;

function TYamlReader.ParsePlain(const AText: string; AOwnerIndent: Integer): TJSONValue;
var
  mText: TStringBuilder;
  mBreaks: Integer;
begin
  mText := TStringBuilder.Create(StripComment(AText));
  try
    mBreaks := 0;
    // Folgezeilen eines Werts ohne Anführungszeichen: weiter eingerückt als der Schlüssel, Leerzeilen = Umbruch.
    while not AtEnd and ((FLines[FIndex].Text = '') or ((FLines[FIndex].Indent > AOwnerIndent) and
      (FLines[FIndex].Text[1] <> '#'))) do
    begin
      if FLines[FIndex].Text = '' then
      begin
        Inc(mBreaks);
      end
      else
      begin
        if mBreaks > 0 then
        begin
          mText.Append(StringOfChar(#10, mBreaks));
        end
        else
        begin
          mText.Append(' ');
        end;
        mText.Append(StripComment(FLines[FIndex].Text));
        mBreaks := 0;
      end;
      Inc(FIndex);
    end;
    Result := Scalar(mText.ToString);
  finally
    mText.Free;
  end;
end;

/// <summary>Trenner vor einer Zeile eines Blockwerts nach ABreaks Leerzeilen. Gefaltet (>) wird ein einzelner
/// Umbruch zwischen zwei normalen Zeilen ein Leerzeichen; weiter eingerückte Zeilen behalten ihre Umbrüche.</summary>
function BlockSeparator(AStarted, AFolded, APreviousNormal, AMore: Boolean; ABreaks: Integer): string;
var
  mJoins: Boolean;
begin
  mJoins := AFolded and APreviousNormal and not AMore;
  if not AStarted then
  begin
    Result := StringOfChar(#10, ABreaks);
  end
  else if mJoins and (ABreaks = 0) then
  begin
    Result := ' ';
  end
  else if mJoins then
  begin
    Result := StringOfChar(#10, ABreaks);
  end
  else
  begin
    Result := StringOfChar(#10, ABreaks + 1);
  end;
end;

/// <summary>Zeilen eines Blockwerts zusammensetzen: | behält Umbrüche, > faltet; AChomp '-', '+' oder ''.
/// </summary>
function JoinBlock(const ALines: TArray<string>; AFolded: Boolean; AChomp: Char): string;
var
  mBuilder: TStringBuilder;
  mLine: string;
  mBreaks: Integer;
  mStarted, mPreviousNormal, mMore: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBreaks := 0;
    mStarted := False;
    mPreviousNormal := False;
    for mLine in ALines do
    begin
      if mLine = '' then
      begin
        Inc(mBreaks);
        Continue;
      end;
      mMore := CharInSet(mLine[1], [' ', #9]);
      mBuilder.Append(BlockSeparator(mStarted, AFolded, mPreviousNormal, mMore, mBreaks));
      mBuilder.Append(mLine);
      mStarted := True;
      mPreviousNormal := not mMore;
      mBreaks := 0;
    end;
    if mStarted and (AChomp = '+') then
    begin
      mBuilder.Append(StringOfChar(#10, mBreaks + 1));
    end
    else if mStarted and (AChomp <> '-') then
    begin
      mBuilder.Append(#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Kopf eines Blockwerts ("|", ">-", "|2+"): Kürzung am Ende und angegebene Einrückung (0 = ohne).
/// </summary>
procedure ReadBlockHeader(const AHeader: string; out AChomp: Char; out AExplicit: Integer);
var
  mIndex: Integer;
begin
  AChomp := #0;
  AExplicit := 0;
  for mIndex := 2 to Length(AHeader) do
  begin
    case AHeader[mIndex] of
      '-', '+':
        AChomp := AHeader[mIndex];
      '1'..'9':
        AExplicit := Ord(AHeader[mIndex]) - Ord('0');
    else
      Fail;
    end;
  end;
end;

function TYamlReader.BlockIndent(AOwnerIndent, AExplicit: Integer): Integer;
var
  mIndex: Integer;
begin
  if AExplicit > 0 then
  begin
    Exit(AOwnerIndent + AExplicit);
  end;
  Result := 0;
  mIndex := FIndex;
  while (mIndex <= High(FLines)) and (Trim(FLines[mIndex].Raw) = '') do
  begin
    Inc(mIndex);
  end;
  if mIndex <= High(FLines) then
  begin
    Result := FLines[mIndex].Indent;
  end;
end;

function TYamlReader.BlockLines(AIndent: Integer): TArray<string>;
var
  mLines: TList<string>;
begin
  mLines := TList<string>.Create;
  try
    while not AtEnd and ((Trim(FLines[FIndex].Raw) = '') or (FLines[FIndex].Indent >= AIndent)) do
    begin
      mLines.Add(TrimRight(Copy(FLines[FIndex].Raw, AIndent + 1, MaxInt)));
      Inc(FIndex);
    end;
    Result := mLines.ToArray;
  finally
    mLines.Free;
  end;
end;

function TYamlReader.ParseBlockScalar(const AHeader: string; AOwnerIndent: Integer): TJSONValue;
var
  mHeader: string;
  mChomp: Char;
  mIndent, mExplicit: Integer;
  mLines: TArray<string>;
begin
  mHeader := StripComment(AHeader);
  ReadBlockHeader(mHeader, mChomp, mExplicit);
  mIndent := BlockIndent(AOwnerIndent, mExplicit);
  mLines := nil;
  if mIndent > AOwnerIndent then
  begin
    mLines := BlockLines(mIndent);
  end;
  Result := TJSONString.Create(JoinBlock(mLines, mHeader[1] = '>', mChomp));
end;

{ TAtlasFormYaml }

class function TAtlasFormYaml.ToJson(const AText: string): TJSONValue;
var
  mReader: TYamlReader;
begin
  try
    mReader := TYamlReader.Create(AText);
    try
      Result := mReader.Document;
    finally
      mReader.Free;
    end;
  except
    // Nicht unterstützt oder fehlerhaft: nil, die Vorlage geht nur im Browser.
    on E: EAtlasFormYaml do
    begin
      Result := nil;
    end;
  end;
end;

end.
