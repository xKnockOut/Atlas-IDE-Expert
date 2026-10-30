unit Atlas.Common.Editing.RoutineParts;

// Bausteine für Umformungen, die Routinen verschieben oder umbauen: lokale
// Routine und Methode (#663), anonyme Methode und Methode (#680).
//   - Änderungen in Offsets eines Ausschnitts (TOffsetEdit, ApplyEdits),
//   - Parameter eines Kopfs einzeln und der Kopf als Text,
//   - freie Namen in der Klasse bzw. auf Unit-Ebene,
//   - lokale Namen je Routine oder anonymer Methode (TLocalsCache) und ob ein
//     Name auf dem Weg nach außen verdeckt ist.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineLocals;

type
  /// <summary>Änderung in Offsets des Dokuments.</summary>
  TOffsetEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    class function Create(AStart, AStop: Integer; const AText: string): TOffsetEdit; static;
  end;

  /// <summary>Ein Parameter einer Deklaration, einzeln auch bei "A, B: Integer".</summary>
  TParameterText = record
    Modifier: string;
    Name: string;
    /// <summary>": Typ" samt Vorgabewert; '' ohne Typ.</summary>
    Rest: string;
    function Text: string;
  end;

  /// <summary>Lokale Namen je Routine bzw. anonymer Methode, einmal gesammelt.</summary>
  TLocalsCache = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLocals: TDictionary<TSyntaxNode, TArray<TRoutineLocal>>;
  public
    constructor Create(const AText: string; ATree: TSyntaxTree);
    destructor Destroy; override;
    function Locals(ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
    /// <summary>Deklariert ARoutine den Namen AName (lokal, lokale Routine, lokaler Typ, Result) für AOffset?</summary>
    function Declares(ARoutine: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
  end;

  TRoutineParts = class
  public
    /// <summary>Kopf einer Routine.</summary>
    class function HeaderOf(ARoutine: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Ist die Routine bzw. anonyme Methode eine Funktion (Ergebnistyp)?</summary>
    class function IsFunction(ARoutine: TSyntaxNode): Boolean; static;
    class function Encloses(ANode: TSyntaxNode; AOffset: Integer): Boolean; static;
    /// <summary>Innerste Routine, deren Kopf AOffset enthält; nil ohne.</summary>
    class function RoutineWithHeaderAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Routine der Implementierung zum Kopf an AOffset, auch über die Deklaration in der Klasse
    /// (dann ADeclaration).</summary>
    class function TopRoutineAt(ATree: TSyntaxTree; AOffset: Integer; out ADeclaration: TSyntaxNode): TSyntaxNode;
      static;
    class function LineIsBlank(const ALines: TArray<string>; ALine: Integer): Boolean; static;
    /// <summary>Wendet AEdits (Offsets in AText, ab ABase) auf ASource = Copy(AText, ABase + 1, …) an.</summary>
    class function ApplyEdits(const ASource: string; ABase: Integer; AEdits: TArray<TOffsetEdit>): string; static;
    /// <summary>Token-Bereich des Namens im Kopf (TKunde.Rechne bzw. Rechne).</summary>
    class function NameTokens(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode;
      out AFirst, ALast: Integer): Boolean; static;
    /// <summary>Beginnt der Kopf mit class (Klassenmethode)?</summary>
    class function IsClassHeader(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean; static;
    /// <summary>Steht im Bereich des Knotens ein Token mit einem der Texte AWords (Direktive wie static)?</summary>
    class function HasWord(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode;
      const AWords: array of string): Boolean; static;
    /// <summary>Parameter des Kopfs bzw. der anonymen Methode AHeader einzeln, mit Modifizierer und Typ; nil auch
    /// bei [ref].</summary>
    class function ParameterTexts(const AText: string; AHeader: TSyntaxNode): TArray<TParameterText>; static;
    class function JoinParameters(const AParameters: TArray<TParameterText>): string; static;
    /// <summary>Kopf (Routine oder anonyme Methode) als Text mit neuem Namen und neuen Parametern (ohne
    /// Direktiven, mit ';').</summary>
    class function HeadText(const AText: string; AHeader: TSyntaxNode; const AName: string;
      const AParameters: TArray<TParameterText>; AClass: Boolean): string; static;
    /// <summary>Kopf einer anonymen Methode mit den Parametern und dem Ergebnistyp von AHeader (Kopf einer Routine
    /// oder anonyme Methode): "procedure(const A: Integer)", "function: string".</summary>
    class function AnonymousHead(const AText: string; AHeader: TSyntaxNode;
      const AParameters: TArray<TParameterText>): string; static;
    /// <summary>Namen der Kinder von ANode ("A, B" einzeln).</summary>
    class function ChildNames(ANode: TSyntaxNode): TArray<string>; static;
    /// <summary>Namen auf Unit-Ebene: Routinen, Typen, Variablen und Konstanten beider Teile.</summary>
    class function UnitNames(ARoot: TSyntaxNode): TArray<string>; static;
    /// <summary>Freier Name aus ABase: ABase, ABase2, ABase3 …, der in ATaken nicht vorkommt.</summary>
    class function FreeName(const ABase: string; const ATaken: TArray<string>): string; static;
    /// <summary>Von ANode bis AStop (ausschließlich): liegt ANode in einer anonymen Methode?</summary>
    class function InAnonymous(ANode, AStop: TSyntaxNode): Boolean; static;
    /// <summary>Deklariert eine Routine oder anonyme Methode zwischen ANode und AStop (AStop eingeschlossen, wenn
    /// AWithStop) den Namen?</summary>
    class function Shadowed(ACache: TLocalsCache; ANode, AStop: TSyntaxNode; const AName: string;
      AWithStop: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Editing.RoutineBody;

{ TOffsetEdit }

class function TOffsetEdit.Create(AStart, AStop: Integer; const AText: string): TOffsetEdit;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
end;

{ TParameterText }

function TParameterText.Text: string;
begin
  Result := Name + Rest;
  if Modifier <> '' then
    Result := Modifier + ' ' + Result;
end;

{ TRoutineParts }

class function TRoutineParts.HeaderOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
end;

class function TRoutineParts.IsFunction(ARoutine: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
begin
  // Die anonyme Methode trägt Parameter und Ergebnistyp selbst.
  if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
    Header := ARoutine
  else
    Header := HeaderOf(ARoutine);
  Result := (Header <> nil) and (Header.FindChild(TSyntaxKind.TypeReference) <> nil);
end;

class function TRoutineParts.Encloses(ANode: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (ANode <> nil) and (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
end;

class function TRoutineParts.RoutineWithHeaderAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
begin
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Header: TSyntaxNode;
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        Header := HeaderOf(ANode);
        if Encloses(Header, Offset) then
          Found := ANode;
      end;
    end);
  Result := Found;
end;

class function TRoutineParts.LineIsBlank(const ALines: TArray<string>; ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine <= High(ALines)) and (Trim(ALines[ALine]) = '');
end;

class function TRoutineParts.ApplyEdits(const ASource: string; ABase: Integer;
  AEdits: TArray<TOffsetEdit>): string;
var
  Index, Inner: Integer;
  Edit: TOffsetEdit;
begin
  // Von hinten nach vorn; nach Start sortiert (einfaches Einfügen, die Listen sind kurz).
  for Index := 1 to High(AEdits) do
  begin
    Edit := AEdits[Index];
    Inner := Index - 1;
    while (Inner >= 0) and (AEdits[Inner].Start > Edit.Start) do
    begin
      AEdits[Inner + 1] := AEdits[Inner];
      Dec(Inner);
    end;
    AEdits[Inner + 1] := Edit;
  end;
  Result := ASource;
  for Index := High(AEdits) downto 0 do
    Result := Copy(Result, 1, AEdits[Index].Start - ABase) + AEdits[Index].Text +
      Copy(Result, AEdits[Index].Stop - ABase + 1, MaxInt);
end;

class function TRoutineParts.NameTokens(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode;
  out AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) and
    (ATokens[Index].IsKeyword('class') or ATokens[Index].IsKeyword('procedure') or
    ATokens[Index].IsKeyword('function') or (ATokens[Index].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive])) do
    Inc(Index);
  if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
    Exit;
  AFirst := Index;
  ALast := Index;
  while (ALast + 2 <= High(ATokens)) and ATokens[ALast + 1].IsSymbol('.') and
    (ATokens[ALast + 2].Kind = TPascalTokenKind.Identifier) do
    Inc(ALast, 2);
  Result := True;
end;

class function TRoutineParts.IsClassHeader(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  Result := (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class');
end;

class function TRoutineParts.HasWord(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode;
  const AWords: array of string): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ANode.EndOffset) do
  begin
    if (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      MatchText(ATokens[Index].Text, AWords) then
      Exit(True);
    Inc(Index);
  end;
  Result := False;
end;

class function TRoutineParts.ParameterTexts(const AText: string; AHeader: TSyntaxNode): TArray<TParameterText>;
var
  Parameters, Node: TSyntaxNode;
  Index, Colon: Integer;
  Source, Head, Modifier, Name: string;
  Item: TParameterText;
begin
  Result := nil;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Node := Parameters[Index];
    Source := Trim(TRoutineBody.TextOf(AText, Node));
    if EndsStr(';', Source) then
      Source := Trim(Copy(Source, 1, Length(Source) - 1));
    Colon := Pos(':', Source);
    if Colon > 0 then
    begin
      Head := Trim(Copy(Source, 1, Colon - 1));
      Item.Rest := ': ' + Trim(Copy(Source, Colon + 1, MaxInt));
    end
    else
    begin
      Head := Source;
      Item.Rest := '';
    end;
    Modifier := '';
    if MatchText(Head.Split([' '])[0], ['const', 'var', 'out', 'constref']) then
    begin
      Modifier := Head.Split([' '])[0];
      Head := Trim(Copy(Head, Length(Modifier) + 1, MaxInt));
    end;
    if StartsText('[ref]', Head) then
      Exit(nil);
    Item.Modifier := Modifier;
    for Name in Head.Split([',']) do
    begin
      Item.Name := Trim(Name);
      Result := Result + [Item];
    end;
  end;
end;

class function TRoutineParts.JoinParameters(const AParameters: TArray<TParameterText>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AParameters) do
  begin
    if Index > 0 then
      Result := Result + '; ';
    Result := Result + AParameters[Index].Text;
  end;
end;

class function TRoutineParts.HeadText(const AText: string; AHeader: TSyntaxNode; const AName: string;
  const AParameters: TArray<TParameterText>; AClass: Boolean): string;
var
  ResultType: TSyntaxNode;
begin
  ResultType := AHeader.FindChild(TSyntaxKind.TypeReference);
  if ResultType <> nil then
    Result := 'function '
  else
    Result := 'procedure ';
  if AClass then
    Result := 'class ' + Result;
  Result := Result + AName;
  if AParameters <> nil then
    Result := Result + '(' + JoinParameters(AParameters) + ')';
  if ResultType <> nil then
    Result := Result + ': ' + TRoutineBody.TextOf(AText, ResultType);
  Result := Result + ';';
end;

class function TRoutineParts.AnonymousHead(const AText: string; AHeader: TSyntaxNode;
  const AParameters: TArray<TParameterText>): string;
var
  ResultType: TSyntaxNode;
begin
  ResultType := AHeader.FindChild(TSyntaxKind.TypeReference);
  if ResultType <> nil then
    Result := 'function'
  else
    Result := 'procedure';
  if AParameters <> nil then
    Result := Result + '(' + JoinParameters(AParameters) + ')';
  if ResultType <> nil then
    Result := Result + ': ' + TRoutineBody.TextOf(AText, ResultType);
end;

class function TRoutineParts.ChildNames(ANode: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    for Name in ANode[Index].Name.Split([',']) do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
end;

class function TRoutineParts.UnitNames(ARoot: TSyntaxNode): TArray<string>;
var
  Section, Child: TSyntaxNode;
  Index, Inner: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ARoot.ChildCount - 1 do
  begin
    Section := ARoot[Index];
    if not (Section.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
      Continue;
    for Inner := 0 to Section.ChildCount - 1 do
    begin
      Child := Section[Inner];
      case Child.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
          if TRoutineBody.QualifierOf(Child.Name) = '' then
            Result := Result + [Child.Name];
        TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
          for Name in TRoutineParts.ChildNames(Child) do
            Result := Result + [Name];
      else
        // Übrige Arten: nichts zu tun.
      end;
    end;
  end;
end;

class function TRoutineParts.FreeName(const ABase: string; const ATaken: TArray<string>): string;
var
  Number: Integer;
begin
  Result := ABase;
  Number := 1;
  while IndexText(Result, ATaken) >= 0 do
  begin
    Inc(Number);
    Result := ABase + IntToStr(Number);
  end;
end;

class function TRoutineParts.InAnonymous(ANode, AStop: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if Node.Kind = TSyntaxKind.AnonymousMethod then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

class function TRoutineParts.Shadowed(ACache: TLocalsCache; ANode, AStop: TSyntaxNode; const AName: string;
  AWithStop: Boolean): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if (Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) and
      ACache.Declares(Node, AName, ANode.StartOffset) then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := AWithStop and (Node = AStop) and ACache.Declares(AStop, AName, ANode.StartOffset);
end;

class function TRoutineParts.TopRoutineAt(ATree: TSyntaxTree; AOffset: Integer;
  out ADeclaration: TSyntaxNode): TSyntaxNode;
var
  Found, Implementation_: TSyntaxNode;
  Offset, Index: Integer;
  Name: string;
begin
  ADeclaration := nil;
  Result := RoutineWithHeaderAt(ATree, AOffset);
  if Result <> nil then
    Exit;
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
        Found := ANode;
    end);
  if (Found = nil) or (Found.Parent.Parent = nil) then
    Exit;
  ADeclaration := Found;
  Name := Found.Parent.Parent.Name + '.' + Found.Name;
  Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Implementation_ = nil then
    Exit;
  for Index := 0 to Implementation_.ChildCount - 1 do
    if (Implementation_[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Implementation_[Index].Name, Name) then
      Exit(Implementation_[Index]);
end;

{ TLocalsCache }

constructor TLocalsCache.Create(const AText: string; ATree: TSyntaxTree);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FLocals := TDictionary<TSyntaxNode, TArray<TRoutineLocal>>.Create;
end;

destructor TLocalsCache.Destroy;
begin
  FLocals.Free;
  inherited;
end;

function TLocalsCache.Locals(ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
begin
  if not FLocals.TryGetValue(ARoutine, Result) then
  begin
    Result := nil;
    if TRoutineBody.BodyOf(ARoutine) <> nil then
      Result := TRoutineLocals.Collect(FText, FTree, ARoutine);
    FLocals.Add(ARoutine, Result);
  end;
end;

function TLocalsCache.Declares(ARoutine: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
var
  Local: TRoutineLocal;
  Index: Integer;
  Child: TSyntaxNode;
  Name: string;
begin
  if SameText(AName, 'Result') and TRoutineParts.IsFunction(ARoutine) then
    Exit(True);
  for Local in Locals(ARoutine) do
    if SameText(Local.Name, AName) and ((Local.Kind in [TRoutineLocalKind.Parameter, TRoutineLocalKind.Variable,
      TRoutineLocalKind.Constant]) or ((Local.ScopeStart <= AOffset) and (AOffset <= Local.ScopeEnd))) then
      Exit(True);
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Child := ARoutine[Index];
    if (Child.Kind = TSyntaxKind.RoutineDecl) and SameText(Child.Name, AName) then
      Exit(True);
    if Child.Kind = TSyntaxKind.TypeSection then
      for Name in TRoutineParts.ChildNames(Child) do
        if SameText(Name, AName) then
          Exit(True);
  end;
  Result := False;
end;
end.
