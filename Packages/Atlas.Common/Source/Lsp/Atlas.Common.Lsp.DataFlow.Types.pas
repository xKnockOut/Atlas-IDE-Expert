unit Atlas.Common.Lsp.DataFlow.Types;

// Datenfluss (#690): Typen der Anfrage und der Antwort, gemeinsam für die Teile des Laufs (Base, Sources,
// Targets) und für TLspDataFlow, das sie als Aliase weitergibt.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  TDataFlowDirection = (Sources, Targets);

  /// <summary>Art einer Stelle im Datenfluss.</summary>
  TDataFlowKind = (Assignment, VarArgument, OutArgument, Input, Initializer, Loop, CallerArgument, Return,
    PropertyWrite, PropertyRead, Modify, Argument, Output, Use, Constant, Outside, Address);

  /// <summary>Warum sich eine Quelle bzw. ein Ziel nicht weiter aufklappen lässt.</summary>
  TDataFlowLeaf = (None, Constant, Outside, Cycle);

  TDataFlowSymbol = record
    Name: string;
    FileName: string;
    /// <summary>Name der Deklaration.</summary>
    Position: TTextPosition;
    SymbolKind: TIndexSymbolKind;
    Leaf: TDataFlowLeaf;
    /// <summary>"DATEI|Zeile:Zeichen" der Deklaration; gleich für alle Wege zum selben Symbol.</summary>
    function Key: string;
  end;

  TDataFlowPlace = record
    FileName: string;
    Position: TTextPosition;
    /// <summary>Zeile ohne Einrückung.</summary>
    LineText: string;
  end;

  TDataFlowNode = record
    Kind: TDataFlowKind;
    /// <summary>Fundorte; mehrere, wenn gleiche Stellen zusammengefasst sind.</summary>
    Places: TArray<TDataFlowPlace>;
    /// <summary>Wert- bzw. Zielausdruck, einzeilig ("A + B", "Kunde.Name").</summary>
    Detail: string;
    /// <summary>Weg des Werts: Aufgerufener, Property oder Setter ("Summe", "Property Name").</summary>
    Via: string;
    /// <summary>Der Wert enthält Literale; ohne Quellen ist die Stelle ein Literal-Blatt.</summary>
    Literal: Boolean;
    Unsafe: Boolean;
    /// <summary>Zeiger, absolute, Move, FillChar oder Adresse.</summary>
    UnsafeReason: string;
    Sources: TArray<TDataFlowSymbol>;
  end;

  TDataFlowOptions = record
    /// <summary>Stellen in Test-Units auslassen.</summary>
    ExcludeTests: Boolean;
    /// <summary>Nur Stellen in Projektdateien; Quellen außerhalb bleiben als Blätter.</summary>
    OnlyProject: Boolean;
    /// <summary>Schlüssel der Vorfahren im Baum des Editors (für Zyklen).</summary>
    Path: TArray<string>;
  end;

  TDataFlowResult = record
    Found: Boolean;
    Symbol: TDataFlowSymbol;
    Nodes: TArray<TDataFlowNode>;
  end;

  /// <summary>Eine Anfrage an TLspDataFlow.Analyze: Datenfluss des Symbols an Position in Tree.</summary>
  TDataFlowRequest = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    Direction: TDataFlowDirection;
    Options: TDataFlowOptions;
    /// <summary>Projektdateien; leer = alles zählt zum Projekt.</summary>
    Files: TArray<string>;
    /// <summary>Liest jede Datei, auch FileName.</summary>
    ReadText: TReferenceReadText;
    Cancellation: IJsonRpcCancellationToken;
  end;

  /// <summary>Parameter einer Routine, Namen einzeln.</summary>
  TDataFlowParam = record
    Name: string;
    Modifier: TParameterModifier;
    FileName: string;
    Position: TTextPosition;
    /// <summary>Der Parameter als Symbol (Variable) für Quellen und Ziele.</summary>
    function Symbol: TDataFlowSymbol;
  end;

  /// <summary>Art und Fundort einer neuen Stelle.</summary>
  TDataFlowSpot = record
    Kind: TDataFlowKind;
    FileName: string;
    Position: TTextPosition;
    class function Create(AKind: TDataFlowKind; const AFileName: string;
      const APosition: TTextPosition): TDataFlowSpot; static;
  end;

  /// <summary>Weg eines Werts an einer Stelle: Detail (Ausdruck), Via (Aufgerufener, Property) und der Grund
  /// einer unsicheren Kante.</summary>
  TDataFlowEdge = record
    Detail: string;
    Via: string;
    UnsafeReason: string;
    class function Create(const ADetail, AVia, AUnsafeReason: string): TDataFlowEdge; static;
  end;

  /// <summary>Ein Argument eines Aufrufs: Call[Argument + 1] in Tree, gefunden an Position.</summary>
  TDataFlowCallSite = record
    Tree: TSyntaxTree;
    FileName: string;
    Call: TSyntaxNode;
    /// <summary>Index des Arguments ab 0 (-1, wenn es nicht unter den Argumenten steht).</summary>
    Argument: Integer;
    Position: TTextPosition;
    UnsafeReason: string;
    class function Create(ATree: TSyntaxTree; const AFileName: string; ACall: TSyntaxNode; AArgument: Integer;
      const APosition: TTextPosition; const AUnsafeReason: string): TDataFlowCallSite; static;
    function Spot(AKind: TDataFlowKind): TDataFlowSpot;
    /// <summary>Kleingeschriebener Name des Aufgerufenen ("inc", "move").</summary>
    function Callee: string;
    /// <summary>Name des Aufgerufenen, wie er dasteht, ohne Typ-Präfix.</summary>
    function Via: string;
  end;

  TDataFlowSyntaxKinds = set of TSyntaxKind;
  TDataFlowSymbolKinds = set of TIndexSymbolKind;

const
  cRoutineKinds: TDataFlowSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine];
  cTypeKinds: TDataFlowSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
  cConstantKinds: TDataFlowSymbolKinds = [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember];
  // Knoten, die in Deklarationen einen Typ statt eines Werts beschreiben.
  cTypeNodeKinds: TDataFlowSyntaxKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType,
    TSyntaxKind.PointerType, TSyntaxKind.ProcedureType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType,
    TSyntaxKind.ClassOfType, TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.GenericArgs];
  cStatementKinds: TDataFlowSyntaxKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
  /// <summary>Höchstzahl der Knoten einer Antwort.</summary>
  cMaxDataFlowNodes = 500;

implementation

uses
  System.SysUtils,
  Atlas.Common.Lsp.DataFlow.Syntax;

{ TDataFlowSymbol }

function TDataFlowSymbol.Key: string;
begin
  Result := UpperCase(FileName) + '|' + IntToStr(Position.Line) + ':' + IntToStr(Position.Character);
end;

{ TDataFlowParam }

function TDataFlowParam.Symbol: TDataFlowSymbol;
begin
  Result := Default(TDataFlowSymbol);
  Result.Name := Name;
  Result.FileName := FileName;
  Result.Position := Position;
  Result.SymbolKind := TIndexSymbolKind.Variable;
end;

{ TDataFlowSpot }

class function TDataFlowSpot.Create(AKind: TDataFlowKind; const AFileName: string;
  const APosition: TTextPosition): TDataFlowSpot;
begin
  Result.Kind := AKind;
  Result.FileName := AFileName;
  Result.Position := APosition;
end;

{ TDataFlowEdge }

class function TDataFlowEdge.Create(const ADetail, AVia, AUnsafeReason: string): TDataFlowEdge;
begin
  Result.Detail := ADetail;
  Result.Via := AVia;
  Result.UnsafeReason := AUnsafeReason;
end;

{ TDataFlowCallSite }

class function TDataFlowCallSite.Create(ATree: TSyntaxTree; const AFileName: string; ACall: TSyntaxNode;
  AArgument: Integer; const APosition: TTextPosition; const AUnsafeReason: string): TDataFlowCallSite;
begin
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Call := ACall;
  Result.Argument := AArgument;
  Result.Position := APosition;
  Result.UnsafeReason := AUnsafeReason;
end;

function TDataFlowCallSite.Spot(AKind: TDataFlowKind): TDataFlowSpot;
begin
  Result := TDataFlowSpot.Create(AKind, FileName, Position);
end;

function TDataFlowCallSite.Callee: string;
begin
  Result := TDataFlowSyntax.CalleeName(Call);
end;

function TDataFlowCallSite.Via: string;
begin
  Result := TDataFlowSyntax.ShortName(Call.Name);
end;

end.
