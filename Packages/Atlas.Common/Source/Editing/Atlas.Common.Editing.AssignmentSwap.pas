unit Atlas.Common.Editing.AssignmentSwap;

// Code-Aktion "Zuweisungen umkehren" (#313): In jeder markierten Zeile der
// Form "Links := Rechts;" werden die Seiten getauscht, z. B. für Paare aus
// "Daten ins Formular laden" und "Formular in Daten speichern".
//
// Umgedreht wird nur, wenn beide Seiten zuweisbar aussehen (Bezeichnerkette
// mit Punkten, Indizes und ^) und die neue linke Seite nicht als nur lesbar
// bekannt ist. Zuweisungen mit Aufruf, Konstante oder Ausdruck rechts bleiben
// stehen und bekommen den Kommentar "// nicht umkehrbar". Kommentare am
// Zeilenende und Einrückung bleiben erhalten. Ein am := ausgerichteter Block
// bleibt ausgerichtet, sonst bleiben die Leerräume um := wie sie sind;
// zweimal anwenden ergibt den Ausgangstext.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract;

type
  /// <summary>True, wenn AExpression nicht geschrieben werden kann (Property ohne write).</summary>
  TReadOnlyCheck = reference to function(const AExpression: string): Boolean;

  /// <summary>Eine Zeile als Zuweisung zerlegt.</summary>
  TAssignmentLine = record
    Indent: string;
    Left: string;
    /// <summary>Leerraum zwischen linker Seite und :=.</summary>
    GapBefore: string;
    /// <summary>Leerraum zwischen := und rechter Seite.</summary>
    GapAfter: string;
    Right: string;
    /// <summary>Leerraum und ';' hinter der rechten Seite; '' ohne Semikolon.</summary>
    Semicolon: string;
    /// <summary>Rest dahinter (Leerraum und Kommentar).</summary>
    Tail: string;
  end;

  TAssignmentSwap = class
  public const
    Marker = 'nicht umkehrbar';
  public
    /// <summary>Zerlegt ALine; False, wenn sie keine einzelne Zuweisung ist.</summary>
    class function Parse(const ALine: string; out AAssignment: TAssignmentLine): Boolean; static;
    /// <summary>Bezeichnerkette mit Punkten, Indizes und ^, keine Konstante.</summary>
    class function IsAssignable(const AExpression: string): Boolean; static;
    /// <summary>Edits für die Zeilen von ARange; False, wenn keine Zeile umgedreht wird.
    /// AReadOnly darf nil sein.</summary>
    class function Swap(const AText: string; const ARange: TTextRange; const AReadOnly: TReadOnlyCheck;
      out AEdits: TArray<TRuleEdit>): Boolean; static;
    /// <summary>Prüfung über den Index (#17): True, wenn alle Properties mit dem letzten Namen
    /// aus AExpression ohne write deklariert sind. Die Datei AFileName liest sie aus AText,
    /// andere von der Platte.</summary>
    class function ReadOnlyByIndex(const AIndex: ISymbolIndex; const AFileName, AText,
      AExpression: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

function IsBlank(C: Char): Boolean;
begin
  Result := CharInSet(C, [' ', #9]);
end;

/// <summary>Beginn des ersten Kommentars außerhalb von Strings; Length + 1 ohne.</summary>
function CommentStart(const ALine: string): Integer;
var
  I: Integer;
  InString: Boolean;
begin
  InString := False;
  for I := 1 to Length(ALine) do
    if ALine[I] = '''' then
      InString := not InString
    else if not InString and ((ALine[I] = '{') or (Copy(ALine, I, 2) = '//') or (Copy(ALine, I, 2) = '(*')) then
      Exit(I);
  Result := Length(ALine) + 1;
end;

/// <summary>Position von AWhat im Code vor ACodeEnd außerhalb von Strings ab AFrom; 0 ohne.</summary>
function CodePos(const AWhat, ALine: string; AFrom, ACodeEnd: Integer): Integer;
var
  I: Integer;
  InString: Boolean;
begin
  InString := False;
  for I := 1 to ACodeEnd - Length(AWhat) do
    if ALine[I] = '''' then
      InString := not InString
    else if not InString and (I >= AFrom) and (Copy(ALine, I, Length(AWhat)) = AWhat) then
      Exit(I);
  Result := 0;
end;

{ TAssignmentSwap }

class function TAssignmentSwap.Parse(const ALine: string; out AAssignment: TAssignmentLine): Boolean;
var
  Assign, Semi, Start, CodeEnd: Integer;
  Before, After: string;
begin
  AAssignment := Default(TAssignmentLine);
  CodeEnd := CommentStart(ALine);
  Assign := CodePos(':=', ALine, 1, CodeEnd);
  if Assign = 0 then
    Exit(False);
  Start := 1;
  while (Start < Assign) and IsBlank(ALine[Start]) do
    Inc(Start);
  AAssignment.Indent := Copy(ALine, 1, Start - 1);
  Before := Copy(ALine, Start, Assign - Start);
  AAssignment.Left := TrimRight(Before);
  AAssignment.GapBefore := Copy(Before, Length(AAssignment.Left) + 1, MaxInt);
  Semi := CodePos(';', ALine, Assign + 2, CodeEnd);
  if Semi = 0 then
    Semi := CodeEnd;
  After := Copy(ALine, Assign + 2, Semi - Assign - 2);
  AAssignment.Right := Trim(After);
  AAssignment.GapAfter := Copy(After, 1, Length(After) - Length(TrimLeft(After)));
  AAssignment.Semicolon := Copy(After, Length(AAssignment.GapAfter + AAssignment.Right) + 1, MaxInt);
  if Semi < CodeEnd then
    AAssignment.Semicolon := AAssignment.Semicolon + ';';
  if Semi < CodeEnd then
    AAssignment.Tail := Copy(ALine, Semi + 1, MaxInt)
  else
    AAssignment.Tail := Copy(ALine, CodeEnd, MaxInt);
  // Hinter dem Semikolon darf nur noch Leerraum und ein Kommentar stehen.
  Result := (AAssignment.Left <> '') and (AAssignment.Right <> '') and
    (Trim(Copy(AAssignment.Tail, 1, CommentStart(AAssignment.Tail) - 1)) = '');
end;

class function TAssignmentSwap.IsAssignable(const AExpression: string): Boolean;
var
  I, Depth: Integer;
  Expression: string;
begin
  Expression := Trim(AExpression);
  if (Expression = '') or SameText(Expression, 'nil') or SameText(Expression, 'True') or
    SameText(Expression, 'False') then
    Exit(False);
  I := 1;
  while I <= Length(Expression) do
  begin
    if not TTextChars.IsIdentStart(Expression[I]) then
      Exit(False);
    while (I <= Length(Expression)) and TTextChars.IsIdentChar(Expression[I]) do
      Inc(I);
    // Nach einem Bezeichner: Indizes und ^, dann ein Punkt oder das Ende.
    while (I <= Length(Expression)) and CharInSet(Expression[I], ['[', '^']) do
      if Expression[I] = '^' then
        Inc(I)
      else
      begin
        Depth := 0;
        repeat
          if Expression[I] = '[' then
            Inc(Depth)
          else if Expression[I] = ']' then
            Dec(Depth);
          Inc(I);
        until (Depth = 0) or (I > Length(Expression));
        if Depth <> 0 then
          Exit(False);
      end;
    if I > Length(Expression) then
      Exit(True);
    if Expression[I] <> '.' then
      Exit(False);
    Inc(I);
  end;
  Result := False;
end;

/// <summary>Kommentar "nicht umkehrbar" vor einen vorhandenen Zeilenkommentar oder ans Ende.</summary>
function MarkTail(const ATail: string): string;
var
  Rest: string;
begin
  Rest := TrimLeft(ATail);
  if StartsStr('//', Rest) then
    Result := Copy(ATail, 1, Length(ATail) - Length(Rest)) + '// ' + TAssignmentSwap.Marker + ';' +
      Copy(Rest, 3, MaxInt)
  else if Rest = '' then
    Result := ' // ' + TAssignmentSwap.Marker
  else
    Result := ' // ' + TAssignmentSwap.Marker + ' ' + Rest;
end;

class function TAssignmentSwap.Swap(const AText: string; const ARange: TTextRange; const AReadOnly: TReadOnlyCheck;
  out AEdits: TArray<TRuleEdit>): Boolean;
var
  Lines: TArray<string>;
  Parsed: TArray<TAssignmentLine>;
  IsAssignment, Swappable: TArray<Boolean>;
  First, LastLine, Index, Column, Width, MinGap, Count: Integer;
  Text, NewText, Gap: string;
  Aligned: Boolean;
begin
  AEdits := nil;
  Lines := TTextLines.SplitLines(AText);
  First := ARange.StartPos.Line;
  LastLine := ARange.EndPos.Line;
  // Markierung bis zum Zeilenanfang: Diese Zeile gehört nicht mehr dazu.
  if (LastLine > First) and (ARange.EndPos.Character = 0) then
    Dec(LastLine);
  if LastLine > High(Lines) then
    LastLine := High(Lines);
  if (First < 0) or (First > LastLine) then
    Exit(False);
  Count := LastLine - First + 1;
  SetLength(Parsed, Count);
  SetLength(IsAssignment, Count);
  SetLength(Swappable, Count);
  Column := -1;
  Aligned := True;
  MinGap := MaxInt;
  Width := 0;
  Result := False;
  for Index := 0 to Count - 1 do
  begin
    IsAssignment[Index] := Parse(Lines[First + Index], Parsed[Index]);
    Swappable[Index] := IsAssignment[Index] and IsAssignable(Parsed[Index].Left) and
      IsAssignable(Parsed[Index].Right) and not (Assigned(AReadOnly) and AReadOnly(Parsed[Index].Right));
    if not Swappable[Index] then
      Continue;
    Result := True;
    if Column < 0 then
      Column := Length(Parsed[Index].Indent + Parsed[Index].Left + Parsed[Index].GapBefore)
    else if Column <> Length(Parsed[Index].Indent + Parsed[Index].Left + Parsed[Index].GapBefore) then
      Aligned := False;
    if Length(Parsed[Index].GapBefore) < MinGap then
      MinGap := Length(Parsed[Index].GapBefore);
    if Length(Parsed[Index].Indent + Parsed[Index].Right) > Width then
      Width := Length(Parsed[Index].Indent + Parsed[Index].Right);
  end;
  if not Result then
    Exit;
  for Index := 0 to Count - 1 do
  begin
    if not IsAssignment[Index] then
      Continue;
    Text := Lines[First + Index];
    if Swappable[Index] then
    begin
      Gap := Parsed[Index].GapBefore;
      if Aligned then
        Gap := StringOfChar(' ', Width + MinGap - Length(Parsed[Index].Indent + Parsed[Index].Right));
      NewText := Parsed[Index].Indent + Parsed[Index].Right + Gap + ':=' + Parsed[Index].GapAfter +
        Parsed[Index].Left + Parsed[Index].Semicolon + Parsed[Index].Tail;
    end
    else if ContainsText(Parsed[Index].Tail, TAssignmentSwap.Marker) then
      Continue
    else
      NewText := Copy(Text, 1, Length(Text) - Length(Parsed[Index].Tail)) + MarkTail(Parsed[Index].Tail);
    if NewText <> Text then
      AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(First + Index, 0, First + Index, Length(Text)),
        NewText)];
  end;
end;

/// <summary>Letzter Bezeichner der Kette ohne Indizes und ^ (Kunde.Adressen[0].Ort → Ort).</summary>
function LastName(const AExpression: string): string;
var
  Expression: string;
  Dot: Integer;
begin
  Expression := Trim(AExpression);
  while (Expression <> '') and CharInSet(Expression[Length(Expression)], [']', '^']) do
    if Expression[Length(Expression)] = '^' then
      Expression := Copy(Expression, 1, Length(Expression) - 1)
    else
      Expression := Copy(Expression, 1, LastDelimiter('[', Expression) - 1);
  Dot := LastDelimiter('.', Expression);
  Result := Copy(Expression, Dot + 1, MaxInt);
end;

/// <summary>Text des Bereichs ARange in AText.</summary>
function RangeText(const AText: string; const ARange: TTextRange): string;
var
  Lines: TArray<string>;
  Line: Integer;
begin
  Result := '';
  Lines := TTextLines.SplitLines(AText);
  for Line := ARange.StartPos.Line to ARange.EndPos.Line do
    if (Line >= 0) and (Line <= High(Lines)) then
      Result := Result + ' ' + Lines[Line];
end;

function HasWord(const AText, AWord: string): Boolean;
var
  Lower: string;
  Start: Integer;
begin
  Lower := LowerCase(AText);
  Start := Pos(AWord, Lower);
  while Start > 0 do
  begin
    if ((Start = 1) or not TTextChars.IsIdentChar(Lower[Start - 1])) and
      ((Start + Length(AWord) > Length(Lower)) or not TTextChars.IsIdentChar(Lower[Start + Length(AWord)])) then
      Exit(True);
    Start := PosEx(AWord, Lower, Start + 1);
  end;
  Result := False;
end;

class function TAssignmentSwap.ReadOnlyByIndex(const AIndex: ISymbolIndex; const AFileName, AText,
  AExpression: string): Boolean;
var
  Location: TSymbolLocation;
  Text, Declaration: string;
begin
  Result := False;
  if AIndex = nil then
    Exit;
  for Location in AIndex.FindSymbols(LastName(AExpression)) do
  begin
    if Location.Symbol.Kind <> TIndexSymbolKind.Property_ then
      Continue;
    if SameText(Location.FileName, AFileName) then
      Text := AText
    else
      try
        Text := TFile.ReadAllText(Location.FileName);
      except
        on EInOutError do
          Continue;
        on EFileNotFoundException do
          Continue;
      end;
    Declaration := RangeText(Text, Location.Symbol.Range);
    // "property X;" hebt nur die Sichtbarkeit an und sagt nichts über write.
    if not HasWord(Declaration, 'read') and not HasWord(Declaration, 'write') then
      Continue;
    if HasWord(Declaration, 'write') then
      Exit(False);
    Result := True;
  end;
end;

end.
