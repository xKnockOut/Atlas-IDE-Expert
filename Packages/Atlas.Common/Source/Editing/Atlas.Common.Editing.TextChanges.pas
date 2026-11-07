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
  mSorted: TArray<TTextEdit>;
  mLines: TLineTable;
  mIndex, mStartOffset, mEndOffset: Integer;
begin
  mSorted := Copy(AEdits);
  // Von hinten nach vorn. TArray.Sort ist nicht stabil: Einfügungen an derselben Stelle gibt es deshalb nicht,
  // die Aufrufer fassen sie vorher zu einer Änderung zusammen.
  TArray.Sort<TTextEdit>(mSorted, TComparer<TTextEdit>.Construct(
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
  mLines := TLineTable.Build(AText);
  Result := AText;
  for mIndex := 0 to High(mSorted) do
  begin
    mStartOffset := mLines.OffsetAt(mSorted[mIndex].Range.StartPos);
    mEndOffset := mLines.OffsetAt(mSorted[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStartOffset) + mSorted[mIndex].NewText + Copy(Result, mEndOffset + 1, MaxInt);
  end;
end;

class function TTextChanges.Diff(const AOld, ANew: string): TArray<TTextEdit>;
var
  mOldLines, mNewLines: TArray<string>;
  mLineBreak, mNewText: string;
  mHunk: TTextLineHunk;
  mLine: Integer;
  mStartPos, mEndPos: TTextPosition;
begin
  Result := nil;
  if AOld = ANew then
  begin
    Exit;
  end;
  mOldLines := TTextLines.SplitLines(AOld);
  mNewLines := TTextLines.SplitLines(ANew, mLineBreak);
  if not AOld.Contains(#10) and not AOld.Contains(#13) then
  begin
    mLineBreak := TTextLines.LineBreakOf(ANew);
  end
  else
  begin
    mLineBreak := TTextLines.LineBreakOf(AOld);
  end;
  for mHunk in TTextDiff.Hunks(mOldLines, mNewLines) do
  begin
    mNewText := '';
    if mHunk.OldStart + mHunk.OldCount < Length(mOldLines) then
    begin
      // Ganze Zeilen samt Umbruch ersetzen.
      mStartPos := TTextPosition.Create(mHunk.OldStart, 0);
      mEndPos := TTextPosition.Create(mHunk.OldStart + mHunk.OldCount, 0);
      for mLine := mHunk.NewStart to mHunk.NewStart + mHunk.NewCount - 1 do
      begin
        mNewText := mNewText + mNewLines[mLine] + mLineBreak;
      end;
    end
    else if mHunk.OldStart > 0 then
    begin
      // Block am Textende: ab dem Ende der Zeile davor ersetzen, damit kein Umbruch übrig bleibt oder fehlt.
      mStartPos := TTextPosition.Create(mHunk.OldStart - 1, Length(mOldLines[mHunk.OldStart - 1]));
      mEndPos := TTextPosition.Create(High(mOldLines), Length(mOldLines[High(mOldLines)]));
      for mLine := mHunk.NewStart to mHunk.NewStart + mHunk.NewCount - 1 do
      begin
        mNewText := mNewText + mLineBreak + mNewLines[mLine];
      end;
    end
    else
    begin
      // Der ganze Text.
      mStartPos := TTextPosition.Create(0, 0);
      mEndPos := TTextPosition.Create(High(mOldLines), Length(mOldLines[High(mOldLines)]));
      mNewText := ANew;
    end;
    Result := Result + [TTextEdit.Create(TTextRange.Create(mStartPos, mEndPos), mNewText)];
  end;
end;

end.
