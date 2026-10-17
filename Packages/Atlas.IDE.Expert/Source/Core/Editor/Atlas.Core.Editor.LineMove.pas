unit Atlas.Core.Editor.LineMove;

// Zeilen und Blöcke verschieben und duplizieren (#634), ohne Open Tools API:
// - Verschieben (Alt+↑/↓): die Zeilen AFirst..ALast tauschen mit der Zeile
//   darüber bzw. darunter. Wandern sie dabei über einen Blockanfang oder ein
//   Blockende (begin/end, try/end, repeat/until, case, class/record … end;
//   gepaarte Blöcke aus Atlas.Core.Editor.Pairs), ändert sich ihr Einzug um
//   die Einrückungsweite je Ebene: Abwärts über "begin" eine Ebene tiefer,
//   über "end;" eine höher, aufwärts umgekehrt. finally/except, "end else
//   begin" und Blöcke in einer Zeile ändern nichts. Leere Zeilen bleiben leer.
// - Duplizieren (Umschalt+Alt+↑/↓): die Zeilen noch einmal darüber bzw.
//   darunter; der Block (und mit ihm der Cursor) ist danach die Kopie.
// - Methode: Steht der Cursor ohne Markierung auf dem Kopf einer
//   Implementierung (Atlas.Core.Editor.MethodToggle), wandert die ganze
//   Methode samt der Kommentare direkt darüber an der Nachbarmethode vorbei.
//   Zwischen beiden dürfen nur Leerzeilen und Kommentare stehen; sie bleiben
//   in der Mitte. Ohne Nachbarmethode passiert nichts.
// Zeilen sind 0-basiert und ohne Zeilenumbruch. Difference macht aus altem und
// neuem Text eine Ersetzung ganzer Zeilen, damit die IDE sie in einem Schritt
// schreiben kann.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasLineMoveKind = (MoveUp, MoveDown, DuplicateUp, DuplicateDown);
  {$SCOPEDENUMS OFF}

  /// <summary>Ersetzt OldCount Zeilen ab StartLine durch Lines.</summary>
  TAtlasLineMove = record
    StartLine: Integer;
    OldCount: Integer;
    Lines: TArray<string>;
    /// <summary>Erste Zeile des Blocks vorher (bei der Methode samt Kommentaren).</summary>
    OldFirstLine: Integer;
    /// <summary>Verschobener bzw. kopierter Block im neuen Text.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>Zeile L des alten Blocks steht danach in L + LineShift.</summary>
    LineShift: Integer;
    /// <summary>Je Zeile des Blocks: Zeichen, um die der Einzug den Text verschiebt.</summary>
    IndentShift: TArray<Integer>;
    /// <summary>Die ganze Methode ist an der Nachbarmethode vorbei gewandert; bei Compute = False: Der Cursor stand
    /// auf einem Methodenkopf ohne Nachbarmethode.</summary>
    Method: Boolean;
  end;

  TAtlasLineMover = class
  public
    /// <summary>Verschieben bzw. Duplizieren der Zeilen AFirst..ALast von AText. AMethodLine: Cursorzeile ohne
    /// Markierung (-1 mit Markierung); steht sie auf einem Methodenkopf, gilt die ganze Methode. AIndent:
    /// Einrückungsweite. False, wenn nichts geht (erste bzw. letzte Zeile, keine Nachbarmethode).</summary>
    class function Compute(const AText: string; AFirst, ALast, AMethodLine: Integer; AKind: TAtlasLineMoveKind;
      AIndent: Integer; out AMove: TAtlasLineMove): Boolean; static;
    /// <summary>AMove auf ALines angewandt.</summary>
    class function Apply(const ALines: TArray<string>; const AMove: TAtlasLineMove): TArray<string>; static;
    /// <summary>Neue Stelle einer Position im alten Block (Zeile, Zeichen); außerhalb des Blocks unverändert.
    /// </summary>
    class procedure MapPosition(const AMove: TAtlasLineMove; var ALine, ACharacter: Integer); static;
    /// <summary>Ersetzung, die AOld zu ANew macht: ab Zeichen AStart (0-basiert) AOldLength Zeichen durch AInsert.
    /// Anfang und Ende liegen an Zeilenanfängen. False, wenn beide gleich sind.</summary>
    class function Difference(const AOld, ANew: string; out AStart, AOldLength: Integer;
      out AInsert: string): Boolean; static;
    /// <summary>Text aus Kommentaren und Leerraum? Direktiven ({$…}, (*$…*)) zählen nicht dazu.</summary>
    class function IsCommentOnly(const AText: string): Boolean; static;
    /// <summary>ALine um ALevels Ebenen ein- (positiv) bzw. ausgerückt; leere Zeilen bleiben, wie sie sind.</summary>
    class function Reindent(const ALine: string; ALevels, AIndent: Integer): string; static;
  end;

implementation

uses
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.MethodToggle;

type
  TSpan = record
    First: Integer;
    Last: Integer;
  end;

function LinesOf(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
    if Result[Index].EndsWith(#13) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

/// <summary>Blöcke über mehrere Zeilen, die in ALine beginnen, weniger die, die dort enden.</summary>
function NetDepth(const ABlocks: TArray<TAtlasPairBlock>; ALine: Integer): Integer;
var
  Block: TAtlasPairBlock;
begin
  Result := 0;
  for Block in ABlocks do
    if Block.OpenLine <> Block.CloseLine then
    begin
      if Block.OpenLine = ALine then
        Inc(Result);
      if Block.CloseLine = ALine then
        Dec(Result);
    end;
end;

function LineRange(const ALines: TArray<string>; AFirst, ALast: Integer): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, ALast - AFirst + 1);
  for Index := AFirst to ALast do
    Result[Index - AFirst] := ALines[Index];
end;

function Joined(const ALines: TArray<string>; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
  begin
    if Index > AFirst then
      Result := Result + #10;
    Result := Result + ALines[Index];
  end;
end;

{ TAtlasLineMover }

class function TAtlasLineMover.IsCommentOnly(const AText: string): Boolean;
var
  Index, Count: Integer;
begin
  Index := 1;
  Count := Length(AText);
  while Index <= Count do
  begin
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Inc(Index)
    else if (AText[Index] = '/') and (Index < Count) and (AText[Index + 1] = '/') then
    begin
      while (Index <= Count) and (AText[Index] <> #10) do
        Inc(Index);
    end
    else if AText[Index] = '{' then
    begin
      if (Index < Count) and (AText[Index + 1] = '$') then
        Exit(False);
      while (Index <= Count) and (AText[Index] <> '}') do
        Inc(Index);
      if Index > Count then
        Exit(False);
      Inc(Index);
    end
    else if (AText[Index] = '(') and (Index < Count) and (AText[Index + 1] = '*') then
    begin
      if (Index + 1 < Count) and (AText[Index + 2] = '$') then
        Exit(False);
      Inc(Index, 2);
      while (Index < Count) and not ((AText[Index] = '*') and (AText[Index + 1] = ')')) do
        Inc(Index);
      if Index >= Count then
        Exit(False);
      Inc(Index, 2);
    end
    else
      Exit(False);
  end;
  Result := True;
end;

class function TAtlasLineMover.Reindent(const ALine: string; ALevels, AIndent: Integer): string;
var
  Need, Removed, Index: Integer;
begin
  Result := ALine;
  if (ALevels = 0) or (Trim(ALine) = '') then
    Exit;
  if ALevels > 0 then
  begin
    // Mit Tabulator eingerückte Zeilen bekommen Tabulatoren.
    if ALine.StartsWith(#9) then
      Exit(StringOfChar(#9, ALevels) + ALine);
    Exit(StringOfChar(' ', ALevels * AIndent) + ALine);
  end;
  Need := -ALevels * AIndent;
  Removed := 0;
  Index := 1;
  while (Index <= Length(ALine)) and (Removed < Need) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    if ALine[Index] = #9 then
      Inc(Removed, AIndent)
    else
      Inc(Removed);
    Inc(Index);
  end;
  Result := Copy(ALine, Index, MaxInt);
end;

class function TAtlasLineMover.Compute(const AText: string; AFirst, ALast, AMethodLine: Integer;
  AKind: TAtlasLineMoveKind; AIndent: Integer; out AMove: TAtlasLineMove): Boolean;
var
  Lines, Block: TArray<string>;
  Blocks: TArray<TAtlasPairBlock>;
  Places, Bodies: TArray<TAtlasMethodPlace>;
  Place: TAtlasMethodPlace;
  Upper, Lower: TSpan;
  Index, Current, Neighbor, Levels, Count: Integer;

  /// <summary>Methode samt der Kommentarzeilen direkt darüber (ohne Leerzeile dazwischen).</summary>
  function SpanOf(const APlace: TAtlasMethodPlace): TSpan;
  const
    // Mehrzeilige Kommentare über einer Methode sind kurz; weiter oben zu suchen kostet nur Zeit.
    MaxCommentLines = 60;
  var
    Line: Integer;
  begin
    Result.First := APlace.FirstLine;
    Result.Last := APlace.LastLine;
    Line := APlace.FirstLine - 1;
    while (Line >= 0) and (Line >= APlace.FirstLine - MaxCommentLines) and (Trim(Lines[Line]) <> '') do
    begin
      if IsCommentOnly(Joined(Lines, Line, APlace.FirstLine - 1)) then
        Result.First := Line;
      Dec(Line);
    end;
  end;

begin
  AMove := Default(TAtlasLineMove);
  Result := False;
  Lines := LinesOf(AText);
  if AIndent < 1 then
    AIndent := 2;
  if (AFirst < 0) or (ALast < AFirst) or (ALast > High(Lines)) then
    Exit;
  // Ganze Methode, wenn der Cursor ohne Markierung auf ihrem Kopf steht.
  if (AMethodLine >= 0) and (AKind in [TAtlasLineMoveKind.MoveUp, TAtlasLineMoveKind.MoveDown]) then
  begin
    Places := TAtlasMethodToggle.Places(AText);
    Bodies := nil;
    Current := -1;
    for Place in Places do
      if Place.IsBody then
      begin
        if (AMethodLine >= Place.FirstLine) and (AMethodLine <= Place.Line) then
          Current := Length(Bodies);
        Bodies := Bodies + [Place];
      end;
    if Current >= 0 then
    begin
      // Auch ohne Nachbarmethode gesetzt: Der Aufrufer meldet dann, warum nichts passiert.
      AMove.Method := True;
      if AKind = TAtlasLineMoveKind.MoveUp then
        Neighbor := Current - 1
      else
        Neighbor := Current + 1;
      if (Neighbor < 0) or (Neighbor > High(Bodies)) then
        Exit;
      if Neighbor < Current then
      begin
        Upper := SpanOf(Bodies[Neighbor]);
        Lower := SpanOf(Bodies[Current]);
      end
      else
      begin
        Upper := SpanOf(Bodies[Current]);
        Lower := SpanOf(Bodies[Neighbor]);
      end;
      // Dazwischen nur Leerzeilen und Kommentare, sonst würde die Methode über Code wandern.
      if (Lower.First <= Upper.Last) or
        ((Lower.First - Upper.Last > 1) and not IsCommentOnly(Joined(Lines, Upper.Last + 1, Lower.First - 1))) then
        Exit;
      AMove.StartLine := Upper.First;
      AMove.OldCount := Lower.Last - Upper.First + 1;
      AMove.Lines := LineRange(Lines, Lower.First, Lower.Last) + LineRange(Lines, Upper.Last + 1, Lower.First - 1) +
        LineRange(Lines, Upper.First, Upper.Last);
      if AKind = TAtlasLineMoveKind.MoveDown then
      begin
        AMove.LineShift := Lower.Last - Upper.Last;
        AMove.OldFirstLine := Upper.First;
        AMove.FirstLine := Upper.First + AMove.LineShift;
        AMove.LastLine := Lower.Last;
        Count := Upper.Last - Upper.First + 1;
      end
      else
      begin
        AMove.LineShift := Upper.First - Lower.First;
        AMove.OldFirstLine := Lower.First;
        AMove.FirstLine := Upper.First;
        AMove.LastLine := Upper.First + Lower.Last - Lower.First;
        Count := Lower.Last - Lower.First + 1;
      end;
      SetLength(AMove.IndentShift, Count);
      Exit(True);
    end;
  end;
  Block := LineRange(Lines, AFirst, ALast);
  Count := Length(Block);
  AMove.OldFirstLine := AFirst;
  SetLength(AMove.IndentShift, Count);
  case AKind of
    TAtlasLineMoveKind.DuplicateUp:
      begin
        AMove.StartLine := AFirst;
        AMove.Lines := Block;
        AMove.FirstLine := AFirst;
        AMove.LineShift := 0;
      end;
    TAtlasLineMoveKind.DuplicateDown:
      begin
        AMove.StartLine := ALast + 1;
        AMove.Lines := Block;
        AMove.FirstLine := ALast + 1;
        AMove.LineShift := Count;
      end;
  else
    begin
      if AKind = TAtlasLineMoveKind.MoveUp then
        Neighbor := AFirst - 1
      else
        Neighbor := ALast + 1;
      if (Neighbor < 0) or (Neighbor > High(Lines)) then
        Exit;
      TAtlasPairs.Analyze(AText, Blocks);
      Levels := NetDepth(Blocks, Neighbor);
      if AKind = TAtlasLineMoveKind.MoveUp then
        Levels := -Levels;
      for Index := 0 to Count - 1 do
      begin
        Block[Index] := Reindent(Block[Index], Levels, AIndent);
        AMove.IndentShift[Index] := Length(Block[Index]) - Length(Lines[AFirst + Index]);
      end;
      AMove.OldCount := Count + 1;
      if AKind = TAtlasLineMoveKind.MoveUp then
      begin
        AMove.StartLine := Neighbor;
        AMove.Lines := Block + [Lines[Neighbor]];
        AMove.LineShift := -1;
      end
      else
      begin
        AMove.StartLine := AFirst;
        AMove.Lines := [Lines[Neighbor]] + Block;
        AMove.LineShift := 1;
      end;
      AMove.FirstLine := AFirst + AMove.LineShift;
    end;
  end;
  AMove.LastLine := AMove.FirstLine + Count - 1;
  Result := True;
end;

class function TAtlasLineMover.Apply(const ALines: TArray<string>; const AMove: TAtlasLineMove): TArray<string>;
begin
  Result := LineRange(ALines, 0, AMove.StartLine - 1) + AMove.Lines +
    LineRange(ALines, AMove.StartLine + AMove.OldCount, High(ALines));
end;

class procedure TAtlasLineMover.MapPosition(const AMove: TAtlasLineMove; var ALine, ACharacter: Integer);
var
  Offset: Integer;
begin
  Offset := ALine - AMove.OldFirstLine;
  if (Offset < 0) or (Offset > High(AMove.IndentShift)) then
    Exit;
  ALine := ALine + AMove.LineShift;
  ACharacter := ACharacter + AMove.IndentShift[Offset];
  if ACharacter < 0 then
    ACharacter := 0;
end;

class function TAtlasLineMover.Difference(const AOld, ANew: string; out AStart, AOldLength: Integer;
  out AInsert: string): Boolean;
var
  Prefix, Suffix, Limit: Integer;
begin
  AStart := 0;
  AOldLength := 0;
  AInsert := '';
  if AOld = ANew then
    Exit(False);
  Limit := Length(AOld);
  if Length(ANew) < Limit then
    Limit := Length(ANew);
  Prefix := 0;
  while (Prefix < Limit) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
    Inc(Prefix);
  // Zurück an den Zeilenanfang: Ersetzt werden ganze Zeilen, nie ein halbes #13#10.
  while (Prefix > 0) and (AOld[Prefix] <> #10) do
    Dec(Prefix);
  Suffix := 0;
  while (Suffix < Limit - Prefix) and (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
    Inc(Suffix);
  while (Suffix > 0) and (AOld[Length(AOld) - Suffix] <> #10) do
    Dec(Suffix);
  AStart := Prefix;
  AOldLength := Length(AOld) - Suffix - Prefix;
  AInsert := Copy(ANew, Prefix + 1, Length(ANew) - Suffix - Prefix);
  Result := True;
end;

end.
