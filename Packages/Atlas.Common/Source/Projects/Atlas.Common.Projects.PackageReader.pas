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
  begin
    Inc(Result);
  end;
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
  begin
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
  end;
end;

type
  /// <summary>Eintrag, der in ReadList gerade gelesen wird.</summary>
  TListState = record
    Entry: TPackageEntry;
    First: Integer;
    Last: Integer;
    AfterIn: Boolean;
  end;

procedure ResetEntry(var AState: TListState);
begin
  AState.Entry := Default(TPackageEntry);
  AState.First := -1;
  AState.AfterIn := False;
end;

procedure FlushEntry(const ATokens: TArray<TPascalToken>; var AState: TListState;
  var AEntries: TArray<TPackageEntry>);
begin
  if AState.Entry.Name <> '' then
  begin
    AState.Entry.Range := TTextRange.Create(ATokens[AState.First].StartPos, ATokens[AState.Last].EndPos);
    AEntries := AEntries + [AState.Entry];
  end;
  ResetEntry(AState);
end;

/// <summary>Nimmt das Token AIndex in den Eintrag auf; False bei einem unerwarteten Wort (z. B. "end"): Die Liste
/// ist dann unvollständig.</summary>
function TakeListToken(const ATokens: TArray<TPascalToken>; AIndex: Integer; var AState: TListState): Boolean;
var
  mToken: TPascalToken;
begin
  Result := True;
  mToken := ATokens[AIndex];
  if mToken.IsKeyword('in') then
  begin
    AState.AfterIn := True;
  end
  else if AState.AfterIn then
  begin
    if mToken.Kind = TPascalTokenKind.StringLiteral then
    begin
      AState.Entry.Path := Unquote(mToken.Text);
    end;
  end
  else if (mToken.Kind = TPascalTokenKind.Identifier) or mToken.IsSymbol('.') then
  begin
    if AState.First < 0 then
    begin
      AState.First := AIndex;
    end;
    AState.Last := AIndex;
    AState.Entry.Name := AState.Entry.Name + mToken.Text;
  end
  else
  begin
    Result := IsTrivia(mToken);
  end;
end;

/// <summary>Liest eine Liste ab dem Token hinter requires/contains bis zum Semikolon; liefert dessen Index.</summary>
function ReadList(const ATokens: TArray<TPascalToken>; AIndex: Integer; var AEntries: TArray<TPackageEntry>): Integer;
var
  mState: TListState;
begin
  ResetEntry(mState);
  mState.Last := -1;
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
    begin
      FlushEntry(ATokens, mState, AEntries);
      Exit;
    end;
    if ATokens[Result].IsSymbol(',') then
    begin
      FlushEntry(ATokens, mState, AEntries);
    end
    else if not TakeListToken(ATokens, Result, mState) then
    begin
      Break;
    end;
    Inc(Result);
  end;
  FlushEntry(ATokens, mState, AEntries);
  Result := -1;
end;

{ TPackageSource }

function TPackageSource.ContainsIndex(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Contains) do
  begin
    if SameText(Contains[Index].Name, AName) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TPackageSource.RequiresPackage(const AName: string): Boolean;
var
  Entry: TPackageEntry;
begin
  for Entry in Requires do
  begin
    if SameText(Entry.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TPackageReader }

/// <summary>Liest die Anweisung ab AIndex (hinter einem Semikolon): requires oder contains. Liefert den Index des
/// nächsten Semikolons oder -1, wenn die Liste nicht endet.</summary>
function ReadSection(const ATokens: TArray<TPascalToken>; AIndex: Integer; var ASource: TPackageSource): Integer;
begin
  Result := AIndex;
  if IsWord(ATokens[AIndex], 'requires') then
  begin
    Result := ReadList(ATokens, AIndex + 1, ASource.Requires);
  end
  else if IsWord(ATokens[AIndex], 'contains') then
  begin
    Result := ReadList(ATokens, AIndex + 1, ASource.Contains);
    if Result >= 0 then
    begin
      ASource.HasContains := True;
      ASource.ContainsEnd := ATokens[Result].StartPos;
    end;
  end;
end;

class function TPackageReader.Read(const AText: string): TPackageSource;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := Default(TPackageSource);
  mTokens := TPascalLexer.Tokenize(AText);
  mIndex := NextCode(mTokens, 0);
  if (mIndex > High(mTokens)) or not IsWord(mTokens[mIndex], 'package') then
  begin
    Exit;
  end;
  Result.IsPackage := True;
  mIndex := NextCode(mTokens, mIndex + 1);
  while (mIndex <= High(mTokens)) and not mTokens[mIndex].IsSymbol(';') do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) or mTokens[mIndex].IsSymbol('.') then
    begin
      Result.Name := Result.Name + mTokens[mIndex].Text;
    end;
    mIndex := NextCode(mTokens, mIndex + 1);
  end;
  // requires und contains nur am Anweisungsanfang: nach einem Semikolon.
  while (mIndex >= 0) and (mIndex <= High(mTokens)) do
  begin
    if mTokens[mIndex].IsSymbol(';') then
    begin
      mIndex := NextCode(mTokens, mIndex + 1);
      if mIndex <= High(mTokens) then
      begin
        mIndex := ReadSection(mTokens, mIndex, Result);
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

class function TPackageReader.ContainsInsertion(const AName, APath, ALineBreak: string): string;
begin
  Result := ',' + ALineBreak + '  ' + AName;
  if APath <> '' then
  begin
    Result := Result + ' in ''' + APath.Replace('''', '''''') + '''';
  end;
end;

end.
