unit Atlas.Core.Completion.ServerPlaceholders;

// Platzhalter, die der Server zu einer Änderung mitschickt (#674, „Überladung
// anlegen“): [{"number": n, "range": {...}}] mit Positionen im Text nach der
// Änderung. Daraus wird eine Vorlage für den Platzhalter-Modus (#51) mit
// leerem Text und Offsets ab dem Anfang des Dokuments; gleiche Nummern sind
// verknüpft, 0 ist die Endposition. Ohne Editor.

interface

uses
  System.JSON,
  Atlas.Core.Completion.Snippets;

type
  TAtlasServerPlaceholders = class
  public
    /// <summary>AValue: Liste der Platzhalter; ADocument: Text nach der Änderung. Für den Platzhalter-Modus mit
    /// Offset 0. Unlesbare Einträge entfallen; Stops in Textreihenfolge.</summary>
    class function Expansion(const AValue: TJSONValue; const ADocument: string): TAtlasSnippetExpansion; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Text.Lines;

function ReadOffset(const ALines: TLineTable; ARange: TJSONObject; const AName: string; out AOffset: Integer): Boolean;
var
  mLine, mCharacter: Integer;
begin
  Result := ARange.TryGetValue<Integer>(AName + '.line', mLine) and
    ARange.TryGetValue<Integer>(AName + '.character', mCharacter);
  if Result then
  begin
    AOffset := TLspTextChanges.OffsetOf(ALines, TLspTextPosition.Create(mLine, mCharacter));
  end
  else
  begin
    AOffset := 0;
  end;
end;

/// <summary>Platzhalter aus einem Eintrag {"number": n, "range": {...}}; False, wenn er unlesbar ist.</summary>
function StopOf(AItem: TJSONValue; const ALines: TLineTable; out AStop: TAtlasSnippetStop): Boolean;
var
  mRange: TJSONObject;
  mStart, mEnd: Integer;
begin
  AStop := Default(TAtlasSnippetStop);
  Result := (AItem is TJSONObject) and TJSONObject(AItem).TryGetValue<Integer>('number', AStop.Number) and
    (AStop.Number >= 0) and TJSONObject(AItem).TryGetValue<TJSONObject>('range', mRange);
  Result := Result and ReadOffset(ALines, mRange, 'start', mStart) and ReadOffset(ALines, mRange, 'end', mEnd) and
    (mEnd >= mStart);
  if Result then
  begin
    AStop.Start := mStart;
    AStop.Length := mEnd - mStart;
  end;
end;

class function TAtlasServerPlaceholders.Expansion(const AValue: TJSONValue;
  const ADocument: string): TAtlasSnippetExpansion;
var
  mLines: TLineTable;
  mItem: TJSONValue;
  mStop: TAtlasSnippetStop;
begin
  Result := Default(TAtlasSnippetExpansion);
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  mLines := TLineTable.Build(ADocument);
  for mItem in TJSONArray(AValue) do
  begin
    if StopOf(mItem, mLines, mStop) then
    begin
      Result.Stops := Result.Stops + [mStop];
    end;
  end;
  // Bei gleichem Anfang zuerst die Nummer, damit die Reihenfolge feststeht.
  TArray.Sort<TAtlasSnippetStop>(Result.Stops, TComparer<TAtlasSnippetStop>.Construct(
    function(const A, B: TAtlasSnippetStop): Integer
    begin
      if A.Start <> B.Start then
      begin
        Result := A.Start - B.Start;
      end
      else
      begin
        Result := A.Number - B.Number;
      end;
    end));
end;

end.
