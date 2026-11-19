unit Atlas.Common.Rules.Builtin.Ownership.CreateOrder;

// Leckregel multiple-create-in-try: mehrere lokale Objekte und ein gemeinsames try … finally, das sie freigibt.
//   Form 1: Die Zuweisungen X := T.Create(…) stehen vor dem try. Scheitert ein späteres Create (oder eine Anweisung
//           dazwischen), ist das frühere Objekt schon da, das try aber noch nicht betreten: Es leckt. Gemeldet am
//           zweiten und jedem weiteren Create.
//   Form 2: Die Zuweisungen stehen im try, und mindestens eine Variable ist vor dem try nicht auf nil gesetzt.
//           Scheitert ein Create, gibt das finally eine nicht gesetzte Variable frei. Gemeldet an ihrer ersten
//           Freigabe.
// Welche Objekte ohne Besitzer sind, entscheidet dieselbe Erkennung wie bei local-object-not-freed
// (TOwnerlessObjects). Korrektur (sicher): alle beteiligten Variablen vor dem try auf nil setzen und die Create in
// den try-Block verschieben; die Reihenfolge der Freigaben bleibt.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cMultipleCreateInTryRuleId = 'multiple-create-in-try';

type
  TMultipleCreateInTryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert multiple-create-in-try.</summary>
procedure RegisterOwnershipCreateOrderRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Rules.Builtin.Ownership.LocalObjects,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TCreateOrderText = (Title, CreateFails, StatementFails, Uninitialized, MoveIntoTry, SetNil, CreateFailsMany,
    StatementFailsMany, UninitializedMany);

const
  cTexts: array[TCreateOrderText] of TAtlasText = (
    (De: 'Mehrere Objekte vor bzw. in einem gemeinsamen try … finally';
     En: 'Several objects before or inside one shared try … finally'),
    (De: 'Scheitert %s.Create, wird %s nicht freigegeben.'; En: 'If %s.Create fails, %s is not freed.'),
    (De: 'Löst eine Anweisung vor dem try eine Ausnahme aus, wird %s nicht freigegeben.';
     En: 'If a statement before the try raises an exception, %s is not freed.'),
    (De: 'Scheitert ein Create im try, gibt das finally die nicht vorbelegte Variable %s frei.';
     En: 'If a Create inside the try fails, the finally frees the unassigned variable %s.'),
    (De: 'Variablen auf nil setzen und Create in das try verschieben';
     En: 'Set the variables to nil and move Create into the try'),
    (De: 'Variablen vor dem try auf nil setzen'; En: 'Set the variables to nil before the try'),
    (De: 'Scheitert %s.Create, werden %s nicht freigegeben.'; En: 'If %s.Create fails, %s are not freed.'),
    (De: 'Löst eine Anweisung vor dem try eine Ausnahme aus, werden %s nicht freigegeben.';
     En: 'If a statement before the try raises an exception, %s are not freed.'),
    (De: 'Scheitert ein Create im try, gibt das finally die nicht vorbelegten Variablen %s frei.';
     En: 'If a Create inside the try fails, the finally frees the unassigned variables %s.'));

{$SCOPEDENUMS OFF}

const
  // Konstruktoren ohne Argumente, die nichts tun, was scheitern kann (außer bei Speichermangel).
  cSafeClasses: array[0..7] of string = ('TObject', 'TMemoryStream', 'TBytesStream', 'TStringBuilder', 'TJSONObject',
    'TJSONArray', 'TInterfaceList', 'TBits');
  // Sammlungen, deren Konstruktoren auch mit Argumenten (Besitz, Kapazität, Vergleicher, Startinhalt) nur Speicher
  // anlegen.
  cSafeCollections: array[0..10] of string = ('TList', 'TObjectList', 'TStringList', 'TDictionary',
    'TObjectDictionary', 'TStack', 'TObjectStack', 'TQueue', 'TObjectQueue', 'THashSet', 'TThreadList');
  // Methoden, die das Objekt freigeben, als X.M bzw. FreeAndNil(X).
  cFreeMembers: array[0..2] of string = ('Free', 'Destroy', 'DisposeOf');

type
  /// <summary>Eine Zuweisung X := T.Create(…) (auch als Inline-Variable) eines Objekts ohne Besitzer.</summary>
  TCreation = record
    Statement: TSyntaxNode;
    Name: string;
    Call: TConstructorCall;
    /// <summary>Inline-Variable var X := …: Typ für die Korrektur (angegeben oder die Klasse).</summary>
    InlineType: string;
  end;

  /// <summary>Ein Lauf von TMultipleCreateInTryRule über eine Unit.</summary>
  TCreateOrderScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FObjects: TOwnerlessObjects;
    FLines: TArray<string>;
    FLineBreak: string;
    FRoutine: TSyntaxNode;
    function LocalDeclaration(const AName: string): TSyntaxNode;
    function IsLocalObject(const AName: string): Boolean;
    function IsKnownObjectVar(const AName: string): Boolean;
    function FreedAssignments(AList: TSyntaxNode; AFirst, ALast: Integer; const AFreed: TArray<string>;
      const ACreations: TArray<TCreation>; out ANames: TArray<string>): Boolean;
    function TryCreation(AStatement: TSyntaxNode; out ACreation: TCreation): Boolean;
    function FreedNames(AFinally: TSyntaxNode): TArray<string>;
    function SetToNilBefore(AList: TSyntaxNode; AIndex: Integer; const AName: string): Boolean;
    function OwnLine(ANode: TSyntaxNode; ATry: Boolean): Boolean;
    function NilLine(const AIndent: string; const ACreation: TCreation): string;
    function MovedText(const ACreations: TArray<TCreation>; AFirstLine, ALastLine: Integer;
      out AText: string): Boolean;
    function MoveFix(const ACreations: TArray<TCreation>; const AOthers: TArray<string>;
      ATry: TSyntaxNode): TArray<TRuleFix>;
    function NilFix(const ANames: TArray<string>; ATry: TSyntaxNode): TArray<TRuleFix>;
    function CreationsBefore(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>;
      out AFirst: Integer): TArray<TCreation>;
    function IsRisky(AList: TSyntaxNode; AIndex, AFirst: Integer; const ACreations: TArray<TCreation>): Boolean;
    procedure ReportBefore(AList: TSyntaxNode; AIndex, AFirst: Integer; const ACreations: TArray<TCreation>;
      const AFreed: TArray<string>);
    procedure CheckBefore(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>);
    function InsideNames(ATry: TSyntaxNode; const AFreed: TArray<string>): TArray<string>;
    procedure CheckInside(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>);
    procedure CheckList(AList: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ Hilfen }

function InList(const AItems: TArray<string>; const AName: string): Boolean;
begin
  Result := MatchText(AName, AItems);
end;

/// <summary>Nennt die Deklaration ADecl ("A, B: T") den Namen AName?</summary>
function DeclaresName(ADecl: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in SplitString(ADecl.Name, ',') do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typ der Deklaration ADecl; '' ohne Angabe.</summary>
function DeclaredType(ADecl: TSyntaxNode): string;
begin
  Result := '';
  if (ADecl.ChildCount > 0) and (ADecl[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := ADecl[0].Name;
  end;
end;

/// <summary>Folgt AName der Namensregel für Interfaces (IName, auch Unit.IName)?</summary>
function LooksLikeInterface(const AName: string): Boolean;
var
  mName: string;
begin
  mName := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

/// <summary>Bezeichner des Objekts in X.Free, X.Destroy, X.DisposeOf bzw. FreeAndNil(X); '' sonst.</summary>
function FreedName(AStatement: TSyntaxNode): string;
var
  mTarget: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount = 2) and (mTarget[0].Kind = TSyntaxKind.Identifier) and
    SameText(mTarget[0].Name, 'FreeAndNil') and (mTarget[1].Kind = TSyntaxKind.Identifier) then
  begin
    Exit(mTarget[1].Name);
  end;
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount = 1) then
  begin
    mTarget := mTarget[0];
  end;
  if (mTarget.Kind = TSyntaxKind.MemberAccess) and MatchText(mTarget.Name, cFreeMembers) and
    (mTarget.ChildCount = 1) and (mTarget[0].Kind = TSyntaxKind.Identifier) then
  begin
    Result := mTarget[0].Name;
  end;
end;

function IsSafe(const ACall: TConstructorCall): Boolean;
begin
  Result := (not ACall.HasArguments and MatchText(ACall.ClassName, cSafeClasses)) or
    MatchText(ACall.ClassName, cSafeCollections);
end;

// Einzahl- bzw. Mehrzahltext für ACount Variablen.
function PluralText(AOne, AMany: TCreateOrderText; ACount: Integer): TCreateOrderText;
begin
  Result := AOne;
  if ACount > 1 then
  begin
    Result := AMany;
  end;
end;

function NamesOf(const ACreations: TArray<TCreation>; ACount: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ACount - 1 do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ACreations[mIndex].Name;
  end;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TCreateOrderScan }

constructor TCreateOrderScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  FObjects := TOwnerlessObjects.Create(FContext.Tree.Root, FAncestry);
end;

destructor TCreateOrderScan.Destroy;
begin
  FAncestry.Free;
  FLines := nil;
  inherited;
end;

// Lokale Variable der Routine (var-Abschnitt oder Inline-Variable), deren Typ kein Interface ist.
// Deklaration der lokalen Variablen AName (var-Abschnitt oder Inline-Variable), nil ohne.
function TCreateOrderScan.LocalDeclaration(const AName: string): TSyntaxNode;
begin
  Result := FRoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode <> FRoutine) and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) and DeclaresName(ANode, AName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else
      begin
        Result := TSyntaxSearchStep.Descend;
      end;
    end);
end;

function TCreateOrderScan.IsLocalObject(const AName: string): Boolean;
var
  mDecl: TSyntaxNode;
begin
  mDecl := LocalDeclaration(AName);
  Result := (mDecl <> nil) and not LooksLikeInterface(DeclaredType(mDecl));
end;

// Lokale Variable, deren Typ sicher eine Klasse ist (darf auf nil gesetzt werden)?
function TCreateOrderScan.IsKnownObjectVar(const AName: string): Boolean;
var
  mDecl: TSyntaxNode;
begin
  mDecl := LocalDeclaration(AName);
  Result := (mDecl <> nil) and (mDecl.Kind = TSyntaxKind.VarDecl) and (DeclaredType(mDecl) <> '') and
    FObjects.IsKnownClass(DeclaredType(mDecl));
end;

// Ziel einer Zuweisung X := … (Bezeichner), sonst ''.
function AssignedName(AStatement: TSyntaxNode): string;
begin
  Result := '';
  if (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) then
  begin
    Result := AStatement[0].Name;
  end;
end;

function IsCreated(const ACreations: TArray<TCreation>; const AName: string): Boolean;
var
  mCreation: TCreation;
begin
  Result := False;
  for mCreation in ACreations do
  begin
    Result := Result or SameText(mCreation.Name, AName);
  end;
end;

// Weitere im finally freigegebene Variablen, die AList[AFirst..ALast] zuweist (X := Parse(…)); False, wenn eine
// davon keine sichere Klasse ist oder als Inline-Variable entsteht (dann keine sichere Korrektur).
function TCreateOrderScan.FreedAssignments(AList: TSyntaxNode; AFirst, ALast: Integer; const AFreed: TArray<string>;
  const ACreations: TArray<TCreation>; out ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  ANames := nil;
  Result := True;
  for mIndex := AFirst to ALast do
  begin
    mName := AssignedName(AList[mIndex]);
    if (AList[mIndex].Kind = TSyntaxKind.InlineVar) and not IsCreated(ACreations, AList[mIndex].Name) and
      InList(AFreed, AList[mIndex].Name) then
    begin
      Result := False;
    end
    else if (mName <> '') and InList(AFreed, mName) and not IsCreated(ACreations, mName) and
      not InList(ANames, mName) then
    begin
      Result := Result and IsKnownObjectVar(mName);
      ANames := ANames + [mName];
    end;
  end;
end;

function TCreateOrderScan.TryCreation(AStatement: TSyntaxNode; out ACreation: TCreation): Boolean;
var
  mValue: TSyntaxNode;
begin
  ACreation := Default(TCreation);
  ACreation.Statement := AStatement;
  if (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) then
  begin
    ACreation.Name := AStatement[0].Name;
    mValue := AStatement[1];
  end
  else if (AStatement.Kind = TSyntaxKind.InlineVar) and not ContainsStr(AStatement.Name, ',') and
    (AStatement.ChildCount > 0) and (AStatement[AStatement.ChildCount - 1].Kind <> TSyntaxKind.TypeReference) then
  begin
    ACreation.Name := AStatement.Name;
    mValue := AStatement[AStatement.ChildCount - 1];
    ACreation.InlineType := DeclaredType(AStatement);
  end
  else
  begin
    Exit(False);
  end;
  Result := ConstructorCall(mValue, ACreation.Call) and FObjects.IsLost(ACreation.Call) and
    IsLocalObject(ACreation.Name);
  if Result and (AStatement.Kind = TSyntaxKind.InlineVar) and (ACreation.InlineType = '') then
  begin
    ACreation.InlineType := ACreation.Call.ClassName;
  end;
end;

function TCreateOrderScan.FreedNames(AFinally: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to AFinally.ChildCount - 1 do
  begin
    mName := FreedName(AFinally[mIndex]);
    if (mName <> '') and not InList(Result, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

// Steht vor AIndex in AList X := nil (bzw. var X: T := nil)?
function TCreateOrderScan.SetToNilBefore(AList: TSyntaxNode; AIndex: Integer; const AName: string): Boolean;
var
  mIndex: Integer;
  mStatement, mValue: TSyntaxNode;
begin
  for mIndex := AIndex - 1 downto 0 do
  begin
    mStatement := AList[mIndex];
    mValue := nil;
    if (mStatement.Kind = TSyntaxKind.AssignStatement) and (mStatement.ChildCount = 2) and
      (mStatement[0].Kind = TSyntaxKind.Identifier) and SameText(mStatement[0].Name, AName) then
    begin
      mValue := mStatement[1];
    end
    else if (mStatement.Kind = TSyntaxKind.InlineVar) and DeclaresName(mStatement, AName) and
      (mStatement.ChildCount > 0) then
    begin
      mValue := mStatement[mStatement.ChildCount - 1];
    end;
    if mValue <> nil then
    begin
      Exit((mValue.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and SameText(mValue.Name, 'nil'));
    end;
  end;
  Result := False;
end;

// Steht ANode allein am Anfang seiner Zeile; bei ATry (das Schlüsselwort try) auch allein in der Zeile?
function TCreateOrderScan.OwnLine(ANode: TSyntaxNode; ATry: Boolean): Boolean;
var
  mLine: string;
begin
  mLine := FLines[ANode.StartPos.Line];
  Result := Trim(Copy(mLine, 1, ANode.StartPos.Character)) = '';
  if ATry then
  begin
    Result := Result and SameText(Trim(mLine), 'try');
  end;
end;

function TCreateOrderScan.NilLine(const AIndent: string; const ACreation: TCreation): string;
begin
  if ACreation.Statement.Kind = TSyntaxKind.InlineVar then
  begin
    Result := AIndent + 'var ' + ACreation.Name + ': ' + ACreation.InlineType + ' := nil;' + FLineBreak;
  end
  else
  begin
    Result := AIndent + ACreation.Name + ' := nil;' + FLineBreak;
  end;
end;

// Die Zeilen AFirstLine bis ALastLine eine Stufe tiefer; Inline-Variablen der Erzeugungen werden zu Zuweisungen
// (nur, wenn sie allein in ihrer Zeile stehen).
function TCreateOrderScan.MovedText(const ACreations: TArray<TCreation>; AFirstLine, ALastLine: Integer;
  out AText: string): Boolean;
var
  mLine, mIndex: Integer;
  mText, mStep: string;
  mCreation: TCreation;
begin
  AText := '';
  mStep := TRoutineBody.IndentUnit(FContext.Formatting);
  for mLine := AFirstLine to ALastLine do
  begin
    mText := FLines[mLine];
    for mIndex := 0 to High(ACreations) do
    begin
      mCreation := ACreations[mIndex];
      if (mCreation.Statement.Kind = TSyntaxKind.InlineVar) and (mCreation.Statement.StartPos.Line = mLine) then
      begin
        if mCreation.Statement.EndPos.Line <> mLine then
        begin
          Exit(False);
        end;
        mText := TTextLines.IndentOf(mText) + mCreation.Name + ' := ' +
          Copy(FContext.Text, mCreation.Call.Node.StartOffset + 1,
          mCreation.Call.Node.EndOffset - mCreation.Call.Node.StartOffset) + ';';
      end;
    end;
    if Trim(mText) = '' then
    begin
      AText := AText + mText + FLineBreak;
    end
    else
    begin
      AText := AText + mStep + mText + FLineBreak;
    end;
  end;
  Result := True;
end;

// Form 1: alle Variablen auf nil setzen (auch weitere, die mit ins try wandern: AOthers) und die Anweisungen ab dem
// ersten Create in das try verschieben.
function TCreateOrderScan.MoveFix(const ACreations: TArray<TCreation>; const AOthers: TArray<string>;
  ATry: TSyntaxNode): TArray<TRuleFix>;
var
  mFirst: TSyntaxNode;
  mIndent, mText, mMoved, mName: string;
  mCreation: TCreation;
begin
  Result := nil;
  mFirst := ACreations[0].Statement;
  if not OwnLine(mFirst, False) or not OwnLine(ATry, True) or (mFirst.StartPos.Line >= ATry.StartPos.Line) or
    not MovedText(ACreations, mFirst.StartPos.Line, ATry.StartPos.Line - 1, mMoved) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(FLines[ATry.StartPos.Line]);
  mText := '';
  for mCreation in ACreations do
  begin
    mText := mText + NilLine(mIndent, mCreation);
  end;
  for mName in AOthers do
  begin
    mText := mText + mIndent + mName + ' := nil;' + FLineBreak;
  end;
  mText := mText + FLines[ATry.StartPos.Line] + FLineBreak + mMoved;
  Result := [TRuleFix.Create(cTexts[TCreateOrderText.MoveIntoTry].Text,
    [TRuleEdit.Create(TTextRange.Create(mFirst.StartPos.Line, 0, ATry.StartPos.Line + 1, 0), mText)], True)];
end;

// Form 2: die nicht vorbelegten Variablen vor dem try auf nil setzen.
function TCreateOrderScan.NilFix(const ANames: TArray<string>; ATry: TSyntaxNode): TArray<TRuleFix>;
var
  mIndent, mText, mName: string;
begin
  Result := nil;
  if not OwnLine(ATry, True) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(FLines[ATry.StartPos.Line]);
  mText := '';
  for mName in ANames do
  begin
    mText := mText + mIndent + mName + ' := nil;' + FLineBreak;
  end;
  Result := [TRuleFix.Create(cTexts[TCreateOrderText.SetNil].Text,
    [TRuleEdit.Create(TTextRange.Create(ATry.StartPos.Line, 0, ATry.StartPos.Line, 0), mText)], True)];
end;

// Erzeugungen der im finally freigegebenen Variablen direkt vor dem try (bis zum vorigen try); AFirst ist der Index
// der ersten.
function TCreateOrderScan.CreationsBefore(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>;
  out AFirst: Integer): TArray<TCreation>;
var
  mIndex: Integer;
  mCreation: TCreation;
  mNames: TArray<string>;
begin
  Result := nil;
  mNames := nil;
  AFirst := -1;
  for mIndex := AIndex - 1 downto 0 do
  begin
    if AList[mIndex].Kind = TSyntaxKind.TryStatement then
    begin
      Break;
    end;
    if TryCreation(AList[mIndex], mCreation) and InList(AFreed, mCreation.Name) and
      not InList(mNames, mCreation.Name) then
    begin
      Result := [mCreation] + Result;
      mNames := mNames + [mCreation.Name];
      AFirst := mIndex;
    end;
  end;
end;

// Gefährlich, sobald nach dem ersten Create etwas scheitern kann: ein weiteres Create mit Argumenten bzw. einer
// Klasse außerhalb der kurzen Liste oder eine andere Anweisung.
function TCreateOrderScan.IsRisky(AList: TSyntaxNode; AIndex, AFirst: Integer;
  const ACreations: TArray<TCreation>): Boolean;
var
  mIndex, mCount: Integer;
begin
  Result := False;
  mCount := 0;
  for mIndex := AFirst + 1 to AIndex - 1 do
  begin
    if (mCount + 1 < Length(ACreations)) and (AList[mIndex] = ACreations[mCount + 1].Statement) then
    begin
      Inc(mCount);
      Result := Result or not IsSafe(ACreations[mCount].Call);
    end
    else if AList[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Result := True;
    end;
  end;
end;

procedure TCreateOrderScan.ReportBefore(AList: TSyntaxNode; AIndex, AFirst: Integer;
  const ACreations: TArray<TCreation>; const AFreed: TArray<string>);
var
  mIndex: Integer;
  mCreation: TCreation;
  mFixes: TArray<TRuleFix>;
  mMessage: string;
  mOthers: TArray<string>;
begin
  // Wandert eine weitere freigegebene Variable mit ins try, die sich nicht sicher auf nil setzen lässt: keine
  // Korrektur.
  mFixes := nil;
  if FreedAssignments(AList, AFirst, AIndex - 1, AFreed, ACreations, mOthers) then
  begin
    mFixes := MoveFix(ACreations, mOthers, AList[AIndex]);
  end;
  for mIndex := 1 to High(ACreations) do
  begin
    mCreation := ACreations[mIndex];
    if IsSafe(mCreation.Call) then
    begin
      mMessage := cTexts[PluralText(TCreateOrderText.StatementFails, TCreateOrderText.StatementFailsMany,
        mIndex)].Fmt([NamesOf(ACreations, mIndex)]);
    end
    else
    begin
      mMessage := cTexts[PluralText(TCreateOrderText.CreateFails, TCreateOrderText.CreateFailsMany,
        mIndex)].Fmt([mCreation.Call.ClassName, NamesOf(ACreations, mIndex)]);
    end;
    FReport.Add(NodeRange(mCreation.Call.Node), mMessage, TRuleConfidence.High, mFixes);
    // Die Korrektur ändert alle zusammen; sie hängt nur am ersten Befund.
    mFixes := nil;
  end;
end;

procedure TCreateOrderScan.CheckBefore(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>);
var
  mFirst: Integer;
  mCreations: TArray<TCreation>;
begin
  mCreations := CreationsBefore(AList, AIndex, AFreed, mFirst);
  if (Length(mCreations) >= 2) and IsRisky(AList, AIndex, mFirst, mCreations) then
  begin
    ReportBefore(AList, AIndex, mFirst, mCreations, AFreed);
  end;
end;

// Im finally freigegebene Variablen, die das try zuweist: Erzeugungen und, nach der ersten, weitere Variablen einer
// sicheren Klasse (X := Parse(…)). Leer ohne Erzeugung.
function TCreateOrderScan.InsideNames(ATry: TSyntaxNode; const AFreed: TArray<string>): TArray<string>;
var
  mIndex: Integer;
  mCreation: TCreation;
  mName: string;
  mCreated: Boolean;
begin
  Result := nil;
  mCreated := False;
  for mIndex := 0 to ATry.ChildCount - 1 do
  begin
    mName := AssignedName(ATry[mIndex]);
    if (mName = '') or not InList(AFreed, mName) or InList(Result, mName) then
    begin
      Continue;
    end;
    if TryCreation(ATry[mIndex], mCreation) then
    begin
      mCreated := True;
      Result := Result + [mName];
    end
    else if mCreated and IsKnownObjectVar(mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

procedure TCreateOrderScan.CheckInside(AList: TSyntaxNode; AIndex: Integer; const AFreed: TArray<string>);
var
  mTry, mFinally, mFree: TSyntaxNode;
  mIndex: Integer;
  mNames, mOpen: TArray<string>;
  mName: string;
begin
  mTry := AList[AIndex];
  mFinally := mTry.FindChild(TSyntaxKind.FinallyBlock);
  mNames := InsideNames(mTry, AFreed);
  if Length(mNames) < 2 then
  begin
    Exit;
  end;
  mOpen := nil;
  for mName in mNames do
  begin
    if not SetToNilBefore(AList, AIndex, mName) then
    begin
      mOpen := mOpen + [mName];
    end;
  end;
  if mOpen = nil then
  begin
    Exit;
  end;
  // Gemeldet an der ersten Freigabe einer nicht vorbelegten Variablen.
  for mIndex := 0 to mFinally.ChildCount - 1 do
  begin
    mFree := mFinally[mIndex];
    if InList(mOpen, FreedName(mFree)) then
    begin
      FReport.Add(NodeRange(mFree), cTexts[PluralText(TCreateOrderText.Uninitialized,
        TCreateOrderText.UninitializedMany, Length(mOpen))].Fmt([string.Join(', ', mOpen)]),
        TRuleConfidence.High, NilFix(mOpen, mTry));
      Exit;
    end;
  end;
end;

procedure TCreateOrderScan.CheckList(AList: TSyntaxNode);
var
  mIndex: Integer;
  mFinally: TSyntaxNode;
  mFreed: TArray<string>;
begin
  for mIndex := 0 to AList.ChildCount - 1 do
  begin
    if AList[mIndex].Kind <> TSyntaxKind.TryStatement then
    begin
      Continue;
    end;
    mFinally := AList[mIndex].FindChild(TSyntaxKind.FinallyBlock);
    if mFinally = nil then
    begin
      Continue;
    end;
    mFreed := FreedNames(mFinally);
    if Length(mFreed) < 2 then
    begin
      Continue;
    end;
    CheckBefore(AList, mIndex, mFreed);
    CheckInside(AList, mIndex, mFreed);
  end;
end;

procedure TCreateOrderScan.Run;
var
  mRoutine, mBody: TSyntaxNode;
begin
  FLines := TTextLines.SplitLines(FContext.Text, FLineBreak);
  for mRoutine in TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext) do
  begin
    FRoutine := mRoutine;
    mBody := mRoutine.FindChild(TSyntaxKind.Block);
    // Anweisungslisten der Routine ohne eingebettete Routinen (die kommen selbst dran) und anonyme Methoden (ihre
    // Variablen können eingefangen sein).
    mBody.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Exit(TSyntaxSearchStep.Skip);
        end;
        if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
          TSyntaxKind.ExceptBlock] then
        begin
          CheckList(ANode);
        end;
        Result := TSyntaxSearchStep.Descend;
      end);
  end;
end;

{ TMultipleCreateInTryRule }

function TMultipleCreateInTryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMultipleCreateInTryRuleId, TRuleSeverity.Warning,
    cTexts[TCreateOrderText.Title].Text);
end;

procedure TMultipleCreateInTryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TCreateOrderScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'finally') then
  begin
    Exit;
  end;
  mScan := TCreateOrderScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipCreateOrderRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMultipleCreateInTryRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Ownership.CreateOrder', cTexts);

end.
