unit BDLsp.Common.Rules.ChangedFiles;

// Auswahl der zu prüfenden Dateien für --changed und --diff (#157). Die Unit
// wertet nur Text aus; Git bzw. SVN (#276) startet die Shell.
//   ParseNameStatus  Ausgabe von "git diff --name-status": umbenannte Dateien
//                    unter neuem Namen, gelöschte werden ignoriert.
//   ParseHunks       Ausgabe von "git diff -U0": geänderte Zeilen je Datei.
//   Select           geänderte Units, Units zu geänderten DFMs/FMXs und zu
//                    geänderten Include-Dateien; Projekt- und Konfigurations-
//                    dateien wählen alles.
//   ParseSvnStatus, ParseSvnSummarize, ParseSvnDiff  dasselbe für SVN: "svn status",
//                    "svn diff --summarize" und "svn diff" mit Kontextzeilen.
// Pfade aus Git sind relativ zur Wurzel des Repositorys und mit "/" getrennt.
// Pfade mit Sonderzeichen gibt Git in Anführungszeichen mit Oktalfolgen für
// die UTF-8-Bytes aus (core.quotepath); UnquotePath macht daraus wieder Text,
// damit die Ausgabe unabhängig von der Codepage der Konsole bleibt.

interface

uses
  System.SysUtils;

type
  /// <summary>Geänderte Zeilen einer Datei, 0-basiert und einschließlich.</summary>
  TLineSpan = record
    First: Integer;
    Last: Integer;
  end;

  TChangedLines = record
    /// <summary>Pfad relativ zur Wurzel des Repositorys, mit "/" getrennt.</summary>
    Path: string;
    Spans: TArray<TLineSpan>;
    function Contains(ALine: Integer): Boolean;
  end;

  /// <summary>Liefert die in AFileName eingebundenen Include-Namen, wie sie in $I stehen.</summary>
  TIncludeNamesOf = reference to function(const AFileName: string): TArray<string>;

  TChangedFiles = class
  public
    /// <summary>Pfade aus "git diff --name-status": A, C, M, R (neuer Name), T; D wird ignoriert.</summary>
    class function ParseNameStatus(const ALines: TArray<string>): TArray<string>; static;
    /// <summary>Geänderte Zeilen je Datei aus "git diff -U0".</summary>
    class function ParseHunks(const ALines: TArray<string>): TArray<TChangedLines>; static;
    /// <summary>Pfade aus "svn status": A, M, R; mit AUnversioned auch "?" (neue Dateien).</summary>
    class function ParseSvnStatus(const ALines: TArray<string>; AUnversioned: Boolean): TArray<string>; static;
    /// <summary>Pfade aus "svn diff --summarize": A, M, R; D und reine Eigenschaftsänderungen nicht.</summary>
    class function ParseSvnSummarize(const ALines: TArray<string>): TArray<string>; static;
    /// <summary>Geänderte Zeilen aus "svn diff"; nur hinzugefügte Zeilen zählen, Kontextzeilen nicht.</summary>
    class function ParseSvnDiff(const ALines: TArray<string>): TArray<TChangedLines>; static;
    /// <summary>Include-Namen aus {$I name} und {$INCLUDE name}; {$I+} und {$I-} sind Schalter.</summary>
    class function IncludeNames(const AText: string): TArray<string>; static;
    /// <summary>Teilmenge von ACandidates (vollständige Pfade), die nach den geänderten Dateien
    /// AChanged (vollständige Pfade) zu prüfen ist.</summary>
    class function Select(const AChanged, ACandidates: TArray<string>;
      const AIncludeNamesOf: TIncludeNamesOf): TArray<string>; static;
    /// <summary>Geänderte Zeilen zu AFullPath; False, wenn die Datei keine Hunks hat.</summary>
    class function LinesOf(const AChanges: TArray<TChangedLines>; const ARepoRoot, AFullPath: string;
      out ALines: TChangedLines): Boolean; static;
    /// <summary>Pfad aus Git ohne Anführungszeichen; "\303\244" wird zu "ä".</summary>
    class function UnquotePath(const APath: string): string; static;
    /// <summary>Vollständiger Pfad zu einem Git-Pfad unterhalb von ARepoRoot.</summary>
    class function FullPath(const ARepoRoot, AGitPath: string): string; static;
  end;

implementation

uses
  System.StrUtils;

{ TChangedLines }

function TChangedLines.Contains(ALine: Integer): Boolean;
var
  Span: TLineSpan;
begin
  for Span in Spans do
    if (ALine >= Span.First) and (ALine <= Span.Last) then
      Exit(True);
  Result := False;
end;

{ TChangedFiles }

class function TChangedFiles.FullPath(const ARepoRoot, AGitPath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ARepoRoot) + StringReplace(AGitPath, '/', PathDelim, [rfReplaceAll]);
  if PathDelim = '/' then
    Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
end;

class function TChangedFiles.UnquotePath(const APath: string): string;
var
  Bytes: TBytes;
  Index, Count: Integer;
  Extra: Byte;

  procedure Add(AByte: Byte);
  begin
    Bytes[Count] := AByte;
    Inc(Count);
  end;

begin
  if (Length(APath) < 2) or (APath[1] <> '"') or (APath[Length(APath)] <> '"') then
    Exit(APath);
  SetLength(Bytes, Length(APath) * 3);
  Count := 0;
  Index := 2;
  while Index < Length(APath) do
  begin
    if (APath[Index] = '\') and (Index + 1 < Length(APath)) then
    begin
      Inc(Index);
      if CharInSet(APath[Index], ['0'..'7']) and (Index + 2 < Length(APath)) then
      begin
        Add((Ord(APath[Index]) - Ord('0')) * 64 + (Ord(APath[Index + 1]) - Ord('0')) * 8 +
          Ord(APath[Index + 2]) - Ord('0'));
        Inc(Index, 2);
      end
      else
        case APath[Index] of
          't': Add(9);
          'n': Add(10);
          'r': Add(13);
        else
          Add(Ord(APath[Index]));
        end;
    end
    else if Ord(APath[Index]) < 128 then
      Add(Ord(APath[Index]))
    else
      // Zeichen außerhalb von ASCII ohne Oktalfolge: als UTF-8 übernehmen.
      for Extra in TEncoding.UTF8.GetBytes(string(APath[Index])) do
        Add(Extra);
    Inc(Index);
  end;
  SetLength(Bytes, Count);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TChangedFiles.ParseNameStatus(const ALines: TArray<string>): TArray<string>;
var
  Line, Status, Rest: string;
  Tab: Integer;
begin
  Result := nil;
  for Line in ALines do
  begin
    // "M<Tab>Pfad", "R087<Tab>Alt<Tab>Neu"
    Tab := Pos(#9, Line);
    if Tab < 2 then
      Continue;
    Status := UpperCase(Copy(Line, 1, 1));
    Rest := Copy(Line, Tab + 1, MaxInt);
    if (Status = 'R') or (Status = 'C') then
    begin
      Tab := Pos(#9, Rest);
      if Tab > 0 then
        Result := Result + [UnquotePath(Copy(Rest, Tab + 1, MaxInt))];
    end
    else if ((Status = 'A') or (Status = 'M') or (Status = 'T')) and (Rest <> '') then
      Result := Result + [UnquotePath(Rest)];
  end;
end;

class function TChangedFiles.ParseHunks(const ALines: TArray<string>): TArray<TChangedLines>;
var
  Line, Header: string;
  Current: Integer;
  Plus, Space, Comma, Start, Count: Integer;
  Span: TLineSpan;
  Item: TChangedLines;
begin
  Result := nil;
  Current := -1;
  for Line in ALines do
  begin
    if StartsStr('+++ ', Line) then
    begin
      Current := -1;
      // "+++ b/Pfad", "+++ "b/Pfad"" bzw. "+++ /dev/null" bei gelöschten Dateien
      Header := UnquotePath(Copy(Line, Length('+++ ') + 1, MaxInt));
      if StartsStr('b/', Header) then
      begin
        Item := Default(TChangedLines);
        Item.Path := Copy(Header, Length('b/') + 1, MaxInt);
        Result := Result + [Item];
        Current := High(Result);
      end;
    end
    else if StartsStr('@@ ', Line) and (Current >= 0) then
    begin
      // @@ -a[,b] +c[,d] @@: neue Zeilen c .. c+d-1 (1-basiert), d fehlt = 1, d = 0 nur gelöscht
      Plus := Pos(' +', Line);
      if Plus = 0 then
        Continue;
      Space := PosEx(' ', Line, Plus + 2);
      if Space = 0 then
        Continue;
      Header := Copy(Line, Plus + 2, Space - Plus - 2);
      Comma := Pos(',', Header);
      if Comma > 0 then
      begin
        Start := StrToIntDef(Copy(Header, 1, Comma - 1), 0);
        Count := StrToIntDef(Copy(Header, Comma + 1, MaxInt), 0);
      end
      else
      begin
        Start := StrToIntDef(Header, 0);
        Count := 1;
      end;
      if (Count <= 0) or (Start <= 0) then
        Continue;
      Span.First := Start - 1;
      Span.Last := Start + Count - 2;
      Result[Current].Spans := Result[Current].Spans + [Span];
    end;
  end;
end;

/// <summary>Pfad ab Spalte 9 bei Status in Spalte 1 aus AStates; '' sonst.</summary>
function SvnPath(const ALine: string; const AStates: string): string;
begin
  Result := '';
  if (Length(ALine) < 9) or (Pos(ALine[1], AStates) = 0) then
    Exit;
  Result := Trim(Copy(ALine, 9, MaxInt));
end;

class function TChangedFiles.ParseSvnStatus(const ALines: TArray<string>; AUnversioned: Boolean): TArray<string>;
var
  Line, States, Path: string;
begin
  Result := nil;
  States := 'AMR';
  if AUnversioned then
    States := States + '?';
  for Line in ALines do
  begin
    Path := SvnPath(Line, States);
    if Path <> '' then
      Result := Result + [Path];
  end;
end;

class function TChangedFiles.ParseSvnSummarize(const ALines: TArray<string>): TArray<string>;
var
  Line, Path: string;
begin
  Result := nil;
  for Line in ALines do
  begin
    Path := SvnPath(Line, 'AMR');
    if Path <> '' then
      Result := Result + [Path];
  end;
end;

class function TChangedFiles.ParseSvnDiff(const ALines: TArray<string>): TArray<TChangedLines>;
var
  Line, Header: string;
  Current, NewLine, Plus, Space, Comma: Integer;
  Span: TLineSpan;
  Item: TChangedLines;
begin
  Result := nil;
  Current := -1;
  NewLine := -1;
  for Line in ALines do
  begin
    if StartsStr('+++ ', Line) then
    begin
      // "+++ Src/Kunde.pas	(working copy)"
      Header := Copy(Line, Length('+++ ') + 1, MaxInt);
      if Pos(#9, Header) > 0 then
        Header := Copy(Header, 1, Pos(#9, Header) - 1);
      Item := Default(TChangedLines);
      Item.Path := Trim(Header);
      Result := Result + [Item];
      Current := High(Result);
      NewLine := -1;
    end
    else if StartsStr('@@ ', Line) and (Current >= 0) then
    begin
      Plus := Pos(' +', Line);
      Space := PosEx(' ', Line, Plus + 2);
      NewLine := -1;
      if (Plus > 0) and (Space > 0) then
      begin
        Header := Copy(Line, Plus + 2, Space - Plus - 2);
        Comma := Pos(',', Header);
        if Comma > 0 then
          Header := Copy(Header, 1, Comma - 1);
        NewLine := StrToIntDef(Header, 0) - 1;
      end;
    end
    else if (Current >= 0) and (NewLine >= 0) and (Line <> '') then
      case Line[1] of
        ' ':
          Inc(NewLine);
        '+':
          begin
            // Benachbarte Zeilen zu einem Bereich zusammenfassen.
            if (Length(Result[Current].Spans) > 0) and
              (Result[Current].Spans[High(Result[Current].Spans)].Last = NewLine - 1) then
              Result[Current].Spans[High(Result[Current].Spans)].Last := NewLine
            else
            begin
              Span.First := NewLine;
              Span.Last := NewLine;
              Result[Current].Spans := Result[Current].Spans + [Span];
            end;
            Inc(NewLine);
          end;
        '-', '\':
          ;
      else
        NewLine := -1;
      end;
  end;
end;

class function TChangedFiles.IncludeNames(const AText: string): TArray<string>;
var
  Upper, Name: string;
  Index, Start, Stop: Integer;
  Quoted: Boolean;
begin
  Result := nil;
  Upper := UpperCase(AText);
  Index := 1;
  while Index <= Length(Upper) do
  begin
    if (Upper[Index] = '{') and (Copy(Upper, Index + 1, 1) = '$') then
      Start := Index + 2
    else if (Copy(Upper, Index, 3) = '(*$') then
      Start := Index + 3
    else
    begin
      Inc(Index);
      Continue;
    end;
    Index := Start;
    if Copy(Upper, Start, 7) = 'INCLUDE' then
      Start := Start + 7
    else if (Copy(Upper, Start, 1) = 'I') and (Copy(Upper, Start + 1, 1) <> '') and
      CharInSet(Upper[Start + 1], [' ', #9]) then
      Start := Start + 1
    else
      Continue;
    if (Start > Length(Upper)) or not CharInSet(Upper[Start], [' ', #9]) then
      Continue;
    while (Start <= Length(Upper)) and CharInSet(Upper[Start], [' ', #9]) do
      Inc(Start);
    if (Start > Length(Upper)) or CharInSet(Upper[Start], ['+', '-']) then
      Continue;
    Quoted := Upper[Start] = '''';
    if Quoted then
    begin
      Inc(Start);
      Stop := PosEx('''', AText, Start);
    end
    else
    begin
      Stop := Start;
      while (Stop <= Length(AText)) and not CharInSet(AText[Stop], [' ', #9, '}', '*', #10, #13]) do
        Inc(Stop);
    end;
    if Stop <= Start then
      Continue;
    Name := Copy(AText, Start, Stop - Start);
    if Name <> '' then
      Result := Result + [Name];
    Index := Stop;
  end;
end;

function Normalize(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
end;

function WithoutExt(const APath: string): string;
begin
  Result := Normalize(ChangeFileExt(APath, ''));
end;

function BaseName(const APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := Copy(Path, LastDelimiter('/', Path) + 1, MaxInt);
end;

function IncludeMatches(const AIncludeName, AIncludeFile: string): Boolean;
var
  Name: string;
begin
  // Abgleich über den Dateinamen; Suchpfade sind hier nicht bekannt.
  Name := BaseName(AIncludeName);
  if Pos('.', Name) = 0 then
    Name := Name + '.inc';
  Result := SameText(Name, BaseName(AIncludeFile));
end;

class function TChangedFiles.Select(const AChanged, ACandidates: TArray<string>;
  const AIncludeNamesOf: TIncludeNamesOf): TArray<string>;
var
  Changed, Ext, IncludeName: string;
  Includes: TArray<string>;
  Wanted: TArray<Boolean>;
  Index: Integer;
begin
  SetLength(Wanted, Length(ACandidates));
  Includes := nil;
  for Changed in AChanged do
  begin
    Ext := LowerCase(ExtractFileExt(Changed));
    if MatchText(Ext, ['.dproj', '.dpk', '.dpr']) or SameText(ExtractFileName(Changed), 'delphi-lsp.json') then
      Exit(Copy(ACandidates));
    if MatchText(Ext, ['.inc']) then
      Includes := Includes + [Changed];
    for Index := 0 to High(ACandidates) do
      if (Normalize(ACandidates[Index]) = Normalize(Changed)) or
        (MatchText(Ext, ['.dfm', '.fmx']) and (WithoutExt(ACandidates[Index]) = WithoutExt(Changed))) then
        Wanted[Index] := True;
  end;
  if (Includes <> nil) and Assigned(AIncludeNamesOf) then
    for Index := 0 to High(ACandidates) do
      if not Wanted[Index] then
        for IncludeName in AIncludeNamesOf(ACandidates[Index]) do
          for Changed in Includes do
            if IncludeMatches(IncludeName, Changed) then
              Wanted[Index] := True;
  Result := nil;
  for Index := 0 to High(ACandidates) do
    if Wanted[Index] then
      Result := Result + [ACandidates[Index]];
end;

class function TChangedFiles.LinesOf(const AChanges: TArray<TChangedLines>; const ARepoRoot, AFullPath: string;
  out ALines: TChangedLines): Boolean;
var
  Item: TChangedLines;
begin
  for Item in AChanges do
    if Normalize(FullPath(ARepoRoot, Item.Path)) = Normalize(AFullPath) then
    begin
      ALines := Item;
      Exit(True);
    end;
  ALines := Default(TChangedLines);
  Result := False;
end;

end.
