unit Atlas.Core.Editor.Metrics.TestSupport;

// Gemeinsame Hilfen der Tests der Metriken im Editor (Kennzahlen, Linse).

interface

uses
  Atlas.Core.Editor.Metrics;

/// <summary>Metriken einer Datei aus der Antwort AJson.</summary>
function Parse(const AJson: string): TAtlasFileMetrics;

implementation

uses
  System.JSON;

function Parse(const AJson: string): TAtlasFileMetrics;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasFileMetrics.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

end.
