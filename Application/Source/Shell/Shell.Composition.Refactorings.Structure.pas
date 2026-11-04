unit Shell.Composition.Refactorings.Structure;

// Internals-Rolle Shell: Refactorings am Aufbau von Klassen: Signatur ändern, Klasse in eigene Unit verschieben,
// Property aus Getter und Setter (#583), Zugriffsmethode durch Feld ersetzen, Sicher löschen, Interface und
// Basisklasse herauslösen, Mitglied verschieben. Die Befehle mit Rückfrage haben je einen
// Befehl zum Vorbereiten und einen zum Ausführen.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.ExtractInterface,
  Atlas.Common.Lsp.ExtractSuperclass,
  Atlas.Common.Lsp.MoveMember,
  Shell.Composition.Refactorings.Services;

type
  TShellStructureRefactorings = class(TShellRefactoringPart)
  private
    function IsReadOnly(const AFileName: string): Boolean;
    /// <summary>Die Datei liegt auf der Platte oder ist im Editor geöffnet.</summary>
    function Exists(const AFileName: string): Boolean;
    function ChangeSignatureActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function ChangeSignaturePrepare(const AArguments: TJSONArray): TJSONValue;
    function ChangeSignature(const AArguments: TJSONArray): TJSONValue;
    function MoveClassActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function MoveClass(const AArguments: TJSONArray): TJSONValue;
    function PropertyFromAccessorsActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function PropertyFromAccessors(const AArguments: TJSONArray): TJSONValue;
    function InlineAccessorActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function InlineAccessor(const AArguments: TJSONArray): TJSONValue;
    function SafeDeleteActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function SafeDeletePrepare(const AArguments: TJSONArray): TJSONValue;
    function SafeDelete(const AArguments: TJSONArray): TJSONValue;
    function ExtractInterfaceActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function ExtractInterfaceContextOf(const AUri: string): TExtractInterfaceContext;
    function ExtractInterfacePrepare(const AArguments: TJSONArray): TJSONValue;
    function ExtractInterface(const AArguments: TJSONArray): TJSONValue;
    function ExtractSuperclassActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function ExtractSuperclassContextOf(const AUri: string): TExtractSuperclassContext;
    function ExtractSuperclassPrepare(const AArguments: TJSONArray): TJSONValue;
    function ExtractSuperclass(const AArguments: TJSONArray): TJSONValue;
    function MoveMemberActions(const AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
    function MoveMemberContextOf(const AArguments: TJSONArray; out ADocument: ITextDocument): TMoveMemberContext;
    function MoveMemberPrepare(const AArguments: TJSONArray): TJSONValue;
    function MoveMember(const AArguments: TJSONArray): TJSONValue;
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
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Editing.PropertyFromAccessors,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.PropertyFromAccessors,
  Atlas.Common.Lsp.InlineAccessor,
  Atlas.Common.Lsp.SafeDelete;

const
  cChangeSignatureOff = '"Signatur ändern" ist abgeschaltet (refactoring.changeSignature).';
  cExtractInterfaceOff = '"Interface herauslösen" ist abgeschaltet (refactoring.extractInterface).';
  cExtractSuperclassOff = '"Basisklasse herauslösen" ist abgeschaltet (refactoring.extractSuperclass).';
  cExtractMissing = 'Argument mit Name, Ziel und Mitgliedern fehlt';

function ParameterModeOf(const ASettings: TRefactoringSettings): TNewParameterMode;
begin
  Result := TNewParameterMode.UpdateCallers;
  if ASettings.NewParameterOverload then
  begin
    Result := TNewParameterMode.Overload;
  end;
end;

function PropertyOptionsOf(const ASettings: TRefactoringSettings): TPropertyFromAccessorsOptions;
begin
  Result := TPropertyFromAccessorsOptions.FromNames(ASettings.PropertyFromAccessorsPrefixes,
    ASettings.PropertyFromAccessorsSection, ASettings.PropertyFromAccessorsHideAccessors);
end;

function ReplaceCallsOf(const ASettings: TRefactoringSettings): TReplaceCalls;
begin
  Result := TReplaceCalls.Ask;
  if ASettings.PropertyFromAccessorsReplaceCalls = 'always' then
  begin
    Result := TReplaceCalls.Always;
  end
  else if ASettings.PropertyFromAccessorsReplaceCalls = 'never' then
  begin
    Result := TReplaceCalls.Never;
  end;
end;

function InlineAccessorOptionsOf(const ASettings: TRefactoringSettings): TInlineAccessorOptions;
begin
  Result := TInlineAccessorOptions.Default;
  Result.EqualityCheck := ASettings.InlineAccessorEqualityCheck;
end;

/// <summary>uses-Umfeld je Datei für „Sicher löschen“ über die Code-Aktionen.</summary>
function UsesForFunc(const AProvider: TUsesContextProvider): TSafeDeleteUsesFunc;
begin
  Result :=
    function(const AFileName: string): TUsesContext
    begin
      if not AProvider(TDocumentUris.FromPath(AFileName), Result) then
      begin
        Result := Default(TUsesContext);
      end;
    end;
end;

procedure TShellStructureRefactorings.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspChangeSignature.PrepareCommand, ChangeSignaturePrepare);
  ACommands.Register(TLspChangeSignature.ApplyCommand, ChangeSignature);
  ACommands.Register(TLspMoveClass.ApplyCommand, MoveClass);
  ACommands.Register(TLspPropertyFromAccessors.ApplyCommand, PropertyFromAccessors);
  ACommands.Register(TLspInlineAccessor.ApplyCommand, InlineAccessor);
  ACommands.Register(TLspSafeDelete.PrepareCommand, SafeDeletePrepare);
  ACommands.Register(TLspSafeDelete.ApplyCommand, SafeDelete);
  ACommands.Register(TLspExtractInterface.PrepareCommand, ExtractInterfacePrepare);
  ACommands.Register(TLspExtractInterface.ApplyCommand, ExtractInterface);
  ACommands.Register(TLspExtractSuperclass.PrepareCommand, ExtractSuperclassPrepare);
  ACommands.Register(TLspExtractSuperclass.ApplyCommand, ExtractSuperclass);
  ACommands.Register(TLspMoveMember.PrepareCommand, MoveMemberPrepare);
  ACommands.Register(TLspMoveMember.ApplyCommand, MoveMember);
end;

function TShellStructureRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := ChangeSignatureActions(AUri, ARange.StartPos);
  Result := Result + MoveClassActions(AUri, ARange.StartPos);
  Result := Result + PropertyFromAccessorsActions(AUri, ARange.StartPos);
  Result := Result + InlineAccessorActions(AUri, ARange.StartPos);
  Result := Result + SafeDeleteActions(AUri, ARange.StartPos);
  Result := Result + ExtractInterfaceActions(AUri, ARange.StartPos);
  Result := Result + ExtractSuperclassActions(AUri, ARange.StartPos);
  Result := Result + MoveMemberActions(AUri, ARange.StartPos);
end;

function TShellStructureRefactorings.IsReadOnly(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName) and FileIsReadOnly(AFileName);
end;

function TShellStructureRefactorings.Exists(const AFileName: string): Boolean;
begin
  Result := SourceExists(AFileName);
end;

function TShellStructureRefactorings.ChangeSignatureActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mResolver: TNameResolver;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).ChangeSignature, mDocument) then
  begin
    Exit;
  end;
  mResolver := NewResolver;
  try
    Result := TLspChangeSignature.Actions(True, mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(AUri), AUri, APosition);
  finally
    mResolver.Free;
  end;
end;

function TShellStructureRefactorings.ChangeSignaturePrepare(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mSettings: TRefactoringSettings;
begin
  // Argumente: URI, Position.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.ChangeSignature, cChangeSignatureOff);
  mResolver := NewResolver;
  try
    Result := TLspChangeSignature.InfoToJson(TLspChangeSignature.Prepare(mResolver, Index,
      TSyntaxTreeCache.Get(mDocument, nil).Tree, TDocumentUris.ToPath(mUri),
      TLspPositions.ReadPosition(AArguments.Items[1]), ProjectFiles, Reader, nil), ParameterModeOf(mSettings),
      mSettings.VirtualOverload);
  finally
    mResolver.Free;
  end;
end;

function TShellStructureRefactorings.ChangeSignature(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mSettings: TRefactoringSettings;
  mRequest: TChangeSignatureRequest;
  mOutcome: TChangeSignatureOutcome;
begin
  // Argumente: URI, Position, die neue Signatur (TLspChangeSignature.ReadRequest).
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.ChangeSignature, cChangeSignatureOff);
  Require(AArguments, 3, 'Argument mit der neuen Signatur fehlt');
  mRequest := TLspChangeSignature.ReadRequest(AArguments.Items[2], ParameterModeOf(mSettings),
    mSettings.VirtualOverload);
  mResolver := NewResolver;
  try
    mOutcome := TLspChangeSignature.Execute(mResolver, Index, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), TLspPositions.ReadPosition(AArguments.Items[1]), mRequest, ProjectFiles, Reader,
      IsReadOnly, nil);
  finally
    mResolver.Free;
  end;
  Log(Format('Signatur ändern: %d Änderungen, %d Warnungen', [Length(mOutcome.Edits), Length(mOutcome.Warnings)]));
  Result := TLspChangeSignature.OutcomeToJson(mOutcome);
end;

function TShellStructureRefactorings.MoveClassActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
  mResolver: TNameResolver;
begin
  Result := nil;
  if not TryOpen(AUri, Settings(AUri).MoveClass, mDocument) then
  begin
    Exit;
  end;
  mResolver := NewResolver;
  try
    Result := TLspMoveClass.Actions(True, mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(AUri), mDocument.Text, AUri, APosition);
  finally
    mResolver.Free;
  end;
end;

function TShellStructureRefactorings.MoveClass(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mFileName: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TMoveClassContext;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, Name der neuen Unit.
  Require(AArguments, 3, 'Argumente "uri", "position" und "name" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).MoveClass, '"Klasse verschieben" ist abgeschaltet (refactoring.moveClass).');
  mFileName := TDocumentUris.ToPath(mUri);
  mContext := Default(TMoveClassContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.Exists := Exists;
  mContext.HasProject := Project(mFileName, mContext.Project);
  mResolver := NewResolver;
  try
    mAnswer := TLspMoveClass.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree, mFileName, mDocument.Text,
      TLspPositions.ReadPosition(AArguments.Items[1]), AArguments.Items[2].Value, mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Klasse verschieben: %d Dateiänderungen',
    [TJSONArray(TJSONObject(mAnswer.GetValue('edit')).GetValue('documentChanges')).Count]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.PropertyFromAccessorsActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if TryOpen(AUri, mSettings.PropertyFromAccessors, mDocument) then
  begin
    Result := TLspPropertyFromAccessors.Actions(True, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
      AUri, APosition, PropertyOptionsOf(mSettings), ReplaceCallsOf(mSettings));
  end;
end;

function TShellStructureRefactorings.PropertyFromAccessors(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TPropertyFromAccessorsContext;
  mAnswer: TJSONObject;
  mReplaceCalls: Boolean;
begin
  // Argumente: URI, Position, Aufrufe umstellen (true/false).
  Require(AArguments, 3, 'Argumente "uri", "position" und "calls" fehlen');
  mUri := AArguments.Items[0].Value;
  mReplaceCalls := (AArguments.Items[2] is TJSONBool) and TJSONBool(AArguments.Items[2]).AsBoolean;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.PropertyFromAccessors,
    '"Property aus Getter und Setter" ist abgeschaltet (refactoring.propertyFromAccessors).');
  mContext := Default(TPropertyFromAccessorsContext);
  mContext.Index := Index;
  mContext.Options := PropertyOptionsOf(mSettings);
  if mReplaceCalls or (mContext.Options.Hiding <> TAccessorHiding.Off) then
  begin
    mContext.Files := ProjectFiles;
    mContext.ReadText := Reader;
  end;
  mResolver := NewResolver;
  try
    mAnswer := TLspPropertyFromAccessors.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mReplaceCalls,
      mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Property aus Getter und Setter: %d Properties, %d Aufrufe', [Number(mAnswer, 'properties'),
    Number(mAnswer, 'calls')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.InlineAccessorActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mOffer: TInlineAccessorOffer;
begin
  Result := nil;
  mSettings := Settings(AUri);
  if TryOpen(AUri, mSettings.InlineAccessor, mDocument) then
  begin
    mOffer := Default(TInlineAccessorOffer);
    mOffer.Enabled := True;
    mOffer.Bulk := mSettings.InlineAccessorBulk;
    mOffer.Options := InlineAccessorOptionsOf(mSettings);
    mOffer.Index := Index;
    Result := TLspInlineAccessor.Actions(mOffer, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, AUri,
      APosition);
  end;
end;

function TShellStructureRefactorings.InlineAccessor(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mScope: string;
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TInlineAccessorContext;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, Bereich (here, unit, project).
  Require(AArguments, 3, 'Argumente "uri", "position" und "scope" fehlen');
  mUri := AArguments.Items[0].Value;
  mScope := AArguments.Items[2].Value;
  mSettings := Settings(mUri);
  Allow(mSettings.InlineAccessor,
    '"Zugriffsmethode durch Feld ersetzen" ist abgeschaltet (refactoring.inlineAccessor).');
  Allow((mScope = TLspInlineAccessor.ScopeHere) or mSettings.InlineAccessorBulk,
    'Die Sammelaktion ist abgeschaltet (refactoring.inlineAccessorBulk).');
  mDocument := Open(mUri);
  mContext := Default(TInlineAccessorContext);
  mContext.Index := Index;
  mContext.Options := InlineAccessorOptionsOf(mSettings);
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.Scope := mScope;
  mResolver := NewResolver;
  try
    mAnswer := TLspInlineAccessor.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Zugriffsmethode durch Feld ersetzen: %d Methoden, %d Dateien', [Number(mAnswer, 'accessors'),
    Number(mAnswer, 'files')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.SafeDeleteActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).SafeDelete, mDocument) then
  begin
    Result := TLspSafeDelete.Actions(True, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, AUri,
      APosition);
  end;
end;

function TShellStructureRefactorings.SafeDeletePrepare(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mSettings: TRefactoringSettings;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mContext: TSafeDeleteContext;
begin
  // Argumente: URI, Position.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mSettings := Settings(mUri);
  mDocument := Open(mUri, mSettings.SafeDelete, '"Sicher löschen" ist abgeschaltet (refactoring.safeDelete).');
  mContext := Default(TSafeDeleteContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.UsesFor := UsesForFunc(UsesProvider);
  mResolver := NewResolver;
  try
    mAnswer := TLspSafeDelete.Prepare(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mContext);
  finally
    mResolver.Free;
  end;
  // Die Einstellungen entscheiden im Plugin über Rückfragen und Vorschau.
  mAnswer.AddPair('previewWhenUnused', TJSONBool.Create(mSettings.SafeDeletePreviewWhenUnused));
  mAnswer.AddPair('cascadeMode', mSettings.SafeDeleteCascade);
  mAnswer.AddPair('overridesMode', mSettings.SafeDeleteIncludeOverrides);
  Log(Format('Sicher löschen geprüft: %d Verwendungen, %d Überschreibungen', [Count(mAnswer, 'usages'),
    Count(mAnswer, 'overrides')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.SafeDelete(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mChoices: TSafeDeleteChoices;
  mContext: TSafeDeleteContext;
begin
  // Argumente: URI, Position, die Antworten auf die Rückfragen.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mChoices := Default(TSafeDeleteChoices);
  if AArguments.Count > 2 then
  begin
    mChoices := TSafeDeleteChoices.FromJson(AArguments.Items[2]);
  end;
  mDocument := Open(mUri, Settings(mUri).SafeDelete, '"Sicher löschen" ist abgeschaltet (refactoring.safeDelete).');
  mContext := Default(TSafeDeleteContext);
  mContext.Index := Index;
  mContext.Files := ProjectFiles;
  mContext.ReadText := Reader;
  mContext.UsesFor := UsesForFunc(UsesProvider);
  mResolver := NewResolver;
  try
    mAnswer := TLspSafeDelete.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]), mChoices,
      mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Sicher löschen: %d Symbole, %d Dateien', [Number(mAnswer, 'deleted'), Number(mAnswer, 'files')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.ExtractInterfaceActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).ExtractInterface, mDocument) then
  begin
    Result := TLspExtractInterface.Actions(True, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, AUri,
      APosition);
  end;
end;

function TShellStructureRefactorings.ExtractInterfaceContextOf(const AUri: string): TExtractInterfaceContext;
begin
  Result := Default(TExtractInterfaceContext);
  Result.Index := Index;
  Result.ReadText := Reader;
  Result.Exists := Exists;
  Result.HasProject := Project(TDocumentUris.ToPath(AUri), Result.Project);
end;

function TShellStructureRefactorings.ExtractInterfacePrepare(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
begin
  // Argumente: URI, Position.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).ExtractInterface, cExtractInterfaceOff);
  Result := TLspExtractInterface.Prepare(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
    TLspPositions.ReadPosition(AArguments.Items[1]), ExtractInterfaceContextOf(mUri));
end;

function TShellStructureRefactorings.ExtractInterface(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, {name, unit, members}.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).ExtractInterface, cExtractInterfaceOff);
  Require(AArguments, 3, cExtractMissing);
  mResolver := NewResolver;
  try
    mAnswer := TLspExtractInterface.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]),
      AArguments.Items[2], ExtractInterfaceContextOf(mUri));
  finally
    mResolver.Free;
  end;
  Log(Format('Interface herauslösen: %d Methoden', [Number(mAnswer, 'methods')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.ExtractSuperclassActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).ExtractSuperclass, mDocument) then
  begin
    Result := TLspExtractSuperclass.Actions(True, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, AUri,
      APosition);
  end;
end;

function TShellStructureRefactorings.ExtractSuperclassContextOf(const AUri: string): TExtractSuperclassContext;
var
  mSettings: TRefactoringSettings;
begin
  mSettings := Settings(AUri);
  Result := Default(TExtractSuperclassContext);
  Result.Index := Index;
  Result.ReadText := Reader;
  Result.Exists := Exists;
  Result.HasProject := Project(TDocumentUris.ToPath(AUri), Result.Project);
  Result.Target := mSettings.ExtractSuperclassTarget;
  Result.NameSuffix := mSettings.ExtractSuperclassNameSuffix;
  Result.MethodMode := mSettings.ExtractSuperclassMethodMode;
  Result.RaiseVisibility := mSettings.ExtractSuperclassRaiseVisibility;
end;

function TShellStructureRefactorings.ExtractSuperclassPrepare(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
begin
  // Argumente: URI, Position.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).ExtractSuperclass, cExtractSuperclassOff);
  Result := TLspExtractSuperclass.Prepare(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
    TLspPositions.ReadPosition(AArguments.Items[1]), ExtractSuperclassContextOf(mUri));
end;

function TShellStructureRefactorings.ExtractSuperclass(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Position, {name, unit, members, abstract}.
  Require(AArguments, 2, 'Argumente "uri" und "position" fehlen');
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri, Settings(mUri).ExtractSuperclass, cExtractSuperclassOff);
  Require(AArguments, 3, cExtractMissing);
  mResolver := NewResolver;
  try
    mAnswer := TLspExtractSuperclass.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(mUri), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]),
      AArguments.Items[2], ExtractSuperclassContextOf(mUri));
  finally
    mResolver.Free;
  end;
  Log(Format('Basisklasse herauslösen: %d Mitglieder', [Number(mAnswer, 'moved')]));
  Result := mAnswer;
end;

function TShellStructureRefactorings.MoveMemberActions(const AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDocument: ITextDocument;
begin
  Result := nil;
  if TryOpen(AUri, Settings(AUri).MoveMember, mDocument) then
  begin
    Result := TLspMoveMember.Actions(True, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
      TDocumentUris.ToPath(AUri), AUri, APosition, Index);
  end;
end;

function TShellStructureRefactorings.MoveMemberContextOf(const AArguments: TJSONArray;
  out ADocument: ITextDocument): TMoveMemberContext;
var
  mUri: string;
begin
  // Argumente: URI, Position, Richtung, beim Ausführen {members, abstract, targets, option}.
  Require(AArguments, 3, 'Argumente "uri", "position" und Richtung fehlen');
  mUri := AArguments.Items[0].Value;
  ADocument := Open(mUri, Settings(mUri).MoveMember,
    '"Mitglied verschieben" ist abgeschaltet (refactoring.moveMember).');
  Result := Default(TMoveMemberContext);
  Result.Index := Index;
  Result.ReadText := Reader;
end;

function TShellStructureRefactorings.MoveMemberPrepare(const AArguments: TJSONArray): TJSONValue;
var
  mDocument: ITextDocument;
  mContext: TMoveMemberContext;
begin
  mContext := MoveMemberContextOf(AArguments, mDocument);
  Result := TLspMoveMember.Prepare(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
    TDocumentUris.ToPath(AArguments.Items[0].Value), TLspPositions.ReadPosition(AArguments.Items[1]),
    AArguments.Items[2].Value, mContext);
end;

function TShellStructureRefactorings.MoveMember(const AArguments: TJSONArray): TJSONValue;
var
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mContext: TMoveMemberContext;
  mAnswer: TJSONObject;
begin
  mContext := MoveMemberContextOf(AArguments, mDocument);
  Require(AArguments, 4, 'Argument mit Mitgliedern und Zielen fehlt');
  mContext.Files := ProjectFiles;
  mResolver := NewResolver;
  try
    mAnswer := TLspMoveMember.Execute(mResolver, TSyntaxTreeCache.Get(mDocument, nil).Tree,
      TDocumentUris.ToPath(AArguments.Items[0].Value), mDocument.Text, TLspPositions.ReadPosition(AArguments.Items[1]),
      AArguments.Items[2].Value, AArguments.Items[3], mContext);
  finally
    mResolver.Free;
  end;
  Log(Format('Mitglied verschieben: %d Mitglieder', [Number(mAnswer, 'moved')]));
  Result := mAnswer;
end;

end.
