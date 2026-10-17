unit Atlas.Common.Lsp.Refactorings;

// Code-Aktionen aus #50 mit Namensauflösung: Extrahieren (Methode, Variable,
// Konstante), „case vervollständigen“ und „with auflösen“. Die Logik liegt in
// Atlas.Common.Editing.Extract, .CaseCompletion und .WithResolution; hier
// kommen Typen, Aufzählungswerte und die Herkunft der Bezeichner im
// with-Rumpf dazu:
//   - Typen eines Ausdrucks über einen Probetext mit "var AtlasProbe := …"
//     und die Typableitung der Inlay Hints (#453), mit eigener
//     Namensauflösung je Probe (der Probebaum lebt nur kurz).
//   - Aufzählungswerte über TLspCompletion.CaseValues (#448).
//   - Herkunft über TNameResolver.WithMember.
// Was refactoring.extract, .completeCase und .resolveWith abschalten, kommt
// nicht.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.WithResolution,
  Atlas.Common.Lsp.CompletionRequest;

type
  TRefactoringContext = record
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TArray<string>;
    FileName: string;
    ReadText: TCompletionReadText;
    Settings: TRefactoringSettings;
    /// <summary>Inline-Variablen erlaubt (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
  end;

  TLspRefactorings = class
  public
    /// <summary>Typabfrage für Probetexte der Datei AContext.FileName.</summary>
    class function Probe(const AContext: TRefactoringContext): TTypeProbe; static;
    /// <summary>Herkunft der Bezeichner im with-Rumpf über AResolver; ATree muss die Datei sein.</summary>
    class function WithLookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TWithOwnerLookup;
      static;
    /// <summary>„case vervollständigen“ bzw. „Fehlende Werte vor else ergänzen“ für die case-Anweisung an
    /// APosition.</summary>
    class function CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>„with auflösen“ für die with-Anweisung an APosition.</summary>
    class function WithAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
      const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Alle eingeschalteten Aktionen aus #50 für ARange.</summary>
    class function Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
      const AContext: TRefactoringContext): TArray<TCodeAction>; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CaseCompletion,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Lsp.Completion;

function OptionsOf(const AContext: TRefactoringContext): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AContext.InlineVar;
  Result.Style := AContext.Style;
  Result.Probe := TLspRefactorings.Probe(AContext);
end;

function NewResolver(const AContext: TRefactoringContext): TNameResolver;
begin
  Result := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  Result.Namespaces := AContext.Namespaces;
end;

class function TLspRefactorings.Probe(const AContext: TRefactoringContext): TTypeProbe;
var
  Context: TRefactoringContext;
begin
  Context := AContext;
  Result :=
    function(const AText: string; const ANamePos: TTextPosition): TProbedType
    var
      Tree: TSyntaxTree;
      Resolver: TNameResolver;
      Found: TInferredType;
      Resolved: TResolvedSymbol;
      Owner: TUnitIndex;
      Base: string;
      Offset: Integer;
    begin
      Result := Default(TProbedType);
      Tree := TPascalParser.Parse(AText);
      Resolver := NewResolver(Context);
      try
        for Found in TLspInlayHints.Inferred(Resolver, Tree, Context.FileName, TTextRange.Create(ANamePos.Line, 0,
          ANamePos.Line, MaxInt)) do
          if (Found.NameStart.Line = ANamePos.Line) and (Found.NameStart.Character = ANamePos.Character) then
          begin
            Result.Name := Found.TypeName;
            Base := Found.TypeName;
            if Pos('<', Base) > 0 then
              Base := Copy(Base, 1, Pos('<', Base) - 1);
            Offset := TLineTable.Build(AText).OffsetAt(ANamePos);
            Resolved := Resolver.ResolveChain(Tree, Context.FileName, Base.Split(['.']), Offset);
            if Resolved.Found and Resolved.IsType then
              // Sichtbar: kein uses nötig.
              Result.UnitName := ''
            else
            begin
              Result.UnitName := Found.TypeUnit;
              if not ((Found.Origin.Name <> '') and Resolver.DeclaringUnit(Found.Origin, Owner) and
                Resolver.ResolveTypeFrom(Owner, Base, Resolved)) then
                Resolved := Default(TResolvedSymbol);
            end;
            if Resolved.Found and Resolved.IsType then
              if Resolved.Builtin then
                Result.IsValue := True
              else
                case Resolved.SymbolKind of
                  TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
                    Result.IsReference := True;
                  TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.EnumType:
                    Result.IsValue := True;
                end;
            Break;
          end;
      finally
        Resolver.Free;
        Tree.Free;
      end;
    end;
end;

class function TLspRefactorings.WithLookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TWithOwnerLookup;
var
  FileName: string;
begin
  FileName := AFileName;
  Result :=
    function(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
    var
      Owner: TSyntaxNode;
      Unknown: Boolean;
    begin
      AElement := -1;
      if AResolver.WithMember(ATree, FileName, AIdentifier.Name, AIdentifier.StartOffset, Owner, AElement,
        Unknown) then
      begin
        if Owner = AWith then
          Result := TWithOwner.Element
        else
          Result := TWithOwner.Other;
      end
      else if Unknown then
        Result := TWithOwner.Unknown
      else
        Result := TWithOwner.Other;
    end;
end;

class function TLspRefactorings.CaseAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean;
var
  CaseNode: TSyntaxNode;
  OfPos: TTextPosition;
  Values: TArray<string>;
  Prefix: string;
  Edits: TArray<TTextEdit>;
  Count: Integer;
  HasElse: Boolean;
begin
  AAction := Default(TCodeAction);
  Result := False;
  CaseNode := TCaseCompletion.CaseAt(ATree, APosition);
  if (CaseNode = nil) or not TCaseCompletion.OfPosition(ATree, CaseNode, OfPos) or
    not TLspCompletion.CaseValues(AResolver, AContext.Index, ATree, AText, AContext.FileName, OfPos,
    AContext.ReadText, Values, Prefix) or
    not TCaseCompletion.Complete(AText, ATree, CaseNode, Values, Prefix, Edits, Count, HasElse) then
    Exit;
  if HasElse then
    AAction.Title := 'Fehlende Werte vor else ergänzen'
  else
  begin
    AAction.Title := Format('case vervollständigen (%d fehlende Werte)', [Count]);
    AAction.IsPreferred := True;
  end;
  AAction.Kind := RewriteKind;
  AAction.Edits := Edits;
  Result := True;
end;

class function TLspRefactorings.WithAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TRefactoringContext; out AAction: TCodeAction): Boolean;
var
  WithNode: TSyntaxNode;
begin
  AAction := Default(TCodeAction);
  WithNode := TWithResolution.WithAt(ATree, APosition);
  Result := (WithNode <> nil) and TWithResolution.Resolve(AText, ATree, WithNode,
    WithLookup(AResolver, ATree, AContext.FileName), OptionsOf(AContext), AAction);
end;

class function TLspRefactorings.Actions(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
  const AContext: TRefactoringContext): TArray<TCodeAction>;
var
  Resolver: TNameResolver;
  Action: TCodeAction;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  if AContext.Settings.Extract then
    Result := Result + TExtractRefactoring.Actions(AText, ATree, ARange, OptionsOf(AContext));
  if not (AContext.Settings.CompleteCase or AContext.Settings.ResolveWith) then
    Exit;
  Resolver := NewResolver(AContext);
  try
    Resolver.PinTree(ATree, AContext.FileName);
    try
      if AContext.Settings.CompleteCase and CaseAction(Resolver, ATree, AText, ARange.StartPos, AContext, Action) then
        Result := Result + [Action];
      if AContext.Settings.ResolveWith and WithAction(Resolver, ATree, AText, ARange.StartPos, AContext, Action) then
        Result := Result + [Action];
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

end.
