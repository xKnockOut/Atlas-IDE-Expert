unit Atlas.Common.Pascal.SyntaxTree;

// Syntaxbaum des Parsers. Jeder Knoten kennt Art, Namen (bei Deklarationen,
// Bezeichnern und Literalen), Bereich im Quelltext und seine Kinder.
// Der Baum ist auch für fehlerhaften Code vollständig; übersprungene Token
// stehen in Knoten der Art Error, Fehler in Diagnostics.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TSyntaxKind = (
    // Datei und Abschnitte
    UnitFile, ProgramFile, LibraryFile, PackageFile,
    InterfaceSection, ImplementationSection, InitializationSection, FinalizationSection,
    UsesClause, UsedUnit,
    // Deklarationsabschnitte
    TypeSection, TypeDecl, ConstSection, ConstDecl, VarSection, VarDecl, LabelSection, ExportsClause,
    GenericParams, Attribute,
    // Typen
    ClassType, ObjectType, RecordType, InterfaceType, HelperType, ClassOfType, ForwardType,
    EnumType, SetType, ArrayType, PointerType, ProcedureType, FileType, SubrangeType, TypeReference,
    VariantPart,
    // Mitglieder
    Visibility, Field, PropertyDecl, RoutineHeader,
    // Routinen
    RoutineDecl, Parameters, Parameter, Directive,
    // Anweisungen
    Block, AsmBlock, AssignStatement, CallStatement, IfStatement, CaseStatement, CaseItem, CaseElse,
    ForStatement, ForInStatement, WhileStatement, RepeatStatement, WithStatement,
    TryStatement, ExceptBlock, ExceptionHandler, FinallyBlock, RaiseStatement, GotoStatement,
    LabeledStatement, InlineVar, InlineConst, EmptyStatement,
    // Ausdrücke
    Identifier, Literal, MemberAccess, Call, IndexAccess, Dereference, AddressOf, GenericArgs,
    SetConstructor, BinaryExpr, UnaryExpr, ParenExpr, InheritedExpr, AnonymousMethod, RangeExpr,
    /// <summary>Bedingter Ausdruck if A then B else C (ab Delphi 13).</summary>
    IfExpr,
    // Fehlerbehandlung
    Error);

  TSyntaxNode = class
  private
    FKind: TSyntaxKind;
    FName: string;
    FParent: TSyntaxNode;
    FChildren: TObjectList<TSyntaxNode>;
    FStartPos: TTextPosition;
    FEndPos: TTextPosition;
    FStartOffset: Integer;
    FEndOffset: Integer;
    function GetChild(AIndex: Integer): TSyntaxNode;
    function GetChildCount: Integer;
  public
    constructor Create(AKind: TSyntaxKind);
    destructor Destroy; override;
    /// <summary>Hängt ANode als letztes Kind an und übernimmt es.</summary>
    procedure Add(ANode: TSyntaxNode);
    /// <summary>Nimmt ANode aus den Kindern, ohne es freizugeben.</summary>
    procedure Extract(ANode: TSyntaxNode);
    /// <summary>Erstes Kind der Art, sonst nil.</summary>
    function FindChild(AKind: TSyntaxKind): TSyntaxNode;
    /// <summary>Setzt den Bereich im Quelltext.</summary>
    procedure SetRange(const AStartPos, AEndPos: TTextPosition; AStartOffset, AEndOffset: Integer);
    property Kind: TSyntaxKind read FKind write FKind;
    /// <summary>Name bei Deklarationen, Text bei Bezeichnern, Literalen und Operatoren.</summary>
    property Name: string read FName write FName;
    property Parent: TSyntaxNode read FParent;
    property ChildCount: Integer read GetChildCount;
    property Children[AIndex: Integer]: TSyntaxNode read GetChild; default;
    property StartPos: TTextPosition read FStartPos;
    property EndPos: TTextPosition read FEndPos;
    property StartOffset: Integer read FStartOffset;
    property EndOffset: Integer read FEndOffset;
  end;

  TSyntaxDiagnostic = record
    Message: string;
    StartPos: TTextPosition;
    EndPos: TTextPosition;
  end;

  /// <summary>Ergebnis des Parsers. Besitzt alle Knoten.</summary>
  TSyntaxTree = class
  private
    FRoot: TSyntaxNode;
    FTokens: TArray<TPascalToken>;
    FDiagnostics: TArray<TSyntaxDiagnostic>;
  public
    constructor Create(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>;
      const ADiagnostics: TArray<TSyntaxDiagnostic>);
    destructor Destroy; override;
    property Root: TSyntaxNode read FRoot;
    /// <summary>Alle Token einschließlich Kommentaren und Direktiven.</summary>
    property Tokens: TArray<TPascalToken> read FTokens;
    property Diagnostics: TArray<TSyntaxDiagnostic> read FDiagnostics;
  end;

/// <summary>Name einer Knotenart, z. B. für Tests und Protokolle.</summary>
function SyntaxKindName(AKind: TSyntaxKind): string;

implementation

uses
  System.TypInfo;

function SyntaxKindName(AKind: TSyntaxKind): string;
begin
  Result := GetEnumName(TypeInfo(TSyntaxKind), Ord(AKind));
end;

{ TSyntaxNode }

constructor TSyntaxNode.Create(AKind: TSyntaxKind);
begin
  inherited Create;
  FKind := AKind;
end;

destructor TSyntaxNode.Destroy;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ statt rekursiv: Lange Ketten wie 1+1+...+1 ergeben sehr tiefe
  // Bäume, die rekursiv den Stapel sprengen würden.
  if (FChildren <> nil) and (FChildren.Count > 0) then
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      FChildren.OwnsObjects := False;
      for Index := 0 to FChildren.Count - 1 do
        Pending.Push(FChildren[Index]);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.FChildren <> nil then
        begin
          Node.FChildren.OwnsObjects := False;
          for Index := 0 to Node.FChildren.Count - 1 do
            Pending.Push(Node.FChildren[Index]);
          Node.FChildren.Clear;
        end;
        Node.Free;
      end;
    finally
      Pending.Free;
    end;
  end;
  FChildren.Free;
  inherited;
end;

procedure TSyntaxNode.Add(ANode: TSyntaxNode);
begin
  if FChildren = nil then
    FChildren := TObjectList<TSyntaxNode>.Create(True);
  ANode.FParent := Self;
  FChildren.Add(ANode);
end;

procedure TSyntaxNode.Extract(ANode: TSyntaxNode);
begin
  if FChildren <> nil then
    FChildren.Extract(ANode);
  ANode.FParent := nil;
end;

function TSyntaxNode.FindChild(AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ChildCount - 1 do
    if Children[Index].Kind = AKind then
      Exit(Children[Index]);
  Result := nil;
end;

function TSyntaxNode.GetChild(AIndex: Integer): TSyntaxNode;
begin
  Result := FChildren[AIndex];
end;

function TSyntaxNode.GetChildCount: Integer;
begin
  if FChildren = nil then
    Result := 0
  else
    Result := FChildren.Count;
end;

procedure TSyntaxNode.SetRange(const AStartPos, AEndPos: TTextPosition; AStartOffset, AEndOffset: Integer);
begin
  FStartPos := AStartPos;
  FEndPos := AEndPos;
  FStartOffset := AStartOffset;
  FEndOffset := AEndOffset;
end;

{ TSyntaxTree }

constructor TSyntaxTree.Create(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>;
  const ADiagnostics: TArray<TSyntaxDiagnostic>);
begin
  inherited Create;
  FRoot := ARoot;
  FTokens := ATokens;
  FDiagnostics := ADiagnostics;
end;

destructor TSyntaxTree.Destroy;
begin
  FRoot.Free;
  inherited;
end;

end.
