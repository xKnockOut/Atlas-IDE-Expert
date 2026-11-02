unit Shell.Composition.Refactorings.Conversions;

// Internals-Rolle Shell: Umwandlungen: Boolean umkehren, lokale Variable und Feld umwandeln, anonyme Methode und
// Methode umwandeln, Methode ohne Self umwandeln.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellConversionRefactorings = class(TShellRefactoringPart)
  private
    function InvertBooleanActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function InvertBoolean(const AArguments: TJSONArray): TJSONValue;
    function PromoteVariableActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function PromoteVariable(const AArguments: TJSONArray): TJSONValue;
    function AnonymousMethodActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function AnonymousMethod(const AArguments: TJSONArray): TJSONValue;
    function MethodKindActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function MethodKind(const AArguments: TJSONArray): TJSONValue;
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
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.InvertBoolean,
  Atlas.Common.Lsp.PromoteVariable,
  Atlas.Common.Lsp.AnonymousMethods,
  Atlas.Common.Lsp.MethodWithoutSelf;

function InvertBooleanContextOf(const ASettings: TRefactoringSettings): TInvertBooleanContext;
begin
  Result := Default(TInvertBooleanContext);
  Result.Antonyms := ASettings.InvertBooleanAntonyms;
  Result.Prefix := ASettings.InvertBooleanFallbackPrefix;
  Result.IncludeDfm := ASettings.InvertBooleanIncludeDfm;
end;

procedure TShellConversionRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspInvertBoolean.ApplyCommand, InvertBoolean);
  ACommands.Register(TLspPromoteVariable.ApplyCommand, PromoteVariable);
  ACommands.Register(TLspAnonymousMethods.ApplyCommand, AnonymousMethod);
  ACommands.Register(TLspMethodWithoutSelf.ApplyCommand, MethodKind);
end;

function TShellConversionRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := InvertBooleanActions(AUri, ARange.StartPos);
  Result := Result + PromoteVariableActions(AUri, ARange.StartPos);
  Result := Result + AnonymousMethodActions(AUri, ARange.StartPos);
  Result := Result + MethodKindActions(AUri, ARange.StartPos);
end;

function TShellConversionRefactorings.InvertBooleanActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TInvertBooleanContext;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if not TryOpen(AUri, mSettings.InvertBoolean, mDocument) then
  begin
    Exit;
  end;
  mContext := InvertBooleanContextOf(mSettings);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mResolver := NewResolver;
  try
    Result := TLspInvertBoolean.Actions(True, mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(AUri), AUri, APosition, mContext);
  finally
    mResolver.Free;
  end;
end;

function TShellConversionRefactorings.InvertBoolean(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TInvertBooleanContext;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, neuer Name.
  Require(AArguments, 3, 'Argumente "uri", "position" und "name" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.InvertBoolean, '"Boolean umkehren" ist abgeschaltet (refactoring.invertBoolean).');
  mContext := InvertBooleanContextOf(mSettings);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mResolver := NewResolver;
  try
    mAnswer := TLspInvertBoolean.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]),
      Trim(AArguments.Items[2].Value), mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Boolean umkehren: %d Stellen in %d Dateien, %d Warnungen', [Number(mAnswer, 'places'),
    Number(mAnswer, 'files'), Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellConversionRefactorings.PromoteVariableActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mFileName: string;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).PromoteVariable, mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(AUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      Result := TLspPromoteVariable.Actions(mShared.Tree, mDocument.Text, AUri, APosition,
        TLspPromoteVariable.Lookup(mResolver, mShared.Tree, mFileName, Reader));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellConversionRefactorings.PromoteVariable(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, Name.
  Require(AArguments, 3, 'Argumente "uri", "position" und "name" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).PromoteVariable,
    '"Lokale Variable und Feld umwandeln" ist abgeschaltet (refactoring.promoteVariable).');
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(mUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      mAnswer := TLspPromoteVariable.Execute(mShared.Tree, mDocument.Text, mUri,
        TLspPositions.ReadPosition(AArguments.Items[1]), Trim(AArguments.Items[2].Value),
        TLspPromoteVariable.Lookup(mResolver, mShared.Tree, mFileName, Reader), FormatStyle(mUri));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
  Log(Format('Variable/Feld umwandeln: %d Stellen, %d Warnungen', [Number(mAnswer, 'places'),
    Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellConversionRefactorings.AnonymousMethodActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mSettings: TRefactoringSettings;
  mFileName: string;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if not TryOpen(AUri, mSettings.AnonymousMethod, mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(AUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      Result := TLspAnonymousMethods.Actions(mShared.Tree, mDocument.Text, AUri, APosition,
        TLspAnonymousMethods.Lookup(mResolver, mShared.Tree, mFileName, Reader),
        TLspAnonymousMethods.CaptureOf(mSettings.AnonymousMethodDeferredCapture), FormatStyle(AUri));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellConversionRefactorings.AnonymousMethod(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mSettings: TRefactoringSettings;
begin
  // Argumente: URI, Position, Name.
  Require(AArguments, 3, 'Argumente "uri", "position" und "name" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.AnonymousMethod,
    '"Anonyme Methode und Methode umwandeln" ist abgeschaltet (refactoring.anonymousMethod).');
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(mUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      mAnswer := TLspAnonymousMethods.Execute(mShared.Tree, mDocument.Text, mUri,
        TLspPositions.ReadPosition(AArguments.Items[1]), Trim(AArguments.Items[2].Value),
        TLspAnonymousMethods.Lookup(mResolver, mShared.Tree, mFileName, Reader),
        TLspAnonymousMethods.CaptureOf(mSettings.AnonymousMethodDeferredCapture), FormatStyle(mUri));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
  Log(Format('Anonyme Methode umwandeln: %d Änderungen, %d Warnungen', [Number(mAnswer, 'places'),
    Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

function TShellConversionRefactorings.MethodKindActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mFileName: string;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).MethodKind, mDocument) then
  begin
    Exit;
  end;
  mShared := TSyntaxTreeCache.Get(mDocument, nil);
  mFileName := TDocumentUris.ToPath(AUri);
  mResolver := NewResolver;
  try
    mResolver.PinTree(mShared.Tree, mFileName);
    try
      Result := TLspMethodWithoutSelf.Actions(mShared.Tree, mDocument.Text, AUri, APosition,
        TLspMethodWithoutSelf.Lookup(mResolver, mShared.Tree, mFileName, Reader));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

function TShellConversionRefactorings.MethodKind(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mSettings: TRefactoringSettings;
  mContext: TMethodKindContext;
begin
  // Argumente: URI, Position, Umwandlung.
  Require(AArguments, 3, 'Argumente "uri", "position" und "conversion" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.MethodKind,
    '"Methode ohne Self umwandeln" ist abgeschaltet (refactoring.methodKind).');
  mContext := Default(TMethodKindContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.WithStatic := mSettings.MethodKindStatic;
  mResolver := NewResolver;
  try
    mAnswer := TLspMethodWithoutSelf.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]),
      Trim(AArguments.Items[2].Value), mContext, FormatStyle(mUri));
  finally
    mResolver.Free;
  end;
  Log(Format('Methode ohne Self umwandeln: %d Änderungen, %d Aufrufe, %d Warnungen', [Number(mAnswer, 'places'),
    Number(mAnswer, 'calls'), Count(mAnswer, 'warnings')]));
  Result := mAnswer;
end;

end.
