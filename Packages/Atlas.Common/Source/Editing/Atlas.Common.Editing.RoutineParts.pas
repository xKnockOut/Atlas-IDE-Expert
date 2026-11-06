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
  begin
    Result := Modifier + ' ' + Result;
  end;
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
  begin
    Header := ARoutine;
  end
  else
  begin
    Header := HeaderOf(ARoutine);
  end;
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
        begin
          Found := ANode;
        end;
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
  begin
    Result := Copy(Result, 1, AEdits[Index].Start - ABase) + AEdits[Index].Text +
      Copy(Result, AEdits[Index].Stop - ABase + 1, MaxInt);
  end;
end;

/// <summary>Wort vor dem Routinennamen im Kopf: class, procedure, function, Kommentar oder Direktive.</summary>
function IsHeadPrefix(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('class') or AToken.IsKeyword('procedure') or AToken.IsKeyword('function') or
    (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

class function TRoutineParts.NameTokens(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode;
  out AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  Index := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) and
    IsHeadPrefix(ATokens[Index]) do
  begin
    Inc(Index);
  end;
  if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  AFirst := Index;
  ALast := Index;
  while (ALast + 2 <= High(ATokens)) and ATokens[ALast + 1].IsSymbol('.') and
    (ATokens[ALast + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(ALast, 2);
  end;
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
    begin
      Exit(True);
    end;
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
  begin
    Exit;
  end;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Node := Parameters[Index];
    Source := Trim(TRoutineBody.TextOf(AText, Node));
    if EndsStr(';', Source) then
    begin
      Source := Trim(Copy(Source, 1, Length(Source) - 1));
    end;
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
    begin
      Exit(nil);
    end;
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
    begin
      Result := Result + '; ';
    end;
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
  begin
    Result := 'function ';
  end
  else
  begin
    Result := 'procedure ';
  end;
  if AClass then
  begin
    Result := 'class ' + Result;
  end;
  Result := Result + AName;
  if AParameters <> nil then
  begin
    Result := Result + '(' + JoinParameters(AParameters) + ')';
  end;
  if ResultType <> nil then
  begin
    Result := Result + ': ' + TRoutineBody.TextOf(AText, ResultType);
  end;
  Result := Result + ';';
end;

class function TRoutineParts.AnonymousHead(const AText: string; AHeader: TSyntaxNode;
  const AParameters: TArray<TParameterText>): string;
var
  ResultType: TSyntaxNode;
begin
  ResultType := AHeader.FindChild(TSyntaxKind.TypeReference);
  if ResultType <> nil then
  begin
    Result := 'function';
  end
  else
  begin
    Result := 'procedure';
  end;
  if AParameters <> nil then
  begin
    Result := Result + '(' + JoinParameters(AParameters) + ')';
  end;
  if ResultType <> nil then
  begin
    Result := Result + ': ' + TRoutineBody.TextOf(AText, ResultType);
  end;
end;

class function TRoutineParts.ChildNames(ANode: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    for Name in ANode[Index].Name.Split([',']) do
    begin
      if Trim(Name) <> '' then
      begin
        Result := Result + [Trim(Name)];
      end;
    end;
  end;
end;

/// <summary>Namen, die der Abschnitt ASection (interface oder implementation) auf Unit-Ebene vergibt.</summary>
function SectionNames(ASection: TSyntaxNode): TArray<string>;
var
  mChild: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    case mChild.Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
        if TRoutineBody.QualifierOf(mChild.Name) = '' then
        begin
          Result := Result + [mChild.Name];
        end;
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        Result := Result + TRoutineParts.ChildNames(mChild);
    else
      // Übrige Arten: nichts zu tun.
    end;
  end;
end;

class function TRoutineParts.UnitNames(ARoot: TSyntaxNode): TArray<string>;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    mSection := ARoot[mIndex];
    if mSection.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
    begin
      Result := Result + SectionNames(mSection);
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
    begin
      Exit(True);
    end;
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
    begin
      Exit(True);
    end;
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
  begin
    Exit;
  end;
  Found := nil;
  Offset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Encloses(ANode, Offset);
      if Result and (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
      begin
        Found := ANode;
      end;
    end);
  if (Found = nil) or (Found.Parent.Parent = nil) then
  begin
    Exit;
  end;
  ADeclaration := Found;
  Name := Found.Parent.Parent.Name + '.' + Found.Name;
  Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Implementation_ = nil then
  begin
    Exit;
  end;
  for Index := 0 to Implementation_.ChildCount - 1 do
  begin
    if (Implementation_[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Implementation_[Index].Name, Name) then
    begin
      Exit(Implementation_[Index]);
    end;
  end;
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
    begin
      Result := TRoutineLocals.Collect(FText, FTree, ARoutine);
    end;
    FLocals.Add(ARoutine, Result);
  end;
end;

/// <summary>Gilt der lokale Name ALocal an AOffset? Parameter, Variablen und Konstanten des Kopfs überall,
/// Inline-Variablen nur in ihrem Gültigkeitsbereich.</summary>
function LocalVisible(const ALocal: TRoutineLocal; const AName: string; AOffset: Integer): Boolean;
begin
  Result := SameText(ALocal.Name, AName) and ((ALocal.Kind in [TRoutineLocalKind.Parameter,
    TRoutineLocalKind.Variable, TRoutineLocalKind.Constant]) or ((ALocal.ScopeStart <= AOffset) and
    (AOffset <= ALocal.ScopeEnd)));
end;

/// <summary>Deklariert ARoutine eine lokale Routine oder einen lokalen Typ namens AName?</summary>
function DeclaresNested(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := False;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mChild := ARoutine[mIndex];
    if (mChild.Kind = TSyntaxKind.RoutineDecl) and SameText(mChild.Name, AName) then
    begin
      Exit(True);
    end;
    if (mChild.Kind = TSyntaxKind.TypeSection) and MatchText(AName, TRoutineParts.ChildNames(mChild)) then
    begin
      Exit(True);
    end;
  end;
end;

function TLocalsCache.Declares(ARoutine: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
var
  mLocal: TRoutineLocal;
begin
  if SameText(AName, 'Result') and TRoutineParts.IsFunction(ARoutine) then
  begin
    Exit(True);
  end;
  for mLocal in Locals(ARoutine) do
  begin
    if LocalVisible(mLocal, AName, AOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := DeclaresNested(ARoutine, AName);
end;
end.
