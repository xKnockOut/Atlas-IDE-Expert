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
      Exit(False);
  end;
  while (P <= Length(APattern)) and (APattern[P] = '*') do
    Inc(P);
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
    Pattern := Copy(Pattern, LastDelimiter('/', Pattern) + 1, MaxInt);
  Open := Pos('{', Pattern);
  Close := Pos('}', Pattern);
  if (Open > 0) and (Close > Open) then
  begin
    Prefix := Copy(Pattern, 1, Open - 1);
    Suffix := Copy(Pattern, Close + 1, MaxInt);
    for Alternative in Copy(Pattern, Open + 1, Close - Open - 1).Split([',']) do
      if MatchWildcard(Prefix + Trim(Alternative) + Suffix, AFileName) then
        Exit(True);
    Exit(False);
  end;
  Result := MatchWildcard(Pattern, AFileName);
end;

class procedure TEditorConfig.Apply(const AText, AFileName: string; var ASettings: TFormatStyle;
  out ARoot: Boolean);
var
  Line, Key, Value, Name: string;
  Equals: Integer;
  InSection, Active: Boolean;
  Size, TabWidth: Integer;
  IndentIsTab: Boolean;
begin
  ARoot := False;
  InSection := False;
  Active := False;
  TabWidth := 0;
  IndentIsTab := False;
  Name := ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  for Line in AText.Replace(#13#10, #10).Split([#10]) do
  begin
    Value := Trim(Line);
    if (Value = '') or CharInSet(Value[1], ['#', ';']) then
      Continue;
    if Value[1] = '[' then
    begin
      InSection := True;
      Active := (Value[Length(Value)] = ']') and Matches(Copy(Value, 2, Length(Value) - 2), Name);
      Continue;
    end;
    Equals := Pos('=', Value);
    if Equals = 0 then
      Continue;
    Key := LowerCase(Trim(Copy(Value, 1, Equals - 1)));
    Value := LowerCase(Trim(Copy(Value, Equals + 1, MaxInt)));
    if not InSection then
    begin
      if (Key = 'root') and (Value = 'true') then
        ARoot := True;
      Continue;
    end;
    if not Active then
      Continue;
    if Key = 'indent_style' then
    begin
      IndentIsTab := Value = 'tab';
      if Value = 'tab' then
        ASettings.UseTabs := True
      else if Value = 'space' then
        ASettings.UseTabs := False;
    end
    else if (Key = 'indent_size') and TryStrToInt(Value, Size) and (Size >= 1) then
      ASettings.IndentSize := Size
    else if (Key = 'indent_size') and (Value = 'tab') then
      IndentIsTab := True
    else if (Key = 'tab_width') and TryStrToInt(Value, Size) and (Size >= 1) then
      TabWidth := Size
    else if Key = 'end_of_line' then
    begin
      if Value = 'lf' then
        ASettings.EndOfLine := #10
      else if Value = 'crlf' then
        ASettings.EndOfLine := #13#10;
    end
    else if (Key = 'trim_trailing_whitespace') and ((Value = 'true') or (Value = 'false')) then
      ASettings.TrimTrailingWhitespace := Value = 'true'
    else if (Key = 'insert_final_newline') and ((Value = 'true') or (Value = 'false')) then
      ASettings.InsertFinalNewline := Value = 'true'
    else if (Key = 'max_line_length') and TryStrToInt(Value, Size) and (Size >= 0) then
      ASettings.MaxLineLength := Size
    else if (Key = 'max_line_length') and (Value = 'off') then
      ASettings.MaxLineLength := 0;
  end;
  // Mit Tabs bestimmt tab_width die Breite einer Ebene, wenn indent_size fehlt.
  if IndentIsTab and (TabWidth > 0) then
    ASettings.IndentSize := TabWidth;
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
          Break;
      end;
      Parent := TProjectPaths.DirectoryOf(Directory);
      if (Parent = '') or SameText(Parent, Directory) then
        Break;
      Directory := Parent;
    end;
    // Die fernste Datei zuerst, damit nähere sie überschreiben.
    for Index := Texts.Count - 1 downto 0 do
      Apply(Texts[Index], AFileName, Result, Root);
  finally
    Texts.Free;
  end;
end;

end.
