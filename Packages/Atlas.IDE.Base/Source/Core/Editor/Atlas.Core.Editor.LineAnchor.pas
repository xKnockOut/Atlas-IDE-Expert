unit Atlas.Core.Editor.LineAnchor;

// Verankerung an einer Codezeile, ohne VCL und Open Tools API; gemeinsam für
// persönliche Notizen (#545) und benannte Lesezeichen (#622). Ein Anker merkt
// sich nicht nur die Zeilennummer, sondern den Inhalt seiner Zeile und je
// zwei Nachbarzeilen davor und danach (ohne Leerraum am Rand, Leerraumfolgen
// zu einem Leerzeichen; Einrücken ändert also nichts). Locate sucht die Zeile
// im aktuellen Text wieder, auf Wunsch nur in einem Bereich (etwa dem Rumpf
// einer Methode, #622):
//   1. Gleicher Inhalt: die Stelle mit den meisten passenden Nachbarzeilen,
//      bei Gleichstand die nächste zur bisherigen Zeile. Same, wenn das die
//      bisherige Zeile ist, sonst Moved (z. B. Zeilen oberhalb eingefügt).
//      Gibt es den Inhalt mehrmals und passt bei keiner Stelle ein Nachbar,
//      gilt nur die bisherige Zeile; sonst ist die Stelle nicht eindeutig.
//      Eine leere Zeile braucht immer mindestens einen passenden Nachbarn.
//   2. Inhalt nirgends mehr: Die Zeile wurde geändert. Stehen alle gemerkten
//      Nachbarn (mindestens einer nicht leer) noch um eine Stelle herum, bleibt
//      der Anker dort (Changed) und der Aufrufer merkt sich den neuen Inhalt.
//   3. Sonst ist der Anker verwaist (Orphaned) und behält seine letzte Zeile.
// Eine gelöschte Zeile wird so verwaist: Ihre Nachbarn liegen danach direkt
// aneinander, an keiner Stelle passen beide Seiten.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis von TAtlasLineAnchors.Locate.</summary>
  TAtlasLineMatch = (
    /// <summary>Die Zeile steht noch an derselben Stelle.</summary>
    Same,
    /// <summary>Gleicher Inhalt an anderer Stelle (Zeilen davor eingefügt oder entfernt).</summary>
    Moved,
    /// <summary>Inhalt der Zeile geändert, die Nachbarzeilen stimmen: Der Anker bleibt dort.</summary>
    Changed,
    /// <summary>Nicht mehr zuordenbar („verwaist“).</summary>
    Orphaned);
{$SCOPEDENUMS OFF}

  /// <summary>Codezeile mit Umfeld; Texte normiert (TAtlasLineAnchors.Normalize).</summary>
  TAtlasLineAnchor = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>Inhalt der Zeile.</summary>
    Text: string;
    /// <summary>Zeilen davor, die nächste zuerst (Before[0] = Line - 1); höchstens ContextLines.</summary>
    Before: TArray<string>;
    /// <summary>Zeilen danach, die nächste zuerst (After[0] = Line + 1); höchstens ContextLines.</summary>
    After: TArray<string>;
    /// <summary>Gleiche Zeile, gleicher Inhalt, gleiches Umfeld.</summary>
    function SameAs(const AOther: TAtlasLineAnchor): Boolean;
  end;

  TAtlasLineAnchors = class
  public const
    /// <summary>Gemerkte Nachbarzeilen je Seite.</summary>
    cContextLines = 2;
  public
    /// <summary>Ohne Leerraum am Rand, Folgen von Leerzeichen und Tabs zu einem Leerzeichen.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>Zeilen eines Textes (CRLF, LF oder CR).</summary>
    class function Lines(const AText: string): TArray<string>; static;
    /// <summary>Anker der Zeile ALine (0-basiert); außerhalb des Textes ohne Inhalt und Umfeld.</summary>
    class function Capture(const ALines: TArray<string>; ALine: Integer): TAtlasLineAnchor; static;
    /// <summary>Sucht die Zeile von AAnchor in ALines (Ablauf oben). ALine ist die gefundene Zeile, bei
    /// Orphaned die bisherige.</summary>
    class function Locate(const ALines: TArray<string>; const AAnchor: TAtlasLineAnchor;
      out ALine: Integer): TAtlasLineMatch; overload; static;
    /// <summary>Wie oben, sucht aber nur Zeilen von AFirst bis ALast (0-basiert, auf den Text begrenzt); die
    /// Nachbarzeilen dürfen außerhalb liegen. Same heißt: gefunden an AAnchor.Line.</summary>
    class function Locate(const ALines: TArray<string>; const AAnchor: TAtlasLineAnchor; AFirst, ALast: Integer;
      out ALine: Integer): TAtlasLineMatch; overload; static;
  end;

implementation

{ TAtlasLineAnchor }

function SameTexts(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if A[mIndex] <> B[mIndex] then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasLineAnchor.SameAs(const AOther: TAtlasLineAnchor): Boolean;
begin
  Result := (Line = AOther.Line) and (Text = AOther.Text) and SameTexts(Before, AOther.Before) and
    SameTexts(After, AOther.After);
end;

{ TAtlasLineAnchors }

class function TAtlasLineAnchors.Normalize(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
  mSpace: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mSpace := False;
    for mCh in AText do
    begin
      if (mCh = ' ') or (mCh = #9) then
      begin
        mSpace := True;
      end
      else
      begin
        if mSpace and (mBuilder.Length > 0) then
        begin
          mBuilder.Append(' ');
        end;
        mSpace := False;
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasLineAnchors.Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

class function TAtlasLineAnchors.Capture(const ALines: TArray<string>; ALine: Integer): TAtlasLineAnchor;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasLineAnchor);
  Result.Line := ALine;
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit;
  end;
  Result.Text := Normalize(ALines[ALine]);
  mIndex := ALine - 1;
  while (mIndex >= 0) and (Length(Result.Before) < cContextLines) do
  begin
    Result.Before := Result.Before + [Normalize(ALines[mIndex])];
    Dec(mIndex);
  end;
  mIndex := ALine + 1;
  while (mIndex <= High(ALines)) and (Length(Result.After) < cContextLines) do
  begin
    Result.After := Result.After + [Normalize(ALines[mIndex])];
    Inc(mIndex);
  end;
end;

/// <summary>Passende Nachbarzeilen um AIndex (ANorm normiert).</summary>
function ContextScore(const ANorm: TArray<string>; const AAnchor: TAtlasLineAnchor; AIndex: Integer): Integer;
var
  mStep, mLine: Integer;
begin
  Result := 0;
  for mStep := 0 to High(AAnchor.Before) do
  begin
    mLine := AIndex - 1 - mStep;
    if (mLine >= 0) and (ANorm[mLine] = AAnchor.Before[mStep]) then
    begin
      Inc(Result);
    end;
  end;
  for mStep := 0 to High(AAnchor.After) do
  begin
    mLine := AIndex + 1 + mStep;
    if (mLine <= High(ANorm)) and (ANorm[mLine] = AAnchor.After[mStep]) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Mindestens eine gemerkte Nachbarzeile hat Inhalt.</summary>
function HasSolidContext(const AAnchor: TAtlasLineAnchor): Boolean;
var
  mText: string;
begin
  Result := False;
  for mText in AAnchor.Before do
  begin
    if mText <> '' then
    begin
      Exit(True);
    end;
  end;
  for mText in AAnchor.After do
  begin
    if mText <> '' then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Ist ACandidate näher an ATarget als ABest (ABest = -1: noch keiner)?</summary>
function Closer(ACandidate, ABest, ATarget: Integer): Boolean;
begin
  Result := (ABest < 0) or (Abs(ACandidate - ATarget) < Abs(ABest - ATarget));
end;

class function TAtlasLineAnchors.Locate(const ALines: TArray<string>; const AAnchor: TAtlasLineAnchor;
  out ALine: Integer): TAtlasLineMatch;
begin
  Result := Locate(ALines, AAnchor, 0, High(ALines), ALine);
end;

function NormalizedLines(const ALines: TArray<string>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ALines));
  for mIndex := 0 to High(ALines) do
  begin
    Result[mIndex] := TAtlasLineAnchors.Normalize(ALines[mIndex]);
  end;
end;

/// <summary>Zeile AIndex mit dem Inhalt des Ankers; AScore: passende Nachbarn. Eine leere Zeile gibt es oft; sie
/// zählt nur mit passendem Nachbarn.</summary>
function IsCandidate(const ANorm: TArray<string>; const AAnchor: TAtlasLineAnchor; AIndex: Integer;
  out AScore: Integer): Boolean;
begin
  AScore := 0;
  Result := ANorm[AIndex] = AAnchor.Text;
  if Result then
  begin
    AScore := ContextScore(ANorm, AAnchor, AIndex);
    Result := (AAnchor.Text <> '') or (AScore > 0);
  end;
end;

/// <summary>Zeile mit gleichem Inhalt und den meisten passenden Nachbarn (bei Gleichstand die nächste); -1 ohne.
/// Mehrere gleiche Zeilen ohne passenden Nachbarn: nur die bisherige Stelle ist eindeutig.</summary>
function SameContent(const ANorm: TArray<string>; const AAnchor: TAtlasLineAnchor; AFirst, ALast: Integer):
  Integer;
var
  mIndex, mScore, mBestScore, mCount: Integer;
begin
  Result := -1;
  mBestScore := -1;
  mCount := 0;
  for mIndex := AFirst to ALast do
  begin
    if IsCandidate(ANorm, AAnchor, mIndex, mScore) then
    begin
      Inc(mCount);
      if (mScore > mBestScore) or ((mScore = mBestScore) and Closer(mIndex, Result, AAnchor.Line)) then
      begin
        Result := mIndex;
        mBestScore := mScore;
      end;
    end;
  end;
  if (Result >= 0) and (mCount > 1) and (mBestScore = 0) and (Result <> AAnchor.Line) then
  begin
    Result := -1;
  end;
end;

/// <summary>Inhalt geändert: nächste Zeile, um die alle Nachbarn noch passen; -1 ohne.</summary>
function ChangedContent(const ANorm: TArray<string>; const AAnchor: TAtlasLineAnchor; AFirst, ALast: Integer):
  Integer;
var
  mIndex, mFull: Integer;
begin
  Result := -1;
  mFull := Length(AAnchor.Before) + Length(AAnchor.After);
  if (mFull > 0) and HasSolidContext(AAnchor) then
  begin
    for mIndex := AFirst to ALast do
    begin
      if (ContextScore(ANorm, AAnchor, mIndex) = mFull) and Closer(mIndex, Result, AAnchor.Line) then
      begin
        Result := mIndex;
      end;
    end;
  end;
end;

class function TAtlasLineAnchors.Locate(const ALines: TArray<string>; const AAnchor: TAtlasLineAnchor;
  AFirst, ALast: Integer; out ALine: Integer): TAtlasLineMatch;
var
  mNorm: TArray<string>;
  mFirst, mLast, mBest: Integer;
begin
  ALine := AAnchor.Line;
  mFirst := AFirst;
  if mFirst < 0 then
  begin
    mFirst := 0;
  end;
  mLast := ALast;
  if mLast > High(ALines) then
  begin
    mLast := High(ALines);
  end;
  mNorm := NormalizedLines(ALines);
  // 1. Gleicher Inhalt.
  mBest := SameContent(mNorm, AAnchor, mFirst, mLast);
  if mBest >= 0 then
  begin
    ALine := mBest;
    Result := TAtlasLineMatch.Moved;
    if mBest = AAnchor.Line then
    begin
      Result := TAtlasLineMatch.Same;
    end;
  end
  else
  begin
    // 2. Inhalt geändert: alle Nachbarn passen noch um eine Stelle.
    Result := TAtlasLineMatch.Orphaned;
    mBest := ChangedContent(mNorm, AAnchor, mFirst, mLast);
    if mBest >= 0 then
    begin
      ALine := mBest;
      Result := TAtlasLineMatch.Changed;
    end;
  end;
end;

end.
