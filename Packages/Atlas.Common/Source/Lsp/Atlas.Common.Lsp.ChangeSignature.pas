unit Atlas.Common.Lsp.ChangeSignature;

// „Signatur ändern“ (#100): Parameter hinzufügen, entfernen, umsortieren und
// umbenennen samt aller Aufrufer, Überschreibungen in Vor- und Nachfahren,
// Interface-Deklarationen und -Implementierungen sowie Ereignistypen von
// Handlern, die eine Formulardatei bindet.
//
// Ablauf: Die Code-Aktion „Signatur ändern …“ trägt den Client-Befehl
// atlas.changeSignature. Das Plugin fragt atlas.server.changeSignature.prepare
// (Parameter, Einschränkungen), zeigt die Eingabemaske und schickt das
// Ergebnis an atlas.server.changeSignature; die Antwort ist ein WorkspaceEdit
// mit Warnungen für die Vorschau.
//
// Neue Parameter: Im Modus overload bekommt die Methode die neue Signatur und
// die alte bleibt als Überladung, die mit dem angegebenen Wert weiterreicht;
// Aufrufer bleiben unverändert. Im Modus updateCallers übergibt jeder Aufrufer
// den Wert. Interface-Methoden und gebundene Handler gehen nur mit
// updateCallers. Atlas erzeugt keine Standardwerte.
//
// Abbruch: Ereignistyp aus einer Bibliothek, entfernter Parameter im Rumpf
// verwendet, Kollision mit einer vorhandenen Überladung, Deklaration
// schreibgeschützt oder außerhalb des Projekts, Zugriffsmethode einer
// Property, Ergebnis parst nicht. Warnung: Verwendung als Methodenzeiger,
// Aufrufer in schreibgeschützten Dateien (bleiben unverändert).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Rename;

type
  {$SCOPEDENUMS ON}
  TNewParameterMode = (Overload, UpdateCallers);
  {$SCOPEDENUMS OFF}

  /// <summary>True, wenn die Datei schreibgeschützt ist.</summary>
  TChangeSignatureReadOnly = reference to function(const AFileName: string): Boolean;

  TChangeSignatureInfo = record
    Name: string;
    Container: string;
    /// <summary>procedure, function, constructor oder destructor.</summary>
    Keyword: string;
    ResultType: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Deklarationen und Rümpfe, die sich mitändern (Vorfahren, Nachfahren, Interfaces).</summary>
    Members: Integer;
    /// <summary>Gehört zu einer Interface-Methode: neue Parameter nur mit updateCallers.</summary>
    InterfaceMethod: Boolean;
    /// <summary>Ereignistyp, an den eine Formulardatei die Methode bindet; '' ohne.</summary>
    BoundEvent: string;
    /// <summary>Der Ereignistyp stammt aus einer Bibliothek: Parameter nur umbenennen.</summary>
    EventFixed: Boolean;
    Warnings: TArray<string>;
  end;

  TChangeSignatureRequest = record
    Changes: TArray<TParameterChange>;
    Mode: TNewParameterMode;
    VirtualOverload: Boolean;
  end;

  TChangeSignatureOutcome = record
    Edits: TArray<TRenameEdit>;
    Warnings: TArray<string>;
    /// <summary>Tatsächlicher Modus (overload kann zu updateCallers werden).</summary>
    Mode: TNewParameterMode;
  end;

  TLspChangeSignature = class
  public const
    ClientCommand = 'atlas.changeSignature';
    PrepareCommand = 'atlas.server.changeSignature.prepare';
    ApplyCommand = 'atlas.server.changeSignature';
    Title = 'Signatur ändern …';
  public
    /// <summary>Steht an APosition der Name einer Routine (Deklaration, Rumpf oder Aufruf)?</summary>
    class function IsOffered(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): Boolean; static;
    /// <summary>Code-Aktion mit dem Client-Befehl. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionJson(const AUri: string; const APosition: TTextPosition): TJSONObject; static;
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet (refactoring.changeSignature) und dort eine
    /// Routine steht; sonst nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Parameter und Einschränkungen; EJsonRpcError, wenn die Signatur nicht änderbar ist.</summary>
    class function Prepare(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TChangeSignatureInfo;
      static;
    /// <summary>Alle Änderungen; EJsonRpcError in den Abbruchfällen.</summary>
    class function Execute(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; const ARequest: TChangeSignatureRequest;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText; const AIsReadOnly: TChangeSignatureReadOnly;
      const ACancellation: IJsonRpcCancellationToken): TChangeSignatureOutcome; static;
    /// <summary>Antwort auf PrepareCommand. Der Aufrufer übernimmt das Objekt.</summary>
    class function InfoToJson(const AInfo: TChangeSignatureInfo; AMode: TNewParameterMode;
      AVirtualOverload: Boolean): TJSONObject; static;
    /// <summary>Drittes Argument von ApplyCommand: {"parameters": [...], "newParameter", "virtualOverload"}.</summary>
    class function ReadRequest(const AValue: TJSONValue; ADefaultMode: TNewParameterMode;
      ADefaultVirtual: Boolean): TChangeSignatureRequest; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "newParameter": ...}. Der Aufrufer übernimmt das Objekt.</summary>
    class function OutcomeToJson(const AOutcome: TChangeSignatureOutcome): TJSONObject; static;
    class function ModeName(AMode: TNewParameterMode): string; static;
    class function ModeOf(const AName: string; ADefault: TNewParameterMode): TNewParameterMode; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Text.Lines;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  MaxDepth = 32;
  MaxMembers = 500;

type
  {$SCOPEDENUMS ON}
  TMemberKind = (Method, InterfaceMethod, Routine, EventType);
  TEditKind = (Header, Rename, Call, Insert);
  {$SCOPEDENUMS OFF}

  TSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Symbols: TArray<TIndexSymbol>;
    destructor Destroy; override;
    function Tokens: TArray<TPascalToken>;
  end;

  TMember = record
    Kind: TMemberKind;
    FileName: string;
    Container: string;
    Name: string;
    Decl: TSignatureHeader;
    HasBody: Boolean;
    /// <summary>Rumpf und Deklaration sind derselbe Kopf (Routine nur im implementation-Teil).</summary>
    DeclIsBody: Boolean;
    Body: TSignatureHeader;
    BodyLast: Integer;
    IsRoot: Boolean;
  end;

  TFileEdit = record
    Kind: TEditKind;
    Range: TTextRange;
    NewText: string;
    /// <summary>Bei Call: Position des Namens und die Werte für neue Parameter.</summary>
    NamePos: TTextPosition;
    Values: TArray<string>;
  end;

  TCallSite = record
    FileName: string;
    NamePos: TTextPosition;
    /// <summary>inherited Name(...) im Rumpf einer Überschreibung: neue Parameter mit ihrem Namen.</summary>
    InheritedInMember: Boolean;
  end;

  /// <summary>Sammelt Mitglieder und Verwendungen; hält die gelesenen Dateien.</summary>
  TSignatureCollector = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FFiles: TArray<string>;
    FReadText: TReferenceReadText;
    FCancellation: IJsonRpcCancellationToken;
    FCurrentFile: string;
    FSources: TObjectDictionary<string, TSourceFile>;
    FSeen: TDictionary<string, Boolean>;
  public
    Members: TArray<TMember>;
    Calls: TArray<TCallSite>;
    Warnings: TArray<string>;
    Accessors: TArray<string>;
    BoundEvent: string;
    EventFixed: Boolean;
    InterfaceMethod: Boolean;
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken; const ACurrentFile: string);
    destructor Destroy; override;
    function Source(const AFileName: string): TSourceFile;
    function InProject(const AFileName: string): Boolean;
    procedure Collect(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition);
    function Root: TMember;
  private
    function FindTarget(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out AFile: string; out ADecl: TIndexSymbol): Boolean;
    function DeclaredIn(const ATypeName: string; const AName: string; const AParamTypes: TArray<string>;
      out AFile: string; out ADecl: TIndexSymbol): Boolean;
    function TypeSymbol(const ATypeName: string; out ALocation: TSymbolLocation): Boolean;
    function AddMember(AKind: TMemberKind; const AFileName: string; const ADecl: TIndexSymbol; AIsRoot: Boolean): Boolean;
    procedure CollectHierarchy(const AFile: string; const ADecl: TIndexSymbol);
    procedure CollectUses(const ADecl: TIndexSymbol);
    procedure CollectFormBinding(const AFormFile: string; const APosition: TTextPosition);
    function IsHeaderName(const AFileName: string; const APosition: TTextPosition): Boolean;
    function InMemberBody(const AFileName: string; ATokenIndex: Integer): Boolean;
    function EventTypeOf(const AClassName, AProperty: string): string;
  end;

function SameTypes(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if not SameText(StringReplace(A[Index], ' ', '', [rfReplaceAll]), StringReplace(B[Index], ' ', '',
        [rfReplaceAll])) then
        Exit(False);
end;

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Contains(const AOuter, AInner: TTextRange): Boolean;
begin
  Result := not Before(AInner.StartPos, AOuter.StartPos) and not Before(AOuter.EndPos, AInner.EndPos) and
    ((AOuter.StartPos <> AInner.StartPos) or (AOuter.EndPos <> AInner.EndPos));
end;

function Overlaps(const A, B: TTextRange): Boolean;
begin
  Result := Before(A.StartPos, B.EndPos) and Before(B.StartPos, A.EndPos);
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function TypeKey(const AName: string): string;
begin
  Result := UpperCase(AName);
end;

{ TSourceFile }

destructor TSourceFile.Destroy;
begin
  Tree.Free;
  inherited;
end;

function TSourceFile.Tokens: TArray<TPascalToken>;
begin
  Result := Tree.Tokens;
end;

{ TSignatureCollector }

constructor TSignatureCollector.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken;
  const ACurrentFile: string);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FFiles := AFiles;
  FReadText := AReadText;
  FCancellation := ACancellation;
  FCurrentFile := ACurrentFile;
  FSources := TObjectDictionary<string, TSourceFile>.Create([doOwnsValues]);
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TSignatureCollector.Destroy;
begin
  FSeen.Free;
  FSources.Free;
  inherited;
end;

function TSignatureCollector.InProject(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, FCurrentFile) or (IndexText(AFileName, FFiles) >= 0);
end;

function TSignatureCollector.Source(const AFileName: string): TSourceFile;
var
  Text: string;
begin
  if FSources.TryGetValue(UpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  if not (Assigned(FReadText) and FReadText(AFileName, Text)) then
    Exit;
  Result := TSourceFile.Create;
  Result.FileName := AFileName;
  Result.Text := Text;
  if SameText(ExtractFileExt(AFileName), '.pas') or SameText(ExtractFileExt(AFileName), '.dpr') or
    SameText(ExtractFileExt(AFileName), '.inc') then
  begin
    Result.Tree := TSyntaxTreeCache.Parse(Text);
    Result.Symbols := TIndexExtractor.Extract(Result.Tree, AFileName).Symbols;
  end;
  FSources.Add(UpperCase(AFileName), Result);
end;

function TSignatureCollector.FindTarget(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AFile: string; out ADecl: TIndexSymbol): Boolean;
var
  Resolved: TResolvedSymbol;
  Current: TSourceFile;
  Symbol, Candidate: TIndexSymbol;
  Position: TTextPosition;
  Found: Boolean;
begin
  Result := False;
  AFile := '';
  Position := Default(TTextPosition);
  Found := False;
  Resolved := FResolver.Resolve(ATree, AFileName, APosition);
  if (Resolved.Kind = TResolvedKind.Symbol) and (Resolved.SymbolKind in RoutineKinds) then
  begin
    AFile := Resolved.FileName;
    Position := Resolved.SelectionRange.StartPos;
    Found := True;
  end
  else
  begin
    // Auf dem Namen einer Deklaration bzw. eines Rumpfs.
    Current := Source(AFileName);
    if Current <> nil then
      for Symbol in Current.Symbols do
        if (Symbol.Kind in RoutineKinds) and Within(APosition, Symbol.SelectionRange) then
        begin
          AFile := AFileName;
          Position := Symbol.SelectionRange.StartPos;
          Found := True;
          Break;
        end;
  end;
  if not Found then
    Exit;
  Current := Source(AFile);
  if Current = nil then
    Exit;
  for Symbol in Current.Symbols do
    if (Symbol.Kind in RoutineKinds) and (Symbol.SelectionRange.StartPos = Position) then
    begin
      // Vom Rumpf zur Deklaration: die erste Fundstelle mit denselben Parametern.
      ADecl := Symbol;
      for Candidate in Current.Symbols do
        if (Candidate.Kind in RoutineKinds) and SameText(Candidate.Container, Symbol.Container) and
          SameText(Candidate.Name, Symbol.Name) and (SameTypes(Candidate.ParamTypes, Symbol.ParamTypes) or
          (Length(Symbol.ParamTypes) = 0)) then
        begin
          ADecl := Candidate;
          Break;
        end;
      Exit(True);
    end;
end;

function TSignatureCollector.TypeSymbol(const ATypeName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
  Name: string;
begin
  Name := ATypeName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Location in FIndex.FindSymbols(Name) do
    if (Location.Symbol.Kind in ClassKinds + [TIndexSymbolKind.InterfaceType]) and
      (SameText(Location.Symbol.QualifiedName, ATypeName) or SameText(Location.Symbol.Name, ATypeName)) then
    begin
      ALocation := Location;
      Exit(True);
    end;
  Result := False;
end;

function TSignatureCollector.DeclaredIn(const ATypeName: string; const AName: string;
  const AParamTypes: TArray<string>; out AFile: string; out ADecl: TIndexSymbol): Boolean;
var
  Location: TSymbolLocation;
  Unit_: TSourceFile;
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not TypeSymbol(ATypeName, Location) then
    Exit;
  AFile := Location.FileName;
  Unit_ := Source(AFile);
  if (Unit_ = nil) or (Unit_.Tree = nil) then
    Exit;
  for Symbol in Unit_.Symbols do
    if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Location.Symbol.QualifiedName) and
      SameText(Symbol.Name, AName) and SameTypes(Symbol.ParamTypes, AParamTypes) then
    begin
      ADecl := Symbol;
      Exit(True);
    end;
end;

function TSignatureCollector.AddMember(AKind: TMemberKind; const AFileName: string; const ADecl: TIndexSymbol;
  AIsRoot: Boolean): Boolean;
var
  Unit_: TSourceFile;
  Member: TMember;
  Symbol: TIndexSymbol;
  Token, Index: Integer;
  Header: TSignatureHeader;
  Key: string;
begin
  Result := False;
  Key := UpperCase(AFileName + '|' + ADecl.Container + '|' + ADecl.Name + '|' +
    IntToStr(ADecl.SelectionRange.StartPos.Line));
  if FSeen.ContainsKey(Key) then
    Exit(True);
  FSeen.Add(Key, True);
  if Length(Members) >= MaxMembers then
    Exit;
  if not InProject(AFileName) then
    raise Fail(Format('%s steht außerhalb des Projekts (%s); dort lässt sich die Signatur nicht ändern.',
      [ADecl.QualifiedName, ExtractFileName(AFileName)]));
  Unit_ := Source(AFileName);
  if (Unit_ = nil) or (Unit_.Tree = nil) then
    raise Fail(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  Member := Default(TMember);
  Member.Kind := AKind;
  Member.FileName := AFileName;
  Member.Container := ADecl.Container;
  Member.Name := ADecl.Name;
  Member.IsRoot := AIsRoot;
  Member.BodyLast := -1;
  Token := TChangeSignature.NameTokenAt(Unit_.Tokens, ADecl.SelectionRange.StartPos);
  if not TChangeSignature.ReadHeader(Unit_.Text, Unit_.Tokens, Token, Member.Decl) then
    raise Fail(Format('Der Kopf von %s lässt sich nicht lesen.', [ADecl.QualifiedName]));
  // Routine nur im implementation-Teil: der Kopf des Rumpfs ist die Deklaration.
  Index := TChangeSignature.BodyEnd(Unit_.Tree, Member.Decl);
  if Index >= 0 then
  begin
    Member.DeclIsBody := True;
    Member.HasBody := True;
    Member.Body := Member.Decl;
    Member.BodyLast := Index;
  end
  else if AKind <> TMemberKind.InterfaceMethod then
    for Symbol in Unit_.Symbols do
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, ADecl.Container) and
        SameText(Symbol.Name, ADecl.Name) and (Symbol.SelectionRange.StartPos <> ADecl.SelectionRange.StartPos) then
      begin
        Token := TChangeSignature.NameTokenAt(Unit_.Tokens, Symbol.SelectionRange.StartPos);
        if not TChangeSignature.ReadHeader(Unit_.Text, Unit_.Tokens, Token, Header) then
          Continue;
        // Überladungen: gleiche Parameter; ein Rumpf ohne Parameterliste gehört zur einzigen Deklaration.
        if not (SameTypes(Header.ParamTypes, Member.Decl.ParamTypes) or
          ((Header.OpenToken < 0) and (Length(Member.Decl.Parameters) > 0))) then
          Continue;
        Index := TChangeSignature.BodyEnd(Unit_.Tree, Header);
        if Index < 0 then
          Continue;
        Member.HasBody := True;
        Member.Body := Header;
        Member.BodyLast := Index;
        Break;
      end;
  Members := Members + [Member];
  Result := True;
end;

procedure TSignatureCollector.CollectHierarchy(const AFile: string; const ADecl: TIndexSymbol);
var
  Pending: TQueue<TPair<string, Integer>>;
  Visited: TDictionary<string, Boolean>;
  Current: TPair<string, Integer>;
  RootFile, MemberFile, Ancestor, Climb: string;
  Root, Found, Inherited_: TIndexSymbol;
  Location, Owner: TSymbolLocation;
  Types: TArray<string>;
  IsInterface, Declares: Boolean;
  Index: Integer;
begin
  Root := ADecl;
  RootFile := AFile;
  Types := ADecl.ParamTypes;
  // Zur Methode, die die Kette beginnt: über override nach oben.
  while Root.HasDirective('override') do
  begin
    if not TypeSymbol(Root.Container, Owner) or (Length(Owner.Symbol.Ancestors) = 0) then
      raise Fail(Format('%s überschreibt eine Methode, deren Vorfahr nicht im Index steht.', [Root.QualifiedName]));
    Ancestor := Owner.Symbol.Ancestors[0];
    Found := Default(TIndexSymbol);
    MemberFile := '';
    Climb := Ancestor;
    Index := 0;
    while (Climb <> '') and (Index < MaxDepth) and not DeclaredIn(Climb, Root.Name, Types, MemberFile, Found) do
    begin
      Inc(Index);
      if TypeSymbol(Climb, Owner) and (Length(Owner.Symbol.Ancestors) > 0) then
        Climb := Owner.Symbol.Ancestors[0]
      else
        Climb := '';
    end;
    if Found.Name = '' then
      raise Fail(Format('Die überschriebene Methode von %s steht nicht im Index.', [Root.QualifiedName]));
    if not InProject(MemberFile) then
      raise Fail(Format('%s überschreibt %s außerhalb des Projekts (%s); dort lässt sich die Signatur nicht ' +
        'ändern.', [Root.QualifiedName, Found.QualifiedName, ExtractFileName(MemberFile)]));
    Root := Found;
    RootFile := MemberFile;
  end;
  if Root.Container = '' then
  begin
    AddMember(TMemberKind.Routine, RootFile, Root, True);
    Exit;
  end;
  IsInterface := TypeSymbol(Root.Container, Owner) and (Owner.Symbol.Kind = TIndexSymbolKind.InterfaceType);
  if IsInterface then
  begin
    InterfaceMethod := True;
    AddMember(TMemberKind.InterfaceMethod, RootFile, Root, True);
  end
  else
    AddMember(TMemberKind.Method, RootFile, Root, True);

  // Nachfahren, implementierende Klassen und implementierte Interfaces.
  Pending := TQueue<TPair<string, Integer>>.Create;
  Visited := TDictionary<string, Boolean>.Create;
  try
    Pending.Enqueue(TPair<string, Integer>.Create(Root.Container, 0));
    Visited.Add(TypeKey(Root.Container), True);
    while Pending.Count > 0 do
    begin
      if Assigned(FCancellation) then
        FCancellation.ThrowIfCancellationRequested;
      Current := Pending.Dequeue;
      if Current.Value >= MaxDepth then
        Continue;
      if not TypeSymbol(Current.Key, Owner) then
        Continue;
      IsInterface := Owner.Symbol.Kind = TIndexSymbolKind.InterfaceType;
      Declares := DeclaredIn(Current.Key, Root.Name, Types, MemberFile, Found);
      if Declares and not SameText(Found.QualifiedName, Root.QualifiedName) then
      begin
        if IsInterface then
        begin
          InterfaceMethod := True;
          AddMember(TMemberKind.InterfaceMethod, MemberFile, Found, False);
        end
        else if Found.HasDirective('override') or InterfaceMethod then
          AddMember(TMemberKind.Method, MemberFile, Found, False);
      end;
      // Interfaces in der Vorfahrenliste einer Klasse.
      if not IsInterface then
        for Index := 1 to High(Owner.Symbol.Ancestors) do
        begin
          Ancestor := Owner.Symbol.Ancestors[Index];
          if Visited.ContainsKey(TypeKey(Ancestor)) then
            Continue;
          if TypeSymbol(Ancestor, Location) and (Location.Symbol.Kind = TIndexSymbolKind.InterfaceType) and
            DeclaredIn(Ancestor, Root.Name, Types, MemberFile, Found) then
          begin
            Visited.Add(TypeKey(Ancestor), True);
            Pending.Enqueue(TPair<string, Integer>.Create(Location.Symbol.QualifiedName, Current.Value + 1));
          end;
        end;
      for Location in FIndex.Descendants(Owner.Symbol.Name) do
      begin
        if not (Location.Symbol.Kind in ClassKinds + [TIndexSymbolKind.InterfaceType]) then
          Continue;
        if Visited.ContainsKey(TypeKey(Location.Symbol.QualifiedName)) then
          Continue;
        Visited.Add(TypeKey(Location.Symbol.QualifiedName), True);
        // Eine Klasse, die das Interface über eine geerbte Methode erfüllt: deren Klasse gehört dazu.
        if IsInterface and (Location.Symbol.Kind <> TIndexSymbolKind.InterfaceType) and
          not DeclaredIn(Location.Symbol.QualifiedName, Root.Name, Types, MemberFile, Found) then
        begin
          Climb := '';
          if Length(Location.Symbol.Ancestors) > 0 then
            Climb := Location.Symbol.Ancestors[0];
          Index := 0;
          while (Climb <> '') and (Index < MaxDepth) do
          begin
            Inc(Index);
            if DeclaredIn(Climb, Root.Name, Types, MemberFile, Inherited_) then
            begin
              if not Visited.ContainsKey(TypeKey(Inherited_.Container)) then
              begin
                Visited.Add(TypeKey(Inherited_.Container), True);
                AddMember(TMemberKind.Method, MemberFile, Inherited_, False);
                Pending.Enqueue(TPair<string, Integer>.Create(Inherited_.Container, Current.Value + 1));
              end;
              Break;
            end;
            if TypeSymbol(Climb, Owner) and (Length(Owner.Symbol.Ancestors) > 0) then
              Climb := Owner.Symbol.Ancestors[0]
            else
              Climb := '';
          end;
        end;
        Pending.Enqueue(TPair<string, Integer>.Create(Location.Symbol.QualifiedName, Current.Value + 1));
      end;
    end;
  finally
    Visited.Free;
    Pending.Free;
  end;
end;

function TSignatureCollector.IsHeaderName(const AFileName: string; const APosition: TTextPosition): Boolean;
var
  Member: TMember;
  Unit_: TSourceFile;
begin
  for Member in Members do
  begin
    if not SameText(Member.FileName, AFileName) then
      Continue;
    Unit_ := Source(Member.FileName);
    if Unit_.Tokens[Member.Decl.NameToken].StartPos = APosition then
      Exit(True);
    if Member.HasBody and (Unit_.Tokens[Member.Body.NameToken].StartPos = APosition) then
      Exit(True);
  end;
  Result := False;
end;

function TSignatureCollector.InMemberBody(const AFileName: string; ATokenIndex: Integer): Boolean;
var
  Member: TMember;
begin
  for Member in Members do
    if SameText(Member.FileName, AFileName) and Member.HasBody and (ATokenIndex > Member.Body.LastToken) and
      (ATokenIndex <= Member.BodyLast) then
      Exit(True);
  Result := False;
end;

function TSignatureCollector.EventTypeOf(const AClassName, AProperty: string): string;
var
  Climb: string;
  Owner: TSymbolLocation;
  Unit_: TSourceFile;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Symbols: TArray<TIndexSymbol>;
  Depth: Integer;
begin
  Result := '';
  Climb := AClassName;
  Depth := 0;
  while (Climb <> '') and (Depth < MaxDepth) do
  begin
    Inc(Depth);
    if not TypeSymbol(Climb, Owner) then
      Exit;
    Unit_ := Source(Owner.FileName);
    if (Unit_ <> nil) and (Unit_.Tree <> nil) then
      Symbols := Unit_.Symbols
    else if FIndex.FindFile(Owner.FileName, UnitIndex) then
      Symbols := UnitIndex.Symbols
    else
      Symbols := nil;
    for Symbol in Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Symbol.Container, Owner.Symbol.QualifiedName) and
        SameText(Symbol.Name, AProperty) and (Symbol.TypeName <> '') then
        Exit(Symbol.TypeName);
    if Length(Owner.Symbol.Ancestors) = 0 then
      Exit;
    Climb := Owner.Symbol.Ancestors[0];
  end;
end;

procedure TSignatureCollector.CollectFormBinding(const AFormFile: string; const APosition: TTextPosition);
var
  Form: TSourceFile;
  Document: TDfmDocument;
  ComponentClass, PropertyName, EventType: string;
  Location: TSymbolLocation;
  Symbol: TIndexSymbol;
  Unit_: TSourceFile;
  Member: TMember;
  Token: Integer;

  function Search(AObject: TDfmObject): Boolean;
  var
    Item: TDfmProperty;
    Child: TDfmObject;
  begin
    for Item in AObject.Properties do
      if Item.IsEvent and (Item.ValueRange.StartPos = APosition) then
      begin
        ComponentClass := AObject.TypeName;
        PropertyName := Item.Name;
        Exit(True);
      end;
    for Child in AObject.Children do
      if Search(Child) then
        Exit(True);
    Result := False;
  end;

begin
  Form := Source(AFormFile);
  if Form = nil then
    Exit;
  Document := TDfmParser.Parse(Form.Text);
  try
    if (Document.Root = nil) or not Search(Document.Root) then
      Exit;
  finally
    Document.Free;
  end;
  EventType := EventTypeOf(ComponentClass, PropertyName);
  if EventType = '' then
  begin
    BoundEvent := PropertyName;
    EventFixed := True;
    Exit;
  end;
  BoundEvent := EventType;
  // Ereignistyp im Projekt: seine Parameterliste ändert sich mit.
  for Location in FIndex.FindSymbols(EventType) do
    if (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and InProject(Location.FileName) then
    begin
      Unit_ := Source(Location.FileName);
      if (Unit_ = nil) or (Unit_.Tree = nil) then
        Continue;
      for Symbol in Unit_.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.TypeAlias) and SameText(Symbol.Name, EventType) then
        begin
          Member := Default(TMember);
          Member.Kind := TMemberKind.EventType;
          Member.FileName := Location.FileName;
          Member.Name := EventType;
          Member.BodyLast := -1;
          Token := TChangeSignature.NameTokenAt(Unit_.Tokens, Symbol.SelectionRange.StartPos);
          if TChangeSignature.ReadProcedureType(Unit_.Text, Unit_.Tokens, Token, Member.Decl) then
          begin
            if not FSeen.ContainsKey('EVENT|' + UpperCase(EventType)) then
            begin
              FSeen.Add('EVENT|' + UpperCase(EventType), True);
              Members := Members + [Member];
              Warnings := Warnings + [Format('Der Ereignistyp %s ändert sich mit; weitere Handler dieses Typs und ' +
                'Aufrufe über das Ereignis passt Atlas nicht an.', [EventType])];
            end;
            Exit;
          end;
        end;
    end;
  EventFixed := True;
end;

procedure TSignatureCollector.CollectUses(const ADecl: TIndexSymbol);
var
  Member: TMember;
  Unit_, Other: TSourceFile;
  Location: TReferenceLocation;
  Seen: TDictionary<string, Boolean>;
  Key, Extension: string;
  Token, Previous: Integer;
  Use: TSignatureUse;
  Site: TCallSite;
  HasRequired: Boolean;
  Parameter: TSignatureParameter;
  Snapshot: TArray<TMember>;
begin
  HasRequired := False;
  for Parameter in Root.Decl.Parameters do
    if Parameter.DefaultValue = '' then
      HasRequired := True;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Snapshot := Members;
    for Member in Snapshot do
    begin
      if Member.Kind = TMemberKind.EventType then
        Continue;
      Unit_ := Source(Member.FileName);
      for Location in TLspReferences.Find(FResolver, FIndex, Unit_.Tree, Member.FileName,
        Unit_.Tokens[Member.Decl.NameToken].StartPos, True, FFiles, FReadText, FCancellation) do
      begin
        Key := UpperCase(Location.FileName) + '|' + IntToStr(Location.Range.StartPos.Line) + ':' +
          IntToStr(Location.Range.StartPos.Character);
        if Seen.ContainsKey(Key) then
          Continue;
        Seen.Add(Key, True);
        if IsHeaderName(Location.FileName, Location.Range.StartPos) then
          Continue;
        Extension := LowerCase(ExtractFileExt(Location.FileName));
        if (Extension = '.dfm') or (Extension = '.fmx') then
        begin
          CollectFormBinding(Location.FileName, Location.Range.StartPos);
          Continue;
        end;
        Other := Source(Location.FileName);
        if (Other = nil) or (Other.Tree = nil) then
          Continue;
        Token := TChangeSignature.NameTokenAt(Other.Tokens, Location.Range.StartPos);
        if Token < 0 then
          Continue;
        Use := TChangeSignature.UseOf(Other.Tokens, Token, HasRequired);
        case Use of
          TSignatureUse.Accessor:
            Accessors := Accessors + [Format('%s, Zeile %d', [ExtractFileName(Location.FileName),
              Location.Range.StartPos.Line + 1])];
          TSignatureUse.Pointer_:
            Warnings := Warnings + [Format('%s, Zeile %d: %s wird als Methodenzeiger verwendet; Aufrufe darüber ' +
              'findet Atlas nicht.', [ExtractFileName(Location.FileName), Location.Range.StartPos.Line + 1,
              ADecl.Name])];
        else
          Site.FileName := Location.FileName;
          Site.NamePos := Location.Range.StartPos;
          Previous := Token - 1;
          while (Previous >= 0) and (Other.Tokens[Previous].Kind in [TPascalTokenKind.Comment,
            TPascalTokenKind.Directive]) do
            Dec(Previous);
          Site.InheritedInMember := (Previous >= 0) and Other.Tokens[Previous].IsKeyword('inherited') and
            InMemberBody(Location.FileName, Token);
          Calls := Calls + [Site];
        end;
      end;
    end;
  finally
    Seen.Free;
  end;
  if BoundEvent <> '' then
    Warnings := Warnings + ['Die Methode ist in einer Formulardatei gebunden; Aufrufe über das Ereignis findet ' +
      'Atlas nicht.'];
end;

function TSignatureCollector.Root: TMember;
var
  Member: TMember;
begin
  for Member in Members do
    if Member.IsRoot then
      Exit(Member);
  Result := Members[0];
end;

procedure TSignatureCollector.Collect(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition);
var
  DeclFile: string;
  Decl: TIndexSymbol;
begin
  if not FindTarget(ATree, AFileName, APosition, DeclFile, Decl) then
    raise Fail('Hier steht keine Routine.');
  if not InProject(DeclFile) then
    raise Fail(Format('"%s" ist außerhalb des Projekts deklariert (%s).', [Decl.Name, ExtractFileName(DeclFile)]));
  CollectHierarchy(DeclFile, Decl);
  CollectUses(Decl);
end;

{ Bearbeitungen je Datei }

type
  TEditList = TDictionary<string, TArray<TFileEdit>>;

procedure AddEdit(AEdits: TEditList; const AFileName: string; const AEdit: TFileEdit);
var
  List: TArray<TFileEdit>;
  Existing: TFileEdit;
begin
  if not AEdits.TryGetValue(UpperCase(AFileName), List) then
    List := nil;
  for Existing in List do
    if (Existing.Range.StartPos = AEdit.Range.StartPos) and (Existing.Range.EndPos = AEdit.Range.EndPos) and
      (Existing.Kind = AEdit.Kind) and (Existing.NewText = AEdit.NewText) then
      Exit;
  AEdits.AddOrSetValue(UpperCase(AFileName), List + [AEdit]);
end;

function MakeEdit(AKind: TEditKind; const ARange: TTextRange; const ANewText: string): TFileEdit;
begin
  Result := Default(TFileEdit);
  Result.Kind := AKind;
  Result.Range := ARange;
  Result.NewText := ANewText;
end;

function ToTextEdits(const AEdits: TArray<TFileEdit>): TArray<TTextEdit>;
var
  Index: Integer;
begin
  SetLength(Result, Length(AEdits));
  for Index := 0 to High(AEdits) do
    Result[Index] := TTextEdit.Create(AEdits[Index].Range, AEdits[Index].NewText);
end;

/// <summary>Verschachtelte Aufrufe (Foo(Foo(1))): Der äußere Aufruf wird auf dem Text mit den inneren
/// Änderungen neu gebildet, die inneren entfallen.</summary>
function ResolveNesting(const AText: string; const AEdits: TArray<TFileEdit>; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): TArray<TFileEdit>;
var
  Order: TArray<Integer>;
  Done: TArray<Boolean>;
  Inner: TArray<TFileEdit>;
  Index, Other, Swap, I, J: Integer;
  Edit: TFileEdit;
  Modified: string;
  Tokens: TArray<TPascalToken>;
  Token: Integer;
  Rebuilt: TTextEdit;
  Maximal: Boolean;

  function Size(const AEdit: TFileEdit): Integer;
  begin
    Result := (AEdit.Range.EndPos.Line - AEdit.Range.StartPos.Line) * 100000 + AEdit.Range.EndPos.Character -
      AEdit.Range.StartPos.Character;
  end;

begin
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(AEdits) do
    Order[Index] := Index;
  // Kleinste zuerst, damit innere Aufrufe fertig sind, bevor der äußere sie aufnimmt.
  for I := 0 to High(Order) - 1 do
    for J := I + 1 to High(Order) do
      if Size(AEdits[Order[J]]) < Size(AEdits[Order[I]]) then
      begin
        Swap := Order[I];
        Order[I] := Order[J];
        Order[J] := Swap;
      end;
  Result := Copy(AEdits);
  SetLength(Done, Length(AEdits));
  for Index in Order do
  begin
    Edit := Result[Index];
    Inner := nil;
    for Other := 0 to High(Result) do
      if (Other <> Index) and not Done[Other] and Contains(Edit.Range, Result[Other].Range) then
      begin
        // Nur die äußersten der enthaltenen Änderungen; deren Inneres steckt schon in ihnen.
        Maximal := True;
        for J := 0 to High(Result) do
          if (J <> Other) and (J <> Index) and not Done[J] and Contains(Edit.Range, Result[J].Range) and
            Contains(Result[J].Range, Result[Other].Range) then
            Maximal := False;
        if Maximal then
          Inner := Inner + [Result[Other]];
      end;
    if Length(Inner) = 0 then
      Continue;
    for Other := 0 to High(Result) do
      if (Other <> Index) and Contains(Edit.Range, Result[Other].Range) then
        Done[Other] := True;
    if Edit.Kind = TEditKind.Call then
    begin
      Modified := TChangeSignature.ApplyEdits(AText, ToTextEdits(Inner));
      Tokens := TPascalLexer.Tokenize(Modified);
      Token := TChangeSignature.NameTokenAt(Tokens, Edit.NamePos);
      if (Token >= 0) and TChangeSignature.CallEdit(Modified, Tokens, Token, AOld, AChanges, Edit.Values, Rebuilt) then
        Result[Index].NewText := Rebuilt.NewText;
    end;
  end;
  Inner := nil;
  for Index := 0 to High(Result) do
    if not Done[Index] then
      Inner := Inner + [Result[Index]];
  Result := Inner;
end;

/// <summary>Zeilen mit /// direkt über dem Token AStart.</summary>
function DocComments(const ATokens: TArray<TPascalToken>; AStart: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  Index := AStart - 1;
  while (Index >= 0) and (ATokens[Index].Kind = TPascalTokenKind.Comment) and StartsStr('///', ATokens[Index].Text) do
  begin
    Result := [Index] + Result;
    Dec(Index);
  end;
end;

function IndentAt(const AText: string; ALine: Integer): string;
begin
  Result := TTextLines.IndentOf(AText, ALine);
end;

{ TLspChangeSignature }

class function TLspChangeSignature.ModeName(AMode: TNewParameterMode): string;
begin
  if AMode = TNewParameterMode.UpdateCallers then
    Result := 'updateCallers'
  else
    Result := 'overload';
end;

class function TLspChangeSignature.ModeOf(const AName: string; ADefault: TNewParameterMode): TNewParameterMode;
begin
  if SameText(AName, 'updateCallers') then
    Result := TNewParameterMode.UpdateCallers
  else if SameText(AName, 'overload') then
    Result := TNewParameterMode.Overload
  else
    Result := ADefault;
end;

class function TLspChangeSignature.IsOffered(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): Boolean;
var
  Token: Integer;
  Header: TSignatureHeader;
  Resolved: TResolvedSymbol;
  Text: string;
begin
  Result := False;
  if (ATree = nil) or (AResolver = nil) then
    Exit;
  Token := TChangeSignature.NameTokenAt(ATree.Tokens, APosition);
  if Token < 0 then
    Exit;
  // Kopf einer Routine: ohne Namensauflösung. Den Text braucht ReadHeader nur für die Parameter.
  Text := '';
  if TChangeSignature.ReadHeader(Text, ATree.Tokens, Token, Header) then
    Exit(True);
  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  Result := (Resolved.Kind = TResolvedKind.Symbol) and (Resolved.SymbolKind in RoutineKinds);
end;

class function TLspChangeSignature.ActionJson(const AUri: string; const APosition: TTextPosition): TJSONObject;
var
  Command: TJSONObject;
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', Title);
  Result.AddPair('kind', 'refactor.rewrite');
  Result.AddPair('command', Command);
end;

class function TLspChangeSignature.Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
begin
  Result := nil;
  if AEnabled and IsOffered(AResolver, ATree, AFileName, APosition) then
    Result := [ActionJson(AUri, APosition)];
end;

class function TLspChangeSignature.Prepare(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TChangeSignatureInfo;
var
  Collector: TSignatureCollector;
  Root: TMember;
begin
  Result := Default(TChangeSignatureInfo);
  Collector := TSignatureCollector.Create(AResolver, AIndex, AFiles, AReadText, ACancellation, AFileName);
  try
    Collector.Collect(ATree, AFileName, APosition);
    Root := Collector.Root;
    Result.Name := Root.Name;
    Result.Container := Root.Container;
    Result.Keyword := Root.Decl.Keyword;
    Result.ResultType := Root.Decl.ResultType;
    Result.Parameters := Root.Decl.Parameters;
    Result.Members := Length(Collector.Members);
    Result.InterfaceMethod := Collector.InterfaceMethod;
    Result.BoundEvent := Collector.BoundEvent;
    Result.EventFixed := Collector.EventFixed;
    Result.Warnings := Collector.Warnings;
    if Length(Collector.Accessors) > 0 then
      Result.Warnings := Result.Warnings + [Format('Zugriffsmethode einer Property (%s): Parameter lassen sich nur ' +
        'umbenennen.', [Collector.Accessors[0]])];
  finally
    Collector.Free;
  end;
end;

/// <summary>Stellen im Rumpf, an denen der Parameter AName steht.</summary>
function BodyUses(AUnit: TSourceFile; const AMember: TMember; const AName: string): TArray<Integer>;
begin
  Result := nil;
  if AMember.HasBody then
    Result := TChangeSignature.Uses_(AUnit.Tokens, AMember.Body.LastToken + 1, AMember.BodyLast, AName);
end;

class function TLspChangeSignature.Execute(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const ARequest: TChangeSignatureRequest;
  const AFiles: TArray<string>; const AReadText: TReferenceReadText; const AIsReadOnly: TChangeSignatureReadOnly;
  const ACancellation: IJsonRpcCancellationToken): TChangeSignatureOutcome;
var
  Collector: TSignatureCollector;
  Root, Member: TMember;
  Unit_: TSourceFile;
  Changes: TArray<TParameterChange>;
  Change: TParameterChange;
  RootNames, Values, NewTypes, Keys: TArray<string>;
  Error, Name, OldName, NewName, Text, LineBreak, Indent, Body, Qualified, Comment, Key: string;
  Index, Token, Line: Integer;
  Added, TypesChanged, UseOverload, Kept, HeaderInFile, Virtual_: Boolean;
  Found: TArray<Integer>;
  Edits: TEditList;
  Edit: TFileEdit;
  Rebuilt: TTextEdit;
  Site: TCallSite;
  Symbol: TIndexSymbol;
  NewParameters, OldParameters: TArray<TSignatureParameter>;
  FileEdits: TArray<TFileEdit>;
  Final: TArray<TFileEdit>;
  Tree: TSyntaxTree;
  Diagnostic: TSyntaxDiagnostic;
  Before_: Integer;
  RenameEdit: TRenameEdit;
  Removed: Boolean;
begin
  Result := Default(TChangeSignatureOutcome);
  Collector := TSignatureCollector.Create(AResolver, AIndex, AFiles, AReadText, ACancellation, AFileName);
  Edits := TEditList.Create;
  try
    Collector.Collect(ATree, AFileName, APosition);
    Root := Collector.Root;
    Changes := ARequest.Changes;
    Error := TChangeSignature.Validate(Root.Decl.Parameters, Changes);
    if Error <> '' then
      raise Fail(Error);
    SetLength(RootNames, Length(Root.Decl.Parameters));
    for Index := 0 to High(Root.Decl.Parameters) do
      RootNames[Index] := Root.Decl.Parameters[Index].Name;
    Added := False;
    TypesChanged := Length(Changes) <> Length(Root.Decl.Parameters);
    for Index := 0 to High(Changes) do
    begin
      if Changes[Index].Origin < 0 then
        Added := True;
      if Changes[Index].Origin <> Index then
        TypesChanged := True;
    end;
    if TypesChanged and Collector.EventFixed then
      raise Fail(Format('Die Methode ist in einer Formulardatei an %s gebunden; der Ereignistyp stammt nicht aus ' +
        'dem Projekt. Die Parameter lassen sich nur umbenennen.', [Collector.BoundEvent]));
    if TypesChanged and (Length(Collector.Accessors) > 0) then
      raise Fail(Format('Die Methode ist Zugriffsmethode einer Property (%s); die Parameter lassen sich nur ' +
        'umbenennen.', [Collector.Accessors[0]]));
    // Entfernte Parameter dürfen im Rumpf nicht mehr vorkommen.
    for Member in Collector.Members do
    begin
      Unit_ := Collector.Source(Member.FileName);
      for Index := 0 to High(Member.Decl.Parameters) do
      begin
        Kept := False;
        for Change in Changes do
          if Change.Origin = Index then
            Kept := True;
        if Kept then
          Continue;
        Found := BodyUses(Unit_, Member, Member.Decl.Parameters[Index].Name);
        if Length(Found) > 0 then
          raise Fail(Format('Der Parameter "%s" wird in %s, Zeile %d noch verwendet; erst die Verwendung entfernen.',
            [Member.Decl.Parameters[Index].Name, ExtractFileName(Member.FileName),
            Unit_.Tokens[Found[0]].StartPos.Line + 1]));
      end;
    end;
    UseOverload := Added and (ARequest.Mode = TNewParameterMode.Overload);
    if UseOverload and (Collector.InterfaceMethod or (Collector.BoundEvent <> '')) then
    begin
      UseOverload := False;
      Collector.Warnings := Collector.Warnings + ['Interface-Methoden und gebundene Handler: Eine Überladung erfüllt ' +
        'das Interface bzw. den Ereignistyp nicht; alle Aufrufer übergeben den neuen Wert.'];
    end;
    if UseOverload then
      Result.Mode := TNewParameterMode.Overload
    else
      Result.Mode := TNewParameterMode.UpdateCallers;
    // Kollision mit einer vorhandenen Überladung.
    NewParameters := TChangeSignature.NewParameters(Root.Decl.Parameters, Changes, RootNames, True);
    SetLength(NewTypes, Length(NewParameters));
    for Index := 0 to High(NewParameters) do
      NewTypes[Index] := NewParameters[Index].TypeName;
    Unit_ := Collector.Source(Root.FileName);
    for Symbol in Unit_.Symbols do
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, Root.Container) and
        SameText(Symbol.Name, Root.Name) and SameTypes(Symbol.ParamTypes, NewTypes) and
        not SameTypes(Symbol.ParamTypes, Root.Decl.ParamTypes) then
        raise Fail(Format('Die neue Signatur kollidiert mit einer vorhandenen Überladung von %s (Zeile %d).',
          [Root.Name, Symbol.SelectionRange.StartPos.Line + 1]));

    // Köpfe, Umbenennungen im Rumpf, Doku-Kommentare.
    for Member in Collector.Members do
    begin
      Unit_ := Collector.Source(Member.FileName);
      NewParameters := TChangeSignature.NewParameters(Member.Decl.Parameters, Changes, RootNames, True);
      Text := TChangeSignature.ParameterList(NewParameters, True);
      Edit := MakeEdit(TEditKind.Header, TChangeSignature.HeaderEdit(Unit_.Tokens, Member.Decl, Text).Range, Text);
      if Text <> TChangeSignature.ParameterList(Member.Decl.Parameters, True) then
        AddEdit(Edits, Member.FileName, Edit);
      if Member.HasBody and not Member.DeclIsBody then
      begin
        NewParameters := TChangeSignature.NewParameters(Member.Decl.Parameters, Changes, RootNames, False);
        Text := TChangeSignature.ParameterList(NewParameters, False);
        Edit := MakeEdit(TEditKind.Header, TChangeSignature.HeaderEdit(Unit_.Tokens, Member.Body, Text).Range, Text);
        if (Member.Body.OpenToken < 0) or (Text <> TChangeSignature.ParameterList(Member.Body.Parameters, False)) then
          if (Text <> '') or (Member.Body.OpenToken >= 0) then
            AddEdit(Edits, Member.FileName, Edit);
      end;
      for Change in Changes do
      begin
        if (Change.Origin < 0) or (Change.Origin > High(Member.Decl.Parameters)) then
          Continue;
        OldName := Member.Decl.Parameters[Change.Origin].Name;
        NewName := TChangeSignature.NewParameters(Member.Decl.Parameters, [Change], RootNames, False)[0].Name;
        if SameStr(OldName, NewName) then
          Continue;
        for Token in BodyUses(Unit_, Member, OldName) do
          AddEdit(Edits, Member.FileName, MakeEdit(TEditKind.Rename, TTextRange.Create(Unit_.Tokens[Token].StartPos,
            Unit_.Tokens[Token].EndPos), NewName));
        // <param name="Alt"> in den ///-Zeilen über der Deklaration.
        for Token in DocComments(Unit_.Tokens, Member.Decl.StartToken) do
        begin
          Comment := Unit_.Tokens[Token].Text;
          if ContainsText(Comment, 'name="' + OldName + '"') then
            AddEdit(Edits, Member.FileName, MakeEdit(TEditKind.Rename, TTextRange.Create(Unit_.Tokens[Token].StartPos,
              Unit_.Tokens[Token].EndPos), StringReplace(Comment, 'name="' + OldName + '"', 'name="' + NewName + '"',
              [rfIgnoreCase])));
        end;
      end;
      // Doku entfernter Parameter: einzeilige <param>-Zeilen löschen.
      for Index := 0 to High(Member.Decl.Parameters) do
      begin
        Removed := True;
        for Change in Changes do
          if Change.Origin = Index then
            Removed := False;
        if not Removed then
          Continue;
        for Token in DocComments(Unit_.Tokens, Member.Decl.StartToken) do
        begin
          Comment := Unit_.Tokens[Token].Text;
          if ContainsText(Comment, '<param name="' + Member.Decl.Parameters[Index].Name + '"') and
            ContainsText(Comment, '</param>') then
          begin
            Line := Unit_.Tokens[Token].StartPos.Line;
            AddEdit(Edits, Member.FileName, MakeEdit(TEditKind.Rename, TTextRange.Create(Line, 0, Line + 1, 0), ''));
          end;
        end;
      end;
    end;

    // Alte Signatur als Überladung, die weiterreicht.
    if UseOverload then
    begin
      Unit_ := Collector.Source(Root.FileName);
      LineBreak := TTextLines.LineBreakOf(Unit_.Text);
      OldParameters := Root.Decl.Parameters;
      Virtual_ := ARequest.VirtualOverload and (Root.Decl.HasDirective('virtual') or
        Root.Decl.HasDirective('dynamic') or Root.Decl.HasDirective('abstract'));
      Indent := IndentAt(Unit_.Text, Unit_.Tokens[Root.Decl.StartToken].StartPos.Line);
      Text := '';
      if not Root.DeclIsBody then
        Text := LineBreak + Indent + TChangeSignature.HeaderText(Root.Decl, Root.Name, OldParameters, True) +
          TChangeSignature.OverloadDirectives(Root.Decl, Virtual_);
      // Ohne weitere Direktiven fallen beide Einfügungen auf dieselbe Stelle: ein Edit, feste Reihenfolge.
      if not Root.Decl.HasDirective('overload') then
      begin
        if Root.Decl.LastToken = Root.Decl.EndToken then
        begin
          Text := ' overload;' + Text;
        end
        else
          AddEdit(Edits, Root.FileName, MakeEdit(TEditKind.Insert, TTextRange.Create(
            Unit_.Tokens[Root.Decl.EndToken].EndPos, Unit_.Tokens[Root.Decl.EndToken].EndPos), ' overload;'));
      end;
      if Text <> '' then
        AddEdit(Edits, Root.FileName, MakeEdit(TEditKind.Insert, TTextRange.Create(
          Unit_.Tokens[Root.Decl.LastToken].EndPos, Unit_.Tokens[Root.Decl.LastToken].EndPos), Text));
      if Root.HasBody then
        Qualified := Root.Body.QualifiedName
      else if Root.Container <> '' then
        Qualified := Root.Container + '.' + Root.Name
      else
        Qualified := Root.Name;
      Body := TChangeSignature.HeaderText(Root.Decl, Qualified, OldParameters, False);
      if Root.DeclIsBody then
        Body := Body + TChangeSignature.OverloadDirectives(Root.Decl, False);
      Body := Body + LineBreak + 'begin' + LineBreak + '  ' + TChangeSignature.ForwardCall(Root.Decl, OldParameters,
        Changes) + LineBreak + 'end;';
      if Root.HasBody then
        AddEdit(Edits, Root.FileName, MakeEdit(TEditKind.Insert, TTextRange.Create(
          Unit_.Tokens[Root.BodyLast].EndPos, Unit_.Tokens[Root.BodyLast].EndPos), LineBreak + LineBreak + Body))
      else if TClassCompletion.BodyEdit(Unit_.Tree, Unit_.Text, Root.Container, Body, Rebuilt) then
        AddEdit(Edits, Root.FileName, MakeEdit(TEditKind.Insert, Rebuilt.Range, Rebuilt.NewText))
      else
        raise Fail(Format('Für die Überladung von %s fehlt ein Platz im implementation-Teil.', [Root.Name]));
      // Überschreibungen bekommen overload, sonst verdecken sie die alte Überladung des Vorfahren.
      for Member in Collector.Members do
        if not Member.IsRoot and (Member.Kind = TMemberKind.Method) and not Member.Decl.HasDirective('overload') then
        begin
          Unit_ := Collector.Source(Member.FileName);
          AddEdit(Edits, Member.FileName, MakeEdit(TEditKind.Insert, TTextRange.Create(
            Unit_.Tokens[Member.Decl.EndToken].EndPos, Unit_.Tokens[Member.Decl.EndToken].EndPos), ' overload;'));
        end;
    end;

    // Aufrufer: im Modus overload nur inherited-Aufrufe in den Rümpfen (sonst riefe die Überschreibung sich
    // über die alte Überladung selbst auf).
    for Site in Collector.Calls do
    begin
      if UseOverload and not Site.InheritedInMember then
        Continue;
      Unit_ := Collector.Source(Site.FileName);
      Token := TChangeSignature.NameTokenAt(Unit_.Tokens, Site.NamePos);
      Values := nil;
      if Site.InheritedInMember then
      begin
        SetLength(Values, Length(Changes));
        for Index := 0 to High(Changes) do
          if Changes[Index].Origin < 0 then
            Values[Index] := Changes[Index].Name;
      end;
      if not TChangeSignature.CallEdit(Unit_.Text, Unit_.Tokens, Token, Root.Decl.Parameters, Changes, Values,
        Rebuilt) then
        Continue;
      Edit := MakeEdit(TEditKind.Call, Rebuilt.Range, Rebuilt.NewText);
      Edit.NamePos := Site.NamePos;
      Edit.Values := Values;
      AddEdit(Edits, Site.FileName, Edit);
    end;

    // Je Datei: Verschachtelung auflösen, Schreibschutz, Ergebnis parsen.
    Keys := Edits.Keys.ToArray;
    for Key in Keys do
    begin
      FileEdits := Edits[Key];
      if Length(FileEdits) = 0 then
        Continue;
      Name := '';
      for Member in Collector.Members do
        if SameText(UpperCase(Member.FileName), Key) then
          Name := Member.FileName;
      for Site in Collector.Calls do
        if (Name = '') and SameText(UpperCase(Site.FileName), Key) then
          Name := Site.FileName;
      Unit_ := Collector.Source(Name);
      Final := ResolveNesting(Unit_.Text, FileEdits, Root.Decl.Parameters, Changes);
      for Index := 0 to High(Final) do
        for Token := Index + 1 to High(Final) do
          if Overlaps(Final[Index].Range, Final[Token].Range) then
            raise Fail(Format('Die Änderungen in %s überschneiden sich (Zeile %d).', [ExtractFileName(Name),
              Final[Index].Range.StartPos.Line + 1]));
      HeaderInFile := False;
      for Edit in Final do
        if Edit.Kind in [TEditKind.Header, TEditKind.Insert, TEditKind.Rename] then
          HeaderInFile := True;
      if not Collector.InProject(Name) or (Assigned(AIsReadOnly) and AIsReadOnly(Name)) then
      begin
        if HeaderInFile then
          raise Fail(Format('%s ist schreibgeschützt bzw. nicht im Projekt; dort steht eine Deklaration der Methode.',
            [ExtractFileName(Name)]));
        Result.Warnings := Result.Warnings + [Format('%s ist schreibgeschützt bzw. nicht im Projekt; %d Aufrufe dort ' +
          'bleiben unverändert.', [ExtractFileName(Name), Length(Final)])];
        Continue;
      end;
      if Unit_.Tree <> nil then
      begin
        Text := TChangeSignature.ApplyEdits(Unit_.Text, ToTextEdits(Final));
        Tree := TSyntaxTreeCache.Parse(Text);
        try
          Before_ := Length(Unit_.Tree.Diagnostics);
          if Length(Tree.Diagnostics) > Before_ then
          begin
            Diagnostic := Tree.Diagnostics[0];
            raise Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
              [ExtractFileName(Name), Diagnostic.StartPos.Line + 1, Diagnostic.Message]));
          end;
        finally
          Tree.Free;
        end;
      end;
      for Edit in Final do
      begin
        RenameEdit.FileName := Name;
        RenameEdit.Range := Edit.Range;
        RenameEdit.NewText := Edit.NewText;
        Result.Edits := Result.Edits + [RenameEdit];
      end;
    end;
    Result.Warnings := Collector.Warnings + Result.Warnings;
  finally
    Edits.Free;
    Collector.Free;
  end;
end;

class function TLspChangeSignature.InfoToJson(const AInfo: TChangeSignatureInfo; AMode: TNewParameterMode;
  AVirtualOverload: Boolean): TJSONObject;
var
  Parameters, Warnings: TJSONArray;
  Parameter: TSignatureParameter;
  Item: TJSONObject;
  Warning: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AInfo.Name);
  Result.AddPair('container', AInfo.Container);
  Result.AddPair('kind', AInfo.Keyword);
  Result.AddPair('resultType', AInfo.ResultType);
  Parameters := TJSONArray.Create;
  Result.AddPair('parameters', Parameters);
  for Parameter in AInfo.Parameters do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Parameter.Name);
    Item.AddPair('type', Parameter.TypeName);
    Item.AddPair('modifier', Parameter.Modifier);
    Item.AddPair('default', Parameter.DefaultValue);
    Parameters.AddElement(Item);
  end;
  Result.AddPair('members', TJSONNumber.Create(AInfo.Members));
  Result.AddPair('interfaceMethod', TJSONBool.Create(AInfo.InterfaceMethod));
  Result.AddPair('boundEvent', AInfo.BoundEvent);
  Result.AddPair('eventFixed', TJSONBool.Create(AInfo.EventFixed));
  // Neue Parameter: Interface und gebundene Handler nur mit updateCallers.
  Result.AddPair('overloadPossible', TJSONBool.Create(not AInfo.InterfaceMethod and (AInfo.BoundEvent = '')));
  Result.AddPair('newParameter', ModeName(AMode));
  Result.AddPair('virtualOverload', TJSONBool.Create(AVirtualOverload));
  Warnings := TJSONArray.Create;
  Result.AddPair('warnings', Warnings);
  for Warning in AInfo.Warnings do
    Warnings.Add(Warning);
end;

class function TLspChangeSignature.ReadRequest(const AValue: TJSONValue; ADefaultMode: TNewParameterMode;
  ADefaultVirtual: Boolean): TChangeSignatureRequest;
var
  Item: TJSONValue;
  Items: TJSONArray;
  Change: TParameterChange;
  Text: string;
begin
  Result := Default(TChangeSignatureRequest);
  Result.Mode := ADefaultMode;
  Result.VirtualOverload := ADefaultVirtual;
  if not (AValue is TJSONObject) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Die neue Signatur fehlt.');
  if TJSONObject(AValue).TryGetValue<string>('newParameter', Text) then
    Result.Mode := ModeOf(Text, ADefaultMode);
  TJSONObject(AValue).TryGetValue<Boolean>('virtualOverload', Result.VirtualOverload);
  Items := TJSONObject(AValue).GetValue('parameters') as TJSONArray;
  if Items = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "parameters" fehlt.');
  for Item in Items do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Change := Default(TParameterChange);
    Change.Origin := TJSONObject(Item).GetValue<Integer>('origin', -1);
    Change.Name := Trim(TJSONObject(Item).GetValue<string>('name', ''));
    Change.TypeName := Trim(TJSONObject(Item).GetValue<string>('type', ''));
    Change.Modifier := Trim(TJSONObject(Item).GetValue<string>('modifier', ''));
    Change.Value := Trim(TJSONObject(Item).GetValue<string>('value', ''));
    Result.Changes := Result.Changes + [Change];
  end;
end;

class function TLspChangeSignature.OutcomeToJson(const AOutcome: TChangeSignatureOutcome): TJSONObject;
var
  Changes, Edit: TJSONObject;
  List, Warnings: TJSONArray;
  Item: TJSONObject;
  Change: TRenameEdit;
  Uri, Warning: string;
begin
  Changes := TJSONObject.Create;
  for Change in AOutcome.Edits do
  begin
    Uri := TDocumentUris.FromPath(Change.FileName);
    List := Changes.GetValue(Uri) as TJSONArray;
    if List = nil then
    begin
      List := TJSONArray.Create;
      Changes.AddPair(Uri, List);
    end;
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Change.Range));
    Item.AddPair('newText', Change.NewText);
    List.AddElement(Item);
  end;
  Edit := TJSONObject.Create;
  Edit.AddPair('changes', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Warnings := TJSONArray.Create;
  Result.AddPair('warnings', Warnings);
  for Warning in AOutcome.Warnings do
    Warnings.Add(Warning);
  Result.AddPair('newParameter', ModeName(AOutcome.Mode));
end;

end.
