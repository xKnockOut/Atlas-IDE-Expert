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

function IsPathChar(AC: Char): Boolean;
begin
  Result := not CharInSet(AC, [#0..' ', '''', '"', '<', '>', '|', '{', '}']);
end;

function IsUrlChar(AC: Char): Boolean;
begin
  Result := not CharInSet(AC, [#0..' ', '''', '"', '<', '>', '{', '}', '`']);
end;

procedure AddLink(var ALinks: TArray<TDocumentLink>; const ARange: TTextRange; const ATarget: string;
  AIsUrl: Boolean);
var
  mLink: TDocumentLink;
begin
  mLink.Range := ARange;
  mLink.Target := ATarget;
  mLink.IsUrl := AIsUrl;
  ALinks := ALinks + [mLink];
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
  mText: string;
  I, mStart, mStop: Integer;
begin
  mText := AToken.Text;
  I := 1;
  while I <= Length(mText) do
  begin
    if StartsText('http://', Copy(mText, I, 7)) or StartsText('https://', Copy(mText, I, 8)) or
      StartsText('file://', Copy(mText, I, 7)) then
    begin
      mStart := I;
      mStop := I;
      while (mStop <= Length(mText)) and IsUrlChar(mText[mStop]) do
      begin
        Inc(mStop);
      end;
      // Satzzeichen am Ende gehören selten zur URL.
      while (mStop > mStart) and CharInSet(mText[mStop - 1], ['.', ',', ';', ':', ')', ']', '!', '?', '*']) do
      begin
        Dec(mStop);
      end;
      AddLink(ALinks, RangeIn(AToken, mStart, mStop - mStart), Copy(mText, mStart, mStop - mStart), True);
      I := mStop;
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
  mText, mName, mPath: string;
  C: Char;
begin
  mText := AToken.Text;
  if (Length(mText) < 3) or (mText[1] <> '''') or (mText[Length(mText)] <> '''') then
  begin
    Exit;
  end;
  mName := Copy(mText, 2, Length(mText) - 2);
  // Nur einfache Dateinamen mit Endung; Formatstrings und Sätze fallen heraus.
  if (ExtractFileExt(mName) = '') or (Pos('''', mName) > 0) or ContainsText(mName, '://') then
  begin
    Exit;
  end;
  for C in mName do
  begin
    if not IsPathChar(C) or (C = '*') or (C = '%') then
    begin
      Exit;
    end;
  end;
  if TIncludeFiles.FindFile(mName, ExtractFileDir(AFileName), ASearchPaths, AFileExists, mPath) then
  begin
    AddLink(ALinks, RangeIn(AToken, 2, Length(mName)), mPath, False);
  end;
end;

class function TDocumentLinks.Find(const AText, AFileName: string; const ASearchPaths: TArray<string>;
  const AFileExists: TFileExistsFunc): TArray<TDocumentLink>;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in TPascalLexer.Tokenize(AText) do
    case mToken.Kind of
      TPascalTokenKind.Directive:
        FindDirectiveLink(mToken, AFileName, ASearchPaths, AFileExists, Result);
      TPascalTokenKind.Comment:
        FindUrls(mToken, Result);
      TPascalTokenKind.StringLiteral:
        begin
          FindUrls(mToken, Result);
          FindStringFile(mToken, AFileName, ASearchPaths, AFileExists, Result);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
end;

end.
