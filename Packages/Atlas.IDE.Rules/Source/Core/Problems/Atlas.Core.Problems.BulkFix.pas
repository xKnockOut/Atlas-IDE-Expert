unit Atlas.Core.Problems.BulkFix;

// Sammelkorrektur aus dem Fenster „Atlas-Prüfung“ (#1352), ohne VCL und Open
// Tools API: „Alle sicheren Treffer von <Regel> korrigieren …“.
// - Dateien: die der angezeigten Befunde dieser Regel (gefiltert, Bereich des
//   Fensters), jede einmal.
// - Anfrage: Argumente für atlas.server.fixFindings ([{"rules": [Regel],
//   "files": [...]}]); der Server korrigiert wie --check --fix und schreibt
//   nichts.
// - Vorschau: je Datei Korrekturen, Diff und WorkspaceEdit aus der Antwort;
//   verworfene Dateien (neue Syntaxfehler) stehen mit drin, lassen sich aber
//   nicht wählen. Gewählt sind anfangs alle übrigen; SelectedEdit fasst die
//   gewählten zu einem WorkspaceEdit zusammen (ein Rückgängig-Schritt je Datei
//   beim Anwenden, ein Satz im Änderungsprotokoll).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Problems.Findings;

type
  TAtlasBulkFixFile = record
    FileName: string;
    Fixes: Integer;
    /// <summary>Verworfen: Die Korrekturen ergäben neue Syntaxfehler; ohne Diff und Edit.</summary>
    Rejected: Boolean;
    Diff: string;
    Edit: TLspWorkspaceEdit;
    Checked: Boolean;
  end;

  TAtlasBulkFixPreview = class
  public const
    cCommand = 'atlas.server.fixFindings';
  private
    FRule: string;
    FSummary: string;
    FFiles: TArray<TAtlasBulkFixFile>;
    function GetFile(AIndex: Integer): TAtlasBulkFixFile;
  public
    /// <summary>Aus der Antwort von atlas.server.fixFindings; nil oder Unlesbares ergibt eine leere Vorschau.
    /// </summary>
    constructor Create(const ARule: string; const AAnswer: TJSONValue);
    /// <summary>Dateien der Befunde von ARule in AFindings, jede einmal, in der Reihenfolge der Befunde.</summary>
    class function FilesOf(const AFindings: TArray<TAtlasFinding>; const ARule: string): TArray<string>; static;
    /// <summary>Argumente für atlas.server.fixFindings als JSON-Text.</summary>
    class function ArgumentsJson(const ARule: string; const AFiles: TArray<string>): string; static;
    function Count: Integer;
    /// <summary>Datei wählen bzw. abwählen; verworfene bleiben abgewählt.</summary>
    procedure SetChecked(AIndex: Integer; AChecked: Boolean);
    /// <summary>Gewählte Dateien und ihre Korrekturen.</summary>
    function SelectedCount: Integer;
    function SelectedFixes: Integer;
    /// <summary>Alle Änderungen der gewählten Dateien in einem WorkspaceEdit.</summary>
    function SelectedEdit: TLspWorkspaceEdit;
    property Rule: string read FRule;
    /// <summary>Zusammenfassung des Servers (Korrekturen je Regel, Übersprungenes).</summary>
    property Summary: string read FSummary;
    property Files[AIndex: Integer]: TAtlasBulkFixFile read GetFile;
  end;

implementation

constructor TAtlasBulkFixPreview.Create(const ARule: string; const AAnswer: TJSONValue);
var
  mItems: TJSONArray;
  mValue: TJSONValue;
  mItem: TJSONObject;
  mFile: TAtlasBulkFixFile;
begin
  inherited Create;
  FRule := ARule;
  FSummary := '';
  FFiles := nil;
  if not (AAnswer is TJSONObject) then
  begin
    Exit;
  end;
  FSummary := TJSONObject(AAnswer).GetValue<string>('summary', '');
  if not TJSONObject(AAnswer).TryGetValue<TJSONArray>('files', mItems) then
  begin
    Exit;
  end;
  for mValue in mItems do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    mFile := Default(TAtlasBulkFixFile);
    mFile.FileName := mItem.GetValue<string>('file', '');
    mFile.Fixes := mItem.GetValue<Integer>('fixes', 0);
    mFile.Rejected := mItem.GetValue<Boolean>('rejected', False);
    mFile.Diff := mItem.GetValue<string>('diff', '');
    mFile.Edit := TLspWorkspaceEdit.FromJson(mItem.GetValue('edit'));
    // Ohne lesbares Edit lässt sich die Datei nicht anwenden: wie verworfen nicht wählbar.
    mFile.Checked := not mFile.Rejected and not mFile.Edit.IsEmpty;
    if mFile.FileName <> '' then
    begin
      FFiles := FFiles + [mFile];
    end;
  end;
end;

class function TAtlasBulkFixPreview.FilesOf(const AFindings: TArray<TAtlasFinding>;
  const ARule: string): TArray<string>;
var
  mFinding: TAtlasFinding;
  mName: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    if (mFinding.Category = TAtlasFindingCategory.Compiler) or not SameText(mFinding.Rule, ARule) or
      (mFinding.FileName = '') then
    begin
      Continue;
    end;
    mKnown := False;
    for mName in Result do
    begin
      if SameText(mName, mFinding.FileName) then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mFinding.FileName];
    end;
  end;
end;

class function TAtlasBulkFixPreview.ArgumentsJson(const ARule: string; const AFiles: TArray<string>): string;
var
  mArguments: TJSONArray;
  mOptions: TJSONObject;
  mRules, mFiles: TJSONArray;
  mName: string;
begin
  mArguments := TJSONArray.Create;
  try
    mOptions := TJSONObject.Create;
    mArguments.AddElement(mOptions);
    mRules := TJSONArray.Create;
    mRules.Add(ARule);
    mOptions.AddPair('rules', mRules);
    mFiles := TJSONArray.Create;
    for mName in AFiles do
    begin
      mFiles.Add(mName);
    end;
    mOptions.AddPair('files', mFiles);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

function TAtlasBulkFixPreview.Count: Integer;
begin
  Result := Length(FFiles);
end;

function TAtlasBulkFixPreview.GetFile(AIndex: Integer): TAtlasBulkFixFile;
begin
  Result := FFiles[AIndex];
end;

procedure TAtlasBulkFixPreview.SetChecked(AIndex: Integer; AChecked: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FFiles)) then
  begin
    Exit;
  end;
  FFiles[AIndex].Checked := AChecked and not FFiles[AIndex].Rejected and not FFiles[AIndex].Edit.IsEmpty;
end;

function TAtlasBulkFixPreview.SelectedCount: Integer;
var
  mFile: TAtlasBulkFixFile;
begin
  Result := 0;
  for mFile in FFiles do
  begin
    if mFile.Checked then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasBulkFixPreview.SelectedFixes: Integer;
var
  mFile: TAtlasBulkFixFile;
begin
  Result := 0;
  for mFile in FFiles do
  begin
    if mFile.Checked then
    begin
      Inc(Result, mFile.Fixes);
    end;
  end;
end;

function TAtlasBulkFixPreview.SelectedEdit: TLspWorkspaceEdit;
var
  mFile: TAtlasBulkFixFile;
begin
  Result := TLspWorkspaceEdit.FromJson(nil);
  for mFile in FFiles do
  begin
    if mFile.Checked then
    begin
      Result.Files := Result.Files + mFile.Edit.Files;
    end;
  end;
end;

end.
