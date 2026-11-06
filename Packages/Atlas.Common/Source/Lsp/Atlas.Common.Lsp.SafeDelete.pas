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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SafeDelete,
  Atlas.Common.Lsp.References;

type
  /// <summary>uses-Kontext einer Datei (wie die uses-Aktionen).</summary>
  TSafeDeleteUsesFunc = reference to function(const AFileName: string): TUsesContext;

  TSafeDeleteChoices = record
    /// <summary>Überschreibungen in Nachfahren mitlöschen.</summary>
    Overrides: Boolean;
    /// <summary>Freigewordenes mitlöschen.</summary>
    Cascade: Boolean;
    /// <summary>Trotz Verwendungen löschen.</summary>
    Force: Boolean;
    class function FromJson(AValue: TJSONValue): TSafeDeleteChoices; static;
  end;

  TSafeDeleteContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche, Nachfahren und uses.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>Für uses-Folgeschritte und das Löschen einer Unit; nil: ohne diese Prüfungen.</summary>
    UsesFor: TSafeDeleteUsesFunc;
    /// <summary>Antworten auf die Rückfragen; nur Execute wertet sie aus.</summary>
    Choices: TSafeDeleteChoices;
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
    /// bei Verwendungen ohne AContext.Choices.Force oder wenn das Ergebnis nicht parst. Der Aufrufer übernimmt
    /// das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TSafeDeleteContext): TJSONObject; static;
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
  Atlas.Common.Lsp.WorkspaceChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspSafeDeleteText = (IsMappedToAnInterface, WhetherImplementsAMethodOf, IsStoredAsBinaryAnd, FormBelongsToTheClass,
    ThereIsNothingHereThat, IsPublishedFormsAndRTTI, OverridesAnInheritedMethodCalls, AfterDeletingNoLongerParses,
    TheUsesEntryInCould, Overrides, SafeDelete, IsStillUsed, DeletedDespiteUses, UsesSymbolsFrom, Includes,
    SymbolsFiles, Implements);

const
  cTexts: array[TLspSafeDeleteText] of TAtlasText = (
    (De: '%s ist einer Interface-Methode zugeordnet.'; En: '%s is mapped to an interface method.'),
    (De: 'Ob %s eine Methode von %s implementiert, ist unbekannt.';
     En: 'Whether %s implements a method of %s is unknown.'),
    (De: '%s ist binär gespeichert und wurde nicht geprüft.'; En: '%s is stored as binary and was not checked.'),
    (De: 'Formular %s gehört zur Klasse.'; En: 'Form %s belongs to the class.'),
    (De: 'Hier steht nichts, das Atlas sicher löschen kann.';
     En: 'There is nothing here that Atlas can safely delete.'),
    (De: '%s ist published: Formulare und RTTI können es ansprechen.';
     En: '%s is published: forms and RTTI can address it.'),
    (De: '%s überschreibt eine geerbte Methode: Aufrufe gehen danach an den Vorfahren.';
     En: '%s overrides an inherited method: calls then go to the ancestor.'),
    (De: 'Nach dem Löschen parst %s nicht mehr fehlerfrei (Zeile %d: %s).';
     En: 'After deleting, %s no longer parses without errors (line %d: %s).'),
    (De: 'Der uses-Eintrag in %s ließ sich nicht entfernen.'; En: 'The uses entry in %s could not be removed.'),
    (De: '%s:%d überschreibt %s'; En: '%s:%d overrides %s'),
    (De: 'Sicher löschen'; En: 'Safe delete'),
    (De: '%s wird noch verwendet: %s'; En: '%s is still used: %s'),
    (De: 'Trotz %d Verwendungen gelöscht.'; En: 'Deleted despite %d uses.'),
    (De: '%s benutzt Symbole aus %s.'; En: '%s uses symbols from %s.'),
    (De: '%s bindet %s ein.'; En: '%s includes %s.'),
    (De: '%d Symbole, %d Dateien'; En: '%d symbols, %d files'),
    (De: '%s.%s implementiert %s.%s.'; En: '%s.%s implements %s.%s.'));

{$SCOPEDENUMS OFF}

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
    /// <summary>Baum von AFileName: der eigene oder ein neu gelesener, den der Plan freigibt.</summary>
    function FileTreeOf(const AFileName, AText: string): TSyntaxTree;
    /// <summary>True, wenn das Mitglied AIndex außerhalb der gelöschten Zeilen verwendet wird.</summary>
    function UsedElsewhere(ALayout: TClassLayout; AIndex: Integer): Boolean;
    procedure DeleteUnit(AChanges: TWorkspaceChanges);
    procedure DeleteOverrides(AChanges: TWorkspaceChanges);
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
  begin
    if Span.Contains(ALine) then
    begin
      Exit(True);
    end;
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(Text);
  if (ALine >= 0) and (ALine <= High(Lines)) then
  begin
    Result := Trim(Lines[ALine]);
  end;
end;

function TSafeDeletePlan.References(const APosition: TTextPosition): TArray<TReferenceLocation>;
begin
  Result := TLspReferences.Find(FResolver, FContext.Index, FTree, TReferenceSearch.Create(FFileName, APosition,
    False, FContext.Files, FContext.ReadText));
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
  begin
    if SameText(Usages[Index].FileName, AFileName) and (Usages[Index].Position.Line = APosition.Line) then
    begin
      if AKind = 'form' then
      begin
        Usages[Index].Text := AText;
        Usages[Index].Kind := AKind;
      end;
      Exit;
    end;
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
  begin
    if not IsOwn(Location.FileName, Location.Range.StartPos) then
    begin
      AddUsage(Location.FileName, Location.Range.StartPos, LineText(Location.FileName, Location.Range.StartPos.Line),
        'code');
    end;
  end;
end;

procedure TSafeDeletePlan.FindInterfaces(ALayout: TClassLayout);
var
  Interfaces: TInterfaceDeclares;
  Answer: TInterfaceAnswer;
  Index: Integer;
begin
  if Target.Kind <> TSafeDeleteKind.Method then
  begin
    Exit;
  end;
  if TInlineAccessor.IsResolution(ALayout, Target.Name) then
  begin
    AddUsage(FFileName, Target.NameRange.StartPos, cTexts[TLspSafeDeleteText.IsMappedToAnInterface].Fmt([Target.Name]),
      'interface');
  end;
  Interfaces := TInlineAccessor.IndexInterfaces(FContext.Index);
  for Index := 0 to High(ALayout.Ancestors) do
  begin
    Answer := TInlineAccessor.LocalInterfaceDeclares(FTree, ALayout.Ancestors[Index], Target.Name);
    if (Answer = TInterfaceAnswer.Unknown) and Assigned(Interfaces) then
    begin
      Answer := Interfaces(ALayout.Ancestors[Index], Target.Name);
    end;
    if Answer = TInterfaceAnswer.Yes then
    begin
      AddUsage(FFileName, Target.NameRange.StartPos, cTexts[TLspSafeDeleteText.Implements].Fmt([ALayout.Name,
        Target.Name, ALayout.Ancestors[Index], Target.Name]), 'interface');
    end
    else if (Answer = TInterfaceAnswer.Unknown) and (Index > 0) then
    begin
      Warnings := Warnings + [cTexts[TLspSafeDeleteText.WhetherImplementsAMethodOf].Fmt([Target.Name,
        ALayout.Ancestors[Index]])];
    end;
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
    begin
      AddUsage(Form, AObject.NameRange.StartPos, Format('object %s: %s', [AObject.Name, AObject.TypeName]), 'form');
    end;
    for Item in AObject.Properties do
    begin
      if (Target.Kind = TSafeDeleteKind.Method) and Item.IsEvent and SameText(Item.Value, Name) then
      begin
        AddUsage(Form, Item.NameRange.StartPos, Format('%s.%s = %s', [AObject.Name, Item.Name, Item.Value]), 'form');
      end
      else if (Target.Kind = TSafeDeleteKind.Property_) and ARoot and SameText(Item.Name, Name) then
      begin
        AddUsage(Form, Item.NameRange.StartPos, Format('%s = %s', [Item.Name, Item.Value]), 'form');
      end;
    end;
    for Child in AObject.Children do
    begin
      Walk(Child, False);
    end;
  end;

begin
  Name := Target.Name;
  for Form in TFormFiles.FormFiles(FFileName, FText) do
  begin
    if not ReadFile(Form, Text) or not ContainsText(Text, Name) then
    begin
      Continue;
    end;
    if TFileEncoding.IsBinaryFormFile(Form) then
    begin
      Warnings := Warnings + [cTexts[TLspSafeDeleteText.IsStoredAsBinaryAnd].Fmt([ExtractFileName(Form)])];
      Continue;
    end;
    Document := TDfmParser.Parse(Text);
    try
      if (Document.Root = nil) or not SameText(Document.Root.TypeName, ALayout.Name) then
      begin
        Continue;
      end;
      if Target.Kind = TSafeDeleteKind.Type_ then
      begin
        AddUsage(Form, Document.Root.TypeRange.StartPos, cTexts[TLspSafeDeleteText.FormBelongsToTheClass].Fmt([
          ExtractFileName(Form)]), 'form');
      end
      else
      begin
        Walk(Document.Root, True);
      end;
    finally
      Document.Free;
    end;
  end;
end;

/// <summary>Überschreibungen von AName mit den Parametern AParameters in der Klasse ALocation des Baums
/// AFileTree.</summary>
function OverridesIn(AFileTree: TSyntaxTree; const AText: string; const ALocation: TSymbolLocation;
  const AName, AParameters: string): TArray<TSafeDeleteOverride>;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mIndex: Integer;
  mHit: TSafeDeleteOverride;
begin
  Result := nil;
  mDecl := TClassLayout.DeclNamed(AFileTree, ALocation.Symbol.Name);
  if mDecl = nil then
  begin
    Exit;
  end;
  mLayout := TClassLayout.Read(AFileTree, AText, mDecl);
  try
    for mIndex in mLayout.Find(AName) do
    begin
      if mLayout.Members[mIndex].HasDirective('override') and (mLayout.Members[mIndex].Parameters = AParameters) then
      begin
        mHit.FileName := ALocation.FileName;
        mHit.ClassName := mLayout.Name;
        mHit.Member := mIndex;
        mHit.Position := mLayout.Members[mIndex].Node.StartPos;
        Result := Result + [mHit];
      end;
    end;
  finally
    mLayout.Free;
  end;
end;

function TSafeDeletePlan.FileTreeOf(const AFileName, AText: string): TSyntaxTree;
begin
  if SameText(AFileName, FFileName) then
  begin
    Exit(FTree);
  end;
  Result := TSyntaxTreeCache.Parse(AText);
  FTrees.Add(Result);
end;

procedure TSafeDeletePlan.FindOverrides(ALayout: TClassLayout);
var
  mQueue, mSeen: TArray<string>;
  mCurrent, mText, mParameters: string;
  mLocation: TSymbolLocation;
begin
  if (Target.Kind <> TSafeDeleteKind.Method) or not Target.IsVirtual or (FContext.Index = nil) then
  begin
    Exit;
  end;
  mParameters := ALayout.Members[Target.Member].Parameters;
  mQueue := [ALayout.Name];
  mSeen := [ALayout.Name];
  while mQueue <> nil do
  begin
    mCurrent := mQueue[0];
    Delete(mQueue, 0, 1);
    for mLocation in FContext.Index.Descendants(mCurrent) do
    begin
      if IndexText(mLocation.Symbol.Name, mSeen) >= 0 then
      begin
        Continue;
      end;
      mSeen := mSeen + [mLocation.Symbol.Name];
      mQueue := mQueue + [mLocation.Symbol.Name];
      if ReadFile(mLocation.FileName, mText) then
      begin
        Overrides := Overrides + OverridesIn(FileTreeOf(mLocation.FileName, mText), mText, mLocation, Target.Name,
          mParameters);
      end;
    end;
  end;
end;

function TSafeDeletePlan.UsedElsewhere(ALayout: TClassLayout; AIndex: Integer): Boolean;
var
  mSpans: TArray<TLineSpan>;
  mLocation: TReferenceLocation;
begin
  mSpans := TSafeDelete.OwnLines(FTree, FText, TSafeDelete.ForMember(ALayout, AIndex)) + OwnSpans;
  for mLocation in References(TSafeDelete.ForMember(ALayout, AIndex).NameRange.StartPos) do
  begin
    if not SameText(mLocation.FileName, FFileName) or not InSpans(mSpans, mLocation.Range.StartPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSafeDeletePlan.FindCascade(ALayout: TClassLayout);
var
  mMember: TClassMember;
  mAccessor: string;
  mIndex: Integer;
begin
  Freed := TSafeDelete.FreedMembers(ALayout, [Target.Member]);
  if Target.Kind <> TSafeDeleteKind.Property_ then
  begin
    Exit;
  end;
  // Getter und Setter, die nicht privat sind: frei, wenn die Referenzsuche nur die Property findet.
  mMember := ALayout.Members[Target.Member];
  for mAccessor in TArray<string>.Create(mMember.ReadAccessor, mMember.WriteAccessor) do
  begin
    for mIndex in ALayout.Find(mAccessor) do
    begin
      if not TMemberTransfer.Has(Freed, mIndex) and (ALayout.Members[mIndex].Kind = TClassMemberKind.Method) and
        not ALayout.Members[mIndex].IsVirtual and not UsedElsewhere(ALayout, mIndex) then
      begin
        Freed := Freed + [mIndex];
      end;
    end;
  end;
end;

/// <summary>True, wenn ein Bezeichner in ATokens AUnitName heißt.</summary>
function NamesUnit(const ATokens: TArray<TPascalToken>; const AUnitName: string): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ungenutzte uses-Einträge in ATokens, wenn AUnitName samt initialization wegfällt (dieselbe Analyse
/// wie "ungenutzte uses"); leer ohne Auskunft über Units.</summary>
function UnusedWithout(const AUses: TUsesContext; const ATokens: TArray<TPascalToken>;
  const AUnitName: string): TArray<string>;
var
  mInfo: TUsesUnitInfoFunc;
  mUnitName: string;
begin
  Result := nil;
  mInfo := AUses.Info;
  if not Assigned(mInfo) then
  begin
    Exit;
  end;
  mUnitName := AUnitName;
  Result := TUsesActions.UnusedUnits(ATokens,
    function(const AName: string): TUsesUnitInfo
    begin
      Result := mInfo(AName);
      // Ihre initialization verschwindet mit ihr.
      if SameText(AName, mUnitName) then
      begin
        Result.HasInitialization := False;
      end;
    end, nil);
end;

procedure TSafeDeletePlan.FindUnitUsers;
var
  mFileName, mText, mUnitName: string;
  mFileTree: TSyntaxTree;
begin
  mUnitName := Target.Name;
  for mFileName in FContext.Files do
  begin
    if SameText(mFileName, FFileName) or not SameText(ExtractFileExt(mFileName), '.pas') or
      not ReadFile(mFileName, mText) or not ContainsText(mText, mUnitName) then
    begin
      Continue;
    end;
    mFileTree := FileTreeOf(mFileName, mText);
    // Steht die Unit in einer uses-Liste?
    if not NamesUnit(mFileTree.Tokens, mUnitName) then
    begin
      Continue;
    end;
    // Nur der uses-Eintrag fällt mit weg; sonst ist es eine Verwendung.
    if Assigned(FContext.UsesFor) and (IndexText(mUnitName, UnusedWithout(FContext.UsesFor(mFileName),
      mFileTree.Tokens, mUnitName)) >= 0) then
    begin
      UsesFiles := UsesFiles + [mFileName];
    end
    else if Assigned(FContext.UsesFor) then
    begin
      AddUsage(mFileName, TTextPosition.Create(0, 0), cTexts[TLspSafeDeleteText.UsesSymbolsFrom].Fmt([
        ExtractFileName(mFileName), mUnitName]), 'uses');
    end
    else
    begin
      AddUsage(mFileName, TTextPosition.Create(0, 0), cTexts[TLspSafeDeleteText.Includes].Fmt([
        ExtractFileName(mFileName),
        mUnitName]), 'uses');
    end;
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
    begin
      Reason := cTexts[TLspSafeDeleteText.ThereIsNothingHereThat].Text;
    end;
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
  begin
    Warnings := Warnings + [cTexts[TLspSafeDeleteText.IsPublishedFormsAndRTTI].Fmt([Target.Name])];
  end;
  if Target.IsOverride then
  begin
    Warnings := Warnings + [cTexts[TLspSafeDeleteText.OverridesAnInheritedMethodCalls].Fmt([Target.Name])];
  end;
  if Target.Kind = TSafeDeleteKind.Type_ then
  begin
    Decl := Target.Node;
  end
  else
  begin
    Decl := TClassLayout.DeclNamed(FTree, Target.ClassName);
  end;
  if (Target.ClassName <> '') or ((Target.Kind = TSafeDeleteKind.Type_) and (TClassLayout.DeclAt(FTree,
    Target.Node.StartPos.Line, True) = Target.Node)) then
  begin
    if Decl = nil then
    begin
      Exit;
    end;
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
  begin
    Exit;
  end;
  Decl := TClassLayout.DeclNamed(FTree, Target.ClassName);
  if Decl = nil then
  begin
    Exit;
  end;
  Layout := TClassLayout.Read(FTree, FText, Decl);
  try
    for Index in Freed do
    begin
      Result := Result + [TSafeDelete.ForMember(Layout, Index)];
    end;
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
  begin
    Result := Result + [Item.Name];
  end;
end;

/// <summary>Ziele der Überschreibungen AOverrides in der Datei AFileName mit dem Baum AFileTree.</summary>
function OverrideTargets(AFileTree: TSyntaxTree; const AText, AFileName: string;
  const AOverrides: TArray<TSafeDeleteOverride>): TArray<TSafeDeleteTarget>;
var
  mHit: TSafeDeleteOverride;
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
begin
  Result := nil;
  for mHit in AOverrides do
  begin
    if not SameText(mHit.FileName, AFileName) then
    begin
      Continue;
    end;
    mDecl := TClassLayout.DeclNamed(AFileTree, mHit.ClassName);
    if mDecl = nil then
    begin
      Continue;
    end;
    mLayout := TClassLayout.Read(AFileTree, AText, mDecl);
    try
      Result := Result + [TSafeDelete.ForMember(mLayout, mHit.Member)];
    finally
      mLayout.Free;
    end;
  end;
end;

function TSafeDeletePlan.NewText(AOverrides, ACascade: Boolean): string;
var
  mTargets: TArray<TSafeDeleteTarget>;
begin
  mTargets := [Target];
  if ACascade then
  begin
    mTargets := mTargets + CascadeTargets;
  end;
  if AOverrides then
  begin
    mTargets := mTargets + OverrideTargets(FTree, FText, FFileName, Overrides);
  end;
  Result := TTextChanges.Apply(FText, TSafeDelete.Edits(FTree, FText, mTargets));
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
  begin
    Exit;
  end;
  Uses_ := FContext.UsesFor(FFileName);
  if not Assigned(Uses_.Info) then
  begin
    Exit;
  end;
  Before := TUsesActions.UnusedUnits(FTree.Tokens, Uses_.Info, Uses_.Keep);
  Check := TSyntaxTreeCache.Parse(ANewText);
  try
    After := TUsesActions.UnusedUnits(Check.Tokens, Uses_.Info, Uses_.Keep);
  finally
    Check.Free;
  end;
  for Name in After do
  begin
    if IndexText(Name, Before) < 0 then
    begin
      Result := Result + [Name];
    end;
  end;
end;

function TSafeDeletePlan.UnitEdits(const AText: string; AFileTree: TSyntaxTree; const AUnits: TArray<string>;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  LineBreak: string;
begin
  LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    LineBreak := #13#10;
  end;
  Result := TUsesActions.RemoveUnits(AFileTree.Tokens, AText, AUnits, LineBreak, AEdits);
end;

/// <summary>EJsonRpcError, wenn ANew mehr Parserfehler hat als AOld.</summary>
procedure CheckParses(const AFileName, AOld, ANew: string);
var
  mBefore, mAfter: TSyntaxTree;
begin
  mBefore := TSyntaxTreeCache.Parse(AOld);
  mAfter := TSyntaxTreeCache.Parse(ANew);
  try
    if Length(mAfter.Diagnostics) > Length(mBefore.Diagnostics) then
    begin
      raise Fail(cTexts[TLspSafeDeleteText.AfterDeletingNoLongerParses].Fmt([ExtractFileName(AFileName),
        mAfter.Diagnostics[0].StartPos.Line + 1, mAfter.Diagnostics[0].Message]));
    end;
  finally
    mAfter.Free;
    mBefore.Free;
  end;
end;

procedure TSafeDeletePlan.DeleteUnit(AChanges: TWorkspaceChanges);
var
  mFileName, mText, mForm: string;
  mEdits: TArray<TTextEdit>;
begin
  for mFileName in UsesFiles do
  begin
    if not ReadFile(mFileName, mText) then
    begin
      Continue;
    end;
    if UnitEdits(mText, FileTreeOf(mFileName, mText), [Target.Name], mEdits) then
    begin
      AChanges.Add(mFileName, mEdits);
    end
    else
    begin
      AChanges.Warn(cTexts[TLspSafeDeleteText.TheUsesEntryInCould].Fmt([ExtractFileName(mFileName)]));
    end;
  end;
  AChanges.DeleteFile(FFileName);
  for mForm in TFormFiles.FormFiles(FFileName, FText) do
  begin
    if ReadFile(mForm, mText) then
    begin
      AChanges.DeleteFile(mForm);
    end;
  end;
end;

procedure TSafeDeletePlan.DeleteOverrides(AChanges: TWorkspaceChanges);
var
  mHit: TSafeDeleteOverride;
  mDone: TArray<string>;
  mText, mChanged: string;
  mFileTree: TSyntaxTree;
begin
  // Überschreibungen in anderen Dateien, je Datei in einem Schritt.
  mDone := nil;
  for mHit in Overrides do
  begin
    if SameText(mHit.FileName, FFileName) or (IndexText(mHit.FileName, mDone) >= 0) or
      not ReadFile(mHit.FileName, mText) then
    begin
      Continue;
    end;
    mDone := mDone + [mHit.FileName];
    mFileTree := FileTreeOf(mHit.FileName, mText);
    mChanged := TTextChanges.Apply(mText, TSafeDelete.Edits(mFileTree, mText, OverrideTargets(mFileTree, mText,
      mHit.FileName, Overrides)));
    CheckParses(mHit.FileName, mText, mChanged);
    AChanges.Add(mHit.FileName, TTextChanges.Diff(mText, mChanged));
  end;
end;

procedure TSafeDeletePlan.Build(const AChoices: TSafeDeleteChoices; AChanges: TWorkspaceChanges);
var
  mChanged: string;
  mFileTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  if Target.Kind = TSafeDeleteKind.Unit_ then
  begin
    DeleteUnit(AChanges);
    Exit;
  end;
  mChanged := NewText(AChoices.Overrides, AChoices.Cascade);
  if AChoices.Cascade and (FreedUnits <> nil) then
  begin
    mFileTree := TSyntaxTreeCache.Parse(mChanged);
    FTrees.Add(mFileTree);
    if UnitEdits(mChanged, mFileTree, FreedUnits, mEdits) then
    begin
      mChanged := TTextChanges.Apply(mChanged, mEdits);
    end;
  end;
  CheckParses(FFileName, FText, mChanged);
  AChanges.Add(FFileName, TTextChanges.Diff(FText, mChanged));
  if AChoices.Overrides then
  begin
    DeleteOverrides(AChanges);
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
  begin
    Exit;
  end;
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
  begin
    Result.Add(Item);
  end;
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
    begin
      Usages.AddElement(UsageJson(Usage.FileName, Usage.Position, Usage.Text, Usage.Kind));
    end;
    Overrides := TJSONArray.Create;
    for Hit in Plan.Overrides do
    begin
      Overrides.AddElement(UsageJson(Hit.FileName, Hit.Position, Hit.ClassName + '.' + Plan.Target.Name, 'override'));
    end;
    Cascade := Plan.CascadeNames;
    for Name in Plan.FreedUnits do
    begin
      Cascade := Cascade + ['uses ' + Name];
    end;
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

/// <summary>Was gegen das Löschen spricht: Verwendungen und ohne AOverrides die Überschreibungen.</summary>
function BlockingOf(APlan: TSafeDeletePlan; AOverrides: Boolean): TArray<string>;
var
  mUsage: TSafeDeleteUsage;
  mHit: TSafeDeleteOverride;
begin
  Result := nil;
  for mUsage in APlan.Usages do
  begin
    Result := Result + [Format('%s:%d %s', [ExtractFileName(mUsage.FileName), mUsage.Position.Line + 1,
      mUsage.Text])];
  end;
  if AOverrides then
  begin
    Exit;
  end;
  for mHit in APlan.Overrides do
  begin
    Result := Result + [cTexts[TLspSafeDeleteText.Overrides].Fmt([ExtractFileName(mHit.FileName), mHit.Position.Line +
      1,
      APlan.Target.Name])];
  end;
end;

/// <summary>Zahl der gelöschten Symbole nach AChoices.</summary>
function DeletedCount(APlan: TSafeDeletePlan; const AChoices: TSafeDeleteChoices): Integer;
begin
  Result := 1;
  if AChoices.Cascade then
  begin
    Inc(Result, Length(APlan.Freed) + Length(APlan.FreedUnits));
  end;
  if AChoices.Overrides then
  begin
    Inc(Result, Length(APlan.Overrides));
  end;
end;

/// <summary>Antwort von atlas.server.safeDelete.</summary>
function ExecuteJson(AChanges: TWorkspaceChanges; ADeleted: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('edit', AChanges.ToJson(TLspSafeDelete.AnnotationId, cTexts[TLspSafeDeleteText.SafeDelete].Text,
    cTexts[TLspSafeDeleteText.SymbolsFiles].Fmt([ADeleted, AChanges.FileCount])));
  Result.AddPair('warnings', AChanges.WarningsJson);
  Result.AddPair('deleted', TJSONNumber.Create(ADeleted));
  Result.AddPair('edits', TJSONNumber.Create(AChanges.EditCount));
  Result.AddPair('files', TJSONNumber.Create(AChanges.FileCount));
end;

class function TLspSafeDelete.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AContext: TSafeDeleteContext): TJSONObject;
var
  mPlan: TSafeDeletePlan;
  mChanges: TWorkspaceChanges;
  mBlocking: TArray<string>;
  mWarning: string;
begin
  mPlan := TSafeDeletePlan.Create(AResolver, ATree, AFileName, AText, AContext);
  mChanges := TWorkspaceChanges.Create;
  try
    mPlan.Analyze(APosition);
    mBlocking := BlockingOf(mPlan, AContext.Choices.Overrides);
    if (mBlocking <> nil) and not AContext.Choices.Force then
    begin
      raise Fail(cTexts[TLspSafeDeleteText.IsStillUsed].Fmt([mPlan.Target.Name, string.Join('; ', mBlocking)]));
    end;
    for mWarning in mPlan.Warnings do
    begin
      mChanges.Warn(mWarning);
    end;
    if mBlocking <> nil then
    begin
      mChanges.Warn(cTexts[TLspSafeDeleteText.DeletedDespiteUses].Fmt([Length(mBlocking)]));
    end;
    mPlan.Build(AContext.Choices, mChanges);
    Result := ExecuteJson(mChanges, DeletedCount(mPlan, AContext.Choices));
  finally
    mChanges.Free;
    mPlan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SafeDelete', cTexts);

end.
