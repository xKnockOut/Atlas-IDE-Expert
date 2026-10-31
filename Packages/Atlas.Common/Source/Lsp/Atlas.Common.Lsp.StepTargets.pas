unit Atlas.Common.Lsp.StepTargets;

// Befehl atlas.server.stepTargets (#836): Aufrufe der Anweisung am
// Ausführungspunkt für „Gezielt hineinspringen“ im IDE-Plugin.
// Argumente: [uri, line] (Zeile ab 0, wie der Debugger sie meldet minus 1).
// Antwort: {"format": 1, "line": 12, "followLine": 13,
//   "calls": [{"name": "GetName", "container": "TKunde", "kind": "getter",
//              "text": "Kunde.Name", "line": 12, "character": 12,
//              "receiver": "Kunde", "receiverSimple": true, "receiverInterface": false,
//              "virtual": false, "declFile": "…", "declLine": 8,
//              "targets": [{"container": "TKunde", "name": "GetName", "file": "…", "line": 30}]}]}
// kind: call, constructor, getter, setter, inherited. targets nennt je Rumpf die
// Zeile seines begin, an der ein Haltepunkt greift; leer, wenn kein Quelltext
// bekannt ist (das Plugin zeigt den Eintrag dann ausgegraut). Bei virtuellen
// Methoden und Interface-Methoden stehen der eigene Rumpf und alle Rümpfe der
// Nachfahren bzw. implementierenden Klassen darin; welcher gilt, entscheidet
// das Plugin über den Laufzeittyp des Empfängers (receiver.ClassName), wenn
// receiverSimple sagt, dass das Auswerten selbst nichts aufruft.
// Welche Stellen in Frage kommen und in welcher Reihenfolge, steht in
// Atlas.Common.Semantics.StepCalls; hier entscheidet die Namensauflösung, ob
// eine Stelle ein Aufruf ist: Methode, Funktion, Konstruktor, Getter bzw.
// Setter einer Eigenschaft (read/write auf eine Methode). Variablen, Felder,
// Typumwandlungen und Compiler-Intrinsics (Length, Inc …) fallen heraus. Eine
// Prozedur ohne Klammern außerhalb einer Aufrufanweisung ist ein
// Methodenzeiger (OnClick := Klick) und kein Aufruf. Nicht auflösbare
// Aufrufe mit Klammern bleiben ausgegraut in der Liste.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.StepCalls,
  Atlas.Common.Metrics.Collector;

type
  TLspStepTarget = record
    Container: string;
    Name: string;
    FileName: string;
    /// <summary>Zeile (ab 0) des begin des Rumpfs.</summary>
    Line: Integer;
  end;

  TLspStepCall = record
    Name: string;
    Container: string;
    /// <summary>call, constructor, getter, setter oder inherited.</summary>
    Kind: string;
    /// <summary>Quelltext der Stelle (Kunde.Name, Format(…)), höchstens MaxText Zeichen.</summary>
    Text: string;
    Position: TTextPosition;
    Receiver: string;
    ReceiverSimple: Boolean;
    ReceiverInterface: Boolean;
    IsVirtual: Boolean;
    DeclFile: string;
    /// <summary>Zeile der Deklaration (ab 0); -1 ohne.</summary>
    DeclLine: Integer;
    Targets: TArray<TLspStepTarget>;
  end;

  TLspStepAnswer = record
    Line: Integer;
    FollowLine: Integer;
    Calls: TArray<TLspStepCall>;
  end;

  TLspStepTargets = class
  public const
    Command = 'atlas.server.stepTargets';
    MaxText = 80;
    MaxTargets = 50;
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FTree: TSyntaxTree;
    FText: string;
    FFileName: string;
    FReadText: TMetricsReadText;
    FTrees: TObjectDictionary<string, TSyntaxTree>;
    FOwnUnit: TUnitIndex;
    FOwnUnitReady: Boolean;
    function TextOf(ANode: TSyntaxNode): string;
    function OwnUnit: TUnitIndex;
    function UnitOf(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function TreeOf(const AFileName: string): TSyntaxTree;
    function BeginLine(const AFileName: string; ANameLine: Integer; out ALine: Integer): Boolean;
    function FindBody(const AUnit: TUnitIndex; const AContainer, AName: string; const AParamTypes: TArray<string>;
      out ABody: TIndexSymbol): Boolean;
    function TargetOf(const AUnit: TUnitIndex; const ABody: TIndexSymbol; out ATarget: TLspStepTarget): Boolean;
    function IsInterface(const AUnit: TUnitIndex; const AContainer: string): Boolean;
    procedure AddTargets(var ACall: TLspStepCall; const AUnit: TUnitIndex; const AParamTypes: TArray<string>);
    function ResolveSite(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
    function ResolveInherited(const APosition: TTextPosition;
      out ACall: TLspStepCall): Boolean;
    function ResolveUnknown(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
    procedure MarkReceivers(var AAnswer: TLspStepAnswer; const ASites: TArray<TStepCallSite>;
      const ACallSites: TArray<Integer>);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; const AReadText: TMetricsReadText);
    destructor Destroy; override;
    /// <summary>Aufrufe der Anweisung an ALine (ab 0); False ohne Anweisung.</summary>
    function Answer(ALine: Integer; out AAnswer: TLspStepAnswer): Boolean;
    /// <summary>Der Befehl: Antwort als JSON (format 1). Ohne Anweisung bleibt calls leer.</summary>
    class function Execute(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AText, AFileName: string; ALine: Integer; const AReadText: TMetricsReadText): TJSONObject; static;
    class function ToJson(const AAnswer: TLspStepAnswer): TJSONObject; static;
    /// <summary>Name hinter read bzw. write im Kopf einer Eigenschaft; '' ohne.</summary>
    class function Accessor(const ASignature: string; AWrite: Boolean): string; static;
    /// <summary>Sieht ein unbekannter Aufruf mit einem Argument wie eine Typumwandlung aus (TFoo(X), IFoo(X))?
    /// </summary>
    class function LooksLikeCast(const AName: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.StrUtils,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Files,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Semantics.SystemIntrinsics;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function SameParams(const A, B: TArray<string>): Boolean;
begin
  Result := SameText(string.Join(',', A), string.Join(',', B));
end;

function InWith(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  while ANode <> nil do
  begin
    if ANode.Kind = TSyntaxKind.WithStatement then
      Exit(True);
    ANode := ANode.Parent;
  end;
end;

function LastPart(const AName: string): string;
var
  Dot: Integer;
begin
  Result := AName;
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

{ TLspStepTargets }

constructor TLspStepTargets.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; const AReadText: TMetricsReadText);
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FTree := ATree;
  FText := AText;
  FFileName := AFileName;
  FReadText := AReadText;
  FTrees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
end;

destructor TLspStepTargets.Destroy;
begin
  FTrees.Free;
  inherited;
end;

class function TLspStepTargets.Accessor(const ASignature: string; AWrite: Boolean): string;
var
  Words: TArray<string>;
  Index: Integer;
  Key: string;
begin
  Result := '';
  if AWrite then
    Key := 'write'
  else
    Key := 'read';
  Words := ASignature.Replace(';', ' ').Replace(#9, ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
    if SameText(Words[Index], Key) then
      Exit(Words[Index + 1]);
end;

class function TLspStepTargets.LooksLikeCast(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['T', 'I', 'P', 'E']) and
    CharInSet(AName[2], ['A'..'Z']);
end;

function TLspStepTargets.TextOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode = nil) or (ANode.EndOffset <= ANode.StartOffset) or (ANode.EndOffset > Length(FText)) then
    Exit;
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  // Mehrzeilig: in eine Zeile.
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  while Pos('  ', Result) > 0 do
    Result := Result.Replace('  ', ' ');
  if Length(Result) > MaxText then
    Result := Copy(Result, 1, MaxText - 1) + '…';
end;

function TLspStepTargets.OwnUnit: TUnitIndex;
begin
  if not FOwnUnitReady then
  begin
    FOwnUnit := FResolver.ExtractedUnit(FTree, FFileName);
    FOwnUnitReady := True;
  end;
  Result := FOwnUnit;
end;

function TLspStepTargets.UnitOf(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(AFileName, FFileName) then
  begin
    AUnit := OwnUnit;
    Exit(True);
  end;
  Result := (FIndex <> nil) and TIndexFiles.UnitOf(FIndex, AFileName, AUnit);
end;

function TLspStepTargets.TreeOf(const AFileName: string): TSyntaxTree;
var
  Text: string;
begin
  if SameText(AFileName, FFileName) then
    Exit(FTree);
  if FTrees.TryGetValue(LowerCase(AFileName), Result) then
    Exit;
  Result := nil;
  if Assigned(FReadText) and FReadText(AFileName, Text) then
    Result := TSyntaxTreeCache.Parse(Text, nil);
  FTrees.Add(LowerCase(AFileName), Result);
end;

function TLspStepTargets.BeginLine(const AFileName: string; ANameLine: Integer; out ALine: Integer): Boolean;
var
  Tree: TSyntaxTree;
  Found: Integer;
begin
  Result := False;
  ALine := -1;
  Tree := TreeOf(AFileName);
  if (Tree = nil) or (Tree.Root = nil) then
    Exit;
  Found := -1;
  // Die innerste Routine, deren Kopf die Namenszeile enthält: Anfang davor, Rumpf danach.
  Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Body: TSyntaxNode;
    begin
      Result := ANode.StartPos.Line <= ANameLine;
      if not Result or (ANode.EndPos.Line < ANameLine) then
        Exit(False);
      if ANode.Kind <> TSyntaxKind.RoutineDecl then
        Exit;
      Body := ANode.FindChild(TSyntaxKind.Block);
      if Body = nil then
        Body := ANode.FindChild(TSyntaxKind.AsmBlock);
      if (Body <> nil) and (Body.StartPos.Line >= ANameLine) then
        Found := Body.StartPos.Line;
    end);
  ALine := Found;
  Result := Found >= 0;
end;

function TLspStepTargets.FindBody(const AUnit: TUnitIndex; const AContainer, AName: string;
  const AParamTypes: TArray<string>; out ABody: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
  Matches: TList<TIndexSymbol>;
  Index: Integer;
begin
  Result := False;
  Matches := TList<TIndexSymbol>.Create;
  try
    for Symbol in AUnit.Symbols do
      if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName)
      then
        Matches.Add(Symbol);
    if Matches.Count = 0 then
      Exit;
    if Matches.Count = 1 then
    begin
      // Nur ein Eintrag: Rumpf nur bei einer Routine, die allein im implementation-Teil steht.
      Result := (AContainer = '') and not Matches[0].InInterface;
      if Result then
        ABody := Matches[0];
      Exit;
    end;
    // Deklaration und Rumpf, bei Überladungen der letzte mit denselben Parametern.
    for Index := Matches.Count - 1 downto 1 do
      if SameParams(Matches[Index].ParamTypes, AParamTypes) then
      begin
        ABody := Matches[Index];
        Exit(True);
      end;
    ABody := Matches[Matches.Count - 1];
    Result := True;
  finally
    Matches.Free;
  end;
end;

function TLspStepTargets.TargetOf(const AUnit: TUnitIndex; const ABody: TIndexSymbol;
  out ATarget: TLspStepTarget): Boolean;
begin
  ATarget.Container := ABody.Container;
  ATarget.Name := ABody.Name;
  ATarget.FileName := AUnit.SymbolFile(ABody);
  Result := BeginLine(ATarget.FileName, ABody.SelectionRange.StartPos.Line, ATarget.Line);
end;

function TLspStepTargets.IsInterface(const AUnit: TUnitIndex; const AContainer: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if AContainer = '' then
    Exit;
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.InterfaceType) and SameText(Symbol.QualifiedName, AContainer) then
      Exit(True);
end;

procedure TLspStepTargets.AddTargets(var ACall: TLspStepCall; const AUnit: TUnitIndex;
  const AParamTypes: TArray<string>);
var
  Body: TIndexSymbol;
  Target: TLspStepTarget;
  Location: TSymbolLocation;
  Other: TUnitIndex;
begin
  if FindBody(AUnit, ACall.Container, ACall.Name, AParamTypes, Body) and TargetOf(AUnit, Body, Target) then
    ACall.Targets := ACall.Targets + [Target];
  if not ACall.IsVirtual or (FIndex = nil) then
    Exit;
  // Überschreibungen in allen Nachfahren bzw. Klassen, die das Interface implementieren.
  for Location in TLspImplementations.AllDescendantsOf(FIndex, ACall.Container) do
  begin
    if Length(ACall.Targets) >= MaxTargets then
      Break;
    if not UnitOf(Location.FileName, Other) then
      Continue;
    if FindBody(Other, Location.Symbol.QualifiedName, ACall.Name, AParamTypes, Body) and
      TargetOf(Other, Body, Target) then
      ACall.Targets := ACall.Targets + [Target];
  end;
end;

function TLspStepTargets.ResolveInherited(const APosition: TTextPosition;
  out ACall: TLspStepCall): Boolean;
var
  Found: TArray<TDefinitionTarget>;
  Item: TDefinitionTarget;
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  Target: TLspStepTarget;
begin
  Result := False;
  Found := TLspImplementations.Targets(FResolver, FIndex, FTree, FFileName, APosition);
  for Item in Found do
  begin
    if not UnitOf(Item.FileName, Owner) then
      Continue;
    for Symbol in Owner.Symbols do
      if (Symbol.Kind in RoutineKinds) and (Symbol.Range.StartPos.Line = Item.Range.StartPos.Line) and
        (Symbol.SelectionRange.StartPos.Line = Item.SelectionRange.StartPos.Line) and
        (Symbol.SelectionRange.StartPos.Character = Item.SelectionRange.StartPos.Character) then
      begin
        ACall.Name := Symbol.Name;
        ACall.Container := Symbol.Container;
        ACall.Kind := 'inherited';
        ACall.DeclFile := Item.FileName;
        ACall.DeclLine := Item.SelectionRange.StartPos.Line;
        if TargetOf(Owner, Symbol, Target) then
          ACall.Targets := [Target];
        Exit(True);
      end;
  end;
end;

function TLspStepTargets.ResolveUnknown(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
var
  Name: string;
begin
  // Aufruf mit Klammern, den die Namensauflösung nicht kennt (RTL nicht indexiert, Zeiger auf Routinen):
  // ausgegraut anbieten, außer Compiler-Intrinsics und Typumwandlungen.
  Result := False;
  if not ASite.Explicit or (ASite.Callee = nil) or
    not (ASite.Callee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    Exit;
  Name := LastPart(ASite.Callee.Name);
  if (Name = '') or TSystemIntrinsics.IsKnown(Name) then
    Exit;
  if (ASite.Node.ChildCount = 2) and LooksLikeCast(Name) then
    Exit;
  ACall.Name := Name;
  ACall.Kind := 'call';
  Result := True;
end;

function TLspStepTargets.ResolveSite(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
var
  Position: TTextPosition;
  Resolved, TypeSymbol, Access: TResolvedSymbol;
  TypeFound: Boolean;
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  AccessorName: string;
  Found: Boolean;
  Target: TLspStepTarget;
  Statement: Boolean;
begin
  Result := False;
  ACall := Default(TLspStepCall);
  ACall.DeclLine := -1;
  ACall.Text := TextOf(ASite.Node);
  if not TStepCalls.NamePosition(ASite.Callee, Position) then
    Exit;
  ACall.Position := Position;
  if ASite.Receiver <> nil then
    ACall.Receiver := TextOf(ASite.Receiver);
  if ASite.Callee.Kind = TSyntaxKind.InheritedExpr then
    Exit(ResolveInherited(Position, ACall));
  if ASite.Node.Kind = TSyntaxKind.IndexAccess then
  begin
    // Liste[i]: die indizierte bzw. Default-Property.
    if not FResolver.NodeType(FTree, FFileName, ASite.Node, Resolved, TypeSymbol, TypeFound) then
      Exit;
  end
  else
    Resolved := FResolver.Resolve(FTree, FFileName, Position);
  if Resolved.Kind = TResolvedKind.None then
    Exit(ResolveUnknown(ASite, ACall));
  if Resolved.IsType then
    Exit;
  // Verschachtelte Routine: Rumpf in dieser Datei.
  if Resolved.Kind = TResolvedKind.Local then
  begin
    if Resolved.SymbolKind <> TIndexSymbolKind.Routine then
      Exit(ResolveUnknown(ASite, ACall));
    ACall.Name := Resolved.Name;
    ACall.Kind := 'call';
    ACall.DeclFile := FFileName;
    ACall.DeclLine := Resolved.SelectionRange.StartPos.Line;
    Target.Container := '';
    Target.Name := Resolved.Name;
    Target.FileName := FFileName;
    if BeginLine(FFileName, Resolved.SelectionRange.StartPos.Line, Target.Line) then
      ACall.Targets := [Target];
    Exit(True);
  end;
  if not UnitOf(Resolved.FileName, Owner) then
    Owner := Default(TUnitIndex);
  ACall.DeclFile := Resolved.FileName;
  ACall.DeclLine := Resolved.SelectionRange.StartPos.Line;
  case Resolved.SymbolKind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_:
      begin
        // Prozedur ohne Klammern als Wert (OnClick := Klick, Sortiere(Vergleiche)): Methodenzeiger, kein Aufruf.
        Statement := (ASite.Node.Parent <> nil) and (ASite.Node.Parent.Kind = TSyntaxKind.CallStatement);
        if not ASite.Explicit and not Statement and (Resolved.TypeName = '') and
          (Resolved.SymbolKind <> TIndexSymbolKind.Constructor_) then
          Exit;
        if ASite.Assigned then
          Exit;
        ACall.Name := Resolved.Name;
        ACall.Container := Resolved.Container;
        if Resolved.SymbolKind = TIndexSymbolKind.Constructor_ then
          ACall.Kind := 'constructor'
        else
          ACall.Kind := 'call';
        ACall.IsVirtual := Resolved.IsVirtual or IsInterface(Owner, Resolved.Container);
        ACall.ReceiverInterface := IsInterface(Owner, Resolved.Container);
        AddTargets(ACall, Owner, Resolved.ParamTypes);
      end;
    TIndexSymbolKind.Property_:
      begin
        AccessorName := Accessor(Resolved.Signature, ASite.Assigned);
        if AccessorName = '' then
          Exit;
        Found := False;
        Access := Default(TResolvedSymbol);
        // Getter bzw. Setter derselben Klasse; ein Feld als Zugriff ist kein Aufruf.
        for Symbol in Owner.Symbols do
          if SameText(Symbol.Container, Resolved.Container) and SameText(Symbol.Name, AccessorName) then
          begin
            if not (Symbol.Kind in RoutineKinds) then
              Exit;
            if not Found then
            begin
              Access.Name := Symbol.Name;
              Access.ParamTypes := Symbol.ParamTypes;
              Access.IsVirtual := Symbol.IsVirtual;
              ACall.DeclFile := Owner.SymbolFile(Symbol);
              ACall.DeclLine := Symbol.SelectionRange.StartPos.Line;
              Found := True;
            end;
          end;
        // Zugriff in einem Vorfahren: nur ein Name mit Get/Set gilt sicher als Methode.
        if not Found and not (StartsText('Get', AccessorName) or StartsText('Set', AccessorName)) then
          Exit;
        ACall.Name := AccessorName;
        ACall.Container := Resolved.Container;
        if ASite.Assigned then
          ACall.Kind := 'setter'
        else
          ACall.Kind := 'getter';
        ACall.IsVirtual := Access.IsVirtual or IsInterface(Owner, Resolved.Container);
        ACall.ReceiverInterface := IsInterface(Owner, Resolved.Container);
        if Found then
          AddTargets(ACall, Owner, Access.ParamTypes);
      end;
  else
    // Variable, Feld, Parameter: mit Klammern ein Aufruf über einen Zeiger, Ziel unbekannt.
    if not ASite.Explicit or ASite.Assigned then
      Exit;
    ACall.Name := Resolved.Name;
    ACall.Kind := 'call';
    ACall.DeclFile := '';
    ACall.DeclLine := -1;
  end;
  // Methode ohne Empfänger in einer Methode: Self (in with gehört sie vielleicht zum with-Ausdruck).
  if (ACall.Receiver = '') and (ACall.Container <> '') and (ACall.Kind <> 'constructor') and
    not InWith(ASite.Node) then
    ACall.Receiver := 'Self';
  Result := True;
end;

procedure TLspStepTargets.MarkReceivers(var AAnswer: TLspStepAnswer; const ASites: TArray<TStepCallSite>;
  const ACallSites: TArray<Integer>);
var
  Index, Other: Integer;
  Receiver, Node: TSyntaxNode;
  Simple: Boolean;
begin
  for Index := 0 to High(AAnswer.Calls) do
  begin
    Receiver := ASites[ACallSites[Index]].Receiver;
    if Receiver = nil then
    begin
      AAnswer.Calls[Index].ReceiverSimple := AAnswer.Calls[Index].Receiver = 'Self';
      Continue;
    end;
    // Nur Namen und Punkte, und kein Aufruf darin: Das Auswerten ruft nichts auf.
    Simple := Receiver.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        if (ANode.Kind = TSyntaxKind.Identifier) or
          ((ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.FindChild(TSyntaxKind.GenericArgs) = nil)) then
          Result := TSyntaxSearchStep.Descend
        else
          Result := TSyntaxSearchStep.Found;
      end) = nil;
    for Other := 0 to High(AAnswer.Calls) do
    begin
      if not Simple then
        Break;
      Node := ASites[ACallSites[Other]].Node;
      if (Node.StartOffset >= Receiver.StartOffset) and (Node.EndOffset <= Receiver.EndOffset) then
        Simple := False;
    end;
    AAnswer.Calls[Index].ReceiverSimple := Simple;
  end;
end;

function TLspStepTargets.Answer(ALine: Integer; out AAnswer: TLspStepAnswer): Boolean;
var
  Statement: TStepStatement;
  Index: Integer;
  Call: TLspStepCall;
  CallSites: TArray<Integer>;
begin
  AAnswer := Default(TLspStepAnswer);
  AAnswer.Line := ALine;
  AAnswer.FollowLine := -1;
  Result := TStepCalls.Find(FTree, ALine, Statement);
  if not Result then
    Exit;
  AAnswer.Line := Statement.Node.StartPos.Line;
  AAnswer.FollowLine := Statement.FollowLine;
  CallSites := nil;
  for Index := 0 to High(Statement.Sites) do
    if ResolveSite(Statement.Sites[Index], Call) then
    begin
      AAnswer.Calls := AAnswer.Calls + [Call];
      CallSites := CallSites + [Index];
    end;
  MarkReceivers(AAnswer, Statement.Sites, CallSites);
end;

class function TLspStepTargets.Execute(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AText, AFileName: string; ALine: Integer; const AReadText: TMetricsReadText): TJSONObject;
var
  Targets: TLspStepTargets;
  Answer: TLspStepAnswer;
begin
  Targets := TLspStepTargets.Create(AResolver, AIndex, ATree, AText, AFileName, AReadText);
  try
    Targets.Answer(ALine, Answer);
  finally
    Targets.Free;
  end;
  Result := ToJson(Answer);
end;

class function TLspStepTargets.ToJson(const AAnswer: TLspStepAnswer): TJSONObject;
var
  Calls, Targets: TJSONArray;
  Call: TLspStepCall;
  Target: TLspStepTarget;
  Item, TargetItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('line', TJSONNumber.Create(AAnswer.Line));
  Result.AddPair('followLine', TJSONNumber.Create(AAnswer.FollowLine));
  Calls := TJSONArray.Create;
  Result.AddPair('calls', Calls);
  for Call in AAnswer.Calls do
  begin
    Item := TJSONObject.Create;
    Calls.AddElement(Item);
    Item.AddPair('name', Call.Name);
    Item.AddPair('container', Call.Container);
    Item.AddPair('kind', Call.Kind);
    Item.AddPair('text', Call.Text);
    Item.AddPair('line', TJSONNumber.Create(Call.Position.Line));
    Item.AddPair('character', TJSONNumber.Create(Call.Position.Character));
    Item.AddPair('receiver', Call.Receiver);
    Item.AddPair('receiverSimple', TJSONBool.Create(Call.ReceiverSimple));
    Item.AddPair('receiverInterface', TJSONBool.Create(Call.ReceiverInterface));
    Item.AddPair('virtual', TJSONBool.Create(Call.IsVirtual));
    Item.AddPair('declFile', Call.DeclFile);
    Item.AddPair('declLine', TJSONNumber.Create(Call.DeclLine));
    Targets := TJSONArray.Create;
    Item.AddPair('targets', Targets);
    for Target in Call.Targets do
    begin
      TargetItem := TJSONObject.Create;
      Targets.AddElement(TargetItem);
      TargetItem.AddPair('container', Target.Container);
      TargetItem.AddPair('name', Target.Name);
      TargetItem.AddPair('file', Target.FileName);
      TargetItem.AddPair('line', TJSONNumber.Create(Target.Line));
    end;
  end;
end;

end.
