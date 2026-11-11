unit Atlas.Common.Configuration.Internals.JsonTree;

// JSON-Leser mit Positionen, damit Fehler in atlas.json genau an der
// Stelle gemeldet werden können. Erlaubt wie VS Code (JSONC) Kommentare
// (// und /* */) und ein Komma vor } bzw. ]. Offsets zählen ab 0 in
// UTF-16-Codeeinheiten.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TJsonKind = (Null, Boolean_, Number, String_, Array_, Object_);

  EJsonTreeError = class(Exception)
  private
    FOffset: Integer;
  public
    constructor Create(const AMessage: string; AOffset: Integer);
    property Offset: Integer read FOffset;
  end;

  TJsonNode = class
  private
    FKind: TJsonKind;
    FValue: string;
    FStart: Integer;
    FStop: Integer;
    FKeys: TList<string>;
    FKeyStarts: TList<Integer>;
    FItems: TObjectList<TJsonNode>;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TJsonNode;
    function GetKey(AIndex: Integer): string;
    function GetKeyStart(AIndex: Integer): Integer;
  public
    constructor Create(AKind: TJsonKind; AStart: Integer);
    destructor Destroy; override;
    property Kind: TJsonKind read FKind;
    /// <summary>Wert bei String_ (entschlüsselt), Number, Boolean_ ("true"/"false").</summary>
    property Value: string read FValue;
    /// <summary>Offset des ersten Zeichens.</summary>
    property Start: Integer read FStart;
    /// <summary>Offset hinter dem letzten Zeichen.</summary>
    property Stop: Integer read FStop;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TJsonNode read GetItem; default;
    /// <summary>Schlüssel bei Object_.</summary>
    property Keys[AIndex: Integer]: string read GetKey;
    /// <summary>Offset des Schlüssels (beim Anführungszeichen) bei Object_.</summary>
    property KeyStarts[AIndex: Integer]: Integer read GetKeyStart;
  end;

  TJsonTree = class
  public
    /// <summary>Liest AText; EJsonTreeError mit Offset bei Fehlern. Der Aufrufer gibt den Knoten frei.</summary>
    class function Parse(const AText: string): TJsonNode; static;
  end;

implementation

uses
  Atlas.Text.Jsonc,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TJsonTreeText = (CommentNotClosed, StringNotClosed, InvalidUSequence, InvalidEscapeSequence, OrExpected,
    KeyInQuotationMarksExpected, Missing, Missing2, ContentAfterTheValue, LineBreakInString, ValueExpected,
    UnknownValue, NestedTooDeeply, Expected);

const
  cTexts: array[TJsonTreeText] of TAtlasText = (
    (De: 'Kommentar nicht abgeschlossen'; En: 'Comment not closed'),
    (De: 'String nicht abgeschlossen'; En: 'String not closed'),
    (De: 'Ungültige \u-Folge'; En: 'Invalid \u sequence'),
    (De: 'Ungültige Escape-Folge'; En: 'Invalid escape sequence'),
    (De: '"," oder "%s" erwartet'; En: '"," or "%s" expected'),
    (De: 'Schlüssel in Anführungszeichen erwartet'; En: 'Key in quotation marks expected'),
    (De: '"}" fehlt'; En: '"}" missing'),
    (De: '"]" fehlt'; En: '"]" missing'),
    (De: 'Inhalt hinter dem Wert'; En: 'Content after the value'),
    (De: 'Zeilenumbruch im String'; En: 'Line break in string'),
    (De: 'Wert erwartet'; En: 'Value expected'),
    (De: 'Unbekannter Wert "%s"'; En: 'Unknown value "%s"'),
    (De: 'Zu tief verschachtelt'; En: 'Nested too deeply'),
    (De: '":" erwartet'; En: '":" expected'));

type
  TReader = class
  private
    FText: string;
    FPos: Integer;
    procedure Fail(const AMessage: string);
    procedure SkipSpace;
    function ReadString: string;
    procedure ReadEscape(ABuilder: TStringBuilder);
    /// <summary>Nach einem Glied: "," überspringen oder AClose erwarten; sonst Fehler.</summary>
    procedure SkipSeparator(AClose: Char);
    procedure ReadMember(ANode: TJsonNode; ADepth: Integer);
    function ParseObject(AStart, ADepth: Integer): TJsonNode;
    function ParseArray(AStart, ADepth: Integer): TJsonNode;
    function ParseWord(AStart: Integer): TJsonNode;
    function ParseValue(ADepth: Integer): TJsonNode;
  public
    constructor Create(const AText: string);
    function Run: TJsonNode;
  end;

const
  cMaxDepth = 64;

{ EJsonTreeError }

constructor EJsonTreeError.Create(const AMessage: string; AOffset: Integer);
begin
  inherited Create(AMessage);
  FOffset := AOffset;
end;

{ TJsonNode }

constructor TJsonNode.Create(AKind: TJsonKind; AStart: Integer);
begin
  inherited Create;
  FKind := AKind;
  FStart := AStart;
  FStop := AStart;
  FKeys := TList<string>.Create;
  FKeyStarts := TList<Integer>.Create;
  FItems := TObjectList<TJsonNode>.Create(True);
end;

destructor TJsonNode.Destroy;
begin
  FItems.Free;
  FKeyStarts.Free;
  FKeys.Free;
  inherited;
end;

function TJsonNode.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJsonNode.GetItem(AIndex: Integer): TJsonNode;
begin
  Result := FItems[AIndex];
end;

function TJsonNode.GetKey(AIndex: Integer): string;
begin
  Result := FKeys[AIndex];
end;

function TJsonNode.GetKeyStart(AIndex: Integer): Integer;
begin
  Result := FKeyStarts[AIndex];
end;

{ TReader }

constructor TReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  if (FText <> '') and (FText[1] = #$FEFF) then
  begin
    FPos := 2;
  end;
end;

procedure TReader.Fail(const AMessage: string);
begin
  raise EJsonTreeError.Create(AMessage, FPos - 1);
end;

procedure TReader.SkipSpace;
var
  mOpenComment: Integer;
begin
  // Gleiche Regeln wie im Plugin (TJsoncScanner); ein offener Blockkommentar ist hier ein Fehler.
  if not TJsoncScanner.SkipSpace(FText, FPos, mOpenComment) then
  begin
    FPos := mOpenComment;
    Fail(cTexts[TJsonTreeText.CommentNotClosed].Text);
  end;
end;

function TReader.ReadString: string;
var
  mBuilder: TStringBuilder;
begin
  // FPos steht auf dem öffnenden Anführungszeichen.
  Inc(FPos);
  mBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      if FPos > Length(FText) then
      begin
        Fail(cTexts[TJsonTreeText.StringNotClosed].Text);
      end;
      case FText[FPos] of
        '"':
          begin
            Inc(FPos);
            Break;
          end;
        #10, #13:
          Fail(cTexts[TJsonTreeText.LineBreakInString].Text);
        '\':
          ReadEscape(mBuilder);
      else
        mBuilder.Append(FText[FPos]);
        Inc(FPos);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TReader.ReadEscape(ABuilder: TStringBuilder);
var
  mCode: Integer;
begin
  // FPos steht auf dem Rückstrich.
  Inc(FPos);
  if FPos > Length(FText) then
  begin
    Fail(cTexts[TJsonTreeText.StringNotClosed].Text);
  end;
  case FText[FPos] of
    '"', '\', '/': ABuilder.Append(FText[FPos]);
    'b': ABuilder.Append(#8);
    'f': ABuilder.Append(#12);
    'n': ABuilder.Append(#10);
    'r': ABuilder.Append(#13);
    't': ABuilder.Append(#9);
    'u':
      begin
        mCode := StrToIntDef('$' + Copy(FText, FPos + 1, 4), -1);
        if (mCode < 0) or (FPos + 4 > Length(FText)) then
        begin
          Fail(cTexts[TJsonTreeText.InvalidUSequence].Text);
        end;
        ABuilder.Append(Char(mCode));
        Inc(FPos, 4);
      end;
  else
    Fail(cTexts[TJsonTreeText.InvalidEscapeSequence].Text);
  end;
  Inc(FPos);
end;

procedure TReader.SkipSeparator(AClose: Char);
begin
  SkipSpace;
  if (FPos <= Length(FText)) and (FText[FPos] = ',') then
  begin
    Inc(FPos);
    SkipSpace;
  end
  else if (FPos <= Length(FText)) and (FText[FPos] <> AClose) then
  begin
    Fail(cTexts[TJsonTreeText.OrExpected].Fmt([AClose]));
  end;
end;

procedure TReader.ReadMember(ANode: TJsonNode; ADepth: Integer);
var
  mKey: string;
  mKeyStart: Integer;
begin
  if FText[FPos] <> '"' then
  begin
    Fail(cTexts[TJsonTreeText.KeyInQuotationMarksExpected].Text);
  end;
  mKeyStart := FPos - 1;
  mKey := ReadString;
  SkipSpace;
  if (FPos > Length(FText)) or (FText[FPos] <> ':') then
  begin
    Fail(cTexts[TJsonTreeText.Expected].Text);
  end;
  Inc(FPos);
  ANode.FKeys.Add(mKey);
  ANode.FKeyStarts.Add(mKeyStart);
  ANode.FItems.Add(ParseValue(ADepth + 1));
end;

function TReader.ParseObject(AStart, ADepth: Integer): TJsonNode;
begin
  Result := TJsonNode.Create(TJsonKind.Object_, AStart);
  try
    Inc(FPos);
    SkipSpace;
    while (FPos <= Length(FText)) and (FText[FPos] <> '}') do
    begin
      ReadMember(Result, ADepth);
      SkipSeparator('}');
    end;
    if FPos > Length(FText) then
    begin
      Fail(cTexts[TJsonTreeText.Missing].Text);
    end;
    Inc(FPos);
    Result.FStop := FPos - 1;
  except
    Result.Free;
    raise;
  end;
end;

function TReader.ParseArray(AStart, ADepth: Integer): TJsonNode;
begin
  Result := TJsonNode.Create(TJsonKind.Array_, AStart);
  try
    Inc(FPos);
    SkipSpace;
    while (FPos <= Length(FText)) and (FText[FPos] <> ']') do
    begin
      Result.FItems.Add(ParseValue(ADepth + 1));
      SkipSeparator(']');
    end;
    if FPos > Length(FText) then
    begin
      Fail(cTexts[TJsonTreeText.Missing2].Text);
    end;
    Inc(FPos);
    Result.FStop := FPos - 1;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>null, true, false oder eine Zahl ab AStart.</summary>
function TReader.ParseWord(AStart: Integer): TJsonNode;
var
  mWord: string;
begin
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], ['A'..'Z', 'a'..'z', '0'..'9', '-', '+', '.']) do
  begin
    Inc(FPos);
  end;
  mWord := Copy(FText, AStart + 1, FPos - 1 - AStart);
  if mWord = '' then
  begin
    Fail(cTexts[TJsonTreeText.ValueExpected].Text);
  end;
  if mWord = 'null' then
  begin
    Result := TJsonNode.Create(TJsonKind.Null, AStart);
  end
  else if (mWord = 'true') or (mWord = 'false') then
  begin
    Result := TJsonNode.Create(TJsonKind.Boolean_, AStart);
  end
  else if CharInSet(mWord[1], ['-', '0'..'9']) then
  begin
    Result := TJsonNode.Create(TJsonKind.Number, AStart);
  end
  else
  begin
    raise EJsonTreeError.Create(cTexts[TJsonTreeText.UnknownValue].Fmt([mWord]), AStart);
  end;
  Result.FValue := mWord;
  Result.FStop := FPos - 1;
end;

function TReader.ParseValue(ADepth: Integer): TJsonNode;
var
  mStart: Integer;
  mText: string;
begin
  if ADepth > cMaxDepth then
  begin
    Fail(cTexts[TJsonTreeText.NestedTooDeeply].Text);
  end;
  SkipSpace;
  if FPos > Length(FText) then
  begin
    Fail(cTexts[TJsonTreeText.ValueExpected].Text);
  end;
  mStart := FPos - 1;
  case FText[FPos] of
    '{':
      Result := ParseObject(mStart, ADepth);
    '[':
      Result := ParseArray(mStart, ADepth);
    '"':
      begin
        mText := ReadString;
        Result := TJsonNode.Create(TJsonKind.String_, mStart);
        Result.FValue := mText;
        Result.FStop := FPos - 1;
      end;
  else
    Result := ParseWord(mStart);
  end;
end;

function TReader.Run: TJsonNode;
begin
  Result := ParseValue(0);
  try
    SkipSpace;
    if FPos <= Length(FText) then
    begin
      Fail(cTexts[TJsonTreeText.ContentAfterTheValue].Text);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TJsonTree }

class function TJsonTree.Parse(const AText: string): TJsonNode;
var
  mReader: TReader;
begin
  mReader := TReader.Create(AText);
  try
    Result := mReader.Run;
  finally
    mReader.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Configuration.Internals.JsonTree', cTexts);

end.
