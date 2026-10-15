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
    if IsSpace(AText[Index]) then
      Pending := Result <> ''
    else
    begin
      if Pending then
        Result := Result + ' ';
      Pending := False;
      Result := Result + AText[Index];
    end;
end;

function IsKeyword(const AWord: string; const AKeywords: TArray<string>): Boolean;
var
  Keyword: string;
begin
  for Keyword in AKeywords do
    if SameText(Trim(Keyword), AWord) then
      Exit(True);
  Result := False;
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
      Inc(First);
  end
  else if Copy(AComment, 1, 2) = '(*' then
  begin
    First := 3;
    if (Last >= 4) and (Copy(AComment, Last - 1, 2) = '*)') then
      Dec(Last, 2);
  end
  else if Copy(AComment, 1, 1) = '{' then
  begin
    First := 2;
    if (Last >= 2) and (AComment[Last] = '}') then
      Dec(Last);
  end;
  Result := Copy(AComment, First, Last - First + 1);
end;

class function TTodoScanner.ParseBody(const ABody: string; const AKeywords: TArray<string>;
  out AEntry: TTodoEntry): Boolean;
var
  Position, Start, Len: Integer;
  Word, Value: string;
  Option, Quote: Char;

  procedure SkipSpaces;
  begin
    while (Position <= Len) and IsSpace(ABody[Position]) do
      Inc(Position);
  end;

  /// <summary>Beginnt an Index eine Option (-o, -c)?</summary>
  function OptionAt(AIndex: Integer): Boolean;
  begin
    Result := (AIndex < Len) and (ABody[AIndex] = '-') and CharInSet(ABody[AIndex + 1], ['o', 'O', 'c', 'C']);
  end;

begin
  AEntry := Default(TTodoEntry);
  Result := False;
  Len := Length(ABody);
  Position := 1;
  SkipSpaces;
  Start := Position;
  while (Position <= Len) and IsLetter(ABody[Position]) do
    Inc(Position);
  Word := UpperCase(Copy(ABody, Start, Position - Start));
  if Word = '' then
    Exit;
  // Nach der Marke: Ende, Leerraum oder Doppelpunkt; sonst ist es ein gewöhnliches Wort.
  if (Position <= Len) and not IsSpace(ABody[Position]) and (ABody[Position] <> ':') then
    Exit;
  if Word = TTodos.DoneKeyword then
    AEntry.Done := True
  else if not IsKeyword(Word, AKeywords) then
    Exit;
  AEntry.Keyword := Word;
  SkipSpaces;
  // Priorität
  Start := Position;
  while (Position <= Len) and CharInSet(ABody[Position], ['0'..'9']) do
    Inc(Position);
  if Position > Start then
  begin
    AEntry.Priority := StrToIntDef(Copy(ABody, Start, Position - Start), 0);
    SkipSpaces;
  end;
  // Optionen -oPerson -cKategorie, Werte mit Leerzeichen auch in ' oder "
  while OptionAt(Position) do
  begin
    Option := UpCase(ABody[Position + 1]);
    Inc(Position, 2);
    if (Position <= Len) and ((ABody[Position] = '''') or (ABody[Position] = '"')) then
    begin
      Quote := ABody[Position];
      Inc(Position);
      Start := Position;
      while (Position <= Len) and (ABody[Position] <> Quote) do
        Inc(Position);
      Value := Copy(ABody, Start, Position - Start);
      if Position <= Len then
        Inc(Position);
    end
    else
    begin
      Start := Position;
      while (Position <= Len) and (ABody[Position] <> ':') and
        not (IsSpace(ABody[Position]) and OptionAt(Position + 1)) do
        Inc(Position);
      Value := Copy(ABody, Start, Position - Start);
    end;
    if Option = 'O' then
      AEntry.Owner := Collapse(Value)
    else
      AEntry.Category := Collapse(Value);
    SkipSpaces;
  end;
  if (Position <= Len) and (ABody[Position] = ':') then
    Inc(Position);
  AEntry.Text := Collapse(Copy(ABody, Position, MaxInt));
  Result := True;
end;

class function TTodoScanner.FromTokens(const ATokens: TArray<TPascalToken>;
  const AKeywords: TArray<string>): TArray<TTodoEntry>;
var
  Token: TPascalToken;
  Entry: TTodoEntry;
begin
  Result := nil;
  for Token in ATokens do
    if (Token.Kind = TPascalTokenKind.Comment) and ParseBody(CommentBody(Token.Text), AKeywords, Entry) then
    begin
      Entry.Range.StartPos := Token.StartPos;
      Entry.Range.EndPos := Token.EndPos;
      Result := Result + [Entry];
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
        Continue;
      Seen.Add(UpperCase(FileName), True);
      if not Assigned(AReadText) or not AReadText(FileName, Text) then
        Continue;
      Entries := ForText(Text, AKeywords);
      if Length(Entries) > 0 then
        List.Add(TFileTodos.Create(TMetricsCollector.RelativePath(ARoot, FileName), Entries));
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
      if AFilter.Matches(FileItem, Entry) then
        Kept.Entries := Kept.Entries + [Entry];
    if Length(Kept.Entries) > 0 then
      Result := Result + [Kept];
  end;
end;

end.
