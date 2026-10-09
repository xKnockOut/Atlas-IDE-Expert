unit Argus.Common.Projects.Internals.Xml;

// Kleiner XML-Leser für Projektdateien (.dproj, .groupproj). Xml.XMLDoc
// setzt unter Windows auf MSXML und darf in Argus.Common nicht verwendet
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

type
  TParser = class
  private
    FText: string;
    FPos: Integer;
    procedure Fail(const AMessage: string);
    function AtEnd: Boolean;
    function Peek(AOffset: Integer = 0): Char;
    function StartsWith(const AValue: string): Boolean;
    procedure Expect(const AValue: string);
    procedure SkipSpace;
    procedure SkipUntil(const ATerminator: string);
    function ReadName: string;
    function Decode(const AValue: string): string;
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
    Result := ''
  else
    Result := FAttributeValues[Index];
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
    if Child.Name = AName then
      Exit(Child);
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
    FPos := 2;
end;

procedure TParser.Fail(const AMessage: string);
begin
  raise EXmlError.CreateFmt('XML-Fehler an Position %d: %s', [FPos, AMessage]);
end;

function TParser.AtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TParser.Peek(AOffset: Integer): Char;
begin
  if FPos + AOffset <= Length(FText) then
    Result := FText[FPos + AOffset]
  else
    Result := #0;
end;

function TParser.StartsWith(const AValue: string): Boolean;
begin
  Result := Copy(FText, FPos, Length(AValue)) = AValue;
end;

procedure TParser.Expect(const AValue: string);
begin
  if not StartsWith(AValue) then
    Fail(Format('"%s" erwartet', [AValue]));
  Inc(FPos, Length(AValue));
end;

procedure TParser.SkipSpace;
begin
  while (not AtEnd) and CharInSet(Peek, [' ', #9, #10, #13]) do
    Inc(FPos);
end;

procedure TParser.SkipUntil(const ATerminator: string);
var
  Found: Integer;
begin
  Found := Pos(ATerminator, FText, FPos);
  if Found = 0 then
    Fail(Format('"%s" fehlt', [ATerminator]));
  FPos := Found + Length(ATerminator);
end;

function TParser.ReadName: string;
var
  Start: Integer;
begin
  Start := FPos;
  while (not AtEnd) and IsNameChar(Peek) do
    Inc(FPos);
  if FPos = Start then
    Fail('Name erwartet');
  Result := Copy(FText, Start, FPos - Start);
end;

function TParser.Decode(const AValue: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Semicolon: Integer;
  Entity: string;
  Code: Integer;
begin
  if Pos('&', AValue) = 0 then
    Exit(AValue);
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AValue) do
    begin
      if AValue[Index] <> '&' then
      begin
        Builder.Append(AValue[Index]);
        Inc(Index);
        Continue;
      end;
      Semicolon := Pos(';', AValue, Index);
      if Semicolon = 0 then
        Fail('";" nach "&" fehlt');
      Entity := Copy(AValue, Index + 1, Semicolon - Index - 1);
      if Entity = 'amp' then
        Builder.Append('&')
      else if Entity = 'lt' then
        Builder.Append('<')
      else if Entity = 'gt' then
        Builder.Append('>')
      else if Entity = 'quot' then
        Builder.Append('"')
      else if Entity = 'apos' then
        Builder.Append('''')
      else if (Entity <> '') and (Entity[1] = '#') then
      begin
        if (Length(Entity) > 1) and CharInSet(Entity[2], ['x', 'X']) then
          Code := StrToIntDef('$' + Copy(Entity, 3, MaxInt), -1)
        else
          Code := StrToIntDef(Copy(Entity, 2, MaxInt), -1);
        if (Code < 0) or (Code > $10FFFF) then
          Fail('Ungültige Zeichenreferenz &' + Entity + ';');
        if Code > $FFFF then
          Builder.Append(Char($D800 + ((Code - $10000) shr 10))).Append(Char($DC00 + ((Code - $10000) and $3FF)))
        else
          Builder.Append(Char(Code));
      end
      else
        Fail('Unbekannte Entity &' + Entity + ';');
      Index := Semicolon + 1;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

// Kommentare, Verarbeitungsanweisungen, DOCTYPE und Leerraum zwischen Elementen.
procedure TParser.SkipMisc;
begin
  while True do
  begin
    SkipSpace;
    if StartsWith('<!--') then
      SkipUntil('-->')
    else if StartsWith('<?') then
      SkipUntil('?>')
    else if StartsWith('<!DOCTYPE') then
      SkipUntil('>')
    else
      Exit;
  end;
end;

function TParser.ParseElement: TXmlElement;
var
  Name: string;
  AttributeName: string;
  Quote: Char;
  Start: Integer;
  TextBuilder: TStringBuilder;
begin
  Expect('<');
  Result := TXmlElement.Create(ReadName);
  try
    while True do
    begin
      SkipSpace;
      if StartsWith('/>') then
      begin
        Inc(FPos, 2);
        Exit;
      end;
      if Peek = '>' then
      begin
        Inc(FPos);
        Break;
      end;
      AttributeName := ReadName;
      SkipSpace;
      Expect('=');
      SkipSpace;
      Quote := Peek;
      if not CharInSet(Quote, ['"', '''']) then
        Fail('Anführungszeichen erwartet');
      Inc(FPos);
      Start := FPos;
      while (not AtEnd) and (Peek <> Quote) do
        Inc(FPos);
      if AtEnd then
        Fail('Attributwert nicht abgeschlossen');
      Result.FAttributeNames.Add(AttributeName);
      Result.FAttributeValues.Add(Decode(Copy(FText, Start, FPos - Start)));
      Inc(FPos);
    end;

    TextBuilder := TStringBuilder.Create;
    try
      while True do
      begin
        if AtEnd then
          Fail(Format('</%s> fehlt', [Result.Name]));
        if StartsWith('</') then
        begin
          Inc(FPos, 2);
          Name := ReadName;
          if Name <> Result.Name then
            Fail(Format('</%s> erwartet, </%s> gefunden', [Result.Name, Name]));
          SkipSpace;
          Expect('>');
          Break;
        end
        else if StartsWith('<!--') then
          SkipUntil('-->')
        else if StartsWith('<![CDATA[') then
        begin
          Inc(FPos, 9);
          Start := FPos;
          SkipUntil(']]>');
          TextBuilder.Append(Copy(FText, Start, FPos - 3 - Start));
        end
        else if StartsWith('<?') then
          SkipUntil('?>')
        else if Peek = '<' then
          Result.FChildren.Add(ParseElement)
        else
        begin
          Start := FPos;
          while (not AtEnd) and (Peek <> '<') do
            Inc(FPos);
          TextBuilder.Append(Decode(Copy(FText, Start, FPos - Start)));
        end;
      end;
      Result.FText := TextBuilder.ToString;
    finally
      TextBuilder.Free;
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
    Fail('Wurzelelement erwartet');
  Result := ParseElement;
  try
    SkipMisc;
    if not AtEnd then
      Fail('Inhalt hinter dem Wurzelelement');
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
