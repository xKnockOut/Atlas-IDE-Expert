unit Atlas.Common.Lsp.EnumTables;

// Aufzählung mit Namenstabelle über das Protokoll (#667), nur mit
// refactoring.enumTables:
//   - Auf einem Aufzählungstyp: „Namenstabelle anlegen (TTyp)“ (hinter dem
//     Typ) und im interface-Teil zusätzlich „…, im implementation-Teil“, je
//     als Client-Befehl atlas.enumTable [uri, position, vorgeschlagener Name,
//     afterType|implementation]; das Plugin fragt den Namen ab. Dazu
//     „Tabellen von TTyp nachziehen“ als atlas.enumTablesSync [uri, position].
//   - Auf einer Tabelle array[TTyp] of …, deren Einträge nicht zum Typ passen:
//     „Fehlenden Eintrag ergänzen (osX)“ bzw. „Überzähligen Eintrag entfernen“
//     mit den Änderungen direkt in der Aktion.
//   - Befehle atlas.server.enumTable und atlas.server.enumTablesSync: {"edit",
//     "warnings", "places", "files", "preview"}. Nachziehen ändert alle
//     Tabellen über den Typ im Projekt und ergänzt in case-Anweisungen ohne
//     else die fehlenden Zweige (wie „case vervollständigen“, #449).
// Der Typ einer Tabelle kommt aus der Namensauflösung: gleichnamige Typen
// anderer Units zählen nicht.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.EnumTables,
  Atlas.Common.Lsp.References;

type
  TEnumTablesContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für das Nachziehen.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>refactoring.enumTablesResourceStrings.</summary>
    ResourceStrings: Boolean;
  end;

  TLspEnumTables = class
  public const
    ClientCommand = 'atlas.enumTable';
    ApplyCommand = 'atlas.server.enumTable';
    SyncClientCommand = 'atlas.enumTablesSync';
    SyncApplyCommand = 'atlas.server.enumTablesSync';
    CreateKind = 'refactor.rewrite';
    RepairKind = 'quickfix';
    AnnotationId = 'enumTables';
    AfterTypeName = 'afterType';
    ImplementationName = 'implementation';
  public
    /// <summary>Die Code-Aktionen an APosition; AResolver hat ATree gepinnt. Der Aufrufer übernimmt die Objekte.
    /// </summary>
    class function Actions(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.enumTable; EJsonRpcError mit dem Grund, wenn es nicht geht.</summary>
    class function Execute(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      const AName, APlacement: string; const AContext: TEnumTablesContext): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.enumTablesSync.</summary>
    class function Sync(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TEnumTablesContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Text.Lines;

const
  /// <summary>Anweisung eines case-Zweigs; die Kinder davor sind Marken.</summary>
  StatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function CommandAction(const ATitle, AKind, ACommand: string; AArguments: TJSONArray): TJSONObject;
var
  Command: TJSONObject;
begin
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', ACommand);
  Command.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', AKind);
  Result.AddPair('command', Command);
end;

function CreateAction(const ATitle, AUri: string; const ATarget: TEnumTarget; const APlacement: string): TJSONObject;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(ATarget.NamePosition));
  Arguments.Add(TEnumTables.TableName(ATarget.TypeName));
  Arguments.Add(APlacement);
  Result := CommandAction(Format(ATitle, [ATarget.TypeName]), TLspEnumTables.CreateKind,
    TLspEnumTables.ClientCommand, Arguments);
end;

/// <summary>Elemente des Indextyps der Tabelle ATable über die Namensauflösung; AUnit: Unit des Typs.</summary>
function IndexNames(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const ATable: TEnumTable; out ANames: TArray<string>; out AUnit: string): Boolean;
var
  Resolved: TResolvedSymbol;
  Values: TConstantValues;
begin
  ANames := nil;
  AUnit := '';
  Resolved := AResolver.ResolveType(ATree, AFileName, ATable.IndexType.StartPos);
  if not Resolved.Found or (Resolved.SymbolKind <> TIndexSymbolKind.EnumType) then
    Exit(False);
  AUnit := Resolved.UnitName;
  Values := TConstantValues.Create(ATree, AFileName, AIndex, AResolver);
  try
    Result := Values.EnumMembers(Resolved, ANames);
  finally
    Values.Free;
  end;
end;

/// <summary>Art neuer Einträge für die Tabelle ATable: nach dem Namen, sonst über die Namensauflösung.</summary>
function ValuesOf(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ATable: TEnumTable): TEnumTableValues;
var
  Name: string;
  Element: TEnumTableElement;
  Resolved: TResolvedSymbol;
begin
  Name := '';
  if ATable.ElementType.Kind = TSyntaxKind.TypeReference then
    Name := ATable.ElementType.Name;
  Element := TEnumTables.ElementOf(Name);
  if (Element = TEnumTableElement.Other) and (Name <> '') then
  begin
    Resolved := AResolver.ResolveType(ATree, AFileName, ATable.ElementType.StartPos);
    if Resolved.Found then
      case Resolved.SymbolKind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          Element := TEnumTableElement.Pointer_;
        TIndexSymbolKind.EnumType:
          Element := TEnumTableElement.Enum;
      end;
  end;
  Result := TEnumTableValues.Create(Element, Name, ATable.IndexType.Name);
end;

class function TLspEnumTables.Actions(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  Target: TEnumTarget;
  Table: TEnumTable;
  Reason, FileName, UnitName: string;
  Names: TArray<string>;
  Repair: TEnumTableRepair;
  Arguments: TJSONArray;
  Action: TJSONObject;
begin
  Result := nil;
  FileName := TDocumentUris.ToPath(AUri);
  if TEnumTables.Target(ATree, APosition, Target, Reason) then
  begin
    Result := Result + [CreateAction(TEnumTables.CreateTitle, AUri, Target, AfterTypeName)];
    if Target.InInterface then
      Result := Result + [CreateAction(TEnumTables.CreateImplementationTitle, AUri, Target, ImplementationName)];
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(Target.NamePosition));
    Result := Result + [CommandAction(Format(TEnumTables.SyncTitle, [Target.TypeName]), CreateKind,
      SyncClientCommand, Arguments)];
    Exit;
  end;
  if not TEnumTables.TableAt(ATree, APosition, Table) or
    not IndexNames(AResolver, AIndex, ATree, FileName, Table, Names, UnitName) or
    not TEnumTables.Repair(AText, ATree, Table.Value, Names, ValuesOf(AResolver, ATree, FileName, Table), Repair) then
    Exit;
  Action := TJSONObject.Create;
  Action.AddPair('title', Repair.Title);
  Action.AddPair('kind', RepairKind);
  Action.AddPair('edit', TLspCodeActions.WorkspaceEditJson(AUri, Repair.Edits));
  Result := Result + [Action];
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
    Item.AddPair('annotationId', TLspEnumTables.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

type
  TFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

function AnswerJson(const AFiles: TArray<TFileEdits>; const AWarnings: TArray<string>; APlaces: Integer;
  const ALabel, APreview: string): TJSONObject;
var
  Item: TFileEdits;
  Changes, Warnings: TJSONArray;
  Edit, Annotation, Annotations: TJSONObject;
  Warning: string;
begin
  Changes := TJSONArray.Create;
  for Item in AFiles do
    Changes.AddElement(EditsJson(TDocumentUris.FromPath(Item.FileName), Item.Edits));
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', ALabel);
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%d Stellen in %d Dateien', [APlaces, Length(AFiles)]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(TLspEnumTables.AnnotationId, Annotation);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Edit.AddPair('changeAnnotations', Annotations);
  Warnings := TJSONArray.Create;
  for Warning in AWarnings do
    Warnings.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(APlaces));
  Result.AddPair('files', TJSONNumber.Create(Length(AFiles)));
  Result.AddPair('preview', APreview);
end;

class function TLspEnumTables.Execute(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AName, APlacement: string; const AContext: TEnumTablesContext): TJSONObject;
var
  Placement: TEnumTablePlacement;
  Edits: TArray<TTextEdit>;
  Reason: string;
  Target: TEnumTarget;
  Files: TArray<TFileEdits>;
begin
  if SameText(APlacement, AfterTypeName) then
    Placement := TEnumTablePlacement.AfterType
  else if SameText(APlacement, ImplementationName) then
    Placement := TEnumTablePlacement.InImplementation
  else
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Stelle "%s"', [APlacement]));
  if not TEnumTables.Target(ATree, APosition, Target, Reason) or
    not TEnumTables.CreateTable(AText, ATree, APosition, Trim(AName), Placement, AContext.ResourceStrings, Edits,
    Reason) then
    raise Fail('Namenstabelle geht nicht: ' + Reason);
  SetLength(Files, 1);
  Files[0].FileName := AFileName;
  Files[0].Edits := Edits;
  Result := AnswerJson(Files, nil, 1, Format(TEnumTables.CreateTitle, [Target.TypeName]),
    Format('%s: %s mit %d Einträgen.', [Target.TypeName, Trim(AName), Length(Target.Names)]));
end;

type
  /// <summary>Eine Datei für das Nachziehen; gibt einen selbst geparsten Baum frei.</summary>
  TSyncFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    destructor Destroy; override;
  end;

destructor TSyncFile.Destroy;
begin
  if OwnsTree then
    Tree.Free;
  inherited;
end;

function Where(const AFileName, AText: string; AOffset: Integer): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), TLineTable.Build(AText).PositionAt(AOffset).Line + 1]);
end;

/// <summary>Sind alle Marken der case-Anweisung ACase (ohne else) Werte aus ANames? APrefix: "ATypeName." bei
/// qualifizierten Marken; AFirst: die erste Marke.</summary>
function CaseMatches(ACase: TSyntaxNode; const ATypeName: string; const ANames: TArray<string>; out APrefix: string;
  out AFirst: TSyntaxNode): Boolean;
var
  Item, Label_: Integer;
  Matching: Boolean;
  Prefix: string;
  First: TSyntaxNode;

  procedure Check(ALabel: TSyntaxNode);
  begin
    if ALabel.Kind = TSyntaxKind.MemberAccess then
      Prefix := ATypeName + '.'
    else if ALabel.Kind <> TSyntaxKind.Identifier then
      Matching := False;
    if IndexText(ALabel.Name, ANames) < 0 then
      Matching := False;
    if First = nil then
      First := ALabel;
  end;

begin
  Matching := ACase.FindChild(TSyntaxKind.CaseElse) = nil;
  Prefix := '';
  First := nil;
  for Item := 1 to ACase.ChildCount - 1 do
    if ACase[Item].Kind = TSyntaxKind.CaseItem then
      for Label_ := 0 to ACase[Item].ChildCount - 1 do
        if ACase[Item][Label_].Kind = TSyntaxKind.RangeExpr then
        begin
          if ACase[Item][Label_].ChildCount <> 2 then
            Matching := False
          else
          begin
            Check(ACase[Item][Label_][0]);
            Check(ACase[Item][Label_][1]);
          end;
        end
        else if not (ACase[Item][Label_].Kind in StatementKinds) then
          Check(ACase[Item][Label_]);
  APrefix := Prefix;
  AFirst := First;
  Result := Matching and (First <> nil);
end;

/// <summary>case-Anweisungen in ATree über ANames ohne else, deren erste Marke AResolver zu AUnit auflöst.
/// </summary>
function CaseStatements(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, ATypeName, AUnit: string;
  const ANames: TArray<string>; out APrefixes: TArray<string>): TArray<TSyntaxNode>;
var
  Cases, Found: TArray<TSyntaxNode>;
  Prefixes: TArray<string>;
  Node, First: TSyntaxNode;
  Prefix: string;
begin
  Cases := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.CaseStatement then
        Cases := Cases + [ANode];
      Result := True;
    end);
  Found := nil;
  Prefixes := nil;
  for Node in Cases do
    if CaseMatches(Node, ATypeName, ANames, Prefix, First) and
      SameText(AResolver.Resolve(ATree, AFileName, First.StartPos).UnitName, AUnit) then
    begin
      Found := Found + [Node];
      Prefixes := Prefixes + [Prefix];
    end;
  APrefixes := Prefixes;
  Result := Found;
end;

class function TLspEnumTables.Sync(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TEnumTablesContext): TJSONObject;
var
  Target: TEnumTarget;
  Reason, OwnUnit, FileName, Text, UnitName: string;
  SyncFiles: TArray<TSyncFile>;
  SyncFile: TSyncFile;
  Table: TEnumTable;
  Names, Prefixes, Warnings, Preview: TArray<string>;
  Repair: TEnumTableRepair;
  Cases: TArray<TSyntaxNode>;
  CaseEdits: TArray<TTextEdit>;
  Index, Count, Places, TableCount, CaseCount: Integer;
  HasElse: Boolean;
  Files: TArray<TFileEdits>;
  Item: TFileEdits;
begin
  if not TEnumTables.Target(ATree, APosition, Target, Reason) then
    raise Fail('Nachziehen geht nicht: ' + Reason);
  OwnUnit := TUsesClauses.OwnName(ATree.Tokens);
  SyncFiles := nil;
  Files := nil;
  Warnings := nil;
  Preview := nil;
  Places := 0;
  TableCount := 0;
  CaseCount := 0;
  try
    SyncFile := TSyncFile.Create;
    SyncFile.FileName := AFileName;
    SyncFile.Text := AText;
    SyncFile.Tree := ATree;
    SyncFiles := SyncFiles + [SyncFile];
    // Andere Units nur, wenn ihr Text den Typ- oder einen Elementnamen nennt.
    for FileName in AContext.Files do
      if not SameText(FileName, AFileName) and MatchText(ExtractFileExt(FileName), ['.pas', '.dpr']) and
        Assigned(AContext.ReadText) and AContext.ReadText(FileName, Text) and (ContainsText(Text, Target.TypeName) or
        ContainsText(Text, Target.Names[0])) then
      begin
        SyncFile := TSyncFile.Create;
        SyncFiles := SyncFiles + [SyncFile];
        SyncFile.FileName := FileName;
        SyncFile.Text := Text;
        SyncFile.Tree := TSyntaxTreeCache.Parse(Text);
        SyncFile.OwnsTree := True;
      end;
    for SyncFile in SyncFiles do
    begin
      Item := Default(TFileEdits);
      Item.FileName := SyncFile.FileName;
      AResolver.PinTree(SyncFile.Tree, SyncFile.FileName);
      try
        for Table in TEnumTables.Tables(SyncFile.Tree) do
        begin
          if not SameText(Copy(Table.IndexType.Name, LastDelimiter('.', Table.IndexType.Name) + 1, MaxInt),
            Target.TypeName) or not IndexNames(AResolver, AContext.Index, SyncFile.Tree, SyncFile.FileName, Table,
            Names, UnitName) or not SameText(UnitName, OwnUnit) then
            Continue;
          // Die Elemente aus dem Baum der eigenen Unit: Er ist neuer als der Index.
          if not TEnumTables.Repair(SyncFile.Text, SyncFile.Tree, Table.Value, Target.Names,
            ValuesOf(AResolver, SyncFile.Tree, SyncFile.FileName, Table), Repair) then
            Continue;
          Item.Edits := Item.Edits + Repair.Edits;
          Inc(TableCount);
          Preview := Preview + [Format('%s: %s: %s', [Where(SyncFile.FileName, SyncFile.Text,
            Table.Decl.StartOffset), Table.Decl.Name, Repair.Title])];
          if Repair.Uncertain then
            Warnings := Warnings + [Format('%s: %s', [Where(SyncFile.FileName, SyncFile.Text,
              Table.Decl.StartOffset), TEnumTables.UncertainNote])];
        end;
        Cases := CaseStatements(AResolver, SyncFile.Tree, SyncFile.FileName, Target.TypeName, OwnUnit,
          Target.Names, Prefixes);
        for Index := 0 to High(Cases) do
          if TCaseCompletion.Complete(SyncFile.Text, SyncFile.Tree, Cases[Index], Target.Names, Prefixes[Index],
            CaseEdits, Count, HasElse) then
          begin
            Item.Edits := Item.Edits + CaseEdits;
            Inc(CaseCount);
            Preview := Preview + [Format('%s: case: %d Zweige ergänzt', [Where(SyncFile.FileName, SyncFile.Text,
              Cases[Index].StartOffset), Count])];
          end;
      finally
        AResolver.UnpinTree;
      end;
      if Item.Edits <> nil then
      begin
        Files := Files + [Item];
        Inc(Places, Length(Item.Edits));
      end;
    end;
  finally
    for SyncFile in SyncFiles do
      SyncFile.Free;
  end;
  Result := AnswerJson(Files, Warnings, Places, Format(TEnumTables.SyncTitle, [Target.TypeName]),
    Format('%s: %d Tabellen und %d case-Anweisungen in %d Dateien.', [Target.TypeName, TableCount, CaseCount,
    Length(Files)]) + sLineBreak + string.Join(sLineBreak, Preview));
end;

end.
