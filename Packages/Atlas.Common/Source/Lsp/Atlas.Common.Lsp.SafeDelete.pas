unit Atlas.Common.Lsp.SafeDelete;

// „Sicher löschen“ über das Protokoll (#716):
//   - Code-Aktion „Methode „Run“ sicher löschen …“ auf jedem Symbol, das
//     TSafeDelete kennt, nur mit refactoring.safeDelete. Sie trägt den
//     Client-Befehl atlas.safeDelete mit [uri, position]; dasselbe startet
//     Alt+Entf im Editor.
//   - Befehl atlas.server.safeDelete.prepare mit [uri, position]: Was gelöscht
//     würde und was dagegen spricht. Verwendungen im Projekt (Referenzsuche
//     #29 ohne die eigenen Zeilen), in den Formularen der Unit (Ereignisse,
//     Komponenten, gesetzte Properties), Interface-Implementierungen und bei
//     einer Unit die Units, die noch Symbole aus ihr benutzen. Dazu die
//     Überschreibungen einer virtuellen Methode in Nachfahren, Folgeschritte
//     (private Mitglieder, die nur das Gelöschte benutzte, Getter und Setter
//     einer Property, uses-Einträge, die danach unbenutzt sind) und Hinweise
//     (published, override).
//   - Befehl atlas.server.safeDelete mit [uri, position, {"overrides",
//     "cascade", "force"}]: WorkspaceEdit mit Änderungsanmerkung. Mit
//     Verwendungen nur mit force; Überschreibungen ohne "overrides" zählen
//     als Verwendung. Eine Unit verschwindet samt Formular als Dateioperation,
//     ihre uses-Einträge in anderen Units fallen weg; aus .dpr, .dpk und .dproj
//     trägt sie das Plugin aus.
// Was in einer Datei wegfällt, bestimmt TSafeDelete.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SafeDelete,
  Atlas.Common.Lsp.References;

type
  /// <summary>uses-Kontext einer Datei (wie die uses-Aktionen).</summary>
  TSafeDeleteUsesFunc = reference to function(const AFileName: string): TUsesContext;

  TSafeDeleteContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche, Nachfahren und uses.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>Für uses-Folgeschritte und das Löschen einer Unit; nil: ohne diese Prüfungen.</summary>
    UsesFor: TSafeDeleteUsesFunc;
  end;

  TSafeDeleteChoices = record
    /// <summary>Überschreibungen in Nachfahren mitlöschen.</summary>
    Overrides: Boolean;
    /// <summary>Freigewordenes mitlöschen.</summary>
    Cascade: Boolean;
    /// <summary>Trotz Verwendungen löschen.</summary>
    Force: Boolean;
    class function FromJson(AValue: TJSONValue): TSafeDeleteChoices; static;
  end;

  TLspSafeDelete = class
  public const
    ClientCommand = 'atlas.safeDelete';
    PrepareCommand = 'atlas.server.safeDelete.prepare';
    ApplyCommand = 'atlas.server.safeDelete';
    Kind = 'refactor';
    AnnotationId = 'safeDelete';
  public
    /// <summary>Code-Aktion an APosition; nil, wenn abgeschaltet oder dort nichts zu löschen ist. Der Aufrufer
    /// übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>{"kind", "name", "title", "usages": [{"file", "line", "character", "text", "kind"}],
    /// "overrides": [...], "cascade": [...], "warnings": [...]}; EJsonRpcError, wenn dort nichts zu löschen ist.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function Prepare(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TSafeDeleteContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "deleted": n, "edits": n, "files": n}; EJsonRpcError
    /// bei Verwendungen ohne AChoices.Force oder wenn das Ergebnis nicht parst. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AChoices: TSafeDeleteChoices; const AContext: TSafeDeleteContext):
      TJSONObject; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.WorkspaceChanges;

type
  TSafeDeleteUsage = record
    FileName: string;
    Position: TTextPosition;
    Text: string;
    /// <summary>code, form, interface, uses oder override.</summary>
    Kind: string;
  end;

  /// <summary>Überschreibung in einem Nachfahren.</summary>
  TSafeDeleteOverride = record
    FileName: string;
    ClassName: string;
    Member: Integer;
    Position: TTextPosition;
  end;

  /// <summary>Was ein Löschauftrag umfasst; Prepare und Execute rechnen gleich.</summary>
  TSafeDeletePlan = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FContext: TSafeDeleteContext;
    FTrees: TObjectList<TSyntaxTree>;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function LineText(const AFileName: string; ALine: Integer): string;
    function References(const APosition: TTextPosition): TArray<TReferenceLocation>;
    function IsOwn(const AFileName: string; const APosition: TTextPosition): Boolean;
    procedure AddUsage(const AFileName: string; const APosition: TTextPosition; const AText, AKind: string);
    procedure FindReferences;
    procedure FindInterfaces(ALayout: TClassLayout);
    procedure FindForms(ALayout: TClassLayout);
    procedure FindOverrides(ALayout: TClassLayout);
    procedure FindCascade(ALayout: TClassLayout);
    procedure FindUnitUsers;
    function CascadeTargets: TArray<TSafeDeleteTarget>;
    function NewlyUnused(const ANewText: string): TArray<string>;
    function UnitEdits(const AText: string; AFileTree: TSyntaxTree; const AUnits: TArray<string>;
      out AEdits: TArray<TTextEdit>): Boolean;
  public
    Target: TSafeDeleteTarget;
    OwnSpans: TArray<TLineSpan>;
    Usages: TArray<TSafeDeleteUsage>;
    Overrides: TArray<TSafeDeleteOverride>;
    /// <summary>Freigewordene Mitglieder der Klasse des Ziels (Indizes in ihrem Layout).</summary>
    Freed: TArray<Integer>;
    /// <summary>uses-Einträge, die nach dem Löschen (samt Folgeschritten) unbenutzt sind.</summary>
    FreedUnits: TArray<string>;
    /// <summary>Beim Löschen einer Unit: Dateien, aus deren uses sie wegfällt.</summary>
    UsesFiles: TArray<string>;
    Warnings: TArray<string>;
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TSafeDeleteContext);
    destructor Destroy; override;
    /// <summary>Ziel finden und alles prüfen; EJsonRpcError, wenn dort nichts zu löschen ist.</summary>
    procedure Analyze(const APosition: TTextPosition);
    /// <summary>Text der Datei des Ziels nach dem Löschen von Ziel, Überschreibungen dort und (mit ACascade)
    /// Folgeschritten.</summary>
    function NewText(AOverrides, ACascade: Boolean): string;
    /// <summary>Alle Änderungen.</summary>
    procedure Build(const AChoices: TSafeDeleteChoices; AChanges: TWorkspaceChanges);
    /// <summary>Namen der Folgeschritte für die Rückfrage.</summary>
    function CascadeNames: TArray<string>;
  end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function InSpans(const ASpans: TArray<TLineSpan>; ALine: Integer): Boolean;
var
  Span: TLineSpan;
begin
  for Span in ASpans do
    if Span.Contains(ALine) then
      Exit(True);
  Result := False;
end;

{ TSafeDeleteChoices }

class function TSafeDeleteChoices.FromJson(AValue: TJSONValue): TSafeDeleteChoices;

  function Flag(AObject: TJSONObject; const AName: string): Boolean;
  begin
    Result := (AObject.GetValue(AName) is TJSONBool) and TJSONBool(AObject.GetValue(AName)).AsBoolean;
  end;

begin
  Result := Default(TSafeDeleteChoices);
  if not (AValue is TJSONObject) then
    Exit;
  Result.Overrides := Flag(TJSONObject(AValue), 'overrides');
  Result.Cascade := Flag(TJSONObject(AValue), 'cascade');
  Result.Force := Flag(TJSONObject(AValue), 'force');
end;

{ TSafeDeletePlan }

constructor TSafeDeletePlan.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TSafeDeleteContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FTrees := TObjectList<TSyntaxTree>.Create(True);
end;

destructor TSafeDeletePlan.Destroy;
begin
  FTrees.Free;
  inherited;
end;

function TSafeDeletePlan.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  if SameText(AFileName, FFileName) then
  begin
    AText := FText;
    Exit(True);
  end;
  AText := '';
  Result := Assigned(FContext.ReadText) and FContext.ReadText(AFileName, AText);
end;

function TSafeDeletePlan.LineText(const AFileName: string; ALine: Integer): string;
var
  Text: string;
  Lines: TArray<string>;
begin
  Result := '';
  if not ReadFile(AFileName, Text) then
    Exit;
  Lines := TTextLines.SplitLines(Text);
  if (ALine >= 0) and (ALine <= High(Lines)) then
    Result := Trim(Lines[ALine]);
end;

function TSafeDeletePlan.References(const APosition: TTextPosition): TArray<TReferenceLocation>;
begin
  Result := TLspReferences.Find(FResolver, FContext.Index, FTree, FFileName, APosition, False, FContext.Files,
    FContext.ReadText);
end;

function TSafeDeletePlan.IsOwn(const AFileName: string; const APosition: TTextPosition): Boolean;
begin
  Result := SameText(AFileName, FFileName) and InSpans(OwnSpans, APosition.Line);
end;

procedure TSafeDeletePlan.AddUsage(const AFileName: string; const APosition: TTextPosition; const AText,
  AKind: string);
var
  Usage: TSafeDeleteUsage;
  Index: Integer;
begin
  // Die Referenzsuche findet Formulare mit; die Formularprüfung beschreibt dieselbe Stelle genauer.
  for Index := 0 to High(Usages) do
    if SameText(Usages[Index].FileName, AFileName) and (Usages[Index].Position.Line = APosition.Line) then
    begin
      if AKind = 'form' then
      begin
        Usages[Index].Text := AText;
        Usages[Index].Kind := AKind;
      end;
      Exit;
    end;
  Usage.FileName := AFileName;
  Usage.Position := APosition;
  Usage.Text := AText;
  Usage.Kind := AKind;
  Usages := Usages + [Usage];
end;

procedure TSafeDeletePlan.FindReferences;
var
  Location: TReferenceLocation;
begin
  for Location in References(Target.NameRange.StartPos) do
    if not IsOwn(Location.FileName, Location.Range.StartPos) then
      AddUsage(Location.FileName, Location.Range.StartPos, LineText(Location.FileName, Location.Range.StartPos.Line),
        'code');
end;

procedure TSafeDeletePlan.FindInterfaces(ALayout: TClassLayout);
var
  Interfaces: TInterfaceDeclares;
  Answer: TInterfaceAnswer;
  Index: Integer;
begin
  if Target.Kind <> TSafeDeleteKind.Method then
    Exit;
  if TInlineAccessor.IsResolution(ALayout, Target.Name) then
    AddUsage(FFileName, Target.NameRange.StartPos, Format('%s ist einer Interface-Methode zugeordnet.',
      [Target.Name]), 'interface');
  Interfaces := TInlineAccessor.IndexInterfaces(FContext.Index);
  for Index := 0 to High(ALayout.Ancestors) do
  begin
    Answer := TInlineAccessor.LocalInterfaceDeclares(FTree, ALayout.Ancestors[Index], Target.Name);
    if (Answer = TInterfaceAnswer.Unknown) and Assigned(Interfaces) then
      Answer := Interfaces(ALayout.Ancestors[Index], Target.Name);
    if Answer = TInterfaceAnswer.Yes then
      AddUsage(FFileName, Target.NameRange.StartPos, Format('%s.%s implementiert %s.%s.', [ALayout.Name,
        Target.Name, ALayout.Ancestors[Index], Target.Name]), 'interface')
    else if (Answer = TInterfaceAnswer.Unknown) and (Index > 0) then
      Warnings := Warnings + [Format('Ob %s eine Methode von %s implementiert, ist unbekannt.', [Target.Name,
        ALayout.Ancestors[Index]])];
  end;
end;

procedure TSafeDeletePlan.FindForms(ALayout: TClassLayout);
var
  Form, Text, Name: string;
  Document: TDfmDocument;

  procedure Walk(AObject: TDfmObject; ARoot: Boolean);
  var
    Child: TDfmObject;
    Item: TDfmProperty;
  begin
    if (Target.Kind = TSafeDeleteKind.Field) and not ARoot and SameText(AObject.Name, Name) then
      AddUsage(Form, AObject.NameRange.StartPos, Format('object %s: %s', [AObject.Name, AObject.TypeName]), 'form');
    for Item in AObject.Properties do
      if (Target.Kind = TSafeDeleteKind.Method) and Item.IsEvent and SameText(Item.Value, Name) then
        AddUsage(Form, Item.NameRange.StartPos, Format('%s.%s = %s', [AObject.Name, Item.Name, Item.Value]), 'form')
      else if (Target.Kind = TSafeDeleteKind.Property_) and ARoot and SameText(Item.Name, Name) then
        AddUsage(Form, Item.NameRange.StartPos, Format('%s = %s', [Item.Name, Item.Value]), 'form');
    for Child in AObject.Children do
      Walk(Child, False);
  end;

begin
  Name := Target.Name;
  for Form in TFormFiles.FormFiles(FFileName, FText) do
  begin
    if not ReadFile(Form, Text) or not ContainsText(Text, Name) then
      Continue;
    if TFileEncoding.IsBinaryFormFile(Form) then
    begin
      Warnings := Warnings + [Format('%s ist binär gespeichert und wurde nicht geprüft.', [ExtractFileName(Form)])];
      Continue;
    end;
    Document := TDfmParser.Parse(Text);
    try
      if (Document.Root = nil) or not SameText(Document.Root.TypeName, ALayout.Name) then
        Continue;
      if Target.Kind = TSafeDeleteKind.Type_ then
        AddUsage(Form, Document.Root.TypeRange.StartPos, Format('Formular %s gehört zur Klasse.',
          [ExtractFileName(Form)]), 'form')
      else
        Walk(Document.Root, True);
    finally
      Document.Free;
    end;
  end;
end;

procedure TSafeDeletePlan.FindOverrides(ALayout: TClassLayout);
var
  Queue, Seen: TArray<string>;
  Current, Text: string;
  Location: TSymbolLocation;
  FileTree: TSyntaxTree;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Index: Integer;
  Hit: TSafeDeleteOverride;
  Parameters: string;
begin
  if (Target.Kind <> TSafeDeleteKind.Method) or not Target.IsVirtual or (FContext.Index = nil) then
    Exit;
  Parameters := ALayout.Members[Target.Member].Parameters;
  Queue := [ALayout.Name];
  Seen := [ALayout.Name];
  while Queue <> nil do
  begin
    Current := Queue[0];
    Delete(Queue, 0, 1);
    for Location in FContext.Index.Descendants(Current) do
    begin
      if IndexText(Location.Symbol.Name, Seen) >= 0 then
        Continue;
      Seen := Seen + [Location.Symbol.Name];
      Queue := Queue + [Location.Symbol.Name];
      if not ReadFile(Location.FileName, Text) then
        Continue;
      if SameText(Location.FileName, FFileName) then
        FileTree := FTree
      else
      begin
        FileTree := TSyntaxTreeCache.Parse(Text);
        FTrees.Add(FileTree);
      end;
      Decl := TClassLayout.DeclNamed(FileTree, Location.Symbol.Name);
      if Decl = nil then
        Continue;
      Layout := TClassLayout.Read(FileTree, Text, Decl);
      try
        for Index in Layout.Find(Target.Name) do
          if Layout.Members[Index].HasDirective('override') and (Layout.Members[Index].Parameters = Parameters) then
          begin
            Hit.FileName := Location.FileName;
            Hit.ClassName := Layout.Name;
            Hit.Member := Index;
            Hit.Position := Layout.Members[Index].Node.StartPos;
            Overrides := Overrides + [Hit];
          end;
      finally
        Layout.Free;
      end;
    end;
  end;
end;

procedure TSafeDeletePlan.FindCascade(ALayout: TClassLayout);
var
  Member: TClassMember;
  Accessors: TArray<string>;
  Accessor: string;
  Index: Integer;
  Location: TReferenceLocation;
  Spans: TArray<TLineSpan>;
  Used: Boolean;
begin
  Freed := TSafeDelete.FreedMembers(ALayout, [Target.Member]);
  if Target.Kind <> TSafeDeleteKind.Property_ then
    Exit;
  // Getter und Setter, die nicht privat sind: frei, wenn die Referenzsuche nur die Property findet.
  Member := ALayout.Members[Target.Member];
  Accessors := [Member.ReadAccessor, Member.WriteAccessor];
  for Accessor in Accessors do
    for Index in ALayout.Find(Accessor) do
    begin
      if TMemberTransfer.Has(Freed, Index) or (ALayout.Members[Index].Kind <> TClassMemberKind.Method) or
        ALayout.Members[Index].IsVirtual then
        Continue;
      Spans := TSafeDelete.OwnLines(FTree, FText, TSafeDelete.ForMember(ALayout, Index)) + OwnSpans;
      Used := False;
      for Location in References(TSafeDelete.ForMember(ALayout, Index).NameRange.StartPos) do
        if not SameText(Location.FileName, FFileName) or not InSpans(Spans, Location.Range.StartPos.Line) then
          Used := True;
      if not Used then
        Freed := Freed + [Index];
    end;
end;

procedure TSafeDeletePlan.FindUnitUsers;
var
  FileName, Text: string;
  FileTree: TSyntaxTree;
  Uses_: TUsesContext;
  Info: TUsesUnitInfoFunc;
  UnitName: string;
  Unused: TArray<string>;
  Token: TPascalToken;
  Found: Boolean;
begin
  UnitName := Target.Name;
  for FileName in FContext.Files do
  begin
    if SameText(FileName, FFileName) or not SameText(ExtractFileExt(FileName), '.pas') or
      not ReadFile(FileName, Text) or not ContainsText(Text, UnitName) then
      Continue;
    FileTree := TSyntaxTreeCache.Parse(Text);
    FTrees.Add(FileTree);
    // Steht die Unit in einer uses-Liste?
    Found := False;
    for Token in FileTree.Tokens do
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, UnitName) then
        Found := True;
    if not Found then
      Continue;
    if not Assigned(FContext.UsesFor) then
    begin
      AddUsage(FileName, TTextPosition.Create(0, 0), Format('%s bindet %s ein.', [ExtractFileName(FileName),
        UnitName]), 'uses');
      Continue;
    end;
    // Nur der uses-Eintrag (dieselbe Analyse wie "ungenutzte uses"): fällt mit weg. Sonst eine Verwendung.
    Uses_ := FContext.UsesFor(FileName);
    Info := Uses_.Info;
    Unused := nil;
    if Assigned(Info) then
      Unused := TUsesActions.UnusedUnits(FileTree.Tokens,
        function(const AName: string): TUsesUnitInfo
        begin
          Result := Info(AName);
          // Ihre initialization verschwindet mit ihr.
          if SameText(AName, UnitName) then
            Result.HasInitialization := False;
        end, nil);
    if IndexText(UnitName, Unused) >= 0 then
      UsesFiles := UsesFiles + [FileName]
    else
      AddUsage(FileName, TTextPosition.Create(0, 0), Format('%s benutzt Symbole aus %s.', [ExtractFileName(FileName),
        UnitName]), 'uses');
  end;
end;

procedure TSafeDeletePlan.Analyze(const APosition: TTextPosition);
var
  Reason: string;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
begin
  if not TSafeDelete.Find(FTree, FText, APosition, Target, Reason) then
  begin
    if Reason = '' then
      Reason := 'Hier steht nichts, das Atlas sicher löschen kann.';
    raise Fail(Reason);
  end;
  if Target.Kind = TSafeDeleteKind.Unit_ then
  begin
    FindUnitUsers;
    Exit;
  end;
  OwnSpans := TSafeDelete.OwnLines(FTree, FText, Target);
  FindReferences;
  if Target.IsPublished then
    Warnings := Warnings + [Format('%s ist published: Formulare und RTTI können es ansprechen.', [Target.Name])];
  if Target.IsOverride then
    Warnings := Warnings + [Format('%s überschreibt eine geerbte Methode: Aufrufe gehen danach an den Vorfahren.',
      [Target.Name])];
  if Target.Kind = TSafeDeleteKind.Type_ then
    Decl := Target.Node
  else
    Decl := TClassLayout.DeclNamed(FTree, Target.ClassName);
  if (Target.ClassName <> '') or ((Target.Kind = TSafeDeleteKind.Type_) and (TClassLayout.DeclAt(FTree,
    Target.Node.StartPos.Line, True) = Target.Node)) then
  begin
    if Decl = nil then
      Exit;
    Layout := TClassLayout.Read(FTree, FText, Decl);
    try
      FindForms(Layout);
      if Target.Member >= 0 then
      begin
        FindInterfaces(Layout);
        FindOverrides(Layout);
        FindCascade(Layout);
      end;
    finally
      Layout.Free;
    end;
  end;
  FreedUnits := NewlyUnused(NewText(True, True));
end;

function TSafeDeletePlan.CascadeTargets: TArray<TSafeDeleteTarget>;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Index: Integer;
begin
  Result := nil;
  if Freed = nil then
    Exit;
  Decl := TClassLayout.DeclNamed(FTree, Target.ClassName);
  if Decl = nil then
    Exit;
  Layout := TClassLayout.Read(FTree, FText, Decl);
  try
    for Index in Freed do
      Result := Result + [TSafeDelete.ForMember(Layout, Index)];
  finally
    Layout.Free;
  end;
end;

function TSafeDeletePlan.CascadeNames: TArray<string>;
var
  Item: TSafeDeleteTarget;
begin
  Result := nil;
  for Item in CascadeTargets do
    Result := Result + [Item.Name];
end;

function TSafeDeletePlan.NewText(AOverrides, ACascade: Boolean): string;
var
  Targets: TArray<TSafeDeleteTarget>;
  Hit: TSafeDeleteOverride;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
begin
  Targets := [Target];
  if ACascade then
    Targets := Targets + CascadeTargets;
  if AOverrides then
    for Hit in Overrides do
      if SameText(Hit.FileName, FFileName) then
      begin
        Decl := TClassLayout.DeclNamed(FTree, Hit.ClassName);
        if Decl = nil then
          Continue;
        Layout := TClassLayout.Read(FTree, FText, Decl);
        try
          Targets := Targets + [TSafeDelete.ForMember(Layout, Hit.Member)];
        finally
          Layout.Free;
        end;
      end;
  Result := TTextChanges.Apply(FText, TSafeDelete.Edits(FTree, FText, Targets));
end;

function TSafeDeletePlan.NewlyUnused(const ANewText: string): TArray<string>;
var
  Uses_: TUsesContext;
  Before, After: TArray<string>;
  Check: TSyntaxTree;
  Name: string;
begin
  Result := nil;
  if not Assigned(FContext.UsesFor) then
    Exit;
  Uses_ := FContext.UsesFor(FFileName);
  if not Assigned(Uses_.Info) then
    Exit;
  Before := TUsesActions.UnusedUnits(FTree.Tokens, Uses_.Info, Uses_.Keep);
  Check := TSyntaxTreeCache.Parse(ANewText);
  try
    After := TUsesActions.UnusedUnits(Check.Tokens, Uses_.Info, Uses_.Keep);
  finally
    Check.Free;
  end;
  for Name in After do
    if IndexText(Name, Before) < 0 then
      Result := Result + [Name];
end;

function TSafeDeletePlan.UnitEdits(const AText: string; AFileTree: TSyntaxTree; const AUnits: TArray<string>;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  LineBreak: string;
begin
  LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10;
  Result := TUsesActions.RemoveUnits(AFileTree.Tokens, AText, AUnits, LineBreak, AEdits);
end;

procedure TSafeDeletePlan.Build(const AChoices: TSafeDeleteChoices; AChanges: TWorkspaceChanges);

  procedure Check(const AFileName, AOld, ANew: string);
  var
    Before, After: TSyntaxTree;
  begin
    Before := TSyntaxTreeCache.Parse(AOld);
    After := TSyntaxTreeCache.Parse(ANew);
    try
      if Length(After.Diagnostics) > Length(Before.Diagnostics) then
        raise Fail(Format('Nach dem Löschen parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
          [ExtractFileName(AFileName), After.Diagnostics[0].StartPos.Line + 1, After.Diagnostics[0].Message]));
    finally
      After.Free;
      Before.Free;
    end;
  end;

var
  Text, Changed, FileName, Form: string;
  FileTree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
  Hit, Other: TSafeDeleteOverride;
  Done: TArray<string>;
  Targets: TArray<TSafeDeleteTarget>;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
begin
  if Target.Kind = TSafeDeleteKind.Unit_ then
  begin
    for FileName in UsesFiles do
    begin
      if not ReadFile(FileName, Text) then
        Continue;
      FileTree := TSyntaxTreeCache.Parse(Text);
      FTrees.Add(FileTree);
      if UnitEdits(Text, FileTree, [Target.Name], Edits) then
        AChanges.Add(FileName, Edits)
      else
        AChanges.Warn(Format('Der uses-Eintrag in %s ließ sich nicht entfernen.', [ExtractFileName(FileName)]));
    end;
    AChanges.DeleteFile(FFileName);
    for Form in TFormFiles.FormFiles(FFileName, FText) do
      if ReadFile(Form, Text) then
        AChanges.DeleteFile(Form);
    Exit;
  end;
  Changed := NewText(AChoices.Overrides, AChoices.Cascade);
  if AChoices.Cascade and (FreedUnits <> nil) then
  begin
    FileTree := TSyntaxTreeCache.Parse(Changed);
    FTrees.Add(FileTree);
    if UnitEdits(Changed, FileTree, FreedUnits, Edits) then
      Changed := TTextChanges.Apply(Changed, Edits);
  end;
  Check(FFileName, FText, Changed);
  AChanges.Add(FFileName, TTextChanges.Diff(FText, Changed));
  if not AChoices.Overrides then
    Exit;
  // Überschreibungen in anderen Dateien, je Datei in einem Schritt.
  Done := nil;
  for Hit in Overrides do
  begin
    if SameText(Hit.FileName, FFileName) or (IndexText(Hit.FileName, Done) >= 0) or
      not ReadFile(Hit.FileName, Text) then
      Continue;
    Done := Done + [Hit.FileName];
    FileTree := TSyntaxTreeCache.Parse(Text);
    FTrees.Add(FileTree);
    Targets := nil;
    for Other in Overrides do
    begin
      if not SameText(Other.FileName, Hit.FileName) then
        Continue;
      Decl := TClassLayout.DeclNamed(FileTree, Other.ClassName);
      if Decl = nil then
        Continue;
      Layout := TClassLayout.Read(FileTree, Text, Decl);
      try
        Targets := Targets + [TSafeDelete.ForMember(Layout, Other.Member)];
      finally
        Layout.Free;
      end;
    end;
    Changed := TTextChanges.Apply(Text, TSafeDelete.Edits(FileTree, Text, Targets));
    Check(Hit.FileName, Text, Changed);
    AChanges.Add(Hit.FileName, TTextChanges.Diff(Text, Changed));
  end;
end;

{ TLspSafeDelete }

class function TLspSafeDelete.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Target: TSafeDeleteTarget;
  Reason, Title: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) or not TSafeDelete.Find(ATree, AText, APosition, Target, Reason) then
    Exit;
  Title := TSafeDelete.Title(Target);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

function UsageJson(const AFileName: string; const APosition: TTextPosition; const AText, AKind: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AFileName);
  Result.AddPair('line', TJSONNumber.Create(APosition.Line));
  Result.AddPair('character', TJSONNumber.Create(APosition.Character));
  Result.AddPair('text', AText);
  Result.AddPair('kind', AKind);
end;

function StringsJson(const AItems: TArray<string>): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in AItems do
    Result.Add(Item);
end;

class function TLspSafeDelete.Prepare(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AContext: TSafeDeleteContext): TJSONObject;
var
  Plan: TSafeDeletePlan;
  Usages, Overrides: TJSONArray;
  Usage: TSafeDeleteUsage;
  Hit: TSafeDeleteOverride;
  Cascade: TArray<string>;
  Name: string;
begin
  Plan := TSafeDeletePlan.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    Plan.Analyze(APosition);
    Usages := TJSONArray.Create;
    for Usage in Plan.Usages do
      Usages.AddElement(UsageJson(Usage.FileName, Usage.Position, Usage.Text, Usage.Kind));
    Overrides := TJSONArray.Create;
    for Hit in Plan.Overrides do
      Overrides.AddElement(UsageJson(Hit.FileName, Hit.Position, Hit.ClassName + '.' + Plan.Target.Name, 'override'));
    Cascade := Plan.CascadeNames;
    for Name in Plan.FreedUnits do
      Cascade := Cascade + ['uses ' + Name];
    Result := TJSONObject.Create;
    Result.AddPair('kind', TSafeDeleteTarget.KindName(Plan.Target.Kind));
    Result.AddPair('name', Plan.Target.Name);
    Result.AddPair('title', TSafeDelete.Title(Plan.Target));
    Result.AddPair('usages', Usages);
    Result.AddPair('overrides', Overrides);
    Result.AddPair('cascade', StringsJson(Cascade));
    Result.AddPair('usesFiles', TJSONNumber.Create(Length(Plan.UsesFiles)));
    Result.AddPair('warnings', StringsJson(Plan.Warnings));
  finally
    Plan.Free;
  end;
end;

class function TLspSafeDelete.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AChoices: TSafeDeleteChoices;
  const AContext: TSafeDeleteContext): TJSONObject;
var
  Plan: TSafeDeletePlan;
  Changes: TWorkspaceChanges;
  Blocking: TArray<string>;
  Usage: TSafeDeleteUsage;
  Hit: TSafeDeleteOverride;
  Warning: string;
  Deleted: Integer;
begin
  Plan := TSafeDeletePlan.Create(AResolver, ATree, AFileName, AText, AContext);
  Changes := TWorkspaceChanges.Create;
  try
    Plan.Analyze(APosition);
    Blocking := nil;
    for Usage in Plan.Usages do
      Blocking := Blocking + [Format('%s:%d %s', [ExtractFileName(Usage.FileName), Usage.Position.Line + 1,
        Usage.Text])];
    if not AChoices.Overrides then
      for Hit in Plan.Overrides do
        Blocking := Blocking + [Format('%s:%d überschreibt %s', [ExtractFileName(Hit.FileName), Hit.Position.Line + 1,
          Plan.Target.Name])];
    if (Blocking <> nil) and not AChoices.Force then
      raise Fail(Format('%s wird noch verwendet: %s', [Plan.Target.Name, string.Join('; ', Blocking)]));
    for Warning in Plan.Warnings do
      Changes.Warn(Warning);
    if Blocking <> nil then
      Changes.Warn(Format('Trotz %d Verwendungen gelöscht.', [Length(Blocking)]));
    Plan.Build(AChoices, Changes);
    Deleted := 1;
    if AChoices.Cascade then
      Inc(Deleted, Length(Plan.Freed) + Length(Plan.FreedUnits));
    if AChoices.Overrides then
      Inc(Deleted, Length(Plan.Overrides));
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson(AnnotationId, 'Sicher löschen', Format('%d Symbole, %d Dateien',
      [Deleted, Changes.FileCount])));
    Result.AddPair('warnings', Changes.WarningsJson);
    Result.AddPair('deleted', TJSONNumber.Create(Deleted));
    Result.AddPair('edits', TJSONNumber.Create(Changes.EditCount));
    Result.AddPair('files', TJSONNumber.Create(Changes.FileCount));
  finally
    Changes.Free;
    Plan.Free;
  end;
end;

end.
