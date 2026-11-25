unit Atlas.Common.CodeActions.Json;

// Code-Aktionen als LSP-CodeAction und Änderungen als WorkspaceEdit (JSON). Sprachserver, Refactorings und
// MCP schreiben Aktionen über diese Unit, ohne den Sprachserver einzubinden.
// Abwählbare Teile einer Aktion (#2054) stehen in data.choices ([{title, range}]) und data.editChoices (je Edit
// des Dokuments die Indizes der Teile, die alle gewählt sein müssen; [] gilt immer).

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.CodeActions.Contract;

type
  TCodeActionsJson = class
  public const
    /// <summary>Quelle der Diagnosen von Atlas (Feld "source").</summary>
    cDiagnosticSource = 'Atlas';
  public
    /// <summary>Eine Aktion als LSP-CodeAction. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject; static;
    /// <summary>WorkspaceEdit {"changes": {AUri: [...]}} für Befehle, die Änderungen liefern (#668). Der Aufrufer
    /// übernimmt das Objekt.</summary>
    class function WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Positions;

function CommandJson(const AAction: TCodeAction): TJSONObject;
var
  mArguments: TJSONArray;
  mArgument: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', AAction.Title);
  Result.AddPair('command', AAction.Command);
  mArguments := TJSONArray.Create;
  for mArgument in AAction.CommandArguments do
  begin
    mArguments.Add(mArgument);
  end;
  Result.AddPair('arguments', mArguments);
end;

/// <summary>Abwählbare Teile (#2054): {"title", "range"} je Teil.</summary>
function ChoicesJson(const AAction: TCodeAction): TJSONArray;
var
  mChoice: TCodeActionChoice;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mChoice in AAction.Choices do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('title', mChoice.Title);
    mItem.AddPair('range', TLspPositions.RangeToJson(mChoice.Range));
    Result.AddElement(mItem);
  end;
end;

/// <summary>Je Edit des Dokuments die Teile, die alle gewählt sein müssen (#2054); [] gilt immer.</summary>
function EditChoicesJson(const AAction: TCodeAction): TJSONArray;
var
  mIndex, mChoice: Integer;
  mItem: TJSONArray;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to High(AAction.Edits) do
  begin
    mItem := TJSONArray.Create;
    if mIndex <= High(AAction.EditChoices) then
    begin
      for mChoice in AAction.EditChoices[mIndex] do
      begin
        mItem.Add(mChoice);
      end;
    end;
    Result.AddElement(mItem);
  end;
end;

/// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (#621), Vorschau vor dem Übernehmen (#663),
/// abwählbare Teile (#2054).</summary>
function DataJson(const AAction: TCodeAction): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AAction.Choices <> nil then
  begin
    Result.AddPair('choices', ChoicesJson(AAction));
    Result.AddPair('editChoices', EditChoicesJson(AAction));
  end;
  if AAction.Tag <> '' then
  begin
    Result.AddPair('tag', AAction.Tag);
  end;
  if AAction.Preview <> '' then
  begin
    Result.AddPair('preview', AAction.Preview);
  end;
end;

function DiagnosticsJson(const AAction: TCodeAction): TJSONArray;
var
  mDiagnostic: TJSONObject;
begin
  mDiagnostic := TJSONObject.Create;
  mDiagnostic.AddPair('range', TLspPositions.RangeToJson(AAction.DiagnosticRange));
  mDiagnostic.AddPair('code', AAction.RuleId);
  mDiagnostic.AddPair('source', TCodeActionsJson.cDiagnosticSource);
  mDiagnostic.AddPair('message', '');
  Result := TJSONArray.Create;
  Result.AddElement(mDiagnostic);
end;

function ChangesJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  mFileEdits: TFileTextEdits;
begin
  Result := TJSONObject.Create;
  // Nur Edits in anderen Dateien (Formulardatei, #309): das Dokument bleibt unverändert.
  if (AAction.Edits <> nil) or (AAction.FileEdits = nil) then
  begin
    Result.AddPair(AUri, TLspPositions.EditsToJson(AAction.Edits));
  end;
  for mFileEdits in AAction.FileEdits do
  begin
    Result.AddPair(TDocumentUris.FromPath(mFileEdits.FileName), TLspPositions.EditsToJson(mFileEdits.Edits));
  end;
end;

class function TCodeActionsJson.ActionToJson(const AUri: string; const AAction: TCodeAction): TJSONObject;
var
  mWorkspaceEdit: TJSONObject;
begin
  mWorkspaceEdit := TJSONObject.Create;
  mWorkspaceEdit.AddPair('changes', ChangesJson(AUri, AAction));
  Result := TJSONObject.Create;
  Result.AddPair('title', AAction.Title);
  Result.AddPair('kind', AAction.Kind);
  if AAction.Command <> '' then
  begin
    Result.AddPair('command', CommandJson(AAction));
  end;
  if AAction.IsPreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  if (AAction.Tag <> '') or (AAction.Preview <> '') or (AAction.Choices <> nil) then
  begin
    Result.AddPair('data', DataJson(AAction));
  end;
  // Hinweis statt Aktion (LSP 3.16 disabled).
  if AAction.Disabled <> '' then
  begin
    Result.AddPair('disabled', TJSONObject.Create(TJSONPair.Create('reason', AAction.Disabled)));
  end;
  if AAction.RuleId <> '' then
  begin
    Result.AddPair('diagnostics', DiagnosticsJson(AAction));
  end;
  Result.AddPair('edit', mWorkspaceEdit);
end;

class function TCodeActionsJson.WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  mChanges: TJSONObject;
begin
  mChanges := TJSONObject.Create;
  mChanges.AddPair(AUri, TLspPositions.EditsToJson(AEdits));
  Result := TJSONObject.Create;
  Result.AddPair('changes', mChanges);
end;

end.
