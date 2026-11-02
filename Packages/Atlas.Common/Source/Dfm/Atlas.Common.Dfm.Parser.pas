unit Atlas.Common.Dfm.Parser;

// Parser für Text-DFMs und -FMXs (#44): object/inherited/inline mit Namen,
// Klasse und optionalem Index ([2]), Properties mit Punkten im Namen,
// Werte aller Arten: Zahlen, Bezeichner, Strings mit #-Zeichen und "+" über
// Zeilen (auch erst ab der Zeile nach "=", #1235), Mengen [..], Listen (..),
// Binärdaten {..} und Collections <item .. end>.
// Fehlertolerant: Unerwartetes wird gemeldet und bis zum Zeilenende übersprungen.
// Binäre Formulare (TPF0) werden vorher im Speicher in Text umgewandelt (#122);
// die Bereiche beziehen sich dann auf den umgewandelten Text.

interface

uses
  System.SysUtils,
  Atlas.Common.Dfm.Contract;

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
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.BinaryForm,
  Atlas.Text.Chars;

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
  begin
    Result := #0;
  end
  else
  begin
    Result := FText[FIndex];
  end;
end;

procedure TScanner.Advance;
begin
  if AtEnd then
  begin
    Exit;
  end;
  if FText[FIndex] = #10 then
  begin
    Inc(FLine);
    FColumn := 0;
  end
  else if FText[FIndex] <> #13 then
  begin
    Inc(FColumn);
  end;
  Inc(FIndex);
end;

procedure TScanner.SkipBlanks;
begin
  while not AtEnd and CharInSet(Current, [' ', #9, #10, #13, #12]) do
  begin
    Advance;
  end;
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
  begin
    Advance;
  end;
end;

function TScanner.PeekWord: string;
var
  Index: Integer;
begin
  Index := FIndex;
  while (Index <= Length(FText)) and TTextChars.IsAsciiIdentChar(FText[Index]) do
  begin
    Inc(Index);
  end;
  Result := LowerCase(Copy(FText, FIndex, Index - FIndex));
end;

function TScanner.ReadWord: string;
var
  Start: Integer;
begin
  Start := FIndex;
  while not AtEnd and TTextChars.IsAsciiIdentChar(Current) do
  begin
    Advance;
  end;
  Result := Copy(FText, Start, FIndex - Start);
end;

function TScanner.ReadQualifiedName: string;
var
  Start: Integer;
begin
  Start := FIndex;
  while not AtEnd and (TTextChars.IsAsciiIdentChar(Current) or (Current = '.')) do
  begin
    Advance;
  end;
  Result := Copy(FText, Start, FIndex - Start);
end;

procedure TScanner.ReadString;
begin
  // Folge aus 'Text' und #13 bzw. #$0D, mit "+" auch über Zeilen.
  repeat
    while not AtEnd and CharInSet(Current, ['''', '#']) do
    begin
      if Current = '''' then
      begin
        Advance;
        while not AtEnd and (Current <> #10) do
        begin
          if Current = '''' then
          begin
            Advance;
            if Current <> '''' then
            begin
              Break;
            end;
          end;
          Advance;
        end;
      end
      else
      begin
        Advance;
        while not AtEnd and (TTextChars.IsAsciiIdentChar(Current) or (Current = '$')) do
        begin
          Advance;
        end;
      end;
    end;
    // "+" am Zeilenende verbindet mit der nächsten Zeile.
    if Current = ' ' then
    begin
      while Current = ' ' do
      begin
        Advance;
      end;
    end;
    if Current <> '+' then
    begin
      Break;
    end;
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
    begin
      ReadString;
    end
    else if (Current = '(') and (AOpen = '(') then
    begin
      ReadBracketed('(', ')');
    end
    else
    begin
      Advance;
    end;
  end;
  if AtEnd then
  begin
    Error(Format('"%s" fehlt', [AClose]));
  end
  else
  begin
    Advance;
  end;
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
  begin
    Error('">" fehlt');
  end
  else
  begin
    Advance;
  end;
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
    begin
      Advance;
    end;
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
        begin
          AObject.Children.Add(Child);
        end;
        Continue;
      end;
      if not (TTextChars.IsAsciiIdentChar(Current)) then
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
      begin
        Advance;
      end;
      if Current <> '=' then
      begin
        Error(Format('"=" nach "%s" erwartet', [Item.Name]));
        SkipLine;
        Continue;
      end;
      Advance;
      while CharInSet(Current, [' ', #9]) do
      begin
        Advance;
      end;
      // Lange Strings schreibt Delphi in die nächste Zeile ("Hint = " und darunter "'Bla'#123 +", #1235).
      if CharInSet(Current, [#13, #10]) then
      begin
        SkipBlanks;
      end;
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
    begin
      Result.Kind := TDfmObjectKind.Inherited_;
    end
    else if Word = 'inline' then
    begin
      Result.Kind := TDfmObjectKind.Inline_;
    end
    else
    begin
      Result.Kind := TDfmObjectKind.Object_;
    end;
    while CharInSet(Current, [' ', #9]) do
    begin
      Advance;
    end;
    FirstRange.StartPos := Position;
    First := ReadQualifiedName;
    FirstRange.EndPos := Position;
    while CharInSet(Current, [' ', #9]) do
    begin
      Advance;
    end;
    if Current = ':' then
    begin
      // object Name: TKlasse
      Result.Name := First;
      Result.NameRange := FirstRange;
      Advance;
      while CharInSet(Current, [' ', #9]) do
      begin
        Advance;
      end;
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
    begin
      Error('Klassenname erwartet');
    end;
    // Optionaler Index: [2]
    while CharInSet(Current, [' ', #9]) do
    begin
      Advance;
    end;
    if Current = '[' then
    begin
      ReadBracketed('[', ']');
    end;
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
  Word, Text: string;
begin
  Result := TDfmDocument.Create;
  Text := AText;
  if (StartsStr('TPF0', AText) or StartsStr(#$FF#$0A#$00, AText)) and
    not TDfmBinary.FromDecodedText(AText, Text) then
  begin
    Text := AText;
  end;
  Scanner := TScanner.Create(Text);
  try
    Scanner.SkipBlanks;
    Word := Scanner.PeekWord;
    if (Word = 'object') or (Word = 'inherited') or (Word = 'inline') then
    begin
      Result.Root := Scanner.ReadObject;
    end
    else if not Scanner.AtEnd then
    begin
      Scanner.Error('"object" erwartet (binäre DFM?)');
    end;
    Result.Errors := Scanner.FErrors.ToArray;
  finally
    Scanner.Free;
  end;
end;

end.
