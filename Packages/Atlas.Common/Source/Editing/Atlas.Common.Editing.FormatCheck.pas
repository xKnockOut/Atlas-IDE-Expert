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
      begin
        Result := A.Last - B.Last;
      end;
    end));
  for mSpan in mSorted do
  begin
    if mSpan.Last < mSpan.First then
    begin
      Continue;
    end;
    if (Result <> nil) and (mSpan.First <= Result[High(Result)].Last + 1) then
    begin
      Result[High(Result)].Last := Max(Result[High(Result)].Last, mSpan.Last);
    end
    else
    begin
      Result := Result + [mSpan];
    end;
  end;
end;

/// <summary>A liegt ganz vor B (Ende von A vor oder am Anfang von B).</summary>
function EndsBefore(const A, B: TTextRange): Boolean;
begin
  Result := (A.EndPos.Line < B.StartPos.Line) or
    ((A.EndPos.Line = B.StartPos.Line) and (A.EndPos.Character <= B.StartPos.Character));
end;

/// <summary>Überschneidet AEdit keine der Änderungen in AFound?</summary>
function IsFree(AFound: TList<TTextEdit>; const AEdit: TTextEdit): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 0 to AFound.Count - 1 do
  begin
    Result := Result and (EndsBefore(AFound[mIndex].Range, AEdit.Range) or
      EndsBefore(AEdit.Range, AFound[mIndex].Range));
  end;
end;

class function TFormatCheck.Edits(const AText: string; const AStyle: TFormatStyle;
  const AScope: TFormatScope): TArray<TTextEdit>;
var
  mTokens: TArray<TPascalToken>;
  mSpan: TFormatLineSpan;
  mEdit: TTextEdit;
  mFound: TList<TTextEdit>;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  if AScope.WholeFile then
  begin
    Exit(TFormatter.Edits(AText, mTokens, AStyle, 0, -1));
  end;
  mFound := TList<TTextEdit>.Create;
  try
    for mSpan in MergedSpans(AScope.Spans) do
    begin
      for mEdit in TFormatter.Edits(AText, mTokens, AStyle, mSpan.First, mSpan.Last) do
      begin
        // Sicherheitsnetz: Ein Umbruch über die Grenze zweier Bereiche darf keine überlappenden Änderungen
        // ergeben (die Bereiche sind getrennt, die Gruppen des Formatierers bleiben in einem Bereich).
        if IsFree(mFound, mEdit) then
        begin
          mFound.Add(mEdit);
        end;
      end;
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
    begin
      Inc(Result);
    end;
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
  begin
    if (mItem.Line = ALine) and (mItem.Kind = AKind) and (mItem.Message = AMessage) then
    begin
      Exit;
    end;
  end;
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
    begin
      mWhat := 'Leerzeichen vor := fehlt';
    end
    else
    begin
      mWhat := 'Zu viele Leerzeichen vor :=';
    end;
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceAssignment, mWhat);
  end
  else if ABefore.IsSymbol(':=') then
  begin
    if AOldGap = 0 then
    begin
      mWhat := 'Leerzeichen nach := fehlt';
    end
    else
    begin
      mWhat := 'Zu viele Leerzeichen nach :=';
    end;
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceAssignment, mWhat);
  end
  else if ABefore.IsSymbol(',') then
  begin
    if AOldGap = 0 then
    begin
      mWhat := 'Leerzeichen nach Komma fehlt';
    end
    else
    begin
      mWhat := 'Zu viele Leerzeichen nach Komma';
    end;
    AddOnce(AList, ALine, TFormatDeviationKind.SpaceComma, mWhat);
  end
  else
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.Alignment, Format('Ausrichtung vor „%s“',
      [AToken.Text]));
  end;
end;

type
  /// <summary>Führender Leerraum einer Zeile.</summary>
  TLeading = record
    /// <summary>Breite in Spalten (Tab bis zur nächsten Ebene).</summary>
    Width: Integer;
    HasTab: Boolean;
    /// <summary>Der Leerraum selbst.</summary>
    Chars: string;
    /// <summary>Die Zeile hinter dem Leerraum.</summary>
    Rest: string;
    class function Create(const ALine: string; AIndentSize: Integer): TLeading; static;
  end;

class function TLeading.Create(const ALine: string; AIndentSize: Integer): TLeading;
var
  mLength: Integer;
begin
  Result.Width := LeadingWidth(ALine, AIndentSize, Result.HasTab, mLength);
  Result.Chars := Copy(ALine, 1, mLength);
  Result.Rest := Copy(ALine, mLength + 1, MaxInt);
end;

/// <summary>Abweichung der Einrückung: Breite, Tab statt Leerzeichen oder umgekehrt, gemischt.</summary>
procedure DescribeIndent(var AList: TArray<TFormatDeviation>; ALine: Integer; const AOld, ANew: TLeading);
begin
  if AOld.Width <> ANew.Width then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.Indent, Format('Einrückung %d statt %d', [AOld.Width, ANew.Width]));
  end
  else if AOld.HasTab and not ANew.HasTab then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung mit Tabulator statt Leerzeichen');
  end
  else if ANew.HasTab and not AOld.HasTab then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung mit Leerzeichen statt Tabulator');
  end
  else if AOld.Chars <> ANew.Chars then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.IndentChars, 'Einrückung aus Tabulatoren und Leerzeichen');
  end;
end;

/// <summary>Dieselben Token bis auf Groß-/Kleinschreibung?</summary>
function SameTokenTexts(const AOld, ANew: TArray<TPascalToken>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AOld) = Length(ANew);
  if Result then
  begin
    for mIndex := 0 to High(AOld) do
    begin
      Result := Result and SameText(AOld[mIndex].Text, ANew[mIndex].Text);
    end;
  end;
end;

/// <summary>Abstand zwischen dem Token AIndex und seinem Vorgänger.</summary>
function GapBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := ATokens[AIndex].StartPos.Character - ATokens[AIndex - 1].EndPos.Character;
end;

/// <summary>Abweichungen im Rest der Zeile hinter der Einrückung: Umbruch, Schreibweise, Leerraum.</summary>
procedure DescribeTokens(var AList: TArray<TFormatDeviation>; ALine: Integer; const AOldRest, ANewRest: string);
var
  mOldTokens, mNewTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mOldTokens := TPascalLexer.Tokenize(AOldRest);
  mNewTokens := TPascalLexer.Tokenize(ANewRest);
  if not SameTokenTexts(mOldTokens, mNewTokens) then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.LineBreaks, 'Zeilenumbruch');
    Exit;
  end;
  for mIndex := 0 to High(mOldTokens) do
  begin
    if mOldTokens[mIndex].Text <> mNewTokens[mIndex].Text then
    begin
      AddOnce(AList, ALine, TFormatDeviationKind.KeywordCase, Format('Schreibweise `%s`',
        [mOldTokens[mIndex].Text]));
    end;
    if (mIndex > 0) and (GapBefore(mOldTokens, mIndex) <> GapBefore(mNewTokens, mIndex)) then
    begin
      DescribeGap(AList, ALine, mOldTokens[mIndex - 1], mOldTokens[mIndex], GapBefore(mOldTokens, mIndex));
    end;
  end;
end;

/// <summary>Abweichungen einer Zeile, deren formatierte Fassung ANew ist.</summary>
procedure DescribeLine(var AList: TArray<TFormatDeviation>; ALine: Integer; const AOld, ANew: string;
  AIndentSize: Integer);
var
  mOld, mNew: TLeading;
begin
  mOld := TLeading.Create(AOld, AIndentSize);
  mNew := TLeading.Create(ANew, AIndentSize);
  if mOld.Rest <> '' then
  begin
    DescribeIndent(AList, ALine, mOld, mNew);
  end;
  if (TrimRight(AOld) <> AOld) and (TrimRight(ANew) = ANew) then
  begin
    AddOnce(AList, ALine, TFormatDeviationKind.TrailingWhitespace, 'Leerzeichen am Zeilenende');
    mOld.Rest := TrimRight(mOld.Rest);
  end;
  if mOld.Rest <> mNew.Rest then
  begin
    DescribeTokens(AList, ALine, mOld.Rest, mNew.Rest);
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

/// <summary>Unterschiedliche Zeilenenden (beide Texte haben welche).</summary>
procedure DescribeLineBreaks(var AList: TArray<TFormatDeviation>; const AOld, ANew: string);
var
  mOldKind, mNewKind: TTextLineBreak;
begin
  mOldKind := TTextLines.KindOf(AOld);
  mNewKind := TTextLines.KindOf(ANew);
  if (mOldKind <> mNewKind) and (mOldKind <> TTextLineBreak.None) and (mNewKind <> TTextLineBreak.None) then
  begin
    AddOnce(AList, 0, TFormatDeviationKind.EndOfLine, Format('Zeilenenden %s statt %s',
      [LineBreakName(mOldKind), LineBreakName(mNewKind)]));
  end;
end;

/// <summary>Hängt AHunk nur leere Zeilen ans Dateiende? Dann fehlt der abschließende Umbruch.</summary>
function OnlyEmptyAppended(const AHunk: TTextLineHunk; const AOld, ANew: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := (AHunk.OldCount = 0) and (AHunk.OldStart = Length(AOld));
  for mIndex := 0 to AHunk.NewCount - 1 do
  begin
    Result := Result and (ANew[AHunk.NewStart + mIndex] = '');
  end;
end;

/// <summary>Abweichungen eines Abschnitts des Zeilenvergleichs.</summary>
procedure DescribeHunk(var AList: TArray<TFormatDeviation>; const AHunk: TTextLineHunk;
  const AOld, ANew: TArray<string>; AIndentSize: Integer);
var
  mIndex: Integer;
begin
  if AHunk.OldCount = AHunk.NewCount then
  begin
    for mIndex := 0 to AHunk.OldCount - 1 do
    begin
      DescribeLine(AList, AHunk.OldStart + mIndex, AOld[AHunk.OldStart + mIndex], ANew[AHunk.NewStart + mIndex],
        AIndentSize);
    end;
  end
  else if OnlyEmptyAppended(AHunk, AOld, ANew) then
  begin
    AddOnce(AList, Max(Length(AOld) - 1, 0), TFormatDeviationKind.FinalNewline, 'Zeilenumbruch am Dateiende fehlt');
  end
  else
  begin
    AddOnce(AList, Min(AHunk.OldStart, Max(Length(AOld) - 1, 0)), TFormatDeviationKind.LineBreaks,
      Format('Zeilenumbruch: %d Zeilen statt %d', [AHunk.OldCount, AHunk.NewCount]));
  end;
end;

class function TFormatCheck.Deviations(const AOld, ANew: string; const AStyle: TFormatStyle):
  TArray<TFormatDeviation>;
var
  mOld, mNew: TArray<string>;
  mHunk: TTextLineHunk;
  mIndentSize: Integer;
begin
  Result := nil;
  if AOld = ANew then
  begin
    Exit;
  end;
  mIndentSize := AStyle.IndentSize;
  if mIndentSize < 1 then
  begin
    mIndentSize := 2;
  end;
  mOld := TTextLines.SplitLines(AOld);
  mNew := TTextLines.SplitLines(ANew);
  DescribeLineBreaks(Result, AOld, ANew);
  for mHunk in TTextDiff.Hunks(mOld, mNew) do
  begin
    DescribeHunk(Result, mHunk, mOld, mNew, mIndentSize);
  end;
  TArray.Sort<TFormatDeviation>(Result, TComparer<TFormatDeviation>.Construct(
    function(const A, B: TFormatDeviation): Integer
    begin
      Result := A.Line - B.Line;
      if Result = 0 then
      begin
        Result := Ord(A.Kind) - Ord(B.Kind);
      end;
      if Result = 0 then
      begin
        Result := CompareStr(A.Message, B.Message);
      end;
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
  begin
    Result.Stable := FormatText(Result.Formatted, AStyle, AScope) = Result.Formatted;
  end;
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
