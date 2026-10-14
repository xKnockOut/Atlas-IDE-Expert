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

implementation

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
