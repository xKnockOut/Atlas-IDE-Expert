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
    cFileName = 'atlas-baseline.json';
    cLegacyFileName = 'delphi-lsp-baseline.json';
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
  mRoot, mFindings, mItem: TJSONValue;
begin
  AEntries := 0;
  Result := -1;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mFindings := TJSONObject(mRoot).GetValue('findings');
    if not (mFindings is TJSONArray) then
    begin
      Exit;
    end;
    Result := 0;
    for mItem in TJSONArray(mFindings) do
    begin
      Inc(AEntries);
      if mItem is TJSONObject then
      begin
        Inc(Result, TJSONObject(mItem).GetValue<Integer>('count', 1));
      end
      else
      begin
        Inc(Result);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBaselineInfo.Suppressions(const AJson: string): TArray<TAtlasSuppressionRow>;
var
  mRoot, mItems, mItem: TJSONValue;
  mRow: TAtlasSuppressionRow;
begin
  Result := nil;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mItems := TJSONObject(mRoot).GetValue('suppressions');
    if mItems is TJSONArray then
    begin
      for mItem in TJSONArray(mItems) do
      begin
        if mItem is TJSONObject then
        begin
          mRow := Default(TAtlasSuppressionRow);
          mRow.Rule := TJSONObject(mItem).GetValue<string>('rule', '');
          mRow.Total := TJSONObject(mItem).GetValue<Integer>('total', 0);
          mRow.Unused := TJSONObject(mItem).GetValue<Integer>('unused', 0);
          mRow.Files := TJSONObject(mItem).GetValue<Integer>('files', 0);
          Result := Result + [mRow];
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

end.
