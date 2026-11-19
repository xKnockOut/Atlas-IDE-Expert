unit Atlas.Common.Editing.BodySpacing;

// Einheitliche Leerzeilen um Methodenrümpfe (#1839), wenn Atlas Rümpfe anlegt
// oder ordnet (classCompletion.blankLines):
// - genau eine Leerzeile zwischen zwei Rümpfen und zwischen einem Rumpf und
//   dem, was davor oder dahinter steht (Typkommentar, initialization,
//   finalization, "end.", freie Routine);
// - neben einer Direktive ({$REGION …}, {$ENDREGION}, {$IFDEF …}) höchstens
//   eine; steht dort keine, bleibt es dabei (so legt Atlas einen Typkommentar
//   als Region an);
// - mehrere Leerzeilen werden zu einer zusammengefasst; Zeilen mit Inhalt,
//   Regionen, Direktiven und Leerzeilen innerhalb eines Rumpfs bleiben
//   unberührt.
// Angeglichen wird nur im betroffenen Bereich: an den Rändern einer Einfügung
// bzw. an den Grenzen der Rümpfe, die sich beim Ordnen verschoben haben. Der
// Rest der Unit bleibt, wie er ist; das ganze Umformatieren ist Sache des
// Formatierers.

interface

uses
  Atlas.Common.Documents.Contract;

type
  TBodySpacing = class
  public
    /// <summary>ALines mit angeglichenen Leerzeilen in den Lücken an den Grenzen der Rümpfe: Eine Lücke liegt
    /// zwischen zwei Zeilen mit Inhalt, von denen die obere einen Rumpf beendet (AEnds) oder die untere einen
    /// beginnt (AStarts), und berührt den Bereich AFirst bis ALast. ASources nennt je Ergebniszeile ihre Zeile in
    /// ALines (-1 = eingefügte Leerzeile).</summary>
    class function Spaced(const ALines: TArray<string>; const AStarts, AEnds: TArray<Boolean>; AFirst,
      ALast: Integer; out ASources: TArray<Integer>): TArray<string>; static;
    /// <summary>Einfügung AEdit in AText mit angeglichenen Leerzeilen an ihren Rändern; AEdit selbst, wenn dort
    /// schon alles passt oder die Einfügung mitten in einer Zeile mit Inhalt beginnt und endet.</summary>
    class function SpacedInsert(const AText: string; const AEdit: TTextEdit): TTextEdit; overload; static;
    /// <summary>Wie oben über die schon geteilten Zeilen ALines von AText (#1477: ohne den ganzen Text je
    /// Einfügung neu zu teilen).</summary>
    class function SpacedInsert(const ALines: TArray<string>; const ALineBreak: string;
      const AEdit: TTextEdit): TTextEdit; overload; static;
    /// <summary>Zeilen von ANew (AFirst bis ALast, ALast &lt; AFirst bei einer reinen Löschung), die sich von AOld
    /// unterscheiden, ohne den gleichen Anfang und das gleiche Ende; False, wenn beide gleich sind.</summary>
    class function ChangedRange(const AOld, ANew: TArray<string>; out AFirst, ALast: Integer): Boolean; static;
    /// <summary>Eine Änderung vom alten zum neuen Zeilenstand über die Zeilen, in denen sie sich unterscheiden;
    /// False, wenn beide gleich sind.</summary>
    class function LinesEdit(const AOld, ANew: TArray<string>; const ALineBreak: string;
      out AEdit: TTextEdit): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Editing.TextChanges;

function IsBlank(const ALine: string): Boolean;
begin
  Result := Trim(ALine) = '';
end;

function IsDirective(const ALine: string): Boolean;
begin
  Result := StartsStr('{$', TrimLeft(ALine));
end;

type
  /// <summary>Baut die Ergebniszeilen von TBodySpacing.Spaced auf.</summary>
  TSpacer = record
    Lines: TArray<string>;
    Starts, Ends: TArray<Boolean>;
    First, Last: Integer;
    Result: TArray<string>;
    Sources: TArray<Integer>;
    procedure Add(const ALine: string; ASource: Integer);
    /// <summary>Gehört die Lücke zwischen den Zeilen APrior und ANext (beide mit Inhalt) zu einem Rumpf im
    /// Bereich?</summary>
    function Managed(APrior, ANext: Integer): Boolean;
    /// <summary>Zahl der Leerzeilen, die zwischen APrior und ANext stehen sollen, wenn es jetzt ACount sind.
    /// </summary>
    function Target(APrior, ANext, ACount: Integer): Integer;
    /// <summary>Setzt die Lücke aus ACount Leerzeilen ab AStart vor die Zeile ANext.</summary>
    procedure Gap(AStart, ACount, ANext: Integer);
    procedure Run;
  end;

{ TSpacer }

procedure TSpacer.Add(const ALine: string; ASource: Integer);
begin
  Result := Result + [ALine];
  Sources := Sources + [ASource];
end;

function TSpacer.Managed(APrior, ANext: Integer): Boolean;
begin
  Result := (APrior >= 0) and (ANext <= High(Lines)) and (ANext >= First) and (APrior <= Last) and
    (Ends[APrior] or Starts[ANext]);
end;

function TSpacer.Target(APrior, ANext, ACount: Integer): Integer;
begin
  Result := 1;
  // Neben einer Direktive kommt keine Leerzeile dazu.
  if (ACount = 0) and (IsDirective(Lines[APrior]) or IsDirective(Lines[ANext])) then
  begin
    Result := 0;
  end;
end;

procedure TSpacer.Gap(AStart, ACount, ANext: Integer);
var
  mWanted, mIndex: Integer;
begin
  mWanted := ACount;
  if Managed(AStart - 1, ANext) then
  begin
    mWanted := Target(AStart - 1, ANext, ACount);
  end;
  for mIndex := 0 to mWanted - 1 do
  begin
    if mIndex < ACount then
    begin
      Add(Lines[AStart + mIndex], AStart + mIndex);
    end
    else
    begin
      Add('', -1);
    end;
  end;
end;

procedure TSpacer.Run;
var
  mLine, mNext: Integer;
begin
  Result := nil;
  Sources := nil;
  mLine := 0;
  while mLine <= High(Lines) do
  begin
    if not IsBlank(Lines[mLine]) then
    begin
      if (mLine > 0) and not IsBlank(Lines[mLine - 1]) then
      begin
        Gap(mLine, 0, mLine);
      end;
      Add(Lines[mLine], mLine);
      Inc(mLine);
      Continue;
    end;
    mNext := mLine;
    while (mNext <= High(Lines)) and IsBlank(Lines[mNext]) do
    begin
      Inc(mNext);
    end;
    Gap(mLine, mNext - mLine, mNext);
    mLine := mNext;
  end;
end;

{ TBodySpacing }

class function TBodySpacing.Spaced(const ALines: TArray<string>; const AStarts, AEnds: TArray<Boolean>; AFirst,
  ALast: Integer; out ASources: TArray<Integer>): TArray<string>;
var
  mSpacer: TSpacer;
begin
  mSpacer := Default(TSpacer);
  mSpacer.Lines := ALines;
  mSpacer.Starts := AStarts;
  mSpacer.Ends := AEnds;
  mSpacer.First := AFirst;
  mSpacer.Last := ALast;
  mSpacer.Run;
  ASources := mSpacer.Sources;
  Result := mSpacer.Result;
end;

/// <summary>Erste (AFromEnd False) bzw. letzte Zeile mit Inhalt in ALines; -1 ohne.</summary>
function ContentLine(const ALines: TArray<string>; AFromEnd: Boolean): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALines) do
  begin
    Result := mIndex;
    if AFromEnd then
    begin
      Result := High(ALines) - mIndex;
    end;
    if not IsBlank(ALines[Result]) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Zeilen um die Einfügung ab AFirst bis ALast (alter Stand): von der letzten Zeile mit Inhalt davor bis
/// zur ersten danach. Nur dort kann SpacedInsert etwas ändern; so bleibt jede Einfügung unabhängig von der
/// Länge der Unit (#1477).</summary>
procedure InsertWindow(const ALines: TArray<string>; AFirst, ALast: Integer; out AFrom, ATo: Integer);
begin
  AFrom := AFirst - 1;
  while (AFrom > 0) and IsBlank(ALines[AFrom]) do
  begin
    Dec(AFrom);
  end;
  if AFrom < 0 then
  begin
    AFrom := 0;
  end;
  ATo := ALast + 1;
  while (ATo < High(ALines)) and IsBlank(ALines[ATo]) do
  begin
    Inc(ATo);
  end;
  if ATo > High(ALines) then
  begin
    ATo := High(ALines);
  end;
end;

/// <summary>AEdit um ALines Zeilen verschoben.</summary>
function Shifted(const AEdit: TTextEdit; ALines: Integer): TTextEdit;
begin
  Result := AEdit;
  Result.Range.StartPos.Line := AEdit.Range.StartPos.Line + ALines;
  Result.Range.EndPos.Line := AEdit.Range.EndPos.Line + ALines;
end;

/// <summary>SpacedInsert über die Zeilen AOld; AEdit liegt in ihnen, das Ergebnis ebenso.</summary>
function SpacedInsertInLines(const AOld: TArray<string>; const ALineBreak: string; const AEdit: TTextEdit;
  out AResult: TTextEdit): Boolean;
var
  mNew, mInserted, mSpaced: TArray<string>;
  mStarts, mEnds: TArray<Boolean>;
  mSources: TArray<Integer>;
  mFirst, mLast, mStart: Integer;
  mBefore, mAfter: string;
begin
  Result := False;
  mStart := AEdit.Range.StartPos.Line;
  mInserted := TTextLines.SplitLines(AEdit.NewText);
  mFirst := ContentLine(mInserted, False);
  mLast := ContentLine(mInserted, True);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mNew := TTextLines.SplitLines(TTextChanges.Apply(TTextLines.JoinLines(AOld, ALineBreak), [AEdit]));
  SetLength(mStarts, Length(mNew));
  SetLength(mEnds, Length(mNew));
  // Teilt die erste bzw. letzte eingefügte Zeile die Zeile mit vorhandenem Code, bleibt dieser Rand, wie er ist.
  mBefore := Copy(AOld[mStart], 1, AEdit.Range.StartPos.Character);
  mAfter := Copy(AOld[AEdit.Range.EndPos.Line], AEdit.Range.EndPos.Character + 1, MaxInt);
  mStarts[mStart + mFirst] := (mFirst > 0) or IsBlank(mBefore);
  mEnds[mStart + mLast] := (mLast < High(mInserted)) or IsBlank(mAfter);
  mSpaced := TBodySpacing.Spaced(mNew, mStarts, mEnds, mStart + mFirst, mStart + mLast, mSources);
  Result := (Length(mSpaced) <> Length(mNew)) or (string.Join(#10, mSpaced) <> string.Join(#10, mNew));
  if Result then
  begin
    TBodySpacing.LinesEdit(AOld, mSpaced, ALineBreak, AResult);
  end;
end;

class function TBodySpacing.SpacedInsert(const AText: string; const AEdit: TTextEdit): TTextEdit;
begin
  Result := SpacedInsert(TTextLines.SplitLines(AText), TTextLines.LineBreakOf(AText), AEdit);
end;

class function TBodySpacing.SpacedInsert(const ALines: TArray<string>; const ALineBreak: string;
  const AEdit: TTextEdit): TTextEdit;
var
  mFrom, mTo: Integer;
  mWindowEdit: TTextEdit;
begin
  Result := AEdit;
  if (AEdit.Range.StartPos.Line < 0) or (AEdit.Range.EndPos.Line > High(ALines)) then
  begin
    Exit;
  end;
  InsertWindow(ALines, AEdit.Range.StartPos.Line, AEdit.Range.EndPos.Line, mFrom, mTo);
  if SpacedInsertInLines(Copy(ALines, mFrom, mTo - mFrom + 1), ALineBreak, Shifted(AEdit, -mFrom),
    mWindowEdit) then
  begin
    Result := Shifted(mWindowEdit, mFrom);
  end;
end;

class function TBodySpacing.ChangedRange(const AOld, ANew: TArray<string>; out AFirst, ALast: Integer): Boolean;
var
  mSuffix: Integer;
begin
  AFirst := 0;
  while (AFirst < Length(AOld)) and (AFirst < Length(ANew)) and (AOld[AFirst] = ANew[AFirst]) do
  begin
    Inc(AFirst);
  end;
  mSuffix := 0;
  while (mSuffix < Length(AOld) - AFirst) and (mSuffix < Length(ANew) - AFirst) and
    (AOld[High(AOld) - mSuffix] = ANew[High(ANew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  ALast := High(ANew) - mSuffix;
  Result := (AFirst < Length(AOld)) or (AFirst < Length(ANew));
end;

class function TBodySpacing.LinesEdit(const AOld, ANew: TArray<string>; const ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mFirst, mLast, mIndex: Integer;
  mText: string;
begin
  AEdit := Default(TTextEdit);
  Result := ChangedRange(AOld, ANew, mFirst, mLast);
  if not Result then
  begin
    Exit;
  end;
  if mLast < High(ANew) then
  begin
    mText := '';
    for mIndex := mFirst to mLast do
    begin
      mText := mText + ANew[mIndex] + ALineBreak;
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(mFirst, 0, Length(AOld) - (High(ANew) - mLast), 0), mText);
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(0, 0, High(AOld), Length(AOld[High(AOld)])),
      TTextLines.JoinLines(ANew, ALineBreak));
  end;
end;

end.
