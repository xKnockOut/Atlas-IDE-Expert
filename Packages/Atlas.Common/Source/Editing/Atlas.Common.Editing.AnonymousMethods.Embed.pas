unit Atlas.Common.Editing.AnonymousMethods.Embed;

// Als anonyme Methode einbetten (#680): Eine private Methode, die genau einmal als Wert an ein
// reference to übergeben oder zugewiesen und nie aufgerufen wird, steht an der Übergabe als anonyme
// Methode; die Methode entfällt. Nur im Rumpf einer Methode derselben Klasse und nicht für Methoden,
// die in der Formulardatei stehen. Nicht angeboten, wenn ein Name des Aufrufers einen Namen des Rumpfs
// verdeckt.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.AnonymousMethods.Shared;

type
  /// <summary>„Als anonyme Methode einbetten“: prüft die Methode und ihre Übergabe und baut die Änderungen.
  /// </summary>
  TAnonymousEmbedding = class
  private
    FInput: TAnonymousInput;
    FTokens: TArray<TPascalToken>;
    FCache: TLocalsCache;
    FRoutine: TSyntaxNode;
    FHeader: TSyntaxNode;
    FBody: TSyntaxNode;
    FTypeBody: TSyntaxNode;
    FDeclaration: TSyntaxNode;
    FShort: string;
    FClassName: string;
    FParameters: TArray<TParameterText>;
    /// <summary>Die eine Übergabe der Methode als Wert und die Methode, in der sie steht.</summary>
    FReference: TSyntaxNode;
    FCaller: TSyntaxNode;
    function RoutineReason: string;
    function HeaderReason: string;
    function FindDeclaration: string;
    function DeclarationReason: string;
    function BodyReason: string;
    function ParameterReason: string;
    function IsIgnoredReference(ANode: TSyntaxNode): Boolean;
    function ReferenceProblem(ANode: TSyntaxNode; var AReferences: TArray<TSyntaxNode>): string;
    function CollectReferences(out AReferences: TArray<TSyntaxNode>): string;
    function ReferenceReason: string;
    function TargetReason: string;
    function CallerReason: string;
    function ScopeReason(const AName: string): string;
    function ShadowReason: string;
    function MovedText(const ALineBreak: string): string;
    function Action: TCodeAction;
  public
    constructor Create(const AInput: TAnonymousInput);
    destructor Destroy; override;
    function Run(out AAction: TCodeAction; out AReason: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

/// <summary>Wird der Wert ANode an der Stelle übergeben oder gespeichert (Argument, rechte Seite, Startwert)?
/// </summary>
function IsValueUse(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (TAnonymousSyntax.IsArgument(ANode, mParent) or
    ((mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount > 1) and (mParent[1] = ANode)) or
    ((mParent.Kind = TSyntaxKind.InlineVar) and (mParent[mParent.ChildCount - 1] = ANode)));
end;

/// <summary>Ist ANode der Qualifizierer eines Mitgliedszugriffs mit dem Namen AName (AName.AName)?</summary>
function IsQualifierOf(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (mParent <> nil) and (mParent.Kind = TSyntaxKind.MemberAccess) and (mParent[0] = ANode) and
    SameText(mParent.Name, AName);
end;

/// <summary>Mitgliedszugriff über Self?</summary>
function IsSelfAccess(AAccess: TSyntaxNode): Boolean;
begin
  Result := (AAccess[0].Kind = TSyntaxKind.Identifier) and SameText(AAccess[0].Name, 'Self');
end;

/// <summary>Hat ein Parameter einen Vorgabewert?</summary>
function HasDefaultValue(const AParameters: TArray<TParameterText>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(AParameters) do
  begin
    if Pos('=', AParameters[mIndex].Rest) > 0 then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Lokale Routinen, Typen oder Marken in ARoutine (haben anonyme Methoden nicht)?</summary>
function HasLocalDeclarations(ARoutine: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeSection, TSyntaxKind.LabelSection] then
    begin
      Result := True;
    end;
  end;
end;

{ TAnonymousEmbedding }

constructor TAnonymousEmbedding.Create(const AInput: TAnonymousInput);
begin
  inherited Create;
  FInput := AInput;
end;

destructor TAnonymousEmbedding.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TAnonymousEmbedding.Run(out AAction: TCodeAction; out AReason: string): Boolean;
begin
  AAction := Default(TCodeAction);
  AReason := RoutineReason;
  if AReason = '' then
  begin
    AReason := HeaderReason;
  end;
  if AReason = '' then
  begin
    AReason := DeclarationReason;
  end;
  if AReason = '' then
  begin
    AReason := BodyReason;
  end;
  if AReason = '' then
  begin
    AReason := ParameterReason;
  end;
  if AReason = '' then
  begin
    FCache := TLocalsCache.Create(FInput.Text, FInput.Tree);
    AReason := ReferenceReason;
  end;
  if AReason = '' then
  begin
    AReason := TargetReason;
  end;
  if AReason = '' then
  begin
    AReason := CallerReason;
  end;
  if AReason = '' then
  begin
    AReason := ShadowReason;
  end;
  Result := AReason = '';
  if Result then
  begin
    AAction := Action;
  end;
end;

/// <summary>Methode der Implementierung an der Stelle mit Kopf und Rumpf.</summary>
function TAnonymousEmbedding.RoutineReason: string;
var
  mTree: TSyntaxTree;
  mDeclaration: TSyntaxNode;
begin
  mTree := FInput.Tree;
  if (mTree = nil) or (mTree.Root = nil) then
  begin
    Exit('kein Baum');
  end;
  FTokens := mTree.Tokens;
  FRoutine := TRoutineParts.TopRoutineAt(mTree, TLineTable.Build(FInput.Text).OffsetAt(FInput.Position),
    mDeclaration);
  if (FRoutine = nil) or (FRoutine.Parent = nil) or (FRoutine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
  begin
    Exit('keine Methode der Implementierung');
  end;
  FHeader := TRoutineParts.HeaderOf(FRoutine);
  FBody := TRoutineBody.BodyOf(FRoutine);
  FShort := TRoutineBody.ShortNameOf(FRoutine.Name);
  FClassName := TRoutineBody.QualifierOf(FRoutine.Name);
  if (FHeader = nil) or (FBody = nil) then
  begin
    Result := 'Methode ohne Rumpf';
  end
  else if (FClassName = '') or (Pos('<', FClassName) > 0) or (Pos('.', FClassName) > 0) then
  begin
    Result := 'keine Methode';
  end
  else
  begin
    Result := '';
  end;
end;

function TAnonymousEmbedding.HeaderReason: string;
begin
  Result := '';
  if TRoutineParts.IsClassHeader(FTokens, FHeader) then
  begin
    Result := 'Klassenmethode';
  end
  else if TRoutineParts.HasWord(FTokens, FHeader, ['overload', 'forward', 'external', 'assembler']) then
  begin
    Result := 'nicht unterstützte Form';
  end
  else
  begin
    FTypeBody := TRoutineBody.TypeBody(FInput.Tree.Root, FClassName);
    if FTypeBody = nil then
    begin
      Result := 'Klasse ' + FClassName + ' nicht in der Datei';
    end;
  end;
end;

/// <summary>Genau eine Deklaration der Methode in der Klasse.</summary>
function TAnonymousEmbedding.FindDeclaration: string;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
begin
  Result := '';
  FDeclaration := nil;
  for mIndex := 0 to FTypeBody.ChildCount - 1 do
  begin
    mNode := FTypeBody[mIndex];
    if (mNode.Kind = TSyntaxKind.RoutineHeader) and SameText(mNode.Name, FShort) then
    begin
      if FDeclaration <> nil then
      begin
        Result := 'überladen';
      end;
      FDeclaration := mNode;
    end;
  end;
  if (Result = '') and (FDeclaration = nil) then
  begin
    Result := 'Deklaration fehlt';
  end;
end;

function TAnonymousEmbedding.DeclarationReason: string;
begin
  Result := FindDeclaration;
  if Result <> '' then
  begin
    Exit;
  end;
  if not MatchText(TRoutineBody.VisibilityOf(FTypeBody, FDeclaration), ['private', 'strict private']) then
  begin
    Result := 'nicht privat';
  end
  else if TRoutineParts.HasWord(FTokens, FDeclaration, ['virtual', 'dynamic', 'override', 'abstract', 'message',
    'overload', 'reintroduce', 'final', 'static']) then
  begin
    Result := 'virtuell, Botschaft oder überladen';
  end
  else if Assigned(FInput.Lookup.InForm) and FInput.Lookup.InForm(FShort) then
  begin
    Result := FShort + ' steht in der Formulardatei';
  end;
end;

/// <summary>Anonyme Methoden haben keine lokalen Routinen, Typen oder Marken; inherited bedeutete dort etwas
/// anderes.</summary>
function TAnonymousEmbedding.BodyReason: string;
begin
  if HasLocalDeclarations(FRoutine) then
  begin
    Result := 'lokale Routinen, Typen oder Marken';
  end
  else if TAnonymousSyntax.HasInherited(FTokens, FBody) or TRoutineLocals.HasKind(FBody, TSyntaxKind.WithStatement) then
  begin
    Result := 'inherited oder with';
  end
  else
  begin
    Result := '';
  end;
end;

function TAnonymousEmbedding.ParameterReason: string;
begin
  FParameters := TRoutineParts.ParameterTexts(FInput.Text, FHeader);
  if TAnonymousSyntax.UnreadParameters(FParameters, FHeader) then
  begin
    Result := 'nicht unterstützte Parameter';
  end
  else if HasDefaultValue(FParameters) then
  begin
    Result := 'Parameter mit Vorgabewert';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Bezeichner, der die Methode nicht meint: Qualifizierer von X.X oder verdeckt.</summary>
function TAnonymousEmbedding.IsIgnoredReference(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind <> TSyntaxKind.MemberAccess) and (IsQualifierOf(ANode, FShort) or
    TRoutineParts.Shadowed(FCache, ANode, nil, FShort, False));
end;

/// <summary>Prüft einen Bezug ANode und nimmt ihn in AReferences auf, wenn er die Methode meint.</summary>
function TAnonymousEmbedding.ReferenceProblem(ANode: TSyntaxNode; var AReferences: TArray<TSyntaxNode>): string;
begin
  Result := '';
  if not SameText(ANode.Name, FShort) or IsIgnoredReference(ANode) then
  begin
    Exit;
  end;
  if (ANode.Kind = TSyntaxKind.MemberAccess) and not IsSelfAccess(ANode) then
  begin
    Result := 'über ein anderes Objekt benutzt';
  end
  else if TRoutineBody.Within(ANode, FRoutine) then
  begin
    Result := 'rekursiv';
  end
  else
  begin
    AReferences := AReferences + [ANode];
  end;
end;

function TAnonymousEmbedding.CollectReferences(out AReferences: TArray<TSyntaxNode>): string;
var
  mCollected: TList<TSyntaxNode>;
  mIndex: Integer;
begin
  Result := '';
  AReferences := nil;
  mCollected := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FInput.Tree.Root, TSyntaxKind.Identifier, mCollected);
    TRoutineLocals.CollectKind(FInput.Tree.Root, TSyntaxKind.MemberAccess, mCollected);
    mIndex := 0;
    while (Result = '') and (mIndex < mCollected.Count) do
    begin
      Result := ReferenceProblem(mCollected[mIndex], AReferences);
      Inc(mIndex);
    end;
  finally
    mCollected.Free;
  end;
end;

/// <summary>Bezüge: genau einer außerhalb der Methode, als Wert.</summary>
function TAnonymousEmbedding.ReferenceReason: string;
var
  mReferences: TArray<TSyntaxNode>;
begin
  Result := CollectReferences(mReferences);
  if Result <> '' then
  begin
    Exit;
  end;
  if Length(mReferences) <> 1 then
  begin
    Exit('nicht genau eine Übergabe');
  end;
  FReference := mReferences[0];
  if not IsValueUse(FReference) then
  begin
    Result := 'wird aufgerufen, nicht als Wert übergeben';
  end;
end;

function TAnonymousEmbedding.TargetReason: string;
var
  mKind: TProcTypeKind;
begin
  mKind := TProcTypeKind.Unknown;
  if Assigned(FInput.Lookup.TargetType) then
  begin
    mKind := FInput.Lookup.TargetType(FReference);
  end;
  case mKind of
    TProcTypeKind.MethodPointer:
      Result := 'das Ziel ist ein Methodenzeiger (of object); dort passt keine anonyme Methode';
    TProcTypeKind.Plain:
      Result := 'das Ziel ist ein prozeduraler Typ ohne reference to';
    TProcTypeKind.Unknown:
      Result := 'Zieltyp unbekannt';
  else
    Result := '';
  end;
end;

function TAnonymousEmbedding.CallerReason: string;
begin
  FCaller := TAnonymousSyntax.TopRoutineOf(FReference);
  if (FCaller = nil) or not SameText(TRoutineBody.QualifierOf(FCaller.Name), FClassName) or
    TRoutineParts.IsClassHeader(FTokens, TRoutineParts.HeaderOf(FCaller)) then
  begin
    Result := 'Übergabe nicht in einer Methode derselben Klasse';
  end
  else if TAnonymousSyntax.Inside(FReference, FCaller, TSyntaxKind.WithStatement) then
  begin
    Result := 'Übergabe in with';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Deklariert eine Routine um die Übergabe AName (verdeckt einen Namen des Rumpfs)?</summary>
function TAnonymousEmbedding.ScopeReason(const AName: string): string;
var
  mScope: TSyntaxNode;
begin
  Result := '';
  mScope := FReference.Parent;
  while (Result = '') and (mScope <> nil) do
  begin
    if (mScope.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) and FCache.Declares(mScope, AName,
      FReference.StartOffset) then
    begin
      Result := mScope.Name + ' verdeckt ' + AName;
    end;
    mScope := mScope.Parent;
  end;
end;

/// <summary>Namen des Rumpfs, die an der Übergabe etwas anderes bedeuten.</summary>
function TAnonymousEmbedding.ShadowReason: string;
var
  mCollected: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mCollected := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FRoutine, TSyntaxKind.Identifier, mCollected);
    TRoutineLocals.CollectKind(FRoutine, TSyntaxKind.TypeReference, mCollected);
    mIndex := 0;
    while (Result = '') and (mIndex < mCollected.Count) do
    begin
      mNode := mCollected[mIndex];
      if not TRoutineParts.Shadowed(FCache, mNode, FRoutine, mNode.Name, True) then
      begin
        Result := ScopeReason(mNode.Name);
      end;
      Inc(mIndex);
    end;
  finally
    mCollected.Free;
  end;
end;

/// <summary>Rumpf ab var, const bzw. begin, eingerückt unter die Zeile der Übergabe.</summary>
function TAnonymousEmbedding.MovedText(const ALineBreak: string): string;
var
  mStart, mIndex: Integer;
  mChild: TSyntaxNode;
  mIndent: string;
begin
  mStart := FBody.StartOffset;
  for mIndex := 0 to FRoutine.ChildCount - 1 do
  begin
    mChild := FRoutine[mIndex];
    if (mChild.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection]) and (mChild.StartOffset < mStart) then
    begin
      mStart := mChild.StartOffset;
    end;
  end;
  mIndent := TTextLines.IndentOf(FInput.Text, FReference.StartPos.Line) + TRoutineBody.IndentUnit(FInput.Style);
  Result := TRoutineBody.Reindent(Copy(FInput.Text, mStart + 1, FBody.EndOffset - mStart),
    TTextLines.IndentOf(FInput.Text, FRoutine.StartPos.Line), mIndent, ALineBreak);
end;

function TAnonymousEmbedding.Action: TCodeAction;
var
  mLineBreak, mHead: string;
  mLines: TArray<string>;
  mFirstLine, mRemoveEnd: Integer;
  mEdits: TArray<TTextEdit>;
begin
  mLineBreak := TTextLines.LineBreakOf(FInput.Text);
  mLines := TTextLines.SplitLines(FInput.Text);
  mHead := TRoutineParts.AnonymousHead(FInput.Text, FHeader, FParameters);
  mFirstLine := TRoutineBody.RoutineInsertLine(FInput.Text, FRoutine);
  mRemoveEnd := FRoutine.EndPos.Line + 1;
  if TRoutineParts.LineIsBlank(mLines, mFirstLine - 1) and TRoutineParts.LineIsBlank(mLines, mRemoveEnd) then
  begin
    Inc(mRemoveEnd);
  end;
  mEdits := nil;
  mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mFirstLine, 0, mRemoveEnd, 0), '')];
  mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(FDeclaration.StartPos.Line, 0,
    FDeclaration.EndPos.Line + 1, 0), '')];
  mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(FReference.StartPos, FReference.EndPos), mHead +
    mLineBreak + MovedText(mLineBreak))];
  Result := Default(TCodeAction);
  Result.Title := cEmbedTitle;
  Result.Kind := RewriteKind;
  Result.Edits := mEdits;
  Result.Preview := Format('%s steht an der Übergabe in %s als anonyme Methode; die Methode entfällt.',
    [FShort, FCaller.Name]) + mLineBreak + mHead;
end;

end.
