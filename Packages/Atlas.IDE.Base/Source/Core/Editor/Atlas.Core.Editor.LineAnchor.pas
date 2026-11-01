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
    ContextLines = 2;
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
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for Index := 0 to High(A) do
    if A[Index] <> B[Index] then
      Exit(False);
end;

function TAtlasLineAnchor.SameAs(const AOther: TAtlasLineAnchor): Boolean;
begin
  Result := (Line = AOther.Line) and (Text = AOther.Text) and SameTexts(Before, AOther.Before) and
    SameTexts(After, AOther.After);
end;

{ TAtlasLineAnchors }

class function TAtlasLineAnchors.Normalize(const AText: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
  Space: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Space := False;
    for Ch in AText do
      if (Ch = ' ') or (Ch = #9) then
        Space := True
      else
      begin
        if Space and (Builder.Length > 0) then
          Builder.Append(' ');
        Space := False;
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasLineAnchors.Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

class function TAtlasLineAnchors.Capture(const ALines: TArray<string>; ALine: Integer): TAtlasLineAnchor;
var
  Index: Integer;
begin
  Result := Default(TAtlasLineAnchor);
  Result.Line := ALine;
  if (ALine < 0) or (ALine > High(ALines)) then
    Exit;
  Result.Text := Normalize(ALines[ALine]);
  Index := ALine - 1;
  while (Index >= 0) and (Length(Result.Before) < ContextLines) do
  begin
    Result.Before := Result.Before + [Normalize(ALines[Index])];
    Dec(Index);
  end;
  Index := ALine + 1;
  while (Index <= High(ALines)) and (Length(Result.After) < ContextLines) do
  begin
    Result.After := Result.After + [Normalize(ALines[Index])];
    Inc(Index);
  end;
end;

/// <summary>Passende Nachbarzeilen um AIndex (ANorm normiert).</summary>
function ContextScore(const ANorm: TArray<string>; const AAnchor: TAtlasLineAnchor; AIndex: Integer): Integer;
var
  Step, Line: Integer;
begin
  Result := 0;
  for Step := 0 to High(AAnchor.Before) do
  begin
    Line := AIndex - 1 - Step;
    if (Line >= 0) and (ANorm[Line] = AAnchor.Before[Step]) then
      Inc(Result);
  end;
  for Step := 0 to High(AAnchor.After) do
  begin
    Line := AIndex + 1 + Step;
    if (Line <= High(ANorm)) and (ANorm[Line] = AAnchor.After[Step]) then
      Inc(Result);
  end;
end;

/// <summary>Mindestens eine gemerkte Nachbarzeile hat Inhalt.</summary>
function HasSolidContext(const AAnchor: TAtlasLineAnchor): Boolean;
var
  Text: string;
begin
  Result := False;
  for Text in AAnchor.Before do
    if Text <> '' then
      Exit(True);
  for Text in AAnchor.After do
    if Text <> '' then
      Exit(True);
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

class function TAtlasLineAnchors.Locate(const ALines: TArray<string>; const AAnchor: TAtlasLineAnchor;
  AFirst, ALast: Integer; out ALine: Integer): TAtlasLineMatch;
var
  Norm: TArray<string>;
  Index, Best, BestScore, Score, Count, Full: Integer;
begin
  ALine := AAnchor.Line;
  Result := TAtlasLineMatch.Orphaned;
  if AFirst < 0 then
    AFirst := 0;
  if ALast > High(ALines) then
    ALast := High(ALines);
  SetLength(Norm, Length(ALines));
  for Index := 0 to High(ALines) do
    Norm[Index] := Normalize(ALines[Index]);
  // 1. Gleicher Inhalt.
  Best := -1;
  BestScore := -1;
  Count := 0;
  for Index := AFirst to ALast do
  begin
    if Norm[Index] <> AAnchor.Text then
      Continue;
    Score := ContextScore(Norm, AAnchor, Index);
    // Eine leere Zeile gibt es oft; sie zählt nur mit passendem Nachbarn.
    if (AAnchor.Text = '') and (Score = 0) then
      Continue;
    Inc(Count);
    if (Score > BestScore) or ((Score = BestScore) and Closer(Index, Best, AAnchor.Line)) then
    begin
      Best := Index;
      BestScore := Score;
    end;
  end;
  // Mehrere gleiche Zeilen ohne passenden Nachbarn: nur die bisherige Stelle ist eindeutig.
  if (Best >= 0) and (Count > 1) and (BestScore = 0) and (Best <> AAnchor.Line) then
    Best := -1;
  if Best >= 0 then
  begin
    ALine := Best;
    if Best = AAnchor.Line then
      Result := TAtlasLineMatch.Same
    else
      Result := TAtlasLineMatch.Moved;
    Exit;
  end;
  // 2. Inhalt geändert: alle Nachbarn passen noch um eine Stelle.
  Full := Length(AAnchor.Before) + Length(AAnchor.After);
  if (Full = 0) or not HasSolidContext(AAnchor) then
    Exit;
  Best := -1;
  for Index := AFirst to ALast do
    if (ContextScore(Norm, AAnchor, Index) = Full) and Closer(Index, Best, AAnchor.Line) then
      Best := Index;
  if Best >= 0 then
  begin
    ALine := Best;
    Result := TAtlasLineMatch.Changed;
  end;
end;

end.
