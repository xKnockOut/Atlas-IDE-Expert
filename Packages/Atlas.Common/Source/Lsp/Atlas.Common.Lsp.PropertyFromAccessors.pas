unit Atlas.Common.Lsp.PropertyFromAccessors;

// „Property aus Getter und Setter“ über das Protokoll (#682):
//   - Code-Aktionen auf der Deklaration einer Zugriffsmethode („Property X
//     anlegen“) und auf der Kopfzeile einer Klasse („Fehlende Properties
//     anlegen (n)“), nur mit refactoring.propertyFromAccessors. Nach
//     refactoring.propertyFromAccessorsReplaceCalls gibt es sie ohne, mit oder
//     (ask) in beiden Formen „… und Aufrufe umstellen“. Sie tragen den
//     Client-Befehl atlas.propertyFromAccessors mit [uri, position, Aufrufe].
//   - Befehl atlas.server.propertyFromAccessors [uri, position, Aufrufe]:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau. Die Aufrufe findet die Referenzsuche (#29) im ganzen Projekt;
//     X.GetCaption → X.Caption, X.SetCaption(V) → X.Caption := V. Methoden-
//     zeiger (@X.GetCaption, Ereigniszuweisungen, Argumente vom Typ eines
//     Methodenzeigers) bleiben; lässt sich der Zieltyp nicht bestimmen, bleibt
//     die Stelle mit einem Hinweis. Rümpfe der Zugriffsmethoden selbst bleiben.
//   - Verbergen (refactoring.propertyFromAccessorsHideAccessors): Eine
//     Zugriffsmethode wandert nur, wenn sie danach außerhalb der Methoden
//     ihrer Klasse nicht mehr benutzt wird.
// Erkennung und Änderungen in der Klasse liefert TPropertyFromAccessors.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.PropertyFromAccessors,
  Atlas.Common.Lsp.References;

type
  TPropertyFromAccessorsContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Aufrufsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Options: TPropertyFromAccessorsOptions;
  end;

  TLspPropertyFromAccessors = class
  public const
    ClientCommand = 'atlas.propertyFromAccessors';
    ApplyCommand = 'atlas.server.propertyFromAccessors';
    Kind = 'refactor.rewrite';
    AnnotationId = 'propertyFromAccessors';
  public
    /// <summary>Code-Aktionen an APosition; nil, wenn abgeschaltet oder dort keine Property fehlt. Der Aufrufer
    /// übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition; const AOptions: TPropertyFromAccessorsOptions;
      AReplaceCalls: TReplaceCalls): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "properties": n, "calls": n}; EJsonRpcError, wenn an
    /// APosition keine Property fehlt oder das Ergebnis nicht parst. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; AReplaceCalls: Boolean; const AContext: TPropertyFromAccessorsContext):
      TJSONObject; static;
    /// <summary>Ist ATypeName ein prozeduraler Typ (procedure/function … of object, reference to)?</summary>
    class function IsProcedural(const ATypeName: string; const AIndex: ISymbolIndex): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions;

const
  ProceduralPattern = '=\s*(reference\s+to\s+)?(procedure|function)\b';
  /// <summary>Bekannte Methodenzeiger der RTL, falls die RTL nicht im Index steht.</summary>
  KnownProcedural: array[0..5] of string = ('TProc', 'TFunc', 'TPredicate', 'TNotifyEvent', 'TThreadMethod',
    'TThreadProcedure');
  /// <summary>Eingebaute Routinen, deren Argumente Werte sind.</summary>
  ValueIntrinsics: array[0..13] of string = ('Exit', 'Write', 'Writeln', 'Length', 'Ord', 'Chr', 'Inc', 'Dec', 'Abs',
    'Round', 'Trunc', 'Succ', 'Pred', 'High');

type
  {$SCOPEDENUMS ON}
  TUnclearResult = (Value, Pointer_, Unknown);
  {$SCOPEDENUMS OFF}

  TSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Edits: TArray<TTextEdit>;
    destructor Destroy; override;
  end;

destructor TSourceFile.Destroy;
begin
  if OwnsTree then
    Tree.Free;
  inherited;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function Where(const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), APosition.Line + 1]);
end;

/// <summary>Routine mit Rumpf, in der APosition liegt; nil außerhalb.</summary>
function RoutineAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= APosition.Line) and (ANode.EndPos.Line >= APosition.Line);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
        Found := ANode;
    end);
  Result := Found;
end;

/// <summary>Liegt APosition in der Klassendeklaration von AProperty?</summary>
function InClassDecl(ATree: TSyntaxTree; const AProperty: TAccessorProperty; const APosition: TTextPosition): Boolean;
var
  Found: Boolean;
begin
  Found := False;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = AProperty.ClassLine) and
        (APosition.Line >= ANode.StartPos.Line) and (APosition.Line <= ANode.EndPos.Line) then
        Found := True;
      Result := not Found;
    end);
  Result := Found;
end;

class function TLspPropertyFromAccessors.IsProcedural(const ATypeName: string; const AIndex: ISymbolIndex): Boolean;
var
  Name: string;
  Location: TSymbolLocation;
begin
  if TRegEx.IsMatch(ATypeName, '^\s*(reference\s+to\s+)?(procedure|function)\b', [roIgnoreCase]) then
    Exit(True);
  Name := Trim(ATypeName);
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if IndexText(Name, KnownProcedural) >= 0 then
    Exit(True);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(Name) do
      if (Location.Symbol.Container = '') and (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and
        TRegEx.IsMatch(Location.Symbol.Signature, ProceduralPattern, [roIgnoreCase]) then
        Exit(True);
  Result := False;
end;

/// <summary>Ist der Getter bei ANameToken ein Wert oder ein Methodenzeiger? Ziel der Zuweisung bzw. Parameter
/// des Aufrufs entscheiden.</summary>
function ResolveUnclear(AResolver: TNameResolver; const AIndex: ISymbolIndex; ASource: TSourceFile;
  ANameToken: Integer): TUnclearResult;
var
  Tokens: TArray<TPascalToken>;
  Target, Argument: Integer;
  Routine, TypeRef: TSyntaxNode;
  Resolved: TResolvedSymbol;
  Candidates: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Checked: Boolean;
begin
  Result := TUnclearResult.Unknown;
  Tokens := ASource.Tree.Tokens;
  Target := TPropertyFromAccessors.UnclearTarget(Tokens, ANameToken, Argument);
  if Target < 0 then
    Exit;
  if Argument < 0 then
  begin
    // Zuweisung: Result nimmt den Ergebnistyp der Routine, sonst der Typ des Ziels.
    if SameText(Tokens[Target].Text, 'Result') then
    begin
      Routine := RoutineAt(ASource.Tree, Tokens[Target].StartPos);
      TypeRef := nil;
      if (Routine <> nil) and (Routine.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
        TypeRef := Routine.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.TypeReference);
      if TypeRef = nil then
        Exit;
      if TLspPropertyFromAccessors.IsProcedural(Copy(ASource.Text, TypeRef.StartOffset + 1,
        TypeRef.EndOffset - TypeRef.StartOffset), AIndex) then
        Exit(TUnclearResult.Pointer_);
      Exit(TUnclearResult.Value);
    end;
    // Variable, Feld, Property: der deklarierte Typ; sonst der aufgelöste Typ.
    Resolved := AResolver.Resolve(ASource.Tree, ASource.FileName, Tokens[Target].StartPos);
    if Resolved.Found and (Resolved.TypeName <> '') then
    begin
      if TLspPropertyFromAccessors.IsProcedural(Resolved.TypeName, AIndex) then
        Exit(TUnclearResult.Pointer_);
      Exit(TUnclearResult.Value);
    end;
    Resolved := AResolver.ResolveType(ASource.Tree, ASource.FileName, Tokens[Target].StartPos);
    if not Resolved.Found then
      Exit;
    if Resolved.Builtin or (not TRegEx.IsMatch(Resolved.Signature, ProceduralPattern, [roIgnoreCase]) and
      not TLspPropertyFromAccessors.IsProcedural(Resolved.Name, AIndex)) then
      Result := TUnclearResult.Value
    else
      Result := TUnclearResult.Pointer_;
    Exit;
  end;
  // Argument: Assigned prüft Zeiger, die eingebauten Routinen oben nehmen Werte.
  if SameText(Tokens[Target].Text, 'Assigned') then
    Exit(TUnclearResult.Pointer_);
  if IndexText(Tokens[Target].Text, ValueIntrinsics) >= 0 then
    Exit(TUnclearResult.Value);
  Candidates := AResolver.ResolveAll(ASource.Tree, ASource.FileName, Tokens[Target].StartPos);
  Checked := False;
  for Candidate in Candidates do
  begin
    if Argument > High(Candidate.ParamTypes) then
      Continue;
    Checked := True;
    if TLspPropertyFromAccessors.IsProcedural(Candidate.ParamTypes[Argument], AIndex) then
      Exit(TUnclearResult.Pointer_);
  end;
  if Checked then
    Result := TUnclearResult.Value;
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
    Item.AddPair('annotationId', TLspPropertyFromAccessors.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

{ TLspPropertyFromAccessors }

class function TLspPropertyFromAccessors.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const AOptions: TPropertyFromAccessorsOptions;
  AReplaceCalls: TReplaceCalls): TArray<TJSONObject>;

  function Action(const ATitle: string; AWithCalls: Boolean): TJSONObject;
  var
    Arguments: TJSONArray;
    Command: TJSONObject;
  begin
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(APosition));
    Arguments.AddElement(TJSONBool.Create(AWithCalls));
    Command := TJSONObject.Create;
    Command.AddPair('title', ATitle);
    Command.AddPair('command', ClientCommand);
    Command.AddPair('arguments', Arguments);
    Result := TJSONObject.Create;
    Result.AddPair('title', ATitle);
    Result.AddPair('kind', Kind);
    Result.AddPair('command', Command);
  end;

var
  Found: TArray<TAccessorProperty>;
  Whole: Boolean;
  Title: string;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) then
    Exit;
  Found := TPropertyFromAccessors.At(ATree, AText, APosition.Line, AOptions, Whole);
  if Found = nil then
    Exit;
  if Whole then
    Title := Format('Fehlende Properties anlegen (%d)', [Length(Found)])
  else
    Title := Format('Property %s anlegen', [Found[0].Name]);
  if AReplaceCalls <> TReplaceCalls.Always then
    Result := Result + [Action(Title, False)];
  if AReplaceCalls <> TReplaceCalls.Never then
    Result := Result + [Action(Title + ' und Aufrufe umstellen', True)];
end;

class function TLspPropertyFromAccessors.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; AReplaceCalls: Boolean;
  const AContext: TPropertyFromAccessorsContext): TJSONObject;
var
  Sources: TObjectDictionary<string, TSourceFile>;
  Order: TList<string>;

  function Source(const AName: string): TSourceFile;
  var
    Text: string;
  begin
    if Sources.TryGetValue(UpperCase(AName), Result) then
      Exit;
    Result := nil;
    if SameText(AName, AFileName) then
    begin
      Result := TSourceFile.Create;
      Result.Text := AText;
      Result.Tree := ATree;
    end
    else if Assigned(AContext.ReadText) and AContext.ReadText(AName, Text) then
    begin
      Result := TSourceFile.Create;
      Result.Text := Text;
      Result.Tree := TSyntaxTreeCache.Parse(Text);
      Result.OwnsTree := True;
    end;
    if Result = nil then
      Exit;
    Result.FileName := AName;
    Sources.Add(UpperCase(AName), Result);
    Order.Add(AName);
  end;

var
  Properties: TArray<TAccessorProperty>;
  Item: TAccessorProperty;
  Method: TAccessorMethod;
  Methods: TArray<TAccessorMethod>;
  IsGetter, Whole, Internal, OwnBody, NeedReferences: Boolean;
  Location: TReferenceLocation;
  Unit_: TSourceFile;
  Token: Integer;
  Use: TAccessorUse;
  Routine: TSyntaxNode;
  Added: TArray<TTextEdit>;
  Remaining: TDictionary<string, Boolean>;
  Warnings, Hidden: TArray<string>;
  Calls, EditCount, FileCount, Before_: Integer;
  Name, Text, Warning: string;
  Tree: TSyntaxTree;
  Changes, WarningList: TJSONArray;
  Edit, Annotation, Annotations: TJSONObject;
begin
  Properties := TPropertyFromAccessors.At(ATree, AText, APosition.Line, AContext.Options, Whole);
  if Properties = nil then
    raise Fail('Hier fehlt keine Property.');
  Warnings := nil;
  Hidden := nil;
  Calls := 0;
  EditCount := 0;
  FileCount := 0;
  Changes := nil;
  NeedReferences := AReplaceCalls or (AContext.Options.Hiding <> TAccessorHiding.Off);
  Sources := TObjectDictionary<string, TSourceFile>.Create([doOwnsValues]);
  Order := TList<string>.Create;
  Remaining := TDictionary<string, Boolean>.Create;
  try
    Source(AFileName);
    for Item in Properties do
    begin
      Methods := nil;
      if Item.Getter.Exists then
        Methods := Methods + [Item.Getter];
      if Item.Setter.Exists then
        Methods := Methods + [Item.Setter];
      for Method in Methods do
      begin
        if not NeedReferences then
          Break;
        IsGetter := Method.Name = Item.Getter.Name;
        for Location in TLspReferences.Find(AResolver, AContext.Index, ATree, AFileName, Method.NamePos, False,
          AContext.Files, AContext.ReadText) do
        begin
          // Formulardateien binden Ereignisse: Methodenzeiger, die Methode bleibt sichtbar.
          if MatchText(ExtractFileExt(Location.FileName), ['.dfm', '.fmx']) then
          begin
            Remaining.AddOrSetValue(UpperCase(Method.Name), True);
            Continue;
          end;
          Unit_ := Source(Location.FileName);
          if (Unit_ = nil) or (Unit_.Tree = nil) then
            Continue;
          Token := TChangeSignature.NameTokenAt(Unit_.Tree.Tokens, Location.Range.StartPos);
          if (Token < 0) or TPropertyFromAccessors.IsHeaderName(Unit_.Tree.Tokens, Token) then
            Continue;
          // In der eigenen Klasse (Deklaration oder Methoden) bleibt eine Verwendung „innen“.
          Routine := RoutineAt(Unit_.Tree, Location.Range.StartPos);
          OwnBody := False;
          Internal := SameText(Location.FileName, AFileName) and (InClassDecl(Unit_.Tree, Item,
            Location.Range.StartPos) or ((Routine <> nil) and StartsText(Item.ClassName + '.', Routine.Name)));
          if Internal and (Routine <> nil) then
            OwnBody := SameText(Routine.Name, Item.ClassName + '.' + Item.Getter.Name) or
              SameText(Routine.Name, Item.ClassName + '.' + Item.Setter.Name);
          Use := TPropertyFromAccessors.UseOf(Unit_.Tree.Tokens, Token, IsGetter);
          if Use = TAccessorUse.Unclear then
            case ResolveUnclear(AResolver, AContext.Index, Unit_, Token) of
              TUnclearResult.Value:
                Use := TAccessorUse.Call;
              TUnclearResult.Pointer_:
                Use := TAccessorUse.Pointer_;
            else
              if AReplaceCalls and not OwnBody then
                Warnings := Warnings + [Format('%s: Ob %s dort als Methodenzeiger gemeint ist, lässt sich nicht ' +
                  'bestimmen; die Stelle bleibt.', [Where(Location.FileName, Location.Range.StartPos), Method.Name])];
              Use := TAccessorUse.Keep;
            end;
          if (Use = TAccessorUse.Call) and AReplaceCalls and not OwnBody and
            TPropertyFromAccessors.CallEdit(Unit_.Tree.Tokens, Token, Item, IsGetter, Added) then
          begin
            Unit_.Edits := Unit_.Edits + Added;
            Inc(Calls);
            Continue;
          end;
          if (Use = TAccessorUse.Pointer_) and AReplaceCalls then
            Warnings := Warnings + [Format('%s: %s wird als Methodenzeiger verwendet und bleibt.',
              [Where(Location.FileName, Location.Range.StartPos), Method.Name])];
          if not Internal then
            Remaining.AddOrSetValue(UpperCase(Method.Name), True);
        end;
      end;
      if AContext.Options.Hiding <> TAccessorHiding.Off then
        for Method in Methods do
          if TPropertyFromAccessors.CanHide(Method, AContext.Options) then
          begin
            if Remaining.ContainsKey(UpperCase(Method.Name)) then
              Warnings := Warnings + [Format('%s bleibt sichtbar: Es wird außerhalb der Klasse noch benutzt.',
                [Method.Name])]
            else
              Hidden := Hidden + [Method.Name];
          end;
    end;
    Unit_ := Source(AFileName);
    Unit_.Edits := Unit_.Edits + TPropertyFromAccessors.Edits(ATree, AText, Properties, Hidden, AContext.Options);
    // Das Ergebnis muss weiter fehlerfrei parsen.
    Changes := TJSONArray.Create;
    try
      for Name in Order do
      begin
        Unit_ := Sources[UpperCase(Name)];
        if Unit_.Edits = nil then
          Continue;
        Text := TChangeSignature.ApplyEdits(Unit_.Text, Unit_.Edits);
        Tree := TSyntaxTreeCache.Parse(Text);
        try
          Before_ := Length(Unit_.Tree.Diagnostics);
          if Length(Tree.Diagnostics) > Before_ then
            raise Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
              [ExtractFileName(Name), Tree.Diagnostics[0].StartPos.Line + 1, Tree.Diagnostics[0].Message]));
        finally
          Tree.Free;
        end;
        Changes.AddElement(EditsJson(TDocumentUris.FromPath(Name), Unit_.Edits));
        Inc(EditCount, Length(Unit_.Edits));
        Inc(FileCount);
      end;
    except
      Changes.Free;
      raise;
    end;
  finally
    Remaining.Free;
    Order.Free;
    Sources.Free;
  end;
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', 'Property aus Getter und Setter');
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%d Properties, %d Aufrufe umgestellt, %d Dateien',
    [Length(Properties), Calls, FileCount]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(AnnotationId, Annotation);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Edit.AddPair('changeAnnotations', Annotations);
  WarningList := TJSONArray.Create;
  for Warning in Warnings do
    WarningList.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('warnings', WarningList);
  Result.AddPair('properties', TJSONNumber.Create(Length(Properties)));
  Result.AddPair('calls', TJSONNumber.Create(Calls));
  Result.AddPair('edits', TJSONNumber.Create(EditCount));
end;

end.
