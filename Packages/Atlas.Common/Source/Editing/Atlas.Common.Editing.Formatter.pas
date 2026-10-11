unit Atlas.Common.Editing.Formatter;

// Formatierung (#43), bewusst vorsichtig: Die Struktur des Codes bleibt, wie
// sie ist; geändert werden nur Leerraum und die Schreibweise reservierter
// Wörter.
//   - Einrückung: führende Tabs bzw. Leerzeichen in die eingestellte Art
//     umrechnen (Breite einer Ebene: indentSize)
//   - Leerzeichen am Zeilenende entfernen
//   - genau ein Leerzeichen um := und nach Kommas
//   - reservierte Wörter klein oder groß schreiben
//   - Zeilenende vereinheitlichen, abschließende Leerzeile
// Zeilen in mehrzeiligen Kommentaren und Strings sowie asm-Blöcke bleiben
// unverändert. Ergebnis sind Textänderungen je Zeile.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Contract;

type
  TFormatter = class
  public
    /// <summary>Änderungen für die Zeilen AFirstLine bis ALastLine (-1 = bis zum Ende).
    /// Zeilenenden und die abschließende Leerzeile nur bei der ganzen Datei.</summary>
    class function Edits(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle; AFirstLine: Integer = 0; ALastLine: Integer = -1): TArray<TRuleEdit>; static;
    /// <summary>Text nach dem Formatieren, z. B. für Tests und den Linter.</summary>
    class function FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TLineInfo = record
    /// <summary>Zeile liegt (ab Spalte 0) in einem mehrzeiligen Token oder einem asm-Block.</summary>
    Frozen: Boolean;
    /// <summary>Ein mehrzeiliges Token beginnt hier; das Zeilenende gehört ihm.</summary>
    KeepEnd: Boolean;
  end;

  TGapEdit = record
    StartColumn: Integer;
    EndColumn: Integer;
    Text: string;
  end;

function SplitLines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function DetectLineBreak(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

/// <summary>Führenden Leerraum nach Spalten umrechnen, Rest unverändert.</summary>
function Reindent(const ALine: string; const ASettings: TFormatStyle): string;
var
  Index, Columns: Integer;
begin
  Index := 1;
  Columns := 0;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    if ALine[Index] = #9 then
      Columns := (Columns div ASettings.IndentSize + 1) * ASettings.IndentSize
    else
      Inc(Columns);
    Inc(Index);
  end;
  if Index > Length(ALine) then
    // Nur Leerraum: Zeile wird leer (falls getrimmt) oder bleibt.
    Exit(ALine);
  if ASettings.UseTabs then
    Result := StringOfChar(#9, Columns div ASettings.IndentSize) + StringOfChar(' ', Columns mod ASettings.IndentSize)
  else
    Result := StringOfChar(' ', Columns);
  Result := Result + Copy(ALine, Index, MaxInt);
end;

procedure AddGap(AEdits: TList<TGapEdit>; AStart, AEnd: Integer; const AText: string);
var
  Edit: TGapEdit;
begin
  Edit.StartColumn := AStart;
  Edit.EndColumn := AEnd;
  Edit.Text := AText;
  AEdits.Add(Edit);
end;

{ TFormatter }

class function TFormatter.Edits(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer): TArray<TRuleEdit>;
var
  Lines, Formatted: TArray<string>;
  Info: TArray<TLineInfo>;
  Gaps: TArray<TList<TGapEdit>>;
  Index, Line, AsmDepth: Integer;
  Token, Previous, Next: TPascalToken;
  Settings: TFormatStyle;
  Text, LB, Wanted: string;
  Gap: TGapEdit;
  Found: TList<TRuleEdit>;
  WholeFile, Changed: Boolean;
  LastLine: Integer;
begin
  Settings := ASettings;
  if Settings.IndentSize < 1 then
    Settings.IndentSize := 2;
  Lines := SplitLines(AText);
  SetLength(Info, Length(Lines));
  SetLength(Gaps, Length(Lines));
  for Line := 0 to High(Lines) do
    Gaps[Line] := TList<TGapEdit>.Create;
  Found := TList<TRuleEdit>.Create;
  try
    // Mehrzeilige Tokens und asm-Blöcke einfrieren.
    AsmDepth := 0;
    for Index := 0 to High(ATokens) do
    begin
      Token := ATokens[Index];
      if Token.EndPos.Line > Token.StartPos.Line then
      begin
        Info[Token.StartPos.Line].KeepEnd := True;
        for Line := Token.StartPos.Line + 1 to Min(Token.EndPos.Line, High(Lines)) do
          Info[Line].Frozen := True;
      end;
      if (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('asm') then
        Inc(AsmDepth)
      else if (AsmDepth > 0) and (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('end') then
      begin
        Dec(AsmDepth);
        Continue;
      end;
      if AsmDepth > 0 then
      begin
        // Zeilen nach "asm" bis zum end bleiben, wie sie sind.
        if not Token.IsKeyword('asm') then
          for Line := Token.StartPos.Line to Min(Token.EndPos.Line, High(Lines)) do
            Info[Line].Frozen := True;
        Continue;
      end;
      if (Token.StartPos.Line >= Length(Lines)) or Info[Token.StartPos.Line].Frozen then
        Continue;
      // Schreibweise reservierter Wörter.
      if (Token.Kind = TPascalTokenKind.Keyword) and (Settings.KeywordCase <> TKeywordCase.Preserve) then
      begin
        if Settings.KeywordCase = TKeywordCase.Lower then
          Wanted := LowerCase(Token.Text)
        else
          Wanted := UpperCase(Token.Text);
        if Wanted <> Token.Text then
          AddGap(Gaps[Token.StartPos.Line], Token.StartPos.Character, Token.EndPos.Character, Wanted);
      end;
      if Token.Kind <> TPascalTokenKind.Symbol then
        Continue;
      if (Token.Text = ':=') and Settings.SpaceAroundAssignment then
      begin
        if Index > 0 then
        begin
          Previous := ATokens[Index - 1];
          if (Previous.EndPos.Line = Token.StartPos.Line) and
            (Token.StartPos.Character - Previous.EndPos.Character <> 1) then
            AddGap(Gaps[Token.StartPos.Line], Previous.EndPos.Character, Token.StartPos.Character, ' ');
        end;
        if Index < High(ATokens) then
        begin
          Next := ATokens[Index + 1];
          if (Next.StartPos.Line = Token.EndPos.Line) and (Next.StartPos.Character - Token.EndPos.Character <> 1) then
            AddGap(Gaps[Token.StartPos.Line], Token.EndPos.Character, Next.StartPos.Character, ' ');
        end;
      end
      else if (Token.Text = ',') and Settings.SpaceAfterComma and (Index < High(ATokens)) then
      begin
        Next := ATokens[Index + 1];
        if (Next.StartPos.Line = Token.EndPos.Line) and (Next.StartPos.Character - Token.EndPos.Character <> 1) then
          AddGap(Gaps[Token.StartPos.Line], Token.EndPos.Character, Next.StartPos.Character, ' ');
      end;
    end;
    if ALastLine < 0 then
      LastLine := High(Lines)
    else
      LastLine := Min(ALastLine, High(Lines));
    Formatted := Copy(Lines);
    for Line := Max(AFirstLine, 0) to LastLine do
    begin
      if Info[Line].Frozen then
        Continue;
      Text := Lines[Line];
      // Von rechts nach links, damit die Spalten gültig bleiben.
      Gaps[Line].Sort(TComparer<TGapEdit>.Construct(
        function(const A, B: TGapEdit): Integer
        begin
          Result := B.StartColumn - A.StartColumn;
        end));
      for Gap in Gaps[Line] do
        Text := Copy(Text, 1, Gap.StartColumn) + Gap.Text + Copy(Text, Gap.EndColumn + 1, MaxInt);
      Text := Reindent(Text, Settings);
      if Settings.TrimTrailingWhitespace and not Info[Line].KeepEnd then
        Text := TrimRight(Text);
      Formatted[Line] := Text;
      if Formatted[Line] <> Lines[Line] then
        Found.Add(TRuleEdit.Create(TTextRange.Create(Line, 0, Line, Length(Lines[Line])), Formatted[Line]));
    end;
    WholeFile := (AFirstLine <= 0) and (ALastLine < 0);
    if WholeFile then
    begin
      LB := DetectLineBreak(AText);
      Changed := (Settings.EndOfLine <> '') and (Settings.EndOfLine <> LB) and (Length(Lines) > 1);
      if Changed then
      begin
        // Neue Zeilenenden: die ganze Datei auf einmal ersetzen.
        Found.Clear;
        Text := string.Join(Settings.EndOfLine, Formatted);
        if Settings.InsertFinalNewline and (Text <> '') and not Text.EndsWith(Settings.EndOfLine) then
          Text := Text + Settings.EndOfLine;
        Found.Add(TRuleEdit.Create(TTextRange.Create(0, 0, High(Lines), Length(Lines[High(Lines)])), Text));
      end
      else if Settings.InsertFinalNewline and (Formatted[High(Formatted)] <> '') then
        Found.Add(TRuleEdit.Create(TTextRange.Create(High(Lines), Length(Lines[High(Lines)]), High(Lines),
          Length(Lines[High(Lines)])), LB));
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    for Line := 0 to High(Gaps) do
      Gaps[Line].Free;
  end;
end;

class function TFormatter.FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Edits: TArray<TRuleEdit>;
  Index: Integer;
  LB: string;
begin
  Edits := TFormatter.Edits(AText, ATokens, ASettings);
  // Ganze Datei ersetzt (neue Zeilenenden).
  if (Length(Edits) = 1) and (Edits[0].Range.StartPos.Line = 0) and (Edits[0].Range.StartPos.Character = 0) and
    (Edits[0].Range.EndPos.Line > 0) then
    Exit(Edits[0].NewText);
  LB := DetectLineBreak(AText);
  Lines := SplitLines(AText);
  for Index := High(Edits) downto 0 do
  begin
    Edit := Edits[Index];
    Lines[Edit.Range.StartPos.Line] := Copy(Lines[Edit.Range.StartPos.Line], 1, Edit.Range.StartPos.Character) +
      Edit.NewText + Copy(Lines[Edit.Range.StartPos.Line], Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(LB, Lines);
end;

end.
