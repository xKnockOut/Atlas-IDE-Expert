unit BDLsp.Common.Dfm.Parser;

// Parser für Text-DFMs und -FMXs (#44): object/inherited/inline mit Namen,
// Klasse und optionalem Index ([2]), Properties mit Punkten im Namen,
// Werte aller Arten: Zahlen, Bezeichner, Strings mit #-Zeichen und "+" über
// Zeilen, Mengen [..], Listen (..), Binärdaten {..} und Collections <item .. end>.
// Fehlertolerant: Unerwartetes wird gemeldet und bis zum Zeilenende übersprungen.

interface

uses
  System.SysUtils,
  BDLsp.Common.Dfm.Contract;

type
  TDfmParser = class
  public
    /// <summary>Baum der Datei. Der Aufrufer übernimmt das Objekt.</summary>
    class function Parse(const AText: string): TDfmDocument; static;
    /// <summary>Ist AFileName eine Formulardatei (.dfm, .fmx, .lfm)?</summary>
    class function IsFormFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract;

const
  /// <summary>Schutz vor Stapelüberlauf bei kaputten Dateien.</summary>
  MaxDepth = 256;

type
  TScanner = class
  private
    FText: string;
    FIndex: Integer;
    FLine: Integer;
    FColumn: Integer;
    FErrors: TList<TDfmError>;
    FDepth: Integer;
    function Current: Char;
    function AtEnd: Boolean;
    procedure Advance;
    procedure SkipBlanks;
    function Position: TTextPosition;
    procedure Error(const AMessage: string);
    procedure SkipLine;
    function PeekWord: string;
    function ReadWord: string;
    function ReadQualifiedName: string;
    procedure ReadString;
    procedure ReadBracketed(AOpen, AClose: Char);
    procedure ReadCollection(AOwner: TDfmObject);
    procedure ReadValue(AOwner: TDfmObject);
    procedure ReadBody(AObject: TDfmObject; const AEndWord: string);
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function ReadObject: TDfmObject;
  end;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ TScanner }

constructor TScanner.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FIndex := 1;
  FErrors := TList<TDfmError>.Create;
end;

destructor TScanner.Destroy;
begin
  FErrors.Free;
  inherited;
end;

function TScanner.AtEnd: Boolean;
begin
  Result := FIndex > Length(FText);
end;

function TScanner.Current: Char;
begin
  if AtEnd then
    Result := #0
  else
    Result := FText[FIndex];
end;

procedure TScanner.Advance;
begin
  if AtEnd then
    Exit;
  if FText[FIndex] = #10 then
  begin
    Inc(FLine);
    FColumn := 0;
  end
  else if FText[FIndex] <> #13 then
    Inc(FColumn);
  Inc(FIndex);
end;

procedure TScanner.SkipBlanks;
begin
  while not AtEnd and CharInSet(Current, [' ', #9, #10, #13, #12]) do
    Advance;
end;

function TScanner.Position: TTextPosition;
begin
  Result := TTextPosition.Create(FLine, FColumn);
end;

procedure TScanner.Error(const AMessage: string);
var
  Item: TDfmError;
begin
  Item.Position := Position;
  Item.Message := AMessage;
  FErrors.Add(Item);
end;

procedure TScanner.SkipLine;
begin
  while not AtEnd and (Current <> #10) do
    Advance;
end;

function TScanner.PeekWord: string;
var
  Index: Integer;
begin
  Index := FIndex;
  while (Index <= Length(FText)) and IsWordChar(FText[Index]) do
    Inc(Index);
  Result := LowerCase(Copy(FText, FIndex, Index - FIndex));
end;

function TScanner.ReadWord: string;
var
  Start: Integer;
begin
  Start := FIndex;
  while not AtEnd and IsWordChar(Current) do
    Advance;
  Result := Copy(FText, Start, FIndex - Start);
end;

function TScanner.ReadQualifiedName: string;
var
  Start: Integer;
begin
  Start := FIndex;
  while not AtEnd and (IsWordChar(Current) or (Current = '.')) do
    Advance;
  Result := Copy(FText, Start, FIndex - Start);
end;

procedure TScanner.ReadString;
begin
  // Folge aus 'Text' und #13 bzw. #$0D, mit "+" auch über Zeilen.
  repeat
    while not AtEnd and CharInSet(Current, ['''', '#']) do
      if Current = '''' then
      begin
        Advance;
        while not AtEnd and (Current <> #10) do
        begin
          if Current = '''' then
          begin
            Advance;
            if Current <> '''' then
              Break;
          end;
          Advance;
        end;
      end
      else
      begin
        Advance;
        while not AtEnd and (IsWordChar(Current) or (Current = '$')) do
          Advance;
      end;
    // "+" am Zeilenende verbindet mit der nächsten Zeile.
    if Current = ' ' then
    begin
      while Current = ' ' do
        Advance;
    end;
    if Current <> '+' then
      Break;
    Advance;
    SkipBlanks;
  until not CharInSet(Current, ['''', '#']);
end;

procedure TScanner.ReadBracketed(AOpen, AClose: Char);
begin
  // ( 'a' 'b' ), [fsBold, fsItalic], { 0A0B }: bis zur passenden Klammer, Strings überspringen.
  Advance;
  while not AtEnd and (Current <> AClose) do
  begin
    if CharInSet(Current, ['''', '#']) and (AOpen <> '{') then
      ReadString
    else if (Current = '(') and (AOpen = '(') then
      ReadBracketed('(', ')')
    else
      Advance;
  end;
  if AtEnd then
    Error(Format('"%s" fehlt', [AClose]))
  else
    Advance;
end;

procedure TScanner.ReadCollection(AOwner: TDfmObject);
var
  Item: TDfmObject;
begin
  // < item ... end item ... end >
  Advance;
  SkipBlanks;
  while not AtEnd and (Current <> '>') do
  begin
    if PeekWord = 'item' then
    begin
      Item := TDfmObject.Create;
      AOwner.Children.Add(Item);
      Item.Kind := TDfmObjectKind.Item;
      Item.Range.StartPos := Position;
      Item.NameRange.StartPos := Position;
      Item.Name := ReadWord;
      Item.NameRange.EndPos := Position;
      ReadBody(Item, 'end');
    end
    else
    begin
      Error('"item" oder ">" erwartet');
      SkipLine;
    end;
    SkipBlanks;
  end;
  if AtEnd then
    Error('">" fehlt')
  else
    Advance;
end;

procedure TScanner.ReadValue(AOwner: TDfmObject);
begin
  case Current of
    '''', '#':
      ReadString;
    '(':
      ReadBracketed('(', ')');
    '[':
      ReadBracketed('[', ']');
    '{':
      ReadBracketed('{', '}');
    '<':
      ReadCollection(AOwner);
  else
    // Zahl, Bezeichner, True/False, -1, 1.5E2 ...
    while not AtEnd and not CharInSet(Current, [#10, #13]) do
      Advance;
  end;
end;

procedure TScanner.ReadBody(AObject: TDfmObject; const AEndWord: string);
var
  Word: string;
  Item: TDfmProperty;
  Child: TDfmObject;
  Start: Integer;
begin
  Inc(FDepth);
  try
    while True do
    begin
      SkipBlanks;
      if AtEnd then
      begin
        Error('"end" fehlt');
        AObject.Range.EndPos := Position;
        Exit;
      end;
      Word := PeekWord;
      if Word = AEndWord then
      begin
        ReadWord;
        AObject.Range.EndPos := Position;
        Exit;
      end;
      if (Word = 'object') or (Word = 'inherited') or (Word = 'inline') then
      begin
        if FDepth >= MaxDepth then
        begin
          Error('Zu tief verschachtelt');
          SkipLine;
          Continue;
        end;
        Child := ReadObject;
        if Child <> nil then
          AObject.Children.Add(Child);
        Continue;
      end;
      if not (IsWordChar(Current)) then
      begin
        Error('Property oder "end" erwartet');
        Advance;
        SkipLine;
        Continue;
      end;
      Item := Default(TDfmProperty);
      Item.NameRange.StartPos := Position;
      Item.Name := ReadQualifiedName;
      Item.NameRange.EndPos := Position;
      while CharInSet(Current, [' ', #9]) do
        Advance;
      if Current <> '=' then
      begin
        Error(Format('"=" nach "%s" erwartet', [Item.Name]));
        SkipLine;
        Continue;
      end;
      Advance;
      while CharInSet(Current, [' ', #9]) do
        Advance;
      Item.ValueRange.StartPos := Position;
      Start := FIndex;
      ReadValue(AObject);
      Item.ValueRange.EndPos := Position;
      Item.Value := TrimRight(Copy(FText, Start, FIndex - Start));
      AObject.Properties := AObject.Properties + [Item];
    end;
  finally
    Dec(FDepth);
  end;
end;

function TScanner.ReadObject: TDfmObject;
var
  Word: string;
  First: string;
  FirstRange: TTextRange;
begin
  SkipBlanks;
  Result := TDfmObject.Create;
  try
    Result.Range.StartPos := Position;
    Word := LowerCase(ReadWord);
    if Word = 'inherited' then
      Result.Kind := TDfmObjectKind.Inherited_
    else if Word = 'inline' then
      Result.Kind := TDfmObjectKind.Inline_
    else
      Result.Kind := TDfmObjectKind.Object_;
    while CharInSet(Current, [' ', #9]) do
      Advance;
    FirstRange.StartPos := Position;
    First := ReadQualifiedName;
    FirstRange.EndPos := Position;
    while CharInSet(Current, [' ', #9]) do
      Advance;
    if Current = ':' then
    begin
      // object Name: TKlasse
      Result.Name := First;
      Result.NameRange := FirstRange;
      Advance;
      while CharInSet(Current, [' ', #9]) do
        Advance;
      Result.TypeRange.StartPos := Position;
      Result.TypeName := ReadQualifiedName;
      Result.TypeRange.EndPos := Position;
    end
    else
    begin
      // object TKlasse (ohne Namen)
      Result.TypeName := First;
      Result.TypeRange := FirstRange;
      Result.NameRange := FirstRange;
    end;
    if Result.TypeName = '' then
      Error('Klassenname erwartet');
    // Optionaler Index: [2]
    while CharInSet(Current, [' ', #9]) do
      Advance;
    if Current = '[' then
      ReadBracketed('[', ']');
    ReadBody(Result, 'end');
  except
    Result.Free;
    raise;
  end;
end;

{ TDfmParser }

class function TDfmParser.IsFormFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dfm') or (Extension = '.fmx') or (Extension = '.lfm');
end;

class function TDfmParser.Parse(const AText: string): TDfmDocument;
var
  Scanner: TScanner;
  Word: string;
begin
  Result := TDfmDocument.Create;
  Scanner := TScanner.Create(AText);
  try
    Scanner.SkipBlanks;
    Word := Scanner.PeekWord;
    if (Word = 'object') or (Word = 'inherited') or (Word = 'inline') then
      Result.Root := Scanner.ReadObject
    else if not Scanner.AtEnd then
      Scanner.Error('"object" erwartet (binäre DFM?)');
    Result.Errors := Scanner.FErrors.ToArray;
  finally
    Scanner.Free;
  end;
end;

end.
