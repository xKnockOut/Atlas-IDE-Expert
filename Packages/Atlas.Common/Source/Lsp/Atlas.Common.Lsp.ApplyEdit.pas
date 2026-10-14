unit Atlas.Common.Lsp.ApplyEdit;

// workspace/applyEdit an den Client (#397): Änderungen des Servers an Dateien
// (etwa die .dproj bei /define) gehen in die Puffer der IDE statt auf die
// Platte, sonst überschreibt die IDE sie beim nächsten Speichern. Hier stehen
// Fähigkeitsprüfung, Aufbau der Anfrage und Lesen der Antwort ohne Transport.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TLspApplyEdit = class
  public const
    Method = 'workspace/applyEdit';
  public
    /// <summary>Kündigt der Client in initialize capabilities.workspace.applyEdit an?</summary>
    class function ClientSupports(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>WorkspaceEdit, das den ganzen Text AOldText der Datei AFileName durch ANewText ersetzt.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function ReplaceAll(const AFileName, AOldText, ANewText: string): TJSONObject; static;
    /// <summary>Vollständige Anfrage mit id AId; übernimmt AEdit. Der Aufrufer übernimmt das Ergebnis.</summary>
    class function Request(const AId, ALabel: string; AEdit: TJSONObject): TJSONObject; static;
    /// <summary>Antwort des Clients: True bei applied; sonst AReason (failureReason bzw. Fehlermeldung).</summary>
    class function ReadResult(const AResponse: TJSONObject; out AReason: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions;

class function TLspApplyEdit.ClientSupports(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.applyEdit', Value) and Value;
end;

class function TLspApplyEdit.ReplaceAll(const AFileName, AOldText, ANewText: string): TJSONObject;
var
  Lines: TArray<string>;
  Last: string;
  Edit: TJSONObject;
  Edits: TJSONArray;
  Changes: TJSONObject;
begin
  // Ende des alten Texts: letzte Zeile, Länge in UTF-16-Einheiten wie im LSP üblich.
  Lines := AOldText.Split([#10]);
  if Length(Lines) = 0 then
    Lines := [''];
  Last := Lines[High(Lines)];
  Edit := TJSONObject.Create;
  Edit.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(0, 0, High(Lines), Length(Last))));
  Edit.AddPair('newText', ANewText);
  Edits := TJSONArray.Create;
  Edits.AddElement(Edit);
  Changes := TJSONObject.Create;
  Changes.AddPair(TDocumentUris.FromPath(AFileName), Edits);
  Result := TJSONObject.Create;
  Result.AddPair('changes', Changes);
end;

class function TLspApplyEdit.Request(const AId, ALabel: string; AEdit: TJSONObject): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  if ALabel <> '' then
    Params.AddPair('label', ALabel);
  Params.AddPair('edit', AEdit);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', AId);
  Result.AddPair('method', Method);
  Result.AddPair('params', Params);
end;

class function TLspApplyEdit.ReadResult(const AResponse: TJSONObject; out AReason: string): Boolean;
var
  Applied: Boolean;
begin
  AReason := '';
  Result := False;
  if AResponse = nil then
  begin
    AReason := 'keine Antwort';
    Exit;
  end;
  if AResponse.GetValue('error') <> nil then
  begin
    if not AResponse.TryGetValue<string>('error.message', AReason) then
      AReason := 'Fehler';
    Exit;
  end;
  Result := AResponse.TryGetValue<Boolean>('result.applied', Applied) and Applied;
  if not Result and not AResponse.TryGetValue<string>('result.failureReason', AReason) then
    AReason := 'nicht übernommen';
end;

end.
