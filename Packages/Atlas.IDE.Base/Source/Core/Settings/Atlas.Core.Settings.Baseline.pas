unit Atlas.Core.Settings.Baseline;

// Abschnitt Baseline der Optionsseite (#227, #97, #147): Anzahl der Einträge
// in atlas-baseline.json und die Übersicht der Unterdrückungen je Regel aus
// der Ausgabe von AtlasServer.exe --suppression-stats --format json. Das
// Plugin ruft dafür den Server als Prozess auf und liest hier nur das Ergebnis.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TAtlasSuppressionRow = record
    Rule: string;
    Total: Integer;
    Unused: Integer;
    Files: Integer;
  end;

  TAtlasBaselineInfo = class
  public const
    FileName = 'atlas-baseline.json';
    LegacyFileName = 'delphi-lsp-baseline.json';
  public
    /// <summary>Treffer in der Baseline (Summe von "count", sonst 1 je Eintrag); AEntries: Einträge.
    /// -1 bei ungültigem Inhalt.</summary>
    class function Count(const AText: string; out AEntries: Integer): Integer; static;
    /// <summary>Zeilen aus {"suppressions": [{"rule", "total", "unused", "files"}]}; häufigste zuerst wie geliefert.
    /// </summary>
    class function Suppressions(const AJson: string): TArray<TAtlasSuppressionRow>; static;
  end;

implementation

{ TAtlasBaselineInfo }

class function TAtlasBaselineInfo.Count(const AText: string; out AEntries: Integer): Integer;
var
  Root, Findings, Item: TJSONValue;
begin
  AEntries := 0;
  Result := -1;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    Findings := TJSONObject(Root).GetValue('findings');
    if not (Findings is TJSONArray) then
      Exit;
    Result := 0;
    for Item in TJSONArray(Findings) do
    begin
      Inc(AEntries);
      if Item is TJSONObject then
        Inc(Result, TJSONObject(Item).GetValue<Integer>('count', 1))
      else
        Inc(Result);
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasBaselineInfo.Suppressions(const AJson: string): TArray<TAtlasSuppressionRow>;
var
  Root, Items, Item: TJSONValue;
  Row: TAtlasSuppressionRow;
begin
  Result := nil;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Items := TJSONObject(Root).GetValue('suppressions');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONObject then
        begin
          Row := Default(TAtlasSuppressionRow);
          Row.Rule := TJSONObject(Item).GetValue<string>('rule', '');
          Row.Total := TJSONObject(Item).GetValue<Integer>('total', 0);
          Row.Unused := TJSONObject(Item).GetValue<Integer>('unused', 0);
          Row.Files := TJSONObject(Item).GetValue<Integer>('files', 0);
          Result := Result + [Row];
        end;
  finally
    Root.Free;
  end;
end;

end.
