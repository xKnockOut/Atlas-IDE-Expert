unit Shell.Composition.Refactorings.Visibility;

// Internals-Rolle Shell: „Sichtbarkeit anheben“ und „Eigenschaft anlegen“ (#2108). Die Code-Aktion auf der
// Deklaration gilt mit refactoring.raiseVisibility; der Befehl für die Vervollständigung liest die Datei der
// Deklaration auch, wenn sie nicht geöffnet ist (offenes Dokument vor der Platte).

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellVisibilityRefactorings = class(TShellRefactoringPart)
  private
    function MemberActions(const AArguments: TJSONArray): TJSONValue;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.RaiseVisibility,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TVisibilityRefactoringText = (NotReadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TVisibilityRefactoringText] of TAtlasText = (
    (De: 'Die Datei der Deklaration lässt sich nicht lesen.'; En: 'The file of the declaration cannot be read.'));

procedure TShellVisibilityRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspRaiseVisibility.cCommand, MemberActions);
end;

function TShellVisibilityRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).RaiseVisibility, mDocument) then
  begin
    Result := TLspRaiseVisibility.Actions(AUri, mDocument.Text, TSyntaxTreeCache.Get(mDocument, nil).Tree, ARange);
  end;
end;

function TShellVisibilityRefactorings.MemberActions(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mText, mName: string;
  mAnswer: TJSONArray;
begin
  // Argumente: URI der Datei der Deklaration, Position der Deklaration, Name des Mitglieds.
  Require(AArguments, ['uri', 'position', 'name']);
  mUri := AArguments.Items[0].Value;
  mName := AArguments.Items[2].Value;
  if not ReadText(TDocumentUris.ToPath(mUri), mText) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed, cTexts[TVisibilityRefactoringText.NotReadable].Text);
  end;
  mAnswer := TLspRaiseVisibility.Execute(mUri, mText, TLspPositions.ReadPosition(AArguments.Items[1]), mName);
  Log(Format('Mitglied-Aktionen: %d', [mAnswer.Count]));
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Refactorings.Visibility', cTexts);

end.
