unit Atlas.Common.Lsp.InlineAccessor;

// „Triviale Zugriffsmethode durch Feld ersetzen“ über das Protokoll (#717):
//   - Code-Aktionen auf einer Property, auf der Deklaration und im Rumpf einer
//     trivialen Zugriffsmethode („Zugriffsmethode GetName durch Feld FName
//     ersetzen“), nur mit refactoring.inlineAccessor. Mit
//     refactoring.inlineAccessorBulk dort und auf der Kopfzeile einer Klasse
//     zusätzlich „Alle trivialen Zugriffsmethoden der Unit ersetzen (n)“ und
//     „… des Projekts ersetzen“. Sie tragen den Client-Befehl
//     atlas.inlineAccessor mit [uri, position, here|unit|project].
//   - Befehl atlas.server.inlineAccessor mit denselben Argumenten:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau. Die Referenzsuche (#29) prüft jede Methode: Wird sie außerhalb
//     ihrer Deklaration, ihres Rumpfs und der Properties ihrer Klasse
//     benutzt, bleibt sie, und ein Hinweis nennt die Stelle. Bleibt nichts
//     übrig, scheitert der Befehl mit diesen Hinweisen.
// Erkennung und Änderungen liefert TInlineAccessor.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Lsp.References;

type
  TInlineAccessorContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche und die Sammelaktion über das Projekt.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Options: TInlineAccessorOptions;
  end;

  TLspInlineAccessor = class
  public const
    ClientCommand = 'atlas.inlineAccessor';
    ApplyCommand = 'atlas.server.inlineAccessor';
    Kind = 'refactor.inline';
    AnnotationId = 'inlineAccessor';
    ScopeHere = 'here';
    ScopeUnit = 'unit';
    ScopeProject = 'project';
  public
    /// <summary>Code-Aktionen an APosition; nil, wenn abgeschaltet oder dort nichts zu ersetzen ist. Der
    /// Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled, ABulk: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition; const AOptions: TInlineAccessorOptions;
      const AIndex: ISymbolIndex): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "accessors": n, "edits": n, "files": n};
    /// EJsonRpcError, wenn nichts zu ersetzen ist oder das Ergebnis nicht parst. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AScope: string; const AContext: TInlineAccessorContext): TJSONObject;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.WorkspaceChanges;

type
  TAccessorGroups = TList<TArray<TTrivialAccessor>>;

  /// <summary>Eine Datei mit den Klassen, deren Zugriffsmethoden ersetzt werden.</summary>
  TAccessorUnit = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Layouts: TObjectList<TClassLayout>;
    Accessors: TAccessorGroups;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TAccessorUnit.Create;
begin
  inherited Create;
  Layouts := TObjectList<TClassLayout>.Create(True);
  Accessors := TAccessorGroups.Create;
end;

destructor TAccessorUnit.Destroy;
begin
  Accessors.Free;
  // Die Layouts verweisen auf den Baum: zuerst freigeben.
  Layouts.Free;
  if OwnsTree then
    Tree.Free;
  inherited;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

/// <summary>Klasse an ALine: Deklaration (Kopf bis end) oder Rumpf einer ihrer Methoden; nil ohne.</summary>
function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Routine: TSyntaxNode;
  Name: string;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, True);
  if Result <> nil then
    Exit;
  Routine := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
        Routine := ANode;
    end);
  if (Routine = nil) or (Pos('.', Routine.Name) = 0) then
    Exit;
  Name := Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1);
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Result := TClassLayout.DeclNamed(ATree, Name);
end;

/// <summary>Alle trivialen Zugriffsmethoden der Datei.</summary>
function CountInFile(ATree: TSyntaxTree; const AText: string; const AOptions: TInlineAccessorOptions;
  const AInterfaces: TInterfaceDeclares): Integer;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
begin
  Result := 0;
  for Decl in TClassLayout.AllDecls(ATree) do
  begin
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      Inc(Result, Length(TInlineAccessor.InClass(Layout, AOptions, AInterfaces)));
    finally
      Layout.Free;
    end;
  end;
end;

{ TLspInlineAccessor }

class function TLspInlineAccessor.Actions(AEnabled, ABulk: Boolean; ATree: TSyntaxTree; const AText,
  AUri: string; const APosition: TTextPosition; const AOptions: TInlineAccessorOptions;
  const AIndex: ISymbolIndex): TArray<TJSONObject>;

  function Action(const ATitle, AScope: string): TJSONObject;
  var
    Arguments: TJSONArray;
    Command: TJSONObject;
  begin
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(APosition));
    Arguments.Add(AScope);
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
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Interfaces: TInterfaceDeclares;
  Found: TArray<TTrivialAccessor>;
  Reason: string;
  OnHeader: Boolean;
  Count: Integer;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) then
    Exit;
  Decl := ClassAt(ATree, APosition.Line);
  if Decl = nil then
    Exit;
  Interfaces := TInlineAccessor.IndexInterfaces(AIndex);
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    Found := TInlineAccessor.At(Layout, APosition.Line, AOptions, Interfaces, Reason);
    OnHeader := APosition.Line = Layout.HeaderLine;
  finally
    Layout.Free;
  end;
  if Found <> nil then
    Result := Result + [Action(TInlineAccessor.Title(Found), ScopeHere)];
  if not ABulk or ((Found = nil) and not OnHeader) then
    Exit;
  Count := CountInFile(ATree, AText, AOptions, Interfaces);
  if Count = 0 then
    Exit;
  Result := Result + [Action(Format('Alle trivialen Zugriffsmethoden der Unit ersetzen (%d)', [Count]), ScopeUnit),
    Action('Alle trivialen Zugriffsmethoden des Projekts ersetzen …', ScopeProject)];
end;

class function TLspInlineAccessor.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AScope: string;
  const AContext: TInlineAccessorContext): TJSONObject;
var
  Units: TObjectList<TAccessorUnit>;
  Interfaces: TInterfaceDeclares;
  Changes: TWorkspaceChanges;

  function AddUnit(const AName, AUnitText: string; AUnitTree: TSyntaxTree; AOwnsTree: Boolean): TAccessorUnit;
  begin
    Result := TAccessorUnit.Create;
    Result.FileName := AName;
    Result.Text := AUnitText;
    Result.Tree := AUnitTree;
    Result.OwnsTree := AOwnsTree;
    Units.Add(Result);
  end;

  procedure AddClasses(AUnit: TAccessorUnit);
  var
    Decl: TSyntaxNode;
    Layout: TClassLayout;
    Found: TArray<TTrivialAccessor>;
  begin
    for Decl in TClassLayout.AllDecls(AUnit.Tree) do
    begin
      Layout := TClassLayout.Read(AUnit.Tree, AUnit.Text, Decl);
      Found := TInlineAccessor.InClass(Layout, AContext.Options, Interfaces);
      if Found = nil then
      begin
        Layout.Free;
        Continue;
      end;
      AUnit.Layouts.Add(Layout);
      AUnit.Accessors.Add(Found);
    end;
  end;

  /// <summary>Fundstellen von AAccessor außerhalb seiner Klasse als "Datei.pas:Zeile"; nil ohne.</summary>
  function ForeignUses(AUnit: TAccessorUnit; ALayout: TClassLayout; const AAccessor: TTrivialAccessor):
    TArray<string>;
  var
    Location: TReferenceLocation;
  begin
    Result := nil;
    for Location in TLspReferences.Find(AResolver, AContext.Index, AUnit.Tree, AUnit.FileName, AAccessor.NamePos,
      False, AContext.Files, AContext.ReadText) do
    begin
      if SameText(Location.FileName, AUnit.FileName) and TInlineAccessor.IsOwnReference(ALayout, AAccessor,
        Location.Range.StartPos) then
        Continue;
      Result := Result + [Format('%s:%d', [ExtractFileName(Location.FileName), Location.Range.StartPos.Line + 1])];
    end;
  end;

var
  CurrentUnit, AccessorUnit: TAccessorUnit;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Found, Kept: TArray<TTrivialAccessor>;
  Accessor: TTrivialAccessor;
  Uses_: TArray<string>;
  Edits: TArray<TTextEdit>;
  Reason, FileName, Text, NewText: string;
  Index, Total: Integer;
  Before, Check: TSyntaxTree;
begin
  if not MatchText(AScope, [ScopeHere, ScopeUnit, ScopeProject]) then
    raise Fail(Format('Unbekannter Bereich "%s".', [AScope]));
  Interfaces := TInlineAccessor.IndexInterfaces(AContext.Index);
  Units := TObjectList<TAccessorUnit>.Create(True);
  Changes := TWorkspaceChanges.Create;
  try
    CurrentUnit := AddUnit(AFileName, AText, ATree, False);
    if AScope = ScopeHere then
    begin
      Decl := ClassAt(ATree, APosition.Line);
      if Decl = nil then
        raise Fail('Hier steht keine triviale Zugriffsmethode.');
      Layout := TClassLayout.Read(ATree, AText, Decl);
      Found := TInlineAccessor.At(Layout, APosition.Line, AContext.Options, Interfaces, Reason);
      if Found = nil then
      begin
        Layout.Free;
        if Reason = '' then
          Reason := 'Hier steht keine triviale Zugriffsmethode.';
        raise Fail(Reason);
      end;
      CurrentUnit.Layouts.Add(Layout);
      CurrentUnit.Accessors.Add(Found);
    end
    else
    begin
      AddClasses(CurrentUnit);
      if AScope = ScopeProject then
        for FileName in AContext.Files do
        begin
          if not SameText(ExtractFileExt(FileName), '.pas') or SameText(FileName, AFileName) or
            not Assigned(AContext.ReadText) or not AContext.ReadText(FileName, Text) then
            Continue;
          AddClasses(AddUnit(FileName, Text, TSyntaxTreeCache.Parse(Text), True));
        end;
    end;
    // Aufrufe außerhalb der Klasse: die Methode bleibt.
    Total := 0;
    for AccessorUnit in Units do
      for Index := 0 to AccessorUnit.Layouts.Count - 1 do
      begin
        Kept := nil;
        for Accessor in AccessorUnit.Accessors[Index] do
        begin
          Uses_ := ForeignUses(AccessorUnit, AccessorUnit.Layouts[Index], Accessor);
          if Uses_ = nil then
            Kept := Kept + [Accessor]
          else
            Changes.Warn(Format('%s.%s bleibt: Es wird noch aufgerufen (%s).', [Accessor.ClassName, Accessor.Name,
              string.Join(', ', Uses_)]));
        end;
        AccessorUnit.Accessors[Index] := Kept;
        Inc(Total, Length(Kept));
      end;
    if Total = 0 then
    begin
      if Changes.Warnings = nil then
        raise Fail('Keine triviale Zugriffsmethode gefunden.');
      raise Fail(string.Join(' ', Changes.Warnings));
    end;
    for AccessorUnit in Units do
    begin
      Edits := nil;
      for Index := 0 to AccessorUnit.Layouts.Count - 1 do
        if AccessorUnit.Accessors[Index] <> nil then
          Edits := Edits + TInlineAccessor.Edits(AccessorUnit.Layouts[Index], AccessorUnit.Accessors[Index]);
      if Edits = nil then
        Continue;
      // Das Ergebnis muss weiter fehlerfrei parsen.
      NewText := TTextChanges.Apply(AccessorUnit.Text, Edits);
      Before := TSyntaxTreeCache.Parse(AccessorUnit.Text);
      Check := TSyntaxTreeCache.Parse(NewText);
      try
        if Length(Check.Diagnostics) > Length(Before.Diagnostics) then
          raise Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
            [ExtractFileName(AccessorUnit.FileName), Check.Diagnostics[0].StartPos.Line + 1,
            Check.Diagnostics[0].Message]));
      finally
        Check.Free;
        Before.Free;
      end;
      Changes.Add(AccessorUnit.FileName, TTextChanges.Diff(AccessorUnit.Text, NewText));
    end;
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson(AnnotationId, 'Zugriffsmethode durch Feld ersetzen',
      Format('%d Zugriffsmethoden, %d Dateien', [Total, Changes.FileCount])));
    Result.AddPair('warnings', Changes.WarningsJson);
    Result.AddPair('accessors', TJSONNumber.Create(Total));
    Result.AddPair('edits', TJSONNumber.Create(Changes.EditCount));
    Result.AddPair('files', TJSONNumber.Create(Changes.FileCount));
  finally
    Changes.Free;
    Units.Free;
  end;
end;

end.
