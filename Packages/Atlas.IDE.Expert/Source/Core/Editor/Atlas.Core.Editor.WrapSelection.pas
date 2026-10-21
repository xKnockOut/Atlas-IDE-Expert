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
      First := Middle
    else
      Last := Middle - 1;
  end;
  Result := TLspTextPosition.Create(First, AOffset - AStarts[First]);
end;

function LeadingWhitespace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

/// <summary>Beginnt APos in einem String (nach dem öffnenden Hochkomma)?</summary>
function InString(const ASpans: TArray<TAtlasCommentSpan>; const APos: TLspTextPosition): Boolean;
var
  Span: TAtlasCommentSpan;
begin
  Result := False;
  for Span in ASpans do
    if (Span.Kind = TAtlasCommentSpanKind.StringLiteral) and
      (TLspTextPosition.Compare(Span.StartPos, APos) < 0) and (TLspTextPosition.Compare(APos, Span.EndPos) < 0) then
      Exit(True);
end;

/// <summary>Steht vor AOffset (0-basiert) direkt ein Typname (Bezeichner, der mit Buchstabe oder _ beginnt)?
/// </summary>
function AfterTypeName(const AText: string; AOffset: Integer): Boolean;
var
  Index: Integer;
begin
  Index := AOffset;
  while (Index >= 1) and TTextChars.IsIdentChar(AText[Index]) do
    Dec(Index);
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

{ TAtlasWrapSelection }

class function TAtlasWrapSelection.Normalize(const AChars: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in AChars do
    if (Pos(Ch, AllChars) > 0) and (Pos(Ch, Result) = 0) then
      Result := Result + Ch;
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
  Lines: TArray<string>;
  Starts, Order: TArray<Integer>;
  Spans: TArray<TAtlasCommentSpan>;
  Plans: TArray<TPlan>;
  Text, NewText, Selected, Indent, Open, Close: string;
  Index, Other, Swap, LineStart, Delta: Integer;
  StartPos, StopPos: TLspTextPosition;
  Plan: TPlan;
  HasSelection, SpansRead: Boolean;
begin
  AResult.Lines := ALines;
  AResult.Selections := ARanges;
  Result := False;
  if not Accepts(AOpen, AChars) or (Length(ARanges) = 0) then
    Exit;
  Lines := ALines;
  if Length(Lines) = 0 then
    Lines := [''];
  Text := string.Join(#10, Lines);
  Starts := LineStarts(Lines);
  SpansRead := False;
  HasSelection := False;
  SetLength(Plans, Length(ARanges));
  for Index := 0 to High(ARanges) do
  begin
    StartPos := ARanges[Index].StartPos;
    StopPos := ARanges[Index].EndPos;
    if TLspTextPosition.Compare(StopPos, StartPos) < 0 then
    begin
      StartPos := ARanges[Index].EndPos;
      StopPos := ARanges[Index].StartPos;
    end;
    Plan := Default(TPlan);
    Plan.Start := OffsetOf(Lines, Starts, StartPos);
    Plan.Stop := OffsetOf(Lines, Starts, StopPos);
    StartPos := PositionOf(Starts, Plan.Start);
    StopPos := PositionOf(Starts, Plan.Stop);
    Selected := Copy(Text, Plan.Start + 1, Plan.Stop - Plan.Start);
    if Selected = '' then
    begin
      // Ohne Markierung: das Zeichen wie beim Tippen.
      Plan.Text := AOpen;
      Plan.SelStart := 1;
      Plan.SelStop := 1;
    end
    else
    begin
      HasSelection := True;
      case AOpen of
        '''':
          begin
            if StartPos.Line <> StopPos.Line then
              Exit;
            if not SpansRead then
            begin
              Spans := TAtlasBlockComment.Spans(Lines);
              SpansRead := True;
            end;
            if InString(Spans, StartPos) then
              Exit;
            Selected := StringReplace(Selected, '''', '''''', [rfReplaceAll]);
            Plan.Text := '''' + Selected + '''';
            Plan.SelStart := 1;
            Plan.SelStop := 1 + Length(Selected);
          end;
        '<':
          begin
            if not AfterTypeName(Text, Plan.Start) then
              Exit;
            Plan.Text := '<' + Selected + '>';
            Plan.SelStart := 1;
            Plan.SelStop := 1 + Length(Selected);
          end;
        '{':
          begin
            Open := '{';
            Close := '}';
            if Pos('}', Selected) > 0 then
            begin
              Open := '(*';
              Close := '*)';
            end;
            if ((Open = '(*') and (Pos('*)', Selected) > 0)) or Selected.StartsWith('$') then
              Exit;
            if WholeLines(Lines, StartPos, StopPos) then
            begin
              // Kommentarzeichen auf eigenen Zeilen, Einrückung der ersten Zeile.
              Indent := LeadingWhitespace(Lines[StartPos.Line]);
              LineStart := Starts[StartPos.Line];
              Plan.Text := Indent + Open + #10 + Copy(Text, LineStart + 1, Plan.Stop - LineStart);
              Plan.SelStart := Length(Indent) + Length(Open) + 1 + (Plan.Start - LineStart);
              Plan.SelStop := Plan.SelStart + (Plan.Stop - Plan.Start);
              if (StopPos.Line > StartPos.Line) and (StopPos.Character = 0) then
                Plan.Text := Plan.Text + Indent + Close + #10
              else
                Plan.Text := Plan.Text + #10 + Indent + Close;
              Plan.Start := LineStart;
            end
            else
            begin
              Plan.Text := Open + Selected + Close;
              Plan.SelStart := Length(Open);
              Plan.SelStop := Length(Open) + Length(Selected);
            end;
          end;
      else
        Plan.Text := AOpen + Selected + CloserOf(AOpen);
        Plan.SelStart := 1;
        Plan.SelStop := 1 + Length(Selected);
      end;
    end;
    Plans[Index] := Plan;
  end;
  if not HasSelection then
    Exit;
  // Von hinten nach vorn einsetzen; was dahinter liegt, rückt um die Längenänderung.
  SetLength(Order, Length(Plans));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  for Index := 1 to High(Order) do
  begin
    Other := Index;
    while (Other > 0) and (Plans[Order[Other - 1]].Start < Plans[Order[Other]].Start) do
    begin
      Swap := Order[Other];
      Order[Other] := Order[Other - 1];
      Order[Other - 1] := Swap;
      Dec(Other);
    end;
  end;
  for Index := 1 to High(Order) do
    if Plans[Order[Index]].Stop > Plans[Order[Index - 1]].Start then
      Exit;
  NewText := Text;
  for Index := 0 to High(Order) do
  begin
    Plan := Plans[Order[Index]];
    NewText := Copy(NewText, 1, Plan.Start) + Plan.Text + Copy(NewText, Plan.Stop + 1, MaxInt);
    Delta := Length(Plan.Text) - (Plan.Stop - Plan.Start);
    for Other := 0 to Index - 1 do
    begin
      Inc(Plans[Order[Other]].FinalStart, Delta);
      Inc(Plans[Order[Other]].FinalStop, Delta);
    end;
    Plans[Order[Index]].FinalStart := Plan.Start + Plan.SelStart;
    Plans[Order[Index]].FinalStop := Plan.Start + Plan.SelStop;
  end;
  AResult.Lines := NewText.Split([#10]);
  if Length(AResult.Lines) = 0 then
    AResult.Lines := [''];
  Starts := LineStarts(AResult.Lines);
  SetLength(AResult.Selections, Length(Plans));
  for Index := 0 to High(Plans) do
  begin
    AResult.Selections[Index].StartPos := PositionOf(Starts, Plans[Index].FinalStart);
    AResult.Selections[Index].EndPos := PositionOf(Starts, Plans[Index].FinalStop);
  end;
  Result := True;
end;

end.
