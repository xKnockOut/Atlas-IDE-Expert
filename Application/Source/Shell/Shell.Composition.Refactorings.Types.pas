unit Shell.Composition.Refactorings.Types;

// Internals-Rolle Shell: Refactorings an Typen und Routinen: Typ-Alias einführen und auflösen, Namenstabellen zu
// Aufzählungen anlegen und nachziehen, Überladung anlegen.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellTypeRefactorings = class(TShellRefactoringPart)
  private
    function TypeAliasActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function TypeAlias(const AArguments: TJSONArray): TJSONValue;
    function InlineTypeAlias(const AArguments: TJSONArray): TJSONValue;
    function EnumTableActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function EnumTable(const AArguments: TJSONArray): TJSONValue;
    function EnumTablesSync(const AArguments: TJSONArray): TJSONValue;
    function OverloadActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function CreateOverload(const AArguments: TJSONArray): TJSONValue;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TypeAlias,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.TypeAlias,
  Atlas.Common.Lsp.EnumTables,
  Atlas.Common.Lsp.Overloads,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TTypeRefactoringText = (TypeAlias, ResolveAlias, EnumTables, UpdateTables, Overloads);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TTypeRefactoringText] of TAtlasText = (
    (De: 'Typ-Alias einführen'; En: 'Introduce type alias'),
    (De: 'Alias auflösen'; En: 'Resolve alias'),
    (De: 'Namenstabelle anlegen'; En: 'Create name table'),
    (De: 'Tabellen nachziehen'; En: 'Update tables'),
    (De: 'Überladung anlegen'; En: 'Create overload'));

procedure TShellTypeRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspTypeAlias.ApplyCommand, TypeAlias);
  ACommands.Register(TLspTypeAlias.InlineApplyCommand, InlineTypeAlias);
  ACommands.Register(TLspEnumTables.ApplyCommand, EnumTable);
  ACommands.Register(TLspEnumTables.SyncApplyCommand, EnumTablesSync);
  ACommands.Register(TLspOverloads.ApplyCommand, CreateOverload);
end;

function TShellTypeRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := TypeAliasActions(AUri, ARange.StartPos);
  Result := Result + EnumTableActions(AUri, ARange.StartPos);
  Result := Result + OverloadActions(AUri, ARange.StartPos);
end;

function TShellTypeRefactorings.TypeAliasActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mSettings: TRefactoringSettings;
  mScope: TTypeAliasScope;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if not TryOpen(AUri, mSettings.TypeAlias, mDocument) then
  begin
    Exit;
  end;
  if not TTypeAlias.ScopeOf(mSettings.TypeAliasScope, mScope) then
  begin
    mScope := TTypeAliasScope.InUnit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspTypeAlias.Actions(mShared.Tree, mDocument.Text, AUri, APosition, mScope,
        TLspTypeAlias.Lookup(mResolver));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellTypeRefactorings.TypeAlias(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mContext: TTypeAliasContext;
begin
  // Argumente: URI, Position, Name, Reichweite.
  Require(AArguments, ['uri', 'position', 'name', 'scope']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).TypeAlias, Disabled(cTexts[TTypeRefactoringText.TypeAlias].Text,
    'refactoring.typeAlias'));
  mContext := Default(TTypeAliasContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.Name := AArguments.Items[2].Value;
  mContext.Scope := Trim(AArguments.Items[3].Value);
  mResolver := NewResolver;
  try
    mAnswer := TLspTypeAlias.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Typ-Alias einführen: %d Stellen, %d Dateien, %d Warnungen', [Number(mAnswer, 'places'),
    Number(mAnswer, 'files'), Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellTypeRefactorings.InlineTypeAlias(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mContext: TTypeAliasContext;
begin
  // Argumente: URI, Position des Alias-Namens.
  Require(AArguments, ['uri', 'position']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).TypeAlias, Disabled(cTexts[TTypeRefactoringText.ResolveAlias].Text,
    'refactoring.typeAlias'));
  mContext := Default(TTypeAliasContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mResolver := NewResolver;
  try
    mAnswer := TLspTypeAlias.ExecuteInline(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Alias auflösen: %d Stellen, %d Dateien, %d Warnungen', [Number(mAnswer, 'places'),
    Number(mAnswer, 'files'), Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellTypeRefactorings.EnumTableActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).EnumTables, ['.pas', '.dpr'], mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, TDocumentUris.ToPath(AUri));
    try
      Result := TLspEnumTables.Actions(mResolver, Index, mShared.Tree, mDocument.Text, AUri, APosition);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellTypeRefactorings.EnumTable(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mContext: TEnumTablesContext;
begin
  // Argumente: URI, Position, Name, Stelle.
  Require(AArguments, ['uri', 'position', 'name', 'placement']);
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.EnumTables, Disabled(cTexts[TTypeRefactoringText.EnumTables].Text,
    'refactoring.enumTables'));
  mContext := Default(TEnumTablesContext);
  mContext.ResourceStrings := mSettings.EnumTablesResourceStrings;
  Result := TLspEnumTables.Execute(TEnumTablesDocument.Create(TSyntaxTreeCache.Get(mDocument, nil).Tree,
    TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1])),
    AArguments.Items[2].Value, Trim(AArguments.Items[3].Value), mContext);
  Log('Namenstabelle angelegt');
end;

function TShellTypeRefactorings.EnumTablesSync(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mContext: TEnumTablesContext;
begin
  // Argumente: URI, Position des Typnamens.
  Require(AArguments, ['uri', 'position']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).EnumTables, Disabled(cTexts[TTypeRefactoringText.UpdateTables].Text,
    'refactoring.enumTables'));
  mContext := Default(TEnumTablesContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mResolver := NewResolver;
  try
    mAnswer := TLspEnumTables.Sync(mResolver, TEnumTablesDocument.Create(TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1])), mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Tabellen nachziehen: %d Stellen, %d Dateien, %d Warnungen', [Number(mAnswer, 'places'),
    Number(mAnswer, 'files'), Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellTypeRefactorings.OverloadActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).Overloads, ['.pas', '.dpr'], mDocument) then
  begin
    Result := TLspOverloads.Actions(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, AUri, APosition);
  end;
end;

function TShellTypeRefactorings.CreateOverload(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
begin
  // Argumente: URI, Position, Art (copy bzw. forward).
  Require(AArguments, ['uri', 'position', 'kind']);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).Overloads, Disabled(cTexts[TTypeRefactoringText.Overloads].Text,
    'refactoring.overloads'));
  mFileName := TDocumentUris.ToPath(mUri);
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      Result := TLspOverloads.Execute(mShared.Tree, mFileName, mDocument.Text,
        TLspPositions.ReadPosition(AArguments.Items[1]), Trim(AArguments.Items[2].Value),
        TLspOverloads.DefaultFunc(mResolver, Index, mShared.Tree, mFileName, mDocument.Text));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
  Log('Überladung angelegt');
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Refactorings.Types', cTexts);

end.
