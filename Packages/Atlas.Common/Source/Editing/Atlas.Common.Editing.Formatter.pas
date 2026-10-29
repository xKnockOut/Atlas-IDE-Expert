unit Atlas.Common.Editing.Formatter;

// Formatierung (#43). Die Tokenfolge bleibt immer gleich; geändert werden
// Leerraum, Zeilenumbrüche und die Schreibweise reservierter Wörter:
//   - Stellung von begin und else (Formatter.Layout, format.beginPlacement,
//     format.elsePlacement)
//   - Einrückung aus der Blockstruktur (Formatter.Indent, format.reindent),
//     sonst führende Tabs bzw. Leerzeichen in die eingestellte Art umrechnen
//   - Leerzeichen am Zeilenende entfernen
//   - genau ein Leerzeichen um := und nach Kommas
//   - reservierte Wörter klein oder groß schreiben
//   - Zuweisungen, Deklarationen und Kommentare ausrichten (format.align*)
//   - lange Zeilen umbrechen (format.maxLineLength)
//   - Zeilenende vereinheitlichen, abschließende Leerzeile
// Zeilen in mehrzeiligen Kommentaren und Strings sowie asm-Blöcke bleiben
// unverändert, ebenso Bereiche von "// atlas-format: off" bis "// atlas-format: on"
// samt dieser Zeilen (#1358; auch in { } und (* *), ohne "on" bis zum Dateiende).
// Ergebnis sind Textänderungen je Zeile bzw. Zeilenbereich.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  TFormatter = class
  public
    /// <summary>Änderungen für die Zeilen AFirstLine bis ALastLine (-1 = bis zum Ende).
    /// Zeilenenden und die abschließende Leerzeile nur bei der ganzen Datei.</summary>
    class function Edits(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle; AFirstLine: Integer = 0; ALastLine: Integer = -1): TArray<TTextEdit>; static;
    /// <summary>Text nach dem Formatieren, z. B. für Tests und den Linter.</summary>
    class function FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter.Indent,
  Atlas.Common.Editing.Formatter.Layout;

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

/// <summary>Breite des führenden Leerraums in Spalten (Tab bis zur nächsten Ebene).</summary>
function LeadingColumns(const ALine: string; AIndentSize: Integer; out ALength: Integer): Integer;
var
  Index: Integer;
begin
  Index := 1;
  Result := 0;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    if ALine[Index] = #9 then
      Result := (Result div AIndentSize + 1) * AIndentSize
    else
      Inc(Result);
    Inc(Index);
  end;
  ALength := Index - 1;
end;

/// <summary>Führenden Leerraum nach Spalten umrechnen (AColumn &lt; 0: vorhandene Breite), Rest unverändert.</summary>
function Reindent(const ALine: string; const ASettings: TFormatStyle; AColumn: Integer): string;
var
  Index, Columns: Integer;
begin
  Columns := LeadingColumns(ALine, ASettings.IndentSize, Index);
  Inc(Index);
  if Index > Length(ALine) then
    // Nur Leerraum: Zeile wird leer (falls getrimmt) oder bleibt.
    Exit(ALine);
  if AColumn >= 0 then
    Columns := AColumn;
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

/// <summary>Leerraum, Einrückung und Schreibweise je Zeile (Zeilen mit Ursprung in AFirst..ALast).</summary>
procedure FormatLines(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirst, ALast: Integer);
var
  Info: TArray<TLineInfo>;
  Gaps: TArray<TList<TGapEdit>>;
  Columns, Leading: TArray<Integer>;
  Index, Line, AsmDepth, Width: Integer;
  Token, Previous, Next: TPascalToken;
  Text, Wanted: string;
  Gap: TGapEdit;
begin
  SetLength(Info, Length(ALines));
  SetLength(Gaps, Length(ALines));
  for Line := 0 to High(ALines) do
    Gaps[Line] := TList<TGapEdit>.Create;
  try
    // Mehrzeilige Tokens und asm-Blöcke einfrieren.
    AsmDepth := 0;
    for Index := 0 to High(ATokens) do
    begin
      Token := ATokens[Index];
      if Token.StartPos.Line > High(ALines) then
        Break;
      if Token.EndPos.Line > Token.StartPos.Line then
      begin
        Info[Token.StartPos.Line].KeepEnd := True;
        for Line := Token.StartPos.Line + 1 to Min(Token.EndPos.Line, High(ALines)) do
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
          for Line := Token.StartPos.Line to Min(Token.EndPos.Line, High(ALines)) do
            Info[Line].Frozen := True;
        Continue;
      end;
      if Info[Token.StartPos.Line].Frozen then
        Continue;
      // Schreibweise reservierter Wörter.
      if (Token.Kind = TPascalTokenKind.Keyword) and (ASettings.KeywordCase <> TKeywordCase.Preserve) then
      begin
        if ASettings.KeywordCase = TKeywordCase.Lower then
          Wanted := LowerCase(Token.Text)
        else
          Wanted := UpperCase(Token.Text);
        if Wanted <> Token.Text then
          AddGap(Gaps[Token.StartPos.Line], Token.StartPos.Character, Token.EndPos.Character, Wanted);
      end;
      if Token.Kind <> TPascalTokenKind.Symbol then
        Continue;
      if (Token.Text = ':=') and ASettings.SpaceAroundAssignment then
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
      else if (Token.Text = ',') and ASettings.SpaceAfterComma and (Index < High(ATokens)) then
      begin
        Next := ATokens[Index + 1];
        if (Next.StartPos.Line = Token.EndPos.Line) and (Next.StartPos.Character - Token.EndPos.Character <> 1) then
          AddGap(Gaps[Token.StartPos.Line], Token.EndPos.Character, Next.StartPos.Character, ' ');
      end;
    end;
    // Einrückung aus der Blockstruktur (#43).
    Columns := nil;
    if ASettings.Reindent then
    begin
      SetLength(Leading, Length(ALines));
      for Line := 0 to High(ALines) do
        Leading[Line] := LeadingColumns(ALines[Line].Text, ASettings.IndentSize, Width);
      Columns := TBlockIndenter.Columns(ATokens, Leading, ASettings.IndentSize);
    end;
    for Line := 0 to High(ALines) do
    begin
      if Info[Line].Frozen or (ALines[Line].Origin < AFirst) or (ALines[Line].Origin > ALast) then
        Continue;
      Text := ALines[Line].Text;
      // Von rechts nach links, damit die Spalten gültig bleiben.
      Gaps[Line].Sort(TComparer<TGapEdit>.Construct(
        function(const A, B: TGapEdit): Integer
        begin
          Result := B.StartColumn - A.StartColumn;
        end));
      for Gap in Gaps[Line] do
        Text := Copy(Text, 1, Gap.StartColumn) + Gap.Text + Copy(Text, Gap.EndColumn + 1, MaxInt);
      if Columns <> nil then
        Text := Reindent(Text, ASettings, Columns[Line])
      else
        Text := Reindent(Text, ASettings, -1);
      if ASettings.TrimTrailingWhitespace and not Info[Line].KeepEnd then
        Text := TrimRight(Text);
      ALines[Line].Text := Text;
    end;
  finally
    for Line := 0 to High(Gaps) do
      Gaps[Line].Free;
  end;
end;

function JoinTexts(const ALines: TArray<TFormatLine>; const ALineBreak: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := 0 to High(ALines) do
    begin
      if Index > 0 then
        Builder.Append(ALineBreak);
      Builder.Append(ALines[Index].Text);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// <summary>"atlas-format: off" bzw. "on" in einem Kommentar (#1358); Leerzeichen und Groß-/Kleinschreibung zählen
/// nicht. AOff gibt an, welche Marke es ist.</summary>
function IsFormatMarker(const AToken: TPascalToken; out AOff: Boolean): Boolean;
var
  mText: string;
begin
  Result := False;
  AOff := False;
  if AToken.Kind <> TPascalTokenKind.Comment then
    Exit;
  mText := AToken.Text;
  if mText.StartsWith('//') then
    mText := Copy(mText, 3, MaxInt)
  else if mText.StartsWith('(*') then
    mText := Copy(mText, 3, Length(mText) - 4)
  else if mText.StartsWith('{') then
    mText := Copy(mText, 2, Length(mText) - 2);
  mText := LowerCase(StringReplace(mText, ' ', '', [rfReplaceAll])).Trim;
  if mText = 'atlas-format:off' then
  begin
    AOff := True;
    Result := True;
  end
  else
    Result := mText = 'atlas-format:on';
end;

/// <summary>Zeilen von ALineCount, die zwischen den Marken liegen (#1358), samt der Zeilen der Marken.</summary>
function ProtectedLines(const ATokens: TArray<TPascalToken>; ALineCount: Integer): TArray<Boolean>;
var
  mToken: TPascalToken;
  mIsOff: Boolean;
  mOffLine, mLine: Integer;
begin
  SetLength(Result, ALineCount);
  mOffLine := -1;
  for mToken in ATokens do
  begin
    if not IsFormatMarker(mToken, mIsOff) then
      Continue;
    if mIsOff and (mOffLine < 0) then
      mOffLine := mToken.StartPos.Line
    else if not mIsOff and (mOffLine >= 0) then
    begin
      for mLine := mOffLine to Min(mToken.EndPos.Line, ALineCount - 1) do
        Result[mLine] := True;
      mOffLine := -1;
    end;
  end;
  if mOffLine >= 0 then
    for mLine := mOffLine to ALineCount - 1 do
      Result[mLine] := True;
end;

/// <summary>Geschützte Zeilen (#1358) wie im Original: Jede Gruppe aus einer Ursprungszeile und den an sie
/// gehängten Folgezeilen, die eine geschützte Zeile enthält, kommt unverändert zurück.</summary>
procedure KeepProtected(var ALines: TArray<TFormatLine>; const AOriginal: TArray<string>;
  var AJoined: TArray<Boolean>; const AProtected: TArray<Boolean>);
var
  mKept: TList<TFormatLine>;
  mItem: TFormatLine;
  mLine, mStop, mIndex, mEach: Integer;
  mHit, mAny: Boolean;
begin
  mAny := False;
  for mEach := 0 to High(AProtected) do
    mAny := mAny or AProtected[mEach];
  if not mAny then
    Exit;
  mKept := TList<TFormatLine>.Create;
  try
    mIndex := 0;
    mLine := 0;
    while mLine <= High(AOriginal) do
    begin
      mStop := mLine;
      while (mStop < High(AOriginal)) and AJoined[mStop + 1] do
        Inc(mStop);
      mHit := False;
      for mEach := mLine to mStop do
        mHit := mHit or AProtected[mEach];
      if mHit then
      begin
        while (mIndex <= High(ALines)) and (ALines[mIndex].Origin <= mStop) do
          Inc(mIndex);
        for mEach := mLine to mStop do
        begin
          mItem.Text := AOriginal[mEach];
          mItem.Origin := mEach;
          mKept.Add(mItem);
          AJoined[mEach] := False;
        end;
      end
      else
        while (mIndex <= High(ALines)) and (ALines[mIndex].Origin <= mStop) do
        begin
          mKept.Add(ALines[mIndex]);
          Inc(mIndex);
        end;
      mLine := mStop + 1;
    end;
    while mIndex <= High(ALines) do
    begin
      mKept.Add(ALines[mIndex]);
      Inc(mIndex);
    end;
    ALines := mKept.ToArray;
  finally
    mKept.Free;
  end;
end;

/// <summary>Alle Schritte; Zeilen mit Ursprung und die an die vorige Zeile gehängten Ursprungszeilen.</summary>
function Pipeline(const AText: string; const ATokens: TArray<TPascalToken>; const ASettings: TFormatStyle;
  AFirstLine, ALastLine: Integer; out AOriginal: TArray<string>; out AJoined: TArray<Boolean>): TArray<TFormatLine>;
var
  Settings: TFormatStyle;
  Tokens: TArray<TPascalToken>;
  LB: string;
  First, Last, Round: Integer;
  Kind: TFormatAlignment;
begin
  Settings := ASettings;
  if Settings.IndentSize < 1 then
    Settings.IndentSize := 2;
  LB := TTextLines.LineBreakOf(AText);
  AOriginal := TTextLines.SplitLines(AText);
  First := Max(AFirstLine, 0);
  if ALastLine < 0 then
    Last := High(AOriginal)
  else
    Last := Min(ALastLine, High(AOriginal));
  Result := TFormatLayout.Place(AOriginal, ATokens, Settings, First, Last, AJoined);
  if Length(Result) = Length(AOriginal) then
    Tokens := ATokens
  else
    Tokens := TPascalLexer.Tokenize(JoinTexts(Result, LB));
  FormatLines(Result, Tokens, Settings, First, Last);
  for Kind := Low(TFormatAlignment) to High(TFormatAlignment) do
    if ((Kind = TFormatAlignment.Assignments) and Settings.AlignAssignments) or
      ((Kind in [TFormatAlignment.Declarations, TFormatAlignment.Constants]) and Settings.AlignDeclarations) or
      ((Kind = TFormatAlignment.Comments) and Settings.AlignComments) then
      TFormatLayout.Align(Result, TPascalLexer.Tokenize(JoinTexts(Result, LB)), Kind, First, Last);
  if Settings.MaxLineLength > 0 then
    for Round := 1 to 64 do
      if not TFormatLayout.Wrap(Result, TPascalLexer.Tokenize(JoinTexts(Result, LB)), Settings, First, Last) then
        Break;
  KeepProtected(Result, AOriginal, AJoined, ProtectedLines(ATokens, Length(AOriginal)));
end;

class function TFormatter.Edits(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer): TArray<TTextEdit>;
var
  Original: TArray<string>;
  Joined: TArray<Boolean>;
  Lines: TArray<TFormatLine>;
  Found: TList<TTextEdit>;
  LB, Text, OldText: string;
  Line, Index, Stop: Integer;
  WholeFile, FirstPart: Boolean;
begin
  Lines := Pipeline(AText, ATokens, ASettings, AFirstLine, ALastLine, Original, Joined);
  LB := TTextLines.LineBreakOf(AText);
  Found := TList<TTextEdit>.Create;
  try
    WholeFile := (AFirstLine <= 0) and (ALastLine < 0);
    if WholeFile and (ASettings.EndOfLine <> '') and (ASettings.EndOfLine <> LB) and (Length(Original) > 1) then
    begin
      // Neue Zeilenenden: die ganze Datei auf einmal ersetzen.
      Text := JoinTexts(Lines, ASettings.EndOfLine);
      if ASettings.InsertFinalNewline and (Text <> '') and not Text.EndsWith(ASettings.EndOfLine) then
        Text := Text + ASettings.EndOfLine;
      Found.Add(TTextEdit.Create(TTextRange.Create(0, 0, High(Original), Length(Original[High(Original)])), Text));
      Exit(Found.ToArray);
    end;
    // Je Ursprungszeile (samt angehängter Folgezeilen) eine Änderung.
    Index := 0;
    for Line := 0 to High(Original) do
    begin
      if Joined[Line] then
        Continue;
      Stop := Line;
      while (Stop < High(Original)) and Joined[Stop + 1] do
        Inc(Stop);
      Text := '';
      OldText := Original[Line];
      FirstPart := True;
      while (Index <= High(Lines)) and (Lines[Index].Origin <= Stop) do
      begin
        if not FirstPart then
          Text := Text + LB;
        FirstPart := False;
        Text := Text + Lines[Index].Text;
        Inc(Index);
      end;
      if (Stop > Line) or (Text <> OldText) then
        Found.Add(TTextEdit.Create(TTextRange.Create(Line, 0, Stop, Length(Original[Stop])), Text));
    end;
    if WholeFile and ASettings.InsertFinalNewline and (Lines <> nil) and (Lines[High(Lines)].Text <> '') then
      Found.Add(TTextEdit.Create(TTextRange.Create(High(Original), Length(Original[High(Original)]),
        High(Original), Length(Original[High(Original)])), LB));
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TFormatter.FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle): string;
var
  Original: TArray<string>;
  Joined: TArray<Boolean>;
  Lines: TArray<TFormatLine>;
  LB: string;
begin
  Lines := Pipeline(AText, ATokens, ASettings, 0, -1, Original, Joined);
  LB := TTextLines.LineBreakOf(AText);
  if (ASettings.EndOfLine <> '') and (Length(Original) > 1) then
    LB := ASettings.EndOfLine;
  Result := JoinTexts(Lines, LB);
  if ASettings.InsertFinalNewline and (Lines <> nil) and (Lines[High(Lines)].Text <> '') then
    Result := Result + LB;
end;

end.
