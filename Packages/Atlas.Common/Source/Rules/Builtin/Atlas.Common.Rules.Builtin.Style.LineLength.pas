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
    DefaultMax = 120;
    /// <summary>Grenze aus dem Text von F2069. Delphi 13 übersetzt in der IDE auch Zeilen mit 1222 Zeichen
    /// (#1383, Cm.F2069b/d); welche Version und welcher Aufruf hier abbricht, ist offen: darüber eine Warnung.
    /// </summary>
    CompilerLimit = 1023;
    /// <summary>Längere Zeilen lehnt auch Delphi 13 ab (F2069, Cm.F2069c).</summary>
    HardLimit = 4095;
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
  Atlas.Common.Rules.Options;

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
  FMaxLength := TRuleOptions.Int(AContext.Options, 'max', TLineLengthRule.DefaultMax);
  if FMaxLength <= 0 then
  begin
    FMaxLength := TLineLengthRule.DefaultMax;
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
  Index, Line: Integer;
begin
  SetLength(FByLine, Length(FLines));
  SetLength(FSpanned, Length(FLines));
  for Index := 0 to High(FTokens) do
  begin
    for Line := Max(FTokens[Index].StartPos.Line, 0) to Min(FTokens[Index].EndPos.Line, High(FLines)) do
    begin
      FByLine[Line] := FByLine[Line] + [Index];
      if Line > FTokens[Index].StartPos.Line then
      begin
        FSpanned[Line] := True;
      end;
    end;
  end;
end;

function TLineScanner.Columns(const ALine: string): TArray<Integer>;
var
  Index: Integer;
begin
  // Sichtbare Spalte vor jedem Zeichen: Result[I] = Breite von ALine[1..I]; Tabs springen zur nächsten
  // Tabstelle, das zweite Zeichen eines Surrogatpaars zählt nicht.
  SetLength(Result, Length(ALine) + 1);
  Result[0] := 0;
  for Index := 1 to Length(ALine) do
  begin
    if ALine[Index] = #9 then
    begin
      Result[Index] := (Result[Index - 1] div FTabWidth + 1) * FTabWidth;
    end
    else if (ALine[Index] >= #$DC00) and (ALine[Index] <= #$DFFF) then
    begin
      Result[Index] := Result[Index - 1];
    end
    else
    begin
      Result[Index] := Result[Index - 1] + 1;
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
  TokenIndex, First, Last: Integer;
  Token: TPascalToken;
begin
  // Breite ohne Strings bzw. Kommentare nach den Optionen; Anführungszeichen und Kommentarzeichen bleiben.
  Result := AColumns[High(AColumns)];
  for TokenIndex in FByLine[ALine] do
  begin
    Token := FTokens[TokenIndex];
    if not Ignored(Token) then
    begin
      Continue;
    end;
    First := 0;
    if Token.StartPos.Line = ALine then
    begin
      First := Token.StartPos.Character;
    end;
    Last := High(AColumns);
    if Token.EndPos.Line = ALine then
    begin
      Last := Token.EndPos.Character;
    end;
    First := EnsureRange(First, 0, High(AColumns));
    Last := EnsureRange(Last, 0, High(AColumns));
    Result := Result - Max(AColumns[Last] - AColumns[First] - 2, 0);
  end;
end;

function TLineScanner.IsBreak(APrevious, AToken: Integer): Boolean;
var
  Previous, Token: TPascalToken;
begin
  Previous := FTokens[APrevious];
  Token := FTokens[AToken];
  if Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
  begin
    Exit(False);
  end;
  // Hinter einem Komma oder vor einem zweistelligen Operator, wie der Formatierer (#43).
  Result := Previous.IsSymbol(',') or (MatchText(Token.Text, cOperators) and
    ((Previous.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or Previous.IsSymbol(')') or Previous.IsSymbol(']')));
end;

function TLineScanner.BreakCandidates(ALine: Integer): TArray<Integer>;
var
  Items: TArray<Integer>;
  Position: Integer;
begin
  // Zeichenindizes, an denen ein Token beginnt, vor dem umgebrochen werden darf.
  Result := nil;
  Items := nil;
  for Position in FByLine[ALine] do
  begin
    if FTokens[Position].StartPos.Line = ALine then
    begin
      Items := Items + [Position];
    end;
  end;
  if FSpanned[ALine] then
  begin
    Exit;
  end;
  for Position := 1 to High(Items) do
  begin
    if (FTokens[Items[Position]].EndPos.Line = ALine) and
      not (FTokens[Items[Position - 1]].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      IsBreak(Items[Position - 1], Items[Position]) then
    begin
      Result := Result + [FTokens[Items[Position]].StartPos.Character];
    end;
  end;
end;

function TLineScanner.ContinuationWidth: Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(FContinuation) do
  begin
    if FContinuation[Index] = #9 then
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
  State: TWrapState;
  Text: string;
  Best, Cut: Integer;
begin
  // Umbruchstellen von links nach rechts, so spät wie möglich; nil, wenn ein Stück nicht unter die Grenze passt.
  Result := nil;
  Text := FLines[ALine];
  State := Default(TWrapState);
  State.Candidates := BreakCandidates(ALine);
  State.SegmentStart := TTextLines.IndentLength(Text);
  State.Prefix := AColumns[State.SegmentStart];
  while State.Prefix + AColumns[Length(Text)] - AColumns[State.SegmentStart] > FMaxLength do
  begin
    Best := LatestCut(Text, AColumns, State);
    if Best < 0 then
    begin
      Result := nil;
      Exit;
    end;
    Cut := Length(TrimRight(Copy(Text, 1, Best)));
    Result := Result + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ALine, Cut),
      TTextPosition.Create(ALine, Best)), FLineBreak + FContinuation)];
    State.SegmentStart := Best;
    State.Prefix := ContinuationWidth;
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
  Text: string;
  Range: TTextRange;
begin
  Text := FLines[ALine];
  Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, Length(Text)));
  Result := True;
  if Length(Text) > TLineLengthRule.HardLimit then
  begin
    FReport.AddWithSeverity(Range, Format('Zeile mit %d Zeichen; der Compiler bricht über %d Zeichen ab (wie F2069).',
      [Length(Text), TLineLengthRule.HardLimit]), TRuleSeverity.Error, nil);
  end
  else if Length(Text) > TLineLengthRule.CompilerLimit then
  begin
    FReport.AddWithSeverity(Range, Format('Zeile mit %d Zeichen; je nach Delphi-Version bricht der Compiler über ' +
      '%d Zeichen ab.', [Length(Text), TLineLengthRule.CompilerLimit]), TRuleSeverity.Warning, nil);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLineScanner.CheckLine(ALine: Integer);
var
  ColumnsOfLine: TArray<Integer>;
  Width: Integer;
  Edits: TArray<TTextEdit>;
  Fixes: TArray<TRuleFix>;
begin
  if OverCompilerLimit(ALine) then
  begin
    Exit;
  end;
  ColumnsOfLine := Columns(FLines[ALine]);
  Width := ColumnsOfLine[High(ColumnsOfLine)];
  if (Width <= FMaxLength) or (CountedWidth(ALine, ColumnsOfLine) <= FMaxLength) then
  begin
    Exit;
  end;
  Fixes := nil;
  Edits := WrapEdits(ALine, ColumnsOfLine);
  if Edits <> nil then
  begin
    Fixes := [TRuleFix.Create('Zeile umbrechen', Edits)];
  end;
  FReport.Add(TTextRange.Create(TTextPosition.Create(ALine, OverflowStart(ColumnsOfLine)),
    TTextPosition.Create(ALine, Length(FLines[ALine]))), Format('Zeile hat %d Zeichen (Grenze %d).',
    [Width, FMaxLength]), Fixes);
end;

function TLineScanner.NeedsCheck(ALine: Integer): Boolean;
begin
  // Ohne Tabs ist die Breite höchstens die Länge.
  Result := (Length(FLines[ALine]) > Min(FMaxLength, TLineLengthRule.CompilerLimit)) or
    ((Pos(#9, FLines[ALine]) > 0) and (Length(FLines[ALine]) * FTabWidth > FMaxLength));
end;

procedure TLineScanner.Run;
var
  Line: Integer;
begin
  IndexTokens;
  FContinuation := '';
  for Line := 0 to High(FLines) do
  begin
    if NeedsCheck(Line) then
    begin
      FContinuation := TTextLines.IndentOf(FLines[Line]) + TFormatLayout.IndentUnit(FStyle);
      CheckLine(Line);
    end;
  end;
end;

{ TLineLengthRule }

function TLineLengthRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('line-length', TRuleSeverity.Hint, 'Zeile zu lang', True);
end;

procedure TLineLengthRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Scanner: TLineScanner;
begin
  if AContext.Text = '' then
  begin
    Exit;
  end;
  Scanner := TLineScanner.Create(AContext, AReport);
  try
    Scanner.Run;
  finally
    Scanner.Free;
  end;
end;

end.
