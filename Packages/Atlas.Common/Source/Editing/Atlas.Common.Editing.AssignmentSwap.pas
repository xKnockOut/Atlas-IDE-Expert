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
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Prüfung über den Index (#17): True, wenn alle Properties mit dem letzten Namen
    /// aus AExpression ohne write deklariert sind. Die Datei AFileName liest sie aus AText,
    /// andere von der Platte.</summary>
    class function ReadOnlyByIndex(const AIndex: ISymbolIndex; const AFileName, AText,
      AExpression: string): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Common.Documents.FileEncoding;

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
  begin
    if ALine[I] = '''' then
    begin
      InString := not InString;
    end
    else if not InString and ((ALine[I] = '{') or (Copy(ALine, I, 2) = '//') or (Copy(ALine, I, 2) = '(*')) then
    begin
      Exit(I);
    end;
  end;
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
  begin
    if ALine[I] = '''' then
    begin
      InString := not InString;
    end
    else if not InString and (I >= AFrom) and (Copy(ALine, I, Length(AWhat)) = AWhat) then
    begin
      Exit(I);
    end;
  end;
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
  begin
    Exit(False);
  end;
  Start := 1;
  while (Start < Assign) and IsBlank(ALine[Start]) do
  begin
    Inc(Start);
  end;
  AAssignment.Indent := Copy(ALine, 1, Start - 1);
  Before := Copy(ALine, Start, Assign - Start);
  AAssignment.Left := TrimRight(Before);
  AAssignment.GapBefore := Copy(Before, Length(AAssignment.Left) + 1, MaxInt);
  Semi := CodePos(';', ALine, Assign + 2, CodeEnd);
  if Semi = 0 then
  begin
    Semi := CodeEnd;
  end;
  After := Copy(ALine, Assign + 2, Semi - Assign - 2);
  AAssignment.Right := Trim(After);
  AAssignment.GapAfter := Copy(After, 1, Length(After) - Length(TrimLeft(After)));
  AAssignment.Semicolon := Copy(After, Length(AAssignment.GapAfter + AAssignment.Right) + 1, MaxInt);
  if Semi < CodeEnd then
  begin
    AAssignment.Semicolon := AAssignment.Semicolon + ';';
  end;
  if Semi < CodeEnd then
  begin
    AAssignment.Tail := Copy(ALine, Semi + 1, MaxInt);
  end
  else
  begin
    AAssignment.Tail := Copy(ALine, CodeEnd, MaxInt);
  end;
  // Hinter dem Semikolon darf nur noch Leerraum und ein Kommentar stehen.
  Result := (AAssignment.Left <> '') and (AAssignment.Right <> '') and
    (Trim(Copy(AAssignment.Tail, 1, CommentStart(AAssignment.Tail) - 1)) = '');
end;

/// <summary>Überspringt ab AIndex eine Indexklammer samt verschachtelter Klammern; False, wenn sie offen
/// bleibt.</summary>
function SkipBrackets(const AExpression: string; var AIndex: Integer): Boolean;
var
  mDepth: Integer;
begin
  mDepth := 0;
  repeat
    if AExpression[AIndex] = '[' then
    begin
      Inc(mDepth);
    end
    else if AExpression[AIndex] = ']' then
    begin
      Dec(mDepth);
    end;
    Inc(AIndex);
  until (mDepth = 0) or (AIndex > Length(AExpression));
  Result := mDepth = 0;
end;

/// <summary>Überspringt Indizes und ^ hinter einem Bezeichner; False bei offener Klammer.</summary>
function SkipSelectors(const AExpression: string; var AIndex: Integer): Boolean;
begin
  Result := True;
  while Result and (AIndex <= Length(AExpression)) and CharInSet(AExpression[AIndex], ['[', '^']) do
  begin
    if AExpression[AIndex] = '^' then
    begin
      Inc(AIndex);
    end
    else
    begin
      Result := SkipBrackets(AExpression, AIndex);
    end;
  end;
end;

/// <summary>Überspringt ab AIndex einen Bezeichner samt Indizes und ^; False, wenn dort keiner beginnt oder eine
/// Klammer offen bleibt.</summary>
function SkipDesignatorPart(const AExpression: string; var AIndex: Integer): Boolean;
begin
  Result := (AIndex <= Length(AExpression)) and TTextChars.IsIdentStart(AExpression[AIndex]);
  if Result then
  begin
    while (AIndex <= Length(AExpression)) and TTextChars.IsIdentChar(AExpression[AIndex]) do
    begin
      Inc(AIndex);
    end;
    Result := SkipSelectors(AExpression, AIndex);
  end;
end;

class function TAssignmentSwap.IsAssignable(const AExpression: string): Boolean;
var
  mIndex: Integer;
  mExpression: string;
begin
  mExpression := Trim(AExpression);
  if (mExpression = '') or (IndexText(mExpression, ['nil', 'True', 'False']) >= 0) then
  begin
    Exit(False);
  end;
  mIndex := 1;
  // Nach jedem Bezeichner: ein Punkt oder das Ende.
  while SkipDesignatorPart(mExpression, mIndex) do
  begin
    if mIndex > Length(mExpression) then
    begin
      Exit(True);
    end;
    if mExpression[mIndex] <> '.' then
    begin
      Exit(False);
    end;
    Inc(mIndex);
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
  begin
    Result := Copy(ATail, 1, Length(ATail) - Length(Rest)) + '// ' + TAssignmentSwap.Marker + ';' +
      Copy(Rest, 3, MaxInt);
  end
  else if Rest = '' then
  begin
    Result := ' // ' + TAssignmentSwap.Marker;
  end
  else
  begin
    Result := ' // ' + TAssignmentSwap.Marker + ' ' + Rest;
  end;
end;

/// <summary>Zeilen der Markierung ARange in einem Text mit den Zeilen 0..AHigh; False ohne.</summary>
function SelectedLines(const ARange: TTextRange; AHigh: Integer; out AFirst, ALast: Integer): Boolean;
begin
  AFirst := ARange.StartPos.Line;
  ALast := ARange.EndPos.Line;
  // Markierung bis zum Zeilenanfang: Diese Zeile gehört nicht mehr dazu.
  if (ALast > AFirst) and (ARange.EndPos.Character = 0) then
  begin
    Dec(ALast);
  end;
  ALast := Min(ALast, AHigh);
  Result := (AFirst >= 0) and (AFirst <= ALast);
end;

/// <summary>Lassen sich beide Seiten der Zuweisung tauschen?</summary>
function IsSwappable(const ALine: TAssignmentLine; const AReadOnly: TReadOnlyCheck): Boolean;
begin
  Result := TAssignmentSwap.IsAssignable(ALine.Left) and TAssignmentSwap.IsAssignable(ALine.Right) and
    not (Assigned(AReadOnly) and AReadOnly(ALine.Right));
end;

type
  /// <summary>Die markierten Zeilen, zerlegt, mit der Ausrichtung der tauschbaren Zuweisungen.</summary>
  TSwapBlock = record
    Lines: TArray<string>;
    First: Integer;
    Parsed: TArray<TAssignmentLine>;
    IsAssignment, Swappable: TArray<Boolean>;
    /// <summary>Spalte von := aller tauschbaren Zeilen; -1 vor der ersten.</summary>
    Column: Integer;
    Width: Integer;
    MinGap: Integer;
    /// <summary>Stehen alle := der tauschbaren Zeilen in derselben Spalte?</summary>
    Aligned: Boolean;
    /// <summary>Zerlegt ACount Zeilen ab First; False, wenn keine tauschbar ist.</summary>
    function Analyze(ACount: Integer; const AReadOnly: TReadOnlyCheck): Boolean;
    procedure Measure(AIndex: Integer);
    /// <summary>Neuer Text der Zeile AIndex: getauscht oder als nicht umkehrbar markiert; False, wenn sie
    /// bleibt.</summary>
    function NewLine(AIndex: Integer; out AText: string): Boolean;
  end;

function TSwapBlock.Analyze(ACount: Integer; const AReadOnly: TReadOnlyCheck): Boolean;
var
  mIndex: Integer;
begin
  SetLength(Parsed, ACount);
  SetLength(IsAssignment, ACount);
  SetLength(Swappable, ACount);
  Column := -1;
  Aligned := True;
  MinGap := MaxInt;
  Width := 0;
  Result := False;
  for mIndex := 0 to ACount - 1 do
  begin
    IsAssignment[mIndex] := TAssignmentSwap.Parse(Lines[First + mIndex], Parsed[mIndex]);
    Swappable[mIndex] := IsAssignment[mIndex] and IsSwappable(Parsed[mIndex], AReadOnly);
    if Swappable[mIndex] then
    begin
      Measure(mIndex);
      Result := True;
    end;
  end;
end;

/// <summary>Merkt Spalte, kleinsten Abstand vor := und Breite der tauschbaren Zeile AIndex.</summary>
procedure TSwapBlock.Measure(AIndex: Integer);
var
  mColumn: Integer;
begin
  mColumn := Length(Parsed[AIndex].Indent + Parsed[AIndex].Left + Parsed[AIndex].GapBefore);
  if Column < 0 then
  begin
    Column := mColumn;
  end
  else if Column <> mColumn then
  begin
    Aligned := False;
  end;
  MinGap := Min(MinGap, Length(Parsed[AIndex].GapBefore));
  Width := Max(Width, Length(Parsed[AIndex].Indent + Parsed[AIndex].Right));
end;

function TSwapBlock.NewLine(AIndex: Integer; out AText: string): Boolean;
var
  mOld, mGap: string;
begin
  mOld := Lines[First + AIndex];
  AText := mOld;
  if Swappable[AIndex] then
  begin
    mGap := Parsed[AIndex].GapBefore;
    if Aligned then
    begin
      mGap := StringOfChar(' ', Width + MinGap - Length(Parsed[AIndex].Indent + Parsed[AIndex].Right));
    end;
    AText := Parsed[AIndex].Indent + Parsed[AIndex].Right + mGap + ':=' + Parsed[AIndex].GapAfter +
      Parsed[AIndex].Left + Parsed[AIndex].Semicolon + Parsed[AIndex].Tail;
  end
  else if IsAssignment[AIndex] and not ContainsText(Parsed[AIndex].Tail, TAssignmentSwap.Marker) then
  begin
    AText := Copy(mOld, 1, Length(mOld) - Length(Parsed[AIndex].Tail)) + MarkTail(Parsed[AIndex].Tail);
  end;
  Result := AText <> mOld;
end;

class function TAssignmentSwap.Swap(const AText: string; const ARange: TTextRange; const AReadOnly: TReadOnlyCheck;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mBlock: TSwapBlock;
  mLast, mIndex: Integer;
  mNewText: string;
begin
  AEdits := nil;
  mBlock.Lines := TTextLines.SplitLines(AText);
  Result := SelectedLines(ARange, High(mBlock.Lines), mBlock.First, mLast) and
    mBlock.Analyze(mLast - mBlock.First + 1, AReadOnly);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mBlock.Parsed) do
  begin
    if mBlock.NewLine(mIndex, mNewText) then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mBlock.First + mIndex, 0, mBlock.First + mIndex,
        Length(mBlock.Lines[mBlock.First + mIndex])), mNewText)];
    end;
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
  begin
    if Expression[Length(Expression)] = '^' then
    begin
      Expression := Copy(Expression, 1, Length(Expression) - 1);
    end
    else
    begin
      Expression := Copy(Expression, 1, LastDelimiter('[', Expression) - 1);
    end;
  end;
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
  begin
    if (Line >= 0) and (Line <= High(Lines)) then
    begin
      Result := Result + ' ' + Lines[Line];
    end;
  end;
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
    begin
      Exit(True);
    end;
    Start := PosEx(AWord, Lower, Start + 1);
  end;
  Result := False;
end;

/// <summary>Deklarationstext der Eigenschaft an ALocation; die Datei AFileName aus AText, andere von der Platte.
/// False, wenn die Datei fehlt, gesperrt ist oder sich nicht lesen lässt.</summary>
function PropertyDeclaration(const ALocation: TSymbolLocation; const AFileName, AText: string;
  out ADeclaration: string): Boolean;
var
  mText: string;
begin
  ADeclaration := '';
  Result := True;
  mText := AText;
  if not SameText(ALocation.FileName, AFileName) then
  begin
    try
      mText := TFileEncoding.LoadText(ALocation.FileName);
    except
      // Fehlt oder gesperrt (EFOpenError) bzw. Lesefehler.
      on EStreamError do
        Result := False;
      on EInOutError do
        Result := False;
    end;
  end;
  if Result then
  begin
    ADeclaration := RangeText(mText, ALocation.Symbol.Range);
  end;
end;

class function TAssignmentSwap.ReadOnlyByIndex(const AIndex: ISymbolIndex; const AFileName, AText,
  AExpression: string): Boolean;
var
  mLocation: TSymbolLocation;
  mDeclaration: string;
begin
  Result := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(LastName(AExpression)) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Property_) and
      PropertyDeclaration(mLocation, AFileName, AText, mDeclaration) then
    begin
      if HasWord(mDeclaration, 'write') then
      begin
        Exit(False);
      end;
      // "property X;" hebt nur die Sichtbarkeit an und sagt nichts über write.
      Result := Result or HasWord(mDeclaration, 'read');
    end;
  end;
end;

end.
