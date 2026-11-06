unit Atlas.Common.Editing.EditorConfig;

// .editorconfig für die Formatierung (#43): Vom Ordner der Datei aufwärts
// werden alle .editorconfig gelesen, bis eine "root = true" enthält. Nähere
// Dateien und spätere Abschnitte gewinnen. Ausgewertet werden indent_style,
// indent_size, tab_width, end_of_line, trim_trailing_whitespace,
// insert_final_newline und max_line_length (Zahl oder off). Abschnittsmuster: *, *.ext, *.{a,b}, Dateiname.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

type
  TEditorConfigReadFile = reference to function(const AFileName: string; out AText: string): Boolean;

  TEditorConfig = class
  public const
    FileName = '.editorconfig';
  public
    /// <summary>Wendet die Werte einer .editorconfig-Datei für AFileName auf ASettings an.
    /// ARoot meldet "root = true".</summary>
    class procedure Apply(const AText, AFileName: string; var ASettings: TFormatStyle;
      out ARoot: Boolean); static;
    /// <summary>Alle .editorconfig vom Ordner von AFileName aufwärts, die fernste zuerst.</summary>
    class function ForFile(const AFileName: string; const AReadFile: TEditorConfigReadFile;
      const ABase: TFormatStyle): TFormatStyle; static;
    /// <summary>Passt AFileName (nur der Name) auf das Abschnittsmuster APattern?</summary>
    class function Matches(const APattern, AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Projects.Paths;

function MatchWildcard(const APattern, AText: string): Boolean;
var
  P, T, Star, Mark: Integer;
begin
  // * und ? ohne Groß-/Kleinschreibung.
  P := 1;
  T := 1;
  Star := 0;
  Mark := 0;
  while T <= Length(AText) do
  begin
    if (P <= Length(APattern)) and ((APattern[P] = '?') or SameText(APattern[P], AText[T])) then
    begin
      Inc(P);
      Inc(T);
    end
    else if (P <= Length(APattern)) and (APattern[P] = '*') then
    begin
      Star := P;
      Mark := T;
      Inc(P);
    end
    else if Star > 0 then
    begin
      P := Star + 1;
      Inc(Mark);
      T := Mark;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (P <= Length(APattern)) and (APattern[P] = '*') do
  begin
    Inc(P);
  end;
  Result := P > Length(APattern);
end;

{ TEditorConfig }

class function TEditorConfig.Matches(const APattern, AFileName: string): Boolean;
var
  Open, Close: Integer;
  Prefix, Suffix: string;
  Alternative: string;
  Pattern: string;
begin
  Pattern := APattern;
  // Muster mit Pfad ("src/*.pas") gelten ab dem Ordner der .editorconfig; hier zählt nur der Name.
  if LastDelimiter('/', Pattern) > 0 then
  begin
    Pattern := Copy(Pattern, LastDelimiter('/', Pattern) + 1, MaxInt);
  end;
  Open := Pos('{', Pattern);
  Close := Pos('}', Pattern);
  if (Open > 0) and (Close > Open) then
  begin
    Prefix := Copy(Pattern, 1, Open - 1);
    Suffix := Copy(Pattern, Close + 1, MaxInt);
    for Alternative in Copy(Pattern, Open + 1, Close - Open - 1).Split([',']) do
    begin
      if MatchWildcard(Prefix + Trim(Alternative) + Suffix, AFileName) then
      begin
        Exit(True);
      end;
    end;
    Exit(False);
  end;
  Result := MatchWildcard(Pattern, AFileName);
end;

type
  /// <summary>Einrückung mit Tabs und tab_width: entscheiden erst am Ende, ob tab_width die Ebene bestimmt.</summary>
  TTabIndent = record
    IsTab: Boolean;
    TabWidth: Integer;
  end;

/// <summary>"key = value" in Kleinbuchstaben; False ohne "=".</summary>
function SplitEntry(const ALine: string; out AKey, AValue: string): Boolean;
var
  mEquals: Integer;
begin
  mEquals := Pos('=', ALine);
  Result := mEquals > 0;
  AKey := LowerCase(Trim(Copy(ALine, 1, mEquals - 1)));
  AValue := LowerCase(Trim(Copy(ALine, mEquals + 1, MaxInt)));
end;

/// <summary>"true" oder "false"; False bei anderen Werten.</summary>
function IsFlag(const AValue: string; out AFlag: Boolean): Boolean;
begin
  AFlag := AValue = 'true';
  Result := AFlag or (AValue = 'false');
end;

/// <summary>Ganze Zahl ab AMinimum.</summary>
function IsSize(const AValue: string; AMinimum: Integer; out ASize: Integer): Boolean;
begin
  Result := TryStrToInt(AValue, ASize) and (ASize >= AMinimum);
end;

/// <summary>indent_style, indent_size, tab_width; False bei anderen Schlüsseln oder Werten.</summary>
function ApplyIndent(const AKey, AValue: string; var ASettings: TFormatStyle; var ATabs: TTabIndent): Boolean;
var
  mSize: Integer;
begin
  Result := True;
  if AKey = 'indent_style' then
  begin
    ATabs.IsTab := AValue = 'tab';
    if ATabs.IsTab or (AValue = 'space') then
    begin
      ASettings.UseTabs := ATabs.IsTab;
    end;
  end
  else if (AKey = 'indent_size') and IsSize(AValue, 1, mSize) then
  begin
    ASettings.IndentSize := mSize;
  end
  else if (AKey = 'indent_size') and (AValue = 'tab') then
  begin
    ATabs.IsTab := True;
  end
  else if (AKey = 'tab_width') and IsSize(AValue, 1, mSize) then
  begin
    ATabs.TabWidth := mSize;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>end_of_line, trim_trailing_whitespace, insert_final_newline, max_line_length.</summary>
procedure ApplyLayout(const AKey, AValue: string; var ASettings: TFormatStyle);
var
  mSize: Integer;
  mFlag: Boolean;
begin
  if (AKey = 'end_of_line') and (AValue = 'lf') then
  begin
    ASettings.EndOfLine := #10;
  end
  else if (AKey = 'end_of_line') and (AValue = 'crlf') then
  begin
    ASettings.EndOfLine := #13#10;
  end
  else if (AKey = 'trim_trailing_whitespace') and IsFlag(AValue, mFlag) then
  begin
    ASettings.TrimTrailingWhitespace := mFlag;
  end
  else if (AKey = 'insert_final_newline') and IsFlag(AValue, mFlag) then
  begin
    ASettings.InsertFinalNewline := mFlag;
  end
  else if (AKey = 'max_line_length') and IsSize(AValue, 0, mSize) then
  begin
    ASettings.MaxLineLength := mSize;
  end
  else if (AKey = 'max_line_length') and (AValue = 'off') then
  begin
    ASettings.MaxLineLength := 0;
  end;
end;

/// <summary>Abschnittskopf "[Muster]": Gilt er für AName?</summary>
function SectionMatches(const ALine, AName: string): Boolean;
begin
  Result := (ALine[Length(ALine)] = ']') and TEditorConfig.Matches(Copy(ALine, 2, Length(ALine) - 2), AName);
end;

class procedure TEditorConfig.Apply(const AText, AFileName: string; var ASettings: TFormatStyle;
  out ARoot: Boolean);
var
  mLine, mEntry, mKey, mValue, mName: string;
  mInSection, mActive: Boolean;
  mTabs: TTabIndent;
begin
  ARoot := False;
  mInSection := False;
  mActive := False;
  mTabs := Default(TTabIndent);
  mName := ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  for mLine in AText.Replace(#13#10, #10).Split([#10]) do
  begin
    mEntry := Trim(mLine);
    if (mEntry = '') or CharInSet(mEntry[1], ['#', ';']) then
    begin
      Continue;
    end;
    if mEntry[1] = '[' then
    begin
      mInSection := True;
      mActive := SectionMatches(mEntry, mName);
    end
    else if not SplitEntry(mEntry, mKey, mValue) then
    begin
      Continue;
    end
    else if not mInSection then
    begin
      ARoot := ARoot or ((mKey = 'root') and (mValue = 'true'));
    end
    else if mActive and not ApplyIndent(mKey, mValue, ASettings, mTabs) then
    begin
      ApplyLayout(mKey, mValue, ASettings);
    end;
  end;
  // Mit Tabs bestimmt tab_width die Breite einer Ebene, wenn indent_size fehlt.
  if mTabs.IsTab and (mTabs.TabWidth > 0) then
  begin
    ASettings.IndentSize := mTabs.TabWidth;
  end;
end;

class function TEditorConfig.ForFile(const AFileName: string; const AReadFile: TEditorConfigReadFile;
  const ABase: TFormatStyle): TFormatStyle;
var
  Directory, Parent, Text: string;
  Texts: TList<string>;
  Root: Boolean;
  Index: Integer;
  Probe: TFormatStyle;
begin
  Result := ABase;
  Texts := TList<string>.Create;
  try
    Directory := TProjectPaths.DirectoryOf(AFileName);
    while Directory <> '' do
    begin
      if AReadFile(TProjectPaths.Combine(Directory, FileName), Text) then
      begin
        Texts.Add(Text);
        Probe := ABase;
        Apply(Text, AFileName, Probe, Root);
        if Root then
        begin
          Break;
        end;
      end;
      Parent := TProjectPaths.DirectoryOf(Directory);
      if (Parent = '') or SameText(Parent, Directory) then
      begin
        Break;
      end;
      Directory := Parent;
    end;
    // Die fernste Datei zuerst, damit nähere sie überschreiben.
    for Index := Texts.Count - 1 downto 0 do
    begin
      Apply(Texts[Index], AFileName, Result, Root);
    end;
  finally
    Texts.Free;
  end;
end;

end.
