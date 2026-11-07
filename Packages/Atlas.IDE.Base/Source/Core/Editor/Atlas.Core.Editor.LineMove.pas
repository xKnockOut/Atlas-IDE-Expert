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

  /// <summary>Zeilen First..Last (0-basiert); MethodLine: Cursorzeile ohne Markierung, -1 mit Markierung.</summary>
  TAtlasLineSelection = record
    First: Integer;
    Last: Integer;
    MethodLine: Integer;
    class function Create(AFirst, ALast, AMethodLine: Integer): TAtlasLineSelection; static;
  end;

  TAtlasLineMover = class
  public
    /// <summary>Verschieben bzw. Duplizieren der Zeilen ASelection.First..Last von AText. Steht
    /// ASelection.MethodLine (Cursorzeile ohne Markierung, -1 mit Markierung) auf einem Methodenkopf, gilt die ganze
    /// Methode. AIndent: Einrückungsweite. False, wenn nichts geht (erste bzw. letzte Zeile, keine Nachbarmethode).
    /// </summary>
    class function Compute(const AText: string; const ASelection: TAtlasLineSelection; AKind: TAtlasLineMoveKind;
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

  TLineMoveJob = record
  private
    FText: string;
    FLines: TArray<string>;
    FSelection: TAtlasLineSelection;
    FKind: TAtlasLineMoveKind;
    FIndent: Integer;
    FMove: TAtlasLineMove;
    /// <summary>Methode samt der Kommentarzeilen direkt darüber.</summary>
    function SpanOf(const APlace: TAtlasMethodPlace): TSpan;
    /// <summary>Implementierungen in Textreihenfolge; ACurrent: die mit dem Cursor auf dem Kopf, -1 ohne.</summary>
    function MethodBodies(out ACurrent: Integer): TArray<TAtlasMethodPlace>;
    procedure FillMethodMove(const AUpper, ALower: TSpan);
    /// <summary>Ganze Methode an der Nachbarmethode vorbei.</summary>
    function MoveMethod(const ABodies: TArray<TAtlasMethodPlace>; ACurrent: Integer): Boolean;
    procedure Duplicate(const ABlock: TArray<string>);
    /// <summary>Zeilen mit der Nachbarzeile tauschen, Einzug nach den Blöcken der Nachbarzeile.</summary>
    function MoveLines(var ABlock: TArray<string>): Boolean;
    function MoveSelection: Boolean;
  public
    function Run(const AText: string; const ASelection: TAtlasLineSelection; AKind: TAtlasLineMoveKind;
      AIndent: Integer; out AMove: TAtlasLineMove): Boolean;
  end;

function LinesOf(const AText: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := AText.Split([#10]);
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex].EndsWith(#13) then
    begin
      Result[mIndex] := Copy(Result[mIndex], 1, Length(Result[mIndex]) - 1);
    end;
  end;
end;

/// <summary>Blöcke über mehrere Zeilen, die in ALine beginnen, weniger die, die dort enden.</summary>
function NetDepth(const ABlocks: TArray<TAtlasPairBlock>; ALine: Integer): Integer;
var
  mBlock: TAtlasPairBlock;
begin
  Result := 0;
  for mBlock in ABlocks do
  begin
    if mBlock.OpenLine <> mBlock.CloseLine then
    begin
      if mBlock.OpenLine = ALine then
      begin
        Inc(Result);
      end;
      if mBlock.CloseLine = ALine then
      begin
        Dec(Result);
      end;
    end;
  end;
end;

function LineRange(const ALines: TArray<string>; AFirst, ALast: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ALast - AFirst + 1);
  for mIndex := AFirst to ALast do
  begin
    Result[mIndex - AFirst] := ALines[mIndex];
  end;
end;

function Joined(const ALines: TArray<string>; AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if mIndex > AFirst then
    begin
      Result := Result + #10;
    end;
    Result := Result + ALines[mIndex];
  end;
end;

function CharAt(const AText: string; AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(AText)) then
  begin
    Result := AText[AIndex];
  end;
end;

/// <summary>Zeilenkommentar ab AIndex: Stelle des Zeilenumbruchs bzw. hinter dem Text.</summary>
function LineCommentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <> #10) do
  begin
    Inc(Result);
  end;
end;

/// <summary>{ … } ab AIndex: Stelle hinter "}"; AClosed = False ohne "}".</summary>
function BraceCommentEnd(const AText: string; AIndex: Integer; out AClosed: Boolean): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <> '}') do
  begin
    Inc(Result);
  end;
  AClosed := Result <= Length(AText);
  Inc(Result);
end;

/// <summary>(* … *) ab AIndex: Stelle hinter "*)"; AClosed = False ohne "*)".</summary>
function ParenCommentEnd(const AText: string; AIndex: Integer; out AClosed: Boolean): Integer;
begin
  Result := AIndex + 2;
  while (Result < Length(AText)) and not ((AText[Result] = '*') and (AText[Result + 1] = ')')) do
  begin
    Inc(Result);
  end;
  AClosed := Result < Length(AText);
  Inc(Result, 2);
end;

/// <summary>Leerraum oder Kommentar ab AIndex überspringen; AOk = False bei anderem Text, Direktiven und offenen
/// Kommentaren.</summary>
function SkipTrivia(const AText: string; AIndex: Integer; out AOk: Boolean): Integer;
var
  mChar, mNext: Char;
begin
  mChar := AText[AIndex];
  mNext := CharAt(AText, AIndex + 1);
  AOk := True;
  if CharInSet(mChar, [' ', #9, #10, #13]) then
  begin
    Result := AIndex + 1;
  end
  else if (mChar = '/') and (mNext = '/') then
  begin
    Result := LineCommentEnd(AText, AIndex);
  end
  else if (mChar = '{') and (mNext <> '$') then
  begin
    Result := BraceCommentEnd(AText, AIndex, AOk);
  end
  else if (mChar = '(') and (mNext = '*') and (CharAt(AText, AIndex + 2) <> '$') then
  begin
    Result := ParenCommentEnd(AText, AIndex, AOk);
  end
  else
  begin
    AOk := False;
    Result := AIndex;
  end;
end;

{ TAtlasLineSelection }

class function TAtlasLineSelection.Create(AFirst, ALast, AMethodLine: Integer): TAtlasLineSelection;
begin
  Result.First := AFirst;
  Result.Last := ALast;
  Result.MethodLine := AMethodLine;
end;

{ TLineMoveJob }

function TLineMoveJob.SpanOf(const APlace: TAtlasMethodPlace): TSpan;
const
  // Mehrzeilige Kommentare über einer Methode sind kurz; weiter oben zu suchen kostet nur Zeit.
  cMaxCommentLines = 60;
var
  mLine: Integer;
begin
  // Methode samt der Kommentarzeilen direkt darüber (ohne Leerzeile dazwischen).
  Result.First := APlace.FirstLine;
  Result.Last := APlace.LastLine;
  mLine := APlace.FirstLine - 1;
  while (mLine >= 0) and (mLine >= APlace.FirstLine - cMaxCommentLines) and (Trim(FLines[mLine]) <> '') do
  begin
    if TAtlasLineMover.IsCommentOnly(Joined(FLines, mLine, APlace.FirstLine - 1)) then
    begin
      Result.First := mLine;
    end;
    Dec(mLine);
  end;
end;

function TLineMoveJob.MethodBodies(out ACurrent: Integer): TArray<TAtlasMethodPlace>;
var
  mPlaces: TArray<TAtlasMethodPlace>;
  mPlace: TAtlasMethodPlace;
begin
  Result := nil;
  ACurrent := -1;
  mPlaces := TAtlasMethodToggle.Places(FText);
  for mPlace in mPlaces do
  begin
    if mPlace.IsBody then
    begin
      if (FSelection.MethodLine >= mPlace.FirstLine) and (FSelection.MethodLine <= mPlace.Line) then
      begin
        ACurrent := Length(Result);
      end;
      Result := Result + [mPlace];
    end;
  end;
end;

procedure TLineMoveJob.FillMethodMove(const AUpper, ALower: TSpan);
var
  mCount: Integer;
begin
  FMove.StartLine := AUpper.First;
  FMove.OldCount := ALower.Last - AUpper.First + 1;
  FMove.Lines := LineRange(FLines, ALower.First, ALower.Last) + LineRange(FLines, AUpper.Last + 1, ALower.First - 1) +
    LineRange(FLines, AUpper.First, AUpper.Last);
  if FKind = TAtlasLineMoveKind.MoveDown then
  begin
    FMove.LineShift := ALower.Last - AUpper.Last;
    FMove.OldFirstLine := AUpper.First;
    FMove.FirstLine := AUpper.First + FMove.LineShift;
    FMove.LastLine := ALower.Last;
    mCount := AUpper.Last - AUpper.First + 1;
  end
  else
  begin
    FMove.LineShift := AUpper.First - ALower.First;
    FMove.OldFirstLine := ALower.First;
    FMove.FirstLine := AUpper.First;
    FMove.LastLine := AUpper.First + ALower.Last - ALower.First;
    mCount := ALower.Last - ALower.First + 1;
  end;
  SetLength(FMove.IndentShift, mCount);
end;

function TLineMoveJob.MoveMethod(const ABodies: TArray<TAtlasMethodPlace>; ACurrent: Integer): Boolean;
var
  mNeighbor: Integer;
  mUpper, mLower: TSpan;
begin
  // Auch ohne Nachbarmethode gesetzt: Der Aufrufer meldet dann, warum nichts passiert.
  FMove.Method := True;
  mNeighbor := ACurrent + 1;
  if FKind = TAtlasLineMoveKind.MoveUp then
  begin
    mNeighbor := ACurrent - 1;
  end;
  Result := (mNeighbor >= 0) and (mNeighbor <= High(ABodies));
  if Result then
  begin
    if mNeighbor < ACurrent then
    begin
      mUpper := SpanOf(ABodies[mNeighbor]);
      mLower := SpanOf(ABodies[ACurrent]);
    end
    else
    begin
      mUpper := SpanOf(ABodies[ACurrent]);
      mLower := SpanOf(ABodies[mNeighbor]);
    end;
    // Dazwischen nur Leerzeilen und Kommentare, sonst würde die Methode über Code wandern.
    Result := (mLower.First > mUpper.Last) and ((mLower.First - mUpper.Last <= 1) or
      TAtlasLineMover.IsCommentOnly(Joined(FLines, mUpper.Last + 1, mLower.First - 1)));
    if Result then
    begin
      FillMethodMove(mUpper, mLower);
    end;
  end;
end;

procedure TLineMoveJob.Duplicate(const ABlock: TArray<string>);
begin
  FMove.Lines := ABlock;
  if FKind = TAtlasLineMoveKind.DuplicateUp then
  begin
    FMove.StartLine := FSelection.First;
    FMove.FirstLine := FSelection.First;
    FMove.LineShift := 0;
  end
  else
  begin
    FMove.StartLine := FSelection.Last + 1;
    FMove.FirstLine := FSelection.Last + 1;
    FMove.LineShift := Length(ABlock);
  end;
end;

function TLineMoveJob.MoveLines(var ABlock: TArray<string>): Boolean;
var
  mBlocks: TArray<TAtlasPairBlock>;
  mNeighbor, mLevels, mIndex: Integer;
begin
  mNeighbor := FSelection.Last + 1;
  if FKind = TAtlasLineMoveKind.MoveUp then
  begin
    mNeighbor := FSelection.First - 1;
  end;
  Result := (mNeighbor >= 0) and (mNeighbor <= High(FLines));
  if Result then
  begin
    TAtlasPairs.Analyze(FText, mBlocks);
    mLevels := NetDepth(mBlocks, mNeighbor);
    if FKind = TAtlasLineMoveKind.MoveUp then
    begin
      mLevels := -mLevels;
    end;
    for mIndex := 0 to High(ABlock) do
    begin
      ABlock[mIndex] := TAtlasLineMover.Reindent(ABlock[mIndex], mLevels, FIndent);
      FMove.IndentShift[mIndex] := Length(ABlock[mIndex]) - Length(FLines[FSelection.First + mIndex]);
    end;
    FMove.OldCount := Length(ABlock) + 1;
    if FKind = TAtlasLineMoveKind.MoveUp then
    begin
      FMove.StartLine := mNeighbor;
      FMove.Lines := ABlock + TArray<string>.Create(FLines[mNeighbor]);
      FMove.LineShift := -1;
    end
    else
    begin
      FMove.StartLine := FSelection.First;
      FMove.Lines := TArray<string>.Create(FLines[mNeighbor]) + ABlock;
      FMove.LineShift := 1;
    end;
    FMove.FirstLine := FSelection.First + FMove.LineShift;
  end;
end;

function TLineMoveJob.MoveSelection: Boolean;
var
  mBlock: TArray<string>;
begin
  mBlock := LineRange(FLines, FSelection.First, FSelection.Last);
  FMove.OldFirstLine := FSelection.First;
  SetLength(FMove.IndentShift, Length(mBlock));
  Result := True;
  if FKind in [TAtlasLineMoveKind.DuplicateUp, TAtlasLineMoveKind.DuplicateDown] then
  begin
    Duplicate(mBlock);
  end
  else
  begin
    Result := MoveLines(mBlock);
  end;
  if Result then
  begin
    FMove.LastLine := FMove.FirstLine + Length(mBlock) - 1;
  end;
end;

function TLineMoveJob.Run(const AText: string; const ASelection: TAtlasLineSelection; AKind: TAtlasLineMoveKind;
  AIndent: Integer; out AMove: TAtlasLineMove): Boolean;
var
  mBodies: TArray<TAtlasMethodPlace>;
  mCurrent: Integer;
begin
  FMove := Default(TAtlasLineMove);
  FText := AText;
  FLines := LinesOf(AText);
  FSelection := ASelection;
  FKind := AKind;
  FIndent := AIndent;
  if FIndent < 1 then
  begin
    FIndent := 2;
  end;
  Result := False;
  if (ASelection.First >= 0) and (ASelection.Last >= ASelection.First) and (ASelection.Last <= High(FLines)) then
  begin
    // Ganze Methode, wenn der Cursor ohne Markierung auf ihrem Kopf steht.
    mCurrent := -1;
    if (ASelection.MethodLine >= 0) and (AKind in [TAtlasLineMoveKind.MoveUp, TAtlasLineMoveKind.MoveDown]) then
    begin
      mBodies := MethodBodies(mCurrent);
    end;
    if mCurrent >= 0 then
    begin
      Result := MoveMethod(mBodies, mCurrent);
    end
    else
    begin
      Result := MoveSelection;
    end;
  end;
  AMove := FMove;
end;

{ TAtlasLineMover }

class function TAtlasLineMover.IsCommentOnly(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := 1;
  Result := True;
  while Result and (mIndex <= Length(AText)) do
  begin
    mIndex := SkipTrivia(AText, mIndex, Result);
  end;
end;

class function TAtlasLineMover.Reindent(const ALine: string; ALevels, AIndent: Integer): string;
var
  mNeed, mRemoved, mIndex: Integer;
begin
  Result := ALine;
  if (ALevels = 0) or (Trim(ALine) = '') then
  begin
    Exit;
  end;
  if ALevels > 0 then
  begin
    // Mit Tabulator eingerückte Zeilen bekommen Tabulatoren.
    if ALine.StartsWith(#9) then
    begin
      Exit(StringOfChar(#9, ALevels) + ALine);
    end;
    Exit(StringOfChar(' ', ALevels * AIndent) + ALine);
  end;
  mNeed := -ALevels * AIndent;
  mRemoved := 0;
  mIndex := 1;
  while (mIndex <= Length(ALine)) and (mRemoved < mNeed) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    if ALine[mIndex] = #9 then
    begin
      Inc(mRemoved, AIndent);
    end
    else
    begin
      Inc(mRemoved);
    end;
    Inc(mIndex);
  end;
  Result := Copy(ALine, mIndex, MaxInt);
end;

class function TAtlasLineMover.Compute(const AText: string; const ASelection: TAtlasLineSelection;
  AKind: TAtlasLineMoveKind; AIndent: Integer; out AMove: TAtlasLineMove): Boolean;
var
  mJob: TLineMoveJob;
begin
  mJob := Default(TLineMoveJob);
  Result := mJob.Run(AText, ASelection, AKind, AIndent, AMove);
end;

class function TAtlasLineMover.Apply(const ALines: TArray<string>; const AMove: TAtlasLineMove): TArray<string>;
begin
  Result := LineRange(ALines, 0, AMove.StartLine - 1) + AMove.Lines +
    LineRange(ALines, AMove.StartLine + AMove.OldCount, High(ALines));
end;

class procedure TAtlasLineMover.MapPosition(const AMove: TAtlasLineMove; var ALine, ACharacter: Integer);
var
  mOffset: Integer;
begin
  mOffset := ALine - AMove.OldFirstLine;
  if (mOffset < 0) or (mOffset > High(AMove.IndentShift)) then
  begin
    Exit;
  end;
  ALine := ALine + AMove.LineShift;
  ACharacter := ACharacter + AMove.IndentShift[mOffset];
  if ACharacter < 0 then
  begin
    ACharacter := 0;
  end;
end;

class function TAtlasLineMover.Difference(const AOld, ANew: string; out AStart, AOldLength: Integer;
  out AInsert: string): Boolean;
var
  mPrefix, mSuffix, mLimit: Integer;
begin
  AStart := 0;
  AOldLength := 0;
  AInsert := '';
  if AOld = ANew then
  begin
    Exit(False);
  end;
  mLimit := Length(AOld);
  if Length(ANew) < mLimit then
  begin
    mLimit := Length(ANew);
  end;
  mPrefix := 0;
  while (mPrefix < mLimit) and (AOld[mPrefix + 1] = ANew[mPrefix + 1]) do
  begin
    Inc(mPrefix);
  end;
  // Zurück an den Zeilenanfang: Ersetzt werden ganze Zeilen, nie ein halbes #13#10.
  while (mPrefix > 0) and (AOld[mPrefix] <> #10) do
  begin
    Dec(mPrefix);
  end;
  mSuffix := 0;
  while (mSuffix < mLimit - mPrefix) and (AOld[Length(AOld) - mSuffix] = ANew[Length(ANew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  while (mSuffix > 0) and (AOld[Length(AOld) - mSuffix] <> #10) do
  begin
    Dec(mSuffix);
  end;
  AStart := mPrefix;
  AOldLength := Length(AOld) - mSuffix - mPrefix;
  AInsert := Copy(ANew, mPrefix + 1, Length(ANew) - mSuffix - mPrefix);
  Result := True;
end;

end.
