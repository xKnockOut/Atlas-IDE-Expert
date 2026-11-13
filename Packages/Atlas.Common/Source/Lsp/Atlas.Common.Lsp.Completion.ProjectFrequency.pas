unit Atlas.Common.Lsp.Completion.ProjectFrequency;

// Rangfolge aus der Verwendung im Projekt (#2109): Nach "X." bekommt jedes Mitglied die Zahl der Stellen, an denen
// sein Name in den Units des Projekts vorkommt (ISymbolIndex.UsageCount). Gezählt wird nach Namen, nicht nach
// (Typ, Mitglied): Innerhalb der Liste eines Typs ordnet die Zahl die Mitglieder nur untereinander. Den Zuschlag und
// die Marke „im Projekt n×“ setzt das Plugin.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionProjectFrequency = class
  public
    /// <summary>Setzt ProjectUses an den Einträgen AItems; nichts ohne Index oder ohne
    /// completion.projectFrequency.</summary>
    class procedure Apply(ARequest: TCompletionRequest; var AItems: TArray<TCompletionItem>); overload; static;
    /// <summary>Wie oben mit Index und Einstellung direkt (Tests).</summary>
    class procedure Apply(const AIndex: ISymbolIndex; AEnabled: Boolean; var AItems: TArray<TCompletionItem>);
      overload; static;
  end;

implementation

class procedure TCompletionProjectFrequency.Apply(ARequest: TCompletionRequest;
  var AItems: TArray<TCompletionItem>);
begin
  Apply(ARequest.Index, ARequest.Settings.ProjectFrequency, AItems);
end;

class procedure TCompletionProjectFrequency.Apply(const AIndex: ISymbolIndex; AEnabled: Boolean;
  var AItems: TArray<TCompletionItem>);
var
  mIndex: Integer;
begin
  if not AEnabled or (AIndex = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Name <> '' then
    begin
      AItems[mIndex].ProjectUses := AIndex.UsageCount(AItems[mIndex].Name);
    end;
  end;
end;

end.
