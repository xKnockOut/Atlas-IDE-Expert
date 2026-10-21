unit Atlas.Common.Projects.PackageReader;

// Liest requires und contains einer Package-Datei (.dpk, #46). Die Listen sind
// Teil des Quelltexts: "requires rtl, vcl;" und "contains A in 'A.pas', B;".
// contains und requires sind am Anweisungsanfang gemeint; Kommentare und
// Direktiven zwischen den Einträgen werden übergangen. Für die Prüfung an der
// .dpk (implicit-package-import) behält jeder Eintrag seine Stelle, und das
// abschließende Semikolon von contains ist der Ort für neue Einträge.

interface

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract;

type
  /// <summary>Ein Eintrag aus requires oder contains.</summary>
  TPackageEntry = record
    Name: string;
    /// <summary>Pfad aus in '…' wie in der Datei (meist relativ zur .dpk); '' ohne.</summary>
    Path: string;
    /// <summary>Stelle des Namens.</summary>
    Range: TTextRange;
  end;

  TPackageSource = record
    /// <summary>Die Datei beginnt mit "package"; sonst sind die übrigen Felder leer.</summary>
    IsPackage: Boolean;
    Name: string;
    Requires: TArray<TPackageEntry>;
    Contains: TArray<TPackageEntry>;
    /// <summary>contains ist vorhanden; ContainsEnd ist dann die Stelle des abschließenden Semikolons.</summary>
    HasContains: Boolean;
    ContainsEnd: TTextPosition;
    /// <summary>Index von AName in Contains (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function ContainsIndex(const AName: string): Integer;
    /// <summary>AName steht in requires (ohne Groß-/Kleinschreibung).</summary>
    function RequiresPackage(const AName: string): Boolean;
  end;

  TPackageReader = class
  public
    class function Read(const AText: string): TPackageSource; static;
    /// <summary>Text für einen neuen contains-Eintrag vor ContainsEnd: ", Zeilenende, zwei Leerzeichen,
    /// Name in 'Pfad'" (APath '' = ohne in).</summary>
    class function ContainsInsertion(const AName, APath, ALineBreak: string): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Index des nächsten Tokens ab AIndex, das kein Kommentar und keine Direktive ist; Length = keins.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := ((AToken.Kind = TPascalTokenKind.Identifier) or (AToken.Kind = TPascalTokenKind.Keyword)) and
    SameText(AToken.Text, AWord);
end;

function Unquote(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
end;

/// <summary>Liest eine Liste ab dem Token hinter requires/contains bis zum Semikolon; liefert dessen Index.</summary>
function ReadList(const ATokens: TArray<TPascalToken>; AIndex: Integer; var AEntries: TArray<TPackageEntry>): Integer;
var
  Entry: TPackageEntry;
  First, Last: Integer;
  AfterIn: Boolean;

  procedure Flush;
  begin
    if Entry.Name <> '' then
    begin
      Entry.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
      AEntries := AEntries + [Entry];
    end;
    Entry := Default(TPackageEntry);
    First := -1;
    AfterIn := False;
  end;

begin
  Entry := Default(TPackageEntry);
  First := -1;
  Last := -1;
  AfterIn := False;
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
    begin
      Flush;
      Exit;
    end;
    if ATokens[Result].IsSymbol(',') then
      Flush
    else if ATokens[Result].IsKeyword('in') then
      AfterIn := True
    else if AfterIn and (ATokens[Result].Kind = TPascalTokenKind.StringLiteral) then
      Entry.Path := Unquote(ATokens[Result].Text)
    else if not AfterIn and ((ATokens[Result].Kind = TPascalTokenKind.Identifier) or
      ATokens[Result].IsSymbol('.')) then
    begin
      if First < 0 then
        First := Result;
      Last := Result;
      Entry.Name := Entry.Name + ATokens[Result].Text;
    end
    else if not IsTrivia(ATokens[Result]) and not AfterIn then
      // Unerwartetes Wort (z. B. "end"): Liste ist unvollständig.
      Break;
    Inc(Result);
  end;
  Flush;
  Result := -1;
end;

{ TPackageSource }

function TPackageSource.ContainsIndex(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Contains) do
    if SameText(Contains[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TPackageSource.RequiresPackage(const AName: string): Boolean;
var
  Entry: TPackageEntry;
begin
  for Entry in Requires do
    if SameText(Entry.Name, AName) then
      Exit(True);
  Result := False;
end;

{ TPackageReader }

class function TPackageReader.Read(const AText: string): TPackageSource;
var
  Tokens: TArray<TPascalToken>;
  Index, Stop: Integer;
begin
  Result := Default(TPackageSource);
  Tokens := TPascalLexer.Tokenize(AText);
  Index := NextCode(Tokens, 0);
  if (Index > High(Tokens)) or not IsWord(Tokens[Index], 'package') then
    Exit;
  Result.IsPackage := True;
  Index := NextCode(Tokens, Index + 1);
  while (Index <= High(Tokens)) and not Tokens[Index].IsSymbol(';') do
  begin
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) or Tokens[Index].IsSymbol('.') then
      Result.Name := Result.Name + Tokens[Index].Text;
    Index := NextCode(Tokens, Index + 1);
  end;
  while Index <= High(Tokens) do
  begin
    // requires und contains nur am Anweisungsanfang: nach einem Semikolon.
    if Tokens[Index].IsSymbol(';') then
    begin
      Index := NextCode(Tokens, Index + 1);
      if Index > High(Tokens) then
        Break;
      if IsWord(Tokens[Index], 'requires') then
      begin
        Stop := ReadList(Tokens, Index + 1, Result.Requires);
        if Stop < 0 then
          Break;
        Index := Stop;
        Continue;
      end;
      if IsWord(Tokens[Index], 'contains') then
      begin
        Stop := ReadList(Tokens, Index + 1, Result.Contains);
        if Stop < 0 then
          Break;
        Result.HasContains := True;
        Result.ContainsEnd := Tokens[Stop].StartPos;
        Index := Stop;
        Continue;
      end;
      Continue;
    end;
    Inc(Index);
  end;
end;

class function TPackageReader.ContainsInsertion(const AName, APath, ALineBreak: string): string;
begin
  Result := ',' + ALineBreak + '  ' + AName;
  if APath <> '' then
    Result := Result + ' in ''' + APath.Replace('''', '''''') + '''';
end;

end.
