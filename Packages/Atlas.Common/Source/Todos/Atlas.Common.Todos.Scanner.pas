unit Atlas.Common.Todos.Scanner;

// Findet TODO-Einträge (#68) in den Kommentaren eines Quelltexts über den
// Lexer (#6): Strings, Direktiven und Code zählen nie. Ein Kommentar ist ein
// Eintrag, wenn sein erstes Wort eine Marke oder DONE ist und danach ein
// Leerzeichen, ein Doppelpunkt oder das Kommentarende folgt („TODO-Liste“
// und „TODOs“ sind keine Einträge). Das Format steht in
// Atlas.Common.Todos.Contract.
// Collect sammelt die Einträge aller Dateien eines Projekts; welche Dateien
// dazugehören, bestimmt der Aufrufer über das Projektmodell (#14).

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Todos.Contract;

type
  /// <summary>Text einer Datei (geöffnetes Dokument oder Platte); False, wenn sie fehlt.</summary>
  TTodoReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TTodoScanner = class
  public
    /// <summary>Inhalt eines Kommentar-Tokens ohne //, { } bzw. (* *); führende „/“ von /// fallen weg.</summary>
    class function CommentBody(const AComment: string): string; static;
    /// <summary>Eintrag aus dem Inhalt eines Kommentars (ohne Begrenzer); False, wenn keiner.
    /// AKeywords: Marken offener Einträge; DONE gilt immer.</summary>
    class function ParseBody(const ABody: string; const AKeywords: TArray<string>; out AEntry: TTodoEntry): Boolean;
      static;
    /// <summary>Einträge aus den Kommentaren in ATokens, in Textreihenfolge.</summary>
    class function FromTokens(const ATokens: TArray<TPascalToken>; const AKeywords: TArray<string>):
      TArray<TTodoEntry>; static;
    /// <summary>Einträge in AText mit den Marken AKeywords.</summary>
    class function ForText(const AText: string; const AKeywords: TArray<string>): TArray<TTodoEntry>; overload;
      static;
    /// <summary>Einträge in AText mit TODO und FIXME.</summary>
    class function ForText(const AText: string): TArray<TTodoEntry>; overload; static;
    /// <summary>Einträge aller Quelltexte (.pas, .dpr, .dpk) aus AFiles, doppelte nur einmal, Pfade relativ zu
    /// ARoot. Unlesbare Dateien und Dateien ohne Eintrag fehlen.</summary>
    class function Collect(const AFiles: TArray<string>; const ARoot: string; const AReadText: TTodoReadText;
      const AKeywords: TArray<string>): TArray<TFileTodos>; static;
    /// <summary>Nur die Einträge, die AFilter trifft; Dateien ohne solche fallen weg.</summary>
    class function Filter(const AFiles: TArray<TFileTodos>; const AFilter: TTodoFilter): TArray<TFileTodos>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Metrics.Collector;

function IsSpace(ACh: Char): Boolean;
begin
  Result := (ACh = ' ') or (ACh = #9) or (ACh = #10) or (ACh = #13);
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z']);
end;

/// <summary>Leerraum (auch Zeilenumbrüche) zu je einem Leerzeichen, außen ohne.</summary>
function Collapse(const AText: string): string;
var
  Index: Integer;
  Pending: Boolean;
begin
  Result := '';
  Pending := False;
  for Index := 1 to Length(AText) do
  begin
    if IsSpace(AText[Index]) then
    begin
      Pending := Result <> '';
    end
    else
    begin
      if Pending then
      begin
        Result := Result + ' ';
      end;
      Pending := False;
      Result := Result + AText[Index];
    end;
  end;
end;

function IsKeyword(const AWord: string; const AKeywords: TArray<string>): Boolean;
var
  Keyword: string;
begin
  for Keyword in AKeywords do
  begin
    if SameText(Trim(Keyword), AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Lesestelle im Inhalt eines Kommentars für ParseBody.</summary>
  TTodoBodyReader = record
    Text: string;
    Position: Integer;
    procedure SkipSpaces;
    /// <summary>Beginnt an AIndex eine Option (-o, -c)?</summary>
    function OptionAt(AIndex: Integer): Boolean;
    /// <summary>Liest Buchstaben (ALetters) bzw. Ziffern ab Position.</summary>
    function ReadLetters: string;
    function ReadDigits: string;
    /// <summary>Wert einer Option: in ' oder " bis zum gleichen Zeichen, sonst bis ":" oder zur nächsten Option.
    /// </summary>
    function ReadOptionValue: string;
    function AtEnd: Boolean;
    function Current: Char;
  end;

procedure TTodoBodyReader.SkipSpaces;
begin
  while not AtEnd and IsSpace(Current) do
  begin
    Inc(Position);
  end;
end;

function TTodoBodyReader.OptionAt(AIndex: Integer): Boolean;
begin
  Result := (AIndex < Length(Text)) and (Text[AIndex] = '-') and CharInSet(Text[AIndex + 1], ['o', 'O', 'c', 'C']);
end;

function TTodoBodyReader.ReadLetters: string;
var
  mStart: Integer;
begin
  mStart := Position;
  while not AtEnd and IsLetter(Current) do
  begin
    Inc(Position);
  end;
  Result := Copy(Text, mStart, Position - mStart);
end;

function TTodoBodyReader.ReadDigits: string;
var
  mStart: Integer;
begin
  mStart := Position;
  while not AtEnd and CharInSet(Current, ['0'..'9']) do
  begin
    Inc(Position);
  end;
  Result := Copy(Text, mStart, Position - mStart);
end;

function TTodoBodyReader.ReadOptionValue: string;
var
  mStart: Integer;
  mQuote: Char;
begin
  if not AtEnd and ((Current = '''') or (Current = '"')) then
  begin
    mQuote := Current;
    Inc(Position);
    mStart := Position;
    while not AtEnd and (Current <> mQuote) do
    begin
      Inc(Position);
    end;
    Result := Copy(Text, mStart, Position - mStart);
    if not AtEnd then
    begin
      Inc(Position);
    end;
    Exit;
  end;
  mStart := Position;
  while not AtEnd and (Current <> ':') and not (IsSpace(Current) and OptionAt(Position + 1)) do
  begin
    Inc(Position);
  end;
  Result := Copy(Text, mStart, Position - mStart);
end;

function TTodoBodyReader.AtEnd: Boolean;
begin
  Result := Position > Length(Text);
end;

function TTodoBodyReader.Current: Char;
begin
  Result := Text[Position];
end;

/// <summary>Liest die Marke am Anfang in AEntry (Keyword, Done); False, wenn keine Marke dasteht.</summary>
function ReadMarker(var AReader: TTodoBodyReader; const AKeywords: TArray<string>; var AEntry: TTodoEntry): Boolean;
var
  mWord: string;
begin
  AReader.SkipSpaces;
  mWord := UpperCase(AReader.ReadLetters);
  // Nach der Marke: Ende, Leerraum oder Doppelpunkt; sonst ist es ein gewöhnliches Wort.
  Result := (mWord <> '') and (AReader.AtEnd or IsSpace(AReader.Current) or (AReader.Current = ':'));
  if Result then
  begin
    AEntry.Done := mWord = TTodos.DoneKeyword;
    Result := AEntry.Done or IsKeyword(mWord, AKeywords);
  end;
  if Result then
  begin
    AEntry.Keyword := mWord;
  end;
end;

/// <summary>Optionen -oPerson -cKategorie, Werte mit Leerzeichen auch in ' oder ".</summary>
procedure ReadOptions(var AReader: TTodoBodyReader; var AEntry: TTodoEntry);
var
  mOption: Char;
  mValue: string;
begin
  while AReader.OptionAt(AReader.Position) do
  begin
    mOption := UpCase(AReader.Text[AReader.Position + 1]);
    Inc(AReader.Position, 2);
    mValue := Collapse(AReader.ReadOptionValue);
    if mOption = 'O' then
    begin
      AEntry.Owner := mValue;
    end
    else
    begin
      AEntry.Category := mValue;
    end;
    AReader.SkipSpaces;
  end;
end;

{ TTodoScanner }
class function TTodoScanner.CommentBody(const AComment: string): string;
var
  First, Last: Integer;
begin
  First := 1;
  Last := Length(AComment);
  if Copy(AComment, 1, 2) = '//' then
  begin
    First := 3;
    while (First <= Last) and (AComment[First] = '/') do
    begin
      Inc(First);
    end;
  end
  else if Copy(AComment, 1, 2) = '(*' then
  begin
    First := 3;
    if (Last >= 4) and (Copy(AComment, Last - 1, 2) = '*)') then
    begin
      Dec(Last, 2);
    end;
  end
  else if Copy(AComment, 1, 1) = '{' then
  begin
    First := 2;
    if (Last >= 2) and (AComment[Last] = '}') then
    begin
      Dec(Last);
    end;
  end;
  Result := Copy(AComment, First, Last - First + 1);
end;

class function TTodoScanner.ParseBody(const ABody: string; const AKeywords: TArray<string>;
  out AEntry: TTodoEntry): Boolean;
var
  mReader: TTodoBodyReader;
  mPriority: string;
begin
  AEntry := Default(TTodoEntry);
  mReader.Text := ABody;
  mReader.Position := 1;
  Result := ReadMarker(mReader, AKeywords, AEntry);
  if not Result then
  begin
    Exit;
  end;
  mReader.SkipSpaces;
  mPriority := mReader.ReadDigits;
  if mPriority <> '' then
  begin
    AEntry.Priority := StrToIntDef(mPriority, 0);
    mReader.SkipSpaces;
  end;
  ReadOptions(mReader, AEntry);
  if not mReader.AtEnd and (mReader.Current = ':') then
  begin
    Inc(mReader.Position);
  end;
  AEntry.Text := Collapse(Copy(ABody, mReader.Position, MaxInt));
end;

class function TTodoScanner.FromTokens(const ATokens: TArray<TPascalToken>;
  const AKeywords: TArray<string>): TArray<TTodoEntry>;
var
  Token: TPascalToken;
  Entry: TTodoEntry;
begin
  Result := nil;
  for Token in ATokens do
  begin
    if (Token.Kind = TPascalTokenKind.Comment) and ParseBody(CommentBody(Token.Text), AKeywords, Entry) then
    begin
      Entry.Range.StartPos := Token.StartPos;
      Entry.Range.EndPos := Token.EndPos;
      Result := Result + [Entry];
    end;
  end;
end;

class function TTodoScanner.ForText(const AText: string; const AKeywords: TArray<string>): TArray<TTodoEntry>;
begin
  Result := FromTokens(TPascalLexer.Tokenize(AText), AKeywords);
end;

class function TTodoScanner.ForText(const AText: string): TArray<TTodoEntry>;
begin
  Result := ForText(AText, TTodos.DefaultKeywords);
end;

class function TTodoScanner.Collect(const AFiles: TArray<string>; const ARoot: string;
  const AReadText: TTodoReadText; const AKeywords: TArray<string>): TArray<TFileTodos>;
var
  Seen: TDictionary<string, Boolean>;
  List: TList<TFileTodos>;
  FileName, Text: string;
  Entries: TArray<TTodoEntry>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  List := TList<TFileTodos>.Create;
  try
    for FileName in AFiles do
    begin
      if not TMetricsCollector.IsSource(FileName) or Seen.ContainsKey(UpperCase(FileName)) then
      begin
        Continue;
      end;
      Seen.Add(UpperCase(FileName), True);
      if not Assigned(AReadText) or not AReadText(FileName, Text) then
      begin
        Continue;
      end;
      Entries := ForText(Text, AKeywords);
      if Length(Entries) > 0 then
      begin
        List.Add(TFileTodos.Create(TMetricsCollector.RelativePath(ARoot, FileName), Entries));
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

class function TTodoScanner.Filter(const AFiles: TArray<TFileTodos>;
  const AFilter: TTodoFilter): TArray<TFileTodos>;
var
  FileItem, Kept: TFileTodos;
  Entry: TTodoEntry;
begin
  Result := nil;
  for FileItem in AFiles do
  begin
    Kept := FileItem;
    Kept.Entries := nil;
    for Entry in FileItem.Entries do
    begin
      if AFilter.Matches(FileItem, Entry) then
      begin
        Kept.Entries := Kept.Entries + [Entry];
      end;
    end;
    if Length(Kept.Entries) > 0 then
    begin
      Result := Result + [Kept];
    end;
  end;
end;

end.
