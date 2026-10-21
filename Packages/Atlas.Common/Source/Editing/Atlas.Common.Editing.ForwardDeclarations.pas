unit Atlas.Common.Editing.ForwardDeclarations;

// Forward-Deklarationen im type-Abschnitt (#685):
//   - Ein Typ wird in einer Typdeklaration benutzt (Feld, Parameter, Ergebnis,
//     Property, generisches Argument, class of), ist aber erst weiter unten im
//     selben Gültigkeitsbereich deklariert (Compiler: E2003). Vorfahren, Aliase
//     (TA = TB) und Zeiger (^T, im selben Block erlaubt) zählen nicht.
//   - Korrektur je nach Lage:
//       Klasse/Interface im selben type-Block   Forward-Deklaration am Blockanfang
//       Forward-Deklaration steht weiter unten   sie nach oben verschieben
//       Klasse/Interface in einem späteren Block Blöcke zusammenlegen: const-,
//                                                var- und label-Abschnitte
//                                                dazwischen wandern vor den
//                                                ersten Block, die übrigen
//                                                verlieren ihr "type"; dazu
//                                                die Forward-Deklaration
//       Record und alle anderen Typen            Deklaration vor den ersten
//                                                Verwender verschieben
//     Geht das nicht ohne neue Lücke, bleibt es beim Treffer mit Begründung.
//   - Forward-Deklarationen, deren Typ vor der vollständigen Deklaration nicht
//     benutzt wird, sind überflüssig ("Entfernen").
// Deklarationen in {$IF…}-Blöcken werden übergangen, weil der Syntaxbaum auch
// inaktive Zweige enthält. Alle Edits einer Korrektur bilden einen Schritt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TForwardIssue = (UsedBeforeDeclaration, UnneededForward);

  TForwardFix = (NoFix, AddForward, MoveForward, MergeBlocks, MoveDeclaration, RemoveForward);

  TForwardFinding = record
    Issue: TForwardIssue;
    /// <summary>Name des zu früh benutzten bzw. vorwärts deklarierten Typs.</summary>
    TypeName: string;
    /// <summary>Typ, in dem die Verwendung steht; '' bei UnneededForward.</summary>
    UserName: string;
    /// <summary>Verwendung bzw. Forward-Deklaration.</summary>
    Range: TTextRange;
    Fix: TForwardFix;
    Edits: TArray<TTextEdit>;
    /// <summary>Warum es keine Korrektur gibt; '' mit Korrektur.</summary>
    Reason: string;
  end;

  TForwardDeclarations = class
  public
    /// <summary>Alle Treffer der Datei in Textreihenfolge.</summary>
    class function Analyze(ATree: TSyntaxTree; const AText: string): TArray<TForwardFinding>; static;
    /// <summary>Titel der Code-Aktion zu AFix; '' für NoFix.</summary>
    class function FixTitle(AFix: TForwardFix): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Text.Lines;

type
  TDecl = record
    Node: TSyntaxNode;
    Section: TSyntaxNode;
    Forward: Boolean;
  end;

  TAnalyzer = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FLines: TArray<string>;
    FTable: TLineTable;
    FBreak: string;
    FConditional: TArray<Boolean>;
    FAll: TArray<TDecl>;
    FFindings: TArray<TForwardFinding>;
    procedure MarkConditional;
    function IsConditional(ANode: TSyntaxNode): Boolean;
    function Source(AStart, AEnd: Integer): string;
    function LineText(ALine: Integer): string;
    function LineCount: Integer;
    function WholeLines(AFirst, ALast: TSyntaxNode; out ARange: TTextRange): Boolean;
    function LinesText(const ARange: TTextRange): string;
    function SectionStart(ASection: TSyntaxNode; const AText: string): TTextEdit;
    function ForwardText(const ADecl: TDecl): string;
    function DropKeyword(ASection: TSyntaxNode; out AEdit: TTextEdit): Boolean;
    function BlockStart(const ADecl: TDecl): TSyntaxNode;
    procedure Scope(AParent: TSyntaxNode);
    procedure UsedBefore(const AUser, ATarget: TDecl; ARef: TSyntaxNode);
    procedure FixMove(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
    procedure FixMerge(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
    procedure Unneeded(const ADecls: TArray<TDecl>; AIndex: Integer);
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    procedure Run;
    property Findings: TArray<TForwardFinding> read FFindings;
  end;

function TypeNode(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind <> TSyntaxKind.GenericParams then
      Exit(ADecl[Index]);
  Result := nil;
end;

function IsForwardDecl(ADecl: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := TypeNode(ADecl);
  Result := (Node <> nil) and (Node.Kind = TSyntaxKind.ForwardType);
end;

/// <summary>Klasse oder Interface: lässt sich vorwärts deklarieren.</summary>
function CanForward(ADecl: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := TypeNode(ADecl);
  Result := (Node <> nil) and ((Node.Kind = TSyntaxKind.ClassType) or (Node.Kind = TSyntaxKind.InterfaceType));
end;

function RangeOf(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function Pos_(ALine, ACharacter: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, ACharacter);
end;

function IsBlank(const AText: string): Boolean;
begin
  Result := Trim(AText) = '';
end;

/// <summary>Verwendungen von Typnamen in ANode: TypeReference ohne Vorfahren, Aliase und Zeiger.</summary>
procedure CollectRefs(ANode, ADecl: TSyntaxNode; var ARefs: TArray<TSyntaxNode>);
var
  Index: Integer;
  Parent: TSyntaxNode;
begin
  if ANode.Kind = TSyntaxKind.TypeReference then
  begin
    Parent := ANode.Parent;
    if (Parent <> ADecl) and (Parent.Kind <> TSyntaxKind.PointerType) and
      (Parent.Kind <> TSyntaxKind.ClassType) and (Parent.Kind <> TSyntaxKind.InterfaceType) and
      (Parent.Kind <> TSyntaxKind.ObjectType) and (Parent.Kind <> TSyntaxKind.HelperType) and
      (Pos('.', ANode.Name) = 0) then
      ARefs := ARefs + [ANode];
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    CollectRefs(ANode[Index], ADecl, ARefs);
end;

function RefsOf(ADecl: TSyntaxNode): TArray<TSyntaxNode>;
begin
  Result := nil;
  CollectRefs(ADecl, ADecl, Result);
end;

/// <summary>Namen aus Bezeichnern und Typverweisen in ANode (erster Teil vor dem Punkt).</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<TSyntaxNode>);
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) or (ANode.Kind = TSyntaxKind.TypeReference) then
    ANames := ANames + [ANode];
  for Index := 0 to ANode.ChildCount - 1 do
    CollectNames(ANode[Index], ANames);
end;

function FirstPart(const AName: string): string;
var
  Dot: Integer;
begin
  Dot := Pos('.', AName);
  if Dot > 0 then
    Result := Copy(AName, 1, Dot - 1)
  else
    Result := AName;
end;

function IsGenericParam(ADecl: TSyntaxNode; const AName: string): Boolean;
var
  Params: TSyntaxNode;
  Index: Integer;
begin
  Params := ADecl.FindChild(TSyntaxKind.GenericParams);
  if Params <> nil then
    for Index := 0 to Params.ChildCount - 1 do
      if SameText(Params[Index].Name, AName) then
        Exit(True);
  Result := False;
end;

/// <summary>Deklarationen (const, var, type) eines Abschnitts.</summary>
function DeclaredNodes(ASection: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ASection.ChildCount - 1 do
    if ASection[Index].Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.TypeDecl] then
      Result := Result + [ASection[Index]];
end;

/// <summary>Namen einer Deklaration; var A, B: Integer hat zwei.</summary>
function NamesOf(ADecl: TSyntaxNode): TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in ADecl.Name.Split([',']) do
    Result := Result + [Trim(Name)];
end;

/// <summary>Deklarierte Namen eines const-, var- oder type-Abschnitts.</summary>
function DeclaredNames(ASection: TSyntaxNode): TArray<string>;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  for Node in DeclaredNodes(ASection) do
    Result := Result + NamesOf(Node);
end;

function SectionWord(ASection: TSyntaxNode): string;
begin
  case ASection.Kind of
    TSyntaxKind.ConstSection:
      Result := 'const';
    TSyntaxKind.VarSection:
      Result := 'var';
    TSyntaxKind.LabelSection:
      Result := 'label';
    TSyntaxKind.TypeSection:
      Result := 'type';
  else
    Result := '';
  end;
end;

{ TAnalyzer }

constructor TAnalyzer.Create(ATree: TSyntaxTree; const AText: string);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FLines := TTextLines.SplitLines(AText, FBreak);
  FTable := TLineTable.Build(AText);
end;

procedure TAnalyzer.MarkConditional;
var
  Token: TPascalToken;
  Text: string;
  Depth, Line, StartLine: Integer;
begin
  SetLength(FConditional, Length(FLines) + 1);
  Depth := 0;
  StartLine := 0;
  for Token in FTree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) then
    begin
      if Depth = 0 then
        StartLine := Token.StartPos.Line;
      Inc(Depth);
    end
    else if (Depth > 0) and (StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) or
      StartsStr('(*$ENDIF', Text) or StartsStr('(*$IFEND', Text)) then
    begin
      Dec(Depth);
      if Depth = 0 then
        for Line := StartLine to Token.EndPos.Line do
          if Line <= High(FConditional) then
            FConditional[Line] := True;
    end;
  end;
  if Depth > 0 then
    for Line := StartLine to High(FConditional) do
      FConditional[Line] := True;
end;

function TAnalyzer.IsConditional(ANode: TSyntaxNode): Boolean;
var
  Line: Integer;
begin
  // Nur die erste Zeile: eine Klasse mit {$IFDEF} im Rumpf bleibt dabei.
  Line := ANode.StartPos.Line;
  Result := (Line >= 0) and (Line <= High(FConditional)) and FConditional[Line];
end;

function TAnalyzer.Source(AStart, AEnd: Integer): string;
begin
  Result := Copy(FText, AStart + 1, AEnd - AStart);
end;

function TAnalyzer.LineText(ALine: Integer): string;
begin
  if (ALine >= 0) and (ALine <= High(FLines)) then
    Result := FLines[ALine]
  else
    Result := '';
end;

function TAnalyzer.LineCount: Integer;
begin
  Result := Length(FLines);
end;

function TAnalyzer.WholeLines(AFirst, ALast: TSyntaxNode; out ARange: TTextRange): Boolean;
var
  First, Last: string;
begin
  // Nur ganze Zeilen verschieben: davor und dahinter darf nichts stehen.
  First := LineText(AFirst.StartPos.Line);
  Last := LineText(ALast.EndPos.Line);
  Result := IsBlank(Copy(First, 1, AFirst.StartPos.Character)) and
    IsBlank(Copy(Last, ALast.EndPos.Character + 1, MaxInt));
  if not Result then
    Exit;
  if ALast.EndPos.Line < LineCount - 1 then
    ARange := TTextRange.Create(Pos_(AFirst.StartPos.Line, 0), Pos_(ALast.EndPos.Line + 1, 0))
  else
    ARange := TTextRange.Create(Pos_(AFirst.StartPos.Line, 0), Pos_(ALast.EndPos.Line, Length(Last)));
end;

function TAnalyzer.LinesText(const ARange: TTextRange): string;
begin
  Result := Source(FTable.OffsetAt(ARange.StartPos), FTable.OffsetAt(ARange.EndPos));
  if (Result <> '') and not EndsStr(#10, Result) and not EndsStr(#13, Result) then
    Result := Result + FBreak;
end;

function TAnalyzer.SectionStart(ASection: TSyntaxNode; const AText: string): TTextEdit;
var
  First: TSyntaxNode;
  At: TTextPosition;
begin
  First := ASection[0];
  if First.StartPos.Line > ASection.StartPos.Line then
  begin
    At := Pos_(First.StartPos.Line, 0);
    Result := TTextEdit.Create(TTextRange.Create(At, At),
      TTextLines.IndentOf(LineText(First.StartPos.Line)) + AText + FBreak);
  end
  else
    Result := TTextEdit.Create(TTextRange.Create(First.StartPos, First.StartPos), AText + ' ');
end;

function TAnalyzer.ForwardText(const ADecl: TDecl): string;
var
  Node, Params: TSyntaxNode;
  Word: string;
begin
  Node := TypeNode(ADecl.Node);
  if Node.Kind = TSyntaxKind.ClassType then
    Word := 'class'
  else
  begin
    // interface oder dispinterface: das Schlüsselwort steht am Anfang des Typs.
    Word := LowerCase(Source(Node.StartOffset, Node.StartOffset + Length('dispinterface')));
    if not StartsStr('dispinterface', Word) then
      Word := 'interface'
    else
      Word := 'dispinterface';
  end;
  Result := ADecl.Node.Name;
  Params := ADecl.Node.FindChild(TSyntaxKind.GenericParams);
  if Params <> nil then
    Result := Result + Source(Params.StartOffset, Params.EndOffset);
  Result := Result + ' = ' + Word + ';';
end;

function TAnalyzer.DropKeyword(ASection: TSyntaxNode; out AEdit: TTextEdit): Boolean;
var
  Line: string;
  Range: TTextRange;
begin
  // "type" allein in der Zeile: die Zeile entfällt; sonst bis zur ersten Deklaration.
  Line := LineText(ASection.StartPos.Line);
  Result := ASection.ChildCount > 0;
  if not Result then
    Exit;
  if SameText(Trim(Line), 'type') then
    Range := TTextRange.Create(Pos_(ASection.StartPos.Line, 0), Pos_(ASection.StartPos.Line + 1, 0))
  else if ASection[0].StartPos.Line = ASection.StartPos.Line then
    Range := TTextRange.Create(ASection.StartPos, ASection[0].StartPos)
  else
    Range := TTextRange.Create(ASection.StartPos, Pos_(ASection.StartPos.Line, ASection.StartPos.Character + 4));
  AEdit := TTextEdit.Create(Range, '');
end;

function TAnalyzer.BlockStart(const ADecl: TDecl): TSyntaxNode;
var
  Index: Integer;
begin
  // Attribute direkt vor der Deklaration gehören dazu.
  Result := ADecl.Node;
  Index := ADecl.Section.ChildCount - 1;
  while (Index >= 0) and (ADecl.Section[Index] <> ADecl.Node) do
    Dec(Index);
  while (Index > 0) and (ADecl.Section[Index - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(Index);
    Result := ADecl.Section[Index];
  end;
end;

procedure TAnalyzer.FixMerge(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
var
  Parent, Child: TSyntaxNode;
  First, Last, Index, Later: Integer;
  Moved, Blocks: TArray<TSyntaxNode>;
  TypeNames: TArray<string>;
  Names: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  Range: TTextRange;
  Edit: TTextEdit;
  Text: string;
begin
  Parent := AUser.Section.Parent;
  First := -1;
  Last := -1;
  for Index := 0 to Parent.ChildCount - 1 do
  begin
    if Parent[Index] = AUser.Section then
      First := Index;
    if Parent[Index] = ATarget.Section then
      Last := Index;
  end;
  Moved := nil;
  Blocks := [AUser.Section];
  for Index := First + 1 to Last do
  begin
    Child := Parent[Index];
    if Child.Kind = TSyntaxKind.TypeSection then
      Blocks := Blocks + [Child]
    else if Child.Kind in [TSyntaxKind.ConstSection, TSyntaxKind.VarSection, TSyntaxKind.LabelSection] then
      Moved := Moved + [Child]
    else
    begin
      AFinding.Reason := 'zwischen den type-Blöcken steht mehr als const, var oder label';
      Exit;
    end;
  end;
  TypeNames := nil;
  for Child in Blocks do
    TypeNames := TypeNames + DeclaredNames(Child);
  // Was die Typen aus den Abschnitten dazwischen brauchen, steht danach weiter vorn und bleibt
  // erreichbar. Brauchen umgekehrt die Abschnitte dazwischen einen der Typen, geht es nicht.
  for Child in Moved do
  begin
    Names := nil;
    CollectNames(Child, Names);
    for Node in Names do
      if MatchText(FirstPart(Node.Name), TypeNames) then
      begin
        AFinding.Reason := Format('der %s-Abschnitt zwischen den type-Blöcken braucht %s',
          [SectionWord(Child), FirstPart(Node.Name)]);
        Exit;
      end;
  end;
  if not IsBlank(Copy(LineText(AUser.Section.StartPos.Line), 1, AUser.Section.StartPos.Character)) then
  begin
    AFinding.Reason := 'der erste type-Block beginnt nicht am Zeilenanfang';
    Exit;
  end;
  Text := '';
  for Child in Moved do
  begin
    if not WholeLines(Child, Child, Range) then
    begin
      AFinding.Reason := Format('der %s-Abschnitt zwischen den type-Blöcken teilt sich Zeilen mit anderem Code',
        [SectionWord(Child)]);
      Exit;
    end;
    Text := Text + LinesText(Range);
    AFinding.Edits := AFinding.Edits + [TTextEdit.Create(Range, '')];
  end;
  for Later := 1 to High(Blocks) do
    if DropKeyword(Blocks[Later], Edit) then
      AFinding.Edits := AFinding.Edits + [Edit];
  if Text <> '' then
    AFinding.Edits := AFinding.Edits + [TTextEdit.Create(TTextRange.Create(Pos_(AUser.Section.StartPos.Line, 0),
      Pos_(AUser.Section.StartPos.Line, 0)), Text)];
  AFinding.Edits := AFinding.Edits + [SectionStart(AUser.Section, ForwardText(ATarget))];
  AFinding.Fix := TForwardFix.MergeBlocks;
end;

procedure TAnalyzer.FixMove(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
var
  UserStart, TargetStart, Section, Node: TSyntaxNode;
  Range: TTextRange;
  Names: TArray<TSyntaxNode>;
  Between: TArray<string>;
  Index: Integer;
  At: TTextPosition;
  OnlyBlock: Boolean;
  Text: string;
begin
  UserStart := BlockStart(AUser);
  TargetStart := BlockStart(ATarget);
  // Was zwischen Verwender und Typ deklariert ist, stünde danach hinter dem Typ: neue Lücke.
  Between := nil;
  for Index := 0 to AUser.Section.Parent.ChildCount - 1 do
  begin
    Section := AUser.Section.Parent[Index];
    if not (Section.Kind in [TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection]) then
      Continue;
    for Node in DeclaredNodes(Section) do
      if (Node.StartOffset >= UserStart.StartOffset) and (Node.StartOffset < TargetStart.StartOffset) then
        Between := Between + NamesOf(Node);
  end;
  Names := nil;
  CollectNames(ATarget.Node, Names);
  for Node in Names do
    if not SameText(Node.Name, ATarget.Node.Name) and not IsGenericParam(ATarget.Node, Node.Name) and
      MatchText(FirstPart(Node.Name), Between) then
    begin
      AFinding.Reason := Format('%s braucht %s, das davor deklariert ist', [ATarget.Node.Name, FirstPart(Node.Name)]);
      Exit;
    end;
  if not IsBlank(Copy(LineText(UserStart.StartPos.Line), 1, UserStart.StartPos.Character)) then
  begin
    AFinding.Reason := Format('%s beginnt nicht am Zeilenanfang', [AUser.Node.Name]);
    Exit;
  end;
  // Besteht der Block nur aus dem Typ, entfällt er ganz.
  OnlyBlock := (ATarget.Section <> AUser.Section) and (ATarget.Section[0] = TargetStart) and
    (ATarget.Section[ATarget.Section.ChildCount - 1] = ATarget.Node);
  if OnlyBlock then
    OnlyBlock := WholeLines(ATarget.Section, ATarget.Section, Range);
  if not OnlyBlock and not WholeLines(TargetStart, ATarget.Node, Range) then
  begin
    AFinding.Reason := Format('%s teilt sich Zeilen mit anderem Code', [ATarget.Node.Name]);
    Exit;
  end;
  Text := TTextLines.IndentOf(LineText(UserStart.StartPos.Line)) +
    Source(TargetStart.StartOffset, ATarget.Node.EndOffset) + FBreak;
  At := Pos_(UserStart.StartPos.Line, 0);
  AFinding.Edits := [TTextEdit.Create(TTextRange.Create(At, At), Text), TTextEdit.Create(Range, '')];
  AFinding.Fix := TForwardFix.MoveDeclaration;
end;

procedure TAnalyzer.UsedBefore(const AUser, ATarget: TDecl; ARef: TSyntaxNode);
var
  Finding: TForwardFinding;
  Range: TTextRange;
begin
  Finding := Default(TForwardFinding);
  Finding.Issue := TForwardIssue.UsedBeforeDeclaration;
  Finding.TypeName := ATarget.Node.Name;
  Finding.UserName := AUser.Node.Name;
  Finding.Range := RangeOf(ARef);
  if ATarget.Forward then
  begin
    // Die Forward-Deklaration gibt es schon, nur zu weit unten.
    if ATarget.Section <> AUser.Section then
      Finding.Reason := 'die Forward-Deklaration steht in einem späteren type-Block'
    else if not WholeLines(ATarget.Node, ATarget.Node, Range) then
      Finding.Reason := 'die Forward-Deklaration teilt sich die Zeile mit anderem Code'
    else
    begin
      Finding.Edits := [TTextEdit.Create(Range, ''),
        SectionStart(AUser.Section, Source(ATarget.Node.StartOffset, ATarget.Node.EndOffset))];
      Finding.Fix := TForwardFix.MoveForward;
    end;
  end
  else if CanForward(ATarget.Node) then
  begin
    if ATarget.Section = AUser.Section then
    begin
      Finding.Edits := [SectionStart(AUser.Section, ForwardText(ATarget))];
      Finding.Fix := TForwardFix.AddForward;
    end
    else
      FixMerge(Finding, AUser, ATarget);
  end
  else
    FixMove(Finding, AUser, ATarget);
  if Finding.Fix = TForwardFix.NoFix then
    Finding.Edits := nil;
  FFindings := FFindings + [Finding];
end;

procedure TAnalyzer.Unneeded(const ADecls: TArray<TDecl>; AIndex: Integer);
var
  Forward_: TDecl;
  Full, Index: Integer;
  Ref: TSyntaxNode;
  Finding: TForwardFinding;
  Range: TTextRange;
  Line: string;
  Stop: Integer;
begin
  Forward_ := ADecls[AIndex];
  Full := -1;
  for Index := AIndex + 1 to High(ADecls) do
    if (ADecls[Index].Section = Forward_.Section) and not ADecls[Index].Forward and
      SameText(ADecls[Index].Node.Name, Forward_.Node.Name) then
    begin
      Full := Index;
      Break;
    end;
  // Ohne vollständige Deklaration im Block meldet der Compiler selbst (E2086).
  if Full < 0 then
    Exit;
  // Benutzt vor der vollständigen Deklaration, auch schon vor der Forward-Deklaration (dann steht
  // sie zu weit unten, das meldet type-used-before-declaration).
  for Index := 0 to Full - 1 do
    if (Index <> AIndex) and (ADecls[Index].Section = Forward_.Section) then
      for Ref in RefsOf(ADecls[Index].Node) do
        if SameText(Ref.Name, Forward_.Node.Name) then
          Exit;
  Finding := Default(TForwardFinding);
  Finding.Issue := TForwardIssue.UnneededForward;
  Finding.TypeName := Forward_.Node.Name;
  Finding.Range := RangeOf(Forward_.Node);
  if not WholeLines(Forward_.Node, Forward_.Node, Range) then
  begin
    // Mit anderen Deklarationen in der Zeile: nur sie samt folgenden Leerzeichen.
    Line := LineText(Forward_.Node.EndPos.Line);
    Stop := Forward_.Node.EndPos.Character;
    while (Stop < Length(Line)) and CharInSet(Line[Stop + 1], [' ', #9]) do
      Inc(Stop);
    Range := TTextRange.Create(Forward_.Node.StartPos, Pos_(Forward_.Node.EndPos.Line, Stop));
  end;
  Finding.Edits := [TTextEdit.Create(Range, '')];
  Finding.Fix := TForwardFix.RemoveForward;
  FFindings := FFindings + [Finding];
end;

procedure TAnalyzer.Scope(AParent: TSyntaxNode);
var
  Decls: TArray<TDecl>;
  Decl: TDecl;
  Section, Ref: TSyntaxNode;
  Index, Child, Target: Integer;
  Name: string;
  Before: Boolean;
begin
  Decls := nil;
  for Index := 0 to AParent.ChildCount - 1 do
  begin
    Section := AParent[Index];
    if Section.Kind <> TSyntaxKind.TypeSection then
      Continue;
    for Child := 0 to Section.ChildCount - 1 do
      if (Section[Child].Kind = TSyntaxKind.TypeDecl) and not IsConditional(Section[Child]) then
      begin
        Decl.Node := Section[Child];
        Decl.Section := Section;
        Decl.Forward := IsForwardDecl(Section[Child]);
        Decls := Decls + [Decl];
      end;
  end;
  for Index := 0 to High(Decls) do
  begin
    if Decls[Index].Forward then
      Continue;
    for Ref in RefsOf(Decls[Index].Node) do
    begin
      Name := Ref.Name;
      if (Name = '') or SameText(Name, Decls[Index].Node.Name) or IsGenericParam(Decls[Index].Node, Name) or
        IsConditional(Ref) then
        Continue;
      // Irgendwo davor deklariert (auch im interface für das implementation): kein Treffer.
      Before := False;
      for Decl in FAll do
        if SameText(Decl.Node.Name, Name) and (Decl.Node.StartOffset < Ref.StartOffset) then
        begin
          Before := True;
          Break;
        end;
      if Before then
        Continue;
      Target := -1;
      for Child := 0 to High(Decls) do
        if SameText(Decls[Child].Node.Name, Name) and (Decls[Child].Node.StartOffset > Ref.StartOffset) then
        begin
          Target := Child;
          Break;
        end;
      if Target >= 0 then
        UsedBefore(Decls[Index], Decls[Target], Ref);
    end;
  end;
  for Index := 0 to High(Decls) do
    if Decls[Index].Forward then
      Unneeded(Decls, Index);
end;

procedure TAnalyzer.Run;
var
  Scopes: TList<TSyntaxNode>;
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Child: Integer;
  HasTypes: Boolean;
  Decl: TDecl;
begin
  MarkConditional;
  Scopes := TList<TSyntaxNode>.Create;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(FTree.Root);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      HasTypes := False;
      for Index := 0 to Node.ChildCount - 1 do
      begin
        if Node[Index].Kind = TSyntaxKind.TypeSection then
        begin
          HasTypes := True;
          for Child := 0 to Node[Index].ChildCount - 1 do
            if Node[Index][Child].Kind = TSyntaxKind.TypeDecl then
            begin
              Decl.Node := Node[Index][Child];
              Decl.Section := Node[Index];
              Decl.Forward := IsForwardDecl(Decl.Node);
              FAll := FAll + [Decl];
            end;
        end;
        Pending.Push(Node[Index]);
      end;
      if HasTypes then
        Scopes.Add(Node);
    end;
    for Node in Scopes do
      Scope(Node);
  finally
    Pending.Free;
    Scopes.Free;
  end;
  // Textreihenfolge.
  TArray.Sort<TForwardFinding>(FFindings, TComparer<TForwardFinding>.Construct(
    function(const ALeft, ARight: TForwardFinding): Integer
    begin
      Result := ALeft.Range.StartPos.Line - ARight.Range.StartPos.Line;
      if Result = 0 then
        Result := ALeft.Range.StartPos.Character - ARight.Range.StartPos.Character;
    end));
end;

{ TForwardDeclarations }

class function TForwardDeclarations.Analyze(ATree: TSyntaxTree; const AText: string): TArray<TForwardFinding>;
var
  Analyzer: TAnalyzer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Analyzer := TAnalyzer.Create(ATree, AText);
  try
    Analyzer.Run;
    Result := Analyzer.Findings;
  finally
    Analyzer.Free;
  end;
end;

class function TForwardDeclarations.FixTitle(AFix: TForwardFix): string;
begin
  case AFix of
    TForwardFix.AddForward:
      Result := 'Forward-Deklaration ergänzen';
    TForwardFix.MoveForward:
      Result := 'Forward-Deklaration nach oben verschieben';
    TForwardFix.MergeBlocks:
      Result := 'type-Blöcke zusammenlegen';
    TForwardFix.MoveDeclaration:
      Result := 'Deklaration nach oben verschieben';
    TForwardFix.RemoveForward:
      Result := 'Forward-Deklaration entfernen';
  else
    Result := '';
  end;
end;

end.
