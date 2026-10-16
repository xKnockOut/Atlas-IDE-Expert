unit Atlas.Common.Editing.CommandSource;

// Gemeinsame Grundlage der Schnellbefehle (#294, #295): Text, Zeilen,
// Syntaxbaum und Index der Datei mit der Befehlszeile als Leerzeichen, damit
// der Parser sie nicht als Fehler sieht und alle Positionen gleich bleiben.
// Dazu Hilfen für Einfügestellen (Routine, Klasse, private, Ende der
// implementation) und für Argumente. Mit WrapUntil (Markierung im
// Erzeugen-Menü, #719) endet ein Umschließen vor dieser Zeile statt am
// Blockende.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.SlashCommands;

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
    FWrapUntil: Integer;
    function GetUnitIndex: TUnitIndex;
  public
    Line: Integer;
    constructor Create(const AContext: TSlashContext);
    destructor Destroy; override;
    /// <summary>Einrückung der Zeile; bei der Befehlszeile die des Befehls.</summary>
    function Indent(ALine: Integer): string;
    /// <summary>Löscht die Befehlszeile samt Zeilenende.</summary>
    function RemoveCommand: TTextEdit;
    /// <summary>Ersetzt die Befehlszeile durch ALines, jede mit der Einrückung der Befehlszeile.</summary>
    function ReplaceWithIndentedLines(const ALines: array of string): TTextEdit;
    /// <summary>Ersetzt die Befehlszeile durch ALines ohne Einrückung (die Zeilen bringen sie mit).</summary>
    function ReplaceWithLines(const ALines: array of string): TTextEdit;
    /// <summary>Fügt ANewText am Ende von Zeile ALine ein.</summary>
    function AfterLine(ALine: Integer; const ANewText: string): TTextEdit;
    /// <summary>Fügt ANewText vor Zeile ALine ein.</summary>
    function BeforeLine(ALine: Integer; const ANewText: string): TTextEdit;
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
    function AddBody(const AClassName, ABody: string): TTextEdit;
    /// <summary>Text mit der Befehlszeile als Leerzeichen.</summary>
    function Text: string;
    /// <summary>Zeichenoffset des Anfangs von Zeile ALine.</summary>
    function Offset(ALine: Integer): Integer;
    property Lines: TArray<string> read FLines;
    property LineBreak: string read FLineBreak;
    property Tree: TSyntaxTree read FTree;
    property UnitIndex: TUnitIndex read GetUnitIndex;
    /// <summary>Umschließen bis vor diese Zeile (TSlashContext.WrapUntil); 0 = bis zum Blockende.</summary>
    property WrapUntil: Integer read FWrapUntil;
  end;

/// <summary>"Name: Typ" bzw. "Name = Wert"; ASeparator ':' oder '='.</summary>
function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
/// <summary>Setzt AReasonOut und liefert False.</summary>
function Fail(const AReason: string; out AReasonOut: string): Boolean;
/// <summary>Anweisung, die den String-Ausdruck AExpression protokolliert: slashCommands.logCall (#304) vom
/// Host, sonst OutputDebugString(PChar(…)). Ein Routinenname bekommt den Ausdruck als Argument, {text}
/// steht für ihn.</summary>
function LogStatement(const AContext: TSlashContext; const AExpression: string): string;
/// <summary>Zeile des Tokens, das den Block um ALine schließt; -1 ohne. Für die Befehlszeile mit
/// ASource.WrapUntil (#719) diese Zeile, wenn sie im Block liegt, sonst -1.</summary>
function BlockEnd(ASource: TCommandSource; ALine: Integer): Integer;
/// <summary>Grund, wenn BlockEnd -1 liefert: Markierung über das Blockende hinaus oder keine Anweisungen.</summary>
function NoStatementsReason(ASource: TCommandSource; const AName: string): string;
/// <summary>Ersetzt Befehlszeile und folgende Anweisungen durch AHead, die eingerückten Anweisungen und ATail.
/// ABodyIndent ist die zusätzliche Einrückung der Anweisungen.</summary>
function Wrap(ASource: TCommandSource; const AName: string; const AHead, ATail: array of string;
  const ABodyIndent: string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
/// <summary>Lokale Deklaration in den Abschnitt AKind der Routine; legt ihn vor begin an.</summary>
function AddLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; AKind: TSyntaxKind; const AKeyword,
  ADeclaration: string): TTextEdit;

/// <summary>Trägt die fehlenden AUnits in das uses des Abschnitts an Zeile ALine ein.</summary>
procedure AddUses(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  const AUnits: array of string; var AEdits: TArray<TTextEdit>);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines;

constructor TCommandSource.Create(const AContext: TSlashContext);
var
  Blanked: string;
begin
  inherited Create;
  Line := AContext.Line;
  FWrapUntil := AContext.WrapUntil;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
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
begin
  if (ALine = Line) and (FTree <> nil) then
    Exit(FCommandIndent);
  Result := TTextLines.IndentOf(FLines[ALine]);
end;

function TCommandSource.RemoveCommand: TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '');
end;

function TCommandSource.ReplaceWithIndentedLines(const ALines: array of string): TTextEdit;
var
  Index: Integer;
  Text: string;
begin
  Text := '';
  for Index := 0 to High(ALines) do
    Text := Text + Indent(Line) + ALines[Index] + FLineBreak;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), Text);
end;

function TCommandSource.ReplaceWithLines(const ALines: array of string): TTextEdit;
var
  Index: Integer;
  Text: string;
begin
  Text := '';
  for Index := 0 to High(ALines) do
    Text := Text + ALines[Index] + FLineBreak;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), Text);
end;

function TCommandSource.AfterLine(ALine: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, Length(FLines[ALine]), ALine, Length(FLines[ALine])),
    FLineBreak + ANewText);
end;

function TCommandSource.BeforeLine(ALine: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), ANewText + FLineBreak);
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

function TCommandSource.AddBody(const AClassName, ABody: string): TTextEdit;
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

function TCommandSource.Offset(ALine: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to ALine - 1 do
    Inc(Result, Length(FLines[Index]) + Length(FLineBreak));
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

function LogStatement(const AContext: TSlashContext; const AExpression: string): string;
var
  Call: string;
begin
  Call := '';
  if AContext.Host <> nil then
    Call := Trim(AContext.Host.LogCall(AContext.Uri));
  if Call = '' then
    Exit(Format('OutputDebugString(PChar(%s));', [AExpression]));
  if Pos('{text}', Call) > 0 then
    Result := StringReplace(Call, '{text}', AExpression, [rfReplaceAll])
  else
    Result := Call + '(' + AExpression + ')';
  if not EndsStr(';', Result) then
    Result := Result + ';';
end;

function BlockEndOfTokens(ASource: TCommandSource; ALine: Integer): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  Tokens := ASource.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].StartPos.Line <= ALine) or (Tokens[Index].Kind <> TPascalTokenKind.Keyword) then
      Continue;
    if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
      Tokens[Index].IsKeyword('repeat') or Tokens[Index].IsKeyword('asm') then
      Inc(Depth)
    else if Tokens[Index].IsKeyword('end') or Tokens[Index].IsKeyword('until') then
    begin
      if Depth = 0 then
        Exit(Tokens[Index].StartPos.Line);
      Dec(Depth);
    end
    else if (Depth = 0) and (Tokens[Index].IsKeyword('finally') or Tokens[Index].IsKeyword('except')) then
      Exit(Tokens[Index].StartPos.Line);
  end;
  Result := -1;
end;

function BlockEnd(ASource: TCommandSource; ALine: Integer): Integer;
begin
  Result := BlockEndOfTokens(ASource, ALine);
  if (ALine <> ASource.Line) or (ASource.WrapUntil <= ALine) then
    Exit;
  // Markierung (#719): nur bis vor ihr Ende, und nur, wenn sie im Block bleibt.
  if (Result >= 0) and (ASource.WrapUntil <= Result) then
    Result := ASource.WrapUntil
  else
    Result := -1;
end;

function NoStatementsReason(ASource: TCommandSource; const AName: string): string;
begin
  if ASource.WrapUntil > ASource.Line then
    Result := 'Die Markierung für /' + AName + ' muss im selben Block liegen und Anweisungen enthalten'
  else
    Result := 'Nach /' + AName + ' stehen keine Anweisungen im Block';
end;

/// <summary>Ersetzt Befehlszeile und folgende Anweisungen durch AHead, die eingerückten Anweisungen und ATail.
/// ABodyIndent ist die zusätzliche Einrückung der Anweisungen.</summary>
function Wrap(ASource: TCommandSource; const AName: string; const AHead, ATail: array of string;
  const ABodyIndent: string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Stop, Index: Integer;
  Indent, Text: string;
begin
  AEdits := nil;
  if ASource.RoutineAt = nil then
    Exit(Fail('/' + AName + ' gilt nur im Rumpf einer Routine', AReason));
  Stop := BlockEnd(ASource, ASource.Line);
  // Nur Leerzeilen bis zum Blockende zählen nicht als Anweisungen.
  Index := ASource.Line + 1;
  while (Stop > 0) and (Index < Stop) and (Trim(ASource.Lines[Index]) = '') do
    Inc(Index);
  if (Stop < 0) or (Index >= Stop) then
    Exit(Fail(NoStatementsReason(ASource, AName), AReason));
  Indent := ASource.Indent(ASource.Line);
  Text := '';
  for Index := 0 to High(AHead) do
    Text := Text + Indent + AHead[Index] + ASource.LineBreak;
  for Index := ASource.Line + 1 to Stop - 1 do
    if Trim(ASource.Lines[Index]) = '' then
      Text := Text + ASource.LineBreak
    else
      Text := Text + ABodyIndent + ASource.Lines[Index] + ASource.LineBreak;
  for Index := 0 to High(ATail) do
    Text := Text + Indent + ATail[Index] + ASource.LineBreak;
  AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, Stop, 0), Text)];
  Result := True;
end;

/// <summary>Lokale Deklaration in den Abschnitt AKind der Routine; legt ihn vor begin an.</summary>
function AddLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; AKind: TSyntaxKind; const AKeyword,
  ADeclaration: string): TTextEdit;
var
  Index: Integer;
  Section: TSyntaxNode;
  Indent: string;
begin
  Indent := ASource.Indent(ARoutine.StartPos.Line);
  Section := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
    if ARoutine[Index].Kind = AKind then
      Section := ARoutine[Index];
  if Section <> nil then
    Result := ASource.AfterLine(Section.EndPos.Line, Indent + '  ' + ADeclaration)
  else
    Result := ASource.BeforeLine(ARoutine.FindChild(TSyntaxKind.Block).StartPos.Line,
      Indent + AKeyword + ASource.LineBreak + Indent + '  ' + ADeclaration);
end;

/// <summary>Trägt die fehlenden AUnits in das uses des Abschnitts an Zeile ALine ein.</summary>
procedure AddUses(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  const AUnits: array of string; var AEdits: TArray<TTextEdit>);
var
  Used: TArray<string>;
  Index: Integer;
  Combined, Edit: TTextEdit;
  Found: Boolean;
begin
  Used := TUsesClauses.UsedUnits(ASource.Tree.Tokens);
  Combined := Default(TTextEdit);
  Found := False;
  for Index := 0 to High(AUnits) do
    if (AUnits[Index] <> '') and not TUsesClauses.IsUsed(Used, AUnits[Index], AContext.Namespaces) and
      TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), AUnits[Index], ASource.LineBreak, Edit) then
    begin
      // Alle Units landen an derselben Stelle: Texte zu einem Edit zusammenfassen.
      if not Found then
        Combined := Edit
      else if StartsStr(',', Edit.NewText) then
        Combined.NewText := Combined.NewText + Edit.NewText
      else
        // Neue uses-Klausel: "uses X;" wird "uses X, Y;".
        Combined.NewText := Copy(Combined.NewText, 1, Length(Combined.NewText) - 1) + ', ' + AUnits[Index] + ';';
      Found := True;
    end;
  if Found then
    AEdits := AEdits + [Combined];
end;

end.
