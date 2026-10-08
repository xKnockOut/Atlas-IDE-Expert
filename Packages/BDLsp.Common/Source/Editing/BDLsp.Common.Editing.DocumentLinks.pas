unit BDLsp.Common.Editing.DocumentLinks;

// Anklickbare Verweise einer Unit (#25):
// - {$I datei}, {$INCLUDE datei}, {$R datei}, {$RESOURCE datei}; "*" steht für
//   den Dateinamen der Unit ({$R *.dfm} → Unit1.dfm)
// - URLs (http, https, file) in Kommentaren und Strings
// - Dateinamen in Strings, wenn die Datei existiert
// Dateien werden relativ zum Ordner der Unit gesucht, danach in den
// zusätzlichen Suchpfaden. Verweise auf fehlende Dateien entfallen.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.IncludeFiles;

type
  /// <summary>Gleicher Typ wie bei der Include-Suche (#264).</summary>
  TFileExistsFunc = TIncludeFileExists;

  TDocumentLink = record
    Range: TTextRange;
    /// <summary>Vollständiger Dateipfad oder URL.</summary>
    Target: string;
    /// <summary>True, wenn Target eine URL ist.</summary>
    IsUrl: Boolean;
  end;

  TDocumentLinks = class
  public
    /// <summary>Alle Verweise in AText der Datei AFileName, in Textreihenfolge.</summary>
    class function Find(const AText, AFileName: string; const ASearchPaths: TArray<string>;
      const AFileExists: TFileExistsFunc): TArray<TDocumentLink>; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.Lexer;

function PositionIn(const AToken: TPascalToken; AIndex: Integer): TTextPosition;
var
  I: Integer;
begin
  // AIndex ab 1 im Tokentext; Kommentare und Strings können mehrzeilig sein.
  Result := AToken.StartPos;
  for I := 1 to AIndex - 1 do
    if AToken.Text[I] = #10 then
    begin
      Result.Line := Result.Line + 1;
      Result.Character := 0;
    end
    else
      Result.Character := Result.Character + 1;
end;

function RangeIn(const AToken: TPascalToken; AStart, ALength: Integer): TTextRange;
begin
  Result := TTextRange.Create(PositionIn(AToken, AStart), PositionIn(AToken, AStart + ALength));
end;

function IsPathChar(C: Char): Boolean;
begin
  Result := not CharInSet(C, [#0..' ', '''', '"', '<', '>', '|', '{', '}']);
end;

function IsUrlChar(C: Char): Boolean;
begin
  Result := not CharInSet(C, [#0..' ', '''', '"', '<', '>', '{', '}', '`']);
end;

procedure AddLink(var ALinks: TArray<TDocumentLink>; const ARange: TTextRange; const ATarget: string;
  AIsUrl: Boolean);
var
  Link: TDocumentLink;
begin
  Link.Range := ARange;
  Link.Target := ATarget;
  Link.IsUrl := AIsUrl;
  ALinks := ALinks + [Link];
end;

procedure FindDirectiveLink(const AToken: TPascalToken; const AFileName: string;
  const ASearchPaths: TArray<string>; const AFileExists: TFileExistsFunc; var ALinks: TArray<TDocumentLink>);
var
  Text, Name, Word, Path: string;
  I, Start, Stop: Integer;
  Found: Boolean;
begin
  Text := AToken.Text;
  // {$ oder (*$
  if StartsText('{$', Text) then
    I := 3
  else if StartsText('(*$', Text) then
    I := 4
  else
    Exit;
  Start := I;
  while (I <= Length(Text)) and CharInSet(Text[I], ['A'..'Z', 'a'..'z']) do
    Inc(I);
  Word := UpperCase(Copy(Text, Start, I - Start));
  if not ((Word = 'I') or (Word = 'INCLUDE') or (Word = 'R') or (Word = 'RESOURCE')) then
    Exit;
  // {$I+} und {$R-} sind Schalter, keine Dateien.
  if (I > Length(Text)) or not CharInSet(Text[I], [' ', #9]) then
    Exit;
  while (I <= Length(Text)) and CharInSet(Text[I], [' ', #9]) do
    Inc(I);
  if (I <= Length(Text)) and (Text[I] = '''') then
  begin
    Start := I + 1;
    Stop := PosEx('''', Text, Start);
    if Stop = 0 then
      Exit;
  end
  else
  begin
    Start := I;
    Stop := Start;
    while (Stop <= Length(Text)) and IsPathChar(Text[Stop]) do
      Inc(Stop);
    // Das Ende von (*$I datei*) gehört nicht zum Namen.
    if (Stop - Start >= 2) and (Copy(Text, Stop - 2, 2) = '*)') then
      Dec(Stop, 2);
  end;
  Name := Copy(Text, Start, Stop - Start);
  if Name = '' then
    Exit;
  // {$R *.dfm}: "*" ist der Dateiname der Unit ohne Endung.
  Name := StringReplace(Name, '*', ChangeFileExt(ExtractFileName(AFileName), ''), [rfReplaceAll]);
  // Dieselbe Suche wie Präprozessor und Index (#264): $I ergänzt ".inc"/".pas".
  if (Word = 'I') or (Word = 'INCLUDE') then
    Found := TIncludeFiles.FindInclude(Name, AFileName, ASearchPaths, AFileExists, Path)
  else
    Found := TIncludeFiles.FindFile(Name, ExtractFileDir(AFileName), ASearchPaths, AFileExists, Path);
  if Found then
    AddLink(ALinks, RangeIn(AToken, Start, Stop - Start), Path, False);
end;

procedure FindUrls(const AToken: TPascalToken; var ALinks: TArray<TDocumentLink>);
var
  Text: string;
  I, Start, Stop: Integer;
begin
  Text := AToken.Text;
  I := 1;
  while I <= Length(Text) do
  begin
    if StartsText('http://', Copy(Text, I, 7)) or StartsText('https://', Copy(Text, I, 8)) or
      StartsText('file://', Copy(Text, I, 7)) then
    begin
      Start := I;
      Stop := I;
      while (Stop <= Length(Text)) and IsUrlChar(Text[Stop]) do
        Inc(Stop);
      // Satzzeichen am Ende gehören selten zur URL.
      while (Stop > Start) and CharInSet(Text[Stop - 1], ['.', ',', ';', ':', ')', ']', '!', '?', '*']) do
        Dec(Stop);
      AddLink(ALinks, RangeIn(AToken, Start, Stop - Start), Copy(Text, Start, Stop - Start), True);
      I := Stop;
    end
    else
      Inc(I);
  end;
end;

procedure FindStringFile(const AToken: TPascalToken; const AFileName: string;
  const ASearchPaths: TArray<string>; const AFileExists: TFileExistsFunc; var ALinks: TArray<TDocumentLink>);
var
  Text, Name, Path: string;
  C: Char;
begin
  Text := AToken.Text;
  if (Length(Text) < 3) or (Text[1] <> '''') or (Text[Length(Text)] <> '''') then
    Exit;
  Name := Copy(Text, 2, Length(Text) - 2);
  // Nur einfache Dateinamen mit Endung; Formatstrings und Sätze fallen heraus.
  if (ExtractFileExt(Name) = '') or (Pos('''', Name) > 0) or ContainsText(Name, '://') then
    Exit;
  for C in Name do
    if not IsPathChar(C) or (C = '*') or (C = '%') then
      Exit;
  if TIncludeFiles.FindFile(Name, ExtractFileDir(AFileName), ASearchPaths, AFileExists, Path) then
    AddLink(ALinks, RangeIn(AToken, 2, Length(Name)), Path, False);
end;

class function TDocumentLinks.Find(const AText, AFileName: string; const ASearchPaths: TArray<string>;
  const AFileExists: TFileExistsFunc): TArray<TDocumentLink>;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in TPascalLexer.Tokenize(AText) do
    case Token.Kind of
      TPascalTokenKind.Directive:
        FindDirectiveLink(Token, AFileName, ASearchPaths, AFileExists, Result);
      TPascalTokenKind.Comment:
        FindUrls(Token, Result);
      TPascalTokenKind.StringLiteral:
        begin
          FindUrls(Token, Result);
          FindStringFile(Token, AFileName, ASearchPaths, AFileExists, Result);
        end;
    end;
end;

end.
