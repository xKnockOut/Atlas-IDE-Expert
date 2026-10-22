unit Atlas.Common.Rules.Builtin.Jumps;

// Regeln für Sprünge (#909, Gruppe Compiler vorab):
//   jump-outside-allowed-scope
//                     Break oder Continue außerhalb einer Schleife (#984, wie
//                     E2097) bzw. Break, Continue oder Exit, die einen
//                     finally-Block verlassen (wie E2126). Eine Schleife ganz
//                     im finally-Block bleibt erlaubt. Routinen und anonyme
//                     Methoden beginnen neu: Ein Break in einer anonymen
//                     Methode gehört nicht zur Schleife um sie herum.
//                     Korrektur außerhalb eines finally: Break durch Exit
//                     ersetzen.
//
// Grundlage ist der Syntaxbaum. Gemeldet werden nur einfache Aufrufe (Break;
// nicht TMonitor.Exit(FLock)) und nur, wenn die Datei den Namen nicht selbst
// deklariert. Meldet der Parser in der Routine einen Fehler, ist die
// Schachtelung nicht sicher, und die Regel bleibt dort still.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  JumpOutsideAllowedScopeRuleId = 'jump-outside-allowed-scope';

type
  TJumpOutsideAllowedScopeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Name eines einfachen Aufrufs als Anweisung (Exit, Exit(1), Break) in Kleinbuchstaben;
    /// '' bei Aufrufen über ein Objekt (TMonitor.Exit(FLock)) und anderen Anweisungen.</summary>
    class function PlainCallName(AStatement: TSyntaxNode): string; static;
  end;

procedure RegisterJumpRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

/// <summary>Routinen, anonyme Methoden und Abschnitte mit eigenen Anweisungen: Grenze für Sprünge.</summary>
function IsJumpScope(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection, TSyntaxKind.ProgramFile,
    TSyntaxKind.LibraryFile];
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Namen, die die Datei selbst deklariert (Routinen, Variablen, Konstanten, Felder, Parameter …),
/// klein. Ein eigenes Break ist dann kein Sprung.</summary>
function DeclaredNames(ARoot: TSyntaxNode): TDictionary<string, Boolean>;
var
  Names: TDictionary<string, Boolean>;
begin
  Names := TDictionary<string, Boolean>.Create;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Part: string;
    begin
      if (ANode.Name <> '') and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader,
        TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.Field, TSyntaxKind.PropertyDecl,
        TSyntaxKind.Parameter, TSyntaxKind.TypeDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) then
        for Part in ANode.Name.Split([',', '.']) do
          Names.AddOrSetValue(LowerCase(Trim(Part)), True);
      Result := True;
    end);
  Result := Names;
end;

{ TJumpOutsideAllowedScopeRule }

function TJumpOutsideAllowedScopeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(JumpOutsideAllowedScopeRuleId, TRuleSeverity.Error,
    'Break, Continue oder Exit an unzulässiger Stelle');
end;

class function TJumpOutsideAllowedScopeRule.PlainCallName(AStatement: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
    Target := Target[0];
  if Target.Kind = TSyntaxKind.Identifier then
    Result := LowerCase(Target.Name);
end;

procedure TJumpOutsideAllowedScopeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Declared: TDictionary<string, Boolean>;

  // Hat der Parser im Bereich von AScope einen Fehler gemeldet?
  function Broken(AScope: TSyntaxNode): Boolean;
  var
    Diagnostic: TSyntaxDiagnostic;
  begin
    for Diagnostic in AContext.Tree.Diagnostics do
      if (AScope = nil) or ((Diagnostic.StartPos.Line >= AScope.StartPos.Line) and
        (Diagnostic.StartPos.Line <= AScope.EndPos.Line)) then
        Exit(True);
    Result := False;
  end;

  procedure Report(AStatement, AScope: TSyntaxNode; const AName, AMessage: string; AWithFix: Boolean);
  var
    Range: TTextRange;
    Fixes: TArray<TRuleFix>;
  begin
    if Broken(AScope) then
      Exit;
    Range := TTextRange.Create(AStatement.StartPos,
      TTextPosition.Create(AStatement.StartPos.Line, AStatement.StartPos.Character + Length(AName)));
    Fixes := nil;
    if AWithFix then
      Fixes := [TRuleFix.Create('Break durch Exit ersetzen', [TRuleEdit.Create(Range, 'Exit')])];
    AReport.Add(Range, AMessage, TRuleConfidence.High, Fixes);
  end;

  // AHasLoop: eine Schleife umschließt die Stelle in derselben Routine; AFinallySinceLoop: zwischen ihr und der
  // Stelle liegt ein finally; AInFinally: irgendein finally der Routine umschließt die Stelle.
  procedure Visit(ANode, AScope: TSyntaxNode; AHasLoop, AFinallySinceLoop, AInFinally: Boolean);
  var
    Index: Integer;
    Name, Written: string;
  begin
    if IsJumpScope(ANode) then
    begin
      AScope := ANode;
      AHasLoop := False;
      AFinallySinceLoop := False;
      AInFinally := False;
    end
    else if IsLoop(ANode) then
    begin
      AHasLoop := True;
      AFinallySinceLoop := False;
    end
    else if ANode.Kind = TSyntaxKind.FinallyBlock then
    begin
      AFinallySinceLoop := True;
      AInFinally := True;
    end
    else if ANode.Kind = TSyntaxKind.CallStatement then
    begin
      Name := PlainCallName(ANode);
      if ((Name = 'break') or (Name = 'continue') or (Name = 'exit')) and not Declared.ContainsKey(Name) then
      begin
        Written := Copy(AContext.Text, ANode.StartOffset + 1, Length(Name));
        if (Name <> 'exit') and not AHasLoop then
          Report(ANode, AScope, Name, Format('%s außerhalb einer Schleife (wie E2097).', [Written]),
            (Name = 'break') and not AInFinally)
        else if ((Name <> 'exit') and AFinallySinceLoop) or ((Name = 'exit') and AInFinally) then
          Report(ANode, AScope, Name, Format('%s darf einen finally-Block nicht verlassen (wie E2126).',
            [Written]), False);
      end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], AScope, AHasLoop, AFinallySinceLoop, AInFinally);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Declared := DeclaredNames(AContext.Tree.Root);
  try
    Visit(AContext.Tree.Root, nil, False, False, False);
  finally
    Declared.Free;
  end;
end;

procedure RegisterJumpRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TJumpOutsideAllowedScopeRule.Create);
end;

end.
