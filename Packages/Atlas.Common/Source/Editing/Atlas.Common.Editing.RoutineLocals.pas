unit Atlas.Common.Editing.RoutineLocals;

// Lokale Namen einer Routine und ihre Zugriffe, gemeinsam für Extrahieren
// (#50) und Einbetten (#103), auch für anonyme Methoden (#680): Parameter,
// var- und const-Abschnitt, Inline-Variablen und for var mit ihrem
// Gültigkeitsbereich; Zugriff eines
// Bezeichners (Lesen, Schreiben, beides) und das Entfernen von Namen aus
// einem var-Eintrag.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow.Signatures;

type
{$SCOPEDENUMS ON}
  TRoutineLocalKind = (Parameter, Variable, InlineVariable, LoopVariable, Constant);
  TLocalAccess = (Read, Write, ReadWrite);
{$SCOPEDENUMS OFF}

  TRoutineLocal = record
    Name: string;
    TypeText: string;
    Kind: TRoutineLocalKind;
    Decl: TSyntaxNode;
    /// <summary>Ausdruck, aus dem der Typ folgt (Inline-Variable ohne Typ, Laufvariable).</summary>
    Initializer: TSyntaxNode;
    /// <summary>Anweisung, vor der die Inline-Variable bzw. Laufvariable steht (für die Typabfrage).</summary>
    Statement: TSyntaxNode;
    ScopeStart: Integer;
    ScopeEnd: Integer;
  end;

  TRoutineLocals = class
  public const
    cTypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.PointerType,
      TSyntaxKind.ProcedureType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType, TSyntaxKind.EnumType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassOfType];
  public
    /// <summary>Alle Knoten der Art AKind unter ANode (einschließlich) in Baumreihenfolge.</summary>
    class procedure CollectKind(ANode: TSyntaxNode; AKind: TSyntaxKind; AList: TList<TSyntaxNode>); static;
    /// <summary>Kommt unter ANode (einschließlich) ein Knoten der Art AKind vor?</summary>
    class function HasKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean; static;
    /// <summary>for var I := … bzw. for var X in …</summary>
    class function IsInlineFor(const ATokens: TArray<TPascalToken>; AFor: TSyntaxNode): Boolean; static;
    /// <summary>Typ als Text, wenn das erste Kind ein Typ ist; sonst ''.</summary>
    class function TypeChildText(const AText: string; ANode: TSyntaxNode): string; static;
    /// <summary>Lokale Namen der Routine (auch einer anonymen Methode): Parameter, var- und const-Abschnitt,
    /// Inline-Variablen, for var; leer ohne Rumpf.</summary>
    class function Collect(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
      static;
    /// <summary>Lokaler Name AName, der an AOffset gilt (innerster zuerst); -1 ohne.</summary>
    class function IndexOf(const ALocals: TArray<TRoutineLocal>; const AName: string; AOffset: Integer): Integer;
      static;
    /// <summary>Zugriff des Bezeichners ANode: Ziel einer Zuweisung, Teilzuweisung, var-Argument oder Lesen.</summary>
    class function AccessOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TLocalAccess; static;
    /// <summary>Bearbeitungen, die die Namen ARemoved aus dem var-Eintrag ADecl entfernen (bei letztem Namen die
    /// Zeile, beim letzten Eintrag auch "var").</summary>
    class procedure RemoveVariables(ATree: TSyntaxTree; ADecl: TSyntaxNode;
      const ARemoved: TArray<string>; var AEdits: TArray<TTextEdit>); static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Editing.RoutineBody;

class procedure TRoutineLocals.CollectKind(ANode: TSyntaxNode; AKind: TSyntaxKind; AList: TList<TSyntaxNode>);
var
  mKind: TSyntaxKind;
  mList: TList<TSyntaxNode>;
begin
  mKind := AKind;
  mList := AList;
  // Walk statt Rekursion.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = mKind then
      begin
        mList.Add(AChild);
      end;
      Result := True;
    end);
end;

class function TRoutineLocals.HasKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mKind: TSyntaxKind;
begin
  mKind := AKind;
  // Search statt Rekursion.
  Result := ANode.Search(
    function(AChild: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if AChild.Kind = mKind then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

class function TRoutineLocals.IsInlineFor(const ATokens: TArray<TPascalToken>; AFor: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.NextToken(ATokens, TRoutineBody.TokenAt(ATokens, AFor.StartOffset));
  Result := (mIndex <= High(ATokens)) and ATokens[mIndex].IsKeyword('var');
end;

class function TRoutineLocals.TypeChildText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.ChildCount > 0) and (ANode[0].Kind in TRoutineLocals.cTypeKinds) then
  begin
    Result := TRoutineBody.TextOf(AText, ANode[0]);
  end;
end;

type
  /// <summary>Sammelt die lokalen Namen einer Routine mit Rumpf ABody.</summary>
  TLocalCollector = record
    Text: string;
    Body: TSyntaxNode;
    List: TList<TRoutineLocal>;
    /// <summary>Lokaler Name mit dem Rumpf als Gültigkeitsbereich.</summary>
    function Local(const AName: string; AKind: TRoutineLocalKind; ADecl: TSyntaxNode): TRoutineLocal;
    /// <summary>Alle Namen von ADecl ("A, B: Integer") mit deren Typ.</summary>
    procedure AddDeclared(ADecl: TSyntaxNode; AKind: TRoutineLocalKind);
    /// <summary>Parameter der Routine bzw. der anonymen Methode.</summary>
    procedure AddParameters(ARoutine: TSyntaxNode);
    /// <summary>Einträge der var- und const-Abschnitte vor dem Rumpf.</summary>
    procedure AddSections(ARoutine: TSyntaxNode);
    /// <summary>Inline-Variablen und -Konstanten im Rumpf.</summary>
    procedure AddInline;
    /// <summary>Laufvariablen aus for var im Rumpf.</summary>
    procedure AddLoops(const ATokens: TArray<TPascalToken>);
  end;

function TLocalCollector.Local(const AName: string; AKind: TRoutineLocalKind; ADecl: TSyntaxNode): TRoutineLocal;
begin
  Result := Default(TRoutineLocal);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Decl := ADecl;
  Result.ScopeStart := Body.StartOffset;
  Result.ScopeEnd := Body.EndOffset;
end;

procedure TLocalCollector.AddDeclared(ADecl: TSyntaxNode; AKind: TRoutineLocalKind);
var
  mName: string;
  mLocal: TRoutineLocal;
begin
  for mName in ADecl.Name.Split([',']) do
  begin
    mLocal := Local(Trim(mName), AKind, ADecl);
    mLocal.TypeText := TRoutineLocals.TypeChildText(Text, ADecl);
    List.Add(mLocal);
  end;
end;

procedure TLocalCollector.AddParameters(ARoutine: TSyntaxNode);
var
  mHeader, mParameters: TSyntaxNode;
  mIndex: Integer;
begin
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mParameters := nil;
  if mHeader <> nil then
  begin
    mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
  end
  else if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
  begin
    // Die anonyme Methode trägt ihre Parameter selbst (#680).
    mParameters := ARoutine.FindChild(TSyntaxKind.Parameters);
  end;
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    // "A, B: Integer" ist ein Knoten mit beiden Namen.
    AddDeclared(mParameters[mIndex], TRoutineLocalKind.Parameter);
  end;
end;

procedure TLocalCollector.AddSections(ARoutine: TSyntaxNode);
var
  mSection: TSyntaxNode;
  mIndex, mInner: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    for mInner := 0 to mSection.ChildCount - 1 do
    begin
      if mSection.Kind = TSyntaxKind.VarSection then
      begin
        AddDeclared(mSection[mInner], TRoutineLocalKind.Variable);
      end
      else if mSection.Kind = TSyntaxKind.ConstSection then
      begin
        List.Add(Local(mSection[mInner].Name, TRoutineLocalKind.Constant, mSection[mInner]));
      end;
    end;
  end;
end;

procedure TLocalCollector.AddInline;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mName: string;
  mLocal: TRoutineLocal;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.InlineVar, mNodes);
    TRoutineLocals.CollectKind(Body, TSyntaxKind.InlineConst, mNodes);
    for mNode in mNodes do
    begin
      for mName in mNode.Name.Split([',']) do
      begin
        mLocal := Local(Trim(mName), TRoutineLocalKind.InlineVariable, mNode);
        mLocal.Statement := mNode;
        mLocal.TypeText := TRoutineLocals.TypeChildText(Text, mNode);
        if (mLocal.TypeText = '') and (mNode.ChildCount > 0) then
        begin
          mLocal.Initializer := mNode[mNode.ChildCount - 1];
        end;
        mLocal.ScopeStart := mNode.StartOffset;
        mLocal.ScopeEnd := mNode.Parent.EndOffset;
        List.Add(mLocal);
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

procedure TLocalCollector.AddLoops(const ATokens: TArray<TPascalToken>);
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mLocal: TRoutineLocal;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.ForStatement, mNodes);
    TRoutineLocals.CollectKind(Body, TSyntaxKind.ForInStatement, mNodes);
    for mNode in mNodes do
    begin
      if not TRoutineLocals.IsInlineFor(ATokens, mNode) then
      begin
        Continue;
      end;
      mLocal := Local(mNode.Name, TRoutineLocalKind.LoopVariable, mNode);
      mLocal.Statement := mNode;
      if mNode.ChildCount > 0 then
      begin
        mLocal.Initializer := mNode[0];
      end;
      mLocal.ScopeStart := mNode.StartOffset;
      mLocal.ScopeEnd := mNode.EndOffset;
      List.Add(mLocal);
    end;
  finally
    mNodes.Free;
  end;
end;

class function TRoutineLocals.Collect(const AText: string; ATree: TSyntaxTree;
  ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
var
  mCollector: TLocalCollector;
begin
  Result := nil;
  mCollector := Default(TLocalCollector);
  mCollector.Body := TRoutineBody.BodyOf(ARoutine);
  if mCollector.Body = nil then
  begin
    Exit;
  end;
  mCollector.Text := AText;
  mCollector.List := TList<TRoutineLocal>.Create;
  try
    mCollector.AddParameters(ARoutine);
    mCollector.AddSections(ARoutine);
    mCollector.AddInline;
    mCollector.AddLoops(ATree.Tokens);
    Result := mCollector.List.ToArray;
  finally
    mCollector.List.Free;
  end;
end;

/// <summary>Gilt ALocal an AOffset?</summary>
function Covers(const ALocal: TRoutineLocal; AOffset: Integer): Boolean;
begin
  Result := (ALocal.ScopeStart <= AOffset) and (AOffset <= ALocal.ScopeEnd);
end;

class function TRoutineLocals.IndexOf(const ALocals: TArray<TRoutineLocal>; const AName: string;
  AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ALocals) do
  begin
    if SameText(ALocals[mIndex].Name, AName) and Covers(ALocals[mIndex], AOffset) and
      ((Result < 0) or (ALocals[mIndex].ScopeStart >= ALocals[Result].ScopeStart)) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Ist ANode das Ziel einer Zuweisung?</summary>
function IsAssignTarget(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and (ANode.Parent[0] = ANode);
end;

/// <summary>Ist ANode Teil eines Ziels (A.Feld := …, A[I] := …)?</summary>
function IsPartOfTarget(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode;
  while (mNode.Parent <> nil) and (mNode.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (mNode.Parent[0] = mNode) do
  begin
    mNode := mNode.Parent;
  end;
  Result := (mNode <> ANode) and IsAssignTarget(mNode);
end;

/// <summary>Zugriff des Arguments ANode im Aufruf ACall: var/out oder unbekannte Signatur ändern womöglich.
/// </summary>
function ArgumentAccess(ACall, ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TLocalAccess;
var
  mIndex: Integer;
  mMode: TFlowArgumentMode;
begin
  mIndex := 0;
  while (mIndex < ACall.ChildCount) and (ACall[mIndex] <> ANode) do
  begin
    Inc(mIndex);
  end;
  mMode := TFlowArgumentMode.Unknown;
  if Assigned(ALookup) then
  begin
    mMode := ALookup(ACall, mIndex - 1);
  end;
  Result := TLocalAccess.Read;
  if mMode <> TFlowArgumentMode.Value then
  begin
    Result := TLocalAccess.ReadWrite;
  end;
end;

class function TRoutineLocals.AccessOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TLocalAccess;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Result := TLocalAccess.Read;
  end
  else if IsAssignTarget(ANode) then
  begin
    Result := TLocalAccess.Write;
  end
  else if (mParent.Kind = TSyntaxKind.AddressOf) or IsPartOfTarget(ANode) then
  begin
    Result := TLocalAccess.ReadWrite;
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] <> ANode) then
  begin
    Result := ArgumentAccess(mParent, ANode, ALookup);
  end
  else
  begin
    Result := TLocalAccess.Read;
  end;
end;

/// <summary>Namen aus ANames (ohne Leerraum), die nicht in ARemoved stehen.</summary>
function KeptNames(const ANames, ARemoved: TArray<string>): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    if IndexText(Trim(mName), ARemoved) < 0 then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

/// <summary>Ersetzt die Namen vor dem ":" von ADecl durch AKept; False ohne ":".</summary>
function KeptNamesEdit(ATree: TSyntaxTree; ADecl: TSyntaxNode; const AKept: TArray<string>;
  out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mColon: Integer;
begin
  mTokens := ATree.Tokens;
  mColon := TRoutineBody.TokenAt(mTokens, ADecl.StartOffset);
  while (mColon <= High(mTokens)) and not mTokens[mColon].IsSymbol(':') do
  begin
    Inc(mColon);
  end;
  Result := mColon <= High(mTokens);
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ADecl.StartPos, mTokens[mColon].StartPos), string.Join(', ', AKept));
  end
  else
  begin
    AEdit := Default(TTextEdit);
  end;
end;

/// <summary>Verschwinden alle Namen der übrigen Einträge von ASection außer ADecl?</summary>
function OthersRemoved(ASection, ADecl: TSyntaxNode; const ARemoved: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if (ASection[mIndex] <> ADecl) and (KeptNames(ASection[mIndex].Name.Split([',']), ARemoved) <> nil) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Liegt ALine in den Zeilen von ANode?</summary>
function InLines(ALine: Integer; ANode: TSyntaxNode): Boolean;
begin
  Result := (ALine >= ANode.StartPos.Line) and (ALine <= ANode.EndPos.Line);
end;

/// <summary>Steht AToken (kein Kommentar) auf den Zeilen von ADecl, aber außerhalb davon?</summary>
function SharesLine(const AToken: TPascalToken; ADecl: TSyntaxNode): Boolean;
begin
  Result := (AToken.Kind <> TPascalTokenKind.Comment) and (AToken.Text <> '') and
    InLines(AToken.StartPos.Line, ADecl) and ((AToken.Offset < ADecl.StartOffset) or
    (AToken.Offset >= ADecl.EndOffset));
end;

/// <summary>Entfernt den Eintrag ADecl: die ganzen Zeilen, oder nur ihn, wenn dort weiterer Code steht ("var"
/// davor, ein Eintrag dahinter, #644).</summary>
function EntryRemoval(ATree: TSyntaxTree; ADecl: TSyntaxNode): TTextEdit;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mNext: Integer;
  mShared: Boolean;
begin
  mTokens := ATree.Tokens;
  mNext := -1;
  mShared := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if not SharesLine(mTokens[mIndex], ADecl) then
    begin
      Continue;
    end;
    mShared := True;
    if (mNext < 0) and (mTokens[mIndex].Offset >= ADecl.EndOffset) then
    begin
      mNext := mIndex;
    end;
  end;
  if not mShared then
  begin
    Result := TTextEdit.Create(TTextRange.Create(ADecl.StartPos.Line, 0, ADecl.EndPos.Line + 1, 0), '');
  end
  else if mNext >= 0 then
  begin
    Result := TTextEdit.Create(TTextRange.Create(ADecl.StartPos, mTokens[mNext].StartPos), '');
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(ADecl.StartPos, ADecl.EndPos), '');
  end;
end;

class procedure TRoutineLocals.RemoveVariables(ATree: TSyntaxTree; ADecl: TSyntaxNode;
  const ARemoved: TArray<string>; var AEdits: TArray<TTextEdit>);
var
  mNames, mKept: TArray<string>;
  mSection: TSyntaxNode;
  mEdit: TTextEdit;
begin
  mNames := ADecl.Name.Split([',']);
  mKept := KeptNames(mNames, ARemoved);
  if Length(mKept) = Length(mNames) then
  begin
    Exit;
  end;
  if mKept <> nil then
  begin
    if KeptNamesEdit(ATree, ADecl, mKept, mEdit) then
    begin
      AEdits := AEdits + [mEdit];
    end;
    Exit;
  end;
  // Ganze Zeile weg; war es der einzige Eintrag, auch "var".
  mSection := ADecl.Parent;
  if (mSection[0] = ADecl) and OthersRemoved(mSection, ADecl, ARemoved) then
  begin
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mSection.StartPos.Line, 0, ADecl.EndPos.Line + 1, 0),
      '')];
  end
  else
  begin
    AEdits := AEdits + [EntryRemoval(ATree, ADecl)];
  end;
end;

end.
