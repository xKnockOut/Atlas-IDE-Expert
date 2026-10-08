unit BDLsp.Common.Configuration.Internals.JsonTree;

// JSON-Leser mit Positionen, damit Fehler in delphi-lsp.json genau an der
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

type
  TReader = class
  private
    FText: string;
    FPos: Integer;
    procedure Fail(const AMessage: string);
    procedure SkipSpace;
    function ReadString: string;
    function ParseValue(ADepth: Integer): TJsonNode;
  public
    constructor Create(const AText: string);
    function Run: TJsonNode;
  end;

const
  MaxDepth = 64;

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
    FPos := 2;
end;

procedure TReader.Fail(const AMessage: string);
begin
  raise EJsonTreeError.Create(AMessage, FPos - 1);
end;

procedure TReader.SkipSpace;
var
  Close: Integer;
begin
  while FPos <= Length(FText) do
  begin
    if CharInSet(FText[FPos], [' ', #9, #10, #13]) then
      Inc(FPos)
    else if (FText[FPos] = '/') and (FPos < Length(FText)) and (FText[FPos + 1] = '/') then
    begin
      while (FPos <= Length(FText)) and not CharInSet(FText[FPos], [#10, #13]) do
        Inc(FPos);
    end
    else if (FText[FPos] = '/') and (FPos < Length(FText)) and (FText[FPos + 1] = '*') then
    begin
      Close := Pos('*/', FText, FPos + 2);
      if Close = 0 then
        Fail('Kommentar nicht abgeschlossen');
      FPos := Close + 2;
    end
    else
      Exit;
  end;
end;

function TReader.ReadString: string;
var
  Builder: TStringBuilder;
  Code: Integer;
begin
  // FPos steht auf dem öffnenden Anführungszeichen.
  Inc(FPos);
  Builder := TStringBuilder.Create;
  try
    while True do
    begin
      if FPos > Length(FText) then
        Fail('String nicht abgeschlossen');
      case FText[FPos] of
        '"':
          begin
            Inc(FPos);
            Break;
          end;
        #10, #13:
          Fail('Zeilenumbruch im String');
        '\':
          begin
            Inc(FPos);
            if FPos > Length(FText) then
              Fail('String nicht abgeschlossen');
            case FText[FPos] of
              '"', '\', '/': Builder.Append(FText[FPos]);
              'b': Builder.Append(#8);
              'f': Builder.Append(#12);
              'n': Builder.Append(#10);
              'r': Builder.Append(#13);
              't': Builder.Append(#9);
              'u':
                begin
                  Code := StrToIntDef('$' + Copy(FText, FPos + 1, 4), -1);
                  if (Code < 0) or (FPos + 4 > Length(FText)) then
                    Fail('Ungültige \u-Folge');
                  Builder.Append(Char(Code));
                  Inc(FPos, 4);
                end;
            else
              Fail('Ungültige Escape-Folge');
            end;
            Inc(FPos);
          end;
      else
        Builder.Append(FText[FPos]);
        Inc(FPos);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TReader.ParseValue(ADepth: Integer): TJsonNode;
var
  Start: Integer;
  Key: string;
  KeyStart: Integer;
  Word: string;
begin
  if ADepth > MaxDepth then
    Fail('Zu tief verschachtelt');
  SkipSpace;
  if FPos > Length(FText) then
    Fail('Wert erwartet');
  Start := FPos - 1;
  case FText[FPos] of
    '{':
      begin
        Result := TJsonNode.Create(TJsonKind.Object_, Start);
        try
          Inc(FPos);
          SkipSpace;
          while (FPos <= Length(FText)) and (FText[FPos] <> '}') do
          begin
            if FText[FPos] <> '"' then
              Fail('Schlüssel in Anführungszeichen erwartet');
            KeyStart := FPos - 1;
            Key := ReadString;
            SkipSpace;
            if (FPos > Length(FText)) or (FText[FPos] <> ':') then
              Fail('":" erwartet');
            Inc(FPos);
            Result.FKeys.Add(Key);
            Result.FKeyStarts.Add(KeyStart);
            Result.FItems.Add(ParseValue(ADepth + 1));
            SkipSpace;
            if (FPos <= Length(FText)) and (FText[FPos] = ',') then
            begin
              Inc(FPos);
              SkipSpace;
            end
            else if (FPos <= Length(FText)) and (FText[FPos] <> '}') then
              Fail('"," oder "}" erwartet');
          end;
          if FPos > Length(FText) then
            Fail('"}" fehlt');
          Inc(FPos);
          Result.FStop := FPos - 1;
        except
          Result.Free;
          raise;
        end;
      end;
    '[':
      begin
        Result := TJsonNode.Create(TJsonKind.Array_, Start);
        try
          Inc(FPos);
          SkipSpace;
          while (FPos <= Length(FText)) and (FText[FPos] <> ']') do
          begin
            Result.FItems.Add(ParseValue(ADepth + 1));
            SkipSpace;
            if (FPos <= Length(FText)) and (FText[FPos] = ',') then
            begin
              Inc(FPos);
              SkipSpace;
            end
            else if (FPos <= Length(FText)) and (FText[FPos] <> ']') then
              Fail('"," oder "]" erwartet');
          end;
          if FPos > Length(FText) then
            Fail('"]" fehlt');
          Inc(FPos);
          Result.FStop := FPos - 1;
        except
          Result.Free;
          raise;
        end;
      end;
    '"':
      begin
        Word := ReadString;
        Result := TJsonNode.Create(TJsonKind.String_, Start);
        Result.FValue := Word;
        Result.FStop := FPos - 1;
      end;
  else
    while (FPos <= Length(FText)) and CharInSet(FText[FPos], ['A'..'Z', 'a'..'z', '0'..'9', '-', '+', '.']) do
      Inc(FPos);
    Word := Copy(FText, Start + 1, FPos - 1 - Start);
    if Word = '' then
      Fail('Wert erwartet');
    if Word = 'null' then
      Result := TJsonNode.Create(TJsonKind.Null, Start)
    else if (Word = 'true') or (Word = 'false') then
      Result := TJsonNode.Create(TJsonKind.Boolean_, Start)
    else if CharInSet(Word[1], ['-', '0'..'9']) then
      Result := TJsonNode.Create(TJsonKind.Number, Start)
    else
      raise EJsonTreeError.Create(Format('Unbekannter Wert "%s"', [Word]), Start);
    Result.FValue := Word;
    Result.FStop := FPos - 1;
  end;
end;

function TReader.Run: TJsonNode;
begin
  Result := ParseValue(0);
  try
    SkipSpace;
    if FPos <= Length(FText) then
      Fail('Inhalt hinter dem Wert');
  except
    Result.Free;
    raise;
  end;
end;

{ TJsonTree }

class function TJsonTree.Parse(const AText: string): TJsonNode;
var
  Reader: TReader;
begin
  Reader := TReader.Create(AText);
  try
    Result := Reader.Run;
  finally
    Reader.Free;
  end;
end;

end.
