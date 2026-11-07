unit Atlas.Core.Editor.Selection;

// Auswahl erweitern und verkleinern (#399), Teil ohne Open Tools API. Der
// Server liefert zu einer Position die Kette der umgebenden Bereiche
// (textDocument/selectionRange, innen zuerst: Bezeichner, Ausdruck,
// Anweisung, Block, Routine, … Datei).
// - Erweitern wählt den kleinsten Bereich, der die Auswahl echt enthält.
// - Verkleinern wählt den größten Bereich, der echt in der Auswahl liegt;
//   gibt es keinen, bleibt eine leere Auswahl an ihrem Anfang.
// Die Kette wird am Anker geholt (der Cursor beim ersten Erweitern), solange
// die Auswahl ihn enthält; so führt Verkleinern zum Ausgangspunkt zurück.
// Markierung suchen (F3 bzw. Umschalt+F3 mit einzeiliger Markierung): nächstes
// bzw. vorheriges Vorkommen ohne Beachtung der Groß-/Kleinschreibung, am
// Dateiende bzw. -anfang geht es von der anderen Seite weiter.

interface

uses
  Atlas.Core.Lsp.TextChanges;

type
  TAtlasSelectionSteps = class
  public
    /// <summary>Nächstgrößerer Bereich der Kette um ACurrent; False, wenn keiner mehr kommt.</summary>
    class function Expand(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
      out ANext: TLspRange): Boolean; static;
    /// <summary>Nächstkleinerer Bereich in ACurrent; False bei leerer Auswahl.</summary>
    class function Shrink(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
      out ANext: TLspRange): Boolean; static;
    /// <summary>Wo die Kette geholt wird: am Anker, solange ACurrent ihn enthält, sonst am Anfang der
    /// Auswahl.</summary>
    class function ChainPosition(const ACurrent: TLspRange; AHasAnchor: Boolean;
      const AAnchor: TLspTextPosition): TLspTextPosition; static;
  end;

  TAtlasSelectionSearch = class
  public
    /// <summary>Nächstes (ABackward: vorheriges) Vorkommen von ANeedle ab AFrom, ohne Groß-/Kleinschreibung,
    /// über das Dateiende hinweg; vorwärts ab AFrom, rückwärts endend vor AFrom. False ohne Treffer.</summary>
    class function Find(const ALines: TArray<string>; const ANeedle: string; const AFrom: TLspTextPosition;
      ABackward: Boolean; out AFound: TLspRange): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

/// <summary>Zeile des Schritts AStep ab ALine, vorwärts oder rückwärts im Kreis über ACount Zeilen.</summary>
function RowOfStep(ALine, AStep, ACount: Integer; ABackward: Boolean): Integer;
begin
  if ABackward then
  begin
    Result := ((ALine - AStep) mod ACount + ACount) mod ACount;
  end
  else
  begin
    Result := (ALine + AStep) mod ACount;
  end;
end;

/// <summary>Letztes Vorkommen von ANeedle in ALine, das bis ALimit endet (1-basiert); 0 ohne.</summary>
function LastIndexBefore(const ANeedle, ALine: string; ALimit: Integer): Integer;
var
  mLast: Integer;
begin
  Result := 0;
  mLast := Pos(ANeedle, ALine);
  while (mLast > 0) and (mLast - 1 + Length(ANeedle) <= ALimit) do
  begin
    Result := mLast;
    mLast := PosEx(ANeedle, ALine, mLast + 1);
  end;
end;

/// <summary>Treffer in ALine (großgeschrieben) für Schritt AStep; in der Ausgangszeile (AStep = 0) ab bzw. vor
/// ACharacter. 1-basiert, 0 ohne.</summary>
function IndexInLine(const ANeedle, ALine: string; AStep, ACharacter: Integer; ABackward: Boolean): Integer;
begin
  if ABackward and (AStep = 0) then
  begin
    // Letztes Vorkommen, das vor AFrom endet.
    Result := LastIndexBefore(ANeedle, ALine, ACharacter);
  end
  else if ABackward then
  begin
    Result := LastIndexBefore(ANeedle, ALine, Length(ALine));
  end
  else if AStep = 0 then
  begin
    Result := PosEx(ANeedle, ALine, ACharacter + 1);
  end
  else
  begin
    Result := Pos(ANeedle, ALine);
  end;
end;

class function TAtlasSelectionSearch.Find(const ALines: TArray<string>; const ANeedle: string;
  const AFrom: TLspTextPosition; ABackward: Boolean; out AFound: TLspRange): Boolean;
var
  mNeedle: string;
  mCount, mStep, mRow, mIndex: Integer;
begin
  Result := False;
  AFound := TLspRange.Create(AFrom.Line, AFrom.Character, AFrom.Line, AFrom.Character);
  mCount := Length(ALines);
  mNeedle := AnsiUpperCase(ANeedle);
  mStep := 0;
  // Einmal um die Datei; die Ausgangszeile kommt am Ende noch einmal ganz dran.
  while (ANeedle <> '') and not Result and (mStep <= mCount) and (mCount > 0) do
  begin
    mRow := RowOfStep(AFrom.Line, mStep, mCount, ABackward);
    mIndex := IndexInLine(mNeedle, AnsiUpperCase(ALines[mRow]), mStep, AFrom.Character, ABackward);
    if mIndex > 0 then
    begin
      AFound := TLspRange.Create(mRow, mIndex - 1, mRow, mIndex - 1 + Length(ANeedle));
      Result := True;
    end;
    Inc(mStep);
  end;
end;

class function TAtlasSelectionSteps.Expand(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
  out ANext: TLspRange): Boolean;
var
  mRange: TLspRange;
begin
  for mRange in AChain do
  begin
    if mRange.Contains(ACurrent) and not mRange.Same(ACurrent) then
    begin
      ANext := mRange;
      Exit(True);
    end;
  end;
  ANext := ACurrent;
  Result := False;
end;

class function TAtlasSelectionSteps.Shrink(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
  out ANext: TLspRange): Boolean;
var
  mIndex: Integer;
begin
  ANext := ACurrent;
  if ACurrent.IsEmpty then
  begin
    Exit(False);
  end;
  // Von außen nach innen: der erste Bereich, der echt in der Auswahl liegt.
  for mIndex := High(AChain) downto 0 do
  begin
    if ACurrent.Contains(AChain[mIndex]) and not AChain[mIndex].Same(ACurrent) and not AChain[mIndex].IsEmpty then
    begin
      ANext := AChain[mIndex];
      Exit(True);
    end;
  end;
  ANext.EndPos := ACurrent.StartPos;
  Result := True;
end;

class function TAtlasSelectionSteps.ChainPosition(const ACurrent: TLspRange; AHasAnchor: Boolean;
  const AAnchor: TLspTextPosition): TLspTextPosition;
var
  mAnchor: TLspRange;
begin
  Result := ACurrent.StartPos;
  if not AHasAnchor then
  begin
    Exit;
  end;
  mAnchor.StartPos := AAnchor;
  mAnchor.EndPos := AAnchor;
  if ACurrent.Contains(mAnchor) then
  begin
    Result := AAnchor;
  end;
end;

end.
