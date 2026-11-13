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
    cCommand = 'atlas.server.stepTargets';
    cMaxText = 80;
    cMaxTargets = 50;
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
    function ResolveTarget(const ASite: TStepCallSite; const APosition: TTextPosition;
      out AResolved: TResolvedSymbol): Boolean;
    function LocalCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
      var ACall: TLspStepCall): Boolean;
    function RoutineCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol; const AOwner: TUnitIndex;
      var ACall: TLspStepCall): Boolean;
    function FindAccessor(const AOwner: TUnitIndex; const AContainer, AName: string; var ACall: TLspStepCall;
      out AAccess: TResolvedSymbol; out AFound: Boolean): Boolean;
    function PropertyCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol; const AOwner: TUnitIndex;
      var ACall: TLspStepCall): Boolean;
    function SymbolCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
      var ACall: TLspStepCall): Boolean;
    function ResolvedCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
      var ACall: TLspStepCall): Boolean;
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
    function Execute(ALine: Integer): TJSONObject;
    /// <summary>Positionen der Aufrufe der Anweisung an ALine (ab 0), für „Warum bin ich hier?“ (#1878).</summary>
    function CallPositions(ALine: Integer): TArray<TTextPosition>;
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
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

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
    begin
      Exit(True);
    end;
    ANode := ANode.Parent;
  end;
end;

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
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
  mWords: TArray<string>;
  mIndex: Integer;
  mKey: string;
begin
  Result := '';
  if AWrite then
  begin
    mKey := 'write';
  end
  else
  begin
    mKey := 'read';
  end;
  mWords := ASignature.Replace(';', ' ').Replace(#9, ' ').Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mWords) - 1 do
  begin
    if SameText(mWords[mIndex], mKey) then
    begin
      Exit(mWords[mIndex + 1]);
    end;
  end;
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
  begin
    Exit;
  end;
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  // Mehrzeilig: in eine Zeile.
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  while Pos('  ', Result) > 0 do
  begin
    Result := Result.Replace('  ', ' ');
  end;
  if Length(Result) > cMaxText then
  begin
    Result := Copy(Result, 1, cMaxText - 1) + '…';
  end;
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
  mText: string;
begin
  if SameText(AFileName, FFileName) then
  begin
    Exit(FTree);
  end;
  if FTrees.TryGetValue(LowerCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  if Assigned(FReadText) and FReadText(AFileName, mText) then
  begin
    Result := TSyntaxTreeCache.Parse(mText, nil);
  end;
  FTrees.Add(LowerCase(AFileName), Result);
end;

function TLspStepTargets.BeginLine(const AFileName: string; ANameLine: Integer; out ALine: Integer): Boolean;
var
  mTree: TSyntaxTree;
  mFound: Integer;
begin
  Result := False;
  ALine := -1;
  mTree := TreeOf(AFileName);
  if (mTree = nil) or (mTree.Root = nil) then
  begin
    Exit;
  end;
  mFound := -1;
  // Die innerste Routine, deren Kopf die Namenszeile enthält: Anfang davor, Rumpf danach.
  mTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Body: TSyntaxNode;
    begin
      Result := ANode.StartPos.Line <= ANameLine;
      if not Result or (ANode.EndPos.Line < ANameLine) then
      begin
        Exit(False);
      end;
      if ANode.Kind <> TSyntaxKind.RoutineDecl then
      begin
        Exit;
      end;
      Body := ANode.FindChild(TSyntaxKind.Block);
      if Body = nil then
      begin
        Body := ANode.FindChild(TSyntaxKind.AsmBlock);
      end;
      if (Body <> nil) and (Body.StartPos.Line >= ANameLine) then
      begin
        mFound := Body.StartPos.Line;
      end;
    end);
  ALine := mFound;
  Result := mFound >= 0;
end;

function TLspStepTargets.FindBody(const AUnit: TUnitIndex; const AContainer, AName: string;
  const AParamTypes: TArray<string>; out ABody: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mMatches: TList<TIndexSymbol>;
  mIndex: Integer;
begin
  Result := False;
  mMatches := TList<TIndexSymbol>.Create;
  try
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName)
      then
      begin
        mMatches.Add(mSymbol);
      end;
    end;
    if mMatches.Count = 0 then
    begin
      Exit;
    end;
    if mMatches.Count = 1 then
    begin
      // Nur ein Eintrag: Rumpf nur bei einer Routine, die allein im implementation-Teil steht.
      Result := (AContainer = '') and not mMatches[0].InInterface;
      if Result then
      begin
        ABody := mMatches[0];
      end;
      Exit;
    end;
    // Deklaration und Rumpf, bei Überladungen der letzte mit denselben Parametern.
    for mIndex := mMatches.Count - 1 downto 1 do
    begin
      if SameParams(mMatches[mIndex].ParamTypes, AParamTypes) then
      begin
        ABody := mMatches[mIndex];
        Exit(True);
      end;
    end;
    ABody := mMatches[mMatches.Count - 1];
    Result := True;
  finally
    mMatches.Free;
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
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if AContainer = '' then
  begin
    Exit;
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.InterfaceType) and SameText(mSymbol.QualifiedName, AContainer) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TLspStepTargets.AddTargets(var ACall: TLspStepCall; const AUnit: TUnitIndex;
  const AParamTypes: TArray<string>);
var
  mBody: TIndexSymbol;
  mTarget: TLspStepTarget;
  mLocation: TSymbolLocation;
  mOther: TUnitIndex;
begin
  if FindBody(AUnit, ACall.Container, ACall.Name, AParamTypes, mBody) and TargetOf(AUnit, mBody, mTarget) then
  begin
    ACall.Targets := ACall.Targets + [mTarget];
  end;
  if not ACall.IsVirtual or (FIndex = nil) then
  begin
    Exit;
  end;
  // Überschreibungen in allen Nachfahren bzw. Klassen, die das Interface implementieren.
  for mLocation in TLspImplementations.AllDescendantsOf(FIndex, ACall.Container) do
  begin
    if Length(ACall.Targets) >= cMaxTargets then
    begin
      Break;
    end;
    if not UnitOf(mLocation.FileName, mOther) then
    begin
      Continue;
    end;
    if FindBody(mOther, mLocation.Symbol.QualifiedName, ACall.Name, AParamTypes, mBody) and
      TargetOf(mOther, mBody, mTarget) then
    begin
      ACall.Targets := ACall.Targets + [mTarget];
    end;
  end;
end;

function TLspStepTargets.ResolveInherited(const APosition: TTextPosition;
  out ACall: TLspStepCall): Boolean;
var
  mFound: TArray<TDefinitionTarget>;
  mItem: TDefinitionTarget;
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mTarget: TLspStepTarget;
begin
  Result := False;
  mFound := TLspImplementations.Targets(FResolver, FIndex, FTree, FFileName, APosition);
  for mItem in mFound do
  begin
    if not UnitOf(mItem.FileName, mOwner) then
    begin
      Continue;
    end;
    for mSymbol in mOwner.Symbols do
    begin
      if (mSymbol.Kind in cRoutineKinds) and (mSymbol.Range.StartPos.Line = mItem.Range.StartPos.Line) and
        (mSymbol.SelectionRange.StartPos.Line = mItem.SelectionRange.StartPos.Line) and
        (mSymbol.SelectionRange.StartPos.Character = mItem.SelectionRange.StartPos.Character) then
      begin
        ACall.Name := mSymbol.Name;
        ACall.Container := mSymbol.Container;
        ACall.Kind := 'inherited';
        ACall.DeclFile := mItem.FileName;
        ACall.DeclLine := mItem.SelectionRange.StartPos.Line;
        if TargetOf(mOwner, mSymbol, mTarget) then
        begin
          ACall.Targets := [mTarget];
        end;
        Exit(True);
      end;
    end;
  end;
end;

function TLspStepTargets.ResolveUnknown(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
var
  mName: string;
begin
  // Aufruf mit Klammern, den die Namensauflösung nicht kennt (RTL nicht indexiert, Zeiger auf Routinen):
  // ausgegraut anbieten, außer Compiler-Intrinsics und Typumwandlungen.
  Result := False;
  if not ASite.Explicit or (ASite.Callee = nil) or
    not (ASite.Callee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Exit;
  end;
  mName := LastPart(ASite.Callee.Name);
  if (mName = '') or TSystemIntrinsics.IsKnown(mName) then
  begin
    Exit;
  end;
  if (ASite.Node.ChildCount = 2) and LooksLikeCast(mName) then
  begin
    Exit;
  end;
  ACall.Name := mName;
  ACall.Kind := 'call';
  Result := True;
end;

function TLspStepTargets.ResolveTarget(const ASite: TStepCallSite; const APosition: TTextPosition;
  out AResolved: TResolvedSymbol): Boolean;
var
  mTypeSymbol: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  if ASite.Node.Kind <> TSyntaxKind.IndexAccess then
  begin
    AResolved := FResolver.Resolve(FTree, FFileName, APosition);
    Exit(True);
  end;
  // Liste[i]: die indizierte bzw. Default-Property.
  Result := FResolver.NodeType(FTree, FFileName, ASite.Node, AResolved, mTypeSymbol, mTypeFound);
end;

function TLspStepTargets.LocalCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
  var ACall: TLspStepCall): Boolean;
var
  mTarget: TLspStepTarget;
begin
  // Verschachtelte Routine: Rumpf in dieser Datei.
  if AResolved.SymbolKind <> TIndexSymbolKind.Routine then
  begin
    Exit(ResolveUnknown(ASite, ACall));
  end;
  ACall.Name := AResolved.Name;
  ACall.Kind := 'call';
  ACall.DeclFile := FFileName;
  ACall.DeclLine := AResolved.SelectionRange.StartPos.Line;
  mTarget.Container := '';
  mTarget.Name := AResolved.Name;
  mTarget.FileName := FFileName;
  if BeginLine(FFileName, AResolved.SelectionRange.StartPos.Line, mTarget.Line) then
  begin
    ACall.Targets := [mTarget];
  end;
  Result := True;
end;

function TLspStepTargets.RoutineCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
  const AOwner: TUnitIndex; var ACall: TLspStepCall): Boolean;
var
  mStatement: Boolean;
begin
  // Prozedur ohne Klammern als Wert (OnClick := Klick, Sortiere(Vergleiche)): Methodenzeiger, kein Aufruf.
  mStatement := (ASite.Node.Parent <> nil) and (ASite.Node.Parent.Kind = TSyntaxKind.CallStatement);
  Result := not ASite.Assigned and (ASite.Explicit or mStatement or (AResolved.TypeName <> '') or
    (AResolved.SymbolKind = TIndexSymbolKind.Constructor_));
  if not Result then
  begin
    Exit;
  end;
  ACall.Name := AResolved.Name;
  ACall.Container := AResolved.Container;
  if AResolved.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    ACall.Kind := 'constructor';
  end
  else
  begin
    ACall.Kind := 'call';
  end;
  ACall.IsVirtual := AResolved.IsVirtual or IsInterface(AOwner, AResolved.Container);
  ACall.ReceiverInterface := IsInterface(AOwner, AResolved.Container);
  AddTargets(ACall, AOwner, AResolved.ParamTypes);
end;

function TLspStepTargets.FindAccessor(const AOwner: TUnitIndex; const AContainer, AName: string;
  var ACall: TLspStepCall; out AAccess: TResolvedSymbol; out AFound: Boolean): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  AAccess := Default(TResolvedSymbol);
  AFound := False;
  // Getter bzw. Setter derselben Klasse; ein Feld als Zugriff ist kein Aufruf.
  for mSymbol in AOwner.Symbols do
  begin
    if not (SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName)) then
    begin
      Continue;
    end;
    if not (mSymbol.Kind in cRoutineKinds) then
    begin
      Exit(False);
    end;
    if not AFound then
    begin
      AAccess.Name := mSymbol.Name;
      AAccess.ParamTypes := mSymbol.ParamTypes;
      AAccess.IsVirtual := mSymbol.IsVirtual;
      ACall.DeclFile := AOwner.SymbolFile(mSymbol);
      ACall.DeclLine := mSymbol.SelectionRange.StartPos.Line;
      AFound := True;
    end;
  end;
  Result := True;
end;

function TLspStepTargets.PropertyCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
  const AOwner: TUnitIndex; var ACall: TLspStepCall): Boolean;
var
  mAccessorName: string;
  mAccess: TResolvedSymbol;
  mFound: Boolean;
begin
  mAccessorName := Accessor(AResolved.Signature, ASite.Assigned);
  Result := (mAccessorName <> '') and FindAccessor(AOwner, AResolved.Container, mAccessorName, ACall, mAccess,
    mFound);
  // Zugriff in einem Vorfahren: nur ein Name mit Get/Set gilt sicher als Methode.
  Result := Result and (mFound or StartsText('Get', mAccessorName) or StartsText('Set', mAccessorName));
  if not Result then
  begin
    Exit;
  end;
  ACall.Name := mAccessorName;
  ACall.Container := AResolved.Container;
  if ASite.Assigned then
  begin
    ACall.Kind := 'setter';
  end
  else
  begin
    ACall.Kind := 'getter';
  end;
  ACall.IsVirtual := mAccess.IsVirtual or IsInterface(AOwner, AResolved.Container);
  ACall.ReceiverInterface := IsInterface(AOwner, AResolved.Container);
  if mFound then
  begin
    AddTargets(ACall, AOwner, mAccess.ParamTypes);
  end;
end;

function TLspStepTargets.SymbolCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
  var ACall: TLspStepCall): Boolean;
var
  mOwner: TUnitIndex;
begin
  if not UnitOf(AResolved.FileName, mOwner) then
  begin
    mOwner := Default(TUnitIndex);
  end;
  ACall.DeclFile := AResolved.FileName;
  ACall.DeclLine := AResolved.SelectionRange.StartPos.Line;
  case AResolved.SymbolKind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_:
      Result := RoutineCall(ASite, AResolved, mOwner, ACall);
    TIndexSymbolKind.Property_:
      Result := PropertyCall(ASite, AResolved, mOwner, ACall);
  else
    // Variable, Feld, Parameter: mit Klammern ein Aufruf über einen Zeiger, Ziel unbekannt.
    Result := ASite.Explicit and not ASite.Assigned;
    if Result then
    begin
      ACall.Name := AResolved.Name;
      ACall.Kind := 'call';
      ACall.DeclFile := '';
      ACall.DeclLine := -1;
    end;
  end;
  // Methode ohne Empfänger in einer Methode: Self (in with gehört sie vielleicht zum with-Ausdruck).
  if Result and (ACall.Receiver = '') and (ACall.Container <> '') and (ACall.Kind <> 'constructor') and
    not InWith(ASite.Node) then
  begin
    ACall.Receiver := 'Self';
  end;
end;

function TLspStepTargets.ResolvedCall(const ASite: TStepCallSite; const AResolved: TResolvedSymbol;
  var ACall: TLspStepCall): Boolean;
begin
  if AResolved.Kind = TResolvedKind.None then
  begin
    Exit(ResolveUnknown(ASite, ACall));
  end;
  if AResolved.IsType then
  begin
    Exit(False);
  end;
  if AResolved.Kind = TResolvedKind.Local then
  begin
    Exit(LocalCall(ASite, AResolved, ACall));
  end;
  Result := SymbolCall(ASite, AResolved, ACall);
end;

function TLspStepTargets.ResolveSite(const ASite: TStepCallSite; out ACall: TLspStepCall): Boolean;
var
  mPosition: TTextPosition;
  mResolved: TResolvedSymbol;
begin
  Result := False;
  ACall := Default(TLspStepCall);
  ACall.DeclLine := -1;
  ACall.Text := TextOf(ASite.Node);
  if not TStepCalls.NamePosition(ASite.Callee, mPosition) then
  begin
    Exit;
  end;
  ACall.Position := mPosition;
  if ASite.Receiver <> nil then
  begin
    ACall.Receiver := TextOf(ASite.Receiver);
  end;
  if ASite.Callee.Kind = TSyntaxKind.InheritedExpr then
  begin
    Result := ResolveInherited(mPosition, ACall);
  end
  else if ResolveTarget(ASite, mPosition, mResolved) then
  begin
    Result := ResolvedCall(ASite, mResolved, ACall);
  end;
end;

/// <summary>Nur Namen und Punkte, und kein Aufruf darin: Das Auswerten von AReceiver ruft nichts auf.</summary>
function IsPlainReceiver(AReceiver: TSyntaxNode): Boolean;
begin
  Result := AReceiver.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind = TSyntaxKind.Identifier) or
        ((ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.FindChild(TSyntaxKind.GenericArgs) = nil)) then
      begin
        Result := TSyntaxSearchStep.Descend;
      end
      else
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) = nil;
end;

/// <summary>True, wenn eine der Aufrufstellen in AReceiver liegt.</summary>
function HasCallInside(AReceiver: TSyntaxNode; const ASites: TArray<TStepCallSite>;
  const ACallSites: TArray<Integer>): Boolean;
var
  mSite: Integer;
  mNode: TSyntaxNode;
begin
  for mSite in ACallSites do
  begin
    mNode := ASites[mSite].Node;
    if (mNode.StartOffset >= AReceiver.StartOffset) and (mNode.EndOffset <= AReceiver.EndOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TLspStepTargets.MarkReceivers(var AAnswer: TLspStepAnswer; const ASites: TArray<TStepCallSite>;
  const ACallSites: TArray<Integer>);
var
  mIndex: Integer;
  mReceiver: TSyntaxNode;
begin
  for mIndex := 0 to High(AAnswer.Calls) do
  begin
    mReceiver := ASites[ACallSites[mIndex]].Receiver;
    if mReceiver = nil then
    begin
      AAnswer.Calls[mIndex].ReceiverSimple := AAnswer.Calls[mIndex].Receiver = 'Self';
    end
    else
    begin
      AAnswer.Calls[mIndex].ReceiverSimple := IsPlainReceiver(mReceiver) and
        not HasCallInside(mReceiver, ASites, ACallSites);
    end;
  end;
end;

function TLspStepTargets.Answer(ALine: Integer; out AAnswer: TLspStepAnswer): Boolean;
var
  mStatement: TStepStatement;
  mIndex: Integer;
  mCall: TLspStepCall;
  mCallSites: TArray<Integer>;
begin
  AAnswer := Default(TLspStepAnswer);
  AAnswer.Line := ALine;
  AAnswer.FollowLine := -1;
  Result := TStepCalls.Find(FTree, ALine, mStatement);
  if not Result then
  begin
    Exit;
  end;
  AAnswer.Line := mStatement.Node.StartPos.Line;
  AAnswer.FollowLine := mStatement.FollowLine;
  mCallSites := nil;
  for mIndex := 0 to High(mStatement.Sites) do
  begin
    if ResolveSite(mStatement.Sites[mIndex], mCall) then
    begin
      AAnswer.Calls := AAnswer.Calls + [mCall];
      mCallSites := mCallSites + [mIndex];
    end;
  end;
  MarkReceivers(AAnswer, mStatement.Sites, mCallSites);
end;

function TLspStepTargets.Execute(ALine: Integer): TJSONObject;
var
  mAnswer: TLspStepAnswer;
begin
  Answer(ALine, mAnswer);
  Result := ToJson(mAnswer);
end;

function TLspStepTargets.CallPositions(ALine: Integer): TArray<TTextPosition>;
var
  mAnswer: TLspStepAnswer;
  mCall: TLspStepCall;
begin
  Result := nil;
  Answer(ALine, mAnswer);
  for mCall in mAnswer.Calls do
  begin
    Result := Result + [mCall.Position];
  end;
end;

class function TLspStepTargets.ToJson(const AAnswer: TLspStepAnswer): TJSONObject;
var
  mCalls, mTargets: TJSONArray;
  mCall: TLspStepCall;
  mTarget: TLspStepTarget;
  mItem, mTargetItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('line', TJSONNumber.Create(AAnswer.Line));
  Result.AddPair('followLine', TJSONNumber.Create(AAnswer.FollowLine));
  mCalls := TJSONArray.Create;
  Result.AddPair('calls', mCalls);
  for mCall in AAnswer.Calls do
  begin
    mItem := TJSONObject.Create;
    mCalls.AddElement(mItem);
    mItem.AddPair('name', mCall.Name);
    mItem.AddPair('container', mCall.Container);
    mItem.AddPair('kind', mCall.Kind);
    mItem.AddPair('text', mCall.Text);
    mItem.AddPair('line', TJSONNumber.Create(mCall.Position.Line));
    mItem.AddPair('character', TJSONNumber.Create(mCall.Position.Character));
    mItem.AddPair('receiver', mCall.Receiver);
    mItem.AddPair('receiverSimple', TJSONBool.Create(mCall.ReceiverSimple));
    mItem.AddPair('receiverInterface', TJSONBool.Create(mCall.ReceiverInterface));
    mItem.AddPair('virtual', TJSONBool.Create(mCall.IsVirtual));
    mItem.AddPair('declFile', mCall.DeclFile);
    mItem.AddPair('declLine', TJSONNumber.Create(mCall.DeclLine));
    mTargets := TJSONArray.Create;
    mItem.AddPair('targets', mTargets);
    for mTarget in mCall.Targets do
    begin
      mTargetItem := TJSONObject.Create;
      mTargets.AddElement(mTargetItem);
      mTargetItem.AddPair('container', mTarget.Container);
      mTargetItem.AddPair('name', mTarget.Name);
      mTargetItem.AddPair('file', mTarget.FileName);
      mTargetItem.AddPair('line', TJSONNumber.Create(mTarget.Line));
    end;
  end;
end;

end.
