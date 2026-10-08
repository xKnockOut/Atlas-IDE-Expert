unit BDLsp.Common.Editing.DeclarationCommands;

// Schnellbefehle für Deklarationen (#294) im Rahmen aus #293:
//   /var Name: Typ        lokale Variable (legt "var" vor begin an)
//   /var Name := Ausdruck Inline-Variable an der Stelle
//   /const Name = Wert    lokale Konstante; /const! in die implementation
//   /field Name: Typ      Feld FName im private-Abschnitt der Klasse
//   /prop Name: Typ [ro]  Feld, Property und Setter samt Rumpf
//   /resstr               String-Literal der vorigen Zeile als resourcestring
//   /guid                 ['{…}'] in der Interface-Deklaration
//
// Gelesen wird der Text mit der Befehlszeile als Leerzeichen, damit der
// Parser sie nicht als Fehler sieht und alle Positionen gleich bleiben.

interface

uses
  BDLsp.Common.Editing.SlashCommands;

/// <summary>Trägt die Deklarationsbefehle in ARegistry ein.</summary>
procedure RegisterDeclarationCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Extractor;

type
  /// <summary>Text, Zeilen und Baum ohne die Befehlszeile.</summary>
  TCommandSource = class
  private
    FLines: TArray<string>;
    FLineBreak: string;
    FTree: TSyntaxTree;
    FUnitIndex: TUnitIndex;
    FIndexed: Boolean;
    function GetUnitIndex: TUnitIndex;
  public
    Line: Integer;
    constructor Create(const AContext: TSlashContext);
    destructor Destroy; override;
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
    property Lines: TArray<string> read FLines;
    property LineBreak: string read FLineBreak;
    property Tree: TSyntaxTree read FTree;
    property UnitIndex: TUnitIndex read GetUnitIndex;
  end;

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
  FLines[Line] := StringOfChar(' ', Length(FLines[Line]));
  Blanked := string.Join(FLineBreak, FLines);
  FTree := TPascalParser.Parse(Blanked);
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

{ Argumente }

/// <summary>"Name: Typ" bzw. "Name = Wert"; ASeparator ':' oder '='.</summary>
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

{ /var und /const }

/// <summary>Lokale Deklaration in den Abschnitt AKind der Routine; legt ihn vor begin an.</summary>
function AddLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; AKind: TSyntaxKind; const AKeyword,
  ADeclaration: string): TRuleEdit;
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

function ExecuteVar(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Name, Value: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/var gilt nur im Rumpf einer Routine', AReason));
    if Pos(':=', AContext.Arguments) > 0 then
    begin
      // Inline-Variable (ab Delphi 10.3) an der Stelle der Befehlszeile.
      Name := Trim(Copy(AContext.Arguments, 1, Pos(':=', AContext.Arguments) - 1));
      Value := Trim(Copy(AContext.Arguments, Pos(':=', AContext.Arguments) + 2, MaxInt));
      if Value.EndsWith(';') then
        Value := Trim(Copy(Value, 1, Length(Value) - 1));
      if (Name = '') or (Value = '') then
        Exit(Fail('Erwartet wird /var Name := Ausdruck', AReason));
      AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line, Length(AContext.LineText)),
        Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) +
        Format('var %s := %s;', [Name, Value]))];
      Exit(True);
    end;
    if not SplitDeclaration(AContext.Arguments, ':', Name, Value) then
      Exit(Fail('Erwartet wird /var Name: Typ', AReason));
    AEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', Format('%s: %s;', [Name, Value])),
      Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function ExecuteConst(const AContext: TSlashContext; AGlobal: Boolean; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine, Section, Node: TSyntaxNode;
  Name, Value, Declaration: string;
  Index: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, '=', Name, Value) then
    Exit(Fail('Erwartet wird /const Name = Wert', AReason));
  Declaration := Format('%s = %s;', [Name, Value]);
  Source := TCommandSource.Create(AContext);
  try
    if not AGlobal then
    begin
      Routine := Source.RoutineAt;
      if Routine = nil then
        Exit(Fail('/const gilt nur im Rumpf einer Routine; /const! schreibt in die implementation', AReason));
      AEdits := [AddLocal(Source, Routine, TSyntaxKind.ConstSection, 'const', Declaration), Source.RemoveCommand];
      Exit(True);
    end;
    if Source.ImplementationStart < 0 then
      Exit(Fail('/const! braucht einen implementation-Abschnitt', AReason));
    // Erster const-Abschnitt direkt in der implementation, sonst ein neuer hinter uses.
    Section := Source.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    Node := nil;
    for Index := 0 to Section.ChildCount - 1 do
      if (Section[Index].Kind = TSyntaxKind.ConstSection) and (Node = nil) then
        Node := Section[Index];
    if Node <> nil then
      AEdits := [Source.AfterLine(Node.EndPos.Line, '  ' + Declaration)]
    else
      AEdits := [Source.AfterLine(Source.ImplementationStart, Source.LineBreak + 'const' + Source.LineBreak + '  ' +
        Declaration)];
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /field und /prop }

function ExecuteField(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Name, TypeName, Indent: string;
  Line: Integer;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, TypeName) then
    Exit(Fail('Erwartet wird /field Name: Typ', AReason));
  if not StartsText('F', Name) or (Length(Name) < 2) or not CharInSet(Name[2], ['A'..'Z']) then
    Name := 'F' + UpperCase(Copy(Name, 1, 1)) + Copy(Name, 2, MaxInt);
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/field gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Line := Source.PrivateLine(ClassSymbol);
    if Line >= 0 then
      AEdits := [Source.AfterLine(Line, Source.Indent(Line) + '  ' + Format('%s: %s;', [Name, TypeName]))]
    else
    begin
      Indent := Source.Indent(ClassSymbol.Range.EndPos.Line);
      AEdits := [Source.BeforeLine(ClassSymbol.Range.EndPos.Line, Indent + 'private' + Source.LineBreak + Indent +
        '  ' + Format('%s: %s;', [Name, TypeName]))];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

/// <summary>Letzte Zeile des letzten Methodenrumpfs von AClassName; -1 ohne.</summary>
function LastMethodEnd(ASource: TCommandSource; const AClassName: string): Integer;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := -1;
  Section := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', Section[Index].Name) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
      Result := Section[Index].EndPos.Line;
end;

function ExecuteProp(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Arguments, Name, TypeName, Field, Setter, Indent, LB, Body: string;
  ReadOnly: Boolean;
  Line, EndLine: Integer;
begin
  AEdits := nil;
  Arguments := Trim(AContext.Arguments);
  ReadOnly := EndsText(' ro', Arguments);
  if ReadOnly then
    Arguments := Trim(Copy(Arguments, 1, Length(Arguments) - 3));
  if not SplitDeclaration(Arguments, ':', Name, TypeName) then
    Exit(Fail('Erwartet wird /prop Name: Typ [ro]', AReason));
  Field := 'F' + Name;
  Setter := 'Set' + Name;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/prop gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    LB := Source.LineBreak;
    EndLine := ClassSymbol.Range.EndPos.Line;
    Indent := Source.Indent(EndLine);
    // Feld oben in private, Setter und Property in eigenen Abschnitten vor "end":
    // Felder müssen in einem Abschnitt vor den Methoden stehen.
    Line := Source.PrivateLine(ClassSymbol);
    if Line >= 0 then
      AEdits := [Source.AfterLine(Line, Source.Indent(Line) + '  ' + Format('%s: %s;', [Field, TypeName]))];
    Body := '';
    if Line < 0 then
      Body := Indent + 'private' + LB + Indent + '  ' + Format('%s: %s;', [Field, TypeName]) + LB;
    if not ReadOnly then
    begin
      if Line >= 0 then
        Body := Body + Indent + 'private' + LB;
      Body := Body + Indent + '  ' + Format('procedure %s(const Value: %s);', [Setter, TypeName]) + LB;
    end;
    Body := Body + Indent + 'public' + LB + Indent + '  ';
    if ReadOnly then
      Body := Body + Format('property %s: %s read %s;', [Name, TypeName, Field])
    else
      Body := Body + Format('property %s: %s read %s write %s;', [Name, TypeName, Field, Setter]);
    AEdits := AEdits + [Source.BeforeLine(EndLine, Body)];
    if not ReadOnly then
    begin
      Body := Format('procedure %s.%s(const Value: %s);', [ClassSymbol.Name, Setter, TypeName]) + LB + 'begin' + LB +
        Format('  %s := Value;', [Field]) + LB + 'end;';
      Line := LastMethodEnd(Source, ClassSymbol.Name);
      if Line >= 0 then
        AEdits := AEdits + [Source.AfterLine(Line, LB + Body)]
      else
        AEdits := AEdits + [Source.BeforeLine(Source.ImplementationEnd, Body + LB)];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /resstr }

/// <summary>SFehlerBeimLaden aus "Fehler beim Laden"; Umlaute als ae, oe, ue, ss.</summary>
function ResourceName(const AText: string): string;
var
  Index: Integer;
  Upper: Boolean;
  Letter: string;
begin
  Result := 'S';
  Upper := True;
  for Index := 1 to Length(AText) do
  begin
    case AText[Index] of
      'ä': Letter := 'ae';
      'ö': Letter := 'oe';
      'ü': Letter := 'ue';
      'Ä': Letter := 'Ae';
      'Ö': Letter := 'Oe';
      'Ü': Letter := 'Ue';
      'ß': Letter := 'ss';
      'A'..'Z', 'a'..'z', '0'..'9': Letter := AText[Index];
    else
      Letter := '';
      Upper := True;
    end;
    if Letter = '' then
      Continue;
    if Upper then
      Letter := UpperCase(Copy(Letter, 1, 1)) + Copy(Letter, 2, MaxInt);
    Upper := False;
    Result := Result + Letter;
    if Length(Result) >= 32 then
      Break;
  end;
  if Result = 'S' then
    Result := 'SText';
end;

function ExecuteResStr(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Token, Literal: TPascalToken;
  Found: Boolean;
  Name, Value: string;
  Start, Index, Last: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Found := False;
    Literal := Default(TPascalToken);
    for Token in Source.Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.StringLiteral) and (Token.StartPos.Line = Source.Line - 1) then
      begin
        Literal := Token;
        Found := True;
        Break;
      end;
    if not Found then
      Exit(Fail('/resstr braucht ein String-Literal in der Zeile darüber', AReason));
    Start := Source.ImplementationStart;
    if Start < 0 then
      Exit(Fail('/resstr braucht einen implementation-Abschnitt', AReason));
    Value := Literal.Text;
    Name := AContext.Arguments;
    if not IsValidIdent(Name) then
      Name := ResourceName(StringReplace(Copy(Value, 2, Length(Value) - 2), '''''', '''', [rfReplaceAll]));
    // Vorhandener resourcestring-Abschnitt hinter implementation: dort anhängen.
    Last := -1;
    for Index := Start + 1 to Source.Line - 1 do
      if SameText(Trim(Source.Lines[Index]), 'resourcestring') then
      begin
        Last := Index;
        while (Last + 1 < Source.Line) and (Pos('=', Source.Lines[Last + 1]) > 0) and
          (Trim(Source.Lines[Last + 1]) <> '') do
          Inc(Last);
        Break;
      end;
    if Last >= 0 then
      AEdits := [Source.AfterLine(Last, Format('  %s = %s;', [Name, Value]))]
    else
      AEdits := [Source.AfterLine(Start, Source.LineBreak + 'resourcestring' + Source.LineBreak +
        Format('  %s = %s;', [Name, Value]))];
    AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(Literal.StartPos, Literal.EndPos), Name),
      Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /guid }

function ExecuteGuid(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Symbol, Target: TIndexSymbol;
  Found: Boolean;
  Index: Integer;
  Guid: TGUID;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Found := False;
    Target := Default(TIndexSymbol);
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.InterfaceType) and (Symbol.Range.StartPos.Line < Source.Line) and
        (Symbol.Range.EndPos.Line >= Source.Line) then
      begin
        Target := Symbol;
        Found := True;
        Break;
      end;
    if not Found then
      Exit(Fail('/guid gilt nur in der Deklaration eines Interfaces', AReason));
    for Index := Target.Range.StartPos.Line to Target.Range.EndPos.Line do
      if StartsStr('[''{', Trim(Source.Lines[Index])) then
        Exit(Fail('Das Interface hat schon eine GUID', AReason));
    CreateGUID(Guid);
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line, Length(AContext.LineText)),
      Copy(AContext.LineText, 1, Pos('/', AContext.LineText) - 1) + Format('[''%s'']', [GUIDToString(Guid)]))];
    Result := True;
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterDeclarationCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('var', 'Lokale Variable anlegen', '/var Liste: TStringList', ExecuteVar));
  ARegistry.Register(Command('const', 'Lokale Konstante anlegen', '/const Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, False, AEdits, AReason);
    end));
  ARegistry.Register(Command('const!', 'Konstante in der implementation anlegen', '/const! Max = 10',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteConst(AContext, True, AEdits, AReason);
    end));
  ARegistry.Register(Command('field', 'Feld im private-Abschnitt anlegen', '/field Name: string', ExecuteField));
  ARegistry.Register(Command('prop', 'Property mit Feld und Setter anlegen', '/prop Name: string', ExecuteProp));
  ARegistry.Register(Command('resstr', 'String-Literal darüber als resourcestring', '/resstr', ExecuteResStr));
  ARegistry.Register(Command('guid', 'GUID in die Interface-Deklaration einfügen', '/guid', ExecuteGuid));
end;

end.
