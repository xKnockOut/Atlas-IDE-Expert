unit Atlas.Common.Editing.FormatCheck;

// Formatieren ohne Editor (#1358): derselbe Formatierer wie „Dokument
// formatieren“ (TFormatter.Edits, #43), für die ganze Datei oder nur für
// Zeilenbereiche wie textDocument/rangeFormatting (geänderte Zeilen aus Git
// bzw. SVN). Dazu:
//   - Abweichungen je Zeile mit Art und Text („Einrückung 3 statt 2“: erst
//     der Ist-, dann der Sollwert), aus dem Zeilenvergleich von altem und
//     formatiertem Text
//   - Syntaxfehler: Eine Datei, die der Parser nicht fehlerfrei liest, wird
//     nicht formatiert (Ergebnis = Original)
//   - Stabilität: Ein zweiter Lauf auf dem Ergebnis darf nichts mehr ändern
// Zeilen außerhalb der Bereiche bleiben Zeichen für Zeichen gleich; die
// Zeilenumbrüche des Originals bleiben, außer format.endOfLine verlangt andere.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zeilen First bis Last (0-basiert, einschließlich).</summary>
  TFormatLineSpan = record
    First: Integer;
    Last: Integer;
    class function Create(AFirst, ALast: Integer): TFormatLineSpan; static;
  end;

  /// <summary>Ganze Datei oder nur die Zeilen der Bereiche (leer = nichts formatieren).</summary>
  TFormatScope = record
    WholeFile: Boolean;
    Spans: TArray<TFormatLineSpan>;
    class function All: TFormatScope; static;
    class function Lines(const ASpans: TArray<TFormatLineSpan>): TFormatScope; static;
  end;

  {$SCOPEDENUMS ON}
  TFormatDeviationKind = (Indent, IndentChars, KeywordCase, SpaceAssignment, SpaceComma, TrailingWhitespace,
    Alignment, LineBreaks, EndOfLine, FinalNewline);
  {$SCOPEDENUMS OFF}

  TFormatDeviation = record
    /// <summary>Zeile im Original, 0-basiert.</summary>
    Line: Integer;
    Kind: TFormatDeviationKind;
    Message: string;
    class function Create(ALine: Integer; AKind: TFormatDeviationKind; const AMessage: string): TFormatDeviation;
      static;
  end;

  TFormatOutcome = record
    Original: string;
    /// <summary>Ergebnis; bei Syntaxfehlern gleich Original.</summary>
    Formatted: string;
    Deviations: TArray<TFormatDeviation>;
    HasSyntaxError: Boolean;
    /// <summary>Erster Syntaxfehler, nur mit HasSyntaxError.</summary>
    SyntaxError: TSyntaxDiagnostic;
    /// <summary>Ein zweiter Lauf auf Formatted ändert nichts mehr.</summary>
    Stable: Boolean;
    /// <summary>Formatted weicht von Original ab.</summary>
    function Changed: Boolean;
  end;

  TFormatCheck = class
  public
    /// <summary>Änderungen des Formatierers für AScope, wie „Dokument formatieren“ bzw. „Auswahl formatieren“.
    /// Mehrere Bereiche überlappen nie; nebeneinanderliegende werden zusammengefasst.</summary>
    class function Edits(const AText: string; const AStyle: TFormatStyle; const AScope: TFormatScope):
      TArray<TTextEdit>; static;
    /// <summary>AText nach dem Formatieren von AScope.</summary>
    class function FormatText(const AText: string; const AStyle: TFormatStyle; const AScope: TFormatScope): string;
      static;
    /// <summary>Abweichungen von AOld zu ANew (formatiert) je Zeile von AOld, aufsteigend.</summary>
    class function Deviations(const AOld, ANew: string; const AStyle: TFormatStyle): TArray<TFormatDeviation>;
      static;
    /// <summary>Prüft AText mit den Symbolen aus AOptions auf Syntaxfehler, formatiert AScope, beschreibt die
    /// Abweichungen und prüft die Stabilität.</summary>
    class function Run(const AText: string; const AStyle: TFormatStyle; const AScope: TFormatScope;
      const AOptions: TPreprocessorOptions): TFormatOutcome; static;
    /// <summary>Kennung für JSON, z. B. "indent".</summary>
    class function KindName(AKind: TFormatDeviationKind): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.TextChanges;

{ TFormatLineSpan }

class function TFormatLineSpan.Create(AFirst, ALast: Integer): TFormatLineSpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

{ TFormatScope }

class function TFormatScope.All: TFormatScope;
begin
  Result.WholeFile := True;
  Result.Spans := nil;
end;

class function TFormatScope.Lines(const ASpans: TArray<TFormatLineSpan>): TFormatScope;
begin
  Result.WholeFile := False;
  Result.Spans := ASpans;
end;

{ TFormatDeviation }

class function TFormatDeviation.Create(ALine: Integer; AKind: TFormatDeviationKind;
  const AMessage: string): TFormatDeviation;
begin
  Result.Line := ALine;
  Result.Kind := AKind;
  Result.Message := AMessage;
end;

{ TFormatOutcome }

function TFormatOutcome.Changed: Boolean;
begin
  Result := Formatted <> Original;
end;

{ TFormatCheck }

/// <summary>Bereiche aufsteigend; überlappende und nebeneinanderliegende zusammengefasst.</summary>
function MergedSpans(const ASpans: TArray<TFormatLineSpan>): TArray<TFormatLineSpan>;
var
  mSorted: TArray<TFormatLineSpan>;
  mSpan: TFormatLineSpan;
begin
  Result := nil;
  mSorted := Copy(ASpans);
  TArray.Sort<TFormatLineSpan>(mSorted, TComparer<TFormatLineSpan>.Construct(
    function(const A, B: TFormatLineSpan): Integer
    begin
      Result := A.First - B.First;
      if Result = 0 then
        Result := A.Last - B.Last;
    end));
  for mSpan in mSorted do
  begin
    if mSpan.Last < mSpan.First then
      Continue;
    if (Result <> nil) and (mSpan.First <= Result[High(Result)].Last + 1) then
      Result[High(Result)].Last := Max(Result[High(Result)].Last, mSpan.Last)
    else
      Result := Result + [mSpan];
  end;
end;

/// <summary>A liegt ganz vor B (Ende von A vor oder am Anfang von B).</summary>
function EndsBefore(const A, B: TTextRange): Boolean;
begin
  Result := (A.EndPos.Line < B.StartPos.Line) or
    ((A.EndPos.Line = B.StartPos.Line) and (A.EndPos.Character <= B.StartPos.Character));
end;

class function TFormatCheck.Edits(const AText: string; const AStyle: TFormatStyle;
  const AScope: TFormatScope): TArray<TTextEdit>;
var
  mTokens: TArray<TPascalToken>;
  mSpan: TFormatLineSpan;
  mEdit: TTextEdit;
  mFound: TList<TTextEdit>;
  mFree: Boolean;
  mIndex: Integer;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  if AScope.WholeFile then
    Exit(TFormatter.Edits(AText, mTokens, AStyle, 0, -1));
  mFound := TList<TTextEdit>.Create;
  try
    for mSpan in MergedSpans(AScope.Spans) do
      for mEdit in TFormatter.Edits(AText, mTokens, AStyle, mSpan.First, mSpan.Last) do
      begin
        // Sicherheitsnetz: Ein Umbruch über die Grenze zweier Bereiche darf keine überlappenden Änderungen
        // ergeben (die Bereiche sind getrennt, die Gruppen des Formatierers bleiben in einem Bereich).
        mFree := True;
        for mIndex := 0 to mFound.Count - 1 do
          if not (EndsBefore(mFound[mIndex].Range, mEdit.Range) or EndsBefore(mEdit.Range, mFound[mIndex].Range))
          then
            mFree := False;
        if mFree then
          mFound.Add(mEdit);
      end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

class function TFormatCheck.FormatText(const AText: string; const AStyle: TFormatStyle;
  const AScope: TFormatScope): string;
begin
  Result := TTextChanges.Apply(AText, Edits(AText, AStyle, AScope));
end;

/// <summary>Breite des führenden Leerraums in Spalten (Tab bis zur nächsten Ebene) und ob ein Tab darin steht.
/// </summary>
function LeadingWidth(const ALine: string; AIndentSize: Integer; out AHasTab: Boolean;
  out ALength: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  AHasTab := False;
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    if ALine[mIndex] = #9 then
    begin
      AHasTab := True;
      Result := (Result div AIndentSize + 1) * AIndentSize;
    end
    else
      Inc(Result);
    Inc(mIndex);
  end;
  ALength := mIndex - 1;
end;

/// <summary>Abweichung der Art AKind höchstens einmal je Zeile.</summary>
procedure AddOnce(var AList: TArray<TFormatDeviation>; ALine: Integer; AKind: TFormatDeviationKind;
  const AMessage: string);
var
  mItem: TFormatDeviation;
begin
  for mItem in AList do
    if (mItem.Line = ALine) and (mItem.Kind = AKind) and (mItem.Message = AMessage) then
      Exit;
  AList := AList + [TFormatDeviation.Create(ALine, AKind, AMessage)];
end;

/// <summary>Leerraum zwischen ABefore und AToken (beide in derselben Zeile) abweichend: Art und Text.</summary>
procedure DescribeGap(var AList: TArray<TFormatDeviation>; ALine: Integer; const ABefore, AToken: TPascalToken;
  AOldGap: Integer);
var
  mWhat: string;
begin
  if AToken.IsSymbol(':=') then
  begin
    if AOldGap = 0 then
      mWhat := 'Leerzeichen vor := fehlt'
    else
      mWhat := 'Zu viele Leerzeichen vor :=';
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceAssignment, mWhat);
  end
  else if ABefore.IsSymbol(':=') then
  begin
    if AOldGap = 0 then
      mWhat := 'Leerzeichen nach := fehlt'
    else
      mWhat := 'Zu viele Leerzeichen nach :=';
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceAssignment, mWhat);
  end
  else if ABefore.IsSymbol(',') then
  begin
    if AOldGap = 0 then
      mWhat := 'Leerzeichen nach Komma fehlt'
    else
      mWhat := 'Zu viele Leerzeichen nach Komma';
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceComma, mWhat);
  end
  else
    AddOnce(AList, ALine, TFormatDeviationKind.Alignment, Format('Ausrichtung vor „%s“',
      [AToken.Text]));
end;

/// <summary>Abweichungen einer Zeile, deren formatierte Fassung ANew ist.</summary>
procedure DescribeLine(var AList: TArray<TFormatDeviation>; ALine: Integer; const AOld, ANew: string;
  AIndentSize: Integer);
var
  mOldWidth, mNewWidth, mOldLength, mNewLength, mIndex: Integer;
  mOldTab, mNewTab, mSameTokens: Boolean;
  mOldRest, mNewRest: string;
  mOldTokens, mNewTokens: TArray<TPascalToken>;
begin
  mOldWidth := LeadingWidth(AOld, AIndentSize, mOldTab, mOldLength);
  mNewWidth := LeadingWidth(ANew, AIndentSize, mNewTab, mNewLength);
  mOldRest := Copy(AOld, mOldLength + 1, MaxInt);
  mNewRest := Copy(ANew, mNewLength + 1, MaxInt);
  if mOldRest <> '' then
  begin
    if mOldWidth <> mNewWidth then
      AddOnce(AList, ALine, TFormatDeviationKind.Indent, Format('Einrückung %d statt %d',
        [mOldWidth, mNewWidth]))
    else if mOldTab and not mNewTab then
      AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung mit Tabulator statt Leerzeichen')
    else if mNewTab and not mOldTab then
      AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung mit Leerzeichen statt Tabulator')
    else if Copy(AOld, 1, mOldLength) <> Copy(ANew, 1, mNewLength) then
      AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung aus Tabulatoren und Leerzeichen');
  end;
  if (TrimRight(AOld) <> AOld) and (TrimRight(ANew) = ANew) then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.TrailingWhitespace, 'Leerzeichen am Zeilenende');
    mOldRest := TrimRight(mOldRest);
  end;
  if mOldRest = mNewRest then
    Exit;
  mOldTokens := TPascalLexer.Tokenize(mOldRest);
  mNewTokens := TPascalLexer.Tokenize(mNewRest);
  mSameTokens := Length(mOldTokens) = Length(mNewTokens);
  if mSameTokens then
    for mIndex := 0 to High(mOldTokens) do
      if not SameText(mOldTokens[mIndex].Text, mNewTokens[mIndex].Text) then
        mSameTokens := False;
  if not mSameTokens then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.LineBreaks, 'Zeilenumbruch');
    Exit;
  end;
  for mIndex := 0 to High(mOldTokens) do
  begin
    if mOldTokens[mIndex].Text <> mNewTokens[mIndex].Text then
      AddOnce(AList, ALine, TFormatDeviationKind.KeywordCase, Format('Schreibweise `%s`',
        [mOldTokens[mIndex].Text]));
    if (mIndex > 0) and (mOldTokens[mIndex].StartPos.Character - mOldTokens[mIndex - 1].EndPos.Character <>
      mNewTokens[mIndex].StartPos.Character - mNewTokens[mIndex - 1].EndPos.Character) then
      DescribeGap(AList, ALine, mOldTokens[mIndex - 1], mOldTokens[mIndex],
        mOldTokens[mIndex].StartPos.Character - mOldTokens[mIndex - 1].EndPos.Character);
  end;
end;

function LineBreakName(AKind: TTextLineBreak): string;
begin
  case AKind of
    TTextLineBreak.CRLF:
      Result := 'CRLF';
    TTextLineBreak.LF:
      Result := 'LF';
    TTextLineBreak.CR:
      Result := 'CR';
    TTextLineBreak.Mixed:
      Result := 'gemischt';
  else
    Result := 'keine';
  end;
end;

class function TFormatCheck.Deviations(const AOld, ANew: string; const AStyle: TFormatStyle):
  TArray<TFormatDeviation>;
var
  mOld, mNew: TArray<string>;
  mHunk: TTextLineHunk;
  mIndex, mIndentSize: Integer;
  mOnlyEmpty: Boolean;
  mOldKind, mNewKind: TTextLineBreak;
begin
  Result := nil;
  if AOld = ANew then
    Exit;
  mIndentSize := AStyle.IndentSize;
  if mIndentSize < 1 then
    mIndentSize := 2;
  mOld := TTextLines.SplitLines(AOld);
  mNew := TTextLines.SplitLines(ANew);
  mOldKind := TTextLines.KindOf(AOld);
  mNewKind := TTextLines.KindOf(ANew);
  if (mOldKind <> mNewKind) and (mOldKind <> TTextLineBreak.None) and (mNewKind <> TTextLineBreak.None) then
    AddOnce(Result, 0, TFormatDeviationKind.EndOfLine, Format('Zeilenenden %s statt %s',
      [LineBreakName(mOldKind), LineBreakName(mNewKind)]));
  for mHunk in TTextDiff.Hunks(mOld, mNew) do
  begin
    if mHunk.OldCount = mHunk.NewCount then
    begin
      for mIndex := 0 to mHunk.OldCount - 1 do
        DescribeLine(Result, mHunk.OldStart + mIndex, mOld[mHunk.OldStart + mIndex], mNew[mHunk.NewStart + mIndex],
          mIndentSize);
      Continue;
    end;
    // Nur leere Zeilen am Dateiende angehängt: der abschließende Umbruch fehlt.
    mOnlyEmpty := (mHunk.OldCount = 0) and (mHunk.OldStart = Length(mOld));
    for mIndex := 0 to mHunk.NewCount - 1 do
      mOnlyEmpty := mOnlyEmpty and (mNew[mHunk.NewStart + mIndex] = '');
    if mOnlyEmpty then
      AddOnce(Result, Max(Length(mOld) - 1, 0), TFormatDeviationKind.FinalNewline, 'Zeilenumbruch am Dateiende fehlt')
    else
      AddOnce(Result, Min(mHunk.OldStart, Max(Length(mOld) - 1, 0)), TFormatDeviationKind.LineBreaks,
        Format('Zeilenumbruch: %d Zeilen statt %d', [mHunk.OldCount, mHunk.NewCount]));
  end;
  TArray.Sort<TFormatDeviation>(Result, TComparer<TFormatDeviation>.Construct(
    function(const A, B: TFormatDeviation): Integer
    begin
      Result := A.Line - B.Line;
      if Result = 0 then
        Result := Ord(A.Kind) - Ord(B.Kind);
      if Result = 0 then
        Result := CompareStr(A.Message, B.Message);
    end));
end;

class function TFormatCheck.Run(const AText: string; const AStyle: TFormatStyle; const AScope: TFormatScope;
  const AOptions: TPreprocessorOptions): TFormatOutcome;
var
  mTree: TSyntaxTree;
  mProcessed: TPreprocessorResult;
  mOnce: string;
begin
  Result := Default(TFormatOutcome);
  Result.Original := AText;
  Result.Formatted := AText;
  Result.Stable := True;
  // Nur die aktiven Zweige wie im Editor und bei --check: Inaktive Zweige erzeugen keine Syntaxfehler.
  mTree := TSyntaxTreeCache.ParseActive(AText, AOptions, nil, mProcessed);
  try
    if Length(mTree.Diagnostics) > 0 then
    begin
      Result.HasSyntaxError := True;
      Result.SyntaxError := mTree.Diagnostics[0];
      Exit;
    end;
  finally
    mTree.Free;
  end;
  Result.Formatted := FormatText(AText, AStyle, AScope);
  Result.Deviations := Deviations(AText, Result.Formatted, AStyle);
  // Zweiter Lauf auf denselben Bereichen. Hat das Formatieren Zeilen umbrochen oder zusammengeführt, passen sie
  // nicht mehr; dann prüft der zweite Lauf, ob die ganze Datei nach einmal Formatieren stabil bleibt.
  if not AScope.WholeFile and (Length(TTextLines.SplitLines(AText)) <>
    Length(TTextLines.SplitLines(Result.Formatted))) then
  begin
    mOnce := FormatText(Result.Formatted, AStyle, TFormatScope.All);
    Result.Stable := FormatText(mOnce, AStyle, TFormatScope.All) = mOnce;
  end
  else
    Result.Stable := FormatText(Result.Formatted, AStyle, AScope) = Result.Formatted;
end;

class function TFormatCheck.KindName(AKind: TFormatDeviationKind): string;
begin
  case AKind of
    TFormatDeviationKind.Indent:
      Result := 'indent';
    TFormatDeviationKind.IndentChars:
      Result := 'indentChars';
    TFormatDeviationKind.KeywordCase:
      Result := 'keywordCase';
    TFormatDeviationKind.SpaceAssignment:
      Result := 'spaceAroundAssignment';
    TFormatDeviationKind.SpaceComma:
      Result := 'spaceAfterComma';
    TFormatDeviationKind.TrailingWhitespace:
      Result := 'trailingWhitespace';
    TFormatDeviationKind.Alignment:
      Result := 'alignment';
    TFormatDeviationKind.LineBreaks:
      Result := 'lineBreaks';
    TFormatDeviationKind.EndOfLine:
      Result := 'endOfLine';
  else
    Result := 'finalNewline';
  end;
end;

end.
