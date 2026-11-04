unit Atlas.Common.Lsp.TypeAlias;

// Typ-Alias einführen und auflösen über das Protokoll (#681):
//   - Code-Aktionen auf einem Typausdruck, nur mit refactoring.typeAlias:
//     „Typ-Alias einführen (Ausdruck)“ mit der Reichweite aus
//     refactoring.typeAliasScope, für den äußeren Ausdruck dazu die beiden
//     anderen Reichweiten. Jede trägt den Client-Befehl atlas.typeAlias mit
//     [uri, position, vorgeschlagener Name, Reichweite]; das Plugin fragt den
//     Namen ab. Mit offenen generischen Parametern ist die Aktion
//     abgeschaltet und nennt den Grund.
//   - Auf dem Namen eines Alias X = Y: „Alias auflösen (X)“ mit dem
//     Client-Befehl atlas.inlineTypeAlias [uri, position].
//   - Befehle atlas.server.typeAlias [uri, position, name, reichweite] und
//     atlas.server.inlineTypeAlias [uri, position]: {"edit": WorkspaceEdit,
//     "warnings": [...], "places": n, "files": n, "preview": Text}; geht es
//     nicht, ein Fehler mit Grund.
// Gleichheit über die Namensauflösung: TList<TKunde> und
// System.Generics.Collections.TList<Kunden.TKunde> sind derselbe Ausdruck.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TypeAlias,
  Atlas.Common.Lsp.References;

type
  TTypeAliasContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts: andere Units für die Reichweite „Projekt“, Verwendungen beim Auflösen.
    /// </summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>Name des neuen Alias (nur Execute).</summary>
    Name: string;
    /// <summary>Reichweite wie refactoring.typeAliasScope (nur Execute).</summary>
    Scope: string;
  end;

  TLspTypeAlias = class
  public const
    ClientCommand = 'atlas.typeAlias';
    ApplyCommand = 'atlas.server.typeAlias';
    InlineClientCommand = 'atlas.inlineTypeAlias';
    InlineApplyCommand = 'atlas.server.inlineTypeAlias';
    IntroduceKind = 'refactor.extract';
    InlineKind = 'refactor.inline';
    AnnotationId = 'typeAlias';
  public
    /// <summary>Schlüssel, vergebene Namen und Units über AResolver; der Baum dient als Rückfall.</summary>
    class function Lookup(AResolver: TNameResolver): TTypeAliasLookup; static;
    /// <summary>Die Code-Aktionen an APosition; ADefaultScope aus refactoring.typeAliasScope. Der Aufrufer
    /// übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      ADefaultScope: TTypeAliasScope; const ALookup: TTypeAliasLookup): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.typeAlias; EJsonRpcError mit dem Grund, wenn es nicht geht. Der Aufrufer
    /// übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TTypeAliasContext): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.inlineTypeAlias; wie Execute.</summary>
    class function ExecuteInline(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TTypeAliasContext): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Text.Lines;

const
  /// <summary>Längere Ausdrücke kürzt der Titel der Aktion.</summary>
  TitleLength = 40;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function NameParts(ANode: TSyntaxNode): TArray<string>;
begin
  Result := ANode.Name.Split(['.']);
end;

function ResolveNode(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  ANode: TSyntaxNode): TResolvedSymbol;
begin
  Result := AResolver.ResolveChain(ATree, AFileName, NameParts(ANode), ANode.StartOffset);
end;

// Jede Methodenreferenz in einer eigenen Routine: Teilen sie sich den Rahmen, hält er sich selbst fest.

function KeyFunc(AResolver: TNameResolver): TTypeKeyFunc;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode): string
    var
      Resolved: TResolvedSymbol;
    begin
      Result := '';
      Resolved := ResolveNode(AResolver, ATree, AFileName, ANode);
      if Resolved.Kind = TResolvedKind.Symbol then
      begin
        if Resolved.Builtin or (Resolved.UnitName = '') then
        begin
          Result := LowerCase(Resolved.Name);
        end
        else
        begin
          Result := LowerCase(Resolved.UnitName + '.' + Resolved.Name);
        end;
      end;
    end;
end;

function NameTakenFunc(AResolver: TNameResolver; const AFallback: TTypeNameTakenFunc): TTypeNameTakenFunc;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName, AName: string; AOffset: Integer): Boolean
    begin
      Result := AFallback(ATree, AFileName, AName, AOffset) or
        (AResolver.ResolveChain(ATree, AFileName, [AName], AOffset).Kind <> TResolvedKind.None);
    end;
end;

function UnitFunc(AResolver: TNameResolver): TTypeUnitFunc;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode; out AImplementation: Boolean): string
    var
      Resolved: TResolvedSymbol;
    begin
      Result := '';
      AImplementation := False;
      Resolved := ResolveNode(AResolver, ATree, AFileName, ANode);
      case Resolved.Kind of
        TResolvedKind.Symbol:
          if not Resolved.Builtin then
          begin
            Result := Resolved.UnitName;
            AImplementation := not Resolved.InInterface and
              SameText(Resolved.UnitName, TUsesClauses.OwnName(ATree.Tokens));
          end;
        // Typen in Routinen sieht keine andere Unit.
        TResolvedKind.Local:
          AImplementation := True;
        TResolvedKind.None, TResolvedKind.UnitName: ;
      end;
    end;
end;

class function TLspTypeAlias.Lookup(AResolver: TNameResolver): TTypeAliasLookup;
begin
  Result := TTypeAliasLookup.FromTree;
  Result.Key := KeyFunc(AResolver);
  Result.NameTaken := NameTakenFunc(AResolver, Result.NameTaken);
  Result.UnitOf := UnitFunc(AResolver);
end;

function Shortened(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  if Length(Result) > TitleLength then
  begin
    Result := Copy(Result, 1, TitleLength - 1) + '…';
  end;
end;

function NewAction(const ATitle, AKind: string; AArguments: TJSONArray; const ACommand: string): TJSONObject;
var
  Command: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', AKind);
  if AArguments = nil then
  begin
    Exit;
  end;
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', ACommand);
  Command.AddPair('arguments', AArguments);
  Result.AddPair('command', Command);
end;

function IntroduceAction(const ATitle, AUri: string; const ATarget: TTypeAliasTarget;
  AScope: TTypeAliasScope): TJSONObject;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(ATarget.Range.StartPos));
  Arguments.Add(ATarget.Suggestion);
  Arguments.Add(TTypeAlias.ScopeName(AScope));
  Result := NewAction(Format(ATitle, [Shortened(ATarget.TypeText)]), TLspTypeAlias.IntroduceKind, Arguments,
    TLspTypeAlias.ClientCommand);
end;

function ScopeTitle(AScope: TTypeAliasScope): string;
begin
  case AScope of
    TTypeAliasScope.Here:
      Result := TTypeAlias.HereTitle;
    TTypeAliasScope.Project:
      Result := TTypeAlias.ProjectTitle;
  else
    Result := TTypeAlias.UnitTitle;
  end;
end;

class function TLspTypeAlias.Actions(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
  ADefaultScope: TTypeAliasScope; const ALookup: TTypeAliasLookup): TArray<TJSONObject>;
var
  Targets: TArray<TTypeAliasTarget>;
  Index: Integer;
  Scope: TTypeAliasScope;
  Action: TJSONObject;
  Inline_: TInlineAliasTarget;
  Reason: string;
  Arguments: TJSONArray;
begin
  Result := nil;
  Targets := TTypeAlias.Targets(AText, ATree, TDocumentUris.ToPath(AUri), APosition, ALookup);
  for Index := 0 to High(Targets) do
  begin
    if Targets[Index].OpenParams <> '' then
    begin
      Action := NewAction(Format(TTypeAlias.IntroduceTitle, [Shortened(Targets[Index].TypeText)]), IntroduceKind,
        nil, '');
      Action.AddPair('disabled', TJSONObject.Create(TJSONPair.Create('reason',
        Format(TTypeAlias.OpenParamsReason, [Targets[Index].OpenParams]))));
      Result := Result + [Action];
      Continue;
    end;
    Result := Result + [IntroduceAction(TTypeAlias.IntroduceTitle, AUri, Targets[Index], ADefaultScope)];
    // Die übrigen Reichweiten nur für den äußeren Ausdruck, sonst wird die Liste lang.
    if Index = 0 then
    begin
      for Scope := Low(TTypeAliasScope) to High(TTypeAliasScope) do
      begin
        if Scope <> ADefaultScope then
        begin
          Result := Result + [IntroduceAction(ScopeTitle(Scope), AUri, Targets[Index], Scope)];
        end;
      end;
    end;
  end;
  if TTypeAlias.InlineTarget(AText, ATree, APosition, Inline_, Reason) then
  begin
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(Inline_.NamePosition));
    Result := Result + [NewAction(Format(TTypeAlias.InlineTitle, [Inline_.Name]), InlineKind, Arguments,
      InlineClientCommand)];
  end;
end;

function EditsJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Document, Item: TJSONObject;
  Items: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Items := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Item.AddPair('annotationId', TLspTypeAlias.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

function AnswerJson(const AResult: TTypeAliasResult; const ALabel: string): TJSONObject;
var
  Item: TTypeAliasFileEdits;
  Changes, Warnings: TJSONArray;
  Edit, Annotation, Annotations: TJSONObject;
  Warning: string;
begin
  Changes := TJSONArray.Create;
  for Item in AResult.Files do
  begin
    Changes.AddElement(EditsJson(TDocumentUris.FromPath(Item.FileName), Item.Edits));
  end;
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', ALabel);
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%d Stellen in %d Dateien', [AResult.Places, Length(AResult.Files)]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(TLspTypeAlias.AnnotationId, Annotation);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Edit.AddPair('changeAnnotations', Annotations);
  Warnings := TJSONArray.Create;
  for Warning in AResult.Warnings do
  begin
    Warnings.Add(Warning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(AResult.Places));
  Result.AddPair('files', TJSONNumber.Create(Length(AResult.Files)));
  Result.AddPair('preview', AResult.Preview);
end;

type
  /// <summary>Gelesene andere Datei; gibt den Baum frei.</summary>
  TAliasFile = class
  public
    Source: TTypeAliasSource;
    Lines: TLineTable;
    destructor Destroy; override;
  end;

destructor TAliasFile.Destroy;
begin
  Source.Tree.Free;
  inherited;
end;

function SourcesOf(const AFiles: TArray<TAliasFile>): TArray<TTypeAliasSource>;
var
  AliasFile: TAliasFile;
begin
  Result := nil;
  for AliasFile in AFiles do
  begin
    Result := Result + [AliasFile.Source];
  end;
end;

function FileOf(const AFileName, AText: string): TAliasFile;
begin
  Result := TAliasFile.Create;
  Result.Lines := TLineTable.Build(AText);
  Result.Source := TTypeAliasSource.Create(AFileName, AText, TSyntaxTreeCache.Parse(AText));
end;

function ReadFile(const AFileName: string; const AContext: TTypeAliasContext): TAliasFile;
var
  Text: string;
begin
  if not Assigned(AContext.ReadText) or not AContext.ReadText(AFileName, Text) then
  begin
    raise Fail(Format('%s lässt sich nicht lesen', [ExtractFileName(AFileName)]));
  end;
  Result := FileOf(AFileName, Text);
end;

procedure PinAll(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AFiles: TArray<TAliasFile>);
var
  AliasFile: TAliasFile;
begin
  AResolver.PinTree(ATree, AFileName);
  for AliasFile in AFiles do
  begin
    AResolver.PinTree(AliasFile.Source.Tree, AliasFile.Source.FileName);
  end;
end;

procedure UnpinAll(AResolver: TNameResolver; const AFiles: TArray<TAliasFile>);
var
  Index: Integer;
begin
  for Index := 0 to Length(AFiles) do
  begin
    AResolver.UnpinTree;
  end;
end;

procedure FreeAll(const AFiles: TArray<TAliasFile>);
var
  AliasFile: TAliasFile;
begin
  for AliasFile in AFiles do
  begin
    AliasFile.Free;
  end;
end;

/// <summary>Text der anderen .pas-Datei AFileName, wenn sie die eigene Unit AOwnName nennt.</summary>
function NamesOwnUnit(const AFileName, AOwnFile, AOwnName: string; const AContext: TTypeAliasContext;
  out AText: string): Boolean;
begin
  AText := '';
  Result := not SameText(AFileName, AOwnFile) and SameText(ExtractFileExt(AFileName), '.pas') and
    (AOwnName <> '') and Assigned(AContext.ReadText);
  Result := Result and AContext.ReadText(AFileName, AText) and ContainsText(AText, AOwnName);
end;

/// <summary>Im Projekt nur Units, die die eigene überhaupt nennen; ob sie sie an der Stelle sehen, prüft der
/// Kern.</summary>
function ProjectFiles(ATree: TSyntaxTree; const AFileName: string;
  const AContext: TTypeAliasContext): TArray<TAliasFile>;
var
  mFileName, mOwnName, mText: string;
begin
  Result := nil;
  mOwnName := TUsesClauses.OwnName(ATree.Tokens);
  for mFileName in AContext.Files do
  begin
    if NamesOwnUnit(mFileName, AFileName, mOwnName, AContext, mText) then
    begin
      Result := Result + [FileOf(mFileName, mText)];
    end;
  end;
end;

class function TLspTypeAlias.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TTypeAliasContext): TJSONObject;
var
  mScope: TTypeAliasScope;
  mFiles: TArray<TAliasFile>;
  mReason: string;
  mOutcome: TTypeAliasResult;
begin
  if not TTypeAlias.ScopeOf(AContext.Scope, mScope) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Reichweite "%s"',
      [AContext.Scope]));
  end;
  mFiles := nil;
  try
    if mScope = TTypeAliasScope.Project then
    begin
      mFiles := ProjectFiles(ATree, AFileName, AContext);
    end;
    PinAll(AResolver, ATree, AFileName, mFiles);
    try
      if not TTypeAlias.Introduce(TTypeAliasSource.Create(AFileName, AText, ATree), SourcesOf(mFiles),
        TTypeAliasRequest.Create(APosition, Trim(AContext.Name), mScope, Lookup(AResolver)), mOutcome, mReason) then
      begin
        raise Fail('Typ-Alias geht nicht: ' + mReason);
      end;
    finally
      UnpinAll(AResolver, mFiles);
    end;
  finally
    FreeAll(mFiles);
  end;
  Result := AnswerJson(mOutcome, Format(TTypeAlias.IntroduceTitle, [Trim(AContext.Name)]));
end;

/// <summary>EJsonRpcError, wenn der Alias ATargetName in einem Formular steht.</summary>
procedure CheckNoForms(const ALocations: TArray<TReferenceLocation>; const ATargetName: string);
var
  mLocation: TReferenceLocation;
begin
  for mLocation in ALocations do
  begin
    if MatchText(ExtractFileExt(mLocation.FileName), ['.dfm', '.fmx']) then
    begin
      raise Fail(Format('Alias auflösen geht nicht: %s steht in %s', [ATargetName,
        ExtractFileName(mLocation.FileName)]));
    end;
  end;
end;

/// <summary>Gelesene Datei AFileName aus AFiles; fehlt sie, wird sie gelesen und angehängt.</summary>
function FileFor(var AFiles: TArray<TAliasFile>; const AFileName: string;
  const AContext: TTypeAliasContext): TAliasFile;
var
  mAliasFile: TAliasFile;
begin
  for mAliasFile in AFiles do
  begin
    if SameText(mAliasFile.Source.FileName, AFileName) then
    begin
      Exit(mAliasFile);
    end;
  end;
  Result := ReadFile(AFileName, AContext);
  AFiles := AFiles + [Result];
end;

class function TLspTypeAlias.ExecuteInline(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; const AContext: TTypeAliasContext): TJSONObject;
var
  mTarget: TInlineAliasTarget;
  mReason: string;
  mLocations: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
  mFiles: TArray<TAliasFile>;
  mFound: TAliasFile;
  mDeclaring: TTypeAliasSource;
  mLines: TLineTable;
  mOutcome: TTypeAliasResult;
begin
  if not TTypeAlias.InlineTarget(AText, ATree, APosition, mTarget, mReason) then
  begin
    raise Fail('Alias auflösen geht nicht: ' + mReason);
  end;
  mLocations := TLspReferences.Find(AResolver, AContext.Index, ATree, TReferenceSearch.Create(AFileName,
    mTarget.NamePosition, False, AContext.Files, AContext.ReadText));
  CheckNoForms(mLocations, mTarget.Name);
  mFiles := nil;
  try
    mDeclaring := TTypeAliasSource.Create(AFileName, AText, ATree);
    mLines := TLineTable.Build(AText);
    for mLocation in mLocations do
    begin
      if SameText(mLocation.FileName, AFileName) then
      begin
        mDeclaring.Offsets := mDeclaring.Offsets + [mLines.OffsetAt(mLocation.Range.StartPos)];
      end
      else
      begin
        mFound := FileFor(mFiles, mLocation.FileName, AContext);
        mFound.Source.Offsets := mFound.Source.Offsets + [mFound.Lines.OffsetAt(mLocation.Range.StartPos)];
      end;
    end;
    PinAll(AResolver, ATree, AFileName, mFiles);
    try
      if not TTypeAlias.InlineAlias(mDeclaring, SourcesOf(mFiles), APosition, Lookup(AResolver), mOutcome,
        mReason) then
      begin
        raise Fail('Alias auflösen geht nicht: ' + mReason);
      end;
    finally
      UnpinAll(AResolver, mFiles);
    end;
  finally
    FreeAll(mFiles);
  end;
  Result := AnswerJson(mOutcome, Format(TTypeAlias.InlineTitle, [mTarget.Name]));
end;

end.
