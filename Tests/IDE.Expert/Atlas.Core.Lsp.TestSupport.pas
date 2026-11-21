unit Atlas.Core.Lsp.TestSupport;

// Gemeinsame Hilfen der Tests rund um Antworten des Servers (Aufrufhierarchie, Fortschritt).

interface

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Progress;

/// <summary>Eintrag der Aufrufhierarchie AName in AFileName, Zeile ALine.</summary>
function Item(const AName, AFileName: string; ALine: Integer): TAtlasHierarchyItem;
/// <summary>Reicht die Fortschrittsmeldung AJson an AProgress.</summary>
procedure Send(const AProgress: ILspProgress; const AJson: string);

implementation

uses
  System.JSON;

function Item(const AName, AFileName: string; ALine: Integer): TAtlasHierarchyItem;
begin
  Result := Default(TAtlasHierarchyItem);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

procedure Send(const AProgress: ILspProgress; const AJson: string);
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    AProgress.Handle(mValue);
  finally
    mValue.Free;
  end;
end;

end.
