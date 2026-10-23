unit Atlas.Common.Pascal.SyntaxChecks;

// Syntaxprüfungen am fertigen Baum wie beim Compiler (#1022), für Fälle, die
// der fehlertolerante Parser durchlässt:
//   E2023  function ohne Ergebnistyp an einer Deklaration
//   E2025  procedure mit Ergebnistyp
//   E2031  goto auf eine nicht deklarierte Marke
//   E2049  label im interface-Teil
//   E2058  object-Typ außerhalb des type-Abschnitts (var X: object … end)
//   E2059  lokaler object-Typ in einer Routine
//   E2060  Klassen- oder Interface-Typ außerhalb des type-Abschnitts
//   E2061  lokaler Klassen- oder Interface-Typ
//   E2067  Wertparameter ohne Typ
//   E2195  lokale Variable mit Anfangswert im var-Abschnitt
//   E2196  mehrere Variablen mit einem Anfangswert
// Gemeldet wird nur, was am Baum sicher ist: Eine Implementierung ohne
// Ergebnistyp ist erlaubt, wenn die Datei die Routine mit Ergebnistyp
// deklariert; Methoden (Name mit Punkt) sind in ihrer Klasse deklariert.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TSyntaxChecks = record
  public
    /// <summary>Befunde zu ARoot; ATokens sind alle Token der Datei (auch Kommentare), sortiert. Inaktive
    /// Zweige der bedingten Übersetzung stehen nicht im Baum und bleiben so still.</summary>
    class function Check(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>): TArray<TSyntaxDiagnostic>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

type
  TTreeChecker = class
  private
    FTokens: TArray<TPascalToken>;
    FByOffset: TDictionary<Integer, Integer>;
    FResult: TList<TSyntaxDiagnostic>;
    // Namen von Routinenköpfen mit Ergebnistyp (klein): Deklarationen, zu denen eine Implementierung ohne
    // Ergebnistyp gehören darf.
    FWithResult: TDictionary<string, Boolean>;
    procedure Add(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition);
    function IndexAt(AOffset: Integer): Integer;
    /// <summary>Erstes Token, das bei AOffset oder dahinter beginnt; Length(FTokens) ohne.</summary>
    function IndexFrom(AOffset: Integer): Integer;
    function NextCode(AIndex: Integer): Integer;
    /// <summary>Erstes Token mit Symbol ASymbol in [AFrom, ATo) (Offsets), -1 ohne.</summary>
    function SymbolBetween(const ASymbol: string; AFrom, ATo: Integer): Integer;
    function WordBetween(const AWord: string; AFrom, ATo: Integer): Boolean;
    function HeaderWord(AHeader: TSyntaxNode): string;
    function ResultTypeOf(AHeader: TSyntaxNode): TSyntaxNode;
    function InRoutine(ANode: TSyntaxNode): Boolean;
    procedure CollectDeclared(ARoot: TSyntaxNode);
    procedure CheckHeader(AHeader: TSyntaxNode);
    procedure CheckParameter(AParameter: TSyntaxNode);
    procedure CheckVarDecl(ADecl: TSyntaxNode);
    procedure CheckFieldType(ADecl: TSyntaxNode);
    procedure CheckTypeDecl(ADecl: TSyntaxNode);
    procedure CheckGoto(AGoto: TSyntaxNode);
    function LabelsOf(AScope: TSyntaxNode): TArray<string>;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    function Run(ARoot: TSyntaxNode): TArray<TSyntaxDiagnostic>;
  end;

const
  TypeKinds: set of TSyntaxKind = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType, TSyntaxKind.HelperType];
  ClassLikeKinds: set of TSyntaxKind = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
    TSyntaxKind.ForwardType];
  HeaderParts: set of TSyntaxKind = [TSyntaxKind.Parameters, TSyntaxKind.GenericParams, TSyntaxKind.Directive,
    TSyntaxKind.Attribute];

/// <summary>Marke vergleichbar machen: Zahlen ohne führende Nullen, Namen klein.</summary>
function LabelKey(const AText: string): string;
var
  Number: Int64;
begin
  if TryStrToInt64(AText, Number) then
    Result := IntToStr(Number)
  else
    Result := LowerCase(AText);
end;

{ TTreeChecker }

constructor TTreeChecker.Create(const ATokens: TArray<TPascalToken>);
var
  Index: Integer;
begin
  inherited Create;
  FTokens := ATokens;
  FByOffset := TDictionary<Integer, Integer>.Create;
  for Index := 0 to High(FTokens) do
    FByOffset.AddOrSetValue(FTokens[Index].Offset, Index);
  FResult := TList<TSyntaxDiagnostic>.Create;
  FWithResult := TDictionary<string, Boolean>.Create;
end;

destructor TTreeChecker.Destroy;
begin
  FWithResult.Free;
  FResult.Free;
  FByOffset.Free;
  inherited;
end;

procedure TTreeChecker.Add(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition);
var
  Diagnostic: TSyntaxDiagnostic;
begin
  Diagnostic := Default(TSyntaxDiagnostic);
  Diagnostic.Message := AMessage + Format(' (wie %s).', [ACode]);
  Diagnostic.StartPos := AStartPos;
  Diagnostic.EndPos := AEndPos;
  Diagnostic.Code := ACode;
  Diagnostic.TreeIntact := True;
  FResult.Add(Diagnostic);
end;

function TTreeChecker.IndexAt(AOffset: Integer): Integer;
begin
  if not FByOffset.TryGetValue(AOffset, Result) then
    Result := -1;
end;

function TTreeChecker.IndexFrom(AOffset: Integer): Integer;
var
  Lower, Upper, Middle: Integer;
begin
  Lower := 0;
  Upper := Length(FTokens);
  while Lower < Upper do
  begin
    Middle := (Lower + Upper) div 2;
    if FTokens[Middle].Offset < AOffset then
      Lower := Middle + 1
    else
      Upper := Middle;
  end;
  Result := Lower;
end;

function TTreeChecker.NextCode(AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
  if Result > High(FTokens) then
    Result := -1;
end;

function TTreeChecker.SymbolBetween(const ASymbol: string; AFrom, ATo: Integer): Integer;
var
  Index: Integer;
begin
  Index := IndexFrom(AFrom);
  while (Index <= High(FTokens)) and (FTokens[Index].Offset < ATo) do
  begin
    if FTokens[Index].IsSymbol(ASymbol) then
      Exit(Index);
    Inc(Index);
  end;
  Result := -1;
end;

function TTreeChecker.WordBetween(const AWord: string; AFrom, ATo: Integer): Boolean;
var
  Index: Integer;
begin
  Index := IndexFrom(AFrom);
  while (Index <= High(FTokens)) and (FTokens[Index].Offset < ATo) do
  begin
    if (FTokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(FTokens[Index].Text, AWord) then
      Exit(True);
    Inc(Index);
  end;
  Result := False;
end;

function TTreeChecker.HeaderWord(AHeader: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := '';
  Index := IndexAt(AHeader.StartOffset);
  if Index < 0 then
    Exit;
  if FTokens[Index].IsKeyword('class') then
    Index := NextCode(Index);
  if Index >= 0 then
    Result := LowerCase(FTokens[Index].Text);
end;

function TTreeChecker.ResultTypeOf(AHeader: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  // Kinder des Kopfs: Typparameter, Parameter, Direktiven, Attribute und der Ergebnistyp.
  for Index := 0 to AHeader.ChildCount - 1 do
    if not (AHeader[Index].Kind in HeaderParts) then
      Exit(AHeader[Index]);
  Result := nil;
end;

function TTreeChecker.InRoutine(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.RoutineDecl then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

procedure TTreeChecker.CollectDeclared(ARoot: TSyntaxNode);
begin
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ResultTypeOf(ANode) <> nil) then
        FWithResult.AddOrSetValue(LowerCase(ANode.Name), True);
    end);
end;

procedure TTreeChecker.CheckHeader(AHeader: TSyntaxNode);
var
  Word: string;
  ResultType, Owner: TSyntaxNode;
  Declaration: Boolean;
begin
  Owner := AHeader.Parent;
  if (Owner = nil) or (AHeader.Name = '') then
    Exit;
  Word := HeaderWord(AHeader);
  ResultType := ResultTypeOf(AHeader);
  if (Word = 'procedure') and (ResultType <> nil) then
  begin
    Add('E2025', 'Eine Prozedur kann keinen Ergebnistyp haben', ResultType.StartPos, ResultType.EndPos);
    Exit;
  end;
  // Eine Methodenzuordnung (function IFoo.GetX = MyGetX) hat nie einen Ergebnistyp (#1134).
  if (Word <> 'function') or (ResultType <> nil) or AHeader.IsMethodResolution then
    Exit;
  // Deklaration: in einem Typ, im interface-Teil, forward/external oder eine freie Routine ohne
  // Deklaration mit Ergebnistyp in der Datei.
  if Owner.Kind in TypeKinds then
    Declaration := True
  else if Owner.Kind = TSyntaxKind.RoutineDecl then
    Declaration := ((Owner.Parent <> nil) and (Owner.Parent.Kind = TSyntaxKind.InterfaceSection)) or
      ((Pos('.', AHeader.Name) = 0) and not FWithResult.ContainsKey(LowerCase(AHeader.Name)))
  else
    Declaration := False;
  if Declaration then
    Add('E2023', Format('Die Funktion %s braucht einen Ergebnistyp', [AHeader.Name]), AHeader.StartPos,
      AHeader.EndPos);
end;

procedure TTreeChecker.CheckParameter(AParameter: TSyntaxNode);
begin
  // procedure Foo(A); – nur const, var, out und constref dürfen ohne Typ stehen.
  if (AParameter.Name = '') or (AParameter.Modifier <> TParameterModifier.None) or
    (SymbolBetween(':', AParameter.StartOffset, AParameter.EndOffset) >= 0) then
    Exit;
  Add('E2067', Format('Parametertyp fehlt bei %s', [StringReplace(AParameter.Name, ',', ', ', [rfReplaceAll])]),
    AParameter.StartPos, AParameter.EndPos);
end;

procedure TTreeChecker.CheckVarDecl(ADecl: TSyntaxNode);
var
  Section, Owner: TSyntaxNode;
  Equal: Integer;
  Local: Boolean;
begin
  CheckFieldType(ADecl);
  Section := ADecl.Parent;
  if (Section = nil) or (Section.Kind <> TSyntaxKind.VarSection) or (Section.Parent = nil) or
    (ADecl.ChildCount < 2) then
    Exit;
  Owner := Section.Parent;
  if Owner.Kind = TSyntaxKind.RoutineDecl then
    Local := True
  else if Owner.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.ProgramFile,
    TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile] then
    Local := False
  else
    Exit;
  // X: Typ = Wert: das "=" zwischen Typ und Ausdruck; absolute hat keins.
  Equal := SymbolBetween('=', ADecl[0].EndOffset, ADecl[1].StartOffset);
  if (Equal < 0) or WordBetween('absolute', ADecl[0].EndOffset, ADecl[1].StartOffset) then
    Exit;
  if Pos(',', ADecl.Name) > 0 then
    Add('E2196', 'Mehrere Variablen lassen sich nicht gemeinsam initialisieren', FTokens[Equal].StartPos,
      FTokens[Equal].EndPos)
  else if Local then
    Add('E2195', 'Lokale Variablen lassen sich im var-Abschnitt nicht initialisieren', FTokens[Equal].StartPos,
      FTokens[Equal].EndPos);
end;

procedure TTreeChecker.CheckFieldType(ADecl: TSyntaxNode);
var
  TypeNode: TSyntaxNode;
begin
  // var X: class … end; – Klassen, Interfaces und Objekte brauchen einen Namen aus dem type-Abschnitt.
  if ADecl.ChildCount = 0 then
    Exit;
  TypeNode := ADecl[0];
  if TypeNode.Kind = TSyntaxKind.ObjectType then
    Add('E2058', 'Klassen-, Interface- und Objekttypen sind nur im type-Abschnitt erlaubt', TypeNode.StartPos,
      TypeNode.EndPos)
  else if TypeNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.InterfaceType] then
    Add('E2060', 'Klassen- und Interface-Typen sind nur im type-Abschnitt erlaubt', TypeNode.StartPos,
      TypeNode.EndPos);
end;

procedure TTreeChecker.CheckTypeDecl(ADecl: TSyntaxNode);
var
  Index: Integer;
  TypeNode: TSyntaxNode;
begin
  if not InRoutine(ADecl) then
    Exit;
  TypeNode := nil;
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind in ClassLikeKinds then
    begin
      TypeNode := ADecl[Index];
      Break;
    end;
  if TypeNode = nil then
    Exit;
  if TypeNode.Kind = TSyntaxKind.ObjectType then
    Add('E2059', 'Lokale Klassen-, Interface- und Objekttypen sind nicht erlaubt', ADecl.StartPos, ADecl.EndPos)
  else
    Add('E2061', 'Lokale Klassen- und Interface-Typen sind nicht erlaubt', ADecl.StartPos, ADecl.EndPos);
end;

function TTreeChecker.LabelsOf(AScope: TSyntaxNode): TArray<string>;
var
  Index, Inner, TokenIndex: Integer;
  Section, Container: TSyntaxNode;
  Containers: TArray<TSyntaxNode>;
begin
  Result := nil;
  Containers := [AScope];
  // Auf Datei-Ebene stehen die Marken in den Abschnitten.
  if AScope.Kind <> TSyntaxKind.RoutineDecl then
    for Index := 0 to AScope.ChildCount - 1 do
      if AScope[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
        Containers := Containers + [AScope[Index]];
  for Container in Containers do
    for Inner := 0 to Container.ChildCount - 1 do
    begin
      Section := Container[Inner];
      if Section.Kind <> TSyntaxKind.LabelSection then
        Continue;
      TokenIndex := IndexAt(Section.StartOffset);
      if TokenIndex < 0 then
        Continue;
      TokenIndex := NextCode(TokenIndex);
      while (TokenIndex >= 0) and (FTokens[TokenIndex].Offset < Section.EndOffset) do
      begin
        if FTokens[TokenIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number] then
          Result := Result + [LabelKey(FTokens[TokenIndex].Text)];
        TokenIndex := NextCode(TokenIndex);
      end;
    end;
end;

procedure TTreeChecker.CheckGoto(AGoto: TSyntaxNode);
var
  Scope, Outer: TSyntaxNode;
  NameIndex: Integer;
  Labels: TArray<string>;
begin
  if AGoto.Name = '' then
    Exit;
  Scope := AGoto.Parent;
  while (Scope <> nil) and (Scope.Parent <> nil) and (Scope.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    // Marken anonymer Methoden kennt der Baum nicht sicher genug.
    if Scope.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    Scope := Scope.Parent;
  end;
  if Scope = nil then
    Exit;
  Labels := LabelsOf(Scope);
  if IndexStr(LabelKey(AGoto.Name), Labels) >= 0 then
    Exit;
  // In einer umgebenden Routine deklariert: das meldet label-misuse genauer (E2093, #995).
  Outer := Scope.Parent;
  while Outer <> nil do
  begin
    if (Outer.Kind = TSyntaxKind.RoutineDecl) and (IndexStr(LabelKey(AGoto.Name), LabelsOf(Outer)) >= 0) then
      Exit;
    Outer := Outer.Parent;
  end;
  NameIndex := IndexAt(AGoto.StartOffset);
  if NameIndex >= 0 then
    NameIndex := NextCode(NameIndex);
  if NameIndex < 0 then
    Exit;
  Add('E2031', Format('Marke erwartet: %s ist nicht als label deklariert', [AGoto.Name]),
    FTokens[NameIndex].StartPos, FTokens[NameIndex].EndPos);
end;

function TTreeChecker.Run(ARoot: TSyntaxNode): TArray<TSyntaxDiagnostic>;
begin
  CollectDeclared(ARoot);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      case ANode.Kind of
        TSyntaxKind.RoutineHeader:
          if (ANode.Parent <> nil) and ((ANode.Parent.Kind = TSyntaxKind.RoutineDecl) or
            (ANode.Parent.Kind in TypeKinds)) then
            CheckHeader(ANode);
        TSyntaxKind.Parameter:
          CheckParameter(ANode);
        TSyntaxKind.VarDecl:
          CheckVarDecl(ANode);
        TSyntaxKind.Field:
          CheckFieldType(ANode);
        TSyntaxKind.TypeDecl:
          CheckTypeDecl(ANode);
        TSyntaxKind.LabelSection:
          if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.InterfaceSection) then
            Add('E2049', 'Label-Deklarationen sind im interface-Teil nicht erlaubt', ANode.StartPos, ANode.EndPos);
        TSyntaxKind.GotoStatement:
          CheckGoto(ANode);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end);
  Result := FResult.ToArray;
end;

{ TSyntaxChecks }

class function TSyntaxChecks.Check(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>):
  TArray<TSyntaxDiagnostic>;
var
  Checker: TTreeChecker;
begin
  if ARoot = nil then
    Exit(nil);
  Checker := TTreeChecker.Create(ATokens);
  try
    Result := Checker.Run(ARoot);
  finally
    Checker.Free;
  end;
end;

end.
