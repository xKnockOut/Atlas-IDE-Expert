unit Atlas.Common.Editing.DocumentLinks;

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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.IncludeFiles;

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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

function PositionIn(const AToken: TPascalToken; AIndex: Integer): TTextPosition;
var
  I: Integer;
begin
  // AIndex ab 1 im Tokentext; Kommentare und Strings können mehrzeilig sein.
  Result := AToken.StartPos;
  for I := 1 to AIndex - 1 do
  begin
    if AToken.Text[I] = #10 then
    begin
      Result.Line := Result.Line + 1;
      Result.Character := 0;
    end
    else
    begin
      Result.Character := Result.Character + 1;
    end;
  end;
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

/// <summary>Großgeschriebener Name der Direktive in {$…} bzw. (*$…*); '' bei anderen Kommentaren. AIndex steht
/// danach hinter dem Namen.</summary>
function DirectiveWord(const AText: string; out AIndex: Integer): string;
var
  mStart: Integer;
begin
  Result := '';
  AIndex := 0;
  if StartsText('{$', AText) then
  begin
    AIndex := 3;
  end
  else if StartsText('(*$', AText) then
  begin
    AIndex := 4;
  end;
  if AIndex = 0 then
  begin
    Exit;
  end;
  mStart := AIndex;
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(AIndex);
  end;
  Result := UpperCase(Copy(AText, mStart, AIndex - mStart));
end;

function IsIncludeWord(const AWord: string): Boolean;
begin
  Result := (AWord = 'I') or (AWord = 'INCLUDE');
end;

/// <summary>Direktive mit Dateiname: $I, $INCLUDE, $R oder $RESOURCE, gefolgt von Leerraum ({$I+} und {$R-}
/// sind Schalter).</summary>
function IsFileDirective(const AText, AWord: string; AIndex: Integer): Boolean;
begin
  Result := (IsIncludeWord(AWord) or (AWord = 'R') or (AWord = 'RESOURCE')) and (AIndex <= Length(AText)) and
    CharInSet(AText[AIndex], [' ', #9]);
end;

/// <summary>Dateiname ab AIndex: in '…' oder bis zum ersten Zeichen, das in Pfaden nicht vorkommt.
/// AStart..AStop - 1 ist der Name; False ohne schließendes Anführungszeichen.</summary>
function FileNameSpan(const AText: string; AIndex: Integer; out AStart, AStop: Integer): Boolean;
begin
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], [' ', #9]) do
  begin
    Inc(AIndex);
  end;
  if (AIndex <= Length(AText)) and (AText[AIndex] = '''') then
  begin
    AStart := AIndex + 1;
    AStop := PosEx('''', AText, AStart);
    Exit(AStop > 0);
  end;
  AStart := AIndex;
  AStop := AStart;
  while (AStop <= Length(AText)) and IsPathChar(AText[AStop]) do
  begin
    Inc(AStop);
  end;
  // Das Ende von (*$I datei*) gehört nicht zum Namen.
  if (AStop - AStart >= 2) and (Copy(AText, AStop - 2, 2) = '*)') then
  begin
    Dec(AStop, 2);
  end;
  Result := True;
end;

/// <summary>Sucht die Datei wie Präprozessor und Index (#264): $I ergänzt ".inc"/".pas".</summary>
function ResolveFile(const AName: string; AInclude: Boolean; const AFileName: string;
  const ASearchPaths: TArray<string>; const AFileExists: TFileExistsFunc; out APath: string): Boolean;
var
  mName: string;
begin
  // {$R *.dfm}: "*" ist der Dateiname der Unit ohne Endung.
  mName := StringReplace(AName, '*', ChangeFileExt(ExtractFileName(AFileName), ''), [rfReplaceAll]);
  if AInclude then
  begin
    Result := TIncludeFiles.FindInclude(mName, AFileName, ASearchPaths, AFileExists, APath);
  end
  else
  begin
    Result := TIncludeFiles.FindFile(mName, ExtractFileDir(AFileName), ASearchPaths, AFileExists, APath);
  end;
end;

procedure FindDirectiveLink(const AToken: TPascalToken; const AFileName: string;
  const ASearchPaths: TArray<string>; const AFileExists: TFileExistsFunc; var ALinks: TArray<TDocumentLink>);
var
  mWord, mName, mPath: string;
  mIndex, mStart, mStop: Integer;
begin
  mWord := DirectiveWord(AToken.Text, mIndex);
  if not IsFileDirective(AToken.Text, mWord, mIndex) or not FileNameSpan(AToken.Text, mIndex, mStart, mStop) then
  begin
    Exit;
  end;
  mName := Copy(AToken.Text, mStart, mStop - mStart);
  if (mName <> '') and ResolveFile(mName, IsIncludeWord(mWord), AFileName, ASearchPaths, AFileExists, mPath) then
  begin
    AddLink(ALinks, RangeIn(AToken, mStart, mStop - mStart), mPath, False);
  end;
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
      begin
        Inc(Stop);
      end;
      // Satzzeichen am Ende gehören selten zur URL.
      while (Stop > Start) and CharInSet(Text[Stop - 1], ['.', ',', ';', ':', ')', ']', '!', '?', '*']) do
      begin
        Dec(Stop);
      end;
      AddLink(ALinks, RangeIn(AToken, Start, Stop - Start), Copy(Text, Start, Stop - Start), True);
      I := Stop;
    end
    else
    begin
      Inc(I);
    end;
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
  begin
    Exit;
  end;
  Name := Copy(Text, 2, Length(Text) - 2);
  // Nur einfache Dateinamen mit Endung; Formatstrings und Sätze fallen heraus.
  if (ExtractFileExt(Name) = '') or (Pos('''', Name) > 0) or ContainsText(Name, '://') then
  begin
    Exit;
  end;
  for C in Name do
  begin
    if not IsPathChar(C) or (C = '*') or (C = '%') then
    begin
      Exit;
    end;
  end;
  if TIncludeFiles.FindFile(Name, ExtractFileDir(AFileName), ASearchPaths, AFileExists, Path) then
  begin
    AddLink(ALinks, RangeIn(AToken, 2, Length(Name)), Path, False);
  end;
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
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
end;

end.
