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
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingSafeDeleteText = (AtlasCannotSafelyDeleteThis, TheClassIsNotIn, TheDeclarationOfCannotBe,
    LocalVariablesAreDeletedBy, SafelyDelete, LocalRoutine, Field);

const
  cTexts: array[TEditingSafeDeleteText] of TAtlasText = (
    (De: 'Diese Deklaration kann Atlas nicht sicher löschen.'; En: 'Atlas cannot safely delete this declaration.'),
    (De: 'Die Klasse %s steht nicht in dieser Unit.'; En: 'The class %s is not in this unit.'),
    (De: 'Die Deklaration von %s ist nicht zu finden.'; En: 'The declaration of %s cannot be found.'),
    (De: 'Lokale Variablen löscht die Regel unused-local.';
     En: 'Local variables are deleted by the rule unused-local.'),
    (De: '%s „%s“ sicher löschen …'; En: 'Safely delete %s “%s” …'),
    (De: 'lokale Routine'; En: 'local routine'),
    (De: 'Feld'; En: 'field'));

{$SCOPEDENUMS OFF}

{ TSafeDeleteTarget }

class function TSafeDeleteTarget.KindName(AKind: TSafeDeleteKind): string;
begin
  case AKind of
    TSafeDeleteKind.Method:
      Result := 'Methode';
    TSafeDeleteKind.Field:
      Result := cTexts[TEditingSafeDeleteText.Field].Text;
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
      Result := cTexts[TEditingSafeDeleteText.LocalRoutine].Text;
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
    begin
      Break;
    end;
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (ATokens[Index].StartPos.Line = APosition.Line) and
      (ATokens[Index].StartPos.Character <= APosition.Character) and
      (ATokens[Index].EndPos.Character >= APosition.Character) then
    begin
      Exit(Index);
    end;
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
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
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
    begin
      Inc(Index);
    end;
    Dec(Index);
    while (Index >= 0) and (Parent[Index].Kind = TSyntaxKind.Attribute) do
    begin
      Result := Parent[Index].StartPos.Line;
      Dec(Index);
    end;
  end;
  while (Result > 0) and StartsText('///', Trim(ALines[Result - 1])) do
  begin
    Dec(Result);
  end;
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
      begin
        Found := Found + [ANode];
      end;
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
  begin
    Exit;
  end;
  Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
  begin
    Result := CollapseSpace(Copy(AText, Parameters.StartOffset + 1, Parameters.EndOffset - Parameters.StartOffset));
  end;
end;

function IsInsideRoutine(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if Parent.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(True);
    end;
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
  begin
    Result.NameRange := TTextRange.Create(Member.Node.StartPos, Member.Node.StartPos);
  end;
end;

/// <summary>Routine, deren Deklaration auf Zeile ALine beginnt (die innerste); nil ohne.</summary>
function RoutineAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Routine: TSyntaxNode;
begin
  Routine := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.StartPos.Line = ALine) then
      begin
        Routine := ANode;
      end;
    end);
  Result := Routine;
end;

/// <summary>Typ, Konstante oder Variable über Zeile ALine; nil ohne.</summary>
function DeclarationAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (Found = nil) and (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
      if Result and (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
      begin
        Found := ANode;
        Result := False;
      end;
    end);
  Result := Found;
end;

/// <summary>Mitglieder, die Atlas nicht sicher löschen kann (z. B. Klassenkonstanten).</summary>
function IsUndeletable(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Kind = TClassMemberKind.Other) and (AMember.Node.Kind <> TSyntaxKind.RoutineHeader);
end;

/// <summary>Name ohne Typparameter ("TList&lt;T&gt;" → "TList").</summary>
function PlainTypeName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

type
  /// <summary>Sucht das Symbol an einer Stelle für TSafeDelete.Find.</summary>
  TSymbolFinder = record
    Tree: TSyntaxTree;
    Text: string;
    Position: TTextPosition;
    Tokens: TArray<TPascalToken>;
    /// <summary>Bezeichner an Position; -1 ohne.</summary>
    Token: Integer;
    /// <summary>Klasse: Kopfzeile = ganzer Typ, sonst ein Mitglied.</summary>
    function InClass(ADecl: TSyntaxNode; var ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
    /// <summary>Mitglied an der Zeile; aus einer Feldgruppe der Name unter dem Cursor.</summary>
    function MemberHit(ALayout: TClassLayout): Integer;
    /// <summary>Rumpf einer Methode, lokale Routine, Routine der Unit.</summary>
    function InRoutine(ARoutine: TSyntaxNode; var ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
    function MethodBody(ARoutine: TSyntaxNode; var ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
    /// <summary>Typ, Konstante, Variable.</summary>
    function InDeclaration(AFound: TSyntaxNode; var ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
    function VariableName(AFound: TSyntaxNode): string;
  end;

function TSymbolFinder.MemberHit(ALayout: TClassLayout): Integer;
var
  mGroup: TSyntaxNode;
  mIndex: Integer;
begin
  Result := ALayout.MemberAtLine(Position.Line);
  if (Result < 0) or (Token < 0) or not ALayout.Members[Result].IsFieldGroup then
  begin
    Exit;
  end;
  mGroup := ALayout.Members[Result].Node;
  for mIndex in ALayout.Find(Tokens[Token].Text) do
  begin
    if ALayout.Members[mIndex].Node = mGroup then
    begin
      Result := mIndex;
    end;
  end;
end;

function TSymbolFinder.InClass(ADecl: TSyntaxNode; var ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
var
  mLayout: TClassLayout;
  mHit: Integer;
begin
  AReason := '';
  mLayout := TClassLayout.Read(Tree, Text, ADecl);
  try
    if Position.Line = mLayout.HeaderLine then
    begin
      ATarget.Kind := TSafeDeleteKind.Type_;
      ATarget.Name := mLayout.Name;
      ATarget.Node := ADecl;
      NameRangeIn(Tree, ADecl, mLayout.Name, ATarget.NameRange);
      Exit(True);
    end;
    mHit := MemberHit(mLayout);
    Result := mHit >= 0;
    if Result and IsUndeletable(mLayout.Members[mHit]) then
    begin
      Result := Fail(AReason, cTexts[TEditingSafeDeleteText.AtlasCannotSafelyDeleteThis].Text);
    end
    else if Result then
    begin
      ATarget := TSafeDelete.ForMember(mLayout, mHit);
    end;
  finally
    mLayout.Free;
  end;
end;

function TSymbolFinder.MethodBody(ARoutine: TSyntaxNode; var ATarget: TSafeDeleteTarget;
  out AReason: string): Boolean;
var
  mClassName: string;
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mIndex: Integer;
begin
  AReason := '';
  mClassName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  mDecl := TClassLayout.DeclNamed(Tree, LastPart(mClassName));
  if mDecl = nil then
  begin
    Exit(Fail(AReason, cTexts[TEditingSafeDeleteText.TheClassIsNotIn].Fmt([mClassName])));
  end;
  mLayout := TClassLayout.Read(Tree, Text, mDecl);
  try
    for mIndex := 0 to High(mLayout.Members) do
    begin
      if mLayout.Members[mIndex].Body = ARoutine then
      begin
        ATarget := TSafeDelete.ForMember(mLayout, mIndex);
        Exit(True);
      end;
    end;
  finally
    mLayout.Free;
  end;
  Result := Fail(AReason, cTexts[TEditingSafeDeleteText.TheDeclarationOfCannotBe].Fmt([ARoutine.Name]));
end;

function TSymbolFinder.InRoutine(ARoutine: TSyntaxNode; var ATarget: TSafeDeleteTarget;
  out AReason: string): Boolean;
var
  mLocal: Boolean;
begin
  AReason := '';
  mLocal := IsInsideRoutine(ARoutine);
  if not mLocal and (Pos('.', ARoutine.Name) > 0) then
  begin
    Exit(MethodBody(ARoutine, ATarget, AReason));
  end;
  ATarget.Kind := TSafeDeleteKind.Routine;
  if mLocal then
  begin
    ATarget.Kind := TSafeDeleteKind.LocalRoutine;
  end;
  ATarget.Name := ARoutine.Name;
  ATarget.Node := ARoutine;
  NameRangeIn(Tree, ARoutine, ARoutine.Name, ATarget.NameRange);
  Result := True;
end;

function TSymbolFinder.VariableName(AFound: TSyntaxNode): string;
var
  mNames: TArray<string>;
  mName: string;
begin
  mNames := AFound.Name.Split([',']);
  Result := Trim(mNames[0]);
  if Token < 0 then
  begin
    Exit;
  end;
  for mName in mNames do
  begin
    if SameText(Trim(mName), Tokens[Token].Text) then
    begin
      Result := Trim(mName);
    end;
  end;
end;

function TSymbolFinder.InDeclaration(AFound: TSyntaxNode; var ATarget: TSafeDeleteTarget;
  out AReason: string): Boolean;
begin
  AReason := '';
  ATarget.Node := AFound;
  case AFound.Kind of
    TSyntaxKind.TypeDecl:
      begin
        ATarget.Kind := TSafeDeleteKind.Type_;
        ATarget.Name := PlainTypeName(AFound.Name);
      end;
    TSyntaxKind.ConstDecl:
      begin
        ATarget.Kind := TSafeDeleteKind.Constant;
        ATarget.Name := AFound.Name;
      end;
  else
    ATarget.Kind := TSafeDeleteKind.Variable;
    ATarget.Name := VariableName(AFound);
  end;
  if (AFound.Kind = TSyntaxKind.VarDecl) and IsInsideRoutine(AFound) then
  begin
    Exit(Fail(AReason, cTexts[TEditingSafeDeleteText.LocalVariablesAreDeletedBy].Text));
  end;
  if not NameRangeIn(Tree, AFound, ATarget.Name, ATarget.NameRange) then
  begin
    ATarget.NameRange := TTextRange.Create(AFound.StartPos, AFound.StartPos);
  end;
  Result := True;
end;

class function TSafeDelete.Find(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out ATarget: TSafeDeleteTarget; out AReason: string): Boolean;
var
  mFinder: TSymbolFinder;
  mDecl, mRoutine, mFound: TSyntaxNode;
begin
  Result := False;
  AReason := '';
  ATarget := Default(TSafeDeleteTarget);
  ATarget.Member := -1;
  // Unit: auf der Zeile "unit X;".
  if (ATree.Root.Kind = TSyntaxKind.UnitFile) and (APosition.Line = ATree.Root.StartPos.Line) then
  begin
    ATarget.Kind := TSafeDeleteKind.Unit_;
    ATarget.Name := ATree.Root.Name;
    ATarget.NameRange := TTextRange.Create(APosition, APosition);
    Exit(True);
  end;
  mFinder := Default(TSymbolFinder);
  mFinder.Tree := ATree;
  mFinder.Text := AText;
  mFinder.Position := APosition;
  mFinder.Tokens := ATree.Tokens;
  mFinder.Token := IdentifierAt(mFinder.Tokens, APosition);
  mDecl := TClassLayout.DeclAt(ATree, APosition.Line, True);
  mRoutine := nil;
  if mDecl = nil then
  begin
    mRoutine := RoutineAt(ATree, APosition.Line);
  end;
  if mDecl <> nil then
  begin
    Result := mFinder.InClass(mDecl, ATarget, AReason);
  end
  else if mRoutine <> nil then
  begin
    Result := mFinder.InRoutine(mRoutine, ATarget, AReason);
  end
  else
  begin
    mFound := DeclarationAt(ATree, APosition.Line);
    if mFound <> nil then
    begin
      Result := mFinder.InDeclaration(mFound, ATarget, AReason);
    end;
  end;
end;

/// <summary>Zeilen eines Mitglieds: Deklaration und Rumpf.</summary>
function MemberLines(ATree: TSyntaxTree; const AText: string; const ATarget: TSafeDeleteTarget): TArray<TLineSpan>;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mMember: TClassMember;
begin
  Result := nil;
  mDecl := TClassLayout.DeclNamed(ATree, ATarget.ClassName);
  if mDecl = nil then
  begin
    Exit;
  end;
  mLayout := TClassLayout.Read(ATree, AText, mDecl);
  try
    mMember := mLayout.Members[ATarget.Member];
    Result := Result + [TLineSpan.Create(mMember.FirstLine, mMember.LastLine)];
    if mMember.Body <> nil then
    begin
      Result := Result + [TLineSpan.Create(mMember.BodyFirstLine, mMember.BodyLastLine)];
    end;
  finally
    mLayout.Free;
  end;
end;

/// <summary>Zeilen eines Typs und der Rümpfe seiner Methoden, auch verschachtelter Typen.</summary>
function TypeLines(ATree: TSyntaxTree; const ATarget: TSafeDeleteTarget; const ALines: TArray<string>):
  TArray<TLineSpan>;
var
  Spans: TArray<TLineSpan>;
  Prefix: string;
begin
  Spans := nil;
  Spans := Spans + [TLineSpan.Create(FirstLineOf(ATarget.Node, ALines), ATarget.Node.EndPos.Line)];
  Prefix := ATarget.Name + '.';
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(Prefix, ANode.Name) then
      begin
        Spans := Spans + [TLineSpan.Create(FirstLineOf(ANode, ALines), ANode.EndPos.Line)];
      end;
    end);
  Result := Spans;
end;

/// <summary>Zeilen einer Routine der Unit: Deklaration im interface, forward und Rumpf.</summary>
function RoutineLines(ATree: TSyntaxTree; const AText: string; const ATarget: TSafeDeleteTarget;
  const ALines: TArray<string>): TArray<TLineSpan>;
var
  mParameters: string;
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  mParameters := ParameterText(AText, ATarget.Node);
  for mRoutine in TopRoutines(ATree, ATarget.Name) do
  begin
    if ParameterText(AText, mRoutine) = mParameters then
    begin
      Result := Result + [TLineSpan.Create(FirstLineOf(mRoutine, ALines), mRoutine.EndPos.Line)];
    end;
  end;
end;

class function TSafeDelete.OwnLines(ATree: TSyntaxTree; const AText: string;
  const ATarget: TSafeDeleteTarget): TArray<TLineSpan>;
var
  mLines: TArray<string>;
begin
  Result := nil;
  mLines := TextLines(AText);
  case ATarget.Kind of
    TSafeDeleteKind.Method, TSafeDeleteKind.Field, TSafeDeleteKind.Property_:
      Result := MemberLines(ATree, AText, ATarget);
    TSafeDeleteKind.Type_:
      Result := TypeLines(ATree, ATarget, mLines);
    TSafeDeleteKind.Constant, TSafeDeleteKind.Variable, TSafeDeleteKind.LocalRoutine:
      Result := Result + [TLineSpan.Create(FirstLineOf(ATarget.Node, mLines), ATarget.Node.EndPos.Line)];
    TSafeDeleteKind.Routine:
      Result := RoutineLines(ATree, AText, ATarget, mLines);
    TSafeDeleteKind.Unit_: ;
  end;
end;

/// <summary>Token des Namens AName in der Gruppe ADecl (vor dem ":"); -1 ohne.</summary>
function GroupNameToken(const ATokens: TArray<TPascalToken>; ADecl: TSyntaxNode; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := TokenIndexAt(ATokens, ADecl.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ADecl.EndOffset) and
    not ATokens[mIndex].IsSymbol(':') do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, AName) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Erstes Token ab AIndex, das kein Leerraum und kein Kommentar ist.</summary>
function NextSolid(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Letztes Token bis AIndex, das kein Leerraum und kein Kommentar ist; -1 ohne.</summary>
function PreviousSolid(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Edit, das den Namen AName aus der Gruppe ADecl ("A, B: Integer") samt Komma streicht.</summary>
function GroupNameEdit(ATree: TSyntaxTree; ADecl: TSyntaxNode; const AName: string; out AEdit: TTextEdit): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mName, mNext, mPrevious: Integer;
begin
  Result := False;
  mTokens := ATree.Tokens;
  mName := GroupNameToken(mTokens, ADecl, AName);
  if mName < 0 then
  begin
    Exit;
  end;
  mNext := NextSolid(mTokens, mName + 1);
  if (mNext <= High(mTokens)) and mTokens[mNext].IsSymbol(',') then
  begin
    mNext := NextSolid(mTokens, mNext + 1);
    AEdit := TTextEdit.Create(TTextRange.Create(mTokens[mName].StartPos, mTokens[mNext].StartPos), '');
    Exit(True);
  end;
  mPrevious := PreviousSolid(mTokens, mName - 1);
  if (mPrevious >= 0) and mTokens[mPrevious].IsSymbol(',') then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mTokens[mPrevious].StartPos, mTokens[mName].EndPos), '');
    Result := True;
  end;
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
  begin
    if Item = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeilenbereiche nach ihrer ersten Zeile sortiert (stabil).</summary>
function SortedSpans(const ASpans: TArray<TLineSpan>): TArray<TLineSpan>;
var
  mIndex, mChild: Integer;
  mSwap: TLineSpan;
begin
  Result := Copy(ASpans);
  for mIndex := 1 to High(Result) do
  begin
    for mChild := mIndex downto 1 do
    begin
      if Result[mChild].First < Result[mChild - 1].First then
      begin
        mSwap := Result[mChild];
        Result[mChild] := Result[mChild - 1];
        Result[mChild - 1] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Sortierte Zeilenbereiche, überlappende und angrenzende zusammengefasst.</summary>
function MergedSpans(const ASpans: TArray<TLineSpan>): TArray<TLineSpan>;
var
  mSpan: TLineSpan;
begin
  Result := nil;
  for mSpan in ASpans do
  begin
    if (Result = nil) or (mSpan.First > Result[High(Result)].Last + 1) then
    begin
      Result := Result + [mSpan];
    end
    else if mSpan.Last > Result[High(Result)].Last then
    begin
      Result[High(Result)].Last := mSpan.Last;
    end;
  end;
end;

function Covered(const AEdit: TTextEdit; const ASpans: TArray<TLineSpan>): Boolean;
var
  mSpan: TLineSpan;
begin
  for mSpan in ASpans do
  begin
    if mSpan.Contains(AEdit.Range.StartPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Sammelt für TSafeDelete.Edits ganze Zeilen und Teiländerungen.</summary>
  TDeletion = record
    Tree: TSyntaxTree;
    Text: string;
    Targets: TArray<TSafeDeleteTarget>;
    Lines: TArray<string>;
    Spans: TArray<TLineSpan>;
    Partial: TArray<TTextEdit>;
    /// <summary>Ganz gelöschte Deklarationen der Unit.</summary>
    Nodes: TArray<TSyntaxNode>;
    /// <summary>Mitglieder je Klasse in einem Schritt (Feldgruppen, leere Abschnitte).</summary>
    function MemberEdits: TArray<TTextEdit>;
    function MemberClasses: TArray<string>;
    function ClassEdits(const AClassName: string): TArray<TTextEdit>;
    /// <summary>Deklarationen der Unit: ganz gelöschte Knoten sammeln, Namen aus Gruppen einzeln.</summary>
    procedure CollectDeclarations;
    procedure AddVariable(const ATarget: TSafeDeleteTarget);
    function NameTaken(ANode: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Alle Namen der Gruppe gewählt: der ganze Knoten.</summary>
    function AllNamesTaken(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
    /// <summary>ANode allein auf seinen Zeilen: die Zeilen, sonst nur sein Text.</summary>
    procedure AddRemoval(ANode: TSyntaxNode);
    procedure AddClassBodies;
    /// <summary>Abschnitte: ganz leer → der ganze Abschnitt, sonst je Knoten.</summary>
    procedure AddSections;
    function Sections: TArray<TSyntaxNode>;
    function IsEmptied(ASection: TSyntaxNode): Boolean;
    /// <summary>Eine Leerzeile dahinter mitnehmen, wenn davor auch eine steht.</summary>
    function SpanEdit(const ASpan: TLineSpan): TTextEdit;
    function LineEdits: TArray<TTextEdit>;
  end;

function TDeletion.MemberClasses: TArray<string>;
var
  mDeleted: TArray<string>;
  mTarget: TSafeDeleteTarget;
begin
  mDeleted := nil;
  for mTarget in Targets do
  begin
    if mTarget.Kind = TSafeDeleteKind.Type_ then
    begin
      mDeleted := mDeleted + [mTarget.Name];
    end;
  end;
  Result := nil;
  for mTarget in Targets do
  begin
    if (mTarget.Member >= 0) and (IndexText(mTarget.ClassName, Result) < 0) and
      (IndexText(mTarget.ClassName, mDeleted) < 0) then
    begin
      Result := Result + [mTarget.ClassName];
    end;
  end;
end;

function TDeletion.ClassEdits(const AClassName: string): TArray<TTextEdit>;
var
  mDecl: TSyntaxNode;
  mIndexes: TArray<Integer>;
  mTarget: TSafeDeleteTarget;
  mLayout: TClassLayout;
begin
  Result := nil;
  mDecl := TClassLayout.DeclNamed(Tree, AClassName);
  if mDecl = nil then
  begin
    Exit;
  end;
  mIndexes := nil;
  for mTarget in Targets do
  begin
    if (mTarget.Member >= 0) and SameText(mTarget.ClassName, AClassName) and
      not TMemberTransfer.Has(mIndexes, mTarget.Member) then
    begin
      mIndexes := mIndexes + [mTarget.Member];
    end;
  end;
  mLayout := TClassLayout.Read(Tree, Text, mDecl);
  try
    Result := TClassEdits.DeleteMembers(mLayout, mIndexes, True) + TMemberTransfer.EmptiedSections(mLayout, mIndexes);
  finally
    mLayout.Free;
  end;
end;

function TDeletion.MemberEdits: TArray<TTextEdit>;
var
  mClassName: string;
begin
  Result := nil;
  for mClassName in MemberClasses do
  begin
    Result := Result + ClassEdits(mClassName);
  end;
end;

function TDeletion.NameTaken(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mTarget: TSafeDeleteTarget;
begin
  for mTarget in Targets do
  begin
    if (mTarget.Node = ANode) and SameText(mTarget.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDeletion.AllNamesTaken(ANode: TSyntaxNode; const ANames: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if not NameTaken(ANode, Trim(mName)) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TDeletion.AddVariable(const ATarget: TSafeDeleteTarget);
var
  mNames: TArray<string>;
  mEdit: TTextEdit;
begin
  mNames := ATarget.Node.Name.Split([',']);
  if Length(mNames) <= 1 then
  begin
    Nodes := Nodes + [ATarget.Node];
  end
  else if AllNamesTaken(ATarget.Node, mNames) then
  begin
    if not HasNode(Nodes, ATarget.Node) then
    begin
      Nodes := Nodes + [ATarget.Node];
    end;
  end
  else if GroupNameEdit(Tree, ATarget.Node, ATarget.Name, mEdit) then
  begin
    Partial := Partial + [mEdit];
  end;
end;

procedure TDeletion.AddRemoval(ANode: TSyntaxNode);
begin
  if AloneOnLines(ANode, Lines) then
  begin
    Spans := Spans + [TLineSpan.Create(FirstLineOf(ANode, Lines), ANode.EndPos.Line)];
  end
  else
  begin
    Partial := Partial + [TTextEdit.Create(TTextRange.Create(ANode.StartPos, ANode.EndPos), '')];
  end;
end;

procedure TDeletion.CollectDeclarations;
var
  mTarget: TSafeDeleteTarget;
begin
  for mTarget in Targets do
  begin
    case mTarget.Kind of
      TSafeDeleteKind.Type_, TSafeDeleteKind.Constant:
        Nodes := Nodes + [mTarget.Node];
      TSafeDeleteKind.Variable:
        AddVariable(mTarget);
      TSafeDeleteKind.LocalRoutine:
        AddRemoval(mTarget.Node);
      TSafeDeleteKind.Routine:
        Spans := Spans + TSafeDelete.OwnLines(Tree, Text, mTarget);
      TSafeDeleteKind.Method, TSafeDeleteKind.Field, TSafeDeleteKind.Property_, TSafeDeleteKind.Unit_: ;
    end;
  end;
end;

procedure TDeletion.AddClassBodies;
var
  mTarget: TSafeDeleteTarget;
  mOwn: TArray<TLineSpan>;
  mIndex: Integer;
begin
  // Rümpfe gelöschter Klassen.
  for mTarget in Targets do
  begin
    if mTarget.Kind <> TSafeDeleteKind.Type_ then
    begin
      Continue;
    end;
    mOwn := TSafeDelete.OwnLines(Tree, Text, mTarget);
    for mIndex := 1 to High(mOwn) do
    begin
      Spans := Spans + [mOwn[mIndex]];
    end;
  end;
end;

function TDeletion.Sections: TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in Nodes do
  begin
    if (mNode.Parent <> nil) and not HasNode(Result, mNode.Parent) then
    begin
      Result := Result + [mNode.Parent];
    end;
  end;
end;

function TDeletion.IsEmptied(ASection: TSyntaxNode): Boolean;
var
  mChild: Integer;
begin
  for mChild := 0 to ASection.ChildCount - 1 do
  begin
    if IsDeclaration(ASection[mChild]) and not HasNode(Nodes, ASection[mChild]) then
    begin
      Exit(False);
    end;
  end;
  Result := (ASection.Kind in [TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection]) and
    AloneOnLines(ASection, Lines);
end;

procedure TDeletion.AddSections;
var
  mSection, mNode: TSyntaxNode;
begin
  for mSection in Sections do
  begin
    if IsEmptied(mSection) then
    begin
      Spans := Spans + [TLineSpan.Create(FirstLineOf(mSection, Lines), mSection.EndPos.Line)];
      Continue;
    end;
    for mNode in Nodes do
    begin
      if mNode.Parent = mSection then
      begin
        AddRemoval(mNode);
      end;
    end;
  end;
end;

function TDeletion.SpanEdit(const ASpan: TLineSpan): TTextEdit;
var
  mLast: Integer;
begin
  mLast := ASpan.Last;
  if (mLast + 1 <= High(Lines)) and (Trim(Lines[mLast + 1]) = '') and ((ASpan.First = 0) or
    (Trim(Lines[ASpan.First - 1]) = '')) then
  begin
    Inc(mLast);
  end;
  Result := TTextEdit.Create(TTextRange.Create(ASpan.First, 0, mLast + 1, 0), '');
end;

function TDeletion.LineEdits: TArray<TTextEdit>;
var
  mMerged: TArray<TLineSpan>;
  mSpan: TLineSpan;
  mEdit: TTextEdit;
begin
  // Zeilenbereiche sortieren und zusammenfassen.
  mMerged := MergedSpans(SortedSpans(Spans));
  Result := nil;
  for mSpan in mMerged do
  begin
    Result := Result + [SpanEdit(mSpan)];
  end;
  for mEdit in Partial do
  begin
    if not Covered(mEdit, mMerged) then
    begin
      Result := Result + [mEdit];
    end;
  end;
end;

class function TSafeDelete.Edits(ATree: TSyntaxTree; const AText: string;
  const ATargets: TArray<TSafeDeleteTarget>): TArray<TTextEdit>;
var
  mDeletion: TDeletion;
begin
  mDeletion := Default(TDeletion);
  mDeletion.Tree := ATree;
  mDeletion.Text := AText;
  mDeletion.Targets := ATargets;
  mDeletion.Lines := TextLines(AText);
  Result := mDeletion.MemberEdits;
  mDeletion.CollectDeclarations;
  mDeletion.AddClassBodies;
  mDeletion.AddSections;
  Result := Result + mDeletion.LineEdits;
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
      begin
        Continue;
      end;
      Member := ALayout.Members[Index];
      if not (Member.Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_]) or
        (Member.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_, TClassMemberKind.Other]) or
        Member.IsVirtual or Member.HasDirective('message') then
      begin
        Continue;
      end;
      // Nur, was gelöschte Mitglieder benutzt haben; was schon vorher unbenutzt war, meldet unused-private-member.
      Users := ALayout.UsersOf(Index);
      if (Users = nil) or not TMemberTransfer.HasAll(Users, Deleted) or
        TMemberTransfer.UsedOutside(ALayout, Member.Name) then
      begin
        Continue;
      end;
      Deleted := Deleted + [Index];
      Result := Result + [Index];
      Changed := True;
    end;
  until not Changed;
end;

class function TSafeDelete.Title(const ATarget: TSafeDeleteTarget): string;
begin
  Result := cTexts[TEditingSafeDeleteText.SafelyDelete].Fmt([TSafeDeleteTarget.KindName(ATarget.Kind), ATarget.Name]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.SafeDelete', cTexts);

end.
