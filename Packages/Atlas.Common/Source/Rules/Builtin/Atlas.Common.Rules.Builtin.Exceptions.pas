unit Atlas.Common.Rules.Builtin.Exceptions;

// Exception-Regeln (#277, abgetrennt aus #57):
//   generic-exception-raised    raise Exception.Create(…) statt einer eigenen Klasse
//   catch-all-without-raise     on E: Exception do ohne raise; nur für Bibliothekscode,
//                               deshalb Standard aus und über Profile/Pfadregeln einzuschalten (#146)
//   exception-freed             Exception-Objekt nach raise bzw. im Handler zusätzlich freigegeben
//   exception-in-destructor     raise in einem Destruktor, das kein except im Destruktor abfängt (#927)
//   except-handler-order        on-Handler, der nie erreicht wird, weil ein früherer die Klasse schon fängt (#957)
//   reraise-exception-object    raise E im Handler statt raise; (#958)
//   reraise-outside-handler     raise; ohne Argument außerhalb eines except-Blocks (#985, wie E2145,
//                               Gruppe Compiler vorab). Routinen und anonyme Methoden beginnen neu; in einer
//                               anonymen Methode innerhalb eines except bleibt die Regel still, ebenso in
//                               Routinen, in denen der Parser einen Fehler meldet.
//   inherited-constructor-after-try  try im Konstruktor vor dem geerbten Konstruktor, Self noch nicht
//                               initialisiert (wie H2505, #1027); ergänzt missing-inherited. Zweige von
//                               {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander
// Der leere except-Block bleibt bei empty-except (#56).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TGenericExceptionRaisedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCatchAllWithoutRaiseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionInDestructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptHandlerOrderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorfahr einer bekannten RTL-, VCL- oder FireDAC-Exception; leer, wenn unbekannt.</summary>
    class function KnownParent(const AName: string): string; static;
  end;

  TReraiseExceptionObjectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TReraiseOutsideHandlerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInheritedConstructorAfterTryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Exception-Regeln.</summary>
procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TExceptionsText = (GenericTitle, Generic, CatchAllTitle, CatchAll, FreedTitle, OwnedByHandler, OwnedByRtl,
    DestructorTitle, InheritedSkipped, LeavesDestructor, OrderTitle, MoveBefore, AlreadyHandled, AncestorHandled,
    ReraiseTitle, ReplaceRaise, Reraise, BareRaiseTitle, BareRaise, TryTitle, MoveBeforeTry, TryBeforeInherited);

const
  cTexts: array[TExceptionsText] of TAtlasText = (
    (De: 'raise Exception statt einer eigenen Exception-Klasse';
     En: 'raise Exception instead of an own exception class'),
    (De: 'raise Exception lässt sich nicht gezielt abfangen; eine eigene Klasse (z. B. EKundeNichtGefunden = ' +
      'class(Exception)) oder eine passende der RTL verwenden';
     En: 'raise Exception cannot be caught specifically; use an own class (e.g. ECustomerNotFound = ' +
      'class(Exception)) or a suitable one from the RTL'),
    (De: 'on E: Exception do ohne raise'; En: 'on E: Exception do without raise'),
    (De: 'Bibliothekscode fängt jede Exception ab, ohne sie weiterzuwerfen; der Aufrufer erfährt nichts vom Fehler. ' +
      'Gezielt abfangen oder mit raise weiterwerfen';
     En: 'Library code catches every exception without re-raising it; the caller learns nothing about the error. ' +
      'Catch specifically or re-raise with raise'),
    (De: 'Exception-Objekt nach raise zusätzlich freigegeben'; En: 'Exception object additionally freed after raise'),
    (De: '%s gehört nach dem Handler der RTL und wird dort freigegeben; eigenes Freigeben führt zur doppelten Freigabe';
     En: '%s belongs to the handler of the RTL after it and is freed there; freeing it yourself leads to a double ' +
      'free'),
    (De: '%s wird mit raise ausgelöst und gehört dann der RTL; zusätzliches Freigeben führt zur doppelten Freigabe';
     En: '%s is raised with raise and then belongs to the RTL; freeing it additionally leads to a double free'),
    (De: 'raise im Destruktor'; En: 'raise in the destructor'),
    (De: 'raise im Destruktor: inherited %s läuft nicht mehr, Felder bleiben liegen.';
     En: 'raise in the destructor: inherited %s no longer runs, fields are left behind.'),
    (De: 'raise im Destruktor: die Ausnahme verlässt %s, der Aufrufer erwartet eine Freigabe ohne Ausnahme.';
     En: 'raise in the destructor: the exception leaves %s, the caller expects freeing without an exception.'),
    (De: 'Allgemeiner Exception-Handler vor speziellem'; En: 'General exception handler before a specific one'),
    (De: 'on %s vor on %s verschieben'; En: 'Move on %s before on %s'),
    (De: 'Nie erreicht: %s wird schon in Zeile %d behandelt.'; En: 'Never reached: %s is already handled in line %d.'),
    (De: 'Nie erreicht: %s ist ein Nachfahr von %s, das schon in Zeile %d behandelt wird.';
     En: 'Never reached: %s is a descendant of %s, which is already handled in line %d.'),
    (De: 'raise E statt raise im Handler'; En: 'raise E instead of raise in the handler'),
    (De: 'raise %s; durch raise; ersetzen'; En: 'Replace raise %s; with raise;'),
    (De: 'raise %s löst das Objekt neu aus: Absprungstelle (ExceptAddr) und Aufrufliste zeigen danach auf diesen ' +
      'Handler statt auf den ursprünglichen Fehler; raise; wirft die Exception unverändert weiter.';
     En: 'raise %s raises the object again: the exception address (ExceptAddr) and the call stack then point to this ' +
      'handler instead of the original error; raise; re-raises the exception unchanged.'),
    (De: 'raise ohne Argument außerhalb eines except-Blocks'; En: 'raise without argument outside an except block'),
    (De: 'raise ohne Argument ist nur in einem except-Block erlaubt (wie E2145).';
     En: 'raise without argument is only allowed in an except block (like E2145).'),
    (De: 'Geerbter Konstruktor erst nach try'; En: 'Inherited constructor only after try'),
    (De: '%s vor try ziehen'; En: 'Move %s before try'),
    (De: 'try vor dem Aufruf des geerbten Konstruktors; Self ist noch nicht initialisiert (wie H2505).';
     En: 'try before the call of the inherited constructor; Self is not initialized yet (like H2505).'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Exception-Handler "on [Name:] Typ do Anweisung".</summary>
  THandler = record
    OnToken: Integer;
    DoToken: Integer;
    /// <summary>Name der Handler-Variablen; '' bei "on Typ do".</summary>
    Name: string;
    TypeName: string;
    /// <summary>Erstes und letztes Token der Anweisung hinter do.</summary>
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm');
end;

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  mIndex := AFirst;
  Result := AFirst;
  while mIndex <= High(ATokens) do
  begin
    if OpensBlock(ATokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsKeyword('end') then
    begin
      if mDepth = 0 then
      begin
        Exit;
      end;
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end
    else if (mDepth = 0) and (ATokens[mIndex].IsSymbol(';') or ATokens[mIndex].IsKeyword('else')) then
    begin
      Exit;
    end;
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Liest ab ANext den Typ eines Handlers (auch qualifiziert: System.SysUtils.Exception) bis zum do;
/// False, wenn dort kein Typ mit do steht.</summary>
function ReadHandlerType(const ATokens: TTokens; ANext: Integer; var AHandler: THandler): Boolean;
begin
  Result := (ANext <= High(ATokens)) and (ATokens[ANext].Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  AHandler.TypeName := ATokens[ANext].Text;
  AHandler.DoToken := NextCode(ATokens, ANext + 1);
  while (AHandler.DoToken < High(ATokens)) and ATokens[AHandler.DoToken].IsSymbol('.') do
  begin
    AHandler.TypeName := ATokens[NextCode(ATokens, AHandler.DoToken + 1)].Text;
    AHandler.DoToken := NextCode(ATokens, NextCode(ATokens, AHandler.DoToken + 1) + 1);
  end;
  Result := (AHandler.DoToken <= High(ATokens)) and ATokens[AHandler.DoToken].IsKeyword('do');
end;

/// <summary>Liest den Handler "on [Name :] Typ do Anweisung" ab dem Token AIndex (on); False, wenn dort keiner
/// steht.</summary>
function ReadHandler(const ATokens: TTokens; AIndex: Integer; out AHandler: THandler): Boolean;
var
  mNext, mColon: Integer;
begin
  AHandler := Default(THandler);
  AHandler.OnToken := AIndex;
  mNext := NextCode(ATokens, AIndex + 1);
  mColon := NextCode(ATokens, mNext + 1);
  Result := mColon <= High(ATokens);
  if Result and ATokens[mColon].IsSymbol(':') then
  begin
    AHandler.Name := ATokens[mNext].Text;
    mNext := NextCode(ATokens, mColon + 1);
  end;
  Result := Result and ReadHandlerType(ATokens, mNext, AHandler);
  if Result then
  begin
    AHandler.First := NextCode(ATokens, AHandler.DoToken + 1);
    Result := AHandler.First <= High(ATokens);
  end;
  if Result then
  begin
    AHandler.Last := StatementEnd(ATokens, AHandler.First);
  end;
end;

function Handlers(const ATokens: TTokens): TArray<THandler>;
var
  mIndex: Integer;
  mHandler: THandler;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    // "on" ist kein reserviertes Wort; im except-Teil folgt Name : Typ do oder Typ do.
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, 'on') and
      ReadHandler(ATokens, mIndex, mHandler) then
    begin
      Result := Result + [mHandler];
    end;
  end;
end;

/// <summary>Gibt Token AIndex den Namen AName frei: AName.Free, AName.Destroy, FreeAndNil(AName)?</summary>
function IsFreeOf(const ATokens: TTokens; AIndex: Integer; const AName: string): Boolean;
var
  mDot, mMethod, mOpen, mArg: Integer;
begin
  Result := False;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  if SameText(ATokens[AIndex].Text, AName) then
  begin
    mDot := NextCode(ATokens, AIndex + 1);
    mMethod := NextCode(ATokens, mDot + 1);
    Result := (mMethod <= High(ATokens)) and ATokens[mDot].IsSymbol('.') and
      MatchText(ATokens[mMethod].Text, ['Free', 'Destroy', 'DisposeOf']) and
      ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
  end
  else if SameText(ATokens[AIndex].Text, 'FreeAndNil') then
  begin
    mOpen := NextCode(ATokens, AIndex + 1);
    mArg := NextCode(ATokens, mOpen + 1);
    Result := (mArg < High(ATokens)) and ATokens[mOpen].IsSymbol('(') and SameText(ATokens[mArg].Text, AName) and
      ATokens[NextCode(ATokens, mArg + 1)].IsSymbol(')');
  end;
end;

{ TGenericExceptionRaisedRule }

function TGenericExceptionRaisedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('generic-exception-raised', TRuleSeverity.Hint,
    cTexts[TExceptionsText.GenericTitle].Text);
end;

procedure TGenericExceptionRaisedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex, mName, mDot, mCtor: Integer;
  mCaught: TArray<THandler>;
  // Handler schon gelesen? Caught = nil heißt auch "keine on-Handler"; ohne eigenen Merker las die Regel dann
  // für jedes raise Exception.Create alle Token der Unit neu (quadratisch in großen Units).
  mCaughtRead: Boolean;

  // Die raise-Anweisung, die bei AOffset beginnt; nil, wenn keine.
  function RaiseAt(AOffset: Integer): TSyntaxNode;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mChild: Integer;
  begin
    Result := nil;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while (mPending.Count > 0) and (Result = nil) do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.RaiseStatement) and (mNode.StartOffset = AOffset) then
        begin
          Result := mNode;
        end
        else if (mNode.StartOffset <= AOffset) and (mNode.EndOffset >= AOffset) then
        begin
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Fängt der except-Teil AExcept jede Exception: on Exception, on TObject oder gar kein on?
  function CatchesAll(AExcept: TSyntaxNode): Boolean;
  var
    mHandler: THandler;
    mAnyOn: Boolean;
  begin
    Result := False;
    mAnyOn := False;
    for mHandler in mCaught do
    begin
      if (mTokens[mHandler.OnToken].Offset >= AExcept.StartOffset) and
        (mTokens[mHandler.OnToken].Offset < AExcept.EndOffset) then
      begin
        mAnyOn := True;
        Result := Result or MatchText(mHandler.TypeName, ['Exception', 'TObject']);
      end;
    end;
    // except ohne on fängt alles.
    Result := Result or not mAnyOn;
  end;

  // raise direkt im try-Teil, dessen except alles fängt: Die Exception verlässt die Routine nie; oft nur, um einen
  // Stack für das Protokoll zu bekommen (#1109).
  function CaughtRightThere(AOffset: Integer): Boolean;
  var
    mRaise, mExcept: TSyntaxNode;
  begin
    mRaise := RaiseAt(AOffset);
    Result := (mRaise <> nil) and (mRaise.Parent <> nil) and (mRaise.Parent.Kind = TSyntaxKind.TryStatement);
    if Result then
    begin
      mExcept := mRaise.Parent.FindChild(TSyntaxKind.ExceptBlock);
      Result := (mExcept <> nil) and CatchesAll(mExcept);
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCaughtRead := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if not mTokens[mIndex].IsKeyword('raise') then
    begin
      Continue;
    end;
    mName := NextCode(mTokens, mIndex + 1);
    // raise SysUtils.Exception.Create bzw. System.SysUtils.Exception.Create
    while (mName + 2 <= High(mTokens)) and MatchText(mTokens[mName].Text, ['System', 'SysUtils']) and
      mTokens[NextCode(mTokens, mName + 1)].IsSymbol('.') do
    begin
      mName := NextCode(mTokens, NextCode(mTokens, mName + 1) + 1);
    end;
    mDot := NextCode(mTokens, mName + 1);
    mCtor := NextCode(mTokens, mDot + 1);
    if (mCtor > High(mTokens)) or not SameText(mTokens[mName].Text, 'Exception') or not mTokens[mDot].IsSymbol('.') or
      not StartsText('Create', mTokens[mCtor].Text) then
    begin
      Continue;
    end;
    if not mCaughtRead then
    begin
      mCaught := Handlers(mTokens);
      mCaughtRead := True;
    end;
    if CaughtRightThere(mTokens[mIndex].Offset) then
    begin
      Continue;
    end;
    AReport.Add(RangeOf(mTokens, mIndex, mCtor), cTexts[TExceptionsText.Generic].Text,
      TRuleConfidence.High);
  end;
end;

{ TCatchAllWithoutRaiseRule }

function TCatchAllWithoutRaiseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('catch-all-without-raise', TRuleSeverity.Warning,
    cTexts[TExceptionsText.CatchAllTitle].Text, True);
end;

procedure TCatchAllWithoutRaiseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mHandler: THandler;
  mIndex: Integer;
  mRaises: Boolean;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mHandler in Handlers(mTokens) do
  begin
    if not MatchText(mHandler.TypeName, ['Exception', 'TObject']) then
    begin
      Continue;
    end;
    mRaises := False;
    for mIndex := mHandler.First to mHandler.Last do
    begin
      if mTokens[mIndex].IsKeyword('raise') then
      begin
        mRaises := True;
      end;
    end;
    if not mRaises then
    begin
      AReport.Add(RangeOf(mTokens, mHandler.OnToken, mHandler.DoToken), cTexts[TExceptionsText.CatchAll].Text,
        TRuleConfidence.Medium);
    end;
  end;
end;

{ TExceptionFreedRule }

function TExceptionFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-freed', TRuleSeverity.Error,
    cTexts[TExceptionsText.FreedTitle].Text);
end;

/// <summary>Erstes und letztes Token der Routine, in der Token AIndex liegt; False ohne.</summary>
function RoutineSpan(ATree: TSyntaxTree; const ATokens: TTokens; AIndex: Integer;
  out AFirst, ALast: Integer): Boolean;
var
  mBest: TSyntaxNode;
  mIndex, mOffset: Integer;
begin
  mBest := nil;
  mOffset := ATokens[AIndex].Offset;
  // Iterativ (Bericht M1); die letzte passende Routine in Baumreihenfolge ist die innerste.
  if ATree.Root <> nil then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.StartOffset <= mOffset) and
          (ANode.EndOffset > mOffset) then
        begin
          mBest := ANode;
        end;
        Result := True;
      end);
  end;
  Result := mBest <> nil;
  if not Result then
  begin
    Exit;
  end;
  AFirst := AIndex;
  ALast := AIndex;
  // Nur die Token von Best, binär angesprungen statt die ganze Datei (#1342).
  mIndex := TSyntaxTree.FirstTokenOf(ATokens, mBest.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < mBest.EndOffset) do
  begin
    if mIndex < AFirst then
    begin
      AFirst := mIndex;
    end;
    if mIndex > ALast then
    begin
      ALast := mIndex;
    end;
    Inc(mIndex);
  end;
end;

procedure TExceptionFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mDone: TArray<Integer>;

  function Reported(AToken: Integer): Boolean;
  var
    mItem: Integer;
  begin
    for mItem in mDone do
    begin
      if mItem = AToken then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Im Handler: on E: Exception do … E.Free; die RTL gibt E nach dem Handler selbst frei.
  procedure CheckHandlers;
  var
    mHandler: THandler;
    mIndex: Integer;
  begin
    for mHandler in Handlers(mTokens) do
    begin
      if mHandler.Name = '' then
      begin
        Continue;
      end;
      for mIndex := mHandler.First to mHandler.Last do
      begin
        if IsFreeOf(mTokens, mIndex, mHandler.Name) then
        begin
          mDone := mDone + [mIndex];
          AReport.Add(RangeOf(mTokens, mIndex, mIndex), cTexts[TExceptionsText.OwnedByHandler].Fmt([mHandler.Name]),
            TRuleConfidence.High);
        end;
      end;
    end;
  end;

  // Token des Namens X bei "raise X;" bzw. "raise X end" für das Token AIndex; -1 sonst.
  function RaisedName(AIndex: Integer): Integer;
  var
    mStop: Integer;
  begin
    Result := -1;
    if not mTokens[AIndex].IsKeyword('raise') then
    begin
      Exit;
    end;
    Result := NextCode(mTokens, AIndex + 1);
    mStop := NextCode(mTokens, Result + 1);
    if (mStop > High(mTokens)) or (mTokens[Result].Kind <> TPascalTokenKind.Identifier) or
      not (mTokens[mStop].IsSymbol(';') or mTokens[mStop].IsKeyword('end')) then
    begin
      Result := -1;
    end;
  end;

  // raise X; … X.Free in derselben Routine: Nach raise gehört das Objekt der RTL.
  procedure CheckRaised(AIndex, AName: Integer);
  var
    mInner, mFirst, mLast: Integer;
  begin
    if not RoutineSpan(AContext.Tree, mTokens, AIndex, mFirst, mLast) then
    begin
      Exit;
    end;
    for mInner := mFirst to mLast do
    begin
      if IsFreeOf(mTokens, mInner, mTokens[AName].Text) and not Reported(mInner) then
      begin
        mDone := mDone + [mInner];
        AReport.Add(RangeOf(mTokens, mInner, mInner), cTexts[TExceptionsText.OwnedByRtl].Fmt([mTokens[AName].Text]),
          TRuleConfidence.High);
        Break;
      end;
    end;
  end;

var
  mIndex, mName: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mDone := nil;
  CheckHandlers;
  for mIndex := 0 to High(mTokens) do
  begin
    mName := RaisedName(mIndex);
    if mName >= 0 then
    begin
      CheckRaised(mIndex, mName);
    end;
  end;
end;

{ TExceptionInDestructorRule }

function TExceptionInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-in-destructor', TRuleSeverity.Warning,
    cTexts[TExceptionsText.DestructorTitle].Text);
end;

procedure TExceptionInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRoutineName: string;
  // Offset des ersten inherited im Destruktor; MaxInt ohne.
  mInheritedOffset: Integer;

  function RoutineText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function IsDestructor(ARoutine: TSyntaxNode): Boolean;
  var
    mHead: string;
  begin
    mHead := RoutineText(ARoutine);
    if StartsText('class', mHead) then
    begin
      mHead := TrimLeft(Copy(mHead, Length('class') + 1, MaxInt));
    end;
    Result := StartsText('destructor', mHead) and ((Length(mHead) = Length('destructor')) or
      CharInSet(mHead[Length('destructor') + 1], [' ', #9, #10, #13]));
  end;

  // Erstes inherited im Destruktor, ohne eingebettete Routinen und anonyme Methoden.
  procedure FindInherited(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.InheritedExpr) and (mNode.StartOffset < mInheritedOffset) then
        begin
          mInheritedOffset := mNode.StartOffset;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure ReportRaise(ANode: TSyntaxNode);
  var
    mMessage: string;
  begin
    if ANode.StartOffset < mInheritedOffset then
    begin
      mMessage := cTexts[TExceptionsText.InheritedSkipped].Fmt([mRoutineName]);
    end
    else
    begin
      mMessage := cTexts[TExceptionsText.LeavesDestructor].Fmt([mRoutineName]);
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
      ANode.StartPos.Character + Length('raise'))), mMessage, TRuleConfidence.High);
  end;

  // Active: eine Ausnahme an dieser Stelle verlässt den Destruktor.
  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mChild: TSyntaxNode;
    mActive, mCaught: Boolean;
    mPending: TStack<TSyntaxNode>;
    mPendingActive: TStack<Boolean>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    mPendingActive := TStack<Boolean>.Create;
    try
      mPending.Push(ARoot);
      mPendingActive.Push(True);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mActive := mPendingActive.Pop;
        if (mNode.Kind = TSyntaxKind.RaiseStatement) and mActive then
        begin
          ReportRaise(mNode);
        end;
        if mNode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl, TSyntaxKind.RaiseStatement] then
        begin
          Continue;
        end;
        // Im try-Teil fängt ein eigenes except die Ausnahme ab; except- und finally-Teil nicht.
        mCaught := (mNode.Kind = TSyntaxKind.TryStatement) and (mNode.FindChild(TSyntaxKind.ExceptBlock) <> nil);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mChild := mNode[mIndex];
          mPending.Push(mChild);
          mPendingActive.Push(mActive and (not mCaught or
            (mChild.Kind in [TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock])));
        end;
      end;
    finally
      mPendingActive.Free;
      mPending.Free;
    end;
  end;

  procedure Search(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mBody: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.RoutineDecl) and IsDestructor(mNode) then
        begin
          mRoutineName := mNode.Name;
          if LastDelimiter('.', mRoutineName) > 0 then
          begin
            mRoutineName := Copy(mRoutineName, LastDelimiter('.', mRoutineName) + 1, MaxInt);
          end;
          mBody := mNode.FindChild(TSyntaxKind.Block);
          if mBody <> nil then
          begin
            mInheritedOffset := MaxInt;
            FindInherited(mBody);
            Visit(mBody);
          end;
        end;
        // Auch eingebettete Routinen und Klassen in Routinen.
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    Search(AContext.Tree.Root);
  end;
end;

{ TExceptHandlerOrderRule }

const
  // Vorfahren bekannter RTL-, VCL- und FireDAC-Exceptions (Klasse=Vorfahr), wenn der Index sie nicht kennt.
  cKnownExceptionParents: array[0..39] of string = (
    'EAbort=Exception', 'EConvertError=Exception', 'EInOutError=Exception', 'EOSError=Exception',
    'EInvalidCast=Exception', 'EInvalidPointer=EHeapException', 'EOutOfMemory=EHeapException',
    'EHeapException=Exception', 'EExternal=Exception', 'EAccessViolation=EExternal', 'EIntError=EExternal',
    'EDivByZero=EIntError', 'ERangeError=EIntError', 'EIntOverflow=EIntError', 'EMathError=EExternal',
    'EInvalidOp=EMathError', 'EZeroDivide=EMathError', 'EOverflow=EMathError', 'EUnderflow=EMathError',
    'EArgumentException=Exception', 'EArgumentOutOfRangeException=EArgumentException',
    'EArgumentNilException=EArgumentException', 'ENotImplemented=Exception', 'ENotSupportedException=Exception',
    'EListError=Exception', 'EStringListError=EListError', 'EStreamError=Exception',
    'EFileStreamError=EStreamError', 'EFOpenError=EFileStreamError', 'EFCreateError=EFileStreamError',
    'EFilerError=EStreamError', 'EReadError=EFilerError', 'EWriteError=EFilerError',
    'EVariantError=Exception', 'EDatabaseError=Exception', 'EFDException=EDatabaseError',
    'EFDDBEngineException=EFDException', 'EEncodingError=Exception', 'EJSONException=Exception',
    'EComponentError=Exception');

function TExceptHandlerOrderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('except-handler-order', TRuleSeverity.Warning,
    cTexts[TExceptionsText.OrderTitle].Text);
end;

class function TExceptHandlerOrderRule.KnownParent(const AName: string): string;
var
  mEntry: string;
begin
  for mEntry in cKnownExceptionParents do
  begin
    if SameText(Copy(mEntry, 1, Pos('=', mEntry) - 1), AName) then
    begin
      Exit(Copy(mEntry, Pos('=', mEntry) + 1, MaxInt));
    end;
  end;
  Result := '';
end;

procedure TExceptHandlerOrderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAncestry: TAncestry;
  mLines: TArray<string>;
  mLineBreak: string;

  function TypeOf(AHandler: TSyntaxNode): string;
  var
    mReference: TSyntaxNode;
  begin
    Result := '';
    mReference := AHandler.FindChild(TSyntaxKind.TypeReference);
    if mReference <> nil then
    begin
      Result := Copy(mReference.Name, LastDelimiter('.', mReference.Name) + 1, MaxInt);
    end;
  end;

  // Fängt ein Handler für AGeneral auch ASpecial? Über die Datei, den Index und die Tabelle bekannter Klassen.
  function Covers(const AGeneral, ASpecial: string): Boolean;
  var
    mCurrent, mParent: string;
    mSteps: Integer;
  begin
    if SameText(AGeneral, 'TObject') then
    begin
      Exit(True);
    end;
    // Alles, was als Exception ausgelöst wird, erbt in der Praxis von Exception.
    if SameText(AGeneral, 'Exception') and not SameText(ASpecial, 'TObject') then
    begin
      Exit(True);
    end;
    mCurrent := ASpecial;
    for mSteps := 1 to 16 do
    begin
      mParent := mAncestry.ParentOf(mCurrent);
      if (mParent = '') or SameText(mParent, 'TObject') then
      begin
        mParent := KnownParent(mCurrent);
      end;
      if mParent = '' then
      begin
        Exit(False);
      end;
      if SameText(mParent, AGeneral) then
      begin
        Exit(True);
      end;
      mCurrent := mParent;
    end;
    Result := False;
  end;

  // Steht der Handler allein auf seinen Zeilen (davor Einrückung, danach höchstens ";")?
  function OwnLines(AHandler: TSyntaxNode): Boolean;
  var
    mRest: string;
  begin
    mRest := Trim(Copy(mLines[AHandler.EndPos.Line], AHandler.EndPos.Character + 1, MaxInt));
    Result := (Trim(Copy(mLines[AHandler.StartPos.Line], 1, AHandler.StartPos.Character)) = '') and
      ((mRest = '') or (mRest = ';')) and (AHandler.EndPos.Line < High(mLines));
  end;

  // Korrektur: den speziellen Handler vor den allgemeinen verschieben.
  function MoveFix(AGeneral, ASpecial: TSyntaxNode): TArray<TRuleFix>;
  var
    mLine: Integer;
    mText: string;
  begin
    Result := nil;
    if not OwnLines(AGeneral) or not OwnLines(ASpecial) or (AGeneral.EndPos.Line >= ASpecial.StartPos.Line) then
    begin
      Exit;
    end;
    mText := '';
    for mLine := ASpecial.StartPos.Line to ASpecial.EndPos.Line do
    begin
      mText := mText + mLines[mLine] + mLineBreak;
    end;
    // Der letzte Handler darf ohne Semikolon stehen; vor einem anderen braucht er eines.
    if Trim(Copy(mLines[ASpecial.EndPos.Line], ASpecial.EndPos.Character + 1, MaxInt)) = '' then
    begin
      mText := Copy(mText, 1, Length(mText) - Length(mLineBreak)) + ';' + mLineBreak;
    end;
    Result := [TRuleFix.Create(cTexts[TExceptionsText.MoveBefore].Fmt([TypeOf(ASpecial), TypeOf(AGeneral)]), [
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(AGeneral.StartPos.Line, 0),
        TTextPosition.Create(AGeneral.StartPos.Line, 0)), mText),
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ASpecial.StartPos.Line, 0),
        TTextPosition.Create(ASpecial.EndPos.Line + 1, 0)), '')])];
  end;

  // Meldet den Handler AHandlers[AIndex], wenn ein früherer seinen Typ schon fängt.
  procedure CheckHandler(const AHandlers: TArray<TSyntaxNode>; AIndex: Integer);
  var
    mEarlier: Integer;
    mGeneral, mSpecial: string;
    mRange: TTextRange;
    mReference: TSyntaxNode;
  begin
    mSpecial := TypeOf(AHandlers[AIndex]);
    if mSpecial = '' then
    begin
      Exit;
    end;
    for mEarlier := 0 to AIndex - 1 do
    begin
      mGeneral := TypeOf(AHandlers[mEarlier]);
      if mGeneral = '' then
      begin
        Continue;
      end;
      mReference := AHandlers[AIndex].FindChild(TSyntaxKind.TypeReference);
      mRange := TTextRange.Create(mReference.StartPos, mReference.EndPos);
      if SameText(mGeneral, mSpecial) then
      begin
        AReport.Add(mRange, cTexts[TExceptionsText.AlreadyHandled].Fmt(
          [mSpecial, AHandlers[mEarlier].StartPos.Line + 1]));
        Exit;
      end;
      if Covers(mGeneral, mSpecial) then
      begin
        AReport.Add(mRange, cTexts[TExceptionsText.AncestorHandled].Fmt([mSpecial, mGeneral,
          AHandlers[mEarlier].StartPos.Line + 1]),
          MoveFix(AHandlers[mEarlier], AHandlers[AIndex]));
        Exit;
      end;
    end;
  end;

  procedure CheckBlock(ABlock: TSyntaxNode);
  var
    mHandlers: TArray<TSyntaxNode>;
    mIndex: Integer;
  begin
    mHandlers := nil;
    for mIndex := 0 to ABlock.ChildCount - 1 do
    begin
      if ABlock[mIndex].Kind = TSyntaxKind.ExceptionHandler then
      begin
        mHandlers := mHandlers + [ABlock[mIndex]];
      end;
    end;
    for mIndex := 1 to High(mHandlers) do
    begin
      CheckHandler(mHandlers, mIndex);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.ExceptBlock then
        begin
          CheckBlock(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'except') then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    mAncestry.Free;
  end;
end;

{ TReraiseExceptionObjectRule }

function TReraiseExceptionObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('reraise-exception-object', TRuleSeverity.Warning,
    cTexts[TExceptionsText.ReraiseTitle].Text);
end;

procedure TReraiseExceptionObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mDone: TArray<Integer>;

  // Übernimmt der Handler das Objekt selbst (AcquireExceptionObject) oder weist er der Variablen neu zu?
  function OwnsObject(const AHandler: THandler): Boolean;
  var
    mPosition: Integer;
  begin
    for mPosition := AHandler.First to AHandler.Last do
    begin
      if SameText(mTokens[mPosition].Text, 'AcquireExceptionObject') or
        (SameText(mTokens[mPosition].Text, AHandler.Name) and
        mTokens[NextCode(mTokens, mPosition + 1)].IsSymbol(':=')) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Liegt das raise in einer anonymen Methode innerhalb des Handlers?
  function InAnonymousMethod(const AHandler: THandler; ARaise: Integer): Boolean;
  var
    mPosition: Integer;
  begin
    for mPosition := AHandler.First to ARaise do
    begin
      if mTokens[mPosition].IsKeyword('procedure') or mTokens[mPosition].IsKeyword('function') then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function Reported(AToken: Integer): Boolean;
  var
    mItem: Integer;
  begin
    for mItem in mDone do
    begin
      if mItem = AToken then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Meldet "raise E" beim Token AIndex im Handler AHandler.
  procedure CheckRaise(const AHandler: THandler; AIndex: Integer);
  var
    mName, mStop: Integer;
    mFixes: TArray<TRuleFix>;
  begin
    mName := NextCode(mTokens, AIndex + 1);
    mStop := NextCode(mTokens, mName + 1);
    if (mStop > High(mTokens)) or not SameText(mTokens[mName].Text, AHandler.Name) or
      InAnonymousMethod(AHandler, AIndex) then
    begin
      Exit;
    end;
    // raise E; raise E end; raise E else; raise E at Adresse (ohne Korrektur).
    mFixes := nil;
    if mTokens[mStop].IsSymbol(';') or mTokens[mStop].IsKeyword('end') or mTokens[mStop].IsKeyword('else') then
    begin
      mFixes := [TRuleFix.Create(cTexts[TExceptionsText.ReplaceRaise].Fmt([AHandler.Name]),
        [TRuleEdit.Create(RangeOf(mTokens, AIndex, mName), 'raise')])];
    end
    else if not SameText(mTokens[mStop].Text, 'at') then
    begin
      Exit;
    end;
    mDone := mDone + [AIndex];
    AReport.Add(RangeOf(mTokens, AIndex, mName), cTexts[TExceptionsText.Reraise].Fmt([AHandler.Name]),
      TRuleConfidence.High, mFixes);
  end;

var
  mHandler: THandler;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'raise') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mDone := nil;
  for mHandler in Handlers(mTokens) do
  begin
    if (mHandler.Name = '') or OwnsObject(mHandler) then
    begin
      Continue;
    end;
    for mIndex := mHandler.First to mHandler.Last do
    begin
      if mTokens[mIndex].IsKeyword('raise') and not Reported(mIndex) then
      begin
        CheckRaise(mHandler, mIndex);
      end;
    end;
  end;
end;

{ TReraiseOutsideHandlerRule }

function TReraiseOutsideHandlerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('reraise-outside-handler', TRuleSeverity.Error,
    cTexts[TExceptionsText.BareRaiseTitle].Text);
end;

procedure TReraiseOutsideHandlerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  // Hat der Parser im Bereich von AScope einen Fehler gemeldet (nil: irgendwo)?
  function Broken(AScope: TSyntaxNode): Boolean;
  var
    mDiagnostic: TSyntaxDiagnostic;
  begin
    for mDiagnostic in AContext.Tree.Diagnostics do
    begin
      if (AScope = nil) or ((mDiagnostic.StartPos.Line >= AScope.StartPos.Line) and
        (mDiagnostic.StartPos.Line <= AScope.EndPos.Line)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Passt Bereich AScope und Zustand an den Knoten ANode an und meldet ein raise ohne Argument außerhalb von
  // except.
  procedure Enter(ANode: TSyntaxNode; var AScope: TSyntaxNode; var AInExcept, AUnknown: Boolean);
  begin
    case ANode.Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection,
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
        begin
          AScope := ANode;
          AInExcept := False;
          AUnknown := False;
        end;
      TSyntaxKind.AnonymousMethod:
        begin
          AScope := ANode;
          AUnknown := AUnknown or AInExcept;
          AInExcept := False;
        end;
      TSyntaxKind.ExceptBlock:
        AInExcept := True;
      TSyntaxKind.RaiseStatement:
        if (ANode.ChildCount = 0) and not AInExcept and not AUnknown and not Broken(AScope) then
        begin
          AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
            ANode.StartPos.Character + Length('raise'))),
            cTexts[TExceptionsText.BareRaise].Text, TRuleConfidence.High);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  // InExcept: ein except der Routine umschließt die Stelle; Unknown: anonyme Methode in einem except.
  procedure Visit(ARoot: TSyntaxNode);
  const
    cInExceptFlag = 1;
    cUnknownFlag = 2;
  var
    mIndex, mFlags: Integer;
    mNode, mScope: TSyntaxNode;
    mInExcept, mUnknown: Boolean;
    mPending, mPendingScope: TStack<TSyntaxNode>;
    mPendingFlags: TStack<Integer>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    mPendingScope := TStack<TSyntaxNode>.Create;
    mPendingFlags := TStack<Integer>.Create;
    try
      mPending.Push(ARoot);
      mPendingScope.Push(nil);
      mPendingFlags.Push(0);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mScope := mPendingScope.Pop;
        mFlags := mPendingFlags.Pop;
        mInExcept := (mFlags and cInExceptFlag) <> 0;
        mUnknown := (mFlags and cUnknownFlag) <> 0;
        Enter(mNode, mScope, mInExcept, mUnknown);
        mFlags := 0;
        if mInExcept then
        begin
          mFlags := mFlags or cInExceptFlag;
        end;
        if mUnknown then
        begin
          mFlags := mFlags or cUnknownFlag;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mPendingScope.Push(mScope);
          mPendingFlags.Push(mFlags);
        end;
      end;
    finally
      mPendingFlags.Free;
      mPendingScope.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'raise') then
  begin
    Exit;
  end;
  Visit(AContext.Tree.Root);
end;

{ TInheritedConstructorAfterTryRule }

function TInheritedConstructorAfterTryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('inherited-constructor-after-try', TRuleSeverity.Hint,
    cTexts[TExceptionsText.TryTitle].Text);
end;

/// <summary>Erstes Token ab AOffset (die Tokens sind nach Offset sortiert).</summary>
function TokenAtOffset(const ATokens: TTokens; AOffset: Integer): Integer;
var
  mUpper, mMiddle: Integer;
begin
  Result := 0;
  mUpper := Length(ATokens);
  while Result < mUpper do
  begin
    mMiddle := (Result + mUpper) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mUpper := mMiddle;
    end;
  end;
end;

/// <summary>Knoten unter ARoot in Quelltextreihenfolge, ohne Rekursion (#1094). Mit ASkipRoutines ohne
/// eingebettete Routinen und anonyme Methoden.</summary>
function NodesBelow(ARoot: TSyntaxNode; ASkipRoutines: Boolean): TArray<TSyntaxNode>;
var
  mStack: TArray<TSyntaxNode>;
  mCount, mIndex, mFound: Integer;
  mNode: TSyntaxNode;
begin
  SetLength(Result, 64);
  mFound := 0;
  SetLength(mStack, 64);
  mStack[0] := ARoot;
  mCount := 1;
  while mCount > 0 do
  begin
    Dec(mCount);
    mNode := mStack[mCount];
    if mFound = Length(Result) then
    begin
      SetLength(Result, 2 * mFound);
    end;
    Result[mFound] := mNode;
    Inc(mFound);
    if mCount + mNode.ChildCount > Length(mStack) then
    begin
      SetLength(mStack, 2 * (mCount + mNode.ChildCount));
    end;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if not ASkipRoutines or not (mNode[mIndex].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        mStack[mCount] := mNode[mIndex];
        Inc(mCount);
      end;
    end;
  end;
  SetLength(Result, mFound);
end;

procedure TInheritedConstructorAfterTryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mPaths, mLines: TArray<string>;
  mLineBreak: string;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, TokenAtOffset(mTokens, ANode.StartOffset));
  end;

  function IsConstructor(ARoutine: TSyntaxNode): Boolean;
  var
    mHead: string;
  begin
    // class constructor ruft kein inherited auf; dort gibt es kein Self.
    mHead := TrimLeft(Copy(AContext.Text, ARoutine.StartOffset + 1, Length('constructor') + 1));
    Result := StartsText('constructor', mHead) and (Length(mHead) > Length('constructor')) and
      CharInSet(mHead[Length('constructor') + 1], [' ', #9, #10, #13]);
  end;

  // inherited ohne Namen, mit dem eigenen Namen oder Create…: der geerbte Konstruktor.
  function IsConstructorCall(ANode: TSyntaxNode; const AOwn: string): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.InheritedExpr) and ((ANode.Name = '') or SameText(ANode.Name, AOwn) or
      StartsText('Create', ANode.Name));
  end;

  // Korrektur, wenn der Aufruf die erste Anweisung des try-Teils ist: vor try ziehen.
  function MoveBeforeTry(ATry, ACall: TSyntaxNode): TArray<TRuleFix>;
  var
    mStatement: TSyntaxNode;
    mTryToken, mLast, mSemicolon: Integer;
    mText, mBefore: string;
    mRemoval: TTextRange;
  begin
    Result := nil;
    mStatement := ACall;
    while (mStatement <> nil) and (mStatement.Parent <> ATry) do
    begin
      mStatement := mStatement.Parent;
    end;
    if (mStatement = nil) or (ATry.ChildCount = 0) or (ATry[0] <> mStatement) or
      (mStatement.Kind <> TSyntaxKind.CallStatement) then
    begin
      Exit;
    end;
    mTryToken := TokenAtOffset(mTokens, ATry.StartOffset);
    // Kommentare zwischen try und Aufruf gingen mit dem Verschieben verloren.
    if (mTryToken + 1 > High(mTokens)) or (mTokens[mTryToken + 1].Offset <> mStatement.StartOffset) then
    begin
      Exit;
    end;
    mLast := PreviousCode(mTokens, TokenAtOffset(mTokens, mStatement.EndOffset));
    mSemicolon := NextCode(mTokens, mLast + 1);
    mRemoval := TTextRange.Create(mTokens[mTryToken].EndPos, mTokens[mLast].EndPos);
    if (mSemicolon <= High(mTokens)) and mTokens[mSemicolon].IsSymbol(';') then
    begin
      mRemoval.EndPos := mTokens[mSemicolon].EndPos;
    end;
    mText := Copy(AContext.Text, mStatement.StartOffset + 1, mStatement.EndOffset - mStatement.StartOffset);
    mBefore := Trim(Copy(mLines[mTokens[mTryToken].StartPos.Line], 1, mTokens[mTryToken].StartPos.Character));
    if mBefore = '' then
    begin
      mText := mText + ';' + mLineBreak + TTextLines.IndentOf(mLines[mTokens[mTryToken].StartPos.Line]);
    end
    else
    begin
      mText := mText + '; ';
    end;
    Result := [TRuleFix.Create(cTexts[TExceptionsText.MoveBeforeTry].Fmt([Trim(Copy(AContext.Text, ACall.StartOffset +
      1,
      ACall.EndOffset - ACall.StartOffset))]), [TRuleEdit.Create(TTextRange.Create(mTokens[mTryToken].StartPos,
      mTokens[mTryToken].StartPos), mText), TRuleEdit.Create(mRemoval, '')], True)];
  end;

  // Eigener Name des Konstruktors ohne Klasse.
  function OwnName(ARoutine: TSyntaxNode): string;
  begin
    Result := ARoutine.Name;
    if LastDelimiter('.', Result) > 0 then
    begin
      Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
    end;
  end;

  // Aufrufe des geerbten Konstruktors und try-Anweisungen im Rumpf ABody, ohne eingebettete Routinen.
  procedure CollectBody(ABody: TSyntaxNode; const AOwn: string; out ACalls, ATrys: TArray<TSyntaxNode>);
  var
    mNode: TSyntaxNode;
  begin
    ACalls := nil;
    ATrys := nil;
    for mNode in NodesBelow(ABody, True) do
    begin
      if IsConstructorCall(mNode, AOwn) then
      begin
        ACalls := ACalls + [mNode];
      end
      else if mNode.Kind = TSyntaxKind.TryStatement then
      begin
        ATrys := ATrys + [mNode];
      end;
    end;
  end;

  // Erster Aufruf des geerbten Konstruktors nach ATry; nil, wenn einer vor ATry steht oder keiner folgt.
  // Zweige von {$IFDEF}, die sich ausschließen, zählen nicht gegeneinander.
  function CallAfter(ATry: TSyntaxNode; const ATryPath: string; const ACalls: TArray<TSyntaxNode>): TSyntaxNode;
  var
    mCall: TSyntaxNode;
  begin
    Result := nil;
    for mCall in ACalls do
    begin
      if TConditionalBranches.Exclusive(ATryPath, PathOf(mCall)) then
      begin
        Continue;
      end;
      if mCall.StartOffset < ATry.StartOffset then
      begin
        Exit(nil);
      end;
      if Result = nil then
      begin
        Result := mCall;
      end;
    end;
  end;

  // Steht schon ein gemeldetes try in einem Zweig, der sich mit ATryPath nicht ausschließt?
  function ReportedBefore(const ATryPath: string; const AReported: TArray<TSyntaxNode>): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    Result := False;
    for mNode in AReported do
    begin
      Result := Result or not TConditionalBranches.Exclusive(ATryPath, PathOf(mNode));
    end;
  end;

  procedure CheckConstructor(ARoutine: TSyntaxNode);
  var
    mBody, mTry, mAfter: TSyntaxNode;
    mTryPath: string;
    mCalls, mTrys, mReported: TArray<TSyntaxNode>;
  begin
    mBody := ARoutine.FindChild(TSyntaxKind.Block);
    if mBody = nil then
    begin
      Exit;
    end;
    CollectBody(mBody, OwnName(ARoutine), mCalls, mTrys);
    mReported := nil;
    for mTry in mTrys do
    begin
      mTryPath := PathOf(mTry);
      mAfter := CallAfter(mTry, mTryPath, mCalls);
      // Gemeldet wird das erste try; ein späteres nur in einem anderen Zweig.
      if (mAfter = nil) or ReportedBefore(mTryPath, mReported) then
      begin
        Continue;
      end;
      mReported := mReported + [mTry];
      AReport.Add(TTextRange.Create(mTry.StartPos, TTextPosition.Create(mTry.StartPos.Line,
        mTry.StartPos.Character + Length('try'))), cTexts[TExceptionsText.TryBeforeInherited].Text,
          TRuleConfidence.High, MoveBeforeTry(mTry, mAfter));
    end;
  end;

var
  Node: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  for Node in NodesBelow(AContext.Tree.Root, False) do
  begin
    if (Node.Kind = TSyntaxKind.RoutineDecl) and IsConstructor(Node) then
    begin
      CheckConstructor(Node);
    end;
  end;
end;

procedure RegisterExceptionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericExceptionRaisedRule.Create);
  ARegistry.Register(TCatchAllWithoutRaiseRule.Create);
  ARegistry.Register(TExceptionFreedRule.Create);
  ARegistry.Register(TExceptionInDestructorRule.Create);
  ARegistry.Register(TExceptHandlerOrderRule.Create);
  ARegistry.Register(TReraiseExceptionObjectRule.Create);
  ARegistry.Register(TReraiseOutsideHandlerRule.Create);
  ARegistry.Register(TInheritedConstructorAfterTryRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Exceptions', cTexts);

end.
