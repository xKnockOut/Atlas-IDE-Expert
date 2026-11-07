unit Atlas.Common.Rules.Builtin.Flow;

// Flussregeln (#269) auf dem Kontrollflussgraphen (#143):
//   result-not-set            Funktion kann enden, ohne Result zu setzen (wie W1035)
//   possibly-uninitialized    lokale Variable wird möglicherweise vor der ersten
//                             Zuweisung gelesen (wie W1036)
//   unreachable-code          Anweisung nach Exit, raise, Abort, goto … wird nie
//                             ausgeführt (#94); gemeldet wird nur die erste
//                             Anweisung eines unerreichbaren Abschnitts
//   use-after-free            nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X)
//                             oder Dispose(X) wird X ohne neue Zuweisung wieder
//                             benutzt (#915): X.Methode, X.Feld, X[…], X^, with X,
//                             nach Free auch Assigned(X) und ein zweites Free.
//                             Vom Freigabeknoten aus folgt die Regel dem Graphen;
//                             eine Zuweisung an X, die Übergabe von X an eine
//                             Routine, @X und nach FreeAndNil eine Abfrage auf nil
//                             (Assigned(X), X <> nil) beenden den Weg. Konfidenz
//                             hoch, wenn Freigabe und Zugriff im selben Block
//                             nacheinander stehen, sonst mittel. Die Aktion
//                             springt zur Freigabe.
//   deref-before-nil-check    X wird benutzt (X.Feld, X.Methode, X[…], X^) und
//                             erst danach mit Assigned(X), X <> nil oder X = nil
//                             geprüft (#916). Still, wenn vor dem Zugriff schon
//                             geprüft wurde, wenn X dazwischen neu gesetzt oder
//                             übergeben wird und bei Feldern und globalen
//                             Variablen nach jedem Aufruf dazwischen (er kann
//                             sie ändern). Steht die Prüfung als if ohne else
//                             direkt nach dem Zugriff im selben Block, zieht die
//                             Korrektur sie vor den Zugriff.
//   field-free-without-nil    FFeld.Free in einer Methode außerhalb des
//                             Destruktors, und ein Weg zum Ende der Methode
//                             setzt das Feld nicht neu (#917). Neu setzt eine
//                             Zuweisung oder der Aufruf einer Methode derselben
//                             Klasse, die das Feld zuweist. Felder sind die der
//                             Klassendeklaration in der Unit. Ausgenommen sind
//                             die Methoden aus ignoreMethods (Vorgabe Destroy,
//                             BeforeDestruction); Korrektur FreeAndNil(FFeld).
//   destructor-not-nil-safe   Der Destruktor (oder eine Methode, die nur er
//                             aufruft) benutzt ein Feld (FFeld.Clear), das ein
//                             Konstruktor erst nach Code anlegt, der eine
//                             Exception werfen kann, oder nur bedingt (#1087).
//                             Wirft der Konstruktor, ruft Delphi den Destruktor
//                             mit dem noch leeren Feld auf. Free, FreeAndNil,
//                             DisposeOf und Zugriffe nach Assigned(FFeld) bzw.
//                             FFeld <> nil sind sicher; BeforeDestruction läuft
//                             auf diesem Weg nicht. Mit onlyAfterRaisingCode
//                             aus zählt jedes im Konstruktor angelegte Feld.
//                             Korrektur: if Assigned(FFeld) then davor.
//   handle-leak               Ein Windows-Handle aus CreateFile, CreateEvent,
//                             OpenProcess, CreateProcess (hProcess, hThread),
//                             FindFirstFile, RegOpenKeyEx, LoadLibrary, GetDC,
//                             GDI-Objekten … in einer lokalen Variablen wird
//                             auf einem Weg zum Ende der Routine nicht mit dem
//                             passenden Gegenstück geschlossen (#1088). Die
//                             Paare stehen in BuiltinHandlePairs, eigene über
//                             die Option pairs. Zurückgeben, Speichern und
//                             Übergabe an unbekannte Routinen gelten als
//                             Weitergabe, ebenso [H] in einem Array-Ausdruck;
//                             Zweige, in denen das Öffnen laut if-Prüfung
//                             misslang, und Ausnahmewege
//                             (pair-without-finally) zählen nicht. Korrektur:
//                             die Anweisungen danach in try … finally mit dem
//                             Schließen einschließen.
//   out-param-read            out-Parameter wird gelesen, bevor die Routine ihn
//                             setzt (#924); bei verwalteten Typen hat ihn der
//                             Aufrufer schon geleert. Korrektur out -> var in
//                             Implementierung und Deklaration.
//   noreturn-returns          Eine noreturn-Routine (ab Delphi 13) kann normal
//                             zurückkehren (#1132): Ein Weg erreicht das Ende des
//                             Rumpfs oder ein Exit, ohne über raise, Abort, Halt,
//                             RunError oder den Aufruf einer anderen noreturn-
//                             Routine zu gehen. Die Direktive zählt an der
//                             Implementierung und an der Deklaration (interface,
//                             Klasse). Aufrufe, deren Ziel weder die Datei, die
//                             Standardroutinen noch der Symbolindex kennt, könnten
//                             selbst noreturn sein und beenden den Weg ebenfalls;
//                             gemeldet wird also nur ein Weg ganz aus bekannten
//                             Anweisungen. Exit wird an der Anweisung gemeldet,
//                             das Ende des Rumpfs am Routinennamen.
//
// Was der Graph nicht sieht, macht die Variable "unbekannt" und erzeugt keinen
// Treffer: Übergabe als Argument (var/out-Parameter, SetLength, FillChar,
// TryGetValue …), @X, Zuweisung an ein Feld oder Element (Result.Feld := …,
// Result[I] := …), with X do, inherited in Funktionen und die alte Zuweisung
// an den Funktionsnamen. Ist der Graph unvollständig (asm, Syntaxfehler),
// gibt es ebenfalls keinen Treffer.
//
// possibly-uninitialized prüft nur Variablen, die Delphi nicht selbst
// vorbelegt: einfache Typen (Konfidenz hoch) und T…-Typen wie Klassen und
// Records (Konfidenz mittel). string, Variant, Interfaces und dynamische
// Arrays sind verwaltet und werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Flow.Uninitialized,
  Atlas.Common.Rules.Builtin.Flow.UseAfterFree,
  Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck,
  Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak,
  Atlas.Common.Rules.Builtin.Flow.OutParamRead;

type
  TResultNotSetRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.Uninitialized.</summary>
  TPossiblyUninitializedRule = Atlas.Common.Rules.Builtin.Flow.Uninitialized.TPossiblyUninitializedRule;

  TUnreachableCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.UseAfterFree.</summary>
  TUseAfterFreeRule = Atlas.Common.Rules.Builtin.Flow.UseAfterFree.TUseAfterFreeRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.</summary>
  TDerefBeforeNilCheckRule = Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.TDerefBeforeNilCheckRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.</summary>
  TFieldFreeWithoutNilRule = Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.TFieldFreeWithoutNilRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.</summary>
  TDestructorNotNilSafeRule = Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.TDestructorNotNilSafeRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.HandleLeak.</summary>
  THandleLeakRule = Atlas.Common.Rules.Builtin.Flow.HandleLeak.THandleLeakRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Flow.OutParamRead.</summary>
  TOutParamReadRule = Atlas.Common.Rules.Builtin.Flow.OutParamRead.TOutParamReadRule;

  TNoreturnReturnsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cUseAfterFreeRuleId = Atlas.Common.Rules.Builtin.Flow.UseAfterFree.cUseAfterFreeRuleId;
  cDerefBeforeNilCheckRuleId = Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.cDerefBeforeNilCheckRuleId;
  cFieldFreeWithoutNilRuleId = Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil.cFieldFreeWithoutNilRuleId;
  cDestructorNotNilSafeRuleId = Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.cDestructorNotNilSafeRuleId;
  cHandleLeakRuleId = Atlas.Common.Rules.Builtin.Flow.HandleLeak.cHandleLeakRuleId;
  cNoreturnReturnsRuleId = 'noreturn-returns';

/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowText = (ResultTitle, NoResult, UnreachableTitle, Unreachable, NoReturnTitle, ExitNoReturn, EndNoReturn);

const
  cTexts: array[TFlowText] of TAtlasText = (
    (De: 'Funktion kann enden, ohne Result zu setzen'; En: 'Function can end without setting Result'),
    (De: '"%s" kann enden, ohne Result zu setzen; der Rückgabewert ist dann undefiniert';
     En: '"%s" can end without setting Result; the return value is then undefined'),
    (De: 'Anweisung wird nie ausgeführt'; En: 'Statement is never executed'),
    (De: 'Diese Anweisung wird nie ausgeführt'; En: 'This statement is never executed'),
    (De: 'noreturn-Routine kann normal zurückkehren'; En: 'noreturn routine can return normally'),
    (De: 'Exit verlässt %s normal, obwohl die Routine noreturn ist.';
     En: 'Exit leaves %s normally although the routine is noreturn.'),
    (De: '%s kann am Ende normal zurückkehren, obwohl die Routine noreturn ist.';
     En: '%s can return normally at the end although the routine is noreturn.'));

{$SCOPEDENUMS OFF}

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
begin
  Result := Atlas.Common.Rules.Builtin.Flow.Shared.HasOpaqueUse(ABlock, AName);
end;

{ TResultNotSetRule }

function TResultNotSetRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('result-not-set', TRuleSeverity.Warning,
    cTexts[TFlowText.ResultTitle].Text);
end;

procedure TResultNotSetRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutines: TArray<TSyntaxNode>;
  mRoutine, mHeader, mBlock: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mCache: IRuleDerivedCache;
  mName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  mCache := TRuleDerived.Open(AContext);
  mRoutines := TRuleDerived.Routines(mCache, AContext);
  for mRoutine in mRoutines do
  begin
    mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
    // Nur Funktionen: der Kopf trägt einen Ergebnistyp.
    if (mHeader = nil) or (mHeader.FindChild(TSyntaxKind.TypeReference) = nil) then
    begin
      Continue;
    end;
    mBlock := mRoutine.FindChild(TSyntaxKind.Block);
    mName := ShortName(mRoutine.Name);
    if HasOpaqueUse(mBlock, 'Result') or HasOpaqueUse(mBlock, mName) or ContainsKind(mBlock, TSyntaxKind.InheritedExpr) then
    begin
      Continue;
    end;
    mGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
    // Alte Schreibweise: Zuweisung an den Funktionsnamen setzt ebenfalls das Ergebnis.
    if (mGraph.MayEndWithout('Result') = TFlowAnswer.Yes) and (mGraph.MayEndWithout(mName) = TFlowAnswer.Yes) then
    begin
      AReport.Add(HeaderNameRange(AContext, mRoutine),
        cTexts[TFlowText.NoResult].Fmt([mName]),
        TRuleConfidence.High);
    end;
  end;
end;

{ TUnreachableCodeRule }

function TUnreachableCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unreachable-code', TRuleSeverity.Warning, cTexts[TFlowText.UnreachableTitle].Text);
end;

/// <summary>Bereich der ersten Zeile von ANode; mehrzeilige Anweisungen werden nicht ganz markiert.</summary>
function FirstLineRange(const AContext: TRuleContext; ANode: TSyntaxNode): TTextRange;
var
  mToken: TPascalToken;
  mIndex: Integer;
  mLast: TTextPosition;
begin
  mLast := ANode.EndPos;
  if mLast.Line <> ANode.StartPos.Line then
  begin
    mLast := ANode.StartPos;
    for mIndex := AContext.Tree.FirstTokenFrom(ANode.StartOffset) to High(AContext.Tree.Tokens) do
    begin
      mToken := AContext.Tree.Tokens[mIndex];
      if mToken.Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if (mToken.Offset >= ANode.StartOffset) and (mToken.StartPos.Line = ANode.StartPos.Line) and
        (mToken.Kind <> TPascalTokenKind.Comment) then
      begin
        mLast := mToken.EndPos;
      end;
    end;
  end;
  Result := TTextRange.Create(ANode.StartPos, mLast);
end;

procedure TUnreachableCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutines: TArray<TSyntaxNode>;
  mDead: TArray<TSyntaxNode>;
  mRoutine: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mCache: IRuleDerivedCache;
  mUnreachable: TArray<TFlowNode>;
  mNode: TFlowNode;

  function IsDead(ANode: TSyntaxNode): Boolean;
  var
    mItem: TSyntaxNode;
  begin
    for mItem in mDead do
    begin
      if mItem = ANode then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Liegt eine unerreichbare Anweisung in ANode (oder ist es ANode selbst)? Iterativ (Bericht M1): von den
  // unerreichbaren Anweisungen aufwärts statt rekursiv durch ANode.
  function HasDead(ANode: TSyntaxNode): Boolean;
  var
    mItem, mCurrent: TSyntaxNode;
  begin
    for mItem in mDead do
    begin
      mCurrent := mItem;
      while mCurrent <> nil do
      begin
        if mCurrent = ANode then
        begin
          Exit(True);
        end;
        mCurrent := mCurrent.Parent;
      end;
    end;
    Result := False;
  end;

  // Erste Anweisung eines unerreichbaren Abschnitts: nicht in einer anderen
  // unerreichbaren Anweisung enthalten, und davor steht (auf der ersten Ebene,
  // die einen Vorgänger hat) erreichbarer Code.
  function StartsDeadRun(AStatement: TSyntaxNode): Boolean;
  var
    mCurrent, mParent: TSyntaxNode;
    mIndex: Integer;
  begin
    mCurrent := AStatement.Parent;
    while (mCurrent <> nil) and (mCurrent <> mRoutine) do
    begin
      if IsDead(mCurrent) then
      begin
        Exit(False);
      end;
      mCurrent := mCurrent.Parent;
    end;
    mCurrent := AStatement;
    while (mCurrent <> mRoutine) and (mCurrent.Parent <> nil) do
    begin
      mParent := mCurrent.Parent;
      for mIndex := 1 to mParent.ChildCount - 1 do
      begin
        if mParent[mIndex] = mCurrent then
        begin
          Exit(not HasDead(mParent[mIndex - 1]));
        end;
      end;
      mCurrent := mParent;
    end;
    Result := True;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  mCache := TRuleDerived.Open(AContext);
  mRoutines := TRuleDerived.Routines(mCache, AContext);
  for mRoutine in mRoutines do
  begin
    mGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
    if not mGraph.Complete then
    begin
      Continue;
    end;
    mUnreachable := mGraph.UnreachableStatements;
    mDead := nil;
    for mNode in mUnreachable do
    begin
      if mNode.Syntax <> nil then
      begin
        mDead := mDead + [mNode.Syntax];
      end;
    end;
    for mNode in mUnreachable do
    begin
      if (mNode.Syntax <> nil) and StartsDeadRun(mNode.Syntax) then
      begin
        AReport.Add(FirstLineRange(AContext, mNode.Syntax), cTexts[TFlowText.Unreachable].Text,
          TRuleConfidence.High);
      end;
    end;
  end;
end;

{ TNoreturnReturnsRule }

type
  /// <summary>Was ein Aufruf für den Weg einer noreturn-Routine bedeutet.</summary>
  TNoreturnCallEffect = (Returns, Ends, Unknown);

/// <summary>AName ohne Typparameter (TListe&lt;T&gt;.Fehler -&gt; TListe.Fehler), klein geschrieben.</summary>
function WithoutTypeParams(const AName: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AName) do
  begin
    if AName[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AName[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      Result := Result + AName[mIndex];
    end;
  end;
  Result := LowerCase(Result);
end;

function HasNoreturn(AHeader: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  if AHeader <> nil then
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, 'noreturn') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Voller Name eines Routinenkopfs: TKlasse.Name in einer Klassendeklaration, sonst der Name der
/// Routine (bei Methoden TKlasse.Name).</summary>
function HeaderFullName(AHeader: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  if (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    Exit(WithoutTypeParams(AHeader.Parent.Name));
  end;
  mParent := AHeader.Parent;
  while (mParent <> nil) and (mParent.Kind <> TSyntaxKind.TypeDecl) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Result := WithoutTypeParams(AHeader.Name);
  end
  else
  begin
    Result := WithoutTypeParams(mParent.Name + '.' + AHeader.Name);
  end;
end;

/// <summary>Aufgerufene Routine der Aufrufanweisung ASyntax (X; bzw. X(…);); nil bei anderen Anweisungen.</summary>
function StatementCallee(ASyntax: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ASyntax = nil) or (ASyntax.Kind <> TSyntaxKind.CallStatement) or (ASyntax.ChildCount = 0) then
  begin
    Exit;
  end;
  Result := ASyntax[0];
  if (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount > 0) then
  begin
    Result := Result[0];
  end;
end;

/// <summary>Exit oder Exit(Wert) als eigene Anweisung (nicht TMonitor.Exit).</summary>
function IsExitStatement(ASyntax: TSyntaxNode): Boolean;
var
  mCallee: TSyntaxNode;
begin
  mCallee := StatementCallee(ASyntax);
  Result := (mCallee <> nil) and IsName(mCallee, 'Exit');
end;

function TNoreturnReturnsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cNoreturnReturnsRuleId, TRuleSeverity.Warning,
    cTexts[TFlowText.NoReturnTitle].Text);
end;

procedure TNoreturnReturnsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mNoreturnFull, mNoreturnShort, mKnownShort: TDictionary<string, Boolean>;
  mCache: IRuleDerivedCache;
  mRoutine: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mExits: TArray<TFlowNode>;
  mExit: TFlowNode;
  mToEnd: TArray<Boolean>;
  mName: string;

  procedure CollectHeaders;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mShort: string;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        for mIndex := 0 to mNode.ChildCount - 1 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
        if mNode.Kind <> TSyntaxKind.RoutineHeader then
        begin
          Continue;
        end;
        mShort := LowerCase(ShortName(HeaderFullName(mNode)));
        mKnownShort.AddOrSetValue(mShort, True);
        if HasNoreturn(mNode) then
        begin
          mNoreturnFull.AddOrSetValue(HeaderFullName(mNode), True);
          mNoreturnShort.AddOrSetValue(mShort, True);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function IndexEffect(const AShort: string): TNoreturnCallEffect;
  var
    mLocation: TSymbolLocation;
  begin
    Result := TNoreturnCallEffect.Unknown;
    if AContext.Index = nil then
    begin
      Exit;
    end;
    for mLocation in AContext.Index.FindSymbols(AShort) do
    begin
      if mLocation.Symbol.HasDirective('noreturn') then
      begin
        Exit(TNoreturnCallEffect.Ends);
      end
      else
      begin
        Result := TNoreturnCallEffect.Returns;
      end;
    end;
  end;

  /// <summary>Wirkung der Anweisung ASyntax: Ends bei Halt, RunError und noreturn-Routinen, Unknown bei
  /// Aufrufen mit unbekanntem Ziel (inherited, Methoden fremder Typen ohne Index).</summary>
  function CallEffect(ASyntax: TSyntaxNode): TNoreturnCallEffect;
  var
    mCallee: TSyntaxNode;
    mShort: string;
    mMode: TFlowArgumentMode;
    mIsName: Boolean;
  begin
    Result := TNoreturnCallEffect.Returns;
    mCallee := StatementCallee(ASyntax);
    if mCallee = nil then
    begin
      Exit;
    end;
    mShort := LowerCase(mCallee.Name);
    mIsName := mCallee.Kind = TSyntaxKind.Identifier;
    if not mIsName and (mCallee.Kind <> TSyntaxKind.MemberAccess) then
    begin
      Result := TNoreturnCallEffect.Unknown;
    end
    else if mIsName and MatchText(mShort, ['halt', 'runerror']) then
    begin
      Result := TNoreturnCallEffect.Ends;
    end
    else if mIsName and MatchText(mShort, ['exit', 'break', 'continue', 'abort']) then
    begin
      // Sprünge modelliert der Graph selbst.
      Result := TNoreturnCallEffect.Returns;
    end
    else if mNoreturnShort.ContainsKey(mShort) then
    begin
      Result := TNoreturnCallEffect.Ends;
    end
    else if not mKnownShort.ContainsKey(mShort) and
      not (mIsName and TFlowSignatures.TryBuiltin(mShort, 0, mMode)) then
    begin
      Result := IndexEffect(mShort);
    end;
  end;

  /// <summary>Knoten, die vom Anfang aus erreichbar sind, ohne einen Knoten zu verlassen, der den Weg
  /// beendet; von solchen Knoten führen nur die Ausnahmekanten weiter. Mit AStopAtExit enden die Wege auch
  /// an Exit.</summary>
  function Reachable(AStopAtExit: Boolean): TArray<Boolean>;
  var
    mPending: TStack<TFlowNode>;
    mNode, mNext: TFlowNode;
    mEnds: Boolean;
  begin
    SetLength(Result, mGraph.Nodes.Count);
    mPending := TStack<TFlowNode>.Create;
    try
      mPending.Push(mGraph.Entry);
      Result[mGraph.Entry.Index] := True;
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mEnds := (AStopAtExit and IsExitStatement(mNode.Syntax)) or
          (CallEffect(mNode.Syntax) <> TNoreturnCallEffect.Returns);
        for mNext in mNode.Successors do
        begin
          if not Result[mNext.Index] and (not mEnds or mNode.IsImplicitRaiseEdge(mNext)) then
          begin
            Result[mNext.Index] := True;
            mPending.Push(mNext);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function ExitsReached: TArray<TFlowNode>;
  var
    mSeen: TArray<Boolean>;
    mNode: TFlowNode;
  begin
    Result := nil;
    mSeen := Reachable(False);
    for mNode in mGraph.Nodes do
    begin
      if mSeen[mNode.Index] and (mNode.Kind = TFlowNodeKind.Statement) and IsExitStatement(mNode.Syntax) then
      begin
        Result := Result + [mNode];
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'noreturn') then
  begin
    Exit;
  end;
  mNoreturnFull := TDictionary<string, Boolean>.Create;
  mNoreturnShort := TDictionary<string, Boolean>.Create;
  mKnownShort := TDictionary<string, Boolean>.Create;
  try
    CollectHeaders;
    mCache := TRuleDerived.Open(AContext);
    for mRoutine in TRuleDerived.Routines(mCache, AContext) do
    begin
      if not (HasNoreturn(mRoutine.FindChild(TSyntaxKind.RoutineHeader)) or
        mNoreturnFull.ContainsKey(WithoutTypeParams(mRoutine.Name))) then
      begin
        Continue;
      end;
      mGraph := TRuleDerived.Graph(mCache, AContext, mRoutine);
      if not mGraph.Complete then
      begin
        Continue;
      end;
      mName := ShortName(mRoutine.Name);
      mExits := ExitsReached;
      for mExit in mExits do
      begin
        AReport.Add(NodeRange(mExit.Syntax),
          cTexts[TFlowText.ExitNoReturn].Fmt([mName]), TRuleConfidence.High);
      end;
      mToEnd := Reachable(True);
      if mToEnd[mGraph.ExitNode.Index] then
      begin
        AReport.Add(HeaderNameRange(AContext, mRoutine),
          cTexts[TFlowText.EndNoReturn].Fmt([mName]),
          TRuleConfidence.High);
      end;
    end;
  finally
    mKnownShort.Free;
    mNoreturnShort.Free;
    mNoreturnFull.Free;
  end;
end;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TResultNotSetRule.Create);
  ARegistry.Register(TPossiblyUninitializedRule.Create);
  ARegistry.Register(TUnreachableCodeRule.Create);
  ARegistry.Register(TUseAfterFreeRule.Create);
  ARegistry.Register(TDerefBeforeNilCheckRule.Create);
  ARegistry.Register(TFieldFreeWithoutNilRule.Create);
  ARegistry.Register(TDestructorNotNilSafeRule.Create);
  ARegistry.Register(THandleLeakRule.Create);
  ARegistry.Register(TOutParamReadRule.Create);
  ARegistry.Register(TNoreturnReturnsRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow', cTexts);

end.
