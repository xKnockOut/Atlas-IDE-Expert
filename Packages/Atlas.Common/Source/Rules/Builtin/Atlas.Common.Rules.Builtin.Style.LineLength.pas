unit Atlas.Common.Rules.Builtin.Style.LineLength;

// Stilregel line-length (#938, #1383), registriert mit den übrigen Stilregeln (RegisterStyleRules):
//   Zeile über der Grenze "max" (Vorgabe 120, Tabs nach format.indentSize), Strings und Kommentare abschaltbar
//   ausgenommen (Standard aus); Korrektur bricht hinter Kommas bzw. vor Operatoren um. Über 1023 Zeichen immer eine
//   Warnung, über 4095 Zeichen ein Error wie F2069.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TLineLengthRule = class(TInterfacedObject, IRule)
  public const
    cDefaultMax = 120;
    /// <summary>Grenze aus dem Text von F2069. Delphi 13 übersetzt in der IDE auch Zeilen mit 1222 Zeichen
    /// (#1383, Cm.F2069b/d); welche Version und welcher Aufruf hier abbricht, ist offen: darüber eine Warnung.
    /// </summary>
    cCompilerLimit = 1023;
    /// <summary>Längere Zeilen lehnt auch Delphi 13 ab (F2069, Cm.F2069c).</summary>
    cHardLimit = 4095;
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Formatter.Layout,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStyleLineLengthText = (CompilerLimit, VersionLimit, WrapLine, TooLong, Title);

const
  cTexts: array[TStyleLineLengthText] of TAtlasText = (
    (De: 'Zeile mit %d Zeichen; der Compiler bricht über %d Zeichen ab (wie F2069).';
     En: 'Line with %d characters; the compiler aborts above %d characters (like F2069).'),
    (De: 'Zeile mit %d Zeichen; je nach Delphi-Version bricht der Compiler über %d Zeichen ab.';
     En: 'Line with %d characters; depending on the Delphi version the compiler aborts above %d characters.'),
    (De: 'Zeile umbrechen'; En: 'Wrap line'),
    (De: 'Zeile hat %d Zeichen (Grenze %d).'; En: 'Line has %d characters (limit %d).'),
    (De: 'Zeile zu lang'; En: 'Line too long'));

{$SCOPEDENUMS OFF}

const
  cOperators: array[0..11] of string = ('+', '-', '*', '/', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', '<>');

type
  /// <summary>Stand beim Umbrechen einer Zeile: Umbruchstellen (Zeichenindex), nächste zu prüfende Stelle, Beginn
  /// des laufenden Stücks und Breite der Einrückung davor.</summary>
  TWrapState = record
    Candidates: TArray<Integer>;
    Position: Integer;
    SegmentStart: Integer;
    Prefix: Integer;
  end;

  /// <summary>Prüft die Zeilen eines Quelltexts gegen die Grenzen von line-length und baut die Umbrüche.</summary>
  TLineScanner = class
  private
    FReport: IRuleReport;
    FLines: TArray<string>;
    FLineBreak: string;
    FContinuation: string;
    FTokens: TArray<TPascalToken>;
    FByLine: TArray<TArray<Integer>>;
    /// <summary>Zeilen, in die ein mehrzeiliges Token hineinragt: dort wird nicht umgebrochen.</summary>
    FSpanned: TArray<Boolean>;
    FMaxLength: Integer;
    FTabWidth: Integer;
    FIgnoreStrings: Boolean;
    FIgnoreComments: Boolean;
    FStyle: TFormatStyle;
    procedure IndexTokens;
    function Columns(const ALine: string): TArray<Integer>;
    function Ignored(const AToken: TPascalToken): Boolean;
    function CountedWidth(ALine: Integer; const AColumns: TArray<Integer>): Integer;
    function IsBreak(APrevious, AToken: Integer): Boolean;
    function BreakCandidates(ALine: Integer): TArray<Integer>;
    function ContinuationWidth: Integer;
    function LatestCut(const AText: string; const AColumns: TArray<Integer>; var AState: TWrapState): Integer;
    function WrapEdits(ALine: Integer; const AColumns: TArray<Integer>): TArray<TTextEdit>;
    function OverflowStart(const AColumns: TArray<Integer>): Integer;
    function OverCompilerLimit(ALine: Integer): Boolean;
    function NeedsCheck(ALine: Integer): Boolean;
    procedure CheckLine(ALine: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TLineScanner }

constructor TLineScanner.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FReport := AReport;
  FMaxLength := TRuleOptions.Int(AContext.Options, 'max', TLineLengthRule.cDefaultMax);
  if FMaxLength <= 0 then
  begin
    FMaxLength := TLineLengthRule.cDefaultMax;
  end;
  FIgnoreStrings := TRuleOptions.Bool(AContext.Options, 'ignoreStrings', True);
  FIgnoreComments := TRuleOptions.Bool(AContext.Options, 'ignoreComments', False);
  FStyle := AContext.Formatting;
  if FStyle.IndentSize <= 0 then
  begin
    FStyle.IndentSize := 2;
  end;
  FTabWidth := FStyle.IndentSize;
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  FTokens := nil;
  if AContext.Tree <> nil then
  begin
    FTokens := AContext.Tree.Tokens;
  end;
end;

procedure TLineScanner.IndexTokens;
var
  mIndex, mLine: Integer;
begin
  SetLength(FByLine, Length(FLines));
  SetLength(FSpanned, Length(FLines));
  for mIndex := 0 to High(FTokens) do
  begin
    for mLine := Max(FTokens[mIndex].StartPos.Line, 0) to Min(FTokens[mIndex].EndPos.Line, High(FLines)) do
    begin
      FByLine[mLine] := FByLine[mLine] + [mIndex];
      if mLine > FTokens[mIndex].StartPos.Line then
      begin
        FSpanned[mLine] := True;
      end;
    end;
  end;
end;

function TLineScanner.Columns(const ALine: string): TArray<Integer>;
var
  mIndex: Integer;
begin
  // Sichtbare Spalte vor jedem Zeichen: Result[I] = Breite von ALine[1..I]; Tabs springen zur nächsten
  // Tabstelle, das zweite Zeichen eines Surrogatpaars zählt nicht.
  SetLength(Result, Length(ALine) + 1);
  Result[0] := 0;
  for mIndex := 1 to Length(ALine) do
  begin
    if ALine[mIndex] = #9 then
    begin
      Result[mIndex] := (Result[mIndex - 1] div FTabWidth + 1) * FTabWidth;
    end
    else if (ALine[mIndex] >= #$DC00) and (ALine[mIndex] <= #$DFFF) then
    begin
      Result[mIndex] := Result[mIndex - 1];
    end
    else
    begin
      Result[mIndex] := Result[mIndex - 1] + 1;
    end;
  end;
end;

function TLineScanner.Ignored(const AToken: TPascalToken): Boolean;
begin
  Result := (FIgnoreStrings and (AToken.Kind = TPascalTokenKind.StringLiteral)) or
    (FIgnoreComments and (AToken.Kind = TPascalTokenKind.Comment));
end;

function TLineScanner.CountedWidth(ALine: Integer; const AColumns: TArray<Integer>): Integer;
var
  mTokenIndex, mFirst, mLast: Integer;
  mToken: TPascalToken;
begin
  // Breite ohne Strings bzw. Kommentare nach den Optionen; Anführungszeichen und Kommentarzeichen bleiben.
  Result := AColumns[High(AColumns)];
  for mTokenIndex in FByLine[ALine] do
  begin
    mToken := FTokens[mTokenIndex];
    if not Ignored(mToken) then
    begin
      Continue;
    end;
    mFirst := 0;
    if mToken.StartPos.Line = ALine then
    begin
      mFirst := mToken.StartPos.Character;
    end;
    mLast := High(AColumns);
    if mToken.EndPos.Line = ALine then
    begin
      mLast := mToken.EndPos.Character;
    end;
    mFirst := EnsureRange(mFirst, 0, High(AColumns));
    mLast := EnsureRange(mLast, 0, High(AColumns));
    Result := Result - Max(AColumns[mLast] - AColumns[mFirst] - 2, 0);
  end;
end;

function TLineScanner.IsBreak(APrevious, AToken: Integer): Boolean;
var
  mPrevious, mToken: TPascalToken;
begin
  mPrevious := FTokens[APrevious];
  mToken := FTokens[AToken];
  if mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
  begin
    Exit(False);
  end;
  // Hinter einem Komma oder vor einem zweistelligen Operator, wie der Formatierer (#43).
  Result := mPrevious.IsSymbol(',') or (MatchText(mToken.Text, cOperators) and
    ((mPrevious.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or mPrevious.IsSymbol(')') or mPrevious.IsSymbol(']')));
end;

function TLineScanner.BreakCandidates(ALine: Integer): TArray<Integer>;
var
  mItems: TArray<Integer>;
  mPosition: Integer;
begin
  // Zeichenindizes, an denen ein Token beginnt, vor dem umgebrochen werden darf.
  Result := nil;
  mItems := nil;
  for mPosition in FByLine[ALine] do
  begin
    if FTokens[mPosition].StartPos.Line = ALine then
    begin
      mItems := mItems + [mPosition];
    end;
  end;
  if FSpanned[ALine] then
  begin
    Exit;
  end;
  for mPosition := 1 to High(mItems) do
  begin
    if (FTokens[mItems[mPosition]].EndPos.Line = ALine) and
      not (FTokens[mItems[mPosition - 1]].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      IsBreak(mItems[mPosition - 1], mItems[mPosition]) then
    begin
      Result := Result + [FTokens[mItems[mPosition]].StartPos.Character];
    end;
  end;
end;

function TLineScanner.ContinuationWidth: Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(FContinuation) do
  begin
    if FContinuation[mIndex] = #9 then
    begin
      Result := (Result div FTabWidth + 1) * FTabWidth;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

function TLineScanner.LatestCut(const AText: string; const AColumns: TArray<Integer>;
  var AState: TWrapState): Integer;
begin
  // Spätester Schnitt, bei dem das Stück davor passt; -1 ohne.
  Result := -1;
  while (AState.Position <= High(AState.Candidates)) and (AState.Prefix +
    AColumns[Length(TrimRight(Copy(AText, 1, AState.Candidates[AState.Position])))] -
    AColumns[AState.SegmentStart] <= FMaxLength) do
  begin
    if AState.Candidates[AState.Position] > AState.SegmentStart then
    begin
      Result := AState.Candidates[AState.Position];
    end;
    Inc(AState.Position);
  end;
end;

function TLineScanner.WrapEdits(ALine: Integer; const AColumns: TArray<Integer>): TArray<TTextEdit>;
var
  mState: TWrapState;
  mText: string;
  mBest, mCut: Integer;
begin
  // Umbruchstellen von links nach rechts, so spät wie möglich; nil, wenn ein Stück nicht unter die Grenze passt.
  Result := nil;
  mText := FLines[ALine];
  mState := Default(TWrapState);
  mState.Candidates := BreakCandidates(ALine);
  mState.SegmentStart := TTextLines.IndentLength(mText);
  mState.Prefix := AColumns[mState.SegmentStart];
  while mState.Prefix + AColumns[Length(mText)] - AColumns[mState.SegmentStart] > FMaxLength do
  begin
    mBest := LatestCut(mText, AColumns, mState);
    if mBest < 0 then
    begin
      Result := nil;
      Exit;
    end;
    mCut := Length(TrimRight(Copy(mText, 1, mBest)));
    Result := Result + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ALine, mCut),
      TTextPosition.Create(ALine, mBest)), FLineBreak + FContinuation)];
    mState.SegmentStart := mBest;
    mState.Prefix := ContinuationWidth;
  end;
end;

function TLineScanner.OverflowStart(const AColumns: TArray<Integer>): Integer;
begin
  // Erstes Zeichen hinter der Grenze; dort beginnt die Markierung.
  Result := 0;
  while (Result < High(AColumns)) and (AColumns[Result + 1] <= FMaxLength) do
  begin
    Inc(Result);
  end;
end;

function TLineScanner.OverCompilerLimit(ALine: Integer): Boolean;
var
  mText: string;
  mRange: TTextRange;
begin
  mText := FLines[ALine];
  mRange := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, Length(mText)));
  Result := True;
  if Length(mText) > TLineLengthRule.cHardLimit then
  begin
    FReport.AddWithSeverity(mRange, cTexts[TStyleLineLengthText.CompilerLimit].Fmt(
      [Length(mText), TLineLengthRule.cHardLimit]), TRuleSeverity.Error, nil);
  end
  else if Length(mText) > TLineLengthRule.cCompilerLimit then
  begin
    FReport.AddWithSeverity(mRange, cTexts[TStyleLineLengthText.VersionLimit].Fmt([Length(mText),
      TLineLengthRule.cCompilerLimit]), TRuleSeverity.Warning, nil);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLineScanner.CheckLine(ALine: Integer);
var
  mColumnsOfLine: TArray<Integer>;
  mWidth: Integer;
  mEdits: TArray<TTextEdit>;
  mFixes: TArray<TRuleFix>;
begin
  if OverCompilerLimit(ALine) then
  begin
    Exit;
  end;
  mColumnsOfLine := Columns(FLines[ALine]);
  mWidth := mColumnsOfLine[High(mColumnsOfLine)];
  if (mWidth <= FMaxLength) or (CountedWidth(ALine, mColumnsOfLine) <= FMaxLength) then
  begin
    Exit;
  end;
  mFixes := nil;
  mEdits := WrapEdits(ALine, mColumnsOfLine);
  if mEdits <> nil then
  begin
    mFixes := [TRuleFix.Create(cTexts[TStyleLineLengthText.WrapLine].Text, mEdits)];
  end;
  FReport.Add(TTextRange.Create(TTextPosition.Create(ALine, OverflowStart(mColumnsOfLine)),
    TTextPosition.Create(ALine, Length(FLines[ALine]))), cTexts[TStyleLineLengthText.TooLong].Fmt(
    [mWidth, FMaxLength]), mFixes);
end;

function TLineScanner.NeedsCheck(ALine: Integer): Boolean;
begin
  // Ohne Tabs ist die Breite höchstens die Länge.
  Result := (Length(FLines[ALine]) > Min(FMaxLength, TLineLengthRule.cCompilerLimit)) or
    ((Pos(#9, FLines[ALine]) > 0) and (Length(FLines[ALine]) * FTabWidth > FMaxLength));
end;

procedure TLineScanner.Run;
var
  mLine: Integer;
begin
  IndexTokens;
  FContinuation := '';
  for mLine := 0 to High(FLines) do
  begin
    if NeedsCheck(mLine) then
    begin
      FContinuation := TTextLines.IndentOf(FLines[mLine]) + TFormatLayout.IndentUnit(FStyle);
      CheckLine(mLine);
    end;
  end;
end;

{ TLineLengthRule }

function TLineLengthRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('line-length', TRuleSeverity.Hint, cTexts[TStyleLineLengthText.Title].Text, True);
end;

procedure TLineLengthRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScanner: TLineScanner;
begin
  if AContext.Text = '' then
  begin
    Exit;
  end;
  mScanner := TLineScanner.Create(AContext, AReport);
  try
    mScanner.Run;
  finally
    mScanner.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.LineLength', cTexts);

end.
