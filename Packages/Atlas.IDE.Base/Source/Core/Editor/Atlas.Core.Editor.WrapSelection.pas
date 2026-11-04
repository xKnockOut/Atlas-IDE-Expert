unit Atlas.Core.Editor.WrapSelection;

// Markierung beim Tippen umschließen (#672), ohne VCL und Open Tools API.
// Tippt man bei markiertem Text ein öffnendes Zeichen, kommt die Markierung
// zwischen das Zeichenpaar, statt überschrieben zu werden:
// - ( → ( … ), [ → [ … ], ' → ' … ', { → { … }, < → < … > (nur direkt hinter
//   einem Typnamen, also bei Generics). Welche Zeichen umschließen, steht in
//   den Einstellungen (editor.wrapSelection.chars); < nur, wenn dort
//   enthalten.
// - ': Hochkommas in der Markierung werden verdoppelt (It's → 'It''s');
//   beginnt die Markierung in einem String oder reicht sie über mehrere
//   Zeilen, wird nicht umschlossen.
// - {: Ganze Zeilen (Anfang im Einzug der ersten, Ende am Zeilenende bzw. am
//   Anfang der nächsten Zeile) bekommen { und } auf eigenen Zeilen in der
//   Einrückung der ersten Zeile. Enthält die Markierung schon }, nimmt Atlas
//   (* … *); enthält sie beides oder beginnt sie mit $ (Direktive), wird
//   nicht umschlossen.
// - Danach liegt die Markierung wieder auf dem ursprünglichen Text (ohne die
//   neuen Zeichen), damit ein zweites Zeichen weiter umschließen kann.
// - Mehrere Bereiche (Spaltenblock, mehrere Einfügemarken #589): jeder wird
//   einzeln umschlossen; ein Bereich ohne Markierung bekommt das Zeichen wie
//   beim Tippen. Lässt sich ein markierter Bereich nicht umschließen,
//   geschieht nichts (False), und das Zeichen wird normal getippt.
// Positionen: Zeile und Zeichen ab 0, UTF-16 wie im LSP; Enden ausschließlich.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges;

type
  TAtlasWrapResult = record
    /// <summary>Neuer Text.</summary>
    Lines: TArray<string>;
    /// <summary>Markierungen danach, in der Reihenfolge der Eingabe.</summary>
    Selections: TArray<TLspRange>;
  end;

  TAtlasWrapSelection = class
  public const
    /// <summary>Vorgabe von editor.wrapSelection.chars.</summary>
    DefaultChars = '([{''';
    /// <summary>Alle Zeichen, die umschließen können.</summary>
    AllChars = '([{''<';
  public
    /// <summary>Nur die Zeichen aus AllChars, je einmal, in der Reihenfolge von AChars.</summary>
    class function Normalize(const AChars: string): string; static;
    /// <summary>Umschließt AChar nach AChars?</summary>
    class function Accepts(AChar: Char; const AChars: string): Boolean; static;
    /// <summary>Schließendes Zeichen zu AOpen; #0 ohne.</summary>
    class function CloserOf(AOpen: Char): Char; static;
    /// <summary>Umschließt die Markierung ARange mit AOpen; False, wenn das Zeichen normal getippt wird.</summary>
    class function Wrap(const ALines: TArray<string>; const ARange: TLspRange; AOpen: Char; const AChars: string;
      out AResult: TAtlasWrapResult): Boolean; overload; static;
    /// <summary>Wie oben für mehrere Bereiche, die sich nicht überlappen.</summary>
    class function Wrap(const ALines: TArray<string>; const ARanges: TArray<TLspRange>; AOpen: Char;
      const AChars: string; out AResult: TAtlasWrapResult): Boolean; overload; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars,
  Atlas.Core.Editor.BlockComment;

type
  /// <summary>Ersetzung von [Start, Stop) durch Text; danach markiert SelStart bis SelStop (relativ zu Start).
  /// </summary>
  TPlan = record
    Start, Stop: Integer;
    Text: string;
    SelStart, SelStop: Integer;
    /// <summary>Markierung im neuen Text (Offsets).</summary>
    FinalStart, FinalStop: Integer;
  end;

  /// <summary>Ein Lauf von Wrap: Text, Zeilenanfänge und die Pläne je Bereich.</summary>
  TWrapJob = record
  private
    FLines: TArray<string>;
    FText: string;
    FStarts: TArray<Integer>;
    FSpans: TArray<TAtlasCommentSpan>;
    FSpansRead: Boolean;
    FOpen: Char;
    /// <summary>Beginnt APos in einem String? Liest die Spannen beim ersten Mal.</summary>
    function InStringAt(const APos: TLspTextPosition): Boolean;
    function PlanQuote(var APlan: TPlan; const ASelected: string; const AStartPos,
      AStopPos: TLspTextPosition): Boolean;
    function PlanAngle(var APlan: TPlan; const ASelected: string): Boolean;
    /// <summary>Kommentarzeichen auf eigenen Zeilen, Einrückung der ersten Zeile.</summary>
    procedure PlanBraceLines(var APlan: TPlan; const AStartPos, AStopPos: TLspTextPosition; const AOpener,
      ACloser: string);
    function PlanBrace(var APlan: TPlan; const ASelected: string; const AStartPos,
      AStopPos: TLspTextPosition): Boolean;
    function PlanSelection(var APlan: TPlan; const ASelected: string; const AStartPos,
      AStopPos: TLspTextPosition): Boolean;
    /// <summary>Plan für ARange; ASelected: mit Markierung. False, wenn nicht umschlossen werden kann.</summary>
    function PlanFor(const ARange: TLspRange; out APlan: TPlan; out ASelected: Boolean): Boolean;
  public
    function Run(const ALines: TArray<string>; const ARanges: TArray<TLspRange>; AOpen: Char;
      var AResult: TAtlasWrapResult): Boolean;
  end;

function LineStarts(const ALines: TArray<string>): TArray<Integer>;
var
  Index, Offset: Integer;
begin
  SetLength(Result, Length(ALines));
  Offset := 0;
  for Index := 0 to High(ALines) do
  begin
    Result[Index] := Offset;
    Inc(Offset, Length(ALines[Index]) + 1);
  end;
end;

function OffsetOf(const ALines: TArray<string>; const AStarts: TArray<Integer>;
  const APos: TLspTextPosition): Integer;
var
  Line: Integer;
begin
  Line := EnsureRange(APos.Line, 0, High(ALines));
  Result := AStarts[Line] + EnsureRange(APos.Character, 0, Length(ALines[Line]));
end;

function PositionOf(const AStarts: TArray<Integer>; AOffset: Integer): TLspTextPosition;
var
  First, Last, Middle: Integer;
begin
  First := 0;
  Last := High(AStarts);
  while First < Last do
  begin
    Middle := (First + Last + 1) div 2;
    if AStarts[Middle] <= AOffset then
    begin
      First := Middle;
    end
    else
    begin
      Last := Middle - 1;
    end;
  end;
  Result := TLspTextPosition.Create(First, AOffset - AStarts[First]);
end;

function LeadingWhitespace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  Result := Copy(ALine, 1, Index - 1);
end;

/// <summary>Beginnt APos in einem String (nach dem öffnenden Hochkomma)?</summary>
function InString(const ASpans: TArray<TAtlasCommentSpan>; const APos: TLspTextPosition): Boolean;
var
  Span: TAtlasCommentSpan;
begin
  Result := False;
  for Span in ASpans do
  begin
    if (Span.Kind = TAtlasCommentSpanKind.StringLiteral) and
      (TLspTextPosition.Compare(Span.StartPos, APos) < 0) and (TLspTextPosition.Compare(APos, Span.EndPos) < 0) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Steht vor AOffset (0-basiert) direkt ein Typname (Bezeichner, der mit Buchstabe oder _ beginnt)?
/// </summary>
function AfterTypeName(const AText: string; AOffset: Integer): Boolean;
var
  Index: Integer;
begin
  Index := AOffset;
  while (Index >= 1) and TTextChars.IsIdentChar(AText[Index]) do
  begin
    Dec(Index);
  end;
  Result := (Index < AOffset) and not CharInSet(AText[Index + 1], ['0'..'9']);
end;

/// <summary>Ganze Zeilen: Anfang im Einzug der ersten Zeile, Ende am Zeilenende bzw. am Anfang einer späteren
/// Zeile.</summary>
function WholeLines(const ALines: TArray<string>; const AStart, AStop: TLspTextPosition): Boolean;
begin
  Result := (AStart.Character <= Length(LeadingWhitespace(ALines[AStart.Line]))) and
    (((AStop.Line > AStart.Line) and (AStop.Character = 0)) or
    (AStop.Character >= Length(ALines[AStop.Line])));
end;

/// <summary>Reihenfolge der Pläne absteigend nach Start (zum Einsetzen von hinten nach vorn).</summary>
function PlanOrder(const APlans: TArray<TPlan>): TArray<Integer>;
var
  mIndex, mOther, mSwap: Integer;
begin
  SetLength(Result, Length(APlans));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIndex;
  end;
  for mIndex := 1 to High(Result) do
  begin
    mOther := mIndex;
    while (mOther > 0) and (APlans[Result[mOther - 1]].Start < APlans[Result[mOther]].Start) do
    begin
      mSwap := Result[mOther];
      Result[mOther] := Result[mOther - 1];
      Result[mOther - 1] := mSwap;
      Dec(mOther);
    end;
  end;
end;

function Overlapping(const APlans: TArray<TPlan>; const AOrder: TArray<Integer>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to High(AOrder) do
  begin
    Result := Result or (APlans[AOrder[mIndex]].Stop > APlans[AOrder[mIndex - 1]].Start);
  end;
end;

/// <summary>Pläne von hinten nach vorn einsetzen; was dahinter liegt, rückt um die Längenänderung.</summary>
function ApplyPlans(const AText: string; var APlans: TArray<TPlan>; const AOrder: TArray<Integer>): string;
var
  mIndex, mOther, mDelta: Integer;
  mPlan: TPlan;
begin
  Result := AText;
  for mIndex := 0 to High(AOrder) do
  begin
    mPlan := APlans[AOrder[mIndex]];
    Result := Copy(Result, 1, mPlan.Start) + mPlan.Text + Copy(Result, mPlan.Stop + 1, MaxInt);
    mDelta := Length(mPlan.Text) - (mPlan.Stop - mPlan.Start);
    for mOther := 0 to mIndex - 1 do
    begin
      Inc(APlans[AOrder[mOther]].FinalStart, mDelta);
      Inc(APlans[AOrder[mOther]].FinalStop, mDelta);
    end;
    APlans[AOrder[mIndex]].FinalStart := mPlan.Start + mPlan.SelStart;
    APlans[AOrder[mIndex]].FinalStop := mPlan.Start + mPlan.SelStop;
  end;
end;

function SelectionsOf(const APlans: TArray<TPlan>; const AStarts: TArray<Integer>): TArray<TLspRange>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(APlans));
  for mIndex := 0 to High(APlans) do
  begin
    Result[mIndex].StartPos := PositionOf(AStarts, APlans[mIndex].FinalStart);
    Result[mIndex].EndPos := PositionOf(AStarts, APlans[mIndex].FinalStop);
  end;
end;

{ TWrapJob }

function TWrapJob.InStringAt(const APos: TLspTextPosition): Boolean;
begin
  if not FSpansRead then
  begin
    FSpans := TAtlasBlockComment.Spans(FLines);
    FSpansRead := True;
  end;
  Result := InString(FSpans, APos);
end;

function TWrapJob.PlanQuote(var APlan: TPlan; const ASelected: string; const AStartPos,
  AStopPos: TLspTextPosition): Boolean;
var
  mSelected: string;
begin
  // Nur in einer Zeile und nicht aus einem String heraus; Hochkommas verdoppeln.
  Result := (AStartPos.Line = AStopPos.Line) and not InStringAt(AStartPos);
  if Result then
  begin
    mSelected := StringReplace(ASelected, '''', '''''', [rfReplaceAll]);
    APlan.Text := '''' + mSelected + '''';
    APlan.SelStart := 1;
    APlan.SelStop := 1 + Length(mSelected);
  end;
end;

function TWrapJob.PlanAngle(var APlan: TPlan; const ASelected: string): Boolean;
begin
  Result := AfterTypeName(FText, APlan.Start);
  if Result then
  begin
    APlan.Text := '<' + ASelected + '>';
    APlan.SelStart := 1;
    APlan.SelStop := 1 + Length(ASelected);
  end;
end;

procedure TWrapJob.PlanBraceLines(var APlan: TPlan; const AStartPos, AStopPos: TLspTextPosition; const AOpener,
  ACloser: string);
var
  mIndent: string;
  mLineStart: Integer;
begin
  mIndent := LeadingWhitespace(FLines[AStartPos.Line]);
  mLineStart := FStarts[AStartPos.Line];
  APlan.Text := mIndent + AOpener + #10 + Copy(FText, mLineStart + 1, APlan.Stop - mLineStart);
  APlan.SelStart := Length(mIndent) + Length(AOpener) + 1 + (APlan.Start - mLineStart);
  APlan.SelStop := APlan.SelStart + (APlan.Stop - APlan.Start);
  if (AStopPos.Line > AStartPos.Line) and (AStopPos.Character = 0) then
  begin
    APlan.Text := APlan.Text + mIndent + ACloser + #10;
  end
  else
  begin
    APlan.Text := APlan.Text + #10 + mIndent + ACloser;
  end;
  APlan.Start := mLineStart;
end;

function TWrapJob.PlanBrace(var APlan: TPlan; const ASelected: string; const AStartPos,
  AStopPos: TLspTextPosition): Boolean;
var
  mOpener, mCloser: string;
begin
  mOpener := '{';
  mCloser := '}';
  if Pos('}', ASelected) > 0 then
  begin
    mOpener := '(*';
    mCloser := '*)';
  end;
  // Beide Kommentarenden oder eine Direktive: nicht umschließen.
  Result := not (((mOpener = '(*') and (Pos('*)', ASelected) > 0)) or ASelected.StartsWith('$'));
  if Result and WholeLines(FLines, AStartPos, AStopPos) then
  begin
    PlanBraceLines(APlan, AStartPos, AStopPos, mOpener, mCloser);
  end
  else if Result then
  begin
    APlan.Text := mOpener + ASelected + mCloser;
    APlan.SelStart := Length(mOpener);
    APlan.SelStop := Length(mOpener) + Length(ASelected);
  end;
end;

function TWrapJob.PlanSelection(var APlan: TPlan; const ASelected: string; const AStartPos,
  AStopPos: TLspTextPosition): Boolean;
begin
  Result := True;
  if FOpen = '''' then
  begin
    Result := PlanQuote(APlan, ASelected, AStartPos, AStopPos);
  end
  else if FOpen = '<' then
  begin
    Result := PlanAngle(APlan, ASelected);
  end
  else if FOpen = '{' then
  begin
    Result := PlanBrace(APlan, ASelected, AStartPos, AStopPos);
  end
  else
  begin
    APlan.Text := FOpen + ASelected + TAtlasWrapSelection.CloserOf(FOpen);
    APlan.SelStart := 1;
    APlan.SelStop := 1 + Length(ASelected);
  end;
end;

function TWrapJob.PlanFor(const ARange: TLspRange; out APlan: TPlan; out ASelected: Boolean): Boolean;
var
  mStartPos, mStopPos: TLspTextPosition;
  mSelected: string;
begin
  mStartPos := ARange.StartPos;
  mStopPos := ARange.EndPos;
  if TLspTextPosition.Compare(mStopPos, mStartPos) < 0 then
  begin
    mStartPos := ARange.EndPos;
    mStopPos := ARange.StartPos;
  end;
  APlan := Default(TPlan);
  APlan.Start := OffsetOf(FLines, FStarts, mStartPos);
  APlan.Stop := OffsetOf(FLines, FStarts, mStopPos);
  mStartPos := PositionOf(FStarts, APlan.Start);
  mStopPos := PositionOf(FStarts, APlan.Stop);
  mSelected := Copy(FText, APlan.Start + 1, APlan.Stop - APlan.Start);
  ASelected := mSelected <> '';
  Result := True;
  if not ASelected then
  begin
    // Ohne Markierung: das Zeichen wie beim Tippen.
    APlan.Text := FOpen;
    APlan.SelStart := 1;
    APlan.SelStop := 1;
  end
  else
  begin
    Result := PlanSelection(APlan, mSelected, mStartPos, mStopPos);
  end;
end;

function TWrapJob.Run(const ALines: TArray<string>; const ARanges: TArray<TLspRange>; AOpen: Char;
  var AResult: TAtlasWrapResult): Boolean;
var
  mPlans: TArray<TPlan>;
  mOrder: TArray<Integer>;
  mIndex: Integer;
  mOk, mSelected, mHasSelection: Boolean;
begin
  FLines := ALines;
  if Length(FLines) = 0 then
  begin
    FLines := [''];
  end;
  FText := string.Join(#10, FLines);
  FStarts := LineStarts(FLines);
  FSpansRead := False;
  FOpen := AOpen;
  SetLength(mPlans, Length(ARanges));
  mOk := True;
  mHasSelection := False;
  mIndex := 0;
  while mOk and (mIndex <= High(ARanges)) do
  begin
    mOk := PlanFor(ARanges[mIndex], mPlans[mIndex], mSelected);
    mHasSelection := mHasSelection or mSelected;
    Inc(mIndex);
  end;
  mOrder := PlanOrder(mPlans);
  Result := mOk and mHasSelection and not Overlapping(mPlans, mOrder);
  if Result then
  begin
    AResult.Lines := ApplyPlans(FText, mPlans, mOrder).Split([#10]);
    if Length(AResult.Lines) = 0 then
    begin
      AResult.Lines := [''];
    end;
    AResult.Selections := SelectionsOf(mPlans, LineStarts(AResult.Lines));
  end;
end;

{ TAtlasWrapSelection }

class function TAtlasWrapSelection.Normalize(const AChars: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in AChars do
  begin
    if (Pos(Ch, AllChars) > 0) and (Pos(Ch, Result) = 0) then
    begin
      Result := Result + Ch;
    end;
  end;
end;

class function TAtlasWrapSelection.Accepts(AChar: Char; const AChars: string): Boolean;
begin
  Result := (Pos(AChar, AllChars) > 0) and (Pos(AChar, AChars) > 0);
end;

class function TAtlasWrapSelection.CloserOf(AOpen: Char): Char;
begin
  case AOpen of
    '(':
      Result := ')';
    '[':
      Result := ']';
    '{':
      Result := '}';
    '<':
      Result := '>';
    '''':
      Result := '''';
  else
    Result := #0;
  end;
end;

class function TAtlasWrapSelection.Wrap(const ALines: TArray<string>; const ARange: TLspRange; AOpen: Char;
  const AChars: string; out AResult: TAtlasWrapResult): Boolean;
begin
  Result := Wrap(ALines, TArray<TLspRange>.Create(ARange), AOpen, AChars, AResult);
end;

class function TAtlasWrapSelection.Wrap(const ALines: TArray<string>; const ARanges: TArray<TLspRange>;
  AOpen: Char; const AChars: string; out AResult: TAtlasWrapResult): Boolean;
var
  mJob: TWrapJob;
begin
  AResult.Lines := ALines;
  AResult.Selections := ARanges;
  Result := False;
  if Accepts(AOpen, AChars) and (Length(ARanges) > 0) then
  begin
    mJob := Default(TWrapJob);
    Result := mJob.Run(ALines, ARanges, AOpen, AResult);
  end;
end;

end.
