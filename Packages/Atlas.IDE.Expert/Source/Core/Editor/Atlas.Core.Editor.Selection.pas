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
    /// <summary>Wo die Kette geholt wird: am Anker, solange ACurrent ihn enthält, sonst am Anfang der Auswahl.</summary>
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

class function TAtlasSelectionSearch.Find(const ALines: TArray<string>; const ANeedle: string;
  const AFrom: TLspTextPosition; ABackward: Boolean; out AFound: TLspRange): Boolean;
var
  Needle, Line: string;
  Count, Step, Row, Index, Last, Limit: Integer;
begin
  Result := False;
  AFound := TLspRange.Create(AFrom.Line, AFrom.Character, AFrom.Line, AFrom.Character);
  Count := Length(ALines);
  if (ANeedle = '') or (Count = 0) then
    Exit;
  Needle := AnsiUpperCase(ANeedle);
  // Einmal um die Datei; die Ausgangszeile kommt am Ende noch einmal ganz dran.
  for Step := 0 to Count do
  begin
    if ABackward then
      Row := ((AFrom.Line - Step) mod Count + Count) mod Count
    else
      Row := (AFrom.Line + Step) mod Count;
    Line := AnsiUpperCase(ALines[Row]);
    if not ABackward then
    begin
      if Step = 0 then
        Index := PosEx(Needle, Line, AFrom.Character + 1)
      else
        Index := Pos(Needle, Line);
    end
    else
    begin
      // Letztes Vorkommen, das vor AFrom endet (in der Ausgangszeile) bzw. irgendwo in der Zeile.
      Limit := Length(Line);
      if Step = 0 then
        Limit := AFrom.Character;
      Index := 0;
      Last := Pos(Needle, Line);
      while (Last > 0) and (Last - 1 + Length(Needle) <= Limit) do
      begin
        Index := Last;
        Last := PosEx(Needle, Line, Last + 1);
      end;
    end;
    if Index > 0 then
    begin
      AFound := TLspRange.Create(Row, Index - 1, Row, Index - 1 + Length(ANeedle));
      Exit(True);
    end;
  end;
end;

class function TAtlasSelectionSteps.Expand(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
  out ANext: TLspRange): Boolean;
var
  Range: TLspRange;
begin
  for Range in AChain do
    if Range.Contains(ACurrent) and not Range.Same(ACurrent) then
    begin
      ANext := Range;
      Exit(True);
    end;
  ANext := ACurrent;
  Result := False;
end;

class function TAtlasSelectionSteps.Shrink(const AChain: TArray<TLspRange>; const ACurrent: TLspRange;
  out ANext: TLspRange): Boolean;
var
  Index: Integer;
begin
  ANext := ACurrent;
  if ACurrent.IsEmpty then
    Exit(False);
  // Von außen nach innen: der erste Bereich, der echt in der Auswahl liegt.
  for Index := High(AChain) downto 0 do
    if ACurrent.Contains(AChain[Index]) and not AChain[Index].Same(ACurrent) and not AChain[Index].IsEmpty then
    begin
      ANext := AChain[Index];
      Exit(True);
    end;
  ANext.EndPos := ACurrent.StartPos;
  Result := True;
end;

class function TAtlasSelectionSteps.ChainPosition(const ACurrent: TLspRange; AHasAnchor: Boolean;
  const AAnchor: TLspTextPosition): TLspTextPosition;
var
  Anchor: TLspRange;
begin
  Result := ACurrent.StartPos;
  if not AHasAnchor then
    Exit;
  Anchor.StartPos := AAnchor;
  Anchor.EndPos := AAnchor;
  if ACurrent.Contains(Anchor) then
    Result := AAnchor;
end;

end.
