unit Atlas.Common.Editing.TextChanges;

// Gemeinsamer Baustein der Umbauten über mehrere Klassen (#664, #713, #675):
// Ein Umbau rechnet in Schritten (Änderungen anwenden, neu parsen, nächster
// Schritt) und vergleicht am Ende den neuen Text mit dem alten. Diff liefert
// daraus zeilenweise Änderungen für das WorkspaceEdit, damit die Vorschau nur
// die geänderten Blöcke zeigt und nicht die ganze Datei.

interface

uses
  Atlas.Common.Documents.Contract;

type
  TTextChanges = class
  public
    /// <summary>AEdits auf AText anwenden; die Bereiche dürfen sich nicht überlappen.</summary>
    class function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string; static;
    /// <summary>Zeilenweise Änderungen, die AOld in ANew überführen; leer, wenn beide gleich sind.</summary>
    class function Diff(const AOld, ANew: string): TArray<TTextEdit>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Diff;

class function TTextChanges.Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Sorted: TArray<TTextEdit>;
  Lines: TLineTable;
  Index, StartOffset, EndOffset: Integer;
begin
  Sorted := Copy(AEdits);
  // Von hinten nach vorn. TArray.Sort ist nicht stabil: Einfügungen an derselben Stelle gibt es deshalb nicht,
  // die Aufrufer fassen sie vorher zu einer Änderung zusammen.
  TArray.Sort<TTextEdit>(Sorted, TComparer<TTextEdit>.Construct(
    function(const A, B: TTextEdit): Integer
    begin
      if A.Range.StartPos.Line <> B.Range.StartPos.Line then
      begin
        Result := B.Range.StartPos.Line - A.Range.StartPos.Line;
      end
      else if A.Range.StartPos.Character <> B.Range.StartPos.Character then
      begin
        Result := B.Range.StartPos.Character - A.Range.StartPos.Character;
      end
      else if A.Range.EndPos.Line <> B.Range.EndPos.Line then
      begin
        Result := B.Range.EndPos.Line - A.Range.EndPos.Line;
      end
      else
      begin
        Result := B.Range.EndPos.Character - A.Range.EndPos.Character;
      end;
    end));
  Lines := TLineTable.Build(AText);
  Result := AText;
  for Index := 0 to High(Sorted) do
  begin
    StartOffset := Lines.OffsetAt(Sorted[Index].Range.StartPos);
    EndOffset := Lines.OffsetAt(Sorted[Index].Range.EndPos);
    Result := Copy(Result, 1, StartOffset) + Sorted[Index].NewText + Copy(Result, EndOffset + 1, MaxInt);
  end;
end;

class function TTextChanges.Diff(const AOld, ANew: string): TArray<TTextEdit>;
var
  OldLines, NewLines: TArray<string>;
  LineBreak, NewText: string;
  Hunk: TTextLineHunk;
  Line: Integer;
  StartPos, EndPos: TTextPosition;
begin
  Result := nil;
  if AOld = ANew then
  begin
    Exit;
  end;
  OldLines := TTextLines.SplitLines(AOld);
  NewLines := TTextLines.SplitLines(ANew, LineBreak);
  if not AOld.Contains(#10) and not AOld.Contains(#13) then
  begin
    LineBreak := TTextLines.LineBreakOf(ANew);
  end
  else
  begin
    LineBreak := TTextLines.LineBreakOf(AOld);
  end;
  for Hunk in TTextDiff.Hunks(OldLines, NewLines) do
  begin
    NewText := '';
    if Hunk.OldStart + Hunk.OldCount < Length(OldLines) then
    begin
      // Ganze Zeilen samt Umbruch ersetzen.
      StartPos := TTextPosition.Create(Hunk.OldStart, 0);
      EndPos := TTextPosition.Create(Hunk.OldStart + Hunk.OldCount, 0);
      for Line := Hunk.NewStart to Hunk.NewStart + Hunk.NewCount - 1 do
      begin
        NewText := NewText + NewLines[Line] + LineBreak;
      end;
    end
    else if Hunk.OldStart > 0 then
    begin
      // Block am Textende: ab dem Ende der Zeile davor ersetzen, damit kein Umbruch übrig bleibt oder fehlt.
      StartPos := TTextPosition.Create(Hunk.OldStart - 1, Length(OldLines[Hunk.OldStart - 1]));
      EndPos := TTextPosition.Create(High(OldLines), Length(OldLines[High(OldLines)]));
      for Line := Hunk.NewStart to Hunk.NewStart + Hunk.NewCount - 1 do
      begin
        NewText := NewText + LineBreak + NewLines[Line];
      end;
    end
    else
    begin
      // Der ganze Text.
      StartPos := TTextPosition.Create(0, 0);
      EndPos := TTextPosition.Create(High(OldLines), Length(OldLines[High(OldLines)]));
      NewText := ANew;
    end;
    Result := Result + [TTextEdit.Create(TTextRange.Create(StartPos, EndPos), NewText)];
  end;
end;

end.
