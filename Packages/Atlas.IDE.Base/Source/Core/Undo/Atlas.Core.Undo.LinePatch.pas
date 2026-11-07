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
    cMaxCells = TTextDiff.cMaxCells;
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

/// <summary>Überlappend oder direkt angrenzend; leere Blöcke (Einfügungen) an derselben Stelle auch.</summary>
function Touches(const AFirst, ASecond: TAtlasLineHunk): Boolean;
begin
  Result := Max(AFirst.OldStart, ASecond.OldStart) <=
    Min(AFirst.OldStart + AFirst.OldCount, ASecond.OldStart + ASecond.OldCount);
end;

function HasConflict(const AStep, ALater: TArray<TAtlasLineHunk>): Boolean;
var
  mA, mB: TAtlasLineHunk;
begin
  Result := False;
  for mA in AStep do
  begin
    for mB in ALater do
    begin
      Result := Result or Touches(mA, mB);
    end;
  end;
end;

type
  /// <summary>Eine Seite beim Zusammenführen: ihre Blöcke, ihre Zeilen und der nächste Block.</summary>
  TPatchSide = record
    Hunks: TArray<TAtlasLineHunk>;
    Lines: TArray<string>;
    Next: Integer;
    function HasMore: Boolean;
    /// <summary>Beginnt der nächste Block an ALine, hängt er seine Zeilen an und rückt ALine hinter sich.</summary>
    function TakeAt(var ALine: Integer; ABuilder: TStringBuilder): Boolean;
  end;

function TPatchSide.HasMore: Boolean;
begin
  Result := Next < Length(Hunks);
end;

function TPatchSide.TakeAt(var ALine: Integer; ABuilder: TStringBuilder): Boolean;
var
  mIndex: Integer;
begin
  Result := HasMore and (Hunks[Next].OldStart = ALine);
  if Result then
  begin
    for mIndex := Hunks[Next].NewStart to Hunks[Next].NewStart + Hunks[Next].NewCount - 1 do
    begin
      ABuilder.Append(Lines[mIndex]);
    end;
    Inc(ALine, Hunks[Next].OldCount);
    Inc(Next);
  end;
end;

function PatchSide(const AHunks: TArray<TAtlasLineHunk>; const ALines: TArray<string>): TPatchSide;
begin
  Result.Hunks := AHunks;
  Result.Lines := ALines;
  Result.Next := 0;
end;

/// <summary>Beide Blocklisten sind disjunkt: den Ausgangstext durchlaufen und je Block die passende Seite
/// einsetzen.</summary>
function Merged(const ASourceLines: TArray<string>; AStep, ALater: TPatchSide; ACapacity: Integer): string;
var
  mBuilder: TStringBuilder;
  mLine: Integer;
begin
  mBuilder := TStringBuilder.Create(ACapacity);
  try
    mLine := 0;
    while (mLine < Length(ASourceLines)) or AStep.HasMore or ALater.HasMore do
    begin
      if AStep.TakeAt(mLine, mBuilder) or ALater.TakeAt(mLine, mBuilder) then
      begin
        Continue;
      end;
      if mLine >= Length(ASourceLines) then
      begin
        Break;
      end;
      mBuilder.Append(ASourceLines[mLine]);
      Inc(mLine);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasLinePatch.Rebase(const ASource, ATarget, ACurrent: string; out AResult: string): Boolean;
var
  mSourceLines, mTargetLines, mCurrentLines: TArray<string>;
  mStep, mLater: TArray<TAtlasLineHunk>;
begin
  AResult := '';
  // Schon im Zielstand (z. B. von Hand genauso zurückgenommen) ist das Ergebnis ebenfalls der Zieltext.
  if (ACurrent = ASource) or (ACurrent = ATarget) then
  begin
    AResult := ATarget;
    Exit(True);
  end;
  mSourceLines := SplitLines(ASource);
  mTargetLines := SplitLines(ATarget);
  mCurrentLines := SplitLines(ACurrent);
  mStep := Hunks(mSourceLines, mTargetLines);
  mLater := Hunks(mSourceLines, mCurrentLines);
  Result := not HasConflict(mStep, mLater);
  if Result then
  begin
    AResult := Merged(mSourceLines, PatchSide(mStep, mTargetLines), PatchSide(mLater, mCurrentLines),
      Length(ACurrent));
  end;
end;

end.
