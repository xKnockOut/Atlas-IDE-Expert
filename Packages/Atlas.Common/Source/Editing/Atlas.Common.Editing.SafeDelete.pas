unit Atlas.Common.Editing.SafeDelete;

// Sicher löschen (#716), Teil ohne Projekt: welches Symbol an einer Stelle
// steht, welche Zeilen zu ihm gehören und wie es samt allem Zugehörigen aus
// der Datei verschwindet.
//   - Symbole: Methode (Deklaration und Rumpf, Überladungen einzeln), Feld
//     (aus einer Gruppe nur der Name), Property, Typ (eine Klasse samt allen
//     Rümpfen), Konstante, globale Variable, Routine der Unit (Deklaration im
//     interface, forward und Rumpf), lokale Routine und die ganze Unit (auf
//     der Zeile "unit X;").
//   - Doku-Kommentar (///) und Attribute direkt darüber gehen mit.
//   - Ein Abschnitt (type, const, var), der dadurch leer wird, fällt weg,
//     ebenso ein leerer Sichtbarkeitsabschnitt einer Klasse.
//   - FreedMembers: private Mitglieder, die nur noch von gelöschten
//     Mitgliedern benutzt wurden (Folgeschritt, auch über mehrere Stufen).
// Verwendungen im Projekt, Formulare, Überschreibungen und uses prüft die
// Protokollschicht (TLspSafeDelete).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout;

type
  {$SCOPEDENUMS ON}
  TSafeDeleteKind = (Method, Field, Property_, Type_, Constant, Variable, Routine, LocalRoutine, Unit_);
  {$SCOPEDENUMS OFF}

  TSafeDeleteTarget = record
    Kind: TSafeDeleteKind;
    Name: string;
    /// <summary>Klasse eines Mitglieds; '' sonst.</summary>
    ClassName: string;
    /// <summary>Index in TClassLayout.Members bei Mitgliedern; -1 sonst.</summary>
    Member: Integer;
    /// <summary>TypeDecl, ConstDecl, VarDecl oder RoutineDecl; nil bei Mitgliedern und Units.</summary>
    Node: TSyntaxNode;
    /// <summary>Name in der Deklaration, Start der Referenzsuche.</summary>
    NameRange: TTextRange;
    IsPublished: Boolean;
    /// <summary>virtual, dynamic oder abstract ohne override.</summary>
    IsVirtual: Boolean;
    IsOverride: Boolean;
    /// <summary>Methode, Typ, …</summary>
    class function KindName(AKind: TSafeDeleteKind): string; static;
  end;

  TLineSpan = record
    First: Integer;
    Last: Integer;
    class function Create(AFirst, ALast: Integer): TLineSpan; static;
    function Contains(ALine: Integer): Boolean;
  end;

  TSafeDelete = class
  public const
    Kind = 'refactor';
  public
    /// <summary>Symbol an APosition. Sonst nennt AReason den Grund ('' wenn dort gar kein Symbol steht).
    /// </summary>
    class function Find(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out ATarget: TSafeDeleteTarget; out AReason: string): Boolean; static;
    /// <summary>Ziel für das Mitglied AMember von ALayout.</summary>
    class function ForMember(ALayout: TClassLayout; AMember: Integer): TSafeDeleteTarget; static;
    /// <summary>Zeilen, die mit ATarget wegfallen: Deklaration samt Doku und Attributen, Rümpfe.</summary>
    class function OwnLines(ATree: TSyntaxTree; const AText: string; const ATarget: TSafeDeleteTarget):
      TArray<TLineSpan>; static;
    /// <summary>Alle ATargets (aus derselben Datei, ohne Units) löschen, leere Abschnitte ebenso.</summary>
    class function Edits(ATree: TSyntaxTree; const AText: string; const ATargets: TArray<TSafeDeleteTarget>):
      TArray<TTextEdit>; static;
    /// <summary>Private Mitglieder, die nur noch von ADeleted (und von einander) benutzt wurden, nicht aber
    /// außerhalb der Klasse in derselben Unit. Ohne ADeleted selbst.</summary>
    class function FreedMembers(ALayout: TClassLayout; const ADeleted: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Titel der Code-Aktion.</summary>
    class function Title(const ATarget: TSafeDeleteTarget): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.MemberTransfer;

{ TSafeDeleteTarget }

class function TSafeDeleteTarget.KindName(AKind: TSafeDeleteKind): string;
begin
  case AKind of
    TSafeDeleteKind.Method:
      Result := 'Methode';
    TSafeDeleteKind.Field:
      Result := 'Feld';
    TSafeDeleteKind.Property_:
      Result := 'Property';
    TSafeDeleteKind.Type_:
      Result := 'Typ';
    TSafeDeleteKind.Constant:
      Result := 'Konstante';
    TSafeDeleteKind.Variable:
      Result := 'Variable';
    TSafeDeleteKind.Routine:
      Result := 'Routine';
    TSafeDeleteKind.LocalRoutine:
      Result := 'lokale Routine';
  else
    Result := 'Unit';
  end;
end;

{ TLineSpan }

class function TLineSpan.Create(AFirst, ALast: Integer): TLineSpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

function TLineSpan.Contains(ALine: Integer): Boolean;
begin
  Result := (ALine >= First) and (ALine <= Last);
end;

function Fail(out AReason: string; const AMessage: string): Boolean;
begin
  AReason := AMessage;
  Result := False;
end;

function TextLines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

/// <summary>Bezeichner an APosition; -1 ohne.</summary>
function IdentifierAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].StartPos.Line > APosition.Line then
      Break;
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (ATokens[Index].StartPos.Line = APosition.Line) and
      (ATokens[Index].StartPos.Character <= APosition.Character) and
      (ATokens[Index].EndPos.Character >= APosition.Character) then
      Exit(Index);
  end;
  Result := -1;
end;

/// <summary>Bereich des ersten Bezeichners AName in ANode (ohne Punkt-Präfix: der letzte Teil zählt).</summary>
function NameRangeIn(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string; out ARange: TTextRange): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := ATree.Tokens;
  Index := TokenIndexAt(Tokens, ANode.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
  begin
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
    begin
      ARange := TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos);
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

function LastPart(const AName: string): string;
begin
  Result := AName;
  if Pos('.', Result) > 0 then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

/// <summary>Erste Zeile von ANode samt Attributen (Geschwister davor) und Doku-Kommentar darüber.</summary>
function FirstLineOf(ANode: TSyntaxNode; const ALines: TArray<string>): Integer;
var
  Parent: TSyntaxNode;
  Index: Integer;
begin
  Result := ANode.StartPos.Line;
  Parent := ANode.Parent;
  if Parent <> nil then
  begin
    Index := 0;
    while (Index < Parent.ChildCount) and (Parent[Index] <> ANode) do
      Inc(Index);
    Dec(Index);
    while (Index >= 0) and (Parent[Index].Kind = TSyntaxKind.Attribute) do
    begin
      Result := Parent[Index].StartPos.Line;
      Dec(Index);
    end;
  end;
  while (Result > 0) and StartsText('///', Trim(ALines[Result - 1])) do
    Dec(Result);
end;

/// <summary>Steht ANode allein auf seinen Zeilen (davor und dahinter nur Leerraum bzw. Kommentar)?</summary>
function AloneOnLines(ANode: TSyntaxNode; const ALines: TArray<string>): Boolean;
var
  Before, After: string;
begin
  Before := Copy(ALines[ANode.StartPos.Line], 1, ANode.StartPos.Character);
  After := Trim(Copy(ALines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
  Result := (Trim(Before) = '') and ((After = '') or StartsText('//', After));
end;

/// <summary>Routinen auf oberster Ebene (interface und implementation) mit Namen AName.</summary>
function TopRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl]);
      if (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(ANode.Name, AName) then
        Found := Found + [ANode];
    end);
  Result := Found;
end;

function ParameterText(const AText: string; ARoutine: TSyntaxNode): string;
var
  Header, Parameters: TSyntaxNode;
begin
  Result := '';
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
    Result := CollapseSpace(Copy(AText, Parameters.StartOffset + 1, Parameters.EndOffset - Parameters.StartOffset));
end;

function IsInsideRoutine(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if Parent.Kind = TSyntaxKind.RoutineDecl then
      Exit(True);
    Parent := Parent.Parent;
  end;
  Result := False;
end;

{ TSafeDelete }

class function TSafeDelete.ForMember(ALayout: TClassLayout; AMember: Integer): TSafeDeleteTarget;
var
  Member: TClassMember;
begin
  Member := ALayout.Members[AMember];
  Result := Default(TSafeDeleteTarget);
  Result.Member := AMember;
  Result.ClassName := ALayout.Name;
  Result.Name := Member.Name;
  case Member.Kind of
    TClassMemberKind.Field, TClassMemberKind.ClassVar:
      Result.Kind := TSafeDeleteKind.Field;
    TClassMemberKind.Property_:
      Result.Kind := TSafeDeleteKind.Property_;
  else
    Result.Kind := TSafeDeleteKind.Method;
  end;
  Result.IsPublished := Member.Visibility = TClassVisibility.Published_;
  Result.IsOverride := Member.HasDirective('override');
  Result.IsVirtual := Member.IsVirtual and not Result.IsOverride;
  if not NameRangeIn(ALayout.Tree, Member.Node, Member.Name, Result.NameRange) then
    Result.NameRange := TTextRange.Create(Member.Node.StartPos, Member.Node.StartPos);
end;

class function TSafeDelete.Find(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Token, Index, Hit: Integer;
  Decl, Found, Routine: TSyntaxNode;
  Layout: TClassLayout;
  Name, ClassName: string;
  Names: TArray<string>;
begin
  Result := False;
  AReason := '';
  ATarget := Default(TSafeDeleteTarget);
  ATarget.Member := -1;
  Tokens := ATree.Tokens;
  Token := IdentifierAt(Tokens, APosition);
  // Unit: auf der Zeile "unit X;".
  if (ATree.Root.Kind = TSyntaxKind.UnitFile) and (APosition.Line = ATree.Root.StartPos.Line) then
  begin
    ATarget.Kind := TSafeDeleteKind.Unit_;
    ATarget.Name := ATree.Root.Name;
    ATarget.NameRange := TTextRange.Create(APosition, APosition);
    Exit(True);
  end;
  // Klasse: Kopfzeile = ganzer Typ, sonst ein Mitglied.
  Decl := TClassLayout.DeclAt(ATree, APosition.Line, True);
  if Decl <> nil then
  begin
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      if APosition.Line = Layout.HeaderLine then
      begin
        ATarget.Kind := TSafeDeleteKind.Type_;
        ATarget.Name := Layout.Name;
        ATarget.Node := Decl;
        NameRangeIn(ATree, Decl, Layout.Name, ATarget.NameRange);
        Exit(True);
      end;
      Hit := Layout.MemberAtLine(APosition.Line);
      if Hit < 0 then
        Exit;
      // Aus einer Feldgruppe der Name unter dem Cursor.
      if (Token >= 0) and Layout.Members[Hit].IsFieldGroup then
        for Index in Layout.Find(Tokens[Token].Text) do
          if Layout.Members[Index].Node = Layout.Members[Hit].Node then
            Hit := Index;
      if Layout.Members[Hit].Kind = TClassMemberKind.Other then
      begin
        if Layout.Members[Hit].Node.Kind <> TSyntaxKind.RoutineHeader then
          Exit(Fail(AReason, 'Diese Deklaration kann Atlas nicht sicher löschen.'));
      end;
      ATarget := ForMember(Layout, Hit);
      Exit(True);
    finally
      Layout.Free;
    end;
  end;
  // Routinen: Rumpf einer Methode, lokale Routine, Routine der Unit.
  Routine := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= APosition.Line) and (ANode.EndPos.Line >= APosition.Line);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.StartPos.Line = APosition.Line) then
        Routine := ANode;
    end);
  if Routine <> nil then
  begin
    if IsInsideRoutine(Routine) then
    begin
      ATarget.Kind := TSafeDeleteKind.LocalRoutine;
      ATarget.Name := Routine.Name;
      ATarget.Node := Routine;
      NameRangeIn(ATree, Routine, Routine.Name, ATarget.NameRange);
      Exit(True);
    end;
    if Pos('.', Routine.Name) > 0 then
    begin
      ClassName := Copy(Routine.Name, 1, LastDelimiter('.', Routine.Name) - 1);
      Decl := TClassLayout.DeclNamed(ATree, LastPart(ClassName));
      if Decl = nil then
        Exit(Fail(AReason, Format('Die Klasse %s steht nicht in dieser Unit.', [ClassName])));
      Layout := TClassLayout.Read(ATree, AText, Decl);
      try
        for Index := 0 to High(Layout.Members) do
          if Layout.Members[Index].Body = Routine then
          begin
            ATarget := ForMember(Layout, Index);
            Exit(True);
          end;
      finally
        Layout.Free;
      end;
      Exit(Fail(AReason, Format('Die Deklaration von %s ist nicht zu finden.', [Routine.Name])));
    end;
    ATarget.Kind := TSafeDeleteKind.Routine;
    ATarget.Name := Routine.Name;
    ATarget.Node := Routine;
    NameRangeIn(ATree, Routine, Routine.Name, ATarget.NameRange);
    Exit(True);
  end;
  // Typ, Konstante, Variable.
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (Found = nil) and (ANode.StartPos.Line <= APosition.Line) and (ANode.EndPos.Line >= APosition.Line);
      if Result and (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
      begin
        Found := ANode;
        Result := False;
      end;
    end);
  if Found = nil then
    Exit;
  ATarget.Node := Found;
  case Found.Kind of
    TSyntaxKind.TypeDecl:
      begin
        ATarget.Kind := TSafeDeleteKind.Type_;
        ATarget.Name := Found.Name;
        if Pos('<', ATarget.Name) > 0 then
          ATarget.Name := Copy(ATarget.Name, 1, Pos('<', ATarget.Name) - 1);
      end;
    TSyntaxKind.ConstDecl:
      begin
        ATarget.Kind := TSafeDeleteKind.Constant;
        ATarget.Name := Found.Name;
      end;
  else
    ATarget.Kind := TSafeDeleteKind.Variable;
    Names := Found.Name.Split([',']);
    Name := Trim(Names[0]);
    if Token >= 0 then
      for Index := 0 to High(Names) do
        if SameText(Trim(Names[Index]), Tokens[Token].Text) then
          Name := Trim(Names[Index]);
    ATarget.Name := Name;
  end;
  if (Found.Kind = TSyntaxKind.VarDecl) and IsInsideRoutine(Found) then
    Exit(Fail(AReason, 'Lokale Variablen löscht die Regel unused-local.'));
  if not NameRangeIn(ATree, Found, ATarget.Name, ATarget.NameRange) then
    ATarget.NameRange := TTextRange.Create(Found.StartPos, Found.StartPos);
  Result := True;
end;

class function TSafeDelete.OwnLines(ATree: TSyntaxTree; const AText: string;
  const ATarget: TSafeDeleteTarget): TArray<TLineSpan>;
var
  Lines: TArray<string>;
  Decl, Routine: TSyntaxNode;
  Layout: TClassLayout;
  Member: TClassMember;
  Parameters, Prefix: string;
  Spans: TArray<TLineSpan>;
begin
  Result := nil;
  Lines := TextLines(AText);
  case ATarget.Kind of
    TSafeDeleteKind.Method, TSafeDeleteKind.Field, TSafeDeleteKind.Property_:
      begin
        Decl := TClassLayout.DeclNamed(ATree, ATarget.ClassName);
        if Decl = nil then
          Exit;
        Layout := TClassLayout.Read(ATree, AText, Decl);
        try
          Member := Layout.Members[ATarget.Member];
          Result := [TLineSpan.Create(Member.FirstLine, Member.LastLine)];
          if Member.Body <> nil then
            Result := Result + [TLineSpan.Create(Member.BodyFirstLine, Member.BodyLastLine)];
        finally
          Layout.Free;
        end;
      end;
    TSafeDeleteKind.Type_:
      begin
        // Rümpfe einer Klasse, auch verschachtelter Typen.
        Spans := [TLineSpan.Create(FirstLineOf(ATarget.Node, Lines), ATarget.Node.EndPos.Line)];
        Prefix := ATarget.Name + '.';
        ATree.Root.Walk(
          function(ANode: TSyntaxNode): Boolean
          begin
            Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
            if not Result and StartsText(Prefix, ANode.Name) then
              Spans := Spans + [TLineSpan.Create(FirstLineOf(ANode, Lines), ANode.EndPos.Line)];
          end);
        Result := Spans;
      end;
    TSafeDeleteKind.Constant, TSafeDeleteKind.Variable, TSafeDeleteKind.LocalRoutine:
      Result := [TLineSpan.Create(FirstLineOf(ATarget.Node, Lines), ATarget.Node.EndPos.Line)];
    TSafeDeleteKind.Routine:
      begin
        Parameters := ParameterText(AText, ATarget.Node);
        for Routine in TopRoutines(ATree, ATarget.Name) do
          if ParameterText(AText, Routine) = Parameters then
            Result := Result + [TLineSpan.Create(FirstLineOf(Routine, Lines), Routine.EndPos.Line)];
      end;
    TSafeDeleteKind.Unit_: ;
  end;
end;

/// <summary>Edit, das den Namen AName aus der Gruppe ADecl ("A, B: Integer") samt Komma streicht.</summary>
function GroupNameEdit(ATree: TSyntaxTree; ADecl: TSyntaxNode; const AName: string; out AEdit: TTextEdit): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Name, Next, Previous: Integer;
begin
  Result := False;
  Tokens := ATree.Tokens;
  Name := -1;
  Index := TokenIndexAt(Tokens, ADecl.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ADecl.EndOffset) and not Tokens[Index].IsSymbol(':') do
  begin
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
      Name := Index;
    Inc(Index);
  end;
  if Name < 0 then
    Exit;
  Next := Name + 1;
  while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
    Inc(Next);
  if (Next <= High(Tokens)) and Tokens[Next].IsSymbol(',') then
  begin
    Inc(Next);
    while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
      Inc(Next);
    AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Name].StartPos, Tokens[Next].StartPos), '');
    Exit(True);
  end;
  Previous := Name - 1;
  while (Previous >= 0) and IsTrivia(Tokens[Previous]) do
    Dec(Previous);
  if (Previous < 0) or not Tokens[Previous].IsSymbol(',') then
    Exit;
  AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Previous].StartPos, Tokens[Name].EndPos), '');
  Result := True;
end;

function IsDeclaration(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl];
end;

function HasNode(const AList: TArray<TSyntaxNode>; ANode: TSyntaxNode): Boolean;
var
  Item: TSyntaxNode;
begin
  for Item in AList do
    if Item = ANode then
      Exit(True);
  Result := False;
end;

class function TSafeDelete.Edits(ATree: TSyntaxTree; const AText: string;
  const ATargets: TArray<TSafeDeleteTarget>): TArray<TTextEdit>;
var
  Lines: TArray<string>;
  Spans, Merged: TArray<TLineSpan>;
  Partial: TArray<TTextEdit>;
  Nodes, Sections: TArray<TSyntaxNode>;
  Classes, DeletedClasses, Names: TArray<string>;
  Target: TSafeDeleteTarget;
  Indexes: TArray<Integer>;
  Decl, Node, Section: TSyntaxNode;
  Layout: TClassLayout;
  ClassName, Name: string;
  Index, Child, Last: Integer;
  AllGone, Taken: Boolean;
  Edit: TTextEdit;
  Span, Swap: TLineSpan;
begin
  Result := nil;
  Lines := TextLines(AText);
  Spans := nil;
  Partial := nil;
  Nodes := nil;
  DeletedClasses := nil;
  for Target in ATargets do
    if Target.Kind = TSafeDeleteKind.Type_ then
      DeletedClasses := DeletedClasses + [Target.Name];
  // Mitglieder je Klasse in einem Schritt (Feldgruppen, leere Abschnitte).
  Classes := nil;
  for Target in ATargets do
    if (Target.Member >= 0) and (IndexText(Target.ClassName, Classes) < 0) and
      (IndexText(Target.ClassName, DeletedClasses) < 0) then
      Classes := Classes + [Target.ClassName];
  for ClassName in Classes do
  begin
    Decl := TClassLayout.DeclNamed(ATree, ClassName);
    if Decl = nil then
      Continue;
    Indexes := nil;
    for Target in ATargets do
      if (Target.Member >= 0) and SameText(Target.ClassName, ClassName) and
        not TMemberTransfer.Has(Indexes, Target.Member) then
        Indexes := Indexes + [Target.Member];
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      Result := Result + TClassEdits.DeleteMembers(Layout, Indexes, True) +
        TMemberTransfer.EmptiedSections(Layout, Indexes);
    finally
      Layout.Free;
    end;
  end;
  // Deklarationen der Unit: ganz gelöschte Knoten sammeln, Namen aus Gruppen einzeln.
  for Target in ATargets do
    case Target.Kind of
      TSafeDeleteKind.Type_, TSafeDeleteKind.Constant:
        Nodes := Nodes + [Target.Node];
      TSafeDeleteKind.Variable:
        begin
          Names := Target.Node.Name.Split([',']);
          if Length(Names) <= 1 then
            Nodes := Nodes + [Target.Node]
          else
          begin
            // Alle Namen der Gruppe gewählt: der ganze Knoten.
            AllGone := True;
            for Name in Names do
            begin
              Taken := False;
              for Index := 0 to High(ATargets) do
                if (ATargets[Index].Node = Target.Node) and SameText(ATargets[Index].Name, Trim(Name)) then
                  Taken := True;
              AllGone := AllGone and Taken;
            end;
            if AllGone then
            begin
              if not HasNode(Nodes, Target.Node) then
                Nodes := Nodes + [Target.Node];
            end
            else if GroupNameEdit(ATree, Target.Node, Target.Name, Edit) then
              Partial := Partial + [Edit];
          end;
        end;
      TSafeDeleteKind.LocalRoutine:
        if AloneOnLines(Target.Node, Lines) then
          Spans := Spans + [TLineSpan.Create(FirstLineOf(Target.Node, Lines), Target.Node.EndPos.Line)]
        else
          Partial := Partial + [TTextEdit.Create(TTextRange.Create(Target.Node.StartPos, Target.Node.EndPos), '')];
      TSafeDeleteKind.Routine:
        Spans := Spans + OwnLines(ATree, AText, Target);
      TSafeDeleteKind.Method, TSafeDeleteKind.Field, TSafeDeleteKind.Property_, TSafeDeleteKind.Unit_: ;
    end;
  // Rümpfe gelöschter Klassen.
  for Target in ATargets do
    if Target.Kind = TSafeDeleteKind.Type_ then
    begin
      Merged := OwnLines(ATree, AText, Target);
      for Index := 1 to High(Merged) do
        Spans := Spans + [Merged[Index]];
    end;
  // Abschnitte: ganz leer → der ganze Abschnitt, sonst je Knoten.
  Sections := nil;
  for Node in Nodes do
    if (Node.Parent <> nil) and not HasNode(Sections, Node.Parent) then
      Sections := Sections + [Node.Parent];
  for Section in Sections do
  begin
    AllGone := True;
    for Child := 0 to Section.ChildCount - 1 do
      if IsDeclaration(Section[Child]) and not HasNode(Nodes, Section[Child]) then
        AllGone := False;
    if AllGone and (Section.Kind in [TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection]) and
      AloneOnLines(Section, Lines) then
    begin
      Spans := Spans + [TLineSpan.Create(FirstLineOf(Section, Lines), Section.EndPos.Line)];
      Continue;
    end;
    for Node in Nodes do
      if Node.Parent = Section then
      begin
        if AloneOnLines(Node, Lines) then
          Spans := Spans + [TLineSpan.Create(FirstLineOf(Node, Lines), Node.EndPos.Line)]
        else
          Partial := Partial + [TTextEdit.Create(TTextRange.Create(Node.StartPos, Node.EndPos), '')];
      end;
  end;
  // Zeilenbereiche sortieren und zusammenfassen.
  for Index := 1 to High(Spans) do
    for Child := Index downto 1 do
      if Spans[Child].First < Spans[Child - 1].First then
      begin
        Swap := Spans[Child];
        Spans[Child] := Spans[Child - 1];
        Spans[Child - 1] := Swap;
      end;
  Merged := nil;
  for Span in Spans do
    if (Merged <> nil) and (Span.First <= Merged[High(Merged)].Last + 1) then
    begin
      if Span.Last > Merged[High(Merged)].Last then
        Merged[High(Merged)].Last := Span.Last;
    end
    else
      Merged := Merged + [Span];
  for Span in Merged do
  begin
    Last := Span.Last;
    // Eine Leerzeile dahinter mitnehmen, wenn davor auch eine steht.
    if (Last + 1 <= High(Lines)) and (Trim(Lines[Last + 1]) = '') and ((Span.First = 0) or
      (Trim(Lines[Span.First - 1]) = '')) then
      Inc(Last);
    Result := Result + [TTextEdit.Create(TTextRange.Create(Span.First, 0, Last + 1, 0), '')];
  end;
  for Edit in Partial do
  begin
    Taken := False;
    for Span in Merged do
      if Span.Contains(Edit.Range.StartPos.Line) then
        Taken := True;
    if not Taken then
      Result := Result + [Edit];
  end;
end;

class function TSafeDelete.FreedMembers(ALayout: TClassLayout; const ADeleted: TArray<Integer>): TArray<Integer>;
var
  Deleted, Users: TArray<Integer>;
  Index: Integer;
  Member: TClassMember;
  Changed: Boolean;
begin
  Result := nil;
  Deleted := ADeleted;
  repeat
    Changed := False;
    for Index := 0 to High(ALayout.Members) do
    begin
      if TMemberTransfer.Has(Deleted, Index) then
        Continue;
      Member := ALayout.Members[Index];
      if not (Member.Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_]) or
        (Member.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_, TClassMemberKind.Other]) or
        Member.IsVirtual or Member.HasDirective('message') then
        Continue;
      // Nur, was gelöschte Mitglieder benutzt haben; was schon vorher unbenutzt war, meldet unused-private-member.
      Users := ALayout.UsersOf(Index);
      if (Users = nil) or not TMemberTransfer.HasAll(Users, Deleted) or
        TMemberTransfer.UsedOutside(ALayout, Member.Name) then
        Continue;
      Deleted := Deleted + [Index];
      Result := Result + [Index];
      Changed := True;
    end;
  until not Changed;
end;

class function TSafeDelete.Title(const ATarget: TSafeDeleteTarget): string;
begin
  Result := Format('%s „%s“ sicher löschen …', [TSafeDeleteTarget.KindName(ATarget.Kind), ATarget.Name]);
end;

end.
