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
  Atlas.Text.Chars,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDfmParserText = (Missing, ItemOrExpected, Missing2, ExpectedAfter, PropertyOrEndExpected, EndMissing,
    ObjectExpectedBinaryDFM, NestedTooDeeply, ClassNameExpected);

const
  cTexts: array[TDfmParserText] of TAtlasText = (
    (De: '"%s" fehlt'; En: '"%s" missing'),
    (De: '"item" oder ">" erwartet'; En: '"item" or ">" expected'),
    (De: '">" fehlt'; En: '">" missing'),
    (De: '"=" nach "%s" erwartet'; En: '"=" expected after "%s"'),
    (De: 'Property oder "end" erwartet'; En: 'Property or "end" expected'),
    (De: '"end" fehlt'; En: '"end" missing'),
    (De: '"object" erwartet (binäre DFM?)'; En: '"object" expected (binary DFM?)'),
    (De: 'Zu tief verschachtelt'; En: 'Nested too deeply'),
    (De: 'Klassenname erwartet'; En: 'Class name expected'));

{$SCOPEDENUMS OFF}

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
    /// <summary>Leerzeichen und Tabulatoren, keine Zeilenumbrüche.</summary>
    procedure SkipSpaces;
    procedure ReadQuoted;
    procedure ReadCharCode;
    procedure ReadString;
    procedure ReadBracketed(AOpen, AClose: Char);
    procedure ReadCollection(AOwner: TDfmObject);
    procedure ReadValue(AOwner: TDfmObject);
    procedure ReadChild(AObject: TDfmObject);
    procedure ReadProperty(AObject: TDfmObject);
    procedure ReadBody(AObject: TDfmObject; const AEndWord: string);
    procedure ReadObjectNames(AObject: TDfmObject);
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

procedure TScanner.SkipSpaces;
begin
  while CharInSet(Current, [' ', #9]) do
  begin
    Advance;
  end;
end;

procedure TScanner.ReadQuoted;
begin
  // 'Text' mit '' für ein Hochkomma, höchstens bis zum Zeilenende.
  Advance;
  while not AtEnd and (Current <> #10) do
  begin
    if Current = '''' then
    begin
      Advance;
      if Current <> '''' then
      begin
        Exit;
      end;
    end;
    Advance;
  end;
end;

procedure TScanner.ReadCharCode;
begin
  // #13 bzw. #$0D
  Advance;
  while not AtEnd and (TTextChars.IsAsciiIdentChar(Current) or (Current = '$')) do
  begin
    Advance;
  end;
end;

procedure TScanner.ReadString;
begin
  // Folge aus 'Text' und #13 bzw. #$0D, mit "+" auch über Zeilen.
  repeat
    while not AtEnd and CharInSet(Current, ['''', '#']) do
    begin
      if Current = '''' then
      begin
        ReadQuoted;
      end
      else
      begin
        ReadCharCode;
      end;
    end;
    // "+" am Zeilenende verbindet mit der nächsten Zeile.
    while Current = ' ' do
    begin
      Advance;
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
    Error(cTexts[TDfmParserText.Missing].Fmt([AClose]));
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
      Error(cTexts[TDfmParserText.ItemOrExpected].Text);
      SkipLine;
    end;
    SkipBlanks;
  end;
  if AtEnd then
  begin
    Error(cTexts[TDfmParserText.Missing2].Text);
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

procedure TScanner.ReadChild(AObject: TDfmObject);
var
  mChild: TDfmObject;
begin
  if FDepth >= MaxDepth then
  begin
    Error(cTexts[TDfmParserText.NestedTooDeeply].Text);
    SkipLine;
    Exit;
  end;
  mChild := ReadObject;
  if mChild <> nil then
  begin
    AObject.Children.Add(mChild);
  end;
end;

procedure TScanner.ReadProperty(AObject: TDfmObject);
var
  mItem: TDfmProperty;
  mStart: Integer;
begin
  mItem := Default(TDfmProperty);
  mItem.NameRange.StartPos := Position;
  mItem.Name := ReadQualifiedName;
  mItem.NameRange.EndPos := Position;
  SkipSpaces;
  if Current <> '=' then
  begin
    Error(cTexts[TDfmParserText.ExpectedAfter].Fmt([mItem.Name]));
    SkipLine;
    Exit;
  end;
  Advance;
  SkipSpaces;
  // Lange Strings schreibt Delphi in die nächste Zeile ("Hint = " und darunter "'Bla'#123 +", #1235).
  if CharInSet(Current, [#13, #10]) then
  begin
    SkipBlanks;
  end;
  mItem.ValueRange.StartPos := Position;
  mStart := FIndex;
  ReadValue(AObject);
  mItem.ValueRange.EndPos := Position;
  mItem.Value := TrimRight(Copy(FText, mStart, FIndex - mStart));
  AObject.Properties := AObject.Properties + [mItem];
end;

procedure TScanner.ReadBody(AObject: TDfmObject; const AEndWord: string);
var
  mWord: string;
begin
  Inc(FDepth);
  try
    SkipBlanks;
    mWord := PeekWord;
    while not AtEnd and (mWord <> AEndWord) do
    begin
      if (mWord = 'object') or (mWord = 'inherited') or (mWord = 'inline') then
      begin
        ReadChild(AObject);
      end
      else if TTextChars.IsAsciiIdentChar(Current) then
      begin
        ReadProperty(AObject);
      end
      else
      begin
        Error(cTexts[TDfmParserText.PropertyOrEndExpected].Text);
        Advance;
        SkipLine;
      end;
      SkipBlanks;
      mWord := PeekWord;
    end;
    if AtEnd then
    begin
      Error(cTexts[TDfmParserText.EndMissing].Text);
    end
    else
    begin
      ReadWord;
    end;
    AObject.Range.EndPos := Position;
  finally
    Dec(FDepth);
  end;
end;

procedure TScanner.ReadObjectNames(AObject: TDfmObject);
var
  mFirst: string;
  mFirstRange: TTextRange;
begin
  SkipSpaces;
  mFirstRange.StartPos := Position;
  mFirst := ReadQualifiedName;
  mFirstRange.EndPos := Position;
  SkipSpaces;
  if Current = ':' then
  begin
    // object Name: TKlasse
    AObject.Name := mFirst;
    AObject.NameRange := mFirstRange;
    Advance;
    SkipSpaces;
    AObject.TypeRange.StartPos := Position;
    AObject.TypeName := ReadQualifiedName;
    AObject.TypeRange.EndPos := Position;
  end
  else
  begin
    // object TKlasse (ohne Namen)
    AObject.TypeName := mFirst;
    AObject.TypeRange := mFirstRange;
    AObject.NameRange := mFirstRange;
  end;
  if AObject.TypeName = '' then
  begin
    Error(cTexts[TDfmParserText.ClassNameExpected].Text);
  end;
end;

function TScanner.ReadObject: TDfmObject;
var
  mWord: string;
begin
  SkipBlanks;
  Result := TDfmObject.Create;
  try
    Result.Range.StartPos := Position;
    mWord := LowerCase(ReadWord);
    if mWord = 'inherited' then
    begin
      Result.Kind := TDfmObjectKind.Inherited_;
    end
    else if mWord = 'inline' then
    begin
      Result.Kind := TDfmObjectKind.Inline_;
    end
    else
    begin
      Result.Kind := TDfmObjectKind.Object_;
    end;
    ReadObjectNames(Result);
    // Optionaler Index: [2]
    SkipSpaces;
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
      Scanner.Error(cTexts[TDfmParserText.ObjectExpectedBinaryDFM].Text);
    end;
    Result.Errors := Scanner.FErrors.ToArray;
  finally
    Scanner.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Dfm.Parser', cTexts);

end.
