unit Atlas.Common.Projects.Internals.Xml;

// Kleiner XML-Leser für Projektdateien (.dproj, .groupproj). Xml.XMLDoc
// setzt unter Windows auf MSXML und darf in Atlas.Common nicht verwendet
// werden. Unterstützt werden Elemente, Attribute, Text, die fünf
// Standard-Entities, numerische Zeichenreferenzen, Kommentare, CDATA und
// Verarbeitungsanweisungen. Namensräume werden nicht ausgewertet; ein Präfix
// bleibt Teil des Namens. Fehlerhaftes XML löst EXmlError aus.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  EXmlError = class(Exception);

  TXmlElement = class
  private
    FName: string;
    FAttributeNames: TList<string>;
    FAttributeValues: TList<string>;
    FChildren: TObjectList<TXmlElement>;
    FText: string;
    function GetChildCount: Integer;
    function GetChild(AIndex: Integer): TXmlElement;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    /// <summary>Wert des Attributs; '' wenn es fehlt.</summary>
    function Attribute(const AName: string): string;
    function HasAttribute(const AName: string): Boolean;
    /// <summary>Erstes Kind mit dem Namen oder nil.</summary>
    function Find(const AName: string): TXmlElement;
    property Name: string read FName;
    /// <summary>Zusammengefügter Text direkt in diesem Element (ohne Kinder).</summary>
    property Text: string read FText;
    property ChildCount: Integer read GetChildCount;
    property Children[AIndex: Integer]: TXmlElement read GetChild; default;
  end;

  TXmlReader = class
  public
    /// <summary>Liest ein Dokument und liefert das Wurzelelement; der Aufrufer gibt es frei.</summary>
    class function Parse(const AText: string): TXmlElement; static;
  end;

implementation

uses
  System.StrUtils;

type
  TParser = class
  private
    FText: string;
    FPos: Integer;
    procedure Fail(const AMessage: string);
    function AtEnd: Boolean;
    function Peek(AOffset: Integer): Char; overload;
    function Peek: Char; overload;
    function StartsWith(const AValue: string): Boolean;
    procedure Expect(const AValue: string);
    procedure SkipSpace;
    procedure SkipUntil(const ATerminator: string);
    function ReadName: string;
    function CharReference(const AEntity: string): string;
    function EntityText(const AEntity: string): string;
    function Decode(const AValue: string): string;
    procedure ReadAttribute(AElement: TXmlElement);
    /// <summary>Liest die Attribute bis "&gt;" oder "/&gt;"; True bei "/&gt;" (Element ohne Inhalt).</summary>
    function ReadAttributes(AElement: TXmlElement): Boolean;
    procedure ReadClosingTag(AElement: TXmlElement);
    procedure ReadPlainText(ABuilder: TStringBuilder);
    procedure ReadContent(AElement: TXmlElement);
    procedure SkipMisc;
    function ParseElement: TXmlElement;
  public
    constructor Create(const AText: string);
    function ParseDocument: TXmlElement;
  end;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ':']) or (Ord(AChar) > 127);
end;

{ TXmlElement }

constructor TXmlElement.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FAttributeNames := TList<string>.Create;
  FAttributeValues := TList<string>.Create;
  FChildren := TObjectList<TXmlElement>.Create(True);
end;

destructor TXmlElement.Destroy;
begin
  FChildren.Free;
  FAttributeValues.Free;
  FAttributeNames.Free;
  inherited;
end;

function TXmlElement.Attribute(const AName: string): string;
var
  Index: Integer;
begin
  Index := FAttributeNames.IndexOf(AName);
  if Index < 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := FAttributeValues[Index];
  end;
end;

function TXmlElement.HasAttribute(const AName: string): Boolean;
begin
  Result := FAttributeNames.IndexOf(AName) >= 0;
end;

function TXmlElement.Find(const AName: string): TXmlElement;
var
  Child: TXmlElement;
begin
  for Child in FChildren do
  begin
    if Child.Name = AName then
    begin
      Exit(Child);
    end;
  end;
  Result := nil;
end;

function TXmlElement.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

function TXmlElement.GetChild(AIndex: Integer): TXmlElement;
begin
  Result := FChildren[AIndex];
end;

{ TParser }

constructor TParser.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  // BOM als Zeichen am Anfang überspringen.
  if (FText <> '') and (FText[1] = #$FEFF) then
  begin
    FPos := 2;
  end;
end;

procedure TParser.Fail(const AMessage: string);
begin
  raise EXmlError.CreateFmt('XML-Fehler an Position %d: %s', [FPos, AMessage]);
end;

function TParser.AtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TParser.Peek: Char;
begin
  Result := Peek(0);
end;

function TParser.Peek(AOffset: Integer): Char;
begin
  if FPos + AOffset <= Length(FText) then
  begin
    Result := FText[FPos + AOffset];
  end
  else
  begin
    Result := #0;
  end;
end;

function TParser.StartsWith(const AValue: string): Boolean;
begin
  Result := Copy(FText, FPos, Length(AValue)) = AValue;
end;

procedure TParser.Expect(const AValue: string);
begin
  if not StartsWith(AValue) then
  begin
    Fail(Format('"%s" erwartet', [AValue]));
  end;
  Inc(FPos, Length(AValue));
end;

procedure TParser.SkipSpace;
begin
  while (not AtEnd) and CharInSet(Peek, [' ', #9, #10, #13]) do
  begin
    Inc(FPos);
  end;
end;

procedure TParser.SkipUntil(const ATerminator: string);
var
  Found: Integer;
begin
  Found := Pos(ATerminator, FText, FPos);
  if Found = 0 then
  begin
    Fail(Format('"%s" fehlt', [ATerminator]));
  end;
  FPos := Found + Length(ATerminator);
end;

function TParser.ReadName: string;
var
  Start: Integer;
begin
  Start := FPos;
  while (not AtEnd) and IsNameChar(Peek) do
  begin
    Inc(FPos);
  end;
  if FPos = Start then
  begin
    Fail('Name erwartet');
  end;
  Result := Copy(FText, Start, FPos - Start);
end;

function TParser.CharReference(const AEntity: string): string;
var
  mCode: Integer;
begin
  if (Length(AEntity) > 1) and CharInSet(AEntity[2], ['x', 'X']) then
  begin
    mCode := StrToIntDef('$' + Copy(AEntity, 3, MaxInt), -1);
  end
  else
  begin
    mCode := StrToIntDef(Copy(AEntity, 2, MaxInt), -1);
  end;
  if (mCode < 0) or (mCode > $10FFFF) then
  begin
    Fail('Ungültige Zeichenreferenz &' + AEntity + ';');
  end;
  if mCode > $FFFF then
  begin
    Result := Char($D800 + ((mCode - $10000) shr 10)) + Char($DC00 + ((mCode - $10000) and $3FF));
  end
  else
  begin
    Result := Char(mCode);
  end;
end;

function TParser.EntityText(const AEntity: string): string;
begin
  case IndexStr(AEntity, ['amp', 'lt', 'gt', 'quot', 'apos']) of
    0:
      Result := '&';
    1:
      Result := '<';
    2:
      Result := '>';
    3:
      Result := '"';
    4:
      Result := '''';
  else
    if (AEntity = '') or (AEntity[1] <> '#') then
    begin
      Fail('Unbekannte Entity &' + AEntity + ';');
    end;
    Result := CharReference(AEntity);
  end;
end;

function TParser.Decode(const AValue: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mSemicolon: Integer;
begin
  if Pos('&', AValue) = 0 then
  begin
    Exit(AValue);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AValue) do
    begin
      if AValue[mIndex] <> '&' then
      begin
        mBuilder.Append(AValue[mIndex]);
        Inc(mIndex);
        Continue;
      end;
      mSemicolon := Pos(';', AValue, mIndex);
      if mSemicolon = 0 then
      begin
        Fail('";" nach "&" fehlt');
      end;
      mBuilder.Append(EntityText(Copy(AValue, mIndex + 1, mSemicolon - mIndex - 1)));
      mIndex := mSemicolon + 1;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

// Kommentare, Verarbeitungsanweisungen, DOCTYPE und Leerraum zwischen Elementen.
procedure TParser.SkipMisc;
begin
  while True do
  begin
    SkipSpace;
    if StartsWith('<!--') then
    begin
      SkipUntil('-->');
    end
    else if StartsWith('<?') then
    begin
      SkipUntil('?>');
    end
    else if StartsWith('<!DOCTYPE') then
    begin
      SkipUntil('>');
    end
    else
    begin
      Exit;
    end;
  end;
end;

procedure TParser.ReadAttribute(AElement: TXmlElement);
var
  mName: string;
  mQuote: Char;
  mStart: Integer;
begin
  mName := ReadName;
  SkipSpace;
  Expect('=');
  SkipSpace;
  mQuote := Peek;
  if not CharInSet(mQuote, ['"', '''']) then
  begin
    Fail('Anführungszeichen erwartet');
  end;
  Inc(FPos);
  mStart := FPos;
  while (not AtEnd) and (Peek <> mQuote) do
  begin
    Inc(FPos);
  end;
  if AtEnd then
  begin
    Fail('Attributwert nicht abgeschlossen');
  end;
  AElement.FAttributeNames.Add(mName);
  AElement.FAttributeValues.Add(Decode(Copy(FText, mStart, FPos - mStart)));
  Inc(FPos);
end;

function TParser.ReadAttributes(AElement: TXmlElement): Boolean;
begin
  SkipSpace;
  while not StartsWith('/>') and (Peek <> '>') do
  begin
    ReadAttribute(AElement);
    SkipSpace;
  end;
  Result := Peek <> '>';
  Inc(FPos, 1 + Ord(Result));
end;

procedure TParser.ReadClosingTag(AElement: TXmlElement);
var
  mName: string;
begin
  Inc(FPos, 2);
  mName := ReadName;
  if mName <> AElement.Name then
  begin
    Fail(Format('</%s> erwartet, </%s> gefunden', [AElement.Name, mName]));
  end;
  SkipSpace;
  Expect('>');
end;

procedure TParser.ReadPlainText(ABuilder: TStringBuilder);
var
  mStart: Integer;
begin
  mStart := FPos;
  while (not AtEnd) and (Peek <> '<') do
  begin
    Inc(FPos);
  end;
  ABuilder.Append(Decode(Copy(FText, mStart, FPos - mStart)));
end;

procedure TParser.ReadContent(AElement: TXmlElement);
var
  mBuilder: TStringBuilder;
  mStart: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    while not StartsWith('</') do
    begin
      if AtEnd then
      begin
        Fail(Format('</%s> fehlt', [AElement.Name]));
      end;
      if StartsWith('<!--') then
      begin
        SkipUntil('-->');
      end
      else if StartsWith('<![CDATA[') then
      begin
        Inc(FPos, 9);
        mStart := FPos;
        SkipUntil(']]>');
        mBuilder.Append(Copy(FText, mStart, FPos - 3 - mStart));
      end
      else if StartsWith('<?') then
      begin
        SkipUntil('?>');
      end
      else if Peek = '<' then
      begin
        AElement.FChildren.Add(ParseElement);
      end
      else
      begin
        ReadPlainText(mBuilder);
      end;
    end;
    ReadClosingTag(AElement);
    AElement.FText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TParser.ParseElement: TXmlElement;
begin
  Expect('<');
  Result := TXmlElement.Create(ReadName);
  try
    if not ReadAttributes(Result) then
    begin
      ReadContent(Result);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseDocument: TXmlElement;
begin
  SkipMisc;
  if Peek <> '<' then
  begin
    Fail('Wurzelelement erwartet');
  end;
  Result := ParseElement;
  try
    SkipMisc;
    if not AtEnd then
    begin
      Fail('Inhalt hinter dem Wurzelelement');
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TXmlReader }

class function TXmlReader.Parse(const AText: string): TXmlElement;
var
  Parser: TParser;
begin
  Parser := TParser.Create(AText);
  try
    Result := Parser.ParseDocument;
  finally
    Parser.Free;
  end;
end;

end.
