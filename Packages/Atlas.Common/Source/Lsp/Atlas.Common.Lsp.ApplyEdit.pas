unit Atlas.Common.Lsp.ApplyEdit;

// workspace/applyEdit an den Client (#397): Änderungen des Servers an Dateien
// (etwa die .dproj bei /define) gehen in die Puffer der IDE statt auf die
// Platte, sonst überschreibt die IDE sie beim nächsten Speichern. Hier stehen
// Fähigkeitsprüfung, Aufbau der Anfrage und Lesen der Antwort ohne Transport.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  /// <summary>Eine Datei in einem WorkspaceEdit mit mehreren Dateien (#297).</summary>
  TLspFileChange = record
    FileName: string;
    /// <summary>Bisheriger Inhalt; bei New leer.</summary>
    OldText: string;
    NewText: string;
    /// <summary>Datei neu anlegen (documentChanges kind create).</summary>
    New: Boolean;
    class function Create(const AFileName, AOldText, ANewText: string; ANew: Boolean): TLspFileChange; static;
  end;

  TLspApplyEdit = class
  public const
    cMethod = 'workspace/applyEdit';
  public
    /// <summary>Kündigt der Client in initialize capabilities.workspace.applyEdit an?</summary>
    class function ClientSupports(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>WorkspaceEdit, das den ganzen Text AOldText der Datei AFileName durch ANewText ersetzt.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function ReplaceAll(const AFileName, AOldText, ANewText: string): TJSONObject; static;
    /// <summary>WorkspaceEdit mit documentChanges: neue Dateien anlegen und füllen, vorhandene ganz ersetzen,
    /// in der Reihenfolge von AChanges. Der Aufrufer übernimmt das Objekt.</summary>
    class function Files(const AChanges: TArray<TLspFileChange>): TJSONObject; static;
    /// <summary>WorkspaceEdit mit den Änderungen AEdits in einer Datei (changes). Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function TextEdits(const AFileName: string; const AEdits: TArray<TTextEdit>): TJSONObject; static;
    /// <summary>Vollständige Anfrage mit id AId; übernimmt AEdit. Der Aufrufer übernimmt das Ergebnis.</summary>
    class function Request(const AId, ALabel: string; AEdit: TJSONObject): TJSONObject; static;
    /// <summary>Antwort des Clients: True bei applied; sonst AReason (failureReason bzw. Fehlermeldung).</summary>
    class function ReadResult(const AResponse: TJSONObject; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TApplyEditText = (NoAnswer, NotApplied, Error);

const
  cTexts: array[TApplyEditText] of TAtlasText = (
    (De: 'keine Antwort'; En: 'no answer'),
    (De: 'nicht übernommen'; En: 'not applied'),
    (De: 'Fehler'; En: 'error'));

{$SCOPEDENUMS OFF}

class function TLspApplyEdit.ClientSupports(const AInitializeParams: TJSONObject): Boolean;
var
  mValue: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.applyEdit', mValue) and mValue;
end;

{ TLspFileChange }

class function TLspFileChange.Create(const AFileName, AOldText, ANewText: string; ANew: Boolean): TLspFileChange;
begin
  Result.FileName := AFileName;
  Result.OldText := AOldText;
  Result.NewText := ANewText;
  Result.New := ANew;
end;

{ TLspApplyEdit }

/// <summary>Bereich über den ganzen Text AText, Länge in UTF-16-Einheiten wie im LSP üblich.</summary>
function WholeRange(const AText: string): TTextRange;
var
  mLines: TArray<string>;
begin
  mLines := AText.Split([#10]);
  if Length(mLines) = 0 then
  begin
    mLines := [''];
  end;
  Result := TTextRange.Create(0, 0, High(mLines), Length(mLines[High(mLines)]));
end;

class function TLspApplyEdit.Files(const AChanges: TArray<TLspFileChange>): TJSONObject;
var
  mChanges, mEdits: TJSONArray;
  mCreation, mOptions, mDocument, mEdit, mItem: TJSONObject;
  mChange: TLspFileChange;
  mUri: string;
  mRange: TTextRange;
begin
  mChanges := TJSONArray.Create;
  for mChange in AChanges do
  begin
    mUri := TDocumentUris.FromPath(mChange.FileName);
    if mChange.New then
    begin
      mCreation := TJSONObject.Create;
      mCreation.AddPair('kind', 'create');
      mCreation.AddPair('uri', mUri);
      mOptions := TJSONObject.Create;
      mOptions.AddPair('ignoreIfExists', TJSONBool.Create(False));
      mCreation.AddPair('options', mOptions);
      mChanges.AddElement(mCreation);
      mRange := TTextRange.Create(0, 0, 0, 0);
    end
    else
    begin
      mRange := WholeRange(mChange.OldText);
    end;
    mDocument := TJSONObject.Create;
    mDocument.AddPair('uri', mUri);
    mDocument.AddPair('version', TJSONNull.Create);
    mEdit := TJSONObject.Create;
    mEdit.AddPair('range', TLspPositions.RangeToJson(mRange));
    mEdit.AddPair('newText', mChange.NewText);
    mEdits := TJSONArray.Create;
    mEdits.AddElement(mEdit);
    mItem := TJSONObject.Create;
    mItem.AddPair('textDocument', mDocument);
    mItem.AddPair('edits', mEdits);
    mChanges.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
end;

class function TLspApplyEdit.ReplaceAll(const AFileName, AOldText, ANewText: string): TJSONObject;
var
  mLines: TArray<string>;
  mLast: string;
  mEdit: TJSONObject;
  mEdits: TJSONArray;
  mChanges: TJSONObject;
begin
  // Ende des alten Texts: letzte Zeile, Länge in UTF-16-Einheiten wie im LSP üblich.
  mLines := AOldText.Split([#10]);
  if Length(mLines) = 0 then
  begin
    mLines := [''];
  end;
  mLast := mLines[High(mLines)];
  mEdit := TJSONObject.Create;
  mEdit.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(0, 0, High(mLines), Length(mLast))));
  mEdit.AddPair('newText', ANewText);
  mEdits := TJSONArray.Create;
  mEdits.AddElement(mEdit);
  mChanges := TJSONObject.Create;
  mChanges.AddPair(TDocumentUris.FromPath(AFileName), mEdits);
  Result := TJSONObject.Create;
  Result.AddPair('changes', mChanges);
end;

class function TLspApplyEdit.TextEdits(const AFileName: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  mEdits: TJSONArray;
  mEdit: TJSONObject;
  mItem: TTextEdit;
  mChanges: TJSONObject;
begin
  mEdits := TJSONArray.Create;
  for mItem in AEdits do
  begin
    mEdit := TJSONObject.Create;
    mEdit.AddPair('range', TLspPositions.RangeToJson(mItem.Range));
    mEdit.AddPair('newText', mItem.NewText);
    mEdits.AddElement(mEdit);
  end;
  mChanges := TJSONObject.Create;
  mChanges.AddPair(TDocumentUris.FromPath(AFileName), mEdits);
  Result := TJSONObject.Create;
  Result.AddPair('changes', mChanges);
end;

class function TLspApplyEdit.Request(const AId, ALabel: string; AEdit: TJSONObject): TJSONObject;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  if ALabel <> '' then
  begin
    mParams.AddPair('label', ALabel);
  end;
  mParams.AddPair('edit', AEdit);
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', AId);
  Result.AddPair('method', cMethod);
  Result.AddPair('params', mParams);
end;

class function TLspApplyEdit.ReadResult(const AResponse: TJSONObject; out AReason: string): Boolean;
var
  mApplied: Boolean;
begin
  AReason := '';
  Result := False;
  if AResponse = nil then
  begin
    AReason := cTexts[TApplyEditText.NoAnswer].Text;
    Exit;
  end;
  if AResponse.GetValue('error') <> nil then
  begin
    if not AResponse.TryGetValue<string>('error.message', AReason) then
    begin
      AReason := cTexts[TApplyEditText.Error].Text;
    end;
    Exit;
  end;
  Result := AResponse.TryGetValue<Boolean>('result.applied', mApplied) and mApplied;
  if not Result and not AResponse.TryGetValue<string>('result.failureReason', AReason) then
  begin
    AReason := cTexts[TApplyEditText.NotApplied].Text;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ApplyEdit', cTexts);

end.
