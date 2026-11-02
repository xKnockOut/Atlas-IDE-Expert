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
  Line, Character: Integer;
begin
  Result := ARange.TryGetValue<Integer>(AName + '.line', Line) and
    ARange.TryGetValue<Integer>(AName + '.character', Character);
  if Result then
    AOffset := TLspTextChanges.OffsetOf(ALines, TLspTextPosition.Create(Line, Character))
  else
    AOffset := 0;
end;

class function TAtlasServerPlaceholders.Expansion(const AValue: TJSONValue;
  const ADocument: string): TAtlasSnippetExpansion;
var
  Lines: TLineTable;
  Item: TJSONValue;
  Range: TJSONObject;
  Stop: TAtlasSnippetStop;
  StartOffset, EndOffset: Integer;
begin
  Result := Default(TAtlasSnippetExpansion);
  if not (AValue is TJSONArray) then
    Exit;
  Lines := TLineTable.Build(ADocument);
  for Item in TJSONArray(AValue) do
    if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<Integer>('number', Stop.Number) and
      (Stop.Number >= 0) and TJSONObject(Item).TryGetValue<TJSONObject>('range', Range) and
      ReadOffset(Lines, Range, 'start', StartOffset) and ReadOffset(Lines, Range, 'end', EndOffset) and
      (EndOffset >= StartOffset) then
    begin
      Stop.Start := StartOffset;
      Stop.Length := EndOffset - StartOffset;
      Result.Stops := Result.Stops + [Stop];
    end;
  // Bei gleichem Anfang zuerst die Nummer, damit die Reihenfolge feststeht.
  TArray.Sort<TAtlasSnippetStop>(Result.Stops, TComparer<TAtlasSnippetStop>.Construct(
    function(const A, B: TAtlasSnippetStop): Integer
    begin
      if A.Start <> B.Start then
        Result := A.Start - B.Start
      else
        Result := A.Number - B.Number;
    end));
end;

end.
