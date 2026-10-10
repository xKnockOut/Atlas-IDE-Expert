unit Argus.Common.Editing.CommandSource;

// Gemeinsame Grundlage der Schnellbefehle (#294, #295): Text, Zeilen,
// Syntaxbaum und Index der Datei mit der Befehlszeile als Leerzeichen, damit
// der Parser sie nicht als Fehler sieht und alle Positionen gleich bleiben.
// Dazu Hilfen für Einfügestellen (Routine, Klasse, private, Ende der
// implementation) und für Argumente.

interface

uses
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Editing.SlashCommands;

type
  /// <summary>Text, Zeilen und Baum ohne die Befehlszeile.</summary>
  TCommandSource = class
  private
    FLines: TArray<string>;
    FLineBreak: string;
    FTree: TSyntaxTree;
    FUnitIndex: TUnitIndex;
    FIndexed: Boolean;
    FCommandIndent: string;
    function GetUnitIndex: TUnitIndex;
  public
    Line: Integer;
    constructor Create(const AContext: TSlashContext);
    destructor Destroy; override;
    /// <summary>Einrückung der Zeile; bei der Befehlszeile die des Befehls.</summary>
    function Indent(ALine: Integer): string;
    /// <summary>Löscht die Befehlszeile samt Zeilenende.</summary>
    function RemoveCommand: TRuleEdit;
    /// <summary>Fügt ANewText am Ende von Zeile ALine ein.</summary>
    function AfterLine(ALine: Integer; const ANewText: string): TRuleEdit;
    /// <summary>Fügt ANewText vor Zeile ALine ein.</summary>
    function BeforeLine(ALine: Integer; const ANewText: string): TRuleEdit;
    /// <summary>Innerste Routine mit Rumpf, in deren begin…end die Befehlszeile steht; nil sonst.</summary>
    function RoutineAt: TSyntaxNode;
    /// <summary>Klasse, in deren Deklaration oder Methode die Befehlszeile steht.</summary>
    function ClassAt(out AClass: TIndexSymbol): Boolean;
    /// <summary>Zeile von "private" (nicht strict) in AClass; -1 ohne.</summary>
    function PrivateLine(const AClass: TIndexSymbol): Integer;
    /// <summary>Zeile, hinter der Code am Ende der implementation steht (vor initialization bzw. end.).</summary>
    function ImplementationEnd: Integer;
    /// <summary>Zeile, hinter der Deklarationen der implementation beginnen (implementation bzw. deren uses).</summary>
    function ImplementationStart: Integer;
    /// <summary>Letzte Zeile des letzten Methodenrumpfs von AClassName; -1 ohne.</summary>
    function LastMethodEnd(const AClassName: string): Integer;
    /// <summary>Rumpf hinter die letzte Methode von AClassName bzw. ans Ende der implementation.</summary>
    function AddBody(const AClassName, ABody: string): TRuleEdit;
    /// <summary>Text mit der Befehlszeile als Leerzeichen.</summary>
    function Text: string;
    property Lines: TArray<string> read FLines;
    property LineBreak: string read FLineBreak;
    property Tree: TSyntaxTree read FTree;
    property UnitIndex: TUnitIndex read GetUnitIndex;
  end;

/// <summary>"Name: Typ" bzw. "Name = Wert"; ASeparator ':' oder '='.</summary>
function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
/// <summary>Setzt AReasonOut und liefert False.</summary>
function Fail(const AReason: string; out AReasonOut: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Index.Extractor;

constructor TCommandSource.Create(const AContext: TSlashContext);
var
  Blanked: string;
begin
  inherited Create;
  Line := AContext.Line;
  if Pos(#13#10, AContext.Text) > 0 then
    FLineBreak := #13#10
  else
    FLineBreak := #10;
  FLines := AContext.Text.Split([FLineBreak]);
  FCommandIndent := Indent(Line);
  FLines[Line] := StringOfChar(' ', Length(FLines[Line]));
  Blanked := string.Join(FLineBreak, FLines);
  FTree := TSyntaxTreeCache.Parse(Blanked);
end;

destructor TCommandSource.Destroy;
begin
  FTree.Free;
  inherited;
end;

function TCommandSource.GetUnitIndex: TUnitIndex;
begin
  if not FIndexed then
  begin
    FUnitIndex := TIndexExtractor.Extract(FTree, '');
    FIndexed := True;
  end;
  Result := FUnitIndex;
end;

function TCommandSource.Indent(ALine: Integer): string;
var
  Index: Integer;
begin
  if (ALine = Line) and (FTree <> nil) then
    Exit(FCommandIndent);
  Index := 1;
  while (Index <= Length(FLines[ALine])) and CharInSet(FLines[ALine][Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(FLines[ALine], 1, Index - 1);
end;

function TCommandSource.RemoveCommand: TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '');
end;

function TCommandSource.AfterLine(ALine: Integer; const ANewText: string): TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(ALine, Length(FLines[ALine]), ALine, Length(FLines[ALine])),
    FLineBreak + ANewText);
end;

function TCommandSource.BeforeLine(ALine: Integer; const ANewText: string): TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), ANewText + FLineBreak);
end;

function FindRoutine(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  Index: Integer;
  Block, Inner: TSyntaxNode;
begin
  Result := nil;
  if (ANode.Kind = TSyntaxKind.RoutineDecl) then
  begin
    Block := ANode.FindChild(TSyntaxKind.Block);
    if (Block <> nil) and (Block.StartPos.Line < ALine) and (Block.EndPos.Line >= ALine) then
      Result := ANode;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartPos.Line <= ALine) and (ANode[Index].EndPos.Line >= ALine) then
    begin
      Inner := FindRoutine(ANode[Index], ALine);
      if Inner <> nil then
        Exit(Inner);
    end;
end;

function TCommandSource.RoutineAt: TSyntaxNode;
begin
  Result := FindRoutine(FTree.Root, Line);
end;

function TCommandSource.ClassAt(out AClass: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Routine: TSyntaxNode;
  TypeName: string;
  Dot: Integer;
begin
  // Deklaration der Klasse um die Zeile.
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Range.StartPos.Line < Line) and
      (Symbol.Range.EndPos.Line > Line) then
    begin
      AClass := Symbol;
      Exit(True);
    end;
  // Methode TFoo.Bar: Klasse TFoo in derselben Datei.
  Routine := RoutineAt;
  if Routine = nil then
    Exit(False);
  Dot := LastDelimiter('.', Routine.Name);
  if Dot = 0 then
    Exit(False);
  TypeName := Copy(Routine.Name, 1, Dot - 1);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, TypeName) and (Symbol.Container = '') then
    begin
      AClass := Symbol;
      Exit(True);
    end;
  Result := False;
end;

function TCommandSource.PrivateLine(const AClass: TIndexSymbol): Integer;
var
  Index: Integer;
begin
  for Index := AClass.Range.StartPos.Line + 1 to AClass.Range.EndPos.Line - 1 do
    if SameText(Trim(FLines[Index]), 'private') then
      Exit(Index);
  Result := -1;
end;

function TCommandSource.ImplementationEnd: Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  InImplementation: Boolean;
begin
  Result := High(FLines);
  InImplementation := False;
  Tokens := FTree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.Keyword then
      Continue;
    if Tokens[Index].IsKeyword('implementation') then
      InImplementation := True
    else if InImplementation and (Tokens[Index].IsKeyword('initialization') or
      Tokens[Index].IsKeyword('finalization')) then
      Exit(Tokens[Index].StartPos.Line)
    else if InImplementation and Tokens[Index].IsKeyword('end') then
    begin
      Next := Index + 1;
      while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Inc(Next);
      if (Next <= High(Tokens)) and Tokens[Next].IsSymbol('.') then
        Result := Tokens[Index].StartPos.Line;
    end;
  end;
end;

function TCommandSource.ImplementationStart: Integer;
var
  Section, UsesNode: TSyntaxNode;
begin
  Result := -1;
  if FTree.Root = nil then
    Exit;
  Section := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  Result := Section.StartPos.Line;
  UsesNode := Section.FindChild(TSyntaxKind.UsesClause);
  if UsesNode <> nil then
    Result := UsesNode.EndPos.Line;
end;

function TCommandSource.LastMethodEnd(const AClassName: string): Integer;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := -1;
  Section := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', Section[Index].Name) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
      Result := Section[Index].EndPos.Line;
end;

function TCommandSource.AddBody(const AClassName, ABody: string): TRuleEdit;
var
  EndLine: Integer;
begin
  EndLine := LastMethodEnd(AClassName);
  if EndLine >= 0 then
    Result := AfterLine(EndLine, FLineBreak + ABody)
  else
    Result := BeforeLine(ImplementationEnd, ABody + FLineBreak);
end;

function TCommandSource.Text: string;
begin
  Result := string.Join(FLineBreak, FLines);
end;

function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
var
  Index: Integer;
begin
  Index := Pos(ASeparator, AArguments);
  AName := Trim(Copy(AArguments, 1, Index - 1));
  AValue := Trim(Copy(AArguments, Index + 1, MaxInt));
  if AValue.EndsWith(';') then
    AValue := Trim(Copy(AValue, 1, Length(AValue) - 1));
  Result := (Index > 1) and IsValidIdent(AName) and (AValue <> '');
end;

function Fail(const AReason: string; out AReasonOut: string): Boolean;
begin
  AReasonOut := AReason;
  Result := False;
end;

end.
