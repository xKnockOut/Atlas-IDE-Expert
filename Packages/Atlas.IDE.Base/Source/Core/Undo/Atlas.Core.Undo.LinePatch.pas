unit Atlas.Core.Undo.LinePatch;

// Stellen eines Änderungsschritts auf einen später geänderten Text übertragen
// (#721): Zurücknehmen heißt, den Schritt „nachher → vorher“ auf den
// aktuellen Text anzuwenden, Wiederherstellen den Schritt „vorher → nachher“.
// Ist der aktuelle Text noch genau der Ausgangstext, ist das Ergebnis der
// Zieltext. Sonst werden die geänderten Zeilenblöcke beider Seiten verglichen
// (Dreiwegevergleich über den Ausgangstext): Berühren sich ein Block des
// Schritts und ein Block, den jemand danach geändert hat (auch direkt
// angrenzend), ist das ein Konflikt und nichts wird übertragen. Nie wird so
// Benutzerarbeit überschrieben.
// Zeilen behalten ihr Zeilenende (CRLF, LF, CR), damit gemischte Zeilenenden
// und eine fehlende letzte Zeilenschaltung erhalten bleiben. Verglichen wird
// nach gleichem Anfang und Ende mit der längsten gemeinsamen Teilfolge; ist der
// Rest zu groß dafür, gilt er als ein Block. Zerlegen und Vergleichen kommen
// aus Atlas.Text (ADR 0012).

interface

uses
  System.SysUtils,
  Atlas.Text.Diff;

type
  /// <summary>Geänderter Zeilenblock: im alten Text ab OldStart OldCount Zeilen, im neuen ab NewStart
  /// NewCount Zeilen (0-basiert).</summary>
  TAtlasLineHunk = TTextLineHunk;

  TAtlasLinePatch = class
  public const
    /// <summary>Größte Fläche (Zeilen alt × neu) für den genauen Vergleich der Mitte.</summary>
    MaxCells = TTextDiff.MaxCells;
  public
    /// <summary>Zeilen samt Zeilenende; die letzte ohne, wenn der Text nicht mit einem endet.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
    /// <summary>Geänderte Blöcke von AOld nach ANew, aufsteigend.</summary>
    class function Hunks(const AOld, ANew: TArray<string>): TArray<TAtlasLineHunk>; static;
    /// <summary>Überträgt den Schritt ASource → ATarget auf ACurrent (ein späterer Stand von ASource).
    /// False bei einem Konflikt; AResult ist dann leer.</summary>
    class function Rebase(const ASource, ATarget, ACurrent: string; out AResult: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Lines;

class function TAtlasLinePatch.SplitLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitKeepingBreaks(AText);
end;

class function TAtlasLinePatch.Hunks(const AOld, ANew: TArray<string>): TArray<TAtlasLineHunk>;
begin
  Result := TTextDiff.Hunks(AOld, ANew);
end;

class function TAtlasLinePatch.Rebase(const ASource, ATarget, ACurrent: string; out AResult: string): Boolean;
var
  SourceLines, TargetLines, CurrentLines: TArray<string>;
  Step, Later: TArray<TAtlasLineHunk>;
  A, B: TAtlasLineHunk;
  StepIndex, LaterIndex, Line, Index: Integer;
  Builder: TStringBuilder;

  function Touches(const AFirst, ASecond: TAtlasLineHunk): Boolean;
  begin
    // Überlappend oder direkt angrenzend; leere Blöcke (Einfügungen) an derselben Stelle auch.
    Result := Max(AFirst.OldStart, ASecond.OldStart) <=
      Min(AFirst.OldStart + AFirst.OldCount, ASecond.OldStart + ASecond.OldCount);
  end;

begin
  AResult := '';
  if ACurrent = ASource then
  begin
    AResult := ATarget;
    Exit(True);
  end;
  if ACurrent = ATarget then
  begin
    // Schon im Zielstand (z. B. von Hand genauso zurückgenommen).
    AResult := ATarget;
    Exit(True);
  end;
  SourceLines := SplitLines(ASource);
  TargetLines := SplitLines(ATarget);
  CurrentLines := SplitLines(ACurrent);
  Step := Hunks(SourceLines, TargetLines);
  Later := Hunks(SourceLines, CurrentLines);
  for A in Step do
    for B in Later do
      if Touches(A, B) then
        Exit(False);
  // Beide Blocklisten sind disjunkt: den Ausgangstext durchlaufen und je Block die passende Seite einsetzen.
  Builder := TStringBuilder.Create(Length(ACurrent));
  try
    StepIndex := 0;
    LaterIndex := 0;
    Line := 0;
    while (Line < Length(SourceLines)) or (StepIndex < Length(Step)) or (LaterIndex < Length(Later)) do
    begin
      if (StepIndex < Length(Step)) and (Step[StepIndex].OldStart = Line) then
      begin
        A := Step[StepIndex];
        for Index := A.NewStart to A.NewStart + A.NewCount - 1 do
          Builder.Append(TargetLines[Index]);
        Inc(Line, A.OldCount);
        Inc(StepIndex);
        Continue;
      end;
      if (LaterIndex < Length(Later)) and (Later[LaterIndex].OldStart = Line) then
      begin
        B := Later[LaterIndex];
        for Index := B.NewStart to B.NewStart + B.NewCount - 1 do
          Builder.Append(CurrentLines[Index]);
        Inc(Line, B.OldCount);
        Inc(LaterIndex);
        Continue;
      end;
      if Line >= Length(SourceLines) then
        Break;
      Builder.Append(SourceLines[Line]);
      Inc(Line);
    end;
    AResult := Builder.ToString;
  finally
    Builder.Free;
  end;
  Result := True;
end;

end.
