unit Atlas.Common.Lsp.ChangeSignature.Collector;

// Sammelt für „Signatur ändern“ (#100) Ziel, Überschreibungen in Vor- und
// Nachfahren, Interface-Deklarationen und -Implementierungen, Ereignistypen
// gebundener Handler und alle Verwendungen über Index und Referenzsuche.
// Atlas.Common.Lsp.ChangeSignature baut daraus die Änderungen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.References;

const
  SignatureRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

type
  {$SCOPEDENUMS ON}
  TMemberKind = (Method, InterfaceMethod, Routine, EventType);
  {$SCOPEDENUMS OFF}

  /// <summary>Wo „Signatur ändern“ ansetzt und womit es sucht.</summary>
  TSignatureSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Cancellation: IJsonRpcCancellationToken;
  end;

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

  TCallSite = record
    FileName: string;
    NamePos: TTextPosition;
    /// <summary>inherited Name(...) im Rumpf einer Überschreibung: neue Parameter mit ihrem Namen.</summary>
    InheritedInMember: Boolean;
  end;

  /// <summary>Sammelt Mitglieder und Verwendungen; hält die gelesenen Dateien.</summary>
  TSignatureCollector = class
  private
    FSource: TSignatureSource;
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
    constructor Create(const ASource: TSignatureSource);
    destructor Destroy; override;
    function Source(const AFileName: string): TSourceFile;
    function InProject(const AFileName: string): Boolean;
    /// <summary>Sammelt alles zur Routine an FSource.Position; EJsonRpcError in den Abbruchfällen.</summary>
    procedure Collect;
    function Root: TMember;
  private
    function TargetPosition(out AFile: string; out APosition: TTextPosition): Boolean;
    function DeclarationAt(const AFile: string; const APosition: TTextPosition; out ADecl: TIndexSymbol): Boolean;
    function DeclaredIn(const ATypeName: string; const AName: string; const AParamTypes: TArray<string>;
      out AFile: string; out ADecl: TIndexSymbol): Boolean;
    function FirstDeclaring(const AStart: string; const ADecl: TIndexSymbol; const AParamTypes: TArray<string>;
      out AFile: string; out AFound: TIndexSymbol): Boolean;
    function NextAncestor(const ATypeName: string): string;
    function TypeSymbol(const ATypeName: string; out ALocation: TSymbolLocation): Boolean;
    function AddMember(AKind: TMemberKind; const AFileName: string; const ADecl: TIndexSymbol; AIsRoot: Boolean): Boolean;
    function ReadableSource(const AFileName: string; const ADecl: TIndexSymbol): TSourceFile;
    function OverriddenRoot(const ADecl: TIndexSymbol; var AFile: string): TIndexSymbol;
    procedure AddRoot(const AFile: string; const ARoot: TIndexSymbol);
    procedure CollectHierarchy(const AFile: string; const ADecl: TIndexSymbol);
    procedure CollectUses(const ADecl: TIndexSymbol);
    procedure AddUse(const ALocation: TReferenceLocation; AHasRequired: Boolean; const AName: string);
    procedure AddCall(AUnit: TSourceFile; AToken: Integer; const ALocation: TReferenceLocation);
    procedure CollectFormBinding(const AFormFile: string; const APosition: TTextPosition);
    function AddEventType(const AEventType: string): Boolean;
    function IsHeaderName(const AFileName: string; const APosition: TTextPosition): Boolean;
    function InMemberBody(const AFileName: string; ATokenIndex: Integer): Boolean;
    function EventTypeOf(const AClassName, AProperty: string): string;
    function SymbolsOf(const AOwner: TSymbolLocation): TArray<TIndexSymbol>;
  end;

/// <summary>Gleiche Parametertypen ohne Rücksicht auf Leerzeichen und Groß-/Kleinschreibung.</summary>
function SameParamTypes(const A, B: TArray<string>): Boolean;
/// <summary>Fehler für den Abbruch mit Meldung an den Benutzer.</summary>
function SignatureError(const AMessage: string): EJsonRpcError;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.Contract;

const
  ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  MaxDepth = 32;
  MaxMembers = 500;

type
  /// <summary>Geht von der Wurzel aus über Nachfahren, implementierende Klassen und implementierte Interfaces.</summary>
  THierarchyWalk = class
  private
    FOwner: TSignatureCollector;
    FRoot: TIndexSymbol;
    FTypes: TArray<string>;
    FPending: TQueue<TPair<string, Integer>>;
    FVisited: TDictionary<string, Boolean>;
    function Visit(const AType: string): Boolean;
    procedure Enqueue(const AType: string; ADepth: Integer);
    procedure AddDeclared(const AType: string; AIsInterface: Boolean);
    procedure EnqueueInterfaces(const AOwner: TIndexSymbol; ADepth: Integer);
    procedure VisitDescendants(const AOwner: TIndexSymbol; AIsInterface: Boolean; ADepth: Integer);
    procedure AddInheritedImplementation(const AClass: TIndexSymbol; ADepth: Integer);
    procedure Step(const ACurrent: TPair<string, Integer>);
  public
    constructor Create(AOwner: TSignatureCollector; const ARoot: TIndexSymbol);
    destructor Destroy; override;
    procedure Run;
  end;

function SameParamTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if not SameText(StringReplace(A[mIndex], ' ', '', [rfReplaceAll]), StringReplace(B[mIndex], ' ', '',
        [rfReplaceAll])) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function SignatureError(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

function TypeKey(const AName: string): string;
begin
  Result := UpperCase(AName);
end;

function IsPascalSource(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.inc']);
end;

/// <summary>Hat die Routine einen Parameter ohne Standardwert?</summary>
function HasRequiredParameter(const AHeader: TSignatureHeader): Boolean;
var
  mParameter: TSignatureParameter;
begin
  for mParameter in AHeader.Parameters do
  begin
    if mParameter.DefaultValue = '' then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gehört der Kopf AHeader als Rumpf zur Deklaration ADecl (gleiche Parameter bzw. Rumpf ohne Liste)?</summary>
function IsBodyOf(const AHeader, ADecl: TSignatureHeader): Boolean;
begin
  Result := SameParamTypes(AHeader.ParamTypes, ADecl.ParamTypes) or
    ((AHeader.OpenToken < 0) and (Length(ADecl.Parameters) > 0));
end;

/// <summary>Sucht in AUnit den Rumpf zur Deklaration in AMember (nicht für Interface-Methoden).</summary>
procedure FindBody(AUnit: TSourceFile; const ADecl: TIndexSymbol; var AMember: TMember);
var
  mSymbol: TIndexSymbol;
  mHeader: TSignatureHeader;
  mLast: Integer;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if not ((mSymbol.Kind in SignatureRoutineKinds) and SameText(mSymbol.Container, ADecl.Container) and
      SameText(mSymbol.Name, ADecl.Name) and (mSymbol.SelectionRange.StartPos <> ADecl.SelectionRange.StartPos)) then
    begin
      Continue;
    end;
    if not TChangeSignature.ReadHeader(AUnit.Text, AUnit.Tokens, TChangeSignature.NameTokenAt(AUnit.Tokens,
      mSymbol.SelectionRange.StartPos), mHeader) or not IsBodyOf(mHeader, AMember.Decl) then
    begin
      Continue;
    end;
    mLast := TChangeSignature.BodyEnd(AUnit.Tree, mHeader);
    if mLast >= 0 then
    begin
      AMember.HasBody := True;
      AMember.Body := mHeader;
      AMember.BodyLast := mLast;
      Exit;
    end;
  end;
end;

/// <summary>Liest Kopf und Rumpf des Mitglieds ADecl aus AUnit; EJsonRpcError, wenn der Kopf nicht lesbar ist.</summary>
function ReadMember(AUnit: TSourceFile; AKind: TMemberKind; const ADecl: TIndexSymbol; AIsRoot: Boolean): TMember;
var
  mLast: Integer;
begin
  Result := Default(TMember);
  Result.Kind := AKind;
  Result.FileName := AUnit.FileName;
  Result.Container := ADecl.Container;
  Result.Name := ADecl.Name;
  Result.IsRoot := AIsRoot;
  Result.BodyLast := -1;
  if not TChangeSignature.ReadHeader(AUnit.Text, AUnit.Tokens, TChangeSignature.NameTokenAt(AUnit.Tokens,
    ADecl.SelectionRange.StartPos), Result.Decl) then
  begin
    raise SignatureError(Format('Der Kopf von %s lässt sich nicht lesen.', [ADecl.QualifiedName]));
  end;
  // Routine nur im implementation-Teil: der Kopf des Rumpfs ist die Deklaration.
  mLast := TChangeSignature.BodyEnd(AUnit.Tree, Result.Decl);
  if mLast >= 0 then
  begin
    Result.DeclIsBody := True;
    Result.HasBody := True;
    Result.Body := Result.Decl;
    Result.BodyLast := mLast;
  end
  else if AKind <> TMemberKind.InterfaceMethod then
  begin
    FindBody(AUnit, ADecl, Result);
  end;
end;

/// <summary>Sucht in der Formulardatei die Ereigniszuweisung an APosition samt Komponentenklasse.</summary>
function FindEvent(AObject: TDfmObject; const APosition: TTextPosition; var AClassName, AProperty: string): Boolean;
var
  mItem: TDfmProperty;
  mChild: TDfmObject;
begin
  for mItem in AObject.Properties do
  begin
    if mItem.IsEvent and (mItem.ValueRange.StartPos = APosition) then
    begin
      AClassName := AObject.TypeName;
      AProperty := mItem.Name;
      Exit(True);
    end;
  end;
  for mChild in AObject.Children do
  begin
    if FindEvent(mChild, APosition, AClassName, AProperty) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Liest den Prozedurtyp AEventType aus AUnit als Mitglied.</summary>
function ReadEventType(AUnit: TSourceFile; const AEventType: string; out AMember: TMember): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if not ((mSymbol.Kind = TIndexSymbolKind.TypeAlias) and SameText(mSymbol.Name, AEventType)) then
    begin
      Continue;
    end;
    AMember := Default(TMember);
    AMember.Kind := TMemberKind.EventType;
    AMember.FileName := AUnit.FileName;
    AMember.Name := AEventType;
    AMember.BodyLast := -1;
    if TChangeSignature.ReadProcedureType(AUnit.Text, AUnit.Tokens, TChangeSignature.NameTokenAt(AUnit.Tokens,
      mSymbol.SelectionRange.StartPos), AMember.Decl) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typ der Property AProperty einer Klasse AContainer in ASymbols; '' ohne.</summary>
function PropertyType(const ASymbols: TArray<TIndexSymbol>; const AContainer, AProperty: string): string;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASymbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mSymbol.Container, AContainer) and
      SameText(mSymbol.Name, AProperty) and (mSymbol.TypeName <> '') then
    begin
      Exit(mSymbol.TypeName);
    end;
  end;
  Result := '';
end;

/// <summary>Steht vor dem Token AToken (ohne Kommentare und Direktiven) inherited?</summary>
function AfterInherited(const ATokens: TArray<TPascalToken>; AToken: Integer): Boolean;
var
  mPrevious: Integer;
begin
  mPrevious := AToken - 1;
  while (mPrevious >= 0) and (ATokens[mPrevious].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mPrevious);
  end;
  Result := (mPrevious >= 0) and ATokens[mPrevious].IsKeyword('inherited');
end;

function UseKey(const ALocation: TReferenceLocation): string;
begin
  Result := UpperCase(ALocation.FileName) + '|' + IntToStr(ALocation.Range.StartPos.Line) + ':' +
    IntToStr(ALocation.Range.StartPos.Character);
end;

function PlaceOf(const ALocation: TReferenceLocation): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(ALocation.FileName), ALocation.Range.StartPos.Line + 1]);
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

{ THierarchyWalk }

constructor THierarchyWalk.Create(AOwner: TSignatureCollector; const ARoot: TIndexSymbol);
begin
  inherited Create;
  FOwner := AOwner;
  FRoot := ARoot;
  FTypes := ARoot.ParamTypes;
  FPending := TQueue<TPair<string, Integer>>.Create;
  FVisited := TDictionary<string, Boolean>.Create;
end;

destructor THierarchyWalk.Destroy;
begin
  FVisited.Free;
  FPending.Free;
  inherited;
end;

function THierarchyWalk.Visit(const AType: string): Boolean;
begin
  Result := not FVisited.ContainsKey(TypeKey(AType));
  if Result then
  begin
    FVisited.Add(TypeKey(AType), True);
  end;
end;

procedure THierarchyWalk.Enqueue(const AType: string; ADepth: Integer);
begin
  FPending.Enqueue(TPair<string, Integer>.Create(AType, ADepth));
end;

procedure THierarchyWalk.AddDeclared(const AType: string; AIsInterface: Boolean);
var
  mFile: string;
  mFound: TIndexSymbol;
begin
  if not FOwner.DeclaredIn(AType, FRoot.Name, FTypes, mFile, mFound) or
    SameText(mFound.QualifiedName, FRoot.QualifiedName) then
  begin
    Exit;
  end;
  if AIsInterface then
  begin
    FOwner.InterfaceMethod := True;
    FOwner.AddMember(TMemberKind.InterfaceMethod, mFile, mFound, False);
  end
  else if mFound.HasDirective('override') or FOwner.InterfaceMethod then
  begin
    FOwner.AddMember(TMemberKind.Method, mFile, mFound, False);
  end;
end;

procedure THierarchyWalk.EnqueueInterfaces(const AOwner: TIndexSymbol; ADepth: Integer);
var
  mIndex: Integer;
  mAncestor, mFile: string;
  mLocation: TSymbolLocation;
  mFound: TIndexSymbol;
begin
  for mIndex := 1 to High(AOwner.Ancestors) do
  begin
    mAncestor := AOwner.Ancestors[mIndex];
    if not FVisited.ContainsKey(TypeKey(mAncestor)) and FOwner.TypeSymbol(mAncestor, mLocation) and
      (mLocation.Symbol.Kind = TIndexSymbolKind.InterfaceType) and
      FOwner.DeclaredIn(mAncestor, FRoot.Name, FTypes, mFile, mFound) then
    begin
      Visit(mAncestor);
      Enqueue(mLocation.Symbol.QualifiedName, ADepth + 1);
    end;
  end;
end;

procedure THierarchyWalk.AddInheritedImplementation(const AClass: TIndexSymbol; ADepth: Integer);
var
  mFile: string;
  mFound: TIndexSymbol;
begin
  if (Length(AClass.Ancestors) = 0) or
    not FOwner.FirstDeclaring(AClass.Ancestors[0], FRoot, FTypes, mFile, mFound) then
  begin
    Exit;
  end;
  if Visit(mFound.Container) then
  begin
    FOwner.AddMember(TMemberKind.Method, mFile, mFound, False);
    Enqueue(mFound.Container, ADepth + 1);
  end;
end;

procedure THierarchyWalk.VisitDescendants(const AOwner: TIndexSymbol; AIsInterface: Boolean; ADepth: Integer);
var
  mLocation: TSymbolLocation;
  mFile: string;
  mFound: TIndexSymbol;
begin
  for mLocation in FOwner.FSource.Index.Descendants(AOwner.Name) do
  begin
    if not (mLocation.Symbol.Kind in ClassKinds + [TIndexSymbolKind.InterfaceType]) or
      not Visit(mLocation.Symbol.QualifiedName) then
    begin
      Continue;
    end;
    // Eine Klasse, die das Interface über eine geerbte Methode erfüllt: deren Klasse gehört dazu.
    if AIsInterface and (mLocation.Symbol.Kind <> TIndexSymbolKind.InterfaceType) and
      not FOwner.DeclaredIn(mLocation.Symbol.QualifiedName, FRoot.Name, FTypes, mFile, mFound) then
    begin
      AddInheritedImplementation(mLocation.Symbol, ADepth);
    end;
    Enqueue(mLocation.Symbol.QualifiedName, ADepth + 1);
  end;
end;

procedure THierarchyWalk.Step(const ACurrent: TPair<string, Integer>);
var
  mOwner: TSymbolLocation;
  mIsInterface: Boolean;
begin
  if (ACurrent.Value >= MaxDepth) or not FOwner.TypeSymbol(ACurrent.Key, mOwner) then
  begin
    Exit;
  end;
  mIsInterface := mOwner.Symbol.Kind = TIndexSymbolKind.InterfaceType;
  AddDeclared(ACurrent.Key, mIsInterface);
  // Interfaces in der Vorfahrenliste einer Klasse.
  if not mIsInterface then
  begin
    EnqueueInterfaces(mOwner.Symbol, ACurrent.Value);
  end;
  VisitDescendants(mOwner.Symbol, mIsInterface, ACurrent.Value);
end;

procedure THierarchyWalk.Run;
begin
  Enqueue(FRoot.Container, 0);
  Visit(FRoot.Container);
  while FPending.Count > 0 do
  begin
    if Assigned(FOwner.FSource.Cancellation) then
    begin
      FOwner.FSource.Cancellation.ThrowIfCancellationRequested;
    end;
    Step(FPending.Dequeue);
  end;
end;

{ TSignatureCollector }

constructor TSignatureCollector.Create(const ASource: TSignatureSource);
begin
  inherited Create;
  FSource := ASource;
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
  Result := SameText(AFileName, FSource.FileName) or (IndexText(AFileName, FSource.Files) >= 0);
end;

function TSignatureCollector.Source(const AFileName: string): TSourceFile;
var
  mText: string;
begin
  if FSources.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if not (Assigned(FSource.ReadText) and FSource.ReadText(AFileName, mText)) then
  begin
    Exit;
  end;
  Result := TSourceFile.Create;
  Result.FileName := AFileName;
  Result.Text := mText;
  if IsPascalSource(AFileName) then
  begin
    Result.Tree := TSyntaxTreeCache.Parse(mText);
    Result.Symbols := TIndexExtractor.Extract(Result.Tree, AFileName).Symbols;
  end;
  FSources.Add(UpperCase(AFileName), Result);
end;

function TSignatureCollector.TargetPosition(out AFile: string; out APosition: TTextPosition): Boolean;
var
  mResolved: TResolvedSymbol;
  mCurrent: TSourceFile;
  mSymbol: TIndexSymbol;
begin
  AFile := '';
  APosition := Default(TTextPosition);
  mResolved := FSource.Resolver.Resolve(FSource.Tree, FSource.FileName, FSource.Position);
  if (mResolved.Kind = TResolvedKind.Symbol) and (mResolved.SymbolKind in SignatureRoutineKinds) then
  begin
    AFile := mResolved.FileName;
    APosition := mResolved.SelectionRange.StartPos;
    Exit(True);
  end;
  // Auf dem Namen einer Deklaration bzw. eines Rumpfs.
  Result := False;
  mCurrent := Source(FSource.FileName);
  if mCurrent = nil then
  begin
    Exit;
  end;
  for mSymbol in mCurrent.Symbols do
  begin
    if (mSymbol.Kind in SignatureRoutineKinds) and Within(FSource.Position, mSymbol.SelectionRange) then
    begin
      AFile := FSource.FileName;
      APosition := mSymbol.SelectionRange.StartPos;
      Exit(True);
    end;
  end;
end;

function TSignatureCollector.DeclarationAt(const AFile: string; const APosition: TTextPosition;
  out ADecl: TIndexSymbol): Boolean;
var
  mCurrent: TSourceFile;
  mSymbol, mCandidate: TIndexSymbol;
begin
  Result := False;
  mCurrent := Source(AFile);
  if mCurrent = nil then
  begin
    Exit;
  end;
  for mSymbol in mCurrent.Symbols do
  begin
    if (mSymbol.Kind in SignatureRoutineKinds) and (mSymbol.SelectionRange.StartPos = APosition) then
    begin
      // Vom Rumpf zur Deklaration: die erste Fundstelle mit denselben Parametern.
      ADecl := mSymbol;
      for mCandidate in mCurrent.Symbols do
      begin
        if (mCandidate.Kind in SignatureRoutineKinds) and SameText(mCandidate.Container, mSymbol.Container) and
          SameText(mCandidate.Name, mSymbol.Name) and (SameParamTypes(mCandidate.ParamTypes, mSymbol.ParamTypes) or
          (Length(mSymbol.ParamTypes) = 0)) then
        begin
          ADecl := mCandidate;
          Break;
        end;
      end;
      Exit(True);
    end;
  end;
end;

function TSignatureCollector.TypeSymbol(const ATypeName: string; out ALocation: TSymbolLocation): Boolean;
var
  mLocation: TSymbolLocation;
  mName: string;
begin
  mName := ATypeName;
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  for mLocation in FSource.Index.FindSymbols(mName) do
  begin
    if (mLocation.Symbol.Kind in ClassKinds + [TIndexSymbolKind.InterfaceType]) and
      (SameText(mLocation.Symbol.QualifiedName, ATypeName) or SameText(mLocation.Symbol.Name, ATypeName)) then
    begin
      ALocation := mLocation;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureCollector.NextAncestor(const ATypeName: string): string;
var
  mOwner: TSymbolLocation;
begin
  Result := '';
  if TypeSymbol(ATypeName, mOwner) and (Length(mOwner.Symbol.Ancestors) > 0) then
  begin
    Result := mOwner.Symbol.Ancestors[0];
  end;
end;

function TSignatureCollector.DeclaredIn(const ATypeName: string; const AName: string;
  const AParamTypes: TArray<string>; out AFile: string; out ADecl: TIndexSymbol): Boolean;
var
  mLocation: TSymbolLocation;
  mUnit: TSourceFile;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if not TypeSymbol(ATypeName, mLocation) then
  begin
    Exit;
  end;
  AFile := mLocation.FileName;
  mUnit := Source(AFile);
  if (mUnit = nil) or (mUnit.Tree = nil) then
  begin
    Exit;
  end;
  for mSymbol in mUnit.Symbols do
  begin
    if (mSymbol.Kind in SignatureRoutineKinds) and SameText(mSymbol.Container, mLocation.Symbol.QualifiedName) and
      SameText(mSymbol.Name, AName) and SameParamTypes(mSymbol.ParamTypes, AParamTypes) then
    begin
      ADecl := mSymbol;
      Exit(True);
    end;
  end;
end;

function TSignatureCollector.FirstDeclaring(const AStart: string; const ADecl: TIndexSymbol;
  const AParamTypes: TArray<string>; out AFile: string; out AFound: TIndexSymbol): Boolean;
var
  mClimb: string;
  mDepth: Integer;
begin
  AFile := '';
  AFound := Default(TIndexSymbol);
  mClimb := AStart;
  mDepth := 0;
  while (mClimb <> '') and (mDepth < MaxDepth) do
  begin
    if DeclaredIn(mClimb, ADecl.Name, AParamTypes, AFile, AFound) then
    begin
      Exit(True);
    end;
    Inc(mDepth);
    mClimb := NextAncestor(mClimb);
  end;
  Result := False;
end;

function TSignatureCollector.ReadableSource(const AFileName: string; const ADecl: TIndexSymbol): TSourceFile;
begin
  if not InProject(AFileName) then
  begin
    raise SignatureError(Format('%s steht außerhalb des Projekts (%s); dort lässt sich die Signatur nicht ändern.',
      [ADecl.QualifiedName, ExtractFileName(AFileName)]));
  end;
  Result := Source(AFileName);
  if (Result = nil) or (Result.Tree = nil) then
  begin
    raise SignatureError(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  end;
end;

function TSignatureCollector.AddMember(AKind: TMemberKind; const AFileName: string; const ADecl: TIndexSymbol;
  AIsRoot: Boolean): Boolean;
var
  mKey: string;
begin
  mKey := UpperCase(AFileName + '|' + ADecl.Container + '|' + ADecl.Name + '|' +
    IntToStr(ADecl.SelectionRange.StartPos.Line));
  if FSeen.ContainsKey(mKey) then
  begin
    Exit(True);
  end;
  FSeen.Add(mKey, True);
  Result := Length(Members) < MaxMembers;
  if Result then
  begin
    Members := Members + [ReadMember(ReadableSource(AFileName, ADecl), AKind, ADecl, AIsRoot)];
  end;
end;

function TSignatureCollector.OverriddenRoot(const ADecl: TIndexSymbol; var AFile: string): TIndexSymbol;
var
  mOwner: TSymbolLocation;
  mFound: TIndexSymbol;
  mFile: string;
begin
  // Zur Methode, die die Kette beginnt: über override nach oben.
  Result := ADecl;
  while Result.HasDirective('override') do
  begin
    if not TypeSymbol(Result.Container, mOwner) or (Length(mOwner.Symbol.Ancestors) = 0) then
    begin
      raise SignatureError(Format('%s überschreibt eine Methode, deren Vorfahr nicht im Index steht.',
        [Result.QualifiedName]));
    end;
    if not FirstDeclaring(mOwner.Symbol.Ancestors[0], Result, ADecl.ParamTypes, mFile, mFound) then
    begin
      raise SignatureError(Format('Die überschriebene Methode von %s steht nicht im Index.', [Result.QualifiedName]));
    end;
    if not InProject(mFile) then
    begin
      raise SignatureError(Format('%s überschreibt %s außerhalb des Projekts (%s); dort lässt sich die Signatur ' +
        'nicht ändern.', [Result.QualifiedName, mFound.QualifiedName, ExtractFileName(mFile)]));
    end;
    Result := mFound;
    AFile := mFile;
  end;
end;

procedure TSignatureCollector.AddRoot(const AFile: string; const ARoot: TIndexSymbol);
var
  mOwner: TSymbolLocation;
begin
  if ARoot.Container = '' then
  begin
    AddMember(TMemberKind.Routine, AFile, ARoot, True);
  end
  else if TypeSymbol(ARoot.Container, mOwner) and (mOwner.Symbol.Kind = TIndexSymbolKind.InterfaceType) then
  begin
    InterfaceMethod := True;
    AddMember(TMemberKind.InterfaceMethod, AFile, ARoot, True);
  end
  else
  begin
    AddMember(TMemberKind.Method, AFile, ARoot, True);
  end;
end;

procedure TSignatureCollector.CollectHierarchy(const AFile: string; const ADecl: TIndexSymbol);
var
  mRoot: TIndexSymbol;
  mFile: string;
  mWalk: THierarchyWalk;
begin
  mFile := AFile;
  mRoot := OverriddenRoot(ADecl, mFile);
  AddRoot(mFile, mRoot);
  if mRoot.Container = '' then
  begin
    Exit;
  end;
  // Nachfahren, implementierende Klassen und implementierte Interfaces.
  mWalk := THierarchyWalk.Create(Self, mRoot);
  try
    mWalk.Run;
  finally
    mWalk.Free;
  end;
end;

function TSignatureCollector.IsHeaderName(const AFileName: string; const APosition: TTextPosition): Boolean;
var
  mMember: TMember;
  mUnit: TSourceFile;
begin
  for mMember in Members do
  begin
    if not SameText(mMember.FileName, AFileName) then
    begin
      Continue;
    end;
    mUnit := Source(mMember.FileName);
    if (mUnit.Tokens[mMember.Decl.NameToken].StartPos = APosition) or
      (mMember.HasBody and (mUnit.Tokens[mMember.Body.NameToken].StartPos = APosition)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureCollector.InMemberBody(const AFileName: string; ATokenIndex: Integer): Boolean;
var
  mMember: TMember;
begin
  for mMember in Members do
  begin
    if SameText(mMember.FileName, AFileName) and mMember.HasBody and (ATokenIndex > mMember.Body.LastToken) and
      (ATokenIndex <= mMember.BodyLast) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureCollector.SymbolsOf(const AOwner: TSymbolLocation): TArray<TIndexSymbol>;
var
  mUnit: TSourceFile;
  mUnitIndex: TUnitIndex;
begin
  Result := nil;
  mUnit := Source(AOwner.FileName);
  if (mUnit <> nil) and (mUnit.Tree <> nil) then
  begin
    Result := mUnit.Symbols;
  end
  else if FSource.Index.FindFile(AOwner.FileName, mUnitIndex) then
  begin
    Result := mUnitIndex.Symbols;
  end;
end;

function TSignatureCollector.EventTypeOf(const AClassName, AProperty: string): string;
var
  mClimb: string;
  mOwner: TSymbolLocation;
  mDepth: Integer;
begin
  Result := '';
  mClimb := AClassName;
  mDepth := 0;
  while (mClimb <> '') and (mDepth < MaxDepth) and TypeSymbol(mClimb, mOwner) do
  begin
    Inc(mDepth);
    Result := PropertyType(SymbolsOf(mOwner), mOwner.Symbol.QualifiedName, AProperty);
    if Result <> '' then
    begin
      Exit;
    end;
    mClimb := '';
    if Length(mOwner.Symbol.Ancestors) > 0 then
    begin
      mClimb := mOwner.Symbol.Ancestors[0];
    end;
  end;
end;

function TSignatureCollector.AddEventType(const AEventType: string): Boolean;
var
  mLocation: TSymbolLocation;
  mUnit: TSourceFile;
  mMember: TMember;
begin
  for mLocation in FSource.Index.FindSymbols(AEventType) do
  begin
    if (mLocation.Symbol.Kind <> TIndexSymbolKind.TypeAlias) or not InProject(mLocation.FileName) then
    begin
      Continue;
    end;
    mUnit := Source(mLocation.FileName);
    if (mUnit = nil) or (mUnit.Tree = nil) or not ReadEventType(mUnit, AEventType, mMember) then
    begin
      Continue;
    end;
    if not FSeen.ContainsKey('EVENT|' + UpperCase(AEventType)) then
    begin
      FSeen.Add('EVENT|' + UpperCase(AEventType), True);
      Members := Members + [mMember];
      Warnings := Warnings + [Format('Der Ereignistyp %s ändert sich mit; weitere Handler dieses Typs und ' +
        'Aufrufe über das Ereignis passt Atlas nicht an.', [AEventType])];
    end;
    Exit(True);
  end;
  Result := False;
end;

procedure TSignatureCollector.CollectFormBinding(const AFormFile: string; const APosition: TTextPosition);
var
  mForm: TSourceFile;
  mDocument: TDfmDocument;
  mComponentClass, mPropertyName, mEventType: string;
  mFound: Boolean;
begin
  mForm := Source(AFormFile);
  if mForm = nil then
  begin
    Exit;
  end;
  mDocument := TDfmParser.Parse(mForm.Text);
  try
    mFound := (mDocument.Root <> nil) and FindEvent(mDocument.Root, APosition, mComponentClass, mPropertyName);
  finally
    mDocument.Free;
  end;
  if not mFound then
  begin
    Exit;
  end;
  mEventType := EventTypeOf(mComponentClass, mPropertyName);
  if mEventType = '' then
  begin
    BoundEvent := mPropertyName;
    EventFixed := True;
  end
  else
  begin
    BoundEvent := mEventType;
    // Ereignistyp im Projekt: seine Parameterliste ändert sich mit.
    if not AddEventType(mEventType) then
    begin
      EventFixed := True;
    end;
  end;
end;

procedure TSignatureCollector.AddCall(AUnit: TSourceFile; AToken: Integer; const ALocation: TReferenceLocation);
var
  mSite: TCallSite;
begin
  mSite.FileName := ALocation.FileName;
  mSite.NamePos := ALocation.Range.StartPos;
  mSite.InheritedInMember := AfterInherited(AUnit.Tokens, AToken) and InMemberBody(ALocation.FileName, AToken);
  Calls := Calls + [mSite];
end;

procedure TSignatureCollector.AddUse(const ALocation: TReferenceLocation; AHasRequired: Boolean; const AName: string);
var
  mOther: TSourceFile;
  mToken: Integer;
begin
  if MatchText(ExtractFileExt(ALocation.FileName), ['.dfm', '.fmx']) then
  begin
    CollectFormBinding(ALocation.FileName, ALocation.Range.StartPos);
    Exit;
  end;
  mOther := Source(ALocation.FileName);
  mToken := -1;
  if (mOther <> nil) and (mOther.Tree <> nil) then
  begin
    mToken := TChangeSignature.NameTokenAt(mOther.Tokens, ALocation.Range.StartPos);
  end;
  if mToken < 0 then
  begin
    Exit;
  end;
  case TChangeSignature.UseOf(mOther.Tokens, mToken, AHasRequired) of
    TSignatureUse.Accessor:
      Accessors := Accessors + [PlaceOf(ALocation)];
    TSignatureUse.Pointer_:
      Warnings := Warnings + [Format('%s: %s wird als Methodenzeiger verwendet; Aufrufe darüber findet Atlas nicht.',
        [PlaceOf(ALocation), AName])];
  else
    AddCall(mOther, mToken, ALocation);
  end;
end;

procedure TSignatureCollector.CollectUses(const ADecl: TIndexSymbol);
var
  mMember: TMember;
  mUnit: TSourceFile;
  mLocation: TReferenceLocation;
  mSeen: TDictionary<string, Boolean>;
  mHasRequired: Boolean;
  mSnapshot: TArray<TMember>;
begin
  mHasRequired := HasRequiredParameter(Root.Decl);
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mSnapshot := Members;
    for mMember in mSnapshot do
    begin
      if mMember.Kind = TMemberKind.EventType then
      begin
        Continue;
      end;
      mUnit := Source(mMember.FileName);
      for mLocation in TLspReferences.Find(FSource.Resolver, FSource.Index, mUnit.Tree, mMember.FileName,
        mUnit.Tokens[mMember.Decl.NameToken].StartPos, True, FSource.Files, FSource.ReadText, FSource.Cancellation) do
      begin
        if not mSeen.ContainsKey(UseKey(mLocation)) and not IsHeaderName(mLocation.FileName,
          mLocation.Range.StartPos) then
        begin
          mSeen.Add(UseKey(mLocation), True);
          AddUse(mLocation, mHasRequired, ADecl.Name);
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
  if BoundEvent <> '' then
  begin
    Warnings := Warnings + ['Die Methode ist in einer Formulardatei gebunden; Aufrufe über das Ereignis findet ' +
      'Atlas nicht.'];
  end;
end;

function TSignatureCollector.Root: TMember;
var
  mMember: TMember;
begin
  for mMember in Members do
  begin
    if mMember.IsRoot then
    begin
      Exit(mMember);
    end;
  end;
  Result := Members[0];
end;

procedure TSignatureCollector.Collect;
var
  mDeclFile: string;
  mPosition: TTextPosition;
  mDecl: TIndexSymbol;
begin
  if not (TargetPosition(mDeclFile, mPosition) and DeclarationAt(mDeclFile, mPosition, mDecl)) then
  begin
    raise SignatureError('Hier steht keine Routine.');
  end;
  if not InProject(mDeclFile) then
  begin
    raise SignatureError(Format('"%s" ist außerhalb des Projekts deklariert (%s).', [mDecl.Name,
      ExtractFileName(mDeclFile)]));
  end;
  CollectHierarchy(mDeclFile, mDecl);
  CollectUses(mDecl);
end;

end.
